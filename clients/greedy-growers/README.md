# Aroyn Hub — Greedy Growers 4.3.96 source

This is the authentic source project for the immutable owner-approved [4.3.96 executable](https://aroyn.xyz/releases/4.3.96/greedy-growers.luau). It has the custom UI, eight navigation pages, mobile adapters, preference AutoSave, profile recovery, Dashboard reconnection and startup morph.

## Source boundaries

| Module | Responsibility |
|---|---|
| `src/Aroyn.luau` | Approved UI core embedded by Hub; independent standalone distribution has its own byte-locked variant |
| `src/GameUI.luau` | Game-specific pages, bindings, responsive sidebar and UI synchronization |
| `src/GreedyRuntime.luau` | Existing gameplay/runtime controllers and embedded integration bridge |
| `src/Bridge.luau` | Authored bridge reference already inserted in GreedyRuntime; do not inject it a second time |
| `src/Dashboard.luau` | Confirmed connection intent, retries, cancellation and transport lifecycle |
| `src/Storage.luau` | Hub preferences, verified file writes and recovery copies |
| `src/Startup.luau` | Real seven-stage initialization and one-window transition/error cleanup |
| `src/Assets.luau` | Bounded Hub asset preparation, mobile PNG fallbacks and project atlas |
| `src/BuildInfo.luau`, `release.json` | Exact authoritative metadata/order/checksums |

The complete readable executable is retained **once** at `apps/dashboard/releases/4.3.96/greedy-growers.luau`, following existing release conventions. Source modules are original build inputs, not reconstructed from guesses or renamed public APIs.

## Exact-byte build

From repository root, Node.js 24 and Python 3.12+:

```sh
python clients/greedy-growers/tools/build.py --output .build/hub-4.3.96
python clients/greedy-growers/tests/run.py
```

The output must be empty. The build checks all source fingerprints, preserves source order/LF/metadata and verifies exact bytes against the immutable reference before compile. It uses the portable [Luau CLI helper](../../tools/luau_cli.py), which wraps the repository's checksum-pinned official Luau 0.740 acquisition. PowerShell/unzip is needed to extract the first download. An explicit `LUAU_BIN_DIR` override is documented developer tooling, not the pinned CI gate.

Expected output: **836402 bytes**, SHA256:

```text
f72f5bc0180c7fc9c7b92027f4a24a3adcbbc68713ae2fe44973b6974b1cf97e
```

The old “candidate; NOT published” banner and internal RC/phase metadata remain exactly as approved; they do not describe current HTTP availability. Never edit them, add a license banner or alter automation merely to make the frozen release look newer.

## Tests and evidence

Portable tests use genuine inherited integration/startup/config/asset/mobile/responsive cases and deterministic Roblox doubles. They exercise actual modules and the full bundle without a real game or production credentials. The historical native-verification metadata fixture is used only in memory to test isolated lifecycle; it is not another published release. Root backend tests remain independently runnable with `npm ci --ignore-scripts` and `npm test`.

The owner confirmed the exact public artifact on **Windows/Potassium and Android/Delta**. New local mocks/Linux CI do not reproduce that native observation or approve all executors/devices. The normal loader selects the live manifest version; source publication does not activate or deploy anything.

## Service and configuration boundaries

The frozen runtime contains already-public Aroyn service origins required by the exact executable. They are not private bindings or credentials. No production resource configs, account keys, `.dev.vars`, private telemetry or operational archives are supplied.

Automation starts off and remains off on profile restore. Dashboard linking is in Settings; saved reconnect intent is separate from credentials/preferences. Explicit Disconnect/Unlink differs from normal teardown. Legacy 4.3.95 downgrade can restore automation ON, and new profiles are not automatically migrated backwards.

The source is reusable under the repository's MIT grant with separate supplied-mark terms. Current navigation assets trace to the project-authored UI atlas/generator; the older unresolved supplied strip remains only in unchanged historical releases. See [asset provenance](../../docs/source-provenance.md) and [notices](../../THIRD_PARTY_NOTICES.md). Optional atlas regeneration needs Pillow and writes only to `--output`; exact runtime reproduction uses the original embedded assets.
