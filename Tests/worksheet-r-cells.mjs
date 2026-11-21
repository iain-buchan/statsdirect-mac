// The production grid's view of chosen cells of a workbook the engine opened, for the Save As checks in
// Tests/excel_closedxml_functions_save.py: each cell's text, kind and formula, whether its value is unavailable, and what
// the R import of that cell alone sends or why it refuses. With an edit, the same after the grid makes it.
// If supplied a snapshot path, writes the grid snapshot that Save As sends, with or without changes.
// Usage: node Tests/worksheet-r-cells.mjs <payload.json> [save-snapshot.sdcol]
// payload: {reply, cells: [[col, row], ...], edit: [col, row, text] or null}; the cells are on the first worksheet.
import fs from 'node:fs';
import {WorkbookStore} from '../Grid/workbook.mjs';
import {decodeSnapshot, encodeSnapshot} from '../Grid/snapshot.mjs';
import {worksheetRImport} from '../Grid/worksheet-r.mjs';

const [payload, saveSnapshot] = process.argv.slice(2);
const {reply, cells, edit} = JSON.parse(fs.readFileSync(payload, 'utf8'));
for (const sheet of reply.sheets) if (sheet.snapshot) sheet.columnar = decodeSnapshot(fs.readFileSync(sheet.snapshot)).sheets[0].columns;
const book = new WorkbookStore();
book.load(reply);
const store = book.sheets[0].store;
const inspect = () => cells.map(([c, r]) => {
  const cell = {text: store.get(c, r), kind: store.kind(c, r), formula: store.formula(c, r), unavailable: store.formulaUnavailable(c, r)};
  try { cell.values = worksheetRImport(book, 0, {range: {x: c, y: r, width: 1, height: 1}}, 'selected').columns[0].values; }
  catch (error) { cell.error = error.message; }
  return cell;
});
const before = inspect();
let after = null;
if (edit) {
  if (!store.apply([edit])) throw new Error('The edit changed nothing.');
  book.changed();
  after = inspect();
}
if (saveSnapshot) fs.writeFileSync(saveSnapshot, new Uint8Array(encodeSnapshot(book.exportColumns().sheets)));
console.log(JSON.stringify({before, after}));
