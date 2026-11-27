import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {CompactSelection} from '@glideapps/glide-data-grid';
import {MAX_ROWS, columnName} from './store.mjs';
import {WorkbookStore} from './workbook.mjs';
import {selectionFingerprint} from './ai-selection.mjs';
import {analysisMetadata, checkColumnData, columnValues} from './analysis-source.mjs';
import {worksheetRows} from './operation-data.mjs';
import {decodeSnapshot, encodeSnapshot} from './snapshot.mjs';
import {trimSpace} from './worksheet-r.mjs';
import {analysisNumber, measurementColumns, measurementTransfer} from './measurement-columns.mjs';

// The Windows texts (frmSpreadsheetGear.MeasurementDiagnostics.cs), the analysis's (operation-data.mjs worksheetInputFrom)
// and the Mac card's for a cell the analysis refuses.
const PAIRED_SELECTION = 'Select two adjacent, visible columns of matched measurements in one worksheet range.';
const INDEPENDENT_SELECTION = 'Select the two adjacent, visible sample columns in one worksheet range.';
const TOO_LARGE = 'A paired difference is too large to check. Rescale the measurements and try again.';
const EXCEL_ERRORS = 'The selection contains Excel errors. Correct them in Excel and reopen the workbook.';
const RECALCULATE = 'Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.';
const notNumeric = (cell, text) => `Cell ${cell}: ‘${text}’ is not numeric. Correct it or use * for a missing value.`;
const HEADINGS = ' If row 1 holds column names, tick “First row has column names”.';

const pieces = (...ranges) => ranges.reduce((selection, range) => selection.add(range), CompactSelection.empty());
const rect = (x, y, width, height, rangeStack = []) =>
  ({columns: CompactSelection.empty(), rows: CompactSelection.empty(), current: {cell: [x, y], range: {x, y, width, height}, rangeStack}});
const columns = (...ranges) => ({columns: pieces(...ranges), rows: CompactSelection.empty()});
const rows = (...ranges) => ({columns: CompactSelection.empty(), rows: pieces(...ranges)});
function book(cells, {width = 4, height = 100, headerRow = false, formulaRegions} = {}) {
  const w = new WorkbookStore();
  w.load({name: 'Measurements.xlsx', sheets: [{name: 'Data', rows: height, columns: width, headerRow, cells, formulaRegions}]});
  return w;
}
// Number cells of column `col` from 0-based row `top`, as a loader gives them; null leaves a cell blank.
const numbers = (col, top, values) => values.flatMap((v, i) => v === null ? [] : [{col, row: top + i, text: String(v), kind: 'number'}]);
// Typed column records from row 0, as a loader's snapshot gives them: stored doubles such as -0, which no text gives.
function columnar(col, nums) {
  const n = nums.length, at = new Uint32Array(n);
  for (let i = 0; i < n; i++) at[i] = i;
  return {col, rows: at, kinds: new Uint8Array(n).fill(1), nums: Float64Array.from(nums), texts: new Map(), formulas: new Map(), extras: new Map()};
}
// Before and After, titled in row 1, over A2:B5 (differences 1, 3, 2, 2), with any cells replaced.
const TITLED = [{col: 0, row: 0, text: 'Before', kind: 'text'}, {col: 1, row: 0, text: 'After', kind: 'text'}, ...numbers(0, 1, [11, 14, 17, 22]), ...numbers(1, 1, [10, 11, 15, 20])];
const titled = (cells = [], options = {}) => book([...TITLED.filter(c => !cells.some(d => d.col === c.col && d.row === c.row)), ...cells], {headerRow: true, ...options});
const read = (w, selection, design = 'paired') => measurementColumns(w, 0, selection, design);
const differences = result => Array.from(result.differences);

test('the card reads one rectangle two columns wide, or two adjacent whole columns, down to the last value', () => {
  // Windows' A1:B6 example without its titles: the differences are 1, 3, 2, 2, 4.
  const w = book([...numbers(0, 0, [11, 14, 17, 22, 23]), ...numbers(1, 0, [10, 11, 15, 20, 19]), ...numbers(2, 0, [1, 2, 3, 4, 5])], {width: 3});
  const fields = {sheet: 0, sheetName: 'Data', design: 'paired', left: 0, right: 1, headerRow: false, firstRow: 1, lastRow: 5, pairs: 5};
  for (const selection of [rect(0, 0, 2, 5), rect(0, 0, 2, 60), columns([0, 2])]) {
    const {fingerprint, differences: d, ...result} = read(w, selection);
    assert.deepEqual([result, Array.from(d)], [fields, [1, 3, 2, 2, 4]]);
  }
  const {fingerprint, differences: d, ...lower} = read(w, rect(1, 1, 2, 3));
  assert.deepEqual([lower, Array.from(d)], [{...fields, left: 1, right: 2, firstRow: 2, lastRow: 4, pairs: 3}, [9, 12, 16]]);
  // A rectangle reaching the trailing "Add a row" row reads to the last value, and one below the data reads no row.
  assert.deepEqual(differences(read(w, rect(0, 3, 2, 97))), [2, 4]);
  const below = read(w, rect(0, 20, 2, 5));
  assert.deepEqual([below.firstRow, below.lastRow, below.pairs, below.error], [null, null, 0, undefined]);
});

