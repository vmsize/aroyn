## Custom domain and compact Pets — 4.3.94

Website and client links use aroyn.xyz. Existing API/live services, Discord callback, database and resource identifiers remain the same; only allowed web origins and the post-login destination change. Login once with the existing Discord identity on the new browser origin. Pets settings use compact cards and count-sized scrolling lists with hunger bars. Physical phone scrolling was confirmed for 4.3.93; the new visual layout awaits confirmation.

## Mobile touch scrolling — 4.3.93

Closed popup overlays are hidden. In compact mode MobilePages owns the Pets page scroll; the redundant full-height inner scroller is disabled and restored on desktop. Native scrolling of nested content lists stays enabled. Physical phone scrolling was confirmed by the user.

# Source package status â€” 2026-10-03

## Direct feeding collection — 4.3.92

Auto Feed uses the same direct FruitSpawn prompt invocation as Auto Collect All Fruits, without character movement or prompt property edits. The corrected Pets switch is included.

## Toggle appearance — 4.3.91

Pets uses a centered normal-sized switch within a larger touch target. Toggle positions use local dimensions at desktop UI scales. Feeding logic is unchanged.

## Mobile UI and pet feeding — 4.3.90

The client adds a responsive single-column layout and a Pets tab with Auto Feed, hunger thresholds and an optional fruit value cap. Feeding defaults off, protects favorites/locked/waxed fruit and requires server acceptance, inventory consumption and hunger growth before counting success. Twenty-nine focused behavioral scenarios and complete chunk compilation passed. Controlled real-game feeding and emulated viewport checks passed; physical phone testing remains. Stable loader and backend are unchanged. See [scope and verification](docs/mobile-pet-feeding.md).

## Complete executor legend

Owner analytics returns all executor groups for the selected period instead of the ten most frequent. The identified-executor legend scrolls, preserving position and keyboard focus across refresh. Cache version 4 refreshes former truncated results. Client 4.3.89, retention and authorization remain unchanged.

## Identified executors chart

The owner executor donut now excludes Unknown and missing names. Counts and percentages use only displayed identified executors, with an empty state when none are available. Backend history and client 4.3.89 are unchanged.

## Browser tab icon

Owner analytics now uses the existing Aroyn brand PNG for its tab and touch icon, replacing references to absent favicon files. Other site pages already use the same brand asset.

## Owner executor chart

The executor panel now includes a donut, color legend, launch counts and percentages for the selected range. The top-ten tail appears as Other executors, preserving the all-launch denominator. Desktop and mobile layout, empty/unknown data and label escaping were verified with synthetic data. Client 4.3.89 and backend are unchanged by this UI update.

## Executor diagnostics — 4.3.89 published

Optional client-reported executor name/version is shown in private owner analytics, including unlinked sessions over WebSocket/HTTPS. Unknown is explicit, values are bounded and escaped, and authentication is unchanged. Additive migration 0006 is applied and the live Worker is deployed. Thirty-five local suites and code CI passed; 14 published assets and API/live/Render health were verified. A real executor launch remains to be observed. Existing session history is preserved. See docs/executor-metadata.md.

## Latest client transport — 4.3.88

WebSocket presence is published with automatic HTTPS fallback. Linked runtimes reuse acknowledged telemetry; basic unlinked presence uses a per-session hibernatable socket. Signed session validation and detailed-telemetry authorization remain in place. No schema, binding or credential migration is needed. See [transport and verification](docs/presence-websocket.md). Thirty-four local suites and code CI passed; published assets, server upgrade and bot health are verified. Real executor execution remains to be observed. See the rollout evidence.

## Public beta opened — 2026-10-03

The owner explicitly approved opening general registration. STAGING_ACCESS was
removed from both existing API/live services; every other binding and existing
Durable Object namespace identity was preserved. Deletion ledger remains required,
the daily cleanup Cron is unchanged, and the allowlist secret is retained for
rollback. Client 4.3.86 and the stable loader are unchanged. The public site serves
beta notices, and the old Veyra site now serves a migration page on its home,
dashboard and owner routes. Twenty-five published asset, service, OAuth and
unauthenticated-private-endpoint checks passed. A first real Discord sign-in
outside the previous allowlist awaits owner confirmation; public-load quota
observations are separate from the completed restricted-load gate.

The owner will publish/update ScriptBlox after launch. The legacy loader/API/live
service remain unchanged until that listing is ready. See
[rollout and limits](docs/public-beta-launch.md). Older restricted/pending statements
below are historical; the owner has confirmed telemetry, account switching and
Auto Compost cancellation for 4.3.86.

## Current release: 4.3.86 paced telemetry

