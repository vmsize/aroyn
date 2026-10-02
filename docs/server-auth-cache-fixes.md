# Authorization and analytics invalidation corrections — 2026-10-02

## AF-01: authorization during delayed request bodies

Sensitive JSON mutation bodies are bounded and completely read before resolving the account and entering its mutation queue. A slow upload cannot hold up logout or key rotation. The queued handler checks credentials again. Logout and dashboard-key generation/rotation now share that account's runtime/deletion queue. An already accepted mutation completes before revocation is acknowledged; subsequent requests with the old credential are rejected.

The key UPDATE also requires the same unexpired web session at execution time, using SQLite's current clock. A rejected deletion request does not create a deletion-ledger event. Bodyless logout and enabled legacy disconnect remain supported.

## AF-02: deletion overlapping owner analytics

The StatsHub orders the complete owner-analytics pipeline and cache invalidation through an awaited instance-local promise queue. It does not wait for prior external I/O inside `blockConcurrencyWhile`. The pipeline includes Roblox profile refreshes, the persistent user directory, the final range-cache write and the realtime overlay. Presence and WebSocket paths do not join this analytics queue.

Account finalization removes profile-cache records after prior analytics drains and before deleting the user. Attributed session history has already been removed, so subsequent analytics cannot rediscover it. Shared profiles belonging to another Aroyn account are preserved. Roblox/ScriptBlox analytics fetches have three-second timeouts. Failed invalidation retains the deletion job for retry and does not poison the queue.

## Verification and release status

The isolated local default gate passed **22 suites** with the pinned existing dependencies. `tests/auth-revocation-check.mjs` covers seven delayed-body/session-expiry/rotation/deletion scenarios with the required ledger and D1 receipt gate. `tests/analytics-deletion-check.mjs` includes a native Miniflare Worker/DO overlap with delayed mocked Roblox I/O, successful deletion and analytics, no restored user/profile cache, fresh analytics isolation, repeated deletion continuation, a barrier at the final persistent cache write, and failed-invalidation retry.

All data is synthetic and external responses are mocked. These results do not claim a production race reproduction or a new independent full review. At this commit the cloud rollout is pending; general registration remains restricted. The remaining independent review stages, ordinary full UTC-day D1 consumption and ordinary post-activation maintenance completion remain release gates.
