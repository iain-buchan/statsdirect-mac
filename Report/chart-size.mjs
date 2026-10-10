// Store the chosen width on the picture, not the disposable editor controls.
// Its intrinsic dimensions/viewBox remain intact, so the picture stays vector
// based and height:auto preserves its proportions in every report format.
export function explicitPictureWidth(picture, fallback) {
  // HTML/R charts can specify a display width in the attribute while their
  // bitmap is twice that size. CSS (including Fit's percentage) takes priority.
  const value=picture.style.width||picture.getAttribute('width')||'';
  const size=value.trim().match(/^(\d+(?:\.\d+)?|\.\d+)(px|pt|in|cm|mm|pc|q)?$/i);
  const units={px:1,pt:4/3,in:96,cm:96/2.54,mm:96/25.4,pc:16,q:96/101.6};
  return size&&Number(size[1])>0?Number(size[1])*units[(size[2]||'px').toLowerCase()]:fallback;
}

const layouts=new WeakMap();
const observer=new ResizeObserver(entries=>{
  for(const {target} of entries) {
    if(!target.isConnected)observer.unobserve(target);
    else layouts.get(target)?.();
  }
});

export function detachPictureSizing(root) {
  root.querySelectorAll('.report-media,svg,img').forEach(el=>observer.unobserve(el));
}

export function attachPictureSizing(picture,wrapper,controls,changed,isEditing) {
  wrapper.classList.add('report-media');
  const tools=document.createElement('span');tools.className='report-chart-sizing';
  const label=document.createElement('label');label.append('Width ');
  const input=document.createElement('input');input.type='number';input.min='80';input.step='1';input.setAttribute('aria-label','Chart width in pixels');input.title='Chart width in pixels';
  label.append(input,' px');
  const fit=document.createElement('button');fit.type='button';fit.textContent='Fit';fit.title='Fit chart to report width';fit.setAttribute('aria-label',fit.title);
  tools.append(label,fit);controls.append(tools);
  const handle=document.createElement('button');handle.type='button';handle.className='report-controls report-chart-resize';
  handle.title='Drag to resize chart. Arrow keys adjust size; Shift makes larger steps.';
  handle.setAttribute('aria-label','Resize chart');wrapper.append(handle);
  let drag=null;
  const limit=()=>Math.max(80,Math.min(4096,Math.floor(wrapper.clientWidth)));
  function layout() {
    const box=picture.getBoundingClientRect(),parent=wrapper.getBoundingClientRect();
    handle.style.left=`${box.right-parent.left-8}px`;handle.style.top=`${box.bottom-parent.top-8}px`;
    if(document.activeElement!==input)input.value=String(Math.round(box.width));
    input.max=String(limit());
    handle.setAttribute('aria-label',`Resize chart, ${Math.round(box.width)} pixels wide`);
  }
  function width(value) {
    picture.style.width=`${Math.round(Math.max(Math.min(80,limit()),Math.min(limit(),value)))}px`;
    picture.style.maxWidth='100%';picture.style.height='auto';layout();
  }
  function apply(value) {
    if(!isEditing()||!Number.isFinite(value)||value<=0){input.value=String(Math.round(picture.getBoundingClientRect().width));layout();return;}
    const before=picture.getAttribute('style');width(value);
    if(picture.getAttribute('style')!==before)changed();
    input.value=String(Math.round(picture.getBoundingClientRect().width));
  }
  input.onchange=()=>apply(input.valueAsNumber);
  input.onkeydown=event=>{if(event.key==='Enter'){event.preventDefault();apply(input.valueAsNumber);}};
  fit.onclick=()=>{
    if(!isEditing())return;
    const before=picture.getAttribute('style');
    picture.style.width='100%';picture.style.maxWidth='100%';picture.style.height='auto';layout();
    if(picture.getAttribute('style')!==before)changed();
  };
  function finish(cancel=false) {
    if(!drag)return;
    const {before,pointer}=drag;drag=null;
    document.removeEventListener('pointermove',move);document.removeEventListener('pointerup',up);document.removeEventListener('pointercancel',cancelDrag);document.removeEventListener('keydown',escape,true);
    wrapper.classList.remove('report-resizing');
    if(cancel){if(before===null)picture.removeAttribute('style');else picture.setAttribute('style',before);}
    else if(before!==picture.getAttribute('style'))changed();
    if(handle.hasPointerCapture(pointer))handle.releasePointerCapture(pointer);
    layout();
  }
  const cancelDrag=()=>finish(true);
  const escape=event=>{if(event.key==='Escape'){event.preventDefault();event.stopImmediatePropagation();finish(true);}};
  const up=event=>{if(event.pointerId===drag?.pointer)finish();};
  function move(event) {
    if(event.pointerId!==drag?.pointer)return;
    event.preventDefault();
    // Pictures are centred. The right edge therefore moves half as far as the
    // width changes; vertical dragging works too, with the same aspect ratio.
    const x=(event.clientX-drag.x)*2,y=(event.clientY-drag.y)*drag.ratio;
    width(drag.width+(Math.abs(x)>Math.abs(y)?x:y));
  }
  handle.onpointerdown=event=>{
    if(!isEditing()||event.button!==0||drag)return;
    event.preventDefault();handle.focus();
    const box=picture.getBoundingClientRect();
    drag={pointer:event.pointerId,x:event.clientX,y:event.clientY,width:box.width,ratio:box.width/box.height||1,before:picture.getAttribute('style')};
    wrapper.classList.add('report-resizing');
    document.addEventListener('pointermove',move,{passive:false});document.addEventListener('pointerup',up);document.addEventListener('pointercancel',cancelDrag);document.addEventListener('keydown',escape,true);
    try{handle.setPointerCapture(event.pointerId);}catch{} // Synthetic events in the native regression harness.
  };
  handle.onlostpointercapture=cancelDrag;
  handle.onkeydown=event=>{
    if(!isEditing()||event.metaKey||event.ctrlKey||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;
    event.preventDefault();apply(picture.getBoundingClientRect().width+(['ArrowLeft','ArrowDown'].includes(event.key)?-1:1)*(event.shiftKey?25:5));
  };
  layouts.set(picture,layout);layouts.set(wrapper,layout);observer.observe(picture);observer.observe(wrapper);layout();
}
