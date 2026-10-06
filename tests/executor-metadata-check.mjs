import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';
import {createRuntime} from './runtime.mjs';
import {seedRecovery} from './recovery-fixture.mjs';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const checks=[];const pass=name=>{checks.push(name);console.log('PASS '+name)};
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const client=(await fs.readFile(new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url),'utf8')).replaceAll('\r\n','\n');
function section(text,first,last){const a=text.indexOf(first),b=text.indexOf(last,a);assert(a>=0&&b>a);return text.slice(a,b);}
const functions=section(client,'function AroynWeb.CleanExecutorText(','function AroynWeb.ClosePresenceSocket()');
const script=`local AroynWeb = {}
local HttpService = {GenerateGUID=function() return string.rep('a',32) end}
local LocalPlayer = {UserId=900002}
local game = {GameId=1,PlaceId=2}
identifyexecutor = nil; getexecutorname = nil
`+functions+String.raw`
AroynWeb.DeviceType=function()return 'desktop' end
AroynWeb.ValidKey=function()return false end
assert(AroynWeb.ExecutorInfo().name=='Unknown' and AroynWeb.ExecutorInfo().version==nil)
identifyexecutor=function() return 'Potassium','1.2.3' end
AroynWeb.executorInfo=nil
local e=AroynWeb.ExecutorInfo();assert(e.name=='Potassium' and e.version=='1.2.3')
identifyexecutor=function()error('must use cached value')end
assert(AroynWeb.ExecutorInfo()==e)
local p=AroynWeb.PresencePayload();assert(p.executorName=='Potassium' and p.executorVersion=='1.2.3')
AroynWeb.executorInfo=nil;getexecutorname=function()return 'Alias executor' end
assert(AroynWeb.ExecutorInfo().name=='Alias executor' and AroynWeb.ExecutorInfo().version==nil)
AroynWeb.executorInfo=nil;identifyexecutor=function()return {},'do not accept' end
assert(AroynWeb.ExecutorInfo().name=='Alias executor')
AroynWeb.executorInfo=nil;identifyexecutor=function()return ' \n Wave\0   ',' 3\n.0 ' end;getexecutorname=nil
e=AroynWeb.ExecutorInfo();assert(e.name=='Wave' and e.version=='3 .0')
AroynWeb.executorInfo=nil;identifyexecutor=function()return string.rep('a',600),string.rep('b',600) end
e=AroynWeb.ExecutorInfo();assert(#e.name==64 and #e.version==32)
AroynWeb.executorInfo=nil;identifyexecutor=function()return 'Unknown','ignore' end
assert(AroynWeb.ExecutorInfo().name=='Unknown' and AroynWeb.ExecutorInfo().version==nil)
print('executor probes passed')
`;
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-executor-'));
const rt=await luauTestRuntime();const probe=path.join(temp,'check.luau');await fs.writeFile(probe,script);
for(const file of [probe]){const c=spawnSync(rt.compiler,['--null',file],{encoding:'utf8'});assert.equal(c.status,0,c.stderr)}
const run=spawnSync(rt.runtime,[probe],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stdout+'\n'+run.stderr);
pass('actual Luau detection handles primary API, alias, absence, errors, invalid types, bounds and cached identity');
const r=await createRuntime({mock:true,ownerDiscordId:'900001'});const sockets=[];
const fetch=(url,options={})=>r.live.fetch('http://local'+url,options);
const post=(body,token='')=>({method:'POST',headers:{'Content-Type':'application/json',...(token?{'X-Presence-Token':token}:{})},body:JSON.stringify(body)});
const row=sid=>r.db.prepare('SELECT * FROM analytics_sessions WHERE session_id=?1').bind(sid).first();
try{
 const bucket=await r.mf.getR2Bucket('PAYLOADS','api');const {accounts:[owner,other]}=await seedRecovery({DB:r.db,PAYLOADS:bucket});
 assert.equal((await row(owner.sid)).executor_name,null);pass('additive migration preserves earlier history as unknown');
 const payload={sessionId:'local-executor-http',robloxUserId:'900002',version:manifest.version,device:'desktop',executorName:'Potassium',executorVersion:'1.2.3'};
 let res=await fetch('/runtime-presence',post(payload));assert.equal(res.status,200);let token=(await res.json()).presenceToken;
 let saved=await row(payload.sessionId);assert.equal(saved.executor_name,'Potassium');assert.equal(saved.executor_version,'1.2.3');pass('HTTPS stores optional executor metadata without dashboard linking');
 const originalSeen=saved.last_seen_at;await new Promise(resolve=>setTimeout(resolve,15));
 res=await fetch('/runtime-presence',post(payload,token));assert.equal(res.status,200);assert.equal((await row(payload.sessionId)).last_seen_at,originalSeen);pass('unchanged metadata does not add rapid analytics checkpoint writes');
 res=await fetch('/runtime-presence',post({...payload,executorName:undefined,executorVersion:undefined},token));assert.equal(res.status,200);assert.equal((await row(payload.sessionId)).executor_name,'Potassium');pass('legacy heartbeat cannot erase known executor metadata');
 res=await fetch('/runtime-presence',post({...payload,executorName:'  Wave\u0000\n  ',executorVersion:'3.0'},token));assert.equal(res.status,200);assert.equal((await row(payload.sessionId)).executor_name,'Wave');
 res=await fetch('/runtime-presence',post({...payload,executorName:'Different executor',executorVersion:undefined},token));assert.equal(res.status,200);saved=await row(payload.sessionId);assert.equal(saved.executor_name,'Different executor');assert.equal(saved.executor_version,null);pass('normalization strips controls and never pairs a new executor with an old version');
 const sid='local-executor-ws',upgrade=await fetch('/runtime-presence/ws?sid='+sid,{headers:{Upgrade:'websocket'}});assert.equal(upgrade.status,101);const ws=upgrade.webSocket;sockets.push(ws);const messages=[];ws.addEventListener('message',e=>messages.push(JSON.parse(e.data)));ws.accept();
 ws.send(JSON.stringify({...payload,sessionId:sid,type:'presence',sequence:1,executorName:'<img src=x onerror=alert(1)>',executorVersion:'1'.repeat(80)}));
 const deadline=Date.now()+5000;while(!messages.length&&Date.now()<deadline)await new Promise(done=>setTimeout(done,10));assert.equal(messages[0]?.type,'presence_ack');saved=await row(sid);assert.equal(saved.executor_name,'<img src=x onerror=alert(1)>');assert.equal(saved.executor_version.length,32);pass('WebSocket uses the same bounded metadata storage');
 const malformed={...payload,sessionId:'local-executor-invalid',executorName:{untrusted:true},executorVersion:'9'};
 res=await fetch('/runtime-presence',post(malformed));assert.equal(res.status,200);saved=await row(malformed.sessionId);assert.equal(saved.executor_name,null);assert.equal(saved.executor_version,null);pass('invalid metadata does not break presence or invent an executor');
 const runtimeToken=await fetch('/token',{method:'POST',headers:{Authorization:'Bearer '+owner.key,'Content-Type':'application/json'},body:JSON.stringify({robloxUserId:owner.robloxId})});assert.equal(runtimeToken.status,200);
 const signedToken=(await runtimeToken.json()).token;
 const rich=await fetch('/ws?token='+encodeURIComponent(signedToken),{headers:{Upgrade:'websocket'}});assert.equal(rich.status,101);
 const linkedSocket=rich.webSocket;sockets.push(linkedSocket);const linkedMessages=[];linkedSocket.addEventListener('message',e=>linkedMessages.push(JSON.parse(e.data)));linkedSocket.accept();
 linkedSocket.send(JSON.stringify({schemaVersion:1,type:'snapshot',player:{userId:Number(owner.robloxId)},session:{id:'local-executor-linked'},product:{version:manifest.version},executor:{name:'Linked executor',version:'2.0'}}));
 const linkedDeadline=Date.now()+5000;while(!(await row('local-executor-linked'))&&Date.now()<linkedDeadline)await new Promise(done=>setTimeout(done,10));
 assert.equal((await row('local-executor-linked'))?.executor_name,'Linked executor');assert.equal((await row('local-executor-linked'))?.executor_version,'2.0');pass('authenticated linked telemetry records the same executor fields on its first snapshot');
 assert.equal((await fetch('/owner/analytics')).status,401);assert.equal((await fetch('/owner/analytics',{headers:{Authorization:'Bearer '+other.token}})).status,403);
 const fixtureNames=Array.from({length:13},(_,i)=>`Executor fixture ${String(i).padStart(2,'0')}`);
 const fixtureNow=Date.now();
 await r.db.batch(fixtureNames.map((name,i)=>r.db.prepare(`INSERT INTO analytics_sessions(session_id,roblox_user_id,version,started_at,last_seen_at,executor_name) VALUES(?1,?2,?3,?4,?4,?5)`).bind('local-executor-list-'+i,String(950000+i),manifest.version,fixtureNow-(i===0?2*86400000:60000),name)));
 res=await fetch('/owner/analytics',{headers:{Authorization:'Bearer '+owner.token}});assert.equal(res.status,200);const {analytics}=await res.json();
 for(const name of fixtureNames.slice(1))assert(analytics.executors.some(x=>x.label===name),'missing executor beyond top ten: '+name);
 assert(!analytics.executors.some(x=>x.label===fixtureNames[0]));
 const week=await fetch('/owner/analytics?range=7d',{headers:{Authorization:'Bearer '+owner.token}});assert.equal(week.status,200);
 const weekBody=await week.json();for(const name of fixtureNames)assert(weekBody.analytics.executors.some(x=>x.label===name));
 pass('executor breakdown includes every group beyond ten and still respects the selected period');

 assert(analytics.executors.some(x=>x.label==='Different executor'));assert(analytics.executors.some(x=>x.label==='Unknown'));
 assert.equal(analytics.onlineSessions.find(x=>x.sessionId===sid).executorName,'<img src=x onerror=alert(1)>');
 assert.equal(analytics.recent.find(x=>x.sessionId===payload.sessionId).executorName,'Different executor');
 assert.equal(analytics.allUsers.find(x=>x.userId==='900002').executorName,null); // Latest launch reported no name.
 pass('owner-only aggregate, live, recent and latest-user metadata remain authorized');
 const stats=await (await fetch('/admin/stats',{headers:{Authorization:'Bearer mock-stats-secret'}})).json();assert(!JSON.stringify(stats).includes('executorName'));pass('bot count endpoint does not expose executor details');
 const ui=await fs.readFile(new URL('../apps/dashboard/assets/js/pages/admin-analytics.js',import.meta.url),'utf8');
 const context=vm.createContext({gameName:()=>'',safeAvatarUrl:()=>'/assets/aroyn-mark.png',dateTime:()=>'',timeAgo:()=>'',duration:()=>'',num:String});
 vm.runInContext(section(ui,'const esc=','const num=')+section(ui,'const executorLabel=','function showGate(')+section(ui,'function renderBreakdown(','function renderTables(')+"globalThis.rowHtml=sessionRow;globalThis.breakdown=renderBreakdown;",context);
 const html=context.rowHtml({executorName:'<img src=x onerror=alert(1)>',executorVersion:'" onclick="bad'});assert(!html.includes('<img src=x'));assert(html.includes('&lt;img'));assert(!html.includes(' onclick="bad'));
 assert(context.rowHtml({}).includes('Unknown'));const el={};context.breakdown(el,[{label:'<script>bad</script>',launches:1,users:1}]);assert(!el.innerHTML.includes('<script>'));pass('actual admin renderers escape executor names and versions and display Unknown');
 await fs.writeFile(new URL('executor-metadata-results.json',import.meta.url),JSON.stringify({version:manifest.version,passed:checks.length,checks,scope:'Actual Luau detection, native synthetic D1/Workers/WebSocket and actual owner renderers; no game or production fixture.'},null,2)+'\n');
}finally{for(const ws of sockets)try{ws.close(1000,'Test complete')}catch{}await r.mf.dispose();}
