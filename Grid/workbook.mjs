import { GridStore, columnName, numeric } from './store.mjs';
export function cellKind(store, c, r) {
  const text = store.get(c, r),
    original = store.metadata.get(`${c},${r}`);
  if (original?.text === text) return original.kind;
  if (text === '') return 'blank';
  // Preserve explicitly typed identifiers such as "0012", even after editing.
  if (original?.kind === 'text') return 'text';
  if (original?.kind === 'datetime' && /^\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?$/.test(text)) return 'datetime';
  if (original?.kind === 'timespan' && /^-?(?:\d+\.)?\d{2}:\d{2}:\d{2}(?:\.\d+)?$/.test(text)) return 'timespan';
  if (original?.kind === 'boolean' && /^(true|false)$/i.test(text)) return 'boolean';
  try {
    if (numeric(text) !== null && !/^[+-]?0\d/.test(text.trim())) return 'number';
  } catch {}
  return 'text';
}
export class WorkbookStore {
  constructor(example) {
    this.name = 'PEFR data';
    this.sheets = [{
      name: 'PEFR',
      hidden: false,
      store: new GridStore(example)
    }];
    this.imported = false;
    this.formulaCount = 0;
    this.edited = false;
    if (!example) this.load({name: 'Untitled', formulaCount: 0, sheets: [{name: 'Sheet 1', columns: 8, rows: 100, headerRow: false, cells: []}]});
  }
  load(workbook) {
    const sheets = workbook.sheets.map(sheet => {
      const store = new GridStore();
      store.columns = Array.from({
        length: Math.max(1, sheet.columns)
      }, (_, c) => columnName(c));
      store.rows = Math.max(100, sheet.rows);
      store.excelRows = true;
      store.csvRows = sheet.csvRows ?? 0;
      for (const cell of sheet.cells) {
        const key = `${cell.col},${cell.row}`;
        if (cell.text !== '') store.cells.set(key, cell.text);
        store.metadata.set(key, cell);
      }
      const first = sheet.cells.filter(c => c.row === 0 && c.text !== '');
      store.headerRow = sheet.headerRow ?? (first.length > 0 && first.every(c => c.kind === 'text' && !c.formula));
      return {
        rColumns: sheet.rColumns, rRowNames: sheet.rRowNames, rObjectName: sheet.rObjectName, rObjectType: sheet.rObjectType,
        name: sheet.name,
        hidden: sheet.hidden,
        store
      };
    });
    if (!sheets.length) throw new Error('The workbook contains no worksheets.');
    this.sheets = sheets;
    this.name = workbook.name;
    this.imported = true;
    this.backed = !!workbook.id;
    this.formulaCount = workbook.formulaCount;
    this.edited = false;
    return Math.max(0, sheets.findIndex(s => !s.hidden));
  }
  changed() {
    this.edited = true;
    for (const sheet of this.sheets) sheet.store.formulasStale = true;
  }
  export() {
    return {
      sheets: this.sheets.map(({
        name,
        store
      }) => {
        const cells = [];
        if (!this.imported) store.columns.forEach((text, col) => cells.push({
          col,
          row: 0,
          text,
          kind: 'text'
        }));
        for (const key of new Set([...store.cells.keys(), ...store.metadata.keys()])) {
          const [col, row] = key.split(',').map(Number),
            text = store.get(col, row);
          const original = store.metadata.get(key);
          if (this.imported && this.backed && (original?.text ?? '') === text) continue;
          cells.push({
            col,
            row: this.imported ? row : row + 1,
            text,
            kind: cellKind(store, col, row)
          });
        }
        return {
          name,
          cells
        };
      })
    };
  }
}
