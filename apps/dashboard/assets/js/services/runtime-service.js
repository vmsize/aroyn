import { mockRuntime } from '../data/mock-runtime.js';
import { storage } from '../core/storage.js';
import { authService } from './auth-service.js';
import { API_BASE, LIVE_BASE, LIVE_WS_BASE } from '../core/config.js';

const API_DEFAULT = API_BASE;
const LIVE_DEFAULT = LIVE_BASE;
const LIVE_WS_DEFAULT = LIVE_WS_BASE;
const clone = value => structuredClone(value);

function formatDuration(total) {
  if (total == null || Number.isNaN(Number(total))) return null;
  let seconds = Math.max(0, Math.floor(Number(total)));
  const h = Math.floor(seconds / 3600);
  seconds %= 3600;
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}h ${String(m).padStart(2, '0')}m ${String(s).padStart(2, '0')}s`;
  return `${m}m ${String(s).padStart(2, '0')}s`;
}

function toneToKind(tone) {
  return tone === 'success' ? 'success' : tone === 'warning' ? 'warning' : tone === 'error' ? 'warning' : 'info';
}

function toneToLevel(tone) {
  return tone === 'success' ? 'success' : tone === 'warning' ? 'warning' : tone === 'error' ? 'error' : tone === 'diagnostic' ? 'debug' : 'info';
}

class VeyraRuntimeService {
  constructor() {
    this.state = clone(mockRuntime);
    this.state.live = null;
    this.apiBase = String(storage.getRaw('runtime.apiBase', API_DEFAULT) || API_DEFAULT).replace(/\/+$/, '');
    this.state.bridge = {
      account: null,
      apiBase: this.apiBase,
      lastSeen: null,
      error: null,
      browserLatency: null,
      accounts: [],
      accountsLoaded: false,
      selectedRobloxUserId: null,
      liveTransport: 'idle'
    };

    this.listeners = new Set();
    this.timer = null;
    this.inFlight = false;
    this.accountsInFlight = false;
    this.accountsFetchedAt = 0;
    this.generation = 0;
    this.logCutoff = 0;

    this.ws = null;
    this.wsAccountId = null;
    this.wsReconnectTimer = null;
    this.wsReconnectAttempt = 0;
    this.wsLastMessageAt = 0;
    this.wsLastSnapshotAt = 0;

    // Initial dashboard hydration gate. The UI can wait for the first
    // authenticated account lookup + runtime snapshot instead of briefly
    // showing stale/default cards on page entry.
    this.initialSyncComplete = false;
    this.initialSyncReason = null;
    this.initialSyncPromise = new Promise(resolve => {
      this.resolveInitialSync = resolve;
    });
    this.initialHydrationPromise = null;

    if (typeof document !== 'undefined') {
      document.addEventListener('visibilitychange', () => {
        if (document.visibilityState === 'visible' && authService.isAuthenticated()) {
          const gen = this.generation;
          if (!this.isLiveSocketOpenForSelected()) this.connectLive(gen);
          if (Date.now() - this.accountsFetchedAt > this.accountsDelay()) this.refreshAccounts(gen, false);
          if (!this.isLiveHealthy()) this.pollOnce(gen);
          this.startPolling(gen);
        }
      });
    }

    authService.subscribe(snapshot => this.onAuth(snapshot));
    queueMicrotask(() => authService.init().then(snapshot => this.onAuth(snapshot)));
  }

  getSnapshot() { return clone(this.state); }
  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); }

  markInitialSyncComplete(reason = 'ready') {
    if (this.initialSyncComplete) return;
    this.initialSyncComplete = true;
    this.initialSyncReason = reason;
    this.resolveInitialSync?.({ reason, snapshot: this.getSnapshot() });
  }

  waitForInitialSync() {
    if (this.initialSyncComplete) {
      return Promise.resolve({ reason: this.initialSyncReason || 'ready', snapshot: this.getSnapshot() });
    }
    return this.initialSyncPromise;
  }

  emit() {
    const snapshot = this.getSnapshot();
    this.listeners.forEach(fn => {
      try { fn(snapshot); }
      catch (err) { console.error('[Veyra] runtime listener failed', err); }
    });
  }

  getApiBase() { return this.apiBase; }
  setApiBase(value) {
    this.apiBase = String(value || API_DEFAULT).trim().replace(/\/+$/, '') || API_DEFAULT;
    storage.setRaw('runtime.apiBase', this.apiBase);
    this.state.bridge.apiBase = this.apiBase;
    this.emit();
  }

  selectionKey(userId) { return `runtime.robloxAccountId.${String(userId || 'guest')}`; }
  selectedAccount() {
    const id = String(this.state.bridge.selectedRobloxUserId || '');
    return (this.state.bridge.accounts || []).find(account => String(account.userId) === id) || null;
  }
  isPageVisible() { return typeof document === 'undefined' || document.visibilityState !== 'hidden'; }
  pollDelay() { return this.isPageVisible() ? 6000 : 30000; }
  accountsDelay() { return this.isPageVisible() ? 60000 : 180000; }

  isLiveSocketOpenForSelected() {
    const selected = String(this.state.bridge.selectedRobloxUserId || '');
    return Boolean(
      this.ws &&
      this.ws.readyState === WebSocket.OPEN &&
      selected &&
      this.wsAccountId === selected
    );
  }

  isLiveHealthy() {
    if (!this.isLiveSocketOpenForSelected()) return false;
    if (!this.wsLastSnapshotAt) return Date.now() - this.wsLastMessageAt < 15000;
    return Date.now() - this.wsLastSnapshotAt < 15000;
  }

  async onAuth(auth) {
    if (auth.status === 'authenticated' && auth.user && auth.token) {
      const same = this.state.bridge.account?.id === auth.user.id;
      this.state.bridge = { ...this.state.bridge, account: auth.user, apiBase: this.apiBase, error: null };

      // authService can publish the same authenticated snapshot more than once
      // during page startup. Do not allow a second startup pass to skip the
      // in-flight /accounts request and prematurely resolve the dashboard loader.
      if (this.initialHydrationPromise) {
        await this.initialHydrationPromise;
        return;
      }

      if (!same || !this.timer) {
        const hydration = (async () => {
          this.generation += 1;
          const gen = this.generation;
          this.stopPolling();
          this.disconnectLive(false);

          const saved = storage.getRaw(this.selectionKey(auth.user.id), '');
          this.state.bridge.accounts = [];
          this.state.bridge.accountsLoaded = false;
          this.state.bridge.selectedRobloxUserId = saved || null;
          this.state.bridge.liveTransport = 'connecting';
          this.state.connection = { state: 'idle', label: 'Connecting', detail: 'Loading your Roblox accounts.' };
          this.emit();

          const accountsReady = await this.refreshAccounts(gen, true);
          if (gen !== this.generation) return;

          // Do not consider the dashboard hydrated until the accounts endpoint
          // has actually completed successfully. This prevents the temporary
          // "No Roblox account" state from flashing on startup.
          if (!accountsReady || !this.state.bridge.accountsLoaded) {
            return;
          }

          await this.pollOnce(gen);
          if (gen !== this.generation) return;

          this.markInitialSyncComplete('initial-runtime-sync');

          if (authService.isAuthenticated()) {
            this.connectLive(gen);
            this.startPolling(gen);
          }
        })();

        this.initialHydrationPromise = hydration;
        try {
          await hydration;
        } finally {
          if (this.initialHydrationPromise === hydration) {
            this.initialHydrationPromise = null;
          }
        }
      } else if (!this.initialSyncComplete && this.state.bridge.accountsLoaded) {
        this.markInitialSyncComplete('already-initialized');
      }
      return;
    }

    if (auth.status === 'guest') {
      this.markInitialSyncComplete('guest');
      this.disconnectAccount();
    }
  }

  disconnectAccount() {
    this.generation += 1;
    this.stopPolling();
    this.disconnectLive(false);
    const config = { ...this.state.config };
    this.state = clone(mockRuntime);
    this.state.config = config;
    this.state.live = null;
    this.state.bridge = {
      account: null,
      apiBase: this.apiBase,
      lastSeen: null,
      error: null,
      browserLatency: null,
      accounts: [],
      accountsLoaded: false,
      selectedRobloxUserId: null,
      liveTransport: 'idle'
    };
    this.state.connection = { state: 'disconnected', label: 'Signed out', detail: 'Sign in with Discord to view your Aroyn runtime.' };
    this.emit();
  }

  startPolling(gen = this.generation) {
    this.stopPolling();

    const tick = async () => {
      if (gen !== this.generation || !authService.isAuthenticated()) return;

      if (Date.now() - this.accountsFetchedAt > this.accountsDelay()) {
        await this.refreshAccounts(gen, false);
      }

      if (!this.isLiveSocketOpenForSelected()) this.connectLive(gen);
      if (!this.isLiveHealthy()) await this.pollOnce(gen);

      if (gen === this.generation && authService.isAuthenticated()) {
        this.timer = setTimeout(tick, this.pollDelay());
      }
    };

    this.timer = setTimeout(tick, this.pollDelay());
  }

  stopPolling() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = null;
    }
  }

  disconnectLive(markState = true) {
    if (this.wsReconnectTimer) {
      clearTimeout(this.wsReconnectTimer);
      this.wsReconnectTimer = null;
    }

    const socket = this.ws;
    this.ws = null;
    this.wsAccountId = null;
    this.wsLastMessageAt = 0;
    this.wsLastSnapshotAt = 0;

    if (socket) {
      try {
        socket.onopen = null;
        socket.onmessage = null;
        socket.onerror = null;
        socket.onclose = null;
        socket.close(1000, 'Veyra reconnect');
      } catch {}
    }

    if (markState && this.state.bridge) {
      this.state.bridge = { ...this.state.bridge, liveTransport: 'idle' };
    }
  }

  scheduleLiveReconnect(gen) {
    if (gen !== this.generation || !authService.isAuthenticated()) return;
    if (this.wsReconnectTimer) return;
    const selected = String(this.state.bridge.selectedRobloxUserId || '');
    if (!selected) return;

    const delays = [1000, 2000, 5000, 10000, 15000];
    const delay = delays[Math.min(this.wsReconnectAttempt, delays.length - 1)];
    this.wsReconnectAttempt += 1;

    this.wsReconnectTimer = setTimeout(() => {
      this.wsReconnectTimer = null;
      this.connectLive(gen);
    }, delay);
  }

  async connectLive(gen = this.generation) {
    const auth = authService.getSnapshot();
    const selected = String(this.state.bridge.selectedRobloxUserId || '');

    if (!auth.token || !selected || gen !== this.generation) return false;
    if (this.isLiveSocketOpenForSelected()) return true;

    if (this.ws && this.wsAccountId !== selected) this.disconnectLive(false);
    if (this.ws && this.ws.readyState === WebSocket.CONNECTING && this.wsAccountId === selected) return true;

    this.state.bridge = { ...this.state.bridge, liveTransport: 'connecting' };
    this.emit();

    try {
      const tokenResponse = await fetch(`${LIVE_DEFAULT}/web-token`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${auth.token}`,
          'Content-Type': 'application/json',
          'Accept': 'application/json'
        },
        body: JSON.stringify({ robloxUserId: selected }),
        cache: 'no-store'
      });

      const tokenBody = await tokenResponse.json().catch(() => ({}));
      if (gen !== this.generation || selected !== String(this.state.bridge.selectedRobloxUserId || '')) return false;
      if (!tokenResponse.ok || !tokenBody.token) throw new Error(tokenBody.error || `Live token API returned ${tokenResponse.status}`);

      const socket = new WebSocket(`${LIVE_WS_DEFAULT}?token=${encodeURIComponent(tokenBody.token)}`);
      this.ws = socket;
      this.wsAccountId = selected;

      socket.onopen = () => {
        if (socket !== this.ws || gen !== this.generation) return;
        this.wsReconnectAttempt = 0;
        this.wsLastMessageAt = Date.now();
        this.state.bridge = { ...this.state.bridge, liveTransport: 'connected', error: null };
        this.emit();
      };

      socket.onmessage = event => {
        if (socket !== this.ws || gen !== this.generation) return;
        this.wsLastMessageAt = Date.now();

        let message;
        try { message = JSON.parse(event.data); }
        catch { return; }

        if (message?.type === 'connected') {
          this.state.bridge = { ...this.state.bridge, liveTransport: 'connected', error: null };
          this.emit();
          return;
        }

        if (message?.type !== 'snapshot') return;
        if (String(message?.player?.userId || '') !== selected) return;

        this.wsLastSnapshotAt = Date.now();
        this.applyEnvelope({
          online: true,
          snapshot: message,
          account: this.selectedAccount(),
          lastSeen: message.sentAt || Date.now()
        }, 0);
      };

      socket.onerror = () => {
        if (socket !== this.ws) return;
        this.state.bridge = { ...this.state.bridge, liveTransport: 'warning' };
        this.emit();
      };

      socket.onclose = () => {
        if (socket !== this.ws) return;
        this.ws = null;
        this.wsAccountId = null;
        this.wsLastMessageAt = 0;
        this.wsLastSnapshotAt = 0;
        this.state.bridge = { ...this.state.bridge, liveTransport: 'reconnecting' };
        this.emit();
        this.scheduleLiveReconnect(gen);
      };

      return true;
    } catch (err) {
      if (gen !== this.generation) return false;
      const message = err instanceof Error ? err.message : String(err);
      this.state.bridge = { ...this.state.bridge, liveTransport: 'reconnecting', error: message };
      this.emit();
      this.scheduleLiveReconnect(gen);
      return false;
    }
  }

  async refreshAccounts(gen = this.generation, force = false) {
    const auth = authService.getSnapshot();
    if (!auth.token || this.accountsInFlight) return false;
    if (!force && Date.now() - this.accountsFetchedAt < 30000) return true;

    this.accountsInFlight = true;
    try {
      const response = await fetch(`${this.apiBase}/api/v2/runtime/accounts`, {
        headers: { Authorization: `Bearer ${auth.token}`, 'Accept': 'application/json' },
        cache: 'no-store'
      });
      if (gen !== this.generation) return false;

      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error || `Accounts API returned ${response.status}`);

      const accounts = Array.isArray(body.accounts) ? body.accounts : [];
      const previous = String(this.state.bridge.selectedRobloxUserId || '');
      let selected = previous && accounts.some(account => String(account.userId) === previous) ? previous : null;
      if (!selected) {
        const online = accounts.find(account => account.online);
        selected = String((online || accounts[0])?.userId || '') || null;
      }

      this.state.bridge = {
        ...this.state.bridge,
        accounts,
        accountsLoaded: true,
        selectedRobloxUserId: selected
      };
      if (selected && auth.user?.id) storage.setRaw(this.selectionKey(auth.user.id), selected);
      this.accountsFetchedAt = Date.now();
      this.emit();
      return true;
    } catch (err) {
      if (gen !== this.generation) return false;
      this.state.bridge = { ...this.state.bridge, error: err instanceof Error ? err.message : String(err) };
      this.emit();
      return false;
    } finally {
      this.accountsInFlight = false;
    }
  }

  async selectRobloxAccount(userId) {
    const id = String(userId || '');
    const account = (this.state.bridge.accounts || []).find(item => String(item.userId) === id);
    if (!account || id === String(this.state.bridge.selectedRobloxUserId || '')) return Boolean(account);

    const auth = authService.getSnapshot();
    this.disconnectLive(false);
    this.state.bridge = { ...this.state.bridge, selectedRobloxUserId: id, error: null, liveTransport: 'connecting' };
    if (auth.user?.id) storage.setRaw(this.selectionKey(auth.user.id), id);

    this.state.live = null;
    this.state.connection = { state: 'idle', label: 'Switching account', detail: `Loading ${account.username || account.displayName || 'Roblox account'}.` };
    this.emit();

    await this.pollOnce(this.generation);
    this.connectLive(this.generation);
    return true;
  }

  async removeRobloxAccount(userId) {
    const id = String(userId || '');
    const auth = authService.getSnapshot();
    if (!id || !auth.token) throw new Error('Authentication required.');

    const response = await fetch(`${this.apiBase}/api/v2/runtime/accounts/${encodeURIComponent(id)}`, {
      method: 'DELETE',
      headers: { Authorization: `Bearer ${auth.token}`, 'Accept': 'application/json' },
      cache: 'no-store'
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(body.error || `Remove account API returned ${response.status}`);

    const wasSelected = id === String(this.state.bridge.selectedRobloxUserId || '');
    if (wasSelected) this.disconnectLive(false);

    this.state.bridge = {
      ...this.state.bridge,
      accounts: (this.state.bridge.accounts || []).filter(account => String(account.userId) !== id),
      selectedRobloxUserId: wasSelected ? null : this.state.bridge.selectedRobloxUserId,
      error: null,
      liveTransport: wasSelected ? 'idle' : this.state.bridge.liveTransport
    };

    if (wasSelected && auth.user?.id) storage.setRaw(this.selectionKey(auth.user.id), '');
    if (wasSelected) this.state.live = null;
    this.emit();

    await this.refreshAccounts(this.generation, true);
    if (wasSelected) {
      await this.pollOnce(this.generation);
      this.connectLive(this.generation);
    }
    return true;
  }

  async pollOnce(gen = this.generation) {
    const auth = authService.getSnapshot();
    if (!auth.token || this.inFlight) return false;

    const selected = String(this.state.bridge.selectedRobloxUserId || '');
    if (!selected) {
      this.state.live = null;
      this.state.connection = { state: 'disconnected', label: 'Waiting for runtime', detail: 'Run Aroyn Hub on a Roblox account using your dashboard key.' };
      this.state.session = { started: null, duration: null, environment: null };
      this.state.task = null;
      this.state.system = { cpu: null, memory: null, latency: null };
      this.emit();
      return false;
    }

    this.inFlight = true;
    const started = performance.now();
    try {
      const endpoint = new URL(`${this.apiBase}/api/v2/runtime/snapshot`);
      endpoint.searchParams.set('robloxUserId', selected);
      const response = await fetch(endpoint.toString(), {
        headers: { Authorization: `Bearer ${auth.token}`, 'Accept': 'application/json' },
        cache: 'no-store'
      });

      if (gen !== this.generation) return false;
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error || `API returned ${response.status}`);
      this.applyEnvelope(body, Math.round(performance.now() - started));
      return true;
    } catch (err) {
      if (gen !== this.generation) return false;
      const message = err instanceof Error ? err.message : String(err);
      this.state.bridge = { ...this.state.bridge, error: message };
      this.state.connection = this.state.live
        ? { state: 'warning', label: 'Reconnecting', detail: 'The dashboard cannot currently reach the Aroyn API.' }
        : { state: 'disconnected', label: 'Offline', detail: 'No live runtime data is available.' };
      this.emit();
      return false;
    } finally {
      this.inFlight = false;
    }
  }

  applyEnvelope(envelope, browserLatency) {
    const payload = envelope?.snapshot || null;
    const online = Boolean(envelope?.online && payload);
    const account = envelope?.account || this.selectedAccount();

    if (account) {
      const accounts = (this.state.bridge.accounts || []).map(item =>
        String(item.userId) === String(account.userId) ? { ...item, ...account, online: online || item.online } : item
      );
      this.state.bridge = { ...this.state.bridge, accounts, selectedRobloxUserId: String(account.userId) };
    }

    this.state.bridge = {
      ...this.state.bridge,
      apiBase: this.apiBase,
      lastSeen: envelope?.lastSeen || null,
      error: null,
      browserLatency,
      liveTransport: this.isLiveSocketOpenForSelected() ? 'connected' : this.state.bridge.liveTransport
    };

    if (!payload) {
      this.state.live = null;
      this.state.connection = {
        state: 'disconnected',
        label: 'Waiting for runtime',
        detail: account ? `${account.username || account.displayName || 'Selected account'} is not currently sending telemetry.` : 'Run Aroyn Hub with your dashboard key.'
      };
      this.state.session = { started: null, duration: null, environment: null };
      this.state.task = null;
      this.state.system = { cpu: null, memory: null, latency: browserLatency ? `${browserLatency} ms` : null };
      this.emit();
      return;
    }

    const activity = (payload.activity || []).map(entry => ({
      time: entry.time || '—',
      kind: toneToKind(entry.tone),
      title: entry.message || 'Runtime event',
      detail: entry.detail || ''
    }));

    const logs = (payload.logs || payload.activity || []).map((entry, index) => ({
      id: entry.id || `${entry.time || 't'}-${index}`,
      time: entry.time || '—',
      level: entry.level || toneToLevel(entry.tone),
      message: entry.message || entry.title || 'Runtime event',
      ts: entry.ts || 0
    })).filter(entry => !this.logCutoff || !entry.ts || entry.ts >= this.logCutoff);

    this.state.connection = online
      ? { state: 'connected', label: 'Connected', detail: `${payload.player?.name || account?.username || 'Runtime'} · ${payload.product?.mode || 'Aroyn Hub'}` }
      : { state: 'warning', label: 'Runtime stale', detail: `${payload.player?.name || account?.username || 'Runtime'} stopped sending telemetry.` };

    this.state.session = {
      started: payload.session?.startedAt || null,
      duration: formatDuration(payload.session?.durationSeconds),
      environment: payload.product?.mode || payload.runtime?.environment || null,
      id: payload.session?.id || null
    };

    this.state.task = payload.runtime?.currentTask
      ? { name: payload.runtime.currentTask, detail: payload.runtime.taskDetail || '' }
      : null;

    this.state.system = {
      cpu: null,
      memory: null,
      latency: payload.runtime?.pushLatencyMs != null
        ? `${Math.round(payload.runtime.pushLatencyMs)} ms`
        : (browserLatency ? `${browserLatency} ms` : null)
    };

    this.state.activity = activity.length ? activity : this.state.activity;
    this.state.logs = logs;
    this.state.modules = Array.isArray(payload.modules) && payload.modules.length ? payload.modules : this.state.modules;
    this.state.live = payload;
    this.emit();
  }

  clearLogs() { this.logCutoff = Date.now(); this.state.logs = []; this.emit(); }
  updateConfig(patch) { Object.assign(this.state.config, patch); this.emit(); }
  setConnectionStatus(state, label, detail) { this.state.connection = { state, label, detail }; this.emit(); }
  addLog(entry) {
    this.state.logs.push({
      id: Date.now(),
      time: new Date().toLocaleTimeString([], { hour12: false }),
      ...entry
    });
    this.emit();
  }
}

export const runtimeService = new VeyraRuntimeService();
export { API_DEFAULT as DEFAULT_API_BASE };