test('every other selection is refused with the Windows texts, and still carries the fields and the fingerprint', () => {
  const w = book([...numbers(0, 0, [1, 2, 3]), ...numbers(1, 0, [4, 5, 6]), ...numbers(2, 0, [7, 8, 9])], {width: 3});
  const refused = {
    'a single cell': rect(0, 0, 1, 1), 'one column': rect(0, 0, 1, 3), 'three columns': rect(0, 0, 3, 3),
    'two rectangles': rect(0, 0, 2, 3, [{x: 0, y: 5, width: 2, height: 2}]),
    'one whole column': columns([0, 1]), 'three whole columns': columns([0, 3]), 'whole columns apart': columns([0, 1], [2, 3]),
    'whole rows': rows([0, 3]), 'every row (the corner)': rows([0, 100]), 'nothing': {columns: CompactSelection.empty(), rows: CompactSelection.empty()},
    'a right column beyond the sheet': rect(2, 0, 2, 3), 'whole columns beyond the sheet': columns([2, 4]),
    'the trailing "Add a row" row': rect(0, 100, 2, 1), 'a rectangle wholly outside the grid': rect(5, 0, 2, 1),
    'a rectangle with whole columns': {...rect(0, 0, 2, 3), columns: pieces([0, 2])}
  };
  for (const [name, selection] of Object.entries(refused)) {
    assert.deepEqual(read(w, selection), {sheet: 0, sheetName: 'Data', design: 'paired', left: null, right: null, headerRow: false,
      firstRow: null, lastRow: null, fingerprint: selectionFingerprint(w, 0, selection), error: PAIRED_SELECTION}, name);
    assert.equal(read(w, selection, 'independent').error, INDEPENDENT_SELECTION, name);
  }
  assert.throws(() => read(w, rect(0, 0, 2, 3), 'Paired'), /paired or independent/);
});

test('Select All on a two-column sheet reads its two columns, which a Windows sheet, 16,384 columns wide, never has', () => {
  const two = book([...numbers(0, 0, [5, 7, 9]), ...numbers(1, 0, [4, 4, 4])], {width: 2}), store = two.sheets[0].store;
  // Edit ▸ Select All (main.tsx) covers the used rows; Glide's Command-A covers the grid's.
  for (const all of [rect(0, 0, 2, store.usedRows()), rect(0, 0, 2, store.rows)]) assert.deepEqual(differences(read(two, all)), [1, 3, 5]);
  const three = book([...numbers(0, 0, [5, 7, 9]), ...numbers(1, 0, [4, 4, 4])], {width: 3});
  assert.equal(read(three, rect(0, 0, 3, three.sheets[0].store.rows)).error, PAIRED_SELECTION);
});

test('row 1 is skipped exactly when "First row has column names" is ticked, whatever it holds', () => {
  const w = titled();
  for (const selection of [rect(0, 0, 2, 5), rect(0, 0, 2, 50), columns([0, 2])]) {
    const result = read(w, selection);
    assert.deepEqual([result.headerRow, result.firstRow, result.lastRow, differences(result)], [true, 2, 5, [1, 3, 2, 2]]);
  }
  // A rectangle of the heading row alone reads nothing (an analysis of it reads row 2: operation-data.mjs worksheetRows).
  const heading = read(w, rect(0, 0, 2, 1));
  assert.deepEqual([heading.firstRow, heading.lastRow, heading.pairs, heading.error], [null, null, 0, undefined]);
  // Without the setting a heading is data, which the analysis refuses: the card names the cell and the setting.
  w.sheets[0].store.headerRow = false;
  assert.equal(read(w, rect(0, 0, 2, 5)).error, notNumeric('A1', 'Before') + HEADINGS);
  assert.equal(read(w, columns([0, 2]), 'independent').error, notNumeric('A1', 'Before') + HEADINGS);
  assert.deepEqual(differences(read(w, rect(0, 1, 2, 4))), [1, 3, 2, 2]);
  // A number in row 1 is data without the setting, and skipped with it.
  const years = book([...numbers(0, 0, [2019, 11, 14]), ...numbers(1, 0, [2018, 10, 11])]);
  assert.deepEqual(differences(read(years, columns([0, 2]))), [1, 1, 3]);
  years.sheets[0].store.headerRow = true;
  assert.deepEqual(differences(read(years, columns([0, 2]))), [1, 3]);
  // A refusal below row 1 does not mention the setting.
  assert.equal(read(titled([{col: 1, row: 2, text: 'eleven', kind: 'text'}]), columns([0, 2])).error, notNumeric('B3', 'eleven'));
  const untitled = book([...numbers(0, 0, [1, 2]), {col: 1, row: 0, text: '3', kind: 'number'}, {col: 1, row: 1, text: 'four', kind: 'text'}]);
  assert.equal(read(untitled, columns([0, 2])).error, notNumeric('B2', 'four'));
});

