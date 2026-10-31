/* Shared console presentation only. R executes in the native host's separate process. */
(function (global) {
  'use strict';
  const VERSION = 1;
  const text = value => typeof value === 'string' ? value : '';
  const safePreview = value => typeof value === 'string' && value.length <= 12 * 1024 * 1024 && /^data:image\/(?:png|jpeg|gif|webp|svg\+xml);base64,[a-z0-9+/=\r\n]+$/i.test(value) ? value : null;
  class ConsoleModel {
    constructor(options = {}) {
      this.textBudget = options.textBudget || 200000;
      this.entryBudget = options.entryBudget || 500;
      this.mediaBudget = options.mediaBudget || 24 * 1024 * 1024;
      this.sessionId = null; this.generation = -1; this.seq = -1;
      this.state = 'starting'; this.prompt = '> '; this.requestId = null; this.requestKind = null;
      this.script = ''; this.mode = 'console'; this.entries = []; this.history = [];
      this.historyIndex = null; this.historyDraft = ''; this.trimmed = false;
      this.capabilities = {}; this.plotKeys = new Set(); this.restarting = false;
    }
    envelope(action, fields = {}) { return {protocolVersion: VERSION, action, sessionId: this.sessionId, generation: Math.max(0, this.generation), ...fields}; }
    acceptsInput() { return ['ready', 'continuation'].includes(this.state) || this.state === 'input' && !!this.requestId; }
    receive(event) {
      if (!event || event.protocolVersion !== VERSION || typeof event.sessionId !== 'string' || !event.sessionId || !Number.isInteger(event.generation) || !Number.isInteger(event.seq)) return false;
      if (event.type === 'session') {
        if (event.generation < 0 || event.seq < 0 || this.sessionId !== null && event.generation <= this.generation) return false;
        this.sessionId = event.sessionId; this.generation = event.generation; this.seq = event.seq;
        this.state = 'starting'; this.prompt = '> '; this.requestId = null; this.requestKind = null; this.entries = []; this.plotKeys.clear(); this.trimmed = false; this.restarting = false;
        this.historyIndex = null; this.historyDraft = ''; this.capabilities = event.capabilities && typeof event.capabilities === 'object' ? {...event.capabilities} : {};
        if (typeof event.script === 'string') this.script = event.script;
        if (Array.isArray(event.events)) for (const item of event.events) this.receive(item);
        return true;
      }
      if (this.restarting || event.sessionId !== this.sessionId || event.generation !== this.generation || event.seq <= this.seq) return false;
      if (event.type === 'inputRequested' && (typeof event.requestId !== 'string' || !event.requestId)) return false;
      if (event.type === 'state' && !['starting', 'ready', 'busy', 'continuation', 'input', 'stopped', 'interrupting'].includes(event.state)) return false;
      if (!['state', 'inputRequested', 'commandAccepted', 'commandFinished', 'output', 'inputEcho', 'plot', 'notice', 'exited', 'started', 'capabilities'].includes(event.type)) return false;
      this.seq = event.seq;
      switch (event.type) {
        case 'state':
          this.state = event.state;
          if (typeof event.prompt === 'string') this.prompt = event.prompt;
          if (event.state !== 'input' && !(event.state === 'continuation' && this.requestKind === 'continuation')) { this.requestId = null; this.requestKind = null; }
          break;
        case 'inputRequested': this.requestKind = event.kind === 'continuation' ? 'continuation' : 'input'; this.state = this.requestKind === 'continuation' ? 'continuation' : 'input'; this.requestId = event.requestId; this.prompt = text(event.prompt); break;
        case 'commandAccepted': this.state = 'busy'; this.requestId = null; this.requestKind = null; break;
        case 'commandFinished': this.requestId = null; this.requestKind = null; break; // Ready is authoritative only after R has unwound.
        case 'started': break;
        case 'capabilities': if (event.capabilities && typeof event.capabilities === 'object') this.capabilities = {...event.capabilities}; break;
        case 'inputEcho': {
          const source = text(event.text), origin = text(event.origin) || 'console';
          this.entries.push({kind: 'input', text: source, prompt: typeof event.prompt === 'string' ? event.prompt : '> ', origin, commandId: event.commandId || null});
          if (origin === 'console' && source.trim()) {
            this.remember(source);
            this.script += (this.script && !this.script.endsWith('\n') ? '\n' : '') + source + (source.endsWith('\n') ? '' : '\n');
          }
          this.trim(); break;
        }
        case 'output': {
          const value = text(event.text); if (!value) break;
          const stream = event.stream === 'stderr' ? 'stderr' : 'stdout', previous = this.entries[this.entries.length - 1];
          if (previous?.kind === 'output' && previous.stream === stream) previous.text += value;
          else this.entries.push({kind: 'output', stream, text: value});
          this.trim(); break;
        }
        case 'notice': this.notice(text(event.text)); break;
        case 'plot': {
          const id = text(event.plotId || event.id), revision = event.revision === undefined ? 1 : event.revision;
          if (!id || !Number.isInteger(revision) || revision < 0) break;
          const key = this.sessionId + ':' + id + ':' + revision;
          if (this.plotKeys.has(key)) break;
          this.plotKeys.add(key);
          this.entries.push({kind: 'plot', plotId: id, revision, mime: text(event.mime), preview: safePreview(event.preview), label: text(event.label) || 'R plot', pages: event.pages || null});
          this.trim(); break;
        }
        case 'exited': this.state = 'stopped'; this.requestId = null; this.requestKind = null; this.notice(text(event.message) || 'R session ended. Restart R to continue.'); break;
      }
      return true;
    }
    notice(value) { if (value) this.entries.push({kind: 'notice', text: value}); this.trim(); }
    trim() {
      let chars = this.entries.reduce((n, e) => n + (e.text?.length || 0), 0);
      let media = this.entries.reduce((n, e) => n + (e.preview?.length || 0), 0);
      while (this.entries.length > 1 && (this.entries.length > this.entryBudget || chars > this.textBudget || media > this.mediaBudget)) {
        const entry = this.entries.shift(); chars -= entry.text?.length || 0; media -= entry.preview?.length || 0; this.trimmed = true;
      }
      const first = this.entries[0];
      if (first?.text?.length > this.textBudget) { first.text = first.text.slice(-this.textBudget); this.trimmed = true; }
      // Large plot previews can be reopened from their original native assets.
      if (first?.preview?.length > this.mediaBudget) { first.preview = null; this.trimmed = true; }
    }
    remember(source) {
      if (this.history[this.history.length - 1] !== source) this.history.push(source);
      let size = this.history.reduce((n, value) => n + value.length, 0);
      while (this.history.length > 1 && (this.history.length > 100 || size > 500000)) size -= this.history.shift().length;
      this.historyIndex = null; this.historyDraft = '';
    }
    navigateHistory(direction, draft) {
      if (!this.history.length || this.state === 'input') return null;
      if (this.historyIndex === null) { this.historyIndex = this.history.length; this.historyDraft = draft; }
      this.historyIndex = Math.max(0, Math.min(this.history.length, this.historyIndex + direction));
      return this.historyIndex === this.history.length ? this.historyDraft : this.history[this.historyIndex];
    }
    submission(source, origin = 'console') {
      if (!this.sessionId || this.restarting || !this.acceptsInput()) return null;
      if (origin !== 'console' && this.state !== 'ready') return null;
      if (this.requestId) {
        if (origin !== 'console') return null;
        const reply = this.envelope('inputReply', {requestId: this.requestId, text: source});
        this.requestId = null; this.requestKind = null; this.state = 'submitting'; return reply;
      }
      if (!source.trim() && this.state !== 'continuation') return null;
      this.state = 'submitting'; return this.envelope('submit', {source, origin});
    }
    interrupt() {
      if (!this.sessionId || !['busy', 'input', 'continuation', 'submitting'].includes(this.state)) return null;
      this.requestId = null; this.requestKind = null; this.state = 'interrupting'; return this.envelope('interrupt');
    }
    restart() {
      if (!this.sessionId || this.restarting) return null;
      this.requestId = null; this.requestKind = null; this.state = 'restarting'; this.restarting = true; return this.envelope('restart');
    }
    plotAction(action, entry) {
      if (!this.sessionId || !['openPlot', 'copyPlot'].includes(action) || !this.entries.includes(entry) || entry.kind !== 'plot') return null;
      return this.envelope(action, {plotId: entry.plotId, revision: entry.revision});
    }
    snapshot() {
      return {protocolVersion: VERSION, sessionId: this.sessionId, generation: this.generation, seq: this.seq, state: this.state, prompt: this.prompt, requestId: this.requestId, requestKind: this.requestKind, mode: this.mode, script: this.script,
        outputText: this.entries.map(e => e.kind === 'plot' ? '[' + e.label + ']' : e.kind === 'input' ? e.prompt + e.text : e.text || '').join('\n'),
        transcript: this.entries.map(({preview, ...entry}) => ({...entry, hasPreview: !!preview})), history: this.history.slice(), trimmed: this.trimmed};
    }
  }
  if (typeof module !== 'undefined' && module.exports) module.exports = {ConsoleModel, safePreview};
  if (!global.document) return;

  const doc = global.document, model = new ConsoleModel();
  const byId = id => doc.getElementById(id), input = byId('console-input'), script = byId('script-source'), transcript = byId('transcript');
  let scheduled = false, renderingScript = false, focusAfterRender = false, transcriptDirty = true;
  const transcriptPointers = new Set();
  function post(message) {
    const handler = global.webkit?.messageHandlers?.statsDirectRConsole;
    if (handler) { handler.postMessage(message); return true; }
    if (global.chrome?.webview?.postMessage) { global.chrome.webview.postMessage({channel: 'statsdirect-r-console', ...message}); return true; }
    return false;
  }
  function send(action, fields) { return post(model.envelope(action, fields)); }
  function showBridgeFailure(previousState) {
    model.state = previousState; model.notice('Open this console inside StatsDirect to run R.'); transcriptDirty = true; render();
  }
  function schedule() { if (!scheduled) { scheduled = true; global.requestAnimationFrame(() => {scheduled = false; render();}); } }
  function element(tag, className, value) { const node = doc.createElement(tag); if (className) node.className = className; if (value !== undefined) node.textContent = value; return node; }
  function render() {
    const atEnd = transcript.scrollHeight - transcript.scrollTop - transcript.clientHeight < 45;
    const range = global.getSelection();
    const selecting = !!range?.rangeCount && !range.isCollapsed && transcript.contains(range.anchorNode);
    // Keep copied text selected and keep a pressed plot button alive until its click.
    // Control, focus and selection changes alone must not replace transcript nodes.
    if (transcriptDirty && !selecting && !transcriptPointers.size) {
      const fragment = doc.createDocumentFragment();
      if (model.trimmed) fragment.append(element('p', 'notice', 'Earlier output is omitted from this view. Your R script is retained.'));
      if (!model.entries.length) fragment.append(element('p', 'notice', model.sessionId ? 'Enter R commands below, or switch to Script.' : 'An interactive R session will start here.'));
      for (const entry of model.entries) {
        if (entry.kind === 'input') {
          const row = element('div', 'input-entry' + (entry.origin === 'input' ? ' reply' : ''));
          row.append(element('pre', 'echo-prompt', entry.prompt), element('pre', '', entry.text)); fragment.append(row);
        } else if (entry.kind === 'output') fragment.append(element('pre', 'output-entry ' + entry.stream, entry.text));
        else if (entry.kind === 'notice') fragment.append(element('p', 'notice', entry.text));
        else if (entry.kind === 'plot') {
          const figure = element('figure', 'plot');
          if (entry.preview) { const image = element('img'); image.src = entry.preview; image.alt = entry.label; figure.append(image); }
          figure.append(element('figcaption', '', entry.label));
          const actions = element('div', 'plot-actions');
          if (model.capabilities.openPlot) { const open = element('button', '', entry.mime === 'application/pdf' ? 'Open vector PDF' : 'Open chart'); open.type = 'button'; open.onclick = () => {const request = model.plotAction('openPlot', entry); if (request) post(request);}; actions.append(open); }
          if (model.capabilities.copyPlot) { const copy = element('button', '', 'Copy chart'); copy.type = 'button'; copy.onclick = () => {const request = model.plotAction('copyPlot', entry); if (request) post(request);}; actions.append(copy); }
          if (actions.childNodes.length) figure.append(actions); fragment.append(figure);
        }
      }
      transcript.replaceChildren(fragment);
      transcriptDirty = false;
      if (atEnd) transcript.scrollTop = transcript.scrollHeight;
    }
    if (script.value !== model.script && doc.activeElement !== script) { renderingScript = true; script.value = model.script; renderingScript = false; }
    input.disabled = !model.acceptsInput(); byId('prompt').textContent = model.prompt;
    input.placeholder = model.state === 'input' ? 'Type your answer · Enter to send' : 'Enter R code · Enter to run · Shift+Enter for a new line';
    const status = {starting: 'Starting R…', ready: 'Ready · R workspace retained', continuation: 'Continue the R expression', input: 'R is waiting for your answer', busy: 'R is running…', submitting: 'Sending to R…', interrupting: 'Interrupting R…', restarting: 'Restarting R · workspace will be cleared', stopped: 'R session ended'};
    byId('state').textContent = status[model.state] || 'R console';
    byId('run').disabled = model.mode === 'script' ? model.state !== 'ready' || !model.script.trim() : !model.acceptsInput();
    byId('run').querySelector('span').textContent = model.mode === 'script' ? script.selectionStart !== script.selectionEnd ? 'Run selection' : 'Run script' : model.state === 'input' ? 'Reply' : 'Run';
    byId('stop').disabled = !['busy', 'input', 'continuation', 'submitting'].includes(model.state);
    byId('restart').disabled = !model.sessionId || model.restarting;
    byId('save').disabled = !model.script;
    byId('ai').disabled = !model.capabilities.ai; byId('help').disabled = !model.capabilities.help;
    sizeInput();
    if (focusAfterRender) {
      focusAfterRender = false;
      const focused = doc.activeElement;
      if (model.mode === 'console' && !input.disabled && !selecting && doc.hasFocus() && [doc.body, input, byId('run'), byId('stop'), byId('restart')].includes(focused)) input.focus({preventScroll: true});
    }
  }
  function sizeInput() { input.style.height = 'auto'; input.style.height = Math.min(150, Math.max(26, input.scrollHeight)) + 'px'; }
  function mode(value) {
    model.mode = value;
    byId('console-panel').hidden = value !== 'console'; byId('script-panel').hidden = value !== 'script';
    for (const name of ['console', 'script']) { const tab = byId(name + '-tab'); tab.setAttribute('aria-selected', String(name === value)); tab.tabIndex = name === value ? 0 : -1; }
    send('modeChanged', {mode: value}); render(); (value === 'script' ? script : input).focus();
  }
  function run() {
    const previous = model.state, origin = model.mode === 'script' ? 'script' : 'console';
    const code = origin === 'script' ? script.selectionStart !== script.selectionEnd ? script.value.slice(script.selectionStart, script.selectionEnd) : script.value : input.value, request = model.submission(code, origin);
    if (!request) return;
    if (!post(request)) { showBridgeFailure(previous); return; }
    if (origin === 'console') input.value = '';
    else mode('console');
    render();
  }
  input.addEventListener('input', () => {model.historyIndex = null; sizeInput();});
  input.addEventListener('keydown', event => {
    if (event.isComposing) return;
    if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); run(); return; }
    const lineHeight = Number.parseFloat(global.getComputedStyle(input).lineHeight);
    const singleLine = !input.value.includes('\n') && input.scrollHeight <= lineHeight * 1.8 + 6;
    if ((singleLine || model.historyIndex !== null) && input.selectionStart === input.selectionEnd && !event.metaKey && !event.ctrlKey && !event.altKey && ['ArrowUp', 'ArrowDown'].includes(event.key)) {
      const value = model.navigateHistory(event.key === 'ArrowUp' ? -1 : 1, input.value);
      if (value !== null) { event.preventDefault(); input.value = value; input.setSelectionRange(value.length, value.length); sizeInput(); }
    }
  });
  script.addEventListener('input', () => {if (renderingScript) return; model.script = script.value; send('scriptChanged', {source: model.script}); render();});
  script.addEventListener('keydown', event => {if (event.key === 'Enter' && (event.metaKey || event.ctrlKey) && !event.isComposing) {event.preventDefault(); run();}});
  byId('run').onclick = run;
  byId('stop').onclick = () => {const previous = model.state, request = model.interrupt(); if (request && !post(request)) showBridgeFailure(previous); render();};
  byId('restart').onclick = () => {const previous = model.state, request = model.restart(); if (request && !post(request)) {model.restarting = false; showBridgeFailure(previous);} render();};
  byId('save').onclick = () => send('saveScript', {source: model.script});
  byId('ai').onclick = () => send('ai'); byId('help').onclick = () => send('help');
  for (const name of ['console', 'script']) {
    const tab = byId(name + '-tab'); tab.onclick = () => mode(name);
    tab.onkeydown = event => {if (['ArrowLeft', 'ArrowRight'].includes(event.key)) {event.preventDefault(); mode(name === 'console' ? 'script' : 'console');}};
  }
  doc.addEventListener('keydown', event => {
    const field = doc.activeElement, fieldSelection = field?.tagName === 'TEXTAREA' && field.selectionStart !== field.selectionEnd;
    const pageSelection = global.getSelection() && !global.getSelection().isCollapsed;
    const cancel = event.key === 'Escape' || event.key.toLowerCase() === 'c' && event.ctrlKey && !event.metaKey && model.mode === 'console' && !fieldSelection && !pageSelection;
    if (cancel && !event.isComposing && ['busy', 'input', 'continuation', 'submitting'].includes(model.state)) {
      event.preventDefault(); byId('stop').click();
    }
  });
  transcript.addEventListener('pointerdown', event => {transcriptPointers.add(event.pointerId);});
  function releaseTranscriptPointer(event) {
    if (transcriptPointers.delete(event.pointerId) && !transcriptPointers.size && transcriptDirty) schedule();
  }
  // The RAF runs after pointerup's click, so output arriving during a press cannot
  // detach the clicked button between its physical pointerdown and click events.
  doc.addEventListener('pointerup', releaseTranscriptPointer);
  doc.addEventListener('pointercancel', releaseTranscriptPointer);
  doc.addEventListener('selectionchange', () => {if (transcriptDirty && global.getSelection()?.isCollapsed) schedule();});
  global.StatsDirectRConsole = {
    receive(event) {
      const previousSource = model.script;
      if (!model.receive(event)) return false;
      if (['session', 'inputEcho', 'output', 'plot', 'notice', 'exited', 'capabilities'].includes(event.type)) transcriptDirty = true;
      if (previousSource !== model.script && event.type === 'inputEcho') send('scriptChanged', {source: model.script});
      if (event.type === 'inputRequested' || event.type === 'state' && ['ready', 'continuation', 'input'].includes(event.state)) focusAfterRender = true;
      schedule(); return true;
    },
    snapshot: () => model.snapshot(),
    focusInput() { if (model.mode !== 'console') mode('console'); if (!input.disabled) input.focus(); },
    setMode: mode,
    paste(value) {
      const target = doc.activeElement === script ? script : input;
      if (target.disabled || typeof value !== 'string') return false;
      target.setRangeText(value, target.selectionStart, target.selectionEnd, 'end'); target.dispatchEvent(new Event('input', {bubbles: true})); return true;
    },
  };
  render(); post(model.envelope('ready'));
})(typeof window !== 'undefined' ? window : globalThis);
