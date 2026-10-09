import {MAX_ROWS, MAX_COLS} from './store.mjs';
// Output frames of an analysis written into a worksheet, as the Windows grid writes them
// (frmSpreadsheetGear.WriteDataFrame): one column per variable, the title in the title row,
// missing values as the missing indicator, placed relative to the selected columns or after
// the used columns. Insertions move the columns to the right of the insertion point along,
// cell kinds included, as Excel's "insert" does. A workbook opened from a file cannot take an
// insertion here (its cell formats and formulas would not move with the values), nor can a
// worksheet with formulas; such a sheet takes the output after its last column, in place of
// the selected columns, or in a new document.
export const PLACEMENTS = ['FirstColumn', 'BeforeSelection', 'ReplaceSelection', 'AfterSelection', 'LastColumn'];
const LABELS = {FirstColumn: 'as the first columns', BeforeSelection: 'before the selected columns', ReplaceSelection: 'in place of the selected columns', AfterSelection: 'after the selected columns', LastColumn: 'after the last used column'};
const BLANK = {text: '', kind: 'blank'};
// Plans the edits for `frames` (engine output frames: {columns, cells:[{col,row,text,kind}], lengths, missingIndicator, placement})
// in `store` at `placement`, relative to the analysis input `range` ({firstRow, lastRow, columns}).
// Returns {edits:[[col,row,text,kind]], rows, cols, written:[{x,y,width,height}], message}; the caller applies the edits as one undo step.
export function planWriteBack(store, frames, placement, range, options = {}) {
  if (!Array.isArray(frames) || !frames.length) throw new Error('There is no data to write.');
  if (!PLACEMENTS.includes(placement)) throw new Error('Unknown write position.');
  const edits = [], written = [];
  const header = !!store.headerRow;
  let rows = store.rows, cols = store.columns.length;
  // The selected columns of the analysis input, as the Windows grid uses its current selection.
  const selected = Array.isArray(range?.columns) ? range.columns.filter(c => Number.isInteger(c) && c >= 0) : [];
  let selection = selected.length ? {x: Math.min(...selected), width: Math.max(...selected) - Math.min(...selected) + 1} : null;
  let position = placement, fellBack = false;
  if (!selection && (position === 'BeforeSelection' || position === 'AfterSelection' || position === 'ReplaceSelection')) { position = 'LastColumn'; fellBack = true; }
  // Cells moved, cleared or written so far, per column, so later frames see the sheet as it will be.
  const moved = new Map();   // col -> Map(row -> {text, kind}); text '' = cleared
  const movedCol = c => { let m = moved.get(c); if (!m) moved.set(c, m = new Map()); return m; };
  const at = (c, r) => moved.get(c)?.get(r) ?? {text: store.get(c, r), kind: store.kind(c, r)};
  const rowsOf = c => {   // rows holding a cell in column c after the edits so far
    const rows = new Set(); const col = store.cols[c];
    if (col) col.forEach(r => rows.add(r));
    for (const r of moved.get(c)?.keys() ?? []) rows.add(r);
    return [...rows].filter(r => at(c, r).text !== '').sort((a, b) => a - b);
  };
  const usedEnd = () => {   // one past the last column holding any cell or formula after the edits so far
    let end = 0;
    store.cols.forEach((col, c) => { if (col && (col.count > 0 || col.formula.size > 0) && c + 1 > end) end = c + 1; });
    for (const [c, cells] of moved) if (c + 1 > end && [...cells.values()].some(cell => cell.text !== '')) end = c + 1;
    return end;
  };
  frames.forEach((frame, index) => {
    const count = Number(frame.columns) || 0;
    if (count <= 0) return;   // an empty frame writes nothing, as on Windows
    const lengths = Array.isArray(frame.lengths) ? frame.lengths : Array.from({length: count}, () => Math.max(0, (Number(frame.rows) || 1) - 1));
    const missing = typeof frame.missingIndicator === 'string' ? frame.missingIndicator : '*';
    const cell = new Map(); for (const c of frame.cells ?? []) cell.set(`${c.col},${c.row}`, {text: String(c.text ?? ''), kind: typeof c.kind === 'string' ? c.kind : undefined});   // no kind: the store derives it from the text
    const titled = Array.from({length: count}, (_, v) => cell.has(`${v},0`)).some(Boolean);
    // Windows selects a written frame and chains the next one after it, unless that frame's own
    // step replaces the selection (never the position the user chose for the first frame).
    const here = index === 0 ? position : frame.placement === 'ReplaceSelection' ? 'ReplaceSelection' : 'AfterSelection';
    let first, shift = false;
    switch (here) {
      case 'FirstColumn': first = 0; shift = true; break;
      case 'BeforeSelection': first = selection.x; shift = true; break;
      case 'AfterSelection': first = selection.x + selection.width; shift = true; break;
      case 'ReplaceSelection': first = selection.x; break;
      default: first = usedEnd();
    }
    const end = usedEnd();
    if (shift && first >= end) shift = false;   // nothing to the right to move
    if ((shift ? end : Math.max(end, first)) + count > MAX_COLS) throw new Error('No room to write output data on the sheet.');
    if (shift) {
      if (options.backed) throw new Error('Columns cannot be inserted into a workbook opened from a file: its cell formats and formulas would not move with the values. Write the results after the last column, in place of the selected columns, or into a new document.');
      if (options.formulaCount > 0 || store.cols.some(col => col && col.formula.size > 0)) throw new Error('Columns cannot be inserted into a worksheet with formulas, which Excel would need to re-reference. Write the results after the last column or into a new document.');
      // Move columns right by `count`, from the rightmost, so each cell is cleared before its new content lands.
      for (let c = end - 1; c >= first; c--) for (const r of rowsOf(c)) {
        const moving = at(c, r);
        edits.push([c + count, r, moving.text, moving.kind], [c, r, '']); movedCol(c + count).set(r, moving); movedCol(c).set(r, BLANK);
      }
    } else if (here === 'ReplaceSelection') {
      for (let c = first; c < first + count; c++) {
        if (store.cols[c]?.formula.size > 0) throw new Error('The selected columns hold formulas, which are read-only here. Write the results elsewhere.');
        for (const r of rowsOf(c)) { edits.push([c, r, '']); movedCol(c).set(r, BLANK); }
      }
    }
    // Values go beside the analysis rows when the output has one value per input row, otherwise from
    // the first data row. A frame without titles (a rotated block) starts in the title row, as on Windows.
    const length = Math.max(0, ...lengths);
    const inputRows = range && Number.isInteger(range.firstRow) && Number.isInteger(range.lastRow) ? range.lastRow - range.firstRow + 1 : 0;
    const top = !titled ? 0 : inputRows > 0 && inputRows === length && range.firstRow >= (header ? 2 : 1) ? range.firstRow - 1 : header ? 1 : 0;
    if (top + length > MAX_ROWS) throw new Error('This exceeds the Excel worksheet dimensions.');
    for (let v = 0; v < count; v++) {
      const c = first + v, title = cell.get(`${v},0`);
      if (header && titled && title) { edits.push([c, 0, title.text, 'text']); movedCol(c).set(0, {text: title.text, kind: 'text'}); }
      for (let r = 0; r < (lengths[v] ?? 0); r++) {
        const got = cell.get(`${v},${r + 1}`), text = got ? got.text : missing, kind = got ? got.kind : 'text';   // the missing indicator is text
        edits.push([c, top + r, text, kind]); movedCol(c).set(top + r, {text, kind});
      }
    }
    const y = header && titled ? 0 : top;
    rows = Math.max(rows, top + length); cols = Math.max(cols, first + count);
    written.push({x: first, y, width: count, height: Math.max(1, top + length - y)});
    selection = {x: first, width: count};
  });
  const total = written.reduce((n, w) => n + w.width, 0);
  const message = total === 0 ? 'No columns were written: the analysis produced no data' : `Wrote ${total} column${total === 1 ? '' : 's'} ${fellBack ? LABELS.LastColumn + ' (no columns were selected)' : LABELS[placement]}`;
  return {edits, rows, cols, written, message};
}
