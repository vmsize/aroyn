# Current Luau source and asset provenance

## Software inputs

`clients/greedy-growers/src/` contains the authentic approved 4.3.96 source snapshot, not modules reconstructed from the executable. The nine input names, exact byte sizes and SHA256 values are recorded in `clients/greedy-growers/release.json`. Bridge is a reference already embedded into GreedyRuntime, not an additional concatenation step. The portable builder preserves wrapper order, build metadata, historical banner and all runtime bytes. Output must equal the existing 836402-byte artifact and SHA256 `f72f5bc0180c7fc9c7b92027f4a24a3adcbbc68713ae2fe44973b6974b1cf97e`.

`libraries/ui/src/` contains the authentic standalone v0.1.0 core, Assets adapter and Entry template. The core is the header-logo hotfix source, distinct from the Hub's approved embedded core. The stable builder follows the original template/payload/license construction and reproduces 232227 bytes and SHA256 `afc4a8ff0f91e64ef4d99fc60e4a23b5c9e33e407051d40a37328c4c8c70689a`. Source fingerprints are in the component metadata; the original Stable manifest remains with the release.

The owner authorized publishing these current authored source projects under the existing repository MIT software grant. Frozen distribution comments are not rewritten to add headers or change Phase/Channel. This is source synchronization, not a new runtime release. Tests/support fixtures are actual project regression harnesses adapted only for portable paths, expected Stable metadata and explicit synthetic execution. Native execution is not simulated as approval.

## Images and generators

- The supplied transparent Aroyn mark has SHA256 `8b03a7b8c10780fd09c2fcf78253a2a071e6056834d87473e36612b1682e9633`. The same unchanged file is embedded in the Hub and standalone library. Its separate permissions and provenance limitations are in [BRAND_ASSETS.md](../BRAND_ASSETS.md); it is not relicensed as MIT software.
- Standalone `assets/navigation.png` is the project-authored seven-symbol atlas. `tools/generate_icons.py` retains its actual hand-authored drawing geometry. The Hub's `assets/navigation-before.png` is that same input atlas, extended by `tools/generate_navigation.py` with authored harvest, stats and gear symbols. The Hub grid and mobile crop payloads in Assets are these authored images, not the unknown historical client strip.
- Hub navigation grid SHA256: `31828921413eeff48c999721c151518158c1b82f33c9419377fdfd0167491535`. Embedded mobile crops have explicit hashes in `src/Assets.luau`. Generators write only to a requested empty output directory. Pillow compression/library changes can alter regenerated PNG bytes; exact releases use the checked-in/embedded byte-locked images. Inspect pixels and deliberate future metadata changes rather than replacing an immutable payload.
- Atlas generators and original symbol drawings are project software under MIT. They introduce no downloaded icon collection. The supplied mark stays under separate brand terms. No Roblox platform image served by asset ID is copied into this source package.

Earlier Hub releases retain the supplied legacy strip and its unresolved original attribution, as already disclosed in [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md). No old release or notice is deleted or rewritten. The new source packages do not reuse that strip; this publication does not claim to resolve its historical provenance or grant new independent asset rights.

## Boundaries

Build/test tools use relative component paths and checksum-pinned official Luau CLI downloads. No private manifests with local filesystem paths, native operational archives, credentials, telemetry or deployment outputs are published. Public service URLs in existing runtime source are necessary runtime configuration, not secrets. Example user IDs, HTTP bodies, keys and accounts in fixtures are synthetic test data. Dependency licenses remain applicable; downloaded tools and node_modules are excluded.
