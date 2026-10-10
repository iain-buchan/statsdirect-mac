import {cleanFragment,inlinePresentation} from './fragment.mjs';
import {clipboardText} from './clipboard.mjs';

const bodySelector='.report-body[data-result-id]';
const element=node=>node?.nodeType===1?node:node?.parentElement;
let host,source=null,destination=null,drag=null,busy=false;
export const transferring=()=>busy;
const uid=()=>crypto.randomUUID();
const selection=()=>window.getSelection();
const blocked=node=>element(node)?.closest('.report-controls,.report-links,details,.report-import-warning');
const ownedBodies=()=>[...document.querySelectorAll(bodySelector)];
function message(text){host.post({action:'transferNotice',text});}
function currentRange() {
  if(document.activeElement?.closest('input,textarea,select,.report-annotation'))return null;
  const sel=selection();return sel?.rangeCount?sel.getRangeAt(0).cloneRange():null;
}
function fullRange(node){const range=document.createRange();range.selectNode(node);return range;}
function contains(range,node) {
  const other=fullRange(node);
  return range.compareBoundaryPoints(Range.START_TO_START,other)<=0&&range.compareBoundaryPoints(Range.END_TO_END,other)>=0;
}
function intersects(range,node) {
  const other=fullRange(node);
  return range.compareBoundaryPoints(Range.END_TO_START,other)<0&&range.compareBoundaryPoints(Range.START_TO_END,other)>0;
}
function segments(range,{caret=false}={}) {
  if(!range||(!caret&&range.collapsed)||blocked(range.startContainer)||blocked(range.endContainer))return [];
  const result=[];
  for(const body of ownedBodies()) {
    const piece=document.createRange();piece.selectNodeContents(body);
    if(range.collapsed) {
      if(body.contains(range.startContainer))result.push({body,range:range.cloneRange()});
      continue;
    }
    if(!intersects(range,body))continue;
    if(range.compareBoundaryPoints(Range.START_TO_START,piece)>0)piece.setStart(range.startContainer,range.startOffset);
    if(range.compareBoundaryPoints(Range.END_TO_END,piece)<0)piece.setEnd(range.endContainer,range.endOffset);
    // Chart labels are not independently editable: moving any part of a chart
    // moves the whole vector/picture, including its selected width.
    for(const edge of ['start','end']) {
      const media=element(piece[edge+'Container'])?.closest('.report-media');
      if(media&&body.contains(media))edge==='start'?piece.setStartBefore(media):piece.setEndAfter(media);
    }
    if(!piece.collapsed)result.push({body,range:piece});
  }
  return result;
}
function path(node,root){const parts=[];while(node!==root){parts.unshift([...node.parentNode.childNodes].indexOf(node));node=node.parentNode;}return parts;}
const atPath=(root,parts)=>parts.reduce((node,index)=>node.childNodes[index],root);
function copySegment({body,range}) {
  const clone=body.cloneNode(true),originals=[body,...body.querySelectorAll('*')],copies=[clone,...clone.querySelectorAll('*')];
  originals.forEach((node,index)=>inlinePresentation(node,copies[index]));
  const copy=document.createRange();copy.setStart(atPath(clone,path(range.startContainer,body)),range.startOffset);copy.setEnd(atPath(clone,path(range.endContainer,body)),range.endOffset);
  let fragment=copy.cloneContents(),ancestor=element(copy.commonAncestorContainer);
  const common=element(range.commonAncestorContainer),block=common?.closest('p,h1,h2,h3,h4,h5,h6,li,td,th');
  // A few words within a paragraph/cell should remain inline at their new
  // destination. Whole paragraphs and table selections retain their structure.
  if(block&&body.contains(block)&&!contains(range,block)&&!fragment.querySelector?.('table,svg,img,.report-media')) {
    const span=document.createElement('span');inlinePresentation(common,span);span.append(fragment);fragment=span;
  } else {
    while(ancestor&&ancestor!==clone) {
      const wrapper=ancestor.cloneNode(false);wrapper.append(fragment);fragment=wrapper;ancestor=ancestor.parentElement;
    }
  }
  const holder=document.createElement('div');holder.append(fragment);return holder.innerHTML;
}
function capture(pieces) {
  if(!pieces.length)return null;
  const html=cleanFragment(pieces.map(copySegment).join(''),{freshIDs:false});
  const holder=document.createElement('div');holder.innerHTML=html;
  if(!holder.textContent.trim()&&!holder.querySelector('svg,img,table,hr'))return null;
  return {token:uid(),pieces,html,text:clipboardText(holder),before:new Map(pieces.map(p=>[p.body,host.serialize(p.body)]))};
}
const unchanged=record=>record&&[...record.before].every(([body,html])=>body.isConnected&&host.serialize(body)===html);
export function prepareClipboard(cut=false) {
  const range=currentRange(),pieces=segments(range);
  if(!pieces.length)return null;
  if(cut&&!host.isEditing())return {handled:true};
  source=capture(pieces);
  return source?{token:source.token,html:source.html,text:source.text}:null;
}
export function preparePaste() {
  const pieces=segments(currentRange(),{caret:true});
  if(!pieces.length)return null;
  if(!host.isEditing())return {handled:true};
  destination={token:uid(),pieces,before:new Map(pieces.map(p=>[p.body,host.serialize(p.body)]))};
  return {token:destination.token};
}

