# Aroyn Hub 4.3.84

The readable client and stable loader are included under `apps/dashboard`. Original code uses the repository's MIT license; embedded brand assets have separate terms.

The current launch command is:

```lua
loadstring(game:HttpGet("https://aroyn-staging.pages.dev/scripts/loader.luau"))()
```

This downloads executable Luau. Read the source and use a compatible environment you already trust. This document does not distribute or recommend an executor. The loader supports Greedy Growers (GameId `10440833423`), checks the downloaded size and rejects HTML fallback responses before compiling. Other games return a warning without downloading the client. It reports download, compilation and startup failures.

The saved launch command has no version. The stable loader reads `/scripts/version.json` without using account credentials, validates the version and downloads the corresponding immutable `/releases/<version>/greedy-growers.luau`. Updating the manifest selects a new release without changing the user command or loader. Source paths remain immutable; publish changed client bytes under a new version. `docs/release-4.3.84.json` records the current release hashes. HTTPS provides transport authentication; the loader does not independently verify that SHA-256 hash in the game environment.

## Settings migration

- New settings/assets are written under `AroynHub/`; preferences read `AroynStagingTest/SeedAutoBuy` or the earlier `SeedAutoBuy` folder if new files are absent.
- The dashboard key can be read from the previous `AroynStagingTest/web_config.json`. A `VeyraHub` production key is deliberately not imported into the separate Aroyn test backend.
- Existing key format and database/transport identifiers remain compatible. The free Worker hostname still contains the Cloudflare account name `veyra-hub`; changing the product name does not rename an account hostname.
- Re-execution unloads the preceding Aroyn/legacy instance, disconnects transport and clears connections before replacing it. Legacy singleton aliases permit an older client to unload the new one as well.

The release uses the restricted Aroyn staging API/live endpoints. Account and telemetry access remain limited to invited Discord accounts. Update checks are restored. After startup, and then every 30 minutes, the client checks the public static manifest and shows the original GUI header notice when a newer version is available. The check executes no downloaded code and writes no D1 rows. To update, rerun the same saved loader command; the existing singleton is unloaded before the new instance starts. An already running script is not forcibly replaced during a game action.

## Current update and cancellation verification

The owner confirmed the 4.3.81 market cancellation, off/on and close/restart check worked. Version 4.3.82 preserves those corrections and restores the update URL/check logic. Actual loader, update-check and GUI label functions pass twelve local Luau groups with HTTP/game stubs; cancellation and full chunk compilation pass seventeen groups. Real execution of the newly restored update notice has not yet been observed in the game.

## Previous 4.3.80 verification scope

The prepared and exact published loader ran in the owner's connected Greedy Growers session. Compilation, initial HTTP snapshot, signed presence, WebSocket acknowledgment, repeat execution and stop/restart passed. Eight controlled loader scenarios passed.

During agent testing, `__AROYN_VERIFY_ONLY` disabled restored farming and suppressed settings writes. The runtime remained passive with anti-AFK enabled. The previous saved key/settings files were compared before and after and were unchanged. This establishes transport and migration-read behavior in that session, not every farming feature, mobile executor, or third-party runtime. The normal configuration-writing path then passed after the saved staging automation flags were confirmed off: new settings/key files were written under AroynHub without changing the previous files, and a restart with the in-memory key cleared reconnected from the new file.

## Forks and distribution

For your own service, change `BASE` in the loader, the client API/live/site endpoints, and `SCRIPT_LOADER_URL` in dashboard configuration. Provision your own backend and credentials. Do not copy private runtime configuration or an account key into a release.

The maintainer will update the existing ScriptBlox/rscripts listings after reviewing this release. These listings were not modified by this update. Additional promotion is undecided. No paid domain is needed for the current Pages/Workers deployment.

## Publishing a later update

Prepare the new client with its matching UpdateVersion, keep earlier release files unchanged, and update scripts/version.json to the new version. Publish the release asset and manifest together in one prepared Pages deployment; the stable loader and homepage command stay unchanged. Update the release hash record and run the client suites. The manifest and loader use no-store cache headers; versioned assets remain immutable.

## 4.3.83 cancellation fixes

Compost, Pet Drops and Leaves bind yielding work to the feature enable cycle and client generation. Disable, off/on and Stop discard old continuations, retries and confirmations. Teleport cleanup is idempotent and cannot restore an old position over a newer task. A cancelled claim is released without clearing a newer claim. The shared automation watchdog cancels stale ownership before handing it to another worker. An already sent game request cannot be recalled.

This version is published on restricted staging: code commit `7dbff7b6122f33814cc057e290389bb7ecc2f6e8` passed hosted CI (25 suites); Pages `2c234f16-c1b1-4ee9-a178-85c43f5597f0` serves the verified assets. Nine asset byte/header checks and five service/login/guest checks passed. See [rollout evidence](client-auth-rollout-2026-10-03.json). The stable launch command and GUI update check remain unchanged. No real game execution of 4.3.83 has been performed.

## 4.3.84 prompt cancellation and session cleanup

The current published release closes three residual independent-review findings: cancelled Compost fallbacks after a prompt error, cross-tab session replacement/tokenless exchange fencing, and hidden revealed-key DOM cleanup. All 28 suites passed, including 57 new focused scenarios. The stable loader and GUI update checks are preserved; immutable earlier versions remain unchanged. See [corrections and owner check](independent-recheck-fixes.md). Code `3b58d21ffadd4c070737a545babfd256b2861a89` passed hosted CI (28 suites); Pages `a56c1b90-03ea-4075-8458-372a1b8081d2` passed ten asset/header checks and five service/login/guest probes. See [rollout evidence](independent-recheck-rollout-2026-10-03.json). Owner game checks are pending for 4.3.84. The earlier 4.3.83 publication evidence above is historical.

## 4.3.85 large inventory and dashboard recovery

Current immutable release: `4.3.85`. The saved loader is unchanged. Large JSON
snapshots use bounded frames without dropping inventory rows or session counters.
The dashboard reconstructs only complete, matching snapshots and recovers stalled
connections. All 30 suites are verified locally and hosted CI passed; static
deployment bytes/headers were checked. The owner still needs to confirm the full
4.3.85 fragmentation path in the executor. See [scope](telemetry-recovery.md),
`release-4.3.85.json`, and `telemetry-rollout-2026-10-03.json`.

## 4.3.86 — paced full-inventory delivery

The owner reported 4.3.85 stale telemetry. Controlled real-game delivery established the synchronous fragment burst as the observed failure path; 150 ms yields restored delivery. 4.3.86 preserves the complete snapshot, fences cancellation between parts and limits fragment cadence. Stable loader, server code and persistence checkpoints are unchanged. See [scope](telemetry-pacing.md) and [measured rollout](telemetry-pacing-rollout-2026-10-03.json).