// What .NET 10.0.14 made of these texts under ReadFrame's rule for a numeric column (String.Trim; "" and "*" missing;
// double.TryParse(NumberStyles.Float, InvariantCulture) of a finite value): the number, NaN for missing, null refused.
const DOTNET = [
  ['12', 12], [' 12 ', 12], ['\t12\n', 12], ['1.', 1], ['.5', 0.5], ['+5', 5], ['-5', -5], ['+.5e-3', 0.0005],
  ['1e5', 100000], ['1E+05', 100000], ['1.e5', 100000], ['.e5', null], ['e5', null], ['1e', null], ['1e+', null],
  ['', NaN], [' ', NaN], ['*', NaN], [' * ', NaN], ['**', null], ['1,234', null], ['1,234.5', null], ['1,5', null],
  ['1.5', 1.5], ['1 234', null], ['0x10', null], ['0b1', null], ['1_000', null], ['Infinity', null],
  ['-Infinity', null], ['infinity', null], ['+Infinity', null], ['\u221e', null], ['-\u221e', null], ['NaN', null],
  ['nan', null], ['-NaN', null], ['1e400', null], ['-1e400', null], ['1e-400', 0], ['-0', -0], ['0012', 12],
  ['-00', -0], ['00.5', 0.5], ['\u00a012\u00a0', 12], ['\u202f12', 12], ['\u200012\u3000', 12], ['12\u0085', 12],
  ['\u0085 12', 12], ['\u1680 12', 12], ['\u2028 12 \u2029', 12], ['\u205f12', 12], ['\ufeff12', null],
  ['12\ufeff', null], ['\u200b12', null], ['\u180e12', null], ['12\u0000', 12], ['12\u0000\u0000', 12],
  ['12 \u0000', 12], ['\u0000 12', null], ['1\u00002', null], ['\u0661\u0662', null], ['\uff11\uff12', null],
  ['12abc', null], ['TRUE', null], ['true', null], ['FALSE', null], ['2024-01-31', null],
  ['2024-01-31 12:30:00', null], ['12:30:00', null], ['1.00:00:00', null], ['25%', null], ['\u00a312.50', null],
  ['$5', null], ['(5)', null], ['5-', null], ['- 5', null], ['+-5', null], ['--5', null], ['1.2.3', null],
  ['1e0000000000000000000001', 10], ['123456789012345678901234567890', 1.2345678901234568E+29], ['0.1', 0.1],
  ['1.7976931348623157e308', 1.7976931348623157E+308], ['-1.7976931348623157e308', NaN /* Constant.MISSING */],
  ['1.7976931348623158e308', 1.7976931348623157E+308], ['1.7976931348623159e308', null], ['4.9e-324', 5E-324],
  ['2.4703282292062327e-324', 0], ['2.4703282292062328e-324', 5E-324], ['#DIV/0!', null], ['#N/A', null],
  ['MISSING', null], ['missing', null], ['.', null], ['NA', null], ['N/A', null], ['NULL', null],
  ['* (missing)', null], ['1e+21', 1E+21], ['1.5e-7', 1.5E-07], ['9007199254740993', 9007199254740992],
  ['0.30000000000000004', 0.30000000000000004], ['\u22125', null], ['\u2212\u2212', null]
];

test('cell texts are read as the engine reads them, checked against .NET itself', () => {
  assert.equal(DOTNET.length, 105);
  for (const [text, expected] of DOTNET) {
    const x = analysisNumber(text);
    assert.ok(expected === null ? x === null : Object.is(x, expected), `${JSON.stringify(text)} gave ${x}`);
  }
  // The same texts typed into the grid, whatever kind the store gives them, read as one pair against 0 in row 2.
  const w = new WorkbookStore(), store = w.sheets[0].store;
  for (const [text, expected] of DOTNET) {
    store.apply([[0, 1, text], [1, 1, '0']]);
    const result = read(w, rect(0, 1, 2, 1)), name = JSON.stringify(text);
    if (expected === null) assert.equal(result.error, notNumeric('A2', trimSpace(text)), name);
    else if (Number.isNaN(expected)) assert.equal(result.pairs, 0, name);
    else assert.ok(result.pairs === 1 && Object.is(result.differences[0], expected), name);
  }
});

