# Local lifecycle and capacity checks — 2026-10-01

These checks use isolated synthetic profiles and local Miniflare 5 D1/R2/Durable Object bindings. They do not contact Discord, Roblox or Cloudflare services and do not use real account credentials.

## Forced hibernation

Nine groups passed after forcing accepted WebSockets to hibernate through Miniflare's unsafe eviction API. They exercise restored runtime/viewer roles and relay, account isolation, logout, key rotation, reconnection, the persisted 120-message rate counter, and idle socket revocation through the authorization alarm after deletion.

The local hibernation proxy can deliver the server's Close frame without promptly closing its TCP tunnel. Native ws clients therefore use closeTimeout=1000. The test still requires the server's 1008 Close frame; the timeout only bounds the subsequent client close handshake. This does not measure normal transport closure timing or prove that cloud objects entered hibernation. The separate real-cloud lifecycle fixture used native clients without this override.

Run through npm test. [Sanitized hibernation evidence](local-hibernation-2026-10-01.json).

## Retention capacity

Run npm run test:capacity separately from the normal CI gate. Each batch creates small JSON snapshots plus expired and fresh history records. The fixture clock advances eight days for snapshot expiry. Three revocation markers must survive, and an immediate second cleanup must remove zero snapshots.

| Expired snapshots and history rows | Fresh history rows preserved | Initial sweep wall time | Coordinator calls |
| ---: | ---: | ---: | ---: |
| 100 each | 10 | 5,870 ms | 100 |
| 1,000 each | 20 | 34,970 ms | 1,000 |

The fresh row count accumulates across the two batches. R2 listing and cache-invalidation counts in the JSON include the idempotence run; wall time covers the first sweep drained as 17 and 57 bounded steps without the normal alarm delay. These runs overlapped a separate local test process, so the wall times are not a controlled performance comparison. [Sanitized capacity evidence](local-retention-capacity-2026-10-01.json).

These are local measurements, not cloud CPU, cost, quota or concurrent-load measurements. They do not show that the free plan supports 1000 users. The current code processes bounded pages and saves progress between alarms; it still calls the coordinator per expired snapshot. See [bounded retention](bounded-retention.md). Before wider access, review cloud limits, backlog behavior and account-finalization SQL/cascade work. Normal daily staging Cron execution and recovery from provider-side failures remain separate checks.
