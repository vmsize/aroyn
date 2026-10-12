# Contributing to Aroyn

Start with an issue describing the problem and affected component. Keep a contribution focused; a reproducible defect or a small documentation correction is more useful than an unrelated rewrite. Security reports belong in the private channel described in [SECURITY.md](SECURITY.md).

## First local check

Use Node.js 24. From the repository root:

```sh
npm ci --ignore-scripts
npm test
```

For the static preview, run `npm run dev` in `apps/dashboard` and open `http://127.0.0.1:4173`. Root tests use synthetic stores and mocked outbound services; no production credentials are needed. See [setup](docs/setup.md) and [testing](docs/testing.md) before configuring your own Workers.

## Choose the right boundary

| Area | Source | Important boundary |
|---|---|---|
| Frontend | `apps/dashboard/` | Keep local preview config local; validate auth races and navigation |
| API | `workers/api/` | Authorization, account keys and serialized runtime mutations |
| Live | `workers/live/` | Session/viewer isolation, reconnect and presence |
| Shared lifecycle | `workers/shared/` | Revocation, retention, deletion and recovery must remain coordinated |
| Historical Hub releases | `apps/dashboard/releases/` | Immutable; fix a maintained source and prepare a separately approved future artifact |
| Hub | `clients/greedy-growers/` | Separate runtime, UI, storage, Dashboard and startup modules; exact frozen rebuild |
| Standalone UI | `libraries/ui/` | Reusable core and asset adapter; no gameplay or Dashboard logic |

Current Hub 4.3.96 and UI v0.1.0 sources reproduce their hosted immutable artifacts. The newer hosted homepage and documentation generator remain separate snapshots. Identify the source/version you changed instead of assuming local GitHub main is production. [Product status](docs/product-status.md) records the distinction.

For a Luau contribution, run the component build and tests described in its README. Do not edit `releases/0.1.0/` or historical Hub release files: changes belong in authored source and a separately reviewed future release. Preserve the v0.1.0 public API unless a change is explicitly agreed. Use project-authored or independently licensed assets and include provenance. Mark byte-identity failures honestly; a changed future build must not be represented as the old release.

## Pull request checklist

- Target `main` in your fork; describe the defect, approach and affected boundaries.
- Include reproduction, before/after behavior and commands actually run, with environment and results.
- Add a meaningful regression for a behavior fix; use synthetic IDs and stores. Do not rewrite historical evidence to make an old test look current.
- Mark checks you could not perform as SKIP. Mocks, browser emulation, cloud fixtures and native owner testing are different evidence.
- Keep docs and current status accurate. Preserve historical releases, dates, checksums and third-party attribution.
- Do not include `.dev.vars`, credential-bearing configs, user records, dashboard keys, cookies, logs from real accounts or deployment archives.
- A PR is not authorization to deploy, alter production storage, change DNS/OAuth, activate Latest or update the public loader.

Original software contributions use the repository's MIT license. Preserve the separate brand-asset permissions and dependency notices. New assets need their own provenance and redistribution review.
