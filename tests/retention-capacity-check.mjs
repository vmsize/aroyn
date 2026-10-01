import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {performance} from 'node:perf_hooks';
import {createRuntime} from './runtime.mjs';
import {runDataRetention} from '../workers/shared/data-lifecycle.js';
const runtime=await createRuntime({mock:true});
const DAY=86400000,now=Date.now()+8*DAY;
const results=[];
try{
 const bucket=await runtime.mf.getR2Bucket('PAYLOADS','api');
 const storage=await runtime.mf.getDurableObjectNamespace('SNAPSHOT_STORAGE','api');
 const cache=await runtime.mf.getDurableObjectNamespace('STATS_CACHE','api');
 for(const size of [100,1000]){
  for(let offset=0;offset<size;offset+=20)await Promise.all(Array.from({length:Math.min(20,size-offset)},(_,j)=>{const i=offset+j;return bucket.put(`runtime-v3/fixture-capacity/roblox/${i}.json`,'{"fixture":true,"cash":1}')}));
  for(let i=0;i<3;i++)await bucket.put(`runtime-v3/fixture-capacity/revoked/${i}.json`,'{"revoked":true}');
  const statements=[];
  for(let i=0;i<size;i++)statements.push(runtime.db.prepare('INSERT INTO analytics_sessions(session_id,roblox_user_id,version,started_at,last_seen_at,dashboard_linked) VALUES(?1,?2,?3,?4,?4,0)').bind('capacity-'+size+'-'+i,String(900000+i),'synthetic',now-31*DAY));
  for(let i=0;i<10;i++)statements.push(runtime.db.prepare('INSERT INTO analytics_sessions(session_id,roblox_user_id,version,started_at,last_seen_at,dashboard_linked) VALUES(?1,?2,?3,?4,?4,0)').bind('current-'+size+'-'+i,String(910000+i),'synthetic',now));
  for(let i=0;i<statements.length;i+=50)await runtime.db.batch(statements.slice(i,i+50));
  const counts={list:0,expiryCoordinator:0,cacheInvalidation:0};
  const countedBucket={list(options){counts.list++;return bucket.list(options)},head:key=>bucket.head(key),get:key=>bucket.get(key),put:(...args)=>bucket.put(...args),delete:key=>bucket.delete(key)};
  const countedStorage={idFromName:key=>storage.idFromName(key),get(id){const stub=storage.get(id);return {fetch(...args){counts.expiryCoordinator++;return stub.fetch(...args)}}}};
  const countedCache={idFromName:key=>cache.idFromName(key),get(id){const stub=cache.get(id);return {fetch(...args){counts.cacheInvalidation++;return stub.fetch(...args)}}}};
  const env={DB:runtime.db,PAYLOADS:countedBucket,SNAPSHOT_STORAGE:countedStorage,STATS_CACHE:countedCache};
  const begin=performance.now();const removed=await runDataRetention(env,now);const elapsedMs=Math.round(performance.now()-begin);
  assert.equal(removed.snapshotsRemoved,size);assert.equal(removed.pendingDeletions,0);
  const remaining=await bucket.list();assert.equal(remaining.objects.length,3);assert(remaining.objects.every(o=>o.key.includes('/revoked/')));
  const histories=await runtime.db.prepare('SELECT COUNT(*) AS n FROM analytics_sessions').first();assert.equal(histories.n,size===100?10:20);
  const again=await runDataRetention(env,now);assert.equal(again.snapshotsRemoved,0);
  results.push({expiredSnapshots:size,expiredHistoryRows:size,freshHistoryRowsPreserved:histories.n,revocationMarkersPreserved:3,elapsedMs,operationCountsIncludingIdempotenceRun:counts});
  console.log(JSON.stringify(results.at(-1)));
 }
 await writeFile(new URL('./retention-capacity-results.json',import.meta.url),JSON.stringify({date:'2026-10-01',passed:true,scope:'local real Miniflare D1/R2/DO bindings; fixture clock advances eight days, small synthetic snapshots; no external services',cloudCpuOrQuotaMeasured:false,results},null,2)+'\n');
}finally{await runtime.mf.dispose();}
