// Prints the cells of a typed columnar snapshot file as the JSON `open` reply lists them.
import fs from 'node:fs';
import { decodeSnapshot } from '../Grid/snapshot.mjs';
import { KINDS } from '../Grid/store.mjs';
const sheets = decodeSnapshot(fs.readFileSync(process.argv[2])).sheets.map(sheet => ({
  name: sheet.name,
  cells: sheet.columns.flatMap(c => Array.from(c.rows, (row, i) => ({
    col: c.col, row, kind: KINDS[c.kinds[i]],
    text: c.kinds[i] === 1 ? String(c.nums[i]) : c.texts.get(i) ?? '',
    formula: c.formulas.get(i) ?? ''
  })))
}));
process.stdout.write(JSON.stringify(sheets));
