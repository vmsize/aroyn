import {DELETION_LEDGER_DAYS, LEDGER_META_KEY, readLedgerMetadata, validateLedgerEvent} from '../workers/shared/deletion-ledger.js';
import {validateRecovery} from './recovery-sanitizer.mjs';

// Operator-only; never expose either operation through a public HTTP route.
// Initialization is permitted only with all deletion writers stopped/drained.
export async function initializeDeletionLedger(bucket, {accessClosed, oldWritersDrained, startedAt = Date.now(), ledgerId = crypto.randomUUID()}) {
  if (accessClosed !== true || oldWritersDrained !== true) throw new Error('Closed, drained cutover required');
  if (!Number.isSafeInteger(startedAt) || startedAt <= 0 || startedAt > Date.now() || typeof ledgerId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(ledgerId)) throw new Error('Invalid deletion coverage initialization');
  if ((await bucket.list({limit: 1})).objects.length) throw new Error('Ledger bucket must be new and empty');
  const meta = {format: 'aroyn-deletion-ledger-v1', startedAt, ledgerId, retentionDays: DELETION_LEDGER_DAYS};
  if (!await bucket.put(LEDGER_META_KEY, JSON.stringify(meta), {onlyIf: {etagDoesNotMatch: '*'}})) throw new Error('Ledger already initialized');
  await readLedgerMetadata(bucket, startedAt);
  return meta;
}

// Read the original, independently preserved bucket after freezing API/live
// access and pausing ledger cleanup. This is not a backup of that bucket.
// IDs returned here are sensitive; keep manifests outside published source.
export async function deletionManifestFromLedger(bucket, context, {ledgerCleanupPaused, expectedLedgerId, now = Date.now()} = {}) {
  if (ledgerCleanupPaused !== true || !expectedLedgerId) throw new Error('Paused ledger cleanup and expected identity required');
  const meta = await readLedgerMetadata(bucket, now);
  if (meta.ledgerId !== expectedLedgerId) throw new Error('Unexpected deletion ledger');
  const coverageFrom = Math.max(meta.startedAt, now - DELETION_LEDGER_DAYS * 86400000);
  const manifest = {format: 'aroyn-recovery-deletions-v1', complete: true, coverageFrom, coverageThrough: context.frozenAt, deletions: []};
  // Validate access prerequisites/time range before exporting any records.
  validateRecovery(manifest, context);
  if (context.frozenAt > now) throw new Error('Access freeze cannot be in the future');
  let cursor;
  do {
    const page = await bucket.list({prefix: 'events/', limit: 25, ...(cursor ? {cursor} : {})});
    for (const item of page.objects) {
      const object = await bucket.get(item.key);
      if (!object || object.size > 1024) throw new Error('Incomplete deletion ledger read');
      const event = validateLedgerEvent(await object.json(), item.key, now, meta.startedAt);
      if (event.requestedAt > context.frozenAt) throw new Error('Deletion writer was not drained before access freeze');
      if (event.requestedAt >= coverageFrom) manifest.deletions.push(event);
    }
    if (page.truncated && (!page.cursor || page.cursor === cursor)) throw new Error('Deletion ledger listing did not advance');
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor);
  const after = await readLedgerMetadata(bucket, now);
  if (JSON.stringify(after) !== JSON.stringify(meta)) throw new Error('Deletion coverage changed during export');
  manifest.deletions.sort((a, b) => a.userId.localeCompare(b.userId));
  validateRecovery(manifest, context);
  return manifest;
}
