import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {worksheetRImport} from './worksheet-r.mjs';
import {analysisMetadata, columnValues} from './analysis-source.mjs';
import {worksheetRows, worksheetInput, worksheetInputFrom} from './operation-data.mjs';
import {rDataTables} from './r-data.mjs';
import {planWriteBack} from './write-back.mjs';

// Array, spill and What-If Data Table results: cells an anchor's formula fills, with no formula of their own, which the
// loader reports as regions ({firstRow, lastRow, firstColumn, lastColumn}, zero-based) beside the cells it read.
const RECALCULATE = 'Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.';
const READ_ONLY = 'Formula cells are read-only. Edit their formulas in Excel.';
const DATA_COPY = 'Recalculate formula results in Excel before exporting an Excel 97–2003 data copy.';
const cell = (col, row, text, kind = 'number', extra = {}) => ({col, row, text, kind, ...extra});
function book(cells, formulaRegions, {columns = 10, rows = 20, headerRow = false} = {}) {
  const w = new WorkbookStore();
  w.load({name: 'Regions.xlsx', id: 'x', formulaCount: 1, sheets: [{name: 'Data', columns, rows, headerRow, cells, formulaRegions}]});
  return w;
}
// Typed column records as the loader's snapshot gives them, for large sheets.
function column(col, n, value, formula) {
  const rows = new Uint32Array(n), nums = new Float64Array(n), formulas = new Map();
  for (let i = 0; i < n; i++) { rows[i] = i; nums[i] = value(i); if (formula) formulas.set(i, formula(i)); }
  return {col, rows, kinds: new Uint8Array(n).fill(1), nums, texts: new Map(), formulas, extras: new Map()};
}

test('formula result checks cost O(log n) a cell, not a look at every region of the column', () => {
  // =XLOOKUP(A1,Ids,Table1[[Age]:[Weight]]) filled down: an array formula over B:D in each row, results saved in B, C and D.
  // Each region counts the reads of its fields, and stops the test once they pass what an index costs to build.
  const n = 20000, budget = 50 * n;
  let reads = 0;
  const regions = Array.from({length: n}, (_, r) => {
    const fields = {firstRow: r, lastRow: r, firstColumn: 1, lastColumn: 3}, region = {};
    for (const key of Object.keys(fields)) Object.defineProperty(region, key, {enumerable: true, get() {
      if (++reads > budget) throw new Error(`the regions were read more than ${budget} times`);
      return fields[key];
    }});
    return region;
  });
  const w = new WorkbookStore();
  w.load({name: 'Lookups.xlsx', id: 'x', formulaCount: n, sheets: [{name: 'Data', rows: n, columns: 4, headerRow: false, formulaRegions: regions,
    columnar: [column(0, n, i => i + 1), column(1, n, i => 20 + i % 50, i => `_xlfn.XLOOKUP(A${i + 1},Ids,Table1[[Age]:[Weight]])`), column(2, n, i => 150 + i % 40), column(3, n, i => 60 + i % 30)]}]});
  const store = w.sheets[0].store;
  assert.equal(worksheetRImport(w, 0, {columns: [2]}, 'selected').columns[0].values.length, n);
  assert.equal(worksheetRImport(w, 0, {columns: [2]}, 'selected', {list: true}).columns[0].values.length, n);
  assert.equal(columnValues(w, 0, {columns: [2], first: 1, last: n}).uncached, 0);
  assert.equal(rDataTables(w, 0).tables[0].rows, n);
  assert.equal(worksheetRImport(w, 0, {rows: [0, 1, 2, 3, 4]}).selected.range, 'A1:D5');
  assert.equal(worksheetRImport(w, 0, {range: {x: 2, y: n - 3, width: 1, height: 3}}, 'selected').columns[0].values.length, 3);
  assert.deepEqual([store.formulaResult(2, n - 1), store.formulaResult(4, 0), store.formulaResult(3, 7)], [true, false, true]);
  assert.ok(reads <= budget, `${reads} reads`);
  // Edited, every result is refused, from the first cell read.
  w.changed();
  assert.throws(() => worksheetRImport(w, 0, {columns: [2]}, 'selected'), {message: RECALCULATE});
  assert.equal(columnValues(w, 0, {columns: [2], first: 1, last: n}).uncached, n);
});

