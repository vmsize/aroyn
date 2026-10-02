## Current result — owner check confirmed

The owner confirmed 4.3.81 worked in the game. Its market corrections are retained in 4.3.82, which restores update notices and the stable manifest-based loader. The following candidate record describes the earlier testing stage; the current launch flow is documented in [client release](client-release.md).

# Auto Market cancellation candidate 4.3.81 — 2026-10-02

AR-10 is corrected in a new immutable candidate at `apps/dashboard/releases/4.3.81/greedy-growers.luau`. Release 4.3.80 and the default loader remain unchanged pending the owner game check.

Each market operation carries the client generation and enable-cycle revision. Delayed children, confirmation loops, remote action entry points and offer responses check that token. Turning Auto Market off and on does not revive older jobs. A burst timeout also invalidates its pending children. A stale scheduled callback cannot clear the newer worker's scheduled flag. Destroy blocks market actions immediately and invalidates the client before waiting for the network disconnect. Teleport cleanup is idempotent and preserves the newer owner.

A request sent before cancellation may still complete on the server. Cancellation prevents subsequent client actions and stale counter/UI updates; it does not undo an accepted game transaction.

## Local verification

`tests/market-cancellation-check.mjs` executes actual extracted client functions on the official Luau CLI with a deterministic coroutine scheduler and stubbed remotes. Sixteen behavioral groups cover normal success, stagger cancellation, off/on cycles, request/confirmation races, actual Destroy ordering, timeouts, scheduled-worker ownership and repeated teleport cleanup. Another group compiles both outer and embedded candidate chunks and verifies immutable release 4.3.80. The script does not run Roblox or validate real game server behavior.

The test CLI is pinned and downloaded only for development; archive digests and platform selection are in `tools/luau-test-runtime.mjs`.

## Owner check before loader promotion

Once this candidate is uploaded to the existing staging site, run it directly in the same supported game/environment already used for testing:

```lua
loadstring(game:HttpGet("https://aroyn-staging.pages.dev/releases/4.3.81/greedy-growers.luau"))()
```

1. With Auto Market initially off, check the UI reports 4.3.81 and the dashboard connects and updates.
2. Start Auto Market with a suitable owned fruit, then turn it off during a batch. Already sent operations may finish; no further batch or reward claim should begin after cancellation.
3. Toggle off/on quickly: the new enable cycle should work without an old batch restarting or duplicated submissions.
4. Close the client during a batch, rerun the candidate and verify one interface, restored settings/key and telemetry. Existing Aroyn settings may save normally; the test does not intentionally reset them.

If no suitable fruit is available, record that the market behavior check remains pending. Do not treat a telemetry-only run as a cancellation pass. Agent control of Roblox/browser requires fresh owner permission.

After this check, update the default loader and working client together, record hashes, verify the hosted loader and publish the release notes. General registration remains restricted pending the other release gates.

Full local gate: **19 suites / 222 groups**, exit 0. The final immutable-loader hash assertion also passed in a focused rerun (17 groups). See [local evidence](local-market-gate-2026-10-02.json). Hosted CI and candidate upload subsequently completed; see the newer evidence below.

## Published candidate

Code commit `70baced555afd8e92a8dccaf8b8ee08a522cceec` passed hosted CI: **19 suites / 222 groups**. The candidate is uploaded on restricted staging Pages 0277f54a. Six asset byte checks, three health/guest checks and the actual hosted cloud login/callback passed. The default loader still downloads immutable 4.3.80. No API/live settings or databases were changed by this batch; no real game test has been performed by the agent. See [rollout evidence](market-cancellation-rollout-2026-10-02.json).
