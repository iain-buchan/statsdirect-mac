import { kindIndex } from './store.mjs';

// Tables for R data files. For each sheet: a manifest (object name and shape, row names,
// and each column's name, type, factor levels, ordering and time zone) and typed column
// records for snapshot.mjs holding every data row's text or number, with `extras` carrying
// the R markers of cells loaded from an R file and not edited since: `rMissing` (an NA, as
// distinct from an empty string) and `rRaw` (the original Date or time number when its
// formatted text does not reproduce it exactly). The application turns the snapshot into
// R's bulk exchange files; nothing is serialised per cell, so a table of Excel's full
// height costs only its data.
export function rDataTables(workbook, currentSheet) {
  const sheets = currentSheet === undefined ? workbook.sheets : [workbook.sheets[currentSheet]];
  const tables = [], records = [];
  for (const sheet of sheets) {
    const store = sheet.store, start = store.headerRow ? 1 : 0;
    const end = Math.max(store.csvRows, store.usedRows());
    const n = Math.max(0, end - start);
    const columns = [], data = [];
    store.columns.forEach((_, c) => {
      const col = store.cols[c], markers = (col?.extra.size ?? 0) > 0;
      const rows = new Uint32Array(n), kinds = new Uint8Array(n), nums = new Float64Array(n), texts = new Map(), extras = new Map();
      const seen = new Set(); let hasTime = false;
      for (let i = 0; i < n; i++) {
        const r = i + start, text = store.get(c, r), kind = store.kind(c, r);
        if (store.formula(c, r) && (store.formulasStale || text === '')) throw new Error('Recalculate formula results in Excel before saving this table as R data.');
        rows[i] = i;
        const k = text === '' ? 0 : kindIndex(kind);
        kinds[i] = k;
        const num = k === 1 ? col.numAt(r) : NaN;
        nums[i] = num;
        if (text !== '' && Number.isNaN(num)) texts.set(i, text);
        if (text !== '') { seen.add(kind); if (kind === 'datetime' && /[ T]\d\d:/.test(text)) hasTime = true; }
        if (markers) {
          const original = store.loaded(c, r);
          if (original && original.text === text && (original.rMissing === true || original.rRaw)) {
            const extra = {};
            if (original.rMissing === true) extra.rMissing = true;
            if (original.rRaw) extra.rRaw = original.rRaw;
            extras.set(i, JSON.stringify(extra));
          }
        }
      }
      const inferred = seen.size === 1 && seen.has('number') ? 'double' : seen.size === 1 && seen.has('boolean') ? 'logical'
        : seen.size === 1 && seen.has('datetime') ? (hasTime ? 'POSIXct' : 'Date') : 'character';
      const metadata = store.headerRow ? col?.rMetadata : undefined;
      columns.push({name: store.columnTitle(c), type: metadata?.type ?? inferred, levels: metadata?.levels ?? [], naLevel: metadata?.naLevel ?? false, ordered: metadata?.ordered ?? false, tzone: metadata?.tzone ?? 'UTC'});
      data.push({col: c, rows, kinds, nums, texts, formulas: new Map(), extras});
    });
    tables.push({name: sheet.rObjectName ?? sheet.name, shape: sheet.rObjectType ?? 'data.frame', rowNames: sheet.rRowNames ?? [], rowNamesType: sheet.rRowNamesType ?? 'character', rows: n, columns});
    records.push({name: sheet.name, columns: data});
  }
  return {tables, sheets: records};
}
