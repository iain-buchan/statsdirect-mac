import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {worksheetRImport} from './worksheet-r.mjs';

function workbook(cells, {headerRow = false, columns = 8, rows = 100} = {}) {
  const book = new WorkbookStore();
  book.load({name: 'Selected.xlsx', sheets: [{name: 'Measurements', headerRow, columns, rows, cells}]});
  return book;
}
const cell = (col, row, text, kind = 'number', extra = {}) => ({col, row, text, kind, ...extra});

test('R selection handles 10000 by 10 data and refuses oversized scripts explicitly', () => {
  const book = workbook([], {columns: 10, rows: 10000});
  book.sheets[0].store.apply(Array.from({length: 10}, (_, c) => Array.from({length: 10000}, (_, r) => [c, r, String(r + c)])).flat());
  const result = worksheetRImport(book, 0, {columns: Array.from({length: 10}, (_, c) => c)}, 'selected');
  assert.equal(result.rowCount, 10000);
  assert.equal(result.columns[9].values[9999], '10008');
  assert.throws(() => worksheetRImport(book, 0, {columns: [0]}, 'selected', 100), /8 MiB/);
  const large = workbook([], {columns: 8, rows: 1048576});
  assert.throws(() => worksheetRImport(large, 0, {range: {x: 0, y: 0, width: 8, height: 1048576}}, 'selected'), /8 MiB/);
});

test('R import previews populated worksheet bounds and includes raw candidate headings', () => {
  const book = workbook([cell(2, 4, ' PEFR  Before ', 'text'), cell(4, 4, 'After', 'text'),
    cell(2, 5, '3.25'), cell(4, 8, '7'), cell(0, 0, '', 'blank', {format: '0.00'})]);
  assert.deepEqual(worksheetRImport(book, 0), {
    entire: {range: 'C5:E9', rowCount: 5, columnCount: 3, suggestHeadings: true}, selected: null
  });
  const data = worksheetRImport(book, 0, {}, 'entire');
  assert.equal(data.rowCount, 5);
  assert.deepEqual(data.columns.map(c => c.title), ['Column C', 'Column D', 'Column E']);
  assert.deepEqual(data.columns[0].values, [' PEFR  Before ', '3.25', '', '', '']);
  assert.deepEqual(data.columns[1].values, ['', '', '', '', '']);
  assert.deepEqual(data.columns[2].values, ['After', '', '', '', '7']);
});

test('R import trims both ends of selected columns without borrowing unrelated worksheet bounds', () => {
  const book = workbook([cell(3, 4, '5'), cell(1, 8, '9'), cell(7, 99, '999')]);
  const selected = {columns: [3, 1]};
  assert.deepEqual(worksheetRImport(book, 0, selected).selected,
    {range: 'D, B · rows 5–9', rowCount: 5, columnCount: 2, suggestHeadings: false});
  const result = worksheetRImport(book, 0, selected, 'selected');
  assert.deepEqual(result.columns.map(c => c.title), ['Column D', 'Column B']);
  assert.deepEqual(result.columns.map(c => c.values), [['5', '', '', '', ''], ['', '', '', '', '9']]);
});

test('R import preserves explicit rectangles including leading blanks, trailing blanks and the configured worksheet header', () => {
  const book = workbook([cell(0, 0, 'First', 'text'), cell(1, 0, 'Second', 'text'),
    cell(0, 2, '5'), cell(1, 3, 'true', 'boolean')], {headerRow: true});
  const rectangle = {range: {x: 0, y: 0, width: 2, height: 8}};
  assert.deepEqual(worksheetRImport(book, 0, rectangle).selected,
    {range: 'A1:B8', rowCount: 8, columnCount: 2, suggestHeadings: true});
  const raw = worksheetRImport(book, 0, rectangle, 'selected');
  assert.equal(raw.columns[0].values[0], 'First');
  assert.deepEqual(raw.columns[0].values.slice(-4), ['', '', '', '']);
  assert.equal(raw.columns[1].kinds[3], 'boolean');
  const interior = {range: {x: 0, y: 1, width: 2, height: 6}};
  assert.equal(worksheetRImport(book, 0, interior).selected.suggestHeadings, false);
  assert.equal(worksheetRImport(book, 0, interior, 'selected').columns[0].values[0], '');
});

test('R import suggests only clear textual candidate headings, including text plus blanks', () => {
  for (const [text, kind] of [['0103', 'text'], ['1.03e+02', 'text'], ['TRUE', 'text'], ['false', 'boolean'], ['12', 'number']]) {
    const book = workbook([cell(1, 4, 'Label', 'text'), cell(2, 4, text, kind)]);
    const selected = {range: {x: 1, y: 4, width: 2, height: 2}};
    assert.equal(worksheetRImport(book, 0, selected).selected.suggestHeadings, false, text);
  }
  const textAndBlank = workbook([cell(1, 4, 'Label', 'text')]);
  assert.equal(worksheetRImport(textAndBlank, 0, {range: {x: 1, y: 4, width: 2, height: 2}}).selected.suggestHeadings, true);
  assert.equal(worksheetRImport(textAndBlank, 0, {range: {x: 1, y: 3, width: 2, height: 3}}).selected.suggestHeadings, false);
  const whitespace = workbook([cell(0, 0, '   ', 'text')]);
  assert.equal(worksheetRImport(whitespace, 0).entire.suggestHeadings, false);
});

