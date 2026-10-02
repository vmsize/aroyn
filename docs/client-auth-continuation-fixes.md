# Client cancellation and dashboard auth continuation fixes

Published client: 4.3.83 on restricted staging. Code commit `7dbff7b6122f33814cc057e290389bb7ecc2f6e8` passed hosted CI (25 suites). Pages `2c234f16-c1b1-4ee9-a178-85c43f5597f0` passed nine asset byte/header checks and five service/login/guest checks. [Rollout evidence](client-auth-rollout-2026-10-03.json).

## AF-03 (P2): cancelled automation continues after a wait

Compost feeding could send a prompt after the replication wait despite disable. Pet Drops and Leaves could send their first prompt after teleport settle. Tokens now include the feature revision and client generation; guards run after yielding boundaries, before additional sends and before accepting confirmations. The arbiter retains a single operation identity, supports the same leaf batch and invalidates stale work on watchdog recovery. Teleport tickets finish once, and cancelled claim cleanup checks identity.

Local checks extract actual product functions and use deterministic coroutines with stubbed Roblox objects/remotes. They cover normal work, disable, off/on, Stop, confirmation, teleport cleanup, newer ownership and watchdog recovery. They do not prove behavior in the live game or undo requests already sent.

## AF-04 (P2): stale profile response restores logged-in UI after logout

The token stayed cleared but a late profile JSON body restored user/status. Auth requests now capture token plus a local generation. Init/exchange/profile/key responses verify that ticket after body parsing and refresh. Logout, cross-tab logout and local account deletion invalidate it. Profile and key paths use an eight-second request timeout. The profile menu clears revealed key/confirmation and closes on guest state; stale key actions do not reveal or toast a returned key.

Eight VM scenarios run the actual service: held refresh during logout POST, local deletion/same token reuse, cross-tab logout, initial me/exchange races, both key response phases and ordinary success. This is a UI state fix; the reproduction did not restore server access.

## Gates still open

Owner game/telemetry checks of 4.3.83; ordinary daily retention after ledger activation; complete UTC-day D1/account usage; targeted independent review. Public registration remains restricted.
