# Reproducible checks

Use Node.js 24 and run from the repository root:

```sh
npm ci --ignore-scripts
npm test
```

The six suites run sequentially and fail the process on a failed assertion:

| Suite | Checks | Scope |
| --- | ---: | --- |
| web-check | 10 | Launch command, Clipboard refusal/success, strict health response/timeout, external URL allowlists, storage migration/reset, JavaScript parsing |
| check | 9 | Mock OAuth, key/link/snapshot round trip and runtime/dashboard relay |
| security-check | 29 | Concurrent credential changes, input bounds, revoked access, rate controls and owner/non-owner authorization |
| data-check | 9 | Scoped export/deletion/retry and retention |
| snapshot-race-check | 8 | Serialized expiry/replacement races, including twelve real Miniflare runs |
| access-check | 20 | Restricted account access, allowlist changes and initial-link ordering |

The Miniflare harness refuses non-mock mode and replaces external Discord/Roblox calls with synthetic responses. Each backend suite has a fresh D1/R2 store. The tests never load private credentials. Result JSON files are ignored by Git. The pinned prerelease Miniflare version uses its V4 options converter; update the harness alongside any dependency upgrade.

Local synthetic results are not evidence of real OAuth behavior, all Cloudflare topology/hibernation cases, large loads, every Roblox environment, or legal/WCAG compliance. Separate cloud/user observations and remaining gates are in [STATUS.md](../STATUS.md).

GitHub Actions is configured for Linux with the same Node/npm commands, a read-only repository token and a ten-minute timeout. A clean Windows installation passed locally; inspect the actual Actions run before claiming remote CI passed.
