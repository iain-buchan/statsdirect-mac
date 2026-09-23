import { MAX_ROWS, MAX_COLS, numeric } from './store.mjs';

export const MAX_CSV_FIELDS = 500000;
// CSV is data: preserve field text exactly, including whitespace, newlines,
// identifiers and strings beginning with '='. Never evaluate imported text.
export function parseCSV(input, maxFields = MAX_CSV_FIELDS) {
  const text = input.replace(/^\uFEFF/, '');
  if (text.includes('\0')) throw new Error('This file contains NUL bytes and is not a supported text CSV.');
  if (!text.length) return [];
  const rows = [];
  let row = [], field = '', quoted = false, closed = false, started = false, fields = 0;
  const finishField = () => {
    if (++fields > maxFields) throw new Error(`CSV files can contain at most ${maxFields.toLocaleString('en-GB')} fields in this prototype.`);
    if (row.length >= MAX_COLS) throw new Error('The CSV exceeds Excel’s column limit.');
    row.push(field); field = ''; closed = false; started = false;
  };
  const finishRow = () => {
    finishField();
    if (rows.length >= MAX_ROWS) throw new Error('The CSV exceeds Excel’s row limit.');
    rows.push(row); row = [];
  };
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (quoted) {
      if (ch === '"') {
        if (text[i + 1] === '"') { field += '"'; i++; }
        else { quoted = false; closed = true; }
      } else field += ch;
    } else if (ch === ',') finishField();
    else if (ch === '\r' || ch === '\n') {
      finishRow();
      if (ch === '\r' && text[i + 1] === '\n') i++;
    } else if (closed) throw new Error(`Unexpected text after a closing quote in CSV record ${rows.length + 1}.`);
    else if (ch === '"') {
      if (started) throw new Error(`Unexpected quote in CSV record ${rows.length + 1}. Enclose fields containing quotes in double quotes.`);
      quoted = true; started = true;
    } else { field += ch; started = true; }
  }
  if (quoted) throw new Error(`Unclosed quote in CSV record ${rows.length + 1}.`);
  if (started || closed || row.length) finishRow();
  return rows;
}
function csvKind(text) {
  if (text === '') return 'blank';
  if (text !== text.trim() || /^[+-]?0\d/.test(text)) return 'text';
  try {
    const n = numeric(text);
    if (n !== null && (!Number.isInteger(n) || Number.isSafeInteger(n))) return 'number';
  } catch {}
  return 'text';
}
export function csvWorkbook(text, name) {
  const rows = parseCSV(text);
  const columns = rows.reduce((n, row) => Math.max(n, row.length), 1);
  // The grid is rectangular. Bound the padded shape as well as input fields.
  if (rows.length * columns > MAX_CSV_FIELDS) throw new Error('The CSV’s rectangular table exceeds 500,000 cells.');
  const cells = [];
  rows.forEach((row, r) => row.forEach((text, c) => {
    if (text !== '') cells.push({ col: c, row: r, text, kind: csvKind(text) });
  }));
  const sheetName = name.replace(/\.csv$/i, '').replace(/[\[\]:*?\/\\]/g, ' ').slice(0, 31) || 'Data';
  return {name, formulaCount: 0, sheets: [{name: sheetName, hidden: false, rows: rows.length, csvRows: rows.length, columns, cells}]};
}
