// Loads a workbook description from the native R reader (sheets name snapshot files), applies
// the grid model, and writes the R tables as a snapshot plus manifest for the native writer.
// node data-file-model.mjs csv <decoded.txt> <grid.csv>
// node data-file-model.mjs r|r-edit|r-invalid <book.json> <tables.sdcol> <tables.json>
import fs from 'node:fs';
import {WorkbookStore} from '../Grid/workbook.mjs';
import {rDataTables} from '../Grid/r-data.mjs';
import {csvWorkbook} from '../Grid/csv.mjs';
import {decodeSnapshot, encodeSnapshot} from '../Grid/snapshot.mjs';
const [mode,input,output,manifest]=process.argv.slice(2);
const book=new WorkbookStore();
if(mode==='csv') {
  book.load(csvWorkbook(fs.readFileSync(input,'utf8'),'round-trip.csv'));
  fs.writeFileSync(output,book.sheets[0].store.csv());
} else {
  const data=JSON.parse(fs.readFileSync(input,'utf8'));
  for (const sheet of data.sheets) if (typeof sheet.snapshot==='string') { sheet.columnar=decodeSnapshot(fs.readFileSync(sheet.snapshot)).sheets[0].columns; delete sheet.snapshot; }
  book.load(data);
  if(mode==='r-edit') {
    book.sheets[0].store.apply([[1,1,'22'],[4,1,'new group']]);book.changed();
  }
  if(mode==='r-invalid') book.sheets[0].store.apply([[1,1,'not a number']]);
  if(mode==='r-nul') book.sheets[0].store.apply([[3,1,'\u0000zzz']]);
  const {tables,sheets}=rDataTables(book);
  fs.writeFileSync(output,encodeSnapshot(sheets));
  fs.writeFileSync(manifest,JSON.stringify(tables));
}
