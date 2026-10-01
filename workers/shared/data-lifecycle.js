import {withSnapshotStorage} from './snapshot-storage.js';
const DAY = 86400000;
export const RETENTION = Object.freeze({historyDays: 30, snapshotDays: 7, webSessionDays: 30, profile: 'until-account-deletion'});

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
  `).bind(String(sessionId), userId, String(robloxUserId), now).run();
  return Number(result.meta?.changes || 0) > 0;
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

export async function finishAccountDeletion(env, job) {
  env = withSnapshotStorage(env);
  const id = job.user_id;
  // The account is already marked and all credentials are revoked before R2 I/O.
  for (const prefix of [`runtime-v2/${id}/`, `runtime-v3/${id}/`]) {
    for await (const object of listObjects(env.PAYLOADS, prefix)) await env.PAYLOADS.delete(object.key);
  }
  if (job.legacy_key_hash) await env.PAYLOADS.delete(`runtime-v1/${job.legacy_key_hash}.json`);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM analytics_sessions WHERE session_id IN (SELECT session_id FROM runtime_session_owners WHERE veyra_user_id=?1)').bind(id),
    env.DB.prepare('DELETE FROM runtime_presence WHERE session_id IN (SELECT session_id FROM runtime_session_owners WHERE veyra_user_id=?1)').bind(id),
    env.DB.prepare('DELETE FROM live_presence WHERE veyra_user_id=?1').bind(id),
    env.DB.prepare(`DELETE FROM roblox_profile_cache WHERE roblox_user_id IN
      (SELECT roblox_user_id FROM roblox_accounts WHERE veyra_user_id=?1)
      AND NOT EXISTS (SELECT 1 FROM roblox_accounts r WHERE r.roblox_user_id=roblox_profile_cache.roblox_user_id AND r.veyra_user_id<>?1)`).bind(id),
    env.DB.prepare('DELETE FROM owner_analytics_cache'),
  ]);
  await invalidateDataCaches(env);
  await env.DB.batch([
    env.DB.prepare('DELETE FROM users WHERE id=?1').bind(id),
    env.DB.prepare('DELETE FROM account_deletions WHERE user_id=?1').bind(id),
  ]);
}

export async function runDataRetention(env, now = Date.now()) {
  env = withSnapshotStorage(env);
  // A failed deletion remains revoked and retries on the next scheduled run.
  const jobs = await env.DB.prepare('SELECT * FROM account_deletions ORDER BY requested_at LIMIT 100').all();
  let pending = 0;
  for (const job of jobs.results || []) {
    try { await finishAccountDeletion(env, job); } catch { pending++; }
  }
  const cutoff = now - RETENTION.historyDays * DAY;
  await env.DB.batch([
    env.DB.prepare('DELETE FROM analytics_sessions WHERE last_seen_at < ?1').bind(cutoff),
    env.DB.prepare('DELETE FROM runtime_session_owners WHERE last_seen_at < ?1').bind(cutoff),
    env.DB.prepare('DELETE FROM runtime_presence WHERE last_seen_at < ?1').bind(now - 15 * 60000),
    env.DB.prepare('DELETE FROM live_presence WHERE last_seen_at < ?1').bind(now - 15 * 60000),
    env.DB.prepare('DELETE FROM roblox_profile_cache WHERE updated_at < ?1').bind(cutoff),
    env.DB.prepare('DELETE FROM web_sessions WHERE expires_at <= ?1').bind(now),
    env.DB.prepare('DELETE FROM auth_exchanges WHERE expires_at <= ?1').bind(now),
    env.DB.prepare('DELETE FROM owner_analytics_cache'),
  ]);
  let snapshotsRemoved = 0;
  for (const prefix of ['runtime-v1/', 'runtime-v2/', 'runtime-v3/']) {
    for await (const object of listObjects(env.PAYLOADS, prefix)) {
      // Revocation markers persist until explicit relink/account deletion.
      if (object.key.includes('/revoked/') || object.uploaded.getTime() >= now - RETENTION.snapshotDays * DAY) continue;
      if (await env.PAYLOADS.expire(object.key, object.etag, now - RETENTION.snapshotDays * DAY)) snapshotsRemoved++;
    }
  }
  await invalidateDataCaches(env);
  return {pendingDeletions: pending, snapshotsRemoved};
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