4.3.85 did not solve the owner's real executor disconnect. Single ~40 KB
messages worked; the synchronous six-fragment burst did not. Yielding 150 ms
between the same full-inventory frames restored acknowledgments and delivery.
4.3.86 adds pacing, cancellation checks and bounded frame cadence; no Worker or
persistence interval changed. The versionless loader and older immutable
releases remain unchanged. Thirty local suites and hosted CI passed; restricted
Pages assets matched the published source.

The published loader was exercised in the actual executor in verification mode
(farming disabled; saved settings not written). See the measured duration,
acknowledgments and reconnect counts in [rollout](docs/telemetry-pacing-rollout-2026-10-03.json)
and [scope](docs/telemetry-pacing.md). Owner visual confirmation of counters and
account switching remains. Earlier pending claims are historical. General
registration is restricted.


## Current release: 4.3.85 telemetry recovery

Published to restricted staging after 30 verified local suites and hosted CI.
Large inventory snapshots are preserved as bounded frames and assembled before
dashboard application. Delayed HTTP replies cannot overwrite fresh telemetry;
stalled open sockets reconnect automatically. Native relay/hibernation tests
preserve coarse ownership/presence checkpoints. Workers and persistence
intervals were not changed. See [telemetry scope](docs/telemetry-recovery.md) and
[rollout](docs/telemetry-rollout-2026-10-03.json).

The owner confirmed 4.3.84 cross-tab logout. Compost's script-driven count grows;
the remaining report was telemetry delivery with a large inventory. An authorized
20-second compact-send trial received relay acknowledgments and restored the
original function. Full 4.3.85 executor/website smoke remains pending. Earlier
release headings below are historical. General registration is still restricted.

## Current published correction: independent recheck findings

IR-01/IR-02 (P2) and IR-03 (P3) are corrected and published on restricted staging. Client 4.3.84 prevents cancelled prompt-error continuations from beginning a new Compost fallback, while accepted holds/key presses still receive cleanup. Cross-tab session changes invalidate late auth work, including tokenless exchange; hidden account panels discard revealed keys on guest or identity/session changes. The isolated gate passed 28 suites and 57 new focused scenarios; the final manifest notice passed an additional loader/update check. Earlier immutable clients and the versionless loader remain unchanged. See [scope and owner checks](docs/independent-recheck-fixes.md) and [local evidence](docs/local-independent-recheck-fixes-2026-10-03.json). Code `3b58d21ffadd4c070737a545babfd256b2861a89` passed hosted CI (28 suites); Pages `a56c1b90-03ea-4075-8458-372a1b8081d2` passed ten asset/header checks and five service/login/guest probes. See [rollout](docs/independent-recheck-rollout-2026-10-03.json). Owner two-tab and game smoke checks remain pending for 4.3.84. General registration remains restricted.

The ordinary post-ledger scheduled cleanup completed with 14 steps, zero failures and zero pending deletions; the full 2026-10-02 UTC day used 7,749 written / 117,635 read rows account-wide (209 / 31,208 for staging). These two gates passed for the observed restricted test load; public-scale capacity and fresh-ledger 35-day expiry are not established by this observation. See [operational evidence](docs/operational-gates-2026-10-03.json). Older pending statements below are historical.

## Latest published correction: client cancellation and profile response fencing

AF-03/AF-04 are fixed and published on restricted staging. Client 4.3.83 prevents stale Compost/Pet Drops/Leaves sends and confirmations, restores movement before Stop can wait on network disconnect, protects newer claims/tickets and preserves watchdog recovery. Profile, exchange and key responses are fenced by session generation; logout cannot be undone by a late profile body. The local gate passed 25 suites; the four affected client suites passed again after the final movement cleanup, including 65 new focused scenarios across client/auth checks. Full outer/embedded client chunks compile and 4.3.80â€“4.3.82 remain unchanged. See [fixes and limitations](docs/client-auth-continuation-fixes.md) and [local verification](docs/local-client-auth-gate-2026-10-03.json). Code commit `7dbff7b6122f33814cc057e290389bb7ecc2f6e8` passed hosted CI (25 suites); Pages `2c234f16-c1b1-4ee9-a178-85c43f5597f0` passed nine asset byte/header checks and five service/login/guest checks. See [rollout](docs/client-auth-rollout-2026-10-03.json). Owner game/telemetry verification of 4.3.83 remains pending. General access remains restricted; ordinary daily cleanup, full UTC-day D1 use and targeted independent review remain release gates.

## Previous correction: delayed authorization and analytics invalidation

