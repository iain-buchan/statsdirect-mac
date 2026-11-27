// What AI Assist shows locally about the worksheet: the current selection in A1 notation and whether the workbook
// holds anything at all. None of this is sent to the provider; the pane uses it for its Selection label and for the
// choices it offers an empty workbook.
import {columnName} from './store.mjs';

const MAX_AREAS = 4;

function cellName(column, row) { return columnName(column) + (row + 1); }

// One rectangle, clipped to the sheet so the trailing "Add a row" row or a selection left behind by Undo never shows.
function rectangleLabel(rect, bounds) {
  if (!rect) return null;
  const left = Math.max(0, rect.x), top = Math.max(0, rect.y);
  const right = Math.min(bounds.columns - 1, rect.x + rect.width - 1), bottom = Math.min(bounds.rows - 1, rect.y + rect.height - 1);
  if (right < left || bottom < top) return null;
  const single = left === right && top === bottom;
  return {label: single ? cellName(left, top) : cellName(left, top) + ':' + cellName(right, bottom), single};
}

// Whole columns as Excel writes them ("A:C", "E:E"), in groups of adjacent columns.
function columnsLabel(columns, bounds) {
  const indexes = [...columns].filter(c => c >= 0 && c < bounds.columns).sort((a, b) => a - b);
  if (!indexes.length) return null;
  const groups = [];
  for (const c of indexes) {
    const last = groups[groups.length - 1];
    if (last && c === last[1] + 1) last[1] = c; else groups.push([c, c]);
  }
  const shown = groups.slice(0, MAX_AREAS).map(([a, b]) => columnName(a) + ':' + columnName(b));
  return shown.join(',') + (groups.length > MAX_AREAS ? ',…' : '');
}

// Whole rows as Excel writes them ("2:5"). Rows can number a million, so only the ends and the count are read.
function rowsLabel(rows, bounds) {
  if (!rows || !rows.length) return null;
  const first = Math.max(0, rows.first()), last = Math.min(bounds.rows - 1, rows.last());
  if (last < first) return null;
  const label = (first + 1) + ':' + (last + 1);
  return rows.length === rows.last() - rows.first() + 1 ? label : label + ' (some rows)';
}

// selection: a Glide GridSelection ({current?: {range, rangeStack}, columns, rows}); bounds: {columns, rows} of the sheet.
export function selectionAddress(selection, bounds) {
  const current = selection?.current;
  if (current?.range) {
    const areas = [current.range, ...(current.rangeStack ?? [])].map(rect => rectangleLabel(rect, bounds)).filter(Boolean);
    if (!areas.length) return {label: '', singleCell: false};
    const label = areas.slice(0, MAX_AREAS).map(a => a.label).join(',') + (areas.length > MAX_AREAS ? ',…' : '');
    return {label, singleCell: areas.length === 1 && areas[0].single};
  }
  if (selection?.columns?.length) return {label: columnsLabel(selection.columns.toArray(), bounds) ?? '', singleCell: false};
  if (selection?.rows?.length) return {label: rowsLabel(selection.rows, bounds) ?? '', singleCell: false};
  return {label: '', singleCell: false};
}

// Any stored cell, formula (including one whose cached result is blank) or array/spill result span, on any sheet,
// hidden sheets included. Column headings count: a workbook with only headings is not empty.
export function workbookHasData(workbook) {
  return workbook.sheets.some(({store}) => store.count() > 0
    || (store.cols ?? []).some(col => col.formula?.size > 0)
    || (store.formulaRegions?.length ?? 0) > 0);
}

export function aiWorksheetState(workbook, sheetIndex, selection) {
  const sheet = workbook.sheets[sheetIndex], store = sheet.store;
  const {label, singleCell} = selectionAddress(selection, {columns: store.columns.length, rows: store.rows});
  return {sheet: sheetIndex, sheetName: sheet.name, label, singleCell, hasData: workbookHasData(workbook)};
}
