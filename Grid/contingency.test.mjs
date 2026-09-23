import test from 'node:test';
import assert from 'node:assert/strict';
import { ContingencyTable, example, validate } from './contingency.mjs';
import options from './chi-options.json' with { type: 'json' };
import { readFileSync } from 'node:fs';

test('example counts, labels and totals are preserved', () => {
  assert.equal(validate(example).counts.flat().reduce((a,b)=>a+b),66);
  const table = new ContingencyTable(); table.change(s=>Object.assign(s,structuredClone(example)));
  assert.match(table.csv(),/"Grief I","17","9","8"/);
});
test('pasting expands the table; undo and redo restore dimensions and labels', () => {
  const table = new ContingencyTable(); table.paste(0,0,'17\t9\t8\r\n6\t5\t1\r\n3\t5\t4\r\n1\t2\t5\r\n');
  assert.deepEqual(validate(table.state).counts,validate(example).counts);
  table.resize(2,2);table.undo();assert.equal(table.state.counts.length,4);table.undo();assert.deepEqual(table.state.counts,[['',''],['','']]);
  table.redo();assert.equal(table.state.counts[3][2],'5');
});
test('an oversized paste is atomic and validation rejects missing and invalid counts', () => {
  const table = new ContingencyTable(), original=structuredClone(table.state);
  assert.throws(()=>table.paste(199,199,'1\t2'),/2,500/);assert.deepEqual(table.state,original);
  for(const value of ['', '-1', '1.2', 'abc', 'Infinity']) {
    assert.throws(()=>validate({...example, counts:[['1',value],['2','3']]}),/whole count/);
  }
  assert.throws(()=>validate({...example,counts:[['0','0'],['1','3']]}),/positive total/);
  assert.deepEqual(validate({...example,counts:[['0','2'],['1','0']]}).counts,[[0,2],[1,0]]);
});
test('checkbox names, labels and defaults match the original operation definition',()=>{
  const xml = readFileSync(new URL('../FullEngine/Upstream/StatsDirectUI/Assets/Operations/ExactChiRbyCScreen.xml',import.meta.url),'utf8');
  const expected = [...xml.matchAll(/<boolean>([\s\S]*?)<\/boolean>/g)].map(([,v])=>({name:v.match(/<name>(.*?)<\/name>/)[1],prompt:v.match(/<prompt>(.*?)<\/prompt>/)[1],default:v.match(/<default-value>(.*?)<\/default-value>/)[1]==='true'}));
  assert.deepEqual(options,expected);
});
