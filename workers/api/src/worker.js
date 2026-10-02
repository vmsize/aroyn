
import {RETENTION, claimRuntimeSession, accountExport, finishAccountDeletionInOrder, runDataRetention} from '../../shared/data-lifecycle.js';
import {ledgerRequired, DELETION_LEDGER_DAYS, recordDeletion} from '../../shared/deletion-ledger.js';
import {withSnapshotStorage} from '../../shared/snapshot-storage.js';
export {AroynSnapshotStore} from '../../shared/snapshot-storage.js';
export {AroynRetentionRunner} from '../../shared/retention-runner.js';
import {stagingRestricted, stagingAccessReady, discordAccessAllowed} from '../../shared/staging-access.js';

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

function base64url(bytes) {
    let binary = "";
    for (const b of bytes) binary += String.fromCharCode(b);
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function randomBytes(length = 32) {
    const bytes = new Uint8Array(length);
    crypto.getRandomValues(bytes);
    return bytes;
}

function randomToken(prefix = "", length = 32) {
    return prefix + base64url(randomBytes(length));
}

function randomHex(bytes = 12) {
    return Array.from(randomBytes(bytes)).map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase();
}

async function sha256Hex(value) {
    const digest = await crypto.subtle.digest("SHA-256", encoder.encode(String(value)));
    return Array.from(new Uint8Array(digest)).map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sign(secret, value) {
    const key = await crypto.subtle.importKey(
        "raw",
        encoder.encode(secret),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
    );
    const signature = await crypto.subtle.sign("HMAC", key, encoder.encode(value));
    return base64url(new Uint8Array(signature));
}

function safeEqual(a, b) {
    a = String(a || "");
    b = String(b || "");
    if (a.length !== b.length) return false;
    let difference = 0;
    for (let i = 0; i < a.length; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
    return difference === 0;
}

function parseCookies(request) {
    const result = {};
    const raw = request.headers.get("Cookie") || "";
    for (const part of raw.split(";")) {
        const index = part.indexOf("=");
        if (index <= 0) continue;
        const key = part.slice(0, index).trim();
        const value = part.slice(index + 1).trim();
        try { result[key] = decodeURIComponent(value); }
        catch { result[key] = value; }
    }
    return result;
}

function siteOrigin(env) {
    return String(env.SITE_ORIGIN || env.ALLOWED_ORIGIN || "https://veyra-hub.pages.dev").replace(/\/+$/, "");
}

function sanitizeReturnTo(value) {
    const raw = String(value || "/dashboard/");
    if (!raw.startsWith("/") || raw.startsWith("//")) return "/dashboard/";
    if (!raw.startsWith("/dashboard") && !raw.startsWith("/admin") && raw !== "/") return "/dashboard/";
    return raw.slice(0, 500);
}

function corsHeaders(request, env) {
    const configured = String(env.ALLOWED_ORIGIN || siteOrigin(env))
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean);
    const origin = request.headers.get("Origin");
    let allowOrigin = configured[0] || siteOrigin(env);
    if (configured.includes("*")) allowOrigin = "*";
    else if (origin && configured.includes(origin)) allowOrigin = origin;
    return {
        "Access-Control-Allow-Origin": allowOrigin,
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
        "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
        "Access-Control-Max-Age": "86400",
        "Vary": "Origin",
    };
}

function jsonResponse(request, env, data, status = 200, extraHeaders = {}) {
    return new Response(JSON.stringify(data), {
        status,
        headers: {
            "Content-Type": "application/json; charset=utf-8",
            "Cache-Control": "no-store",
            ...corsHeaders(request, env),
            ...extraHeaders,
        },
    });
}

function bearerToken(request) {
    const raw = request.headers.get("Authorization") || "";
    const match = raw.match(/^Bearer\s+(.+)$/i);
    return match ? match[1].trim() : "";
}

function requireDb(request, env) {
    if (!env.DB) return jsonResponse(request, env, { error: "Aroyn account database is not configured." }, 503);
    return null;
}

function discordAvatarUrl(row) {
    if (!row || !row.discord_id || !row.discord_avatar) return null;
    const ext = String(row.discord_avatar).startsWith("a_") ? "gif" : "png";
    return `https://cdn.discordapp.com/avatars/${row.discord_id}/${row.discord_avatar}.${ext}?size=128`;
}

function publicUser(row) {
    if (!row) return null;
    return {
        id: row.id,
        discordId: row.discord_id,
        username: row.discord_username,
        displayName: row.discord_display_name || row.discord_username,
        avatarUrl: discordAvatarUrl(row),
        dashboardKey: {
            exists: Boolean(row.dashboard_key_hash),
            suffix: row.dashboard_key_suffix || null,
        },
    };
}

async function getWebSessionUser(request, env) {
    const token = bearerToken(request);
    if (!token || !token.startsWith("VS_")) return null;
    const tokenHash = await sha256Hex(token);
    const now = Date.now();
    const row = await env.DB.prepare(`
        SELECT u.*, s.created_at AS web_session_created_at
        FROM web_sessions s
        JOIN users u ON u.id = s.user_id
        WHERE s.token_hash = ?1 AND s.expires_at > ?2
          AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=u.id)
        LIMIT 1
    `).bind(tokenHash, now).first();
    return row && discordAccessAllowed(env, row.discord_id) ? { token, tokenHash, user: row } : null;
}

async function requireWebSession(request, env) {
    const dbError = requireDb(request, env);
    if (dbError) return { error: dbError };
    const session = await getWebSessionUser(request, env);
    if (!session) return { error: jsonResponse(request, env, { error: "Authentication required." }, 401) };
    return { session };
}

const DASHBOARD_KEY_RE = /^VY-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}-[A-F0-9]{6}$/;
const LEGACY_MAX_RUNTIME_BODY = 96 * 1024;
const ACCOUNT_MAX_RUNTIME_BODY = 256 * 1024;
const RUNTIME_STALE_AFTER_MS = 9000;

function normalizeDashboardKey(value) {
    return String(value || "").trim().toUpperCase().replace(/\s+/g, "");
}

function generateDashboardKey() {
    const raw = randomHex(12);
    return `VY-${raw.slice(0, 6)}-${raw.slice(6, 12)}-${raw.slice(12, 18)}-${raw.slice(18, 24)}`;
}

async function resolveDashboardUser(request, env) {
    if (!env.DB) return null;
    const key = normalizeDashboardKey(bearerToken(request));
    if (!DASHBOARD_KEY_RE.test(key)) return null;
    const keyHash = await sha256Hex(key);
    const user = await env.DB.prepare(`
        SELECT * FROM users WHERE dashboard_key_hash = ?1
          AND NOT EXISTS (SELECT 1 FROM account_deletions d WHERE d.user_id=users.id) LIMIT 1
    `).bind(keyHash).first();
    return user && discordAccessAllowed(env, user.discord_id) ? { key, keyHash, user } : null;
}

let robloxAccountsSchemaReady = false;

async function ensureRobloxAccountsSchema(env) {
    if (robloxAccountsSchemaReady || !env.DB) return;
    await env.DB.batch([
        env.DB.prepare(`
            CREATE TABLE IF NOT EXISTS roblox_accounts (
                veyra_user_id TEXT NOT NULL,
                roblox_user_id TEXT NOT NULL,
                username TEXT NOT NULL,
                display_name TEXT,
                avatar_url TEXT,
                avatar_updated_at INTEGER,
                first_seen_at INTEGER NOT NULL,
                last_seen_at INTEGER NOT NULL,
                last_session_id TEXT,
                PRIMARY KEY (veyra_user_id, roblox_user_id),
                FOREIGN KEY (veyra_user_id) REFERENCES users(id) ON DELETE CASCADE
            )
        `),
        env.DB.prepare(`CREATE INDEX IF NOT EXISTS idx_roblox_accounts_user_last_seen ON roblox_accounts(veyra_user_id, last_seen_at DESC)`),
        env.DB.prepare(`CREATE INDEX IF NOT EXISTS idx_roblox_accounts_last_seen ON roblox_accounts(last_seen_at DESC)`),
    ]);
    robloxAccountsSchemaReady = true;
}

function normalizeRobloxUserId(value) {
    const id = String(value ?? "").trim();
    return /^\d{1,20}$/.test(id) && id !== "0" ? id : null;
}

function publicRobloxAccount(row) {
    if (!row) return null;
    const lastSeen = Number(row.last_seen_at || 0) || null;
    return {
        userId: String(row.roblox_user_id),
        username: row.username || "Unknown",
        displayName: row.display_name || row.username || "Unknown",
        avatarUrl: row.avatar_url || null,
        firstSeen: Number(row.first_seen_at || 0) || null,
        lastSeen,
        sessionId: row.last_session_id || null,
        online: Boolean(lastSeen && (Date.now() - lastSeen) < RUNTIME_STALE_AFTER_MS),
    };
}

async function fetchRobloxHeadshot(robloxUserId) {
    try {
        const endpoint = new URL("https://thumbnails.roblox.com/v1/users/avatar-headshot");
        endpoint.searchParams.set("userIds", String(robloxUserId));
        endpoint.searchParams.set("size", "150x150");
        endpoint.searchParams.set("format", "Png");
        endpoint.searchParams.set("isCircular", "true");
        const response = await fetch(endpoint.toString(), {
            headers: { "Accept": "application/json" },
            signal: AbortSignal.timeout(3000),
        });
        if (!response.ok) return null;
        const body = await response.json().catch(() => ({}));
        const item = Array.isArray(body?.data) ? body.data[0] : null;
        return item && item.state === "Completed" && item.imageUrl ? String(item.imageUrl) : null;
    } catch {
        return null;
    }
}

async function upsertRobloxAccount(env, veyraUserId, snapshot, receivedAt) {
    await ensureRobloxAccountsSchema(env);
    const robloxUserId = normalizeRobloxUserId(snapshot?.player?.userId);
    if (!robloxUserId) return null;

    const current = await env.DB.prepare(`
        SELECT * FROM roblox_accounts
        WHERE veyra_user_id = ?1 AND roblox_user_id = ?2
        LIMIT 1
    `).bind(veyraUserId, robloxUserId).first();

    const username = String(snapshot?.player?.name || current?.username || `User ${robloxUserId}`).slice(0, 64);
    const displayName = String(snapshot?.player?.displayName || current?.display_name || username).slice(0, 64);
    const sessionId = snapshot?.session?.id ? String(snapshot.session.id).slice(0, 128) : null;
    let avatarUrl = current?.avatar_url || null;
    let avatarUpdatedAt = Number(current?.avatar_updated_at || 0);

    // Avatar URLs are refreshed at most twice per day, not on every telemetry push.
    if (!avatarUpdatedAt || (receivedAt - avatarUpdatedAt) > 12 * 60 * 60 * 1000) {
        const freshAvatar = await fetchRobloxHeadshot(robloxUserId);
        avatarUpdatedAt = receivedAt;
        if (freshAvatar) {
            avatarUrl = freshAvatar;
        }
    }

    await env.DB.prepare(`
        INSERT INTO roblox_accounts (
            veyra_user_id, roblox_user_id, username, display_name,
            avatar_url, avatar_updated_at, first_seen_at, last_seen_at, last_session_id
        ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?7, ?8)
        ON CONFLICT(veyra_user_id, roblox_user_id) DO UPDATE SET
            username = excluded.username,
            display_name = excluded.display_name,
            avatar_url = COALESCE(excluded.avatar_url, roblox_accounts.avatar_url),
            avatar_updated_at = excluded.avatar_updated_at,
            last_seen_at = excluded.last_seen_at,
            last_session_id = excluded.last_session_id
    `).bind(
        veyraUserId,
        robloxUserId,
        username,
        displayName,
        avatarUrl,
        avatarUpdatedAt || null,
        receivedAt,
        sessionId
    ).run();

    return {
        userId: robloxUserId,
        username,
        displayName,
        avatarUrl,
        lastSeen: receivedAt,
        sessionId,
    };
}

async function runtimeV2ObjectName(userId) {
    return `runtime-v2/${userId}/current.json`;
}

async function runtimeAccountObjectName(userId, robloxUserId) {
    return `runtime-v3/${userId}/accounts/${robloxUserId}.json`;
}

async function runtimeRevokedObjectName(userId, robloxUserId) {
    return `runtime-v3/${userId}/revoked/${robloxUserId}.json`;
}

async function isRobloxAccountRevoked(env, userId, robloxUserId) {
    const objectName = await runtimeRevokedObjectName(userId, robloxUserId);
    const object = await env.PAYLOADS.head(objectName);
    return Boolean(object);
}

async function readRuntimeObject(env, objectName) {
    const object = await env.PAYLOADS.get(objectName);
    if (!object) return { objectName, envelope: null };
    try { return { objectName, envelope: JSON.parse(await object.text()) }; }
    catch { return { objectName, envelope: null }; }
}

async function readRuntimeV2(env, userId) {
    return readRuntimeObject(env, await runtimeV2ObjectName(userId));
}

async function readRuntimeAccount(env, userId, robloxUserId) {
    return readRuntimeObject(env, await runtimeAccountObjectName(userId, robloxUserId));
}

async function writeRuntimeV2(env, objectName, envelope) {
    await env.PAYLOADS.put(objectName, JSON.stringify(envelope), {
        httpMetadata: { contentType: "application/json; charset=utf-8" },
    });
}

async function getRobloxAccountRow(env, veyraUserId, robloxUserId = null) {
    await ensureRobloxAccountsSchema(env);
    if (robloxUserId) {
        return env.DB.prepare(`
            SELECT * FROM roblox_accounts
            WHERE veyra_user_id = ?1 AND roblox_user_id = ?2
            LIMIT 1
        `).bind(veyraUserId, String(robloxUserId)).first();
    }
    return env.DB.prepare(`
        SELECT * FROM roblox_accounts
        WHERE veyra_user_id = ?1
        ORDER BY last_seen_at DESC
        LIMIT 1
    `).bind(veyraUserId).first();
}

async function listRobloxAccountRows(env, veyraUserId) {
    await ensureRobloxAccountsSchema(env);
    const result = await env.DB.prepare(`
        SELECT * FROM roblox_accounts
        WHERE veyra_user_id = ?1
        ORDER BY last_seen_at DESC, username COLLATE NOCASE ASC
    `).bind(veyraUserId).all();
    return Array.isArray(result?.results) ? result.results : [];
}

async function handleAccountDataApi(request, env) {
    const path = new URL(request.url).pathname;
    if (!path.startsWith('/api/v2/account/')) return null;
    if (request.method === 'OPTIONS') return new Response(null, {status: 204, headers: corsHeaders(request, env)});
    const auth = await requireWebSession(request, env);
    if (auth.error) return auth.error;
    if (path === '/api/v2/account/retention' && request.method === 'GET') {
        return jsonResponse(request, env, {ok: true, retention: {...RETENTION, ...(ledgerRequired(env) ? {deletionLedgerDays: DELETION_LEDGER_DAYS} : {})}});
    }
    if (path === '/api/v2/account/export' && request.method === 'GET') {
        const response = await accountExport(request, env, auth.session, getWebSessionUser);
        const headers = new Headers(response.headers);
        for (const [name, value] of Object.entries(corsHeaders(request, env))) headers.set(name, value);
        return new Response(response.body, {headers});
    }
    if (path === '/api/v2/account/delete' && request.method === 'POST') {
        const body = await boundedJson(request);
        if (body.confirmation !== 'DELETE') return jsonResponse(request, env, {error: 'Type DELETE to confirm account deletion.'}, 400);
        if (Date.now() - Number(auth.session.user.web_session_created_at || 0) > 15 * 60000) {
            return jsonResponse(request, env, {error: 'Sign in with Discord again before deleting your account.', code: 'REAUTH_REQUIRED'}, 403);
        }
        if (!env.STATS_CACHE || !env.RETENTION_RUNNER) return jsonResponse(request, env, {error: 'Account deletion is temporarily unavailable.'}, 503);
        const id = auth.session.user.id;
        const requestedAt = Date.now();
        try { await recordDeletion(env, id, requestedAt); }
        catch { return jsonResponse(request, env, {error: 'Account deletion is temporarily unavailable. Your request was not completed; please retry.', code: 'DELETION_LEDGER_UNAVAILABLE'}, 503); }
        await env.DB.batch([
            env.DB.prepare('INSERT OR IGNORE INTO account_deletions (user_id, requested_at, legacy_key_hash) SELECT id, ?2, dashboard_key_hash FROM users WHERE id=?1').bind(id, requestedAt),
            env.DB.prepare('UPDATE users SET dashboard_key_hash=NULL, dashboard_key_suffix=NULL WHERE id=?1').bind(id),
            env.DB.prepare('DELETE FROM web_sessions WHERE user_id=?1').bind(id),
            env.DB.prepare('DELETE FROM auth_exchanges WHERE user_id=?1').bind(id),
        ]);
        const job = await env.DB.prepare('SELECT * FROM account_deletions WHERE user_id=?1').bind(id).first();
        try {
            if (!job || await finishAccountDeletionInOrder(env, job)) return jsonResponse(request, env, {ok: true, deleted: true});
        } catch {
            // Credentials are already revoked; the durable job remains pending.
        }
        return jsonResponse(request, env, {ok: true, deleted: false, pending: true,
            message: 'Access revoked. Stored-data cleanup is pending and will retry automatically.'}, 202);
    }
    return jsonResponse(request, env, {error: 'Not found.'}, 404);
}

async function handleAccountAuthApi(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/api/v2/auth/") && !url.pathname.startsWith("/api/v2/account/") && !url.pathname.startsWith("/api/v2/dashboard-key/")) return null;

    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(request, env) });

    if (url.pathname === "/api/v2/auth/discord/start" && request.method === "GET") {
        if (!stagingAccessReady(env)) return jsonResponse(request, env, {error: 'Test access is not configured.'}, 503);
        if (!env.DISCORD_CLIENT_ID || !env.DISCORD_CLIENT_SECRET) {
            return jsonResponse(request, env, { error: "Discord OAuth is not configured." }, 503);
        }
        const state = randomToken("", 24);
        const returnTo = sanitizeReturnTo(url.searchParams.get("returnTo"));
        const redirectUri = String(env.DISCORD_REDIRECT_URI || `${url.origin}/api/v2/auth/discord/callback`);
        const authorize = new URL("https://discord.com/oauth2/authorize");
        authorize.searchParams.set("client_id", env.DISCORD_CLIENT_ID);
        authorize.searchParams.set("response_type", "code");
        authorize.searchParams.set("redirect_uri", redirectUri);
        authorize.searchParams.set("scope", "identify");
        authorize.searchParams.set("state", state);

        const headers = new Headers({ "Location": authorize.toString(), "Cache-Control": "no-store" });
        headers.append("Set-Cookie", `veyra_oauth_state=${encodeURIComponent(state)}; Max-Age=600; Path=/api/v2/auth/discord; HttpOnly; Secure; SameSite=Lax`);
        headers.append("Set-Cookie", `veyra_oauth_return=${encodeURIComponent(returnTo)}; Max-Age=600; Path=/api/v2/auth/discord; HttpOnly; Secure; SameSite=Lax`);
        return new Response(null, { status: 302, headers });
    }

    if (url.pathname === "/api/v2/auth/discord/callback" && request.method === "GET") {
        const dbError = requireDb(request, env);
        if (dbError) return dbError;
        const cookies = parseCookies(request);
        const state = url.searchParams.get("state") || "";
        const code = url.searchParams.get("code") || "";
        if (!state || !cookies.veyra_oauth_state || !safeEqual(state, cookies.veyra_oauth_state)) {
            return jsonResponse(request, env, { error: "OAuth state validation failed." }, 400);
        }
        if (!code) return jsonResponse(request, env, { error: "Discord did not return an authorization code." }, 400);

        const redirectUri = String(env.DISCORD_REDIRECT_URI || `${url.origin}/api/v2/auth/discord/callback`);
        const tokenBody = new URLSearchParams({
            client_id: String(env.DISCORD_CLIENT_ID || ""),
            client_secret: String(env.DISCORD_CLIENT_SECRET || ""),
            grant_type: "authorization_code",
            code,
            redirect_uri: redirectUri,
        });
        const tokenResponse = await fetch("https://discord.com/api/oauth2/token", {
            method: "POST",
            headers: { "Content-Type": "application/x-www-form-urlencoded" },
            body: tokenBody,
        });
        const tokenData = await tokenResponse.json().catch(() => ({}));
        if (!tokenResponse.ok || !tokenData.access_token) {
            return jsonResponse(request, env, { error: "Discord token exchange failed." }, 502);
        }

        const profileResponse = await fetch("https://discord.com/api/v10/users/@me", {
            headers: { "Authorization": `Bearer ${tokenData.access_token}` },
        });
        const profile = await profileResponse.json().catch(() => ({}));
        if (!profileResponse.ok || !profile.id || !profile.username) {
            return jsonResponse(request, env, { error: "Discord profile lookup failed." }, 502);
        }

        if (!discordAccessAllowed(env, profile.id)) {
            return jsonResponse(request, env, {error: 'This test environment is limited to invited accounts.'}, 403);
        }

        const deleting = await env.DB.prepare('SELECT u.id FROM users u JOIN account_deletions d ON d.user_id=u.id WHERE u.discord_id=?1').bind(String(profile.id)).first();
        if (deleting) return jsonResponse(request, env, {error: 'Account deletion is still being completed. Please try again later.'}, 409);
        const now = Date.now();
        await env.DB.prepare(`
            INSERT INTO users (id, discord_id, discord_username, discord_display_name, discord_avatar,
                dashboard_key_hash, dashboard_key_suffix, created_at, updated_at, last_login_at)
            VALUES (?1, ?2, ?3, ?4, ?5, NULL, NULL, ?6, ?6, ?6)
            ON CONFLICT(discord_id) DO UPDATE SET
                discord_username = excluded.discord_username,
                discord_display_name = excluded.discord_display_name,
                discord_avatar = excluded.discord_avatar,
                updated_at = excluded.updated_at, last_login_at = excluded.last_login_at
        `).bind(`usr_${randomHex(12).toLowerCase()}`, String(profile.id), String(profile.username),
            String(profile.global_name || profile.username), profile.avatar ? String(profile.avatar) : null, now).run();
        const user = await env.DB.prepare("SELECT * FROM users WHERE discord_id = ?1 LIMIT 1")
            .bind(String(profile.id)).first();

        const exchangeCode = randomToken("VX_", 32);
        const exchangeHash = await sha256Hex(exchangeCode);
        await env.DB.prepare("DELETE FROM auth_exchanges WHERE expires_at <= ?1").bind(now).run();
        await env.DB.prepare(`
            INSERT INTO auth_exchanges (code_hash, user_id, expires_at, created_at)
            VALUES (?1, ?2, ?3, ?4)
        `).bind(exchangeHash, user.id, now + 60_000, now).run();

        const returnTo = sanitizeReturnTo(cookies.veyra_oauth_return || "/dashboard/");
        const destination = new URL(returnTo, siteOrigin(env));
        destination.searchParams.set("veyra_auth", exchangeCode);
        const headers = new Headers({ "Location": destination.toString(), "Cache-Control": "no-store" });
        headers.append("Set-Cookie", "veyra_oauth_state=; Max-Age=0; Path=/api/v2/auth/discord; HttpOnly; Secure; SameSite=Lax");
        headers.append("Set-Cookie", "veyra_oauth_return=; Max-Age=0; Path=/api/v2/auth/discord; HttpOnly; Secure; SameSite=Lax");
        return new Response(null, { status: 302, headers });
    }

    if (url.pathname === "/api/v2/auth/exchange" && request.method === "POST") {
        const dbError = requireDb(request, env);
        if (dbError) return dbError;
        const body = await boundedJson(request);
        const code = String(body.code || "");
        if (!code.startsWith("VX_")) return jsonResponse(request, env, { error: "Invalid exchange code." }, 400);
        const hash = await sha256Hex(code);
        const now = Date.now();
        // Consume and test expiry in one atomic SQLite statement.
        const consumed = await env.DB.prepare(`
            DELETE FROM auth_exchanges WHERE code_hash = ?1 AND expires_at > ?2
            RETURNING user_id
        `).bind(hash, now).first();
        if (!consumed) return jsonResponse(request, env, { error: "Login exchange expired. Please sign in again." }, 401);
        const row = await env.DB.prepare("SELECT *, id AS user_id FROM users WHERE id = ?1 AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id=?1)")
            .bind(consumed.user_id).first();
        if (!row || !discordAccessAllowed(env, row.discord_id)) return jsonResponse(request, env, { error: "Login exchange expired. Please sign in again." }, 401);
        const sessionToken = randomToken("VS_", 32);
        const sessionHash = await sha256Hex(sessionToken);
        await env.DB.prepare("DELETE FROM web_sessions WHERE expires_at <= ?1").bind(now).run();
        await env.DB.prepare(`
            INSERT INTO web_sessions (token_hash, user_id, created_at, expires_at)
            VALUES (?1, ?2, ?3, ?4)
        `).bind(sessionHash, row.user_id, now, now + 30 * 24 * 60 * 60 * 1000).run();
        return jsonResponse(request, env, { ok: true, token: sessionToken, user: publicUser(row) });
    }

    if (url.pathname === "/api/v2/auth/me" && request.method === "GET") {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;
        return jsonResponse(request, env, { ok: true, user: publicUser(auth.session.user) });
    }

    if (url.pathname === "/api/v2/auth/logout" && request.method === "POST") {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;
        await env.DB.prepare("DELETE FROM web_sessions WHERE token_hash = ?1").bind(auth.session.tokenHash).run();
        return jsonResponse(request, env, { ok: true });
    }

    if (url.pathname === "/api/v2/dashboard-key/generate" && request.method === "POST") {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;
        const body = await boundedJson(request);
        const alreadyExists = Boolean(auth.session.user.dashboard_key_hash);
        if (alreadyExists && body.confirm !== true) {
            return jsonResponse(request, env, { error: "Confirmation required to replace the current dashboard key." }, 409);
        }
        const key = generateDashboardKey();
        const keyHash = await sha256Hex(key);
        const suffix = key.slice(-6);
        const now = Date.now();
        const changed = await env.DB.prepare(`
            UPDATE users
            SET dashboard_key_hash = ?1, dashboard_key_suffix = ?2, updated_at = ?3
            WHERE id = ?4 AND (dashboard_key_hash IS NULL OR ?5 = 1)
              AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id=?4)
              AND EXISTS (SELECT 1 FROM web_sessions WHERE token_hash=?6 AND user_id=?4
                AND expires_at>CAST((julianday('now')-2440587.5)*86400000 AS INTEGER))
        `).bind(keyHash, suffix, now, auth.session.user.id, body.confirm === true ? 1 : 0, auth.session.tokenHash).run();
        if (!changed.meta?.changes) {
            const current = await requireWebSession(request, env);
            if (current.error) return current.error;
            return jsonResponse(request, env, { error: "Confirmation required to replace the current dashboard key." }, 409);
        }
        return jsonResponse(request, env, { ok: true, dashboardKey: key, suffix, replaced: alreadyExists });
    }

    if (url.pathname === "/api/v2/dashboard-key/verify" && request.method === "GET") {
        const dbError = requireDb(request, env);
        if (dbError) return dbError;
        const linked = await resolveDashboardUser(request, env);
        if (!linked) return jsonResponse(request, env, { error: "Invalid dashboard key." }, 401);
        return jsonResponse(request, env, { ok: true, user: publicUser(linked.user) });
    }

    return jsonResponse(request, env, { error: "Not found." }, 404);
}

