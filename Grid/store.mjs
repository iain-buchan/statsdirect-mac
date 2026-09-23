export const MAX_ROWS = 1048576,
  MAX_COLS = 16384;
export function columnName(index) {
  let s = '';
  for (let n = index + 1; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s;
  return s;
}
export function parseDelimited(text, delimiter = '\t') {
  const rows = [];
  let row = [],
    field = '',
    quoted = false;
  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    if (ch === '"') {
      if (quoted && text[i + 1] === '"') {
        field += '"';
        i++;
      } else if (quoted || field === '') quoted = !quoted;else field += ch;
    } else if (!quoted && ch === delimiter) {
      row.push(field);
      field = '';
    } else if (!quoted && (ch === '\n' || ch === '\r')) {
      if (ch === '\r' && text[i + 1] === '\n') i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else field += ch;
  }
  if (quoted) throw new Error('The pasted text has an unclosed quote.');
  if (field !== '' || row.length) {
    row.push(field);
    rows.push(row);
  }
  return rows;
}
export function numeric(raw) {
  if (raw.trim() === '') return null;
  if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(raw.trim())) throw new Error(`“${raw.slice(0, 30)}” is not a number.`);
  const n = Number(raw);
  if (!Number.isFinite(n)) throw new Error('Numbers must be finite.');
  return n;
}
export class GridStore {
  constructor(example) {
    this.columns = ['PEFR Before', 'PEFR After', 'Variable C', 'Variable D', 'Variable E', 'Notes'];
    this.rows = 100;
    this.cells = new Map();
    this.undoStack = [];
    this.redoStack = [];
    if (example) {
      example.before.forEach((v, r) => this.cells.set(`0,${r}`, String(v)));
      example.after.forEach((v, r) => this.cells.set(`1,${r}`, String(v)));
    }
  }
  get(c, r) {
    return this.cells.get(`${c},${r}`) ?? '';
  }
  usedRows() {
    let end = 0;
    for (const k of this.cells.keys()) end = Math.max(end, Number(k.split(',')[1]) + 1);
    return end;
  }
  apply(edits, rows = this.rows, cols = this.columns.length) {
    if (rows > MAX_ROWS || cols > MAX_COLS) throw new Error('This exceeds the Excel worksheet dimensions.');
    if (edits.length > 100000) throw new Error('Paste at most 100,000 cells at a time in this prototype.');
    const changes = [];
    const seen = new Map();
    for (const [c, r, value] of edits) {
      if (c < 0 || r < 0 || c >= MAX_COLS || r >= MAX_ROWS) throw new Error('Cell is outside the worksheet.');
      seen.set(`${c},${r}`, String(value));
      rows = Math.max(rows, r + 1);
      cols = Math.max(cols, c + 1);
    }
    for (const [key, after] of seen) {
      const before = this.cells.get(key) ?? '';
      if (before !== after) changes.push({
        key,
        before,
        after
      });
    }
    if (!changes.length && rows === this.rows && cols === this.columns.length) return false;
    const step = {
      changes,
      oldRows: this.rows,
      newRows: rows,
      oldCols: this.columns.length,
      newCols: cols
    };
    this.replay(step, true);
    this.undoStack.push(step);
    if (this.undoStack.length > 50) this.undoStack.shift();
    this.redoStack = [];
    return true;
  }
  replay(step, forward) {
    for (const change of step.changes) {
      const value = forward ? change.after : change.before;
      if (value === '') this.cells.delete(change.key);else this.cells.set(change.key, value);
    }
    this.rows = forward ? step.newRows : step.oldRows;
    const cols = forward ? step.newCols : step.oldCols;
    while (this.columns.length < cols) this.columns.push('Variable ' + columnName(this.columns.length));
    this.columns.length = cols;
  }
  undo() {
    const s = this.undoStack.pop();
    if (!s) return false;
    this.replay(s, false);
    this.redoStack.push(s);
    return true;
  }
  redo() {
    const s = this.redoStack.pop();
    if (!s) return false;
    this.replay(s, true);
    this.undoStack.push(s);
    return true;
  }
  paste(c, r, text) {
    const rows = parseDelimited(text);
    const size = rows.reduce((n, x) => n + x.length, 0);
    if (size > 100000) throw new Error('Paste at most 100,000 cells at a time.');
    return this.apply(rows.flatMap((row, y) => row.map((v, x) => [c + x, r + y, v])));
  }
  paired(c1, c2, start = 0, end = this.usedRows()) {
    if (c1 < 0 || c2 < 0 || c1 >= this.columns.length || c2 >= this.columns.length) throw new Error('Choose columns that exist in this worksheet.');
    if (c1 === c2) throw new Error('Choose two different columns.');
    if (end - start > 1000000) throw new Error('This analysis currently accepts at most 1,000,000 rows.');
    const before = [],
      after = [];
    for (let r = start; r < end; r++) {
      try {
        before.push(numeric(this.get(c1, r)));
        after.push(numeric(this.get(c2, r)));
      } catch (e) {
        throw new Error(`Row ${r + 1}: ${e.message} Correct the cell or leave it blank for missing data.`);
      }
    }
    if (before.filter((v, i) => v !== null && after[i] !== null).length < 2) throw new Error('At least two complete numeric pairs are needed.');
    return {
      before,
      after,
      labels: [this.columns[c1], this.columns[c2]],
      range: `${columnName(c1)}${start + 1} and ${columnName(c2)}${start + 1}, ${end - start} rows`
    };
  }
  csv() {
    const quote = s => /[",\r\n]/.test(s) ? '"' + s.replaceAll('"', '""') + '"' : s;
    const rows = [this.columns.map(quote).join(',')];
    const end = this.usedRows();
    for (let r = 0; r < end; r++) rows.push(this.columns.map((_, c) => quote(this.get(c, r))).join(','));
    return rows.join('\r\n') + '\r\n';
  }
}
