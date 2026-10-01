// Optional restricted test environment. An invalid/empty list denies access.
// Keep the allowlist in a server-side secret binding, never in the site bundle.
export function stagingRestricted(env) {
  return String(env.STAGING_ACCESS || '').trim() !== '';
}

function allowedIds(env) {
  if (String(env.STAGING_ACCESS || '').trim() !== 'restricted') return [];
  const raw = String(env.STAGING_DISCORD_IDS || '');
  if (raw.length > 4096) return [];
  const ids = raw.split(',').map(id => id.trim());
  return ids.length <= 32 && ids.every(id => /^\d{15,22}$/.test(id)) ? ids : [];
}

export function stagingAccessReady(env) {
  return !stagingRestricted(env) || allowedIds(env).length > 0;
}

export function discordAccessAllowed(env, id) {
  return !stagingRestricted(env) || allowedIds(env).includes(String(id || ''));
}
