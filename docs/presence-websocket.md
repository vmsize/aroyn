# Runtime presence over WebSocket — 4.3.88

## Protocol

The client prefers an acknowledged WebSocket transport. A linked runtime with recent relay ACKs reuses its existing authenticated telemetry socket, after one HTTPS registration obtains a scoped presence token for future unlink/failover. Otherwise it opens `wss://<live-host>/runtime-presence/ws?sid=<session-id>` and sends small `presence` JSON messages. Only the non-secret session ID is in the URL. Dashboard credentials, signed presence tokens and an independent random resume proof remain in TLS frames; they are not logged or broadcast.

The route uses the existing LIVE binding/class under a separate `presence:<session-id>` object identity, with hibernation and serialized socket attachments. No new namespace, schema, migration, secret or plan change is required. This basic socket cannot relay detailed snapshots or join dashboard channels. Existing token, account-deletion, session-ownership, staging-access and first-report limitations are preserved. Roblox IDs are client claims, not verified ownership.

## Failure handling

- No executor WebSocket API, connection or event setup failure: signed HTTPS fallback.
- No matching server ACK within five seconds, send failure, server rejection or socket close: close that transport and fall back.
- Reconnect delays grow from five seconds to a maximum of five minutes. Server ACKs reset the backoff. Retired socket callbacks cannot replace current state.
- HTTP fallback normally runs every 300 seconds; failed HTTP attempts are spaced at least 15 seconds. The lightweight local loop checks transport every five seconds and does not send HTTP each tick. Key/link changes are sent promptly.
- Signed tokens and the same session identity continue across fallback/reconnection. If the very first server ACK is lost, the client can recover using its independent 256-bit random resume nonce. The server stores only its hash and scoped session identity, for 15 minutes of inactivity; session ID alone cannot recover a token.
- Graceful stop waits up to two seconds for a signed socket disconnect ACK, then uses HTTPS if not confirmed. A socket close alone does not delete a row: that close can race a working HTTPS or telemetry connection. Silent exits still expire with the existing seven-minute stale window and scheduled safety cleanup.

## Resource scope

Successful presence WebSocket operation avoids repeated outer Worker HTTP heartbeat requests. WebSocket upgrade/reconnects, Durable Object messages/compute/storage and D1 operations still consume resources. Basic heartbeat cadence is unchanged at five minutes, analytics history checkpoints at 15 minutes. Linked HTTP snapshot persistence is retained separately. No observed production savings or public-scale capacity is claimed from local tests.

## Verification

Actual release Luau functions are exercised with socket events, HTTP fixtures and a controlled clock: supported/unsupported executors, connection/send/ACK failures, recovery, stale events, linked telemetry reuse, credential removal and graceful stop. Native Miniflare checks real Workers, D1, per-session sockets, signed identity, duplicate counts, native hibernation, lost-ACK recovery, HTTPS fallback, linking/unlinking, bounded frames/queues and stop. Existing security/lifecycle/telemetry suites remain in the complete gate. No synthetic production sessions are created. A real executor launch remains an owner check when Potassium is unavailable.

## Published rollout — 2026-10-05

Code commit `2bca4cb70aab158b139ab50a4206ac8b748c46b4`, Pages deployment `dd825b73-2a7a-4368-82b9-b28cbd25d440`, live Worker version `2434f7ff-5eb6-41ff-9130-f9635ea68044`. All 34 local suites and code CI passed. Eleven public assets match the prepared package, API/live/Render health is HTTP 200, and the new public WSS upgrade succeeds without sending runtime-registration frames. Worker bindings, variables, secrets and compatibility date are preserved; Wrangler removed the previous deployment-message annotation. API code is unchanged. No production runtime fixtures or real executor execution were performed. Measured cost savings and real-game behavior remain observation checks, not inferred from a successful upgrade.