AF-01/AF-02 are corrected in the source and the isolated local gate passed 22 suites. Logout/key rotation share the account mutation queue; untrusted request bodies are read before authentication/queue admission, and key issuance has a session-expiry fence at its D1 write. Analytics invalidation drains the full pipeline without blocking prior I/O, and profile cleanup follows that drain. See [changes, evidence and limits](docs/server-auth-cache-fixes.md). AF-01/AF-02 code commit `146910cc544002806d64522f5cb7d5a5552488ef` passed hosted CI and was deployed on API 71c76b56 and live 448b2df8; nine guest/service probes passed. This does not replace owner authenticated telemetry verification. General registration remains restricted; remaining independent review stages, full UTC-day D1 use and ordinary post-activation maintenance completion remain open.

## Latest update: stable loader and GUI update checks published in 4.3.82

The owner confirmed 4.3.81 cancellation/off-on/close-restart worked. Its corrections are retained in 4.3.82. The stable loader now selects the version through a public static manifest; the saved command has no version. GUI update-check code is restored after the staging override disabled it. Local gate passed 20 suites / 234 groups. See [update flow and limits](docs/client-updates.md). Published code commit `c7b2e4aecc8e72e97e7b280190e7e7655ad20796` passed hosted CI (20 suites / 234 groups) and is deployed on Pages 0dcc9ba7. Eight assets, JSON/no-store headers, three health/guest probes and functional cloud login/callback passed; see [rollout evidence](docs/client-updates-rollout-2026-10-02.json). Earlier immutable clients are preserved; general registration remains restricted. Ordinary daily cleanup, deferred full UTC-day D1 use, owner menu/theme checks and targeted independent review remain open.

## Previous update: AR-10 cancellation candidate published for owner test

New immutable candidate 4.3.81 guards Auto Market delayed tasks, remote entry points, confirmation/reply continuations and burst timeouts with generation/revision tokens. Destroy blocks market actions before network disconnect yields. The full local gate passed 19 suites / 222 groups; seventeen focused groups passed with actual Luau functions and compiler checks. See [candidate scope and owner check](docs/market-cancellation.md). Published candidate code commit `70baced555afd8e92a8dccaf8b8ee08a522cceec` passed hosted CI (19 suites / 222 groups) and is uploaded on Pages 0277f54a. Six assets, three health/guest probes and functional cloud login checks passed; see [rollout evidence](docs/market-cancellation-rollout-2026-10-02.json). Default loader and release 4.3.80 are unchanged until the owner game check. General access remains restricted; real keyboard/game checks, ordinary daily cleanup, deferred full UTC-day D1 usage and targeted independent review remain open.

## Previous update: keyboard, focus, contrast and retained-record labels published

AR-07â€“AR-09 and AR-11 are implemented locally. The full local gate passed 18 suites / 205 groups; twelve focused component checks also passed after the final confirmation-reset adjustment. See [correction and limits](docs/dashboard-accessibility.md). Published code commit `03983c4183166dc361dca7301cb86d3c866698aa` passed hosted CI (18 suites / 205 groups) and is deployed on restricted Pages b71b7ef5. Eleven assets, three health/guest checks and functional cloud login/callback checks passed; see [rollout evidence](docs/dashboard-accessibility-rollout-2026-10-02.json). Owner keyboard/menu/theme verification remains pending. The owner confirmed the previous cloud Discord login correction works. General access remains restricted; AR-10, full UTC-day D1 usage, ordinary daily cleanup and targeted independent review remain open.

## Previous update: staging login configuration corrected

The AR-04â€“AR-06 frontend upload mistakenly replaced cloud endpoint configuration with repository local preview defaults. The owner observed login redirecting to 127.0.0.1. Existing staging API/live/WSS endpoints were restored in Pages deployment e3fc1685. The actual hosted auth service now constructs the cloud login target; OAuth start returns 302 to Discord with the correct staging callback. No backend settings or account data changed. See [incident and verification](docs/login-config-correction-2026-10-02.json).

A new cloud preparation tool requires explicit public HTTPS endpoints and rejects local configuration; four focused regressions and eleven existing web checks passed. The default CI includes these regressions. Full hosted CI for this tooling update and the owner's real Discord retry have not yet been observed. Remaining accessibility, Luau cancellation and release gates remain open.

## Previous update: dashboard stability corrections published and deployed

AR-04â€“AR-06 are corrected: stale account responses are rejected, initial API failures recover through bounded requests/retries, and route subscriptions are disposed. The full local gate passed 16 suites / 189 groups. See [dashboard correction](docs/dashboard-stability.md). The frontend batch is published in source commit `16cc7c1eee7b65427746c2ab4f21129b2a0d6190` and deployed on restricted staging. Hosted CI passed the same 16 suites / 189 groups; twelve asset byte checks and three health/guest probes passed. See [rollout evidence](docs/dashboard-stability-rollout-2026-10-02.json). Its real-browser owner check is pending. Remaining AR-07â€“AR-11, full-day usage, the next ordinary daily cleanup and targeted independent review remain open.

