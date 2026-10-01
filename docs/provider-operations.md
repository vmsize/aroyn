# Hosting, recovery and capacity

Reviewed against provider documentation on 2026-10-01. This records operational limits, not independent certification or a legal assessment.

## Data after application deletion

D1 Time Travel is always enabled for production-storage databases. Its documented recovery window is seven days on Workers Free and thirty days on Workers Paid. A completed application deletion does not erase those earlier database states immediately. The account's exact plan and provider-internal retention were not independently established here. [D1 Time Travel](https://developers.cloudflare.com/d1/reference/time-travel/)

The test configuration disables application Workers observability and Logpush; public R2 access was previously checked as disabled. This does not establish the absence of Cloudflare's own infrastructure/security records. If Workers Logs is later enabled, its documented retention is three days on Free and seven on Paid. [Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/)

R2 binding reads reflect completed object deletion immediately. This is an application-read guarantee, not a promise of physical erasure of all provider copies. No public object-cache purge is needed for the current private binding path. [R2 consistency](https://developers.cloudflare.com/r2/reference/consistency/)

## Recovery procedure before reopening a service

Restoring an earlier database could restore deleted profiles and old credential hashes. Restoring the database alone is therefore insufficient.

1. Close account/runtime access on both Workers before restoration. Keep a separately isolated recovery environment; do not restore directly into a running public service.
2. Determine all deletion requests and credential revocations after the restore point. Reapply them before exposing any restored data. The current application does not provide a separate backup-independent deletion ledger.
3. Invalidate restored web sessions and dashboard keys and rotate signing secrets before reopening access. Clear/rebuild live and analytics caches. Reauthentication must not grant access to a previously deleted profile.
4. If post-backup deletions cannot be reconstructed reliably, do not return the old personal-data snapshot to service. Recreate an empty account store rather than revive unknown deleted records.
5. Verify two-account isolation, export/deletion, token rejection and open-socket revocation in the recovery environment. Only then decide whether to reopen it.

The initial provider review performed no restore. A subsequent [isolated recovery drill](recovery-drill.md) exercised actual D1 Time Travel, fresh signing secrets/namespaces and deletion replay on invented profiles only. Existing staging and real user data were not restored. A backup-independent production deletion ledger is still absent; recovery with historical real data remains an explicit gate.

## Capacity and cost gates

The existing Pages/Workers addresses do not require a purchased domain. Hosting limits still apply. Workers Free currently allows 100,000 requests/day and 10 ms CPU per invocation, including Cron invocations. Network waiting is separate from CPU time. Retention now runs bounded alarm steps with durable progress. Local 100/1000-object sweeps and an isolated cloud 63-object native-alarm sweep passed; they do not measure cloud CPU, quotas or large-account SQL/cascade cost. See [bounded retention](bounded-retention.md). [Workers limits](https://developers.cloudflare.com/workers/platform/limits/)

Measure API/live HTTP requests, Durable Object activity, D1 reads/writes, R2 operations and retention sweep work separately. A successful health response does not show remaining quota. Rate limits are burst controls, not global spending caps. [Durable Object pricing](https://developers.cloudflare.com/durable-objects/platform/pricing/)

Before expanding beyond the restricted test, use isolated synthetic data to measure concurrent users and a larger expiry backlog, review continuation backlog and account-finalization SQL/cascade work, and review actual aggregate usage in the provider account. Do not enable a paid plan or promise unlimited availability on the basis of the two-user test. Operator/contact and teenage-audience requirements still need review for the intended audience and jurisdiction.
