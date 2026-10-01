-- Initial D1 schema snapshot from read-only sqlite_master query, 2026-09-30.
-- No production rows or secret values are included.
-- Compatibility field names retain Veyra until client and API migration.

-- table: analytics_peaks
CREATE TABLE IF NOT EXISTS analytics_peaks (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        peak_script_sessions INTEGER NOT NULL DEFAULT 0,
        peak_script_sessions_at INTEGER,
        peak_script_users INTEGER NOT NULL DEFAULT 0,
        peak_script_users_at INTEGER,
        peak_dashboard_sessions INTEGER NOT NULL DEFAULT 0,
        peak_dashboard_sessions_at INTEGER,
        peak_dashboard_users INTEGER NOT NULL DEFAULT 0,
        peak_dashboard_users_at INTEGER
      );

-- table: analytics_samples
CREATE TABLE IF NOT EXISTS analytics_samples (
        bucket_start INTEGER PRIMARY KEY,
        sample_count INTEGER NOT NULL DEFAULT 0,
        max_script_sessions INTEGER NOT NULL DEFAULT 0,
        max_script_users INTEGER NOT NULL DEFAULT 0,
        max_dashboard_sessions INTEGER NOT NULL DEFAULT 0,
        max_dashboard_users INTEGER NOT NULL DEFAULT 0,
        last_script_sessions INTEGER NOT NULL DEFAULT 0,
        last_script_users INTEGER NOT NULL DEFAULT 0,
        last_dashboard_sessions INTEGER NOT NULL DEFAULT 0,
        last_dashboard_users INTEGER NOT NULL DEFAULT 0
      );

-- table: analytics_sessions
CREATE TABLE IF NOT EXISTS analytics_sessions (
        session_id TEXT PRIMARY KEY,
        roblox_user_id TEXT NOT NULL,
        version TEXT NOT NULL DEFAULT 'unknown',
        game_id TEXT,
        place_id TEXT,
        game_slug TEXT,
        device TEXT,
        started_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        dashboard_linked INTEGER NOT NULL DEFAULT 0
      );

-- table: auth_exchanges
CREATE TABLE IF NOT EXISTS auth_exchanges (     code_hash TEXT PRIMARY KEY,     user_id TEXT NOT NULL,     expires_at INTEGER NOT NULL,     created_at INTEGER NOT NULL,     FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE );

-- table: live_presence
CREATE TABLE IF NOT EXISTS live_presence (session_id TEXT PRIMARY KEY, veyra_user_id TEXT NOT NULL, roblox_user_id TEXT NOT NULL, role TEXT NOT NULL, connected_at INTEGER NOT NULL, last_seen_at INTEGER NOT NULL);

-- table: owner_analytics_cache
CREATE TABLE IF NOT EXISTS owner_analytics_cache (
        cache_key TEXT PRIMARY KEY,
        generated_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        payload_json TEXT NOT NULL
      );

-- table: roblox_accounts
CREATE TABLE IF NOT EXISTS roblox_accounts (     veyra_user_id TEXT NOT NULL,     roblox_user_id TEXT NOT NULL,     username TEXT NOT NULL,     display_name TEXT,     avatar_url TEXT,     avatar_updated_at INTEGER,     first_seen_at INTEGER NOT NULL,     last_seen_at INTEGER NOT NULL,     last_session_id TEXT,     PRIMARY KEY (veyra_user_id, roblox_user_id),     FOREIGN KEY (veyra_user_id) REFERENCES users(id) ON DELETE CASCADE );

-- table: roblox_profile_cache
CREATE TABLE IF NOT EXISTS roblox_profile_cache (
        roblox_user_id TEXT PRIMARY KEY,
        username TEXT,
        display_name TEXT,
        avatar_url TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      );

-- table: runtime_presence
CREATE TABLE IF NOT EXISTS runtime_presence (session_id TEXT PRIMARY KEY, roblox_user_id TEXT NOT NULL, dashboard_linked INTEGER NOT NULL DEFAULT 0, version TEXT, started_at INTEGER NOT NULL, last_seen_at INTEGER NOT NULL);