## Previous update: P1 fixes published and verified on restricted staging

AR-01â€“AR-03 are included in public source commit `dff3e8f03851cef3c85dd351726ae3ce2e8a66de`. GitHub Actions passed 15 suites / 174 groups with no failures. API, live and frontend were deployed on the existing restricted staging; original bindings, namespaces, secret names, access settings and journal identity were preserved. Eight published files matched prepared source bytes and seven guest/health probes passed. The owner confirmed real game telemetry still updates after deployment. See [rollout and CI evidence](docs/hosted-p1-ci-2026-10-02.json).

Maintenance was resumed without reinitialization: saved completed state showed 14 steps, zero failures and no pending deletions. This is not observation of the next ordinary daily Cron. Full UTC-day D1 usage remains deferred. AR-04â€“AR-11 and targeted independent review remain pending; general access remains restricted.

## Previous update: three Astra P1 findings corrected locally

AR-01 escapes runtime status labels and limits state classes. AR-02 separates the fixed ledger expiry cutoff from current event validation after reads. AR-03 orders account deletion and maintenance/recovery continuations with runtime mutations, reauthenticates queued requests and guards linked live D1 inserts against deleted ownership. Cleanup wake-up is outside the user queue to avoid mutual waiting. Legacy disabled writes retain HTTP 410.

The local default gate passed 15 suites / 174 groups, exit 0, including 14 new P1 regression groups and one additional web check. See [current local evidence](docs/local-p1-gate-2026-10-02.json). These changes were subsequently published and deployed; see the newer evidence above. Remaining AR-04â€“AR-11, full-day D1 consumption and ordinary daily cleanup completion remain pending. General access remains restricted.

## Previous update: provider configuration and contact instructions checked

Read-only provider inspection on 2026-10-02 confirmed Logpush disabled and no Tail consumers on API/live, no Pages Web Analytics tag/token, and both R2 buckets with r2.dev disabled and no custom domains. Workers script-settings returned Observability=null; this is recorded without claiming all provider logging is absent. R2 lifecycle only aborts unfinished multipart uploads, so application expiry still depends on maintenance. See [settings evidence](docs/provider-settings-2026-10-02.json).

Contact notices now explain sending septave a Discord friend request when direct messages are unavailable. The owner confirmed friend-request delivery from a second account on 2026-10-02; this is a user-observed functional check, not a future-availability guarantee. No second private contact was selected. Provider settings and user data were not changed. Full-day consumption remains deferred by the owner; cleanup completion and final independent review remain unverified.

## Previous update: privacy wording aligned with source

On 2026-10-02, RU/EN privacy notices were clarified for connection-IP request limiting and account-export scope. Server authorization credential records are excluded; stored runtime snapshot contents are preserved. Account-data documentation now reflects the active restricted-staging journal. No API/live code, credentials or access list changed. Ten existing local web checks passed. See [targeted consistency review](docs/privacy-code-check-2026-10-02.md).

The owner deferred ordinary full-day D1 consumption until later; the earlier partial-day measurement was not marked a full-day or capacity pass. Post-activation daily cleanup completion also remains unobserved. Work continues on other release checks while restricted access remains in place.

## Previous update: operational documentation reconciled

On 2026-10-02, setup, testing, recovery/provider and D1-budget instructions were reconciled with the completed journal activation and all five SQL migrations. No runtime code, deployment or cloud data changed. Cloudflare/GitHub authenticated access was restored and checked. A read-only capture around 06:14 UTC reported 2,518 account-wide D1 written rows (126 staging, 2,392 legacy Veyra) and 6,109 read rows during part of the UTC day; the existing account/day/completeness validator accepted both database groups. API settings remain required/restricted with the original ledger identity, live remains restricted, and both report Logpush disabled. No cloud mutation was performed. This does not establish full-day consumption, cleanup completion or all provider logging settings. The previously successful hosted CI remains valid for its recorded source commit. Full-day normal usage, post-activation daily cleanup completion and reachable private contact remain pending.

## Previous update: hosted CI and owner UI checks confirmed

GitHub Actions attempt 3 passed on 2026-10-02 after the external account restriction was resolved. All job steps, including dependency installation and the complete fourteen-suite / 159-group synthetic gate, succeeded on Ubuntu 24.04.5 / Node.js 24.21.0 at source commit 9bed86447ce600b1b3d79c8b891f80f0bb7d748f. See [hosted evidence](docs/hosted-ci-2026-10-02.json). No production cloud fixture or real profile deletion was performed.

