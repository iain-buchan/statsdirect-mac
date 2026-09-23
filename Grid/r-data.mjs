import { cellKind } from './workbook.mjs';

export function rDataTables(workbook, currentSheet) {
  const sheets = currentSheet === undefined ? workbook.sheets : [workbook.sheets[currentSheet]];
  let size = 0;
  return sheets.map(sheet => {
    const store = sheet.store, start = store.headerRow ? 1 : 0;
    const end = Math.max(store.csvRows, store.usedRows());
    size += Math.max(0, end - start) * store.columns.length;
    if (size > 500000) throw new Error('R data files support at most 500,000 cells in this prototype.');
    const columns = store.columns.map((_, c) => {
      const values = Array.from({length: Math.max(0, end - start)}, (_, i) => {
        const r = i + start, text = store.get(c, r), original = store.metadata.get(`${c},${r}`);
        if (original?.formula && (store.formulasStale || text === '')) throw new Error('Recalculate formula results in Excel before saving this table as R data.');
        return {text, kind: cellKind(store, c, r), missing: original?.text === text && original?.rMissing === true,
          raw: original?.text === text ? original?.rRaw ?? '' : ''};
      });
      const kinds = new Set(values.filter(v => v.text !== '').map(v => v.kind));
      const inferred = kinds.size === 1 && kinds.has('number') ? 'double' : kinds.size === 1 && kinds.has('boolean') ? 'logical'
        : kinds.size === 1 && kinds.has('datetime') ? (values.some(v => /[ T]\d\d:/.test(v.text)) ? 'POSIXct' : 'Date') : 'character';
      const metadata = store.headerRow ? sheet.rColumns?.[c] : undefined;
      const type = metadata?.type ?? inferred;
      return {name: store.columnTitle(c), type, levels: metadata?.levels ?? [], ordered: metadata?.ordered ?? false, tzone: metadata?.tzone ?? 'UTC',
        values: values.map(v => ({text: v.text, missing: v.missing || (v.text === '' && type !== 'character' && type !== 'factor'), raw: v.raw}))};
    });
    return {name: sheet.rObjectName ?? sheet.name, shape: sheet.rObjectType ?? 'data.frame', rowNames: sheet.rRowNames ?? [], columns};
  });
}