async function handleRuntimeV2(request, env) {
    const url = new URL(request.url);
    if (!url.pathname.startsWith("/api/v2/runtime/")) return null;
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(request, env) });
    const dbError = requireDb(request, env);
    if (dbError) return dbError;

    if (url.pathname === "/api/v2/runtime/verify" && request.method === "GET") {
        const linked = await resolveDashboardUser(request, env);
        if (!linked) return jsonResponse(request, env, { error: "Invalid dashboard key." }, 401);
        await ensureRobloxAccountsSchema(env);
        return jsonResponse(request, env, { ok: true, user: publicUser(linked.user) });
    }

    if (url.pathname === "/api/v2/runtime/accounts" && request.method === "GET") {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;
        const rows = await listRobloxAccountRows(env, auth.session.user.id);
        return jsonResponse(request, env, {
            ok: true,
            accounts: rows.map(publicRobloxAccount),
        });
    }

    const accountDeleteMatch = url.pathname.match(/^\/api\/v2\/runtime\/accounts\/(\d+)$/);
    if (accountDeleteMatch && request.method === "DELETE") {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;
        const robloxUserId = normalizeRobloxUserId(accountDeleteMatch[1]);
        if (!robloxUserId) return jsonResponse(request, env, { error: "Invalid Roblox user ID." }, 400);

        const row = await getRobloxAccountRow(env, auth.session.user.id, robloxUserId);
        const accountObjectName = await runtimeAccountObjectName(auth.session.user.id, robloxUserId);
        const revokedObjectName = await runtimeRevokedObjectName(auth.session.user.id, robloxUserId);
        // Persist revocation first. A failed later cleanup stays blocked and a
        // repeated unlink must clean leftovers even when its row is absent.
        await env.PAYLOADS.put(revokedObjectName, JSON.stringify({ revokedAt: Date.now(), robloxUserId }), {
            httpMetadata: { contentType: "application/json; charset=utf-8" },
        });
        await env.DB.prepare(`DELETE FROM roblox_accounts WHERE veyra_user_id = ?1 AND roblox_user_id = ?2`)
            .bind(auth.session.user.id, robloxUserId).run();
        await env.PAYLOADS.delete(accountObjectName);

        const current = await readRuntimeV2(env, auth.session.user.id);
        const currentId = normalizeRobloxUserId(current.envelope?.robloxUserId || current.envelope?.snapshot?.player?.userId);
        if (currentId === robloxUserId) await env.PAYLOADS.delete(current.objectName);

        return jsonResponse(request, env, { ok: true, removed: Boolean(row), robloxUserId });
    }

    if (url.pathname === "/api/v2/runtime/link" && request.method === "POST") {
        const linked = await resolveDashboardUser(request, env);
        if (!linked) return jsonResponse(request, env, { error: "Invalid or expired dashboard key." }, 401);
        const body = await boundedJson(request);
        const robloxUserId = normalizeRobloxUserId(body.robloxUserId || body.userId);
        if (!robloxUserId) return jsonResponse(request, env, { error: "A valid Roblox user ID is required." }, 400);
        const revokedObjectName = await runtimeRevokedObjectName(linked.user.id, robloxUserId);
        await env.PAYLOADS.delete(revokedObjectName);
        return jsonResponse(request, env, { ok: true, user: publicUser(linked.user), robloxUserId });
    }

    if (url.pathname === "/api/v2/runtime/push" && request.method === "POST") {
        const linked = await resolveDashboardUser(request, env);
        if (!linked) return jsonResponse(request, env, { error: "Invalid or expired dashboard key." }, 401);
        const snapshot = await boundedJson(request, ACCOUNT_MAX_RUNTIME_BODY);
        if (!snapshot || typeof snapshot !== "object" || snapshot.schemaVersion !== 1) {
            return jsonResponse(request, env, { error: "Unsupported telemetry schema." }, 400);
        }

        const robloxUserId = normalizeRobloxUserId(snapshot?.player?.userId);
        if (!robloxUserId) {
            return jsonResponse(request, env, { error: "Telemetry is missing a valid Roblox user ID." }, 400);
        }
        if (await isRobloxAccountRevoked(env, linked.user.id, robloxUserId)) {
            return jsonResponse(request, env, {
                error: "This Roblox account was removed from the dashboard. Link the dashboard key again in Aroyn Hub → Session.",
                code: "ROBLOX_ACCOUNT_UNLINKED",
            }, 403);
        }

        const receivedAt = Date.now();
        if (!(await claimRuntimeSession(env, linked.user.id, robloxUserId, snapshot.session?.id, receivedAt))) {
            return jsonResponse(request, env, {error: 'Invalid session or session owned by another account.'}, 409);
        }
        const account = await upsertRobloxAccount(env, linked.user.id, snapshot, receivedAt);
        const accountObjectName = await runtimeAccountObjectName(linked.user.id, robloxUserId);
        const currentObjectName = await runtimeV2ObjectName(linked.user.id);
        const envelope = { snapshot, lastSeen: receivedAt, explicitOffline: false, robloxUserId };

        // Store a per-Roblox-account snapshot for the new selector and keep
        // the old "current" object as a compatibility mirror for older clients.
        await Promise.all([
            writeRuntimeV2(env, accountObjectName, envelope),
            writeRuntimeV2(env, currentObjectName, envelope),
        ]);
        const activeUser = await env.DB.prepare('SELECT id FROM users WHERE id=?1 AND dashboard_key_hash=?2 AND NOT EXISTS (SELECT 1 FROM account_deletions WHERE user_id=?1)').bind(linked.user.id, linked.user.dashboard_key_hash).first();
        if (!activeUser) {
            await Promise.all([env.PAYLOADS.delete(accountObjectName), env.PAYLOADS.delete(currentObjectName)]);
            return jsonResponse(request, env, {error: 'Account access revoked.'}, 401);
        }

        return jsonResponse(request, env, {
            ok: true,
            receivedAt,
            userId: linked.user.id,
            robloxAccount: account,
        });
    }

    if (url.pathname === "/api/v2/runtime/disconnect" && request.method === "POST") {
        const linked = await resolveDashboardUser(request, env);
        if (!linked) return jsonResponse(request, env, { error: "Invalid or expired dashboard key." }, 401);
        const body = await boundedJson(request);
        let robloxUserId = normalizeRobloxUserId(body.robloxUserId || body.userId);
        if (!robloxUserId) {
            const latest = await getRobloxAccountRow(env, linked.user.id, null);
            robloxUserId = latest ? String(latest.roblox_user_id) : null;
        }
        if (!robloxUserId) return jsonResponse(request, env, { ok: true });

        const { objectName, envelope } = await readRuntimeAccount(env, linked.user.id, robloxUserId);
        if (envelope) {
            await writeRuntimeV2(env, objectName, {
                snapshot: envelope.snapshot || null,
                lastSeen: Number(envelope.lastSeen || 0),
                explicitOffline: true,
                robloxUserId,
            });
        }

        const current = await readRuntimeV2(env, linked.user.id);
        const currentId = normalizeRobloxUserId(current.envelope?.robloxUserId || current.envelope?.snapshot?.player?.userId);
        if (currentId === robloxUserId && current.envelope) {
            await writeRuntimeV2(env, current.objectName, {
                snapshot: current.envelope.snapshot || null,
                lastSeen: Number(current.envelope.lastSeen || 0),
                explicitOffline: true,
                robloxUserId,
            });
        }
        return jsonResponse(request, env, { ok: true, robloxUserId });
    }

    if (url.pathname === "/api/v2/runtime/snapshot" && request.method === "GET") {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;

        const requestedId = normalizeRobloxUserId(url.searchParams.get("robloxUserId"));
        const accountRow = await getRobloxAccountRow(env, auth.session.user.id, requestedId);
        if (!accountRow) {
            return jsonResponse(request, env, {
                ok: true,
                online: false,
                lastSeen: null,
                snapshot: null,
                account: null,
            });
        }

        const robloxUserId = String(accountRow.roblox_user_id);
        const { envelope } = await readRuntimeAccount(env, auth.session.user.id, robloxUserId);
        if (!envelope || !envelope.snapshot) {
            return jsonResponse(request, env, {
                ok: true,
                online: false,
                lastSeen: Number(accountRow.last_seen_at || 0) || null,
                snapshot: null,
                account: publicRobloxAccount(accountRow),
            });
        }

        const lastSeen = Number(envelope.lastSeen || accountRow.last_seen_at || 0);
        const online = envelope.explicitOffline !== true && lastSeen > 0 && (Date.now() - lastSeen) < RUNTIME_STALE_AFTER_MS;
        return jsonResponse(request, env, {
            ok: true,
            online,
            lastSeen: lastSeen || null,
            snapshot: envelope.snapshot,
            account: publicRobloxAccount({ ...accountRow, last_seen_at: lastSeen }),
        });
    }

    return jsonResponse(request, env, { error: "Method not allowed." }, 405);
}