The owner confirmed post-cutover game telemetry updates and the planned owner analytics checks: populated statistics/charts, search/filter empty states, Refresh, Pause/Resume and period switching. A 394Ã—842 browser responsive-mode screenshot supported the narrow layout check; this was not a physical-phone or full accessibility review. Read-only provider analytics captured 1,995 account-wide D1 written rows, including 19 staging rows, during part of the UTC day; analytics may lag. A successful ordinary scheduled invocation was observed at 2026-10-02T03:17:48Z, before journal activation. The first daily invocation after activation, completion of its alarm-driven cleanup and a full UTC day's normal resource usage remain wider-access gates.

## Previous update: deletion journal activated on restricted staging

On 2026-10-02, fresh account-wide D1 analytics showed 1,928 written rows before initialization; a small 250-row operator allowance was reserved. API/live access was closed, native maintenance paused and existing bindings/namespaces/secret names preserved. The receipt fence and matching private R2 coverage were initialized with the provider clock. Required journal mode is now enabled. Inspection found matching gate/configuration/bucket identities, no pending deletion jobs and no deletion events. No actual profile was deleted and no large fixture was repeated.

RU/EN privacy and account notices were deployed and fetched with active wording. Maintenance resumed with a fresh cutoff, progressed without observed failures, and both Workers returned to the same restricted access list. The temporary secret-gated operator was removed; Cron and private bucket access were preserved. API/live health and unauthenticated account/token rejection passed. Provider analytics may lag, so repeated 1,928-row captures are not a measurement of the exact cutover cost. Authenticated telemetry and ordinary daily Cron execution remain to be observed. Coverage begins at activation; earlier real-data backups remain unsupported. See [activation evidence](docs/deletion-ledger-cutover-2026-10-02.json).

## Previous update: complete local release gate

On 2026-10-02, the complete fourteen-suite / 159-group local gate passed on Windows with Node.js 24, exit code 0. The release archive's 152 pre-update files matched the source bytes and recorded Git blob hashes, with no private paths, known actual dashboard keys, session-token patterns or test allowlist IDs found; both secret example files contained only placeholders. Documentation/evidence updates are then included in a regenerated archive. This is local verification, not a new cloud storage, authenticated UI, hosted CI or complete Roblox-feature check. No cloud write or desktop control was performed. The deletion journal is still not independently confirmed active: its last verified mode was disabled, with no coverage. Cloudflare control tools are currently unavailable in this chat. See [local release evidence](docs/local-release-gate-2026-10-02.json).

## Previous update: read-only account usage report

The operator collector now queries the full account's D1 usage for the current UTC day, validates account identity/completeness and includes deleted databases. Four targeted local groups passed. Its generated query was executed through the existing authenticated connector; nine real groups normalized successfully and the 119,082-row capture correctly blocked cloud work. Standalone token transport was tested with synthetic responses only. The configured default gate now has fourteen suites / 159 groups; the last full run remains thirteen suites / 155 groups plus the subsequent four targeted checks. No additional cloud fixture or D1 write was performed. The journal remains disabled pending reset and a fresh budget; activation/failure instructions now require the account-wide preflight. See [collection and limits](docs/d1-write-budget.md).

## Previous update: D1 quota incident correction

Account-wide read-only analytics attributed 105,242 of 118,919 written rows on 2026-10-01 to the disposable large mutation fixture; restricted staging contributed 3,027. The large cloud seed is disabled and fourteen archived fixture entrypoints are blocked pending adaptation. New small cloud checks require fresh account-wide metrics, 30,000 rows of headroom and a shared 2,000-row daily fixture reservation. Large capacity checks remain local. These operator controls are not a global provider spending cap.

Runtime ownership timestamps now checkpoint at most once per minute, with current identity/deletion/collision checks even when the timestamp write is skipped. Incoming telemetry cadence and credential revocation are retained. All thirteen local suites / 155 groups passed, including nine new write-budget groups. The API correction was deployed to restricted staging with existing bindings/secrets/namespaces and Cron preserved; health and guest gates passed. No D1 migration, new cloud fixture or real-account mutation was performed for this correction. Authenticated cloud telemetry after this upload remains unverified while the daily quota is exhausted. The consumed quota cannot be refunded by this code change. See [write budget and limits](docs/d1-write-budget.md) and [sanitized evidence](docs/d1-write-budget-2026-10-01.json).

## Previous update: approved journal; activation deferred by D1 quota

The owner approved the additional 35-day ID/time-only journal retention. The candidate now includes migration 0005: a default-inactive D1 receipt fence preventing old deletion finalizers from completing without a matching journal receipt after the gate is enabled. Six new cutover groups passed; the complete local gate passed twelve suites / 146 groups.