test('the white space trimmed is .NET Char.IsWhiteSpace, which String.Trim removes', () => {
  const dotnet = [0x9, 0xa, 0xb, 0xc, 0xd, 0x20, 0x85, 0xa0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008,
    0x2009, 0x200a, 0x2028, 0x2029, 0x202f, 0x205f, 0x3000];
  const trimmed = [];
  for (let u = 0; u <= 0xffff; u++) if (trimSpace(String.fromCharCode(u) + '1' + String.fromCharCode(u)) === '1') trimmed.push(u);
  assert.deepEqual(trimmed, dotnet);
});

test('booleans, dates and times are refused by name, and Excel errors before any cell the analysis cannot read', () => {
  for (const [kind, text] of [['boolean', 'TRUE'], ['datetime', '2024-01-31'], ['datetime', '2024-01-31 12:30:00'], ['timespan', '12:30:00'], ['timespan', '1.00:00:00']]) {
    const w = titled([{col: 1, row: 3, text, kind}]);
    for (const design of ['paired', 'independent']) assert.equal(read(w, columns([0, 2]), design).error, notNumeric('B4', text), kind);
  }
  const error = {col: 1, row: 3, text: '#DIV/0!', kind: 'error'}, trailing = {col: 1, row: 7, text: '#N/A', kind: 'error'};
  for (const design of ['paired', 'independent']) {
    assert.equal(read(titled([error]), columns([0, 2]), design).error, EXCEL_ERRORS);
    // before a text in an earlier row of the left column, which ReadFrame would meet first
    assert.equal(read(titled([error, {col: 0, row: 1, text: 'abc', kind: 'text'}]), columns([0, 2]), design).error, EXCEL_ERRORS);
    // in a row where the other column is blank, after the last value of both
    assert.equal(read(titled([trailing]), columns([0, 2]), design).error, EXCEL_ERRORS);
    // but not outside a rectangle
    assert.equal(read(titled([trailing]), rect(0, 0, 2, 5), design).error, undefined);
  }
});

test('formula results: saved ones are read, a saved empty text is missing, and a missing or out-of-date one is refused', () => {
  const saved = titled([{col: 1, row: 3, text: '15', kind: 'number', formula: 'A4-2'}]);
  assert.deepEqual(differences(read(saved, columns([0, 2]))), [1, 3, 2, 2]);
  const empty = titled([{col: 1, row: 3, text: '', kind: 'blank', formula: 'IF(A4>13,"",A4)', savedEmpty: true}]);
  assert.deepEqual(differences(read(empty, columns([0, 2]))), [1, 3, 2]);
  assert.deepEqual(read(empty, columns([0, 2]), 'independent').samples.map(s => s.count), [4, 3]);
  assert.equal(read(titled([{col: 1, row: 3, text: '', kind: 'blank', formula: 'A4-2'}]), columns([0, 2])).error, RECALCULATE);
  // Whole columns reach a formula without a result after the data, as an analysis does; a rectangle above it does not.
  const trailing = titled([{col: 1, row: 9, text: '', kind: 'blank', formula: 'A10-2'}]);
  assert.equal(read(trailing, columns([0, 2])).error, RECALCULATE);
  assert.deepEqual(differences(read(trailing, rect(0, 0, 2, 5))), [1, 3, 2, 2]);
  // Once the workbook is edited, every formula result may be out of date.
  saved.changed();
  assert.equal(read(saved, columns([0, 2]), 'independent').error, RECALCULATE);
  // Excel errors are refused first, then formula results, then cells that are not numbers.
  const none = {col: 1, row: 3, text: '', kind: 'blank', formula: 'A4-2'};
  assert.equal(read(titled([none, {col: 0, row: 2, text: '#REF!', kind: 'error'}]), columns([0, 2])).error, EXCEL_ERRORS);
  assert.equal(read(titled([none, {col: 0, row: 1, text: 'abc', kind: 'text'}]), columns([0, 2])).error, RECALCULATE);
  // Array, spill and data-table results: rows the file saved are read; a row it did not, or any once edited, is refused.
  const formulaRegions = [{firstRow: 1, lastRow: 4, firstColumn: 1, lastColumn: 1}];
  const region = titled([], {formulaRegions});
  assert.deepEqual(differences(read(region, columns([0, 2]))), [1, 3, 2, 2]);
  const gap = book(TITLED.filter(c => c.col !== 1 || c.row !== 3), {headerRow: true, formulaRegions});
  assert.equal(read(gap, columns([0, 2])).error, RECALCULATE);
  assert.deepEqual(differences(read(gap, rect(0, 0, 2, 3))), [1, 3]);
  assert.deepEqual(differences(read(titled([{col: 1, row: 3, text: '', kind: 'blank', savedEmpty: true}], {formulaRegions}), columns([0, 2]))), [1, 3, 2]);
  region.changed();
  assert.equal(read(region, rect(0, 0, 2, 3)).error, RECALCULATE);
  // An R NA, a blank cell marked rMissing, is missing.
  assert.deepEqual(differences(read(titled([{col: 1, row: 3, text: '', kind: 'blank', rMissing: true}]), columns([0, 2]))), [1, 3, 2]);
});

