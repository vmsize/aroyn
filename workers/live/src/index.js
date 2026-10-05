
import {claimRuntimeSession} from '../../shared/data-lifecycle.js';
import {stagingRestricted, discordAccessAllowed} from '../../shared/staging-access.js';

class RequestInputError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

// Count bytes while reading, including chunked requests without Content-Length.
async function boundedJson(request, maxBytes = 8192) {
  if (Number(request.headers.get("Content-Length") || 0) > maxBytes) {
    throw new RequestInputError("Payload too large.", 413);
  }
  if (!request.body) throw new RequestInputError("JSON object required.");
  const reader = request.body.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  let size = 0, text = "";
  try {
    while (true) {
      const {value, done} = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        await reader.cancel().catch(() => {});
        throw new RequestInputError("Payload too large.", 413);
      }
      text += decoder.decode(value, {stream: true});
    }
    const body = JSON.parse(text + decoder.decode());
    if (!body || typeof body !== "object" || Array.isArray(body)) {
      throw new RequestInputError("JSON object required.");
    }
    return body;
  } catch (error) {
    if (error instanceof RequestInputError) throw error;
    throw new RequestInputError("Invalid JSON.");
  } finally { reader.releaseLock(); }
}

async function requestRateLimit(request, binding) {
  if (!binding) throw new RequestInputError("Request limiter unavailable.", 503);
  // CF-Connecting-IP is supplied by Cloudflare, never a user ID or raw credential.
  const ip = request.headers.get("CF-Connecting-IP") || "local";
  const route = new URL(request.url).pathname;
  const result = await binding.limit({key: `${route}:${ip}`});
  if (result.success === false) throw new RequestInputError("Too many requests.", 429);
}

const encoder = new TextEncoder();

// D1 write budget optimization.
// Normal runtime presence is intentionally coarse-grained: explicit disconnects
// and linked WebSocket closes still remove users immediately, while silent exits
// age out after the stale window.
const LINKED_WS_TOUCH_MS = 180 * 1000;
const LINKED_STALE_MS = 420 * 1000;

const UNLINKED_HEARTBEAT_SECONDS = 300;
const UNLINKED_STALE_MS = 420 * 1000;

const LINKED_HTTP_HEARTBEAT_SECONDS = 300;

const ANALYTICS_SESSION_CHECKPOINT_MS = 15 * 60 * 1000;

// Owner analytics is mostly historical. Keep the expensive aggregate bundle
// cached for minutes, not seconds, and overlay live/recent data separately.
// This keeps the dashboard responsive while avoiding repeated full-table scans.
const OWNER_ANALYTICS_CACHE_MS = 30 * 60 * 1000;
const OWNER_ANALYTICS_CACHE_VERSION = 3;
const OWNER_ANALYTICS_REALTIME_CACHE_MS = 10 * 1000;
const OWNER_USER_DIRECTORY_CACHE_MS = 30 * 60 * 1000;

// Avoid scanning runtime_presence for stale rows on every stats read. Explicit
// disconnects remove sessions immediately; this throttle is only a safety net.
const RUNTIME_PRESENCE_CLEANUP_MIN_MS = 60 * 1000;
let runtimePresenceCleanupNextAt = 0;

// Safety sweep for rare stale linked rows. Normal linked disconnects
// are pushed immediately through WebSocket close/error handlers.
const STATS_SAFETY_SWEEP_MS = 5 * 60 * 1000;

function base64url(bytes) {
  let binary = "";

  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }

  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function base64urlText(value) {
  return base64url(encoder.encode(String(value)));
}

function decodeBase64url(value) {
  let normalized = String(value).replace(/-/g, "+").replace(/_/g, "/");

  while (normalized.length % 4) {
    normalized += "=";
  }

  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);

  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }

  return new TextDecoder().decode(bytes);
}

async function sha256Hex(value) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    encoder.encode(String(value)),
  );

  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function sign(secret, value) {
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    {
      name: "HMAC",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(value),
  );

  return base64url(new Uint8Array(signature));
}

function safeEqual(a, b) {
  a = String(a || "");
  b = String(b || "");

  if (a.length !== b.length) {
    return false;
  }

  let difference = 0;

  for (let i = 0; i < a.length; i++) {
    difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }

  return difference === 0;
}

const PRESENCE_TOKEN_MAX_AGE_SECONDS = 7 * 24 * 60 * 60;

async function issuePresenceToken(env, sessionId, robloxUserId) {
  const payload = base64urlText(JSON.stringify({
    sid: sessionId,
    uid: robloxUserId,
    iat: Math.floor(Date.now() / 1000),
  }));
  return `PT1.${payload}.${await sign(env.PRESENCE_TOKEN_SECRET, `PT1.${payload}`)}`;
}

async function validPresenceToken(env, token, sessionId, robloxUserId) {
  if (!env.PRESENCE_TOKEN_SECRET || typeof token !== "string" || token.length > 1024) return false;
  const parts = token.split(".");
  if (parts.length !== 3 || parts[0] !== "PT1") return false;
  const expected = await sign(env.PRESENCE_TOKEN_SECRET, `PT1.${parts[1]}`);
  if (!safeEqual(parts[2], expected)) return false;
  try {
    const payload = JSON.parse(decodeBase64url(parts[1]));
    const age = Math.floor(Date.now() / 1000) - payload.iat;
    return payload.sid === sessionId && payload.uid === robloxUserId &&
      Number.isInteger(payload.iat) && age >= 0 && age <= PRESENCE_TOKEN_MAX_AGE_SECONDS;
  } catch {
    return false;
  }
}

async function presenceRateLimited(env, route, request) {
  const ip = request.headers.get("CF-Connecting-IP") || "local";
  const result = await env.PRESENCE_RATE_LIMITER.limit({ key: `${route}:${ip}` });
  return result.success === false;
}

function bearerToken(request) {
  const raw = request.headers.get("Authorization") || "";

  const match = raw.match(/^Bearer\s+(.+)$/i);

  return match ? match[1].trim() : "";
}

function corsHeaders(request, env) {
  const origin = String(request.headers.get("Origin") || "").trim();
  const configured = String(env.ALLOWED_ORIGIN || "https://veyra-hub.pages.dev")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);

  // Preserve transition compatibility unless an isolated deployment opts out.
  const isVeyraPagesOrigin =
    env.ALLOW_LEGACY_SITE_ORIGINS !== "false" &&
    /^https:\/\/(?:[a-z0-9-]+\.)?veyra-hub\.pages\.dev$/i.test(origin);
  const allowedOrigin =
    configured.includes(origin) || isVeyraPagesOrigin
      ? origin
      : configured[0] || "https://veyra-hub.pages.dev";

  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Presence-Token",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function json(request, data, status = 200, env) {
  return new Response(JSON.stringify(data), {
    status,

    headers: {
      "Content-Type": "application/json; charset=utf-8",

      "Cache-Control": "no-store",

      ...corsHeaders(request, env),
    },
  });
}

async function limitedJsonBody(request, maxBytes = 8192) {
  if (!request.body) return { body: {} };
  const reader = request.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let size = 0;

  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > maxBytes) {
        try {
          await reader.cancel();
        } catch {}
        return { tooLarge: true };
      }
      text += decoder.decode(value, { stream: true });
    }
    text += decoder.decode();
    return { body: JSON.parse(text) };
  } catch {
    return { body: {} };
  }
}

function normalizeDashboardKey(value) {
  return String(value || "")
    .trim()
    .toUpperCase()
    .replace(/\s+/g, "");
}

const DASHBOARD_KEY_RE = /^VY-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$/;

const PRESENCE_SESSION_RE = /^[A-Za-z0-9_-]{8,128}$/;

const ANALYTICS_SAMPLE_MS = 5 * 60 * 1000;
let analyticsSchemaReady = false;

async function ensureAnalyticsSchema(env) {
  if (analyticsSchemaReady || !env.DB) return;

  await env.DB.batch([
    env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS runtime_presence (
        session_id TEXT PRIMARY KEY,
        roblox_user_id TEXT NOT NULL,
        dashboard_linked INTEGER NOT NULL DEFAULT 0,
        version TEXT NOT NULL DEFAULT 'unknown',
        started_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL
      )
    `),
    // Presence is a small hot table. Indexes on fields changed by every heartbeat
    // multiply D1 rows-written, so keep it deliberately index-free.
    env.DB.prepare(`DROP INDEX IF EXISTS idx_runtime_presence_last_seen`),
    env.DB.prepare(`DROP INDEX IF EXISTS idx_runtime_presence_user`),
    env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS analytics_sessions (
        session_id TEXT PRIMARY KEY,
        roblox_user_id TEXT NOT NULL,
        version TEXT NOT NULL DEFAULT 'unknown',
        game_id TEXT,
        place_id TEXT,
        game_slug TEXT,
        device TEXT,
        executor_name TEXT,
        executor_version TEXT,
        started_at INTEGER NOT NULL,
        last_seen_at INTEGER NOT NULL,
        dashboard_linked INTEGER NOT NULL DEFAULT 0
      )
    `),
    env.DB.prepare(`
      CREATE INDEX IF NOT EXISTS idx_analytics_sessions_started
      ON analytics_sessions(started_at DESC)
    `),
    env.DB.prepare(`
      CREATE INDEX IF NOT EXISTS idx_analytics_sessions_user
      ON analytics_sessions(roblox_user_id, started_at DESC)
    `),
    // last_seen_at is checkpointed and dashboard_linked can change after launch.
    // Neither needs a dedicated index for the current owner queries, and removing
    // them avoids index-row rewrites on every checkpoint/link transition.
    env.DB.prepare(`DROP INDEX IF EXISTS idx_analytics_sessions_last_seen`),
    env.DB.prepare(`DROP INDEX IF EXISTS idx_analytics_sessions_dashboard`),
    env.DB.prepare(`
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
      )
    `),
    env.DB.prepare(`
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
      )
    `),
    env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS roblox_profile_cache (
        roblox_user_id TEXT PRIMARY KEY,
        username TEXT,
        display_name TEXT,
        avatar_url TEXT,
        updated_at INTEGER NOT NULL DEFAULT 0
      )
    `),
    env.DB.prepare(`
      CREATE TABLE IF NOT EXISTS owner_analytics_cache (
        cache_key TEXT PRIMARY KEY,
        generated_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        payload_json TEXT NOT NULL
      )
    `),
    env.DB.prepare(`
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
      )
    `),
    env.DB.prepare(`
      CREATE INDEX IF NOT EXISTS idx_scriptblox_snapshots_time
      ON scriptblox_snapshots(script_id, captured_at DESC)
    `),
    env.DB.prepare(`
      INSERT OR IGNORE INTO analytics_peaks(id)
      VALUES (1)
    `),
  ]);

  analyticsSchemaReady = true;
}

const ROBLOX_PROFILE_CACHE_MS = 24 * 60 * 60 * 1000;
const ROBLOX_PROFILE_REFRESH_BATCH = 20;

function validRobloxUserId(value) {
  const id = String(value ?? "").trim();
  return /^\d{1,20}$/.test(id) && id !== "0" ? id : null;
}

async function readRobloxProfileCache(env, ids) {
  const map = new Map();
  const clean = [
    ...new Set((ids || []).map(validRobloxUserId).filter(Boolean)),
  ];

  for (let offset = 0; offset < clean.length; offset += 80) {
    const chunk = clean.slice(offset, offset + 80);
    if (!chunk.length) continue;
    const placeholders = chunk.map(() => "?").join(",");
    const result = await env.DB.prepare(
      `
      SELECT roblox_user_id, username, display_name, avatar_url, updated_at
      FROM roblox_profile_cache
      WHERE roblox_user_id IN (${placeholders})
    `,
    )
      .bind(...chunk)
      .all();

    for (const row of resultRows(result)) {
      map.set(String(row.roblox_user_id), {
        userId: String(row.roblox_user_id),
        username: row.username ? String(row.username) : null,
        displayName: row.display_name ? String(row.display_name) : null,
        avatarUrl: row.avatar_url ? String(row.avatar_url) : null,
        updatedAt: Number(row.updated_at || 0),
      });
    }
  }

  return map;
}

async function fetchRobloxUserProfile(userId) {
  try {
    const response = await fetch(
      `https://users.roblox.com/v1/users/${encodeURIComponent(userId)}`,
      { headers: { Accept: "application/json" }, signal: AbortSignal.timeout(3000) },
    );
    if (!response.ok) return null;
    const body = await response.json().catch(() => null);
    if (!body || !body.id) return null;
    return {
      userId: String(body.id),
      username: body.name ? String(body.name).slice(0, 64) : null,
      displayName: body.displayName
        ? String(body.displayName).slice(0, 64)
        : null,
    };
  } catch {
    return null;
  }
}