// ============================================================
// LEGACY V1 RUNTIME API
// Kept so the existing v1.10 site / V4.3.26 script do not break
// while the account system is being deployed.
// ============================================================

async function legacyRuntimeObjectName(key) {
    const hash = await sha256Hex(key);
    return `runtime-v1/${hash}.json`;
}

async function readLegacyRuntimeEnvelope(env, key) {
    const objectName = await legacyRuntimeObjectName(key);
    const object = await env.PAYLOADS.get(objectName);
    if (!object) return { objectName, envelope: null };
    try { return { objectName, envelope: JSON.parse(await object.text()) }; }
    catch { return { objectName, envelope: null }; }
}

async function writeLegacyRuntimeEnvelope(env, objectName, envelope) {
    await env.PAYLOADS.put(objectName, JSON.stringify(envelope), {
        httpMetadata: { contentType: "application/json; charset=utf-8" },
    });
}

async function handleLegacyRuntimeApi(request, env) {
    const url = new URL(request.url);
    const isRuntimeRoute = url.pathname === "/api/v1/health" || url.pathname.startsWith("/api/v1/runtime/");
    if (!isRuntimeRoute) return null;
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders(request, env) });
    if (url.pathname === "/api/v1/health") {
        return jsonResponse(request, env, { ok: true, service: "aroyn-runtime-api", storage: "r2", version: 3.1, accounts: Boolean(env.DB), multiRobloxAccounts: true, accountRemoval: true });
    }
    if (env.ALLOW_LEGACY_RUNTIME !== "true") return jsonResponse(request, env, { error: "Legacy runtime disabled. Use /api/v2/runtime/." }, 410);
    const linked = await resolveDashboardUser(request, env);
    if (!linked) return jsonResponse(request, env, { error: "Invalid dashboard key." }, 401);
    const dashboardKey = normalizeDashboardKey(bearerToken(request));
    if (!DASHBOARD_KEY_RE.test(dashboardKey)) return jsonResponse(request, env, { error: "Missing or invalid dashboard key." }, 401);

    if (url.pathname === "/api/v1/runtime/push" && request.method === "POST") {
        const snapshot = await boundedJson(request, LEGACY_MAX_RUNTIME_BODY);
        if (!snapshot || typeof snapshot !== "object" || snapshot.schemaVersion !== 1) return jsonResponse(request, env, { error: "Unsupported telemetry schema." }, 400);
        const objectName = await legacyRuntimeObjectName(dashboardKey);
        const receivedAt = Date.now();
        await writeLegacyRuntimeEnvelope(env, objectName, { snapshot, lastSeen: receivedAt, explicitOffline: false });
        return jsonResponse(request, env, { ok: true, receivedAt });
    }

    if (url.pathname === "/api/v1/runtime/snapshot" && request.method === "GET") {
        const { envelope } = await readLegacyRuntimeEnvelope(env, dashboardKey);
        if (!envelope || !envelope.snapshot) return jsonResponse(request, env, { ok: true, online: false, lastSeen: null, snapshot: null });
        const lastSeen = Number(envelope.lastSeen || 0);
        const online = envelope.explicitOffline !== true && lastSeen > 0 && (Date.now() - lastSeen) < RUNTIME_STALE_AFTER_MS;
        return jsonResponse(request, env, { ok: true, online, lastSeen: lastSeen || null, snapshot: envelope.snapshot });
    }

    if (url.pathname === "/api/v1/runtime/disconnect" && request.method === "POST") {
        const { objectName, envelope } = await readLegacyRuntimeEnvelope(env, dashboardKey);
        await writeLegacyRuntimeEnvelope(env, objectName, {
            snapshot: envelope?.snapshot || null,
            lastSeen: Number(envelope?.lastSeen || 0),
            explicitOffline: true,
        });
        return jsonResponse(request, env, { ok: true });
    }

    return jsonResponse(request, env, { error: "Method not allowed." }, 405);
}