test('whole rows find the result spans they meet by binary search, however many regions the sheet has', () => {
  // One single-cell array formula in each row ({=A1*2} in B1, and so on): the preview for the first five rows.
  const n = 200000, w = new WorkbookStore();
  w.load({name: 'Arrays.xlsx', id: 'x', formulaCount: n, sheets: [{name: 'Data', rows: n, columns: 2, headerRow: false,
    columnar: [column(0, n, i => i + 1), column(1, n, i => 2 * (i + 1), i => `A${i + 1}*2`)],
    formulaRegions: Array.from({length: n}, (_, r) => ({firstRow: r, lastRow: r, firstColumn: 1, lastColumn: 1}))}]});
  const started = performance.now();
  assert.equal(worksheetRImport(w, 0, {rows: [0, 1, 2, 3, 4]}).selected.range, 'A1:B5');
  assert.equal(worksheetRImport(w, 0, {rows: [n - 2, n - 1]}).selected.range, `A${n - 1}:B${n}`);
  const elapsed = performance.now() - started;
  assert.ok(elapsed < 2000, `the previews took ${elapsed.toFixed(0)} ms`);
  // Regions in a column without any stored cell, apart and touching, and rows between them.
  const sparse = book([cell(0, 0, '1')], [{firstRow: 3, lastRow: 4, firstColumn: 5, lastColumn: 5}, {firstRow: 5, lastRow: 5, firstColumn: 5, lastColumn: 6},
    {firstRow: 9, lastRow: 9, firstColumn: 5, lastColumn: 5}]);
  assert.deepEqual(sparse.sheets[0].store.formulaResultSpans(5), [{firstRow: 3, lastRow: 5}, {firstRow: 9, lastRow: 9}]);
  for (const [rows, range] of [[[4], 'F5'], [[0, 7], 'A1'], [[7, 8], null], [[5, 9], 'F6:G6,F10:G10'], [[2, 6, 9], 'F10']]) {
    const preview = worksheetRImport(sparse, 0, {rows});
    assert.equal(preview.selected?.range ?? null, range, JSON.stringify(rows));
  }
});

