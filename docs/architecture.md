# Architecture

`apps/dashboard` is the Pages frontend. `workers/api` handles account and dashboard API routes and binds to D1 and R2. `workers/live` handles live sessions and telemetry; it binds to the same D1 and R2 resources and two Durable Objects. Production secrets are supplied through Cloudflare bindings and are not included in this draft.

The Roblox client sends telemetry to the backend. The client itself is outside this review package pending version, ownership, and disclosure review.
