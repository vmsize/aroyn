# Bounded retention and retry

The API Cron enqueues maintenance through its RETENTION_RUNNER binding, rather than sweeping all storage in the Cron invocation. AroynRetentionRunner stores a checkpoint and alarm in its own SQLite-backed Durable Object. It handles maintenance only; telemetry retains its existing per-object coordinators.

## Work per step

- History expiry deletes at most 250 selected rows from one indexed table.
- Snapshot expiry visits one R2 page of at most 25 objects. Revocation markers are skipped. Each candidate is rechecked for ETag and upload date inside AroynSnapshotStore before removal.
- Pending account deletion handles one account and at most 25 v2/v3 objects. Completed deletes disappear from the next first-page listing. Account finalization still includes scoped SQL cleanup and foreign-key cascades; their work is not globally bounded by the 250-row history limit.
- Successful steps checkpoint their position and schedule the next alarm approximately ten seconds later. The cutoff stays fixed during a cycle.

The default daily Cron starts a cycle or leaves an active one running. Repeated starts do not reset a cursor. A deletion request arriving during a cycle asks for another cycle five minutes after completion so a newly queued job is not left waiting for the next daily Cron.

## Failure and recovery

Storage/page failure retains the earlier checkpoint and retries with persisted exponential backoff from one minute to one hour. Repeating a partially applied page is safe through idempotent deletion and the per-object coordinator. Counters can undercount after a crash between a side effect and its checkpoint; they are operational observations, not an audit ledger.

A failed account job remains revoked in D1. Its error does not block unrelated jobs or expiry. A cycle with failed jobs schedules another cycle after five minutes. If even checkpoint/alarm storage fails, the provider's alarm retry and the next Cron wake-up are additional recovery paths. Cloudflare documents at-least-once alarms and limited built-in retries. [Alarm behavior](https://developers.cloudflare.com/durable-objects/api/alarms/).

## Required deployment changes

1. Apply 0003_retention_indexes.sql after the existing two D1 migrations.
2. Preserve SNAPSHOT_STORAGE and STATS_CACHE. Add the local RETENTION_RUNNER binding to AroynRetentionRunner and the retention-runner-v1 SQLite DO migration from the API example.
3. Keep the daily Cron. The API refuses account deletion before revocation when the continuation binding is absent; runtime writes retain their existing fail-closed coordination check.

Internal /status is available only through the DO binding; there is no public maintenance API. Completed-cycle and retry logs contain counts/phase rather than account IDs or snapshot payloads. Actual application observability remains disabled in the restricted staging configuration.

R2 continuation uses its opaque cursor and truncated flag. Inserts behind the current cursor can be visited in the next cycle. Administrative R2 mutations bypass the coordinator and must not race it. An unusable cursor or persistent failure requires operator investigation; no automatic blind cursor reset is implemented. [R2 pagination](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/#r2listoptions).

## Verification and remaining limits

Thirteen local groups cover bounded pages/rows, overlapping starts, resumed checkpoints, R2 failure/backoff, replay after a partial deletion, preserved fresh data/markers, failed-job isolation, a follow-up deletion cycle, and real Miniflare alarms surviving forced eviction. The optional 100/1000-object capacity test drains bounded steps without the normal alarm delay. It is not a cloud quota or CPU measurement.

A temporary synthetic cloud fixture passed eight checks: native alarms completed 16 steps, removed 63 old snapshots and 270 history rows, and preserved a fresh row, profile, revocation marker and unrelated payload. Its clock advanced eight days and analytics-cache invalidation was stubbed. It did not test OAuth, Cloudflare CPU/quotas or the later follow-up flag; that flag passed locally. The fixture was removed. [Cloud evidence](cloud-bounded-retention-2026-10-01.json), [local evidence](local-bounded-retention-2026-10-01.json).

The API code, four retention indexes and new continuation binding were deployed to the existing restricted staging after the checks. Signing secrets, invited identities, existing namespace bindings and the daily Cron were retained. Health and unauthenticated access probes passed; real-account deletion was not repeated. The ordinary daily staging run remains unobserved.

Normal daily staging Cron observation, large account SQL/cascade work, long backlogs, provider outages and isolated backup recovery remain separate gates. These bounds reduce per-invocation work; they do not guarantee a free-plan capacity or a precise deletion deadline. [Workers limits](https://developers.cloudflare.com/workers/platform/limits/).