test('paired: left minus right over the complete pairs in row order, refusing a difference Windows cannot check', () => {
  // The preflight's alternating_missing: before 11, 13, 999, 12, blank, 12, 14; after 10, 10, blank, 10, 10, 10, 10.
  const w = book([...numbers(0, 0, [11, 13, 999, 12, null, 12, 14]), ...numbers(1, 0, [10, 10, null, 10, 10, 10, 10])]);
  const result = read(w, columns([0, 2]));
  assert.deepEqual([result.pairs, differences(result), result.firstRow, result.lastRow], [5, [1, 3, 2, 2, 4], 1, 7]);
  // "*" is missing, and so is the MISSING value, double.MinValue, whether stored as a double or typed.
  const marked = book([...numbers(0, 0, [5, 6, 7, 8, 9]), {col: 1, row: 0, text: '*', kind: 'text'}, {col: 1, row: 1, text: ' * ', kind: 'text'},
    {col: 1, row: 2, text: String(-Number.MAX_VALUE), kind: 'number'}, {col: 1, row: 3, text: '-1.7976931348623157e308', kind: 'text'}, ...numbers(1, 4, [1])]);
  assert.deepEqual(differences(read(marked, columns([0, 2]))), [8]);
  // Across the edge of a stored chunk (4,096 rows), in row order.
  const edge = book([...numbers(0, 4093, [1, 2, 3, 4, 5]), ...numbers(1, 4093, [0, 0, 0, 0, 0])], {height: 5000});
  assert.deepEqual(differences(read(edge, columns([0, 2]))), [1, 2, 3, 4, 5]);
  // A stored -0 reaches the analysis as "0", and a typed "-0" as -0, which .NET reads as negative zero.
  const zeros = new WorkbookStore();
  zeros.load({name: 'Zeros.xlsx', sheets: [{name: 'Data', rows: 100, columns: 2, headerRow: false, columnar: [columnar(0, [-0, 1]), columnar(1, [0, 1])]}]});
  zeros.sheets[0].store.apply([[0, 2, '-0'], [1, 2, '0']]);
  const z = differences(read(zeros, columns([0, 2])));
  assert.equal(zeros.sheets[0].store.get(0, 0), '0');
  assert.ok(Object.is(z[0], 0) && Object.is(z[1], 0) && Object.is(z[2], -0), String(z));
  // A difference that overflows, or is exactly double.MinValue, is one RunRecord.Missing would drop: Windows refuses it.
  const half = Number.MAX_VALUE / 2;
  for (const [x, y] of [[1e308, -1e308], [-half, half]]) {
    const big = book([...numbers(0, 0, [1, x, 3]), ...numbers(1, 0, [0, y, 1])]);
    assert.equal(read(big, columns([0, 2])).error, TOO_LARGE);
    assert.deepEqual(read(big, columns([0, 2]), 'independent').samples.map(s => s.values), [[1, x, 3], [0, y, 1]]);
    // Not in an incomplete row, and not before a cell the analysis refuses while reading.
    assert.deepEqual(differences(read(book([...numbers(0, 0, [1, x, 3]), ...numbers(1, 0, [0, null, 1])]), columns([0, 2]))), [1, 2]);
    assert.equal(read(book([...numbers(0, 0, [1, x, 3]), ...numbers(1, 0, [0, y]), {col: 1, row: 2, text: 'one', kind: 'text'}]), columns([0, 2])).error,
      notNumeric('B3', 'one'));
  }
});

