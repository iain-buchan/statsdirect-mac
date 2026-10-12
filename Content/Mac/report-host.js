// Mac shell integration. Keep the shared Report sources identical to the
// released Windows editor pin (4e9f9d1); Windows does not load this file.
(() => {
  const root = document.getElementById('report-results');
  const row = document.querySelector('.report-format-row');
  let active = null;
  const buttons = new Map();
  const post = body => window.webkit.messageHandlers.statsDirectReport.postMessage(body);
  // Use the native clipboard bridge for Office formats, vector charts and the
  // editor's single undo history. The shared toolbar preserves the selection.
  const clipboard = document.createDocumentFragment();
  for (const [command, key, icon] of [
    ['cut','X','<circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="m8 8 12 12M8 16 20 4"/>'],
    ['copy','C','<rect x="8" y="8" width="12" height="13" rx="2"/><path d="M16 8V3H3v13h5"/>'],
    ['paste','V','<path d="M8 5H4v16h16V5h-4"/><rect x="8" y="2" width="8" height="6" rx="2"/><path d="M8 12h8M8 16h8"/>']
  ]) {
    const button = document.createElement('button'); button.type='button'; button.className='report-icon-button'; button.dataset.command=command;
    button.title=`${command[0].toUpperCase()+command.slice(1)} (⌘${key})`; button.setAttribute('aria-label',button.title);
    button.innerHTML=`<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icon}</svg>`;
    button.onclick=()=>post({action:'clipboard',command}); clipboard.append(button);
  }
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
  for (const [action, icon] of [['methodHelp','<circle cx="12" cy="12" r="9"/><path d="M9 8a3 3 0 1 1 4 3c-1 .6-1 1-1 3m0 3v.1"/>'],['continueInR','<path d="M6 20V4h6a5 5 0 0 1 0 10H6m6 0 6 6"/>']]) {
    const button = document.createElement('button'); button.type='button'; button.className='report-icon-button'; button.dataset.command=action;
    button.innerHTML=`<svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true">${icon}</svg>`;
    button.onclick=()=>invoke(action); buttons.set(action,button);row.append(button);
  }
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
