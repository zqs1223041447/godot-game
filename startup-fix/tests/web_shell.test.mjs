import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../web/shell.html', import.meta.url), 'utf8');
const gateSource = readFileSync(new URL('../web/single_instance_gate.js', import.meta.url), 'utf8');
const inline = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(match => match[1]);
assert.equal(inline.length, 1, 'Execute the actual single startup script, not a copied model');
const script = inline[0].replace('$GODOT_CONFIG', JSON.stringify({ executable: 'index', fileSizes: { 'index.wasm': 12345 } })).replace('$GODOT_THREADS_ENABLED', 'false');
const settle = () => new Promise(resolve => setImmediate(resolve));

// Specification-shaped scheduler only. Actual browser lifecycle needs separate acceptance.
class LockManagerFake {
  held = new Map();
  calls = [];
  request(name, options, callback) {
    this.calls.push({ name, options: { ...options } });
    assert.deepEqual({ ...options }, { mode: 'exclusive', ifAvailable: true });
    if (this.held.has(name)) return Promise.resolve().then(() => callback(null));
    const token = {};
    this.held.set(name, token);
    return Promise.resolve().then(() => callback({ name, mode: 'exclusive' }))
      .finally(() => { if (this.held.get(name) === token) this.held.delete(name); });
  }
}

function loadShell(locks = new LockManagerFake(), options = {}) {
  const elements = new Map();
  for (const id of ['status', 'status-title', 'status-notice', 'status-progress', 'retry']) {
    elements.set(id, { dataset: {}, hidden: id === 'retry' || id === 'status-progress', disabled: false,
      textContent: '', handlers: {}, addEventListener(type, callback) { this.handlers[type] = callback; },
      removeAttribute(name) { delete this[name]; } });
  }
  const stats = { loaded: 0, loadCalls: [], loadedWhileLocked: [], featureChecks: 0, constructed: 0, started: 0, calls: [], errors: [], checkedWhileLocked: [] };
  class Engine {
    static load(path, size) {
      stats.loaded++;
      stats.loadCalls.push({ path, size });
      stats.loadedWhileLocked.push(locks?.held?.size);
      return options.load ? options.load(path, size) : Promise.resolve();
    }
    static getMissingFeatures() { stats.featureChecks++; return options.missing || []; }
    constructor() {
      stats.constructed++;
      stats.checkedWhileLocked.push(locks?.held?.size);
      if (options.constructorError) throw Error('constructor failed');
    }
    startGame(config) {
      stats.started++;
      stats.calls.push(config);
      return options.start ? options.start(config) : Promise.resolve();
    }
  }
  const navigator = options.navigator || { locks };
  const context = vm.createContext({
    document: { getElementById: id => elements.get(id) }, navigator,
    isSecureContext: options.secure !== false,
    console: { error: error => stats.errors.push(error) },
    ...(options.engineMissing ? {} : { Engine }),
    location: { protocol: options.protocol || 'https:', pathname: options.path || '/', search: options.search || '', hash: options.hash || '' },
  });
  if (!options.gateMissing) vm.runInContext(gateSource, context);
  vm.runInContext(script, context);
  return { stats, elements, state: () => elements.get('status').dataset.state,
    retry: () => elements.get('retry').handlers.click(),
    notice: () => elements.get('status-notice').textContent };
}

test('contending actual shell never constructs an Engine before the lock', async () => {
  const locks = new LockManagerFake();
  const a = loadShell(locks), b = loadShell(locks);
  await settle();
  assert.equal(a.stats.started, 1);
  assert.deepEqual(a.stats.checkedWhileLocked, [1]);
  assert.deepEqual(a.stats.loadedWhileLocked, [1]);
  assert.equal(b.stats.loaded, 0);
  assert.equal(b.stats.constructed, 0);
  assert.equal(b.stats.started, 0);
  assert.equal(b.state(), 'blocked');
  assert.equal(b.elements.get('retry').hidden, false);
  assert.match(b.notice(), /本页尚未启动游戏/);
});

