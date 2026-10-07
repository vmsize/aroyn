# Custom domain: aroyn.xyz

The domain is attached to the existing `aroyn-staging` Pages project. Both origins serve the same deployment. No database or account migration is performed. Login with the same Discord identity retrieves existing dashboard links, data and admin access. Browser sessions are origin-specific, so first access on aroyn.xyz requires login.

API `SITE_ORIGIN`: `https://aroyn.xyz`.
API and live `ALLOWED_ORIGIN`: `https://aroyn.xyz,https://aroyn-staging.pages.dev`.
Discord callback stays on the existing API Worker: `/api/v2/auth/discord/callback`. The callback sends the exchange code to the custom-domain dashboard or admin path requested at login. Script API/live endpoints stay unchanged.

The stable loader on both domains uses aroyn.xyz for the manifest and immutable release downloads. Existing saved Pages launch commands remain usable. New website/client copy buttons use `https://aroyn.xyz/scripts/loader.luau` and `https://aroyn.xyz/`.

Worker environment updates preserve existing code bytes, bindings, secrets, D1 IDs, DO namespace IDs and bucket names. No schema migration or retention changes. Deployment verification must compare these against the saved baseline, check both origins' CORS, static dashboard/admin routes, and API/live/bot health. An actual new-domain Discord login is the final user check.

Rollback: restore only the previous origin variables and the prior Pages deployment. Do not recreate services or databases.
