import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
const require = createRequire(import.meta.url);
const {ConsoleModel} = require('../Content/RConsole/console.js');

const event = (type, seq, fields = {}) => ({protocolVersion: 1, sessionId: 'retained-session', generation: 1, type, seq, ...fields});
const entered = 'x <- 42';
const script = '# authored introduction\nx <- 42\n# user-edited ending\n';
const replay = [
  event('inputEcho', 1, {origin: 'console', text: entered, prompt: '> '}),
  event('output', 2, {text: '[1] 42\n', stream: 'stdout'}),
  event('state', 3, {state: 'ready', prompt: '> '})
];
function restore(model, source = script) {
  assert.equal(model.receive(event('session', 0, {script: source, events: replay, capabilities: {consoleInput: true}})), true);
  return model;
}

test('initial native replay restores the authoritative edited script once', () => {
  const model = restore(new ConsoleModel());
  assert.equal(model.script, script);
  assert.equal(model.entries.filter(entry => entry.kind === 'input').length, 1);
  assert.equal(model.entries.find(entry => entry.kind === 'output').text, '[1] 42\n');
  assert.equal(model.state, 'ready');
});

test('repeated renderer recovery never appends replayed console commands to Script', () => {
  let model = restore(new ConsoleModel());
  for (let reload = 0; reload < 3; reload++) {
    model = restore(new ConsoleModel(), model.script);
    assert.equal(model.script, script);
    assert.deepEqual(model.history, [entered]);
  }
});

test('restored console history recalls commands while new commands append exactly once', () => {
  const model = restore(new ConsoleModel());
  assert.equal(model.navigateHistory(-1, 'unfinished draft'), entered);
  assert.equal(model.navigateHistory(1, ''), 'unfinished draft');
  const next = 'x + 1';
  assert.equal(model.receive(event('inputEcho', 4, {origin: 'console', text: next, prompt: '> '})), true);
  assert.equal(model.script, script + next + '\n');
  assert.deepEqual(model.history, [entered, next]);
  assert.equal(model.receive(event('inputEcho', 4, {origin: 'console', text: next, prompt: '> '})), false);
  assert.equal(model.script, script + next + '\n');
});

test('optional file notice metadata survives live output and renderer recovery', () => {
  const model = restore(new ConsoleModel());
  const filePath = 'C:\\R output\\résumé #1.txt', label = 'résumé #1.txt';
  const file = event('notice', 4, {text: 'File written: ' + label, filePath, label});
  assert.equal(model.receive(file), true);
  const notice = model.entries.at(-1);
  assert.deepEqual(notice, {kind: 'notice', text: 'File written: ' + label, filePath, label});
  assert.equal(model.script, script);
  const recovered = new ConsoleModel();
  assert.equal(recovered.receive(event('session', 0, {script, events: [...replay, file]})), true);
  assert.deepEqual(recovered.entries.at(-1), notice);
  assert.equal(recovered.script, script);
  assert.equal(recovered.receive(event('notice', 5, {text: 'Plain notice remains supported'})), true);
  assert.equal(recovered.entries.at(-1).text, 'Plain notice remains supported');
  assert.equal(recovered.entries.at(-1).filePath, undefined);
});
