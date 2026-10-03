# Public beta launch — 2026-10-03

The owner explicitly authorized opening Aroyn general registration. The service
keeps its free existing URLs and client 4.3.86:

- Website: https://aroyn-staging.pages.dev/
- Dashboard: https://aroyn-staging.pages.dev/dashboard/
- Status: https://aroyn-staging.pages.dev/status/

```lua
loadstring(game:HttpGet("https://aroyn-staging.pages.dev/scripts/loader.luau"))()
```

## Deployment and verification

- API: `309dc47d-d62f-43ee-bf38-7364d969c34e`, 100% traffic.
- Live: `6e7f460a-4c4e-4548-b201-8becf599b3c9`, 100% traffic.
- Aroyn Pages: `496f94e7-fb4e-4247-9480-78f3c76f40e1`.
- Old Veyra Pages migration notice: `7e2ae80a-af6e-40a5-8b5f-31df39e76a4b`.

Only STAGING_ACCESS was removed from both Worker binding sets. Other settings,
secrets and resource identities were compared before/after and preserved;
DELETION_LEDGER_MODE remains required and the API cleanup Cron is still
`17 3 * * *`. Existing Durable Object namespaces were declared with their observed
SQLite storage type for the provider's settings API; no namespaces were reset,
renamed or deleted. Two rejected API requests were corrected before any settings
change was applied. The retained allowlist supports returning to restricted access.

Twenty-five published checks passed: fourteen asset byte comparisons (including
the loader, manifest and 4.3.86 client), two health checks, four private API guest
rejections, OAuth start redirect and four old-site paths showing the migration
page. The old-site deployment includes migration HTML at the prior page paths to
replace cached assets. No browser GUI control or game execution was performed
during launch. The first real Discord sign-in outside the former allowlist is
pending owner confirmation; it was not replaced with a synthetic cloud account.

The client bytes and runtime code were not changed by launch. Previously passed
30-suite CI and real-executor delivery evidence apply to 4.3.86. The owner has
since confirmed telemetry, account switching and no new Auto Compost feed after
switching it off. This does not establish capacity under widespread public use.

## Distribution and old service

The owner will create/update ScriptBlox listings after launch. Until then, the old
Veyra script/API/live service remain unchanged so the migration link cannot send
users back to an outdated launch command. A persistent, UI-only legacy script
notice has been prepared separately. Old Veyra data were not deleted or copied to
Aroyn. Old Pages preview deployments may still retain previous assets; the main
old site is the migration page.

## Operations and rollback

The site retains noindex for the initial beta; this is not access control. The
previous full-day D1 and ordinary-cleanup checks passed for restricted traffic.
Account-wide reads/writes and other Cloudflare resource quotas need observations
under new public traffic. There is no newly installed automatic quota monitor or
global quota circuit breaker. Paid plans were not enabled by this launch.

If rollback is needed, restore STAGING_ACCESS=restricted on API then live using
the retained allowlist, and verify excluded access/connection shutdown. Preserve
accounts, keys, resources and the deletion ledger; do not restore an old database.
The private prelaunch configuration and previous Pages deployment IDs are saved
locally for recovery and are not part of this public repository.