-- table: scriptblox_snapshots
CREATE TABLE IF NOT EXISTS scriptblox_snapshots (
        script_id TEXT NOT NULL,
        captured_at INTEGER NOT NULL,
        title TEXT,
        slug TEXT,
        owner_username TEXT,
        game_name TEXT,
        views INTEGER NOT NULL DEFAULT 0,
        likes INTEGER NOT NULL DEFAULT 0,
        dislikes INTEGER NOT NULL DEFAULT 0,
        verified INTEGER NOT NULL DEFAULT 0,
        patched INTEGER NOT NULL DEFAULT 0,
        visibility TEXT,
        script_type TEXT,
        created_at TEXT,
        PRIMARY KEY (script_id, captured_at)
      );

-- table: users
CREATE TABLE IF NOT EXISTS users (     id TEXT PRIMARY KEY,     discord_id TEXT NOT NULL UNIQUE,     discord_username TEXT NOT NULL,     discord_display_name TEXT,     discord_avatar TEXT,     dashboard_key_hash TEXT UNIQUE,     dashboard_key_suffix TEXT,     created_at INTEGER NOT NULL,     updated_at INTEGER NOT NULL,     last_login_at INTEGER NOT NULL );

-- table: web_sessions
CREATE TABLE IF NOT EXISTS web_sessions (     token_hash TEXT PRIMARY KEY,     user_id TEXT NOT NULL,     created_at INTEGER NOT NULL,     expires_at INTEGER NOT NULL,     FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE );

-- index: idx_analytics_sessions_started
CREATE INDEX IF NOT EXISTS idx_analytics_sessions_started
      ON analytics_sessions(started_at DESC);

-- index: idx_analytics_sessions_user
CREATE INDEX IF NOT EXISTS idx_analytics_sessions_user
      ON analytics_sessions(roblox_user_id, started_at DESC);

-- index: idx_auth_exchanges_expires_at
CREATE INDEX IF NOT EXISTS idx_auth_exchanges_expires_at ON auth_exchanges(expires_at);

-- index: idx_live_presence_roblox
CREATE INDEX IF NOT EXISTS idx_live_presence_roblox ON live_presence(roblox_user_id);

-- index: idx_live_presence_role
CREATE INDEX IF NOT EXISTS idx_live_presence_role ON live_presence(role);

-- index: idx_live_presence_user
CREATE INDEX IF NOT EXISTS idx_live_presence_user ON live_presence(veyra_user_id);

-- index: idx_roblox_accounts_last_seen
CREATE INDEX IF NOT EXISTS idx_roblox_accounts_last_seen ON roblox_accounts(last_seen_at DESC);

-- index: idx_roblox_accounts_user_last_seen
CREATE INDEX IF NOT EXISTS idx_roblox_accounts_user_last_seen ON roblox_accounts(veyra_user_id, last_seen_at DESC);

-- index: idx_runtime_presence_linked
CREATE INDEX IF NOT EXISTS idx_runtime_presence_linked ON runtime_presence(dashboard_linked);

-- index: idx_runtime_presence_roblox
CREATE INDEX IF NOT EXISTS idx_runtime_presence_roblox ON runtime_presence(roblox_user_id);

-- index: idx_runtime_presence_seen
CREATE INDEX IF NOT EXISTS idx_runtime_presence_seen ON runtime_presence(last_seen_at);

-- index: idx_scriptblox_snapshots_time
CREATE INDEX IF NOT EXISTS idx_scriptblox_snapshots_time
      ON scriptblox_snapshots(script_id, captured_at DESC);

-- index: idx_web_sessions_expires_at
CREATE INDEX IF NOT EXISTS idx_web_sessions_expires_at ON web_sessions(expires_at);

-- index: idx_web_sessions_user_id
CREATE INDEX IF NOT EXISTS idx_web_sessions_user_id ON web_sessions(user_id);
