import { test } from 'node:test';
import assert from 'node:assert/strict';
import { encodeSnapshot, decodeSnapshot } from './snapshot.mjs';
import { GridStore, MAX_ROWS, MAX_COLS } from './store.mjs';
import { WorkbookStore } from './workbook.mjs';
import { analysisMetadata, columnValues, snapshotColumns } from './analysis-source.mjs';
import { worksheetInput, worksheetInputFrom, worksheetRows, screenSelection } from './operation-data.mjs';

const column = (col, rows, kinds, nums, texts = [], formulas = []) => ({col, rows, kinds, nums, texts: new Map(texts), formulas: new Map(formulas)});

test('snapshot round trip keeps every kind, text and formula, and tolerates odd buffer offsets', () => {
  const sheets = [{name: 'Données ✓', columns: [
    column(0, [0, 1, 5, MAX_ROWS - 1], [2, 1, 3, 6], [NaN, 1.5, NaN, NaN], [[0, 'id'], [2, '2024-02-29 12:34:56'], [3, '#DIV/0!']]),
    column(MAX_COLS - 1, [2, 3], [0, 5], [NaN, NaN], [[1, 'TRUE']], [[0, 'SUM(A1:A2)']]),
    column(7, [], [], [])
  ]}, {name: '', columns: []}];
  const bytes = encodeSnapshot(sheets);
  assert.equal(bytes.length % 4, 0);
  for (const offset of [0, 1, 3]) {
    const padded = new Uint8Array(bytes.length + offset); padded.set(bytes, offset);
    const decoded = decodeSnapshot(new Uint8Array(padded.buffer, offset, bytes.length));
    assert.equal(decoded.sheets.length, 2);
    assert.equal(decoded.sheets[0].name, 'Données ✓');
    const [a, b, c] = decoded.sheets[0].columns;
    assert.deepEqual([a.col, Array.from(a.rows), Array.from(a.kinds)], [0, [0, 1, 5, MAX_ROWS - 1], [2, 1, 3, 6]]);
    assert.equal(a.nums[1], 1.5);
    assert.deepEqual([...a.texts], [[0, 'id'], [2, '2024-02-29 12:34:56'], [3, '#DIV/0!']]);
    assert.deepEqual([b.col, [...b.formulas], [...b.texts]], [MAX_COLS - 1, [[0, 'SUM(A1:A2)']], [[1, 'TRUE']]]);
    assert.equal(c.rows.length, 0);
    assert.equal(decoded.sheets[1].columns.length, 0);
  }
  // A byte-order mark at the start of a cell's text is part of the text.
  const bom = decodeSnapshot(encodeSnapshot([{name: '\uFEFFx', columns: [column(0, [0], [2], [NaN], [[0, '\uFEFFid']])]}])).sheets[0];
  assert.deepEqual([bom.name, bom.columns[0].texts.get(0)], ['\uFEFFx', '\uFEFFid']);
  assert.throws(() => decodeSnapshot(bytes.subarray(0, 40)), /truncated|format/);
  assert.throws(() => decodeSnapshot(new Uint8Array(16)), /format/);
});

test('a store loads typed columns and exports the same cells it would list as JSON', () => {
  const book = new WorkbookStore();
  const columns = [
    column(0, [0, 1, 2, 3], [2, 1, 1, 0], [NaN, 12, 15, NaN], [[0, 'Before']], [[3, 'SUM(A2:A3)']]),
    column(2, [1], [2], [NaN], [[0, '0012']])
  ];
  book.load({id: 'x', name: 'typed.xlsx', formulaCount: 1, sheets: [{name: 'S', rows: 4, columns: 3, columnar: columns}]});
  const store = book.sheets[0].store;
  assert.equal(store.headerRow, true);
  assert.deepEqual([store.get(0, 1), store.kind(0, 1), store.get(2, 1), store.kind(2, 1), store.get(0, 3), store.formula(0, 3)], ['12', 'number', '0012', 'text', '', 'SUM(A2:A3)']);
  assert.equal(store.count(), 4);
  assert.deepEqual(store.loaded(0, 3), {col: 0, row: 3, text: '', kind: 'blank', formula: 'SUM(A2:A3)'});
  assert.deepEqual(book.export().sheets[0].cells, []);
  store.apply([[0, 1, '13'], [2, 1, ''], [1, 0, 'After']]);
  const json = book.export().sheets[0].cells, typed = book.exportColumns().sheets[0];
  assert.deepEqual(json, [{col: 0, row: 1, text: '13', kind: 'number'}, {col: 2, row: 1, text: '', kind: 'blank'}, {col: 1, row: 0, text: 'After', kind: 'text'}]);
  const back = decodeSnapshot(encodeSnapshot([typed])).sheets[0].columns;
  assert.deepEqual(back.map(c => [c.col, Array.from(c.rows), Array.from(c.kinds), Array.from(c.nums).map(n => Number.isNaN(n) ? null : n), [...c.texts]]),
    [[0, [1], [1], [13], []], [1, [0], [2], [null], [[0, 'After']]], [2, [1], [0], [null], []]]);
  assert.throws(() => store.setLoadedColumns([column(0, [MAX_ROWS], [1], [1])]), /outside/);
});

