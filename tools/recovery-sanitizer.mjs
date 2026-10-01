import {finishAccountDeletion, invalidateDataCaches} from '../workers/shared/data-lifecycle.js';
import {withSnapshotStorage} from '../workers/shared/snapshot-storage.js';
import {newRetentionCycle, retentionStep} from '../workers/shared/retention-runner.js';

const prefixes = ['runtime-v1/', 'runtime-v2/', 'runtime-v3/'];
const resetTables = ['live_presence', 'runtime_presence', 'roblox_accounts', 'roblox_profile_cache', 'owner_analytics_cache'];
// Operator-only helper: no public route, deployment command or automatic reopen.
// These assertions are prerequisites supplied by the operator, not independent
// proof of access closure, manifest completeness or secret rotation.
export function validateRecovery(manifest, context) {
  for (const flag of ['isolatedDestination', 'apiAccessClosed', 'liveAccessClosed', 'freshDurableObjects', 'signingSecretsRotated']) {
    if (context?.[flag] !== true) throw new Error('Recovery prerequisite missing: ' + flag);
  }
  if (manifest?.format !== 'aroyn-recovery-deletions-v1' || manifest.complete !== true || !Array.isArray(manifest.deletions)) throw new Error('Complete external deletion manifest required');
  const clocks = [context.backupAt, context.frozenAt, manifest.coverageFrom, manifest.coverageThrough];
  if (clocks.some(n => !Number.isSafeInteger(n) || n <= 0) || context.backupAt > context.frozenAt || manifest.coverageFrom > context.backupAt || manifest.coverageThrough < context.frozenAt) throw new Error('Deletion coverage does not span backup through access freeze');
  const seen = new Set();
  for (const event of manifest.deletions) {
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(event.userId || '') || !Number.isSafeInteger(event.requestedAt) || event.requestedAt < manifest.coverageFrom || event.requestedAt > manifest.coverageThrough || seen.has(event.userId)) throw new Error('Invalid deletion event');
    seen.add(event.userId);
  }
}

export async function recoveryStep(environment, manifest, context, checkpoint = null) {
  validateRecovery(manifest, context);
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(JSON.stringify({manifest, context})));
  const fingerprint = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('');
  if (checkpoint && checkpoint.fingerprint !== fingerprint) throw new Error('Recovery inputs changed');
  const state = checkpoint ? structuredClone(checkpoint) : {fingerprint, phase: 'revoke', event: 0, prefix: 0, table: 0, steps: 0};
  const env = withSnapshotStorage(environment);
  state.steps++;
  if (state.phase === 'revoke') {
    // Preserve preexisting pending jobs and their legacy hashes before reset.
    await env.DB.batch([
      env.DB.prepare('DELETE FROM web_sessions'), env.DB.prepare('DELETE FROM auth_exchanges'),
      env.DB.prepare('UPDATE users SET dashboard_key_hash=NULL, dashboard_key_suffix=NULL'),
    ]);
    state.phase = 'mark';
  } else if (state.phase === 'mark') {
    const event = manifest.deletions[state.event];
    if (event) {
      await env.DB.prepare('INSERT OR IGNORE INTO account_deletions(user_id,requested_at) VALUES (?1,?2)').bind(event.userId, event.requestedAt).run();
      state.event++;
    } else state.phase = 'delete';
  } else if (state.phase === 'delete') {
    const job = await env.DB.prepare('SELECT * FROM account_deletions ORDER BY user_id LIMIT 1').first();
    if (job) await finishAccountDeletion(env, job, {maxObjects: 25});
    else state.phase = 'runtime';
  } else if (state.phase === 'runtime') {
    // Conservative recovery discards ALL old snapshots and associations,
    // including post-backup unlinks whose individual history is unavailable.
    const page = await env.PAYLOADS.list({prefix: prefixes[state.prefix], limit: 25});
    for (const object of page.objects) await env.PAYLOADS.delete(object.key);
    if (!page.truncated && page.objects.length < 25) state.prefix++;
    if (state.prefix === prefixes.length) state.phase = 'reset';
  } else if (state.phase === 'reset') {
    // Offline operation. Scoped deletion/cascades and table resets are not
    // claimed to fit a production Worker invocation's CPU or SQL budget.
    await env.DB.prepare('DELETE FROM ' + resetTables[state.table]).run();
    state.table++;
    if (state.table === resetTables.length) {
      state.phase = 'retention'; state.retention = newRetentionCycle(context.frozenAt);
    }
  } else if (state.phase === 'retention') {
    state.retention = await retentionStep(env, state.retention);
    if (!state.retention.active) {
      if (state.retention.pendingDeletions || await env.DB.prepare('SELECT user_id FROM account_deletions LIMIT 1').first()) throw new Error('Recovery deletion remains pending');
      await invalidateDataCaches(env);
      state.phase = 'done'; delete state.retention;
    }
  } else if (state.phase !== 'done') throw new Error('Unknown recovery phase');
  return {...state, sanitized: state.phase === 'done', reopenAllowed: false};
}
