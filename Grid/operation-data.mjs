// Snapshot is sparse; only the chosen columns are materialised for the calculation.
export function worksheetInput(source, selected, first, last) {
  if (!source || !selected.length) throw new Error('Choose at least one column.');
  if (new Set(selected).size !== selected.length) throw new Error('Choose each column once.');
  if (!Number.isInteger(first) || !Number.isInteger(last) || first < source.firstRow || last < first || last > source.rows) throw new Error('Enter a valid first and last worksheet row.');
  const indices = new Set(selected), cells = source.cells.filter(c=>indices.has(c.col) && c.row >= first-1 && c.row < last);
  if (cells.some(c=>c.kind==='error')) throw new Error('The selection contains Excel errors. Correct them in Excel and reopen the workbook.');
  if (cells.some(c=>c.formula && (source.formulasStale || !c.text))) throw new Error('Recalculate and save this workbook in Excel, then reopen it before analysing formula cells.');
  return {source:source.name+` · rows ${first}–${last}`, columns:selected.map(col=>{
    if (!source.columns[col]) throw new Error('That column is no longer available. Refresh the worksheet.');
    const values = Array.from({length:last-first+1},()=> '');
    cells.filter(c=>c.col===col).forEach(c=>values[c.row-first+1]=c.text);
    // Preserve row alignment across separate variable-selection steps.
    if (values.at(-1)==='') values[values.length-1]='*';
    return {title:source.columns[col],values};
  })};
}
export function enteredInput(matrix, titles, fixedRows=false) {
  let end=matrix.length;
  if(!fixedRows) while(end>0 && matrix[end-1].every(v=>String(v).trim()===''))end--;
  if(!end)throw new Error('Enter data, paste a table, or choose worksheet columns.');
  return {source:'Entered data',columns:titles.map((title,c)=>({title,values:matrix.slice(0,end).map(row=>row[c]??'')}))};
}
export function pasteMatrix(matrix, text, col=0, row=0, fixedRows=false, maxColumns=16384) {
  const incoming=String(text).replace(/\r\n?/g,'\n').replace(/\n$/,'').split('\n').map(r=>r.split('\t'));
  const rows=Math.max(matrix.length,row+incoming.length),columns=Math.max(matrix[0]?.length??1,col+Math.max(...incoming.map(r=>r.length)));
  if(columns>maxColumns || fixedRows && rows>matrix.length) throw new Error('The pasted table is larger than this form allows.');
  if(rows*columns>1000000)throw new Error('Use worksheet column selection for more than one million input cells.');
  const next=Array.from({length:rows},(_,r)=>Array.from({length:columns},(_,c)=>matrix[r]?.[c]??''));
  incoming.forEach((r,y)=>r.forEach((v,x)=>next[row+y][col+x]=v));return next;
}
