import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GridStore, MAX_ROWS, MAX_COLS, scanDelimited, parseDelimited } from './store.mjs';
import { WorkbookStore, cellKind } from './workbook.mjs';
import { csvWorkbook } from './csv.mjs';

const FULL = process.env.STATSDIRECT_SCALE_FULL === '1';

test('the worksheet addresses every Excel cell and nothing beyond', () => {
  const s = new GridStore();
  assert.ok(s.paste(MAX_COLS - 1, MAX_ROWS - 1, '42'));
  assert.equal(s.get(MAX_COLS - 1, MAX_ROWS - 1), '42');
  assert.equal(s.rows, MAX_ROWS);
  assert.equal(s.columns.length, MAX_COLS);
  assert.equal(s.usedRows(), MAX_ROWS);
  assert.throws(() => s.paste(MAX_COLS - 1, MAX_ROWS - 1, '1\t2'), /Excel worksheet dimensions/);
  assert.throws(() => s.paste(0, MAX_ROWS - 1, '1\n2'), /Excel worksheet dimensions/);
  assert.throws(() => s.apply([[0, MAX_ROWS, '1']]), /outside/);
  assert.ok(s.undo());
  assert.equal(s.get(MAX_COLS - 1, MAX_ROWS - 1), '');
  assert.equal(s.count(), 0);
});

test('numbers are stored as doubles, text exactly as typed, kinds follow the grid rules', () => {
  const s = new GridStore();
  s.paste(0, 0, '12\t1.50\t0012\t1e21\t-0.5\thello\t\t3.');
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 7].map(c => s.get(c, 0)), ['12', '1.50', '0012', '1e21', '-0.5', 'hello', '', '3.']);
  assert.deepEqual([0, 1, 2, 3, 4, 5, 6, 7].map(c => s.kind(c, 0)), ['number', 'number', 'text', 'number', 'number', 'text', 'blank', 'number']);
  assert.equal(s.count(), 7);
  assert.deepEqual(s.usedColumns(), [0, 1, 2, 3, 4, 5, 7]);
  // Editing a cell loaded as text keeps it text, as before.
  const book = new WorkbookStore();
  book.load({name: 'ids.xlsx', id: 'x', formulaCount: 0, sheets: [{name: 'S', rows: 2, columns: 1, cells: [{col: 0, row: 0, text: '0012', kind: 'text', formula: ''}]}]});
  const store = book.sheets[0].store;
  store.apply([[0, 0, '13']]);
  assert.equal(cellKind(store, 0, 0), 'text');
  assert.deepEqual(store.loaded(0, 0), {col: 0, row: 0, text: '0012', kind: 'text', formula: ''});
  assert.deepEqual(book.export().sheets[0].cells, [{col: 0, row: 0, text: '13', kind: 'text'}]);
  store.undo();
  assert.deepEqual(book.export().sheets[0].cells, []);
});

test('streaming scan matches the row parser on awkward input', () => {
  for (const text of ['', 'a', 'a\n', '\n', 'a\tb\n\tc', '"x\ty"\t"q""r"\r\n0\t\r\n', '1\r2\r', '\t\t']) {
    const rows = [];
    scanDelimited(text, '\t', (c, r, v) => { (rows[r] ??= [])[c] = v; });
    assert.deepEqual(rows.map(r => Array.from(r, v => v ?? '')), parseDelimited(text), JSON.stringify(text));
  }
});

test(`a full Excel column height paste (${FULL ? 16 : 4} columns) stays within time and memory`, () => {
  const cols = FULL ? 16 : 4, rows = MAX_ROWS;
  const lines = new Array(rows);
  for (let r = 0; r < rows; r++) lines[r] = `${r}\t${(r % 1000) / 8}\tgroup ${r % 7}\t${r % 2 ? '-1' : '2.5'}${cols > 4 ? '\t1\t2\t3\t4\t5\t6\t7\t8\t9\t10\t11\t12' : ''}`;
  const text = lines.join('\n');
  lines.length = 0;
  const s = new GridStore();
  const before = process.memoryUsage();
  const t = performance.now();
  assert.ok(s.paste(0, 0, text));
  const elapsed = performance.now() - t;
  const after = process.memoryUsage();
  assert.equal(s.rows, rows);
  assert.equal(s.count(), rows * cols);
  assert.equal(s.get(0, rows - 1), String(rows - 1));
  assert.equal(s.get(2, rows - 1), `group ${(rows - 1) % 7}`);
  assert.equal(s.get(3, 1), '-1');
  assert.equal(s.kind(1, 5), 'number');
  assert.equal(s.usedRows(), rows);
  // Typed storage plus the undo snapshot of the paste: well under 100 bytes per cell all in.
  const bytesPerCell = (after.arrayBuffers - before.arrayBuffers + after.heapUsed - before.heapUsed) / (rows * cols);
  assert.ok(bytesPerCell < 100, `memory ${bytesPerCell.toFixed(1)} bytes per cell`);
  assert.ok(elapsed < 60000, `paste took ${elapsed.toFixed(0)} ms`);
  const t2 = performance.now();
  assert.ok(s.undo());
  assert.equal(s.count(), 0);
  assert.ok(s.redo());
  assert.equal(s.count(), rows * cols);
  assert.ok(performance.now() - t2 < 60000);
  // Column text store holds only the non-numeric column.
  assert.equal(s.cols[2].text.size, rows);
  assert.equal(s.cols[0].text.size, 0);
  console.log(`scale: ${rows}x${cols} paste ${elapsed.toFixed(0)} ms, ${bytesPerCell.toFixed(1)} bytes/cell`);
});

test('CSV import at scale loads into typed columns', () => {
  const rows = 200000;
  const lines = ['id,value,label'];
  for (let r = 0; r < rows; r++) lines.push(`${r},${r / 4},L${r % 3}`);
  const book = new WorkbookStore();
  const t = performance.now();
  book.load(csvWorkbook(lines.join('\n'), 'big.csv'));
  const store = book.sheets[0].store;
  assert.ok(performance.now() - t < 60000);
  assert.equal(store.headerRow, true);
  assert.equal(store.count(), (rows + 1) * 3);
  assert.equal(store.get(1, rows), String((rows - 1) / 4));
  assert.equal(store.kind(1, rows), 'number');
  assert.equal(store.kind(2, rows), 'text');
  assert.equal(store.cols[1].text.size, 1); // the heading
  assert.equal(store.paired(0, 1, 1, 11).before.length, 10);
});
