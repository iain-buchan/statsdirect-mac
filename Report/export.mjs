import {clipboardText, formatClipboardTables, formatOfficePresentation, flattenOfficeTableBorders} from './clipboard.mjs';
import {wordEquation} from './math.mjs';
import {explicitPictureWidth} from './chart-size.mjs';
import {inlinePresentation} from './fragment.mjs';
import {Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun, ExternalHyperlink, HeadingLevel, WidthType, TableLayoutType, AlignmentType, BorderStyle, LevelFormat, ShadingType, VerticalAlignTable} from 'docx';

const MAX_HTML = 30_000_000;
// Export retains report presentation. Only pagination and page fitting belong
// here; screen/export fonts, table padding and colours must not diverge.
const printCSS = `@page{size:A4;margin:16mm}@media print{body{max-width:none!important;padding:0!important}h1,h2,h3{break-after:avoid}tr,svg,img{break-inside:avoid}thead{display:table-header-group}svg,img{max-width:100%;max-height:230mm}details:not([open]){display:none}details[open]{display:block}}`;
const blockTags = new Set(['P','DIV','SECTION','ARTICLE','MAIN','HEADER','FOOTER','ASIDE','NAV','FIGURE','FIGCAPTION','ADDRESS','DL','DT','DD','H1','H2','H3','H4','H5','H6','PRE','TABLE','UL','OL','LI','DETAILS','BLOCKQUOTE','SVG','IMG','HR']);
const blockSelector = [...blockTags].map(tag=>tag.toLowerCase()).join(',');
function isBlock(node) {
  // Host-specific/custom wrappers can contain structured report content too.
  // Keep equations atomic: KaTeX's presentation tree can contain SVG elements.
  return node.nodeType===Node.ELEMENT_NODE && !node.matches('.katex,math') &&
    (blockTags.has(node.tagName.toUpperCase()) || [...node.querySelectorAll(blockSelector)].some(child=>!child.closest('.katex,math')));
}
const bytes = data => Uint8Array.from(atob(data.substring(data.indexOf(',')+1)), c=>c.charCodeAt(0));
const text = node => (node.textContent ?? '').replace(/\s+/g,' ').trim();
const safeLink = value => /^(https?:|mailto:|#)/i.test(value);

function clean(root, helpRoot) {
  // A result's help lives on its block for the host's context menu; a saved or
  // exported report carries it as a link, so the method stays one click away.
  for(const entry of root.querySelectorAll('.report-entry[data-help]')) {
    if(entry.querySelector('.report-links a[href]'))continue;
    const links=document.createElement('p');links.className='report-links';
    const link=document.createElement('a');link.setAttribute('href',entry.getAttribute('data-help'));link.textContent='Method and worked example →';
    links.append(link);entry.append(links);
  }
  root.querySelectorAll('.report-chart[hidden],.report-annotation:empty').forEach(e=>e.remove());
  root.querySelectorAll('script,iframe,object,embed,form,button,input,textarea,select,link,base,meta[http-equiv],.report-r-link,.report-links span,.report-controls,.code-actions').forEach(e=>e.remove());
  root.querySelectorAll('.report-media,.report-chart').forEach(e=>e.replaceWith(...e.childNodes));
  for(const el of [root,...root.querySelectorAll('*')]) {
    el.classList.remove('report-editing');
    if(el.getAttribute('role')==='textbox')el.removeAttribute('role');
    for(const name of ['data-report-chart-index','data-result-id','data-hidden-charts','data-help','data-r'])el.removeAttribute(name);
    for(const attr of [...el.attributes]) if(/^on/i.test(attr.name)||['srcdoc','action','formaction','contenteditable','nonce','integrity'].includes(attr.name.toLowerCase())) el.removeAttribute(attr.name);
    if(el.localName==='a') {
      const original=el.getAttribute('href')??'';
      let href; try { href=new URL(original,document.baseURI).href; } catch { href=''; }
      if(helpRoot&&href.startsWith(helpRoot)) href='https://www.statsdirect.com/help/'+href.slice(helpRoot.length);
      if(original.startsWith('#')) href=original;
      if(safeLink(href)) el.setAttribute('href',href); else el.removeAttribute('href');
      el.removeAttribute('target');
    }
  }
}
function timeout(promise) {
  let timer;return Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('An image could not be prepared for export. Wait for the report to finish loading, then try again.')),15000);})]).finally(()=>clearTimeout(timer));
}
async function raster(data,width,height) {
  const image=new Image();
  await timeout(new Promise((resolve,reject)=>{image.onload=resolve;image.onerror=()=>reject(new Error('A report chart could not be exported.'));image.src=data;}));
  const canvas=document.createElement('canvas'),scale=Math.min(2,4096/Math.max(width,height));
  canvas.width=Math.max(1,Math.ceil(width*scale));canvas.height=Math.max(1,Math.ceil(height*scale));
  const ctx=canvas.getContext('2d');ctx.fillStyle='white';ctx.fillRect(0,0,canvas.width,canvas.height);ctx.drawImage(image,0,0,canvas.width,canvas.height);
  return canvas.toDataURL('image/png');
}
async function snapshot({title,helpRoot,format}) {
  if(document.documentElement.outerHTML.length>MAX_HTML) throw new Error('This report is too large to export in one file. Save smaller reports.');
  const clone=document.documentElement.cloneNode(true);
  // Resolve presentation while still attached, including the body defaults.
  // All formats then carry the same styles even if wrappers/classes are removed
  // on import. Never modify the live editor or its revision history.
  const live=[document.body,...document.body.querySelectorAll('*')],styled=[clone.querySelector('body'),...clone.querySelector('body').querySelectorAll('*')];
  for(let i=0;i<live.length;i++)if(!live[i].closest('svg,.report-controls'))inlinePresentation(live[i],styled[i]);
  const visible=el=>!el.closest('.report-chart[hidden],.report-controls')&&!el.parentElement.closest('svg');
  const originals=[...document.querySelectorAll('svg,img,canvas')].filter(visible),copies=[...clone.querySelectorAll('svg,img,canvas')].filter(visible),pictures=new Map();
  if(originals.length>200) throw new Error('This report has too many charts to export in one file. Save smaller reports.');
  for(let i=0;i<originals.length;i++) {
    const src=originals[i],dst=copies[i];
    if(src.closest('script,iframe,object,embed')) continue;
    let width,height,png,svg;
    if(src.localName==='svg') {
      const view=src.viewBox?.baseVal;
      width=view?.width||src.getBoundingClientRect().width||640;height=view?.height||src.getBoundingClientRect().height||400;
      const vector=src.cloneNode(true);clean(vector,helpRoot);
      vector.setAttribute('xmlns','http://www.w3.org/2000/svg');vector.setAttribute('width',String(width));vector.setAttribute('height',String(height));
      // Raster fallbacks use intrinsic coordinates; the chosen report width is
      // applied by the Word drawing/HTML layout, never baked into the chart.
      for(const name of ['width','height','max-width','max-height'])vector.style.removeProperty(name);
      svg=new XMLSerializer().serializeToString(vector);
      png=await raster('data:image/svg+xml;charset=utf-8,'+encodeURIComponent(svg),width,height);
    } else {
      if(src.localName==='img') {await timeout(src.decode());width=src.naturalWidth;height=src.naturalHeight;}
      else {width=src.width;height=src.height;}
      if(!width||!height) throw new Error('A report image has no readable size.');
      const canvas=document.createElement('canvas');const scale=Math.min(1,4096/Math.max(width,height));canvas.width=Math.ceil(width*scale);canvas.height=Math.ceil(height*scale);
      canvas.getContext('2d').drawImage(src,0,0,canvas.width,canvas.height);png=canvas.toDataURL('image/png');
      if(src.localName==='canvas') {const image=document.createElement('img');image.src=png;dst.replaceWith(image);copies[i]=image;} else {dst.src=png;dst.removeAttribute('srcset');}
    }
    const factor=Math.min(explicitPictureWidth(src,width)/width,640/width,820/height);
    pictures.set(copies[i],{svg,png,width:Math.round(width*factor),height:Math.round(height*factor),alt:src.getAttribute('aria-label')||src.getAttribute('alt')||src.querySelector('title')?.textContent||'StatsDirect chart'});
  }
  clean(clone,helpRoot);
  const head=clone.querySelector('head');let css='';
  for(const sheet of document.styleSheets) {
    try {css += [...sheet.cssRules].map(r=>r.cssText).join('\n')+'\n';}
    catch {throw new Error('A stylesheet could not be included. Open the report with its original supporting files and try again.');}
  }
  head.replaceChildren();
  const charset=document.createElement('meta');charset.setAttribute('charset','utf-8');head.append(charset);
  const name=document.createElement('title');name.textContent=title;head.append(name);
  const style=document.createElement('style');style.textContent=css+'\n'+printCSS;head.append(style);
  return {clone,pictures};
}
function wordColor(value) {
  if(!value||value==='transparent')return null;
  const hex=value.match(/^#([a-f\d]{6})$/i);if(hex)return hex[1].toUpperCase();
  const rgb=value.match(/^rgba?\(\s*(\d+)[, ]+\s*(\d+)[, ]+\s*(\d+)(?:\s*[,/]\s*([\d.]+))?\s*\)$/i);
  return rgb&&Number(rgb[4]??1)>0?rgb.slice(1,4).map(n=>Number(n).toString(16).padStart(2,'0')).join('').toUpperCase():null;
}
function runStyle(node,options={}) {
  const style={...options};
  if(['B','STRONG','TH'].includes(node.tagName))style.bold=true;
  if(['I','EM'].includes(node.tagName))style.italics=true;
  if(node.tagName==='SUP'){style.superScript=true;style.subScript=false;}
  if(node.tagName==='SUB'){style.subScript=true;style.superScript=false;}
  if(node.tagName==='U'||/underline/.test(node.style?.textDecorationLine||node.style?.textDecoration||''))style.underline={};
  if(['S','STRIKE','DEL'].includes(node.tagName))style.strike=true;
  const css=node.style;
  if(css) {
    if(/line-through/.test(css.textDecorationLine||css.textDecoration||''))style.strike=true;
    if(css.verticalAlign==='super'){style.superScript=true;style.subScript=false;}
    if(css.verticalAlign==='sub'){style.subScript=true;style.superScript=false;}
    const color=wordColor(css.color),background=wordColor(css.backgroundColor);
    if(color)style.color=color;
    if(background)style.shading={type:ShadingType.CLEAR,fill:background};
    if(css.fontWeight)style.bold=css.fontWeight==='bold'||Number(css.fontWeight)>=600;
    if(css.fontStyle)style.italics=['italic','oblique'].includes(css.fontStyle);
    if(css.fontSize && /(?:px|pt)$/.test(css.fontSize))style.size=Math.round(parseFloat(css.fontSize)*(css.fontSize.endsWith('pt')?2:1.5));
    if(css.fontFamily)style.font=css.fontFamily.split(',')[0].replace(/["']/g,'').trim();
  }
  if(['CODE','PRE'].includes(node.tagName)&&!css?.fontFamily)style.font='Courier New';
  if(/^pre/.test(css?.whiteSpace||''))style.preserve=true;
  return style;
}
const twips=value=>Math.round((parseFloat(value)||0)*(value?.endsWith('pt')?20:15));
function paragraphStyle(node,options={}) {
  const css=node.style,alignment=({left:AlignmentType.LEFT,start:AlignmentType.LEFT,center:AlignmentType.CENTER,right:AlignmentType.RIGHT,end:AlignmentType.RIGHT,justify:AlignmentType.JUSTIFIED}[css.textAlign]||options.alignment);
  const result={alignment,spacing:{after:0,...options.spacing},indent:options.indent};
  if(css.marginTop)result.spacing.before=Math.max(0,twips(css.marginTop));
  if(css.marginBottom)result.spacing.after=Math.max(0,twips(css.marginBottom));
  if(css.lineHeight&&css.lineHeight!=='normal') {
    const unitless=/^[\d.]+$/.test(css.lineHeight),line=parseFloat(css.lineHeight),font=parseFloat(css.fontSize)||16;
    if(line>0)result.spacing.line=Math.round(240*(unitless?line:line/font));
  }
  for(const side of ['left','right']) {
    const margin=twips(css.getPropertyValue('margin-'+side));
    if(margin)result.indent={...result.indent,[side]:margin+(options.indent?.[side]||0)};
  }
  return result;
}
function listParagraphs(list,pictures,options={},level=0) {
  const reference='report-list-'+pictures.numbering.length,ordered=list.tagName==='OL';
  pictures.numbering.push({reference,levels:Array.from({length:9},(_,i)=>({level:i,format:ordered?LevelFormat.DECIMAL:LevelFormat.BULLET,text:ordered?`%${i+1}.`:'•',start:Number(list.start)||1,alignment:AlignmentType.LEFT,style:{paragraph:{indent:{left:720*(i+1),hanging:360}}}}))});
  const output=[];
  for(const item of list.children) {
    // WebKit represents an indented first item as ul > ul > li.
    if(['UL','OL'].includes(item.tagName)){output.push(...listParagraphs(item,pictures,options,level+1));continue;}
    if(item.tagName!=='LI')continue;
    const copy=item.cloneNode(true);copy.querySelectorAll('ul,ol').forEach(n=>n.remove());
    output.push(new Paragraph({...paragraphStyle(item,options),children:inline(copy,options),numbering:{reference,level:Math.min(level,8)}}));
    for(const nested of item.querySelectorAll('ul,ol'))if(nested.parentElement.closest('ul,ol')===list)output.push(...listParagraphs(nested,pictures,runStyle(item,options),level+1));
  }
  return output;
}
function inline(node, options={}) {
  if(node.nodeType===Node.TEXT_NODE) {
    const value=options.preserve?node.textContent:node.textContent.replace(/\s+/g,' ');
    return value?(options.preserve?value.split(/\r\n|\r|\n/).map((line,index)=>new TextRun({...options,text:line,...(index?{break:1}:{})})):[new TextRun({...options,text:value})]):[];
  }
  if(node.nodeType!==Node.ELEMENT_NODE)return [];
  if(node.classList.contains('katex')||node.localName==='math') { const equation=wordEquation(node);if(equation)return [equation]; }
  if(node.tagName==='BR') return [new TextRun({...options,break:1})];
  const style=runStyle(node,options);
  const runs=[...node.childNodes].flatMap(n=>inline(n,style));
  if(node.tagName==='A'&&/^https?:|^mailto:/i.test(node.getAttribute('href')??''))return [new ExternalHyperlink({link:node.getAttribute('href'),children:runs})];
  return runs;
}
function paragraphs(node,pictures,options={}) {
  const output=[];let pending=[];
  const flush=()=>{if(pending.some(n=>text(n)))output.push(new Paragraph({children:pending.flatMap(n=>inline(n,options)),alignment:options.alignment,indent:options.indent,spacing:{after:0,...options.spacing}}));pending=[];};
  for(const child of node.childNodes) {
    if(!isBlock(child)){pending.push(child);continue;}
    flush();
    const tag=child.tagName.toUpperCase();
    if(tag==='TABLE') {output.push(table(child,pictures),new Paragraph({spacing:{after:70}}));continue;}
    if(pictures.has(child)) {
      const p=pictures.get(child),image=p.svg?{type:'svg',data:new TextEncoder().encode(p.svg),fallback:{type:'png',data:bytes(p.png)}}:{type:'png',data:bytes(p.png)};
      output.push(new Paragraph({alignment:AlignmentType.CENTER,children:[new ImageRun({...image,transformation:{width:p.width,height:p.height},altText:{title:p.alt,description:p.alt,name:p.alt}})],spacing:{before:120,after:160}}));continue;
    }
    if(tag==='DETAILS'&&!child.open)continue;
    if(tag==='HR'){output.push(new Paragraph({spacing:{after:160}}));continue;}
    if(/^H[1-6]$/.test(tag)) {output.push(new Paragraph({heading:HeadingLevel['HEADING_'+tag[1]],keepNext:true,...paragraphStyle(child,options),children:inline(child,options)}));continue;}
    if(tag==='UL'||tag==='OL') {output.push(...listParagraphs(child,pictures,options));continue;}
    if(tag==='P'||tag==='PRE'||tag==='BLOCKQUOTE') {
      if(child.querySelector('svg,img,table,canvas')||tag==='BLOCKQUOTE'&&child.querySelector('p,div,ul,ol'))output.push(...paragraphs(child,pictures,{...runStyle(child,options),...paragraphStyle(child,options)}));
      else if(tag==='PRE')output.push(new Paragraph({...paragraphStyle(child,options),children:inline(child,{...options,preserve:true})}));
      else output.push(new Paragraph({...paragraphStyle(child,options),children:inline(child,options)}));
    } else output.push(...paragraphs(child,pictures,{...runStyle(child,options),...paragraphStyle(child,options)}));
  }
  flush();return output;
}
const sides=['top','bottom','left','right'];
function borders(element) {
  return Object.fromEntries(sides.map(side=>{
    const css=element.style,type=css.getPropertyValue(`border-${side}-style`),width=twips(css.getPropertyValue(`border-${side}-width`));
    const style=({solid:BorderStyle.SINGLE,dashed:BorderStyle.DASHED,dotted:BorderStyle.DOTTED,double:BorderStyle.DOUBLE,inset:BorderStyle.INSET,outset:BorderStyle.OUTSET,groove:BorderStyle.THREE_D_ENGRAVE,ridge:BorderStyle.THREE_D_EMBOSS})[type];
    return [side,style&&width>0?{style,size:Math.max(2,Math.round(width*.4)),color:wordColor(css.getPropertyValue(`border-${side}-color`))||'auto'}:{style:BorderStyle.NONE}];
  }));
}
function cellBackground(cell) {
  // CSS table backgrounds show through transparent cells and row groups.
  for(let node=cell;node&&node.tagName!=='BODY';node=node.parentElement) {
    const fill=wordColor(node.style.backgroundColor);if(fill)return {type:ShadingType.CLEAR,fill};
  }
}
function table(element,pictures) {
  const rows=[...element.rows];
  if(!rows.length)return new Paragraph('');
  const columns=Math.max(...rows.map(row=>[...row.cells].reduce((n,c)=>n+c.colSpan,0)));
  return new Table({width:{size:100,type:WidthType.PERCENTAGE},layout:TableLayoutType.AUTOFIT,
    // docx otherwise supplies a single border on every table edge, even when
    // individual cells explicitly have no border.
    borders:{...borders(element),insideHorizontal:{style:BorderStyle.NONE},insideVertical:{style:BorderStyle.NONE}},
    rows:rows.map((row,index)=>new TableRow({tableHeader:row.parentElement.tagName==='THEAD'||index===0&&[...row.cells].some(c=>c.tagName==='TH'),cantSplit:true,
      children:[...row.cells].map(cell=>{
        const style={...runStyle(cell),...paragraphStyle(cell)},content=paragraphs(cell,pictures,style);
        return new TableCell({columnSpan:cell.colSpan,rowSpan:cell.rowSpan>1?cell.rowSpan:undefined,
          width:{size:Math.floor(10466*cell.colSpan/columns),type:WidthType.DXA},
          margins:Object.fromEntries(sides.map(side=>[side,Math.max(0,twips(cell.style.getPropertyValue('padding-'+side)))])),
          borders:borders(cell),shading:cellBackground(cell),
          verticalAlign:({middle:VerticalAlignTable.CENTER,bottom:VerticalAlignTable.BOTTOM})[cell.style.verticalAlign]||VerticalAlignTable.TOP,
          children:content.length?content:[new Paragraph({...paragraphStyle(cell),children:[new TextRun({...runStyle(cell),text:''})]})]
        });})}))});
}
export async function capture(options) {
  const {clone,pictures}=await snapshot(options);
  if(options.format==='html')return '<!doctype html>\n'+clone.outerHTML;
  if(options.format!=='docx')throw new Error('Unknown report format.');
  pictures.numbering=[];
  const body=clone.querySelector('body'),defaults=runStyle(body),content=paragraphs(body,pictures,defaults);
  const doc=new Document({creator:'StatsDirect',title:options.title,description:'Statistical analysis report',
    numbering:{config:pictures.numbering},
    styles:{default:{document:{run:defaults,paragraph:{spacing:{after:0}}}},
      paragraphStyles:Array.from({length:6},(_,i)=>({id:`Heading${i+1}`,name:`Heading ${i+1}`,basedOn:'Normal',next:'Normal',quickFormat:true,paragraph:{keepNext:true}}))},
    sections:[{properties:{page:{size:{width:11906,height:16838},margin:{top:720,right:720,bottom:720,left:720}}},children:content.length?content:[new Paragraph(options.title)]}]});
  const encoded=await Packer.toBase64String(doc);
  if(encoded.length>80_000_000)throw new Error('This report is too large to export in one file. Save smaller reports.');
  return encoded;
}

export async function clipboard(options) {
  const selection=window.getSelection();
  if(!options.fragment&&(!selection||selection.isCollapsed||!selection.rangeCount))return null;
  const root=document.createElement('div');
  if(options.fragment)root.innerHTML=options.fragment;
  else {
  const source=selection.getRangeAt(0),body=document.body,copy=body.cloneNode(true);
  const originals=[body,...body.querySelectorAll('*')],copies=[copy,...copy.querySelectorAll('*')];
  originals.forEach((node,i)=>inlinePresentation(node,copies[i]));
  const equivalent=node=>{const path=[];while(node!==body){path.unshift([...node.parentNode.childNodes].indexOf(node));node=node.parentNode;}return path.reduce((parent,i)=>parent.childNodes[i],copy);};
  const range=document.createRange();range.setStart(equivalent(source.startContainer),source.startOffset);range.setEnd(equivalent(source.endContainer),source.endOffset);
  let fragment=range.cloneContents(),ancestor=range.commonAncestorContainer;
  if(ancestor.nodeType!==Node.ELEMENT_NODE)ancestor=ancestor.parentElement;
  // Restore table/paragraph structure omitted by a partial selection.
  while(ancestor&&ancestor!==copy) {
    const wrapper=ancestor.cloneNode(false);wrapper.append(fragment);fragment=wrapper;ancestor=ancestor.parentElement;
  }
  root.append(fragment);
  }
  if(root.innerHTML.length>MAX_HTML)throw new Error('The selection is too large to copy. Select a smaller part of the report.');
  clean(root,options.helpRoot);
  root.querySelectorAll('details:not([open])').forEach(e=>e.remove());
  const widths=new Map([...root.querySelectorAll('svg,img')].map(e=>[e,explicitPictureWidth(e,0)]));
  // Keep text formatting for Word and other rich editors. Table formatting
  // below still supplies the numeric/cell hints Excel needs.
  for(const img of root.querySelectorAll('img'))if(widths.get(img)) {
    await timeout(img.decode());
    const width=Math.min(640,widths.get(img)),height=Math.round(width*img.naturalHeight/img.naturalWidth);
    img.width=Math.round(width*.75);img.height=Math.round(height*.75);img.style.cssText=`width:${width}px;height:${height}px`;
  }
  for(const svg of root.querySelectorAll('svg')) {
    const box=svg.viewBox?.baseVal,width=box?.width||640,height=box?.height||400;
    svg.setAttribute('xmlns','http://www.w3.org/2000/svg');
    svg.setAttribute('width',String(width));svg.setAttribute('height',String(height));
    for(const property of ['width','height','max-width','max-height'])svg.style.removeProperty(property);
    const img=document.createElement('img');img.alt=svg.getAttribute('aria-label')||'StatsDirect chart';
    img.src=await raster('data:image/svg+xml;charset=utf-8,'+encodeURIComponent(new XMLSerializer().serializeToString(svg)),width,height);
    const displayWidth=Math.min(640,widths.get(svg)||width),displayHeight=Math.round(height*displayWidth/width);
    // Excel treats image HTML attributes as points but lays out CSS dimensions as pixels.
    img.width=Math.round(displayWidth*.75);img.height=Math.round(displayHeight*.75);
    img.style.cssText=`width:${displayWidth}px;height:${displayHeight}px`;
    // Word showed every line break after a picture as an empty line, and Excel
    // places the next text below the picture without them.
    const holder=document.createElement('div');holder.append(img);
    svg.replaceWith(holder);
  }
  flattenOfficeTableBorders(root);
  formatOfficePresentation(root);
  formatClipboardTables(root);
  const html='<!doctype html><html xmlns:x="urn:schemas-microsoft-com:office:excel"><head><meta charset="utf-8"></head><body><!--StartFragment-->'+root.innerHTML+'<!--EndFragment--></body></html>';
  return JSON.stringify({html,text:clipboardText(root)});
}