test('independent: each column on its own, with its values while there are at most 100', () => {
  // Windows J1:K8: x = 2…8, y = 1, 3, 5, 7.
  const w = book([...numbers(0, 0, [2, 3, 4, 5, 6, 7, 8]), ...numbers(1, 0, [1, 3, 5, 7])]);
  const {fingerprint, ...result} = read(w, columns([0, 2]), 'independent');
  assert.deepEqual(result, {sheet: 0, sheetName: 'Data', design: 'independent', left: 0, right: 1, headerRow: false, firstRow: 1, lastRow: 7,
    samples: [{count: 7, values: [2, 3, 4, 5, 6, 7, 8]}, {count: 4, values: [1, 3, 5, 7]}]});
  // A missing value in one column removes nothing from the other.
  const uneven = book([...numbers(0, 0, [1, null, 3, 4]), {col: 0, row: 4, text: '*', kind: 'text'}, ...numbers(1, 0, [null, 2, null, 4, 5])]);
  assert.deepEqual(read(uneven, columns([0, 2]), 'independent').samples, [{count: 3, values: [1, 3, 4]}, {count: 3, values: [2, 4, 5]}]);
  const sized = n => book([...numbers(0, 0, Array.from({length: n}, (_, i) => i)), ...numbers(1, 0, Array.from({length: 100}, (_, i) => 2 * i))], {height: 200});
  assert.deepEqual(read(sized(100), columns([0, 2]), 'independent').samples.map(s => [s.count, s.values.length]), [[100, 100], [100, 100]]);
  assert.deepEqual(read(sized(101), columns([0, 2]), 'independent').samples.map(s => [s.count, s.values.length]), [[101, 0], [100, 100]]);
});

test('a refusal names the first cell the analysis cannot read, the left column first, by its trimmed text up to 40 characters', () => {
  const cells = [...numbers(0, 0, [1, 2, 3, 4, 5, 6, 7, 8, 9]), ...numbers(1, 0, [1, 2, 3, 4, 5, 6, 7, 8, 9])];
  const at = (...extra) => book([...cells.filter(c => !extra.some(e => e.col === c.col && e.row === c.row)), ...extra]);
  const right = {col: 1, row: 1, text: 'n/a', kind: 'text'}, left = {col: 0, row: 7, text: '\u00a0 abc\t', kind: 'text'};
  assert.equal(read(at(right, left), columns([0, 2])).error, notNumeric('A8', 'abc'));
  assert.equal(read(at(right), columns([0, 2]), 'independent').error, notNumeric('B2', 'n/a'));
  const text = value => read(at({col: 0, row: 2, text: value, kind: 'text'}), columns([0, 2])).error;
  assert.equal(text('x'.repeat(41)), notNumeric('A3', 'x'.repeat(40) + '…'));
  assert.equal(text('y'.repeat(40)), notNumeric('A3', 'y'.repeat(40)));
  // Characters, not UTF-16 code units: the cut never splits a surrogate pair.
  assert.equal(text('\u{1F600}'.repeat(41)), notNumeric('A3', '\u{1F600}'.repeat(40) + '…'));
});

test('the fingerprint is the one the click check reads, taken with the read, and moves with an edit and the setting', () => {
  const w = book([...numbers(0, 0, [11, 14, 17]), ...numbers(1, 0, [10, 11, 15])]), selection = rect(0, 0, 2, 3);
  const plain = read(w, selection);
  assert.equal(plain.fingerprint, selectionFingerprint(w, 0, selection));
  w.sheets[0].store.headerRow = true;
  assert.notEqual(selectionFingerprint(w, 0, selection), plain.fingerprint);
  const headed = read(w, selection);
  assert.equal(headed.fingerprint, selectionFingerprint(w, 0, selection));
  w.sheets[0].store.paste(0, 2, '18');
  w.changed();
  assert.notEqual(selectionFingerprint(w, 0, selection), headed.fingerprint);
});

test('the transfer posts the paired differences as one f64 snapshot column, and returns plain values only', async () => {
  const w = book([...numbers(0, 0, [11, 14, 17, 22, 23, 1]), ...numbers(1, 0, [10, 11, 15, 20, 19])]);
  const posts = [];
  const post = async sheets => { const bytes = encodeSnapshot(sheets); posts.push(bytes); return {id: `snapshot-${posts.length}`, bytes: bytes.length}; };
  const typed = value => ArrayBuffer.isView(value) || (!!value && typeof value === 'object' && Object.values(value).some(typed));
  const paired = await measurementTransfer(read(w, columns([0, 2])), post);
  const {fingerprint, ...fields} = paired;
  assert.deepEqual(fields, {sheet: 0, sheetName: 'Data', design: 'paired', left: 0, right: 1, headerRow: false, firstRow: 1, lastRow: 6, pairs: 5,
    snapshot: {id: 'snapshot-1', bytes: posts[0].length}});
  assert.equal(typed(paired), false);
  const {sheets} = decodeSnapshot(posts[0]), [column] = sheets[0].columns;
  assert.deepEqual([sheets.length, sheets[0].columns.length, column.col, Array.from(column.rows), Array.from(column.kinds), Array.from(column.nums), column.texts.size],
    [1, 1, 0, [0, 1, 2, 3, 4], [1, 1, 1, 1, 1], [1, 3, 2, 2, 4], 0]);
  // No pairs, the independent card and refusals post nothing.
  const none = await measurementTransfer(read(w, rect(0, 10, 2, 3)), post);
  assert.deepEqual([none.pairs, 'snapshot' in none, 'differences' in none], [0, false, false]);
  const independent = await measurementTransfer(read(w, columns([0, 2]), 'independent'), post);
  assert.deepEqual(independent.samples, [{count: 6, values: [11, 14, 17, 22, 23, 1]}, {count: 5, values: [10, 11, 15, 20, 19]}]);
  assert.equal(typed(independent), false);
  assert.equal((await measurementTransfer(read(w, rect(0, 0, 1, 1)), post)).error, PAIRED_SELECTION);
  assert.equal(posts.length, 1);
});

