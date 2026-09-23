import fs from 'node:fs';
import {WorkbookStore} from '../Grid/workbook.mjs';
import {rDataTables} from '../Grid/r-data.mjs';
import {csvWorkbook} from '../Grid/csv.mjs';
const [mode,input,output]=process.argv.slice(2);
const book=new WorkbookStore();
if(mode==='csv') {
  book.load(csvWorkbook(fs.readFileSync(input,'utf8'),'round-trip.csv'));
  fs.writeFileSync(output,book.sheets[0].store.csv());
} else {
  book.load(JSON.parse(fs.readFileSync(input,'utf8')));
  if(mode==='r-edit') {
    book.sheets[0].store.apply([[1,1,'22'],[4,1,'new group']]);book.changed();
  }
  if(mode==='r-invalid') book.sheets[0].store.apply([[1,1,'not a number']]);
  fs.writeFileSync(output,JSON.stringify(rDataTables(book)));
}
