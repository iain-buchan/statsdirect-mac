import {columnName} from './store.mjs';

// Plan bounds from the sparse column store. Formatting-only cells may allocate
// chunks, but only actual values and formulas define an importable worksheet.
function columnBounds(store, c) {
  const column = store.cols[c];
  if (!column) return null;
  let first = Infinity, last = column.used() - 1;
  if (column.count) {
    outer: for (const chunk of [...column.chunks.keys()].sort((a, b) => a - b)) {
      const kinds = column.chunks.get(chunk).kind;
      for (let i = 0; i < kinds.length; i++) {
        if (kinds[i] !== 0) { first = chunk * kinds.length + i; break outer; }
      }
    }
  }
  for (const row of column.formula.keys()) { first = Math.min(first, row); last = Math.max(last, row); }
  return Number.isFinite(first) ? {first, last} : null;
}

function populatedBounds(store, columns = null) {
  let first = Infinity, last = -1, left = Infinity, right = -1;
  const visit = c => {
    const bounds = columnBounds(store, c);
    if (!bounds) return;
    first = Math.min(first, bounds.first); last = Math.max(last, bounds.last);
    left = Math.min(left, c); right = Math.max(right, c);
  };
  if (columns) columns.forEach(visit);
  else store.cols.forEach((_column, c) => visit(c));
  return Number.isFinite(first) ? {first, last, left, right} : null;
}

function importPlan(store, selection, scope, entire) {
  if (scope === 'entire') return entire ? {
    columns: Array.from({length: entire.right - entire.left + 1}, (_, i) => entire.left + i),
    first: entire.first, last: entire.last
  } : null;
  const headings = selection.columns ?? [], selectedRows = selection.rows ?? [], range = selection.range;
  if (headings.length) {
    const columns = [...headings];
    if (new Set(columns).size !== columns.length || columns.some(c => !Number.isInteger(c) || c < 0 || c >= store.columns.length)) {
      throw new Error('Select cells inside the worksheet.');
    }
    const bounds = populatedBounds(store, columns);
    return bounds ? {columns, first: bounds.first, last: bounds.last} : null;
  }
  if (selectedRows.length) {
    if (selectedRows.some(r => !Number.isInteger(r) || r < 0 || r >= store.rows)) throw new Error('Select cells inside the worksheet.');
    // Retain row-heading selections, including their gaps, over the populated
    // worksheet width; rows beyond its last populated row remain excluded.
    const rows = [...new Set(selectedRows)].filter(r => entire && r <= entire.last).sort((a, b) => a - b);
    return rows.length ? {columns: Array.from({length: entire.right + 1}, (_, c) => c), first: rows[0], last: rows.at(-1), rows} : null;
  }
  if (!range) return null;
  const {x, y, width, height} = range;
  if (![x, y, width, height].every(Number.isInteger) || x < 0 || y < 0 || width < 1 || height < 1 || x + width > store.columns.length || y + height > store.rows) {
    throw new Error('Select cells inside the worksheet.');
  }
  return {columns: Array.from({length: width}, (_, i) => x + i), first: y, last: y + height - 1};
}

function importRange(plan) {
  const {columns, first, last, rows} = plan;
  const consecutiveColumns = columns.every((c, i) => c === columns[0] + i);
  const consecutiveRows = !rows || rows.length === last - first + 1;
  if (consecutiveColumns && consecutiveRows) {
    const from = columnName(columns[0]) + (first + 1), to = columnName(columns.at(-1)) + (last + 1);
    return from === to ? from : from + ':' + to;
  }
  const labels = consecutiveColumns ? `${columnName(columns[0])}:${columnName(columns.at(-1))}` : columns.map(columnName).join(', ');
  return labels + ' · rows ' + (consecutiveRows ? `${first + 1}–${last + 1}` : rows.map(r => r + 1).join(', '));
}

function suggestHeadings(store, plan) {
  let any = false;
  const numeric = /^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/;
  for (const c of plan.columns) {
    const text = store.get(c, plan.first).trim();
    if (!text) continue;
    any = true;
    if (store.kind(c, plan.first) !== 'text' || store.formula(c, plan.first) || numeric.test(text) || /^(true|false)$/i.test(text)) return false;
  }
  return any;
}

// The prompt asks for bounds and heading advice without materialising the
// selected data. Only its confirmed scope reads cells; the first row stays raw
// so the native dialog's heading choice, independent of the grid flag, owns it.
export function worksheetRImport(workbook, sheetIndex, selection = {}, scope, maximumBytes = 8 * 1024 * 1024) {
  const sheet = workbook.sheets[sheetIndex], store = sheet?.store;
  if (!store) throw new Error('Choose an open worksheet.');
  const entire = populatedBounds(store);
  const plan = name => importPlan(store, selection, name, entire);
  const preview = value => value ? {
    range: importRange(value), rowCount: value.rows?.length ?? value.last - value.first + 1,
    columnCount: value.columns.length, suggestHeadings: suggestHeadings(store, value)
  } : null;
  if (scope === undefined) return {entire: preview(plan('entire')), selected: preview(plan('selected'))};
  if (!['entire', 'selected'].includes(scope)) throw new Error('Choose the entire worksheet or selected cells.');
  const chosen = plan(scope);
  if (!chosen) throw new Error(scope === 'entire' ? 'The worksheet contains no data.' : 'Select worksheet cells, columns or rows to import.');
  const info = preview(chosen);
  const tooLarge = () => new Error('The selected data exceed the 8 MiB editable R script limit. Select a smaller range, or export the worksheet as RDS from File → Export.');
  let minimumBytes = chosen.columns.length * info.rowCount * 3;
  if (minimumBytes > maximumBytes) throw tooLarge();
  const encoder = new TextEncoder();
  const columns = chosen.columns.map(c => {
    const title = store.headerRow ? store.columnTitle(c) : 'Column ' + columnName(c), values = [], kinds = [];
    minimumBytes += encoder.encode(title).length;
    for (let i = 0; i < info.rowCount; i++) {
      const r = chosen.rows ? chosen.rows[i] : chosen.first + i, text = store.get(c, r), kind = store.kind(c, r);
      if (kind === 'error') throw new Error('The selection contains Excel errors. Correct them in Excel and reopen the workbook.');
      if (store.formula(c, r) && (store.formulasStale || text === '')) throw new Error('Recalculate and save this workbook in Excel, then reopen it before using formula cells in R.');
      minimumBytes += Math.max(1, encoder.encode(text).length) - 1;
      if (minimumBytes > maximumBytes) throw tooLarge();
      values.push(text); kinds.push(kind);
    }
    return {title, values, kinds};
  });
  return {workbook: workbook.name, sheet: sheet.name, range: info.range, rowCount: info.rowCount, columns};
}
