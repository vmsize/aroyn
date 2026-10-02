# Reproducible checks

Use Node.js 24 and run from the repository root:

```sh
npm ci --ignore-scripts
npm test
```

The fourteen suites run sequentially and fail the process on a failed assertion (159 check groups). The complete gate passed on Windows with Node.js 24 on 2026-10-02, exit code 0. This includes the four read-only usage-report groups as part of the full run. See [local release evidence](local-release-gate-2026-10-02.json).

| Suite | Checks | Scope |
| --- | ---: | --- |
| web-check | 10 | Launch command, Clipboard refusal/success, strict health response/timeout, external URL allowlists, storage migration/reset, JavaScript parsing |
| check | 9 | Mock OAuth, key/link/snapshot round trip and runtime/dashboard relay |
| security-check | 29 | Concurrent credential changes, input bounds, revoked access, rate controls and owner/non-owner authorization |
| data-check | 9 | Scoped export/deletion/retry and retention |
| snapshot-race-check | 8 | Serialized expiry/replacement races, including twelve real Miniflare runs |
| access-check | 20 | Restricted account access, allowlist changes and initial-link ordering |
| hibernation-check | 9 | Forced local object eviction, restored socket roles/isolation, credential revocation, persisted rate counter and authorization alarm |
| retention-check | 13 | Bounded expiry, checkpoint replay/backoff, failed-job isolation, follow-up cycles and native alarms after eviction |
| recovery-check | 11 | Isolated restore, external deletion coverage, credential reset, unexpired old live token, cleanup retry and surviving history/export |
| mutation-race-check | 10 | Per-account mutation ordering, unlink retry, shared mirror, active/queued credential revocation, independent users and eight native concurrent pairs |
| deletion-ledger-check | 12 | Write-ahead failures, minimal immutable records, new-profile identity, independent restore coverage, bounded expiry and corrupt-data rejection |
| ledger-cutover-check | 6 | Transactional legacy-delete fence, receipt identity, fail-closed initialization/retry, native maintenance pause/eviction/resume and private routing |
| write-budget-check | 9 | Ownership checkpoint writes without auth caching, quota headroom/stale report rejection and persistent concurrent fixture reservations |
| usage-report-check | 4 | Account-wide aggregation including deleted databases; partial/truncated/identity/date/count rejection; fixed read-only GraphQL request and failure handling |

The Miniflare harness refuses non-mock mode and replaces external Discord/Roblox calls with synthetic responses. Each backend suite has a fresh D1/R2 store. The tests never load private credentials. Result JSON files are ignored by Git. The pinned prerelease Miniflare version uses its V4 options converter; update the harness alongside any dependency upgrade.

Local synthetic results are not evidence of real OAuth behavior, all Cloudflare topology/hibernation cases, large loads, every Roblox environment, or legal/WCAG compliance. Separate cloud/user observations and remaining gates are in [STATUS.md](../STATUS.md).

GitHub Actions is configured for Linux with the same Node/npm commands, a read-only repository token and a ten-minute timeout. A clean Windows installation passed locally. The first hosted run stopped before executing any step because of an external account restriction; remote CI remains unverified. Resolve that restriction and rerun the workflow before treating its check as a release gate.

A separate temporary real-cloud API/live deployment passed 18 lifecycle checks on seeded synthetic profiles, including logout/deletion/key rotation, idle socket revocation, account isolation and new-session/new-key reconnection. This is separate from npm test and did not test OAuth or force hibernation. See [sanitized results](cloud-split-lifecycle-2026-10-01.json). All temporary resources were removed.

The hibernation suite calls Miniflare's unsafeEvictDurableObject with webSockets=hibernate. Native ws clients use a one-second closeTimeout because the local hibernation proxy can forward the server Close frame while keeping its TCP tunnel open. Tests require the server's 1008 close code; they do not establish normal TCP close timing on Cloudflare. See [local verification notes](local-lifecycle-capacity-2026-10-01.md).

An optional larger retention check is separate from the default CI gate:

```sh
npm run test:capacity
```

It drains bounded steps without their normal ten-second alarm delay using local D1/R2/DO bindings, small synthetic snapshots and an eight-day advanced fixture clock. The 100- and 1000-object batches passed expiry, fresh-history preservation, revocation-marker preservation and a repeated empty cleanup. Wall time and operation counts are local observations; this does not measure cloud CPU, quotas, cost or supported user count. See [bounded retention](bounded-retention.md).

The recovery suite copies synthetic rows/objects between two local runtimes. A separate disposable cloud database exercised real D1 Time Travel and passed ten checks over 26 operator-driven sanitation steps. The cloud drill did not restore staging or real profiles, and a real-data deletion ledger remains a gate. See [recovery scope and limitations](recovery-drill.md).

Optional `npm run test:account-capacity` verifies scoped SQL deletion and foreign-key cascades at 1,000/10,000 local history rows plus associated ownership, web sessions and exchanges. A separate actual cloud fixture exercised 5,000 history rows and 15,000 related rows, and twelve concurrent push/unlink pairs. No cloud CPU/quota or supported user-count guarantee follows. See [runtime mutation correction and scope](runtime-mutations.md).

A separate 10-check actual-cloud journal fixture restored D1 with Time Travel while retaining the dedicated R2 deletion ledger, then derived the recovery manifest from that ledger and sanitized the closed destination. Its temporary resources were removed. The retention decision is approved; real-data activation remains deferred because the D1 free daily row-write quota blocked the closed cutover. See [deletion ledger](deletion-ledger.md).
