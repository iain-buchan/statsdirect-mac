// AI Assist's distribution card (Windows 5.3.22): the two selected columns' measurements for its local check, read as an
// analysis of that selection reads them, so that the card counts only what the confirmed analysis accepts. The engine
// summarises them (statsdirect_measurement_check); none of them is sent to the provider.
import {MAX_ROWS, columnName, kindIndex} from './store.mjs';
import {trimSpace} from './worksheet-r.mjs';
import {checkColumnData, columnEnd} from './analysis-source.mjs';
import {selectionFingerprint} from './ai-selection.mjs';

// Windows frmSpreadsheetGear.MeasurementDiagnostics.cs: MeasurementDistributionDiagnostics.LargeSampleThreshold and the
// texts of CheckSelectedPairedDifferences and CheckSelectedIndependentSamples. The Mac grid hides no columns, but the
// texts keep "visible": one text on both platforms.
const LARGE_SAMPLE_THRESHOLD = 100;
const SELECTION = {
  paired: 'Select two adjacent, visible columns of matched measurements in one worksheet range.',
  independent: 'Select the two adjacent, visible sample columns in one worksheet range.'
};
const TOO_LARGE = 'A paired difference is too large to check. Rescale the measurements and try again.';

const BLANK = kindIndex('blank'), NUMBER = kindIndex('number'), ERROR = kindIndex('error');
// Constant.MISSING (double.MinValue): every analysis takes a cell holding it as missing.
const MISSING = -Number.MAX_VALUE;
// What double.TryParse(NumberStyles.Float, InvariantCulture) accepts once String.Trim has run: an optional sign, ASCII
// digits with an optional point and exponent, then any ASCII white space and NUL characters, which .NET skips.
const FLOAT = /^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?(?=[\t\n\v\f\r ]*\0*$)/;

// The value the engine reads from a cell's text in a numeric column (FullEngine/HostParameters.cs ReadFrame, whose modes
// for the card's methods take no missing markers): NaN for a missing cell ("" or "*" once trimmed, or the MISSING value);
// null for text it refuses; otherwise the number. JavaScript's own trim and Number differ (U+0085, U+FEFF, hexadecimal,
// trailing NULs).
export function analysisNumber(text) {
  const t = trimSpace(text);
  if (t === '' || t === '*') return NaN;
  const m = FLOAT.exec(t);
  if (!m) return null;
  const x = Number(m[0]);
  return !Number.isFinite(x) ? null : x === MISSING ? NaN : x;
}

// A cell of a stored chunk, as analysisNumber reads it. A number cell's double reaches the analysis as String(x), which
// .NET reads back exactly, except that -0 is written "0".
function cellValue(column, chunk, i, r) {
  const kind = chunk.kind[i];
  if (kind === BLANK) return NaN;
  const x = kind === NUMBER ? chunk.num[i] : NaN;
  if (!Number.isNaN(x)) return x === MISSING ? NaN : x + 0;
  return analysisNumber(column.text.get(r) ?? '');
}

// The selection the card reads: one rectangle exactly two columns wide, or exactly two adjacent whole columns, inside the
// grid; null for anything else, whole rows and several areas included. Select All on a two-column sheet is a rectangle two
// columns wide, which a Windows sheet, 16,384 columns wide, never has.
function selectedPair(selection, store) {
  const current = selection?.current, columns = selection?.columns, rows = selection?.rows;
  if (current?.range) {
    const {x, y, width, height} = current.range;
    if (current.rangeStack?.length || columns?.length || rows?.length || width !== 2 || ![x, y, height].every(Number.isInteger)
      || x < 0 || y < 0 || height < 1 || x + 1 >= store.columns.length || y >= store.rows) return null;
    return {left: x, top: y, bottom: y + height - 1};
  }
  if (rows?.length || columns?.length !== 2 || columns.last() !== columns.first() + 1 || columns.last() >= store.columns.length) return null;
  return {left: columns.first(), top: 0, bottom: MAX_ROWS - 1};
}

// A column's stored chunks that meet rows first to last, by chunk index; rows in no chunk are blank.
function chunksIn(column, first, last) {
  const chunks = new Map();
  if (column) for (const [index, chunk] of column.chunks) {
    const start = index * chunk.kind.length;
    if (start <= last && start + chunk.kind.length > first) chunks.set(index, chunk);
  }
  return chunks;
}
function holdsError(chunks, first, last) {
  for (const [index, {kind}] of chunks) {
    const start = index * kind.length;
    for (let r = Math.max(first, start), end = Math.min(last, start + kind.length - 1); r <= end; r++) if (kind[r - start] === ERROR) return true;
  }
  return false;
}
// As store.formulaUnavailable(c, r) for some row r from first to last, without visiting every row: column c's formula
// cells, then each array, spill or data-table result span that meets the rows.
function formulaUnavailableIn(store, c, first, last) {
  const column = store.cols[c];
  if (column) for (const r of column.formula.keys()) if (r >= first && r <= last && store.formulaUnavailable(c, r)) return true;
  return store.formulaResultSpans(c).some(span => span.lastRow >= first && span.firstRow <= last
    && store.unavailableResultRow(c, Math.max(first, span.firstRow), Math.min(last, span.lastRow)) >= 0);
}

