// Loads the JSON `open` reply from stdin, applies the same edit as edit-workbook.mjs and
// writes the typed snapshot of the edits to the file named in argv[2].
import fs from 'node:fs';
import { WorkbookStore } from '../Grid/workbook.mjs';
import { encodeSnapshot } from '../Grid/snapshot.mjs';
const book = new WorkbookStore(); book.load(JSON.parse(fs.readFileSync(0, 'utf8')));
book.sheets[0].store.apply([[0, 1, '332']]);
const sheets = book.exportColumns().sheets;
fs.writeFileSync(process.argv[2], encodeSnapshot(sheets));
process.stdout.write(JSON.stringify({cells: sheets.reduce((n, s) => n + s.columns.reduce((m, c) => m + c.rows.length, 0), 0)}));
