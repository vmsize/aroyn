import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {createRuntime,folder} from './runtime.mjs';
const NativeWebSocket=createRequire(resolve(process.env.AROYN_TEST_DEPENDENCIES || resolve(folder,'../package.json')))('ws');
const runtime=await createRuntime({mock:true,ownerDiscordId:'900001'});
const results=[],sockets=[];
const api=(path,options={})=>runtime.api.fetch('http://127.0.0.1:8787'+path,{redirect:'manual',...options});
const live=(path,options={})=>runtime.live.fetch('http://127.0.0.1:8788'+path,{redirect:'manual',...options});
const post=(token,body)=>({method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
function result(name,passed){results.push({name,pass:Boolean(passed)});console.log((passed?'PASS ':'FAIL ')+name);}
async function exchangeCode(code='mock') {
  const start=await api('/api/v2/auth/discord/start');
  const state=new URL(start.headers.get('location')).searchParams.get('state');
  const cookie=start.headers.getSetCookie().map(c=>c.split(';')[0]).join('; ');
  const cb=await api('/api/v2/auth/discord/callback?code='+code+'&state='+state,{headers:{cookie}});
  assert.equal(cb.status,302);
  return new URL(cb.headers.get('location')).searchParams.get('veyra_auth');
}
async function login(){const code=await exchangeCode();const r=await api('/api/v2/auth/exchange',post('',{code}));assert.equal(r.status,200);return r.json();}
async function connect(token){const r=await live('/ws?token='+encodeURIComponent(token),{headers:{Upgrade:'websocket'}});if(r.status===101){r.webSocket.accept();sockets.push(r.webSocket);}return r;}
async function connectNative(token) {
  const url=new URL('/ws',await runtime.mf.ready);
  url.protocol='ws:';url.searchParams.set('token',token);
  const socket=new NativeWebSocket(url);
  sockets.push(socket);
  await new Promise((done,reject)=>{socket.addEventListener('open',done,{once:true});socket.addEventListener('error',()=>reject(new Error('Native WebSocket failed')),{once:true});});
  return socket;
}
async function closedAfterAction(ws,action,timeout=1500) {
  const event=new Promise(resolveEvent=>{const timer=setTimeout(()=>resolveEvent(false),timeout);ws.addEventListener('close',()=>{clearTimeout(timer);resolveEvent(true)},{once:true});});
  await action();return event;
}
async function closingAfterAction(ws,action,timeout=1500) {
  // Observe the protocol closing state separately from TCP teardown in Miniflare.
  await action();
  const started=Date.now();
  while(Date.now()-started<timeout) {
    if(ws.readyState===2||ws.readyState===3)return true;
    await new Promise(done=>setTimeout(done,50));
  }
  return false;
}
try {
  const code=await exchangeCode();
  const simultaneous=await Promise.all([api('/api/v2/auth/exchange',post('',{code})),api('/api/v2/auth/exchange',post('',{code}))]);
  const statuses=simultaneous.map(r=>r.status).sort();
  result('parallel exchange gives exactly one session',[200,401].every((v,i)=>statuses[i]===v));
  const account=await login();
  const initialKeys=await Promise.all([api('/api/v2/dashboard-key/generate',post(account.token,{})),api('/api/v2/dashboard-key/generate',post(account.token,{}))]);
  result('parallel first key generation cannot silently replace key',initialKeys.map(r=>r.status).sort().join(',')==='200,409');
  const generated=initialKeys.find(r=>r.status===200);
  assert.equal(generated.status,200);
  const key=(await generated.json()).dashboardKey;
  const snapshot={schemaVersion:1,type:'snapshot',player:{userId:900002,name:'robloxuser'},session:{id:'security-fixture-session'},cash:100};
  assert.equal((await api('/api/v2/runtime/push',post(key,snapshot))).status,200);
  const oversized={...snapshot,description:'€'.repeat(90000)};
  result('UTF-8 byte limit on HTTP telemetry',(await api('/api/v2/runtime/push',post(key,oversized))).status===413);
  result('legacy v1 arbitrary-key writes disabled by default',(await api('/api/v1/runtime/push',post('VY-000000-000000-000000-000000',snapshot))).status===410);
  let nullStatus=0;
  try {nullStatus=(await api('/api/v2/auth/exchange',post('',null))).status;} catch {}
  result('null auth payload rejected cleanly',nullStatus===400);
  const wt=await (await live('/web-token',post(account.token,{robloxUserId:'900002'}))).json();
  assert(wt.token);
  await api('/api/v2/auth/logout',{method:'POST',headers:{authorization:'Bearer '+account.token}});
  result('issued web live token rejected after logout',(await connect(wt.token)).status===401);
  const fresh=await login();
  const rt=await (await live('/token',post(key,{robloxUserId:'900002'}))).json();
  const runtimeSocket=(await connect(rt.token)).webSocket;
  assert(runtimeSocket);
  const keyRotation=await api('/api/v2/dashboard-key/generate',post(fresh.token,{confirm:true}));
  assert.equal(keyRotation.status,200);
  result('issued runtime live token rejected after key rotation',(await connect(rt.token)).status===401);
  result('open runtime socket closed on next message after rotation',await closedAfterAction(runtimeSocket,()=>runtimeSocket.send(JSON.stringify(snapshot))));
  const newKey=(await keyRotation.json()).dashboardKey;
  const rt2=await (await live('/token',post(newKey,{robloxUserId:'900002'}))).json();
  const ws2=(await connect(rt2.token)).webSocket;
  result('WebSocket identity mismatch rejected',await closedAfterAction(ws2,()=>ws2.send(JSON.stringify({...snapshot,player:{userId:900099}}))));
  const rt3=await (await live('/token',post(newKey,{robloxUserId:'900002'}))).json();
  const ws3=(await connect(rt3.token)).webSocket;
  result('oversized WebSocket message rejected',await closedAfterAction(ws3,()=>ws3.send(JSON.stringify(oversized))));
  result('oversized auth JSON rejected',(await api('/api/v2/auth/exchange',post('',{code:'VX_'+ 'a'.repeat(9000)}))).status===413);
  result('null live token JSON rejected',(await live('/web-token',post(fresh.token,null))).status===400);
  const floodToken=await (await live('/web-token',post(fresh.token,{robloxUserId:'900002'}))).json();
  const floodSocket=(await connect(floodToken.token)).webSocket;
  result('WebSocket message burst rejected',await closedAfterAction(floodSocket,()=>{for(let i=0;i<121;i++)floodSocket.send(JSON.stringify({type:'ping'}));},5000));
  const rt4=await (await live('/token',post(newKey,{robloxUserId:'900002'}))).json();
  const ws4=(await connect(rt4.token)).webSocket;
  const viewer=await login();
  const viewerToken=await (await live('/web-token',post(viewer.token,{robloxUserId:'900002'}))).json();
  const viewerSocket=await connectNative(viewerToken.token);
  let revokedSnapshots=0;
  viewerSocket.addEventListener('message',event=>{if(JSON.parse(event.data).type==='snapshot')revokedSnapshots++;});
  await api('/api/v2/auth/logout',post(viewer.token,{}));
  result('logged-out dashboard starts closing before next relay',await closingAfterAction(viewerSocket,()=>ws4.send(JSON.stringify(snapshot))));
  result('logged-out dashboard receives no further telemetry',revokedSnapshots===0);
  const idleViewer=await login();
  const idleToken=await (await live('/web-token',post(idleViewer.token,{robloxUserId:'900002'}))).json();
  const idleSocket=await connectNative(idleToken.token);
  result('idle logged-out socket starts closing via alarm',await closingAfterAction(idleSocket,()=>api('/api/v2/auth/logout',post(idleViewer.token,{})),20000));
  // A socket must not change or remove another identity's existing presence session.
  await runtime.db.prepare('INSERT INTO runtime_presence (session_id,roblox_user_id,dashboard_linked,version,started_at,last_seen_at) VALUES (?1,?2,0,?3,?4,?4)')
    .bind('foreign-presence-session','900099','test',Date.now()).run();
  result('foreign presence session collision rejected',await closedAfterAction(ws4,()=>ws4.send(JSON.stringify({...snapshot,session:{id:'foreign-presence-session'}}))));
  result('foreign presence session preserved',Boolean(await runtime.db.prepare('SELECT session_id FROM runtime_presence WHERE session_id=?1 AND roblox_user_id=?2').bind('foreign-presence-session','900099').first()));
  const rt5=await (await live('/token',post(newKey,{robloxUserId:'900002'}))).json();
  const ws5=(await connect(rt5.token)).webSocket;
  await api('/api/v2/runtime/accounts/900002',{method:'DELETE',headers:{authorization:'Bearer '+fresh.token}});
  result('issued live token rejected after account unlink',(await connect(rt5.token)).status===401);
  result('open runtime closed after account unlink',await closedAfterAction(ws5,()=>ws5.send(JSON.stringify(snapshot))));
  result('unlinked account HTTP push rejected',(await api('/api/v2/runtime/push',post(newKey,snapshot))).status===403);
  // An exact 121-call sequential loop can straddle a minute reset and admit
  // every call. A short 241-request burst exceeds two adjacent 120-call
  // windows; require a rejection, not a particular completion order.
  const rateResponses=await Promise.all(Array.from({length:241},()=>api('/api/v2/auth/me',{headers:{'CF-Connecting-IP':'198.51.100.10'}})));
  result('HTTP rate limit returns 429',rateResponses.some(r=>r.status===429)&&rateResponses.every(r=>[401,429].includes(r.status)));
  result('rate limit is separated by source IP',(await api('/api/v2/auth/me',{headers:{'CF-Connecting-IP':'198.51.100.11'}})).status===401);
  const owner=await live('/owner/analytics',{headers:{authorization:'Bearer '+fresh.token}});
  result('configured owner analytics succeeds',owner.status===200);
  const otherCode=await exchangeCode('mock-b');
  const other=await (await api('/api/v2/auth/exchange',post('',{code:otherCode}))).json();
  result('non-owner analytics forbidden',(await live('/owner/analytics',{headers:{authorization:'Bearer '+other.token}})).status===403);
  for(const route of ['/admin/ws','/admin/stats'])result(route+' requires private secret',(await live(route)).status===401);
  // Deliberate failure in this fresh synthetic database, never a user store.
  await runtime.db.prepare('DROP TABLE analytics_sessions').run();
  const failedOwner=await live('/owner/analytics?range=7d',{headers:{authorization:'Bearer '+fresh.token}});
  const error=await failedOwner.json();
  result('owner failure omits internal error detail',failedOwner.status===500&&!Object.hasOwn(error,'detail'));
  const response=await api('/session',{method:'POST'});
  result('loader session only supports GET',response.status===405);
  const stage=process.argv[2]==='baseline'?'baseline':'fixed';
  await writeFile(resolve(folder,'security-'+stage+'-results.json'),JSON.stringify({externalServices:'mocked; fresh synthetic database',limitation:'Native receiver closes enter CLOSING promptly; TCP teardown/CLOSED still requires independent HTTPS verification.',results},null,2));
  if(stage!=='baseline')assert(results.every(r=>r.pass),'Security checks failed; see sanitized result file');
} finally {for(const ws of sockets)try{ws.close(1000,'Test finished')}catch{}await runtime.mf.dispose();}
