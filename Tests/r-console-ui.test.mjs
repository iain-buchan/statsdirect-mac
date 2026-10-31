import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
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
  assert.deepEqual(model.history, ['mean(before)']);
  assert.equal(model.navigateHistory(-1, 'draft <- 3'), 'mean(before)');
  assert.equal(model.navigateHistory(1, 'ignored'), 'draft <- 3');
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
