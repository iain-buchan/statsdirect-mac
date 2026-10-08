// What an analysis form learns about a worksheet, and how it reads columns from it.
//
// A form used to receive every cell of the sheet as JSON. It now receives metadata (column
// titles, the extent of each column, the selection) and asks for the chosen columns when the
// user submits a step, so a sheet of Excel's full size costs the form nothing until then.
import { MAX_ROWS } from './store.mjs';
import { worksheetSelection } from './operation-data.mjs';

const SCREEN_CELLS = 1000000;

// Last 1-based row of a column that holds a value or a formula (0 for an empty column).
export function columnEnd(store, c) {
  let end = store.columnUsedRows(c);
  const col = store.cols[c];
  if (col) for (const r of col.formula.keys()) if (r + 1 > end) end = r + 1;
  return end;
}

export function analysisMetadata(workbook, sheetIndex, selection) {
  const sheet = workbook.sheets[sheetIndex], store = sheet.store;
  const firstRow = store.headerRow ? 2 : 1;
  const chosen = worksheetSelection(selection.columns ?? [], selection.range);
  const columnEnds = store.columns.map((_, c) => columnEnd(store, c));
  const used = store.usedColumns();
  const source = {
    name: workbook.name + ' / ' + sheet.name,
    sheet: sheetIndex,
    sheetName: sheet.name,
    columns: store.columns.map((_, c) => store.columnTitle(c)),
    firstRow,
    rows: Math.max(firstRow, store.usedRows(), chosen.range?.last ?? 0),
    formulasStale: store.formulasStale,
    columnEnds,
    width: used.length ? used[used.length - 1] + 1 : 0,
    lazy: true,
    ...chosen
  };
  // Screen forms take the highlighted rectangle itself, so its values travel with the metadata.
  if (chosen.range && chosen.selection.length) {
    const rows = chosen.range.last - chosen.range.first + 1;
    if (rows * chosen.selection.length > SCREEN_CELLS) source.screenError = 'The selected table is too large for this form.';
    else {
      try {
        const data = columnValues(workbook, sheetIndex, {columns: chosen.selection, first: chosen.range.first, last: chosen.range.last});
        checkColumnData(data);
        source.screen = Array.from({length: rows}, (_, r) => data.columns.map(c => c.values[r]));
      } catch (e) { source.screenError = e.message; }
    }
  }
  return source;
}

// Errors a form reports for a column read, in the words the forms have always used.
export function checkColumnData(data) {
  if (data.errors > 0) throw new Error('The selection contains Excel errors. Correct them in Excel and reopen the workbook.');
  if (data.uncached > 0) throw new Error('Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.');
}

// The chosen columns over 1-based rows first..last as text, with counts of Excel error cells
// and of formula cells whose saved result is missing or out of date.
// A request made from metadata names its sheet; the values come from that sheet, whichever
// sheet the grid is showing now, and a sheet that is gone or renamed is refused.
function requestedSheet(workbook, sheetIndex, request) {
  const index = Number.isInteger(request?.sheet) ? request.sheet : sheetIndex;
  const sheet = workbook.sheets[index];
  if (!sheet || (typeof request?.sheetName === 'string' && sheet.name !== request.sheetName)) throw new Error('That worksheet is no longer available. Refresh the worksheet.');
  return sheet;
}
export function columnValues(workbook, sheetIndex, request) {
  const sheet = requestedSheet(workbook, sheetIndex, request), store = sheet.store;
  const columns = request?.columns, first = request?.first, last = request?.last;
  if (!Array.isArray(columns) || !columns.length || !columns.every(c => Number.isInteger(c) && c >= 0 && c < store.columns.length)) throw new Error('That column is no longer available. Refresh the worksheet.');
  if (new Set(columns).size !== columns.length) throw new Error('Choose each column once.');
  if (!Number.isInteger(first) || !Number.isInteger(last) || first < 1 || last < first || last > MAX_ROWS) throw new Error('Enter a valid first and last worksheet row.');
  let errors = 0, uncached = 0;
  const out = columns.map(c => {
    const values = new Array(last - first + 1);
    for (let r = first - 1; r < last; r++) {
      const text = store.get(c, r);
      values[r - first + 1] = text;
      if (store.kind(c, r) === 'error') errors++;
      if (store.formula(c, r) && (store.formulasStale || text === '')) uncached++;
    }
    return {title: store.columnTitle(c), values};
  });
  return {name: workbook.name + ' / ' + sheet.name, columns: out, errors, uncached, first, last};
}

// Typed column records of the given columns for a snapshot (derived worksheets copy the
// source columns beside the engine's output).
export function snapshotColumns(workbook, sheetIndex, request) {
  const store = requestedSheet(workbook, sheetIndex, request).store;
  const columns = request?.columns, rowOffset = request?.rowOffset ?? 0, header = !!request?.header;
  if (!Array.isArray(columns) || !columns.every(c => Number.isInteger(c) && c >= 0 && c < store.columns.length)) throw new Error('That column is no longer available.');
  if (!Number.isInteger(rowOffset) || rowOffset < 0 || store.usedRows() + rowOffset > MAX_ROWS) throw new Error('The derived worksheet would exceed the Excel worksheet dimensions.');
  return store.columnRecords(columns, rowOffset, header);
}