test('analysis forms receive metadata and read columns on demand', () => {
  const book = new WorkbookStore();
  book.load({id: 'x', name: 'book.xlsx', formulaCount: 1, sheets: [{name: 'S', rows: 5, columns: 3, cells: [
    {col: 0, row: 0, text: 'Before', kind: 'text'}, {col: 1, row: 0, text: 'After', kind: 'text'},
    {col: 0, row: 1, text: '12', kind: 'number'}, {col: 1, row: 1, text: '8', kind: 'number'},
    {col: 0, row: 2, text: '15', kind: 'number'}, {col: 1, row: 2, text: '9', kind: 'number'},
    {col: 1, row: 4, text: '', kind: 'blank', formula: 'SUM(B2:B3)'}
  ]}]});
  const meta = analysisMetadata(book, 0, {columns: [1, 0]});
  assert.equal(meta.lazy, true);
  assert.deepEqual([meta.sheet, meta.sheetName], [0, 'S']);
  assert.deepEqual([meta.firstRow, meta.rows, meta.columnEnds, meta.width, meta.selection], [2, 3, [3, 5, 0], 2, [1, 0]]);
  assert.equal(JSON.stringify(meta).includes('"12"'), false);
  assert.deepEqual(worksheetRows(meta, [0, 1]), {first: 2, last: 5});
  const pending = worksheetInput(meta, [1, 0], 2, 3);
  assert.deepEqual(pending.request, {sheet: 0, sheetName: 'S', columns: [1, 0], first: 2, last: 3});
  const data = columnValues(book, 0, pending.request);
  assert.deepEqual(data.columns, [{title: 'After', values: ['8', '9']}, {title: 'Before', values: ['12', '15']}]);
  assert.deepEqual(worksheetInputFrom(pending, data).columns[1].values, ['12', '15']);
  assert.equal(worksheetInputFrom(pending, data).range.lastRow, 3);
  assert.throws(() => worksheetInputFrom(pending, columnValues(book, 0, {columns: [1], first: 2, last: 5})), /Recalculate/);
  assert.throws(() => columnValues(book, 0, {columns: [3], first: 2, last: 3}), /no longer available/);
  // A request names the sheet its metadata came from, whichever sheet the grid shows now.
  assert.deepEqual(worksheetInput(meta, [0], 2, 3).request, {sheet: 0, sheetName: 'S', columns: [0], first: 2, last: 3});
  book.sheets.push({name: 'T', hidden: false, store: new GridStore()});
  assert.equal(columnValues(book, 1, {sheet: 0, sheetName: 'S', columns: [0], first: 2, last: 3}).columns[0].values[0], '12');
  assert.throws(() => columnValues(book, 1, {sheet: 0, sheetName: 'Renamed', columns: [0], first: 2, last: 3}), /no longer available/);
  assert.throws(() => snapshotColumns(book, 0, {sheet: 5, columns: [0]}), /no longer available/);
  book.sheets.pop();
  assert.throws(() => columnValues(book, 0, {columns: [0], first: 0, last: 3}), /valid first and last/);
  // A highlighted rectangle travels with the metadata for screen forms.
  const screen = analysisMetadata(book, 0, {columns: [], range: {x: 0, y: 1, width: 2, height: 2}});
  assert.deepEqual(screen.screen, [['12', '8'], ['15', '9']]);
  assert.deepEqual(screenSelection(screen, {screen: true, minColumns: 2, maxColumns: 9}), [['12', '8'], ['15', '9']]);
  book.sheets[0].store.setLoaded([{col: 0, row: 1, text: '#VALUE!', kind: 'error'}]);
  assert.match(analysisMetadata(book, 0, {columns: [], range: {x: 0, y: 1, width: 2, height: 2}}).screenError, /Excel errors/);
  // Derived worksheets copy the source columns through a snapshot, titles first when there is no header row.
  const records = snapshotColumns(book, 0, {columns: [0, 1], rowOffset: 1, header: true});
  assert.deepEqual(records.map(c => [c.col, Array.from(c.rows), [...c.texts]]), [[0, [0, 1, 2, 3], [[0, 'Before'], [1, 'Before'], [2, '#VALUE!']]], [1, [0, 1, 2, 3], [[0, 'After'], [1, 'After']]]]);
  assert.equal(records[0].nums[3], 15);
});
