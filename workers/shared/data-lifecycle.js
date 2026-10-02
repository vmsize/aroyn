import {withSnapshotStorage} from './snapshot-storage.js';
import {recordDeletion, recordDeletionReceipt} from './deletion-ledger.js';
export const RETENTION = Object.freeze({historyDays: 30, snapshotDays: 7, webSessionDays: 30, profile: 'until-account-deletion'});
export const OWNER_CHECKPOINT_MS = 60000;

// Ownership is an authenticated Aroyn association, not proof of Roblox ownership.
export async function claimRuntimeSession(env, userId, robloxUserId, sessionId, now = Date.now()) {
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(String(sessionId || ''))) return false;
  const result = await env.DB.prepare(`
    INSERT INTO runtime_session_owners (session_id, veyra_user_id, roblox_user_id, first_linked_at, last_seen_at)
    SELECT ?1, id, ?3, ?4, ?4 FROM users
    WHERE id = ?2 AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id = ?2)
      AND NOT EXISTS (SELECT 1 FROM analytics_sessions WHERE session_id=?1 AND roblox_user_id<>?3)
      AND NOT EXISTS (SELECT 1 FROM runtime_presence WHERE session_id=?1 AND roblox_user_id<>?3)
    ON CONFLICT(session_id) DO UPDATE SET last_seen_at = excluded.last_seen_at
    WHERE runtime_session_owners.veyra_user_id = excluded.veyra_user_id
      AND runtime_session_owners.roblox_user_id = excluded.roblox_user_id
      AND runtime_session_owners.last_seen_at <= ?5
  `).bind(String(sessionId), userId, String(robloxUserId), now, now - OWNER_CHECKPOINT_MS).run();
  if (Number(result.meta?.changes || 0) > 0) return true;
  // A skipped timestamp write is not proof of ownership. Recheck the same
  // identity/revocation/collision rules even within the checkpoint interval.
  const existing = await env.DB.prepare(`SELECT 1 AS permitted
    FROM runtime_session_owners o JOIN users u ON u.id=o.veyra_user_id
    WHERE o.session_id=?1 AND u.id=?2 AND o.roblox_user_id=?3
      AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id=?2)
      AND NOT EXISTS (SELECT 1 FROM analytics_sessions WHERE session_id=?1 AND roblox_user_id<>?3)
      AND NOT EXISTS (SELECT 1 FROM runtime_presence WHERE session_id=?1 AND roblox_user_id<>?3)
  `).bind(String(sessionId), userId, String(robloxUserId)).first();
  return existing?.permitted === 1;
}

async function* listObjects(bucket, prefix) {
  let cursor;
  do {
    const page = await bucket.list({prefix, limit: 100, ...(cursor ? {cursor} : {})});
    for (const object of page.objects) yield object;
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
}

export async function invalidateDataCaches(env) {
  if (!env.STATS_CACHE) throw new Error('Analytics cache binding unavailable');
  const stub = env.STATS_CACHE.get(env.STATS_CACHE.idFromName('global'));
  const response = await stub.fetch('https://internal/invalidate-user-data', {method: 'POST'});
  if (!response.ok) throw new Error('Analytics cache invalidation failed');
}

export async function finishAccountDeletion(env, job, {maxObjects = 25} = {}) {
  if (!env.RUNTIME_MUTATIONS) throw new Error('Account mutation coordination binding unavailable');
  if (!/^[A-Za-z0-9_-]{1,128}$/.test(job.user_id) || !Number.isInteger(maxObjects) || maxObjects < 1 || maxObjects > 25) throw new Error('Invalid deletion continuation');
  const stub = env.RUNTIME_MUTATIONS.get(env.RUNTIME_MUTATIONS.idFromName(job.user_id));
  const response = await stub.fetch('https://internal/account-deletion/finish', {
    method: 'POST', headers: {'x-deletion-user-id': job.user_id, 'x-deletion-max-objects': String(maxObjects)},
  });
  if (!response.ok) throw new Error('Coordinated account deletion failed');
  return (await response.json()).deleted === true;
}

// Only called at the front of this user's AroynRuntimeMutations queue. HTTP
// deletion and background/recovery continuations share that same queue.
export async function finishAccountDeletionInOrder(env, job, {maxObjects = 25} = {}) {
  env = withSnapshotStorage(env);
  const id = job.user_id;
  // Existing pre-cutover jobs also reach the independent ledger before their
  // durable D1 marker can disappear. Disabled deployments retain old behavior.
  await recordDeletion(env, id, Number(job.requested_at));
  await recordDeletionReceipt(env, id);
  let removed = 0;
  // The account is already marked and all credentials are revoked before R2 I/O.
  for (const prefix of [`runtime-v2/${id}/`, `runtime-v3/${id}/`]) {
    // Always restart from the beginning: completed deletes are absent. No
    // account cursor can skip a late write that raced credential revocation.
    const page = await env.PAYLOADS.list({prefix, limit: maxObjects - removed});
    for (const object of page.objects) { await env.PAYLOADS.delete(object.key); removed++; }
    if (page.truncated || removed >= maxObjects) return false;
  }
  if (job.legacy_key_hash) await env.PAYLOADS.delete(`runtime-v1/${job.legacy_key_hash}.json`);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM analytics_sessions WHERE session_id IN (SELECT session_id FROM runtime_session_owners WHERE veyra_user_id=?1)').bind(id),
    env.DB.prepare('DELETE FROM runtime_presence WHERE session_id IN (SELECT session_id FROM runtime_session_owners WHERE veyra_user_id=?1)').bind(id),
    env.DB.prepare('DELETE FROM live_presence WHERE veyra_user_id=?1').bind(id),
    env.DB.prepare('DELETE FROM owner_analytics_cache'),
  ]);
  await invalidateDataCaches(env);
  await env.DB.batch([
    // Prior analytics may have refreshed profiles while deletion was waiting.
    // Remove them only after that whole pipeline has drained. New analytics
    // cannot rediscover this account's already-removed session history.
    env.DB.prepare(`DELETE FROM roblox_profile_cache WHERE roblox_user_id IN
      (SELECT roblox_user_id FROM roblox_accounts WHERE veyra_user_id=?1)
      AND NOT EXISTS (SELECT 1 FROM roblox_accounts r WHERE r.roblox_user_id=roblox_profile_cache.roblox_user_id AND r.veyra_user_id<>?1)`).bind(id),
    env.DB.prepare('DELETE FROM users WHERE id=?1').bind(id),
    env.DB.prepare('DELETE FROM account_deletions WHERE user_id=?1').bind(id),
  ]);
  return true;
}