async function fetchRobloxAvatarBusts(userIds) {
  const result = new Map();
  const ids = [
    ...new Set((userIds || []).map(validRobloxUserId).filter(Boolean)),
  ];
  if (!ids.length) return result;

  try {
    const url = new URL("https://thumbnails.roblox.com/v1/users/avatar-bust");
    url.searchParams.set("userIds", ids.join(","));
    url.searchParams.set("size", "150x150");
    url.searchParams.set("format", "Png");
    url.searchParams.set("isCircular", "false");

    const response = await fetch(url.toString(), {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return result;

    const body = await response.json().catch(() => ({}));
    for (const item of Array.isArray(body?.data) ? body.data : []) {
      const id = validRobloxUserId(item?.targetId);
      if (!id) continue;
      if (item?.state === "Completed" && item?.imageUrl) {
        result.set(id, String(item.imageUrl));
      }
    }
  } catch {}

  return result;
}

async function refreshRobloxProfiles(env, ids, existing) {
  const now = Date.now();
  const targets = [
    ...new Set((ids || []).map(validRobloxUserId).filter(Boolean)),
  ]
    .filter((id) => {
      const cached = existing.get(id);
      return (
        !cached ||
        !cached.updatedAt ||
        now - cached.updatedAt >= ROBLOX_PROFILE_CACHE_MS
      );
    })
    .slice(0, ROBLOX_PROFILE_REFRESH_BATCH);

  if (!targets.length) return existing;

  const [profiles, avatars] = await Promise.all([
    Promise.all(targets.map(fetchRobloxUserProfile)),
    fetchRobloxAvatarBusts(targets),
  ]);

  const writes = [];
  for (let i = 0; i < targets.length; i++) {
    const id = targets[i];
    const previous = existing.get(id) || {};
    const fetched = profiles[i] || {};
    const next = {
      userId: id,
      username: fetched.username || previous.username || null,
      displayName:
        fetched.displayName ||
        previous.displayName ||
        fetched.username ||
        previous.username ||
        null,
      avatarUrl: avatars.get(id) || previous.avatarUrl || null,
      updatedAt: now,
    };
    existing.set(id, next);

    writes.push(
      env.DB.prepare(
        `
        INSERT INTO roblox_profile_cache (
          roblox_user_id, username, display_name, avatar_url, updated_at
        ) VALUES (?1, ?2, ?3, ?4, ?5)
        ON CONFLICT(roblox_user_id) DO UPDATE SET
          username = COALESCE(excluded.username, roblox_profile_cache.username),
          display_name = COALESCE(excluded.display_name, roblox_profile_cache.display_name),
          avatar_url = COALESCE(excluded.avatar_url, roblox_profile_cache.avatar_url),
          updated_at = excluded.updated_at
      `,
      ).bind(id, next.username, next.displayName, next.avatarUrl, now),
    );
  }

  if (writes.length) await env.DB.batch(writes);
  return existing;
}

async function getRobloxProfilesForAnalytics(env, ids) {
  await ensureAnalyticsSchema(env);
  const clean = [
    ...new Set((ids || []).map(validRobloxUserId).filter(Boolean)),
  ];
  const cached = await readRobloxProfileCache(env, clean);
  await refreshRobloxProfiles(env, clean, cached);
  return cached;
}

const SCRIPTBLOX_SCRIPT_ID =
  "Greedy-Growers-Veyra-Hub-or-or-Auto-Farm-Compost-and-More-228824";
const SCRIPTBLOX_PAGE_URL = `https://scriptblox.com/script/${SCRIPTBLOX_SCRIPT_ID}`;
const SCRIPTBLOX_API_URL = `https://scriptblox.com/api/script/${SCRIPTBLOX_SCRIPT_ID}`;
const SCRIPTBLOX_CACHE_MS = 10 * 60 * 1000;
const SCRIPTBLOX_SNAPSHOT_BUCKET_MS = 10 * 60 * 1000;

function normalizeScriptBloxSnapshot(row) {
  if (!row) return null;
  return {
    available: true,
    scriptId: SCRIPTBLOX_SCRIPT_ID,
    pageUrl: SCRIPTBLOX_PAGE_URL,
    title: row.title ? String(row.title) : null,
    slug: row.slug ? String(row.slug) : SCRIPTBLOX_SCRIPT_ID,
    ownerUsername: row.owner_username ? String(row.owner_username) : null,
    gameName: row.game_name ? String(row.game_name) : null,
    views: Number(row.views || 0),
    likes: Number(row.likes || 0),
    dislikes: Number(row.dislikes || 0),
    verified: Number(row.verified || 0) === 1,
    patched: Number(row.patched || 0) === 1,
    visibility: row.visibility ? String(row.visibility) : null,
    scriptType: row.script_type ? String(row.script_type) : null,
    createdAt: row.created_at ? String(row.created_at) : null,
    capturedAt: Number(row.captured_at || 0) || null,
  };
}

async function readLatestScriptBloxSnapshot(env) {
  return await env.DB.prepare(
    `
    SELECT *
    FROM scriptblox_snapshots
    WHERE script_id = ?1
    ORDER BY captured_at DESC
    LIMIT 1
  `,
  )
    .bind(SCRIPTBLOX_SCRIPT_ID)
    .first();
}

async function fetchScriptBloxSnapshot(env) {
  const response = await fetch(SCRIPTBLOX_API_URL, {
    signal: AbortSignal.timeout(3000),
    headers: {
      Accept: "application/json",
      "User-Agent": "Veyra-Owner-Analytics/1.0",
    },
  });
  if (!response.ok) {
    throw new Error(`ScriptBlox API returned HTTP ${response.status}`);
  }

  const body = await response.json().catch(() => null);
  const script = body && typeof body === "object" ? body.script : null;
  if (!script || typeof script !== "object") {
    throw new Error(
      String(body?.message || "ScriptBlox returned an invalid response"),
    );
  }

  const now = Date.now();
  const bucket =
    Math.floor(now / SCRIPTBLOX_SNAPSHOT_BUCKET_MS) *
    SCRIPTBLOX_SNAPSHOT_BUCKET_MS;
  const row = {
    script_id: SCRIPTBLOX_SCRIPT_ID,
    captured_at: bucket,
    title: String(script.title || "").slice(0, 180) || null,
    slug: String(script.slug || SCRIPTBLOX_SCRIPT_ID).slice(0, 220),
    owner_username: String(script.owner?.username || "").slice(0, 80) || null,
    game_name: String(script.game?.name || "").slice(0, 120) || null,
    views: Math.max(0, Number(script.views || 0) || 0),
    likes: Math.max(0, Number(script.likeCount || 0) || 0),
    dislikes: Math.max(0, Number(script.dislikeCount || 0) || 0),
    verified: script.verified === true ? 1 : 0,
    patched: script.isPatched === true ? 1 : 0,
    visibility: String(script.visibility || "").slice(0, 40) || null,
    script_type: String(script.scriptType || "").slice(0, 40) || null,
    created_at: script.createdAt ? String(script.createdAt).slice(0, 80) : null,
  };

  await env.DB.prepare(
    `
    INSERT INTO scriptblox_snapshots (
      script_id, captured_at, title, slug, owner_username, game_name,
      views, likes, dislikes, verified, patched, visibility, script_type, created_at
    ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
    ON CONFLICT(script_id, captured_at) DO UPDATE SET
      title = excluded.title,
      slug = excluded.slug,
      owner_username = excluded.owner_username,
      game_name = excluded.game_name,
      views = excluded.views,
      likes = excluded.likes,
      dislikes = excluded.dislikes,
      verified = excluded.verified,
      patched = excluded.patched,
      visibility = excluded.visibility,
      script_type = excluded.script_type,
      created_at = excluded.created_at
  `,
  )
    .bind(
      row.script_id,
      row.captured_at,
      row.title,
      row.slug,
      row.owner_username,
      row.game_name,
      row.views,
      row.likes,
      row.dislikes,
      row.verified,
      row.patched,
      row.visibility,
      row.script_type,
      row.created_at,
    )
    .run();

  return row;
}

async function scriptBloxHistoricalSnapshot(env, beforeAt) {
  return await env.DB.prepare(
    `
    SELECT views, likes, dislikes, captured_at
    FROM scriptblox_snapshots
    WHERE script_id = ?1
      AND captured_at <= ?2
    ORDER BY captured_at DESC
    LIMIT 1
  `,
  )
    .bind(SCRIPTBLOX_SCRIPT_ID, beforeAt)
    .first();
}

function scriptBloxDelta(current, old) {
  if (!current || !old) return { views: null, likes: null, dislikes: null };
  return {
    views: Number(current.views || 0) - Number(old.views || 0),
    likes: Number(current.likes || 0) - Number(old.likes || 0),
    dislikes: Number(current.dislikes || 0) - Number(old.dislikes || 0),
  };
}

async function getScriptBloxStats(env) {
  await ensureAnalyticsSchema(env);
  const now = Date.now();
  let latest = await readLatestScriptBloxSnapshot(env);
  let fetchError = null;

  if (!latest || now - Number(latest.captured_at || 0) >= SCRIPTBLOX_CACHE_MS) {
    try {
      latest = await fetchScriptBloxSnapshot(env);
    } catch (error) {
      fetchError = String(error?.message || error);
      latest = latest || (await readLatestScriptBloxSnapshot(env));
    }
  }

  if (!latest) {
    return {
      available: false,
      pageUrl: SCRIPTBLOX_PAGE_URL,
      error: fetchError || "No ScriptBlox snapshot is available yet.",
    };
  }

  const [old24h, old7d] = await Promise.all([
    scriptBloxHistoricalSnapshot(env, now - 24 * 60 * 60 * 1000),
    scriptBloxHistoricalSnapshot(env, now - 7 * 24 * 60 * 60 * 1000),
  ]);

  return {
    ...normalizeScriptBloxSnapshot(latest),
    stale: Boolean(fetchError),
    error: fetchError,
    change24h: scriptBloxDelta(latest, old24h),
    change7d: scriptBloxDelta(latest, old7d),
  };
}

function cleanAnalyticsText(value, maxLength = 64) {
  const text = String(value ?? "").trim();
  return text ? text.slice(0, maxLength) : null;
}

// Optional client-reported diagnostics, never an identity or authorization proof.
function cleanExecutorText(value, maxLength = 64) {
  if (typeof value !== "string") return null;
  const text = value.slice(0, 256).replace(/[^\x20-\x7e]/g, " ").replace(/\s+/g, " ").trim();
  return !text || /^(unknown|nil|null|undefined)$/i.test(text) ? null : text.slice(0, maxLength);
}

async function upsertAnalyticsSession(
  env,
  {
    sessionId,
    robloxUserId,
    dashboardLinked = false,
    userId = null,
    version = "unknown",
    gameId = null,
    placeId = null,
    gameSlug = null,
    device = null,
    executorName = null,
    executorVersion = null,
  },
) {
  await ensureAnalyticsSchema(env);

  const now = Date.now();
  const checkpointBefore = now - ANALYTICS_SESSION_CHECKPOINT_MS;

  const normalized = {
    sessionId: String(sessionId),
    robloxUserId: String(robloxUserId),
    version: cleanAnalyticsText(version, 32) || "unknown",
    gameId: cleanAnalyticsText(gameId, 32),
    placeId: cleanAnalyticsText(placeId, 32),
    gameSlug: cleanAnalyticsText(gameSlug, 64),
    device: cleanAnalyticsText(device, 24),
    executorName: cleanExecutorText(executorName),
    executorVersion: cleanExecutorText(executorName) ? cleanExecutorText(executorVersion, 32) : null,
    dashboardLinked: dashboardLinked ? 1 : 0,
  };

  // Linked writes recheck ownership and deletion inside the same D1 statement;
  // a previously accepted request cannot recreate history after deletion.
  // One statement replaces the old SELECT + optional INSERT/UPDATE sequence.
  // On conflict, SQLite only writes when metadata changed, the launch became
  // dashboard-linked, or the coarse last_seen checkpoint is due.
  const result = await env.DB.prepare(
    `
      INSERT INTO analytics_sessions (
        session_id,
        roblox_user_id,
        version,
        game_id,
        place_id,
        game_slug,
        device,
        started_at,
        last_seen_at,
        dashboard_linked,
        executor_name,
        executor_version
      ) SELECT ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, ?9, ?12, ?13
      WHERE ?9 = 0 OR EXISTS (
        SELECT 1 FROM runtime_session_owners o JOIN users u ON u.id=o.veyra_user_id
        WHERE o.session_id=?1 AND o.roblox_user_id=?2 AND u.id=?11
          AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=u.id)
      )

      ON CONFLICT(session_id)
      DO UPDATE SET
        roblox_user_id =
          excluded.roblox_user_id,

        version = CASE
          WHEN excluded.version <> 'unknown'
          THEN excluded.version
          ELSE analytics_sessions.version
        END,

        game_id =
          COALESCE(
            excluded.game_id,
            analytics_sessions.game_id
          ),

        place_id =
          COALESCE(
            excluded.place_id,
            analytics_sessions.place_id
          ),

        game_slug =
          COALESCE(
            excluded.game_slug,
            analytics_sessions.game_slug
          ),

        device =
          COALESCE(
            excluded.device,
            analytics_sessions.device
          ),

        executor_name = COALESCE(excluded.executor_name, analytics_sessions.executor_name),
        executor_version = CASE
          WHEN excluded.executor_name IS NULL THEN analytics_sessions.executor_version
          WHEN excluded.executor_name = analytics_sessions.executor_name
            THEN COALESCE(excluded.executor_version, analytics_sessions.executor_version)
          ELSE excluded.executor_version
        END,

        last_seen_at =
          excluded.last_seen_at,

        dashboard_linked =
          MAX(
            analytics_sessions.dashboard_linked,
            excluded.dashboard_linked
          )

      WHERE
        analytics_sessions.roblox_user_id = excluded.roblox_user_id
        AND (
        (
          excluded.version <> 'unknown'
          AND analytics_sessions.version <> excluded.version
        )

        OR (
          excluded.game_id IS NOT NULL
          AND COALESCE(analytics_sessions.game_id, '') <> excluded.game_id
        )

        OR (
          excluded.place_id IS NOT NULL
          AND COALESCE(analytics_sessions.place_id, '') <> excluded.place_id
        )

        OR (
          excluded.game_slug IS NOT NULL
          AND COALESCE(analytics_sessions.game_slug, '') <> excluded.game_slug
        )

        OR (
          excluded.device IS NOT NULL
          AND COALESCE(analytics_sessions.device, '') <> excluded.device
        )

        OR (
          excluded.dashboard_linked = 1
          AND analytics_sessions.dashboard_linked <> 1
        )

        OR (excluded.executor_name IS NOT NULL AND COALESCE(analytics_sessions.executor_name, '') <> excluded.executor_name)
        OR (excluded.executor_name IS NOT NULL AND excluded.executor_version IS NOT NULL
          AND COALESCE(analytics_sessions.executor_version, '') <> excluded.executor_version)
        OR analytics_sessions.last_seen_at <= ?10
        )
    `,
  )
    .bind(
      normalized.sessionId,
      normalized.robloxUserId,
      normalized.version,
      normalized.gameId,
      normalized.placeId,
      normalized.gameSlug,
      normalized.device,
      now,
      normalized.dashboardLinked,
      checkpointBefore,
      userId,
      normalized.executorName,
      normalized.executorVersion,
    )
    .run();

  return {
    written: Number(result?.meta?.changes || 0) > 0,
  };
}

async function recordAnalyticsSnapshot(env) {
  await ensureAnalyticsSchema(env);

  const stats = await getRuntimePresenceStats(env);
  const now = Date.now();
  const bucketStart =
    Math.floor(now / ANALYTICS_SAMPLE_MS) * ANALYTICS_SAMPLE_MS;

  const existing = await env.DB.prepare(
    `
    SELECT
      max_script_sessions,
      max_script_users,
      max_dashboard_sessions,
      max_dashboard_users
    FROM analytics_samples
    WHERE bucket_start = ?1
    LIMIT 1
  `,
  )
    .bind(bucketStart)
    .first();

  const writes = [];

  if (!existing) {
    writes.push(
      env.DB.prepare(
        `
        INSERT INTO analytics_samples (
          bucket_start,
          sample_count,
          max_script_sessions,
          max_script_users,
          max_dashboard_sessions,
          max_dashboard_users,
          last_script_sessions,
          last_script_users,
          last_dashboard_sessions,
          last_dashboard_users
        ) VALUES (?1, 1, ?2, ?3, ?4, ?5, ?2, ?3, ?4, ?5)
      `,
      ).bind(
        bucketStart,
        stats.scriptSessions,
        stats.scriptUsers,
        stats.dashboardSessions,
        stats.dashboardUsers,
      ),
    );
  } else {
    const newWithinBucketPeak =
      stats.scriptSessions > Number(existing.max_script_sessions || 0) ||
      stats.scriptUsers > Number(existing.max_script_users || 0) ||
      stats.dashboardSessions > Number(existing.max_dashboard_sessions || 0) ||
      stats.dashboardUsers > Number(existing.max_dashboard_users || 0);

    if (newWithinBucketPeak) {
      writes.push(
        env.DB.prepare(
          `
          UPDATE analytics_samples SET
            sample_count = sample_count + 1,
            max_script_sessions = MAX(max_script_sessions, ?2),
            max_script_users = MAX(max_script_users, ?3),
            max_dashboard_sessions = MAX(max_dashboard_sessions, ?4),
            max_dashboard_users = MAX(max_dashboard_users, ?5),
            last_script_sessions = ?2,
            last_script_users = ?3,
            last_dashboard_sessions = ?4,
            last_dashboard_users = ?5
          WHERE bucket_start = ?1
        `,
        ).bind(
          bucketStart,
          stats.scriptSessions,
          stats.scriptUsers,
          stats.dashboardSessions,
          stats.dashboardUsers,
        ),
      );
    }
  }

  const peaks = await env.DB.prepare(
    `
    SELECT
      peak_script_sessions,
      peak_script_users,
      peak_dashboard_sessions,
      peak_dashboard_users
    FROM analytics_peaks
    WHERE id = 1
    LIMIT 1
  `,
  ).first();

  const newAllTimePeak =
    stats.scriptSessions > Number(peaks?.peak_script_sessions || 0) ||
    stats.scriptUsers > Number(peaks?.peak_script_users || 0) ||
    stats.dashboardSessions > Number(peaks?.peak_dashboard_sessions || 0) ||
    stats.dashboardUsers > Number(peaks?.peak_dashboard_users || 0);

  if (newAllTimePeak) {
    writes.push(
      env.DB.prepare(
        `
        UPDATE analytics_peaks SET
          peak_script_sessions = MAX(peak_script_sessions, ?1),
          peak_script_sessions_at = CASE WHEN ?1 > peak_script_sessions THEN ?5 ELSE peak_script_sessions_at END,
          peak_script_users = MAX(peak_script_users, ?2),
          peak_script_users_at = CASE WHEN ?2 > peak_script_users THEN ?5 ELSE peak_script_users_at END,
          peak_dashboard_sessions = MAX(peak_dashboard_sessions, ?3),
          peak_dashboard_sessions_at = CASE WHEN ?3 > peak_dashboard_sessions THEN ?5 ELSE peak_dashboard_sessions_at END,
          peak_dashboard_users = MAX(peak_dashboard_users, ?4),
          peak_dashboard_users_at = CASE WHEN ?4 > peak_dashboard_users THEN ?5 ELSE peak_dashboard_users_at END
        WHERE id = 1
      `,
      ).bind(
        stats.scriptSessions,
        stats.scriptUsers,
        stats.dashboardSessions,
        stats.dashboardUsers,
        now,
      ),
    );
  }

  if (writes.length === 1) {
    await writes[0].run();
  } else if (writes.length > 1) {
    await env.DB.batch(writes);
  }

  return stats;
}

function analyticsRangeConfig(value, now = Date.now()) {
  const range = String(value || "24h").toLowerCase();
  if (range === "7d")
    return { range, start: now - 7 * 86400000, step: 60 * 60 * 1000 };
  if (range === "30d")
    return { range, start: now - 30 * 86400000, step: 6 * 60 * 60 * 1000 };
  if (range === "90d")
    return { range, start: now - 90 * 86400000, step: 24 * 60 * 60 * 1000 };
  if (range === "all") return { range, start: 0, step: 24 * 60 * 60 * 1000 };
  return {
    range: "24h",
    start: now - 24 * 60 * 60 * 1000,
    step: 5 * 60 * 1000,
  };
}

function resultRows(result) {
  return Array.isArray(result?.results) ? result.results : [];
}

function ownerAnalyticsCacheTtlMs(rangeValue) {
  const range = analyticsRangeConfig(rangeValue).range;

  if (range === "7d") {
    return 60 * 60 * 1000;
  }

  if (range === "30d") {
    return 2 * 60 * 60 * 1000;
  }

  if (range === "90d" || range === "all") {
    return 6 * 60 * 60 * 1000;
  }

  return OWNER_ANALYTICS_CACHE_MS;
}

async function readPersistentOwnerAnalyticsCache(env, key, now = Date.now()) {
  await ensureAnalyticsSchema(env);

  const row = await env.DB.prepare(
    `
        SELECT
          generated_at,
          expires_at,
          payload_json
        FROM owner_analytics_cache
        WHERE cache_key = ?1
        LIMIT 1
      `,
  )
    .bind(String(key))
    .first();

  if (
    !row ||
    Number(row.expires_at || 0) <= now ||
    typeof row.payload_json !== "string" ||
    row.payload_json === ""
  ) {
    return null;
  }

  try {
    const analytics = JSON.parse(row.payload_json);

    if (!analytics || typeof analytics !== "object") {
      return null;
    }

    return {
      analytics,
      generatedAt: Number(row.generated_at || 0),
      expiresAt: Number(row.expires_at || 0),
    };
  } catch {
    return null;
  }
}

async function writePersistentOwnerAnalyticsCache(env, key, analytics, ttlMs) {
  const generatedAt = Date.now();
  const expiresAt =
    generatedAt +
    Math.max(60 * 1000, Number(ttlMs) || OWNER_ANALYTICS_CACHE_MS);

  const payloadJson = JSON.stringify(analytics);

  await env.DB.prepare(
    `
      INSERT INTO owner_analytics_cache (
        cache_key,
        generated_at,
        expires_at,
        payload_json
      ) VALUES (?1, ?2, ?3, ?4)

      ON CONFLICT(cache_key)
      DO UPDATE SET
        generated_at = excluded.generated_at,
        expires_at = excluded.expires_at,
        payload_json = excluded.payload_json
    `,
  )
    .bind(String(key), generatedAt, expiresAt, payloadJson)
    .run();

  return {
    generatedAt,
    expiresAt,
  };
}

async function getCachedOwnerUserDirectory(env) {
  const cacheKey = `v${OWNER_ANALYTICS_CACHE_VERSION}:users`;

  const now = Date.now();
  const cached = await readPersistentOwnerAnalyticsCache(env, cacheKey, now);

  if (cached && Array.isArray(cached.analytics?.users)) {
    return cached.analytics.users;
  }

  const allUsersResult = await env.DB.prepare(
    `
      SELECT
        s.roblox_user_id,
        COUNT(*) AS launch_count,
        MIN(s.started_at) AS first_seen_at,
        MAX(s.last_seen_at) AS last_seen_at,
        MAX(
          CASE
            WHEN s.dashboard_linked = 1
            THEN 1
            ELSE 0
          END
        ) AS dashboard_linked,
        COALESCE((
          SELECT NULLIF(latest.device, '')
          FROM analytics_sessions latest
          WHERE latest.roblox_user_id = s.roblox_user_id
          ORDER BY latest.started_at DESC
          LIMIT 1
        ), 'unknown') AS device,
        (SELECT latest.executor_name FROM analytics_sessions latest
          WHERE latest.roblox_user_id = s.roblox_user_id ORDER BY latest.started_at DESC LIMIT 1) AS executor_name,
        (SELECT latest.executor_version FROM analytics_sessions latest
          WHERE latest.roblox_user_id = s.roblox_user_id ORDER BY latest.started_at DESC LIMIT 1) AS executor_version
      FROM analytics_sessions s
      GROUP BY s.roblox_user_id
      ORDER BY first_seen_at ASC, s.roblox_user_id ASC
    `,
  ).all();

  const rows = resultRows(allUsersResult);
  const profiles = await getRobloxProfilesForAnalytics(
    env,
    rows.map((row) => row.roblox_user_id),
  );

  const users = rows
    .map((row) => {
      const userId = String(row.roblox_user_id || "");

      const profile = profiles.get(userId) || {};

      return {
        userId,
        username: profile.username || null,
        displayName: profile.displayName || profile.username || null,
        avatarUrl: profile.avatarUrl || null,
        launchCount: Number(row.launch_count || 0),
        firstSeenAt: Number(row.first_seen_at || 0) || null,
        lastSeenAt: Number(row.last_seen_at || 0) || null,
        online: false,
        dashboardLinked: Number(row.dashboard_linked || 0) === 1,
        device: String(row.device || "unknown").toLowerCase(),
        executorName: cleanExecutorText(row.executor_name),
        executorVersion: cleanExecutorText(row.executor_version, 32),
      };
    })
    .filter((row) => Boolean(row.userId));

  await writePersistentOwnerAnalyticsCache(
    env,
    cacheKey,
    { users },
    OWNER_USER_DIRECTORY_CACHE_MS,
  );

  return users;
}

async function requireOwnerSession(request, env) {
  const configured = String(env.OWNER_DISCORD_ID || "").trim();
  if (!configured)
    return { error: "Owner access is not configured.", status: 503 };

  const session = await resolveWebSession(env, bearerToken(request));
  if (!session) return { error: "Authentication required.", status: 401 };
  if (String(session.discord_id || "") !== configured)
    return { error: "Owner access required.", status: 403 };
  return { session };
}

async function getOwnerAnalytics(env, rangeValue, timezoneOffsetMinutes = 0) {
  await ensureAnalyticsSchema(env);
  const now = Date.now();
  const cfg = analyticsRangeConfig(rangeValue, now);
  const start = cfg.start;
  const step = cfg.step;
  const timezoneShiftMs =
    -Math.max(-840, Math.min(840, Number(timezoneOffsetMinutes) || 0)) * 60000;

  const peaks = await env.DB.prepare(
    `SELECT * FROM analytics_peaks WHERE id = 1`,
  ).first();
  const scriptBloxPromise = getScriptBloxStats(env).catch((error) => ({
    available: false,
    pageUrl: SCRIPTBLOX_PAGE_URL,
    error: String(error?.message || error),
  }));

  const allTime = await env.DB.prepare(
    `
    SELECT
      COUNT(*) AS total_launches,
      SUM(CASE WHEN dashboard_linked = 1 THEN 1 ELSE 0 END) AS dashboard_launches,
      AVG(MAX(0, last_seen_at - started_at)) AS avg_session_ms,
      SUM(MAX(0, last_seen_at - started_at)) AS total_seen_ms
    FROM analytics_sessions
  `,
  ).first();

  const rangeSummary = await env.DB.prepare(
    `
    SELECT
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS unique_users,
      SUM(CASE WHEN dashboard_linked = 1 THEN 1 ELSE 0 END) AS dashboard_launches,
      COUNT(DISTINCT CASE WHEN dashboard_linked = 1 THEN roblox_user_id END) AS dashboard_users,
      AVG(MAX(0, last_seen_at - started_at)) AS avg_session_ms,
      SUM(MAX(0, last_seen_at - started_at)) AS total_seen_ms
    FROM analytics_sessions
    WHERE started_at >= ?1
  `,
  )
    .bind(start)
    .first();

  const accountTotals = await env.DB.prepare(
    `
    SELECT
      (SELECT COUNT(*) FROM users) AS veyra_accounts,
      (SELECT COUNT(DISTINCT roblox_user_id) FROM roblox_accounts) AS linked_roblox_accounts
  `,
  ).first();

  const activityWindows = await env.DB.prepare(
    `
    SELECT
      COUNT(DISTINCT CASE WHEN started_at >= ?1 THEN roblox_user_id END) AS users_24h,
      COUNT(DISTINCT CASE WHEN started_at >= ?2 THEN roblox_user_id END) AS users_7d,
      COUNT(DISTINCT CASE WHEN started_at >= ?3 THEN roblox_user_id END) AS users_30d,
      SUM(CASE WHEN started_at >= ?1 THEN 1 ELSE 0 END) AS launches_24h,
      SUM(CASE WHEN started_at >= ?2 THEN 1 ELSE 0 END) AS launches_7d,
      SUM(CASE WHEN started_at >= ?3 THEN 1 ELSE 0 END) AS launches_30d
    FROM analytics_sessions
    WHERE started_at >= ?3
  `,
  )
    .bind(
      now - 24 * 60 * 60 * 1000,
      now - 7 * 24 * 60 * 60 * 1000,
      now - 30 * 24 * 60 * 60 * 1000,
    )
    .first();

  const sampleResult = await env.DB.prepare(
    `
    SELECT
      CAST(bucket_start / ?1 AS INTEGER) * ?1 AS bucket,
      MAX(max_script_sessions) AS script_sessions,
      MAX(max_script_users) AS script_users,
      MAX(max_dashboard_sessions) AS dashboard_sessions,
      MAX(max_dashboard_users) AS dashboard_users
    FROM analytics_samples
    WHERE bucket_start >= ?2
    GROUP BY bucket
    ORDER BY bucket ASC
    LIMIT 1200
  `,
  )
    .bind(step, start)
    .all();

  const launchesResult = await env.DB.prepare(
    `
    SELECT
      CAST(started_at / ?1 AS INTEGER) * ?1 AS bucket,
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS users,
      SUM(CASE WHEN dashboard_linked = 1 THEN 1 ELSE 0 END) AS dashboard_launches
    FROM analytics_sessions
    WHERE started_at >= ?2
    GROUP BY bucket
    ORDER BY bucket ASC
    LIMIT 1200
  `,
  )
    .bind(step, start)
    .all();

  const hourlyResult = await env.DB.prepare(
    `
    SELECT
      CAST(strftime('%H', (started_at + ?1) / 1000, 'unixepoch') AS INTEGER) AS hour,
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS users
    FROM analytics_sessions
    WHERE started_at >= ?2
    GROUP BY hour
    ORDER BY hour ASC
  `,
  )
    .bind(timezoneShiftMs, start)
    .all();

  const versionResult = await env.DB.prepare(
    `
    SELECT
      COALESCE(NULLIF(version, ''), 'unknown') AS label,
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS users
    FROM analytics_sessions
    WHERE started_at >= ?1
    GROUP BY label
    ORDER BY launches DESC
    LIMIT 10
  `,
  )
    .bind(start)
    .all();

  const gameResult = await env.DB.prepare(
    `
    SELECT
      COALESCE(NULLIF(game_slug, ''), NULLIF(game_id, ''), 'unknown') AS label,
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS users
    FROM analytics_sessions
    WHERE started_at >= ?1
    GROUP BY label
    ORDER BY launches DESC
    LIMIT 10
  `,
  )
    .bind(start)
    .all();

  const placeResult = await env.DB.prepare(
    `
    SELECT
      COALESCE(NULLIF(place_id, ''), 'unknown') AS label,
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS users
    FROM analytics_sessions
    WHERE started_at >= ?1
    GROUP BY label
    ORDER BY launches DESC
    LIMIT 10
  `,
  )
    .bind(start)
    .all();

  const executorResult = await env.DB.prepare(`
    SELECT COALESCE(NULLIF(executor_name, ''), 'Unknown') AS label,
      COUNT(*) AS launches, COUNT(DISTINCT roblox_user_id) AS users
    FROM analytics_sessions WHERE started_at >= ?1
    GROUP BY label ORDER BY launches DESC LIMIT 10
  `).bind(start).all();

  const deviceResult = await env.DB.prepare(
    `
    SELECT
      COALESCE(NULLIF(device, ''), 'unknown') AS label,
      COUNT(*) AS launches,
      COUNT(DISTINCT roblox_user_id) AS users
    FROM analytics_sessions
    WHERE started_at >= ?1
    GROUP BY label
    ORDER BY launches DESC
    LIMIT 10
  `,
  )
    .bind(start)
    .all();

  // The all-time user directory is range-independent and expensive to rebuild.
  // Cache it separately so switching 24h/7d/30d does not rescan every session
  // or reread the Roblox profile cache each time.
  const allUsers = await getCachedOwnerUserDirectory(env);

  const allTimeUniqueUsers = allUsers.length;
  const allTimeDashboardUsers = allUsers.reduce(
    (count, row) => count + (row.dashboardLinked ? 1 : 0),
    0,
  );
  const returningUsers = allUsers.reduce(
    (count, row) => count + (Number(row.launchCount || 0) > 1 ? 1 : 0),
    0,
  );
  const rangeNewUsers = allUsers.reduce(
    (count, row) => count + (Number(row.firstSeenAt || 0) >= start ? 1 : 0),
    0,
  );

  // Recent launches and live sessions are overlaid separately by the Stats Hub.
  // Keeping them out of the historical cache lets the expensive aggregates use
  // a long TTL without making the live dashboard feel stale.

  const sampleRows = resultRows(sampleResult);
  const launchRows = resultRows(launchesResult);
  const launchByBucket = new Map(
    launchRows.map((row) => [Number(row.bucket), row]),
  );
  const sampleByBucket = new Map(
    sampleRows.map((row) => [Number(row.bucket), row]),
  );
  const buckets = [
    ...new Set([...sampleByBucket.keys(), ...launchByBucket.keys()]),
  ].sort((a, b) => a - b);
  const timeline = buckets.map((bucket) => {
    const sample = sampleByBucket.get(bucket) || {};
    const launches = launchByBucket.get(bucket) || {};
    return {
      bucket,
      scriptSessions: Number(sample.script_sessions || 0),
      scriptUsers: Number(sample.script_users || 0),
      dashboardSessions: Number(sample.dashboard_sessions || 0),
      dashboardUsers: Number(sample.dashboard_users || 0),
      launches: Number(launches.launches || 0),
      launchUsers: Number(launches.users || 0),
      dashboardLaunches: Number(launches.dashboard_launches || 0),
    };
  });

  const scriptBlox = await scriptBloxPromise;

  return {
    generatedAt: now,
    scriptBlox,
    range: cfg.range,
    rangeStart: start,
    stepMs: step,
    online: {
      scriptSessions: 0,
      scriptUsers: 0,
      dashboardSessions: 0,
      dashboardUsers: 0,
    },
    allTime: {
      totalLaunches: Number(allTime?.total_launches || 0),
      uniqueUsers: allTimeUniqueUsers,
      dashboardLaunches: Number(allTime?.dashboard_launches || 0),
      dashboardUsers: allTimeDashboardUsers,
      avgSessionMs: Number(allTime?.avg_session_ms || 0),
      totalSeenMs: Number(allTime?.total_seen_ms || 0),
      returningUsers,
      veyraAccounts: Number(accountTotals?.veyra_accounts || 0),
      linkedRobloxAccounts: Number(accountTotals?.linked_roblox_accounts || 0),
    },
    selectedRange: {
      launches: Number(rangeSummary?.launches || 0),
      uniqueUsers: Number(rangeSummary?.unique_users || 0),
      dashboardLaunches: Number(rangeSummary?.dashboard_launches || 0),
      dashboardUsers: Number(rangeSummary?.dashboard_users || 0),
      avgSessionMs: Number(rangeSummary?.avg_session_ms || 0),
      totalSeenMs: Number(rangeSummary?.total_seen_ms || 0),
      newUsers: rangeNewUsers,
    },
    activeWindows: {
      users24h: Number(activityWindows?.users_24h || 0),
      users7d: Number(activityWindows?.users_7d || 0),
      users30d: Number(activityWindows?.users_30d || 0),
      launches24h: Number(activityWindows?.launches_24h || 0),
      launches7d: Number(activityWindows?.launches_7d || 0),
      launches30d: Number(activityWindows?.launches_30d || 0),
    },
    peaks: {
      scriptSessions: Number(peaks?.peak_script_sessions || 0),
      scriptSessionsAt: Number(peaks?.peak_script_sessions_at || 0) || null,
      scriptUsers: Number(peaks?.peak_script_users || 0),
      scriptUsersAt: Number(peaks?.peak_script_users_at || 0) || null,
      dashboardSessions: Number(peaks?.peak_dashboard_sessions || 0),
      dashboardSessionsAt:
        Number(peaks?.peak_dashboard_sessions_at || 0) || null,
      dashboardUsers: Number(peaks?.peak_dashboard_users || 0),
      dashboardUsersAt: Number(peaks?.peak_dashboard_users_at || 0) || null,
    },
    timeline,
    hourly: resultRows(hourlyResult).map((row) => ({
      hour: Number(row.hour || 0),
      launches: Number(row.launches || 0),
      users: Number(row.users || 0),
    })),
    versions: resultRows(versionResult).map((row) => ({
      label: String(row.label || "unknown"),
      launches: Number(row.launches || 0),
      users: Number(row.users || 0),
    })),
    games: resultRows(gameResult).map((row) => ({
      label: String(row.label || "unknown"),
      launches: Number(row.launches || 0),
      users: Number(row.users || 0),
    })),
    places: resultRows(placeResult).map((row) => ({
      label: String(row.label || "unknown"),
      launches: Number(row.launches || 0),
      users: Number(row.users || 0),
    })),
    executors: resultRows(executorResult).map((row) => ({
      label: String(row.label || "Unknown"), launches: Number(row.launches || 0), users: Number(row.users || 0),
    })),
    devices: resultRows(deviceResult).map((row) => ({
      label: String(row.label || "unknown"),
      launches: Number(row.launches || 0),
      users: Number(row.users || 0),
    })),
    allUsers: allUsers.map((row) => ({
      ...row,
      online: false,
    })),
    recent: [],
    onlineSessions: [],
  };
}

async function overlayOwnerRealtimeAnalytics(env, baseAnalytics) {
  const analytics =
    typeof structuredClone === "function"
      ? structuredClone(baseAnalytics)
      : JSON.parse(JSON.stringify(baseAnalytics));

  const [recentResult, onlineResult] = await Promise.all([
    env.DB.prepare(
      `
        SELECT
          session_id,
          roblox_user_id,
          version,
          game_id,
          place_id,
          game_slug,
          device,
          executor_name,
          executor_version,
          started_at,
          last_seen_at,
          dashboard_linked
        FROM analytics_sessions
        ORDER BY started_at DESC
        LIMIT 30
      `,
    ).all(),

    env.DB.prepare(
      `
        SELECT
          p.session_id,
          p.roblox_user_id,
          p.dashboard_linked,
          p.version,
          p.started_at,
          p.last_seen_at,
          a.game_id,
          a.place_id,
          a.game_slug,
          a.device,
          a.executor_name,
          a.executor_version
        FROM runtime_presence p
        LEFT JOIN analytics_sessions a
          ON a.session_id = p.session_id
        ORDER BY p.last_seen_at DESC
      `,
    ).all(),
  ]);

  const recentRows = resultRows(recentResult);
  const onlineRows = resultRows(onlineResult);

  const profileMap = new Map();

  for (const row of analytics.allUsers || []) {
    const userId = String(row?.userId || "");
    if (!userId) continue;

    profileMap.set(userId, {
      username: row?.username || null,
      displayName: row?.displayName || row?.username || null,
      avatarUrl: row?.avatarUrl || null,
    });
  }

  const missingProfileIds = [
    ...new Set(
      [...recentRows, ...onlineRows]
        .map((row) => validRobloxUserId(row?.roblox_user_id))
        .filter(Boolean)
        .filter((id) => !profileMap.has(id)),
    ),
  ];

  if (missingProfileIds.length) {
    const cachedProfiles = await readRobloxProfileCache(env, missingProfileIds);

    for (const [userId, profile] of cachedProfiles) {
      profileMap.set(userId, profile);
    }
  }

  const onlineUserIds = new Set(
    onlineRows.map((row) => String(row?.roblox_user_id || "")).filter(Boolean),
  );

  const dashboardRows = onlineRows.filter(
    (row) => Number(row?.dashboard_linked || 0) === 1,
  );

  analytics.online = {
    scriptSessions: onlineRows.length,
    scriptUsers: onlineUserIds.size,
    dashboardSessions: dashboardRows.length,
    dashboardUsers: new Set(
      dashboardRows
        .map((row) => String(row?.roblox_user_id || ""))
        .filter(Boolean),
    ).size,
  };
  analytics.historicalGeneratedAt = Number(analytics.generatedAt || 0) || null;
  analytics.realtimeGeneratedAt = Date.now();
  analytics.generatedAt = analytics.realtimeGeneratedAt;

  analytics.allUsers = (analytics.allUsers || []).map((row) => ({
    ...row,
    online: onlineUserIds.has(String(row?.userId || "")),
  }));

  analytics.recent = recentRows.map((row) => {
    const robloxUserId = String(row.roblox_user_id || "");

    const profile = profileMap.get(robloxUserId) || {};

    return {
      sessionId: String(row.session_id || ""),
      robloxUserId,
      username: profile.username || null,
      displayName: profile.displayName || profile.username || null,
      avatarUrl: profile.avatarUrl || null,
      version: String(row.version || "unknown"),
      gameId: row.game_id == null ? null : String(row.game_id),
      placeId: row.place_id == null ? null : String(row.place_id),
      gameSlug: row.game_slug == null ? null : String(row.game_slug),
      device: row.device == null ? null : String(row.device),
      executorName: cleanExecutorText(row.executor_name),
      executorVersion: cleanExecutorText(row.executor_version, 32),
      startedAt: Number(row.started_at || 0),
      lastSeenAt: Number(row.last_seen_at || 0),
      dashboardLinked: Number(row.dashboard_linked || 0) === 1,
    };
  });

  analytics.onlineSessions = onlineRows.slice(0, 100).map((row) => {
    const robloxUserId = String(row.roblox_user_id || "");

    const profile = profileMap.get(robloxUserId) || {};

    return {
      sessionId: String(row.session_id || ""),
      robloxUserId,
      username: profile.username || null,
      displayName: profile.displayName || profile.username || null,
      avatarUrl: profile.avatarUrl || null,
      version: String(row.version || "unknown"),
      gameId: row.game_id == null ? null : String(row.game_id),
      placeId: row.place_id == null ? null : String(row.place_id),
      gameSlug: row.game_slug == null ? null : String(row.game_slug),
      device: row.device == null ? null : String(row.device),
      executorName: cleanExecutorText(row.executor_name),
      executorVersion: cleanExecutorText(row.executor_version, 32),
      startedAt: Number(row.started_at || 0),
      lastSeenAt: Number(row.last_seen_at || 0),
      dashboardLinked: Number(row.dashboard_linked || 0) === 1,
    };
  });

  return analytics;
}

async function resolveDashboardUser(env, key) {
  key = normalizeDashboardKey(key);

  if (!DASHBOARD_KEY_RE.test(key)) {
    return null;
  }

  const hash = await sha256Hex(key);

  const user = await env.DB.prepare(
    `
      SELECT
        id,
        discord_id,
        discord_username,
        discord_display_name
      FROM users
      WHERE dashboard_key_hash = ?1
        AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=users.id)
      LIMIT 1
    `,
  )
    .bind(hash)
    .first();
  return user && discordAccessAllowed(env, user.discord_id) ? user : null;
}

async function resolveWebSession(env, token) {
  token = String(token || "");

  if (!token.startsWith("VS_")) {
    return null;
  }

  const hash = await sha256Hex(token);

  const now = Date.now();

  const user = await env.DB.prepare(
    `
      SELECT
        u.id,
        u.discord_id,
        u.discord_username,
        u.discord_display_name
      FROM web_sessions s
      JOIN users u
        ON u.id = s.user_id
      WHERE s.token_hash = ?1
        AND s.expires_at > ?2
        AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=u.id)
      LIMIT 1
    `,
  )
    .bind(hash, now)
    .first();
  return user && discordAccessAllowed(env, user.discord_id) ? user : null;
}

async function resolveRobloxAccount(env, userId, robloxUserId) {
  robloxUserId = String(robloxUserId || "").trim();

  if (!/^\d+$/.test(robloxUserId)) {
    return null;
  }

  return await env.DB.prepare(
    `
      SELECT
        roblox_user_id,
        username,
        display_name
      FROM roblox_accounts
      WHERE veyra_user_id = ?1
        AND roblox_user_id = ?2
      LIMIT 1
    `,
  )
    .bind(String(userId), robloxUserId)
    .first();
}

async function resolveDashboardLink(env, dashboardKey, robloxUserId) {
  dashboardKey = normalizeDashboardKey(dashboardKey);

  robloxUserId = String(robloxUserId || "").trim();

  if (!DASHBOARD_KEY_RE.test(dashboardKey) || !/^\d+$/.test(robloxUserId)) {
    return null;
  }

  const hash = await sha256Hex(dashboardKey);

  const linked = await env.DB.prepare(
    `
      SELECT
        u.id AS veyra_user_id, u.discord_id
      FROM users u
      JOIN roblox_accounts r
        ON r.veyra_user_id = u.id
      WHERE u.dashboard_key_hash = ?1
        AND r.roblox_user_id = ?2
        AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=u.id)
      LIMIT 1
    `,
  )
    .bind(hash, robloxUserId)
    .first();
  return linked && discordAccessAllowed(env, linked.discord_id) ? linked : null;
}


async function liveAuthorizationValid(env, identity) {
  if (!identity || !/^[a-f0-9]{64}$/.test(String(identity.authHash || ""))) return false;
  if (identity.role !== "runtime" && identity.role !== "dashboard") return false;
  const row = identity.role === "runtime"
    ? await env.DB.prepare(`SELECT u.id, u.discord_id FROM users u JOIN roblox_accounts r ON r.veyra_user_id = u.id
        WHERE u.id = ?1 AND r.roblox_user_id = ?2 AND u.dashboard_key_hash = ?3
          AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id=?1) LIMIT 1`)
        .bind(identity.userId, identity.robloxUserId, identity.authHash).first()
    : await env.DB.prepare(`SELECT s.user_id, u.discord_id FROM web_sessions s JOIN users u ON u.id=s.user_id JOIN roblox_accounts r ON r.veyra_user_id = s.user_id
        WHERE s.user_id = ?1 AND r.roblox_user_id = ?2 AND s.token_hash = ?3 AND s.expires_at > ?4
          AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id=?1) LIMIT 1`)
        .bind(identity.userId, identity.robloxUserId, identity.authHash, Date.now()).first();
  return Boolean(row && discordAccessAllowed(env, row.discord_id));
}

async function createLiveToken(env, userId, role, robloxUserId, authHash) {
  const payload = {
    version: 1,
    authHash,

    userId: String(userId),

    role: String(role),

    robloxUserId: String(robloxUserId),

    expiresAt: Math.floor(Date.now() / 1000) + 60,

    nonce: crypto.randomUUID(),
  };

  const encoded = base64urlText(JSON.stringify(payload));

  const unsigned = `VL1.${encoded}`;

  const signature = await sign(env.LIVE_TOKEN_SECRET, unsigned);

  return `${unsigned}.${signature}`;
}

async function verifyLiveToken(env, token) {
  const parts = String(token || "").split(".");

  if (parts.length !== 3 || parts[0] !== "VL1") {
    return null;
  }

  const unsigned = `${parts[0]}.${parts[1]}`;

  const expected = await sign(env.LIVE_TOKEN_SECRET, unsigned);

  if (!safeEqual(parts[2], expected)) {
    return null;
  }

  let payload;

  try {
    payload = JSON.parse(decodeBase64url(parts[1]));
  } catch {
    return null;
  }

  if (
    !payload ||
    payload.version !== 1 ||
    !/^[a-f0-9]{64}$/.test(String(payload.authHash || "")) ||
    !payload.userId ||
    !payload.role ||
    !payload.robloxUserId ||
    !/^\d+$/.test(String(payload.robloxUserId)) ||
    !Number.isFinite(payload.expiresAt)
  ) {
    return null;
  }

  if (payload.role !== "runtime" && payload.role !== "dashboard") {
    return null;
  }

  if (Math.floor(Date.now() / 1000) > payload.expiresAt) {
    return null;
  }

  return payload;
}

/*
  Runtime Presence
*/

async function upsertRuntimePresence(
  env,
  { sessionId, robloxUserId, dashboardLinked, version, userId = null },
) {
  await ensureAnalyticsSchema(env);

  const now = Date.now();

  const written = await env.DB.prepare(
    `
      INSERT INTO runtime_presence (
        session_id,
        roblox_user_id,
        dashboard_linked,
        version,
        started_at,
        last_seen_at
      )
      SELECT ?1, ?2, ?3, ?4, ?5, ?6
      WHERE ?3 = 0 OR EXISTS (
        SELECT 1 FROM runtime_session_owners o JOIN users u ON u.id=o.veyra_user_id
        WHERE o.session_id=?1 AND o.roblox_user_id=?2 AND u.id=?7
          AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=u.id)
      )

      ON CONFLICT(session_id)
      DO UPDATE SET
        roblox_user_id =
          excluded.roblox_user_id,

        dashboard_linked =
          excluded.dashboard_linked,

        version =
          excluded.version,

        last_seen_at =
          excluded.last_seen_at
      WHERE runtime_presence.roblox_user_id = excluded.roblox_user_id
    `,
  )
    .bind(
      String(sessionId),
      String(robloxUserId),
      dashboardLinked ? 1 : 0,
      String(version || "unknown"),
      now,
      now,
      userId,
    )
    .run();
  return Number(written?.meta?.changes || 0) > 0;
}

async function touchLinkedRuntimePresence(
  env,
  { sessionId, robloxUserId, version, userId },
) {
  if (!PRESENCE_SESSION_RE.test(String(sessionId || ""))) {
    return;
  }

  return await upsertRuntimePresence(env, {
    sessionId: String(sessionId),

    robloxUserId: String(robloxUserId),

    dashboardLinked: true,
    userId,

    version: String(version || "unknown"),
  });
}

async function removeRuntimePresence(env, sessionId, robloxUserId) {
  if (!PRESENCE_SESSION_RE.test(String(sessionId || ""))) {
    return false;
  }

  const result = await env.DB.prepare(
    `
        DELETE FROM runtime_presence
        WHERE session_id = ?1 AND roblox_user_id = ?2
      `,
  )
    .bind(String(sessionId), String(robloxUserId || ""))
    .run();

  return Number(result?.meta?.changes || 0) > 0;
}

async function cleanupRuntimePresence(env, { force = false } = {}) {
  const now = Date.now();

  if (!force && now < runtimePresenceCleanupNextAt) {
    return false;
  }

  runtimePresenceCleanupNextAt = now + RUNTIME_PRESENCE_CLEANUP_MIN_MS;

  const linkedStaleBefore = now - LINKED_STALE_MS;

  const unlinkedStaleBefore = now - UNLINKED_STALE_MS;

  await env.DB.prepare(
    `
      DELETE FROM runtime_presence

      WHERE
        (
          dashboard_linked = 1
          AND last_seen_at < ?1
        )

        OR

        (
          dashboard_linked = 0
          AND last_seen_at < ?2
        )
    `,
  )
    .bind(linkedStaleBefore, unlinkedStaleBefore)
    .run();

  return true;
}

async function getRuntimePresenceStats(env, { cleanup = true } = {}) {
  if (cleanup) {
    await cleanupRuntimePresence(env);
  }

  const row = await env.DB.prepare(
    `
        SELECT

          COUNT(*) AS script_sessions,

          COUNT(
            DISTINCT roblox_user_id
          ) AS script_users,

          SUM(
            CASE
              WHEN dashboard_linked = 1
              THEN 1
              ELSE 0
            END
          ) AS dashboard_sessions,

          COUNT(
            DISTINCT CASE
              WHEN dashboard_linked = 1
              THEN roblox_user_id
            END
          ) AS dashboard_users

        FROM runtime_presence
      `,
  ).first();

  return {
    scriptSessions: Number(row?.script_sessions || 0),

    scriptUsers: Number(row?.script_users || 0),

    dashboardSessions: Number(row?.dashboard_sessions || 0),

    dashboardUsers: Number(row?.dashboard_users || 0),
  };
}

async function getRuntimePresenceState(env, sessionId) {
  return await env.DB.prepare(
    `
      SELECT
        roblox_user_id,
        dashboard_linked
      FROM runtime_presence
      WHERE session_id = ?1
      LIMIT 1
    `,
  )
    .bind(String(sessionId))
    .first();
}

function runtimeStatsEqual(a, b) {
  if (!a || !b) {
    return false;
  }

  return (
    Number(a.scriptSessions || 0) === Number(b.scriptSessions || 0) &&
    Number(a.scriptUsers || 0) === Number(b.scriptUsers || 0) &&
    Number(a.dashboardSessions || 0) === Number(b.dashboardSessions || 0) &&
    Number(a.dashboardUsers || 0) === Number(b.dashboardUsers || 0)
  );
}

function makeStatsMessage(stats) {
  return JSON.stringify({
    type: "stats_update",
    generatedAt: Date.now(),
    online: stats,
  });
}

async function notifyStatsHub(env, reason = "presence-change", stats = null) {
  if (!env.STATS) {
    return;
  }

  try {
    const id = env.STATS.idFromName("global");

    const stub = env.STATS.get(id);

    await stub.fetch("https://veyra-stats.internal/refresh", {
      method: "POST",

      headers: {
        "Content-Type": "application/json",
      },

      body: JSON.stringify({
        reason,
        stats: stats && typeof stats === "object" ? stats : null,
      }),
    });
  } catch (error) {
    console.error("Stats hub refresh error:", error);
  }
}

/*
  Admin stats WebSocket Durable Object

  The Discord bot keeps one inbound WebSocket
  connected here. Presence changes are pushed
  immediately instead of polling /admin/stats.
*/

export class VeyraStatsHub {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;

    // These caches are intentionally in-memory. The owner dashboard keeps the
    // global stats DO warm in normal use, and a cold restart simply causes one
    // fresh analytics read before caching resumes.
    this.ownerAnalyticsCache = new Map();
    this.ownerAnalyticsInFlight = new Map();
    this.ownerAnalyticsRealtimeCache = new Map();
    this.dataCacheRevision = 0;
    this.ownerAnalyticsTail = Promise.resolve();
  }

  enqueueOwnerAnalytics(operation) {
    // Coordinate the entire pipeline, including profile and persistent-cache
    // writes. Keep the event loop open so earlier external I/O can finish.
    const task = this.ownerAnalyticsTail.then(operation);
    this.ownerAnalyticsTail = task.then(() => undefined, () => undefined);
    return task;
  }

  getCachedOwnerAnalytics(rangeValue, timezoneOffsetMinutes) {
    return this.enqueueOwnerAnalytics(() => this.readOwnerAnalytics(rangeValue, timezoneOffsetMinutes));
  }

  async readOwnerAnalytics(rangeValue, timezoneOffsetMinutes) {
    const revision = this.dataCacheRevision;
    const range = analyticsRangeConfig(rangeValue).range;

    const tz = Math.max(
      -840,
      Math.min(840, Number(timezoneOffsetMinutes) || 0),
    );

    const ttlMs = ownerAnalyticsCacheTtlMs(range);

    const key = `v${OWNER_ANALYTICS_CACHE_VERSION}:${range}:${tz}`;

    const now = Date.now();

    let baseAnalytics = null;
    let baseCachedAt = 0;
    let source = "fresh";

    const memoryCached = this.ownerAnalyticsCache.get(key);

    if (memoryCached && now - Number(memoryCached.cachedAt || 0) < ttlMs) {
      baseAnalytics = memoryCached.analytics;
      baseCachedAt = Number(memoryCached.cachedAt || now);
      source = "memory";
    }

    if (!baseAnalytics) {
      const persistent = await readPersistentOwnerAnalyticsCache(
        this.env,
        key,
        now,
      );

      if (persistent) {
        baseAnalytics = persistent.analytics;
        baseCachedAt = Number(persistent.generatedAt || now);
        source = "d1-cache";

        this.ownerAnalyticsCache.set(key, {
          analytics: baseAnalytics,
          cachedAt: baseCachedAt,
        });
      }
    }

    if (!baseAnalytics) {
      const existing = this.ownerAnalyticsInFlight.get(key);

      if (existing) {
        baseAnalytics = await existing;

        const entry = this.ownerAnalyticsCache.get(key);

        baseCachedAt = Number(entry?.cachedAt || Date.now());
        source = "coalesced";
      } else {
        const promise = getOwnerAnalytics(this.env, range, tz);

        this.ownerAnalyticsInFlight.set(key, promise);

        try {
          baseAnalytics = await promise;
          if (revision !== this.dataCacheRevision) return this.readOwnerAnalytics(rangeValue, timezoneOffsetMinutes);

          const persisted = await writePersistentOwnerAnalyticsCache(
            this.env,
            key,
            baseAnalytics,
            ttlMs,
          );
          if (revision !== this.dataCacheRevision) return this.readOwnerAnalytics(rangeValue, timezoneOffsetMinutes);

          baseCachedAt = Number(persisted.generatedAt || Date.now());

          this.ownerAnalyticsCache.set(key, {
            analytics: baseAnalytics,
            cachedAt: baseCachedAt,
          });

          this.ownerAnalyticsRealtimeCache.delete(key);
          source = "fresh";
        } finally {
          this.ownerAnalyticsInFlight.delete(key);
        }
      }
    }

    // Keep the memory cache bounded even if someone manually requests many
    // timezone offsets or ranges. Persistent D1 cache survives DO hibernation.
    if (this.ownerAnalyticsCache.size > 12) {
      const oldest = [...this.ownerAnalyticsCache.entries()]
        .sort(
          (a, b) => Number(a[1]?.cachedAt || 0) - Number(b[1]?.cachedAt || 0),
        )
        .slice(0, this.ownerAnalyticsCache.size - 12);

      for (const [oldKey] of oldest) {
        this.ownerAnalyticsCache.delete(oldKey);
        this.ownerAnalyticsRealtimeCache.delete(oldKey);
      }
    }

    let analytics = null;
    let realtimeHit = false;

    const realtimeCached = this.ownerAnalyticsRealtimeCache.get(key);

    if (
      realtimeCached &&
      now - Number(realtimeCached.cachedAt || 0) <
        OWNER_ANALYTICS_REALTIME_CACHE_MS
    ) {
      analytics = realtimeCached.analytics;
      realtimeHit = true;
    } else {
      analytics = await overlayOwnerRealtimeAnalytics(this.env, baseAnalytics);
      if (revision !== this.dataCacheRevision) return this.readOwnerAnalytics(rangeValue, timezoneOffsetMinutes);

      this.ownerAnalyticsRealtimeCache.set(key, {
        analytics,
        cachedAt: Date.now(),
      });
    }

    return {
      analytics,
      cache: {
        hit: source !== "fresh",
        source,
        ageMs: Math.max(0, Date.now() - baseCachedAt),
        ttlMs,
        persistent: true,
        realtimeHit,
        realtimeTtlMs: OWNER_ANALYTICS_REALTIME_CACHE_MS,
      },
    };
  }

  async scheduleSafetyAlarm() {
    const sockets = this.ctx.getWebSockets("stats");

    if (!sockets.length) {
      try {
        await this.ctx.storage.deleteAlarm();
      } catch {}

      return;
    }

    // No D1 read is needed here. Explicit presence changes already refresh the
    // stats hub; this alarm exists only as a coarse stale-row safety sweep.
    const now = Date.now();
    const desired = now + STATS_SAFETY_SWEEP_MS;

    let current = null;

    try {
      current = await this.ctx.storage.getAlarm();
    } catch {}

    if (
      !Number.isFinite(Number(current)) ||
      Number(current) <= now ||
      Number(current) > desired + 30 * 1000
    ) {
      await this.ctx.storage.setAlarm(desired);
    }
  }

  async refreshStats({
    force = false,
    target = null,
    statsOverride = null,
  } = {}) {
    const sockets = this.ctx.getWebSockets("stats");

    // Persist refreshed counters even when the bot has temporarily lost its
    // stats socket, so its HTTPS fallback does not read obsolete lastStats.

    const stats =
      statsOverride && typeof statsOverride === "object"
        ? statsOverride
        : await getRuntimePresenceStats(this.env);

    let previous = null;

    try {
      previous = await this.ctx.storage.get("lastStats");
    } catch {}

    const changed = !runtimeStatsEqual(previous, stats);

    if (target || force || changed) {
      const message = makeStatsMessage(stats);

      if (target) {
        try {
          target.send(message);
        } catch {}
      } else {
        for (const ws of sockets) {
          try {
            ws.send(message);
          } catch {}
        }
      }
    }

    if (force || changed || !previous) {
      try {
        await this.ctx.storage.put("lastStats", stats);
      } catch {}
    }

    await this.scheduleSafetyAlarm();

    return stats;
  }

  async fetch(request) {
    if (new URL(request.url).pathname === '/invalidate-user-data' && request.method === 'POST') {
      await this.enqueueOwnerAnalytics(async () => {
        this.dataCacheRevision++;
        this.ownerAnalyticsCache.clear();
        this.ownerAnalyticsRealtimeCache.clear();
        this.ownerAnalyticsInFlight.clear();
        await this.env.DB.prepare('DELETE FROM owner_analytics_cache').run();
      });
      return new Response(null, {status: 204});
    }
    const url = new URL(request.url);

    const upgrade = request.headers.get("Upgrade");

    if (upgrade && upgrade.toLowerCase() === "websocket") {
      const pair = new WebSocketPair();

      const [client, server] = Object.values(pair);

      this.ctx.acceptWebSocket(server, ["stats"]);

      server.serializeAttachment({
        role: "stats-bot",
        connectedAt: Date.now(),
      });

      await this.refreshStats({
        force: true,
        target: server,
      });

      return new Response(null, {
        status: 101,
        webSocket: client,
      });
    }

    if (request.method === "POST" && url.pathname === "/refresh") {
      let body = {};

      try {
        body = await request.json();
      } catch {}

      const suppliedStats =
        body?.stats && typeof body.stats === "object" ? body.stats : null;

      await this.refreshStats({
        statsOverride: suppliedStats,
      });

      return new Response(null, { status: 204 });
    }

    if (request.method === "GET" && url.pathname === "/current-stats") {
      let stats = null;

      try {
        stats = await this.ctx.storage.get("lastStats");
      } catch {}

      if (!stats) {
        stats = await getRuntimePresenceStats(this.env);

        try {
          await this.ctx.storage.put("lastStats", stats);
        } catch {}
      }

      return new Response(
        JSON.stringify({
          ok: true,
          generatedAt: Date.now(),
          online: stats,
        }),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
          },
        },
      );
    }

    if (request.method === "GET" && url.pathname === "/owner-analytics") {
      try {
        const payload = await this.getCachedOwnerAnalytics(
          url.searchParams.get("range") || "24h",
          url.searchParams.get("tzOffsetMinutes") || 0,
        );

        return new Response(JSON.stringify(payload), {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
          },
        });
      } catch (error) {
        return new Response(
          JSON.stringify({
            error: "Owner analytics cache failed",

          }),
          {
            status: 500,
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Cache-Control": "no-store",
            },
          },
        );
      }
    }

    /*
      Global Veyra update broadcast.

      Called by the R2 release Queue consumer when greedy-growers.luau is
      overwritten. No D1 writes are performed here. We only read currently
      linked runtime targets, then forward one tiny message to each existing
      per-user LIVE Durable Object.
    */
    if (request.method === "POST" && url.pathname === "/broadcast-update") {
      let body = {};

      try {
        body = await request.json();
      } catch {}

      const version = String(body?.version || "")
        .trim()
        .slice(0, 32);

      const sourceETag = String(body?.sourceETag || "")
        .trim()
        .slice(0, 128);

      if (!/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9._-]+)?$/.test(version)) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "Invalid update version",
          }),
          {
            status: 400,
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Cache-Control": "no-store",
            },
          },
        );
      }

      let previous = null;

      try {
        previous = await this.ctx.storage.get("lastUpdateBroadcast");
      } catch {}

      if (
        previous &&
        previous.version === version &&
        (!sourceETag ||
          !previous.sourceETag ||
          previous.sourceETag === sourceETag)
      ) {
        return new Response(
          JSON.stringify({
            ok: true,
            duplicate: true,
            version,
            delivered: 0,
            targets: 0,
          }),
          {
            status: 200,
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Cache-Control": "no-store",
            },
          },
        );
      }

      const activeAfter = Date.now() - LINKED_STALE_MS;

      const query = await this.env.DB.prepare(
        `
            SELECT DISTINCT
              r.veyra_user_id AS veyra_user_id,
              p.roblox_user_id AS roblox_user_id
            FROM runtime_presence p
            JOIN roblox_accounts r
              ON r.roblox_user_id = p.roblox_user_id
            WHERE p.dashboard_linked = 1
              AND p.last_seen_at >= ?1
          `,
      )
        .bind(activeAfter)
        .all();

      const rows = Array.isArray(query?.results) ? query.results : [];

      const targets = new Map();

      for (const row of rows) {
        const veyraUserId = String(row?.veyra_user_id || "").trim();

        const robloxUserId = String(row?.roblox_user_id || "").trim();

        if (!veyraUserId || !/^\d+$/.test(robloxUserId)) {
          continue;
        }

        targets.set(`${veyraUserId}:${robloxUserId}`, {
          veyraUserId,
          robloxUserId,
        });
      }

      const updatePayload = {
        version,
        message:
          typeof body?.message === "string"
            ? body.message.slice(0, 240)
            : "A new Veyra update is available.",
        releasedAt: Number(body?.releasedAt) || Date.now(),
      };

      let delivered = 0;
      let targetErrors = 0;

      await Promise.all(
        [...targets.values()].map(async ({ veyraUserId, robloxUserId }) => {
          try {
            const liveId = this.env.LIVE.idFromName(
              `user:${veyraUserId}:roblox:${robloxUserId}`,
            );

            const liveStub = this.env.LIVE.get(liveId);

            const response = await liveStub.fetch(
              "https://veyra-live.internal/broadcast-update",
              {
                method: "POST",
                headers: {
                  "Content-Type": "application/json",
                },
                body: JSON.stringify(updatePayload),
              },
            );

            if (!response.ok) {
              targetErrors++;
              return;
            }

            const result = await response.json().catch(() => null);

            delivered += Number(result?.delivered || 0);
          } catch {
            targetErrors++;
          }
        }),
      );

      try {
        await this.ctx.storage.put("lastUpdateBroadcast", {
          version,
          sourceETag: sourceETag || null,
          delivered,
          targets: targets.size,
          targetErrors,
          broadcastAt: Date.now(),
        });
      } catch {}

      return new Response(
        JSON.stringify({
          ok: true,
          duplicate: false,
          version,
          delivered,
          targets: targets.size,
          targetErrors,
        }),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
          },
        },
      );
    }

    return new Response("Not found", { status: 404 });
  }

  async alarm() {
    await this.refreshStats();
  }

  async webSocketMessage(ws, message) {
    let parsed = null;

    try {
      if (typeof message === "string") {
        parsed = JSON.parse(message);
      }
    } catch {}

    if (parsed?.type === "get_stats") {
      await this.refreshStats({
        force: true,
        target: ws,
      });
    }
  }

  async webSocketClose(ws, code, reason) {
    try {
      ws.close(code, reason);
    } catch {}

    await this.scheduleSafetyAlarm();
  }

  async webSocketError(ws) {
    try {
      ws.close(1011, "WebSocket error");
    } catch {}

    await this.scheduleSafetyAlarm();
  }
}