// Keep the layout of partially selected tables: clear exactly the highlighted
// cell contents, leaving unselected cells and merged-cell boundaries intact.
// A completely selected table is removed as a unit.
function deletePiece({body,range}) {
  const actions=[];
  function visit(node) {
    if(!intersects(range,node))return;
    if(node.nodeType===Node.TEXT_NODE) {
      const start=range.startContainer===node?range.startOffset:0,end=range.endContainer===node?range.endOffset:node.length;
      if(end>start)actions.push(()=>node.deleteData(start,end-start));return;
    }
    if(node.nodeType!==Node.ELEMENT_NODE)return;
    const table=node.closest('table'),keepShell=table&&!contains(range,table)&&/^(TABLE|THEAD|TBODY|TFOOT|TR|TD|TH|COLGROUP|COL)$/.test(node.tagName);
    if(contains(range,node)&&!keepShell){actions.push(()=>node.remove());return;}
    for(const child of node.childNodes)visit(child);
  }
  for(const child of body.childNodes)visit(child);
  actions.reverse().forEach(action=>action());range.collapse(true);
}
function transaction(bodies,work) {
  const unique=[...new Set(bodies)],before=new Map(unique.map(body=>[body,host.serialize(body)]));
  busy=true;
  try {
    if(work()===false)throw new Error('The content could not be inserted here. Choose a position in the report text.');
    const edits=[];
    for(const body of unique) {
      host.protect(body);const html=host.serialize(body);
      if(new TextEncoder().encode(html).length>30_000_000)throw new Error('This report section is too large. Paste a smaller selection.');
      if(html!==before.get(body))edits.push({id:body.dataset.resultId,html});
    }
    const encoder=new TextEncoder();
    if(edits.reduce((bytes,edit)=>bytes+encoder.encode(edit.html).length+encoder.encode(before.get(unique.find(body=>body.dataset.resultId===edit.id))).length,0)>60_000_000)throw new Error('This move is too large to keep in Undo. Select content in fewer report sections.');
    if(edits.length)host.post({action:'editBodies',edits});
    host.remember();return true;
  } catch(error) {
    source=null;destination=null;drag=null;
    for(const [body,html] of before){host.detach(body);body.innerHTML=html;host.protect(body);}
    message(error.message);return false;
  } finally {busy=false;}
}
export function cutPrepared(token) {
  if(!host.isEditing()||source?.token!==token||!unchanged(source)){message('The selection changed before it could be cut. Copy or cut it again.');return false;}
  const pending=source;source=null;
  return transaction(pending.pieces.map(p=>p.body),()=>{
    const caret=pending.pieces[0].range.cloneRange();caret.collapse(true);
    [...pending.pieces].reverse().forEach(deletePiece);selectRange(pending.pieces[0].body,caret);
  });
}
function selectRange(body,range){body.focus({preventScroll:true});const sel=selection();sel.removeAllRanges();sel.addRange(range);}
function insertion(html,body) {
  const holder=document.createElement('div');holder.innerHTML=html;
  let next=Math.max(-1,...[...body.querySelectorAll('svg[data-report-chart-index]')].map(el=>Number(el.dataset.reportChartIndex)),...(body.dataset.hiddenCharts||'').split(',').filter(Boolean).map(Number))+1;
  for(const svg of holder.querySelectorAll('svg'))if(!svg.parentElement.closest('svg'))svg.dataset.reportChartIndex=String(next++);
  return holder.innerHTML;
}
function insertFragment(body,caret,fragment) {
  const last=fragment.lastChild;if(!last)return false;
  const blocks=fragment.querySelector('p,div,section,article,h1,h2,h3,h4,h5,h6,table,ul,ol,li,blockquote,hr,svg,img');
  const paragraph=element(caret.startContainer)?.closest('p,h1,h2,h3,h4,h5,h6,pre');
  if(blocks&&paragraph&&body.contains(paragraph)) {
    // Split a paragraph around block content instead of placing a table/SVG
    // inside <p>. All nodes are inserted intact: WebKit's insertHTML editing
    // command may normalize away SVG definitions or surrounding whitespace.
    const tail=document.createRange();tail.selectNodeContents(paragraph);tail.setStart(caret.startContainer,caret.startOffset);
    const after=paragraph.cloneNode(false);after.removeAttribute('id');after.append(tail.extractContents());
    paragraph.after(fragment);last.after(after);
    if(!after.textContent&&!after.querySelector('img,svg,br'))after.remove();
    if(!paragraph.textContent&&!paragraph.querySelector('img,svg,br'))paragraph.remove();
  } else caret.insertNode(fragment);
  caret.setStartAfter(last);caret.collapse(true);selectRange(body,caret);return true;
}
function insert(pieces,payload,{remove=[]}={}) {
  let html;
  try {html=payload.html?cleanFragment(payload.html):null;} catch(error){message(error.message);return false;}
  if(!html&&!payload.text)return false;
  const first=pieces[0],caret=first.range.cloneRange();caret.collapse(true);
  return transaction([...pieces,...remove].map(p=>p.body),()=>{
    // The live caret follows removal even when content moves forward in the
    // same paragraph. No source deletion occurs until sanitization succeeds.
    [...remove,...pieces.filter(p=>!p.range.collapsed)].reverse().forEach(deletePiece);
    selectRange(first.body,caret);
    const template=document.createElement('template');
    if(html)template.innerHTML=insertion(html,first.body);
    else payload.text.replace(/\r\n?/g,'\n').split('\n').forEach((line,index)=>{if(index)template.content.append(document.createElement('br'));template.content.append(document.createTextNode(line));});
    return insertFragment(first.body,caret,template.content);
  });
}
export function pastePrepared(token,payload) {
  if(!host.isEditing()||destination?.token!==token||!unchanged(destination)){message('The insertion point changed before pasting. Choose it again and paste.');return false;}
  const pending=destination;destination=null;return insert(pending.pieces,payload);
}

