import {RETENTION, finishAccountDeletion, invalidateDataCaches} from './data-lifecycle.js';
import {withSnapshotStorage} from './snapshot-storage.js';

export const RETENTION_BATCH = Object.freeze({objects: 25, rows: 250, continuationMs: 10000, retryMs: 60000});
const DAY = 86400000;
const prefixes = ['runtime-v1/', 'runtime-v2/', 'runtime-v3/'];
const historyTables = [
  ['analytics_sessions', 'last_seen_at', 'history'],
  ['runtime_session_owners', 'last_seen_at', 'history'],
  ['runtime_presence', 'last_seen_at', 'presence'],
  ['live_presence', 'last_seen_at', 'presence'],
  ['roblox_profile_cache', 'updated_at', 'history'],
  ['web_sessions', 'expires_at', 'session'],
  ['auth_exchanges', 'expires_at', 'session'],
  ['owner_analytics_cache', null, null],
];

export function newRetentionCycle(now = Date.now()) {
  if (!Number.isSafeInteger(now) || now <= 0) throw new Error('Invalid retention clock');
  return {active: true, now, phase: 'deletions', jobCursor: '', table: 0, prefix: 0, cursor: null,
    snapshotsRemoved: 0, objectsVisited: 0, rowsRemoved: 0, pendingDeletions: 0, steps: 0, failures: 0};
}

// One bounded step. Persist its returned checkpoint only after every side
// effect succeeds; retrying an earlier page is safe through per-key expiry.
export async function retentionStep(env, checkpoint) {
  env = withSnapshotStorage(env);
  const state = structuredClone(checkpoint);
  state.steps++;
  state.failures = 0;
  if (state.phase === 'deletions') {
    const job = await env.DB.prepare('SELECT * FROM account_deletions WHERE user_id > ?1 ORDER BY user_id LIMIT 1').bind(state.jobCursor).first();
    if (!job) { state.phase = 'history'; return state; }
    try {
      if (await finishAccountDeletion(env, job, {maxObjects: RETENTION_BATCH.objects})) state.jobCursor = job.user_id;
    } catch {
      // One broken account does not starve unrelated expiry. It remains
      // revoked in D1 and is retried by a later cycle.
      state.pendingDeletions++; state.jobCursor = job.user_id;
    }
    return state;
  }
  if (state.phase === 'history') {
    const [table, column, kind] = historyTables[state.table];
    const cutoff = kind === 'history' ? state.now - RETENTION.historyDays * DAY : kind === 'presence' ? state.now - 15 * 60000 : state.now;
    const where = column ? `WHERE ${column} ${kind === 'session' ? '<=' : '<'} ?1 ORDER BY ${column}` : '';
    const statement = env.DB.prepare(`DELETE FROM ${table} WHERE rowid IN (SELECT rowid FROM ${table} ${where} LIMIT ${RETENTION_BATCH.rows})`);
    const result = await (column ? statement.bind(cutoff) : statement).run();
    const changes = Number(result.meta?.changes || 0);
    state.rowsRemoved += changes;
    if (changes < RETENTION_BATCH.rows) state.table++;
    if (state.table === historyTables.length) { state.phase = 'snapshots'; delete state.jobCursor; }
    return state;
  }
  if (state.phase === 'snapshots') {
    const page = await env.PAYLOADS.list({prefix: prefixes[state.prefix], limit: RETENTION_BATCH.objects, ...(state.cursor ? {cursor: state.cursor} : {})});
    const cutoff = state.now - RETENTION.snapshotDays * DAY;
    for (const object of page.objects) {
      state.objectsVisited++;
      if (object.key.includes('/revoked/') || object.uploaded.getTime() >= cutoff) continue;
      if (await env.PAYLOADS.expire(object.key, object.etag, cutoff)) state.snapshotsRemoved++;
    }
    if (page.truncated) {
      if (!page.cursor || page.cursor === state.cursor) throw new Error('R2 listing did not advance');
      state.cursor = page.cursor;
    } else { state.prefix++; state.cursor = null; }
    if (state.prefix === prefixes.length) state.phase = 'invalidate';
    return state;
  }
  if (state.phase === 'invalidate') {
    await invalidateDataCaches(env);
    return {active: false, completedAt: Date.now(), now: state.now, steps: state.steps,
      snapshotsRemoved: state.snapshotsRemoved, objectsVisited: state.objectsVisited,
      rowsRemoved: state.rowsRemoved, pendingDeletions: state.pendingDeletions,
      followupRequested: state.followupRequested === true, failures: 0};
  }
  throw new Error('Unknown retention phase');
}

// This object handles only maintenance, never user requests or telemetry.
// Serialized handlers plus a durable checkpoint prevent overlapping sweeps.
export class AroynRetentionRunner {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; this.tail = Promise.resolve(); }
  enqueue(fn) {
    const task = this.tail.then(fn);
    this.tail = task.then(() => undefined, () => undefined);
    return task;
  }
  async save(state, delay) {
    await this.ctx.storage.transaction(async storage => {
      await storage.put('progress', state);
      if (delay === null) await storage.deleteAlarm();
      else await storage.setAlarm(Date.now() + delay);
    });
  }
  fetch(request) {
    return this.enqueue(async () => {
      const path = new URL(request.url).pathname;
      const previous = await this.ctx.storage.get('progress');
      if (path === '/status' && request.method === 'GET') return Response.json(previous || {active: false});
      if (path !== '/start' || request.method !== 'POST') return new Response('Not found', {status: 404});
      if (previous?.active) {
        if (request.headers.get('x-retention-deletion') === 'true') {
          await this.ctx.storage.put('progress', {...previous, followupRequested: true});
        }
        if (await this.ctx.storage.getAlarm() === null) await this.ctx.storage.setAlarm(Date.now() + RETENTION_BATCH.continuationMs);
        return Response.json({ok: true, started: false, active: true});
      }
      const now = Number(request.headers.get('x-retention-now') || Date.now());
      await this.save(newRetentionCycle(now), RETENTION_BATCH.continuationMs);
      return Response.json({ok: true, started: true, active: true});
    });
  }
  alarm() {
    return this.enqueue(async () => {
      let state = await this.ctx.storage.get('progress');
      if (!state?.active) {
        if (!state?.pendingDeletions && !state?.followupRequested) return;
        state = newRetentionCycle();
      }
      try {
        const next = await retentionStep(this.env, state);
        await this.save(next, next.active ? RETENTION_BATCH.continuationMs : next.pendingDeletions || next.followupRequested ? 5 * 60000 : null);
        if (!next.active) console.log(JSON.stringify({event: 'account-data-maintenance-completed', steps: next.steps,
          snapshotsRemoved: next.snapshotsRemoved, rowsRemoved: next.rowsRemoved, pendingDeletions: next.pendingDeletions}));
      } catch {
        // Persisted backoff outlives the provider's limited alarm retries.
        const failures = Math.min((state.failures || 0) + 1, 7);
        await this.save({...state, failures}, Math.min(RETENTION_BATCH.retryMs * 2 ** (failures - 1), 3600000));
        console.log(JSON.stringify({event: 'retention-step-retry', phase: state.phase, failures}));
      }
    });
  }
}
