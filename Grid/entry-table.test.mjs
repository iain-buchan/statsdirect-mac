import {test} from 'node:test';
import assert from 'node:assert/strict';
import {EntryTable} from './entry-table.mjs';
import {MAX_ROWS, MAX_COLS} from './store.mjs';
import {analysisMetadata, columnValues} from './analysis-source.mjs';
import {worksheetInputFrom} from './operation-data.mjs';

test('entry tables paste and submit two full Excel columns, and edit only the affected storage',()=>{
  const table=new EntryTable({minColumns:2,maxColumns:2});
  table.paste('1\t2\n'.repeat(MAX_ROWS));
  assert.equal(table.store.rows,MAX_ROWS);
  assert.equal(table.store.count(),MAX_ROWS*2);
  const column=table.store.cols[0],chunk=column.chunks.get(0);
  table.pasteValues([['3']],1,MAX_ROWS-1);
  assert.equal(table.store.cols[0],column);
  assert.equal(column.chunks.get(0),chunk);
  const input=table.input();
  assert.equal(input.columns[0].values.length,MAX_ROWS);
  assert.equal(input.columns[1].values[MAX_ROWS-1],'3');
  assert.equal(input.columns[1].values[MAX_ROWS-2],'2');
  // Reject the complete paste before writing its valid first cell.
  assert.throws(()=>table.paste('8\n9',0,MAX_ROWS-1),/Excel worksheet/);
  assert.equal(table.store.get(0,MAX_ROWS-1),'1');
});

test('entry width reaches XFD without allocating blank rows, and overflow is atomic',()=>{
  const table=new EntryTable({minColumns:1});
  table.paste('1\t'.repeat(MAX_COLS-1)+'2');
  assert.equal(table.store.columns.length,MAX_COLS);
  assert.equal(table.store.get(MAX_COLS-1,0),'2');
  assert.throws(()=>table.pasteValues([['8','9']],MAX_COLS-1,0),/Excel worksheet/);
  assert.equal(table.store.get(MAX_COLS-1,0),'2');
  table.dimensions(12,1);table.dimensions(12,MAX_COLS);
  assert.equal(table.store.get(MAX_COLS-1,0),'');
});

test('fixed tables preserve dimensions, exact text and quoted cells; malformed pastes change nothing',()=>{
  const table=new EntryTable({minColumns:2,maxColumns:2,rows:2,fixedRows:true});
  table.paste('"a\tb"\t"line 1\nline 2"\r\n0012\t"a ""quote"""');
  assert.deepEqual(table.input().columns.map(c=>c.values),[['a\tb','0012'],['line 1\nline 2','a "quote"']]);
  const before=table.input();
  for (const text of ['9\n8\n7','9\t8\t7','9\t"unclosed']) assert.throws(()=>table.paste(text));
  assert.deepEqual(table.input(),before);
  table.pasteValues([[' \t ','*']],0,1);
  assert.deepEqual(table.input().columns.map(c=>c.values[1]),[' \t ','*']);
});

test('removing unused columns leaves an editable table; expanding pastes use form column names',()=>{
  const table=new EntryTable({minColumns:1,labels:['First','Unused']});
  table.dimensions(12,1);
  table.paste('1\t2');
  table.pasteValues([['3']],2,0);
  assert.deepEqual(table.input().columns,[{title:'First',values:['1']},{title:'Column 2',values:['2']},{title:'Column 3',values:['3']}]);
});

test('large selected rectangles load on demand without a million-cell cap or eager screen copy',()=>{
  const sheet=new EntryTable({minColumns:2,maxColumns:2});
  sheet.paste('12\t3\n'.repeat(500001));
  const book={name:'Selected workbook',sheets:[{name:'Counts',store:sheet.store}]};
  const source=analysisMetadata(book,0,{range:{x:0,y:0,width:2,height:500001}});
  assert.equal(source.screen,undefined);
  assert.equal(source.screenError,undefined);
  assert.equal(source.screenDeferred,true);
  const table=new EntryTable({screen:true,minColumns:2,maxColumns:2},source);
  assert.throws(()=>table.input(),/still loading/);
  const pending=table.pending;
  table.load(worksheetInputFrom(pending,columnValues(book,0,pending.request)));
  assert.equal(table.pending,null);
  assert.equal(table.store.rows,500001);
  assert.equal(table.store.count(),1000002);
  assert.equal(table.store.get(1,500000),'3');
  assert.equal(table.input().columns[0].values.length,500001);
  // A fixed 2×2 form must reject this selection before requesting any values.
  const fixed=new EntryTable({screen:true,minColumns:2,maxColumns:2,rows:2,fixedRows:true},source);
  assert.equal(fixed.pending,null);
  assert.match(fixed.error,/not been copied/);
  assert.equal(fixed.store.count(),0);
  assert.throws(()=>worksheetInputFrom(pending,{columns:[],errors:1}),/Excel errors/);
  assert.throws(()=>worksheetInputFrom(pending,{columns:[],uncached:1}),/Recalculate/);
});