function dropRange(event) {
  const target=document.elementFromPoint(event.clientX,event.clientY),body=target?.closest(bodySelector);
  if(!body||blocked(target)||target?.closest('.report-media'))return null;
  const caret=document.caretRangeFromPoint(event.clientX,event.clientY);
  if(!caret||!body.contains(caret.startContainer)||blocked(caret.startContainer)||element(caret.startContainer)?.closest('.report-media'))return null;
  return {body,range:caret};
}
let indicator;
function clearDrop(){indicator?.remove();indicator=null;}
function showDrop(target) {
  clearDrop();if(!target)return;
  const rect=target.range.getClientRects()[0]||target.range.startContainer.parentElement?.getBoundingClientRect();
  if(!rect)return;
  indicator=document.createElement('div');indicator.className='report-controls report-drop-caret';indicator.style.cssText=`left:${rect.left+window.scrollX}px;top:${rect.top+window.scrollY}px;height:${Math.max(16,rect.height)}px`;document.body.append(indicator);
}
function moveSelection(record,target,copy=false) {
  if(!host.isEditing()||!target)return false;
  if(!unchanged(record)){message('The dragged content changed. Select it again.');return false;}
  if(record.pieces.some(p=>p.range.isPointInRange(target.range.startContainer,target.range.startOffset)))return false;
  return insert([target],record,{remove:copy?[]:record.pieces});
}

