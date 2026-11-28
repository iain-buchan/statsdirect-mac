import {test} from 'node:test';
import assert from 'node:assert/strict';
import {CompactSelection} from '@glideapps/glide-data-grid';
import {WorkbookStore} from './workbook.mjs';
import {selectionAddress, workbookHasData, aiWorksheetState, selectionFingerprint, headingCells, worksheetAISelection} from './ai-selection.mjs';

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
  // So does the header-row setting, which advances neither revision.
  const headed = print(rect(0, 0, 1, 1));
  w.sheets[0].store.headerRow = !w.sheets[0].store.headerRow;
  assert.notEqual(print(rect(0, 0, 1, 1)), headed);
});

test('a heading counts when its row-1 cell holds text, even text that reads like the stand-in', () => {
  const w = book([{name: 'One', rows: 10, columns: 4, headerRow: true, cells: [
    {col: 0, row: 0, text: 'Before', kind: 'text'}, {col: 1, row: 0, text: 'Column B', kind: 'text'},
    {col: 0, row: 1, text: '1', kind: 'number'}, {col: 2, row: 1, text: '2', kind: 'number'}]}]);
  assert.deepEqual(headingCells(w, 0, [0, 1, 2]), [0, 1]);
  w.sheets[0].store.headerRow = false;
  assert.deepEqual(headingCells(w, 0, [0, 1, 2]), []);
});

test('the state the pane receives names the sheet and holds no cell values', () => {
  const w = book([{name: 'Sheet 1', rows: 20, columns: 4, cells: [{col: 0, row: 0, text: 'Qzheading', kind: 'text'}, {col: 0, row: 1, text: '142741', kind: 'number'}]}]);
  const state = aiWorksheetState(w, 0, rect(0, 0, 2, 3));
  assert.deepEqual(state, {sheet: 0, sheetName: 'Sheet 1', label: 'A1:B3', singleCell: false, hasData: true, headerRow: true});
  assert.equal(JSON.stringify(state).includes('142741') || JSON.stringify(state).includes('Qzheading'), false);
});

test('the "First row has column names" setting is part of the state, so the page posts a change of it', () => {
  const w = book([{name: 'Sheet 1', rows: 20, columns: 4, headerRow: true, cells: [{col: 0, row: 0, text: 'Before', kind: 'text'}, {col: 0, row: 1, text: '12', kind: 'number'}]}]);
  // main.tsx posts the state when this text differs from the last one it posted.
  const posted = () => JSON.stringify(aiWorksheetState(w, 0, rect(0, 0, 2, 3)));
  const headed = posted();
  w.sheets[0].store.headerRow = false;
  assert.notEqual(posted(), headed);
  assert.equal(aiWorksheetState(w, 0, rect(0, 0, 2, 3)).headerRow, false);
  w.sheets[0].store.headerRow = true;
  assert.equal(posted(), headed);
});

test('the selection a method offer is made for carries the click fingerprint of the same moment', () => {
  const w = book([{name: 'Sheet 1', rows: 20, columns: 4, headerRow: true, cells: [
    {col: 0, row: 0, text: 'Qzheading', kind: 'text'}, {col: 0, row: 1, text: '11', kind: 'number'}, {col: 1, row: 1, text: '10', kind: 'number'}]}]);
  const selection = rect(0, 0, 2, 5);
  const offered = worksheetAISelection(w, 0, selection);
  // The fields WorksheetAIAnalysis.swift decodes, as main.tsx gave them before, and no cell value.
  assert.deepEqual(offered, {sheet: 0, sheetName: 'Sheet 1', workbookRevision: w.revision, sheetRevision: w.sheets[0].store.version,
    columns: [], rowCount: 0, firstRow: null, lastRow: null, range: {x: 0, y: 0, width: 2, height: 5}, ranges: [],
    fingerprint: selectionFingerprint(w, 0, selection)});
  assert.equal(/Qzheading|"11"|"10"/.test(JSON.stringify(offered)), false);
  assert.deepEqual(worksheetAISelection(w, 0, columns([0, 2])).columns, [0, 1]);
  const picked = worksheetAISelection(w, 0, rows([1, 4]));
  assert.deepEqual([picked.rowCount, picked.firstRow, picked.lastRow], [3, 1, 3]);
  // "First row has column names" leaves the selection and both revisions as they were, so only the fingerprint tells an
  // offer chosen on a distribution card that its card was read with the other setting.
  const {fingerprint: headed, ...before} = offered;
  w.sheets[0].store.headerRow = false;
  const {fingerprint: unheaded, ...after} = worksheetAISelection(w, 0, selection);
  assert.deepEqual(after, before);
  assert.notEqual(unheaded, headed);
  assert.equal(unheaded, selectionFingerprint(w, 0, selection));
  // A selection changed in the same call is the one both name.
  const moved = rect(2, 0, 2, 5), then = worksheetAISelection(w, 0, moved);
  assert.deepEqual([then.range, then.fingerprint], [moved.current.range, selectionFingerprint(w, 0, moved)]);
});