test('the selection and overflow texts are word for word those of Windows', () => {
  const windows = readFileSync(new URL('../FullEngine/Upstream/StatsDirectUI/UI/frmSpreadsheetGear.MeasurementDiagnostics.cs', import.meta.url), 'utf8');
  for (const text of [PAIRED_SELECTION, INDEPENDENT_SELECTION, TOO_LARGE]) assert.ok(windows.includes(`"${text}"`), text);
});

// The analysis's own path for the same selection, cell by cell: analysisMetadata, worksheetRows, columnValues and
// checkColumnData (operation-data.mjs worksheetInputFrom refuses in the same order), then ReadFrame's rule on each text.
function analysisRead(w, selection, design) {
  const store = w.sheets[0].store;
  const source = analysisMetadata(w, 0, {columns: selection.columns.toArray(), range: selection.current?.range});
  const {first, last} = worksheetRows(source, source.selection);
  const data = columnValues(w, 0, {sheet: 0, sheetName: 'Data', columns: source.selection, first, last});
  try { checkColumnData(data); } catch (error) { return {error: error.message}; }
  const parsed = data.columns.map(column => column.values.map(analysisNumber));
  for (const [k, values] of parsed.entries()) {
    const i = values.indexOf(null);
    if (i < 0) continue;
    const characters = [...trimSpace(data.columns[k].values[i])], row = first + i;
    const text = characters.length > 40 ? characters.slice(0, 40).join('') + '…' : characters.join('');
    return {error: notNumeric(columnName(source.selection[k]) + row, text) + (row === 1 && !store.headerRow ? HEADINGS : '')};
  }
  const present = parsed.map(values => values.filter(x => !Number.isNaN(x)));
  if (design === 'independent') return {samples: present.map(values => ({count: values.length, values: values.length <= 100 ? values : []}))};
  const found = [];
  for (let i = 0; i < parsed[0].length; i++) {
    const x = parsed[0][i], y = parsed[1][i];
    if (Number.isNaN(x) || Number.isNaN(y)) continue;
    if (!Number.isFinite(x - y) || x - y === -Number.MAX_VALUE) return {error: TOO_LARGE};
    found.push(x - y);
  }
  return {pairs: found.length, differences: found};
}

