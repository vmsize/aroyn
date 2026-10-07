# Mobile layout and pet feeding — 4.3.94

Run the existing saved loader again to receive the release. Already running clients are not replaced automatically. No API, live Worker, database migration or presence interval changes are needed.

## Mobile layout

When the full 1124 × 520 layout does not fit, the client reflows into one column. The six tabs scroll horizontally; pages, lists and popup contents scroll vertically. Fields and navigation remain readable rather than scaling the whole desktop panel down. Rotation, minimization and return to a larger viewport preserve the existing controls and their event connections. Dashboard linking remains in Session.

## Pets tab

- Auto Feed is disabled by default; enable it in Pets.
- Start feeding below defaults to 25%. Stop feeding at defaults to 80%. Feeding continues between these thresholds once it has started.
- Max fruit value defaults to 0, meaning no price cap. Set a positive value to limit what can be consumed.
- The most hungry eligible active pet is selected, and the cheapest usable fruit is chosen across inventory and mature fruit on the current own plot.
- Favorited inventory items, locked/waxed plot fruit, claimed/queued fruit and items with unknown or invalid values are excluded.
- A mature plot fruit is collected using the direct Auto Collect All Fruits prompt method, then equipped before feeding. This does not move the character or edit prompt properties. The client reads the game's shared growth duration; camera-dependent prompt visibility is not used as a maturity check.
- The confirmed counter increments only after server acceptance, observed inventory consumption and increased pet hunger. Replication delays and errors can leave an accepted action uncounted; the client does not invent a success.

Feed work uses the existing shared automation lock. Disable, off/on and Stop invalidate queued continuations before subsequent collection, equip or feed requests. Claim cleanup cannot overwrite a newer owner; feeding has no movement to restore. An already sent request cannot be recalled. A pending feed response blocks another feed request; failures pause retries for that pet.

Settings are saved with the existing preferences. Verification mode disables restored farming and suppresses settings writes. Finite validators reject NaN/infinite values and keep the stop threshold above the start threshold.

## Verification and limits

The `pet-feed-check` suite runs 29 scenarios using the actual release functions: filtering, ownership, maturity, hysteresis, value limits, server refusal, rejected Promise, errors, delayed response, missing inventory/consumption/hunger, cancellation at collection/equip/send/confirmation, generation changes and cleanup. It also compiles the complete outer and embedded chunks with the official Luau 0.740 CLI.

Two controlled feeding cycles in the owner's connected desktop executor succeeded during development: own-plot collection, equip, server acceptance, consumption and hunger growth. Both returned feeding to off. The final collection/confirmation functions were exercised after their protection fixes; a later claim-cleanup-only change has local cancellation coverage.

Actual GUI controls were inspected in the connected executor at emulated 320 × 568, 390 × 844, 844 × 390, 768 × 1024, 1024 × 768 and 1280 × 720 viewports. All six tabs had no horizontal control overflow. Popup scrolling, reachability of bottom settings, minimize/restore and desktop parent restoration passed. This is not a physical phone or universal executor compatibility test. Game service/data changes can require another client update.

## 4.3.92 direct collection correction

The actual new prepare function collected one Chestnut fruit in the connected game. Inventory arrival was confirmed, character displacement was 0, and the prompt remained disabled before and after invocation. Auto Feed remained off after the bounded test. All 36 local suites, including 29 pet scenarios and full outer/embedded compilation, passed for this release. The complete feed cycle and mobile layout evidence above belongs to 4.3.90; this correction did not reload the active farming client.

## 4.3.93 touch scrolling

Hide the full-body popup layer when no popup is open; opening, switching and closing popups update the layer visibility. Compact Pets delegates page scrolling to MobilePages and disables the redundant inner full-height scroller, preserving the pet list and restoring desktop properties. Regression checks exercise popup lifecycle and compact/desktop scrolling ownership. The user confirmed physical phone swipes after publication of 4.3.93.

## 4.3.94 Pets layout

Three compact setting cards sit side by side on wide screens, switching to labelled rows on narrow screens. Pet rows have hunger bars; list height follows the current count up to a scrolling limit. Page canvas height follows this layout and updates after pet-count changes and rotation. The prior touch-scroll fix is retained. Physical appearance on a phone still needs user confirmation for this release.

## 4.3.94 compact Buy Seeds

Mobile seed rows match Compost's 42-unit height. Price, priority and both direction buttons have explicit top anchors and fit inside each row. Per-seed activity remains visible on wide layouts and is hidden in the narrow row; Session activity and desktop details remain available. Desktop restoration is retained.
