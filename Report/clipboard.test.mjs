import test from 'node:test';
import assert from 'node:assert/strict';
import {numericValue} from './clipboard.mjs';
test('Excel values preserve decimals, signs, exponents and percentages',()=>{
  for(const [input,expected] of [['12',12],['-2.5',-2.5],['−2.5',-2.5],['1.2e-7',1.2e-7],['.05',.05],['95%',.95],['0',0]])assert.equal(numericValue(input),expected,input);
});
test('Identifiers, precision beyond Excel and nonnumeric labels stay text',()=>{
  for(const input of ['0123','1234567890123456','Observation 1','1/2/2026','=1+1','<0.001','1,234','Infinity','NaN','','1e999'])assert.equal(numericValue(input),null,input);
});
