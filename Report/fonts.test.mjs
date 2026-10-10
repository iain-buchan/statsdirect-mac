import test from 'node:test';
import assert from 'node:assert/strict';
import {chartFontFamily} from './fonts.mjs';

test('Windows chart faces retain the requested font and fall back within its family',()=>{
  assert.equal(chartFontFamily('CALIBRI'),'Calibri, Carlito, Arial, Helvetica, sans-serif');
  assert.equal(chartFontFamily('"Calibri"'),'Calibri, Carlito, Arial, Helvetica, sans-serif');
  assert.match(chartFontFamily('Times New Roman'),/^Times New Roman,.* serif$/);
  assert.match(chartFontFamily('Consolas'),/^Consolas,.* monospace$/);
  for(const original of ['Symbol','My Custom Font','Calibri, sans-serif'])assert.equal(chartFontFamily(original),original);
});