function isRuntimeMutation(request) {
    const path = new URL(request.url).pathname;
    return request.method === 'POST' && ['/api/v2/runtime/push', '/api/v2/runtime/link', '/api/v2/runtime/disconnect', '/api/v2/account/delete', '/api/v2/dashboard-key/generate', '/api/v2/auth/logout', '/api/v1/runtime/push', '/api/v1/runtime/disconnect'].includes(path)
        || request.method === 'DELETE' && /^\/api\/v2\/runtime\/accounts\/\d+$/.test(path);
}

// Per-Aroyn-account ordering also protects the shared compatibility mirror
// across different Roblox accounts. Only active requests use the promise tail;
// durable revocation/data remain in R2/D1. No credentials or telemetry are
// stored in DO storage. Awaited work keeps the object alive until completion.
export class AroynRuntimeMutations {
    constructor(ctx, env) { this.env = env; this.userId = ctx.id?.name; this.tail = Promise.resolve(); }
    fetch(request) {
        const path = new URL(request.url).pathname;
        const continuation = path === '/account-deletion/finish' && request.method === 'POST';
        if (!isRuntimeMutation(request) && !continuation) return new Response('Not found', {status: 404});
        const task = this.tail.then(async () => {
            try {
                const env = withSnapshotStorage(this.env);
                if (continuation) {
                    const id = request.headers.get('x-deletion-user-id');
                    const maxObjects = Number(request.headers.get('x-deletion-max-objects'));
                    if (!/^[A-Za-z0-9_-]{1,128}$/.test(id || '') || (this.userId && this.userId !== id) || !Number.isInteger(maxObjects) || maxObjects < 1 || maxObjects > 25) return new Response('Invalid deletion continuation', {status: 400});
                    // Reload the durable job after waiting; stale callers cannot
                    // replay finalization or its ledger writes after completion.
                    const job = await env.DB.prepare('SELECT * FROM account_deletions WHERE user_id=?1').bind(id).first();
                    return Response.json({deleted: !job || await finishAccountDeletionInOrder(env, job, {maxObjects})});
                }
                if (path === '/api/v2/account/delete') return await handleAccountDataApi(request, env);
                if (path === '/api/v2/dashboard-key/generate' || path === '/api/v2/auth/logout') return await handleAccountAuthApi(request, env);
                if (path.startsWith('/api/v1/runtime/')) return await handleLegacyRuntimeApi(request, env);
                return await handleRuntimeV2(request, env);
            }
            catch (error) {
                if (error instanceof RequestInputError) return jsonResponse(request, this.env, {error: error.message}, error.status);
                throw error;
            }
        });
        this.tail = task.then(() => undefined, () => undefined);
        return task;
    }
}

