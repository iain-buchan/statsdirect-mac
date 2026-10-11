// Mac shell integration. Keep the shared Report sources identical to the
// released Windows editor pin (4e9f9d1); Windows does not load this file.
(() => {
  const root = document.getElementById('report-results');
  const row = document.querySelector('.report-format-row');
  let active = null;
  const buttons = new Map();
  const post = body => window.webkit.messageHandlers.statsDirectReport.postMessage(body);
  function current() {
    return active?.isConnected ? active : root.querySelector('.report-entry:last-child');
  }
  // The R button's result, as the Windows toolbar's R button picks it (host.js 'currentTarget'): the result the selection or focus is
  // in now, whether or not it has a record of its run (one without is reported as such rather than another result's script opened);
  // else the latest result that has a record; none in a report with neither.
  function entryAt(node) {
    const element = node?.nodeType === 1 ? node : node?.parentElement;
    const entry = element?.closest('.report-entry');
    return entry && root.contains(entry) ? entry : null;
  }
  function rTarget() {
    const selection = window.getSelection();
    const at = entryAt(selection?.rangeCount ? selection.anchorNode : null) ?? entryAt(document.activeElement);
    if (at) return {entry: at, how: 'selection'};
    const latest = [...root.querySelectorAll('.report-entry[data-r]')].pop();
    return latest ? {entry: latest, how: 'latest'} : {entry: null, how: 'none'};
  }
  function update() {
    for (const [action, button] of buttons) {
      if (action === 'continueInR') {
        const {entry, how} = rTarget();
        button.disabled = false; button.dataset.how = how; button.dataset.target = entry?.dataset.resultId ?? '';
        const label = entry?.dataset.r === 'data' ? 'Open Data and Settings in R' : 'Continue in R';
        const title = label + ': the result the cursor is in, or the latest result, as an R script';
        button.title = title; button.setAttribute('aria-label', title);
        continue;
      }
      const entry = current();
      button.disabled = !entry?.dataset.help;
      button.title = 'Method Help'; button.setAttribute('aria-label', 'Method Help');
    }
  }
  function invoke(action) {
    if (action === 'continueInR') { const {entry, how} = rTarget(); post({action, resultID: entry?.dataset.resultId ?? null, how}); return; }
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
