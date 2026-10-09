import {MAX_ROWS, MAX_COLS} from './store.mjs';
// Plan against column identities. Inserting a column moves its data and metadata together;
// only analysis output and explicit replacements become cell edits.
export const PLACEMENTS = ['FirstColumn', 'BeforeSelection', 'ReplaceSelection', 'AfterSelection', 'LastColumn'];
const LABELS = {FirstColumn: 'as the first columns', BeforeSelection: 'before the selected columns', ReplaceSelection: 'in place of the selected columns', AfterSelection: 'after the selected columns', LastColumn: 'after the last used column'};
const BLANK = {text: '', kind: 'blank'};
// Plans the edits for `frames` (engine output frames: {columns, cells:[{col,row,text,kind}], lengths, missingIndicator, placement})
// in `store` at `placement`, relative to the analysis input `range` ({firstRow, lastRow, columns}).
// Returns {edits:[[col,row,text,kind]], rows, cols, written:[{x,y,width,height}], message}; the caller applies the edits as one undo step.
export function planWriteBack(store, frames, placement, range, options = {}) {
  if (!Array.isArray(frames) || !frames.length) throw new Error('There is no data to write.');
  if (!PLACEMENTS.includes(placement)) throw new Error('Unknown write position.');
  const edits = [], written = [], inserts = [];
  const header = !!store.headerRow;
  let rows = store.rows, cols = store.columns.length;
  // The selected columns of the analysis input, as the Windows grid uses its current selection.
  const selected = Array.isArray(range?.columns) ? range.columns.filter(c => Number.isInteger(c) && c >= 0 && c < MAX_COLS) : [];
  let selection = selected.length ? {x: Math.min(...selected), width: Math.max(...selected) - Math.min(...selected) + 1} : null;
  let position = placement, fellBack = false;
  if (!selection && (position === 'BeforeSelection' || position === 'AfterSelection' || position === 'ReplaceSelection')) { position = 'LastColumn'; fellBack = true; }
  const virtual = store.cols.map(source => ({source, edits: new Map()}));
  const column = c => { while (virtual.length <= c) virtual.push({source: null, edits: new Map()}); return virtual[c]; };
  const movedCol = c => column(c).edits;
  const at = (c, r) => column(c).edits.get(r) ?? {text: column(c).source?.get(r) ?? ''};
  const rowsOf = c => {
    const rows = new Set(); column(c).source?.forEach(r => rows.add(r));
    for (const r of column(c).edits.keys()) rows.add(r);
    return [...rows].filter(r => at(c, r).text !== '').sort((a,b) => a-b);
  };
  const usedEnd = () => {
    let end = 0;
    virtual.forEach((col,c) => { if (col.source?.count || col.source?.formula.size || col.source?.extra.size || col.source?.rMetadata || col.source?.displayWidth || [...col.edits.values()].some(v => v.text !== '')) end = c+1; });
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
    if (shift && first >= end && !options.backed) shift = false;   // nothing to the right to move
    if ((shift ? Math.max(end + count, first + count) : Math.max(end, first + count)) > MAX_COLS) throw new Error('No room to write output data on the sheet.');
    if (shift) {
      inserts.push({col: first, count});
      column(first);
      virtual.splice(first, 0, ...Array.from({length: count}, () => ({source: null, edits: new Map()})));
      cols = Math.min(MAX_COLS, Math.max(cols + count, end + count));
      for (const previous of written) if (previous.x >= first) previous.x += count;
    } else if (here === 'ReplaceSelection') {
      for (let c = first; c < first + count; c++) {
        if (column(c).source?.formula.size > 0) throw new Error('The selected columns hold formulas, which are read-only here. Write the results elsewhere.');
        for (const r of rowsOf(c)) { movedCol(c).set(r, BLANK); }
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
      if (header && titled && title) { movedCol(c).set(0, {text: title.text, kind: 'text'}); }
      for (let r = 0; r < (lengths[v] ?? 0); r++) {
        const got = cell.get(`${v},${r + 1}`), text = got ? got.text : missing, kind = got ? got.kind : 'text';   // the missing indicator is text
        movedCol(c).set(top + r, {text, kind});
      }
    }
    const y = header && titled ? 0 : top;
    rows = Math.max(rows, top + length); cols = Math.max(cols, first + count);
    written.push({x: first, y, width: count, height: Math.max(1, top + length - y)});
    selection = {x: first, width: count};
  });
  const total = written.reduce((n, w) => n + w.width, 0);
  const message = total === 0 ? 'No columns were written: the analysis produced no data' : `Wrote ${total} column${total === 1 ? '' : 's'} ${fellBack ? LABELS.LastColumn + ' (no columns were selected)' : LABELS[placement]}`;
  virtual.forEach((col,c) => { for (const [r, cell] of col.edits) edits.push([c,r,cell.text,cell.kind]); });
  return {edits, rows, cols, written, inserts, message};
}
