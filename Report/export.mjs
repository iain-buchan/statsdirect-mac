import {numericValue, clipboardText, formatClipboardTables} from './clipboard.mjs';
import {Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell, ImageRun, ExternalHyperlink, HeadingLevel, WidthType, TableLayoutType, AlignmentType, BorderStyle} from 'docx';

const MAX_HTML = 30_000_000;
const printCSS = `@page{size:A4;margin:16mm}body{font-family:Arial,sans-serif;font-size:11pt;line-height:1.4;color:#182b38}h1{font-size:19pt}h2{font-size:14pt}h1,h2,h3{break-after:avoid}table{width:100%;border-collapse:collapse;font-size:9pt}th,td{padding:5pt 7pt;overflow-wrap:anywhere}tr,svg,img{break-inside:avoid}thead{display:table-header-group}svg,img{max-width:100%;height:auto}.report-r-link{display:none}@media print{body{max-width:none!important;padding:0!important}details:not([open]){display:none}details[open]{display:block}svg,img{max-height:230mm}a{color:inherit}}`;
const blockTags = new Set(['P','DIV','SECTION','ARTICLE','H1','H2','H3','H4','H5','H6','PRE','TABLE','UL','OL','LI','DETAILS','BLOCKQUOTE','SVG','IMG','HR']);
const bytes = data => Uint8Array.from(atob(data.substring(data.indexOf(',')+1)), c=>c.charCodeAt(0));
const text = node => (node.textContent ?? '').replace(/\s+/g,' ').trim();
const safeLink = value => /^(https?:|mailto:|#)/i.test(value);

function clean(root, helpRoot) {
  root.querySelectorAll('script,iframe,object,embed,form,button,input,textarea,select,link,base,meta[http-equiv],.report-r-link,.report-links span').forEach(e=>e.remove());
  for(const el of [root,...root.querySelectorAll('*')]) {
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
async function snapshot({title,helpRoot}) {
  if(document.documentElement.outerHTML.length>MAX_HTML) throw new Error('This report is too large to export in one file. Save smaller reports.');
  const clone=document.documentElement.cloneNode(true);
  const originals=[...document.querySelectorAll('svg,img,canvas')],copies=[...clone.querySelectorAll('svg,img,canvas')],pictures=new Map();
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
    const factor=Math.min(1,640/width,820/height);
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
function inline(node, options={}) {
  if(node.nodeType===Node.TEXT_NODE) {
    const value=options.preserve?node.textContent:node.textContent.replace(/\s+/g,' ');
    return value?[new TextRun({...options,text:value})]:[];
  }
  if(node.nodeType!==Node.ELEMENT_NODE)return [];
  if(node.tagName==='BR') return [new TextRun({break:1})];
  const style={...options};
  if(['B','STRONG','TH'].includes(node.tagName))style.bold=true;
  if(['I','EM'].includes(node.tagName))style.italics=true;
  if(node.tagName==='SUP')style.superScript=true;
  if(node.tagName==='SUB')style.subScript=true;
  if(['CODE','PRE'].includes(node.tagName))style.font='Courier New';
  const runs=[...node.childNodes].flatMap(n=>inline(n,style));
  if(node.tagName==='A'&&/^https?:|^mailto:/i.test(node.getAttribute('href')??''))return [new ExternalHyperlink({link:node.getAttribute('href'),children:runs})];
  return runs;
}
function paragraphs(node,pictures,options={}) {
  const output=[];let pending=[];
  const flush=()=>{if(pending.some(n=>text(n)))output.push(new Paragraph({children:pending.flatMap(n=>inline(n,options)),alignment:options.alignment,spacing:{after:110}}));pending=[];};
  for(const child of node.childNodes) {
    if(child.nodeType!==Node.ELEMENT_NODE||!blockTags.has(child.tagName.toUpperCase())){pending.push(child);continue;}
    flush();
    const tag=child.tagName.toUpperCase();
    if(tag==='TABLE') {output.push(table(child,pictures),new Paragraph({spacing:{after:70}}));continue;}
    if(pictures.has(child)) {
      const p=pictures.get(child),image=p.svg?{type:'svg',data:new TextEncoder().encode(p.svg),fallback:{type:'png',data:bytes(p.png)}}:{type:'png',data:bytes(p.png)};
      output.push(new Paragraph({alignment:AlignmentType.CENTER,children:[new ImageRun({...image,transformation:{width:p.width,height:p.height},altText:{title:p.alt,description:p.alt,name:p.alt}})],spacing:{before:120,after:160}}));continue;
    }
    if(tag==='DETAILS'&&!child.open)continue;
    if(tag==='HR'){output.push(new Paragraph({spacing:{after:160}}));continue;}
    if(/^H[1-6]$/.test(tag)) {output.push(new Paragraph({heading:HeadingLevel['HEADING_'+tag[1]],keepNext:true,children:inline(child),spacing:{before:180,after:100}}));continue;}
    if(tag==='UL'||tag==='OL') {
      let n=Number(child.start)||1;
      for(const item of child.children)output.push(new Paragraph({children:[new TextRun(tag==='OL'?`${n++}. `:'• '),...inline(item)],spacing:{after:80}}));
      continue;
    }
    if(tag==='P'||tag==='PRE'||tag==='BLOCKQUOTE') {
      if(child.querySelector('svg,img,table,canvas'))output.push(...paragraphs(child,pictures,options));
      else if(tag==='PRE')for(const line of child.textContent.split('\n'))output.push(new Paragraph({children:[new TextRun({text:line,font:'Courier New',size:16})],spacing:{after:0}}));
      else output.push(new Paragraph({children:inline(child,options),alignment:options.alignment,spacing:{after:110}}));
    } else output.push(...paragraphs(child,pictures,options));
  }
  flush();return output;
}
function table(element,pictures) {
  const rows=[...element.rows];
  if(!rows.length)return new Paragraph('');
  const columns=Math.max(...rows.map(row=>[...row.cells].reduce((n,c)=>n+c.colSpan,0)));
  const border={style:BorderStyle.SINGLE,size:4,color:'D5DFE3'};
  return new Table({width:{size:100,type:WidthType.PERCENTAGE},layout:TableLayoutType.AUTOFIT,
    rows:rows.map((row,index)=>new TableRow({tableHeader:row.parentElement.tagName==='THEAD'||index===0&&[...row.cells].some(c=>c.tagName==='TH'),cantSplit:true,
      children:[...row.cells].map(cell=>{
        const content=paragraphs(cell,pictures,{bold:cell.tagName==='TH',size:19,alignment:numericValue(text(cell))!==null?AlignmentType.RIGHT:AlignmentType.LEFT});
        return new TableCell({columnSpan:cell.colSpan,rowSpan:cell.rowSpan>1?cell.rowSpan:undefined,
        width:{size:Math.floor(10466*cell.colSpan/columns),type:WidthType.DXA},margins:{top:65,bottom:65,left:90,right:90},
        borders:{top:border,bottom:border,left:border,right:border},shading:cell.tagName==='TH'?{fill:'EDF4F5'}:undefined,
        children:content.length?content:[new Paragraph('')]
      });})}))});
}
export async function capture(options) {
  const {clone,pictures}=await snapshot(options);
  if(options.format==='html')return '<!doctype html>\n'+clone.outerHTML;
  if(options.format!=='docx')throw new Error('Unknown report format.');
  const content=paragraphs(clone.querySelector('body'),pictures);
  const doc=new Document({creator:'StatsDirect',title:options.title,description:'Statistical analysis report',
    styles:{default:{document:{run:{font:'Arial',size:22,color:'182B38'},paragraph:{spacing:{after:110}}}},
      paragraphStyles:[{id:'Heading1',name:'Heading 1',basedOn:'Normal',next:'Normal',quickFormat:true,run:{bold:true,size:34,color:'182B38'},paragraph:{keepNext:true}},{id:'Heading2',name:'Heading 2',basedOn:'Normal',next:'Normal',quickFormat:true,run:{bold:true,size:27,color:'182B38'},paragraph:{keepNext:true}}]},
    sections:[{properties:{page:{size:{width:11906,height:16838},margin:{top:720,right:720,bottom:720,left:720}}},children:content.length?content:[new Paragraph(options.title)]}]});
  const encoded=await Packer.toBase64String(doc);
  if(encoded.length>80_000_000)throw new Error('This report is too large to export in one file. Save smaller reports.');
  return encoded;
}

export async function clipboard(options) {
  const selection=window.getSelection();
  if(!selection||selection.isCollapsed||!selection.rangeCount)return null;
  const range=selection.getRangeAt(0),root=document.createElement('div');
  let fragment=range.cloneContents(),ancestor=range.commonAncestorContainer;
  if(ancestor.nodeType!==Node.ELEMENT_NODE)ancestor=ancestor.parentElement;
  // cloneContents omits the common ancestor; restore table/paragraph structure for partial selections.
  while(ancestor&&ancestor!==document.body&&ancestor!==document.documentElement) {
    const wrapper=ancestor.cloneNode(false);wrapper.append(fragment);fragment=wrapper;ancestor=ancestor.parentElement;
  }
  root.append(fragment);
  if(root.innerHTML.length>MAX_HTML)throw new Error('The selection is too large to copy. Select a smaller part of the report.');
  clean(root,options.helpRoot);
  root.querySelectorAll('details:not([open])').forEach(e=>e.remove());
  root.querySelectorAll('[style]').forEach(e=>e.removeAttribute('style'));
  for(const svg of root.querySelectorAll('svg')) {
    const box=svg.viewBox?.baseVal,width=box?.width||640,height=box?.height||400;
    svg.setAttribute('xmlns','http://www.w3.org/2000/svg');
    const img=document.createElement('img');img.alt=svg.getAttribute('aria-label')||'StatsDirect chart';
    img.src=await raster('data:image/svg+xml;charset=utf-8,'+encodeURIComponent(new XMLSerializer().serializeToString(svg)),width,height);
    const displayWidth=Math.min(640,width),displayHeight=Math.round(height*displayWidth/width);
    // Excel treats image HTML attributes as points but lays out CSS dimensions as pixels.
    img.width=Math.round(displayWidth*.75);img.height=Math.round(displayHeight*.75);
    img.style.cssText=`width:${displayWidth}px;height:${displayHeight}px`;
    const holder=document.createElement('div');holder.append(img);
    // Excel places HTML pictures over cells. Reserve the extra vertical space caused by
    // its different point/pixel interpretation, keeping the next result unobscured.
    for(let n=0;n<Math.ceil(img.height*.25/12)+2;n++)holder.append(document.createElement('br'));
    svg.replaceWith(holder);
  }
  formatClipboardTables(root);
  const html='<!doctype html><html xmlns:x="urn:schemas-microsoft-com:office:excel"><head><meta charset="utf-8"><style>body,p,td,th{font:11pt Arial}h1,h2,h3{font: bold 12pt Arial}td,th{white-space:normal}p{margin:6pt 0}</style></head><body><!--StartFragment-->'+root.innerHTML+'<!--EndFragment--></body></html>';
  return JSON.stringify({html,text:clipboardText(root)});
}
