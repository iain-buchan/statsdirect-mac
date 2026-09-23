import { test } from 'node:test';
import assert from 'node:assert/strict';
import { WorkbookStore } from './workbook.mjs';
const fixture = () => ({
  id: 'workbook-fixture',
  name: 'sample.xlsx',
  formulaCount: 1,
  sheets: [{
    name: 'Observations',
    rows: 4,
    columns: 3,
    cells: [{
      col: 0,
      row: 0,
      text: 'Before',
      kind: 'text',
      formula: ''
    }, {
      col: 1,
      row: 0,
      text: 'After',
      kind: 'text',
      formula: ''
    }, {
      col: 0,
      row: 1,
      text: '12',
      kind: 'number',
      formula: ''
    }, {
      col: 1,
      row: 1,
      text: '8',
      kind: 'number',
      formula: ''
    }, {
      col: 0,
      row: 2,
      text: '15',
      kind: 'number',
      formula: ''
    }, {
      col: 1,
      row: 2,
      text: '9',
      kind: 'number',
      formula: ''
    }, {
      col: 2,
      row: 1,
      text: '0012',
      kind: 'text',
      formula: ''
    }, {
      col: 2,
      row: 2,
      text: '27',
      kind: 'number',
      formula: 'SUM(A2:A3)'
    }]
  }, {
    name: 'Other',
    hidden: true,
    rows: 1,
    columns: 1,
    cells: [{
      col: 0,
      row: 0,
      text: 'TRUE',
      kind: 'boolean',
      formula: ''
    }]
  }]
});
test('all sheets are retained and Excel row-one headers are not observations', () => {
  const book = new WorkbookStore();
  book.load(fixture());
  const store = book.sheets[0].store;
  assert.equal(book.sheets.length, 2);
  assert.equal(book.sheets[1].hidden, true);
  assert.deepEqual(store.paired(0, 1).before, [12, 15]);
  assert.deepEqual(store.paired(0, 1, 0, 3).labels, ['Before', 'After']);
  assert.equal(store.csv().split('\r\n')[0], 'Before,After,');
  assert.deepEqual(book.export().sheets.map(s => s.cells), [[], []]);
});
test('export contains only edits, preserves text identifiers, and undo removes the patch', () => {
  const book = new WorkbookStore();
  book.load(fixture());
  const store = book.sheets[0].store;
  store.apply([[0, 1, '13'], [2, 1, '0013'], [1, 2, '']]);
  const edits = book.export().sheets[0].cells;
  assert.equal(edits.find(c => c.col === 0).kind, 'number');
  assert.equal(edits.find(c => c.col === 2).kind, 'text');
  assert.equal(edits.find(c => c.col === 1).kind, 'blank');
  store.undo();
  assert.deepEqual(book.export().sheets[0].cells, []);
});
test('formula edits are atomic and analysis refuses stale or missing cached results', () => {
  const book = new WorkbookStore();
  book.load(fixture());
  const store = book.sheets[0].store;
  assert.throws(() => store.apply([[0, 1, '99'], [2, 2, '0']]), /read-only/);
  assert.equal(store.get(0, 1), '12');
  book.changed();
  assert.throws(() => store.paired(0, 2), /out of date/);
  store.formulasStale = false;
  store.cells.delete('2,2');
  assert.throws(() => store.paired(0, 2), /no saved result/);
});
test('a new worksheet exports headers and numbers to actual Excel coordinates', () => {
  const book = new WorkbookStore({
    before: [12, 15],
    after: [8, 9]
  });
  const cells = book.export().sheets[0].cells;
  assert.deepEqual(cells.find(c => c.col === 0 && c.row === 0), {
    col: 0,
    row: 0,
    text: 'PEFR Before',
    kind: 'text'
  });
  assert.deepEqual(cells.find(c => c.col === 0 && c.row === 1), {
    col: 0,
    row: 1,
    text: '12',
    kind: 'number'
  });
});

test('generated analysis tables without a backing Excel file export all cells',()=>{
  const data=fixture(); delete data.id; data.formulaCount=0;
  const workbook=new WorkbookStore();workbook.load(data);
  const exported=workbook.export();
  assert.equal(exported.sheets[0].cells.length,data.sheets[0].cells.length);
  assert.equal(exported.sheets[0].cells.find(c=>c.col===0&&c.row===1).text,'12');
});
