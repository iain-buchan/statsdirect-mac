import {test} from 'node:test';
import assert from 'node:assert/strict';
import {GridStore} from './store.mjs';
import {decodeSnapshot, encodeSnapshot} from './snapshot.mjs';

// The loader marks a formula whose saved result is empty text with the snapshot extra {"savedEmpty":true}, one JSON
// string per cell (contract I1). setLoadedColumns knows that exact text and gives every such cell one shared, frozen
// object, instead of parsing a new object for each: a column of them can run to the last row of the sheet.
const loaded = extras => {
  const n = extras.length, store = new GridStore();
  const snapshot = encodeSnapshot([{name: 'S', columns: [{col: 0, rows: Array.from({length: n}, (_, i) => i), kinds: new Uint8Array(n),
    nums: new Float64Array(n).fill(NaN), texts: new Map(), formulas: new Map(extras.map((_, i) => [i, `IF(B${i + 1}="","",B${i + 1})`])),
    extras: new Map(extras.flatMap((extra, i) => extra === null ? [] : [[i, extra]]))}]}]);
  store.setLoadedColumns(decodeSnapshot(snapshot).sheets[0].columns);
  return store;
};

test('every saved empty formula result shares one frozen {savedEmpty: true}, and reads as before', () => {
  const store = loaded(['{"savedEmpty":true}', '{"savedEmpty":true}', null, '{"rMissing":true}', '{"savedEmpty": true}', '{"savedEmpty":true,"x":1}', 'not JSON']);
  const extra = r => store.cols[0].extra.get(r);
  assert.equal(extra(0), extra(1));
  assert.ok(Object.isFrozen(extra(0)));
  assert.deepEqual(extra(0), {savedEmpty: true});
  // Other text is parsed as before, each into its own object: other spacing, other fields, other markers. Text that is
  // not JSON is ignored, as before.
  assert.deepEqual([extra(2), extra(3), extra(4), extra(5), extra(6)], [undefined, {rMissing: true}, {savedEmpty: true}, {savedEmpty: true, x: 1}, undefined]);
  assert.ok(extra(4) !== extra(0) && !Object.isFrozen(extra(4)));
  // What the cell means is unchanged: blank, with its formula, its saved result usable, and loaded() a copy of its own.
  assert.deepEqual([store.get(0, 0), store.formula(0, 0), store.formulaUnavailable(0, 0), store.formulaUnavailable(0, 2)], ['', 'IF(B1="","",B1)', false, true]);
  const copy = store.loaded(0, 1);
  assert.deepEqual(copy, {col: 0, row: 1, text: '', kind: 'blank', formula: 'IF(B2="","",B2)', savedEmpty: true});
  copy.savedEmpty = false;
  assert.equal(store.loaded(0, 0).savedEmpty, true);
  store.formulasStale = true;
  assert.equal(store.formulaUnavailable(0, 0), true);
});

test('a column of saved empty results down to the last row keeps one object for them all', () => {
  const store = loaded(Array(1048576).fill('{"savedEmpty":true}')), column = store.cols[0];
  assert.deepEqual([store.rows, column.extra.size, column.formula.size], [1048576, 1048576, 1048576]);
  const first = column.extra.get(0);
  for (const [, extra] of column.extra) assert.ok(extra === first);
  assert.equal(store.formulaUnavailable(0, 1048575), false);
});
