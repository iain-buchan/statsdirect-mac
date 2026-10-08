import {test} from 'node:test';
import assert from 'node:assert/strict';
import {worksheetInput,worksheetRows,worksheetSelection} from './operation-data.mjs';
const source={name:'Book / Sheet',firstRow:2,rows:4,columns:['A','B'],cells:[{col:0,row:1,text:'12'},{col:0,row:3,text:'14'},{col:1,row:1,text:'20'},{col:1,row:2,text:'21'}]};
test('worksheet selection preserves requested column order, row alignment and missing tail',()=>{
 const value=worksheetInput(source,[1,0],2,4);
 assert.deepEqual(value.columns.map(c=>c.title),['B','A']);
 assert.deepEqual(value.columns[0].values,['20','21','']);
 assert.equal(value.preserveRows,true);
 assert.deepEqual(value.columns[1].values,['12','','14']);
});
test('automatic range follows selected columns instead of unrelated worksheet data',()=>{
 const data={...source,rows:1000,cells:[...source.cells,{col:9,row:999,text:'unrelated'}]};
 assert.deepEqual(worksheetRows(data,[0,1]),{first:2,last:4});
 assert.deepEqual(worksheetRows(data,[1]),{first:2,last:3});
 const range=worksheetRows(data,[0,1]);
 assert.equal(worksheetInput(data,[0,1],range.first,range.last).columns[0].values.length,3);
 // A subsequent matched variable keeps the earlier acquisition's length.
 assert.deepEqual(worksheetRows(data,[1],3),{first:2,last:4});
});
test('cell rectangles preserve their exact row and column selection',()=>{
 const selected=worksheetSelection([],{x:1,y:4,width:2,height:5});
 assert.deepEqual(selected,{selection:[1,2],range:{first:5,last:9}});
 assert.deepEqual(worksheetRows({...source,rows:100,...selected},[1,2]),{first:5,last:9});
 assert.deepEqual(worksheetSelection([],{x:1,y:4,width:1,height:1}),{selection:[1],range:{first:5,last:5}});
 assert.deepEqual(worksheetSelection([1,0],{x:1,y:4,width:2,height:5}),{selection:[1,0]});
});
test('internal blank rows and explicit missing final observations survive selection',()=>{
 const data={...source,rows:99,cells:[{col:0,row:1,text:'12'},{col:0,row:3,text:'*'},{col:1,row:1,text:'20'}]};
 assert.deepEqual(worksheetRows(data,[0,1]),{first:2,last:4});
 assert.deepEqual(worksheetInput(data,[0,1],2,4).columns.map(c=>c.values),[['12','','*'],['20','','']]);
});
test('formula safety checks apply only to selected cells',()=>{
 const data={...source,formulasStale:true,cells:[...source.cells,{col:1,row:3,text:'23',formula:'SUM(B2:B3)'}]};
 assert.throws(()=>worksheetInput(data,[1],2,4),/Recalculate/);
 assert.doesNotThrow(()=>worksheetInput(data,[0],2,4));
 assert.throws(()=>worksheetInput({...data,formulasStale:false,cells:[{col:0,row:1,text:'#VALUE!',kind:'error'}]},[0],2,4),/Excel errors/);
});
test('entered tables trim blank tail without dropping explicit missing observations',()=>{
 const table=new EntryTable({minColumns:2});table.paste('1\t2\n*\t3\n\t');
 assert.deepEqual(table.input().columns[0].values,['1','*']);
 const fixed=new EntryTable({minColumns:2,rows:2,fixedRows:true});fixed.paste('1\t2');
 assert.equal(fixed.input().columns[0].values.length,2);
});
test('paste expands without truncating and rejects fixed-table overflow',()=>{
 const table=new EntryTable({minColumns:1,rows:1});table.paste('1\t2\r\n3\t4\r\n');
 assert.deepEqual(table.input().columns.map(c=>c.values),[['1','3'],['2','4']]);
 assert.throws(()=>new EntryTable({minColumns:2,maxColumns:2,rows:2,fixedRows:true}).paste('1\n2\n3'),/larger/);
 assert.throws(()=>worksheetInput(source,[0,0],2,4),/once/);
 assert.throws(()=>worksheetInput(source,[0],0,4),/valid/);
});

