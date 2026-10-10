import test from 'node:test';
import assert from 'node:assert/strict';
import {columnSpans} from './legacy-layout.mjs';
test('RTF physical cell boundaries restore spanning headings without guessing from text',()=>{
  const grid=[900,1800,2700,3600,4500,5700];
  assert.deepEqual(columnSpans([900,5700],grid),[1,5]);
  assert.deepEqual(columnSpans([900,2700,5700],grid),[1,2,3]);
  assert.deepEqual(columnSpans(grid,grid),[1,1,1,1,1,1]);
  assert.deepEqual(columnSpans([905,5695],grid),[1,5]);
  assert.equal(columnSpans([900,2900,5700],grid),null);
  assert.equal(columnSpans([900,4500],grid),null);
  assert.equal(columnSpans([1800,900,5700],grid),null);
});
