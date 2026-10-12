# Aroyn UI Library — Stable 0.1.0

A reusable native Roblox UI library: windows, pages/sections, typed controls, overlays, theme values and named configurations. It contains **no Greedy Growers controller, Dashboard connection or gameplay automation**.

This source package reproduces the existing [Stable distribution](https://lib.aroyn.xyz/stable/0.1.0/Aroyn.lua). It does not publish a new release, change the public API or upgrade its executor support.

## Layout

- `src/Aroyn.luau`: authentic complete UI core, including motion, configuration and lifecycle. It was authored as one module; internal classes have not been artificially split.
- `src/Assets.luau`: generic embedded PNG/file/custom-asset adapter.
- `src/Entry.luau`: deterministic composition template, returning the API without creating a window.
- `assets/`: permitted brand mark and project-authored seven-cell atlas; generator in `tools/`.
- `examples/`: minimal file-loading demo and reusable basic/showcase/configuration factories.
- `tests/`: existing component/config/motion/overlay and distribution regressions with explicit Roblox doubles.
- `releases/0.1.0/`: exact readable immutable code and its published manifest, retained once as a reference.

## Install and create a window

Read the pinned source first. In an environment with `loadstring` and compatible HTTP/custom-asset support:

```luau
local Aroyn = assert(loadstring(game:HttpGet("https://lib.aroyn.xyz/stable/0.1.0/Aroyn.lua")))()
local parent = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local window = Aroyn:CreateWindow({Parent=parent, Id="my-window", Title="AROYN", Logo=Aroyn.Logo})
local page = window:CreatePage({Name="General", Icon="components"})
local section = page:CreateSection({Title="Preferences"})
section:CreateToggle({Name="Enabled", Default=false, Callback=function(value) print(value) end})
-- When the application finishes: window:Destroy()
```

For local file loading, copy the built code to `AroynUI/Aroyn.lua`; use [examples/minimal.luau](examples/minimal.luau). `basic.factory.luau` and `showcase.factory.luau` accept the API and parent. No downloaded demo or test starts game automation.

The core can be placed in a Studio ModuleScript, but that path is not certified by native testing here. The public distribution image adapter requires executor file/custom-asset APIs; callers without them must provide usable image URIs or accept empty slots. `pcall` catches errors, not indefinite API yields. Registration Ready is not a visual approval.

## Configuration and cleanup

`Config={Namespace="my-app",AutoLoad=false,AutoSave=false}` opts a window into named configuration management. Components use flags, for example `Flag="enabled"`; use `SaveConfig("main")`, `LoadConfig("main")`, `ResetConfig()` and `Destroy()` as in [configuration.factory.luau](examples/configuration.factory.luau).

Library AutoSave/AutoLoad are opt-in; restoration is silent by default and does not start gameplay. Supported file APIs give File mode; otherwise values are session-only. The existing `AroynUILab/configs/<Namespace>` path is a persisted compatibility namespace, not a dependency on a private development folder. Applications clean up their own external connections; `Destroy()` cleans owned GUI/listeners/tweens/popups/launcher.

The same owned Parent/Id replaces a prior library window, not unrelated GUI. Minimize/restore, dialogs, notifications and popup behavior are the unchanged v0.1.0 implementation. [Full API docs](https://docs.aroyn.xyz/ui/) cover actual defaults/types and supported methods.

## Reproduce and test

From repository root, use Node.js 24 and Python 3.12+:

```sh
python libraries/ui/tools/build.py --output .build/ui-0.1.0
python libraries/ui/tests/run.py
```

Output must be empty. The builder uses checked-in source/assets and the existing public tool downloader for official **Luau 0.740**, with pinned Windows/Linux/macOS ZIP hashes. No npm installation is needed for this component gate; Node, Python and platform extraction tools (PowerShell or unzip) are needed. First CLI acquisition needs network access. `LUAU_BIN_DIR` is an explicit developer override containing `luau` and `luau-compile`; results using an override are not the pinned-tool gate.

Expected `Aroyn.lua`: **232227 bytes**, SHA256:

```text
afc4a8ff0f91e64ef4d99fc60e4a23b5c9e33e407051d40a37328c4c8c70689a
```

The generated showcase is compiled separately. Tests run real source and exact Stable code in deterministic doubles, including callbacks, typed values, config persistence, assets, popups, motion/reversal and cleanup. They do not certify native rendering or physical phone touch. CI runs the same checks without credentials or deployment steps.

Optional original atlas regeneration requires Pillow and an explicit empty output directory:

```sh
python libraries/ui/tools/generate_icons.py --output .build/ui-icons
```

This writes only generated files, never rewrites source. PNG compression can vary across Pillow versions; exact Stable reproduction uses the checked-in hash-locked assets rather than regenerating them.

## Support and releases

Initial independently documented native scope: **Windows PC / Potassium**. Android/Delta approval of the **Hub** does not approve this standalone adapter; other executors, mobile and Studio remain unverified. Local mocks and Linux CI are engineering evidence, not new native support.

Stable 0.1.0 is immutable. A changed runtime requires a separately approved version/artifact; these build tools only reproduce the existing release and never promote Latest, publish, or deploy. Source/tooling changes should preserve public API and recorded Stable hashes. See root [contributing](../../CONTRIBUTING.md) and [release verification](../../docs/release-verification.md).

## License

Original software and project-authored icon code: [MIT](LICENSE), copyright 2026 vmsize. The logo has separate [brand permissions](BRAND_NOTICE.md), retained in the bundle. Preserve notices and use your own branding for an independent product. Dependency/asset boundaries are in [THIRD_PARTY_NOTICES.md](../../THIRD_PARTY_NOTICES.md).
