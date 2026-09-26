// Snapshot is sparse; only the chosen columns are materialised for the calculation.
export function worksheetSelection(columns, range) {
  if (columns.length) return {selection:columns};
  if (!range || range.width * range.height <= 1) return {selection:[]};
  return {selection:Array.from({length:range.width},(_,i)=>range.x+i),range:{first:range.y+1,last:range.y+range.height}};
}
export function worksheetRows(source, selected, requiredLength) {
  const first=Math.max(source?.firstRow??1,source?.range?.first??1);
  if (requiredLength) return {first,last:first+requiredLength-1};
  if (source?.range) return {first,last:Math.max(first,Math.min(source.rows,source.range.last))};
  const columns=new Set(selected);
  const last=(source?.cells??[]).filter(c=>columns.has(c.col) && c.row>=first-1 && (String(c.text??'').trim()!=='' || c.formula))
    .reduce((end,c)=>Math.max(end,c.row+1),first);
  return {first,last};
}
export function worksheetInput(source, selected, first, last) {
  if (!source || !selected.length) throw new Error('Choose at least one column.');
  if (new Set(selected).size !== selected.length) throw new Error('Choose each column once.');
  if (!Number.isInteger(first) || !Number.isInteger(last) || first < source.firstRow || last < first || last > source.rows) throw new Error('Enter a valid first and last worksheet row.');
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
export function screenSelection(source, prompt) {
  if (!prompt.screen || !source?.range || !source.selection?.length) return null;
  const {first,last}=source.range, columns=source.selection;
  const rows=last-first+1;
  if (columns.length<prompt.minColumns || columns.length>prompt.maxColumns ||
      (prompt.fixedRows && rows!==prompt.rows))
    throw new Error(`Select ${prompt.fixedRows?prompt.rows+' rows and ':''}${prompt.minColumns===prompt.maxColumns?prompt.minColumns:prompt.minColumns+'–'+prompt.maxColumns} columns in the worksheet to fill this table. The selection has not been copied.`);
  if (rows*columns.length>1000000) throw new Error('The selected table is too large for this form.');
  const input=worksheetInput(source,columns,first,last);
  return Array.from({length:rows},(_,r)=>input.columns.map(c=>String(c.values[r]??'')));
}
export function initialGrid(prompt, source, initial) {
  const titles=initial?.columns?.map(c=>c.title)??prompt.labels??Array.from({length:Math.max(1,prompt.minColumns)},(_,i)=>`Column ${i+1}`);
  if(initial?.columns) return {titles,matrix:Array.from({length:Math.max(prompt.rows??0,initial.columns[0].values.length)},(_,r)=>initial.columns.map(c=>String(c.values[r]??''))),error:''};
  const blank=Array.from({length:prompt.rows??12},()=>titles.map(()=>''));
  try { const matrix=screenSelection(source,prompt); return {titles:matrix?Array.from({length:matrix[0].length},(_,i)=>titles[i]??`Column ${i+1}`):titles,matrix:matrix??blank,error:''}; }
  catch(e) {return {titles,matrix:blank,error:e.message};}
}
export function enteredInput(matrix, titles, fixedRows=false) {
  let end=matrix.length;
  if(!fixedRows) while(end>0 && matrix[end-1].every(v=>String(v).trim()===''))end--;
  if(!end)throw new Error('Enter data, paste a table, or choose worksheet columns.');
  return {source:'Entered data',preserveRows:true,columns:titles.map((title,c)=>({title,values:matrix.slice(0,end).map(row=>row[c]??'')}))};
}
export function pasteMatrix(matrix, text, col=0, row=0, fixedRows=false, maxColumns=16384) {
  const incoming=String(text).replace(/\r\n?/g,'\n').replace(/\n$/,'').split('\n').map(r=>r.split('\t'));
  const rows=Math.max(matrix.length,row+incoming.length),columns=Math.max(matrix[0]?.length??1,col+Math.max(...incoming.map(r=>r.length)));
  if(columns>maxColumns || fixedRows && rows>matrix.length) throw new Error('The pasted table is larger than this form allows.');
  if(rows*columns>1000000)throw new Error('Use worksheet column selection for more than one million input cells.');
  const next=Array.from({length:rows},(_,r)=>Array.from({length:columns},(_,c)=>matrix[r]?.[c]??''));
  incoming.forEach((r,y)=>r.forEach((v,x)=>next[row+y][col+x]=v));return next;
}
