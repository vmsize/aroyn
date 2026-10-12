# Compatibility and verification scope

| Component | Evidence | Limits |
|---|---|---|
| Hub 4.3.96 exact frozen artifact | Owner-reported Windows/Potassium and Android/Delta tests | Other executors, iOS, Studio and arbitrary physical devices are not certified |
| UI Library Stable v0.1.0 | Separate Windows PC/Potassium approval; readable bundle and automated tests | Do not transfer Hub Android approval to the standalone asset adapter |
| Dashboard preview | Static Node server and local config | Sign-in/live data require the API and Live services |
| Root tests | Node 24, synthetic Miniflare stores/outbound doubles and Luau/DOM checks | Not live production capacity or native Roblox rendering |

Hub mobile asset failures were addressed in its own bounded asset/startup adapter, including graceful fallbacks. Standalone v0.1.0 still uses filesystem/custom-asset APIs and can show blank asset slots when they are unavailable; an API call that yields indefinitely is not bounded merely because it is wrapped in `pcall`.

Hub 4.3.96 persists preferences and Dashboard intent while restoring automation **off**. Downgrading to legacy 4.3.95 can restore saved automation flags, does not automatically reverse-migrate new profiles and may have different singleton behavior. Close a running client before deliberate downgrade and keep backups/credentials intact. Changing a loader manifest affects future downloads, not already running clients.

Browser viewport emulation checks layout; it does not establish physical touch/executor behavior. Report the exact artifact/version, platform and executor when describing a native result, and redact all dashboard keys.
