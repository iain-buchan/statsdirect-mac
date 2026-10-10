import {currentRange,segments,deletePiece,selectRange,entryRange,clampSelection} from './transfer.mjs';
import {region,entries,entryOf,entryById,field,elementOf,emptyNotice} from './region.mjs';

let host,anchor=null;

// A caret immediately next to a protected picture deletes the picture as a
// unit. Stop at any text or other protected content. The walk crosses results:
// the report is one region, and a picture at the start of the next result is
// the next thing after the end of this one.
function adjacentMedia(range,backward) {
  const root=region();if(!root||!root.contains(range.startContainer))return null;
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
  while(node!==root) {
    const sibling=backward?node.previousSibling:node.nextSibling;
    if(sibling){const found=edge(sibling);if(found)return found.media||null;node=sibling;}
    else node=node.parentNode;
  }
  return null;
}
function wholeEntry({entry,range}) {
  const all=document.createRange();all.selectNodeContents(entry);
  return range.compareBoundaryPoints(Range.START_TO_START,all)<=0&&range.compareBoundaryPoints(Range.END_TO_END,all)>=0;
}
function removeSelection(range,backward) {
  if(!range)return false;
  if(range.collapsed) {
    const media=adjacentMedia(range,backward);if(!media)return false;
    range=document.createRange();range.selectNode(media);
  }
  const pieces=segments(range);if(!pieces.length)return false;
  const removed=pieces.filter(wholeEntry),partial=pieces.filter(p=>!removed.includes(p));
  const before=new Map(pieces.map(p=>[p.entry,host.serialize(p.entry)]));
  const encoder=new TextEncoder();
  // Keep this transaction within the same budget as rich cut/paste and undo.
  if([...before.values()].reduce((n,html)=>n+encoder.encode(html).length*2,0)>60_000_000) {
    host.post({action:'transferNotice',text:'This deletion is too large to keep in Undo. Select fewer report sections.'});return true;
  }
  const first=pieces[0],caret=first.range.cloneRange();caret.collapse(true);
  const original=entries(),position=original.indexOf(first.entry);
  for(const piece of [...partial].reverse())deletePiece(piece);
  host.protect();
  const edits=partial.map(({entry})=>({id:entry.dataset.resultId,html:host.serialize(entry)})).filter(e=>e.html!==before.get(pieces.find(p=>p.entry.dataset.resultId===e.id).entry));
  for(const {entry} of removed){host.detach(entry);entry.remove();}
  if(edits.length||removed.length)host.post({action:'editBodies',edits,remove:removed.map(p=>p.entry.dataset.resultId)});
  const notice=emptyNotice();if(notice)notice.hidden=entries().length>0;
  if(first.entry.isConnected)selectRange(caret);
  else {
    const remaining=entries(),target=remaining[Math.min(position,remaining.length-1)];
    if(target){const next=document.createRange();next.selectNodeContents(target);next.collapse(position<remaining.length);selectRange(next);}
    else region()?.focus({preventScroll:true});
  }
  host.remember();return true;
}
export function selectAllResults() {
  const list=entries();if(!list.length)return false;
  selectRange(entryRange(list[0],list.at(-1)));anchor=list[0].dataset.resultId;return true;
}
// A result selected as a unit, as a click on its heading selects it.
export function selectResult(id) {
  const entry=entryById(id);if(!entry)return false;
  selectRange(entryRange(entry,entry));anchor=id;return true;
}
export function installDeletion(options) {
  host=options;
  document.addEventListener('click',event=>{
    if(!host.isEditing()||field(event.target)||event.target.closest('.report-controls'))return;
    const heading=event.target.closest('h1,h2,h3,h4,h5,h6'),entry=entryOf(heading);
    if(!entry||heading!==entry.querySelector('h1,h2,h3,h4,h5,h6'))return;
    const list=entries(),start=event.shiftKey?list.find(e=>e.dataset.resultId===anchor):null;
    const ends=[start||entry,entry].sort((a,b)=>list.indexOf(a)-list.indexOf(b));
    selectRange(entryRange(ends[0],ends[1]));if(!start)anchor=entry.dataset.resultId;
  });
  // Select all, anywhere on the page but in a field, selects every result: a
  // selection that took the toolbar as well would be copied as raw markup.
  document.addEventListener('keydown',event=>{
    if(event.defaultPrevented||event.isComposing||!host.isEditing()||field(event.target))return;
    if((event.metaKey||event.ctrlKey)&&!event.altKey&&event.key.toLowerCase()==='a'){event.preventDefault();selectAllResults();}
  },true);
  document.addEventListener('keydown',event=>{
    if(event.defaultPrevented||event.isComposing||!host.isEditing()||field(event.target)||!region()?.contains(event.target))return;
    if(!['Backspace','Delete'].includes(event.key))return;
    const range=currentRange();
    if(range?.collapsed&&(event.metaKey||event.ctrlKey||event.altKey))return;
    if(removeSelection(range,event.key==='Backspace'))event.preventDefault();
  });
  // Also covers WebKit's contextual Delete and accessibility editing actions.
  document.addEventListener('beforeinput',event=>{
    if(event.defaultPrevented||event.isComposing||!host.isEditing()||field(event.target)||!region()?.contains(event.target))return;
    if(event.inputType==='deleteContentBackward'||event.inputType==='deleteContentForward'||event.inputType==='deleteByCut') {
      if(removeSelection(clampSelection(currentRange()),event.inputType==='deleteContentBackward'))event.preventDefault();
    }
  });
}