test('startup completion hides overlay but holds the lock', async () => {
  const locks = new LockManagerFake(), a = loadShell(locks);
  await settle();
  assert.equal(a.state(), 'running');
  assert.equal(a.elements.get('status').hidden, true);
  assert.equal(locks.held.size, 1);
  const b = loadShell(locks);
  await settle();
  assert.equal(b.state(), 'blocked');
});

test('trusted onExit allows blocked tab to start only after manual retry', async () => {
  const locks = new LockManagerFake(), a = loadShell(locks), b = loadShell(locks);
  await settle();
  a.stats.calls[0].onExit(0);
  await settle();
  assert.equal(locks.held.size, 0);
  assert.equal(a.state(), 'exited');
  assert.equal(a.elements.get('status').hidden, false);
  assert.equal(b.stats.constructed, 0);
  b.retry();
  await settle();
  assert.equal(b.stats.started, 1);
  assert.equal(locks.held.size, 1);
});

test('same document repeated retry cannot construct another live Engine', async () => {
  const a = loadShell();
  await settle();
  a.retry();
  a.retry();
  await settle();
  assert.equal(a.stats.constructed, 1);
  assert.equal(a.stats.started, 1);
});

test('missing Web Locks API fails closed in the actual shell', async () => {
  const a = loadShell(null);
  await settle();
  assert.equal(a.state(), 'unsupported');
  assert.equal(a.stats.constructed, 0);
  assert.match(a.notice(), /Web Locks/);
});

test('insecure context fails closed without requesting a lock', async () => {
  const locks = new LockManagerFake(), a = loadShell(locks, { secure: false });
  await settle();
  assert.equal(a.state(), 'unsupported');
  assert.equal(a.stats.constructed, 0);
  assert.equal(locks.calls.length, 0);
});

test('Web Locks SecurityError fails closed with explicit notice', async () => {
  const a = loadShell({ request: () => Promise.reject(Error('SecurityError')) });
  await settle();
  assert.equal(a.state(), 'unavailable');
  assert.equal(a.stats.constructed, 0);
  assert.match(a.notice(), /游戏未启动/);
});

test('throwing navigator.locks getter does not initialize Engine', async () => {
  const a = loadShell(null, { navigator: { get locks() { throw Error('denied'); } } });
  await settle();
  assert.equal(a.state(), 'unavailable');
  assert.equal(a.stats.constructed, 0);
});

test('missing WebGL feature never initializes Engine', async () => {
  const locks = new LockManagerFake(), a = loadShell(locks, { missing: ['WebGL 2'] });
  await settle();
  assert.equal(a.state(), 'unsupported');
  assert.equal(a.stats.constructed, 0);
  assert.equal(locks.calls.length, 0);
  assert.match(a.notice(), /WebGL 2/);
});

test('missing gate script prevents unguarded fallback', async () => {
  const a = loadShell(undefined, { gateMissing: true });
  await settle();
  assert.equal(a.state(), 'unavailable');
  assert.equal(a.stats.constructed, 0);
});

test('missing Engine script presents failure without attempting startup', async () => {
  const a = loadShell(undefined, { engineMissing: true });
  await settle();
  assert.equal(a.state(), 'unavailable');
  assert.equal(a.stats.constructed, 0);
});

test('partial startup rejection retains ownership and states refresh risk', async () => {
  const locks = new LockManagerFake(), a = loadShell(locks, { start: () => Promise.reject(Error('wasm load')) });
  await settle();
  const b = loadShell(locks);
  await settle();
  assert.equal(a.state(), 'failed-held');
  assert.match(a.notice(), /刷新可能丢失/);
  assert.equal(b.stats.constructed, 0);
  assert.equal(b.state(), 'blocked');
  assert.equal(locks.held.size, 1);
});

test('constructor failure keeps ownership rather than guessing initialization state', async () => {
  const locks = new LockManagerFake(), a = loadShell(locks, { constructorError: true });
  await settle();
  assert.equal(a.state(), 'failed-held');
  assert.equal(a.stats.started, 0);
  assert.equal(locks.held.size, 1);
  const b = loadShell(locks);
  await settle();
  assert.equal(b.stats.constructed, 0);
});

