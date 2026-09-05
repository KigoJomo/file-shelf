import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import assert from 'node:assert/strict';

// Execute the actual QML JavaScript callback, with process/timer boundaries
// controlled by the test. Runtime loading is checked separately in Omarchy.
const source = readFileSync(new URL('../Service.qml', import.meta.url), 'utf8');
const controller = source.slice(source.indexOf('id: controllerProc'), source.indexOf('id: focusProc'));
const callback = controller.match(/onExited: function\(exitCode\) \{([\s\S]*)\n    \}\n  \}/)[1];
function complete({ operation = 'status', result = 'open', exitCode = 0, queued = '', opened = false } = {}) {
  const calls = [];
  const root = { opened, queuedOperation: queued, statusText: '', focusMisses: 2,
    focusCheckReady: true, invoke: operation => calls.push(operation) };
  const context = { root, controllerProc: { operation, result, errorText: 'mock failure' },
    focusWarmupTimer: { restart: () => calls.push('warmup') }, console: { warn() {} }, exitCode };
  vm.runInNewContext(`(function(exitCode) {${callback}})(exitCode)`, context);
  return { root, calls };
}

test('startup reconciles an already open shelf and resumes focus checks', () => {
  const { root, calls } = complete();
  assert.equal(root.opened, true);
  assert.equal(root.statusText, 'open');
  assert.equal(root.focusMisses, 0);
  assert.deepEqual(calls, ['warmup']);
});
test('hidden and closed status reset bar state', () => {
  for (const result of ['hidden', 'closed']) {
    const { root, calls } = complete({ result, opened: true });
    assert.equal(root.opened, false);
    assert.deepEqual(calls, []);
  }
});
test('failed hide queries actual state and preserves an actionable error', () => {
  const { root, calls } = complete({ operation: 'hide', exitCode: 1 });
  assert.deepEqual(calls, ['status']);
  assert.match(root.statusText, /mock failure/);
});
test('failed status does not loop forever', () => {
  assert.deepEqual(complete({ exitCode: 1 }).calls, []);
});
test('newer user intent wins over completed or failed operation', () => {
  for (const exitCode of [0, 1]) {
    const { root, calls } = complete({ operation: 'show', queued: 'hide', exitCode });
    assert.deepEqual(calls, ['hide']);
    assert.equal(root.queuedOperation, '');
    assert.equal(root.opened, false);
  }
});

test('a click before screens/preferences load remains queued', () => {
  const invoke = source.slice(source.indexOf('  function invoke('), source.indexOf('  function open('));
  const root = { stateLoaded: false, queuedOperation: '' };
  vm.runInNewContext(`${invoke}; invoke('show')`, { root });
  assert.equal(root.queuedOperation, 'show');
  root.stateLoaded = true;
  root.targetScreen = null;
  vm.runInNewContext(`${invoke}; invoke('show')`, { root });
  assert.equal(root.queuedOperation, 'show');
});

test('an old focus result cannot hide a newly reopened shelf', () => {
  const focus = source.slice(source.indexOf('id: focusProc'), source.indexOf('id: revealTimer'));
  const callback = focus.match(/onStreamFinished: \{([\s\S]*?)\n      \}/)[1];
  const calls = [];
  const root = { focusGeneration: 3, handleFocusStatus: result => calls.push(result) };
  const focusProc = { generation: 2 };
  vm.runInNewContext(callback, { root, focusProc, text: 'closed' });
  assert.deepEqual(calls, []);
  focusProc.generation = 3;
  vm.runInNewContext(callback, { root, focusProc, text: 'focused' });
  assert.deepEqual(calls, ['focused']);
});