/*
  Live WebSocket Durable Object
*/

async function handleRuntimePresence(request, env, {rateLimit = true, proofStore = null} = {}) {
      if (!env.PRESENCE_TOKEN_SECRET || !env.PRESENCE_RATE_LIMITER) {
        return json(request, { ok: false, error: "Presence unavailable" }, 503, env);
      }
      if (rateLimit && await presenceRateLimited(env, "runtime-presence", request)) {
        return json(request, { ok: false, error: "Too many presence requests" }, 429, env);
      }
      const parsed = await limitedJsonBody(request);
      if (parsed.tooLarge) {
        return json(
          request,
          { ok: false, error: "Request body too large" },
          413,
          env,
        );
      }
      const body = parsed.body;

      const sessionId = String(body?.sessionId || "").trim();

      const robloxUserId = String(body?.robloxUserId || "").trim();

      const version = String(body?.version || "unknown")
        .trim()
        .slice(0, 32);

      const gameId = cleanAnalyticsText(body?.gameId, 32);
      const placeId = cleanAnalyticsText(body?.placeId, 32);
      const gameSlug = cleanAnalyticsText(body?.gameSlug, 64);
      const device = cleanAnalyticsText(body?.device, 24);
      const executorName = cleanExecutorText(body?.executorName);
      const executorVersion = cleanExecutorText(body?.executorVersion, 32);

      if (!PRESENCE_SESSION_RE.test(sessionId)) {
        return json(
          request,
          {
            ok: false,

            error: "Invalid sessionId",
          },
          400,
          env,
        );
      }

      if (!/^\d+$/.test(robloxUserId)) {
        return json(
          request,
          {
            ok: false,

            error: "Invalid robloxUserId",
          },
          400,
          env,
        );
      }

      const dashboardKey = bearerToken(request);

      let dashboardLinked = false;

      let veyraUserId = null;

      if (dashboardKey) {
        try {
          const linked = await resolveDashboardLink(
            env,
            dashboardKey,
            robloxUserId,
          );

          if (linked) {
            dashboardLinked = true;

            veyraUserId = linked.veyra_user_id;
          }
        } catch (error) {
          console.error("Dashboard presence validation error:", error);
        }
      }

      if (stagingRestricted(env) && !dashboardLinked) {
        return json(request, {ok: false, error: 'An invited dashboard account is required.'}, 403, env);
      }

      try {
        const previousPresence = await getRuntimePresenceState(env, sessionId);
        const recordedSession = previousPresence
          ? null
          : await env.DB.prepare(
              "SELECT roblox_user_id FROM analytics_sessions WHERE session_id = ?1 UNION ALL SELECT roblox_user_id FROM runtime_presence WHERE session_id = ?1 LIMIT 1",
            )
              .bind(sessionId)
              .first();
        const existingRobloxUserId =
          previousPresence?.roblox_user_id || recordedSession?.roblox_user_id;
        if (
          existingRobloxUserId &&
          String(existingRobloxUserId) !== robloxUserId
        ) {
          return json(
            request,
            {
              ok: false,
              error: "Session ID already belongs to another Roblox ID",
            },
            409,
            env,
          );
        }

        let suppliedPresenceToken = request.headers.get("X-Presence-Token") || "";
        if (existingRobloxUserId && !suppliedPresenceToken && /^[a-f0-9]{64}$/.test(String(body?.resumeNonce || ""))) {
          // Recover a lost initial ACK using a separate random client proof.
          // A public session ID alone never grants signed heartbeat access.
          if (proofStore) suppliedPresenceToken = await proofStore.resumePresenceToken(body);
          else if (env.LIVE) {
            const stub=env.LIVE.get(env.LIVE.idFromName("presence:"+sessionId));
            const recovered=await stub.fetch("https://presence.internal/resume-presence",{method:"POST",body:JSON.stringify(body)});
            if (recovered.ok) suppliedPresenceToken=(await recovered.json()).presenceToken || "";
          }
        }
        // A currently valid dashboard credential can bootstrap its own owned
        // session after HTTP telemetry created the history row. Anonymous
        // resumes still require the signed token or the independent proof.
        if ((existingRobloxUserId && !dashboardLinked && env.REQUIRE_PRESENCE_TOKEN === "true") || suppliedPresenceToken) {
          if (!(await validPresenceToken(env, suppliedPresenceToken, sessionId, robloxUserId))) {
            return json(request, { ok: false, error: "Invalid presence token" }, 401, env);
          }
        }
        if (veyraUserId && !(await claimRuntimeSession(env, veyraUserId, robloxUserId, sessionId))) {
          return json(request, {ok: false, error: 'Session belongs to another account'}, 409, env);
        }

        const written = await upsertRuntimePresence(env, {
          sessionId,
          robloxUserId,
          dashboardLinked,
          userId: veyraUserId,
          version,
        });
        if (!written) return json(request, {ok: false, error: "Session ID already belongs to another Roblox ID"}, 409, env);

        await upsertAnalyticsSession(env, {
          sessionId,
          robloxUserId,
          dashboardLinked,
          userId: veyraUserId,
          version,
          gameId,
          placeId,
          gameSlug,
          device,
          executorName,
          executorVersion,
        });

        const stateChanged =
          !previousPresence ||
          String(previousPresence.roblox_user_id || "") !== robloxUserId ||
          Number(previousPresence.dashboard_linked || 0) !==
            (dashboardLinked ? 1 : 0);

        if (stateChanged) {
          // Concurrency samples only need to change when presence membership or
          // dashboard-link state changes. Heartbeats do not change the counts.
          const stats = await recordAnalyticsSnapshot(env);

          await notifyStatsHub(env, "runtime-presence-change", stats);
        }
      } catch (error) {
        return json(
          request,
          {
            ok: false,

            error: "Presence update failed",
          },
          500,
          env,
        );
      }

      const presenceToken = await issuePresenceToken(env, sessionId, robloxUserId);
      if (/^[a-f0-9]{64}$/.test(String(body?.resumeNonce || ""))) {
        const proof={sessionId,robloxUserId,resumeNonce:body.resumeNonce,presenceToken};
        if (proofStore) await proofStore.rememberPresenceProof(proof);
        else if (env.LIVE) {
          const stub=env.LIVE.get(env.LIVE.idFromName("presence:"+sessionId));
          await stub.fetch("https://presence.internal/remember-presence",{method:"POST",body:JSON.stringify(proof)});
        }
      }
      return json(
        request,
        {
          ok: true,

          dashboardLinked,

          veyraUserId,

          presenceToken,

          heartbeatSeconds: dashboardLinked
            ? LINKED_HTTP_HEARTBEAT_SECONDS
            : UNLINKED_HEARTBEAT_SECONDS,

          staleSeconds: dashboardLinked
            ? LINKED_STALE_MS / 1000
            : UNLINKED_STALE_MS / 1000,

          wsPresence: dashboardLinked,
        },
        undefined,
        env,
      );
}

