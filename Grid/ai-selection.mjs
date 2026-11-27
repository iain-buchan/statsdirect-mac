// What AI Assist shows locally about the worksheet: the current selection in A1 notation, whether the workbook holds
// anything at all and whether row 1 holds the column names. None of this is sent to the provider; the pane uses it for
// its Selection label, for the choices it offers an empty workbook and to read its distribution card again.
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

// Whole columns or rows as [start, end) slices. Glide's CompactSelection already keeps them so (its `items`), which
// encodes a million-row selection in a few numbers; anything else is walked only when small.
function slices(compact) {
  const items = compact?.items;
  if (Array.isArray(items) && items.every(slice => Array.isArray(slice) && slice.length === 2)) return items.map(([a, b]) => [a, b]);
  if (!compact?.length) return [];
  if (compact.length > 100000) return [[compact.first(), compact.last() + 1, compact.length]];
  const out = [];
  for (const i of compact) { const last = out[out.length - 1]; if (last && last[1] === i) last[1] = i + 1; else out.push([i, i + 1]); }
  return out;
}

// The exact selection, with the sheet and the workbook and sheet revisions every edit changes, for AI Assist's check
// that a clarification click still belongs to the selection its card was drawn for. Sparse rows such as 2, 3, 6 and
// 2, 4, 6 differ here although their caption ("2:6 (some rows)") is the same.
export function selectionFingerprint(workbook, sheetIndex, selection) {
  const store = workbook.sheets[sheetIndex].store, current = selection?.current;
  // The "First row has column names" setting changes what a read sends without advancing either revision.
  return JSON.stringify({sheet: sheetIndex, workbookRevision: workbook.revision, sheetRevision: store.version, headerRow: !!store.headerRow,
    cell: current?.cell ?? null, range: current?.range ?? null, stack: current?.rangeStack ?? [],
    columns: slices(selection?.columns), rows: slices(selection?.rows)});
}

// The selection AI Assist's method offer is made for and Continue checks (WorksheetAIAnalysis.swift WorksheetAISelection),
// with the click fingerprint of the same moment: an offer chosen on a distribution card is held to the reading the card
// showed, which "First row has column names" changes although the selection and both revisions do not.
export function worksheetAISelection(workbook, sheetIndex, selection) {
  return {sheet: sheetIndex, sheetName: workbook.sheets[sheetIndex].name, workbookRevision: workbook.revision,
    sheetRevision: workbook.sheets[sheetIndex].store.version, columns: selection.columns.toArray(), rowCount: selection.rows.length,
    firstRow: selection.rows.first() ?? null, lastRow: selection.rows.last() ?? null,
    range: selection.current?.range ?? null, ranges: selection.current?.rangeStack ?? [],
    fingerprint: selectionFingerprint(workbook, sheetIndex, selection)};
}

// The read columns whose row-1 cell holds text, with the header row on: their heading travelled as the column's
// title. A blank one sends only the stand-in "Column X"; a real heading that reads "Column X" is still a heading.
export function headingCells(workbook, sheetIndex, columns) {
  const store = workbook.sheets[sheetIndex]?.store;
  if (!store?.headerRow || !Array.isArray(columns)) return [];
  return columns.filter(c => Number.isInteger(c) && c >= 0 && c < store.columns.length && store.get(c, 0) !== '');
}

export function aiWorksheetState(workbook, sheetIndex, selection) {
  const sheet = workbook.sheets[sheetIndex], store = sheet.store;
  const {label, singleCell} = selectionAddress(selection, {columns: store.columns.length, rows: store.rows});
  // The "First row has column names" setting changes what the distribution card reads, so a change is posted too.
  return {sheet: sheetIndex, sheetName: sheet.name, label, singleCell, hasData: workbookHasData(workbook), headerRow: !!store.headerRow};
}
