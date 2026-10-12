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
  // The R button's result, as the Windows toolbar's R button picks it (host.js 'currentTarget'): the result the selection or focus is
  // in now, whether or not it has a record of its run (one without disables the button rather than another result's script being
  // opened); else the latest result that has a record; none in a report with neither.
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
        // Disabled when the selection is a note without a record, or the report has no recorded result (Iain, 12 October 2026: a
        // toolbar button is scanned, so its state carries the information), with the reason in the tooltip; the latest result with a
        // record is still taken when the cursor is in no result.
        const {entry, how} = rTarget(); const usable = !!entry?.dataset.r;
        button.disabled = !usable; button.dataset.how = how; button.dataset.target = entry?.dataset.resultId ?? '';
        const label = entry?.dataset.r === 'data' ? 'Open Data and Settings in R' : 'Continue in R';
        const title = usable ? label + ': the result the cursor is in, or the latest result, as an R script'
          : how === 'selection' ? 'Continue in R: put the cursor in a result; this text has no record of a run'
          : 'Continue in R: run an analysis into this report first';
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
