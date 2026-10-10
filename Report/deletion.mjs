import {currentRange,segments,deletePiece,selectRange} from './transfer.mjs';

const element=node=>node?.nodeType===1?node:node?.parentElement;
const bodies=()=>[...document.querySelectorAll('.report-body[data-result-id]')];
const inputSelector='input,textarea,select,.report-annotation';
const field=node=>element(node)?.closest(inputSelector);
let host,anchor=null;

// A caret immediately next to a protected picture deletes the picture as a
// unit. Stop at any text or other protected content, and never cross results.
function adjacentMedia(range,backward) {
  const body=element(range.startContainer)?.closest('.report-body');if(!body)return null;
  let node=range.startContainer,offset=range.startOffset;
  if(node.nodeType===Node.TEXT_NODE&& (backward?offset>0:offset<node.length))return null;
  let candidate=node.nodeType===Node.ELEMENT_NODE?node.childNodes[backward?offset-1:offset]:null;
  function edge(n) {
    if(n.nodeType===Node.TEXT_NODE) {
      if(n.textContent.trim())return {stop:true};
      // Source newlines between block elements have no rendered width. A real
      // space (including preformatted whitespace) still belongs to text editing.
      const text=document.createRange();text.selectNodeContents(n);
      return [...text.getClientRects()].some(rect=>rect.width>0&&rect.height>0)?{stop:true}:null;
    }
    if(n.nodeType!==Node.ELEMENT_NODE)return null;
    if(n.matches('.report-media'))return n.hidden?{stop:true}:{media:n};
    if(n.matches('br,.report-links,details,.report-import-warning,[contenteditable="false"]'))return {stop:true};
    for(const child of backward?[...n.childNodes].reverse():n.childNodes){const found=edge(child);if(found)return found;}
    return null;
  }
  if(candidate){const found=edge(candidate);if(found)return found.media||null;node=candidate;}
  while(node!==body) {
    const sibling=backward?node.previousSibling:node.nextSibling;
    if(sibling){const found=edge(sibling);if(found)return found.media||null;node=sibling;}
    else node=node.parentNode;
  }
  return null;
}
function wholeBody({body,range}) {
  const all=document.createRange();all.selectNodeContents(body);
  return range.compareBoundaryPoints(Range.START_TO_START,all)<=0&&range.compareBoundaryPoints(Range.END_TO_END,all)>=0;
}
function removeSelection(range,backward) {
  if(!range)return false;
  if(range.collapsed) {
    const media=adjacentMedia(range,backward);if(!media)return false;
    range=document.createRange();range.selectNode(media);
  }
  const pieces=segments(range);if(!pieces.length)return false;
  const removed=pieces.filter(wholeBody),partial=pieces.filter(p=>!removed.includes(p));
  const before=new Map(pieces.map(p=>[p.body,host.serialize(p.body)]));
  const encoder=new TextEncoder();
  // Keep this transaction within the same budget as rich cut/paste and undo.
  if([...before.values()].reduce((n,html)=>n+encoder.encode(html).length*2,0)>60_000_000) {
    host.post({action:'transferNotice',text:'This deletion is too large to keep in Undo. Select fewer report sections.'});return true;
  }
  const first=pieces[0],caret=first.range.cloneRange();caret.collapse(true);
  const original=bodies(),position=original.indexOf(first.body);
  for(const piece of [...partial].reverse())deletePiece(piece);
  const edits=partial.map(({body})=>{host.protect(body);return {id:body.dataset.resultId,html:host.serialize(body)};}).filter(e=>e.html!==before.get(pieces.find(p=>p.body.dataset.resultId===e.id).body));
  for(const {body} of removed){host.detach(body);body.closest('.report-entry').remove();}
  if(edits.length||removed.length)host.post({action:'editBodies',edits,remove:removed.map(p=>p.body.dataset.resultId)});
  if(first.body.isConnected)selectRange(first.body,caret);
  else {
    const remaining=bodies(),target=remaining[Math.min(position,remaining.length-1)];
    if(target){const next=document.createRange();next.selectNodeContents(target);next.collapse(position<remaining.length);selectRange(target,next);}
    else document.getElementById('report-results').focus({preventScroll:true});
  }
  host.remember();return true;
}
export function selectAllResults() {
  const list=bodies();if(!list.length)return false;
  const range=document.createRange();range.setStart(list[0],0);range.setEnd(list.at(-1),list.at(-1).childNodes.length);
  selectRange(list[0],range);anchor=list[0].dataset.resultId;return true;
}
export function installDeletion(options) {
  host=options;
  document.addEventListener('click',event=>{
    if(!host.isEditing()||field(event.target)||event.target.closest('.report-controls'))return;
    const heading=event.target.closest('h1,h2,h3,h4,h5,h6'),body=heading?.closest('.report-body');
    if(!body||heading!==body.querySelector('h1,h2,h3,h4,h5,h6'))return;
    const list=bodies(),start=event.shiftKey?list.find(b=>b.dataset.resultId===anchor):null;
    const ends=[start||body,body].sort((a,b)=>list.indexOf(a)-list.indexOf(b));
    const range=document.createRange();range.setStart(ends[0],0);range.setEnd(ends[1],ends[1].childNodes.length);
    selectRange(body,range);if(!start)anchor=body.dataset.resultId;
  });
  document.addEventListener('keydown',event=>{
    if(event.defaultPrevented||event.isComposing||!host.isEditing()||field(event.target)||!event.target.closest('#report-results'))return;
    if(event.metaKey&&!event.ctrlKey&&!event.altKey&&event.key.toLowerCase()==='a'){event.preventDefault();selectAllResults();return;}
    if(!['Backspace','Delete'].includes(event.key))return;
    const range=currentRange();
    if(range?.collapsed&&(event.metaKey||event.ctrlKey||event.altKey))return;
    if(removeSelection(range,event.key==='Backspace'))event.preventDefault();
  });
  // Also covers WebKit's contextual Delete and accessibility editing actions.
  document.addEventListener('beforeinput',event=>{
    if(event.defaultPrevented||event.isComposing||!host.isEditing()||field(event.target)||!event.target.closest('#report-results'))return;
    if(event.inputType==='deleteContentBackward'||event.inputType==='deleteContentForward'||event.inputType==='deleteByCut') {
      if(removeSelection(currentRange(),event.inputType==='deleteContentBackward'))event.preventDefault();
    }
  });
}
