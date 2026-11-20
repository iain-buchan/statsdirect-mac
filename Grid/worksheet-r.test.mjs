import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {worksheetRSelection} from './worksheet-r.mjs';

function workbook(cells, {headerRow = false, columns = 8, rows = 100} = {}) {
  const book = new WorkbookStore();
  book.load({name: 'Selected.xlsx', sheets: [{name: 'Measurements', headerRow, columns, rows, cells}]});
  return book;
}
const cell = (col, row, text, kind = 'number', extra = {}) => ({col, row, text, kind, ...extra});

test('R column selection follows the chosen columns and leaves unrelated empty tails behind', () => {
  const book = workbook([cell(0, 0, 'Before', 'text'), cell(1, 0, 'After', 'text'),
    cell(0, 1, '3.25'), cell(0, 3, '5'), cell(1, 1, '2'), cell(4, 90, '999')], {headerRow: true});
  const result = worksheetRSelection(book, 0, {columns: [1, 0]});
  assert.equal(result.rowCount, 3);
  assert.deepEqual(result.columns.map(c => c.title), ['After', 'Before']);
  assert.deepEqual(result.columns.map(c => c.values), [['2', '', ''], ['3.25', '', '5']]);
  assert.equal(result.range, 'B, A · rows 2–4');
});

test('R cell rectangles retain all selected missing positions and original cell types', () => {
  const book = workbook([cell(0, 1, '001', 'text'), cell(1, 1, 'true', 'boolean'), cell(0, 2, '2.5')]);
  const result = worksheetRSelection(book, 0, {range: {x: 0, y: 1, width: 2, height: 4}});
  assert.equal(result.rowCount, 4);
  assert.deepEqual(result.columns[0], {title: 'Column A', values: ['001', '2.5', '', ''], kinds: ['text', 'number', 'blank', 'blank']});
  assert.deepEqual(result.columns[1].values, ['true', '', '', '']);
});

test('R row headings use the populated width and selected data rows', () => {
  const book = workbook([cell(0, 0, 'Name', 'text'), cell(2, 0, 'Count', 'text'),
    cell(0, 1, 'Alpha', 'text'), cell(2, 1, '5'), cell(2, 3, '7')], {headerRow: true});
  const result = worksheetRSelection(book, 0, {rows: [0, 1, 3, 90]});
  assert.equal(result.rowCount, 2);
  assert.equal(result.columns.length, 3);
  assert.deepEqual(result.columns[2].values, ['5', '7']);
  assert.equal(result.range, 'A, B, C · rows 2, 4');
});

test('R selection requires data and refuses Excel errors or stale formula values', () => {
  const book = workbook([cell(0, 0, 'Heading', 'text'), cell(0, 1, '3', 'number', {formula: '1+2'})], {headerRow: true});
  assert.throws(() => worksheetRSelection(book, 0), /Select worksheet/);
  assert.throws(() => worksheetRSelection(book, 0, {range: {x: 0, y: 0, width: 1, height: 1}}), /no data rows/);
  const selected = {columns: [0]};
  assert.deepEqual(worksheetRSelection(book, 0, selected).columns[0].values, ['3']);
  book.sheets[0].store.formulasStale = true;
  assert.throws(() => worksheetRSelection(book, 0, selected), /Recalculate/);
  const errorBook = workbook([cell(0, 0, '#DIV/0!', 'error')]);
  assert.throws(() => worksheetRSelection(errorBook, 0, selected), /Excel errors/);
});

test('R selection handles 10000 by 10 data and refuses oversized scripts explicitly', () => {
  const book = workbook([], {columns: 10, rows: 10000});
  book.sheets[0].store.apply(Array.from({length: 10}, (_, c) => Array.from({length: 10000}, (_, r) => [c, r, String(r + c)])).flat());
  const result = worksheetRSelection(book, 0, {columns: Array.from({length: 10}, (_, c) => c)});
  assert.equal(result.rowCount, 10000);
  assert.equal(result.columns[9].values[9999], '10008');
  assert.throws(() => worksheetRSelection(book, 0, {columns: [0]}, 100), /8 MiB/);
  const large = workbook([], {columns: 8, rows: 1048576});
  assert.throws(() => worksheetRSelection(large, 0, {range: {x: 0, y: 0, width: 8, height: 1048576}}), /8 MiB/);
});
