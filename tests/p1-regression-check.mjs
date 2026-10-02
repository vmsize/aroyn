// Synthetic local identities and Miniflare stores only. No cloud or browser.
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';
import {hash} from './recovery-fixture.mjs';
import {localMutationNamespace} from './mutation-helpers.mjs';
import api from '../workers/api/src/worker.js';
import live from '../workers/live/src/index.js';
import {pruneDeletionLedger} from '../workers/shared/deletion-ledger.js';
import {withSnapshotStorage} from '../workers/shared/snapshot-storage.js';
import {finishAccountDeletion} from '../workers/shared/data-lifecycle.js';
import {AroynRetentionRunner,newRetentionCycle} from '../workers/shared/retention-runner.js';

const ledgerId='local-p1-ledger';
const runtime=await createRuntime({mock:true,apiBindings:{DELETION_LEDGER_MODE:'required',DELETION_LEDGER_ID:ledgerId,ALLOW_LEGACY_RUNTIME:'true'}});
const results=[],DAY=86400000;
const pass=name=>{results.push({name,pass:true});console.log('PASS '+name);};
function barrier(){let enter,release;return {entered:new Promise(r=>enter=r),gate:new Promise(r=>release=r),enter:()=>enter(),release:()=>release()};}
async function within(p,label){let timer;try{return await Promise.race([p,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Timed out: '+label)),5000);})]);}finally{clearTimeout(timer);}}
async function until(fn,label){await within((async()=>{while(!fn())await new Promise(r=>setTimeout(r,5));})(),label);}
function memoryStorage(){const data=new Map();let alarm=null;return {async get(k){return structuredClone(data.get(k));},async put(k,v){data.set(k,structuredClone(v));},async setAlarm(v){alarm=v;},async getAlarm(){return alarm;},async deleteAlarm(){alarm=null;},async transaction(fn){return fn(this);}};}
try {
 const bucket=await runtime.mf.getR2Bucket('PAYLOADS','api'),ledger=await runtime.mf.getR2Bucket('DELETION_LEDGER','api');
 const clock=Date.now();const coverage={format:'aroyn-deletion-ledger-v1',ledgerId,startedAt:clock-40*DAY,retentionDays:35};
 await ledger.put('coverage.json',JSON.stringify(coverage));
 await runtime.db.prepare('INSERT INTO deletion_ledger_gate VALUES(1,?1)').bind(ledgerId).run();
 const env={DB:runtime.db,PAYLOADS:bucket,DELETION_LEDGER:ledger,DELETION_LEDGER_MODE:'required',DELETION_LEDGER_ID:ledgerId,ALLOW_LEGACY_RUNTIME:'true',
  API_RATE_LIMITER:{limit:async()=>({success:true})},SNAPSHOT_STORAGE:await runtime.mf.getDurableObjectNamespace('SNAPSHOT_STORAGE','api'),STATS_CACHE:await runtime.mf.getDurableObjectNamespace('STATS_CACHE','api'),
  RETENTION_RUNNER:{idFromName:id=>id,get:()=>({fetch:async()=>Response.json({ok:true,started:true})})}};
 const normal=withSnapshotStorage(env).PAYLOADS;env.PAYLOADS=normal;
 const queued=new Map();function resetCoordinator(){const local=localMutationNamespace(env);env.RUNTIME_MUTATIONS={idFromName:id=>id,get:id=>({fetch:(input,options)=>{queued.set(id,(queued.get(id)||0)+1);return local.get(id).fetch(input,options);}})};}
 resetCoordinator();
 let serial=0;
 async function account(){const i=++serial,now=Date.now(),id='usr_p1_'+i,token='VS_local_p1_'+i,key=`VY-${String(i).padStart(6,'0')}-AAAAAA-BBBBBB-CCCCCC`,robloxId=String(991000+i),sid='p1-local-session-'+i;
  await runtime.db.batch([
   runtime.db.prepare('INSERT INTO users(id,discord_id,discord_username,dashboard_key_hash,dashboard_key_suffix,created_at,updated_at,last_login_at) VALUES(?1,?2,?3,?4,?5,?6,?6,?6)').bind(id,String(901000+i),'synthetic',await hash(key),key.slice(-6),now),
   runtime.db.prepare('INSERT INTO web_sessions VALUES(?1,?2,?3,?4)').bind(await hash(token),id,now,now+DAY),
   runtime.db.prepare('INSERT INTO roblox_accounts(veyra_user_id,roblox_user_id,username,avatar_updated_at,first_seen_at,last_seen_at) VALUES(?1,?2,?3,?4,?4,?4)').bind(id,robloxId,'synthetic',now),
  ]);return {id,token,key,robloxId,sid};
 }
 const req=(path,token,method='POST',body)=>api.fetch(new Request('http://local'+path,{method,headers:{authorization:'Bearer '+token,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})}),env);
 const push=a=>req('/api/v2/runtime/push',a.key,'POST',{schemaVersion:1,player:{userId:Number(a.robloxId)},session:{id:a.sid},stats:{cash:123}});
 const del=a=>req('/api/v2/account/delete',a.token,'POST',{confirmation:'DELETE'});
 const key=a=>`runtime-v3/${a.id}/accounts/${a.robloxId}.json`;
 async function absent(a){assert.equal(await runtime.db.prepare('SELECT id FROM users WHERE id=?1').bind(a.id).first(),null);for(const prefix of [`runtime-v2/${a.id}/`,`runtime-v3/${a.id}/`])assert.equal((await bucket.list({prefix})).objects.length,0);assert.equal(await bucket.head('runtime-v1/'+await hash(a.key)+'.json'),null);assert((await ledger.get('events/'+a.id+'.json')));}

 // AR-02: preserve the expiry cutoff while validating against a later clock.
 const cutoff=clock-1000;
 await ledger.put('events/usr_p1_old.json',JSON.stringify({userId:'usr_p1_old',requestedAt:clock-36*DAY}));
 await ledger.put('events/usr_p1_recent.json',JSON.stringify({userId:'usr_p1_recent',requestedAt:clock}));
 const storage=memoryStorage();await storage.put('progress',{...newRetentionCycle(cutoff),phase:'ledger'});
 let runner=new AroynRetentionRunner({storage},env);await runner.alarm();
 assert.equal((await storage.get('progress')).phase,'invalidate');assert.equal((await storage.get('progress')).now,cutoff);assert.equal(await ledger.get('events/usr_p1_old.json'),null);assert(await ledger.get('events/usr_p1_recent.json'));
 pass('new deletion after cycle cutoff is kept while expired ledger event is removed');
 // The record can also arrive during an awaited R2 read within this page.
 const validationStart=Date.now();let concurrentEvent;
 const concurrentLedger={
  get:async k=>k==='coverage.json'?{size:100,json:async()=>coverage}:{size:100,json:async()=>{
   await until(()=>Date.now()>validationStart,'ledger read clock advances');
   concurrentEvent={userId:'usr_during_read',requestedAt:Date.now()};return concurrentEvent;
  }},
  list:async()=>({objects:[{key:'events/usr_during_read.json'}],truncated:false}),
  delete:async()=>assert.fail('A current deletion must be retained'),
 };
 assert.equal((await pruneDeletionLedger({...env,DELETION_LEDGER:concurrentLedger},{now:cutoff,validationNow:validationStart})).visited,1);
 assert(concurrentEvent.requestedAt>validationStart);
 pass('deletion arriving during a ledger read validates against the clock after that read');
 // A genuinely future event is still rejected; a corrected retry resumes the
 // saved cutoff after recreation rather than silently claiming completeness.
 await ledger.put('events/usr_p1_future.json',JSON.stringify({userId:'usr_p1_future',requestedAt:clock+DAY}));
 await storage.put('progress',{...newRetentionCycle(cutoff),phase:'ledger'});await runner.alarm();
 assert.equal((await storage.get('progress')).phase,'ledger');assert.equal((await storage.get('progress')).failures,1);
 await ledger.delete('events/usr_p1_future.json');runner=new AroynRetentionRunner({storage},env);await runner.alarm();await runner.alarm();
 assert.equal((await storage.get('progress')).active,false);assert.equal((await storage.get('progress')).now,cutoff);
 const start=await runner.fetch(new Request('https://internal/start',{method:'POST'}));assert.equal((await start.json()).started,true);assert.equal((await ledger.get('coverage.json')).size,JSON.stringify(coverage).length);
 pass('real future event fails closed; retry after restart completes and next cycle starts without resetting ledger');

 // Another user can proceed while a mutation for this one waits.
 const other=await account();assert.equal((await push(other)).status,200);
 for(const operation of ['disconnect','unlink','push','legacy-disconnect']) {
  const a=await account();assert.equal((await push(a)).status,200);
  if(operation==='legacy-disconnect')await bucket.put('runtime-v1/'+await hash(a.key)+'.json',JSON.stringify({snapshot:{schemaVersion:1,stats:{cash:5}},lastSeen:Date.now()}));
  const pause=barrier();let once=true;
  const marker=`runtime-v3/${a.id}/revoked/${a.robloxId}.json`;
  if(operation==='unlink')env.PAYLOADS={...normal,put:async(k,...args)=>{if(once&&k===marker){once=false;pause.enter();await pause.gate;}return normal.put(k,...args);}};
  else if(operation==='push')env.PAYLOADS={...normal,head:async k=>{const value=await normal.head(k);if(once&&k===marker){once=false;pause.enter();await pause.gate;}return value;}};
  else {const target=operation==='disconnect'?key(a):'runtime-v1/'+await hash(a.key)+'.json';env.PAYLOADS={...normal,get:async k=>{const value=await normal.get(k);if(once&&k===target){once=false;pause.enter();await pause.gate;}return value;}};}
  const first=operation==='unlink'?req('/api/v2/runtime/accounts/'+a.robloxId,a.token,'DELETE'):operation==='push'?push(a):req(operation==='disconnect'?'/api/v2/runtime/disconnect':'/api/v1/runtime/disconnect',a.key,'POST',{robloxUserId:a.robloxId});
  await within(pause.entered,operation+' barrier');let settled=false;const before=queued.get(a.id)||0;const deletion=del(a).then(r=>{settled=true;return r;});await until(()=>(queued.get(a.id)||0)>before,'deletion queued');
  assert.equal(settled,false);assert.equal((await push(other)).status,200);
  pause.release();assert.equal((await within(first,'accepted mutation')).status,200);assert.equal((await within(deletion,'ordered deletion')).status,200);env.PAYLOADS=normal;await absent(a);
  resetCoordinator();assert.equal((await push(a)).status,401);assert.equal((await req('/api/v2/runtime/disconnect',a.key,'POST',{robloxUserId:a.robloxId})).status,401);assert.equal((await req('/api/v2/runtime/accounts/'+a.robloxId,a.token,'DELETE')).status,401);await absent(a);
  pass(`${operation} before deletion drains before 200; no late data after coordinator recreation, other user preserved`);
 }

 // Deletion first: outer-authenticated requests waiting behind it must recheck
 // the durable user/deletion state before touching R2 or D1.
 const a=await account();assert.equal((await push(a)).status,200);const pause=barrier();let once=true;
 env.DELETION_LEDGER={get:(...args)=>ledger.get(...args),list:(...args)=>ledger.list(...args),delete:(...args)=>ledger.delete(...args),put:async(k,...args)=>{if(once&&k==='events/'+a.id+'.json'){once=false;pause.enter();await pause.gate;}return ledger.put(k,...args);}};
 const deleting=del(a);await within(pause.entered,'delete before revocation');const before=queued.get(a.id)||0;
 const later=[push(a),req('/api/v2/runtime/disconnect',a.key,'POST',{robloxUserId:a.robloxId}),req('/api/v2/runtime/link',a.key,'POST',{robloxUserId:a.robloxId}),req('/api/v2/runtime/accounts/'+a.robloxId,a.token,'DELETE'),req('/api/v1/runtime/push',a.key,'POST',{schemaVersion:1})];
 await until(()=>(queued.get(a.id)||0)>=before+later.length,'mutations queued behind delete');pause.release();assert.equal((await within(deleting,'delete first')).status,200);
 for(const response of await within(Promise.all(later),'queued reauth'))assert.equal(response.status,401);env.DELETION_LEDGER=ledger;await absent(a);
 pass('push disconnect link unlink and enabled legacy push queued after deletion all reauthenticate and reject');

 // Failed cleanup stays revoked. A maintenance continuation uses the same
 // per-user queue and reads the latest durable job rather than a stale copy.
 const pending=await account();assert.equal((await push(pending)).status,200);
 const r2Pause=barrier();once=true;
 env.PAYLOADS={...normal,list:async options=>{if(once&&options.prefix===`runtime-v2/${pending.id}/`){once=false;r2Pause.enter();await r2Pause.gate;throw new Error('Synthetic R2 list outage');}return normal.list(options);}};
 const waitingDeletion=del(pending);await within(r2Pause.entered,'pending deletion list');
 const job=await runtime.db.prepare('SELECT * FROM account_deletions WHERE user_id=?1').bind(pending.id).first();assert(job);
 const resumed=finishAccountDeletion(env,job);r2Pause.release();const firstResult=await within(waitingDeletion,'202 with concurrent continuation');assert.equal(firstResult.status,202);assert.equal(await within(resumed,'background finish'),true);env.PAYLOADS=normal;await absent(pending);
 assert.equal(await finishAccountDeletion(env,job),true);pass('R2 failure retains revocation; queued background cleanup succeeds and stale continuation is idempotent');
 await assert.rejects(finishAccountDeletion({...env,RUNTIME_MUTATIONS:null},job),/coordination binding/);
 const external=await req('/account-deletion/finish',other.token,'POST',{});assert.equal(external.status,404);pass('deletion continuation has no public endpoint and absent coordinator fails closed');

 // Simulate maintenance already awaiting this user's queue. Wake-up must be
 // outside that queue or the outer response and maintenance would deadlock.
 const circular=await account();assert.equal((await push(circular)).status,200);let continuing;
 const wakeOriginal=env.RETENTION_RUNNER;
 env.RETENTION_RUNNER={idFromName:id=>id,get:()=>({fetch:async()=>{assert.equal(await continuing,true);return Response.json({ok:true,started:true});}})};
 env.PAYLOADS={...normal,list:async options=>{if(options.prefix===`runtime-v2/${circular.id}/`){const persisted=await runtime.db.prepare('SELECT * FROM account_deletions WHERE user_id=?1').bind(circular.id).first();continuing=finishAccountDeletion(env,persisted);env.PAYLOADS=normal;throw new Error('Synthetic partial cleanup');}return normal.list(options);}};
 assert.equal((await within(del(circular),'maintenance wake outside mutation queue')).status,202);await absent(circular);env.RETENTION_RUNNER=wakeOriginal;
 pass('pending deletion releases mutation queue before awaiting maintenance wake-up');

 // Live HTTP writes use the same SQL guards as linked WebSocket updates.
 // Pause each actual D1 INSERT after authentication/claim, finish deletion,
 // then execute the delayed statement and verify it cannot restore rows.
 for(const table of ['runtime_presence','analytics_sessions']) {
  const linked=await account();assert.equal((await push(linked)).status,200);
  const wait=barrier();let armed=true;
  const wrap=(stmt,sql)=>new Proxy(stmt,{get(target,name){
   if(name==='bind')return (...args)=>wrap(target.bind(...args),sql);
   if(name==='run')return async()=>{if(armed&&sql.includes('INSERT INTO '+table)){armed=false;wait.enter();await wait.gate;}return target.run();};
   const value=Reflect.get(target,name);return typeof value==='function'?value.bind(target):value;
  }});
  const liveEnv={...env,DB:{prepare:sql=>wrap(runtime.db.prepare(sql),sql),batch:stmts=>runtime.db.batch(stmts)},
   PRESENCE_TOKEN_SECRET:'local-presence-secret',PRESENCE_RATE_LIMITER:{limit:async()=>({success:true})},
   STATS:{idFromName:id=>id,get:()=>({fetch:async()=>Response.json({ok:true})})}};
  const response=live.fetch(new Request('http://local/runtime-presence',{method:'POST',headers:{authorization:'Bearer '+linked.key,'content-type':'application/json'},body:JSON.stringify({sessionId:linked.sid,robloxUserId:linked.robloxId,version:'local-p1'})}),liveEnv);
  await within(wait.entered,'live '+table+' before write');assert.equal((await del(linked)).status,200);wait.release();
  const completed=await within(response,'live write after deletion');assert([200,409].includes(completed.status));
  for(const name of ['runtime_presence','analytics_sessions','runtime_session_owners'])assert.equal(await runtime.db.prepare('SELECT session_id FROM '+name+' WHERE session_id=?1').bind(linked.sid).first(),null);
  await absent(linked);pass('linked live '+table+' write paused after claim cannot recreate rows after deletion');
 }

 const native=await account();assert.equal((await push(native)).status,200);
 const nativeDeletion=await runtime.api.fetch('http://local/api/v2/account/delete',{method:'POST',headers:{authorization:'Bearer '+native.token,'content-type':'application/json'},body:JSON.stringify({confirmation:'DELETE'})});assert.equal(nativeDeletion.status,200);await absent(native);
 const ns=await runtime.mf.getDurableObjectNamespace('RUNTIME_MUTATIONS','api');const response=await ns.get(ns.idFromName(native.id)).fetch('https://internal/account-deletion/finish',{method:'POST',headers:{'x-deletion-user-id':native.id,'x-deletion-max-objects':'25'}});assert.equal(response.status,200);assert.equal((await response.json()).deleted,true);
 assert.equal((await req('/api/v2/auth/me',other.token,'GET')).status,200);assert(await bucket.head(key(other)));pass('native Miniflare binding deletes account and handles repeated continuation without changing another user');
 await writeFile(new URL('./p1-regression-results.json',import.meta.url),JSON.stringify({scope:'local synthetic Miniflare D1/R2/native coordinator and injected class barriers; no cloud, browser, real accounts or ledger reset',results},null,2)+'\n');
} finally {await runtime.mf.dispose();}
