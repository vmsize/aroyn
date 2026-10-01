import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';
import {AroynRetentionRunner,newRetentionCycle,retentionStep,RETENTION_BATCH} from '../workers/shared/retention-runner.js';
import {runDataRetention} from '../workers/shared/data-lifecycle.js';
const runtime=await createRuntime({mock:true}),checks=[];
const pass=name=>{checks.push({name,pass:true});console.log('PASS '+name)};
const pause=ms=>new Promise(r=>setTimeout(r,ms));
async function until(test,label){for(let i=0;i<150;i++){if(await test())return;await pause(200)}throw new Error(label)}
// Re-created class instances share only persisted state. D1/R2/coordinator
// operations below use the actual isolated Miniflare bindings.
function memoryStorage(){let data=new Map(),alarm=null;return {
 async get(key){return structuredClone(data.get(key))},async put(key,value){data.set(key,structuredClone(value))},
 async getAlarm(){return alarm},async setAlarm(value){alarm=value},async deleteAlarm(){alarm=null},
 async transaction(fn){const old=structuredClone(data),oldAlarm=alarm;try{return await fn(this)}catch(error){data=old;alarm=oldAlarm;throw error}}
}}
try {
 const bucket=await runtime.mf.getR2Bucket('PAYLOADS','api'),coordinator=await runtime.mf.getDurableObjectNamespace('SNAPSHOT_STORAGE','api'),cache=await runtime.mf.getDurableObjectNamespace('STATS_CACHE','api');
 const namespace=await runtime.mf.getDurableObjectNamespace('RETENTION_RUNNER','api');
 const env={DB:runtime.db,PAYLOADS:bucket,SNAPSHOT_STORAGE:coordinator,STATS_CACHE:cache,RETENTION_RUNNER:namespace};
 await assert.rejects(()=>runDataRetention({...env,RETENTION_RUNNER:null}),/binding unavailable/);pass('missing continuation binding fails closed');
 const now=Date.now()+8*86400000;
 const statements=[];for(let i=0;i<620;i++)statements.push(runtime.db.prepare('INSERT INTO analytics_sessions(session_id,roblox_user_id,started_at,last_seen_at) VALUES(?1,?2,?3,?3)').bind('old-bounded-'+i,'900001',now-31*86400000));
 statements.push(runtime.db.prepare('INSERT INTO analytics_sessions(session_id,roblox_user_id,started_at,last_seen_at) VALUES(?1,?2,?3,?3)').bind('fresh-bounded','900001',now));
 for(let i=0;i<statements.length;i+=50)await runtime.db.batch(statements.slice(i,i+50));
 for(let i=0;i<63;i++)await bucket.put('runtime-v3/bounded/roblox/'+String(i).padStart(3,'0')+'.json','{"fixture":true}');
 await bucket.put('runtime-v3/bounded/revoked/one.json','{"revoked":true}');
 const storage=memoryStorage(),ctx={storage};let runner=new AroynRetentionRunner(ctx,env);
 const starts=await Promise.all([1,2,3].map(()=>runner.fetch(new Request('https://internal/start',{method:'POST',headers:{'x-retention-now':String(now)}})).then(r=>r.json())));
 assert.equal(starts.filter(x=>x.started).length,1);assert(await storage.getAlarm());pass('overlapping starts share one persisted cycle and alarm');
 await runner.alarm();await runner.alarm();
 assert.equal((await runtime.db.prepare("SELECT COUNT(*) AS n FROM analytics_sessions WHERE session_id LIKE 'old-bounded-%'").first()).n,370);
 assert.equal((await storage.get('progress')).phase,'history');pass('one history step removes at most 250 rows');
 const followupStore=memoryStorage(),followupRunner=new AroynRetentionRunner({storage:followupStore},env);
 await followupStore.put('progress',{...newRetentionCycle(now),phase:'invalidate'});
 await followupRunner.fetch(new Request('https://internal/start',{method:'POST',headers:{'x-retention-deletion':'true'}}));
 await followupRunner.alarm();assert.equal((await followupStore.get('progress')).followupRequested,true);assert(await followupStore.getAlarm()>Date.now()+250000);pass('deletion arriving during a sweep schedules a follow-up cycle');
 runner=new AroynRetentionRunner(ctx,env);await runner.alarm();
 assert.equal((await runtime.db.prepare("SELECT COUNT(*) AS n FROM analytics_sessions WHERE session_id LIKE 'old-bounded-%'").first()).n,120);pass('re-created maintenance instance resumes stored progress');
 while((await storage.get('progress')).phase!=='snapshots')await runner.alarm();
 while((await storage.get('progress')).prefix!==2)await runner.alarm();
 await runner.alarm();const firstPage=await storage.get('progress');assert.equal(firstPage.objectsVisited,25);assert(firstPage.snapshotsRemoved>0&&firstPage.snapshotsRemoved<=25);assert.equal((await bucket.list({prefix:'runtime-v3/bounded/roblox/'})).objects.length,63-firstPage.snapshotsRemoved);pass('one snapshot step expires at most 25 objects');
 const checkpoint=await storage.get('progress'),oldList=bucket.list.bind(bucket);
 const brokenEnv={...env,PAYLOADS:{list:async()=>{throw new Error('synthetic outage')}}};
 const broken=new AroynRetentionRunner(ctx,brokenEnv);await broken.alarm();
 const failed=await storage.get('progress');assert.equal(failed.cursor,checkpoint.cursor);assert.equal(failed.snapshotsRemoved,checkpoint.snapshotsRemoved);assert.equal(failed.failures,1);assert(await storage.getAlarm()>Date.now()+50000);pass('R2 failure keeps checkpoint and schedules durable backoff');
 runner=new AroynRetentionRunner(ctx,env);while((await storage.get('progress')).active)await runner.alarm();
 assert.equal((await storage.get('progress')).snapshotsRemoved,63);assert.equal(await storage.getAlarm(),null);assert(await bucket.head('runtime-v3/bounded/revoked/one.json'));assert(await runtime.db.prepare("SELECT session_id FROM analytics_sessions WHERE session_id='fresh-bounded'").first());pass('resumed sweep preserves fresh history and revocation markers');
 // A crash after one expiry but before its checkpoint must safely repeat.
 const snapshotState={...newRetentionCycle(now),phase:'snapshots',prefix:2};
 for(let i=0;i<2;i++)await bucket.put('runtime-v3/replay/roblox/'+i+'.json','{"fixture":true}');
 let calls=0;const crashStorage={idFromName:key=>coordinator.idFromName(key),get(id){const stub=coordinator.get(id);return {async fetch(...args){const response=await stub.fetch(...args);if(++calls===1)throw new Error('crash after deletion');return response}}}};
 await assert.rejects(()=>retentionStep({...env,SNAPSHOT_STORAGE:crashStorage},snapshotState),/crash after deletion/);
 await retentionStep(env,snapshotState);assert.equal((await oldList({prefix:'runtime-v3/replay/'})).objects.length,0);pass('replaying partially applied page does not skip remaining expiry');
 const freshState={...newRetentionCycle(Date.now()),phase:'snapshots',prefix:2};await bucket.put('runtime-v3/fresh/one.json','{"fresh":true}');
 await retentionStep(env,freshState);assert(await bucket.head('runtime-v3/fresh/one.json'));pass('fresh snapshots are preserved at the cycle cutoff');
 // A failed deletion must not prevent history expiry or an unrelated job.
 for(const id of ['usr_bounded_bad','usr_bounded_good']){await runtime.db.prepare('INSERT INTO users(id,discord_id,discord_username,created_at,updated_at,last_login_at) VALUES(?1,?1,?1,?2,?2,?2)').bind(id,Date.now()).run();await runtime.db.prepare('INSERT INTO account_deletions(user_id,requested_at) VALUES(?1,?2)').bind(id,Date.now()).run()}
 await bucket.put('runtime-v3/usr_bounded_bad/one.json','{}');let state=newRetentionCycle(now);
 const bad={...env,PAYLOADS:{list:options=>options.prefix.includes('usr_bounded_bad')?Promise.reject(new Error('synthetic account outage')):bucket.list(options),delete:key=>bucket.delete(key)}};
 state=await retentionStep(bad,state);assert.equal(state.pendingDeletions,1);state=await retentionStep(env,state);assert.equal(await runtime.db.prepare("SELECT id FROM users WHERE id='usr_bounded_good'").first(),null);assert(await runtime.db.prepare("SELECT user_id FROM account_deletions WHERE user_id='usr_bounded_bad'").first());pass('failed deletion stays revoked without starving unrelated jobs');
 // Native Miniflare alarms, not the in-memory alarm clock above.
 const actual=await runDataRetention(env);assert.equal(actual.started,true);const stub=namespace.get(namespace.idFromName('daily'));
 const status=async()=> (await stub.fetch('https://internal/status')).json();
 await until(async()=> (await status()).steps>=1,'first native maintenance alarm');
 const before=(await status()).steps;await runtime.mf.unsafeEvictDurableObject('api','AroynRetentionRunner',{name:'daily'});
 await until(async()=> (await status()).steps>before,'native alarm resumes after eviction');pass('real Miniflare alarm and checkpoint survive forced object eviction');
 assert.equal((await runtime.api.fetch('http://local/api/v2/retention/status')).status,404);pass('maintenance status has no public API route');
 await writeFile(new URL('./retention-results.json',import.meta.url),JSON.stringify({date:'2026-10-01',passed:true,batch:RETENTION_BATCH,checks,scope:'synthetic local D1/R2/DO; fake checkpoint store for failure tests plus native Miniflare alarm/eviction check; no cloud CPU measurement'},null,2)+'\n');
} finally {await runtime.mf.dispose()}
