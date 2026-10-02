# Dashboard stability correction — 2026-10-02

AR-04: snapshot and live-token requests carry authentication generation, selected ID and selection revision. Switching cancels outstanding requests and starts the selected account's snapshot immediately. Responses are checked after JSON reading, including identity matching; an old finally block cannot release a newer request. Account discovery checks the current authentication after reading and preserves the latest valid selection.

AR-05: the initial account lookup error completes hydration with an error state and starts retries. Requests, including body reads, have an eight-second timeout. Repeated initial failures use delays of 6, 12, 24 and 30 seconds, capped at 30 seconds; hidden pages poll no faster than 30 seconds. Logout cancels requests and retries. Polling epochs prevent an older in-progress tick from recreating a second timer.

AR-06: dashboard route pages use scoped runtime/auth subscriptions. Before replacing the main content, the router disposes the current page; subscription callbacks and the runtime page's pending authentication callback then become inactive. Shell subscriptions retain their document lifetime. DOM-local handlers are released with the discarded nodes.

The local gate passed 16 suites / 189 groups, including 15 targeted dashboard regressions: delayed fetch/body, rapid A → B → A switches, logout, timeout and recovery, late token failure, wrong identity, bounded retry delays, duplicate timers, and repeated actual Modules-page mounts. See [local evidence](local-dashboard-stability-gate-2026-10-02.json). Tests use synthetic data and do not prove real-browser interaction. The API/live backend and Luau client were not modified by this frontend batch. General access remains restricted.
