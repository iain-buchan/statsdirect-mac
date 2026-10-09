// Typed columnar worksheet store.
//
// Each column keeps its populated rows in 4,096-row chunks: a Float64Array of numeric values
// (NaN where the cell holds no canonical number), a Uint8Array of cell kinds and a Uint8Array
// of flags. Text that is not a canonical number lives in a sparse Map per column, formulas in
// another. A numeric cell therefore costs about ten bytes, so a worksheet of Excel's full
// dimensions (1,048,576 rows by 16,384 columns) is bounded only by the data actually in it.
// The public surface used by the grid, the workbook, CSV, R data and the tutor is kept:
// get, apply, paste, undo/redo, paired, columnTitle, csv, usedRows, headerRow, excelRows,
// csvRows, formulasStale, columns and rows. Cell-level metadata is read through kind(),
// formula() and loaded() instead of a per-cell Map.
export const MAX_ROWS = 1048576,
  MAX_COLS = 16384;
const CHUNK_BITS = 12,
  CHUNK = 1 << CHUNK_BITS,
  MASK = CHUNK - 1;
export const KINDS = ['blank', 'number', 'text', 'datetime', 'timespan', 'boolean', 'error'];
const KIND_INDEX = new Map(KINDS.map((k, i) => [k, i]));
const BLANK = 0, NUMBER = 1, TEXT = 2;
export function kindIndex(name) { return KIND_INDEX.get(name) ?? TEXT; }
const LOADED = 1, MODIFIED = 2;
const UNDO_STEPS = 50,
  UNDO_BYTES = 256 * 1024 * 1024;
const DATETIME = /^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?$/,
  TIMESPAN = /^-?(?:\d+\.)?\d{2}:\d{2}:\d{2}(?:\.\d+)?$/,
  BOOLEAN = /^(true|false)$/i,
  NUMERIC = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/,
  LEADING_ZERO = /^[+-]?0\d/;

export function columnName(index) {
  let s = '';
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s;
  return s;
}
// Spreadsheet-style delimited text (as pasted from Excel): quoted fields with doubled quotes,
// \r\n or \n or \r record ends. Returns rows of strings; scanDelimited below is the streaming form.
export function parseDelimited(text, delimiter = '\t') {
  const rows = [];
  let row = [];
  scanDelimited(text, delimiter, (c, r, field) => {
    while (rows.length <= r) { rows.push(row = []); }
    row = rows[r];
    while (row.length < c) row.push('');
    row[c] = field;
  });
  return rows;
}
// Walk delimited text once without materialising rows. emit(col, row, field) is called for
// every field, including empty ones, in document order. Returns the row and column counts.
export function scanDelimited(text, delimiter, emit) {
  let c = 0, r = 0, start = 0, cols = 0, field = null, quoted = false, any = false;
  const n = text.length;
  const finish = (value) => { emit(c, r, value); c++; if (c > cols) cols = c; any = true; };
  for (let i = 0; i < n; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else quoted = false;
      } else field += ch;
      continue;
    }
    if (ch === '"') {
      if (field === null || field === '') { quoted = true; field = field ?? ''; }
      else field += ch;
    } else if (ch === delimiter) {
      finish(field ?? text.slice(start, i)); field = null; start = i + 1;
    } else if (ch === '\n' || ch === '\r') {
      finish(field ?? text.slice(start, i)); field = null;
      if (ch === '\r' && text[i + 1] === '\n') i++;
      start = i + 1; r++; c = 0;
    } else if (field !== null) field += ch;
  }
  if (quoted) throw new Error('The pasted text has an unclosed quote.');
  const tail = field ?? text.slice(start);
  if (tail !== '' || c > 0) { finish(tail); r++; }
  else if (!any) r = 0;
  return {rows: r, cols};
}
export function numeric(raw) {
  if (raw.trim() === '') return null;
  if (!NUMERIC.test(raw.trim())) throw new Error(`“${raw.slice(0, 30)}” is not a number.`);
  const n = Number(raw);
  if (!Number.isFinite(n)) throw new Error('Numbers must be finite.');
  return n;
}
// A number is stored as a double only when its text is the shortest round-trip form, so that
// get() returns exactly what was entered or imported ("1.50" and "0012" stay text).
function canonical(text) {
  if (text.length > 24 || !NUMERIC.test(text)) return NaN;
  const n = Number(text);
  return Number.isFinite(n) && String(n) === text ? n : NaN;
}
// The kind rules the grid has always used (formerly cellKind in workbook.mjs).
export function deriveKind(text, original) {
  if (original && original.text === text) return KIND_INDEX.get(original.kind) ?? TEXT;
  if (text === '') return BLANK;
  if (original?.kind === 'text') return TEXT;
  if (original?.kind === 'datetime' && DATETIME.test(text)) return KIND_INDEX.get('datetime');
  if (original?.kind === 'timespan' && TIMESPAN.test(text)) return KIND_INDEX.get('timespan');
  if (original?.kind === 'boolean' && BOOLEAN.test(text)) return KIND_INDEX.get('boolean');
  const trimmed = text.trim();
  if (trimmed !== '' && NUMERIC.test(trimmed) && Number.isFinite(Number(trimmed)) && !LEADING_ZERO.test(trimmed)) return NUMBER;
  return TEXT;
}

