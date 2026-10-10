import {attachPictureSizing,detachPictureSizing} from './chart-size.mjs';
import {installTransfer,transferring,prepareClipboard,cutPrepared,preparePaste,pastePrepared} from './transfer.mjs';
export {prepareClipboard,cutPrepared,preparePaste,pastePrepared};
let editing=false, savedRange=null, pendingSize=null, performing=false;
const fontSizes=[8,9,10,11,12,14,16,18,20,24,28,36,48,72];
const fonts=['Arial','Calibri','Cambria','Courier New','Georgia','Helvetica','Menlo','Times New Roman','Trebuchet MS','Verdana'];
const toggles=['bold','italic','underline','strikeThrough','subscript','superscript','insertUnorderedList','insertOrderedList','justifyLeft','justifyCenter','justifyRight','justifyFull'];
const allowed=new Set([...toggles,'fontName','fontSize','formatBlock','foreColor','hiliteColor','indent','outdent','lineSpacing','removeFormat']);
const elementOf=node=>node?.nodeType===1?node:node?.parentElement;
function remember() {
  if(document.activeElement?.closest('#report-toolbar'))return;
  const selection=window.getSelection();
  if(selectionBody()&&selection?.rangeCount)savedRange=selection.getRangeAt(0).cloneRange();
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
  button(top,'undo','Undo','Undo (⌘Z)');button(top,'redo','Redo','Redo (⇧⌘Z)');
  select(top,'formatBlock','Style',[['p','Normal'],['h1','Heading 1'],['h2','Heading 2'],['h3','Heading 3']]);
  select(top,'fontName','Font',fonts.map(f=>[f,f]));
  const label=document.createElement('label');label.title='Font size in points';
  const size=document.createElement('input');size.type='text';size.inputMode='decimal';size.pattern='[0-9]+([.][0-9]+)?';size.autocomplete='off';size.placeholder='Size';size.dataset.format='fontSize';size.setAttribute('aria-label','Font size in points');size.setAttribute('list','report-font-sizes');
  size.onchange=()=>{if(size.value&&size.checkValidity())command('fontSize',size.value);};
  size.onkeydown=e=>{if(e.key==='Enter'){e.preventDefault();size.onchange();}};
  const list=document.createElement('datalist');list.id='report-font-sizes';for(const n of fontSizes)list.append(new Option(String(n),String(n)));
  label.append(size,list);top.append(label);
  for(const [name,text,title] of [['bold','B','Bold (⌘B)'],['italic','I','Italic (⌘I)'],['underline','U','Underline (⌘U)']])button(top,name,text,title).classList.add('report-icon-button');
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
  const add=bar.querySelector('[data-command="addText"]');if(add){add.textContent='+ Text';add.title='Add a text section';add.setAttribute('aria-label','Add text');}
  const removal=[...bar.children].find(el=>el.tagName==='BUTTON'&&el!==document.getElementById('report-edit-toggle')&&el!==add);
  if(removal)removal.classList.add('report-undo-removal');
}
function updateControls() {
  if(!editing||document.activeElement?.closest('#report-format-tools'))return;
  const selection=window.getSelection(),body=selectionBody();if(!body)return;
  for(const name of toggles)document.querySelector(`[data-command="${name}"]`)?.setAttribute('aria-pressed',String(document.queryCommandState(name)));
  const range=selection.getRangeAt(0),nodes=[];
  if(range.collapsed)nodes.push(elementOf(selection.anchorNode));
  else {const walker=document.createTreeWalker(body,NodeFilter.SHOW_TEXT);let node;while((node=walker.nextNode()))if(node.textContent.trim()&&range.intersectsNode(node)&&!(range.startContainer===node&&range.startOffset===node.length)&&!(range.endContainer===node&&range.endOffset===0)&&!node.parentElement.closest('[contenteditable="false"]'))nodes.push(node.parentElement);}
  const common=property=>{const values=new Set(nodes.map(n=>getComputedStyle(n)[property]));return values.size===1?[...values][0]:'';};
  const family=common('fontFamily').split(',')[0].replace(/["']/g,'').trim();
  const font=document.querySelector('[data-format="fontName"]');if(family&&![...font.options].some(o=>o.value===family))font.append(new Option(family,family));font.value=family;
  const size=common('fontSize');document.querySelector('[data-format="fontSize"]').value=pendingSize??(size?Math.round(parseFloat(size)*.75*100)/100:'');
  const block=document.querySelector('[data-format="formatBlock"]');block.value=document.queryCommandValue('formatBlock').toLowerCase().replace(/[<>]/g,'');
  const spacing=common('lineHeight'),base=common('fontSize');document.querySelector('[data-format="lineSpacing"]').value=spacing&&base?String(Math.round(parseFloat(spacing)/parseFloat(base)*100)/100):'';
}
// WebKit's fontSize command uses HTML sizes 1–7. Convert its temporary size 7
// immediately to an exact point size; the pending value also covers new typing.
function exactSizes(body,size=pendingSize) {
  for(const font of body.querySelectorAll('font[size]')) {
    font.style.fontSize=Number(font.getAttribute('size'))===7&&size?`${size}pt`:`${[0,8,10,12,14,18,24,36][Number(font.getAttribute('size'))]||12}pt`;
    font.removeAttribute('size');
    if(font.face){font.style.fontFamily=font.face;font.removeAttribute('face');}
    if(font.color){font.style.color=font.color;font.removeAttribute('color');}
  }
}
function selectedBlocks(body,range) {
  const selector='p,h1,h2,h3,h4,h5,h6,li,div,blockquote,td,th';
  if(range.collapsed){const block=elementOf(range.startContainer)?.closest(selector);return block&&body.contains(block)&&block!==body?[block]:[];}
  return [...body.querySelectorAll(selector)].filter(el=>range.intersectsNode(el)&&!el.closest('[contenteditable="false"]')&&![...el.querySelectorAll(selector)].some(child=>range.intersectsNode(child)));
}
const post=message=>window.webkit.messageHandlers.statsDirectReport.postMessage(message);
const bodies=()=>[...document.querySelectorAll('.report-body')];
function selectionBody() {
  const selection=window.getSelection(),node=selection?.anchorNode;
  return (node?.nodeType===1?node:node?.parentElement)?.closest('.report-body');
}
function protect(body) {
  exactSizes(body);
  const hidden=new Set((body.dataset.hiddenCharts||'').split(',').filter(Boolean).map(Number));
  [...body.querySelectorAll('svg')].filter(svg=>!svg.parentElement.closest('svg')).forEach((svg,index)=>{
    if(svg.closest('.report-chart'))return;
    const chart=Number(svg.dataset.reportChartIndex??index);svg.dataset.reportChartIndex=String(chart);
    const wrapper=document.createElement('div');wrapper.className='report-chart';wrapper.hidden=hidden.has(chart);
    const controls=document.createElement('div');controls.className='report-controls';
    const button=document.createElement('button');button.textContent='Remove plot';
    button.onclick=()=>post({action:'hideChart',resultID:body.dataset.resultId,index:chart});controls.append(button);
    svg.replaceWith(wrapper);wrapper.append(controls,svg);
    attachPictureSizing(svg,wrapper,controls,()=>changed(body),()=>editing);
  });
  for(const img of body.querySelectorAll('img')) {
    if(img.closest('.report-media,svg,.report-links'))continue;
    const wrapper=document.createElement('div'),controls=document.createElement('div');controls.className='report-controls';
    img.replaceWith(wrapper);wrapper.append(controls,img);
    attachPictureSizing(img,wrapper,controls,()=>changed(body),()=>editing);
  }
  body.querySelectorAll('.report-media,.report-chart,.report-links,details,svg,img,.report-import-warning').forEach(el=>el.contentEditable='false');
}
export function serialize(body) {
  const clone=body.cloneNode(true);
  clone.querySelectorAll('.report-controls').forEach(el=>el.remove());
  clone.querySelectorAll('.report-media,.report-chart').forEach(el=>el.replaceWith(...el.childNodes));
  clone.querySelectorAll('[contenteditable]').forEach(el=>el.removeAttribute('contenteditable'));
  return clone.innerHTML;
}
function changed(body,inputType='') {
  if(!body)return;
  protect(body);
  post({action:'editBody',resultID:body.dataset.resultId,html:serialize(body),typing:inputType==='insertText'||inputType==='deleteContentBackward'||inputType==='deleteContentForward'});
}
export function history(undo,redo) {
  document.querySelector('[data-command="undo"]').disabled=!undo;
  document.querySelector('[data-command="redo"]').disabled=!redo;
}
export function setEditing(value,notify=true) {
  editing=value;
  document.body.classList.toggle('report-editing',value);
  for(const body of bodies()) {body.contentEditable=String(value);protect(body);}
  const toggle=document.getElementById('report-edit-toggle');toggle.textContent=value?'Done':'Edit report';toggle.title=value?'Done editing':'Edit report';toggle.setAttribute('aria-label',toggle.title);toggle.setAttribute('aria-pressed',String(value));
  document.getElementById('report-format-tools').hidden=!value;
  if(!value){savedRange=null;pendingSize=null;document.getElementById('report-more-tools').hidden=true;document.getElementById('report-more-toggle').setAttribute('aria-expanded','false');}
  if(notify)post({action:'editing',value});
  updateControls();
}
export function replace(id,html) {
  const old=document.getElementById('result-'+id);if(!old)return;
  const template=document.createElement('template');template.innerHTML=html;const replacement=template.content.firstElementChild;
  const hadFocus=old.contains(document.activeElement),scroll=window.scrollY;
  detachPictureSizing(old);old.replaceWith(replacement);const body=replacement.querySelector('.report-body');body.contentEditable=String(editing);protect(body);savedRange=null;
  if(editing&&hadFocus){body.focus();const range=document.createRange();range.selectNodeContents(body);range.collapse(false);const sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);window.scrollTo(0,scroll);}
}
export function replaceEntries(entries) {
  const scroll=window.scrollY;
  for(const {id,html} of entries)replace(id,html);
  window.scrollTo(0,scroll);
}
export function command(name,value=null) {
  if(name==='toggle'){setEditing(!editing);return;}
  if(name==='addText'){post({action:'addText'});return;}
  if(name==='undo'||name==='redo'){pendingSize=null;post({action:name==='undo'?'undoText':'redoText'});return;}
  if(!editing||!allowed.has(name))return;
  if(name==='fontSize'&&(!Number.isFinite(Number(value))||Number(value)<6||Number(value)>96))return;
  if(name==='lineSpacing'&&!['1','1.15','1.5','2'].includes(String(value)))return;
  if(name==='formatBlock'&&!['p','h1','h2','h3'].includes(value))return;
  // Controls can own focus while the report selection remains visible in WebKit.
  if(!document.activeElement?.closest('#report-toolbar'))remember();
  const selection=window.getSelection();
  if(savedRange&&document.contains(savedRange.commonAncestorContainer)){selection.removeAllRanges();selection.addRange(savedRange);}
  const body=selectionBody();if(!body||!selection.rangeCount)return;
  const range=selection.getRangeAt(0);
  if(!body.contains(range.endContainer)||elementOf(range.startContainer)?.closest('[contenteditable="false"]'))return;
  if([...body.querySelectorAll('[contenteditable="false"]')].some(el=>range.intersectsNode(el)))return;
  body.focus();performing=true;
  try {
    if(name==='fontSize') {
      exactSizes(body);pendingSize=Number(value);
      document.execCommand('styleWithCSS',false,false);document.execCommand('fontSize',false,'7');exactSizes(body,pendingSize);if(!range.collapsed)pendingSize=null;
    } else if(name==='lineSpacing') {
      let blocks=selectedBlocks(body,range);
      if(!blocks.length){document.execCommand('formatBlock',false,'p');blocks=selectedBlocks(body,selection.getRangeAt(0));}
      for(const block of blocks)block.style.lineHeight=value;
    } else {
      document.execCommand('styleWithCSS',false,true);document.execCommand(name,false,value);
      if(name==='removeFormat') {
        pendingSize=null;
        for(const block of selectedBlocks(body,selection.getRangeAt(0)).filter(el=>selection.toString().includes(el.textContent)))for(const prop of ['font-family','font-size','font-weight','font-style','text-decoration','text-decoration-line','color','background-color','vertical-align'])block.style.removeProperty(prop);
      }
    }
    remember();changed(body);updateControls();
  } finally {performing=false;}
}
export function menuCommand(name,value=null) {
  if(!editing)return false;
  if(['undo','redo'].includes(name)&&!document.activeElement?.closest('.report-body,#report-toolbar'))return false;
  if(['undo','redo'].includes(name)&&document.activeElement?.closest('.report-media')){command(name);return true;}
  if(!selectionBody()&&!(savedRange&&document.contains(savedRange.commonAncestorContainer)))return false;
  command(name,value);return true;
}
export function start({editing:initial=false,undo=false,redo=false}={}) {
  toolbar();setEditing(initial,false);history(undo,redo);
  installTransfer({isEditing:()=>editing,serialize,protect,detach:detachPictureSizing,post,remember});
  document.getElementById('report-toolbar').addEventListener('mousedown',event=>{remember();if(event.target.closest('button'))event.preventDefault();});
  document.addEventListener('selectionchange',()=>{remember();updateControls();});
  document.addEventListener('pointerdown',event=>{if(event.target.closest('.report-body'))pendingSize=null;});
  document.addEventListener('input',event=>{const body=event.target.closest('.report-body');if(editing&&body&&!performing&&!transferring()&&!event.target.closest('.report-controls')){changed(body,event.inputType);updateControls();}});
  document.addEventListener('keydown',event=>{
    if(!editing||!event.target.closest('.report-body'))return;
    if(['ArrowLeft','ArrowRight','ArrowUp','ArrowDown','Home','End'].includes(event.key))pendingSize=null;
    if(!event.metaKey&&!event.ctrlKey)return;
    if(event.key.toLowerCase()==='z'){event.preventDefault();command(event.shiftKey?'redo':'undo');}
    if(event.target.closest('.report-controls'))return;
    if(['b','i','u'].includes(event.key.toLowerCase())){event.preventDefault();command({b:'bold',i:'italic',u:'underline'}[event.key.toLowerCase()]);}
  });
}
