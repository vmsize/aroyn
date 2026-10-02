import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createRuntime, folder} from './runtime.mjs';
import {seedRecovery, recoveryInputs, hash} from './recovery-fixture.mjs';
import {recoveryStep} from '../tools/recovery-sanitizer.mjs';
import {localMutationNamespace} from './mutation-helpers.mjs';

const original = await createRuntime({mock: true});
let restored;
const results = [];
const pass = name => {results.push({name, pass: true}); console.log('PASS ' + name);};
const bearer = token => ({headers: {authorization: 'Bearer ' + token}});
try {
  const oldBucket = await original.mf.getR2Bucket('PAYLOADS', 'api');
  const seeded = await seedRecovery({DB: original.db, PAYLOADS: oldBucket});
  const [a, b] = seeded.accounts;
  const issued = await original.live.fetch('http://local/token', {method: 'POST', headers: {authorization: 'Bearer ' + b.key, 'content-type': 'application/json'}, body: JSON.stringify({robloxUserId: b.robloxId})});
  assert.equal(issued.status, 200); const oldLiveToken = (await issued.json()).token;
  const tables = (await original.db.prepare("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' ORDER BY CASE WHEN name='users' THEN 0 ELSE 1 END, name").all()).results.map(r => r.name);
  const backup = [];
  for (const table of tables) backup.push({table, rows: (await original.db.prepare('SELECT * FROM ' + table).all()).results});
  const objects = [];
  for (const o of (await oldBucket.list()).objects) objects.push({key: o.key, value: await (await oldBucket.get(o.key)).text()});
  const deleted = await original.api.fetch('http://local/api/v2/account/delete', {method: 'POST', headers: {authorization: 'Bearer ' + a.token, 'content-type': 'application/json'}, body: JSON.stringify({confirmation: 'DELETE'})});
  assert.equal(deleted.status, 200);
  assert.equal(await original.db.prepare('SELECT id FROM users WHERE id=?1').bind(a.id).first(), null);
  pass('backup precedes completed deletion; external synthetic manifest survives separately');

  restored = await createRuntime({mock: true, apiBindings: {TOKEN_SECRET: 'fresh-recovery-api-secret'}, liveBindings: {LIVE_TOKEN_SECRET: 'fresh-recovery-live-secret', PRESENCE_TOKEN_SECRET: 'fresh-recovery-presence-secret', STATS_API_SECRET: 'fresh-recovery-stats-secret'}});
  for (const {table, rows} of backup) for (const row of rows) {
    const columns = Object.keys(row);
    await restored.db.prepare(`INSERT INTO ${table}(${columns.join(',')}) VALUES(${columns.map(() => '?').join(',')})`).bind(...Object.values(row)).run();
  }
  const bucket = await restored.mf.getR2Bucket('PAYLOADS', 'api');
  for (const object of objects) await bucket.put(object.key, object.value);
  // Controlled call inside a closed fixture demonstrates why DB restore alone
  // is unsafe: rotating signing secrets does not revoke stored bearer sessions.
  assert.equal((await restored.api.fetch('http://local/api/v2/auth/me', bearer(a.token))).status, 200);
  pass('raw isolated restore resurrects deleted profile and stored bearer session');
  const payload = JSON.parse(Buffer.from(oldLiveToken.split('.')[1], 'base64url').toString());
  assert(payload.expiresAt > Math.floor(Date.now() / 1000));
  assert.equal((await restored.live.fetch('http://local/ws?token=' + encodeURIComponent(oldLiveToken), {headers: {Upgrade: 'websocket'}})).status, 401);
  const freshIssued = await restored.live.fetch('http://local/token', {method: 'POST', headers: {authorization: 'Bearer ' + b.key, 'content-type': 'application/json'}, body: JSON.stringify({robloxUserId: b.robloxId})});
  assert.equal(freshIssued.status, 200); const freshLiveToken = (await freshIssued.json()).token;
  pass('fresh signer rejects demonstrably unexpired old live token while restored linkage can issue a fresh one');
  const env = {DB: restored.db, PAYLOADS: bucket, SNAPSHOT_STORAGE: await restored.mf.getDurableObjectNamespace('SNAPSHOT_STORAGE', 'api'), STATS_CACHE: await restored.mf.getDurableObjectNamespace('STATS_CACHE', 'api')};
  env.RUNTIME_MUTATIONS=localMutationNamespace(env);
  const {manifest, context} = recoveryInputs(seeded.backupAt);
  for (const flag of ['isolatedDestination', 'apiAccessClosed', 'liveAccessClosed', 'freshDurableObjects', 'signingSecretsRotated']) await assert.rejects(recoveryStep(env, manifest, {...context, [flag]: false}));
  await assert.rejects(recoveryStep(env, {...manifest, complete: false}, context));
  await assert.rejects(recoveryStep(env, {...manifest, coverageFrom: seeded.backupAt + 1}, context));
  await assert.rejects(recoveryStep(env, {...manifest, coverageThrough: context.frozenAt - 1}, context));
  await assert.rejects(recoveryStep(env, {...manifest, deletions: [...manifest.deletions, ...manifest.deletions]}, context));
  assert.equal((await restored.api.fetch('http://local/api/v2/auth/me', bearer(a.token))).status, 200);
  pass('missing isolation, access freeze, rotations or complete coverage rejects before mutations');

  let state = await recoveryStep(env, manifest, context);
  for (const account of [a, b]) {
    assert.equal((await restored.api.fetch('http://local/api/v2/auth/me', bearer(account.token))).status, 401);
    assert.equal((await restored.api.fetch('http://local/api/v2/runtime/verify', bearer(account.key))).status, 401);
  }
  assert.equal((await restored.db.prepare('SELECT COUNT(*) AS n FROM auth_exchanges').first()).n, 0);
  pass('first recovery step revokes both accounts sessions, exchanges and dashboard keys');
  await assert.rejects(recoveryStep(env, {...manifest, complete: false}, context, state));
  await assert.rejects(recoveryStep(env, manifest, {...context, frozenAt: context.frozenAt + 1}, state));
  pass('saved progress cannot continue with changed recovery inputs');

  while (state.phase !== 'delete') state = await recoveryStep(env, manifest, context, state);
  const beforeFailure = structuredClone(state);
  const brokenEnv={...env,PAYLOADS:{list:async()=>{throw new Error('Fixture storage outage');}}};brokenEnv.RUNTIME_MUTATIONS=localMutationNamespace(brokenEnv);
  await assert.rejects(recoveryStep(brokenEnv, manifest, context, state));
  assert.deepEqual(state, beforeFailure);
  assert(await restored.db.prepare('SELECT user_id FROM account_deletions WHERE user_id=?1').bind(a.id).first());
  pass('failed deletion keeps checkpoint and deletion marker for safe retry');
  let rounds = 0;
  while (!state.sanitized && rounds++ < 100) state = await recoveryStep(env, manifest, context, JSON.parse(JSON.stringify(state)));
  assert(state.sanitized); assert.equal(state.reopenAllowed, false);
  assert.equal(await restored.db.prepare('SELECT id FROM users WHERE id=?1').bind(a.id).first(), null);
  assert.equal(await restored.db.prepare('SELECT session_id FROM analytics_sessions WHERE session_id=?1').bind(a.sid).first(), null);
  assert(await restored.db.prepare('SELECT id FROM users WHERE id=?1').bind(b.id).first());
  assert(await restored.db.prepare('SELECT session_id FROM analytics_sessions WHERE session_id=?1').bind(b.sid).first());
  assert.equal(await restored.db.prepare('SELECT session_id FROM analytics_sessions WHERE session_id=?1').bind('recovery-expired-history').first(), null);
  pass('replayed deletion removes restored account; other profile and unexpired attributed history survive');
  for (const table of ['account_deletions', 'web_sessions', 'auth_exchanges', 'roblox_accounts', 'runtime_presence', 'live_presence', 'roblox_profile_cache', 'owner_analytics_cache']) assert.equal((await restored.db.prepare('SELECT COUNT(*) AS n FROM ' + table).first()).n, 0);
  assert.deepEqual((await bucket.list()).objects.map(o => o.key), ['unrelated-fixture.txt']);
  assert.equal((await restored.live.fetch('http://local/ws?token=' + encodeURIComponent(freshLiveToken), {headers: {Upgrade: 'websocket'}})).status, 401);
  pass('old associations, presence and all runtime copies are cleared; unrelated payload survives');
  const again = await recoveryStep(env, manifest, context, state); assert(again.sanitized); assert.equal(again.reopenAllowed, false);
  pass('completed sanitation is repeatable and never opens access automatically');
  const freshToken = 'VS_fresh-recovery-session';
  await restored.db.prepare('INSERT INTO web_sessions VALUES(?1,?2,?3,?4)').bind(await hash(freshToken), b.id, Date.now(), Date.now() + 3600000).run();
  const exportResponse = await restored.api.fetch('http://local/api/v2/account/export', bearer(freshToken));
  assert.equal(exportResponse.status, 200); const exported = await exportResponse.text();
  assert(exported.includes(b.sid)); assert(!exported.includes(a.sid)); assert.equal(JSON.parse(exported.trim().split('\n').at(-1)).type, 'complete');
  pass('fresh surviving-account session exports preserved history without deleted account records');
  await writeFile(resolve(folder, 'recovery-results.json'), JSON.stringify({source: 'isolated Miniflare; row/object copies; OAuth mocked; not provider Time Travel', results}, null, 2));
} finally {await original.mf.dispose(); if (restored) await restored.mf.dispose();}