async function handleRuntimePresenceDisconnect(request, env, {rateLimit = true} = {}) {
      if (!env.PRESENCE_TOKEN_SECRET || !env.PRESENCE_RATE_LIMITER) {
        return json(request, { ok: false, error: "Presence unavailable" }, 503, env);
      }
      if (await presenceRateLimited(env, "runtime-presence-disconnect", request)) {
        return json(request, { ok: false, error: "Too many presence requests" }, 429, env);
      }
      const parsed = await limitedJsonBody(request);
      if (parsed.tooLarge) {
        return json(
          request,
          { ok: false, error: "Request body too large" },
          413,
          env,
        );
      }
      const body = parsed.body;

      const sessionId = String(body?.sessionId || "").trim();
      if (!PRESENCE_SESSION_RE.test(sessionId)) {
        return json(
          request,
          { ok: false, error: "Invalid sessionId" },
          400,
          env,
        );
      }

      try {
        const recordedSession = await env.DB.prepare(
          "SELECT roblox_user_id FROM analytics_sessions WHERE session_id = ?1 UNION ALL SELECT roblox_user_id FROM runtime_presence WHERE session_id = ?1 LIMIT 1",
        ).bind(sessionId).first();
        if (stagingRestricted(env) && !(recordedSession && await resolveDashboardLink(env, bearerToken(request), String(recordedSession.roblox_user_id)))) {
          return json(request, {ok: false, error: 'An invited dashboard account is required.'}, 403, env);
        }
        const suppliedPresenceToken = request.headers.get("X-Presence-Token") || "";
        if (recordedSession && (env.REQUIRE_PRESENCE_TOKEN === "true" || suppliedPresenceToken)) {
          if (!(await validPresenceToken(env, suppliedPresenceToken, sessionId, String(recordedSession.roblox_user_id)))) {
            return json(request, { ok: false, error: "Invalid presence token" }, 401, env);
          }
        }
        const now = Date.now();
        await env.DB.prepare(
          `
          UPDATE analytics_sessions
          SET last_seen_at = MAX(last_seen_at, ?2)
          WHERE session_id = ?1
        `,
        )
          .bind(sessionId, now)
          .run();

        const removed = await removeRuntimePresence(env, sessionId, recordedSession?.roblox_user_id);
        if (removed) {
          const stats = await recordAnalyticsSnapshot(env);
          await notifyStatsHub(env, "runtime-presence-disconnect", stats);
        }
        return json(request, { ok: true, removed }, undefined, env);
      } catch (error) {
        return json(
          request,
          {
            ok: false,
            error: "Presence disconnect failed",
          },
          500,
          env,
        );
      }
}

