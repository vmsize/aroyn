-- Optional client-reported executor diagnostics; existing rows remain unknown.
-- Apply before deploying the live Worker that reads these columns.
ALTER TABLE analytics_sessions ADD COLUMN executor_name TEXT;
ALTER TABLE analytics_sessions ADD COLUMN executor_version TEXT;
