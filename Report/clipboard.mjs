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
export function excelNumberFormat(value) {
  if(numericValue(value)===null)return '\\@';
  const decimal=value.trim().match(/\.(\d+)/),places=decimal?.[1].length||0;
  const digits='0'+(places?'.'+'0'.repeat(places):'');
  return value.trim().endsWith('%')?digits+'%':/e/i.test(value)?digits+'E+00':places?digits:'General';
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
export function flattenOfficeTableBorders(root) {
  // Excel gives a table's outside border precedence over its cells, unlike
  // CSS collapsed borders. Move that outline onto the actual outside cells,
  // choosing the visible CSS winner, before handing the table to Office.
  const sides=['top','right','bottom','left'];
  const rank=['none','inset','groove','outset','ridge','dotted','dashed','solid','double','hidden'];
  const edge=(node,side)=>({width:parseFloat(node.style.getPropertyValue('border-'+side+'-width'))||0,style:node.style.getPropertyValue('border-'+side+'-style'),css:node.style.getPropertyValue('border-'+side)});
  const wins=(a,b)=>a.style==='hidden'||b.style!=='hidden'&&a.style!=='none'&&(b.style==='none'||a.width>b.width||a.width===b.width&&rank.indexOf(a.style)>rank.indexOf(b.style));
  for(const table of root.querySelectorAll('table')) {
    if(table.style.borderCollapse!=='collapse'||!sides.some(side=>!['','none'].includes(edge(table,side).style)))continue;
    const rows=[...table.rows],matrix=[],positions=[];
    rows.forEach((row,r)=>{
      matrix[r]??=[];let c=0;
      for(const cell of row.cells) {
        while(matrix[r][c])c++;
        const height=Math.min(cell.rowSpan||rows.length-r,rows.length-r);
        positions.push({cell,r,c,height,width:cell.colSpan});
        for(let dy=0;dy<height;dy++)for(let dx=0;dx<cell.colSpan;dx++){matrix[r+dy]??=[];matrix[r+dy][c+dx]=cell;}
        c+=cell.colSpan;
      }
    });
    const columns=Math.max(0,...matrix.map(row=>row.length));
    for(const {cell,r,c,height,width} of positions) {
      const outside={top:r===0,bottom:r+height===rows.length,left:c===0,right:c+width===columns};
      for(const side of sides)if(outside[side]&&wins(edge(table,side),edge(cell,side)))cell.style.setProperty('border-'+side,edge(table,side).css);
    }
    table.style.border='none';
  }
}
export function formatOfficePresentation(root) {
  // Excel interprets several CSS pixel lengths as points. Explicit points keep
  // Office at the report's physical font size, without changing browser layout.
  const lengths=['font-size','line-height',...['margin','padding'].flatMap(name=>['top','right','bottom','left'].map(side=>name+'-'+side)),...['top','right','bottom','left'].map(side=>'border-'+side+'-width')];
  for(const element of root.querySelectorAll('*')) {
    if(element.closest('svg'))continue;
    for(const name of lengths) {
      const value=element.style.getPropertyValue(name);
      if(/^[\d.]+px$/.test(value))element.style.setProperty(name,(Math.round(parseFloat(value)*.75*10000)/10000)+'pt');
    }
    // Office's HTML reader understands the older shorthand, whereas sanitizing
    // a CSS declaration expands it to the CSS3 text-decoration-line property.
    const decoration=element.style.textDecorationLine,declarations=[];
    if(decoration&&decoration!=='none')declarations.push('text-decoration:'+decoration);
    const sides=['top','right','bottom','left'];
    // Excel does not reliably parse four-value border shorthands. Spell out
    // each edge so different widths, colours and dashed/dotted styles survive.
    if(sides.some(side=>!['','none','hidden'].includes(element.style.getPropertyValue('border-'+side+'-style')))) {
      for(const side of sides)declarations.push('border-'+side+':'+['width','style','color'].map(part=>element.style.getPropertyValue('border-'+side+'-'+part)).join(' '));
    }
    if(declarations.length)element.setAttribute('style',element.getAttribute('style')+';'+declarations.join(';')+';');
  }
}
export function formatClipboardTables(root) {
  for(const table of root.querySelectorAll('table')) {
    // Presentation has already been resolved from the report. Supply only
    // Excel's value/type hints; do not replace fonts, borders or alignment.
    if(!table.querySelector('colgroup,col')) {
      const matrix=tableMatrix(table),widths=[];
      for(const row of matrix)row.forEach((value,c)=>widths[c]=Math.max(widths[c]||90,Math.min(280,value.length*8+20)));
      const group=document.createElement('colgroup');
      for(const width of widths) {const col=document.createElement('col');col.setAttribute('width',String(width));col.style.width=width+'px';group.append(col);}
      table.prepend(group);
    }
    for(const row of table.rows)for(const cell of row.cells) {
      const value=cell.textContent.trim(),number=numericValue(value);
      cell.removeAttribute('x:num');cell.removeAttribute('x:str');
      cell.setAttribute(number===null?'x:str':'x:num',number===null?value:String(number));
      const format=excelNumberFormat(value);
      // Unknown Office properties are dropped by CSSStyleDeclaration. Append
      // the literal hint last, after all standard CSS has been written.
      const style=(cell.getAttribute('style')||'').replace(/mso-number-format\s*:[^;]*;?/gi,'');
      cell.setAttribute('style',style+';mso-number-format:"'+format+'";');
    }
  }
}