export class VeyraLiveSession {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    const internalUrl = new URL(request.url);
    if (internalUrl.pathname === "/presence-ws") return this.acceptPresenceSocket(request);
    if (request.method === "POST" && ["/resume-presence","/remember-presence"].includes(internalUrl.pathname)) {
      const body=await boundedJson(request);
      if (internalUrl.pathname === "/remember-presence") {
        const ok=await this.rememberPresenceProof(body);
        return Response.json({ok},{status:ok?200:401});
      }
      const presenceToken=await this.resumePresenceToken(body);
      return Response.json({presenceToken},{status:presenceToken?200:401});
    }

    /*
      Internal release broadcast.

      This route is reached only through the LIVE Durable Object binding from
      the global stats/update hub; it is never exposed as a public Worker route.
      It reuses the already-open runtime WebSocket, so clients do not need a
      second socket just for update notifications.
    */
    if (
      request.method === "POST" &&
      internalUrl.pathname === "/broadcast-update"
    ) {
      let body = {};

      try {
        body = await request.json();
      } catch {}

      const version = String(body?.version || "")
        .trim()
        .slice(0, 32);

      if (!/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9._-]+)?$/.test(version)) {
        return new Response(
          JSON.stringify({
            ok: false,
            error: "Invalid update version",
          }),
          {
            status: 400,
            headers: {
              "Content-Type": "application/json; charset=utf-8",
              "Cache-Control": "no-store",
            },
          },
        );
      }

      const runtimes = this.ctx.getWebSockets("runtime");

      const message = JSON.stringify({
        type: "update_available",
        version,
        message:
          typeof body?.message === "string"
            ? body.message.slice(0, 240)
            : "A new Veyra update is available.",
        releasedAt: Number(body?.releasedAt) || Date.now(),
      });

      let delivered = 0;

      for (const runtime of runtimes) {
        if (!(await this.socketAuthorized(runtime))) continue;
        try {
          runtime.send(message);
          delivered++;
        } catch {}
      }

      return new Response(
        JSON.stringify({
          ok: true,
          delivered,
        }),
        {
          status: 200,
          headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
          },
        },
      );
    }

    const upgrade = request.headers.get("Upgrade");

    if (!upgrade || upgrade.toLowerCase() !== "websocket") {
      return new Response("Expected WebSocket", {
        status: 426,
      });
    }

    const role = request.headers.get("X-Veyra-Role");

    const userId = request.headers.get("X-Veyra-User-Id");

    const robloxUserId = request.headers.get("X-Veyra-Roblox-User-Id");

    const liveUrl = new URL(request.url);

    const runtimeSessionId = String(
      liveUrl.searchParams.get("sid") || "",
    ).slice(0, 96);

    const clientAttempt = String(
      liveUrl.searchParams.get("attempt") || "",
    ).slice(0, 32);

    const clientReason = String(liveUrl.searchParams.get("reason") || "").slice(
      0,
      96,
    );

    if (role !== "runtime" && role !== "dashboard") {
      return new Response("Invalid live role", {
        status: 403,
      });
    }

    if (!userId || !robloxUserId || !/^\d+$/.test(String(robloxUserId))) {
      return new Response("Invalid live identity", {
        status: 403,
      });
    }

    const authHash = request.headers.get("X-Veyra-Auth-Hash");
    if (!(await liveAuthorizationValid(this.env, {role, userId, robloxUserId, authHash}))) {
      return new Response("Live access revoked", {status: 401});
    }
    const pair = new WebSocketPair();

    const [client, server] = Object.values(pair);

    this.ctx.acceptWebSocket(server, [role]);

    const connectedAt = Date.now();

    server.serializeAttachment({
      role,
      userId,
      robloxUserId,
      authHash,

      connectedAt,

      runtimePresenceSessionId: null,

      clientRuntimeSessionId: runtimeSessionId || null,

      clientAttempt: clientAttempt || null,

      clientReason: clientReason || null,

      runtimePresenceUpdatedAt: 0,
    });

    await this.scheduleAuthorizationCheck();

    console.log("[LIVE WS OPEN]", {
      role,
      robloxUserId,
      connectedAt,
      runtimeSessionId: runtimeSessionId || null,
      clientAttempt: clientAttempt || null,
      clientReason: clientReason || null,
    });

    try {
      server.send(
        JSON.stringify({
          type: "connected",
          role,
          userId,
          robloxUserId,
        }),
      );
    } catch (error) {
      console.error("[LIVE WS HANDSHAKE SEND ERROR]", {
        role,
        robloxUserId,
        name: error?.name || null,
        message: error?.message || String(error),
        stack: error?.stack || null,
      });

      throw error;
    }

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }


  async rememberPresenceProof(body) {
    if (!PRESENCE_SESSION_RE.test(String(body.sessionId||"")) || !/^[a-f0-9]{64}$/.test(String(body.resumeNonce||"")) ||
        !(await validPresenceToken(this.env,body.presenceToken,body.sessionId,body.robloxUserId))) return false;
    await this.ctx.storage.put("presence-proof",{sessionId:body.sessionId,robloxUserId:body.robloxUserId,
      hash:await sha256Hex(body.resumeNonce),expiresAt:Date.now()+15*60*1000});
    await this.schedulePresenceAlarm();
    return true;
  }

  async resumePresenceToken(body) {
    if (!/^[a-f0-9]{64}$/.test(String(body.resumeNonce||""))) return "";
    const proof=await this.ctx.storage.get("presence-proof");
    if (!proof || proof.expiresAt<=Date.now() || proof.sessionId!==body.sessionId || proof.robloxUserId!==String(body.robloxUserId) ||
        !safeEqual(proof.hash,await sha256Hex(body.resumeNonce))) return "";
    return issuePresenceToken(this.env,body.sessionId,String(body.robloxUserId));
  }

  async acceptPresenceSocket(request) {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") return new Response("Expected WebSocket", {status:426});
    const sessionId = new URL(request.url).searchParams.get("sid") || "";
    if (!PRESENCE_SESSION_RE.test(sessionId)) return new Response("Invalid session", {status:400});
    if (this.ctx.getWebSockets("presence").length >= 4) return new Response("Too many session connections", {status:429});
    const [client,server] = Object.values(new WebSocketPair());
    this.ctx.acceptWebSocket(server,["presence"]);
    server.serializeAttachment({role:"presence",sessionId,registered:false,deadline:Date.now()+15000});
    await this.schedulePresenceAlarm();
    return new Response(null,{status:101,webSocket:client});
  }

  async schedulePresenceAlarm() {
    const sockets=this.ctx.getWebSockets("presence").filter(ws=>ws.readyState===1);
    const proof=await this.ctx.storage.get("presence-proof");
    if (!sockets.length && !proof) { await this.ctx.storage.deleteAlarm(); return; }
    const deadline=Math.min(...sockets.map(ws=>Number(ws.deserializeAttachment()?.deadline)||Date.now()),proof?.expiresAt || Infinity);
    await this.ctx.storage.setAlarm(Math.max(Date.now()+1000,deadline));
  }

  async expirePresenceSockets() {
    const proof=await this.ctx.storage.get("presence-proof");
    if (proof && proof.expiresAt<=Date.now()) await this.ctx.storage.delete("presence-proof");
    for (const ws of this.ctx.getWebSockets("presence")) {
      if (Number(ws.deserializeAttachment()?.deadline||0)<=Date.now()) {
        try { ws.close(1008,"Presence confirmation expired"); } catch {}
      }
    }
    await this.schedulePresenceAlarm();
  }

  async presenceMessage(ws,message) {
    let a=ws.deserializeAttachment()||{};
    if (ws.readyState!==1 || a.retired) return;
    const now=Date.now();
    if (now>=Number(a.deadline||0)) {ws.close(1008,"Presence confirmation expired");return;}
    if (typeof message!=="string") {ws.close(1003,"JSON text required");return;}
    if (encoder.encode(message).byteLength>8192) {ws.close(1009,"Presence message too large");return;}
    if (now-Number(a.windowAt||0)>=60000) {a.windowAt=now;a.messageCount=0;}
    a.messageCount=Number(a.messageCount||0)+1;ws.serializeAttachment(a);
    if (a.messageCount>12) {ws.close(1008,"Presence message rate exceeded");return;}
    let body;try {body=JSON.parse(message);}catch {ws.close(1008,"Invalid JSON");return;}
    if (!body || Array.isArray(body) || String(body.sessionId)!==a.sessionId ||
        !["presence","presence_disconnect"].includes(body.type) ||
        !Number.isSafeInteger(body.sequence) || body.sequence<1 || body.sequence>1e9) {
      ws.close(1008,"Invalid presence message");return;
    }
    if (a.robloxUserId && String(body.robloxUserId)!==a.robloxUserId) {ws.close(1008,"Presence identity changed");return;}
    // Credentials stay inside TLS messages and are never serialized or logged.
    const headers={"Content-Type":"application/json"};
    if (typeof body.dashboardKey==="string" && body.dashboardKey.length<=256) headers.Authorization="Bearer "+body.dashboardKey;
    if (typeof body.presenceToken==="string" && body.presenceToken.length<=1024) headers["X-Presence-Token"]=body.presenceToken;
    const disconnect=body.type==="presence_disconnect";
    if (disconnect && !a.registered) {ws.close(1008,"Presence not registered");return;}
    const request=new Request("https://presence.internal/"+(disconnect?"runtime-presence/disconnect":"runtime-presence"),
      {method:"POST",headers,body:JSON.stringify(body)});
    try {
      const response=await (disconnect?handleRuntimePresenceDisconnect:handleRuntimePresence)(request,this.env,{rateLimit:false,proofStore:this});
      const data=await response.json();
      if (!response.ok || !data.ok) {
        ws.send(JSON.stringify({type:"presence_error",sequence:body.sequence,status:response.status}));
        ws.close(1008,"Presence rejected");return;
      }
      if (!disconnect) {
        a={...a,registered:true,robloxUserId:String(body.robloxUserId),deadline:Date.now()+UNLINKED_STALE_MS};
        ws.serializeAttachment(a);
        // Replace an older socket only after signed registration succeeds.
        for (const other of this.ctx.getWebSockets("presence")) if (other!==ws && other.deserializeAttachment()?.registered) {
          other.serializeAttachment({...other.deserializeAttachment(),retired:true});
          try {other.close(1000,"Presence connection replaced");}catch {}
        }
      }
      ws.send(JSON.stringify({...data,type:disconnect?"presence_disconnected":"presence_ack",sequence:body.sequence}));
      if (disconnect) {ws.serializeAttachment({...a,retired:true});ws.close(1000,"Runtime stopped");}
      await this.schedulePresenceAlarm();
    } catch {
      try {ws.send(JSON.stringify({type:"presence_error",sequence:body.sequence,status:503}));ws.close(1011,"Presence unavailable");}catch {}
    }
  }

  async scheduleAuthorizationCheck() {
    if (await this.ctx.storage.getAlarm() === null) {
      await this.ctx.storage.setAlarm(Date.now() + 15000);
    }
  }

  async socketAuthorized(ws) {
    try {
      if (await liveAuthorizationValid(this.env, ws.deserializeAttachment())) return true;
      ws.close(1008, "Live access revoked");
    } catch { try { ws.close(1011, "Authorization unavailable"); } catch {} }
    return false;
  }

  async alarm() {
    if (this.ctx.getWebSockets("presence").length || await this.ctx.storage.get("presence-proof")) {
      await this.expirePresenceSockets();
      return;
    }
    const sockets = this.ctx.getWebSockets();
    let valid = false;
    for (const ws of sockets) {
      if (await this.socketAuthorized(ws)) valid = true;
    }
    if (valid) await this.ctx.storage.setAlarm(Date.now() + 15000);
  }

  async webSocketMessage(ws, message) {
    if (ws.deserializeAttachment()?.role === "presence") {
      if (Number(this.presencePending || 0) >= 12) { ws.close(1008,"Presence queue exceeded"); return; }
      this.presencePending = Number(this.presencePending || 0) + 1;
      // Keep first registration and heartbeats ordered across D1 awaits.
      const pending = (this.presenceQueue || Promise.resolve()).then(() => this.presenceMessage(ws, message));
      this.presenceQueue = pending.catch(() => {});
      try { return await pending; } finally { this.presencePending--; }
    }
    if (!(await this.socketAuthorized(ws))) return;
    let attachment = {};

    try {
      attachment = ws.deserializeAttachment() || {};
    } catch {}

    const now = Date.now();
    if (now - Number(attachment.messageWindowAt || 0) >= 60000) {
      attachment.messageWindowAt = now;
      attachment.messageCount = 0;
    }
    attachment.messageCount = Number(attachment.messageCount || 0) + 1;
    ws.serializeAttachment(attachment);
    if (attachment.messageCount > 120) { ws.close(1008, "Message rate exceeded"); return; }
    if (typeof message !== "string") { ws.close(1003, "JSON text required"); return; }
    const maxBytes = attachment.role === "runtime" ? 256 * 1024 : 8192;
    if (new TextEncoder().encode(message).byteLength > maxBytes) { ws.close(1009, "Message too large"); return; }
    let parsed = null;

    try {
      if (typeof message === "string") {
        parsed = JSON.parse(message);
      }
    } catch {}

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) { ws.close(1008, "Invalid JSON object"); return; }
    if (attachment.role === "runtime" && (parsed.type !== "snapshot" || parsed.schemaVersion !== 1 ||
        String(parsed.player?.userId || "") !== attachment.robloxUserId ||
        !PRESENCE_SESSION_RE.test(String(parsed.session?.id || "")))) {
      ws.close(1008, "Invalid telemetry identity or schema"); return;
    }

    /*
      Runtime -> dashboard

      A normal Veyra snapshot already contains:

      session.id
      product.version

      So linked runtimes can refresh their
      presence through the existing WS without
      creating extra HTTP requests.
    */

    if (attachment.role === "runtime") {
      const now = Date.now();

      const snapshotSessionId = String(parsed?.session?.id || "");

      const snapshotVersion = String(parsed?.product?.version || "unknown");
      if (!(await claimRuntimeSession(this.env, attachment.userId, attachment.robloxUserId, snapshotSessionId, now))) {
        ws.close(1008, 'Telemetry session belongs to another account'); return;
      }

      if (
        parsed?.type === "snapshot" &&
        PRESENCE_SESSION_RE.test(snapshotSessionId)
      ) {
        await ensureAnalyticsSchema(this.env);
        const existingSession = await this.env.DB.prepare(
          "SELECT roblox_user_id FROM analytics_sessions WHERE session_id = ?1 UNION ALL SELECT roblox_user_id FROM runtime_presence WHERE session_id = ?1 LIMIT 1",
        ).bind(snapshotSessionId).first();
        if (existingSession && String(existingSession.roblox_user_id) !== attachment.robloxUserId) {
          ws.close(1008, "Telemetry session belongs to another identity"); return;
        }
        const previousSessionId = String(
          attachment.runtimePresenceSessionId || "",
        );

        const needsImmediateUpsert = previousSessionId !== snapshotSessionId;

        const needsTouch =
          now - Number(attachment.runtimePresenceUpdatedAt || 0) >=
          LINKED_WS_TOUCH_MS;

        if (needsImmediateUpsert || needsTouch) {
          if (previousSessionId && previousSessionId !== snapshotSessionId) {
            try {
              await removeRuntimePresence(this.env, previousSessionId, attachment.robloxUserId);
            } catch {}
          }

          try {
            const written = await touchLinkedRuntimePresence(this.env, {
              sessionId: snapshotSessionId,
              userId: attachment.userId,

              robloxUserId: attachment.robloxUserId,

              version: snapshotVersion,
            });
            if (!written) { ws.close(1008, "Telemetry session belongs to another identity"); return; }

            attachment.runtimePresenceSessionId = snapshotSessionId;

            attachment.runtimePresenceUpdatedAt = now;

            try {
              // Preserve counters written by messages interleaved during D1 awaits.
              const latest = ws.deserializeAttachment() || attachment;
              ws.serializeAttachment({...latest,
                runtimePresenceSessionId: snapshotSessionId, runtimePresenceUpdatedAt: now});
            } catch {}

            if (needsImmediateUpsert) {
              console.log("[LIVE WS SESSION]", {
                robloxUserId: attachment.robloxUserId || null,

                runtimePresenceSessionId: snapshotSessionId,

                connectedAt: attachment.connectedAt || null,

                connectedForMs: Math.max(
                  0,
                  now - Number(attachment.connectedAt || now),
                ),

                clientRuntimeSessionId:
                  attachment.clientRuntimeSessionId || null,

                clientAttempt: attachment.clientAttempt || null,

                clientReason: attachment.clientReason || null,
              });
              await upsertAnalyticsSession(this.env, {
                sessionId: snapshotSessionId,
                robloxUserId: attachment.robloxUserId,
                dashboardLinked: true,
                userId: attachment.userId,
                version: snapshotVersion,
                executorName: parsed?.executor?.name,
                executorVersion: parsed?.executor?.version,
              });
              const stats = await recordAnalyticsSnapshot(this.env);

              await notifyStatsHub(this.env, "linked-runtime-online", stats);
            }
          } catch (error) {
            console.error("WS runtime presence error:", error);
          }
        }
      }

      const dashboards = this.ctx.getWebSockets("dashboard");

      let delivered = 0;

      for (const dashboard of dashboards) {
        if (!(await this.socketAuthorized(dashboard))) continue;
        try {
          dashboard.send(message);

          delivered++;
        } catch {}
      }

      try {
        ws.send(
          JSON.stringify({
            type: "relay_ack",

            deliveredTo: delivered,

            originalType: parsed?.type || null,
          }),
        );
      } catch {}

      return;
    }

    if (attachment.role === "dashboard") {
      try {
        ws.send(
          JSON.stringify({
            type: "dashboard_ack",

            originalType: parsed?.type || null,
          }),
        );
      } catch {}
    }
  }

  async webSocketClose(ws, code, reason, wasClean) {
    if (ws.deserializeAttachment()?.role === "presence") {
      try { ws.close(code, reason); } catch {}
      // A close can race HTTPS fallback or another live transport. Only an
      // explicit signed disconnect deletes presence; silent exits age out.
      await this.schedulePresenceAlarm();
      return;
    }
    // Safe with auto-reply runtimes; completes the handshake on older/local runtimes.
    try { ws.close(code, reason); } catch {}
    let attachment = {};

    try {
      attachment = ws.deserializeAttachment() || {};
    } catch {}

    console.log("[LIVE WS CLOSE]", {
      role: attachment.role || null,

      robloxUserId: attachment.robloxUserId || null,

      runtimePresenceSessionId: attachment.runtimePresenceSessionId || null,

      clientRuntimeSessionId: attachment.clientRuntimeSessionId || null,

      clientAttempt: attachment.clientAttempt || null,

      clientReason: attachment.clientReason || null,

      code,

      reason: String(reason || "").slice(0, 240),

      wasClean: Boolean(wasClean),

      connectedForMs: Math.max(
        0,
        Date.now() - Number(attachment.connectedAt || Date.now()),
      ),
    });

    if (attachment.role === "runtime" && attachment.runtimePresenceSessionId) {
      try {
        const removed = await removeRuntimePresence(
          this.env,
          attachment.runtimePresenceSessionId,
          attachment.robloxUserId,
        );

        if (removed) {
          await notifyStatsHub(this.env, "linked-runtime-offline");
        }
      } catch (error) {
        console.error("WS presence close cleanup error:", error);
      }
    }
  }

  async webSocketError(ws, error) {
    if (ws.deserializeAttachment()?.role === "presence") {
      try { ws.close(1011, "Presence transport error"); } catch {}
      await this.schedulePresenceAlarm();
      return;
    }
    let attachment = {};

    try {
      attachment = ws.deserializeAttachment() || {};
    } catch {}

    console.error("[LIVE WS ERROR]", {
      role: attachment.role || null,

      robloxUserId: attachment.robloxUserId || null,

      runtimePresenceSessionId: attachment.runtimePresenceSessionId || null,

      clientRuntimeSessionId: attachment.clientRuntimeSessionId || null,

      clientAttempt: attachment.clientAttempt || null,

      clientReason: attachment.clientReason || null,

      connectedForMs: Math.max(
        0,
        Date.now() - Number(attachment.connectedAt || Date.now()),
      ),

      name: error?.name || null,

      message: error?.message || String(error || "WebSocket error"),

      stack: error?.stack || null,
    });

    if (attachment.role === "runtime" && attachment.runtimePresenceSessionId) {
      try {
        const removed = await removeRuntimePresence(
          this.env,
          attachment.runtimePresenceSessionId,
          attachment.robloxUserId,
        );

        if (removed) {
          await notifyStatsHub(this.env, "linked-runtime-error");
        }
      } catch {}
    }

    try {
      ws.close(1011, "WebSocket error");
    } catch {}
  }
}

