import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import { beginPage, disposePage, subscribePage, pageCallback } from '../apps/dashboard/assets/js/core/page-lifecycle.js';
const source = (await fs.readFile(new URL('../apps/dashboard/assets/js/services/runtime-service.js', import.meta.url), 'utf8'))
  .replace(/^import .*;\r?\n/gm, '').replace(/export const runtimeService = new AroynRuntimeService\(\);/, 'globalThis.Service = AroynRuntimeService;').replace(/^export \{.*;\r?$/gm, '');
const checks = [];
async function check(name, test) { await test(); checks.push(name); }
function deferred() { let resolve, reject; const promise = new Promise((yes, no) => { resolve = yes; reject = no; }); return { promise, resolve, reject }; }
function response(body, status = 200) { return { ok: status < 400, status, json: async () => body }; }
const accounts = [{ userId: '101', username: 'alpha' }, { userId: '202', username: 'beta' }];
const envelope = id => ({ account: accounts.find(a => a.userId === id), online: true, snapshot: { player: { userId: id, name: id }, activity: [], modules: [], session: { durationSeconds: 12 } } });
async function settle() { for (let i = 0; i < 20; i++) await Promise.resolve(); }
function fixture(fetcher = async () => response({ accounts })) {
  const timers = new Map(); let next = 0, now = 1791000000000;
  const auth = { status: 'authenticated', token: 'synthetic-session', user: { id: 'fixture-user' } };
  const sockets = [];
  class Socket { static OPEN = 1; static CONNECTING = 0; constructor(url) { this.url = url; this.readyState = 0; sockets.push(this); } close() { this.readyState = 3; } }
  const context = vm.createContext({ structuredClone, AbortController, URL, console, performance, WebSocket: Socket, LiveSnapshotAssembler,
    Date: class extends Date { static now() { return now; } },
    setTimeout(fn, delay) { const id = ++next; timers.set(id, { fn, delay }); return id; }, clearTimeout(id) { timers.delete(id); }, queueMicrotask() {},
    mockRuntime: { config: {}, activity: [], logs: [], modules: [], session: {}, system: {}, connection: {} },
    API_BASE: 'https://api.example.test', LIVE_BASE: 'https://live.example.test', LIVE_WS_BASE: 'wss://live.example.test/socket',
    storage: { getRaw: (key, fallback) => fallback, setRaw() {} },
    authService: { getSnapshot: () => auth, subscribe() {}, init: async () => auth, isAuthenticated: () => auth.status === 'authenticated' },
    fetch: (...args) => fetcher(...args) });
  vm.runInContext(source, context);
  const service = new context.Service();
  service.state.bridge = { ...service.state.bridge, account: auth.user, accounts, accountsLoaded: true, selectedRobloxUserId: '101' };
  return { service, auth, timers, sockets, async runTimer(delay) { const entry = [...timers].find(([, t]) => t.delay === delay); assert(entry, `Missing ${delay}ms timer`); timers.delete(entry[0]); now += delay; return entry[1].fn(); } };
}
await check('switch starts a new snapshot and late old body cannot restore old selection', async () => {
  const old = deferred(); const calls = [];
  const f = fixture(async (url, opts) => { const id = new URL(url).searchParams.get('robloxUserId'); calls.push({ id, signal: opts.signal }); return id === '101' ? { ok: true, json: () => old.promise } : response(envelope(id)); });
  f.service.connectLive = async () => false;
  const first = f.service.pollOnce(); await settle();
  await f.service.selectRobloxAccount('202');
  assert.equal(calls.length, 2); assert(calls[0].signal.aborted);
  old.resolve(envelope('101')); await first; await settle();
  assert.equal(f.service.state.bridge.selectedRobloxUserId, '202'); assert.equal(f.service.state.live.player.userId, '202');
});
await check('old finally cannot release a newer pending snapshot', async () => {
  const a = deferred(), b = deferred(); let calls = 0;
  const f = fixture(async url => { calls++; return { ok: true, json: () => new URL(url).searchParams.get('robloxUserId') === '101' ? a.promise : b.promise }; });
  f.service.connectLive = async () => false;
  const old = f.service.pollOnce(); await settle();
  const next = f.service.selectRobloxAccount('202'); await settle(); await old;
  assert.equal(await f.service.pollOnce(), false); assert.equal(calls, 2);
  b.resolve(envelope('202')); await next; a.resolve(envelope('101')); await settle();
  assert.equal(f.service.state.live.player.userId, '202');
});
await check('rapid A B A switches reject an earlier response for the same ID', async () => {
  const bodies = []; const f = fixture(async () => { const body = deferred(); bodies.push(body); return { ok: true, json: () => body.promise }; });
  f.service.connectLive = async () => false;
  const first = f.service.pollOnce(); await settle(); const second = f.service.selectRobloxAccount('202'); await settle(); const third = f.service.selectRobloxAccount('101'); await settle();
  bodies[2].resolve({ ...envelope('101'), lastSeen: 300 }); await third;
  bodies[0].resolve({ ...envelope('101'), lastSeen: 100 }); bodies[1].resolve(envelope('202')); await Promise.all([first, second]); await settle();
  assert.equal(f.service.state.bridge.lastSeen, 300);
});
await check('logout while accounts JSON is pending cannot restore profile accounts', async () => {
  const body = deferred(); const f = fixture(async () => ({ ok: true, json: () => body.promise }));
  const request = f.service.refreshAccounts(0, true); await settle();
  f.auth.status = 'guest'; f.auth.token = null; f.service.disconnectAccount();
  body.resolve({ accounts }); await request; await settle();
  assert.equal(f.service.state.bridge.account, null); assert.equal(f.service.state.bridge.accounts.length, 0); assert.equal(f.timers.size, 0);
});
await check('initial accounts error completes error hydration and automatically recovers', async () => {
  let failed = true, calls = 0;
  const f = fixture(async url => { calls++; if (failed) throw new Error('Outage'); return response(String(url).endsWith('/accounts') ? { accounts } : envelope('101')); });
  f.service.connectLive = async () => false; f.service.state.bridge.account = null;
  await f.service.onAuth(f.auth);
  assert.equal(f.service.initialSyncReason, 'initial-runtime-error'); assert.match(f.service.state.bridge.error, /Outage/); assert.equal(calls, 1);
  assert([...f.timers.values()].some(t => t.delay === 6000));
  failed = false; await f.runTimer(6000);
  assert.equal(f.service.state.live.player.userId, '101'); assert.equal(f.service.state.bridge.error, null); assert.equal(f.service.requests.size, 0);
  f.service.disconnectAccount(); assert.equal(f.timers.size, 0);
});
for (const stage of ['fetch', 'body']) await check(`initial ${stage} hang times out and remains retryable`, async () => {
  const f = fixture(async () => stage === 'fetch' ? new Promise(() => {}) : { ok: true, json: () => new Promise(() => {}) });
  f.service.state.bridge.account = null; f.service.connectLive = async () => false;
  const hydration = f.service.onAuth(f.auth); await settle(); await f.runTimer(8000); await hydration;
  assert.match(f.service.state.bridge.error, /timed out/); assert.equal(f.service.requests.size, 0); assert.equal(f.service.initialSyncComplete, true);
  assert([...f.timers.values()].some(t => t.delay === 6000)); f.service.disconnectAccount(); assert.equal(f.timers.size, 0);
});
await check('stale live-token failure cannot change the current connection', async () => {
  const old = deferred(); const f = fixture(async (url, opts) => String(url).endsWith('/web-token') ? JSON.parse(opts.body).robloxUserId === '101' ? old.promise : response({ token: 'synthetic-web-token' }) : response(envelope('202')));
  const pending = f.service.connectLive(); await settle(); await f.service.selectRobloxAccount('202'); await settle();
  assert.equal(f.sockets.length, 1); f.sockets[0].readyState = 1; f.sockets[0].onopen();
  old.reject(new Error('Old failure')); await pending; await settle();
  assert.equal(f.service.state.bridge.liveTransport, 'connected'); assert.equal(f.service.state.bridge.error, null); assert.equal(f.service.wsAccountId, '202');
  f.service.disconnectAccount();
});
await check('wrong-account snapshot fails safely without changing selection', async () => {
  const f = fixture(async () => response(envelope('202'))); assert.equal(await f.service.pollOnce(), false);
  assert.equal(f.service.state.bridge.selectedRobloxUserId, '101'); assert.equal(f.service.state.live, null); assert.match(f.service.state.bridge.error, /did not match/);
});
await check('restarting polling during a tick creates only one next timer', async () => {
  const body = deferred(); const f = fixture(async () => ({ ok: true, json: () => body.promise }));
  f.service.accountsFetchedAt = Date.now(); f.service.isLiveHealthy = () => false; f.service.connectLive = async () => false;
  f.service.startPolling(); const tick = f.runTimer(6000); await settle(); f.service.startPolling();
  body.resolve(envelope('101')); await tick;
  assert.equal([...f.timers.values()].filter(t => t.delay === 6000).length, 1); f.service.disconnectAccount();
});
await check('repeated initial failures back off and logout cancels retries', async () => {
  let calls = 0; const f = fixture(async () => { calls++; throw new Error('Unavailable'); });
  f.service.state.bridge.account = null; f.service.connectLive = async () => false;
  await f.service.onAuth(f.auth);
  for (const delay of [6000, 12000, 24000, 30000]) await f.runTimer(delay);
  assert.equal(calls, 5); assert([...f.timers.values()].some(t => t.delay === 30000));
  f.auth.status = 'guest'; f.auth.token = null; f.service.disconnectAccount(); assert.equal(f.timers.size, 0);
});
await check('refreshing account list preserves a newer selection made during its JSON read', async () => {
  const list = deferred(); const f = fixture(async url => String(url).endsWith('/accounts') ? { ok: true, json: () => list.promise } : response(envelope('202')));
  f.service.connectLive = async () => false;
  const refresh = f.service.refreshAccounts(0, true); await settle(); await f.service.selectRobloxAccount('202');
  list.resolve({ accounts }); await refresh;
  assert.equal(f.service.state.bridge.selectedRobloxUserId, '202'); assert.equal(f.service.state.live.player.userId, '202');
});
await check('logout cancels pending snapshot and live token with no restoration or reconnect', async () => {
  const f = fixture(async () => new Promise(() => {}));
  const snapshot = f.service.pollOnce(); const live = f.service.connectLive(); await settle();
  f.auth.status = 'guest'; f.auth.token = null; f.service.disconnectAccount();
  assert.equal(await snapshot, false); assert.equal(await live, false); assert.equal(f.service.requests.size, 0);
  assert.equal(f.timers.size, 0); assert.equal(f.sockets.length, 0); assert.equal(f.service.state.bridge.selectedRobloxUserId, null);
});
await check('route disposal releases subscribers and ignores queued page callbacks', async () => {
  const listeners = new Set(); const service = { subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); } };
  let calls = 0;
  for (let i = 0; i < 40; i++) { beginPage(); subscribePage(service, () => calls++); assert.equal(listeners.size, 1); }
  const pending = pageCallback(() => calls++); const stale = [...listeners][0]; disposePage(); pending(); stale();
  assert.equal(listeners.size, 0); assert.equal(calls, 0); disposePage();
});
await check('repeated actual modules-page mounts leave only the current table subscribed', async () => {
  const listeners = new Set(); let snapshot = { modules: [] };
  const service = { getSnapshot: () => snapshot, subscribe(fn) { listeners.add(fn); return () => listeners.delete(fn); } };
  const pageSource = (await fs.readFile(new URL('../apps/dashboard/assets/js/pages/modules.js', import.meta.url), 'utf8')).replace(/^import .*;\r?\n/gm, '');
  const tables = [];
  for (let i = 0; i < 15; i++) {
    const nodes = new Map(); const document = { querySelector(q) { if (!nodes.has(q)) nodes.set(q, { value: '', innerHTML: '', hidden: true, addEventListener() {} }); return nodes.get(q); }, querySelectorAll() { return []; } };
    vm.runInNewContext(pageSource, { document, initPage: beginPage, subscribePage, runtimeService: service, escapeHTML: x => String(x), statusHTML: () => 'safe status' });
    tables.push(nodes.get('[data-module-body]')); assert.equal(listeners.size, 1);
  }
  snapshot = { modules: [{ name: 'current', type: 'local', status: 'running', loaded: 'yes' }] };
  for (const listener of listeners) listener(snapshot);
  assert(tables.at(-1).innerHTML.includes('current')); assert(tables.slice(0, -1).every(table => !table.innerHTML.includes('current')));
  disposePage(); assert.equal(listeners.size, 0);
  const shell = await fs.readFile(new URL('../apps/dashboard/assets/js/components/shell.js', import.meta.url), 'utf8');
  assert(shell.indexOf('disposePage();') < shell.indexOf('main.innerHTML=next.innerHTML;'));
});
await fs.writeFile(new URL('dashboard-stability-results.json', import.meta.url), JSON.stringify({ date: '2026-10-02', passed: checks.length, checks, scope: 'Actual runtime source in VM with deferred fetch/body and controlled timers; real page module and lifecycle; no browser or cloud writes.' }, null, 2) + '\n');
console.log(JSON.stringify({ passed: checks.length, checks }));
import {LiveSnapshotAssembler} from '../apps/dashboard/assets/js/services/live-snapshot.js';
