// A picture's chosen width lives on the picture itself, so it stays vector
// based and height:auto keeps its proportions in every report format. The
// sizing controls belong to the toolbar and the context menu, not the report:
// the body holds content only.
export function explicitPictureWidth(picture, fallback) {
  // HTML/R charts can specify a display width in the attribute while their
  // bitmap is twice that size. CSS (including Fit's percentage) takes priority.
  const value=picture.style.width||picture.getAttribute('width')||'';
  const size=value.trim().match(/^(\d+(?:\.\d+)?|\.\d+)(px|pt|in|cm|mm|pc|q)?$/i);
  const units={px:1,pt:4/3,in:96,cm:96/2.54,mm:96/25.4,pc:16,q:96/101.6};
  return size&&Number(size[1])>0?Number(size[1])*units[(size[2]||'px').toLowerCase()]:fallback;
}

// Pictures are edited as units: the wrapper is not editable text, can take the
// focus (the keyboard selects and deletes it) and names itself for assistive technology.
export function wrapPicture(picture,wrapper=document.createElement('div')) {
  wrapper.classList.add('report-media');
  wrapper.contentEditable='false';wrapper.tabIndex=0;
  wrapper.setAttribute('aria-label',picture.localName==='svg'?'Chart':'Picture');
  if(wrapper!==picture.parentElement){picture.replaceWith(wrapper);wrapper.append(picture);}
  ensureHandle(wrapper);
  return wrapper;
}
// The one control a chart carries: the corner marker at its bottom right while editing, which drags to
// resize it (proportions kept). With the focus on the marker, the arrow keys adjust the size, Shift in
// larger steps. It is a control, so it is never part of the result's text or of a saved report.
const HANDLE='report-chart-resize';
const pictureIn=wrapper=>wrapper.querySelector(':scope>svg,:scope>img');
const observer=typeof ResizeObserver==='function'?new ResizeObserver(entries=>{for(const entry of entries){const wrapper=entry.target.closest('.report-media');if(wrapper)layoutHandle(wrapper);}}):null;
export function ensureHandle(wrapper) {
  let handle=wrapper.querySelector(':scope>.'+HANDLE);
  if(!handle) {
    handle=document.createElement('button');handle.type='button';handle.className='report-controls '+HANDLE;
    handle.title='Drag to resize chart. Arrow keys adjust size; Shift makes larger steps.';handle.contentEditable='false';
    wrapper.append(handle);
    const picture=pictureIn(wrapper);if(observer&&picture){observer.observe(picture);observer.observe(wrapper);}
  }
  layoutHandle(wrapper);return handle;
}
export function layoutHandle(wrapper) {
  const handle=wrapper.querySelector(':scope>.'+HANDLE),picture=pictureIn(wrapper);
  if(!handle||!picture)return;
  const box=picture.getBoundingClientRect(),parent=wrapper.getBoundingClientRect();
  handle.style.left=`${Math.round(box.right-parent.left-10)}px`;handle.style.top=`${Math.round(box.bottom-parent.top-10)}px`;
  handle.setAttribute('aria-label',`Resize chart, ${Math.round(box.width)} pixels wide`);
}
export function installPictureSizing({isEditing,changed}) {
  let drag=null;
  const pictureOf=handle=>handle.parentElement?pictureIn(handle.parentElement):null;
  function finish(cancel=false) {
    if(!drag)return;
    const {handle,picture,before,pointer}=drag;drag=null;
    document.removeEventListener('pointermove',move);document.removeEventListener('pointerup',up);document.removeEventListener('pointercancel',cancelDrag);document.removeEventListener('keydown',escape,true);
    handle.parentElement?.classList.remove('report-resizing');
    if(cancel){if(before===null)picture.removeAttribute('style');else picture.setAttribute('style',before);}
    else if(before!==picture.getAttribute('style'))changed();
    try{if(handle.hasPointerCapture(pointer))handle.releasePointerCapture(pointer);}catch{}
    const wrapper=picture.closest('.report-media');if(wrapper)layoutHandle(wrapper);
  }
  const cancelDrag=()=>finish(true);
  const escape=event=>{if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();finish(true);}};
  const up=event=>{if(event.pointerId===drag?.pointer)finish();};
  function move(event) {
    if(event.pointerId!==drag?.pointer)return;
    event.preventDefault();
    // Pictures are centred: the right edge moves half as far as the width changes. A vertical drag works too, in proportion.
    const x=(event.clientX-drag.x)*2,y=(event.clientY-drag.y)*drag.ratio;
    applyPictureWidth(drag.picture,drag.width+(Math.abs(x)>Math.abs(y)?x:y));
  }
  document.addEventListener('pointerdown',event=>{
    const handle=event.target.closest?.('.'+HANDLE);if(!handle)return;
    const picture=pictureOf(handle);
    if(!picture||!isEditing()||event.button!==0||drag)return;
    event.preventDefault();event.stopPropagation();handle.focus();
    const box=picture.getBoundingClientRect();
    drag={handle,picture,pointer:event.pointerId,x:event.clientX,y:event.clientY,width:box.width,ratio:box.width/box.height||1,before:picture.getAttribute('style')};
    handle.parentElement.classList.add('report-resizing');
    document.addEventListener('pointermove',move,{passive:false});document.addEventListener('pointerup',up);document.addEventListener('pointercancel',cancelDrag);document.addEventListener('keydown',escape,true);
    try{handle.setPointerCapture(event.pointerId);}catch{} // Synthetic events in the native regression harness.
  },true);
  document.addEventListener('keydown',event=>{
    const handle=event.target.closest?.('.'+HANDLE);if(!handle)return;
    const picture=pictureOf(handle);
    if(!picture||!isEditing()||event.metaKey||event.ctrlKey||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;
    event.preventDefault();event.stopPropagation();
    if(applyPictureWidth(picture,picture.getBoundingClientRect().width+(['ArrowLeft','ArrowDown'].includes(event.key)?-1:1)*(event.shiftKey?25:5)))changed();
  },true);
}
export const pictureLimit=picture=>Math.max(80,Math.min(4096,Math.floor((picture.closest('.report-media')||picture.parentElement||document.body).clientWidth)));
export const pictureWidth=picture=>Math.round(picture.getBoundingClientRect().width);
// True when the picture's style changed.
export function applyPictureWidth(picture,value) {
  if(!Number.isFinite(value)||value<=0)return false;
  const limit=pictureLimit(picture),before=picture.getAttribute('style');
  picture.style.width=`${Math.round(Math.max(Math.min(80,limit),Math.min(limit,value)))}px`;
  picture.style.maxWidth='100%';picture.style.height='auto';
  const wrapper=picture.closest('.report-media');if(wrapper)layoutHandle(wrapper);
  return picture.getAttribute('style')!==before;
}
export function fitPicture(picture) {
  const before=picture.getAttribute('style');
  picture.style.width='100%';picture.style.maxWidth='100%';picture.style.height='auto';
  const wrapper=picture.closest('.report-media');if(wrapper)layoutHandle(wrapper);
  return picture.getAttribute('style')!==before;
}
