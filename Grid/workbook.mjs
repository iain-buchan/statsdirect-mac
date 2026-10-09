import { GridStore, columnName, kindIndex } from './store.mjs';
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
      // A sheet carries typed `columnar` records (decoded from a snapshot file), per-column
      // `batches` from the CSV loader, per-cell `cells`, or a combination.
      if (sheet.columnar) store.setLoadedColumns(sheet.columnar);
      if (sheet.batches) store.setLoadedBatches(sheet.batches, sheet.kindOf ?? (() => 'text'));
      if (sheet.cells?.length || !(sheet.columnar || sheet.batches)) store.setLoaded(sheet.cells ?? []);
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
        rColumns: sheet.rColumns, rRowNames: sheet.rRowNames, rRowNamesType: sheet.rRowNamesType, rObjectName: sheet.rObjectName, rObjectType: sheet.rObjectType,
        name: sheet.name,
        hidden: sheet.hidden,
        store
      };
    });
    if (!sheets.length) throw new Error('The workbook contains no worksheets.');
    this.sheets = sheets;
    this.name = workbook.name;
    this.imported = true;
    this.backed = !!workbook.id && !workbook.dataCopy;
    this.importNotice = workbook.importNotice ?? '';
    this.formulaCount = workbook.formulaCount;
    this.edited = false;
    return Math.max(0, sheets.findIndex(s => !s.hidden));
  }
  changed() {
    this.edited = true;
    for (const sheet of this.sheets) sheet.store.formulasStale = true;
  }
  // Visits the cells a save must write, as (sheetIndex, col, row, text, kind). For a workbook
  // backed by a file: loaded cells edited since loading (including those now blank), then
  // cells never in the file. Otherwise every populated cell, with a new worksheet's column
  // titles as row 0 and its data shifted down one row.
  exportCells(visit) {
    this.sheets.forEach(({store}, sheetIndex) => {
      if (!this.imported) store.columns.forEach((text, col) => visit(sheetIndex, col, 0, text, 'text'));
      const push = (col, row, text) => visit(sheetIndex, col, this.imported ? row : row + 1, text, store.kind(col, row));
      if (this.imported && this.backed) {
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
    });
  }
  export() {
    const sheets = this.sheets.map(({name}) => ({name, cells: []}));
    this.exportCells((s, col, row, text, kind) => sheets[s].cells.push({col, row, text, kind}));
    return {sheets};
  }
  // The same cells as typed column records per sheet, for snapshot.mjs encodeSnapshot.
  exportColumns() {
    const sheets = this.sheets.map(({name, store}) => ({name, store, columns: new Map()}));
    this.exportCells((s, col, row, text, kind) => {
      const sheet = sheets[s];
      let b = sheet.columns.get(col);
      if (!b) sheet.columns.set(col, b = {col, rows: [], kinds: [], nums: [], texts: new Map(), formulas: new Map()});
      const i = b.rows.length, k = kindIndex(kind);
      b.rows.push(row); b.kinds.push(text === '' ? 0 : k);
      const n = kind === 'number' ? Number(text) : NaN;
      b.nums.push(n); if (text !== '' && Number.isNaN(n)) b.texts.set(i, text);
    });
    return {sheets: sheets.map(({name, store, columns}) => ({name, columns: [...columns.values()].sort((a, b) => a.col - b.col), inserts: store.inserts.map(i => ({col: i.col, count: i.count}))}))};
  }
}
