import {columnName} from './store.mjs';
import {cellKind} from './workbook.mjs';
import {worksheetSelection} from './operation-data.mjs';

function extent(store) {
  let lastRow=store.headerRow?1:0;const columns=new Set();
  for(const [key,text] of store.cells)if(text!==''){const [c,r]=key.split(',').map(Number);lastRow=Math.max(lastRow,r+1);columns.add(c);}
  return {lastRow,columns:[...columns].sort((a,b)=>a-b)};
}
function selectionFor(store,selection={}) {
  const cols=selection.columns??[],rows=selection.rows??[],range=selection.range;
  const selected=worksheetSelection(cols,range);
  if(rows.length){const ordered=[...rows].sort((a,b)=>a-b);if(ordered.at(-1)-ordered[0]+1!==ordered.length)return {...selected,noncontiguousRows:true};selected.range={first:ordered[0]+1,last:ordered.at(-1)+1};}
  return selected;
}
export function tutorInfo(workbook,sheetIndex,selection={}) {
  return {workbook:workbook.name,activeSheet:sheetIndex,sheets:workbook.sheets.map((sheet,index)=>{
    const bounds=extent(sheet.store),selected=index===sheetIndex?selectionFor(sheet.store,selection):{};
    return {index,name:sheet.name,hidden:!!sheet.hidden,firstDataRow:sheet.store.headerRow?2:1,lastDataRow:bounds.lastRow,columnCount:bounds.columns.length,columns:bounds.columns.slice(0,128).map(c=>({index:c,letter:columnName(c),title:sheet.store.columnTitle(c)})),columnsTruncated:bounds.columns.length>128,...selected};
  })};
}
export function tutorData(workbook,sheetIndex,selection={},options={}) {
  const index=options.sheetIndex??sheetIndex;
  if(!Number.isInteger(index)||index<0||index>=workbook.sheets.length)throw Error('Choose an open worksheet.');
  const sheet=workbook.sheets[index],store=sheet.store;
  if(sheet.hidden)throw Error('Show this worksheet in StatsDirect before using it with the tutor.');
  const bounds=extent(store),selected=index===sheetIndex?selectionFor(store,selection):{};
  if(selected.noncontiguousRows&&options.firstRow===undefined)throw Error('Select one continuous row range, or specify its first and last worksheet rows.');
  const columns=options.columns??(selected.selection?.length?selected.selection:bounds.columns);
  if(!Array.isArray(columns)||!columns.length||columns.length>32||new Set(columns).size!==columns.length||columns.some(c=>!Number.isInteger(c)||c<0||c>=store.columns.length))throw Error('Choose 1–32 distinct column indexes from the worksheet metadata.');
  const firstRow=options.firstRow??Math.max(store.headerRow?2:1,selected.range?.first??(store.headerRow?2:1));
  let lastRow=options.lastRow??selected.range?.last;
  if(lastRow===undefined){lastRow=firstRow-1;for(const [key,text] of store.cells)if(text!==''){const[c,r]=key.split(',').map(Number);if(columns.includes(c))lastRow=Math.max(lastRow,r+1);}}
  if(!Number.isInteger(firstRow)||!Number.isInteger(lastRow)||firstRow<(store.headerRow?2:1)||lastRow<firstRow||lastRow>store.rows)throw Error('Choose a nonempty data range using worksheet row numbers (excluding column headings).');
  const rowCount=lastRow-firstRow+1;
  if(rowCount*columns.length>4000)throw Error('This range is too large for the tutor. Select or request at most 4,000 cells. It has not been sampled or truncated.');
  let characters=0,hasErrors=false,hasStaleFormulas=false;
  const data=columns.map(c=>({index:c,title:store.columnTitle(c),values:Array.from({length:rowCount},(_,i)=>{
    const r=firstRow+i-1,text=store.get(c,r),metadata=store.metadata.get(`${c},${r}`);
    characters+=text.length;if(cellKind(store,c,r)==='error')hasErrors=true;
    if(metadata?.formula&&(store.formulasStale||!text))hasStaleFormulas=true;
    return text===''?null:text;
  })}));
  if(characters>50000)throw Error('The selected text is too large for the tutor. Choose a smaller range.');
  const columnLabel=columns.map(c=>columnName(c)).join(', ');
  return {workbook:workbook.name,sheet:sheet.name,sheetIndex:index,firstRow,lastRow,rowCount,columns:data,range:`${columnLabel} · rows ${firstRow}–${lastRow}`,complete:true,hasErrors,hasStaleFormulas};
}
