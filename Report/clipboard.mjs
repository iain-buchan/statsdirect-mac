// Office receives real HTML tables, plus a tab-separated fallback for plain-text destinations.
const numberPattern=/^[+-]?(?:0|[1-9]\d*)(?:\.\d+)?(?:e[+-]?\d+)?%?$|^[+-]?\.\d+(?:e[+-]?\d+)?%?$/i;
export function numericValue(value) {
  value=value.trim().replace(/\u2212/g,'-');
  if(!numberPattern.test(value))return null;
  // Excel stores at most 15 significant digits. Preserve longer identifiers as text.
  if(value.split(/e/i)[0].replace(/\D/g,'').replace(/^0+/,'').length>15)return null;
  const result=Number(value.replace(/%$/,''))/(value.endsWith('%')?100:1);
  return Number.isFinite(result)?result:null;
}
export function tableMatrix(table) {
  const result=[];
  [...table.rows].forEach((row,r)=>{
    result[r]??=[];let c=0;
    for(const cell of row.cells) {
      while(result[r][c]!==undefined)c++;
      const value=(cell.innerText||cell.textContent||'').trim();
      for(let dy=0;dy<cell.rowSpan;dy++)for(let dx=0;dx<cell.colSpan;dx++) {
        result[r+dy]??=[];result[r+dy][c+dx]=dy||dx?'':value;
      }
      c+=cell.colSpan;
    }
  });
  const width=Math.max(0,...result.map(r=>r.length));
  return result.map(row=>Array.from({length:width},(_,i)=>row[i]??''));
}
const tsvCell=value=>/[\t\n\r"]/.test(value)?'"'+value.replace(/"/g,'""')+'"':value;
export function clipboardText(root) {
  function walk(node) {
    if(node.nodeType===Node.TEXT_NODE)return node.textContent.replace(/\s+/g,' ');
    if(node.nodeType!==Node.ELEMENT_NODE)return '';
    if(node.tagName==='TABLE')return '\n'+tableMatrix(node).map(row=>row.map(tsvCell).join('\t')).join('\n')+'\n';
    if(node.tagName==='BR')return '\n';
    if(['svg','img','canvas'].includes(node.localName))return '';
    const content=[...node.childNodes].map(walk).join('');
    return /^(P|DIV|SECTION|ARTICLE|H[1-6]|LI|PRE|DETAILS)$/.test(node.tagName)?'\n'+content+'\n':content;
  }
  return walk(root).replace(/ *\n */g,'\n').replace(/\n{3,}/g,'\n\n').trim();
}
export function formatClipboardTables(root) {
  for(const table of root.querySelectorAll('table')) {
    table.removeAttribute('class');table.removeAttribute('style');
    table.setAttribute('border','1');table.style.cssText='border-collapse:collapse;font:11pt Arial;';
    const matrix=tableMatrix(table),widths=[];
    for(const row of matrix)row.forEach((value,c)=>widths[c]=Math.max(widths[c]||90,Math.min(280,value.length*8+20)));
    table.querySelectorAll('colgroup').forEach(e=>e.remove());
    const group=document.createElement('colgroup');
    for(const width of widths) {const col=document.createElement('col');col.setAttribute('width',String(width));col.style.width=width+'px';group.append(col);}
    table.prepend(group);
    for(const row of table.rows)for(const cell of row.cells) {
      const value=cell.textContent.trim(),number=numericValue(value);
      cell.removeAttribute('class');cell.removeAttribute('style');
      cell.style.cssText='padding:4px 8px;border:1px solid #c7d3d9;vertical-align:top;white-space:normal;font:11pt Arial;';
      if(cell.tagName==='TH')cell.style.cssText+='font-weight:bold;background:#edf4f5;';
      if(number!==null) {
        cell.setAttribute('x:num',String(number));cell.style.textAlign='right';
        cell.style.whiteSpace='nowrap';
        const format=value.includes('%')?'0.##############%':/e/i.test(value)?'0.##############E+00':'General';
        cell.setAttribute('style',cell.getAttribute('style')+';mso-number-format:"'+format+'";');
      } else {cell.setAttribute('x:str',value);cell.style.textAlign='left';cell.setAttribute('style',cell.getAttribute('style')+';mso-number-format:"\\@";');}
    }
  }
}
