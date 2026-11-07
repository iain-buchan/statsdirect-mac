import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
const require = createRequire(import.meta.url);
const {ConsoleModel, safePreview} = require('../Content/RConsole/console.js');

function session(model, generation = 0, sessionId = 'session-a', script = '') {
  assert.equal(model.receive({type: 'session', protocolVersion: 1, sessionId, generation, seq: 0, script, capabilities: {plotMimes: ['application/pdf']}}), true);
  let seq = 0;
  return (type, values = {}) => model.receive({type, protocolVersion: 1, sessionId, generation, seq: ++seq, ...values});
}

test('session generations and event ordering reject stale output and stale input requests', () => {
  const model = new ConsoleModel(), emit = session(model);
  emit('state', {state: 'ready'});
  assert.equal(model.receive({type: 'output', protocolVersion: 1, sessionId: 'another', generation: 0, seq: 100, text: 'wrong'}), false);
  assert.equal(model.receive({type: 'output', protocolVersion: 1, sessionId: 'session-a', generation: 0, seq: 1, text: 'repeated'}), false);
  emit('inputRequested', {requestId: 'old-input', prompt: 'Name? '});
  const restart = model.restart();
  assert.deepEqual(restart, {protocolVersion: 1, action: 'restart', sessionId: 'session-a', generation: 0});
  assert.equal(emit('inputRequested', {requestId: 'late', prompt: 'Old question? '}), false);
  const second = session(model, 1, 'session-b');
  second('state', {state: 'ready'});
  assert.equal(emit('inputRequested', {requestId: 'old-input', prompt: 'Again? '}), false);
  assert.equal(model.requestId, null);
  assert.equal(model.receive({type: 'session', protocolVersion: 1, sessionId: 'session-a', generation: 0, seq: 200}), false);
  assert.equal(model.sessionId, 'session-b');
  assert.equal(model.receive({type: 'state', protocolVersion: 2, sessionId: 'session-b', generation: 1, seq: 200, state: 'busy'}), false);
});