// WebKit otherwise treats a quick drag inside selected text as a new selection,
// and SVG children are not reliably native drag sources. Handle an existing
// selection directly, leaving ordinary unselected text gestures to WebKit.
function pointerTransfers() {
  let pending=null,frame=0,skipClick=false;
  function clear() {
    const previous=pending;pending=null;cancelAnimationFrame(frame);frame=0;clearDrop();
    if(previous?.body.hasPointerCapture(previous.pointer))previous.body.releasePointerCapture(previous.pointer);
    return previous;
  }
  function track() {
    if(!pending?.moving)return;
    const bar=document.getElementById('report-toolbar').getBoundingClientRect(),top=Math.max(0,bar.bottom)+20;
    const speed=pending.y<top?-12:pending.y>window.innerHeight-28?12:0;
    if(speed)window.scrollBy(0,speed);
    showDrop(dropRange({clientX:pending.x,clientY:pending.y}));frame=requestAnimationFrame(track);
  }
  document.addEventListener('pointerdown',event=>{
    skipClick=false;
    if(pending||!host.isEditing()||event.button!==0||event.ctrlKey||event.metaKey||event.shiftKey||blocked(event.target))return;
    const body=element(event.target)?.closest(bodySelector);if(!body)return;
    const media=element(event.target)?.closest('.report-media');
    const selected=currentRange(),range=media&&!(selected&&!selected.collapsed&&contains(selected,media))?fullRange(media):selected;
    if(!range||range.collapsed)return;
    if(!media) {
      const point=document.caretRangeFromPoint(event.clientX,event.clientY);
      if(!point||!range.isPointInRange(point.startContainer,point.startOffset)||![...range.getClientRects()].some(rect=>event.clientX>=rect.left&&event.clientX<=rect.right&&event.clientY>=rect.top&&event.clientY<=rect.bottom))return;
    }
    const record=capture(segments(range));if(!record)return;
    event.preventDefault();selectRange(body,range);
    pending={record,body,pointer:event.pointerId,startX:event.clientX,startY:event.clientY,x:event.clientX,y:event.clientY,moving:false};
    try{body.setPointerCapture(event.pointerId);}catch{} // Synthetic native regression events.
  });
  document.addEventListener('pointermove',event=>{
    if(event.pointerId!==pending?.pointer)return;
    event.preventDefault();pending.x=event.clientX;pending.y=event.clientY;
    if(!pending.moving&&Math.hypot(pending.x-pending.startX,pending.y-pending.startY)>=4){pending.moving=true;track();}
    else if(pending.moving)showDrop(dropRange(event));
  },{passive:false});
  document.addEventListener('pointerup',event=>{
    if(event.pointerId!==pending?.pointer)return;
    event.preventDefault();const previous=clear();
    if(previous.moving){skipClick=true;moveSelection(previous.record,dropRange(event),event.altKey);}
    else {const target=dropRange(event);if(target)selectRange(target.body,target.range);}
  });
  document.addEventListener('pointercancel',clear);
  document.addEventListener('lostpointercapture',event=>{if(event.pointerId===pending?.pointer)clear();});
  window.addEventListener('blur',clear);
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&pending){event.preventDefault();skipClick=true;clear();}},true);
  document.addEventListener('click',event=>{if(skipClick){skipClick=false;event.preventDefault();event.stopImmediatePropagation();}},true);
}
export function installTransfer(options) {
  host=options;
  pointerTransfers();
  document.addEventListener('copy',event=>{
    if(!segments(currentRange()).length)return;
    event.preventDefault();host.post({action:'clipboard',command:'copy'});
  });
  document.addEventListener('cut',event=>{
    if(!segments(currentRange()).length)return;
    event.preventDefault();if(host.isEditing())host.post({action:'clipboard',command:'cut'});
  });
  document.addEventListener('paste',event=>{
    if(!segments(currentRange(),{caret:true}).length)return;
    event.preventDefault();if(host.isEditing())host.post({action:'clipboard',command:'paste'});
  });
  document.addEventListener('click',event=>{
    if(!host.isEditing()||event.target.closest('.report-controls'))return;
    const media=event.target.closest('.report-media');
    if(media&&!media.hidden)selectRange(media.closest(bodySelector),fullRange(media));
  });
  document.addEventListener('selectionchange',()=>{
    const range=currentRange();
    document.querySelectorAll('.report-media').forEach(media=>{
      const selected=host.isEditing()&&range&&!range.collapsed&&contains(range,media);
      media.classList.toggle('report-media-selected',!!selected);media.draggable=!!selected;
      media.querySelectorAll('svg,img').forEach(picture=>picture.draggable=false);
    });
  });
  document.addEventListener('dragstart',event=>{
    if(!host.isEditing()||blocked(event.target)||!element(event.target)?.closest(bodySelector))return;
    const pieces=segments(currentRange());drag=capture(pieces);
    if(!drag){event.preventDefault();return;}
    event.dataTransfer.setData('text/html',drag.html);event.dataTransfer.setData('text/plain',drag.text);
    event.dataTransfer.setData('application/x-statsdirect-report-move',drag.token);event.dataTransfer.effectAllowed='copyMove';
  });
  document.addEventListener('dragover',event=>{
    if(!host.isEditing())return;
    const target=dropRange(event);clearDrop();
    if(target){event.preventDefault();event.dataTransfer.dropEffect=drag&&!event.altKey?'move':'copy';showDrop(target);}
  });
  document.addEventListener('drop',event=>{
    clearDrop();
    if(!element(event.target)?.closest(bodySelector))return;
    event.preventDefault();if(!host.isEditing())return;
    const target=dropRange(event);if(!target)return;
    const local=drag&&event.dataTransfer.getData('application/x-statsdirect-report-move')===drag.token?drag:null;
    if(local)moveSelection(local,target,event.altKey);
    else insert([target],{html:event.dataTransfer.getData('text/html'),text:event.dataTransfer.getData('text/plain')});
    drag=null;
  });
  document.addEventListener('dragend',()=>{drag=null;clearDrop();});
  document.addEventListener('dragleave',event=>{if(!event.relatedTarget)clearDrop();});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'){drag=null;clearDrop();}});
}
