import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';

const r=await createRuntime({mock:true});
const checks=[],sockets=[],received=[];
const api=(p,o={})=>r.api.fetch('http://local'+p,{redirect:'manual',...o});
const live=(p,o={})=>r.live.fetch('http://local'+p,{redirect:'manual',...o});
const post=(body,key='',token='')=>({method:'POST',headers:{'content-type':'application/json',...(key?{authorization:'Bearer '+key}:{}),...(token?{'X-Presence-Token':token}:{})},body:JSON.stringify(body)});
const fixture=(sessionId,id)=>({sessionId,robloxUserId:id,version:'fixture',gameId:'10440833423',gameSlug:'greedy-growers',device:'desktop'});
function pass(name){checks.push(name);console.log('PASS '+name);}
async function stats(){const res=await live('/admin/stats',{headers:{authorization:'Bearer mock-stats-secret'}});assert.equal(res.status,200);return (await res.json()).online;}
async function wsCount(expected){const end=Date.now()+5000;while(Date.now()<end){if(received.some(x=>x.type==='stats_update'&&Object.entries(expected).every(([k,v])=>x.online?.[k]===v)))return;await new Promise(done=>setTimeout(done,20));}assert.fail('Stats WebSocket did not deliver expected counts');}
try{
 const response=await live('/admin/ws',{headers:{Upgrade:'websocket',authorization:'Bearer mock-stats-secret'}});assert.equal(response.status,101);
 const ws=response.webSocket;sockets.push(ws);ws.addEventListener('message',e=>received.push(JSON.parse(e.data)));ws.accept();
 const a=fixture('presence-local-session-a','900002'),duplicate=fixture('presence-local-session-a2','900002'),b=fixture('presence-local-session-b','900004');
 async function launch(f){const res=await live('/runtime-presence',post(f));assert.equal(res.status,200);const data=await res.json();assert.equal(data.dashboardLinked,false);assert(data.presenceToken);return data.presenceToken;}
 const ta=await launch(a),td=await launch(duplicate),tb=await launch(b);
 assert.deepEqual(await stats(),{scriptSessions:3,scriptUsers:2,dashboardSessions:0,dashboardUsers:0});
 pass('unlinked launches count as users and sessions; duplicate Roblox ID is deduplicated');
 await wsCount({scriptUsers:2,dashboardUsers:0,scriptSessions:3});pass('bot stats WebSocket delivers unlinked online counts');
 assert.equal((await live('/runtime-presence',post(a))).status,401);
 assert.equal((await live('/runtime-presence',post(a,'',tb))).status,401);
 assert.equal((await live('/runtime-presence',post({...a,robloxUserId:'900099'},'',ta))).status,409);
 pass('signed heartbeat identity and session collision protections remain enforced');
 assert.equal((await live('/runtime-presence',post(a,'',ta))).status,200);
 assert.equal((await stats()).scriptSessions,3);pass('heartbeat updates a session without adding another launch');
 const start=await api('/api/v2/auth/discord/start');const state=new URL(start.headers.get('location')).searchParams.get('state');
 const cookie=start.headers.getSetCookie().map(x=>x.split(';')[0]).join('; ');
 const callback=await api('/api/v2/auth/discord/callback?code=mock&state='+state,{headers:{cookie}});
 const code=new URL(callback.headers.get('location')).searchParams.get('veyra_auth');
 const account=await (await api('/api/v2/auth/exchange',post({code}))).json();
 const keyResponse=await api('/api/v2/dashboard-key/generate',post({},account.token));assert.equal(keyResponse.status,200);
 const {dashboardKey}=await keyResponse.json();
 assert.equal((await api('/api/v2/runtime/link',post({robloxUserId:'900002'},dashboardKey))).status,200);
 const snapshot={schemaVersion:1,type:'snapshot',player:{userId:900002,name:'fixture'},session:{id:a.sessionId},product:{version:'fixture'},cash:42};
 assert.equal((await api('/api/v2/runtime/push',post(snapshot,dashboardKey))).status,200);
 const upgrade=await live('/runtime-presence',post(a,dashboardKey,ta));assert.equal(upgrade.status,200);assert.equal((await upgrade.json()).dashboardLinked,true);
 assert.deepEqual(await stats(),{scriptSessions:3,scriptUsers:2,dashboardSessions:1,dashboardUsers:1});
 await wsCount({scriptUsers:2,dashboardUsers:1});pass('linking an existing unlinked session changes only dashboard counts');
 const history=await r.db.prepare('SELECT COUNT(*) AS launches FROM analytics_sessions').first();assert.equal(history.launches,3);
 pass('presence and later dashboard bootstrap share one session history row');
 for(const [sessionId,token,key] of [[b.sessionId,tb,''],[duplicate.sessionId,td,''],[a.sessionId,ta,dashboardKey]]){
  const res=await live('/runtime-presence/disconnect',post({sessionId},key,token));assert.equal(res.status,200);
 }
 assert.deepEqual(await stats(),{scriptSessions:0,scriptUsers:0,dashboardSessions:0,dashboardUsers:0});
 await wsCount({scriptUsers:0,scriptSessions:0});pass('signed disconnect removes linked and unlinked runtime counts');
 await fs.writeFile(new URL('presence-accounting-results.json',import.meta.url),JSON.stringify({passed:checks.length,checks,scope:'Fresh Miniflare database and mocked external services; actual presence routes and stats hub WebSocket; no production fixtures.'},null,2)+'\n');
}finally{for(const ws of sockets)try{ws.close(1000,'Test complete');}catch{}await r.mf.dispose();}
