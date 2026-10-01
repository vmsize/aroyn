# Aroyn

Aroyn (formerly Veyra) is a web dashboard for Roblox runtime telemetry, backed by Cloudflare Pages and Workers. This repository contains the static website, backend source and the Aroyn Hub 4.3.80 client release. Original project code is licensed under MIT, with attribution to vmsize. The supplied mark has separate permissions for source redistribution and truthful references to Aroyn. See [brand assets](BRAND_ASSETS.md) for scope and provenance. Third-party components retain their own licenses; see [notices](THIRD_PARTY_NOTICES.md).

Some technical service and class names still use `Veyra` for compatibility.

## Included

- `apps/dashboard`: static site recovered from the latest located Pages deployment archive, v1.52, then updated locally with Aroyn branding, illustrative dashboard imagery, an independent Canvas ASCII background and the Portal CTA.
- `workers/api`: API Worker imported from Cloudflare on 2026-09-30, then hardened locally with bounded JSON, atomic login/key handling, rate controls, account export/deletion and daily retention.
- `workers/live`: editable live source compared with the deployed bundle before local changes, now with signed presence tokens, revocable live access, scoped cleanup and rate controls. First anonymous reports remain unverified. See [backend review](docs/security-review.md).
- `workers/shared`: account data lifecycle helpers used by both Workers.
- `apps/dashboard/releases/4.3.80`: readable Greedy Growers client; `scripts/loader.luau` downloads this fixed release.
- `apps/dashboard/status` and `admin`: public HTTP availability checks and a server-authorized private owner interface.
- `tests`: synthetic backend, lifecycle, access and browser-component checks; GitHub Actions runs `npm ci` and `npm test`.
- `docs`: architecture, usage methodology, data lifecycle and release review notes.

Obfuscated bundles, the status bot, runtime data, credentials, actual allowlists and deployment archives are outside this repository. Embedded client assets follow THIRD_PARTY_NOTICES.md and BRAND_ASSETS.md.

## Preview the dashboard

Install Node.js, then from `apps/dashboard` run `npm run dev` and open `http://127.0.0.1:4173`. No package install is needed for this static preview. Its default API and live endpoints point to local ports 8787 and 8788, so the preview does not call production services. Edit `assets/js/core/config.js` to point to your own Workers.

The home page and the dashboard sign-in screens can be viewed without backend setup. The home-page screenshot contains illustrative data. All dashboard sections require sign-in; account sign-in, live statistics, and runtime data need your own API and live Workers plus the services described below.

For the existing product flow, see the [user guide](docs/user-guide.md) ([Русский](docs/user-guide.ru.md)).

## Run your own backend

Each Worker has a `wrangler.example.jsonc`. Copy it to `wrangler.jsonc`, substitute your own D1 database ID, R2 bucket name, site origin, and Discord OAuth values, then install dependencies with `npm install` in that Worker's directory. Put secret values in `.dev.vars` locally; its `.example` file lists the required names. Do not commit `.dev.vars` or production values.

Run `npm run dev -- --port 8787 --persist-to ../../.wrangler/local-shared` inside `workers/api` and `npm run dev -- --port 8788 --persist-to ../../.wrangler/local-shared` inside `workers/live` to start local Workers on the ports expected by the dashboard with a shared local data directory. Apply the schema migration to that same directory first, as described in [setup](docs/setup.md). Adjust `apps/dashboard/assets/js/core/config.js` if you choose different ports. The API needs Discord OAuth for sign-in. The live Worker uses Durable Objects, D1, and R2.

## Status

The site is a static HTML/CSS/JavaScript deployment package; it does not include its original build process. The API import contains a Worker script and a small package file. The live Worker uses its local source. Configuration examples use placeholders and are not ready for deployment as-is.

Local security, integration and data lifecycle checks passed on isolated synthetic data. A separate restricted HTTPS/WSS staging deployment was tested with its owner: Discord sign-in, live updates, export/deletion, reconnection and key revocation. An isolated cloud Cron test passed 17 retention/concurrency checks using a fixture clock. The profile menu provides **Account data** for export and deletion; retention is 30 days for history and 7 days for snapshots without updates. See [account data](docs/account-data.md) for setup, scope and concurrency limits.

This is an initial source publication. General registration is still restricted. Larger-scale lifecycle testing and final provider/privacy review remain before wider service access. See [release status](STATUS.md). The [usage evidence](docs/usage.md) contains aggregate figures and their definitions.

## Current restricted test and client

- [Website](https://aroyn-staging.pages.dev/) · [Service status](https://aroyn-staging.pages.dev/status/)
- [Owner analytics](https://aroyn-staging.pages.dev/admin/): private data requires the configured owner account; a public HTML route grants no data access.
- The homepage copies the published launch command. It does not execute code in the browser. The script can run independently; dashboard data access remains restricted to invited accounts.

See [client release](docs/client-release.md) for saved-setting migration, compatible endpoints, hashes and test scope. No custom domain is required. For a fork, update the loader base and client endpoints before advertising your own launch command.

## Run synthetic checks

From the repository root, with Node.js 24: `npm ci --ignore-scripts` then `npm test`. External Discord/Roblox responses are mocked and each backend suite uses a fresh synthetic D1/R2 store. No real credentials or Cloudflare account are needed. Tests write ignored result JSON files under `tests/`. See [testing](docs/testing.md) for the limits of local evidence.
