// A chart as other programs read it: the editor's Save chart as SVG and the export module's clipboard copy share this.
// A chart as other programs read it (once the Windows host's exportableSvg): the engine's charts carry text
// anchoring and font styling in style attributes on tspans and baseline shifts as dy in em, which Office's converter to
// shapes does not read, so every label was placed by its left edge at its anchor and off its baseline. The copy sets
// xmlns, drops data-* attributes, derives the height from the width and the viewBox when missing, puts each text's
// font-family (quotes removed), font-size, font-weight, font-style, fill and text-anchor as attributes of the text from
// the declarations on it and its spans, folds a span's dy (em or px) into the text's y and drops the spans when they
// carry nothing else, removes transform="rotate(0)", and turns shape style declarations into presentation attributes.
export function exportableSvg(el) {
  const svg=el.cloneNode(true);
  // Margins position the chart on the report page, not inside a standalone SVG.
  for(const name of ['margin','margin-left','margin-right','margin-top','margin-bottom'])svg.style.removeProperty(name);
  if(!svg.style.length)svg.removeAttribute('style');
  svg.setAttribute('xmlns','http://www.w3.org/2000/svg');
  for(const a of [...svg.attributes])if(a.name.startsWith('data-'))svg.removeAttribute(a.name);
  const box=(svg.getAttribute('viewBox')||'').trim().split(/[\s,]+/).map(Number);
  if(box.length===4&&box[2]>0&&box[3]>0){
    const w=svg.getAttribute('width'),m=w&&/^([\d.]+)([a-z%]*)$/i.exec(w);
    if(m&&!svg.getAttribute('height'))svg.setAttribute('height',(Math.round(Number(m[1])*box[3]/box[2]*1000)/1000)+(m[2]||''));
    else if(!w){svg.setAttribute('width',String(box[2]));svg.setAttribute('height',String(box[3]));}
  }
  const declared=style=>{const out={};for(const d of (style||'').split(';')){const i=d.indexOf(':');if(i<0)continue;const k=d.slice(0,i).trim(),v=d.slice(i+1).trim();if(k&&v)out[k]=v;}return out;};
  for(const text of svg.querySelectorAll('text')){
    const spans=[...text.querySelectorAll('tspan')],props={};
    for(const node of [text,...spans])for(const [k,v] of Object.entries(declared(node.getAttribute('style'))))if(!(k in props))props[k]=v;
    for(const k of ['font-family','font-size','font-weight','font-style','fill','text-anchor'])if(props[k]!==undefined)text.setAttribute(k,props[k].replace(/['"]/g,''));
    const size=parseFloat(props['font-size'])||16;
    let shift=0;
    for(const s of spans){
      const dy=s.getAttribute('dy'),m=dy&&/^(-?[\d.]+)(em|px)?$/.exec(dy.trim());
      if(m){shift+=Number(m[1])*(m[2]==='em'?size:1);s.removeAttribute('dy');}
      s.removeAttribute('style');
      for(const a of ['x','y'])if(s.getAttribute(a)==='0')s.removeAttribute(a);
    }
    if(shift)text.setAttribute('y',String((parseFloat(text.getAttribute('y'))||0)+shift));
    text.removeAttribute('style');
    if(/^rotate\(\s*0\s*\)$/.test(text.getAttribute('transform')||''))text.removeAttribute('transform');
    if(spans.length&&spans.every(s=>!s.attributes.length))text.textContent=spans.map(s=>s.textContent).join('');
  }
  for(const node of svg.querySelectorAll('line,ellipse,circle,rect,path,polyline,polygon,g')){
    const style=node.getAttribute('style');if(!style)continue;
    for(const [k,v] of Object.entries(declared(style)))if(!node.hasAttribute(k))node.setAttribute(k,v);
    node.removeAttribute('style');
  }
  // Office's conversion of a graphic to shapes places every text by its left edge at its anchor, whatever text-anchor says: a
  // centred or end-anchored text takes an explicit left-edge position, its width measured on the page (the element itself when
  // it is on the page, or a hidden copy), and the anchor becomes start, which draws the same everywhere with the same font. The
  // saved chart gets this too, so that an inserted file converts the same way. A text whose spans carry positions of their own
  // is left as it is.
  const measured=el.isConnected?el:(()=>{const copy=el.cloneNode(true);copy.style.position='absolute';copy.style.left='-100000px';copy.style.top='0';copy.style.visibility='hidden';document.body.append(copy);return copy;})();
  try {
    const liveTexts=[...measured.querySelectorAll('text')],texts=[...svg.querySelectorAll('text')];
    texts.forEach((text,i)=>{
      const anchor=text.getAttribute('text-anchor');if(anchor!=='middle'&&anchor!=='end')return;
      const live=liveTexts[i];if(!live)return;
      if([...live.querySelectorAll('tspan')].some(s=>['x','y'].some(a=>s.hasAttribute(a)&&s.getAttribute(a)!=='0')))return;
      let width=0;try{width=live.getComputedTextLength()||0;}catch{}
      if(!width)return;
      const x=parseFloat(text.getAttribute('x'))||0;
      text.setAttribute('x',String(Math.round((x-(anchor==='middle'?width/2:width))*1000)/1000));
      text.setAttribute('text-anchor','start');
    });
  } finally { if(measured!==el)measured.remove(); }
  return svg;
}