async function dispatchRuntimeMutation(request, env) {
    const path = new URL(request.url).pathname;
    if (path.startsWith('/api/v1/runtime/') && env.ALLOW_LEGACY_RUNTIME !== 'true') {
        return jsonResponse(request, env, {error: 'Legacy runtime disabled. Use /api/v2/runtime/.'}, 410);
    }
    const dbError = requireDb(request, env);
    if (dbError) return dbError;
    // Finish reading the untrusted stream before authorization and before
    // joining the account queue. A slow upload must not hold up logout or
    // key rotation. The queued handler only receives a bounded, finite body.
    if (request.method === 'POST' && path !== '/api/v2/auth/logout' && path !== '/api/v1/runtime/disconnect') {
        const maxBytes = path === '/api/v2/runtime/push' ? ACCOUNT_MAX_RUNTIME_BODY
            : path === '/api/v1/runtime/push' ? LEGACY_MAX_RUNTIME_BODY : 8192;
        const body = await boundedJson(request, maxBytes);
        const headers = new Headers(request.headers);
        headers.delete('content-length');
        request = new Request(request, {headers, body: JSON.stringify(body)});
    }
    let userId;
    if (request.method === 'DELETE' || ['/api/v2/account/delete', '/api/v2/dashboard-key/generate', '/api/v2/auth/logout'].includes(path)) {
        const auth = await requireWebSession(request, env);
        if (auth.error) return auth.error;
        userId = auth.session.user.id;
    } else {
        const linked = await resolveDashboardUser(request, env);
        if (!linked) return jsonResponse(request, env, {error: 'Invalid or expired dashboard key.'}, 401);
        userId = linked.user.id;
    }
    if (!env.RUNTIME_MUTATIONS) return jsonResponse(request, env, {error: 'Runtime coordination unavailable.'}, 503);
    const stub = env.RUNTIME_MUTATIONS.get(env.RUNTIME_MUTATIONS.idFromName(userId));
    // Reauthenticate inside the serialized handler: queued credentials may
    // have been revoked after the outer routing lookup.
    const response = await stub.fetch(request);
    // Wake maintenance only AFTER releasing the user queue: its alarm may
    // already be awaiting this same user's deletion continuation.
    if (new URL(request.url).pathname === '/api/v2/account/delete' && response.status === 202) {
        try { await runDataRetention(env, Date.now(), {deletionRequested: true}); } catch { /* Daily Cron retries a failed wake-up. */ }
    }
    return response;
}

