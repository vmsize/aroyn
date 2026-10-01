import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import {createRuntime} from './runtime.mjs';
import {seedRecovery} from './recovery-fixture.mjs';
const runtime=await createRuntime({mock:true}),results=[];
try {
  const bucket=await runtime.mf.getR2Bucket('PAYLOADS','api');
  const {accounts:[a,b]}=await seedRecovery({DB:runtime.db,PAYLOADS:bucket});
  for(const size of [1000,10000]) {
    if(size===10000) {
      const now=Date.now();
      await runtime.db.batch([
        runtime.db.prepare('INSERT INTO users(id,discord_id,discord_username,dashboard_key_hash,dashboard_key_suffix,created_at,updated_at,last_login_at) VALUES(?1,?2,?3,?4,?5,?6,?6,?6)').bind(a.id,'900001','fixture',null,null,now),
      ]);
      const {hash}=await import('./recovery-fixture.mjs');
      await runtime.db.prepare('INSERT INTO web_sessions VALUES(?1,?2,?3,?4)').bind(await hash(a.token),a.id,now,now+3600000).run();
    }
    const now=Date.now(),prefix='large-deletion-'+size+'-';
    const range='WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i+1 FROM n WHERE i<?1) ';
    await runtime.db.batch([
      runtime.db.prepare(range+'INSERT INTO analytics_sessions(session_id,roblox_user_id,version,started_at,last_seen_at) SELECT ?2||i,?3,?4,?5,?5 FROM n').bind(size,prefix,a.robloxId,'synthetic',now),
      runtime.db.prepare(range+'INSERT INTO runtime_session_owners SELECT ?2||i,?3,?4,?5,?5 FROM n').bind(size,prefix,a.id,a.robloxId,now),
      runtime.db.prepare(range+'INSERT INTO web_sessions SELECT ?2||i,?3,?4,?5 FROM n').bind(size,prefix+'web-',a.id,now,now+3600000),
      runtime.db.prepare(range+'INSERT INTO auth_exchanges SELECT ?2||i,?3,?4,?5 FROM n').bind(size,prefix+'exchange-',a.id,now+3600000,now),
    ]);
    const begin=performance.now();
    const response=await runtime.api.fetch('http://local/api/v2/account/delete',{method:'POST',headers:{authorization:'Bearer '+a.token,'content-type':'application/json'},body:JSON.stringify({confirmation:'DELETE'})});
    const elapsedMs=Math.round(performance.now()-begin);assert.equal(response.status,200);
    for(const [table,column] of [['users','id'],['web_sessions','user_id'],['auth_exchanges','user_id'],['runtime_session_owners','veyra_user_id']]) assert.equal((await runtime.db.prepare(`SELECT COUNT(*) AS n FROM ${table} WHERE ${column}=?1`).bind(a.id).first()).n,0);
    assert.equal((await runtime.db.prepare('SELECT COUNT(*) AS n FROM analytics_sessions WHERE session_id LIKE ?1').bind(prefix+'%').first()).n,0);
    assert(await runtime.db.prepare('SELECT id FROM users WHERE id=?1').bind(b.id).first());
    assert(await runtime.db.prepare('SELECT session_id FROM analytics_sessions WHERE session_id=?1').bind(b.sid).first());
    assert(await bucket.head(`runtime-v3/${b.id}/accounts/${b.robloxId}.json`));
    results.push({ownedHistoryRows:size,ownershipRows:size,extraWebSessions:size,authExchanges:size,elapsedMs,deletedAccountAbsent:true,unrelatedAccountPreserved:true});console.log(JSON.stringify(results.at(-1)));
  }
  await fs.writeFile(new URL('./account-capacity-results.json',import.meta.url),JSON.stringify({date:'2026-10-01',passed:true,scope:'local Miniflare D1/R2/DO; mocked external services; scoped history SQL and foreign-key cascades; small R2 footprint',cloudCpuOrQuotaMeasured:false,results},null,2)+'\n');
}finally{await runtime.mf.dispose();}
