import {test} from 'node:test';
import assert from 'node:assert/strict';
import {CompactSelection} from '@glideapps/glide-data-grid';
import {WorkbookStore} from './workbook.mjs';
import {selectionAddress, workbookHasData, aiWorksheetState, selectionFingerprint} from './ai-selection.mjs';

const bounds = {columns: 8, rows: 100};
const pieces = (...ranges) => ranges.reduce((selection, range) => selection.add(range), CompactSelection.empty());
const rect = (x, y, width, height, rangeStack = []) =>
  ({columns: CompactSelection.empty(), rows: CompactSelection.empty(), current: {cell: [x, y], range: {x, y, width, height}, rangeStack}});
const columns = (...ranges) => ({columns: pieces(...ranges), rows: CompactSelection.empty()});
const rows = (...ranges) => ({columns: CompactSelection.empty(), rows: pieces(...ranges)});
function book(sheets) { const w = new WorkbookStore(); w.load({name: 'Fixture.xlsx', sheets}); return w; }

test('a rectangle, a single cell and extra rectangles read as A1 addresses', () => {
  assert.deepEqual(selectionAddress(rect(0, 1, 2, 4), bounds), {label: 'A2:B5', singleCell: false});
  assert.deepEqual(selectionAddress(rect(1, 2, 1, 1), bounds), {label: 'B3', singleCell: true});
  assert.deepEqual(selectionAddress(rect(0, 0, 1, 1, [{x: 3, y: 0, width: 1, height: 3}]), bounds), {label: 'A1,D1:D3', singleCell: false});
  const many = rect(0, 0, 1, 1, [1, 2, 3, 4, 5].map(x => ({x, y: 0, width: 1, height: 1})));
  assert.equal(selectionAddress(many, bounds).label, 'A1,B1,C1,D1,…');
});

test('a selection beyond the sheet is clipped, and one wholly outside shows nothing', () => {
  // The trailing "Add a row" row is row 100 (0-based) of a 100-row sheet.
  assert.equal(selectionAddress(rect(0, 98, 2, 5), bounds).label, 'A99:B100');
  assert.deepEqual(selectionAddress(rect(0, 100, 1, 1), bounds), {label: '', singleCell: false});
  assert.deepEqual(selectionAddress(rect(9, 0, 1, 1), bounds), {label: '', singleCell: false});
});

test('whole columns and whole rows read as Excel writes them', () => {
  assert.equal(selectionAddress(columns([0, 3]), bounds).label, 'A:C');
  assert.equal(selectionAddress(columns([1, 2], [4, 5]), bounds).label, 'B:B,E:E');
  assert.equal(selectionAddress(columns([0, 1], [2, 3], [4, 5], [6, 7], [7, 8]), {columns: 9, rows: 100}).label, 'A:A,C:C,E:E,G:H');
  assert.equal(selectionAddress(columns([0, 1], [2, 3], [4, 5], [6, 7], [8, 9]), {columns: 10, rows: 100}).label, 'A:A,C:C,E:E,G:G,…');
  assert.equal(selectionAddress(rows([1, 5]), bounds).label, '2:5');
  assert.equal(selectionAddress(rows([1, 2], [4, 5]), bounds).label, '2:5 (some rows)');
  // A corner selection of an Excel-size sheet: only the ends are read.
  assert.equal(selectionAddress(rows([0, 1048576]), {columns: 8, rows: 1048576}).label, '1:1048576');
  assert.deepEqual(selectionAddress({columns: CompactSelection.empty(), rows: CompactSelection.empty()}, bounds), {label: '', singleCell: false});
});

test('the workbook is empty only when no sheet holds a cell, a formula or a result span', () => {
  assert.equal(workbookHasData(new WorkbookStore()), false);
  const blank = book([{name: 'One', rows: 10, columns: 4, cells: []}, {name: 'Two', hidden: true, rows: 10, columns: 4, cells: []}]);
  assert.equal(workbookHasData(blank), false);
  const hidden = book([{name: 'One', rows: 10, columns: 4, cells: []}, {name: 'Two', hidden: true, rows: 10, columns: 4, cells: [{col: 1, row: 2, text: '7', kind: 'number'}]}]);
  assert.equal(workbookHasData(hidden), true);
  const headings = book([{name: 'One', rows: 10, columns: 4, headerRow: true, cells: [{col: 0, row: 0, text: 'Before', kind: 'text'}]}]);
  assert.equal(workbookHasData(headings), true);
  const formula = book([{name: 'One', rows: 10, columns: 4, cells: []}]);
  formula.sheets[0].store.setLoaded([{col: 0, row: 1, text: '', kind: 'blank', formula: 'SUM(B1:B2)'}]);
  assert.equal(workbookHasData(formula), true);
  const edited = new WorkbookStore();
  edited.sheets[0].store.paste(0, 0, '3');
  assert.equal(workbookHasData(edited), true);
});

test('the click fingerprint is exact for sparse rows and columns, without expanding them', () => {
  const w = book([{name: 'One', rows: 1048576, columns: 16384, cells: []}]);
  const print = selection => selectionFingerprint(w, 0, selection);
  // Rows 2, 3, 6 and 2, 4, 6 share their caption but not their fingerprint.
  assert.equal(selectionAddress(rows([1, 3], [5, 6]), bounds).label, selectionAddress(rows([1, 2], [3, 4], [5, 6]), bounds).label);
  assert.notEqual(print(rows([1, 3], [5, 6])), print(rows([1, 2], [3, 4], [5, 6])));
  assert.notEqual(print(columns([0, 1], [2, 3])), print(columns([0, 1], [3, 4])));
  assert.equal(print(rows([1, 3], [5, 6])), print(rows([5, 6], [1, 3])));
  // A whole-sheet row selection stays a few numbers long.
  assert.ok(print(rows([0, 1048576])).length < 300);
  // An edit changes it although the selection does not.
  const before = print(rect(0, 0, 1, 1));
  w.sheets[0].store.paste(0, 0, '3'); w.changed();
  assert.notEqual(print(rect(0, 0, 1, 1)), before);
});

test('the state the pane receives names the sheet and holds no cell values', () => {
  const w = book([{name: 'Sheet 1', rows: 20, columns: 4, cells: [{col: 0, row: 0, text: 'Qzheading', kind: 'text'}, {col: 0, row: 1, text: '142741', kind: 'number'}]}]);
  const state = aiWorksheetState(w, 0, rect(0, 0, 2, 3));
  assert.deepEqual(state, {sheet: 0, sheetName: 'Sheet 1', label: 'A1:B3', singleCell: false, hasData: true});
  assert.equal(JSON.stringify(state).includes('142741') || JSON.stringify(state).includes('Qzheading'), false);
});
