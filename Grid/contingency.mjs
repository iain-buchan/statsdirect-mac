import { parseDelimited } from './store.mjs';
export const example = {
  counts: [['17','9','8'],['6','5','1'],['3','5','4'],['1','2','5']],
  rowLabels: ['Grief I','Grief II','Grief III','Grief IV'],
  columnLabels: ['Good support','Adequate support','Poor support']
};
export function dimensions(rows, cols) {
  if (!Number.isInteger(rows) || !Number.isInteger(cols) || rows < 2 || cols < 2 || rows > 200 || cols > 200 || rows * cols > 2500)
    throw new Error('Use 2–200 rows and columns, with at most 2,500 cells in this prototype.');
}
export function validate(state) {
  const rows = state.counts.length, cols = state.counts[0]?.length ?? 0;
  dimensions(rows, cols);
  const values = state.counts.map((row, r) => {
    if (row.length !== cols) throw new Error('Every row must have the same number of counts.');
    return row.map((text, c) => {
      const value = Number(text);
      if (String(text).trim() === '' || !Number.isSafeInteger(value) || value < 0 || value > 1e9)
        throw new Error(`Row ${r+1}, column ${c+1}: enter a non-negative whole count (0 for an empty cell).`);
      return value;
    });
  });
  if (values.some(row => row.reduce((a,b) => a+b, 0) === 0) || values[0].some((_, c) => values.every(row => row[c] === 0)))
    throw new Error('Every row and column must have a positive total. Remove unused categories.');
  if (values.flat().reduce((a,b) => a+b, 0) > 1e9) throw new Error('The total count must not exceed 1,000,000,000.');
  return { counts: values, rowLabels: state.rowLabels, columnLabels: state.columnLabels };
}
export class ContingencyTable {
  constructor() { this.state = { counts: [['',''],['','']], rowLabels: ['Row 1','Row 2'], columnLabels: ['Column 1','Column 2'] }; this.undoStack = []; this.redoStack = []; }
  change(edit) {
    const next = structuredClone(this.state); edit(next);
    dimensions(next.counts.length, next.counts[0].length);
    if (JSON.stringify(next) === JSON.stringify(this.state)) return;
    this.undoStack.push(this.state); if (this.undoStack.length > 100) this.undoStack.shift();
    this.state = next; this.redoStack = [];
  }
  resize(rows, cols) {
    dimensions(rows, cols);
    this.change(s => {
      s.counts = Array.from({length:rows}, (_,r) => Array.from({length:cols}, (_,c) => s.counts[r]?.[c] ?? ''));
      s.rowLabels = Array.from({length:rows}, (_,r) => s.rowLabels[r] ?? `Row ${r+1}`);
      s.columnLabels = Array.from({length:cols}, (_,c) => s.columnLabels[c] ?? `Column ${c+1}`);
    });
  }
  paste(col, row, text) { this.pasteValues(col, row, parseDelimited(text, text.includes('\t') ? '\t' : ',')); }
  pasteValues(col, row, values) {
    if (!values.length || col < 0 || row < 0) return;
    const rows = Math.max(this.state.counts.length, row + values.length), cols = Math.max(this.state.counts[0].length, col + Math.max(...values.map(v=>v.length)));
    dimensions(rows, cols);
    this.change(s => {
      s.counts = Array.from({length:rows}, (_,r) => Array.from({length:cols}, (_,c) => s.counts[r]?.[c] ?? ''));
      s.rowLabels = Array.from({length:rows}, (_,r) => s.rowLabels[r] ?? `Row ${r+1}`);
      s.columnLabels = Array.from({length:cols}, (_,c) => s.columnLabels[c] ?? `Column ${c+1}`);
      values.forEach((line,r) => line.forEach((v,c) => s.counts[row+r][col+c] = String(v).trim()));
    });
  }
  undo() { if (this.undoStack.length) { this.redoStack.push(this.state); this.state = this.undoStack.pop(); } }
  redo() { if (this.redoStack.length) { this.undoStack.push(this.state); this.state = this.redoStack.pop(); } }
  csv() {
    const quote = value => '"' + String(value).replaceAll('"','""') + '"';
    return [['',...this.state.columnLabels], ...this.state.counts.map((row,r) => [this.state.rowLabels[r], ...row])].map(row => row.map(quote).join(',')).join('\r\n')+'\r\n';
  }
}
