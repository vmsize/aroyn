# Independent recheck corrections — 2026-10-03

The independent review confirmed two P2 residual findings and one P3 secret-DOM finding on the 4.3.83 baseline. This correction addresses all three. No server, billing, access-list or account data changes are included.

## IR-01: invalidate replaced cross-tab sessions

Auth now invalidates pending operations when the current storage session is replaced, removed or cleared, including a pending exchange that has no token yet. Both canonical and legacy session keys are supported. Stale queued events and foreign sessionStorage events are ignored. A replacement session is preserved in shared storage; the current page becomes guest and the dashboard shell reloads to read the new session. The owner analytics page drops its gate and private rows. Late profile, exchange and key JSON cannot revive the former state. Ordinary refresh with the same nonempty token remains valid. This correction changes frontend state fencing, not server credentials or account permissions.

## IR-02: Compost prompt errors cannot begin a cancelled fallback

Client 4.3.84 rechecks the action token after either yielding fireproximityprompt attempt and before each fallback begins. Disable, off/on or Stop prevents the stale continuation from starting InputHoldBegin or keypress. An already attempted hold/keypress is paired with a separate InputHoldEnd/keyrelease cleanup even if its operation or wait errors. Previously accepted game requests cannot be recalled. The prompt and keyboard APIs are existing compatibility fallbacks; no new interaction method is added.

## IR-03: clear revealed keys from closed panels

Guest transitions and changes of user/session clear the revealed key, reset replacement confirmation and rebuild the account panel even when it is hidden. Ordinary same-identity refresh retains the freshly generated key so it can still be copied. The key is removed from the panel DOM rather than merely hidden; an earlier copy or a server-issued key is not revoked by this UI cleanup.

## Verification and publication

The isolated full gate passed 28 suites. Three new suites exercised 57 focused scenarios against actual auth/account modules and actual Luau prompt/token functions. The manifest notice text was then corrected and the loader/update/GUI suite rerun. Full outer and embedded Luau chunks compile. Immutable 4.3.80–4.3.83 clients and the stable loader remain byte-identical. See [local evidence](local-independent-recheck-fixes-2026-10-03.json) and [4.3.84 bytes](release-4.3.84.json). Restricted staging publication is pending until its rollout record is present.

The ordinary daily maintenance cycle and the full UTC-day D1 usage gate were observed on 2026-10-03; see [operational gate evidence](operational-gates-2026-10-03.json). Their limits do not establish public-scale capacity. The reviewer did not establish new P0/P1 findings in the covered scope. A broad audit of every possible executor or all product behavior is not claimed.

## Owner smoke check

1. In two dashboard tabs, sign out in one. The other must stop displaying the previous account and a revealed key must disappear. Sign in again; refresh both tabs and confirm the correct profile. Do not share keys in screenshots.
2. Rerun the saved versionless loader to obtain 4.3.84. Confirm telemetry, then disable Compost during movement/wait, try off/on, and Stop. Old work must stop; a new enabled cycle must still work. A synthetic prompt-error case was covered locally; reproducing a real executor failure is not required for this smoke check.

These manual checks require owner control or explicit new permission for computer control. General registration remains restricted. New 4.3.84 owner checks are pending.
