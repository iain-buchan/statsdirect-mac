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
  return wrapper;
}
export const pictureLimit=picture=>Math.max(80,Math.min(4096,Math.floor((picture.closest('.report-media')||picture.parentElement||document.body).clientWidth)));
export const pictureWidth=picture=>Math.round(picture.getBoundingClientRect().width);
// True when the picture's style changed.
export function applyPictureWidth(picture,value) {
  if(!Number.isFinite(value)||value<=0)return false;
  const limit=pictureLimit(picture),before=picture.getAttribute('style');
  picture.style.width=`${Math.round(Math.max(Math.min(80,limit),Math.min(limit,value)))}px`;
  picture.style.maxWidth='100%';picture.style.height='auto';
  return picture.getAttribute('style')!==before;
}
export function fitPicture(picture) {
  const before=picture.getAttribute('style');
  picture.style.width='100%';picture.style.maxWidth='100%';picture.style.height='auto';
  return picture.getAttribute('style')!==before;
}
