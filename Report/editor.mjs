import {explicitPictureWidth,wrapPicture,applyPictureWidth,fitPicture,pictureWidth} from './chart-size.mjs';
import {installTransfer,transferring,prepareClipboard,cutPrepared,preparePaste,pastePrepared,selectRange,clampSelection} from './transfer.mjs';
import {installDeletion,selectAllResults,selectResult} from './deletion.mjs';
import {region,entries,entryOf,entryById,entrySelector,inRegion,elementOf,field,emptyNotice,protectedSelector} from './region.mjs';
export {prepareClipboard,cutPrepared,preparePaste,pastePrepared,selectResult,explicitPictureWidth};
// The report is one editable region (see region.mjs). Results are blocks in it,
// identified by their result id, so that the host can replace a result, add the
// further output of a run to it, undo its edits and offer its help and R script.
// Nothing in the region is a control: help, chart sizing and the R script are
// offered by the host's toolbar and context menu.
let editing=false, savedRange=null, pendingSize=null, performing=false, context={};
let post=message=>{if(window.webkit?.messageHandlers?.statsDirectReport)window.webkit.messageHandlers.statsDirectReport.postMessage(message);else window.statsDirectReportHost?.post(message);};
const snapshots=new Map();   // result id -> the markup last reported to or received from the host
const fontSizes=[8,9,10,11,12,14,16,18,20,24,28,36,48,72];
const fonts=['Arial','Calibri','Cambria','Courier New','Georgia','Helvetica','Menlo','Times New Roman','Trebuchet MS','Verdana'];
const toggles=['bold','italic','underline','strikeThrough','subscript','superscript','insertUnorderedList','insertOrderedList','justifyLeft','justifyCenter','justifyRight','justifyFull'];
const allowed=new Set([...toggles,'fontName','fontSize','formatBlock','foreColor','hiliteColor','indent','outdent','lineSpacing','removeFormat','pictureWidth','pictureFit']);
const blockSelector='p,h1,h2,h3,h4,h5,h6,li,div,blockquote,td,th,pre';
const inlineStyled='font,b,strong,i,em,u,s,strike,del,sub,sup,span,mark,code,small,big';
const mac=/Mac|iPhone|iPad/.test(navigator.platform);
const key=label=>mac?'⌘'+label:'Ctrl+'+label;
const shiftKey=label=>mac?'⇧⌘'+label:'Ctrl+Shift+'+label;
function remember() {
  if(document.activeElement?.closest('#report-toolbar'))return;
  const selection=window.getSelection();
  if(selection?.rangeCount&&inRegion(selection.anchorNode))savedRange=selection.getRangeAt(0).cloneRange();
}
function toolbar() {
  const bar=document.getElementById('report-toolbar'),tools=document.getElementById('report-format-tools');tools.replaceChildren();
  const top=document.createElement('div');top.className='report-format-row';tools.append(top);
  const more=document.createElement('div');more.id='report-more-tools';more.className='report-more-tools';more.hidden=true;more.setAttribute('role','group');more.setAttribute('aria-label','More report formatting');tools.append(more);
  const row=()=>{const div=document.createElement('div');div.className='report-more-row';more.append(div);return div;};
  const styles=row(),colours=row(),paragraph=row();
  const icons={
    undo:'<path d="M7 4 3 8l4 4M3 8h8a6 6 0 0 1 0 12"/>',
    redo:'<path d="m17 4 4 4-4 4m4-4h-8a6 6 0 0 0 0 12"/>',
    insertUnorderedList:'<path d="M9 6h12M9 12h12M9 18h12"/><circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/><circle cx="4" cy="18" r="1"/>',
    insertOrderedList:'<path d="M10 6h11M10 12h11M10 18h11M3 4h1v4M3 8h2M3 12c0-2 3-2 3 0l-3 4h3M3 19h3l-2 2h2"/>',
    justifyLeft:'<path d="M3 5h18M3 10h12M3 15h18M3 20h12"/>',
    justifyCenter:'<path d="M3 5h18M6 10h12M3 15h18M6 20h12"/>',
    justifyRight:'<path d="M3 5h18M9 10h12M3 15h18M9 20h12"/>',
    justifyFull:'<path d="M3 5h18M3 10h18M3 15h18M3 20h18"/>'
  };
  function button(parent,name,label,title=label) {
    const b=document.createElement('button');b.type='button';b.dataset.command=name;b.title=title;b.setAttribute('aria-label',title);
    if(icons[name]) {b.className='report-icon-button';b.innerHTML=`<svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name]}</svg>`;}
    else b.textContent=label;
    if(toggles.includes(name))b.setAttribute('aria-pressed','false');
    b.onclick=()=>command(name);parent.append(b);return b;
  }
  function select(parent,name,label,options) {
    const wrap=document.createElement('label');wrap.title=label;
    if(parent!==top)wrap.append(document.createTextNode(label+' '));
    const input=document.createElement('select');input.dataset.format=name;input.setAttribute('aria-label',label);
    input.append(new Option(label,''));for(const [value,text] of options)input.append(new Option(text,value));
    input.onchange=()=>{if(input.value)command(name,input.value);};wrap.append(input);parent.append(wrap);return input;
  }
  button(top,'undo','Undo','Undo ('+key('Z')+')');button(top,'redo','Redo','Redo ('+shiftKey('Z')+')');
  select(top,'formatBlock','Style',[['p','Normal'],['h1','Heading 1'],['h2','Heading 2'],['h3','Heading 3']]);
  select(top,'fontName','Font',fonts.map(f=>[f,f]));
  const label=document.createElement('label');label.title='Font size in points';
  const size=document.createElement('input');size.type='text';size.inputMode='decimal';size.pattern='[0-9]+([.][0-9]+)?';size.autocomplete='off';size.placeholder='Size';size.dataset.format='fontSize';size.setAttribute('aria-label','Font size in points');size.setAttribute('list','report-font-sizes');
  size.onchange=()=>{if(size.value&&size.checkValidity())command('fontSize',size.value);};
  size.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();size.onchange();}};
  const list=document.createElement('datalist');list.id='report-font-sizes';for(const n of fontSizes)list.append(new Option(String(n),String(n)));
  label.append(size,list);top.append(label);
  for(const [name,text,title] of [['bold','B','Bold ('+key('B')+')'],['italic','I','Italic ('+key('I')+')'],['underline','U','Underline ('+key('U')+')']])button(top,name,text,title).classList.add('report-icon-button');
  for(const [name,text] of [['insertUnorderedList','Bullets'],['insertOrderedList','Numbering'],['justifyLeft','Align left'],['justifyCenter','Centre'],['justifyRight','Align right'],['justifyFull','Justify']])button(top,name,text);
  const toggle=document.createElement('button');toggle.type='button';toggle.id='report-more-toggle';toggle.textContent='More ⋯';toggle.title='More formatting';toggle.setAttribute('aria-label','More formatting');toggle.setAttribute('aria-controls',more.id);toggle.setAttribute('aria-expanded','false');top.append(toggle);
  function showMore(value) {more.hidden=!value;toggle.setAttribute('aria-expanded',String(value));}
  toggle.onclick=()=>showMore(more.hidden);
  document.addEventListener('pointerdown',event=>{if(!bar.contains(event.target))showMore(false);});
  document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!more.hidden){event.preventDefault();showMore(false);toggle.focus();}});
  for(const [name,text] of [['strikeThrough','Strikethrough'],['subscript','Subscript'],['superscript','Superscript']])button(styles,name,text);
  for(const [name,text,value] of [['foreColor','Text colour','#233748'],['hiliteColor','Highlight','#ffff00']]) {
    const wrap=document.createElement('label');wrap.textContent=text+' ';
    const input=document.createElement('input');input.type='color';input.value=value;input.dataset.format=name;input.setAttribute('aria-label',text);input.onchange=()=>command(name,input.value);wrap.append(input);colours.append(wrap);
  }
  for(const [name,text] of [['outdent','Decrease indent'],['indent','Increase indent']])button(paragraph,name,text);
  select(paragraph,'lineSpacing','Spacing',[['1','Single'],['1.15','1.15'],['1.5','1.5'],['2','Double']]);
  button(paragraph,'removeFormat','Clear formatting');
  // The selected chart or picture: its width in pixels, or the report's width. Shown while a picture is selected.
  const picture=document.createElement('span');picture.className='report-picture-tools';picture.hidden=true;top.append(picture);
  const widthLabel=document.createElement('label');widthLabel.append('Width ');
  const width=document.createElement('input');width.type='number';width.min='80';width.step='1';width.dataset.format='pictureWidth';width.setAttribute('aria-label','Chart width in pixels');width.title='Width of the selected chart or picture, in pixels';
  width.onchange=()=>{if(width.value)command('pictureWidth',width.value);};
  width.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();width.onchange();}};
  widthLabel.append(width,' px');picture.append(widthLabel);
  button(picture,'pictureFit','Fit','Fit the selected chart to the report width');
  const add=bar.querySelector('[data-command="addText"]');if(add){add.textContent='+ Text';add.title='Add a text section';add.setAttribute('aria-label','Add text');}
}
// The selected picture, when the selection is exactly one chart or picture.
export function selectedPicture() {
  if(document.activeElement?.matches?.('.report-media'))return document.activeElement.querySelector('svg,img');
  const selection=window.getSelection();
  if(document.activeElement?.closest?.('#report-toolbar')&&savedRange&&document.contains(savedRange.commonAncestorContainer)) {
    const node=savedRange.collapsed?null:savedRange.startContainer.childNodes?.[savedRange.startOffset];
    const wrapper=node?.nodeType===1&&node.matches('.report-media')?node:elementOf(savedRange.startContainer)?.closest?.('.report-media');
    if(wrapper&&inRegion(wrapper))return wrapper.querySelector('svg,img');
  }
  if(!selection?.rangeCount)return null;
  const range=selection.getRangeAt(0);
  const node=range.startContainer,media=range.collapsed?null:elementOf(node)?.closest?.('.report-media')||(node.nodeType===1?node.childNodes[range.startOffset]:null);
  const wrapper=media?.classList?.contains('report-media')?media:media?.closest?.('.report-media');
  return wrapper&&inRegion(wrapper)?wrapper.querySelector('svg,img'):null;
}
function updateControls() {
  if(!editing||document.activeElement?.closest('#report-format-tools'))return;
  const selection=window.getSelection(),root=region();if(!root||!selection?.rangeCount||!inRegion(selection.anchorNode))return;
  for(const name of toggles)document.querySelector(`[data-command="${name}"]`)?.setAttribute('aria-pressed',String(document.queryCommandState(name)));
  const range=selection.getRangeAt(0),nodes=[];
  if(range.collapsed)nodes.push(elementOf(selection.anchorNode));
  else {const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);let node;while((node=walker.nextNode()))if(node.textContent.trim()&&range.intersectsNode(node)&&!(range.startContainer===node&&range.startOffset===node.length)&&!(range.endContainer===node&&range.endOffset===0)&&!node.parentElement.closest('[contenteditable="false"]'))nodes.push(node.parentElement);}
  const common=property=>{const values=new Set(nodes.map(n=>getComputedStyle(n)[property]));return values.size===1?[...values][0]:'';};
  const family=common('fontFamily').split(',')[0].replace(/["']/g,'').trim();
  const font=document.querySelector('[data-format="fontName"]');if(family&&![...font.options].some(o=>o.value===family))font.append(new Option(family,family));font.value=family;
  const size=common('fontSize');document.querySelector('[data-format="fontSize"]').value=pendingSize??(size?Math.round(parseFloat(size)*.75*100)/100:'');
  const block=document.querySelector('[data-format="formatBlock"]');block.value=document.queryCommandValue('formatBlock').toLowerCase().replace(/[<>]/g,'');
  const spacing=common('lineHeight'),base=common('fontSize');document.querySelector('[data-format="lineSpacing"]').value=spacing&&base?String(Math.round(parseFloat(spacing)/parseFloat(base)*100)/100):'';
  const picture=selectedPicture(),width=document.querySelector('[data-format="pictureWidth"]'),fit=document.querySelector('[data-command="pictureFit"]');
  // The field keeps its focus (and its value) while it is being typed in; the picture stays selected meanwhile.
  const tools=document.querySelector('.report-picture-tools');
  if(width&&document.activeElement!==width&&document.activeElement!==fit){tools.hidden=!picture;width.disabled=!picture;fit.disabled=!picture;width.value=picture?String(pictureWidth(picture)):'';}
}
// WebKit's fontSize command uses HTML sizes 1–7. Convert its temporary size 7
// immediately to an exact point size; the pending value also covers new typing.
function exactSizes(root,size=pendingSize) {
  for(const font of root.querySelectorAll('font[size]')) {
    font.style.fontSize=Number(font.getAttribute('size'))===7&&size?`${size}pt`:`${[0,8,10,12,14,18,24,36][Number(font.getAttribute('size'))]||12}pt`;
    font.removeAttribute('size');
    if(font.face){font.style.fontFamily=font.face;font.removeAttribute('face');}
    if(font.color){font.style.color=font.color;font.removeAttribute('color');}
  }
}
// The innermost blocks the range touches, anywhere in the region, leaving out protected content.
function selectedBlocks(range) {
  const root=region();
  if(range.collapsed){const block=elementOf(range.startContainer)?.closest(blockSelector);return block&&root.contains(block)&&!block.matches(entrySelector)&&block!==root?[block]:[];}
  return [...root.querySelectorAll(blockSelector)].filter(el=>range.intersectsNode(el)&&!el.closest('[contenteditable="false"]')&&!el.matches(entrySelector)&&![...el.querySelectorAll(blockSelector)].some(child=>range.intersectsNode(child)));
}
const textProperties=['font-family','font-size','font-weight','font-style','text-decoration','text-decoration-line','text-decoration-color','text-decoration-style','color','background-color','vertical-align','letter-spacing','text-transform','text-shadow'];
const blockProperties=[...textProperties,'line-height','text-align','text-indent','margin-left','margin-right','padding-left'];
// Clear formatting as a word processor does: with a caret the paragraph at the
// caret, with a selection every block the selection touches. Inline formatting
// elements are unwrapped and inline text styles removed; block styles too. The
// headings and lists of a result are its structure and stay. Protected content
// (a chart, the inputs record) is passed over, never a reason to stop.
function clearFormatting(range) {
  const blocks=selectedBlocks(range);
  const whole=block=>range.collapsed||(range.compareBoundaryPoints(Range.START_TO_START,fullRange(block))<=0&&range.compareBoundaryPoints(Range.END_TO_END,fullRange(block))>=0);
  const fullRange=node=>{const r=document.createRange();r.selectNode(node);return r;};
  const touched=blocks.filter(block=>!block.closest('[contenteditable="false"]'));
  if(!range.collapsed&&touched.some(block=>!whole(block))) {
    // Partial blocks: the browser's own command clears the selected run of text.
    document.execCommand('styleWithCSS',false,true);document.execCommand('removeFormat',false,null);
  }
  for(const block of touched) {
    if(whole(block)) {
      for(const el of [...block.querySelectorAll(inlineStyled)].reverse())if(!el.closest('[contenteditable="false"]')&&!el.closest('svg')) {
        if(el.matches('span,font,mark,small,big')||el.matches('b,strong,i,em,u,s,strike,del,sub,sup,code'))el.replaceWith(...el.childNodes);
      }
      for(const el of block.querySelectorAll('[style]'))if(!el.closest('[contenteditable="false"]')&&!el.closest('svg'))for(const property of textProperties)el.style.removeProperty(property);
    }
    for(const property of blockProperties)block.style.removeProperty(property);
    if(!block.getAttribute('style'))block.removeAttribute('style');
    block.normalize();
  }
  return touched.length>0;
}
// Every piece of a result remembers its result. WebKit's block commands (a heading,
// a list, an alignment, an indent) can lift a piece out of its result's block or
// split the block in two; the pieces go back to their result, in order, and split
// halves become one block again. Content that lands between results with no
// known owner (new nodes) joins the result the selection is in, or its neighbour.
const owners=new WeakMap();
function tagOwners() {
  for(const entry of entries())for(const child of entry.children)owners.set(child,entry.dataset.resultId);
}
function ownerOf(node) {
  if(node.nodeType!==Node.ELEMENT_NODE)return null;
  if(owners.has(node))return owners.get(node);
  for(const el of node.querySelectorAll('*'))if(owners.has(el))return owners.get(el);
  return null;
}
function absorbStrays(root) {
  const selection=window.getSelection(),focused=selection?.rangeCount?entryOf(selection.anchorNode):null;
  for(const node of [...root.childNodes]) {
    if(node.nodeType===Node.ELEMENT_NODE&&node.matches(entrySelector))continue;
    if(node.nodeType===Node.TEXT_NODE&&!node.textContent.trim()){node.remove();continue;}
    const owner=ownerOf(node),known=owner?entryById(owner):null;
    let target=known&&known.parentElement===root?known:focused&&focused.parentElement===root?focused:null;
    if(!target) {
      let previous=node.previousSibling;while(previous&&!(previous.nodeType===1&&previous.matches(entrySelector)))previous=previous.previousSibling;
      let next=node.nextSibling;while(next&&!(next.nodeType===1&&next.matches(entrySelector)))next=next.nextSibling;
      target=previous||next;
    }
    if(!target){node.remove();continue;}
    if(node.compareDocumentPosition(target)&Node.DOCUMENT_POSITION_FOLLOWING)target.prepend(node);else target.append(node);
  }
  // A result pasted inside another stays content: one level of results only.
  for(const entry of root.querySelectorAll(entrySelector))if(entry.parentElement!==root){entry.removeAttribute('data-result-id');entry.removeAttribute('id');entry.classList.remove('report-entry');}
  // Split halves are one result again, in order.
  let previous=null;
  for(const entry of [...root.children]) {
    if(!entry.matches(entrySelector)){previous=null;continue;}
    if(previous&&previous.dataset.resultId===entry.dataset.resultId){previous.append(...entry.childNodes);entry.remove();continue;}
    previous=entry;
  }
  tagOwners();
}
function protect() {
  const root=region();if(!root)return;
  absorbStrays(root);
  for(const entry of entries()) {
    if(!entry.hasChildNodes())entry.innerHTML='<p><br></p>';
    exactSizes(entry);
    [...entry.querySelectorAll('svg')].filter(svg=>!svg.parentElement.closest('svg')).forEach((svg,index)=>{
      if(svg.closest('.report-media'))return;
      svg.dataset.reportChartIndex=String(Number(svg.dataset.reportChartIndex??index));
      wrapPicture(svg);
    });
    for(const img of entry.querySelectorAll('img'))if(!img.closest('.report-media,svg,.report-links'))wrapPicture(img);
    entry.querySelectorAll(protectedSelector).forEach(el=>{el.contentEditable='false';});
  }
  const notice=emptyNotice();if(notice)notice.hidden=entries().length>0;
}
export function serialize(entry) {
  const clone=entry.cloneNode(true);
  clone.querySelectorAll('.report-controls').forEach(el=>el.remove());
  clone.querySelectorAll('.report-media,.report-chart').forEach(el=>el.replaceWith(...el.childNodes));
  clone.querySelectorAll('[contenteditable],[tabindex],[draggable]').forEach(el=>{el.removeAttribute('contenteditable');el.removeAttribute('tabindex');el.removeAttribute('draggable');});
  clone.querySelectorAll('.report-media-selected').forEach(el=>el.classList.remove('report-media-selected'));
  return clone.innerHTML;
}
function remeasure(entry){snapshots.set(entry.dataset.resultId,serialize(entry));}
// What changed since the host last heard: the results whose markup differs,
// those that are gone (deleted as a whole or emptied by editing), as one message.
function changed(inputType='') {
  const root=region();if(!root)return;
  protect();
  const present=new Map(entries().map(entry=>[entry.dataset.resultId,entry]));
  const remove=[];
  for(const [id,entry] of present)if(!entry.textContent.trim()&&!entry.querySelector('svg,img,table,hr')){entry.remove();present.delete(id);remove.push(id);}
  for(const id of snapshots.keys())if(!present.has(id)&&!remove.includes(id))remove.push(id);
  const edits=[];
  for(const [id,entry] of present){const html=serialize(entry);if(html!==snapshots.get(id)){edits.push({id,html});snapshots.set(id,html);}}
  for(const id of remove)snapshots.delete(id);
  const notice=emptyNotice();if(notice)notice.hidden=present.size>0;
  if(!edits.length&&!remove.length)return;
  const typing=inputType==='insertText'||inputType==='deleteContentBackward'||inputType==='deleteContentForward';
  if(edits.length===1&&!remove.length)post({action:'editBody',resultID:edits[0].id,html:edits[0].html,typing});
  else post({action:'editBodies',edits,remove});
}
export function history(undo,redo) {
  document.querySelector('[data-command="undo"]').disabled=!undo;
  document.querySelector('[data-command="redo"]').disabled=!redo;
}
export function setEditing(value,notify=true) {
  editing=value;
  document.body.classList.toggle('report-editing',value);
  const root=region();if(root){root.contentEditable=String(value);protect();}
  const toggle=document.getElementById('report-edit-toggle');
  if(toggle){toggle.textContent=value?'Done':'Edit report';toggle.title=value?'Done editing':'Edit report';toggle.setAttribute('aria-label',toggle.title);toggle.setAttribute('aria-pressed',String(value));}
  const tools=document.getElementById('report-format-tools');if(tools)tools.hidden=!value;
  if(!value){savedRange=null;pendingSize=null;const more=document.getElementById('report-more-tools');if(more)more.hidden=true;document.getElementById('report-more-toggle')?.setAttribute('aria-expanded','false');}
  if(notify)post({action:'editing',value});
  updateControls();
}
// A result's markup from the host: the whole block (an article with its result id).
function parse(html) {
  const template=document.createElement('template');template.innerHTML=html;
  const block=template.content.firstElementChild;
  if(!block||!block.matches(entrySelector))throw new Error('A report result must be a block with its result id.');
  return block;
}
export function replace(id,html) {
  const old=entryById(id);if(!old)return;
  const replacement=parse(html);
  const hadFocus=old.contains(document.activeElement)||(inRegion(document.activeElement)&&old.contains(window.getSelection()?.anchorNode)),scroll=window.scrollY;
  old.replaceWith(replacement);protect();remeasure(replacement);savedRange=null;
  if(editing&&hadFocus){const range=document.createRange();range.selectNodeContents(replacement);range.collapse(false);selectRange(range);window.scrollTo(0,scroll);}
}
export function replaceEntries(list,order=null) {
  const scroll=window.scrollY,root=region();
  const focused=entryOf(document.activeElement)||entryOf(window.getSelection()?.anchorNode),index=focused?entries().indexOf(focused):0;
  const refocus=document.activeElement===root||!!focused;
  if(order)for(const entry of entries())if(!order.includes(entry.dataset.resultId)){entry.remove();snapshots.delete(entry.dataset.resultId);}
  for(const {id,html} of list) {
    if(entryById(id))replace(id,html);
    else {const block=parse(html);root.append(block);protect();remeasure(block);}
  }
  if(order)order.forEach((id,position)=>{const entry=entryById(id);const current=entries();if(entry&&current[position]!==entry)root.insertBefore(entry,current[position]||null);});
  protect();
  if(refocus&&!inRegion(document.activeElement)&&!inRegion(window.getSelection()?.anchorNode)) {
    const current=entries(),target=current[Math.min(index,current.length-1)];
    if(target){const range=document.createRange();range.selectNodeContents(target);range.collapse(true);selectRange(range);}
    else root.focus({preventScroll:true});
  }
  savedRange=null;
  window.scrollTo(0,scroll);
}
// More of a result into its block (a chart after its analysis): added by the host, not an edit.
export function extend(id,html) {
  const entry=entryById(id);if(!entry)return false;
  const template=document.createElement('template');template.innerHTML=html;
  entry.append(template.content);protect();remeasure(entry);return true;
}
// A result scrolled so that its top is just below the toolbar; a result near
// the end of the report gets the room below it to reach there.
export function reveal(id) {
  const entry=entryById(id),root=region();if(!entry||!root)return false;
  const bar=document.getElementById('report-toolbar'),gap=(bar?bar.getBoundingClientRect().height:0)+8;
  const room=Math.max(0,window.innerHeight-gap-entry.getBoundingClientRect().height);
  root.style.setProperty('--reveal-room',room+'px');
  window.scrollTo({top:entry.getBoundingClientRect().top+window.scrollY-gap,behavior:'auto'});
  return true;
}
export function selectAll(){return selectAllResults();}
// What a right-click is on, for the host's context menu: the result, its help
// and R, whether text is selected, whether a chart is there and the place is editable.
export function contextTarget(){return context;}
function describe(node) {
  const entry=entryOf(node),selection=window.getSelection(),picture=elementOf(node)?.closest('.report-media')?.querySelector('svg,img')||null;
  return {resultId:entry?.dataset.resultId??null,help:entry?.dataset.help||null,r:entry?.dataset.r||null,title:entry?.getAttribute('aria-label')||null,
    hasSelection:!!selection&&!selection.isCollapsed&&inRegion(selection.anchorNode),editable:editing&&inRegion(node)&&!elementOf(node)?.closest('[contenteditable="false"]'),
    picture:!!picture,pictureWidth:picture?pictureWidth(picture):null,inReport:inRegion(node)};
}
export function command(name,value=null) {
  if(name==='toggle'){setEditing(!editing);return;}
  if(name==='addText'){post({action:'addText'});return;}
  if(name==='undo'||name==='redo'){pendingSize=null;post({action:name==='undo'?'undoText':'redoText'});return;}
  if(name==='selectAll'){selectAllResults();return;}
  if(!editing||!allowed.has(name))return;
  if(name==='fontSize'&&(!Number.isFinite(Number(value))||Number(value)<6||Number(value)>96))return;
  if(name==='lineSpacing'&&!['1','1.15','1.5','2'].includes(String(value)))return;
  if(name==='formatBlock'&&!['p','h1','h2','h3'].includes(value))return;
  if(name==='pictureWidth'||name==='pictureFit') {
    const picture=selectedPicture();if(!picture)return;
    const did=name==='pictureFit'?fitPicture(picture):applyPictureWidth(picture,Number(value));
    if(did)changed();updateControls();return;
  }
  // Controls can own focus while the report selection remains visible in WebKit.
  if(!document.activeElement?.closest('#report-toolbar'))remember();
  const selection=window.getSelection(),root=region();
  if(savedRange&&document.contains(savedRange.commonAncestorContainer)){selection.removeAllRanges();selection.addRange(savedRange);}
  if(!root||!selection.rangeCount)return;
  const range=selection.getRangeAt(0);
  if(!inRegion(range.startContainer)||!inRegion(range.endContainer)||elementOf(range.startContainer)?.closest('[contenteditable="false"]'))return;
  root.focus({preventScroll:true});performing=true;
  try {
    if(name==='fontSize') {
      exactSizes(root);pendingSize=Number(value);
      document.execCommand('styleWithCSS',false,false);document.execCommand('fontSize',false,'7');exactSizes(root,pendingSize);if(!range.collapsed)pendingSize=null;
    } else if(name==='lineSpacing') {
      let blocks=selectedBlocks(range);
      if(!blocks.length){document.execCommand('formatBlock',false,'p');blocks=selectedBlocks(selection.getRangeAt(0));}
      for(const block of blocks)block.style.lineHeight=value;
    } else if(name==='removeFormat') {
      pendingSize=null;clearFormatting(range);
    } else {
      document.execCommand('styleWithCSS',false,true);document.execCommand(name,false,value);
    }
    remember();changed();updateControls();
  } finally {performing=false;}
}
export function menuCommand(name,value=null) {
  if(!editing)return false;
  if(['undo','redo','selectAll'].includes(name)) {
    if(field(document.activeElement))return false;
    if(!document.activeElement?.closest('#report-results,#results,#report-toolbar'))return false;
    if(name==='selectAll')selectAllResults();else command(name);return true;
  }
  if(!inRegion(window.getSelection()?.anchorNode)&&!(savedRange&&document.contains(savedRange.commonAncestorContainer)))return false;
  command(name,value);return true;
}
export function start({editing:initial=false,undo=false,redo=false,post:bridge=null}={}) {
  if(bridge)post=bridge;
  toolbar();
  for(const entry of entries())remeasure(entry);
  setEditing(initial,false);history(undo,redo);
  const hooks={isEditing:()=>editing,serialize,protect,detach:()=>{},post:m=>post(m),remember};
  installTransfer(hooks);
  installDeletion(hooks);
  document.getElementById('report-toolbar').addEventListener('mousedown',event=>{remember();if(event.target.closest('button'))event.preventDefault();});
  document.addEventListener('selectionchange',()=>{remember();updateControls();});
  document.addEventListener('pointerdown',event=>{if(inRegion(event.target))pendingSize=null;});
  document.addEventListener('input',event=>{if(editing&&inRegion(event.target)&&!performing&&!transferring()&&!field(event.target)){changed(event.inputType);updateControls();}});
  document.addEventListener('contextmenu',event=>{context=describe(event.target);post({action:'context',...context});});
  document.addEventListener('keydown',event=>{
    if(event.defaultPrevented||event.isComposing||!editing||field(event.target)||!event.target.closest('#report-results,#results,#report-toolbar'))return;
    if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key))pendingSize=null;
    if(!event.metaKey&&!event.ctrlKey)return;
    if(event.key.toLowerCase()==='z'){event.preventDefault();command(event.shiftKey?'redo':'undo');}
    if(event.target.closest('.report-controls'))return;
    if(['b','i','u'].includes(event.key.toLowerCase())){event.preventDefault();command({b:'bold',i:'italic',u:'underline'}[event.key.toLowerCase()]);}
  });
}
