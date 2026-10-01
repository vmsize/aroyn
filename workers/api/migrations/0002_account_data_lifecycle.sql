-- New session ownership is explicit; do not infer old history from claimed Roblox IDs.
CREATE TABLE IF NOT EXISTS runtime_session_owners (
  session_id TEXT PRIMARY KEY,
  veyra_user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  roblox_user_id TEXT NOT NULL,
  first_linked_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_runtime_session_owner ON runtime_session_owners(veyra_user_id, session_id);
CREATE TABLE IF NOT EXISTS account_deletions (
  user_id TEXT PRIMARY KEY,
  requested_at INTEGER NOT NULL,
  legacy_key_hash TEXT
);
