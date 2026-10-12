import test from 'node:test';
import assert from 'node:assert/strict';
import {GridStore, MAX_ROWS, MAX_COLS} from './store.mjs';
import {findCell} from './find.mjs';
test('worksheet Find follows rows, wraps in both directions, includes numeric values and ignores empty space',()=>{
  const store=new GridStore();
  store.apply([[4,0,'Alpha'],[1,2,'alpha beta'],[3,2,'ALPHA'],[MAX_COLS-1,MAX_ROWS-1,'42']], MAX_ROWS, MAX_COLS);
  assert.deepEqual(findCell(store,'alpha'),[4,0]);
  assert.deepEqual(findCell(store,'alpha',[4,0]),[1,2]);
  assert.deepEqual(findCell(store,'alpha',[3,2]),[4,0]);
  assert.deepEqual(findCell(store,'alpha',[4,0],true),[3,2]);
  assert.deepEqual(findCell(store,'alpha',[3,2],true),[1,2]);
  assert.deepEqual(findCell(store,'42'),[MAX_COLS-1,MAX_ROWS-1]);
  assert.equal(findCell(store,'missing'),null);
  assert.equal(findCell(store,''),null);
});