/*
  Worker
*/

const liveWorker = {
  async fetch(request, env) {
    try {
      const path = new URL(request.url).pathname;
      if (request.method !== "OPTIONS" && ["/token", "/web-token", "/ws", "/owner/analytics", "/admin/ws", "/admin/stats"].includes(path)) {
        await requestRateLimit(request, env.LIVE_RATE_LIMITER);
      }
      if (["/token", "/web-token", "/ws"].includes(path) && !env.LIVE_TOKEN_SECRET) {
        return json(request, {ok: false, error: "Live signing unavailable."}, 503, env);
      }
      return await liveWorker.handleRequest(request, env);
    } catch (error) {
      if (error instanceof RequestInputError) return json(request, {ok: false, error: error.message}, error.status, env);
      console.error(JSON.stringify({event: "live-request-failed", path: new URL(request.url).pathname}));
      return json(request, {ok: false, error: "Service temporarily unavailable."}, 500, env);
    }
  },
  async handleRequest(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        status: 204,

        headers: corsHeaders(request, env),
      });
    }

    if (url.pathname === "/health") {
      return json(
        request,
        {
          ok: true,

          service: "aroyn-live",

          database: Boolean(env.DB),

          tokenSecret: Boolean(env.LIVE_TOKEN_SECRET),

          statsSecret: Boolean(env.STATS_API_SECRET),

          statsWebSocket: Boolean(env.STATS),

          ownerAnalytics: Boolean(env.OWNER_DISCORD_ID),

          runtimePresence: {
            websocket: true,
            linkedWsTouchSeconds: LINKED_WS_TOUCH_MS / 1000,

            linkedStaleSeconds: LINKED_STALE_MS / 1000,

            unlinkedHeartbeatSeconds: UNLINKED_HEARTBEAT_SECONDS,

            unlinkedStaleSeconds: UNLINKED_STALE_MS / 1000,

            linkedHttpHeartbeatSeconds: LINKED_HTTP_HEARTBEAT_SECONDS,

            analyticsCheckpointSeconds: ANALYTICS_SESSION_CHECKPOINT_MS / 1000,

            snapshotBucketSeconds: ANALYTICS_SAMPLE_MS / 1000,
          },
        },
        undefined,
        env,
      );
    }

    if (url.pathname === "/runtime-presence/ws") {
      if (!env.LIVE || !env.PRESENCE_TOKEN_SECRET || !env.PRESENCE_RATE_LIMITER) return json(request,{ok:false,error:"Presence unavailable"},503,env);
      if (request.method!=="GET" || request.headers.get("Upgrade")?.toLowerCase()!=="websocket") return json(request,{ok:false,error:"Expected WebSocket"},426,env);
      const sid=url.searchParams.get("sid")||"";
      if (!PRESENCE_SESSION_RE.test(sid)) return json(request,{ok:false,error:"Invalid sessionId"},400,env);
      if (await presenceRateLimited(env,"runtime-presence/ws",request)) return json(request,{ok:false,error:"Too many presence connections"},429,env);
      const target=new URL("https://presence.internal/presence-ws");target.searchParams.set("sid",sid);
      const stub=env.LIVE.get(env.LIVE.idFromName("presence:"+sid));
      // Public request headers are not trusted as live telemetry identity.
      return stub.fetch(new Request(target,{headers:{Upgrade:"websocket"}}));
    }

    /*
      Runtime HTTP presence.

      No valid Dashboard:
        script online only.

      Valid Dashboard + linked Roblox account:
        script online + dashboard linked.

      Linked runtimes also get refreshed by
      their normal WS snapshots.
    */

    if (url.pathname === "/runtime-presence" && request.method === "POST") {
      return handleRuntimePresence(request, env);
    }

    /*
      Best-effort explicit runtime disconnect.
      This makes owner analytics and status counts drop immediately when
      Veyra is re-executed or stopped instead of waiting for stale cleanup.
    */
    if (
      url.pathname === "/runtime-presence/disconnect" &&
      request.method === "POST"
    ) {
      return handleRuntimePresenceDisconnect(request, env);
    }

    /*
      Owner-only historical analytics.

      Authentication is the normal Veyra Discord web session.
      Authorization is enforced server-side against OWNER_DISCORD_ID.
      The static site never receives the owner ID or STATS_API_SECRET.
    */

    if (url.pathname === "/owner/analytics" && request.method === "GET") {
      const owner = await requireOwnerSession(request, env);

      if (owner.error) {
        return json(
          request,
          { ok: false, error: owner.error },
          owner.status,
          env,
        );
      }

      try {
        const range = url.searchParams.get("range") || "24h";
        const tzOffsetMinutes = url.searchParams.get("tzOffsetMinutes") || 0;

        let analytics;
        let analyticsCache = {
          hit: false,
          fallback: true,
          ttlMs: OWNER_ANALYTICS_CACHE_MS,
        };

        if (env.STATS) {
          const id = env.STATS.idFromName("global");
          const stub = env.STATS.get(id);
          const cacheUrl = new URL(
            "https://veyra-stats.internal/owner-analytics",
          );
          cacheUrl.searchParams.set("range", range);
          cacheUrl.searchParams.set("tzOffsetMinutes", String(tzOffsetMinutes));

          const cachedResponse = await stub.fetch(cacheUrl.toString(), {
            method: "GET",
          });

          if (!cachedResponse.ok) {
            const detail = await cachedResponse.text().catch(() => "");
            throw new Error(
              `Owner analytics cache returned HTTP ${cachedResponse.status}` +
                (detail ? `: ${detail.slice(0, 240)}` : ""),
            );
          }

          const cachedPayload = await cachedResponse.json();
          analytics = cachedPayload?.analytics;
          analyticsCache = cachedPayload?.cache || analyticsCache;
        } else {
          analytics = await getOwnerAnalytics(env, range, tzOffsetMinutes);
        }

        return json(
          request,
          {
            ok: true,
            owner: {
              username: owner.session.discord_username || null,
              displayName:
                owner.session.discord_display_name ||
                owner.session.discord_username ||
                null,
            },
            analytics,
            analyticsCache,
          },
          undefined,
          env,
        );
      } catch (error) {
        return json(
          request,
          {
            ok: false,
            error: "Owner analytics query failed",

          },
          500,
          env,
        );
      }
    }

    /*
      Private bot/admin stats WebSocket.

      The status bot authenticates with the same
      STATS_API_SECRET used by /admin/stats.
    */

    if (url.pathname === "/admin/ws" && request.method === "GET") {
      const supplied = bearerToken(request);

      if (!env.STATS_API_SECRET || !safeEqual(supplied, env.STATS_API_SECRET)) {
        return json(
          request,
          {
            ok: false,
            error: "Unauthorized",
          },
          401,
          env,
        );
      }

      const upgrade = request.headers.get("Upgrade");

      if (!upgrade || upgrade.toLowerCase() !== "websocket") {
        return new Response("Expected WebSocket", { status: 426 });
      }

      const id = env.STATS.idFromName("global");

      const stub = env.STATS.get(id);

      return stub.fetch(request);
    }

    /*
      Private bot/admin stats.

      "dashboardUsers" means active Veyra
      runtimes with a valid linked Dashboard.

      Browser tabs are irrelevant.
    */

    if (url.pathname === "/admin/stats" && request.method === "GET") {
      const supplied = bearerToken(request);

      if (!env.STATS_API_SECRET || !safeEqual(supplied, env.STATS_API_SECRET)) {
        return json(
          request,
          {
            ok: false,
            error: "Unauthorized",
          },
          401,
          env,
        );
      }

      try {
        let stats = null;

        if (env.STATS) {
          const id = env.STATS.idFromName("global");

          const stub = env.STATS.get(id);

          const response = await stub.fetch(
            "https://veyra-stats.internal/current-stats",
            { method: "GET" },
          );

          if (response.ok) {
            const payload = await response.json().catch(() => null);

            stats = payload?.online || null;
          }
        }

        if (!stats) {
          stats = await getRuntimePresenceStats(env);
        }

        return json(
          request,
          {
            ok: true,

            generatedAt: Date.now(),

            online: stats,

            semantics: {
              scriptUsers: "Unique Roblox users with Veyra currently running",

              dashboardUsers:
                "Unique active Veyra Roblox users with a valid connected dashboard",

              scriptSessions: "Active Veyra runtime sessions",

              dashboardSessions:
                "Active Veyra runtime sessions with a valid connected dashboard",
            },

            presence: {
              linkedWsTouchSeconds: LINKED_WS_TOUCH_MS / 1000,

              linkedStaleSeconds: LINKED_STALE_MS / 1000,

              unlinkedHeartbeatSeconds: UNLINKED_HEARTBEAT_SECONDS,

              unlinkedStaleSeconds: UNLINKED_STALE_MS / 1000,
            },
          },
          undefined,
          env,
        );
      } catch (error) {
        return json(
          request,
          {
            ok: false,

            error: "Stats query failed",


          },
          500,
          env,
        );
      }
    }

    /*
      Roblox live WebSocket token
    */

    if (url.pathname === "/token" && request.method === "POST") {
      const dashboardKey = bearerToken(request);

      const user = await resolveDashboardUser(env, dashboardKey);

      if (!user) {
        return json(
          request,
          {
            ok: false,

            error: "Invalid dashboard key",
          },
          401,
          env,
        );
      }

      const body = await boundedJson(request);

      const robloxUserId = String(body?.robloxUserId || "").trim();

      if (!/^\d+$/.test(robloxUserId)) {
        return json(
          request,
          {
            ok: false,

            error: "robloxUserId is required",
          },
          400,
          env,
        );
      }

      const robloxAccount = await resolveRobloxAccount(
        env,
        user.id,
        robloxUserId,
      );

      if (!robloxAccount) {
        return json(
          request,
          {
            ok: false,

            error: "Roblox account is not linked to this Aroyn account",
          },
          403,
          env,
        );
      }

      const token = await createLiveToken(
        env,
        user.id,
        "runtime",
        robloxAccount.roblox_user_id,
        await sha256Hex(normalizeDashboardKey(dashboardKey)),
      );

      return json(
        request,
        {
          ok: true,
          token,

          expiresIn: 60,

          userId: user.id,

          robloxUserId: String(robloxAccount.roblox_user_id),

          role: "runtime",

          account: {
            username: robloxAccount.username,

            displayName: robloxAccount.display_name,
          },
        },
        undefined,
        env,
      );
    }

    /*
      Dashboard WebSocket token
    */

    if (url.pathname === "/web-token" && request.method === "POST") {
      const sessionToken = bearerToken(request);

      const user = await resolveWebSession(env, sessionToken);

      if (!user) {
        return json(
          request,
          {
            ok: false,

            error: "Invalid or expired web session",
          },
          401,
          env,
        );
      }

      const body = await boundedJson(request);

      const robloxUserId = String(body?.robloxUserId || "").trim();

      if (!/^\d+$/.test(robloxUserId)) {
        return json(
          request,
          {
            ok: false,

            error: "robloxUserId is required",
          },
          400,
          env,
        );
      }

      const robloxAccount = await resolveRobloxAccount(
        env,
        user.id,
        robloxUserId,
      );

      if (!robloxAccount) {
        return json(
          request,
          {
            ok: false,

            error: "Roblox account is not linked to this Aroyn account",
          },
          403,
          env,
        );
      }

      const token = await createLiveToken(
        env,
        user.id,
        "dashboard",
        robloxAccount.roblox_user_id,
        await sha256Hex(sessionToken),
      );

      return json(
        request,
        {
          ok: true,
          token,

          expiresIn: 60,

          userId: user.id,

          robloxUserId: String(robloxAccount.roblox_user_id),

          role: "dashboard",

          account: {
            username: robloxAccount.username,

            displayName: robloxAccount.display_name,
          },
        },
        undefined,
        env,
      );
    }

    /*
      Live telemetry WebSocket
    */

    if (url.pathname === "/ws") {
      let wsDiagStage = "verify-token";

      let wsDiagUserId = null;

      let wsDiagRobloxUserId = null;

      let wsDiagRole = null;

      try {
        const payload = await verifyLiveToken(
          env,
          url.searchParams.get("token"),
        );

        if (!payload || !(await liveAuthorizationValid(env, payload))) {
          return new Response("Invalid or expired live token", {
            status: 401,
          });
        }

        wsDiagUserId = payload.userId;

        wsDiagRobloxUserId = payload.robloxUserId;

        wsDiagRole = payload.role;

        wsDiagStage = "get-live-durable-object";

        const id = env.LIVE.idFromName(
          `user:${payload.userId}:roblox:${payload.robloxUserId}`,
        );

        const stub = env.LIVE.get(id);

        wsDiagStage = "forward-live-request";

        const headers = new Headers(request.headers);

        headers.set("X-Veyra-Auth-Hash", payload.authHash);
        headers.set("X-Veyra-User-Id", payload.userId);

        headers.set("X-Veyra-Role", payload.role);

        headers.set("X-Veyra-Roblox-User-Id", payload.robloxUserId);

        const forwardUrl = new URL(request.url);
        forwardUrl.searchParams.delete("token");
        const forwarded = new Request(forwardUrl, {
          method: request.method,

          headers,
        });

        return await stub.fetch(forwarded);
      } catch (error) {
        console.error("[LIVE WS ROUTE ERROR]", {
          stage: wsDiagStage,

          userId: wsDiagUserId,

          robloxUserId: wsDiagRobloxUserId,

          role: wsDiagRole,

          name: error?.name || null,

          message: error?.message || String(error),

          stack: error?.stack || null,
        });

        throw error;
      }
    }

    return new Response("Veyra Live online", {
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
      },
    });
  },

  /*
    R2 release event consumer.

    An R2 object-create notification is emitted when greedy-growers.luau is
    uploaded or overwritten. This handler reads only the first 4 KB from R2,
    extracts the canonical `local UpdateVersion = "x.y.z"` line and pushes the
    version through the already-open Veyra runtime WebSockets.
  */
  async queue(batch, env) {
    let releaseEvent = null;

    for (const message of batch.messages) {
      const event = message?.body || {};

      if (
        event?.bucket === "veyra-payloads" &&
        event?.object?.key === "greedy-growers.luau" &&
        (event?.action === "PutObject" ||
          event?.action === "CopyObject" ||
          event?.action === "CompleteMultipartUpload")
      ) {
        releaseEvent = event;
      }
    }

    if (!releaseEvent) {
      return;
    }

    const object = await env.PAYLOADS.get("greedy-growers.luau", {
      range: {
        offset: 0,
        length: 4096,
      },
    });

    if (!object) {
      throw new Error("greedy-growers.luau not found after R2 release event");
    }

    const source = await object.text();

    const match = source.match(/local\s+UpdateVersion\s*=\s*["']([^"']+)["']/);

    const version = String(match?.[1] || "").trim();

    if (!/^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9._-]+)?$/.test(version)) {
      throw new Error(
        "UpdateVersion not found in first 4 KB of greedy-growers.luau",
      );
    }

    if (!env.STATS) {
      throw new Error("STATS Durable Object binding unavailable");
    }

    const statsId = env.STATS.idFromName("global");

    const statsStub = env.STATS.get(statsId);

    const response = await statsStub.fetch(
      "https://veyra-stats.internal/broadcast-update",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          version,
          sourceETag: String(releaseEvent?.object?.eTag || ""),
          releasedAt: Date.now(),
          message: "A new Veyra update is available.",
        }),
      },
    );

    if (!response.ok) {
      const detail = await response.text().catch(() => "");

      throw new Error(
        `Update broadcast failed: HTTP ${response.status}` +
          (detail ? ` ${detail.slice(0, 240)}` : ""),
      );
    }

    const result = await response.json().catch(() => null);

    console.log("[AUTO UPDATE PUSH]", {
      version,
      delivered: Number(result?.delivered || 0),
      targets: Number(result?.targets || 0),
      duplicate: Boolean(result?.duplicate),
    });
  },
};

export default liveWorker;
