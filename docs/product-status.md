# Current product and source status

Verified on **2026-10-12**. Mutable hosted pointers can change independently of source publication.

| Product | Hosted state | Source boundary |
|---|---|---|
| Main site / Dashboard | https://aroyn.xyz/ and guest Dashboard | Older homepage snapshot; most Dashboard assets match the newer frozen frontend |
| Hub | Public manifest selects **4.3.96** | Authentic modular source/build/tests in `clients/greedy-growers/`; immutable releases retained in `apps/dashboard/releases/` |
| UI Library | Stable **v0.1.0** | Independent source/adapter/build/examples/tests in `libraries/ui/`; exact Stable bundle retained |
| Documentation | Public Hub/UI documentation | New site generator/content/screenshots remain a separate source project |
| API / Live | Hosted account and telemetry services | Public Workers source; deployment secrets, bindings and user data excluded; live backend byte parity not re-audited here |

Both current Luau source projects reproduce their published immutable artifacts exactly. Hub: **836402 bytes**, SHA256 `f72f5bc0180c7fc9c7b92027f4a24a3adcbbc68713ae2fe44973b6974b1cf97e`. UI: **232227 bytes**, SHA256 `afc4a8ff0f91e64ef4d99fc60e4a23b5c9e33e407051d40a37328c4c8c70689a`. [Provenance](source-provenance.md) and [build/test instructions](testing.md) record their boundaries.

Hub retains internal RC/Phase metadata and the historical unpublished-candidate banner to preserve approved bytes. Actual hosting and manifest selection establish its public state. Owner-reported native approval covers Windows/Potassium and Android/Delta for these exact Hub bytes; standalone UI approval remains Windows PC/Potassium. Final normal-loader smoke after Hub activation was pending in the historical activation report. This source-publication phase does not claim another native test.

Hub startup/profile restore keeps gameplay automation off; Dashboard is optional. Its bounded mobile asset adapter is not part of standalone v0.1.0 compatibility. Software uses MIT with separate brand terms; unresolved legacy strip provenance is retained as a historical notice, not attributed to the new project-authored atlases.

Source publication does not deploy frontend/backend, change public loader selection or grant production access. A complete coordinated self-hosting launcher and synchronization of the latest homepage/documentation generator remain follow-up work. Historical status entries are retained in [STATUS.md](../STATUS.md).
