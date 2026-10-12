// Mac shell integration. Windows does not load this file. The Report sources
// are based on its released editor pin (4e9f9d1), with local chart-alignment
// changes documented in Docs/mac-unified-toolbars-2026-10-12.md.
(() => {
  const root = document.getElementById('report-results');
  const row = document.querySelector('.report-format-row');
  let active = null;
  const buttons = new Map();
  const post = body => window.webkit.messageHandlers.statsDirectReport.postMessage(body);
  const {icon, overflow} = window.StatsDirectToolbar;
  function control(command, title, glyph, action) {
    const b=document.createElement('button');b.type='button';b.className='report-icon-button sd-icon';b.dataset.command=command;
    b.title=title;b.setAttribute('aria-label',title);b.innerHTML=icon(glyph);b.onclick=action;return b;
  }
  // The native bridge preserves Office formats, charts and the single undo history.
  row.prepend(control('save','Save report (⌘S)','save',()=>post({action:'save'})));
  const clipboard=document.createDocumentFragment();
  for(const [command,key] of [['cut','X'],['copy','C'],['paste','V']])
    clipboard.append(control(command,`${command[0].toUpperCase()+command.slice(1)} (⌘${key})`,command,()=>post({action:'clipboard',command})));
  clipboard.append(control('find','Find (⌘F)','find',()=>post({action:'find'})));
  row.querySelector('[data-command=redo]').after(clipboard);
  function current() {
    return active?.isConnected ? active : root.querySelector('.report-entry:last-child');
  }
  function update() {
    const entry = current();
    for (const [action, button] of buttons) {
      button.disabled = !entry?.dataset[action === 'methodHelp' ? 'help' : 'r'];
      const label = action === 'methodHelp' ? 'Method Help' : entry?.dataset.r === 'data' ? 'Open Data and Settings in R' : 'Continue in R';
      button.title = label; button.setAttribute('aria-label', label);
    }
  }
  function invoke(action) {
    const entry = current();
    if (entry) post({action, resultID:entry.dataset.resultId});
  }
  for (const [action,glyph] of [['methodHelp','help'],['continueInR','r']]) {
    const b=control(action,'',glyph,()=>invoke(action));buttons.set(action,b);row.append(b);
  }
  for(const b of row.querySelectorAll('button[data-command]')) {
    const glyph=icon(b.dataset.command);
    if(glyph){b.innerHTML=glyph;b.classList.add('sd-icon');}
    b.dataset.priority=({save:0,undo:10,redo:10,cut:10,copy:10,paste:10,find:20,bold:30,italic:35,underline:40,methodHelp:25,continueInR:25})[b.dataset.command]??70;
  }
  for(const name of ['undo','cut','find','bold','methodHelp'])row.querySelector(`[data-command=${name}]`).dataset.groupStart='';
  for(const label of row.querySelectorAll(':scope > label')) {
    const format=label.querySelector('[data-format]')?.dataset.format;
    label.dataset.priority=({fontName:45,fontSize:30,formatBlock:65})[format]??60;
  }
  const picture=row.querySelector('.report-picture-tools');picture.dataset.priority='35';
  const toggle=document.getElementById('report-more-toggle');row.append(toggle);
  overflow(row,toggle,document.getElementById('report-more-tools'),document.getElementById('report-toolbar'));
  function remember(node) {
    const element = node?.nodeType === 1 ? node : node?.parentElement;
    const entry = element?.closest('.report-entry');
    if (entry && root.contains(entry)) active=entry;
    update();
  }
  document.addEventListener('selectionchange',()=>remember(window.getSelection()?.anchorNode));
  root.addEventListener('pointerdown',event=>remember(event.target));
  root.addEventListener('keydown',event=>{if(event.key==='F1'){event.preventDefault();invoke('methodHelp');}});
  // An empty report still accepts typing and paste. The native model records
  // this draft only upon an actual edit, preserving clean state and undo.
  function ensureDraft() {
    if(!root.querySelector('.report-entry')) {
      const id=root.dataset.draftId;
      StatsDirectReportEditor.replaceEntries([{id,html:`<article class="report-entry" id="result-${id}" data-result-id="${id}" aria-label="Text"><p><br></p></article>`}],[id]);
    }
    if (!root.textContent.trim() && !root.querySelector('table,svg,img,hr')) document.getElementById('report-empty').hidden=false;
    update();
  }
  new MutationObserver(ensureDraft).observe(root,{childList:true});
  ensureDraft();
})();