Restricted staging received the new API code and migration 0005. RU/EN notices were deployed before the cutover attempt. API/live access was closed and maintenance paused. The dedicated R2 bucket has public access disabled. D1 rejected the gate insert because the account's free daily row-write limit had been exceeded. Coverage was NOT initialized and no real-data journal coverage is claimed. Access was restored to restricted mode, journal mode returned to disabled, and maintenance resumed inactive/unpaused. Existing secret binding names, D1/R2/DO identities and Cron were preserved. The temporary operator Worker was removed. Notices now explicitly mark the journal planned/not enabled.

Cloud D1 write-dependent operations may fail until the provider's daily reset at 00:00 UTC; healthy HTTP endpoints do not establish working storage, sign-in or telemetry. No billing change was made. Before retrying, review the write budget and shared account usage, then repeat the closed/fenced initialization with a fresh provider-clock coverage start. Historical real-data recovery remains prohibited without coverage; backups predating activation remain unsupported. See [cutover evidence](docs/deletion-ledger-cutover-2026-10-01.json) and [ledger design](docs/deletion-ledger.md).

## Previous update: concurrent runtime mutation correction

A deterministic synthetic race reproduced a push recreating a Roblox-account row/snapshot after unlink returned success. The new per-Aroyn-account AroynRuntimeMutations binding orders push/link/disconnect/unlink, reauthenticates queued requests, persists revocation before cleanup and allows cleanup retry without the row. Push also rechecks the current key hash after writes. Different Aroyn users stay independent; the shared compatibility mirror is protected across one user's Roblox accounts. Migration 0004 indexes account-scoped exchange-code revocation/cascades. Ten local regression groups passed; the complete default gate passed ten suites / 128 groups. A separate cloud fixture passed ten checks with twelve concurrent request pairs and deletion of 5,000 history plus 15,000 related rows. Local 1,000/10,000-row account deletion checks also passed. These do not establish all races, higher concurrent load, cloud CPU/quota limits, or mixed-version rollout. Temporary cloud resources were removed. The corrected API, new mutation binding and migration 0004 index were deployed to restricted staging; existing namespaces/secrets and Cron were preserved. Health/guest gates passed. The owner subsequently confirmed that authenticated game telemetry continued updating after this upload (user observation, not an independent latency measurement). See [runtime mutation evidence and limits](docs/runtime-mutations.md).

## Isolated recovery

The synthetic recovery drill passed eleven local checks and ten actual-cloud checks. D1 Time Travel restored a previously deleted invented profile; sanitation replayed a separate deletion manifest, revoked every restored session/key, cleared old runtime copies/associations, applied retention and preserved the other profile's recent attributed history/export. The local check also rejected a demonstrably unexpired old live token with a fresh signer. The cloud drill used fresh Worker/DO namespaces and secrets, stubbed cache/rate controls, and no OAuth or live socket. All disposable resources were removed; existing staging was unchanged. The operator helper cannot reopen service automatically. The default gate is now nine suites / 118 groups. A real-data deletion ledger remains unactivated (approved retention; cutover is deferred as documented above), so restoring historical real data still requires reliable external coverage or rebuilding an empty store. See [recovery drill](docs/recovery-drill.md).

The owner approved publishing this initial source package, including the supplied mark and synthetic dashboard screenshot. Original project code is MIT, with attribution to vmsize; brand assets have separate terms in BRAND_ASSETS.md. A separate restricted Cloudflare staging derived from this source was deployed on 2026-10-01. General registration remains restricted.

The client 4.3.80 release, owner analytics UI and public status page are now included. The status bot, runtime data, credentials and actual deployment configurations remain outside this package. Some technical Veyra identifiers remain for compatibility.

## Completed