const apiWorker = {
    async scheduled(controller, env) {
        const result = await runDataRetention(env);
        console.log(JSON.stringify({event: 'account-data-maintenance-enqueued', ...result}));
    },
    async fetch(request, env) {
        try {
            env = withSnapshotStorage(env);
            const path = new URL(request.url).pathname;
            if (request.method !== "OPTIONS" && path !== "/api/v1/health") {
                await requestRateLimit(request, env.API_RATE_LIMITER);
            }
            if ((path === "/loader" || path === "/session" || path === "/payload" || path.startsWith("/game/")) && !env.TOKEN_SECRET) {
                return jsonResponse(request, env, {error: "Payload signing unavailable."}, 503);
            }
            if (stagingRestricted(env) && (path === '/loader' || path === '/session' || path === '/payload' || path.startsWith('/game/'))) {
                return jsonResponse(request, env, {error: 'Script distribution is disabled on the test environment.'}, 410);
            }
            if (isRuntimeMutation(request)) return await dispatchRuntimeMutation(request, env);
            return await apiWorker.handleRequest(request, env);
        } catch (error) {
            if (error instanceof RequestInputError) return jsonResponse(request, env, {error: error.message}, error.status);
            console.error(JSON.stringify({event: "api-request-failed", path: new URL(request.url).pathname}));
            return jsonResponse(request, env, {error: "Service temporarily unavailable."}, 500);
        }
    },
    async handleRequest(request, env) {
        const url = new URL(request.url);

        // ====================================================
        // PUBLIC VERSION MANIFEST
        //
        // Source of truth: first line of R2 object greedy-growers.luau:
        // local UpdateVersion = "x.y.z"
        //
        // Reads only the first 4 KiB of the payload and never touches D1.
        // The response is cacheable for 60 seconds.
        // ====================================================
        if (url.pathname === "/version.json" && request.method === "GET") {
            const object = await env.PAYLOADS.get("greedy-growers.luau", {
                range: { offset: 0, length: 4096 },
            });

            if (!object) {
                return jsonResponse(request, env, { error: "Greedy Growers payload not found." }, 404, {
                    "Cache-Control": "public, max-age=30",
                });
            }

            const source = await object.text();
            const match = source.match(/local\s+UpdateVersion\s*=\s*["']([^"']+)["']/);

            if (!match || !match[1]) {
                return jsonResponse(request, env, { error: "UpdateVersion was not found in the payload header." }, 500, {
                    "Cache-Control": "no-store",
                });
            }

            return jsonResponse(request, env, {
                version: String(match[1]),
            }, 200, {
                "Cache-Control": "public, max-age=60, stale-while-revalidate=300",
                "X-Content-Type-Options": "nosniff",
            });
        }

        const dataResponse = await handleAccountDataApi(request, env);
        if (dataResponse) return dataResponse;
        const accountResponse = await handleAccountAuthApi(request, env);
        if (accountResponse) return accountResponse;

        const runtimeV2Response = await handleRuntimeV2(request, env);
        if (runtimeV2Response) return runtimeV2Response;

        const legacyRuntimeResponse = await handleLegacyRuntimeApi(request, env);
        if (legacyRuntimeResponse) return legacyRuntimeResponse;

        // ====================================================
        // VEYRA HUB LOADER
        // Public entry point used by:
        // loadstring(game:HttpGet("https://veyra-api.veyra-hub.workers.dev/loader"))()
        //
        // The loader itself lives in R2 as: loader.luau
        // It checks game.GameId and then requests /game/<slug>.
        // ====================================================
        if (url.pathname === "/loader" && request.method === "GET") {
            const object = await env.PAYLOADS.get("loader.luau");
            if (!object) {
                return new Response("Veyra loader not found", {
                    status: 404,
                    headers: { "Content-Type": "text/plain; charset=utf-8" },
                });
            }

            // Create the short-lived payload token here so the Roblox client
            // does not need a separate /session request.
            const expires = Math.floor(Date.now() / 1000) + 60;
            const nonce = crypto.randomUUID();
            const unsigned = `${expires}.${nonce}`;
            const signature = await sign(env.TOKEN_SECRET, unsigned);
            const token = `${unsigned}.${signature}`;

            const loaderSource = await object.text();
            const bootstrap = `getgenv().__VEYRA_BOOTSTRAP = { api = ${JSON.stringify(url.origin)}, token = ${JSON.stringify(token)} }\n`;

            return new Response(bootstrap + loaderSource, {
                status: 200,
                headers: {
                    "Content-Type": "text/plain; charset=utf-8",
                    "Cache-Control": "no-store, no-cache, must-revalidate",
                    "X-Content-Type-Options": "nosniff",
                },
            });
        }

        // ====================================================
        // GAME PAYLOAD ROUTER
        //
        // /game/greedy-growers -> R2 object greedy-growers.luau
        // /game/another-game   -> R2 object another-game.luau
        //
        // Because the route is generic, adding future games does NOT require
        // redeploying this Worker. Upload <slug>.luau to R2 and add its
        // GameId -> slug mapping to loader.luau.
        // ====================================================
        const gameRoute = url.pathname.match(/^\/game\/([a-z0-9][a-z0-9-]{0,63})$/);
        if (gameRoute && request.method === "GET") {
            const token = url.searchParams.get("token");
            if (!token) return new Response("Missing token", { status: 401 });

            const parts = token.split(".");
            if (parts.length !== 3) return new Response("Invalid token", { status: 401 });

            const [expiresString, nonce, signature] = parts;
            const expires = Number(expiresString);
            const now = Math.floor(Date.now() / 1000);

            if (!Number.isFinite(expires) || now > expires) {
                return new Response("Token expired", { status: 401 });
            }

            const unsigned = `${expiresString}.${nonce}`;
            const expected = await sign(env.TOKEN_SECRET, unsigned);

            if (!safeEqual(signature, expected)) {
                return new Response("Invalid signature", { status: 401 });
            }

            const slug = gameRoute[1];
            const objectName = `${slug}.luau`;
            const object = await env.PAYLOADS.get(objectName);

            if (!object) {
                return new Response(`Veyra game payload not found: ${slug}`, {
                    status: 404,
                    headers: {
                        "Content-Type": "text/plain; charset=utf-8",
                        "Cache-Control": "no-store",
                    },
                });
            }

            return new Response(object.body, {
                status: 200,
                headers: {
                    "Content-Type": "text/plain; charset=utf-8",
                    "Cache-Control": "no-store, no-cache, must-revalidate",
                    "X-Content-Type-Options": "nosniff",
                    "X-Veyra-Game": slug,
                },
            });
        }

        // ====================================================
        // CREATE TEMP SESSION
        // Legacy compatibility: kept so old cached Veyra loaders continue
        // working while the new Hub loader is rolled out.
        // ====================================================
        if (url.pathname === "/session") {
            if (request.method !== "GET") return jsonResponse(request, env, { error: "Method not allowed." }, 405, { Allow: "GET" });
            const expires = Math.floor(Date.now() / 1000) + 60;
            const nonce = crypto.randomUUID();
            const unsigned = `${expires}.${nonce}`;
            const signature = await sign(env.TOKEN_SECRET, unsigned);
            const token = `${unsigned}.${signature}`;
            return new Response(token, {
                status: 200,
                headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" },
            });
        }

        // ====================================================
        // LEGACY PRIVATE PAYLOAD
        // Old loader compatibility only. It now serves the renamed
        // Greedy Growers payload instead of main.obfuscated.luau.
        // ====================================================
        if (url.pathname === "/payload") {
            if (request.method !== "GET") return jsonResponse(request, env, { error: "Method not allowed." }, 405, { Allow: "GET" });
            const token = url.searchParams.get("token");
            if (!token) return new Response("Missing token", { status: 401 });
            const parts = token.split(".");
            if (parts.length !== 3) return new Response("Invalid token", { status: 401 });
            const [expiresString, nonce, signature] = parts;
            const expires = Number(expiresString);
            const now = Math.floor(Date.now() / 1000);
            if (!Number.isFinite(expires) || now > expires) return new Response("Token expired", { status: 401 });
            const unsigned = `${expiresString}.${nonce}`;
            const expected = await sign(env.TOKEN_SECRET, unsigned);
            if (!safeEqual(signature, expected)) return new Response("Invalid signature", { status: 401 });

            const object = await env.PAYLOADS.get("greedy-growers.luau");
            if (!object) return new Response("Payload not found", { status: 404 });

            return new Response(object.body, {
                status: 200,
                headers: {
                    "Content-Type": "text/plain; charset=utf-8",
                    "Cache-Control": "no-store, no-cache, must-revalidate",
                    "X-Content-Type-Options": "nosniff",
                },
            });
        }

        return new Response(url.pathname === '/' ? "Aroyn API online" : "Not found", {
            status: url.pathname === '/' ? 200 : 404,
            headers: { "Content-Type": "text/plain; charset=utf-8" },
        });
    },
};

export default apiWorker;
