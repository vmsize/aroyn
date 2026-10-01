-- Bounded retention selects expiry batches through timestamp indexes.
CREATE INDEX IF NOT EXISTS idx_analytics_sessions_retention ON analytics_sessions(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_runtime_owners_retention ON runtime_session_owners(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_live_presence_retention ON live_presence(last_seen_at);
CREATE INDEX IF NOT EXISTS idx_roblox_profile_retention ON roblox_profile_cache(updated_at);
