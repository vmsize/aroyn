# Backend review — 2026-10-01

This describes the source package and its restricted staging verification. It is not a production security certification.

## Changes

- Login exchange codes are consumed atomically with expiry checks. Concurrent first sign-ins preserve one Discord user record. Initial key generation cannot silently replace a key created by a concurrent request; replacement still requires confirmation.
- Auth/control JSON is limited to 8 KiB while reading the request stream. Account telemetry is limited to 256 KiB and opt-in legacy telemetry to 96 KiB, measured in UTF-8 bytes. Malformed JSON, arrays and null are rejected with a controlled 400 response.
- Live tokens reference the hash of the web session or dashboard key that issued them. D1 authorization and account linkage are checked at upgrade, on messages, and before relaying to each receiver. A Durable Object alarm rechecks idle sockets every 15 seconds. A revoked credential or removed account starts connection closure with code 1008; authorization lookup failures start closure with 1011.
- Runtime WebSockets accept schema-v1 JSON snapshots for their authenticated, linked Roblox ID. Binary, malformed and oversized messages are rejected. Connections allow at most 120 incoming messages per 60-second window.
- Presence session collisions cannot overwrite another identity, and cleanup deletes a session only when its Roblox ID also matches. Concurrent anonymous first reports now check the conditional insert result before creating analytics records or issuing a token.
- API and live authorization/handshake routes require Cloudflare rate-limit bindings. Presence limiting uses a route and source-IP key rather than one shared route key. Missing limiters or signing secrets fail closed. Limits are burst controls; they are not globally exact quotas.
- Legacy `/api/v1/runtime/*` routes default to 410. If explicitly enabled, they require a registered dashboard key, not merely a correctly formatted string. The health endpoint remains available. `/session` and `/payload` accept GET only.
- Unexpected public request failures return generic JSON. Owner/stats error responses omit exception details. Failed avatar lookups record their refresh attempt instead of retrying on every push.

## Verification

A private local Miniflare harness with mocked Discord/Roblox responses and synthetic records passed:

| Suite | Passed groups |
| --- | ---: |
| Security, revocation, input and owner access | 29 |
| Presence concurrency, signed disconnect and rate controls | 6 |
| Login, key linkage, R2 and WebSocket relay | 9 |
| Two-account isolation and persisted fixture seed | 5 |
| Separate process restart using persisted D1/R2 | 3 |

The earlier baseline reproduced oversized UTF-8 payload acceptance, unregistered legacy writes, a null-input exception, live-token reuse after logout/key rotation, missing WebSocket identity/size checks, and public error detail. The concurrent exchange test already passed before the atomic SQL change; that change is preventive and is not evidence of a successfully exploited race.

Native local receiver connections entered `CLOSING` after revocation, and a logged-out receiver received no further telemetry. Later, an idle runtime WebSocket on independent HTTPS/WSS staging reached `CLOSED` with code 1008 after key rotation, approximately 14 seconds after observed revocation; old-key verification and new-token issuance returned 401. Additional logout/deletion scenarios with already-open sockets remain unverified in the cloud. Alarm delivery and in-flight requests mean this is not a guarantee of instantaneous revocation.

## Configuration and rollout

Use `API_RATE_LIMITER` on the API Worker and both `LIVE_RATE_LIMITER` and `PRESENCE_RATE_LIMITER` on the live Worker. Example configurations contain them. Choose unused positive namespace IDs in the destination Cloudflare account. Store independent random signing secrets of at least 32 bytes in secret bindings.

Keep `ALLOW_LEGACY_RUNTIME=false` unless an identified old client needs a temporary transition. Even opt-in legacy runtime access requires a database-issued key. Previously issued live tokens without a credential reference are rejected; clients must request fresh tokens. A separate compatible private client was tested against the restricted HTTPS staging environment. A wider client rollout remains required.

The reviewed source was subsequently deployed to separate restricted staging resources. Existing Veyra deployments and the original public client were not changed.

## Remaining release gates

- Anonymous first presence reports and caller-supplied Roblox IDs remain unverified. Signed later reports prevent session substitution; they do not prove Roblox account ownership or authentic game activity. Account linkage is possession of a dashboard key plus a claimed ID, not a Roblox OAuth verification.
- Broaden testing of Durable Object hibernation/alarms, concurrent unlink/push behavior, load and resource costs. Restricted cloud provisioning and runtime key-rotation close completion passed; they do not establish all lifecycle scenarios.
- Account export/deletion, approved retention and policy previews are implemented and exercised on restricted staging. Final provider/privacy review and a verified reachable private reporting channel remain before wider service access.
- The live source still contains transitional `veyra-hub.pages.dev` CORS allowance and optional release-event handlers. Review the old origin and release bucket/queue configuration for the new deployment.
