import {test} from 'node:test';
import assert from 'node:assert/strict';
import {WorkbookStore} from './workbook.mjs';
import {csvWorkbook,parseCSV} from './csv.mjs';
import {worksheetPrintHTML,entryTablePrintHTML} from './printing.mjs';

test('TSV round trip preserves literal formulas, identifiers, tabs and multiline text',()=>{
 const rows=[['id','note','value'],['0012','comma, tab\there\nand newline','=1+1'],['é','"quoted"','1.50']];
 const input=rows.map(row=>row.map(s=>'"'+s.replaceAll('"','""')+'"').join('\t')).join('\r\n');
 const book=new WorkbookStore();book.load(csvWorkbook(input,'data.tsv'));
 assert.equal(book.sheets[0].store.kind(0,1),'text');assert.equal(book.sheets[0].store.formula(2,1),'');
 assert.deepEqual(parseCSV(book.sheets[0].store.csv('\t'),undefined,'\t'),rows);
});
test('printing respects selected columns/ranges and escapes data; wide sheets are banded',()=>{
 const book=new WorkbookStore();book.load({name:'Print',sheets:[{name:'Sheet',columns:20,rows:100,cells:[{col:0,row:0,text:'<script>unsafe</script>',kind:'text'},{col:12,row:9,text:'last',kind:'text'}]}]});
 const store=book.sheets[0].store;
 const all=worksheetPrintHTML(store);assert.equal((all.match(/<section>/g)||[]).length,2);assert.ok(all.includes('&lt;script&gt;'));assert.ok(all.includes('last'));assert.ok(!all.includes('<script>'));
 const chosen=worksheetPrintHTML(store,{columns:[12]});assert.ok(chosen.includes('last'));assert.ok(!chosen.includes('unsafe'));
 const range=worksheetPrintHTML(store,{range:{x:12,y:9,width:1,height:1}});assert.equal((range.match(/<td>/g)||[]).length,1);
 assert.throws(()=>worksheetPrintHTML(store,{range:{x:0,y:0,width:256,height:65536}}),/No cells have been omitted/);
 assert.ok(entryTablePrintHTML({columnLabels:['<A>'],rowLabels:['&B'],counts:[['4']]}).includes('&lt;A&gt;'));
});
test('legacy export includes unchanged loaded cells, while regular save remains a patch',()=>{
 const book=new WorkbookStore();book.load({id:'original',name:'test',sheets:[{name:'Sheet',columns:2,rows:4,cells:[{col:0,row:0,text:'12',kind:'number'},{col:1,row:3,text:'0012',kind:'text'}]}]});
 assert.equal(book.exportColumns().sheets[0].columns.length,0);
 const all=book.exportColumns(true).sheets[0].columns;assert.equal(all.length,2);assert.equal(all[1].texts.get(0),'0012');
 assert.equal(book.exportColumns().sheets[0].columns.length,0);
});
