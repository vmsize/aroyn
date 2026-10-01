# Account data and retention

Implemented in the source candidate on 2026-10-01 and exercised on a separate restricted cloud staging. Existing Veyra production deployments and the running private backend were not updated. Later verification results are recorded below.

## User controls

Profile/avatar menu → **Account data** (`/dashboard/account/`). The page checks the retention endpoint before enabling its actions.

- **Download my data** exports JSON Lines containing profile fields, linked accounts, explicitly associated history and account-scoped v2/v3 R2 objects. Credentials and other users' records are excluded. The browser waits for a completion record before offering a file.
- **Delete account…** requires exactly `DELETE` and a Discord web session created within 15 minutes. Older sessions require signing in and confirming again. Cancel or Escape clears confirmation.
- Deletion first revokes all web sessions, exchange codes and dashboard-key access. Live checks reject the deletion marker. The current browser clears Aroyn local/session storage; other tabs react to session removal. Local caches on other devices cannot be remotely erased.
- Cleanup removes owned records and the profile. Later sign-in creates a new empty Aroyn account. Discord and Roblox accounts are unaffected.
- When cleanup exceeds a 25-object portion or fails, HTTP 202 means access is revoked but deletion is pending. The persistent job blocks new sign-in and wakes the continuation runner and remains eligible for daily Cron recovery. A pending job must not be described as completed deletion.

## Approved retention

| Data | Application retention |
|---|---|
| Session history/ownership | 30 days after last update |
| Runtime snapshots | 7 days after last stored update |
| Aroyn profile/linked accounts | Until account deletion or explicit unlinking |
| Linked-account revocation markers | Until explicit relinking or account deletion |
| Transient presence | 15 minutes of inactivity |
| Public Roblox profile cache | 30 days after last update |
| Web sessions | Up to 30 days, or earlier revocation |
| Aggregate samples/peaks without account IDs | Retained |

The example API cron runs daily at 03:17 UTC and enqueues a durable cycle. Alarms process bounded portions with saved progress. Expiration is cleanup on the next successful run, not an exact deletion instant. Provider logs, backups and external caches require separate production review.

## Legacy data and ownership

Migration `0002_account_data_lifecycle.sql` adds explicit Aroyn session ownership and persistent deletion jobs. Another Aroyn account or different Roblox ID cannot claim an owned session ID. This association does not prove ownership of a Roblox account.

Unassigned older history is not automatically assigned/exported/deleted merely by a matching Roblox ID; it expires under the 30-day schedule. Legacy v1 snapshots are not exported. Deletion removes the known current v1 key object; unidentified older rotated-key objects expire under the snapshot schedule. This is an account-scoped export, not a guarantee of recovering every historical occurrence of a Roblox ID.

## Deployment