test('the card reads what the analysis of the same selection reads, on random workbooks', () => {
  let seed = 20261127;
  // mulberry32
  const random = () => { seed = (seed + 0x6D2B79F5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  const pick = list => list[Math.floor(random() * list.length)];
  const number = () => random() < 0.1 ? pick(['1.5e+308', '-1.5e+308']) : String(Math.round(random() * 20000 - 10000) / 100);
  const CELLS = [
    () => ({text: pick(['1.50', '+5', ' 7 ', '1e3', '-0', '.5', '5.', '0012', ' 12', '12\u0085', '12\u0000', '\u00a012\u00a0']), kind: pick(['number', 'text'])}),
    () => ({text: pick(['abc', 'NA', '.', 'MISSING', '* (missing)', 'Infinity', '1e400', '\ufeff12', '1,5', '\u22125', 'z'.repeat(45)]), kind: 'text'}),
    () => ({text: pick(['*', ' * ']), kind: 'text'}),
    () => pick([{text: 'TRUE', kind: 'boolean'}, {text: '2024-01-31', kind: 'datetime'}, {text: '12:30:00', kind: 'timespan'}, {text: '#DIV/0!', kind: 'error'}]),
    () => pick([{text: '5', kind: 'number', formula: 'A1+1'}, {text: '', kind: 'blank', formula: 'A1+1'}, {text: '', kind: 'blank', formula: 'IF(A1>0,"",A1)', savedEmpty: true}]),
    () => ({text: pick([String(-Number.MAX_VALUE), '-1.7976931348623157e308']), kind: 'number'}),
    () => ({text: '', kind: 'blank', rMissing: true})
  ];
  const outcomes = {values: 0, errors: 0, formulas: 0, text: 0, heading: 0, overflow: 0};
  for (let t = 0; t < 3000; t++) {
    // Titles in row 1, with the setting ticked or, sometimes, not.
    const headerRow = random() < 0.5, titles = headerRow || random() < 0.3, offset = random() < 0.2 ? 4090 : 0, length = 4 + Math.floor(random() * 30), mixed = random() < 0.5;
    const cells = [];
    for (let c = 0; c < 4; c++) {
      if (titles) cells.push({col: c, row: 0, text: 'Heading ' + c, kind: 'text'});
      for (let r = Math.max(offset, titles ? 1 : 0); r < offset + length; r++) {
        const u = random();
        if (u >= 0.15) cells.push({col: c, row: r, ...(mixed && u > 0.8 ? pick(CELLS)() : {text: number(), kind: 'number'})});
      }
    }
    const formulaRegions = [];
    if (random() < 0.2) {
      const firstColumn = Math.floor(random() * 4), firstRow = offset + Math.floor(random() * length);
      formulaRegions.push({firstRow, lastRow: firstRow + Math.floor(random() * 6), firstColumn, lastColumn: firstColumn});
    }
    const w = book(cells, {headerRow, height: offset + 100, formulaRegions});
    if (random() < 0.15) w.changed();
    const x = Math.floor(random() * 3), y = (random() < 0.3 ? 0 : offset) + Math.floor(random() * 8);
    const selection = random() < 0.3 ? columns([x, x + 2]) : rect(x, y, 2, 1 + Math.floor(random() * 40)), design = random() < 0.5 ? 'paired' : 'independent';
    // The analysis reads row 2 for a rectangle of the heading row alone (worksheetRows); the card reads no row there.
    if (headerRow && selection.current?.range.y === 0 && selection.current.range.height === 1) continue;
    const card = read(w, selection, design), expected = analysisRead(w, selection, design), name = `case ${t}: ${JSON.stringify(cells).slice(0, 300)}`;
    if (expected.error) assert.equal(card.error, expected.error, name);
    else if (design === 'paired') assert.deepEqual([card.error, card.pairs, differences(card)], [undefined, expected.pairs, expected.differences], name);
    else assert.deepEqual([card.error, card.samples], [undefined, expected.samples], name);
    const error = card.error ?? '';
    outcomes[error === EXCEL_ERRORS ? 'errors' : error === RECALCULATE ? 'formulas' : error === TOO_LARGE ? 'overflow'
      : error.endsWith(HEADINGS) ? 'heading' : error ? 'text' : 'values']++;
  }
  // Every outcome was met, and most cases were compared.
  assert.ok(Object.values(outcomes).every(n => n > 10) && Object.values(outcomes).reduce((a, b) => a + b) > 2500, JSON.stringify(outcomes));
});

test('two whole columns of 1,048,576 rows are read a stored chunk at a time', async () => {
  const n = MAX_ROWS, a = new Float64Array(n), b = new Float64Array(n);
  for (let i = 0; i < n; i++) { a[i] = (i % 1000) / 8; b[i] = i % 7; }
  const w = new WorkbookStore();
  w.load({name: 'Big.xlsx', sheets: [{name: 'Data', rows: n, columns: 2, headerRow: false, columnar: [columnar(0, a), columnar(1, b)]}]});
  const whole = columns([0, 2]);
  let t = performance.now();
  const paired = read(w, whole);
  const pairedTime = performance.now() - t;
  t = performance.now();
  const independent = read(w, whole, 'independent');
  const independentTime = performance.now() - t;
  assert.deepEqual([paired.pairs, paired.firstRow, paired.lastRow], [n, 1, n]);
  assert.ok(paired.differences.every((d, i) => d === a[i] - b[i]));
  assert.deepEqual(independent.samples, [{count: n, values: []}, {count: n, values: []}]);
  // The fingerprint holds the columns' slice, never their rows.
  assert.ok(paired.fingerprint.length < 300, paired.fingerprint);
  let posted;
  await measurementTransfer(paired, async sheets => { posted = encodeSnapshot(sheets); return {id: 'big', bytes: posted.length}; });
  // 13 bytes a pair (its row, kind and value) beside the headers.
  assert.ok(posted.length > 13 * n && posted.length < 13 * n + 64, String(posted.length));
  assert.ok(decodeSnapshot(posted).sheets[0].columns[0].nums.every((d, i) => d === a[i] - b[i]));
  assert.ok(pairedTime < 5000 && independentTime < 5000, `paired ${pairedTime.toFixed(0)} ms, independent ${independentTime.toFixed(0)} ms`);
  console.log(`scale: 2 × ${n} rows read in ${pairedTime.toFixed(0)} ms (paired) and ${independentTime.toFixed(0)} ms (independent); snapshot ${posted.length} bytes`);
});
