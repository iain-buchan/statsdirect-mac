import { test } from 'node:test';
import assert from 'node:assert/strict';
import { GridStore, parseDelimited } from './store.mjs';
test('rectangular paste grows the sheet and undo/redo is atomic', () => {
  const s = new GridStore();
  s.paste(5, 99, '1\t2\n3\t4');
  assert.equal(s.rows, 101);
  assert.equal(s.columns.length, 7);
  assert.equal(s.get(6, 100), '4');
  s.undo();
  assert.equal(s.rows, 100);
  assert.equal(s.get(5, 99), '');
  s.redo();
  assert.equal(s.get(6, 100), '4');
});
test('quoted spreadsheet cells, zero, missing and invalid numbers', () => {
  assert.deepEqual(parseDelimited('"a\tb"\t"c""d"\r\n0\t\r\n'), [['a\tb', 'c"d'], ['0', '']]);
  const s = new GridStore();
  s.paste(0, 0, '0\t1\n2\t4\n\t5');
  assert.deepEqual(s.paired(0, 1).before, [0, 2, null]);
  s.paste(0, 1, 'oops');
  assert.throws(() => s.paired(0, 1), /Row 2/);
});
test('CSV preserves user text and serializes only populated rows', () => {
  const s = new GridStore();
  s.paste(0, 0, '"a,b"\t"a""b"');
  assert.ok(s.csv().includes('"a,b","a""b"'));
  assert.equal(s.csv().split('\r\n').length, 3);
});
test('range analysis selects only requested pairs', () => {
  const s = new GridStore();
  s.paste(2, 0, '1\t2\n3\t4\n5\t8');
  assert.deepEqual(s.paired(2, 3, 1, 3).before, [3, 5]);
  assert.throws(() => s.paired(2, 2), /different/);
});
