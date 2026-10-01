const hex = bytes => Array.from(bytes, n => n.toString(16).padStart(2, '0')).join('');
export const hash = async value => hex(new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))));
const random = () => hex(crypto.getRandomValues(new Uint8Array(32)));
export async function seedRecovery(env) {
  const now = Date.now(), accounts = [];
  for (let i = 0; i < 2; i++) {
    const id = 'usr_recovery_' + i, token = 'VS_' + random();
    const parts = random().slice(0, 24).toUpperCase().match(/.{6}/g);
    const key = ['VY', ...parts].join('-'), sid = 'recovery-session-' + i;
    await env.DB.batch([
      env.DB.prepare('INSERT INTO users(id,discord_id,discord_username,dashboard_key_hash,dashboard_key_suffix,created_at,updated_at,last_login_at) VALUES(?1,?2,?3,?4,?5,?6,?6,?6)').bind(id, String(900001 + i), 'recovery-fixture-' + i, await hash(key), key.slice(-6), now),
      env.DB.prepare('INSERT INTO web_sessions VALUES(?1,?2,?3,?4)').bind(await hash(token), id, now, now + 3600000),
      env.DB.prepare('INSERT INTO auth_exchanges VALUES(?1,?2,?3,?4)').bind(await hash('exchange-' + id), id, now + 3600000, now),
      env.DB.prepare('INSERT INTO roblox_accounts(veyra_user_id,roblox_user_id,username,first_seen_at,last_seen_at,last_session_id) VALUES(?1,?2,?3,?4,?4,?5)').bind(id, String(990001 + i), 'fixture-' + i, now, sid),
      env.DB.prepare('INSERT INTO runtime_session_owners VALUES(?1,?2,?3,?4,?4)').bind(sid, id, String(990001 + i), now),
      env.DB.prepare('INSERT INTO analytics_sessions(session_id,roblox_user_id,version,started_at,last_seen_at) VALUES(?1,?2,?3,?4,?4)').bind(sid, String(990001 + i), 'recovery-fixture', now),
    ]);
    await env.PAYLOADS.put(`runtime-v3/${id}/accounts/${990001 + i}.json`, JSON.stringify({fixture: true}));
    accounts.push({id, token, key, sid, robloxId: String(990001 + i)});
  }
  await env.DB.prepare('INSERT INTO analytics_sessions(session_id,roblox_user_id,started_at,last_seen_at) VALUES(?1,?2,?3,?3)').bind('recovery-expired-history', '990001', now - 31 * 86400000).run();
  await env.PAYLOADS.put('unrelated-fixture.txt', 'Keep this synthetic payload');
  return {accounts, backupAt: now};
}
export function recoveryInputs(backupAt) {
  const frozenAt = Date.now();
  return {
    manifest: {format: 'aroyn-recovery-deletions-v1', complete: true, coverageFrom: backupAt, coverageThrough: frozenAt, deletions: [{userId: 'usr_recovery_0', requestedAt: frozenAt}]},
    context: {isolatedDestination: true, apiAccessClosed: true, liveAccessClosed: true, freshDurableObjects: true, signingSecretsRotated: true, backupAt, frozenAt},
  };
}
