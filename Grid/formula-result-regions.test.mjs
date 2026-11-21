import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {worksheetRImport} from './worksheet-r.mjs';
import {columnValues} from './analysis-source.mjs';
import {rDataTables} from './r-data.mjs';

// Array, spill and What-If Data Table results: cells an anchor's formula fills, with no formula of their own, which the
// loader reports as regions ({firstRow, lastRow, firstColumn, lastColumn}, zero-based) beside the cells it read.
const RECALCULATE = 'Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.';
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