test('R import retains configured column titles when selected numeric rows remain data', () => {
  const book = workbook([cell(0, 0, ' Before  ', 'text'), cell(1, 0, 'After', 'text'),
    cell(0, 1, '4'), cell(1, 1, '3'), cell(0, 2, '8'), cell(1, 2, '7')], {headerRow: true});
  const selection = {range: {x: 0, y: 1, width: 2, height: 2}};
  assert.equal(worksheetRImport(book, 0, selection).selected.suggestHeadings, false);
  const result = worksheetRImport(book, 0, selection, 'selected');
  assert.deepEqual(result.columns.map(column => column.title), [' Before  ', 'After']);
  assert.deepEqual(result.columns.map(column => column.values), [['4', '8'], ['3', '7']]);
});

test('R import retains row-heading gaps, its populated width and candidate heading row', () => {
  const book = workbook([cell(0, 0, 'Name', 'text'), cell(2, 0, 'Count', 'text'),
    cell(0, 1, 'Alpha', 'text'), cell(2, 1, '5'), cell(2, 3, '7')], {headerRow: true});
  const selection = {rows: [0, 1, 3, 90]};
  assert.deepEqual(worksheetRImport(book, 0, selection).selected,
    {range: 'A:C · rows 1, 2, 4', rowCount: 3, columnCount: 3, suggestHeadings: true});
  assert.deepEqual(worksheetRImport(book, 0, selection, 'selected').columns[2].values, ['Count', '5', '7']);
});

test('R import bounds include formulas with no cached value but ignore formatting-only cells', () => {
  const formulaOnly = workbook([cell(25, 11, '', 'blank', {formula: '1+2'}), cell(0, 0, '', 'blank', {style: 'Heading'})], {columns: 26});
  assert.deepEqual(worksheetRImport(formulaOnly, 0).entire,
    {range: 'Z12', rowCount: 1, columnCount: 1, suggestHeadings: false});
  assert.throws(() => worksheetRImport(formulaOnly, 0, {}, 'entire'), /Recalculate/);
  const cached = workbook([cell(25, 11, '3', 'number', {formula: '1+2'})], {columns: 26});
  assert.equal(worksheetRImport(cached, 0, {}, 'entire').columns[0].values[0], '3');
});

test('R import preview does not materialise huge sparse worksheet data', () => {
  const book = workbook([cell(0, 0, '1'), cell(16383, 1048575, '2')], {columns: 16384, rows: 1048576});
  const store = book.sheets[0].store, get = store.get.bind(store);
  let reads = 0;
  store.get = (c, r) => { assert.ok(++reads <= 16384); return get(c, r); };
  assert.deepEqual(worksheetRImport(book, 0).entire,
    {range: 'A1:XFD1048576', rowCount: 1048576, columnCount: 16384, suggestHeadings: false});
  assert.throws(() => worksheetRImport(book, 0, {}, 'entire'), /8 MiB/);
});

test('R import distinguishes absent data from a blank explicitly selected rectangle', () => {
  const empty = workbook([]);
  assert.deepEqual(worksheetRImport(empty, 0), {entire: null, selected: null});
  assert.throws(() => worksheetRImport(empty, 0, {}, 'entire'), /no data/);
  assert.throws(() => worksheetRImport(empty, 0, {}, 'selected'), /Select worksheet/);
  const selected = {range: {x: 1, y: 3, width: 2, height: 4}};
  assert.deepEqual(worksheetRImport(empty, 0, selected).selected,
    {range: 'B4:C7', rowCount: 4, columnCount: 2, suggestHeadings: false});
  assert.equal(worksheetRImport(empty, 0, selected, 'selected').columns[0].values.length, 4);
  assert.throws(() => worksheetRImport(empty, 0, {range: {x: 7, y: 0, width: 2, height: 1}}), /inside/);
  assert.throws(() => worksheetRImport(empty, 0, {columns: [0, 0]}), /inside/);
  assert.throws(() => worksheetRImport(empty, 0, {}, 'invalid'), /entire worksheet/);
});

test('R import retains error and stale-formula protection before returning chosen data', () => {
  const error = workbook([cell(0, 0, '#DIV/0!', 'error')]);
  assert.throws(() => worksheetRImport(error, 0, {}, 'entire'), /Excel errors/);
  const stale = workbook([cell(0, 0, '3', 'number', {formula: '1+2'})]);
  stale.sheets[0].store.formulasStale = true;
  assert.throws(() => worksheetRImport(stale, 0, {columns: [0]}, 'selected'), /Recalculate/);
});