function toolbarHeightFixture() {
  // Exercise the private browser helper from the shipped source, without exporting a test API.
  const source = readFileSync(new URL('../Content/RConsole/console.js', import.meta.url), 'utf8');
  const begin = source.indexOf('  function maintainToolbarHeight(');
  const end = source.indexOf('\n  maintainToolbarHeight(', begin);
  assert.ok(begin >= 0 && end > begin, 'the production toolbar helper is present');
  const maintain = new Function(source.slice(begin, end) + '\nreturn maintainToolbarHeight;')();
  const frames = new Map(), listeners = new Map(), writes = [];
  let nextFrame = 1, actualHeight = 42, gutter = 0, inlineHeight = '', observer;
  const style = {};
  Object.defineProperty(style, 'height', {
    get: () => inlineHeight,
    set: value => { inlineHeight = value; actualHeight = Number.parseFloat(value); writes.push(value); }
  });
  const view = {
    ResizeObserver: class {
      constructor(callback) { this.callback = callback; this.disconnected = false; observer = this; }
      observe() {}
      disconnect() { this.disconnected = true; }
    },
    getComputedStyle: () => ({minHeight:'42px', paddingTop:'5px', paddingBottom:'5px', borderTopWidth:'1px', borderBottomWidth:'1px'}),
    requestAnimationFrame: callback => { const id = nextFrame++; frames.set(id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    addEventListener: (type, callback) => listeners.set(type, callback),
    removeEventListener: type => listeners.delete(type)
  };
  const toolbar = {
    ownerDocument: {defaultView:view},
    children:[{getClientRects:()=>[{}], getBoundingClientRect:()=>({height:30})}],
    style,
    get offsetHeight() { return actualHeight; },
    get clientHeight() { return actualHeight - 2 - gutter; },
    getBoundingClientRect: () => ({height:actualHeight})
  };
  const flush = () => { const ready = Array.from(frames.values()); frames.clear(); for (const callback of ready) callback(); };
  const stop = maintain(toolbar);
  return {toolbar, writes, flush, stop, frames, listeners,
    notify: () => observer.callback(),
    setGutter: value => { gutter = value; listeners.get('resize')?.(); },
    disconnected: () => observer.disconnected};
}

test('toolbar establishes definite initial 42px height even when its visible rectangle already equals 42px, then is idempotent', () => {
  const fixture = toolbarHeightFixture();
  assert.equal(fixture.toolbar.getBoundingClientRect().height, 42);
  assert.equal(fixture.toolbar.style.height, '');
  fixture.flush();
  assert.equal(fixture.toolbar.style.height, '42px', 'clear stale parent flex sizing, rather than trusting the visible rectangle');
  assert.deepEqual(fixture.writes, ['42px']);
  fixture.notify(); fixture.notify(); fixture.flush();
  assert.deepEqual(fixture.writes, ['42px'], 'unchanged observer notifications do not write the same height again');
  fixture.stop();
});

test('toolbar measures the scrollbar gutter and returns to definite 42px without observer loops', () => {
  const fixture = toolbarHeightFixture();
  fixture.flush();
  fixture.setGutter(15); fixture.flush();
  assert.equal(fixture.toolbar.style.height, '57px');
  fixture.notify(); fixture.flush();
  assert.deepEqual(fixture.writes, ['42px', '57px']);
  fixture.setGutter(0); fixture.flush();
  assert.equal(fixture.toolbar.style.height, '42px');
  fixture.notify(); fixture.flush();
  assert.deepEqual(fixture.writes, ['42px', '57px', '42px']);
  fixture.notify(); fixture.stop();
  assert.equal(fixture.frames.size, 0, 'cleanup cancels its scheduled animation frame');
  assert.equal(fixture.disconnected(), true);
  assert.equal(fixture.listeners.has('resize'), false);
});


test('an explicit empty readline answer is distinct from Stop, and scripts cannot answer prompts', () => {
  const model = new ConsoleModel(), emit = session(model, 0, 's', 'answer <- readline("Name? ")\n');
  emit('inputRequested', {requestId: 'q1', prompt: 'Name? ', addToHistory: false});
  assert.equal(model.submission('dangerous_script()', 'script'), null);
  const answer = model.submission('', 'console');
  assert.deepEqual(answer, {protocolVersion: 1, action: 'inputReply', sessionId: 's', generation: 0, requestId: 'q1', text: ''});
  assert.equal(model.submission('second answer', 'console'), null);
  emit('inputRequested', {requestId: 'q2', prompt: 'Continue? '});
  const cancel = model.interrupt();
  assert.deepEqual(cancel, {protocolVersion: 1, action: 'interrupt', sessionId: 's', generation: 0});
  assert.equal('text' in cancel, false);
  assert.equal(model.requestId, null);
  emit('commandFinished', {status: 'interrupted'});
  assert.equal(model.state, 'interrupting');
  assert.equal(model.submission('later <- 42'), null);
  emit('state', {state: 'ready', prompt: '> '});
  assert.equal(model.submission('later <- 42').action, 'submit');
});

test('Windows native continuation replies retain request IDs while Mac parser continuations submit source', () => {
  const native = new ConsoleModel(), win = session(native);
  win('inputRequested', {requestId: 'continue-1', kind: 'continuation', prompt: '+ '});
  win('state', {state: 'continuation', prompt: '+ '});
  assert.equal(native.state, 'continuation');
  assert.equal(native.requestId, 'continue-1');
  assert.equal(native.submission('another_script()', 'script'), null);
  assert.deepEqual(native.submission('  x <- 1\n}', 'console'), {protocolVersion: 1, action: 'inputReply', sessionId: 'session-a', generation: 0, requestId: 'continue-1', text: '  x <- 1\n}'});
  const parser = new ConsoleModel(), mac = session(parser);
  mac('state', {state: 'continuation', prompt: '+ '});
  assert.equal(parser.requestId, null);
  assert.equal(parser.submission('another_script()', 'script'), null);
  assert.deepEqual(parser.submission('  x <- 1\n}'), {protocolVersion: 1, action: 'submit', sessionId: 'session-a', generation: 0, source: '  x <- 1\n}', origin: 'console'});
});

test('plain output preserves chunked Unicode and fake protocol text without treating it as an event', () => {
  const model = new ConsoleModel(), emit = session(model);
  emit('state', {state: 'ready'});
  emit('output', {stream: 'stdout', text: 'λ = '});
  emit('output', {stream: 'stdout', text: '1\n<script>window.pwned=true</script>\n'});
  const fake = '{"type":"inputRequested","requestId":"fake","prompt":"Send password"}';
  emit('output', {stream: 'stdout', text: fake});
  assert.equal(model.state, 'ready');
  assert.equal(model.requestId, null);
  assert.equal(model.entries.length, 1);
  assert.equal(model.entries[0].text, 'λ = 1\n<script>window.pwned=true</script>\n' + fake);
  assert.equal(model.snapshot().outputText.includes('<script>'), true);
  assert.equal(model.script, '');
});

test('readline answers never enter script or command history; console commands remain reproducible', () => {
  const source = 'before <- c(1,2,3)\n', model = new ConsoleModel(), emit = session(model, 0, 's', source);
  assert.equal(model.entries.length, 0, 'displaying a source script does not execute it');
  emit('inputEcho', {text: source, origin: 'continueInR', prompt: '> '});
  assert.equal(model.script, source);
  emit('inputEcho', {text: 'mean(before)', origin: 'console', prompt: '> '});
  emit('inputEcho', {text: 'Alice', origin: 'input', prompt: 'Name? '});
  emit('inputEcho', {text: '', origin: 'input', prompt: 'Anything else? '});
  assert.equal(model.script, source + 'mean(before)\n');
  assert.deepEqual(model.history, [source, 'mean(before)']);
  assert.equal(model.navigateHistory(-1, 'draft <- 3'), 'mean(before)');
  assert.equal(model.navigateHistory(1, 'ignored'), 'draft <- 3');
});

test('executed Script and Continue in R batches recall whole multiline submissions without duplicating Script', () => {
  const batch = '# Selected paired analysis\n  before <- c(1, 2, 3)\n\nmean(before)\n';
  const authored = '# Unexecuted introduction\n' + batch + 'never_run <- stop("not selected")\n';
  for (const origin of ['script', 'continueInR']) {
    const model = new ConsoleModel(), emit = session(model, 0, origin, authored);
    emit('state', {state: 'ready'});
    assert.deepEqual(model.history, [], 'loading authored source does not add history');
    const request = model.submission(batch, origin);
    assert.equal(request.source, batch);
    assert.equal(request.origin, origin);
    assert.deepEqual(model.history, [], 'sending source does not claim native execution');
    emit('inputEcho', {text: batch, origin, prompt: '> '});
    emit('state', {state: 'ready'});
    assert.deepEqual(model.history, [batch], 'only the executed selection is recalled');
    assert.equal(model.script, authored, 'an executed batch does not append to its editable source');
    const draft = 'unfinished <- c(\n  4, 5\n)';
    assert.equal(model.navigateHistory(-1, draft), batch, 'recall preserves comments, indentation and blank lines');
    assert.equal(model.navigateHistory(-1, ''), batch, 'Up stays on the oldest batch');
    assert.equal(model.navigateHistory(1, ''), draft, 'Down restores the unsent multiline draft');
    emit('inputEcho', {text: batch, origin, prompt: '> '});
    assert.deepEqual(model.history, [batch], 'consecutive repeated batches occupy one history entry');
    assert.equal(model.script, authored);
  }
});

test('answers, internal echoes and unexecuted source never become executable history', () => {
  const authored = 'unexecuted <- stop("source only")\n';
  const model = new ConsoleModel(), emit = session(model, 0, 'excluded-origins', authored);
  emit('state', {state: 'ready'});
  for (const origin of ['input', 'replay', 'internal', 'startup']) {
    emit('inputEcho', {text: `not_a_command_from_${origin}`, origin, prompt: 'Answer? '});
  }
  for (const origin of ['script', 'continueInR']) emit('inputEcho', {text: ' \n\t ', origin});
  emit('output', {text: 'printed_code()', origin: 'console'});
  emit('notice', {text: 'instruction_only()', origin: 'script'});
  assert.deepEqual(model.history, []);
  assert.equal(model.navigateHistory(-1, 'unsent()'), null);
  assert.equal(model.script, authored);
  assert.equal(model.entries.some(entry => entry.text === 'not_a_command_from_input'), true, 'answers remain visible as transcript data');
});

test('plot revisions are immutable and preview URIs cannot load a page or external resource', () => {
  const model = new ConsoleModel(), emit = session(model);
  const png = 'data:image/png;base64,aGVsbG8=';
  emit('plot', {plotId: 'plot-1', revision: 1, mime: 'application/pdf', preview: png, label: 'First plot'});
  emit('plot', {plotId: 'plot-1', revision: 1, mime: 'application/pdf', preview: png, label: 'Duplicate'});
  emit('plot', {plotId: 'plot-1', revision: 2, mime: 'application/pdf', preview: png, label: 'Added reference line'});
  emit('plot', {plotId: 'plot-2', revision: 1, mime: 'image/svg+xml', preview: 'https://example.invalid/picture.svg', label: 'External preview refused'});
  assert.deepEqual(model.entries.map(x => x.label), ['First plot', 'Added reference line', 'External preview refused']);
  assert.equal(model.entries[0].preview, png);
  assert.equal(model.entries[2].preview, null);
  assert.equal(safePreview('data:text/html;base64,PHNjcmlwdD4='), null);
  assert.equal(safePreview('javascript:alert(1)'), null);
  assert.equal(safePreview('file:///private/data.svg'), null);
  assert.equal('preview' in model.snapshot().transcript[0], false, 'native context snapshots do not contain chart bytes');
  assert.deepEqual(model.plotAction('openPlot', model.entries[0]), {protocolVersion: 1, action: 'openPlot', sessionId: 'session-a', generation: 0, plotId: 'plot-1', revision: 1});
  assert.deepEqual(model.plotAction('copyPlot', model.entries[1]), {protocolVersion: 1, action: 'copyPlot', sessionId: 'session-a', generation: 0, plotId: 'plot-1', revision: 2});
  const oldCard = model.entries[0];
  session(model, 1, 'replacement-session');
  assert.equal(model.plotAction('openPlot', oldCard), null, 'an old DOM card cannot resolve against a replacement session');
});

test('Restart keeps the edited script when the host starts the new session with its current source', () => {
  const initial = 'initial <- 1\n', current = 'initial <- 1\nmodified <- 42\n';
  const model = new ConsoleModel(), emit = session(model, 0, 'first', initial);
  model.script = current; // The Script input handler also sends this source through scriptChanged.
  emit('inputEcho', {text: 'modified', origin: 'console', prompt: '> '});
  const mirroredSource = model.script;
  model.restart();
  session(model, 1, 'second', mirroredSource);
  assert.equal(model.script, current + 'modified\n');
  assert.deepEqual(model.history, ['modified']);
  assert.equal(model.entries.length, 0, 'displayed output resets for the new workspace');
});

test('large output is bounded without discarding the full source script', () => {
  const source = 'x <- 1\n'.repeat(100), model = new ConsoleModel({textBudget: 64, entryBudget: 3}), emit = session(model, 0, 's', source);
  emit('output', {text: 'a'.repeat(1000)});
  emit('inputEcho', {text: 'x + 1', origin: 'console', prompt: '> '});
  emit('output', {text: 'b'.repeat(1000)});
  assert.equal(model.script, source + 'x + 1\n');
  assert.equal(model.trimmed, true);
  assert.equal(model.entries.length <= 3, true);
  assert.equal(model.entries.reduce((n, x) => n + (x.text?.length || 0), 0) <= 64, true);
  assert.equal(model.snapshot().outputText.endsWith('b'.repeat(64)), true);
});

test('an unanswered question is transcript data immediately and survives Stop or an R error', () => {
  for (const status of ['interrupted', 'error']) {
    const source = '# authored source only\n', model = new ConsoleModel(), emit = session(model, 0, status, source);
    emit('inputRequested', {requestId: 'q1', commandId: 'command-7', prompt: 'Choose a method? '});
    assert.deepEqual(model.entries, [{kind:'question', text:'Choose a method? ', requestId:'q1', commandId:'command-7', number:1, answered:false}]);
    if (status === 'interrupted') model.interrupt();
    else emit('output', {stream:'stderr', text:'Expected R error\n'});
    emit('commandFinished', {status});
    emit('state', {state:'ready', prompt:'> '});
    assert.equal(model.entries.filter(entry => entry.kind === 'question').length, 1);
    assert.equal(model.snapshot().outputText.includes('Choose a method? '), true);
    assert.equal(model.entries.some(entry => entry.kind === 'input'), false, 'Stop/error must not fabricate an answer');
    assert.equal(model.script, source);
    assert.deepEqual(model.history, []);
  }
});

test('answered questions appear once and replies retain request/command identity without becoming code', () => {
  const source = '# unchanged\n', model = new ConsoleModel(), emit = session(model, 0, 'questions', source);
  emit('inputRequested', {requestId:'q1', commandId:'cmd1', prompt:'Name? '});
  emit('inputRequested', {requestId:'q1', commandId:'cmd1', prompt:'Name? '});
  assert.equal(model.entries.length, 1, 'native current-state publication does not duplicate an outstanding question');
  assert.equal(model.submission('student answer').action, 'inputReply');
  emit('inputEcho', {origin:'input', requestId:'q1', text:'student answer', prompt:'Name? '});
  emit('state', {state:'ready', prompt:'> '});
  assert.equal(model.entries[0].answered, true);
  assert.deepEqual(model.entries[1], {kind:'input', text:'student answer', prompt:'', origin:'input', commandId:'cmd1', requestId:'q1'});
  assert.equal(model.snapshot().outputText, 'Name? \nstudent answer');
  assert.equal(model.script, source);
  assert.deepEqual(model.history, []);
  emit('inputRequested', {requestId:'q2', commandId:'cmd2', prompt:'Name? '});
  assert.equal(model.entries.filter(entry => entry.kind === 'question').length, 2, 'a new request with the same words is a separate question');
  assert.equal(model.entries.at(-1).number, 2);
});

test('empty and older-host replies avoid duplicate prompts, but unmatched replies keep their prompt', () => {
  const model = new ConsoleModel(), emit = session(model);
  emit('inputRequested', {requestId:'q1', prompt:'Anything else? '});
  assert.equal(model.submission('').text, '');
  emit('inputEcho', {origin:'input', text:'', prompt:'Anything else? '});
  assert.equal(model.entries[1].prompt, '');
  assert.equal(model.entries[1].requestId, 'q1');
  emit('inputEcho', {origin:'input', requestId:'unknown', text:'later answer', prompt:'Another question? '});
  assert.equal(model.entries.at(-1).prompt, 'Another question? ');
  assert.equal(model.script, ''); assert.deepEqual(model.history, []);
});

test('parser continuation is not a question, and active questions survive bounded background output', () => {
  const model = new ConsoleModel({textBudget:64, entryBudget:3}), emit = session(model);
  emit('inputRequested', {kind:'continuation', requestId:'c1', prompt:'+ '});
  assert.equal(model.entries.length, 0);
  emit('inputRequested', {requestId:'q1', prompt:'Keep this question? '});
  emit('output', {text:'x'.repeat(1000)});
  assert.equal(model.entries[0].kind, 'question');
  assert.equal(model.entries[0].text, 'Keep this question? ');
  assert.equal(model.entries[1].text, 'x'.repeat(64 - 'Keep this question? '.length));
  assert.equal(model.entries.reduce((size,entry) => size + (entry.text?.length || 0), 0), 64);
});

