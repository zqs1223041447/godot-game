import assert from 'node:assert/strict';
import test from 'node:test';
import gateModule from '../web/single_instance_gate.js';
const { createSingleInstanceGate, SAVE_LOCK } = gateModule;

// Deterministic specification-shaped scheduler. This is not a real browser.
class LockManagerFake {
  held = new Map();
  calls = [];
  request(name, options, callback) {
    this.calls.push({ name, options });
    assert.deepEqual(options, { mode: 'exclusive', ifAvailable: true });
    if (this.held.has(name)) return Promise.resolve().then(() => callback(null));
    const token = {};
    this.held.set(name, token);
    return Promise.resolve().then(() => callback({ name, mode: 'exclusive' }))
      .finally(() => { if (this.held.get(name) === token) this.held.delete(name); });
  }
  // Simulates document teardown per the Web Locks specification, not app code.
  terminateDocument() { this.held.clear(); }
}
const settle = () => new Promise(resolve => setImmediate(resolve));
function fixture(manager = new LockManagerFake(), overrides = {}) {
  const fake = { starts: 0, exit: null, states: [] };
  fake.gate = createSingleInstanceGate({
    locks: manager, secure: true,
    start({ onExit }) { fake.starts++; fake.exit = onExit; return Promise.resolve(); },
    onState(state) { fake.states.push(state); }, ...overrides,
  });
  return fake;
}

test('missing Locks API fails closed before start', async () => {
  const f = fixture(null);
  assert.equal((await f.gate.requestStart()).code, 'unsupported');
  assert.equal(f.starts, 0);
});
test('insecure origin fails closed before requesting a lock', async () => {
  const locks = new LockManagerFake();
  const f = fixture(locks, { secure: false });
  assert.equal((await f.gate.requestStart()).code, 'unsupported');
  assert.equal(locks.calls.length, 0);
  assert.equal(f.starts, 0);
});
test('SecurityError rejection never falls back to unlocked startup', async () => {
  const f = fixture({ request: () => Promise.reject(new DOMException('denied', 'SecurityError')) });
  assert.equal((await f.gate.requestStart()).code, 'unavailable');
  assert.equal(f.starts, 0);
});
test('synchronous lock API failure also blocks startup', async () => {
  const f = fixture({ request() { throw Error('broken'); } });
  assert.equal((await f.gate.requestStart()).code, 'unavailable');
  assert.equal(f.starts, 0);
});
test('startup completion does not release the instance lease', async () => {
  const locks = new LockManagerFake();
  const first = fixture(locks), second = fixture(locks);
  assert.equal((await first.gate.requestStart()).code, 'started');
  await settle();
  assert.equal((await second.gate.requestStart()).code, 'blocked');
  assert.equal(first.starts, 1);
  assert.equal(second.starts, 0);
  assert.equal(locks.held.size, 1);
});
test('double clicks in one document create only one runtime', async () => {
  const locks = new LockManagerFake(), f = fixture(locks);
  const [a, b] = await Promise.all([f.gate.requestStart(), f.gate.requestStart()]);
  assert.equal(a.code, 'started');
  assert.equal(b.code, 'started');
  assert.equal(f.starts, 1);
  assert.equal(locks.calls.length, 1);
});
test('blocked manual retries never take over a live owner', async () => {
  const locks = new LockManagerFake(), a = fixture(locks), b = fixture(locks);
  await a.gate.requestStart();
  for (let i = 0; i < 5; i++) assert.equal((await b.gate.requestStart()).code, 'blocked');
  assert.equal(a.starts, 1);
  assert.equal(b.starts, 0);
});
test('trusted final engine exit allows a new document to start', async () => {
  const locks = new LockManagerFake(), a = fixture(locks), b = fixture(locks);
  await a.gate.requestStart();
  await b.gate.requestStart();
  a.exit(0);
  await settle();
  assert.equal((await b.gate.requestStart()).code, 'started');
  assert.equal(b.starts, 1);
});
test('simultaneous contenders start exactly one runtime', async () => {
  const locks = new LockManagerFake();
  const instances = Array.from({ length: 12 }, () => fixture(locks));
  const results = await Promise.all(instances.map(f => f.gate.requestStart()));
  assert.equal(results.filter(r => r.code === 'started').length, 1);
  assert.equal(results.filter(r => r.code === 'blocked').length, 11);
  assert.equal(instances.reduce((sum, f) => sum + f.starts, 0), 1);
});
test('rejected engine startup conservatively retains the lease', async () => {
  const locks = new LockManagerFake();
  const a = fixture(locks, { start: () => Promise.reject(Error('partial runtime')) });
  assert.equal((await a.gate.requestStart()).code, 'failed-held');
  const b = fixture(locks);
  assert.equal((await b.gate.requestStart()).code, 'blocked');
  assert.equal(b.starts, 0);
});
test('synchronous engine exception retains lease until document cleanup', async () => {
  const locks = new LockManagerFake();
  const a = fixture(locks, { start() { throw Error('constructor'); } });
  assert.equal((await a.gate.requestStart()).code, 'failed-held');
  assert.equal(locks.held.size, 1);
});
test('status renderer exception cannot accidentally release the lease', async () => {
  const locks = new LockManagerFake();
  const a = fixture(locks, { onState() { throw Error('UI'); } });
  assert.equal((await a.gate.requestStart()).code, 'started');
  assert.equal((await fixture(locks).gate.requestStart()).code, 'blocked');
});
test('engine exit before start promise resolution cannot revive running state', async () => {
  const locks = new LockManagerFake();
  const a = fixture(locks, { start({ onExit }) { onExit(1); return Promise.resolve(); } });
  assert.equal((await a.gate.requestStart()).code, 'exited');
  await settle();
  assert.equal(a.gate.phase, 'exited');
  assert.equal(locks.held.size, 0);
});
test('duplicate onExit calls are idempotent', async () => {
  const locks = new LockManagerFake(), a = fixture(locks);
  await a.gate.requestStart();
  a.exit(0); a.exit(0);
  await settle();
  assert.equal(a.states.filter(x => x === 'exited').length, 1);
  assert.equal(locks.held.size, 0);
});
test('simulated document destruction does not leave a persistent deadlock', async () => {
  const locks = new LockManagerFake(), a = fixture(locks), b = fixture(locks);
  await a.gate.requestStart();
  locks.terminateDocument();
  assert.equal((await b.gate.requestStart()).code, 'started');
  // Actual browser close/crash teardown still needs cross-tab acceptance.
});
test('resource key is stable and no steal, TTL, signal, or storage token is used', async () => {
  const locks = new LockManagerFake(), a = fixture(locks);
  await a.gate.requestStart();
  assert.equal(locks.calls[0].name, SAVE_LOCK);
  assert.deepEqual(locks.calls[0].options, { mode: 'exclusive', ifAvailable: true });
});
