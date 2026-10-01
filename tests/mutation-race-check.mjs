import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';
import {seedRecovery} from './recovery-fixture.mjs';
import api, {AroynRuntimeMutations} from '../workers/api/src/worker.js';
import {withSnapshotStorage} from '../workers/shared/snapshot-storage.js';
const runtime=await createRuntime({mock:true}),results=[];
const pass=name=>{results.push({name,pass:true});console.log('PASS '+name);};
const barrier=()=>{let enter,release;return {entered:new Promise(r=>enter=r),gate:new Promise(r=>release=r),enter:()=>enter(),release:()=>release()};};
try {
  const bucket=await runtime.mf.getR2Bucket('PAYLOADS','api');
  const {accounts:[a,b]}=await seedRecovery({DB:runtime.db,PAYLOADS:bucket});
  await runtime.db.prepare('UPDATE roblox_accounts SET avatar_updated_at=?1').bind(Date.now()).run();
  const env={DB:runtime.db,PAYLOADS:bucket,SNAPSHOT_STORAGE:await runtime.mf.getDurableObjectNamespace('SNAPSHOT_STORAGE','api'),STATS_CACHE:await runtime.mf.getDurableObjectNamespace('STATS_CACHE','api'),RETENTION_RUNNER:await runtime.mf.getDurableObjectNamespace('RETENTION_RUNNER','api'),API_RATE_LIMITER:{limit:async()=>({success:true})}};
  const normal=withSnapshotStorage(env).PAYLOADS;env.PAYLOADS=normal;
  const objects=new Map(),queued=new Map();
  env.RUNTIME_MUTATIONS={idFromName:id=>id,get:id=>{if(!objects.has(id))objects.set(id,new AroynRuntimeMutations({},env));return {fetch:request=>{queued.set(id,(queued.get(id)||0)+1);return objects.get(id).fetch(request);}};}};
  const request=(path,token,method='GET',body)=>api.fetch(new Request('http://local'+path,{method,headers:{authorization:'Bearer '+token,...body?{'content-type':'application/json'}:{}},...body?{body:JSON.stringify(body)}:{}}),env);
  const snapshot=(account,cash=111)=>({schemaVersion:1,player:{userId:Number(account.robloxId)},session:{id:account.sid},cash});
  const push=(account=a,cash=111)=>request('/api/v2/runtime/push',account.key,'POST',snapshot(account,cash));
  const unlink=()=>request('/api/v2/runtime/accounts/'+a.robloxId,a.token,'DELETE');
  const accountKey=()=>`runtime-v3/${a.id}/accounts/${a.robloxId}.json`;
  const mirror=()=>`runtime-v2/${a.id}/current.json`;
  const marker=()=>`runtime-v3/${a.id}/revoked/${a.robloxId}.json`;
  const row=()=>runtime.db.prepare('SELECT username FROM roblox_accounts WHERE veyra_user_id=?1 AND roblox_user_id=?2').bind(a.id,a.robloxId).first();
  const restore=async()=>{
    assert.equal((await request('/api/v2/runtime/link',a.key,'POST',{robloxUserId:a.robloxId})).status,200);
    // Avoid real avatar fetch in the directly invoked synthetic class.
    await runtime.db.prepare('INSERT OR IGNORE INTO roblox_accounts(veyra_user_id,roblox_user_id,username,avatar_updated_at,first_seen_at,last_seen_at) VALUES(?1,?2,?3,?4,?4,?4)').bind(a.id,a.robloxId,'fixture',Date.now()).run();
    assert.equal((await push()).status,200);
  };
  assert.equal((await api.fetch(new Request('http://local/api/v2/runtime/push',{method:'POST',headers:{authorization:'Bearer '+a.key,'content-type':'application/json'},body:JSON.stringify(snapshot(a))}),{...env,RUNTIME_MUTATIONS:null})).status,503);
  pass('missing account mutation binding fails closed');

  let pause=barrier(),once=true;
  env.PAYLOADS={...normal,head:async key=>{const value=await normal.head(key);if(once&&key===marker()){once=false;pause.enter();await pause.gate;}return value;}};
  const first=push();await pause.entered;
  const pendingUnlink=unlink();
  while((queued.get(a.id)||0)<2)await new Promise(r=>setTimeout(r,5));
  assert(await row());assert.equal(await bucket.head(marker()),null);
  assert.equal((await push(b,222)).status,200);
  pass('paused mutation for one account does not block another account');
  pause.release();assert.equal((await first).status,200);assert.equal((await pendingUnlink).status,200);
  assert.equal(await row(),null);assert.equal(await bucket.head(accountKey()),null);assert.equal(await bucket.head(mirror()),null);assert(await bucket.head(marker()));
  pass('unlink waits for already accepted push and removes its row and both snapshots');

  env.PAYLOADS=normal;await restore();pause=barrier();once=true;
  env.PAYLOADS={...normal,put:async(...args)=>{if(once&&args[0]===marker()){once=false;pause.enter();await pause.gate;}return normal.put(...args);}};
  const removing=unlink();await pause.entered;
  const later=push();pause.release();assert.equal((await removing).status,200);assert.equal((await later).status,403);
  assert.equal(await row(),null);assert.equal(await bucket.head(accountKey()),null);
  pass('push queued after unlink observes persisted revocation and cannot resurrect data');

  env.PAYLOADS=normal;await restore();pause=barrier();once=true;
  env.PAYLOADS={...normal,get:async key=>{const value=await normal.get(key);if(once&&key===accountKey()){once=false;pause.enter();await pause.gate;}return value;}};
  const disconnect=request('/api/v2/runtime/disconnect',a.key,'POST',{robloxUserId:a.robloxId});await pause.entered;
  const fresh=push(a,333);pause.release();assert.equal((await disconnect).status,200);assert.equal((await fresh).status,200);
  const current=await (await bucket.get(accountKey())).json();assert.equal(current.snapshot.cash,333);assert.equal(current.explicitOffline,false);
  pass('disconnect cannot overwrite the fresh push queued behind it');

  env.PAYLOADS=normal;
  const otherRoblox={...a,robloxId:'990009',sid:'mutation-second-roblox-session'};
  await runtime.db.prepare('INSERT INTO roblox_accounts(veyra_user_id,roblox_user_id,username,avatar_updated_at,first_seen_at,last_seen_at) VALUES(?1,?2,?3,?4,?4,?4)').bind(a.id,otherRoblox.robloxId,'fixture-other-roblox',Date.now()).run();
  assert.equal((await push(otherRoblox,999)).status,200);
  assert.equal((await unlink()).status,200);
  assert.equal((await (await bucket.get(mirror())).json()).snapshot.cash,999);
  assert(await bucket.head(`runtime-v3/${a.id}/accounts/${otherRoblox.robloxId}.json`));
  pass('unlink preserves compatibility mirror belonging to another Roblox account');
  await restore();

  env.PAYLOADS=normal;let fail=true;
  env.PAYLOADS={...normal,delete:async key=>{if(fail&&key===accountKey()){fail=false;throw new Error('Fixture delete outage');}return normal.delete(key);}};
  assert.equal((await unlink()).status,500);assert(await bucket.head(marker()));assert.equal(await row(),null);assert.equal((await push()).status,403);
  env.PAYLOADS=normal;assert.equal((await unlink()).status,200);assert.equal(await bucket.head(accountKey()),null);assert.equal(await bucket.head(mirror()),null);
  pass('failed unlink cleanup stays revoked and retry removes leftovers even without account row');

  await restore();pause=barrier();once=true;
  env.PAYLOADS={...normal,head:async key=>{const value=await normal.head(key);if(once&&key===marker()){once=false;pause.enter();await pause.gate;}return value;}};
  const oldActive=push();await pause.entered;const oldQueued=push(a,444);
  const rotated=await request('/api/v2/dashboard-key/generate',a.token,'POST',{confirm:true});assert.equal(rotated.status,200);a.key=(await rotated.json()).dashboardKey;
  pause.release();assert.equal((await oldActive).status,401);assert.equal((await oldQueued).status,401);assert.equal(await bucket.head(accountKey()),null);
  env.PAYLOADS=normal;assert.equal((await push(a,555)).status,200);
  pass('rotation rejects active old-key result and reauthenticates queued old-key request');

  pause=barrier();once=true;
  env.PAYLOADS={...normal,head:async key=>{const value=await normal.head(key);if(once&&key===marker()){once=false;pause.enter();await pause.gate;}return value;}};
  const late=push();await pause.entered;
  const removed=await request('/api/v2/account/delete',a.token,'POST',{confirmation:'DELETE'});assert.equal(removed.status,200);
  pause.release();assert([401,409].includes((await late).status));env.PAYLOADS=normal;
  assert.equal(await runtime.db.prepare('SELECT id FROM users WHERE id=?1').bind(a.id).first(),null);assert.equal((await bucket.list({prefix:`runtime-v3/${a.id}/`})).objects.length,0);
  assert.equal((await request('/api/v2/auth/me',b.token)).status,200);assert(await bucket.head(`runtime-v3/${b.id}/accounts/${b.robloxId}.json`));
  pass('account deletion during accepted push prevents late restoration and preserves other account');

  // Real native Miniflare binding, no injected class/barriers.
  const native=await runtime.mf.getDurableObjectNamespace('RUNTIME_MUTATIONS','api');
  assert.equal((await native.get(native.idFromName('fixture')).fetch('http://local/health')).status,404);
  for(let i=0;i<8;i++) {
    const link=await runtime.api.fetch('http://local/api/v2/runtime/link',{method:'POST',headers:{authorization:'Bearer '+b.key,'content-type':'application/json'},body:JSON.stringify({robloxUserId:b.robloxId})});assert.equal(link.status,200);
    const pushRequest=()=>runtime.api.fetch('http://local/api/v2/runtime/push',{method:'POST',headers:{authorization:'Bearer '+b.key,'content-type':'application/json'},body:JSON.stringify(snapshot(b,i))});
    const unlinkRequest=()=>runtime.api.fetch('http://local/api/v2/runtime/accounts/'+b.robloxId,{method:'DELETE',headers:{authorization:'Bearer '+b.token}});
    const responses=await Promise.all(i%2?[unlinkRequest(),pushRequest()]:[pushRequest(),unlinkRequest()]);
    assert(responses.every(r=>[200,403].includes(r.status)));assert.equal(await runtime.db.prepare('SELECT username FROM roblox_accounts WHERE veyra_user_id=?1 AND roblox_user_id=?2').bind(b.id,b.robloxId).first(),null);assert.equal(await bucket.head(`runtime-v3/${b.id}/accounts/${b.robloxId}.json`),null);
  }
  pass('native Miniflare mutation namespace preserves unlink outcome over eight concurrent request pairs');
  await fs.writeFile(new URL('./mutation-race-results.json',import.meta.url),JSON.stringify({source:'deterministic injected class barriers with real local D1/R2/coordinator, plus native Miniflare request pairs; external services mocked',results},null,2)+'\n');
}finally{await runtime.mf.dispose();}
