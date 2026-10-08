import { GridStore, columnName } from './store.mjs';
// The kind rules live in the store now; this wrapper keeps the old call sites working.
export function cellKind(store, c, r) {
  return store.kind(c, r);
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
  // A sheet carries either `cells` ({col,row,text,kind,formula,...}) or per-column `batches`
  // ({col, rows, nums, texts}) with a `kindOf(text)` function, as produced by the CSV loader.
  load(workbook) {
    const sheets = workbook.sheets.map(sheet => {
      const store = new GridStore();
      store.columns = Array.from({
        length: Math.max(1, sheet.columns)
      }, (_, c) => columnName(c));
      store.rows = Math.max(100, sheet.rows);
      store.excelRows = true;
      store.csvRows = sheet.csvRows ?? 0;
      if (sheet.batches) store.setLoadedBatches(sheet.batches, sheet.kindOf ?? (() => 'text'));
      else store.setLoaded(sheet.cells);
      let headerRow = sheet.headerRow;
      if (headerRow === undefined) {
        let any = false, all = true;
        for (let c = 0; c < store.columns.length; c++) {
          if (store.get(c, 0) === '') continue;
          any = true;
          if (store.kind(c, 0) !== 'text' || store.formula(c, 0)) all = false;
        }
        headerRow = any && all;
      }
      store.headerRow = headerRow;
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
        const push = (col, row, text) => cells.push({
          col,
          row: this.imported ? row : row + 1,
          text,
          kind: store.kind(col, row)
        });
        if (this.imported && this.backed) {
          // Only what differs from the file: loaded cells edited since loading (including
          // those now blank), then cells that were never in the file.
          for (const [key, original] of store.originals) {
            const [col, row] = key.split(',').map(Number), text = store.get(col, row);
            if (text !== original.text) push(col, row, text);
          }
          store.forEachCell((col, row, text) => {
            if (text !== '' && !store.loaded(col, row)) push(col, row, text);
          });
        } else store.forEachCell((col, row, text) => {
          if (text !== '') push(col, row, text);
        });
        return {
          name,
          cells
        };
      })
    };
  }
}
