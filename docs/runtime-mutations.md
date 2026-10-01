# Runtime mutation ordering — 2026-10-01

## Reproduced defect

A deterministic synthetic request paused just after checking the unlink marker. Unlink then returned 200, deleted the account row/snapshots and stored the marker. Resuming the previously authorized push returned 200 and recreated both the row and snapshot. A per-object R2 lock alone did not serialize the whole D1/R2 lifecycle. This was reproduced in isolated data; no real user's account was used.

## Correction

The API routes v2 push, explicit link, disconnect and Roblox-account unlink through the new `RUNTIME_MUTATIONS` binding to `AroynRuntimeMutations`. The object name is the authenticated **Aroyn user ID**, so different Roblox accounts sharing that user's compatibility mirror are ordered together. Different Aroyn users use different objects. The outer API applies rate controls and resolves the routing identity; the object reauthenticates each request after it reaches the front of its queue. Missing binding returns 503 for an otherwise authenticated mutation.

An awaited promise tail serializes active handlers; it is not a persisted job queue. Credentials and telemetry are not written to DO storage. D1/R2 remain the durable sources of truth, and the existing per-key snapshot coordinator continues to order expiry/writes. A failed handler releases the queue for later retry. Unlink writes its revocation marker **before** row/object cleanup. Retry cleans remaining objects even if the account row was removed by an earlier attempt. Push rechecks the current dashboard-key hash as well as the deletion marker after writing; a revoked in-flight result clears its late snapshots. Avatar refresh has a three-second timeout so that an unavailable thumbnail service does not wait indefinitely inside this queue.

These operations are ordered, not a cross-service transaction. An interrupted unlink may leave old storage awaiting retry; its persisted marker blocks subsequent pushes once written. If writing the marker itself fails, unlink fails rather than reporting completion. Full account deletion and key rotation retain their existing D1 revocation and post-write checks; they are not all routed through this new queue. Mixed-version rollout, arbitrary provider crashes and every lifecycle interleaving are not established by these tests.

## Deployment

Add the API's local `RUNTIME_MUTATIONS` binding and SQLite `runtime-mutations-v1` DO migration from `wrangler.example.jsonc`. Apply all four D1 migrations; `0004_auth_exchange_owner.sql` indexes account-scoped exchange-code revocation and the users foreign-key cascade. Keep the existing snapshot/retention namespaces and cross-Worker analytics binding. No live Worker or client protocol changes are required for these mutation routes.

## Verification

Ten new local groups passed: absent binding; another user progressing while one is paused; push then unlink; unlink then push; disconnect then fresh push; preserving another Roblox account's current mirror; cleanup outage/retry without an account row; active/queued old credentials during key rotation; deletion during an accepted push; and eight real Miniflare concurrent request pairs. Deterministic barriers invoke the class directly with real local D1/R2/per-key coordination; external responses are mocked. The complete default gate is ten suites / 128 groups.

A separate real Cloudflare fixture passed ten checks, including twelve concurrent push/unlink pairs through the native new DO binding, explicit relink, concurrent disconnect/push, key replacement, isolation and account deletion with 5,000 owned history rows plus 15,000 owner/session/exchange rows. Deletion's observed HTTP wall time was 1,771 ms. The surviving account retained its profile and cash snapshot. Cache transport and rate controls were stubbed in a secret-gated wrapper; there was no OAuth, UI, live WebSocket or CPU/quota measurement. These cloud pairs did not force exact interleavings; the deterministic local regression does that. The first setup request returned 404 before seeding; a later diagnostic reached the empty fixture and the full run passed. The initial cause was not independently established. All temporary Worker/DO/D1/R2 resources were removed after the bucket reached zero objects. [Cloud evidence](cloud-runtime-mutations-2026-10-01.json), [local regression evidence](local-runtime-mutations-2026-10-01.json).

An optional `npm run test:account-capacity` passed local deletions with 1,000 and 10,000 owned history rows, matching owner rows, extra web sessions and exchanges. Observed local deletion times were 258 and 1,119 ms. These runs overlapped another local test, so they are correctness/scale observations, not controlled benchmark comparisons. R2 volume was small. Scoped SQL and foreign-key cascades are still not bounded by the retention runner's 250-row limit. Larger shared datasets, account cardinality, backlog, concurrent load and provider resource usage remain gates. [Local capacity evidence](local-account-capacity-2026-10-01.json).

The previous 121-call sequential rate-limit assertion failed once during the full run. It could split across a minute reset; the cause of that particular failure was not independently established. The test now sends a short 241-request native-binding burst and requires an HTTP 429 without depending on completion order. Production rate-limit settings were not changed.

References: [DO coordination rules](https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/), [D1 batches](https://developers.cloudflare.com/d1/worker-api/d1-database/).

## Subsequent daily quota correction

The historical large cloud fixture was subsequently identified as the primary contributor to a shared-account D1 daily write-limit incident. Its bulk seed route is now disabled; large capacity checks must remain local. Runtime ownership checkpoints were reduced without weakening current ownership checks. See [write budget and current verification](d1-write-budget.md). The historical cloud success does not establish safe quota usage.

## Restricted staging rollout

The corrected API and new native mutation binding were uploaded after the checks. Existing snapshot/retention/cross-Worker namespaces and secret binding names were preserved; access remains restricted and the normal daily Cron remains 03:17 UTC. Migration 0004's index was applied. API/live health returned 200, guest profile and guest push returned 401, and an unknown runtime method returned 405. No real user's deletion, unlink or key replacement was performed. The live Worker/frontend were unchanged. Authenticated telemetry on the existing staging after this particular upload remains an owner follow-up; the isolated cloud mutation checks exercised the new binding before rollout.
