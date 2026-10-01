# Aroyn Hub 4.3.80

The readable client and fixed-release loader are included under `apps/dashboard`. Original code uses the repository's MIT license; embedded brand assets have separate terms.

The current launch command is:

```lua
loadstring(game:HttpGet("https://aroyn-staging.pages.dev/scripts/loader.luau"))()
```

This downloads executable Luau. Read the source and use a compatible environment you already trust. This document does not distribute or recommend an executor. The loader supports Greedy Growers (GameId `10440833423`), checks the downloaded size and rejects HTML fallback responses before compiling. Other games return a warning without downloading the client. It reports download, compilation and startup failures.

The loader downloads `/releases/4.3.80/greedy-growers.luau`; this path is immutable. Publish changed client bytes under a new version instead of replacing that file. `docs/release-4.3.80.json` records SHA-256 hashes. HTTPS provides transport authentication; the loader does not independently verify that SHA-256 hash in the game environment.

## Settings migration

- New settings/assets are written under `AroynHub/`; preferences read `AroynStagingTest/SeedAutoBuy` or the earlier `SeedAutoBuy` folder if new files are absent.
- The dashboard key can be read from the previous `AroynStagingTest/web_config.json`. A `VeyraHub` production key is deliberately not imported into the separate Aroyn test backend.
- Existing key format and database/transport identifiers remain compatible. The free Worker hostname still contains the Cloudflare account name `veyra-hub`; changing the product name does not rename an account hostname.
- Re-execution unloads the preceding Aroyn/legacy instance, disconnects transport and clears connections before replacing it. Legacy singleton aliases permit an older client to unload the new one as well.

The release uses the restricted Aroyn staging API/live endpoints. Account and telemetry access remain limited to invited Discord accounts. Automatic update downloads are disabled; updating the public loader is a separate release action.

## Verification scope

The prepared and exact published loader ran in the owner's connected Greedy Growers session. Compilation, initial HTTP snapshot, signed presence, WebSocket acknowledgment, repeat execution and stop/restart passed. Eight controlled loader scenarios passed.

During agent testing, `__AROYN_VERIFY_ONLY` disabled restored farming and suppressed settings writes. The runtime remained passive with anti-AFK enabled. The previous saved key/settings files were compared before and after and were unchanged. This establishes transport and migration-read behavior in that session, not every farming feature, mobile executor, or third-party runtime. The normal configuration-writing path then passed after the saved staging automation flags were confirmed off: new settings/key files were written under AroynHub without changing the previous files, and a restart with the in-memory key cleared reconnected from the new file.

## Forks and distribution

For your own service, change `BASE` in the loader, the client API/live/site endpoints, and `SCRIPT_LOADER_URL` in dashboard configuration. Provision your own backend and credentials. Do not copy private runtime configuration or an account key into a release.

The maintainer will update the existing ScriptBlox/rscripts listings after reviewing this release. These listings were not modified by this update. Additional promotion is undecided. No paid domain is needed for the current Pages/Workers deployment.