export async function runDataRetention(env, now = Date.now(), {deletionRequested = false} = {}) {
  if (!env.RETENTION_RUNNER) throw new Error('Retention continuation binding unavailable');
  const stub = env.RETENTION_RUNNER.get(env.RETENTION_RUNNER.idFromName('daily'));
  const response = await stub.fetch('https://internal/start', {method: 'POST', headers: {'x-retention-now': String(now), 'x-retention-deletion': String(deletionRequested)}});
  if (!response.ok) throw new Error('Retention continuation could not be scheduled');
  return response.json();
}

export async function accountExport(request, env, session, requireSession) {
  const encoder = new TextEncoder();
  const id = session.user.id;
  const record = (type, data) => encoder.encode(JSON.stringify({type, data}) + '\n');
  async function checkAccess() { if (!(await requireSession(request, env))) throw new Error('Export authorization ended'); }
  async function* records() {
    yield record('manifest', {format: 'aroyn-data-export-v1', generatedAt: new Date().toISOString(), retention: RETENTION,
      scope: 'This account and explicitly attributed sessions. Unassigned legacy/anonymous history is not exposed by matching Roblox IDs. Credentials are excluded.'});
    const u = session.user;
    yield record('account', {id, discordId: u.discord_id, username: u.discord_username, displayName: u.discord_display_name,
      avatarReference: u.discord_avatar, createdAt: u.created_at, updatedAt: u.updated_at, lastLoginAt: u.last_login_at});
    let cursor = '';
    while (true) {
      await checkAccess();
      const rows = await env.DB.prepare('SELECT * FROM roblox_accounts WHERE veyra_user_id=?1 AND roblox_user_id>?2 ORDER BY roblox_user_id LIMIT 100').bind(id, cursor).all();
      for (const row of rows.results || []) yield record('roblox-account', row);
      if (!rows.results?.length) break;
      cursor = rows.results.at(-1).roblox_user_id;
    }
    cursor = '';
    while (true) {
      await checkAccess();
      const rows = await env.DB.prepare(`SELECT a.* FROM analytics_sessions a JOIN runtime_session_owners o USING(session_id)
        WHERE o.veyra_user_id=?1 AND a.session_id>?2 ORDER BY a.session_id LIMIT 100`).bind(id, cursor).all();
      for (const row of rows.results || []) yield record('runtime-history', row);
      if (!rows.results?.length) break;
      cursor = rows.results.at(-1).session_id;
    }
    for (const prefix of [`runtime-v2/${id}/`, `runtime-v3/${id}/`]) {
      for await (const item of listObjects(env.PAYLOADS, prefix)) {
        await checkAccess();
        const object = await env.PAYLOADS.get(item.key);
        if (!object) continue;
        if (object.size > 300 * 1024) throw new Error('Unexpected export object size');
        yield record('stored-runtime', {key: item.key, uploadedAt: object.uploaded.toISOString(), value: await object.json()});
      }
    }
    yield record('complete', {complete: true});
  }
  const iterator = records();
  const body = new ReadableStream({
    async pull(controller) {
      try {
        const next = await iterator.next();
        if (next.done) controller.close(); else controller.enqueue(next.value);
      } catch { controller.error(new Error('Account export interrupted')); }
    },
    async cancel() { await iterator.return(); },
  });
  return new Response(body, {headers: {'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-store',
    'Content-Disposition': 'attachment; filename="aroyn-account-export.jsonl"', 'X-Content-Type-Options': 'nosniff'}});
}
