# Dashboard keyboard, focus, contrast and retained records — 2026-10-02

AR-07: account choices are native buttons, with separate remove buttons. Opening focuses the selected account; arrows, Home and End move among choices. Escape returns focus to the trigger. Empty lists remain labelled and dismissible.

AR-08: settings, profile and account panels start inert and hidden from the accessibility tree. Opening moves focus inside; closing returns it when needed. Moving focus outside dismisses a panel without stealing focus. Telemetry and account rerenders preserve the focused action. Destructive confirmations initially focus Cancel and reset when reopened.

AR-09: dedicated log text colors preserve status marker colors. Numeric checks cover all five levels against normal and hovered backgrounds in light and dark themes, with a minimum 4.5:1 contrast ratio.

AR-11: owner statistics and directory labels describe retained records, rather than asserting lifetime totals or every user ever seen. Existing payload fields and retention periods are unchanged.

The full local gate passed 18 suites / 205 groups. A final small account confirmation reset was followed by a successful rerun of the twelve focused groups. LinkeDOM tests run actual components with an explicit focus-event model, not a full browser or screen reader. See [evidence](local-accessibility-gate-2026-10-02.json). These results do not establish full accessibility compliance.

The owner confirmed the previous Discord login correction works. This frontend batch does not change the API/live backend, Luau client or registration access. AR-10 delayed Luau cancellation, deferred full UTC-day D1 usage, the next ordinary daily cleanup and targeted independent review remain open.

Cloud bundles must be prepared with tools/prepare-dashboard.mjs and explicit staging endpoints; repository config.js remains local preview configuration.

## Publication and restricted staging

Code commit `03983c4183166dc361dca7301cb86d3c866698aa` passed hosted CI: 18 suites / 205 groups. Pages b71b7ef5-e33a-4b5f-b22e-da480a7d596e serves the prepared cloud configuration. Eleven assets matched bytes, three backend health/guest checks passed, and actual hosted login construction plus the Discord OAuth callback passed. Public source and ZIP were verified for 173 files before this rollout evidence was added. No API/live or Luau deployment was performed. Real keyboard/menu/theme verification by the owner remains pending. See [rollout evidence](dashboard-accessibility-rollout-2026-10-02.json).