test('array, spill and data-table results are read-only, as formula cells are, and the other edits still save', () => {
  // B2:C3 spills from B2; E2:E3 is a CSE array from E2; G3:G4 a What-If Data Table from G3; H2:H3 an array whose results
  // the file did not save; J5 an ordinary value.
  const w = book([
    cell(1, 1, '1', 'number', {formula: '_xlfn.SEQUENCE(2,2)'}), cell(2, 1, '2'), cell(1, 2, '3'), cell(2, 2, '4'),
    cell(0, 1, '5'), cell(0, 2, '6'), cell(4, 1, '10', 'number', {formula: 'A2:A3*2'}), cell(4, 2, '12'),
    cell(6, 2, '7', 'number', {formula: '='}), cell(6, 3, '8'), cell(7, 1, '', 'blank', {formula: 'A2:A3+1'}), cell(9, 4, '5')],
  [{firstRow: 1, lastRow: 2, firstColumn: 1, lastColumn: 2}, {firstRow: 1, lastRow: 2, firstColumn: 4, lastColumn: 4},
    {firstRow: 2, lastRow: 3, firstColumn: 6, lastColumn: 6}, {firstRow: 1, lastRow: 2, firstColumn: 7, lastColumn: 7}]);
  const store = w.sheets[0].store;
  // Typing, Delete, paste and cut all reach the store as edits, and each is refused.
  for (const [c, r] of [[2, 2], [2, 1], [1, 2], [4, 2], [6, 3], [7, 2]]) {
    assert.throws(() => store.apply([[c, r, '99']]), {message: READ_ONLY}, `typed into ${c},${r}`);
    assert.throws(() => store.paste(c, r, '99'), {message: READ_ONLY}, `pasted into ${c},${r}`);
  }
  // The grid and the formula bar lock the same cells (main.tsx asks readOnly).
  assert.deepEqual([[1, 1], [2, 1], [1, 2], [2, 2], [4, 2], [6, 3], [7, 2], [9, 4], [0, 1], [3, 1], [2, 3]].map(([c, r]) => store.readOnly(c, r)),
    [true, true, true, true, true, true, true, false, false, false, false]);
  assert.throws(() => store.apply([[2, 2, '']]), {message: READ_ONLY});
  assert.throws(() => store.apply([[9, 4, '6'], [2, 2, '']]), {message: READ_ONLY}, 'a clear across the region');
  assert.throws(() => store.paste(3, 2, '1\t2'), {message: READ_ONLY}, 'a paste from D3 that reaches E3');
  assert.equal(store.apply([[7, 2, '']]), false, 'clearing a result that is already blank changes nothing');
  assert.deepEqual([store.version, store.canUndo, store.get(2, 2)], [0, false, '4'], 'nothing refused was applied');
  assert.equal(store.paste(8, 2, '1\t2\n3\t4'), true, 'a paste beside the regions');
  assert.ok(store.undo());
  // Analysis output written in place of the selected column C clears it first, and is refused; so are columns it inserts.
  const frame = {name: 'Out', columns: 1, rows: 3, headerRow: false, lengths: [2], missingIndicator: '*', cells: [{col: 0, row: 0, text: 'fit'}, {col: 0, row: 1, text: '1'}, {col: 0, row: 2, text: '2'}]};
  const write = (placement, columns) => {
    const plan = planWriteBack(store, [frame], placement, {firstRow: 2, lastRow: 3, columns}, {backed: true});
    return store.apply(plan.edits, Math.max(store.rows, plan.rows), Math.max(store.columns.length, plan.cols), plan.inserts);
  };
  assert.throws(() => write('ReplaceSelection', [2]), {message: READ_ONLY});
  assert.equal(write('BeforeSelection', [2]), true);
  // The new column C is not a result; the spill's right-hand column is now D, still read-only, and Undo moves it back.
  assert.deepEqual([store.readOnly(2, 2), store.readOnly(3, 2), store.get(3, 2)], [false, true, '4']);
  assert.throws(() => store.apply([[3, 2, '99']]), {message: READ_ONLY});
  assert.ok(store.undo());
  assert.deepEqual([store.readOnly(2, 2), store.readOnly(3, 2)], [true, false]);
  // In one step with its insertions, a result is judged by the column it was in before them.
  const cols = store.columns.length;
  assert.throws(() => store.apply([[3, 2, '99']], store.rows, cols + 1, [{col: 2, count: 1}]), {message: READ_ONLY});
  assert.equal(store.apply([[2, 2, '99']], store.rows, cols + 1, [{col: 2, count: 1}]), true);
  assert.ok(store.undo());
  // An ordinary edit is accepted, and the save sends it alone.
  assert.equal(store.apply([[9, 4, '6']]), true);
  w.changed();
  assert.deepEqual(w.exportColumns().sheets[0].columns.map(c => [c.col, Array.from(c.rows), Array.from(c.nums)]), [[9, [4], [6]]]);
});

test('a whole-column analysis takes in trailing results without saved values, as the R import does, and refuses them', () => {
  // C2:C5 hold 11 to 14 under the title in C1; B6 spills over B6:C8. Reopened after a save that removed the saved results
  // (the streaming save writes C6:C8 empty), the results are missing, and a whole column C must not quietly stop at C5.
  const values = [cell(2, 0, 'Value', 'text'), cell(0, 0, 'Id', 'text'), ...[11, 12, 13, 14].map((v, i) => cell(2, i + 1, String(v)))];
  const spill = {firstRow: 5, lastRow: 7, firstColumn: 1, lastColumn: 2};
  const ids = rows => Array.from({length: rows}, (_, i) => cell(0, i + 1, String(i + 1)));
  const analyse = w => {
    const meta = analysisMetadata(w, 0, {columns: [2]}), {first, last} = worksheetRows(meta, [2]);
    return {end: meta.columnEnds[2], first, last, run: () => {
      const pending = worksheetInput(meta, [2], first, last);
      return worksheetInputFrom(pending, columnValues(w, 0, pending.request)).columns[0].values;
    }};
  };
  for (const rows of [4, 7]) {   // column A ends with C5, or reaches C8
    const reopened = book([...values, ...ids(rows), cell(1, 5, '', 'blank', {formula: '_xlfn.SEQUENCE(3,2)'}), cell(2, 5, ''), cell(2, 6, ''), cell(2, 7, '')], [spill], {headerRow: true});
    const missing = analyse(reopened);
    assert.deepEqual([missing.end, missing.first, missing.last], [8, 2, 8]);
    assert.throws(missing.run, {message: rows === 7 ? 'Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.' : 'Enter a valid first and last worksheet row.'});
    assert.throws(() => worksheetRImport(reopened, 0, {columns: [2]}, 'selected'), {message: RECALCULATE});
  }
  // Opened fresh, with the results Excel saved, the analysis reads all seven, and the R import sends them.
  const fresh = book([...values, ...ids(7), cell(1, 5, '1', 'number', {formula: '_xlfn.SEQUENCE(3,2)'}), cell(2, 5, '2'), cell(1, 6, '3'), cell(2, 6, '4'), cell(1, 7, '5'), cell(2, 7, '6')], [spill], {headerRow: true});
  const read = analyse(fresh);
  assert.deepEqual([read.end, read.first, read.last, read.run()], [8, 2, 8, ['11', '12', '13', '14', '2', '4', '6']]);
  assert.deepEqual(worksheetRImport(fresh, 0, {columns: [2]}, 'selected', {headings: true}).columns[0].values, ['11', '12', '13', '14', '2', '4', '6']);
});