class Column {
  constructor() {
    this.chunks = new Map();
    this.text = new Map();
    this.formula = new Map();
    this.extra = new Map();
    this.count = 0;
    this.max = -1;
    this.maxDirty = false;
  }
  chunk(r, create) {
    const index = r >> CHUNK_BITS;
    let ch = this.chunks.get(index);
    if (!ch && create) {
      ch = {num: new Float64Array(CHUNK), kind: new Uint8Array(CHUNK), flags: new Uint8Array(CHUNK)};
      ch.num.fill(NaN);
      this.chunks.set(index, ch);
    }
    return ch;
  }
  kindAt(r) {
    const ch = this.chunks.get(r >> CHUNK_BITS);
    return ch ? ch.kind[r & MASK] : BLANK;
  }
  flagsAt(r) {
    const ch = this.chunks.get(r >> CHUNK_BITS);
    return ch ? ch.flags[r & MASK] : 0;
  }
  numAt(r) {
    const ch = this.chunks.get(r >> CHUNK_BITS);
    return ch ? ch.num[r & MASK] : NaN;
  }
  get(r) {
    const ch = this.chunks.get(r >> CHUNK_BITS);
    if (!ch) return '';
    const i = r & MASK, k = ch.kind[i];
    if (k === BLANK) return '';
    const n = ch.num[i];
    return k === NUMBER && !Number.isNaN(n) ? String(n) : this.text.get(r) ?? '';
  }
  // Write one cell: kind index, numeric value (NaN when text is stored) and text.
  write(r, kind, num, text) {
    const ch = this.chunk(r, true), i = r & MASK, was = ch.kind[i] !== BLANK;
    if (kind === BLANK) {
      ch.kind[i] = BLANK; ch.num[i] = NaN; this.text.delete(r);
      if (was) { this.count--; if (r === this.max) this.maxDirty = true; }
      return;
    }
    ch.kind[i] = kind; ch.num[i] = num;
    if (Number.isNaN(num)) this.text.set(r, text); else this.text.delete(r);
    if (!was) this.count++;
    if (r > this.max) { this.max = r; this.maxDirty = false; }
  }
  setFlags(r, flags) { this.chunk(r, true).flags[r & MASK] = flags; }
  used() {
    if (this.maxDirty) {
      this.max = -1;
      for (const index of [...this.chunks.keys()].sort((a, b) => b - a)) {
        const kind = this.chunks.get(index).kind;
        for (let i = CHUNK - 1; i >= 0; i--) if (kind[i] !== BLANK) { this.max = (index << CHUNK_BITS) + i; break; }
        if (this.max >= 0) break;
      }
      this.maxDirty = false;
    }
    return this.max + 1;
  }
  forEach(fn) {
    for (const index of [...this.chunks.keys()].sort((a, b) => a - b)) {
      const ch = this.chunks.get(index), base = index << CHUNK_BITS;
      for (let i = 0; i < CHUNK; i++) {
        const k = ch.kind[i];
        if (k === BLANK) { if (this.formula.has(base + i)) fn(base + i, '', BLANK); continue; }
        const n = ch.num[i], r = base + i;
        fn(r, k === NUMBER && !Number.isNaN(n) ? String(n) : this.text.get(r) ?? '', k);
      }
    }
  }
}

