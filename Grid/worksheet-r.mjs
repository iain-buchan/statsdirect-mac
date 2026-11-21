import {columnName} from './store.mjs';

// Worksheet data for R, by the rules shared with StatsDirect for Windows ("Worksheet data sent to
// R" in the statisticalhelp repository; rule numbers below refer to it). The prompt's preview reads
// only bounds and the first row. The import reads the confirmed cells and returns each column's R
// type with its values as text: exact R numeric literals, TRUE/FALSE, day counts for Date, or the
// raw strings of a character column, which the host quotes. null is a missing value.

const RECALCULATE = 'Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.';
const TOO_LARGE = 'The selected data exceed the 8 MiB editable R script limit. Select a smaller range, or export the worksheet as RDS from File → Export.';
const DAY = 86400000;

// Rule 3.1: white space is Unicode White_Space, which .NET's String.Trim removes (not U+200B or U+FEFF).
const SPACE = '[\\t-\\r \\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000]';
const EDGE_SPACE = new RegExp(`^${SPACE}+|${SPACE}+$`, 'g');
export const trimSpace = text => text.replace(EDGE_SPACE, '');

// Rule 3.4 (C9): trimmed text that counts as a number: ASCII digits, a finite value and no
// leading zero. Returns the number, or NaN.
const DECIMAL = /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$/, LEADING_ZERO = /^[+-]?0[0-9]/;
export function numberValue(text) {
  if (!DECIMAL.test(text) || LEADING_ZERO.test(text)) return NaN;
  const x = Number(text);
  return Number.isFinite(x) ? x : NaN;
}

// Rules 3.2, 3.3 and 3.5. The markers are missing in any column when written exactly so; the
// words in any other case, and the Inf words, only beside an anchor (A1). Case is ASCII only.
const MARKERS = new Set(['*', '* (missing)', '.', 'NA', 'N/A', 'NaN', 'NULL', 'MISSING']);
const MISSING_WORD = /^(?:na|n\/a|nan|null|missing)$/i, INFINITY_WORD = /^(-?)inf(?:inity)?$/i, BOOLEAN_WORD = /^(?:true|false)$/i;
const LETTER = /\p{L}/u;

// Rule 3.8 (I4): the R literal that reads back as exactly this double. The shortest decimal when it
// has no exponent, at most four digits after the point and at most 15 digits; otherwise R's
// hexadecimal form, with subnormals as 0x0.<fraction>p-1022 (R reads C's %a form of them as 0).
export function rNumber(x) {
  if (x === Infinity) return 'Inf';
  if (x === -Infinity) return '-Inf';
  const text = String(x);   // -0 gives "0"
  if (!text.includes('e')) {
    const point = text.indexOf('.'), decimals = point < 0 ? 0 : text.length - point - 1;
    if (decimals <= 4 && text.replace(/[-.]/g, '').replace(/^0+/, '').length <= 15) return text;
  }
  const view = new DataView(new ArrayBuffer(8));
  view.setFloat64(0, x);
  const high = view.getUint32(0), exponent = (high >>> 20) & 0x7ff, sign = high >>> 31 ? '-' : '';
  const fraction = (high & 0xfffff).toString(16).padStart(5, '0') + view.getUint32(4).toString(16).padStart(8, '0');
  return exponent ? `${sign}0x1.${fraction}p${exponent >= 1023 ? '+' : ''}${exponent - 1023}` : `${sign}0x0.${fraction}p-1022`;
}