Apply all four D1 migrations, including 0003_retention_indexes.sql and 0004_auth_exchange_owner.sql to the shared DB. The API `STATS_CACHE` binding must target `VeyraStatsHub` in the actual live Worker (`script_name` equals that Worker's name). Provision/deploy that live Worker and its DO migration first. Both Workers use the same D1 database/R2 bucket.

The API requires a local RETENTION_RUNNER binding to AroynRetentionRunner and its retention-runner-v1 SQLite DO migration. It also requires its own `SNAPSHOT_STORAGE` binding to `AroynSnapshotStore`, with the `snapshot-storage-v1` SQLite DO migration from the example configuration. Every runtime R2 mutation uses a coordinator determined by the full object key. Retention checks the listed ETag and current upload date inside that same coordinator before deleting. An update either happens before the check (so a replaced object is retained), or after deletion (so the fresh write remains). The queue does not store telemetry or account rows in DO storage. It uses an instance-local awaited promise chain, never a module-global lock. Missing coordination fails runtime writes closed rather than bypassing the guard. Administrative direct R2 writes bypass this mechanism and must not race cleanup.

The API also requires RUNTIME_MUTATIONS bound to AroynRuntimeMutations with the runtime-mutations-v1 SQLite DO migration. It orders push/link/disconnect/unlink for one Aroyn user and keeps different users independent. See [runtime mutation correction](runtime-mutations.md).

Deletion refuses to begin without the binding. A failed target leaves access revoked and cleanup pending. Cache invalidation waits for earlier in-flight cache computations, clears memory caches and removes persisted cache entries. Scheduled retention invalidates analytics too. Enable the API scheduled trigger and monitor failures/pending jobs.

## Verification and limits

Nine synthetic lifecycle groups passed, covering two accounts claiming the same Roblox ID, pagination beyond 100 records/objects, revocation, an R2 outage, idempotent retry, a new account after deletion and simulated expiry. The existing 29-group security suite was rerun successfully. UI checks covered profile navigation, desktop/mobile dark/light rendering, exact confirmation and Escape cancellation. On 2026-10-01 the owner's downloaded JSONL file confirmed browser saving for an empty synthetic account: valid manifest/account/completion records with the approved retention and no credential fields. It contained no history or snapshots, so populated-account browser exports still need verification.

The former R2 head/delete race is now guarded by the per-key mutation coordinator. Eight local checks passed, including a deterministic write arriving while deletion is paused and twelve real Miniflare DO/R2 expiry/replacement runs in both request orders. An isolated cloud scheduled run and scoped push/unlink/deletion races have subsequently passed; wider lifecycle and load verification remains. See [runtime mutation correction](runtime-mutations.md). The API rechecks access after writing and removes late objects, but D1/R2 operations are not one transaction. Retention now visits at most 25 snapshot objects or deletes 250 history rows per step, with saved checkpoints and alarm continuation. Account finalization includes scoped SQL/cascades whose work is not covered by the history limit. See [bounded retention](bounded-retention.md). Long backlogs and further lifecycle races remain separate gates.

References: [D1 batches](https://developers.cloudflare.com/d1/worker-api/d1-database/), [R2 Workers API](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/), [Cron triggers](https://developers.cloudflare.com/workers/configuration/cron-triggers/), [DO bindings](https://developers.cloudflare.com/durable-objects/get-started/).

## Restricted cloud staging update — 2026-10-01

A separate restricted staging was deployed without changing existing Veyra resources. The owner confirmed real sign-in, updates, stale and saved-key reconnect. A downloaded populated export passed 17 format/internal consistency checks: 9 records comprising manifest, account, one Roblox account, three runtime-history rows, two stored-runtime objects and final complete:true. Recognized credentials were absent. This confirms populated browser download and stream completion, not an independent inventory of all storage at export time. Cloud deletion, terminal WebSocket revocation and actual scheduled cleanup remain pending. Owner data is not included in this source package.

Owner deletion/re-login completed on restricted staging: targeted old-ID checks found no old profile, sessions or links; history/runtime owners were removed, R2 was empty, no deletion jobs remained, and a new profile had no key. These checks validate initial cloud data removal, not provider backups, final close of an already-open WebSocket, or actual scheduled retention execution.

A separate native runtime receiver confirmed terminal WebSocket closure after dashboard key rotation on real restricted cloud staging: close code 1008, reason Live access revoked, state CLOSED. Old-key verification and live-token issuance both returned 401. This was an idle runtime connection; other roles and revocation/message races were not covered.

The shared cleanup code subsequently passed 17 checks from a real Cron event on an isolated temporary cloud Worker with separate synthetic D1/R2 and actual per-key DO coordination. Snapshot age used an isolated +8-day test clock; cache transport was stubbed. Concurrent replacements and pending-deletion retry passed. The temporary resources were removed and the corrected API was deployed to restricted staging. Its ordinary daily invocation has not yet been observed; larger volume, other lifecycle races and provider recovery remain separate concerns.

## Prepared deletion journal

The source supports DELETION_LEDGER_MODE=required with a separate private R2 binding. It records minimal internal-profile ID/time intents before DB revocation and includes bounded 35-day expiry in maintenance. This optional feature is not activated on real staging data. Retention confirmation, amended notices and closed/drained cutover are still required. See [design and activation procedure](deletion-ledger.md). A newly created profile has a new internal ID and remains usable.
