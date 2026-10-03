# Large-inventory telemetry and dashboard recovery

The 4.3.85 candidate keeps the complete JSON snapshot and sends large snapshots
as bounded `snapshot` envelopes with `transport.encoding=json-fragments-v1`.
Each envelope retains the authenticated player/session/product metadata used by
the existing relay. The dashboard assembles up to 16 parts, at most 256 KiB,
within 15 seconds on the same socket. Only a complete identity/schema-matched
snapshot updates counters. Small snapshots keep the previous wire format.

Inventory rows are not truncated. HTTP persistence, presence checkpoints,
ownership checkpoints, Workers and registration settings are unchanged. Multiple
frames use more relay authorization reads; timestamp writes remain checkpointed.
The existing runtime message rate limit still applies. This is a restricted-load
fix, not evidence of public-scale capacity.

Dashboard recovery also rejects stale HTTP replies after fresh WebSocket data,
replaces an open socket after 30 seconds without a complete snapshot, and keeps
the selected account's online indicator consistent with the latest live data.

An authorized 20-second game diagnostic with compact snapshots received server
acknowledgments where the approximately 180 KiB original frames did not. Its
temporary function was restored automatically. Exact executor frame limits were
not determined. The new full-fragmentation client needs an owner smoke test.

Local tests exercise actual Luau framing/sending, Unicode and large inventories,
bounded assembly, missing/conflicting/expired parts, account isolation, native
relay and mid-transfer hibernation. Previous immutable releases and the saved
versionless loader remain unchanged. See the current release record for hashes
and the published rollout for deployment status.
