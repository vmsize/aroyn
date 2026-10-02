# Privacy notice and code consistency — 2026-10-02

This is a targeted source/notice comparison, not a legal assessment or complete independent security review. Ordinary full-day D1 consumption was deferred by the owner; the last partial-day measurement remains the only current cost evidence. Daily cleanup completion is still unobserved. Neither item was marked passed.

| Topic | Source evidence | Notice/check outcome |
|---|---|---|
| Discord identity | API OAuth requests `identify`; profile upsert stores ID, username, display name, avatar reference and timestamps | Described; no request for email, server list or messages found in this flow |
| Authorization | Profile serialization/export select public fields; secret hashes/suffix and expiry support access and revocation | Notice now distinguishes excluded server authorization credential records from preserved runtime snapshot contents |
| Connection IP | API request limiter uses `CF-Connecting-IP` with route; reviewed D1 schema has no dedicated IP column | RU/EN notice now explicitly describes this protection use; no promise that the hosting provider keeps no IP logs |
| Runtime export | Account-scoped v2/v3 objects and attributed SQL history are streamed; legacy v1/unattributed matching-ID history excluded | Scope described; snapshots export their stored contents, so callers must not send secrets inside them |
| Retention | shared data lifecycle: history30days, snapshots7days, web sessions30days; runner: presence15minutes, profile cache30days | Notice durations match configured code; successful bounded cleanup can occur after the expiry instant |
| Deletion | Recent15minute session, exact DELETE; independent intent before DB revocation; pending job retries; scoped removal | Notice distinguishes pending/completed removal and permits later new empty profile |
| Journal | Dedicated ledger35days, minimal internalID/request time, required mode activated on restricted staging | Account-data documentation corrected from activation-pending to active; original coverage must not be reinitialized |
| Browser storage | Auth service/storage migration, current-session signout and local account-data clearing | Cookie/storage notice describes legacy prefixes, temporary OAuth cookies and local-only effects |

Only two deployed privacy HTML pages changed; the remaining 64 deployment assets matched their previous hashes. No API/live code, credentials, access list or database records were changed. Ten existing local web checks passed; they check clipboard, health, URL validation, storage migration and JavaScript syntax, not the legal accuracy of these notices.

Remaining: independently reachable private contact, intended-jurisdiction and teenage-audience review, actual provider logging/backups settings, ordinary cleanup observation and final whole-project Astra review. The owner selected Discord septave; unfamiliar-user friend-request reachability is assumed by the owner but not yet tested. An additional contact is deferred. This report does not authorize messages, broader registration or physical-PC control.
