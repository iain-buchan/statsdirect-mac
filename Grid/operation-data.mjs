import {MAX_ROWS, MAX_COLS} from './store.mjs';
// Snapshot is sparse; only the chosen columns are materialised for the calculation.
export function worksheetSelection(columns, range) {
  if (columns.length) return {selection:columns};
  if (!range) return {selection:[]};
  return {selection:Array.from({length:range.width},(_,i)=>range.x+i),range:{first:range.y+1,last:range.y+range.height}};
}
export function worksheetRows(source, selected, requiredLength) {
  const first=Math.max(source?.firstRow??1,source?.range?.first??1);
  if (requiredLength) return {first,last:first+requiredLength-1};
  if (source?.range) return {first,last:Math.max(first,Math.min(source.rows,source.range.last))};
  if (source?.columnEnds) return {first,last:selected.reduce((end,c)=>Math.max(end,source.columnEnds[c]??0),first)};
  const columns=new Set(selected);
  const last=(source?.cells??[]).filter(c=>columns.has(c.col) && c.row>=first-1 && (String(c.text??'').trim()!=='' || c.formula))
    .reduce((end,c)=>Math.max(end,c.row+1),first);
  return {first,last};
}
// A snapshot with `cells` is read here. A lazy source (metadata of a live worksheet) yields a
// request that the form sends to the worksheet; worksheetInputFrom builds the input from the
// values that come back.
export function worksheetInput(source, selected, first, last) {
  if (!source || !selected.length) throw new Error('Choose at least one column.');
  if (new Set(selected).size !== selected.length) throw new Error('Choose each column once.');
  if (!Number.isInteger(first) || !Number.isInteger(last) || first < source.firstRow || last < first || last > source.rows) throw new Error('Enter a valid first and last worksheet row.');
  selected.forEach(col=>{ if (!source.columns[col]) throw new Error('That column is no longer available. Refresh the worksheet.'); });
  if (source.lazy) return {lazy:true, request:{sheet:source.sheet, sheetName:source.sheetName, columns:selected, first, last}, source:source.name+` · rows ${first}–${last}`, titles:selected.map(col=>source.columns[col])};
  const indices = new Set(selected), cells = source.cells.filter(c=>indices.has(c.col) && c.row >= first-1 && c.row < last);
  if (cells.some(c=>c.kind==='error')) throw new Error('The selection contains Excel errors. Correct them in Excel and reopen the workbook.');
  if (cells.some(c=>c.formula && (source.formulasStale || !c.text))) throw new Error('Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.');
  return {source:source.name+` · rows ${first}–${last}`, range:{firstRow:first,lastRow:last,columns:selected}, preserveRows:true, columns:selected.map(col=>{
    if (!source.columns[col]) throw new Error('That column is no longer available. Refresh the worksheet.');
    const values = Array.from({length:last-first+1},()=> '');
    cells.filter(c=>c.col===col).forEach(c=>values[c.row-first+1]=c.text);
    return {title:source.columns[col],values};
  })};
}
// Screen forms take an explicitly highlighted rectangle, never a cropped larger selection.
export function screenInput(source, prompt) {
  if (!prompt.screen || !source?.range || !source.selection?.length) return null;
  const {first,last}=source.range, columns=source.selection;
  const rows=last-first+1;
  if (columns.length<prompt.minColumns || columns.length>prompt.maxColumns ||
      (prompt.fixedRows && rows!==prompt.rows))
    throw new Error(`Select ${prompt.fixedRows?prompt.rows+' rows and ':''}${prompt.minColumns===prompt.maxColumns?prompt.minColumns:prompt.minColumns+'–'+prompt.maxColumns} columns in the worksheet to fill this table. The selection has not been copied.`);
  if (rows>MAX_ROWS || columns.length>MAX_COLS) throw new Error('This exceeds the Excel worksheet dimensions.');
  if (source.lazy) {
    if (source.screenError) throw new Error(source.screenError);
    if (source.screenDeferred) return worksheetInput(source,columns,first,last);
    if (!source.screen) throw new Error('The highlighted worksheet range is not available. Refresh the worksheet.');
    return {columns:columns.map((c,i)=>({title:source.columns[c],values:source.screen.map(row=>String(row[i]??''))}))};
  }
  return worksheetInput(source,columns,first,last);
}
// The dedicated contingency form uses small, synchronous tables.
export function screenSelection(source, prompt) {
  const input=screenInput(source,prompt);
  if (!input) return null;
  if (input.lazy) throw new Error('The selected rectangle is too large for this contingency table.');
  return Array.from({length:input.columns[0].values.length},(_,r)=>input.columns.map(c=>String(c.values[r]??'')));
}
// Builds the input from the values a lazy request returned ({columns:[{title,values}], errors, uncached}).
export function worksheetInputFrom(pending, data) {
  if (!data || !Array.isArray(data.columns)) throw new Error('The worksheet did not return the selected columns. Refresh the worksheet.');
  if (data.errors > 0) throw new Error('The selection contains Excel errors. Correct them in Excel and reopen the workbook.');
  if (data.uncached > 0) throw new Error('Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.');
  const {columns, first, last} = pending.request;
  return {source:pending.source, range:{firstRow:first,lastRow:last,columns}, preserveRows:true, columns:data.columns.map(c=>({title:c.title,values:c.values.map(v=>v??'')}))};
}
