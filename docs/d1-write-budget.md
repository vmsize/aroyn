# D1 daily write budget

## Observed incident, 2026-10-01

Read-only Cloudflare GraphQL analytics reported 118,919 rows written across the account for the UTC day. The disposable mutation/cascade fixture contributed 105,242 (about 88.5%); restricted Aroyn staging contributed 3,027. The older Veyra database contributed 8,021 and other disposable checks the remainder. The large fixture was already removed, but removing a database does not undo its day's operations.

The provider rejected the deletion-journal gate insert with a Free daily row-write quota error. The journal was left disabled and uninitialized; restricted access and maintenance were restored. This incident primarily reflects the synthetic cloud test, not a measurement showing that normal Aroyn traffic alone exhausted the quota. The real-data journal cutover still needs completion after reset.

Workers Free includes 100,000 D1 rows written per day. INSERT, UPDATE, DELETE and affected index rows contribute; this is not a count of stored profiles or HTTP requests. Free daily limits reset at 00:00 UTC. [D1 pricing and counting rules](https://developers.cloudflare.com/d1/platform/pricing/)

## Cloud verification controls

Large row/cascade/backlog capacity checks run through the local Miniflare suites. Never replay the previous 5,000/15,000-row cloud mutation fixture. Its bulk cloud seed route is disabled; its replacement uses ten synthetic history rows and thirty related rows. Fourteen archived cloud fixture entrypoints are blocked pending adaptation to the budget preflight. Those private harness changes are operator workspace changes, not public deployment routes.

`tools/cloud-test-budget.mjs` provides the required operator preflight for new disposable cloud checks:

- Account-wide metrics must include deleted databases, be complete, match the UTC day and be no more than five minutes old.
- Maximum conservative estimate: 1,000 written rows per run, including setup, indexes, retries, cascades and cleanup.
- Keep at least 30,000 rows of account headroom. A forecast exceeding 70,000 total blocks cloud writes.
- A shared per-account reservation file allows at most 2,000 reserved fixture rows per UTC day. Reservations remain charged if a test fails. The exclusive file lock prevents concurrent local callers from using the same allowance.
- Missing, malformed, stale or exhausted metrics block preparation and test requests before they contact a cloud fixture. Cleanup after an already started run remains necessary and must be included in its estimate.

The mutation harness reserves 250 setup rows and 750 execution/cleanup rows. Other archived probes must be resized and reviewed before enabling them. Generate metrics through the read-only GraphQL `d1AnalyticsAdaptiveGroups` query over the entire account/day, without filtering to only the surviving staging database. Store the resulting operator report and reservations outside public source. The expected report shape is:

```js
{
  format: 'aroyn-d1-budget-v1',
  complete: true,
  accountId: /* actual account ID */,
  date: /* UTC YYYY-MM-DD */,
  collectedAt: /* capture time in milliseconds */,
  rowsWritten: /* sum for ALL returned database groups */
}
```

Pass absolute paths as `AROYN_D1_BUDGET_METRICS` and `AROYN_CLOUD_TEST_RESERVATIONS`. Do not fabricate a low usage count or change the date to bypass the check. Validate that the account matches the fixture deployment. An operator-controlled report is not an independent provider attestation. [D1 analytics](https://developers.cloudflare.com/d1/observability/metrics-analytics/)

## Runtime reduction

`claimRuntimeSession` previously updated the ownership timestamp on every HTTP telemetry snapshot. It now creates ownership immediately and updates its retention checkpoint at most once per minute for the same session. A skipped write still checks the current profile, pending deletion, account/Roblox identity and conflicting presence/history rows. No cached authorization or client-side promise replaces these checks. Clock regression does not move the checkpoint backwards.

Per-account mutation ordering, final credential checks, snapshot storage, live relay and key/logout/deletion revocation are retained. The panel's incoming snapshot cadence is unchanged. Ownership retention time is now a coarse checkpoint with up to one minute of lag; it is not the source of the panel's stale status.

Nine local groups verify D1 write reduction, due checkpoints, ownership/revocation/collision checks, competing first claims, exhausted/stale budget reports and concurrent persistent reservations. Sixty synthetic one-second claims produced only the initial ownership insert (four local D1 written rows including indexes), followed by one due checkpoint at sixty seconds. This measures that SQL path only, not total application writes, a cloud saving percentage or supported user count.

## Limits and next measurement

This fixes the observed bulk-test cause and reduces the largest staging write query. It is not a global provider spending cap: telemetry, account deletion, other projects and direct administrators share account quota; analytics can lag, estimates can be wrong, and bursts can arrive after preflight. Do not claim that any number of users can run indefinitely on the free tier. Before broader service access, measure a full UTC day's reads/writes, errors, session churn and cleanup, and add service admission/backpressure if normal traffic approaches the reserved headroom. HTTP health alone does not establish storage availability. Do not change billing or create another database/account to bypass quota.