export class GridStore {
  constructor(example) {
    this.columns = example ? ['PEFR Before', 'PEFR After', 'Variable C', 'Variable D', 'Variable E', 'Notes'] : Array.from({length: 6}, (_, c) => columnName(c));
    this.rows = 100;
    this.cols = [];
    this.undoStack = [];
    this.redoStack = [];
    this.undoBytes = 0;
    this.originals = new Map();
    this.headerRow = false;
    this.excelRows = false;
    this.csvRows = 0;
    this.formulasStale = false;
    if (example) {
      this.setLoaded(example.before.map((v, r) => ({col: 0, row: r, text: String(v), kind: 'number'})).concat(example.after.map((v, r) => ({col: 1, row: r, text: String(v), kind: 'number'}))), false);
    }
  }
  col(c) {
    while (this.cols.length <= c) this.cols.push(new Column());
    return this.cols[c];
  }
  get(c, r) {
    const col = this.cols[c];
    return col ? col.get(r) : '';
  }
  kind(c, r) {
    const col = this.cols[c];
    return KINDS[col ? col.kindAt(r) : BLANK];
  }
  formula(c, r) {
    const col = this.cols[c];
    return col ? col.formula.get(r) ?? '' : '';
  }
  // The cell as loaded from a file (undefined for cells that were never loaded). For a cell
  // edited since loading, the values it had when loaded.
  loaded(c, r) {
    const col = this.cols[c];
    if (!col || !(col.flagsAt(r) & LOADED)) return undefined;
    const stashed = this.originals.get(`${c},${r}`);
    if (stashed) return stashed;
    return {col: c, row: r, text: col.get(r), kind: KINDS[col.kindAt(r)], formula: col.formula.get(r) ?? '', ...(col.extra.get(r) ?? {})};
  }
  count() {
    let n = 0;
    for (const col of this.cols) n += col.count;
    return n;
  }
  usedRows() {
    let end = 0;
    for (const col of this.cols) end = Math.max(end, col.used());
    return end;
  }
  columnUsedRows(c) {
    const col = this.cols[c];
    return col ? col.used() : 0;
  }
  usedColumns() {
    const used = [];
    this.cols.forEach((col, c) => { if (col.count > 0) used.push(c); });
    return used;
  }
  get canUndo() { return this.undoStack.length > 0; }
  get canRedo() { return this.redoStack.length > 0; }
  // Every populated cell, plus formula cells without a cached result, in column order.
  forEachCell(fn) {
    this.cols.forEach((col, c) => col.forEach((r, text, k) => fn(c, r, text, KINDS[k], col.formula.get(r) ?? '')));
  }
  // Bulk load from a file: cells as {col,row,text,kind,formula,...extra}. No undo step.
  setLoaded(cells, markLoaded = true) {
    for (const cell of cells) {
      const c = cell.col, r = cell.row;
      if (c < 0 || r < 0 || c >= MAX_COLS || r >= MAX_ROWS) throw new Error('Cell is outside the worksheet.');
      const col = this.col(c), text = cell.text ?? '';
      const kind = text === '' ? BLANK : KIND_INDEX.get(cell.kind) ?? TEXT;
      col.write(r, kind, kind === NUMBER ? canonical(text) : NaN, text);
      if (cell.formula) col.formula.set(r, cell.formula);
      if (markLoaded) col.setFlags(r, LOADED);
      const {col: _c, row: _r, text: _t, kind: _k, formula: _f, ...extra} = cell;
      if (Object.keys(extra).length) col.extra.set(r, extra);
      if (c + 1 > this.columns.length) this.growColumns(c + 1);
      if (r + 1 > this.rows) this.rows = r + 1;
    }
  }
  // Bulk load from per-column batches ({col, rows, nums, texts}) as produced by scanning text.
  setLoadedBatches(batches, kindOf) {
    for (const b of batches) {
      const col = this.col(b.col);
      for (let i = 0; i < b.rows.length; i++) {
        const r = b.rows[i], num = b.nums[i], text = Number.isNaN(num) ? b.texts.get(i) ?? '' : String(num);
        if (text === '') continue;
        const kind = KIND_INDEX.get(kindOf(text)) ?? TEXT;
        col.write(r, kind, kind === NUMBER ? (Number.isNaN(num) ? canonical(text) : num) : NaN, text);
        col.setFlags(r, LOADED);
      }
      if (b.col + 1 > this.columns.length) this.growColumns(b.col + 1);
    }
  }
  // Bulk load typed column records as decoded from a snapshot file (see snapshot.mjs):
  // {col, rows, kinds, nums, texts: Map<ordinal, text>, formulas: Map<ordinal, text>}.
  setLoadedColumns(columns) {
    let maxRow = -1, maxCol = -1;
    for (const b of columns) {
      const col = this.col(b.col), n = b.rows.length;
      for (let i = 0; i < n; i++) {
        const r = b.rows[i];
        if (r >= MAX_ROWS || b.col >= MAX_COLS) throw new Error('Cell is outside the worksheet.');
        let kind = b.kinds[i];
        if (kind === NUMBER) {
          const num = b.nums[i];
          if (Number.isFinite(num)) col.write(r, NUMBER, num, '');
          else { const text = b.texts.get(i) ?? ''; if (text === '') kind = BLANK; else col.write(r, NUMBER, canonical(text), text); }
        } else if (kind !== BLANK) {
          const text = b.texts.get(i) ?? '';
          if (text === '') kind = BLANK; else col.write(r, kind, NaN, text);
        }
        const formula = b.formulas?.get(i), extra = b.extras?.get(i);
        if (formula) col.formula.set(r, formula);
        if (extra) { try { col.extra.set(r, JSON.parse(extra)); } catch { /* malformed loader metadata is ignored */ } }
        else if (!formula && kind === BLANK) continue;
        col.setFlags(r, LOADED);
        if (r > maxRow) maxRow = r;
      }
      if (b.col > maxCol) maxCol = b.col;
    }
    if (maxCol + 1 > this.columns.length) this.growColumns(maxCol + 1);
    if (maxRow + 1 > this.rows) this.rows = maxRow + 1;
  }
  // Typed column records for the given columns, as snapshot.mjs encodes them. Rows are shifted
  // by `rowOffset`; with `header`, the column titles become row 0. Formulas are not carried.
  columnRecords(columns, rowOffset = 0, header = false) {
    return columns.map(c => {
      const col = this.cols[c], rows = [], kinds = [], nums = [], texts = new Map();
      if (header) { rows.push(0); kinds.push(TEXT); nums.push(NaN); texts.set(0, this.columnTitle(c)); }
      if (col) col.forEach((r, text, k) => {
        if (k === BLANK) return;
        const i = rows.length; rows.push(r + rowOffset); kinds.push(k);
        const n = k === NUMBER ? col.numAt(r) : NaN;
        nums.push(n); if (Number.isNaN(n)) texts.set(i, text);
      });
      return {col: c, rows, kinds, nums, texts, formulas: new Map()};
    });
  }
  growColumns(cols) {
    while (this.columns.length < cols) this.columns.push('Variable ' + columnName(this.columns.length));
    this.columns.length = cols;
  }
  // edits: [[col, row, text, kind?]]. An explicit kind (as the grid names them: number, text,
  // datetime, timespan, boolean, error) is kept, as when cells move; otherwise the kind is derived
  // from the text. Returns true if anything changed.
  apply(edits, rows = this.rows, cols = this.columns.length) {
    const byColumn = new Map();
    for (const [c, r, value, kind] of edits) {
      let b = byColumn.get(c);
      if (!b) byColumn.set(c, b = {col: c, rows: [], nums: [], texts: new Map(), kinds: []});
      const text = String(value), n = kind && kind !== 'number' ? NaN : canonical(text);
      b.rows.push(r); b.nums.push(n); b.kinds.push(typeof kind === 'string' && KIND_INDEX.has(kind) ? kind : undefined);
      if (Number.isNaN(n)) b.texts.set(b.rows.length - 1, text);
    }
    return this.applyBatches([...byColumn.values()], rows, cols);
  }
  applyBatches(batches, rows = this.rows, cols = this.columns.length) {
    if (rows > MAX_ROWS || cols > MAX_COLS) throw new Error('This exceeds the Excel worksheet dimensions.');
    const patches = [];
    let bytes = 0;
    for (const b of batches) {
      const c = b.col;
      if (c < 0 || c >= MAX_COLS) throw new Error('Cell is outside the worksheet.');
      const col = this.col(c), n = b.rows.length;
      // Last write to a cell wins; collect the distinct rows in order of first appearance.
      const index = new Map();
      for (let i = 0; i < n; i++) {
        const r = b.rows[i];
        if (r < 0 || r >= MAX_ROWS) throw new Error('Cell is outside the worksheet.');
        index.set(r, i);
      }
      const rowsOut = new Uint32Array(index.size), beforeNum = new Float64Array(index.size), beforeKind = new Uint8Array(index.size), beforeText = new Map(),
        afterNum = new Float64Array(index.size), afterKind = new Uint8Array(index.size), afterText = new Map();
      let k = 0, changed = 0;
      for (const [r, i] of index) {
        const num = b.nums[i], text = Number.isNaN(num) ? b.texts.get(i) ?? '' : String(num);
        const current = col.get(r);
        if (col.formula.has(r) && text !== current) throw new Error('Formula cells are read-only. Edit their formulas in Excel.');
        const original = col.flagsAt(r) & LOADED ? this.loaded(c, r) : undefined;
        const explicit = b.kinds?.[i];
        const kind = text === '' ? BLANK : explicit ? KIND_INDEX.get(explicit) : deriveKind(text, original);
        const oldKind = col.kindAt(r);
        if (text === current && kind === oldKind) continue;
        rowsOut[k] = r;
        beforeKind[k] = oldKind; beforeNum[k] = col.numAt(r);
        if (oldKind !== BLANK && Number.isNaN(beforeNum[k])) beforeText.set(k, current);
        afterKind[k] = kind; afterNum[k] = kind === NUMBER ? (Number.isNaN(num) ? canonical(text) : num) : NaN;
        if (kind !== BLANK && Number.isNaN(afterNum[k])) afterText.set(k, text);
        rows = Math.max(rows, r + 1);
        k++; changed++;
      }
      cols = Math.max(cols, c + 1);
      if (changed) {
        patches.push({col: c, rows: rowsOut.subarray(0, k), before: {num: beforeNum.subarray(0, k), kind: beforeKind.subarray(0, k), text: beforeText}, after: {num: afterNum.subarray(0, k), kind: afterKind.subarray(0, k), text: afterText}});
        bytes += k * 26;
        for (const t of beforeText.values()) bytes += t.length * 2;
        for (const t of afterText.values()) bytes += t.length * 2;
      }
    }
    if (!patches.length && rows === this.rows && cols === this.columns.length) return false;
    const step = {patches, oldRows: this.rows, newRows: rows, oldCols: this.columns.length, newCols: cols, bytes};
    this.replay(step, true);
    this.undoStack.push(step);
    this.undoBytes += bytes;
    while (this.undoStack.length > UNDO_STEPS || this.undoBytes > UNDO_BYTES && this.undoStack.length > 1) this.undoBytes -= this.undoStack.shift().bytes;
    this.redoStack = [];
    return true;
  }
  replay(step, forward) {
    for (const p of step.patches) {
      const col = this.col(p.col), side = forward ? p.after : p.before, key = p.col;
      for (let i = 0; i < p.rows.length; i++) {
        const r = p.rows[i], flags = col.flagsAt(r);
        if (flags & LOADED && !(flags & MODIFIED)) {
          this.originals.set(`${key},${r}`, this.loaded(p.col, r));
          col.setFlags(r, LOADED | MODIFIED);
        }
        col.write(r, side.kind[i], side.num[i], side.text.get(i) ?? '');
      }
    }
    this.rows = forward ? step.newRows : step.oldRows;
    this.growColumns(forward ? step.newCols : step.oldCols);
  }
  undo() {
    const s = this.undoStack.pop();
    if (!s) return false;
    this.replay(s, false);
    this.redoStack.push(s);
    return true;
  }
  redo() {
    const s = this.redoStack.pop();
    if (!s) return false;
    this.replay(s, true);
    this.undoStack.push(s);
    return true;
  }
  // Paste delimited text at (c, r) without materialising it as rows of strings.
  paste(c, r, text, delimiter = '\t') {
    const batches = new Map();
    const shape = scanDelimited(text, delimiter, (x, y, field) => {
      const col = c + x;
      let b = batches.get(col);
      if (!b) batches.set(col, b = {col, rows: [], nums: [], texts: new Map()});
      const n = canonical(field);
      b.rows.push(r + y); b.nums.push(n);
      if (Number.isNaN(n)) b.texts.set(b.rows.length - 1, field);
    });
    if (r + shape.rows > MAX_ROWS || c + shape.cols > MAX_COLS) throw new Error('This exceeds the Excel worksheet dimensions.');
    return this.applyBatches([...batches.values()]);
  }
  paired(c1, c2, start = this.headerRow ? 1 : 0, end = this.usedRows()) {
    if (this.headerRow) start = Math.max(1, start);
    if (c1 < 0 || c2 < 0 || c1 >= this.columns.length || c2 >= this.columns.length) throw new Error('Choose columns that exist in this worksheet.');
    if (c1 === c2) throw new Error('Choose two different columns.');
    const before = [],
      after = [];
    for (let r = start; r < end; r++) {
      try {
        if ([c1, c2].some(c => this.formula(c, r) && this.get(c, r) === '')) throw new Error('A formula has no saved result. Recalculate and save this workbook in Excel before analysing it.');
        if (this.formulasStale && [c1, c2].some(c => this.formula(c, r))) throw new Error('This selection contains formula results that may be out of date. Save, recalculate in Excel, and reopen the workbook before analysing these cells.');
        before.push(numeric(this.get(c1, r)));
        after.push(numeric(this.get(c2, r)));
      } catch (e) {
        throw new Error(`Row ${r + 1}: ${e.message} Correct the cell or leave it blank for missing data.`);
      }
    }
    if (before.filter((v, i) => v !== null && after[i] !== null).length < 2) throw new Error('At least two complete numeric pairs are needed.');
    return {
      before,
      after,
      labels: [this.columnTitle(c1), this.columnTitle(c2)],
      range: `${columnName(c1)}${start + 1} and ${columnName(c2)}${start + 1}, ${end - start} rows`
    };
  }
  columnTitle(c) {
    return this.excelRows ? this.headerRow ? this.get(c, 0) || `Column ${columnName(c)}` : `Column ${columnName(c)}` : this.columns[c];
  }
  csv() {
    const quote = s => /[",\r\n]/.test(s) ? '"' + s.replaceAll('"', '""') + '"' : s;
    const rows = this.excelRows ? [] : [this.columns.map(quote).join(',')];
    const end = Math.max(this.csvRows, this.usedRows()), width = this.columns.length;
    for (let r = 0; r < end; r++) {
      const fields = new Array(width);
      for (let c = 0; c < width; c++) fields[c] = quote(this.get(c, r));
      rows.push(fields.join(','));
    }
    return rows.length ? rows.join('\r\n') + '\r\n' : '';
  }
}
