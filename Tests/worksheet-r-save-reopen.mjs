// Production grid load/edit/export and child-only R selection for the native
// Save As regression in excel_formula_region_save.py. No hand-written metadata.
import fs from 'node:fs';
import {WorkbookStore} from '../Grid/workbook.mjs';
import {decodeSnapshot, encodeSnapshot} from '../Grid/snapshot.mjs';
import {worksheetRImport} from '../Grid/worksheet-r.mjs';

const [payload, editSnapshot] = process.argv.slice(2);
const {reply, variant} = JSON.parse(fs.readFileSync(payload, 'utf8'));
for (const sheet of reply.sheets) if (sheet.snapshot) sheet.columnar = decodeSnapshot(fs.readFileSync(sheet.snapshot)).sheets[0].columns;
const book = new WorkbookStore();
book.load(reply);
const store = book.sheets[0].store;
const table = variant === 'what-if';
const input = table ? [1, 3] : [4, 0];
const child = table ? [2, 3] : variant === 'scalar' ? [5, 0] : [1, 0];
function inspect() {
  const [c, r] = child;
  try {
    const data = worksheetRImport(book, 0, {range: {x: c, y: r, width: 1, height: 1}}, 'selected');
    return {text: store.get(c, r), unavailable: store.formulaUnavailable(c, r), values: data.columns[0].values, input: store.get(...input)};
  } catch (error) {
    return {text: store.get(c, r), unavailable: store.formulaUnavailable(c, r), error: error.message, input: store.get(...input)};
  }
}
const before = inspect();
let after;
if (editSnapshot) {
  if (!store.apply([[...input, '10']])) throw new Error('The fixture input was not edited');
  book.changed();
  after = inspect();
  fs.writeFileSync(editSnapshot, new Uint8Array(encodeSnapshot(book.exportColumns().sheets)));
}
console.log(JSON.stringify({before, after}));