test('download progress is rendered without suppressing later errors', async () => {
  let reject;
  const a = loadShell(undefined, { start: () => new Promise((_, no) => { reject = no; }) });
  await settle();
  const callback = a.stats.calls[0].onProgress;
  callback(5, 20);
  assert.equal(a.elements.get('status-progress').value, 5);
  assert.equal(a.elements.get('status-progress').max, 20);
  callback(0, 0);
  assert.equal(a.elements.get('status-progress').value, undefined);
  reject(Error('network'));
  await settle();
  callback(20, 20);
  assert.equal(a.state(), 'failed-held');
  assert.equal(a.elements.get('status-progress').hidden, true);
});

test('paths, query, fragments and simultaneous documents share a fixed key', async () => {
  const locks = new LockManagerFake();
  const pages = Array.from({ length: 8 }, (_, i) => loadShell(locks,
    { path: `/version-${i}/index.html`, search: `?build=${i}`, hash: `#${i}` }));
  await settle();
  assert.equal(pages.reduce((sum, page) => sum + page.stats.constructed, 0), 1);
  assert.equal(new Set(locks.calls.map(call => call.name)).size, 1);
  assert.equal(locks.calls[0].name, 'godot-game:exclusive-userfs:/userfs');
});

test('shell preserves export placeholders, local assets, Chinese warning and canvas', () => {
  for (const token of ['$GODOT_PROJECT_NAME', '$GODOT_HEAD_INCLUDE', '$GODOT_URL', '$GODOT_CONFIG', '$GODOT_THREADS_ENABLED'])
    assert.ok(html.includes(token));
  assert.match(html, /lang="zh-CN"/);
  assert.match(html, /<canvas id="canvas"/);
  assert.match(html, /保存后请勿立即刷新或关闭页面/);
  assert.doesNotMatch(html, /(?:src|href)="https?:\/\//);
  assert.doesNotMatch(html, /beforeunload|visibilitychange|\.requestQuit\(|\.installServiceWorker\(/);
});

test('file URLs explain correct hosting before features, Engine or save lock', async () => {
  for (const missingScripts of [{}, { engineMissing: true, gateMissing: true }]) {
    const locks = new LockManagerFake();
    const a = loadShell(locks, { protocol: 'file:', ...missingScripts,
      navigator: { get locks() { throw Error('must not inspect locks'); } } });
    await settle();
    assert.equal(a.state(), 'unsupported');
    assert.equal(a.stats.featureChecks, 0);
    assert.equal(a.stats.constructed, 0);
    assert.equal(locks.calls.length, 0);
    assert.match(a.notice(), /完整导出目录/);
    assert.match(a.notice(), /本版本请通过本地服务器或 HTTPS 运行/);
    assert.match(a.notice(), /部分浏览器会拦截/);
    assert.doesNotMatch(a.notice(), /网页游戏不能|所有浏览器/);
    assert.match(a.notice(), /http:\/\/localhost/);
    assert.match(a.notice(), /HTTPS/);
    assert.equal(a.elements.get('retry').hidden, true);
  }
});

test('HTTP localhost secure contexts still start normally', async () => {
  const a = loadShell(undefined, { protocol: 'http:', secure: true });
  await settle();
  assert.equal(a.state(), 'running');
  assert.equal(a.stats.constructed, 1);
});

test('startup error message crosses realms and is visible with lock retained', async () => {
  for (const error of [Error('WASM compilation failed'), 'WASM compilation failed']) {
    const locks = new LockManagerFake();
    const a = loadShell(locks, { start: () => Promise.reject(error) });
    await settle();
    assert.match(a.notice(), /启动错误：WASM compilation failed/);
    assert.match(a.notice(), /仍保留使用权限/);
    assert.match(a.notice(), /刷新可能丢失/);
    assert.equal(locks.held.size, 1);
    assert.equal(a.elements.get('retry').hidden, true);
    assert.equal(a.elements.get('retry').disabled, true);
    a.retry();
    await settle();
    assert.equal(a.stats.constructed, 1);
    assert.equal(locks.calls.length, 1);
  }
});

test('startup error display redacts URLs, relative query and fragments without rendering HTML', async () => {
  const error = Error('fetch https://user:private@host.test/index.wasm?token=secret#auth '
    + '//host.test/private-path index.pck?key=relativeSecret#frag '
    + 'file:///Users/private/index.pck blob:https://host.test/privateId '
    + 'data:text/plain,privateData #fragmentSecret <img src=x onerror=alert(1)>');
  const a = loadShell(undefined, { start: () => Promise.reject(error) });
  await settle();
  assert.match(a.notice(), /fetch/);
  assert.match(a.notice(), /资源地址已隐藏/);
  assert.match(a.notice(), /参数已隐藏/);
  assert.match(a.notice(), /<img src=x onerror=alert\(1\)>/);
  assert.equal(a.elements.get('status-notice').innerHTML, undefined);
  for (const text of [a.notice(), ...a.stats.errors]) {
    assert.doesNotMatch(text, /private|secret|relativeSecret|fragmentSecret|host\.test|Users/);
  }
});

test('startup diagnostics are bounded, strip control characters and omit stacks', async () => {
  const error = Error('network\u0000\n\u202e failure ' + 'x'.repeat(5000));
  error.stack = 'sensitive stack https://secret.test/';
  const a = loadShell(undefined, { start: () => Promise.reject(error) });
  await settle();
  const reason = a.notice().split('启动错误：')[1];
  assert.equal(reason.length, 400);
  assert.doesNotMatch(reason, /[\u0000-\u001f\u202e]|sensitive|secret/);
});

test('unusable error objects cannot disrupt failure notice or release save lock', async () => {
  for (const error of [null, 42, {}, { message: {} }, { get message() { throw Error('getter'); } }]) {
    const locks = new LockManagerFake();
    const a = loadShell(locks, { start: () => Promise.reject(error) });
    await settle();
    assert.equal(a.state(), 'failed-held');
    assert.match(a.notice(), /仍保留使用权限/);
    assert.doesNotMatch(a.notice(), /启动错误：|undefined|object Object/);
    assert.equal(locks.held.size, 1);
  }
});

test('WASM load rejection reaches failure UI and retains the lock without starting Engine', async () => {
  const locks = new LockManagerFake();
  const a = loadShell(locks, { load: () => Promise.reject(Error('WASM download failed: 404')) });
  await settle();
  assert.equal(a.state(), 'failed-held');
  assert.match(a.notice(), /WASM download failed: 404/);
  assert.deepEqual(a.stats.loadCalls, [{ path: 'index', size: 12345 }]);
  assert.deepEqual(a.stats.loadedWhileLocked, [1]);
  assert.equal(a.stats.constructed, 0);
  assert.equal(a.stats.started, 0);
  assert.equal(locks.held.size, 1);
  const b = loadShell(locks);
  await settle();
  assert.equal(b.state(), 'blocked');
  assert.equal(b.stats.loaded, 0);
  a.retry();
  await settle();
  assert.equal(a.stats.loaded, 1);
});

test('pending WASM load holds ownership and must settle before construction and startGame', async () => {
  let resolve;
  const locks = new LockManagerFake();
  const a = loadShell(locks, { load: () => new Promise(yes => { resolve = yes; }) });
  await settle();
  assert.equal(a.state(), 'starting');
  assert.equal(a.stats.loaded, 1);
  assert.equal(a.stats.constructed, 0);
  assert.equal(a.stats.started, 0);
  const b = loadShell(locks);
  await settle();
  assert.equal(b.stats.loaded, 0);
  resolve();
  await settle();
  assert.equal(a.state(), 'running');
  assert.equal(a.stats.loaded, 1);
  assert.equal(a.stats.constructed, 1);
  assert.equal(a.stats.started, 1);
  assert.equal(locks.held.size, 1);
});

test('synchronous loader failure also reaches failure UI with the lock held', async () => {
  const locks = new LockManagerFake();
  const a = loadShell(locks, { load: () => { throw Error('loader exception'); } });
  await settle();
  assert.equal(a.state(), 'failed-held');
  assert.match(a.notice(), /loader exception/);
  assert.equal(a.stats.constructed, 0);
  assert.equal(locks.held.size, 1);
});
