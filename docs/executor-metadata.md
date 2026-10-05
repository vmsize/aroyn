# Executor diagnostics

Client 4.3.89 reports the executor name and optional version using a protected `identifyexecutor()` call, falling back to `getexecutorname()` when available. Detection happens once per script instance. Missing APIs, exceptions and invalid results produce `Unknown`; Aroyn does not guess from unrelated globals, inspect installed programs or request a HWID.

Only printable text is accepted (64 characters for name, 32 for version). These client-supplied values are informational and can be spoofed. They never grant access, establish account ownership or alter transport selection.

Basic presence includes `executorName` and `executorVersion` over the existing signed WebSocket and HTTPS fallback. Linked snapshots carry `executor.name` / `executor.version`, and linked startup's normal presence registration records the same metadata. No new requests or heartbeat frequency are introduced. Existing clients omit these fields and remain compatible. A legacy/missing report cannot erase an existing known name; a different name cannot retain a previous executor's version.

Private owner analytics shows the metadata in Online now, Recent launches and the latest launch in the user directory, plus a top-ten breakdown by name for the selected range. Unknown includes historical launches and unsupported clients. The breakdown counts recorded launches and distinct Roblox IDs; it does not count verified people. Detailed values are not returned by the bot's aggregate count endpoint. Rendering escapes names and versions as text.

Apply `workers/api/migrations/0006_executor_metadata.sql` before deploying the live Worker. It adds two nullable columns to `analytics_sessions` and preserves existing rows; there are no new indexes, resources, secrets or retention rules. Fresh setup must apply migrations 0001–0006. History export/deletion already handles these fields through the existing associated session records. Both language versions of the privacy notice list executor metadata.

Verification: `tests/executor-metadata-check.mjs` uses actual Luau detection, native synthetic D1/Workers/WebSocket and owner render functions, alongside existing transport, authorization and lifecycle suites. A real executor cannot be checked without an available game connector; re-execute the unchanged saved loader to update an existing game session.

API reference: [sUNC identifyexecutor](https://docs.sunc.io/Miscellaneous/identifyexecutor/).
