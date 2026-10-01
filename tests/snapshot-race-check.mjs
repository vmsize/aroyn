import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {AroynSnapshotStore,withSnapshotStorage} from '../workers/shared/snapshot-storage.js';
import {createRuntime} from './runtime.mjs';
const results=[];
const check=(name,value)=>{assert(value,name);results.push({name,pass:true});console.log('PASS '+name);};
const key='runtime-v3/synthetic/accounts/900002.json';
let object={etag:'old',uploaded:new Date(0),value:'old'};
let deleting,releaseDelete;
const deleteStarted=new Promise(r=>deleting=r);
const deleteBarrier=new Promise(r=>releaseDelete=r);
const bucket={
  head:async()=>object&&{...object},
  async delete(){deleting();await deleteBarrier;object=null;},
  async put(k,stream){const value=await new Response(stream).text();object={etag:'fresh',uploaded:new Date(),value};},
};
const store=new AroynSnapshotStore({}, {PAYLOADS:bucket});
const namespace={idFromName:k=>k,get:()=>({fetch:(url,options)=>store.fetch(new Request(url,options))})};
const env=withSnapshotStorage({PAYLOADS:bucket,SNAPSHOT_STORAGE:namespace});
const expiry=env.PAYLOADS.expire(key,'old',Date.now()-1000);
await deleteStarted;
const update=env.PAYLOADS.put(key,'fresh');
await new Promise(r=>setTimeout(r,30));
check('new write waits while expiry is between head and delete',object.value==='old');
releaseDelete();await Promise.all([expiry,update]);
check('update during deletion remains stored after both operations',object.value==='fresh');
check('old enumerated etag cannot delete a replacement',!(await env.PAYLOADS.expire(key,'old',Date.now()+1000))&&object.value==='fresh');
check('fresh upload is not expired at the cutoff',!(await env.PAYLOADS.expire(key,'fresh',Date.now()-1000)));
check('revocation markers are not removed by expiry',!(await env.PAYLOADS.expire('runtime-v3/synthetic/revoked/900002.json','fresh',Date.now()+1000)));
await assert.rejects(withSnapshotStorage({PAYLOADS:bucket}).PAYLOADS.put(key,'blocked'));
check('missing coordinator fails closed for runtime mutations',true);
let failed=true;
const failing=new AroynSnapshotStore({}, {PAYLOADS:{head:bucket.head,put:bucket.put,delete:async()=>{if(failed){failed=false;throw new Error('Fixture failure');}}}});
await assert.rejects(failing.fetch(new Request('https://internal/delete',{method:'POST',headers:{'x-object-key':key}})));
check('failed operation does not poison the mutation queue',(await failing.fetch(new Request('https://internal/put',{method:'POST',headers:{'x-object-key':key},body:'recovery'}))).ok);
const runtime=await createRuntime({mock:true});
try{
  const realBucket=await runtime.mf.getR2Bucket('PAYLOADS','api');
  const realNamespace=await runtime.mf.getDurableObjectNamespace('SNAPSHOT_STORAGE','api');
  const coordinated=withSnapshotStorage({PAYLOADS:realBucket,SNAPSHOT_STORAGE:realNamespace}).PAYLOADS;
  for(let i=0;i<12;i++){
    await coordinated.put(key,'old-'+i);
    const before=await realBucket.head(key);
    const expire=()=>coordinated.expire(key,before.etag,Date.now()+1000);
    const put=()=>coordinated.put(key,'fresh-'+i);
    await Promise.all(i%2?[put(),expire()]:[expire(),put()]);
    assert.equal(await (await realBucket.get(key)).text(),'fresh-'+i);
  }
  check('real Miniflare DO/R2 preserves concurrent replacement in both request orders, 12 runs',true);
}finally{await runtime.mf.dispose();}
await fs.writeFile(new URL('./snapshot-race-results.json',import.meta.url),JSON.stringify({results},null,2)+'\n');
