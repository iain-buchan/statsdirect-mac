import {columnEnd} from './analysis-source.mjs';
import {columnName} from './store.mjs';

// Read a fixed selection for an editable R script. The AI's sampling limits do
// not apply to this local transfer. The host checks its complete script size.
export function worksheetRSelection(workbook, sheetIndex, selection = {}, maximumBytes = 8 * 1024 * 1024) {
  const sheet = workbook.sheets[sheetIndex], store = sheet?.store;
  if (!store) throw new Error('Choose an open worksheet.');
  const firstDataRow = store.headerRow ? 1 : 0;
  const headings = selection.columns ?? [], selectedRows = selection.rows ?? [], range = selection.range;
  let columns, rows;
  if (headings.length) {
    columns = [...headings];
    const end = columns.reduce((last, c) => Math.max(last, columnEnd(store, c)), firstDataRow);
    rows = Array.from({length: end - firstDataRow}, (_, i) => firstDataRow + i);
  } else if (selectedRows.length) {
    const used = store.usedColumns(), width = (used.at(-1) ?? -1) + 1, lastRow = store.usedRows();
    columns = Array.from({length: width}, (_, c) => c);
    rows = [...new Set(selectedRows)].filter(r => r >= firstDataRow && r < lastRow).sort((a, b) => a - b);
  } else if (range) {
    columns = Array.from({length: range.width}, (_, i) => range.x + i);
    rows = Array.from({length: range.height}, (_, i) => range.y + i).filter(r => r >= firstDataRow);
  } else {
    throw new Error('Select worksheet cells, columns or rows to open their data in R.');
  }
  if (!columns.length || !rows.length) throw new Error('The selection contains no data rows. Select the data you want to open in R.');
  if (columns.some(c => !Number.isInteger(c) || c < 0 || c >= store.columns.length) || rows.some(r => !Number.isInteger(r) || r < 0 || r >= store.rows)) {
    throw new Error('Select cells inside the worksheet.');
  }
  const tooLarge = () => new Error('The selected data exceed the 8 MiB editable R script limit. Select a smaller range, or export the worksheet as RDS from File → Export.');
  // Every R cell needs a literal and separator. Refuse huge empty rectangles
  // before materialising them, then count the text as the chosen cells are read.
  let minimumBytes = columns.length * rows.length * 3;
  if (minimumBytes > maximumBytes) throw tooLarge();
  const encoder = new TextEncoder();
  const data = columns.map(c => {
    const title = store.columnTitle(c), values = [], kinds = [];
    minimumBytes += encoder.encode(title).length;
    for (const r of rows) {
      const text = store.get(c, r), kind = store.kind(c, r);
      if (kind === 'error') throw new Error('The selection contains Excel errors. Correct them in Excel and reopen the workbook.');
      if (store.formula(c, r) && (store.formulasStale || text === '')) throw new Error('Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.');
      minimumBytes += Math.max(1, encoder.encode(text).length) - 1;
      if (minimumBytes > maximumBytes) throw tooLarge();
      values.push(text);
      kinds.push(kind);
    }
    return {title, values, kinds};
  });
  const first = rows[0] + 1, last = rows.at(-1) + 1;
  const rowLabel = selectedRows.length && rows.length !== last - first + 1 ? rows.map(r => r + 1).join(', ') : `${first}–${last}`;
  return {workbook: workbook.name, sheet: sheet.name, rowCount: rows.length, first, last,
    range: `${columns.map(columnName).join(', ')} · rows ${rowLabel}`, columns: data};
}