- The owner approved dark/light themes, mobile layout, keyboard controls, the independent ASCII homepage background and Portal CTA. The homepage no longer imports React/vgpu from esm.sh. See THIRD_PARTY_NOTICES.md.
- Authentication, login/key concurrency, bounded input, signed presence, rate controls and revocable WebSocket access were reviewed and exercised on isolated synthetic data. Local checks include 29 security groups, six presence groups and 17 integration/persistence groups. Separate-process persistence was tested with a private harness.
- Approved retention is implemented: 30-day history, 7-day inactive snapshots, profiles until deletion. Export/deletion with recent Discord sign-in is available through the profile menu. Nine synthetic lifecycle groups passed.
- RU/EN privacy, terms and cookie/storage previews are integrated and linked before sign-in. Keyboard links, 394px table overflow and sampled light/dark text contrast were checked. This does not establish full WCAG or legal compliance.
- Separate Pages/API/live/D1/R2/DO resources and both D1 migrations were deployed. Account/data access is restricted through server-side invited Discord identity checks. Signing secrets and the allowlist are excluded from source. Legacy runtime distribution is disabled on that staging.
- 20 local access/initial-link checks and 25 initial cloud probes passed. The owner confirmed real Discord sign-in and persistence after refresh, connected telemetry, updates in 1â€“2 seconds, stale approximately 13 seconds after game exit and automatic saved-key linkage after rejoining. These timings are observations, not service guarantees.
- A populated cloud export passed 17 checks on nine records, with a completion marker and no recognized credential fields/values. The owner then deleted the test account and re-created it. Cloud read-only checks confirmed the old profile/session/history/links/runtime owners removed, R2 empty, no pending deletion job and a new profile without a key.
- An idle native runtime WebSocket on cloud staging reached CLOSED with code 1008 / Live access revoked after key rotation, approximately 14 seconds after observed revocation. Old-key verification and new-token issuance returned 401. The receiver sent no telemetry during this test.
- A separate temporary cloud fixture passed 14 additional checks on three synthetic accounts and six native WebSockets. Idle dashboard closure after logout and both dashboard/runtime closures after deletion reached CLOSED / 1008 in approximately 12 seconds; old issued tokens were rejected, and the unrelated account kept receiving data. This fixture combined API/live handlers in one Worker and seeded sessions directly; it did not test Discord OAuth or the separate cross-Worker deployment topology. Temporary Worker/D1/R2/DO resources were removed.
- One additional invited tester was added to restricted staging. The owner reported successful use and supplied a screenshot of the tester's distinct empty profile. The screenshot and tester identifiers are not published here. The tester's game telemetry and export contents were not independently verified.
- Runtime R2 mutations are serialized per object key through AroynSnapshotStore. Eight local race checks, including twelve Miniflare replacement runs, passed. A real Cron event on a separate temporary synthetic Worker ran shared retention code and passed 17 checks: history/snapshot expiry, eight concurrent replacements, fresh cutoff preservation and failed-deletion retry. D1 independently confirmed the result. The fixture clock advanced eight days for snapshot expiry; cache transport was stubbed. Temporary resources were removed. The owner confirmed telemetry continued updating after the correction was deployed to restricted staging.
- R2 public access, Pages Web Analytics and Logpush were checked as disabled. Observability is disabled in the deployment configuration. This does not establish that the provider retains no internal logs or backups.

## Remaining limits and wider-access gates

- Observe the normal daily staging retention invocation; review larger backlog duration/cost and account-finalization SQL/cascade work. The isolated cloud Cron probe does not establish ordinary daily execution or large-volume operation.
- Verify hibernation on Cloudflare and broaden concurrent unlink/push and other lifecycle races. Nine forced local hibernation groups passed; this does not establish cloud sleep behavior or all races. The separate API/live synthetic cloud fixture passed logout/deletion/key-rotation and reconnect scenarios. D1/R2 are not one transaction, and direct administrative R2 writes bypass the application coordinator.
- Broaden client verification beyond the ownerâ€™s connected Greedy Growers session. Aroyn 4.3.80 supports signed presence and credential-bound live tokens. Other client environments, active farming behavior, and additional testersâ€™ telemetry have not been exercised in this release. Existing Veyra deployments and original client files were not changed.
- Caller-claimed Roblox IDs and anonymous first presence reports are unverified. Signed later tokens and dashboard-key linkage do not prove Roblox ownership or authentic activity. Restricted staging requires an invited key and linked identity; ordinary deployment settings have different access behavior.
- Finish provider log/backup review, operator information, teenage-audience requirements and review of the policy previews before wider service access. The owner chose nickname vmsize and Discord contact septave; their legal sufficiency and direct-message reachability have not been established. SECURITY.md explains a fallback for requesting a private reporting channel.
- Review production CORS/release queue configuration and destination resources. Examples contain placeholders; source publication does not provision a service for someone cloning this repository.
- Owner permission for the supplied mark is recorded separately from MIT. It is not independent clearance of third-party rights or trademark registration.

## October 1 update: client, status and owner interface

