import {columnName} from './store.mjs';
export const escapeHTML = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
// Print the chosen cells, or the used rectangle when nothing is selected. Split
// wide ranges into readable page-width bands; never print Glide's canvas viewport.
export function worksheetPrintHTML(store, selection = {}, title = 'Worksheet') {
  const used = store.usedColumns(), end = Math.max(1,store.usedRows());
  const range = selection.range;
  const columns = selection.columns?.length ? [...selection.columns] : range ? Array.from({length:range.width},(_,i)=>range.x+i) : Array.from({length:Math.max(1,(used.at(-1)??0)+1)},(_,i)=>i);
  const rows = selection.rows?.length ? [...selection.rows] : Array.from({length:range ? range.height : end},(_,i)=>(range?.y??0)+i);
  if (columns.length * rows.length > 250000) throw new Error('This print range is too large. Select a smaller range of cells or columns and choose Print again. No cells have been omitted.');
  let html = '';
  for(let start=0;start<columns.length;start+=8){
    const band=columns.slice(start,start+8);
    html += `<section><h1>${escapeHTML(title)}</h1><table><thead><tr><th></th>${band.map(c=>`<th>${escapeHTML(store.excelRows?columnName(c):store.columns[c])}</th>`).join('')}</tr></thead><tbody>`;
    for(const r of rows) html += `<tr><th>${r+1}</th>${band.map(c=>`<td>${escapeHTML(store.get(c,r))}</td>`).join('')}</tr>`;
    html += '</tbody></table></section>';
  }
  return html;
}
export function entryTablePrintHTML(table) {
  if(table.counts.length * table.columnLabels.length > 250000) throw new Error("This entry table is too large to print. Export it and select a smaller print range in the worksheet.");
  return `<h1>Chi-square r × c</h1><table><thead><tr><th></th>${table.columnLabels.map(c=>`<th>${escapeHTML(c)}</th>`).join('')}</tr></thead><tbody>${table.counts.map((row,r)=>`<tr><th>${escapeHTML(table.rowLabels[r])}</th>${row.map(c=>`<td>${escapeHTML(c)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
}
