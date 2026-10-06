import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';
import {seedRecovery} from './recovery-fixture.mjs';
import {VeyraStatsHub} from '../workers/live/src/index.js';
let release,entered;
const gate=new Promise(r=>release=r),started=new Promise(r=>entered=r);
let armed=true;
const ledgerId='synthetic-analytics-deletion';
const runtime=await createRuntime({mock:true,ownerDiscordId:'900002',apiBindings:{DELETION_LEDGER_MODE:'required',DELETION_LEDGER_ID:ledgerId},outboundHook:async request=>{if(armed&&new URL(request.url).hostname==='users.roblox.com'){armed=false;entered();await gate;}}});
const wait=async(p,label)=>{let t;try{return await Promise.race([p,new Promise((_,r)=>t=setTimeout(()=>r(new Error('timeout '+label)),10000))]);}finally{clearTimeout(t);}};
try{
 const bucket=await runtime.mf.getR2Bucket('PAYLOADS','api');
 const {accounts:[a,b]}=await seedRecovery({DB:runtime.db,PAYLOADS:bucket});
 const ledger=await runtime.mf.getR2Bucket('DELETION_LEDGER','api');
 await ledger.put('coverage.json',JSON.stringify({format:'aroyn-deletion-ledger-v1',startedAt:Date.now()-1000,ledgerId,retentionDays:35}));
 await runtime.db.prepare('INSERT INTO deletion_ledger_gate VALUES(1,?1)').bind(ledgerId).run();
 await runtime.db.prepare('DELETE FROM analytics_sessions WHERE session_id=?1').bind('recovery-expired-history').run();
 await runtime.db.prepare('INSERT INTO roblox_profile_cache(roblox_user_id,username,updated_at) VALUES(?1,?2,?3)').bind(a.robloxId,'synthetic-old',1).run();
 const analytics=runtime.live.fetch('http://local/owner/analytics',{headers:{authorization:'Bearer '+b.token}});
 await wait(started,'native outbound');
 const deletion=runtime.api.fetch('http://local/api/v2/account/delete',{method:'POST',headers:{authorization:'Bearer '+a.token,'content-type':'application/json'},body:'{"confirmation":"DELETE"}'});
 await wait((async()=>{while(await runtime.db.prepare('SELECT session_id FROM analytics_sessions WHERE session_id=?1').bind(a.sid).first())await new Promise(r=>setTimeout(r,20));})(),'attributed analytics removal before invalidation');
 await new Promise(r=>setTimeout(r,100));
 const began=Date.now(); release();
 const [deleted,owner]=await wait(Promise.all([deletion,analytics]),'native requests');
 const result={deletionStatus:deleted.status,analyticsStatus:owner.status,userExists:Boolean(await runtime.db.prepare('SELECT id FROM users WHERE id=?1').bind(a.id).first()),cacheExists:Boolean(await runtime.db.prepare('SELECT roblox_user_id FROM roblox_profile_cache WHERE roblox_user_id=?1').bind(a.robloxId).first()),scope:'Native Miniflare Worker/DO with actual Workers/DO event loop and delayed external I/O; only synthetic stores and mocked delayed Roblox response'};
 result.elapsedAfterReleaseMs=Date.now()-began;
 assert.equal(result.deletionStatus,200); assert.equal(result.analyticsStatus,200); assert(result.elapsedAfterReleaseMs<5000);
 assert.equal(result.cacheExists,false); assert.equal(result.userExists,false);
 result.revokedSessionStatus=(await runtime.api.fetch('http://local/api/v2/auth/me',{headers:{authorization:'Bearer '+a.token}})).status;
 const ns=await runtime.mf.getDurableObjectNamespace('RUNTIME_MUTATIONS','api');
 const retry=await ns.get(ns.idFromName(a.id)).fetch('https://internal/account-deletion/finish',{method:'POST',headers:{'x-deletion-user-id':a.id,'x-deletion-max-objects':'25'}});
 result.retryStatus=retry.status; result.retryDeleted=(await retry.json()).deleted;
 result.userAfterRetry=Boolean(await runtime.db.prepare('SELECT id FROM users WHERE id=?1').bind(a.id).first());
 result.cacheAfterRetry=Boolean(await runtime.db.prepare('SELECT roblox_user_id FROM roblox_profile_cache WHERE roblox_user_id=?1').bind(a.robloxId).first());
 assert.equal(result.revokedSessionStatus,401); assert.equal(result.retryDeleted,true); assert.equal(result.userAfterRetry,false); assert.equal(result.cacheAfterRetry,false);

 const fresh=await runtime.live.fetch('http://local/owner/analytics',{headers:{authorization:'Bearer '+b.token}});
 assert.equal(fresh.status,200);
 const payload=await fresh.json();
 assert(!payload.analytics.allUsers.some(user=>String(user.userId)===a.robloxId));
 assert(payload.analytics.allUsers.some(user=>String(user.userId)===b.robloxId));
 assert.equal(await runtime.db.prepare('SELECT roblox_user_id FROM roblox_profile_cache WHERE roblox_user_id=?1').bind(a.robloxId).first(),null);
 result.freshAnalyticsExcludesDeletedUser=true;
 // Pause the final persistent range-cache write after the raw analytics
 // promise has resolved. Invalidation must drain this write as well.
 const originalFetch=globalThis.fetch;
 let releaseWrite,enterWrite;
 const writeGate=new Promise(r=>releaseWrite=r),writeStarted=new Promise(r=>enterWrite=r);
 let writeArmed=true,failInvalidation=false;
 const wrap=(stmt,sql,args=[])=>new Proxy(stmt,{get(target,name){
  if(name==='bind')return (...values)=>wrap(target.bind(...values),sql,values);
  if(name==='run')return async()=>{
   if(failInvalidation&&sql==='DELETE FROM owner_analytics_cache'){failInvalidation=false;throw new Error('Synthetic cache outage');}
   if(writeArmed&&sql.includes('INSERT INTO owner_analytics_cache')&&args[0]==='v4:24h:0'){writeArmed=false;enterWrite();await writeGate;}
   return target.run();
  };
  const value=Reflect.get(target,name);return typeof value==='function'?value.bind(target):value;
 }});
 try {
  globalThis.fetch=async()=>new Response('External requests disabled',{status:502});
  await runtime.db.prepare('DELETE FROM owner_analytics_cache').run();
  const hub=new VeyraStatsHub({blockConcurrencyWhile(){assert.fail('Invalidation must leave the I/O event loop open');}},
   {DB:{prepare:sql=>wrap(runtime.db.prepare(sql),sql),batch:stmts=>runtime.db.batch(stmts)}});
  const reading=hub.getCachedOwnerAnalytics('24h',0);
  await wait(writeStarted,'persistent analytics write');
  let invalidated=false;
  const invalidation=hub.fetch(new Request('https://internal/invalidate-user-data',{method:'POST'})).then(r=>{invalidated=true;return r;});
  await new Promise(r=>setTimeout(r,20));assert.equal(invalidated,false);
  releaseWrite();await wait(reading,'analytics persistent completion');
  assert.equal((await wait(invalidation,'ordered cache invalidation')).status,204);
  assert.equal((await runtime.db.prepare('SELECT COUNT(*) AS n FROM owner_analytics_cache').first()).n,0);
  assert.equal(hub.ownerAnalyticsCache.size,0);
  failInvalidation=true;
  await assert.rejects(hub.fetch(new Request('https://internal/invalidate-user-data',{method:'POST'})),/Synthetic cache outage/);
  assert.equal((await hub.fetch(new Request('https://internal/invalidate-user-data',{method:'POST'}))).status,204);
  assert((await hub.getCachedOwnerAnalytics('24h',0)).analytics);
  result.finalPersistentWriteDrained=true;result.failedInvalidationRetryWorks=true;
 } finally {releaseWrite();globalThis.fetch=originalFetch;}
 console.log(JSON.stringify(result));await writeFile(new URL('./native-deletion-overlap-results.json',import.meta.url),JSON.stringify(result,null,2));
}finally{release();await runtime.mf.dispose();}

