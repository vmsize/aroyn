# Architecture and source boundaries

Aroyn has a game-specific Hub, a browser Dashboard, an account API, a live relay and a separate reusable UI library. They have independent publication and compatibility boundaries; [product status](product-status.md) records the current source and hosted coverage.

## Public source in this repository

- `apps/dashboard/`: static HTML/CSS/JavaScript. Discord auth, runtime reconstruction, account UI and route subscription lifecycles live in separate client modules. Local API/Live defaults are intentional; a cloud package must use the deployment-config preparation tool.
- `workers/api/src/worker.js`: Discord OAuth and account sessions, dashboard keys, scoped runtime HTTP routes and account-data operations. Mutations are serialized by `AroynRuntimeMutations`.
- `workers/live/src/index.js`: runtime/viewer WebSocket sessions and presence, implemented by `VeyraLiveSession` and `VeyraStatsHub`. D1/R2 and signing secrets are configured through bindings.
- `workers/shared/`: snapshot serialization, retention continuation, deletion ledger and shared lifecycle/access helpers. These protect cross-Worker invariants and must not be treated as unrelated utilities.
- `apps/dashboard/releases/`: immutable Hub artifacts through 4.3.96.
- `clients/greedy-growers/src/`: Aroyn core, GameUI, GreedyRuntime, Dashboard, Storage, Startup, Assets, BuildInfo and the already-embedded Bridge reference. The builder must not inject Bridge a second time.
- `libraries/ui/`: independent core, asset adapter, entry template, examples, tests and exact Stable v0.1.0 distribution. See [source provenance](source-provenance.md).

The root synthetic harness bundles the actual API/Live code into one Miniflare runtime with fresh stores and mocked external calls. This exercises cross-Worker coordination without production credentials; it is not a turnkey independent live OAuth deployment.

## Data and authorization

Discord sign-in establishes a web account session. A dashboard key links a running Hub session; detailed snapshots and viewer access are scoped to the corresponding account. Signed presence and live tokens support transport authorization/revocation, but an anonymously reported Roblox ID does not verify identity. CORS is a browser response policy, not authentication.

API and Live use a shared D1 database and runtime R2 bucket. A separate deletion-ledger bucket has independent recovery semantics; never restore it with ordinary payload backups or reinitialize an existing journal. Retention and larger account deletion continue through bounded steps/alarms. See [account data](account-data.md), [runtime mutations](runtime-mutations.md), [bounded retention](bounded-retention.md) and [deletion ledger](deletion-ledger.md).

## Independent UI Library

Stable v0.1.0 is a readable native Luau bundle with MIT software and separate brand terms. It supplies window/page/section/control, configuration and overlay behavior without gameplay controllers or backend telemetry. Its modular core, image adapter, stable rebuild tool, examples and mocked tests are published under `libraries/ui/`. This source package does not publish the private operational promotion archives or an automatic release/deployment mechanism.

Hub 4.3.96 embeds a related core plus Hub-only storage, dashboard, startup/mobile and gameplay adapters. API-name similarity does not establish byte-identical cores or transferable executor support. Contributions must preserve this separation and notices; the Hub adapter is not a standalone library API.

Production infrastructure, credentials, private archives and user records are outside this repository. Public source availability and HTTP health do not establish current deployed backend byte identity or production capacity.
