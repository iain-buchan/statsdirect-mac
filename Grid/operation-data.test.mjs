import {test} from 'node:test';
import assert from 'node:assert/strict';
import {worksheetInput,enteredInput,pasteMatrix} from './operation-data.mjs';
const source={name:'Book / Sheet',firstRow:2,rows:4,columns:['A','B'],cells:[{col:0,row:1,text:'12'},{col:0,row:3,text:'14'},{col:1,row:1,text:'20'},{col:1,row:2,text:'21'}]};
test('worksheet selection preserves requested column order, row alignment and missing tail',()=>{
 const value=worksheetInput(source,[1,0],2,4);
 assert.deepEqual(value.columns.map(c=>c.title),['B','A']);
 assert.deepEqual(value.columns[0].values,['20','21','*']);
 assert.deepEqual(value.columns[1].values,['12','','14']);
});
test('formula safety checks apply only to selected cells',()=>{
 const data={...source,formulasStale:true,cells:[...source.cells,{col:1,row:3,text:'23',formula:'SUM(B2:B3)'}]};
 assert.throws(()=>worksheetInput(data,[1],2,4),/Recalculate/);
 assert.doesNotThrow(()=>worksheetInput(data,[0],2,4));
 assert.throws(()=>worksheetInput({...data,formulasStale:false,cells:[{col:0,row:1,text:'#VALUE!',kind:'error'}]},[0],2,4),/Excel errors/);
});
test('entered tables trim blank tail without dropping explicit missing observations',()=>{
 assert.deepEqual(enteredInput([['1','2'],['*','3'],['','']],['X','Y']).columns[0].values,['1','*']);
 assert.equal(enteredInput([['1','2'],['','']],['X','Y'],true).columns[0].values.length,2);
});
test('paste expands without truncating and rejects fixed-table overflow',()=>{
 assert.deepEqual(pasteMatrix([['']], '1\t2\r\n3\t4\r\n'),[['1','2'],['3','4']]);
 assert.throws(()=>pasteMatrix([['',''],['','']],'1\n2\n3',0,0,true,2),/larger/);
 assert.throws(()=>worksheetInput(source,[0,0],2,4),/once/);
 assert.throws(()=>worksheetInput(source,[0],0,4),/valid/);
});
