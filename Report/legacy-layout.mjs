// A Windows RTF row can give a heading one wide cell where data rows have
// several columns. AppKit exports those cells without HTML colspan attributes.
export function columnSpans(edges, grid) {
  let previous=-1;const spans=[];
  for(const edge of edges) {
    const index=grid.findIndex((boundary,i)=>i>previous&&Math.abs(boundary-edge)<=15);
    if(index<0)return null;
    spans.push(index-previous);previous=index;
  }
  return previous===grid.length-1?spans:null;
}

const numeric = value => /^[-+−]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?%?$/.test(value.trim());
const contentElements = root => [...root.querySelectorAll('*')].filter(el=>!el.closest('svg'));
function usualSize(elements, fallback) {
  const weights=new Map();
  for(const el of elements) {
    const text=[...el.childNodes].filter(n=>n.nodeType===Node.TEXT_NODE).map(n=>n.textContent.trim()).join('');
    const size=parseFloat(el.style.fontSize);
    if(text && size>0 && !el.closest('sup,sub'))weights.set(size,(weights.get(size)||0)+text.length);
  }
  return [...weights].sort((a,b)=>b[1]-a[1])[0]?.[0]||fallback;
}

export function normalizeLegacyLayout(root, tableRows=[]) {
  const elements=contentElements(root), body=elements.filter(e=>!e.closest('table')),cells=elements.filter(e=>e.closest('table'));
  // AppKit's HTML uses px for the RTF point sizes. Make normal body/table text
  // match the viewer's 16/14px sizes while retaining relative sizes and emphasis.
  const bodyBase=usualSize(body,usualSize(cells,10)),tableBase=usualSize(cells,bodyBase);
  for(const el of elements) {
    const inTable=!!el.closest('table'),base=inTable?tableBase:bodyBase,target=inTable?14:16;
    const size=parseFloat(el.style.fontSize);
    if(size>0)el.style.fontSize=`${Math.round(size/base*target*100)/100}px`;
    el.style.lineHeight='1.5';
    if(el.localName==='p') {
      el.style.margin=inTable?'0':'0 0 0.65em';
      if(!el.textContent.trim()&&!el.querySelector('svg,img'))el.remove();
    }
  }
  let offset=0;
  for(const table of root.querySelectorAll('table')) {
    const rows=[...table.rows],definitions=tableRows.slice(offset,offset+rows.length);offset+=rows.length;
    const grid=definitions.reduce((a,b)=>b.length>a.length?b:a,[]);
    if(definitions.length===rows.length && grid.length && rows.every((r,i)=>r.cells.length===definitions[i].length)) {
      const spans=definitions.map(edges=>columnSpans(edges,grid));
      if(spans.every(Boolean))rows.forEach((row,i)=>[...row.cells].forEach((cell,j)=>cell.colSpan=spans[i][j]));
    }
    // Earlier HTML imports did not retain RTF row geometry. A short, underlined
    // heading followed by full data rows identifies the old StatsDirect layout.
    const first=rows[0],width=Math.max(0,...rows.map(r=>[...r.cells].reduce((n,c)=>n+c.colSpan,0)));
    const heading=first&&[...first.cells].every(c=>!numeric(c.textContent))&&rows.slice(1).some(r=>[...r.cells].some(c=>numeric(c.textContent)));
    if(!tableRows.length&&heading&&[...first.cells].every(c=>[c,...c.querySelectorAll('*')].some(e=>e.style.textDecorationLine.includes('underline')))) {
      const used=[...first.cells].reduce((n,c)=>n+c.colSpan,0);
      if(used<width)first.lastElementChild.colSpan+=width-used;
    }
    if(heading)for(const cell of [...first.cells])if(cell.tagName==='TD') {
      const header=document.createElement('th');
      for(const attr of cell.attributes)header.setAttribute(attr.name,attr.value);
      header.append(...cell.childNodes);header.scope=header.colSpan>1?'colgroup':'col';cell.replaceWith(header);
    }
    table.removeAttribute('width');table.removeAttribute('height');
    Object.assign(table.style,{width:'100%',maxWidth:'100%',height:'auto',borderCollapse:'collapse',borderSpacing:'0',fontSize:'14px',margin:'20px 0'});
    for(const cell of table.querySelectorAll('td,th')) {
      cell.removeAttribute('width');cell.removeAttribute('height');
      const align=cell.tagName==='TH'?'left':numeric(cell.textContent)?'right':'left';
      Object.assign(cell.style,{width:'auto',height:'auto',fontSize:'14px',padding:'9px 15px',border:'0',borderBottom:'1px solid #e2e9ec',verticalAlign:'top',textAlign:align});
      for(const el of cell.querySelectorAll('*'))if(!el.closest('svg'))el.style.textAlign=align;
    }
  }
  root.classList.add('legacy-report');
}