- Aroyn Hub 4.3.80 and its fixed-release loader are hosted on the existing free Pages test address. HTTPS responses matched local SHA-256 values and returned text/plain. The homepage copy action shows a success state; a controlled Clipboard refusal exposes a selected manual command. The browser automation clipboard bridge returned empty text, so the operating-system clipboard was not independently read back. Component checks verify the exact copied value.
- The published loader ran in the ownerâ€™s connected Greedy Growers session. Signed presence, initial HTTP snapshot, WebSocket acknowledgment and subsequent pushes succeeded. Re-execution replaced the singleton and stopped the previous instance. Stop/restart was exercised earlier in the same session. Eight controlled loader success/failure cases passed.
- Tests used verification mode: restored auto farming was disabled and persisted user settings were not overwritten. Legacy saved settings/key files remained unchanged. New Aroyn folders read compatible legacy data; the old production key is not imported into this test backend. After verifying that the saved staging automation flags were off, normal mode was tested as well: new settings/key files were saved under AroynHub, the old files remained unchanged, and a restart after clearing the in-memory key reconnected from the new saved config. Anti-AFK remained enabled. This does not establish correct behavior of every farming feature.
- Public status checks both HTTP endpoints from the browser without credentials. It makes no uptime, sign-in, storage or telemetry guarantee. Cloud API/live health responded and anonymous account/owner-data requests returned 401.
- Owner analytics includes pause/resume, refresh, period selection, mobile layouts, keyboard table regions, safe external URLs and stale/error states. A delayed response after sign-out cannot reopen private analytics. Synthetic mobile preview and unauthenticated cloud gate were verified; the ownerâ€™s full authenticated browser view remains a manual follow-up. Backend synthetic owner/non-owner checks passed.
- New browser storage uses aroyn.* and reads legacy veyra.* preferences. Sign-out updates both session namespaces; reset/deletion removes both. Database columns, durable-object class names, OAuth compatibility fields and Cloudflare account hostname retain legacy names to preserve data.
- Six portable synthetic suites passed 85 check groups after a clean npm dependency install on Windows. CI is configured for Node 24 on Linux. Initial hosted attempts were stopped by an external account restriction; the later complete hosted gate passed as documented above. The source and clean local checks were published successfully.

## Separate cloud lifecycle verification

On 2026-10-01, 18 checks passed with two distinct temporary API/live Workers, isolated shared D1/R2 and an API STATS_CACHE binding pointing to the live Worker. Three seeded synthetic profiles opened six native runtime/viewer WebSockets. Logout rejected the old web session and closed its idle viewer in 10.3 seconds while the separately authorized runtime remained connected. Account deletion closed both idle sockets in 10.5 seconds and removed the synthetic D1/R2 data. Previously issued tokens could not reconnect. Another profile kept receiving telemetry. A new synthetic web session restored viewing after logout; key rotation rejected the old key/runtime token and a new key restored runtime telemetry while the valid viewer stayed connected. These observed timings are not guarantees.

The handlers came from the published source; the control wrapper required a generated probe secret, and no real accounts or existing staging secrets were copied. OAuth was not tested. The first setup attempt returned 404; its cause was not independently determined. After a diagnostic success and fixture reset, the full run passed. R2 cleanup left zero objects; both Workers, their DO namespaces, D1 and the R2 bucket were removed. Forced hibernation and higher load were not tested. Sanitized results: [cloud-split-lifecycle-2026-10-01.json](docs/cloud-split-lifecycle-2026-10-01.json).

## Local hibernation and retention capacity verification

Nine additional forced Miniflare hibernation groups passed on synthetic profiles. Runtime/viewer attachments, isolation, credential revocation, the message-rate counter and the persisted authorization alarm survived object recreation. The native client bounds the local proxy close-handshake wait to one second and requires the server's 1008 Close frame. This is not a cloud hibernation or TCP-close-timing measurement. The default test gate now contains seven suites and 94 groups.

The optional local retention check removed batches of 100 and 1000 small expired snapshots and the same number of expired history rows, preserved fresh history and three revocation markers, and removed nothing on a repeated cleanup. The initial sweep took approximately 2.9 and 32.2 seconds locally, respectively. The larger sweep called the snapshot coordinator 1000 times. Cloud quotas, CPU and cost were not measured; the current sweep still scans all pages in one invocation, so bounded continuation and backlog handling remain wider-access gates. [Verification notes and sanitized evidence](docs/local-lifecycle-capacity-2026-10-01.md).

## Bounded cleanup update

Retention now runs through AroynRetentionRunner with saved progress, a fixed cycle cutoff, at most 25 listed objects or 250 history rows per step, and native alarm continuation. Failure keeps the checkpoint and schedules bounded exponential backoff. Large account removal returns 202 while storage cleanup continues, with credentials already revoked. A new deletion arriving during another cycle schedules a follow-up. Scoped account-finalization SQL and foreign-key cascades are not covered by the 250-row history limit.

Eight default suites passed 107 groups, including 13 new continuation checks and actual Miniflare alarms after forced object eviction. The optional 100/1000-object local runs passed 17/57 bounded steps drained without alarm delay; no cloud CPU/quotas were measured. A temporary synthetic cloud fixture passed eight checks through native ten-second alarms: 63 old snapshots and 270 history rows expired over 16 steps, while fresh history, a profile, a revocation marker and an unrelated payload survived. Cache transport was stubbed and the fixture clock advanced eight days. The cloud run preceded the small follow-up-deletion flag addition; that addition passed local checks. Temporary resources were removed. See [implementation notes](docs/bounded-retention.md) and [cloud evidence](docs/cloud-bounded-retention-2026-10-01.json).