// ReadFrame's refusal of a cell that is not a number, naming the cell by its worksheet address (ReadFrame counts rows from
// the first one read) and its trimmed text by at most 40 characters; in row 1 without the header option, a heading may be
// the cause.
function notNumeric(store, c, r) {
  const text = trimSpace(store.get(c, r));
  let end = 0;
  for (let shown = 0; end < text.length && shown < 40; shown++) end += text.codePointAt(end) > 0xffff ? 2 : 1;
  const message = `Cell ${columnName(c)}${r + 1}: ‘${end < text.length ? text.slice(0, end) + '…' : text}’ is not numeric. Correct it or use * for a missing value.`;
  return r === 0 && !store.headerRow ? message + ' If row 1 holds column names, tick “First row has column names”.' : message;
}

// The selected columns' values for design 'paired' or 'independent', with the selection's click fingerprint
// (ai-selection.mjs) taken in the same call. Always {sheet, sheetName, design, left, right, headerRow, firstRow, lastRow,
// fingerprint}, the rows 1-based and null when none is read; then either `error`, a text the user sees as it is, or the
// values: paired `pairs` and `differences` (left minus right over the complete pairs in row order, a Float64Array),
// independent `samples`, each column's count with its values while there are at most 100.
export function measurementColumns(workbook, sheetIndex, selection, design) {
  if (design !== 'paired' && design !== 'independent') throw new Error('The measurement design must be paired or independent.');
  const sheet = workbook.sheets[sheetIndex], store = sheet.store, headerRow = !!store.headerRow;
  const fingerprint = selectionFingerprint(workbook, sheetIndex, selection), pair = selectedPair(selection, store);
  if (!pair) return {sheet: sheetIndex, sheetName: sheet.name, design, left: null, right: null, headerRow, firstRow: null, lastRow: null, fingerprint, error: SELECTION[design]};
  const left = pair.left, right = left + 1;
  // The rows an analysis reads: from row 2 when row 1 holds the column names, to the last row of either column that holds
  // a value or a formula result it refuses (analysis-source.mjs columnEnd); the rows after it are blank in both columns.
  const first = Math.max(pair.top, headerRow ? 1 : 0);
  const last = Math.min(pair.bottom, Math.max(columnEnd(store, left), columnEnd(store, right)) - 1);
  const result = {sheet: sheetIndex, sheetName: sheet.name, design, left, right, headerRow,
    firstRow: last >= first ? first + 1 : null, lastRow: last >= first ? last + 1 : null, fingerprint};
  const a = store.cols[left], b = store.cols[right], chunksA = chunksIn(a, first, last), chunksB = chunksIn(b, first, last);
  // Refused in the analysis's order: Excel errors, then formula results it cannot use (checkColumnData), then the first
  // cell that is not a number, the left column first (ReadFrame reads one column after the other).
  try {
    checkColumnData({errors: Number(holdsError(chunksA, first, last) || holdsError(chunksB, first, last)),
      uncached: Number(formulaUnavailableIn(store, left, first, last) || formulaUnavailableIn(store, right, first, last))});
  } catch (error) { return {...result, error: error.message}; }
  const paired = design === 'paired', differences = paired ? new Float64Array(Math.max(0, last - first + 1)) : null;
  const samples = [{count: 0, values: []}, {count: 0, values: []}];
  let pairs = 0, overflow = false, refused = null;
  // One pass over both columns, a stored chunk at a time.
  scan: for (const index of [...new Set([...chunksA.keys(), ...chunksB.keys()])].sort((i, j) => i - j)) {
    const ca = chunksA.get(index), cb = chunksB.get(index), size = (ca ?? cb).kind.length, start = index * size;
    for (let r = Math.max(first, start), end = Math.min(last, start + size - 1); r <= end; r++) {
      const x = ca ? cellValue(a, ca, r - start, r) : NaN;
      if (x === null) { refused = [left, r]; break scan; }
      if (refused) continue;   // a refusal in the right column stands unless one in the left column follows it
      const y = cb ? cellValue(b, cb, r - start, r) : NaN;
      if (y === null) { refused = [right, r]; continue; }
      if (paired) {
        if (Number.isNaN(x) || Number.isNaN(y)) continue;
        // Windows refuses a difference that RunRecord.Missing would drop: infinite after an overflow, or double.MinValue.
        const d = x - y;
        if (!Number.isFinite(d) || d === MISSING) overflow = true; else differences[pairs++] = d;
      } else {
        // Each column on its own; Windows keeps its first 100 values, for Shapiro–Wilk up to the large-sample threshold.
        if (!Number.isNaN(x) && ++samples[0].count <= LARGE_SAMPLE_THRESHOLD) samples[0].values.push(x);
        if (!Number.isNaN(y) && ++samples[1].count <= LARGE_SAMPLE_THRESHOLD) samples[1].values.push(y);
      }
    }
  }
  if (refused) return {...result, error: notNumeric(store, ...refused)};
  if (overflow) return {...result, error: TOO_LARGE};
  if (paired) return {...result, pairs, differences: differences.subarray(0, pairs)};
  return {...result, samples: samples.map(({count, values}) => ({count, values: count <= LARGE_SAMPLE_THRESHOLD ? values : []}))};
}

// What reaches Swift through callAsyncJavaScript, plain values only. The paired differences go as a typed snapshot, one
// f64 column in row order, posted with `post` (main.tsx postSnapshot, answering {id, bytes}); the engine reads its file,
// and Swift forgets it once the engine has replied.
export async function measurementTransfer(result, post) {
  const {differences, ...transfer} = result;
  if (!differences?.length) return transfer;
  const n = differences.length, rows = new Uint32Array(n);
  for (let i = 0; i < n; i++) rows[i] = i;
  const {id, bytes} = await post([{name: '', columns: [{col: 0, rows, kinds: new Uint8Array(n).fill(NUMBER), nums: differences, texts: new Map(), formulas: new Map()}]}]);
  return {...transfer, snapshot: {id, bytes}};
}
