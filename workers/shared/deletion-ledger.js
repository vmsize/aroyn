// Dedicated private R2 bucket. Never include it in a profile/payload restore.
// Deployment enables this explicitly, after closing access for cutover.
export const DELETION_LEDGER_DAYS = 35;
export const LEDGER_META_KEY = 'coverage.json';
const DAY = 86400000;
const PREFIX = 'events/';
const validId = id => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
const validClock = n => Number.isSafeInteger(n) && n > 0;

export function ledgerRequired(env) { return env.DELETION_LEDGER_MODE === 'required'; }
function checkIdentity(env, meta) {
  if (env.DELETION_LEDGER_ID && env.DELETION_LEDGER_ID !== meta.ledgerId) throw new Error('Unexpected deletion ledger');
}

export async function readLedgerMetadata(bucket, now = Date.now()) {
  if (!bucket || !validClock(now)) throw new Error('Deletion ledger unavailable');
  const object = await bucket.get(LEDGER_META_KEY);
  if (!object || object.size > 1024) throw new Error('Deletion coverage not initialized');
  const meta = await object.json();
  if (meta?.format !== 'aroyn-deletion-ledger-v1' || !validClock(meta.startedAt) || meta.startedAt > now || meta.retentionDays !== DELETION_LEDGER_DAYS || !validId(meta.ledgerId)) throw new Error('Invalid deletion coverage');
  return meta;
}

export function validateLedgerEvent(event, key, now, startedAt = 1) {
  if (!event || Object.keys(event).sort().join(',') !== 'requestedAt,userId' || !validId(event.userId) || key !== PREFIX + event.userId + '.json' || !validClock(event.requestedAt) || event.requestedAt < startedAt || event.requestedAt > now) throw new Error('Invalid deletion ledger event');
  return event;
}

export async function recordDeletion(env, userId, requestedAt = Date.now(), now = Date.now()) {
  if (!ledgerRequired(env)) return null;
  if (!validId(userId) || !validClock(requestedAt) || requestedAt > now) throw new Error('Invalid deletion request');
  const meta = await readLedgerMetadata(env.DELETION_LEDGER, now);
  checkIdentity(env, meta);
  // Pending jobs predating cutover remain in D1. Preserve their intent at the
  // beginning of this ledger's coverage, before any finalization removes them.
  const event = {userId, requestedAt: Math.max(requestedAt, meta.startedAt)};
  if (event.requestedAt < now - DELETION_LEDGER_DAYS * DAY) return {expired: true};
  const key = PREFIX + userId + '.json';
  const existing = await env.DELETION_LEDGER.get(key);
  if (existing) {
    if (existing.size > 1024) throw new Error('Invalid deletion record size');
    return validateLedgerEvent(await existing.json(), key, now, meta.startedAt);
  }
  let stored;
  try {
    stored = await env.DELETION_LEDGER.put(key, JSON.stringify(event), {
      onlyIf: {etagDoesNotMatch: '*'}, httpMetadata: {contentType: 'application/json'},
    });
  } catch {
    // R2 can reject concurrent writes to the same key. Continue only if a
    // completed winner is independently readable; otherwise fail closed.
  }
  if (stored) return event;
  // Concurrent retries never replace the first timestamp or extend retention.
  const winner = await env.DELETION_LEDGER.get(key);
  if (!winner || winner.size > 1024) throw new Error('Deletion intent not recorded');
  return validateLedgerEvent(await winner.json(), key, now, meta.startedAt);
}

export async function pruneDeletionLedger(env, {now = Date.now(), validationNow = now, cursor = null, limit = 25} = {}) {
  if (!ledgerRequired(env)) return {done: true, cursor: null, removed: 0, visited: 0};
  // `now` fixes expiry for the whole sweep; validation must also accept valid
  // deletions recorded while that sweep was running. Future/corrupt events
  // still fail closed against the current validation clock.
  if (!validClock(now) || !validClock(validationNow) || validationNow < now) throw new Error('Invalid ledger cleanup clock');
  const meta = await readLedgerMetadata(env.DELETION_LEDGER, validationNow);
  checkIdentity(env, meta);
  if (!Number.isInteger(limit) || limit < 1 || limit > 25) throw new Error('Invalid ledger page limit');
  const page = await env.DELETION_LEDGER.list({prefix: PREFIX, limit, ...(cursor ? {cursor} : {})});
  let removed = 0;
  for (const item of page.objects) {
    const object = await env.DELETION_LEDGER.get(item.key);
    if (!object) continue; // Another bounded sweep already removed it.
    if (object.size > 1024) throw new Error('Invalid deletion record size');
    const payload = await object.json();
    // Listing/reading may await a concurrently recorded deletion. Sample the
    // validation clock after the read without moving the sweep's expiry cutoff.
    const event = validateLedgerEvent(payload, item.key, Math.max(validationNow, Date.now()), meta.startedAt);
    if (event.requestedAt < now - DELETION_LEDGER_DAYS * DAY) {
      // Records are immutable through this application. Direct admin writes
      // must not race pruning; R2 delete has no ETag precondition.
      await env.DELETION_LEDGER.delete(item.key); removed++;
    }
  }
  if (page.truncated && (!page.cursor || page.cursor === cursor)) throw new Error('Deletion ledger listing did not advance');
  return {done: !page.truncated, cursor: page.truncated ? page.cursor : null, removed, visited: page.objects.length};
}

export async function recordDeletionReceipt(env, userId) {
  if (!ledgerRequired(env)) return;
  const meta = await readLedgerMetadata(env.DELETION_LEDGER);
  checkIdentity(env, meta);
  const gate = await env.DB.prepare('SELECT ledger_id FROM deletion_ledger_gate WHERE singleton=1').first();
  if (gate && gate.ledger_id !== meta.ledgerId) throw new Error('Deletion ledger fence mismatch');
  await env.DB.prepare(`INSERT INTO account_deletion_receipts(user_id,ledger_id)
    SELECT id, ?2 FROM users WHERE id=?1 AND EXISTS(SELECT 1 FROM account_deletions WHERE user_id=?1)
    ON CONFLICT(user_id) DO UPDATE SET ledger_id=excluded.ledger_id`).bind(userId, meta.ledgerId).run();
}
