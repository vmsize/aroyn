# Independent deletion ledger — prepared, not activated

The source candidate contains an optional write-ahead deletion ledger. Restricted staging still runs the previous deployment and has no real-data ledger coverage. The proposed additional 35-day retention has been explained to the owner; explicit confirmation and a closed cutover remain prerequisites. Historical real-data restore remains prohibited without trustworthy independent coverage.

## Data and registration

One immutable JSON event contains only `{userId, requestedAt}`: the internal Aroyn profile ID and deletion-intent time. No Discord/Roblox ID, name, avatar, key, session token or telemetry is included. The object key repeats the internal ID. Provider object metadata has upload time/ETag; a separate coverage marker contains the ledger's random identity, activation time and retention setting.

A subsequent Discord sign-in creates a new empty profile with a different internal ID. The journal is not a registration blocklist. It prevents an older deleted profile from returning when an old database is restored.

The event resides in a **dedicated private R2 bucket**, outside both D1 and the runtime payload bucket. Never restore, overwrite or clear that bucket with account backups. This is independence from profile restoration, not independence from the hosting account or protection against a malicious administrator. The API's binding can read/write/delete the bucket; restrict administrative access and do not grant public R2 access.

## Write ordering and expiry

`DELETION_LEDGER_MODE=required` enables the feature. Disabled or absent mode preserves the existing deployment behavior. With required mode, missing/malformed coverage or an unsuccessful event write returns HTTP 503 before D1 credentials/profile changes. The request requires the existing authenticated recent web session and exact DELETE confirmation.

The API records intent before its D1 revocation batch. A storage/DB failure after intent is recorded may leave the profile temporarily usable, but a later recovery conservatively honors the already requested deletion; HTTP failure is not proof that nothing was recorded. Retry rather than reporting completion. D1 deletion jobs continue to drive actual removal, including multi-step cleanup. Existing jobs record their intent before finalization removes the job. Pre-cutover pending intents use the coverage start as their conservative replay time; their earlier D1 marker remains part of the restored-state sanitizer.

Conditional R2 create plus validation/read of a completed winner prevents concurrent retries replacing the first timestamp. If the winner is not readable yet, the operation fails closed and can be retried. It does not assume all concurrent requests succeed. No combined R2/D1 transaction exists.

Events expire after 35 days. Daily maintenance visits at most 25 events per persisted step, checks the immutable event timestamp and removes expired events. Removal occurs during successful maintenance, not at an exact deadline. A delayed already-revoked job older than the supported restore window does not recreate an expired event. R2 failures retain the checkpoint and use the existing durable backoff. Direct administrator writes must not race pruning: R2 delete has no ETag condition. The non-personal coverage marker remains to prevent an empty journal being mistaken for a new complete history.

## Controlled activation

1. Obtain the retention decision and update RU/EN privacy notices before collecting real deletion events. Suggested text appears below.
2. Provision a new dedicated private bucket and bind it as DELETION_LEDGER. Do not bind the runtime payload bucket. Preserve the current resource IDs, secrets, access list and Cron.
3. Close both API/live user access, stop maintenance and drain older deletion writers. Verify closure; a Boolean passed to the helper does not independently prove it. Do not initialize coverage while an older Worker can still complete an unrecorded deletion.
4. Deploy required mode while access remains closed. Required mode rejects deletion until coverage is initialized. Operator-only `initializeDeletionLedger(bucket, {accessClosed:true, oldWritersDrained:true})` creates coverage once in an empty bucket; record its ID and provider-clock activation time outside profile backups. There is no initialization route in the public API.
5. Exercise a disposable account through the same deployment configuration, verify its completed deletion has a minimal event and no credentials, verify pending jobs and maintenance continuation, then separately decide to reopen the existing restricted access list. New historical coverage begins at this cutover, never retroactively.

## Recovery from the preserved bucket

Use `tools/deletion-ledger-recovery.mjs` offline with original private bucket bindings. Close/drain API/live access and pause ledger cleanup before reading. Supply the recorded expected ledger ID and a trustworthy provider-clock backup point/access-freeze time. The cloud fixture revealed local PC time approximately 2 seconds behind provider time; a copy wrongly dated before activation was correctly rejected. Do not backdate coverage to bypass this check.

`deletionManifestFromLedger` reads 25-object pages, validates all event shapes/key IDs/timestamps, rejects missing reads/non-advancing cursors/identity changes and constructs the manifest accepted by the existing sanitizer. Coverage starts at the later of activation or capture time minus 35 days. Backups earlier than that are rejected, including when no events remain. Feed the manifest to `recoveryStep` on a closed isolated destination with current migrations, fresh DO namespaces and rotated signing secrets. Save checkpoints only after success and never automatically reopen.

The export cannot detect an administrator silently deleting a valid event or forging coverage. Its completeness depends on the closed cutover, uninterrupted required mode, correct original bucket, reliable timestamps and restricted administrative writes. If any interval is uncertain, rebuild an empty profile store instead of reopening restored personal data. Retire temporary personal manifests when recovery is complete; do not publish them or include them in generic diagnostic archives.

## Prepared privacy wording, pending activation

EN: “To prevent a deleted profile returning from an older backup, we keep its internal Aroyn ID and deletion-request time in a separate private journal for 35 days. It contains no username, Discord ID or dashboard key. It does not prevent you signing in again to create a new empty profile. Expired entries are removed during the next successful cleanup.”

RU: «Чтобы удалённый профиль не вернулся из старой резервной копии, мы сохраняем его внутренний ID Aroyn и время запроса удаления в отдельном закрытом журнале на 35 дней. В нём нет имени пользователя, Discord ID или ключа панели. Можно снова войти и создать новый пустой профиль. Просроченные записи удаляются при следующей успешной очистке.»

This prepared wording is not yet the staging privacy notice or an assertion of legal compliance.

## Evidence and limits

Twelve local groups passed with isolated Miniflare D1/R2/DO, including unavailable-ledger fail-closed behavior, completed HTTP deletion, concurrent first/repeated writes, new profile with the same synthetic Discord identity, pre-cutover pending intent, original-ledger recovery, 63-record bounded expiry, corrupt data and persisted maintenance phase. The complete default gate passed 11 suites / 140 groups; the ledger suite was rerun after conditional-write and timestamp-bound hardening.

Ten actual cloud checks passed on a disposable D1 database and two separate private R2 buckets. Real D1 Time Travel resurrected an invented deleted profile and bearer session, while the independent R2 ledger retained both fixture events. A replacement Worker with fresh namespaces/secrets read the original journal, replayed sanitation in 29 steps and preserved the other profile's recent history. Both old access and deleted records were removed. Fixture-clock +36-day expiry removed events while keeping coverage. All temporary Workers/namespaces, database and buckets were removed.

The first cloud attempt assumed all simultaneous writes succeeded; the wrapper reported transient rejections. Their exact provider error was not exposed by the wrapper. The implementation now accepts only a separately readable completed winner or fails closed. A later attempt correctly refused a PC-clock coverage interval; the successful run used provider clocks. The final start-bound timestamp check was additionally verified locally after the cloud run. OAuth, native live sockets, provider automatic lifecycle, multi-region outages, tampering, CPU/cost/quota limits and real staging cutover were not tested by this fixture.

See [local evidence](local-deletion-ledger-2026-10-01.json) and [cloud evidence](cloud-deletion-ledger-2026-10-01.json). R2 API behavior was checked against the [Workers API reference](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/) and [consistency documentation](https://developers.cloudflare.com/r2/reference/consistency/); object consistency is not a cross-store transaction.