// Rule 3.9: dates and times, rounded to the millisecond. A datetime cell's text is
// YYYY-MM-DD[ T]HH:MM[:SS[.f…]], with a final Z (UTC) from R data files; a timespan cell's is
// .NET's "c" text, [-][d.]hh:mm:ss[.fffffff].
const DATE_TIME = /^([0-9]{4})-([0-9]{2})-([0-9]{2})(?:[ T]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\.([0-9]+))?)?Z?)?$/;
const DURATION = /^(-?)(?:([0-9]+)\.)?([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.([0-9]+))?$/;
const milliseconds = (digits = '') => Number(digits.padEnd(3, '0').slice(0, 3)) + (digits[3] >= '5' ? 1 : 0);
const two = n => String(n).padStart(2, '0');
// Milliseconds since 1970-01-01, carried into the seconds, minutes and date, or NaN for a time or
// date the calendar does not have.
function dateTimeValue(text) {
  const match = DATE_TIME.exec(text);
  if (!match) return NaN;
  const [y, mo, d, h, mi, s] = match.slice(1, 7).map(v => Number(v ?? 0));
  if (h > 23 || mi > 59 || s > 59) return NaN;
  const date = new Date(0);
  date.setUTCFullYear(y, mo - 1, d);
  if (date.getUTCMonth() !== mo - 1 || date.getUTCDate() !== d) return NaN;
  return date.getTime() + ((h * 60 + mi) * 60 + s) * 1000 + milliseconds(match[7]);
}
function dayText(days) {
  const date = new Date(days * DAY);
  return String(date.getUTCFullYear()).padStart(4, '0') + '-' + two(date.getUTCMonth() + 1) + '-' + two(date.getUTCDate());
}
// HH:MM:SS, the hours not wrapped, and a point with one to three digits only for a fraction.
function clockText(ms) {
  const fraction = ms % 1000;
  return two(Math.floor(ms / 3600000)) + ':' + two(Math.floor(ms / 60000) % 60) + ':' + two(Math.floor(ms / 1000) % 60)
    + (fraction ? '.' + String(fraction).padStart(3, '0').replace(/0+$/, '') : '');
}
// A time of day or duration as [-]HH:MM:SS[.f], or null when the text is not a duration.
function durationText(text) {
  const match = DURATION.exec(text);
  if (!match) return null;
  const [d, h, mi, s] = match.slice(2, 6).map(v => Number(v ?? 0));
  const ms = (((d * 24 + h) * 60 + mi) * 60 + s) * 1000 + milliseconds(match[6]);
  if (mi > 59 || s > 59 || !Number.isSafeInteger(ms)) return null;
  return (match[1] && ms ? '-' : '') + clockText(ms);
}

// Rule 3.10: text arrives exactly as in the cell, except that a lone surrogate becomes U+FFFD.
const LONE_SURROGATE = /[\ud800-\udbff](?![\udc00-\udfff])|(?<![\ud800-\udbff])[\udc00-\udfff]/g;
const wellFormed = text => text.replace(LONE_SURROGATE, '\ufffd');

// What a copied cell holds. The first four are always missing: blank (also empty or white-space
// text, and a formula whose saved result is empty text), a marker written exactly so, a
// spreadsheet error (C4), and the nonexistent 1900-02-29. A typed cell whose text does not read as
// its type counts as text.
const Cell = {blank: 0, marker: 1, error: 2, serial60: 3, word: 4, infinite: 5, number: 6, numberText: 7,
  boolean: 8, booleanText: 9, date: 10, dateTime: 11, time: 12, text: 13};
const CLASSES = 14;
// The class of one cell. Its value goes in value[i]: the number, ±Infinity, 1 or 0 for a Boolean,
// the day count of a date, or the milliseconds since 1970 of a date-time.
function classify(text, kind, value, i) {
  if (kind === 'error') return Cell.error;
  if (text === '') return Cell.blank;
  const t = trimSpace(text);
  if (kind === 'number') {
    const x = numberValue(t);
    if (!Number.isNaN(x)) { value[i] = x; return Cell.number; }
  } else if (kind === 'boolean') {
    if (BOOLEAN_WORD.test(t)) { value[i] = /^t/i.test(t) ? 1 : 0; return Cell.boolean; }
  } else if (kind === 'datetime' && DATE_TIME.test(t)) {
    if (t.startsWith('1900-02-29')) return Cell.serial60;
    const time = dateTimeValue(t);
    if (!Number.isNaN(time)) {
      if (time % DAY) { value[i] = time; return Cell.dateTime; }
      value[i] = time / DAY; return Cell.date;
    }
  } else if (kind === 'timespan' && durationText(t) !== null) return Cell.time;
  if (t === '') return Cell.blank;
  if (MARKERS.has(t)) return Cell.marker;
  if (MISSING_WORD.test(t)) return Cell.word;
  const x = numberValue(t);
  if (!Number.isNaN(x)) { value[i] = x; return Cell.numberText; }
  const infinite = INFINITY_WORD.exec(t);
  if (infinite) { value[i] = infinite[1] ? -Infinity : Infinity; return Cell.infinite; }
  if (BOOLEAN_WORD.test(t)) { value[i] = /^t/i.test(t) ? 1 : 0; return Cell.booleanText; }
  return Cell.text;
}

// Rule 3.6, judged on the non-missing cells. The any-case words are missing, and the Inf words
// numbers, only beside at least one number, Boolean, date or date-time with every other cell of that
// kind (A1; a column of dates and date-times is character, and its words become NA in valueText).
function columnType(n) {
  const numbers = n[Cell.number] + n[Cell.numberText], booleans = n[Cell.boolean] + n[Cell.booleanText], dates = n[Cell.date];
  if (n[Cell.dateTime] + n[Cell.time] + n[Cell.text] === 0) {
    if (numbers && !booleans && !dates) return 'double';
    if (!numbers && !n[Cell.infinite]) {
      if (booleans && !dates) return 'logical';
      if (dates && !booleans) return 'Date';
      if (!booleans && !dates && !n[Cell.word]) return 'logical';   // every cell missing
    }
  }
  return 'character';
}
// A date-time column: every non-missing cell a date or date-time, at least one with a time. Its
// midnights keep 00:00:00, because as.POSIXct() drops the time from every value if one lacks it.
// Date-times anchor the any-case words as dates do (agreed with Windows, 21 November 2026), so a
// word there is missing; beside a time of day or a duration it stays text.
const dateTimeColumn = n => n[Cell.dateTime] > 0 && n[Cell.number] + n[Cell.numberText] + n[Cell.boolean] + n[Cell.booleanText]
  + n[Cell.time] + n[Cell.text] + n[Cell.infinite] === 0;

// Rule 3.7: a value in a character column, and a heading's name (4.5). A text cell keeps its exact text.
function cellText(cls, x, text, dateTimes) {
  switch (cls) {
    case Cell.number: return String(x === 0 ? 0 : x);   // -0 as 0
    case Cell.boolean: return x ? 'TRUE' : 'FALSE';
    case Cell.date: return dayText(x) + (dateTimes ? ' 00:00:00' : '');
    case Cell.dateTime: { const days = Math.floor(x / DAY); return dayText(days) + ' ' + clockText(x - days * DAY); }
    case Cell.time: return durationText(trimSpace(text));
    default: return wellFormed(text);
  }
}
function valueText(type, cls, x, text, dateTimes) {
  switch (type) {
    case 'double': return cls === Cell.number || cls === Cell.numberText ? rNumber(x) : cls === Cell.infinite ? (x > 0 ? 'Inf' : '-Inf') : null;
    case 'logical': return cls === Cell.boolean || cls === Cell.booleanText ? (x ? 'TRUE' : 'FALSE') : null;
    case 'Date': return cls === Cell.date ? rNumber(x) : null;
    default: return cls > Cell.serial60 && !(dateTimes && cls === Cell.word) ? cellText(cls, x, text, dateTimes) : null;
  }
}

// Rule 4.1: the first row is suggested as headings when the data has at least two rows and every
// non-blank first-row cell is text with a letter, not numeric text, a Boolean or an exact marker.
// Blank and white-space cells are passed over; a formula counts by its value; one heading is needed.
function suggestHeadings(store, plan) {
  if (rowCount(plan) < 2) return false;
  const r = rowAt(plan, 0), value = new Float64Array(1);
  let any = false;
  for (const c of plan.columns) {
    const text = store.get(c, r), cls = classify(text, store.kind(c, r), value, 0);
    if (cls === Cell.blank) continue;
    if (![Cell.text, Cell.word, Cell.infinite].includes(cls) || !LETTER.test(text)) return false;
    any = true;
  }
  return any;
}

// Plan bounds from the sparse column store. Formatting-only cells may allocate chunks, but only
// values and formulas (rule 2.1: white-space text too) define the data.
function columnBounds(store, c) {
  const column = store.cols[c];
  if (!column) return null;
  let first = Infinity, last = column.used() - 1;
  if (column.count) {
    outer: for (const chunk of [...column.chunks.keys()].sort((a, b) => a - b)) {
      const kinds = column.chunks.get(chunk).kind;
      for (let i = 0; i < kinds.length; i++) {
        if (kinds[i] !== 0) { first = chunk * kinds.length + i; break outer; }
      }
    }
  }
  for (const row of column.formula.keys()) { first = Math.min(first, row); last = Math.max(last, row); }
  return Number.isFinite(first) ? {first, last} : null;
}
function populatedBounds(store, columns = null) {
  let first = Infinity, last = -1, left = Infinity, right = -1;
  const visit = c => {
    const bounds = columnBounds(store, c);
    if (!bounds) return;
    first = Math.min(first, bounds.first); last = Math.max(last, bounds.last);
    left = Math.min(left, c); right = Math.max(right, c);
  };
  if (columns) columns.forEach(visit);
  else store.cols.forEach((_column, c) => visit(c));
  return Number.isFinite(first) ? {first, last, left, right} : null;
}
// Every row from first to last of a column that holds a value, then every formula row in that span (which can repeat a
// row holding a value), unless formulas is false. Only the column's stored chunks are read, never its blank rows.
function forEachFilledRow(column, first, last, visit, formulas = true) {
  for (const [index, {kind}] of column.chunks) {
    const base = index * kind.length;
    for (let r = Math.max(first, base), end = Math.min(last, base + kind.length - 1); r <= end; r++) if (kind[r - base] !== 0) visit(r);
  }
  if (formulas) for (const r of column.formula.keys()) if (r >= first && r <= last) visit(r);
}
function hasData(store, c, first, last) {
  const column = store.cols[c];
  if (!column) return false;
  for (const r of column.formula.keys()) if (r >= first && r <= last) return true;
  for (const [index, {kind}] of column.chunks) {
    const base = index * kind.length;
    for (let r = Math.max(first, base), end = Math.min(last, base + kind.length - 1); r <= end; r++) if (kind[r - base] !== 0) return true;
  }
  return false;
}

const span = (from, to) => Array.from({length: to - from + 1}, (_, i) => from + i);
// Runs of consecutive indices in a sorted list, as [first, last] pairs.
function runs(sorted) {
  const out = [];
  for (const i of sorted) {
    if (out.length && out.at(-1)[1] === i - 1) out.at(-1)[1] = i;
    else out.push([i, i]);
  }
  return out;
}
// Whether indices inside the grid name every index below n.
function covers(list, n) {
  if (list.length < n) return false;
  const seen = new Uint8Array(n);
  let count = 0;
  for (const i of list) if (!seen[i]) { seen[i] = 1; count++; }
  return count === n;
}

// The selection as main.tsx hands it over: the columns and rows of Glide's CompactSelections (toArray(), which has
// merged the pieces of a Command-click or Shift-click selection), the current rectangle, the rectangles a Command-click
// stacked before it, and Edit ▸ Select All's marker. Glide can leave a selection reaching beyond the grid: its cursor
// on the trailing "Add a row" row, or a row or column selected before Undo made the grid smaller. Such a selection is
// clipped to the grid, the same way for the preview and the import, so that the prompt still opens and the import
// sends what the preview showed; what is left may be nothing, "empty". Only what Glide never gives is refused:
// positions that are not whole numbers from 0, an empty rectangle, or a column named twice.
const MALFORMED = 'Select cells inside the worksheet.';
const position = i => Number.isInteger(i) && i >= 0, extent = n => Number.isInteger(n) && n > 0;
function clipped(store, selection) {
  const columns = selection.columns ?? [], rows = selection.rows ?? [], range = selection.range;
  const parts = (columns.length > 0) + (rows.length > 0) + !!range;
  if (!parts) return 'none';
  if (parts > 1 || selection.ranges?.length) return 'shape';
  if (range) {
    const {x, y, width, height} = range;
    if (!position(x) || !position(y) || !extent(width) || !extent(height)) throw new Error(MALFORMED);
    const right = Math.min(x + width, store.columns.length), bottom = Math.min(y + height, store.rows);
    return x < right && y < bottom ? {range: {x, y, width: right - x, height: bottom - y}} : 'empty';
  }
  if (columns.length) {
    if (!columns.every(position) || new Set(columns).size !== columns.length) throw new Error(MALFORMED);
    const inside = columns.filter(c => c < store.columns.length);
    return inside.length ? {columns: inside} : 'empty';
  }
  if (!rows.every(position)) throw new Error(MALFORMED);
  const inside = rows.filter(r => r < store.rows);
  return inside.length ? {rows: inside} : 'empty';
}

// A plan is the columns sent, their rows (first to last, or a sorted list for whole rows) and the
// areas the range text names. A selection that cannot be sent is a reason instead: "none" (no
// selection), "empty" (no non-blank cell) or "shape" (a multiple selection other than several whole
// columns or several whole rows).
const rowCount = plan => plan.rows ? plan.rows.length : plan.last - plan.first + 1;
const rowAt = (plan, i) => plan.rows ? plan.rows[i] : plan.first + i;
function entirePlan(store) {
  const bounds = populatedBounds(store);
  return bounds && {columns: span(bounds.left, bounds.right), first: bounds.first, last: bounds.last, areas: [bounds]};
}
function selectedPlan(store, selection) {
  const chosen = clipped(store, selection);
  if (typeof chosen === 'string') return chosen;
  if (selection.all === true || selectsAll(store, chosen)) return entirePlan(store) ?? 'empty';
  if (chosen.columns) return columnsPlan(store, chosen.columns);
  if (chosen.rows) return rowsPlan(store, chosen.rows);
  return rectanglePlan(store, chosen.range);
}
// Rule 2.6: select all is the same as Entire worksheet. That is Edit ▸ Select All (`all`, set by main.tsx while that
// selection lasts), Glide's own Command-A (a rectangle over the whole grid) and the corner (every grid row). So are
// whole columns that together are every grid column, and whole rows that together are every grid row (amendment 1),
// however they were selected: one drag, Shift-click, or Command-click pieces such as A:M with N:XFD. Judged on the
// clipped selection, so an index beyond the grid neither counts nor stops it.
function selectsAll(store, {columns, rows, range}) {
  if (range) return range.x === 0 && range.y === 0 && range.width === store.columns.length && range.height === store.rows;
  return rows ? covers(rows, store.rows) : covers(columns, store.columns.length);
}
// Rule 2.2: a rectangle keeps its explicit bounds, if it holds any data.
function rectanglePlan(store, {x, y, width, height}) {
  const columns = span(x, x + width - 1), last = y + height - 1;
  if (!columns.some(c => hasData(store, c, y, last))) return 'empty';
  return {columns, first: y, last, areas: [{left: x, right: x + width - 1, first: y, last}]};
}
// Rules 2.3 and C7: whole columns, in sheet order, from the first to the last non-blank row of those
// columns. A selected column with no data stays, as a column of NA.
function columnsPlan(store, selected) {
  const columns = [...selected].sort((a, b) => a - b), bounds = populatedBounds(store, columns);
  if (!bounds) return 'empty';
  return {columns, first: bounds.first, last: bounds.last,
    areas: runs(columns).map(([left, right]) => ({left, right, first: bounds.first, last: bounds.last}))};
}
// C6: whole rows, from the first to the last selected row holding a non-blank cell (blank selected
// rows between them stay), across from the first to the last non-blank column of those rows.
function rowsPlan(store, selected) {
  const marked = new Uint8Array(store.rows);
  let low = Infinity, high = -1;
  for (const r of selected) { marked[r] = 1; low = Math.min(low, r); high = Math.max(high, r); }
  let first = Infinity, last = -1, left = Infinity, right = -1;
  store.cols.forEach((column, c) => forEachFilledRow(column, low, high, r => {
    if (!marked[r]) return;
    first = Math.min(first, r); last = Math.max(last, r);
    left = Math.min(left, c); right = Math.max(right, c);
  }));
  if (last < 0) return 'empty';
  const rows = [];
  for (let r = first; r <= last; r++) if (marked[r]) rows.push(r);
  return {columns: span(left, right), rows, areas: runs(rows).map(([top, bottom]) => ({left, right, first: top, last: bottom}))};
}

// Rule 1.4: A1 notation, areas in sheet order. The prompt lists at most three, then ",…".
function rangeText(areas, limit = Infinity) {
  const text = areas.slice(0, limit).map(({left, right, first, last}) => {
    const from = columnName(left) + (first + 1), to = columnName(right) + (last + 1);
    return from === to ? from : from + ':' + to;
  }).join(',');
  return areas.length > limit ? text + ',…' : text;
}
const summary = (store, plan) => ({range: rangeText(plan.areas, 3), rowCount: rowCount(plan), columnCount: plan.columns.length,
  suggestHeadings: suggestHeadings(store, plan)});

// Rule 3.10: the refusal names the first cell holding a null character in sheet order, rows then
// columns. The copying loop runs column by column, so it calls this only once it has met one.
function firstNull(store, plan, rows) {
  for (let i = 0; i < rows; i++) {
    const r = rowAt(plan, i);
    for (const c of plan.columns) if (store.get(c, r).includes('\0')) return columnName(c) + (r + 1);
  }
  return '';
}

// The non-blank cells among a plan's data rows (those after the first `start`), counted from the store's chunks.
function filledCells(store, plan, start) {
  const first = rowAt(plan, start), last = rowAt(plan, rowCount(plan) - 1);
  let marked = null, count = 0;
  if (plan.rows) {   // whole rows: only the selected ones between first and last
    marked = new Uint8Array(last - first + 1);
    for (let i = start; i < plan.rows.length; i++) marked[plan.rows[i] - first] = 1;
  }
  const visit = marked ? r => { count += marked[r - first]; } : () => { count++; };
  for (const c of plan.columns) if (store.cols[c]) forEachFilledRow(store.cols[c], first, last, visit, false);
  return count;
}
// Whether no script could hold the plan's data rows, checked before they are read. A data frame writes every cell, so
// it needs at least 3 bytes for each ("NA, "). A list leaves its missing values out (rule 5.3), so it needs at least 3
// bytes only for each non-blank cell; but its values still come with one entry for each data row, as a data frame's
// do, so a list may also cover at most one cell for each byte of the limit, which keeps a huge sparse area from being
// read cell by cell.
function tooLarge(store, plan, start, list, maximumBytes) {
  const cells = plan.columns.length * (rowCount(plan) - start);
  if (!list) return cells * 3 > maximumBytes;
  return cells > maximumBytes || filledCells(store, plan, start) * 3 > maximumBytes;
}

// Without a scope: the prompt's preview, {sheet, entire, selected, selectedReason}. With "entire"
// or "selected": the data, {sheet, range, rangeAll, rowCount, columnCount, names, columns, dates}.
// options.headings takes the names from the first row (rule 4); rowCount still counts that row.
// options.list says the host writes a list of vectors, which leaves missing values out, rather than a data frame; the
// values are the same either way. The size check here only refuses what no script could hold (tooLarge, and each
// value's own length); the host makes the exact check on the script it writes.
export function worksheetRImport(workbook, sheetIndex, selection = {}, scope, options = {}, maximumBytes = 8 * 1024 * 1024) {
  const sheet = workbook.sheets[sheetIndex], store = sheet?.store;
  if (!store) throw new Error('Choose an open worksheet.');
  if (scope === undefined) {
    const entire = entirePlan(store), selected = selectedPlan(store, selection), reason = typeof selected === 'string' ? selected : null;
    return {sheet: sheet.name, entire: entire && summary(store, entire), selected: reason ? null : summary(store, selected), selectedReason: reason};
  }
  if (!['entire', 'selected'].includes(scope)) throw new Error('Choose the entire worksheet or selected cells.');
  const plan = scope === 'entire' ? entirePlan(store) : selectedPlan(store, selection);
  if (!plan || typeof plan === 'string') throw new Error(scope === 'entire' ? 'The worksheet contains no data.' : 'Select worksheet cells, columns or rows to import.');
  const rows = rowCount(plan), headings = options?.headings === true && rows > 1, start = headings ? 1 : 0;
  if (tooLarge(store, plan, start, options?.list === true, maximumBytes)) throw new Error(TOO_LARGE);
  const kinds = new Uint8Array(rows), numbers = new Float64Array(rows), names = [], columns = [];
  let bytes = 0, dates = false;
  for (const c of plan.columns) {
    const counts = new Uint32Array(CLASSES);
    for (let i = 0; i < rows; i++) {
      const r = rowAt(plan, i), text = store.get(c, r), kind = store.kind(c, r);
      if (store.formulaUnavailable(c, r)) throw new Error(RECALCULATE);
      if (text.includes('\0')) throw new Error(`Cell ${firstNull(store, plan, rows)} contains a null character, which R cannot hold. Remove it, then open the R import again.`);
      kinds[i] = classify(text, kind, numbers, i);
      if (i < start) continue;
      counts[kinds[i]]++;
      if (kind === 'datetime' || kind === 'timespan') dates = true;   // A2
    }
    const type = columnType(counts), dateTimes = type === 'character' && dateTimeColumn(counts), values = new Array(rows - start);
    for (let i = start; i < rows; i++) {
      const value = valueText(type, kinds[i], numbers[i], store.get(c, rowAt(plan, i)), dateTimes);
      values[i - start] = value;
      if (value !== null && (bytes += value.length + 2) > maximumBytes) throw new Error(TOO_LARGE);
    }
    const name = headings && ![Cell.blank, Cell.error, Cell.serial60].includes(kinds[0])
      ? cellText(kinds[0], numbers[0], store.get(c, rowAt(plan, 0)), false) : columnName(c);
    if ((bytes += name.length + 2) > maximumBytes) throw new Error(TOO_LARGE);
    names.push(name);
    columns.push({type, values});
  }
  return {sheet: sheet.name, range: rangeText(plan.areas, 3), rangeAll: rangeText(plan.areas), rowCount: rows,
    columnCount: plan.columns.length, names, columns, dates};
}