test('the Excel 97-2003 data copy refuses formula results that may be out of date or were never saved, as R data does', () => {
  // A1:B1 is {=E1+{0,1}} from A1 and F1 is =E1*2, saved with E1 = 2 as 2, 3 and 4.
  const array = () => book([cell(0, 0, '2', 'number', {formula: 'E1+{0,1}'}), cell(1, 0, '3'), cell(4, 0, '2'), cell(5, 0, '4', 'number', {formula: 'E1*2'})],
    [{firstRow: 0, lastRow: 0, firstColumn: 0, lastColumn: 1}]);
  const copy = w => w.exportColumns(true).sheets[0].columns.map(c => [c.col, Array.from(c.rows), Array.from(c.nums)]);
  assert.deepEqual(copy(array()), [[0, [0], [2]], [1, [0], [3]], [4, [0], [2]], [5, [0], [4]]]);
  // Edited, every result may be out of date: the data copy is refused, as the R data export is; the Excel save is not.
  const edited = array();
  assert.ok(edited.sheets[0].store.apply([[4, 0, '10']]));
  edited.changed();
  assert.throws(() => edited.exportColumns(true), {message: DATA_COPY});
  assert.throws(() => rDataTables(edited, 0), {message: 'Recalculate formula results in Excel before saving this table as R data.'});
  assert.deepEqual(edited.exportColumns().sheets[0].columns.map(c => c.col), [4]);
  // Unedited, an array result, a spill result absent from the file, or a formula the file saved no result for is refused.
  const unsaved = [
    book([cell(0, 0, '2', 'number', {formula: 'E1+{0,1}'}), cell(1, 0, ''), cell(4, 0, '2')], [{firstRow: 0, lastRow: 0, firstColumn: 0, lastColumn: 1}]),
    book([cell(0, 0, '1', 'number', {formula: '_xlfn.SEQUENCE(2,2)'}), cell(1, 0, '2'), cell(0, 1, '3')], [{firstRow: 0, lastRow: 1, firstColumn: 0, lastColumn: 1}]),
    book([cell(0, 0, '1', 'number', {formula: '_xlfn.SEQUENCE(1000000)'})], [{firstRow: 0, lastRow: 999999, firstColumn: 0, lastColumn: 0}], {rows: 1000000}),
    book([cell(0, 0, '2'), cell(5, 0, '', 'blank', {formula: 'E1*2'})], [])];
  for (const w of unsaved) assert.throws(() => w.exportColumns(true), {message: DATA_COPY});
  // A saved empty-text result is a blank cell, and a workbook without formulas is copied after any edit.
  const empty = book([cell(0, 0, '', 'blank', {formula: 'IF(E1>0,{"",""},0)', savedEmpty: true}), cell(1, 0, '', 'blank', {savedEmpty: true}), cell(4, 0, '2')],
    [{firstRow: 0, lastRow: 0, firstColumn: 0, lastColumn: 1}]);
  assert.deepEqual(copy(empty), [[4, [0], [2]]]);
  const plain = book([cell(0, 0, '1'), cell(1, 0, '2')], []);
  assert.ok(plain.sheets[0].store.apply([[0, 0, '5']]));
  plain.changed();
  assert.deepEqual(copy(plain), [[0, [0], [5]], [1, [0], [2]]]);
});
