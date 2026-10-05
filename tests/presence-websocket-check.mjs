import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';
const r=await createRuntime({mock:true}),sockets=[],checks=[];
const fetch=(p,o={})=>r.live.fetch('http://local'+p,o);
const post=(body,key='',token='')=>({method:'POST',headers:{'Content-Type':'application/json',...(key?{Authorization:'Bearer '+key}:{}),...(token?{'X-Presence-Token':token}:{})},body:JSON.stringify(body)});
const fixture=(sid,id='900002')=>({type:'presence',sequence:1,sessionId:sid,robloxUserId:id,version:'fixture',gameSlug:'greedy-growers',device:'desktop',resumeNonce:'a'.repeat(64)});
function pass(name){checks.push(name);console.log('PASS '+name);}
async function stats(){return (await (await fetch('/admin/stats',{headers:{Authorization:'Bearer mock-stats-secret'}})).json()).online;}
async function connect(sid,extra={}){
 const res=await fetch('/runtime-presence/ws?sid='+sid,{headers:{Upgrade:'websocket',...extra}});assert.equal(res.status,101);
 const ws=res.webSocket,messages=[];let closed=false;
 ws.addEventListener('message',e=>messages.push(JSON.parse(e.data)));ws.addEventListener('close',()=>{closed=true;});ws.accept();sockets.push(ws);
 return {ws,messages,get closed(){return closed;}};
}
async function wait(test){const end=Date.now()+5000;while(Date.now()<end){if(test())return;await new Promise(done=>setTimeout(done,10));}assert.fail('Expected WebSocket event not received');}
async function send(c,body){c.ws.send(JSON.stringify(body));await wait(()=>c.messages.some(x=>x.sequence===body.sequence));return c.messages.find(x=>x.sequence===body.sequence);}
try{
 assert.equal((await fetch('/runtime-presence/ws?sid=short',{headers:{Upgrade:'websocket'}})).status,400);
 assert.equal((await fetch('/runtime-presence/ws?sid=local-ws-session-a')).status,426);pass('invalid session and missing upgrade rejected');
 const a=fixture('local-ws-session-a'),c=await connect(a.sessionId,{'X-Veyra-Role':'dashboard','X-Veyra-User-Id':'forged'});
 assert.equal((await stats()).scriptUsers,0);
 const ack=await send(c,a);assert.equal(ack.type,'presence_ack');assert.equal(ack.ok,true);assert.equal(ack.dashboardLinked,false);assert(ack.presenceToken);
 assert.deepEqual(await stats(),{scriptSessions:1,scriptUsers:1,dashboardSessions:0,dashboardUsers:0});pass('basic socket registers unlinked presence only after signed ACK and ignores forged live headers');
 const again=await send(c,{...a,sequence:2,presenceToken:ack.presenceToken});assert.equal(again.type,'presence_ack');
 assert.equal((await r.db.prepare('SELECT COUNT(*) AS n FROM analytics_sessions').first()).n,1);pass('signed heartbeat keeps one history row');
 await r.mf.unsafeEvictDurableObject('live','VeyraLiveSession',{name:'presence:'+a.sessionId,webSockets:'hibernate'});
 const hibernated=await send(c,{...a,sequence:3,presenceToken:again.presenceToken});assert.equal(hibernated.type,'presence_ack');pass('socket identity and signed heartbeat survive native DO hibernation');
 assert.equal((await fetch('/runtime-presence',post({...a,resumeNonce:'b'.repeat(64)}))).status,401);
 const lostAckRecovery=await fetch('/runtime-presence',post(a));assert.equal(lostAckRecovery.status,200);
 assert((await lostAckRecovery.json()).presenceToken);assert.equal((await stats()).scriptSessions,1);pass('lost initial ACK recovers over HTTPS only with the independent client proof');
 const d=fixture('local-ws-session-duplicate'),duplicate=await connect(d.sessionId),da=await send(duplicate,d);
 assert.deepEqual(await stats(),{scriptSessions:2,scriptUsers:1,dashboardSessions:0,dashboardUsers:0});pass('duplicate Roblox IDs count as one user');
 const bad=await connect(a.sessionId),rejected=await send(bad,{...a,presenceToken:'invalid'});
 assert.equal(rejected.status,401);await wait(()=>bad.closed);assert.equal((await stats()).scriptSessions,2);pass('invalid signed resume cannot disturb existing presence');
 const replaced=await connect(a.sessionId),ra=await send(replaced,{...a,presenceToken:again.presenceToken});
 await wait(()=>c.closed);assert.equal(ra.type,'presence_ack');assert.equal((await stats()).scriptSessions,2);pass('signed reconnect replaces old socket without duplicate counts');
 replaced.ws.close(1000,'Transport disconnected');await wait(()=>replaced.closed);
 const fallback=await fetch('/runtime-presence',post(a,'',ra.presenceToken));assert.equal(fallback.status,200);const fa=await fallback.json();
 assert.equal((await stats()).scriptSessions,2);pass('socket close cannot erase HTTPS fallback presence');
 const recovered=await connect(a.sessionId),reca=await send(recovered,{...a,presenceToken:fa.presenceToken});assert.equal(reca.type,'presence_ack');pass('HTTPS fallback returns to signed WebSocket');
 const api=(p,o={})=>r.api.fetch('http://local'+p,{redirect:'manual',...o});
 const start=await api('/api/v2/auth/discord/start'),state=new URL(start.headers.get('location')).searchParams.get('state'),cookie=start.headers.getSetCookie().map(x=>x.split(';')[0]).join('; ');
 const callback=await api('/api/v2/auth/discord/callback?code=mock&state='+state,{headers:{cookie}}),code=new URL(callback.headers.get('location')).searchParams.get('veyra_auth');
 const account=await (await api('/api/v2/auth/exchange',post({code}))).json(),{dashboardKey}=await (await api('/api/v2/dashboard-key/generate',post({},account.token))).json();
 assert.equal((await api('/api/v2/runtime/link',post({robloxUserId:'900002'},dashboardKey))).status,200);
 assert.equal((await api('/api/v2/runtime/push',post({schemaVersion:1,type:'snapshot',player:{userId:900002,name:'fixture'},session:{id:a.sessionId},product:{version:'fixture'},cash:42},dashboardKey))).status,200);
 const bootstrap=await fetch('/runtime-presence',post({...a,resumeNonce:undefined},dashboardKey));assert.equal(bootstrap.status,200);assert((await bootstrap.json()).presenceToken);
 pass('valid owned dashboard credential bootstraps a presence token after telemetry history exists');
 const linked=await send(recovered,{...a,sequence:2,presenceToken:reca.presenceToken,dashboardKey});assert.equal(linked.dashboardLinked,true);assert.equal((await stats()).dashboardUsers,1);pass('dashboard linking upgrades same session with ownership validation');
 const unlinked=await send(recovered,{...a,sequence:3,presenceToken:linked.presenceToken});assert.equal(unlinked.dashboardLinked,false);assert.equal((await stats()).dashboardUsers,0);pass('unlink downgrades dashboard counts without losing online session');
 const invalid=await connect('local-ws-invalid-frame');invalid.ws.send(JSON.stringify({type:'snapshot',schemaVersion:1,sessionId:'local-ws-invalid-frame',sequence:1}));await wait(()=>invalid.closed);pass('basic socket rejects detailed telemetry');
 const large=await connect('local-ws-large-frame');large.ws.send('x'.repeat(8193));await wait(()=>large.closed);pass('oversized frames rejected before D1 writes');
 const flood=await connect('local-ws-flood-frame');for(let i=1;i<=15;i++)flood.ws.send(JSON.stringify({...fixture('local-ws-flood-frame'),sequence:i,robloxUserId:'bad'}));await wait(()=>flood.closed);pass('abusive messages and pending queues bounded');
 const stopped=await send(recovered,{...a,type:'presence_disconnect',sequence:4,presenceToken:unlinked.presenceToken});assert.equal(stopped.type,'presence_disconnected');await wait(()=>recovered.closed);
 assert.equal((await fetch('/runtime-presence/disconnect',post({sessionId:d.sessionId},'',da.presenceToken))).status,200);assert.equal((await stats()).scriptSessions,0);pass('signed stop removes counts over WebSocket and HTTPS');
 await fs.writeFile(new URL('presence-websocket-results.json',import.meta.url),JSON.stringify({passed:checks.length,checks,scope:'Native Miniflare Workers/D1/hibernation sockets; no production fixtures.'},null,2)+'\n');
}finally{for(const ws of sockets)try{ws.close(1000,'Test complete');}catch{}await r.mf.dispose();}
