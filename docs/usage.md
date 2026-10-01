# Usage evidence

Aggregated from the production D1 database on 2026-09-30 at approximately 05:29 UTC:

| Measure | Value | Definition |
| --- | ---: | --- |
| Observed Roblox IDs | 2,282 | Distinct non-null Roblox user IDs in `analytics_sessions`. |
| Recorded sessions | 4,192 | Rows in `analytics_sessions`; used as an approximate launch count. |
| Repeated Roblox IDs | 696 | Roblox user IDs with at least two session rows. |
| Peak concurrent sessions | 25 | Maximum `peak_script_sessions` in `analytics_peaks`. |
| Dashboard-linked sessions | 80 | Session rows that had a successful dashboard-key association at least once. |
| Dashboard-linked Roblox IDs | 12 | Distinct IDs among those linked session rows. |

These observations predate the Aroyn rename and belong to the same product formerly called Veyra. They are product usage metrics, not GitHub repository metrics. Publish only the aggregates and methodology, never raw IDs or session rows.

The read-only aggregation used these definitions:

```sql
SELECT COUNT(DISTINCT roblox_user_id) FROM analytics_sessions;
SELECT COUNT(*) FROM analytics_sessions;
SELECT COUNT(*) FROM (
  SELECT roblox_user_id FROM analytics_sessions
  WHERE roblox_user_id IS NOT NULL
  GROUP BY roblox_user_id HAVING COUNT(*) >= 2
);
SELECT MAX(peak_script_sessions) FROM analytics_peaks;
SELECT COUNT(*) FROM analytics_sessions WHERE dashboard_linked = 1;
SELECT COUNT(DISTINCT roblox_user_id)
FROM analytics_sessions WHERE dashboard_linked = 1;
```

The values are a snapshot and can change as sessions continue. Presence ingestion currently accepts anonymous client reports, so the full-population figures are observed telemetry records, not independently verified people, launches, or concurrent clients. `dashboard_linked` is set by the Worker after a valid dashboard-key association and remains set for that session; the API accepts a client-supplied Roblox ID, so this marker does not verify Roblox account ownership or a unique human. Treat these figures as directional product evidence until anti-abuse controls and their effect on measurement are assessed.
