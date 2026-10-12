// Mac-only toolbar presentation. Native and web toolbars use the same geometry.
(() => {
  function icon(name) {
    const parts = window.StatsDirectToolbarIcons?.[name];
    if (!parts) return '';
    let path='', shapes='';
    for (const [op,...v] of parts) {
      if(op==='E') shapes+=`<ellipse cx="${v[0]+v[2]/2}" cy="${v[1]+v[3]/2}" rx="${v[2]/2}" ry="${v[3]/2}"/>`;
      else if(op==='R') shapes+=`<rect x="${v[0]}" y="${v[1]}" width="${v[2]}" height="${v[3]}"/>`;
      else path+=op+v.join(' ')+' ';
    }
    return `<svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${shapes}<path d="${path}"/></svg>`;
  }
  // Move the actual controls, retaining event handlers, formatting state and the
  // editor's saved selection. Priority 0 stays longest; ties overflow from right.
  function overflow(row, toggle, popup, host=row.parentElement) {
    host.classList.add('sd-toolbar'); row.classList.add('sd-toolbar-row');
    popup.classList.add('sd-toolbar-popup');
    const extra=document.createElement('div');extra.className='sd-toolbar-overflow';popup.prepend(extra);
    const items=[...row.children].filter(x=>x!==toggle);
    let updating=false, widths=new Map();
    const close=()=>{popup.hidden=true;toggle.setAttribute('aria-expanded','false');};
    toggle.onclick=()=>{popup.hidden=!popup.hidden;toggle.setAttribute('aria-expanded',String(!popup.hidden));};
    toggle.title='More commands';toggle.setAttribute('aria-label','More commands');toggle.setAttribute('aria-controls',popup.id);toggle.setAttribute('aria-expanded','false');
    toggle.innerHTML=icon('more');toggle.classList.add('sd-icon');
    function layout() {
      if(updating || !row.isConnected || !row.clientWidth)return;
      updating=true;
      // Do not detach a focused input: resizing must not discard a pending edit.
      const focus=document.activeElement;
      if((popup.contains(focus)||host.contains(focus)&&focus.matches('input,select,textarea'))&&focus!==document.body){updating=false;return;}
      for(const item of items) row.insertBefore(item,toggle);
      const candidates=items.filter(x=>!x.hidden&&getComputedStyle(x).display!=='none');
      const gap=4, available=row.clientWidth;
      for(const item of candidates){const style=getComputedStyle(item);widths.set(item,item.getBoundingClientRect().width+(parseFloat(style.marginLeft)||0)+(parseFloat(style.marginRight)||0));}
      let used=candidates.reduce((n,x)=>n+widths.get(x)+gap,0)+30;
      const ranked=candidates.slice().sort((a,b)=>Number(b.dataset.priority??50)-Number(a.dataset.priority??50)||items.indexOf(b)-items.indexOf(a));
      const hidden=new Set();
      for(const item of ranked){if(used<=available)break;if(item.contains(focus))continue;hidden.add(item);used-=widths.get(item)+gap;}
      for(const item of items)if(hidden.has(item))extra.append(item);
      extra.hidden=!hidden.size;
      toggle.hidden=popup.children.length===1&&!hidden.size;
      if(toggle.hidden)close();
      updating=false;
    }
    const onPointer=e=>{if(!host.contains(e.target))close();};
    const onKey=e=>{if(e.key==='Escape'&&!popup.hidden){e.preventDefault();close();toggle.focus();}};
    document.addEventListener('pointerdown',onPointer);
    host.addEventListener('keydown',onKey);
    const onBlur=()=>requestAnimationFrame(layout);host.addEventListener('focusout',onBlur);
    const resize=new ResizeObserver(layout);resize.observe(row);
    // Chart controls and native enabled states can appear without a resize.
    const mutation=new MutationObserver(()=>requestAnimationFrame(layout));
    for(const item of items)mutation.observe(item,{attributes:true,attributeFilter:['hidden']});
    layout();
    return ()=>{resize.disconnect();mutation.disconnect();document.removeEventListener('pointerdown',onPointer);host.removeEventListener('keydown',onKey);host.removeEventListener('focusout',onBlur);};
  }
  window.StatsDirectToolbar={icon,overflow};
})();
