# Isolated recovery drill — 2026-10-01

This is a synthetic recovery exercise, not restoration of staging or real user data. General access remains restricted.

## Operator helper

`tools/recovery-sanitizer.mjs` exports `recoveryStep(environment, manifest, context, checkpoint)`. It is not imported by either deployed Worker and has no public endpoint or automatic deployment/reopening action. An operator must supply isolated D1/R2 bindings, snapshot coordination and analytics invalidation bindings, drive one step at a time, and save the returned checkpoint **only after success**. Keep the destination closed after errors; retry the previous checkpoint. Run serially, never through concurrent operator processes.

Prerequisites include closed API/live access, independent signing secrets and fresh Durable Object namespaces. The helper validates operator assertions about these prerequisites; it does not configure or independently prove them. The isolated destination must be brought to the current schema before sanitation.

The external manifest must declare format `aroyn-recovery-deletions-v1`, `complete: true`, a coverage interval spanning the backup point through the access freeze, and a deduplicated `deletions` array of `{userId, requestedAt}`. Store it outside the restored database and protect it as personal data. `complete: true` is an operator assertion, not evidence that every deletion was captured. The helper fingerprints all inputs to prevent accidentally continuing a checkpoint with different inputs.

Steps revoke every restored web session, auth exchange and dashboard key; mark/replay account deletions using existing scoped cleanup; remove **all** runtime-v1/v2/v3 objects, associations, presence and profile caches; and apply existing history retention. The conservative runtime reset also prevents restored post-backup unlinks from exposing old snapshots. A surviving profile's unexpired attributed history is retained, but its old snapshots and Roblox association must be established again. Unrelated R2 payloads and aggregate counters are preserved. Account SQL/cascades and full-table resets are offline maintenance work and are not claimed to fit the production Worker CPU budget.

The result always reports `reopenAllowed: false`. A successful sanitation is one prerequisite for a separate manual reopen decision; it is not permission to expose the database.

## Local result

Eleven groups passed against two isolated Miniflare runtimes, real local D1/R2/DO and mocked external services. A row/object copy taken before account deletion resurrected that profile and its old stored bearer session in the destination. A demonstrably unexpired old live token was rejected by the destination's new signer while the restored linkage could issue a fresh token. Missing prerequisites, incomplete coverage, duplicate deletion events and changed checkpoint inputs were rejected. A simulated R2 outage kept the deletion marker and checkpoint; retry completed. The deleted account and history disappeared; the other profile and recent attributed history remained, expired history was removed, and a fresh session exported only the surviving account's data. Completed sanitation was repeatable without reopening access.

## Cloud result

Ten checks passed using an actual D1 Time Travel bookmark restore in a new disposable database with two invented profiles. A secret-gated original Worker was removed before restoration. The replacement Worker used independently generated signing secrets and new DO namespaces. The restored database contained the deleted profile/history and accepted the old stored bearer sessions **only inside the operator-controlled fixture**. The full sanitation took 26 operator-driven steps, revoked those sessions/keys, replayed the separate fixture manifest, removed reconstructed runtime copies and preserved the other profile/recent history. A new surviving-account session exported that history with no deleted account records.

Old issued live tokens were rejected on the cloud fixture, but their short expiry was not independently ruled out as an additional reason. The local unexpired-token test is the specific signer-rotation check. No live socket was opened during this recovery drill. Cloud cache transport and rate controls were stubbed; OAuth, in-flight requests, load/cost and distributed concurrent recovery were not tested. R2 objects were reconstructed from known synthetic values separately; D1 Time Travel does not restore R2.

R2 cleanup returned zero objects. Both temporary Workers and their namespaces, D1 database and R2 bucket were deleted through the provider API. No existing staging resources, account allowlist, real profile, key or secret changed. See [cloud evidence](cloud-recovery-2026-10-01.json) and [local evidence](local-recovery-2026-10-01.json).

## Remaining real-data recovery gate

Restricted staging activated its independent real-data deletion journal on 2026-10-02. Coverage begins at that activation and does not cover earlier backups; see [journal design and cutover prerequisites](deletion-ledger.md). This drill used a complete, separately kept synthetic fixture manifest. It does not establish that a complete manifest can be reconstructed for real users. Validate uninterrupted required mode, preserved bucket identity and the complete supported coverage interval before any real-data recovery. The earlier synthetic drill is not proof of a completed recovery of actual staging data. If reliable deletion coverage is unavailable, keep the old personal-data backup offline and rebuild an empty account store. Never infer completeness merely from an empty `account_deletions` table, since completed jobs are removed.

[Cloudflare D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/) is an in-place database restore and can cancel queries. It currently does not clone/fork a database; this exercise restored only its disposable synthetic database. Use [import/export](https://developers.cloudflare.com/d1/best-practices/import-export-data/) for a separate destination where appropriate. [R2 consistency](https://developers.cloudflare.com/r2/reference/consistency/) describes object visibility, not a combined D1/R2 transaction.