const screen={screen:true,rows:2,fixedRows:true,minColumns:2,maxColumns:2,labels:['Present','Absent']};
const block={name:'Book / Counts',firstRow:1,rows:30,columns:['A','B','C','D'],selection:[2,3],range:{first:5,last:6},cells:[{col:0,row:0,text:'999'},{col:2,row:4,text:'12'},{col:3,row:4,text:'3'},{col:2,row:5,text:'0'},{col:3,row:5,text:'17'}]};
import {screenSelection} from './operation-data.mjs';
import {EntryTable} from './entry-table.mjs';
test('screen table fills exactly the highlighted rectangle in worksheet orientation',()=>{
 assert.deepEqual(screenSelection(block,screen),[['12','3'],['0','17']]);
 assert.deepEqual(new EntryTable(screen,block).store.columns,['Present','Absent']);
 assert.deepEqual(screenSelection({...block,cells:block.cells.slice(0,-1)},screen),[['12','3'],['0','']]);
 assert.equal(screenSelection({...block,range:undefined},screen),null);
 assert.equal(screenSelection(block,{...screen,screen:false}),null);
});
test('screen selection never crops an oversized block or bypasses formula safety',()=>{
 assert.throws(()=>screenSelection({...block,range:{first:5,last:7}},screen),/not been copied/);
 assert.throws(()=>screenSelection({...block,selection:[1,2,3]},screen),/not been copied/);
 assert.match(new EntryTable(screen,{...block,selection:[1]}).error,/not been copied/);
 assert.throws(()=>screenSelection({...block,formulasStale:true,cells:[...block.cells,{col:2,row:4,text:'12',formula:'SUM(A1:B1)'}]},screen),/Recalculate/);
 assert.throws(()=>screenSelection({...block,cells:[{col:2,row:4,text:'#VALUE!',kind:'error'}]},screen),/Excel errors/);
});
test('edited/rejected answers take precedence over the original worksheet snapshot',()=>{
 const initial={columns:[{title:'Present',values:['9','7']},{title:'Absent',values:['4','20']}]};
 assert.deepEqual(new EntryTable(screen,block,initial).input().columns,initial.columns);
});

import {worksheetInputFrom} from './operation-data.mjs';
test('long data: the form sends the data column, the identifiers and the block, and the application receives them by role', () => {
  const source = {lazy: true, sheet: 0, sheetName: 'S', name: 'book / S', firstRow: 2, rows: 13, columns: ['score', 'treatment', 'block', 'other'], columnEnds: [13, 13, 13, 0]};
  const pending = worksheetInput(source, [], 2, 13, {mode: 'treatmentAndBlock', data: 0, identifiers: [1], block: 2});
  assert.deepEqual(pending.request.columns, [0, 1, 2]);
  assert.deepEqual(pending.layout, {mode: 'treatmentAndBlock', identifiers: 1, block: true});
  const data = {columns: [{title: 'score', values: ['1', '2']}, {title: 'treatment', values: ['a', 'b']}, {title: 'block', values: ['x', 'x']}]};
  const input = worksheetInputFrom(pending, data);
  assert.equal(input.layout, 'long');
  assert.deepEqual(input.columns, [{title: 'score', values: ['1', '2']}]);
  assert.deepEqual(input.groupIdentifiers, [{title: 'treatment', values: ['a', 'b']}]);
  assert.deepEqual(input.blockIdentifiers, [{title: 'block', values: ['x', 'x']}]);
  assert.match(input.source, /groups by identifier/);
  assert.deepEqual(input.roles, {mode: 'treatmentAndBlock', identifiers: 1, block: true});
  const single = worksheetInput(source, [], 2, 13, {mode: 'single', data: 0, identifiers: [1, 2]});
  assert.deepEqual(single.request.columns, [0, 1, 2]);
  assert.equal(worksheetInputFrom(single, data).blockIdentifiers, undefined);
  assert.throws(() => worksheetInput(source, [], 2, 13, {mode: 'single', data: undefined, identifiers: [1]}), /data column/);
  assert.throws(() => worksheetInput(source, [], 2, 13, {mode: 'single', data: 0, identifiers: []}), /group identifier/);
  assert.throws(() => worksheetInput(source, [], 2, 13, {mode: 'single', data: 1, identifiers: [1]}), /different columns/);
  assert.throws(() => worksheetInput(source, [], 2, 13, {mode: 'treatmentAndBlock', data: 0, identifiers: [1, 2]}), /one treatment/);
  assert.throws(() => worksheetInput(source, [], 2, 13, {mode: 'treatmentAndBlock', data: 0, identifiers: [1]}), /block/);
  // A lesson source that carries cells cannot pivot: identifiers need the live worksheet.
  assert.throws(() => worksheetInput({...source, lazy: false, cells: []}, [], 2, 13, {mode: 'single', data: 0, identifiers: [1]}), /open worksheet/);
});
