import {test} from 'node:test';
import assert from 'node:assert/strict';
import {parseCSV,csvWorkbook} from './csv.mjs';
import {WorkbookStore,cellKind} from './workbook.mjs';

test('CSV preserves quoted delimiters, doubled quotes, line breaks and Unicode',()=>{
  const input='\uFEFFid,note,score\r\n0012,"café, \"\"quoted\"\"",0\r\n0045,"two\nlines",-1.2e-3\r\n';
  const rows=parseCSV(input);
  assert.deepEqual(rows,[['id','note','score'],['0012','café, "quoted"','0'],['0045','two\nlines','-1.2e-3']]);
  const book=new WorkbookStore();book.load(csvWorkbook(input,'sample.csv'));
  assert.equal(cellKind(book.sheets[0].store,0,1),'text');
  assert.equal(book.sheets[0].store.headerRow,true);
  assert.deepEqual(parseCSV(book.sheets[0].store.csv()),rows);
});
test('CSV preserves blanks, trailing blank records, whitespace and quoted empty fields',()=>{
  for(const input of ['','""','a,b,\n,,\n','  a  ," b "\r\n','\r\n\r\n','1,2\r3,4\r']) {
    const book=new WorkbookStore();book.load(csvWorkbook(input,'empty.csv'));
    assert.deepEqual(parseCSV(book.sheets[0].store.csv()),parseCSV(input));
  }
});
test('Headerless data remain observations and edits export without invented headers',()=>{
  const book=new WorkbookStore();book.load(csvWorkbook('0,1\n2,4\n3,8','observations.csv'));
  const grid=book.sheets[0].store;
  assert.equal(grid.headerRow,false);assert.deepEqual(grid.paired(0,1).before,[0,2,3]);
  grid.apply([[0,1,'5']]);assert.equal(parseCSV(grid.csv())[1][0],'5');
  grid.undo();assert.equal(parseCSV(grid.csv())[1][0],'2');
});
test('CSV identifiers, literal formulas and large integers remain text',()=>{
  const book=new WorkbookStore();book.load(csvWorkbook('id,formula,large\n0012,=1+2,9007199254740993','codes.csv'));
  for(const c of [0,1,2])assert.equal(cellKind(book.sheets[0].store,c,1),'text');
  assert.ok(book.export().sheets[0].cells.some(c=>c.text==='=1+2'&&c.kind==='text'));
});
test('Invalid CSV fails without replacing a loaded workbook',()=>{
  const book=new WorkbookStore({before:[1,2],after:[3,4]});
  for(const text of ['"unclosed','"closed"junk','bare"quote','a\0b']) assert.throws(()=>book.load(csvWorkbook(text,'bad.csv')));
  assert.equal(book.name,'PEFR data');assert.equal(book.sheets[0].store.get(0,0),'1');
  assert.throws(()=>parseCSV('1,2,3',2),/at most/);
  assert.throws(()=>csvWorkbook('a,'.repeat(16384),'wide.csv'),/column limit/);
});
