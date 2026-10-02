# Reproducible checks

Use Node.js 24 and run from the repository root:

```sh
npm ci --ignore-scripts
npm test
```

The fifteen suites run sequentially and fail the process on a failed assertion (174 check groups). The current complete gate passed locally on Windows with Node.js 24 on 2026-10-02, exit code 0, including the P1 regression suite. See [current evidence](local-p1-gate-2026-10-02.json). Previous hosted CI results below refer to earlier source versions; current changes have not been published/deployed.

| Suite | Checks | Scope |
| --- | ---: | --- |
| web-check | 11 | Launch command, Clipboard refusal/success, strict health response/timeout, external URL allowlists, storage migration/reset, safe runtime status HTML, JavaScript parsing |
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

| p1-regression-check | 14 | Concurrent ledger records, recovery after failed validation, delayed API/live writes versus full deletion, queued reauthentication, maintenance wake ordering, retry and native coordinator |

The Miniflare harness refuses non-mock mode and replaces external Discord/Roblox calls with synthetic responses. Each backend suite has a fresh D1/R2 store. The tests never load private credentials. Result JSON files are ignored by Git. The pinned prerelease Miniflare version uses its V4 options converter; update the harness alongside any dependency upgrade.

Local synthetic results are not evidence of real OAuth behavior, all Cloudflare topology/hibernation cases, large loads, every Roblox environment, or legal/WCAG compliance. Separate cloud/user observations and remaining gates are in [STATUS.md](../STATUS.md).

GitHub Actions is configured for Linux with the same Node/npm commands, a read-only repository token and a ten-minute timeout. A clean Windows installation passed locally. After two attempts stopped before test execution because of an external account restriction, attempt 3 passed all fourteen suites / 159 groups on Ubuntu 24.04.5 with Node.js 24.21.0 on 2026-10-02. The tested commit is 9bed86447ce600b1b3d79c8b891f80f0bb7d748f; all job steps succeeded. See [hosted evidence](hosted-ci-2026-10-02.json). These are synthetic Miniflare checks, not new production cloud storage or Roblox farming checks.

A separate temporary real-cloud API/live deployment passed 18 lifecycle checks on seeded synthetic profiles, including logout/deletion/key rotation, idle socket revocation, account isolation and new-session/new-key reconnection. This is separate from npm test and did not test OAuth or force hibernation. See [sanitized results](cloud-split-lifecycle-2026-10-01.json). All temporary resources were removed.

The hibernation suite calls Miniflare's unsafeEvictDurableObject with webSockets=hibernate. Native ws clients use a one-second closeTimeout because the local hibernation proxy can forward the server Close frame while keeping its TCP tunnel open. Tests require the server's 1008 close code; they do not establish normal TCP close timing on Cloudflare. See [local verification notes](local-lifecycle-capacity-2026-10-01.md).

An optional larger retention check is separate from the default CI gate:

```sh
npm run test:capacity
```

It drains bounded steps without their normal ten-second alarm delay using local D1/R2/DO bindings, small synthetic snapshots and an eight-day advanced fixture clock. The 100- and 1000-object batches passed expiry, fresh-history preservation, revocation-marker preservation and a repeated empty cleanup. Wall time and operation counts are local observations; this does not measure cloud CPU, quotas, cost or supported user count. See [bounded retention](bounded-retention.md).

The recovery suite copies synthetic rows/objects between two local runtimes. A separate disposable cloud database exercised real D1 Time Travel and passed ten checks over 26 operator-driven sanitation steps. The cloud drill did not restore staging or real profiles, and does not establish recovery of actual profiles. The restricted-staging journal was subsequently activated on 2026-10-02; its supported coverage starts at activation. See [recovery scope and limitations](recovery-drill.md).

Optional `npm run test:account-capacity` verifies scoped SQL deletion and foreign-key cascades at 1,000/10,000 local history rows plus associated ownership, web sessions and exchanges. A separate actual cloud fixture exercised 5,000 history rows and 15,000 related rows, and twelve concurrent push/unlink pairs. No cloud CPU/quota or supported user-count guarantee follows. See [runtime mutation correction and scope](runtime-mutations.md).

A separate 10-check actual-cloud journal fixture restored D1 with Time Travel while retaining the dedicated R2 deletion ledger, then derived the recovery manifest from that ledger and sanitized the closed destination. Its temporary resources were removed. The first real-data cutover attempt was deferred by the D1 quota; restricted staging subsequently activated the journal on 2026-10-02. Ordinary post-activation daily cleanup completion and full-day normal usage are still unverified. See [deletion ledger](deletion-ledger.md).

## P1 staging verification — 2026-10-02

Public source dff3e8f passed hosted CI: 15 suites / 174 groups. The corrected API/live/frontend are on restricted staging, and the owner confirmed telemetry updates. The original journal and resource identities were preserved; maintenance is resumed with a saved completed cycle, no failures or pending deletions. The next ordinary daily cycle and full-day consumption are still unobserved. See [current evidence](hosted-p1-ci-2026-10-02.json).

## Dashboard stability regression gate — 2026-10-02

The default gate now includes dashboard-stability-check: 16 suites / 189 groups pass locally. Fifteen new checks exercise actual runtime source with controlled timers and delayed fetch/body, logout and recovery; page lifetime is tested with actual Modules-page mounts. Browser behavior requires an owner follow-up. See [scope](dashboard-stability.md).

The dashboard stability source commit 16cc7c1eee7b65427746c2ab4f21129b2a0d6190 also passed hosted GitHub Actions: 16 suites / 189 groups. Its corrected frontend is on restricted staging; browser follow-up is still pending. See [rollout evidence](dashboard-stability-rollout-2026-10-02.json).
