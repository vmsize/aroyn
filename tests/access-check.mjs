import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
import {createRuntime} from './runtime.mjs';
import {discordAccessAllowed,stagingAccessReady} from '../workers/shared/staging-access.js';
const allowed='900000000000000001',denied='900000000000000003';
const bindings={STAGING_ACCESS:'restricted',STAGING_DISCORD_IDS:allowed};
const results=[];
const check=(name,value)=>{assert(value,name);results.push({name,pass:true});console.log('PASS '+name);};
check('ordinary environment remains unrestricted',discordAccessAllowed({},denied));
check('empty restricted configuration fails closed',!stagingAccessReady({STAGING_ACCESS:'restricted'})&&!discordAccessAllowed({STAGING_ACCESS:'restricted'},allowed));
check('malformed list and unknown mode fail closed',!discordAccessAllowed({...bindings,STAGING_DISCORD_IDS:allowed+',bad'},allowed)&&!discordAccessAllowed({...bindings,STAGING_ACCESS:'typo'},allowed));
check('IDs must match exactly',discordAccessAllowed(bindings,allowed)&&!discordAccessAllowed(bindings,denied)&&!discordAccessAllowed(bindings,allowed.slice(1)));
let runtime=await createRuntime({mock:true,apiBindings:{STAGING_ACCESS:'restricted'}});
try{check('OAuth cannot start without an allowlist',(await runtime.api.fetch('http://local/api/v2/auth/discord/start')).status===503);}finally{await runtime.mf.dispose();}
runtime=await createRuntime({mock:true,apiBindings:bindings,liveBindings:bindings,mockDiscordIds:[allowed,denied]});
const api=(path,options={})=>runtime.api.fetch('http://local'+path,{redirect:'manual',...options});
const live=(path,options={})=>runtime.live.fetch('http://local'+path,{redirect:'manual',...options});
const post=(token,body)=>({method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
async function callback(code){const start=await api('/api/v2/auth/discord/start');const state=new URL(start.headers.get('location')).searchParams.get('state');const cookie=start.headers.getSetCookie().map(c=>c.split(';')[0]).join('; ');return api('/api/v2/auth/discord/callback?code='+code+'&state='+state,{headers:{cookie}});}
try{
 check('uninvited Discord callback is denied',(await callback('mock-b')).status===403);
 check('denied callback creates no account',Number((await runtime.db.prepare('SELECT COUNT(*) AS count FROM users').first()).count)===0);
 const cb=await callback('mock');check('invited Discord callback succeeds',cb.status===302);
 const code=new URL(cb.headers.get('location')).searchParams.get('veyra_auth');
 const session=await (await api('/api/v2/auth/exchange',post('',{code}))).json();assert(session.token);
 const key=await (await api('/api/v2/dashboard-key/generate',post(session.token,{}))).json();assert(key.dashboardKey);
 check('runtime link accepts key before first snapshot',(await api('/api/v2/runtime/link',post(key.dashboardKey,{robloxUserId:'900002'}))).status===200);
 check('live token needs initial HTTP snapshot',(await live('/token',post(key.dashboardKey,{robloxUserId:'900002'}))).status===403);
 const snapshot={schemaVersion:1,type:'snapshot',player:{userId:900002,name:'robloxuser'},session:{id:'staging-fixture-session'},cash:100};
 check('invited runtime HTTP push succeeds',(await api('/api/v2/runtime/push',post(key.dashboardKey,snapshot))).status===200);
 const presence={sessionId:'staging-fixture-session',robloxUserId:'900002'};
 check('anonymous presence is denied',(await live('/runtime-presence',post('',presence))).status===403);
 const presenceResponse=await live('/runtime-presence',post(key.dashboardKey,presence));check('linked invited presence succeeds',presenceResponse.status===200);
 const presenceBody=await presenceResponse.json();assert(presenceBody.presenceToken);
 check('anonymous disconnect is denied',(await live('/runtime-presence/disconnect',post('',presence))).status===403);
 const disconnectOptions=post(key.dashboardKey,presence);disconnectOptions.headers['X-Presence-Token']=presenceBody.presenceToken;
 check('authenticated signed presence disconnect succeeds',(await live('/runtime-presence/disconnect',disconnectOptions)).status===200);
 check('script distribution is disabled',(await api('/loader')).status===410);
 const runtimeToken=await (await live('/token',post(key.dashboardKey,{robloxUserId:'900002'}))).json();assert(runtimeToken.token);
 const socketResponse=await live('/ws?token='+encodeURIComponent(runtimeToken.token),{headers:{Upgrade:'websocket'}});
 check('invited runtime can connect a WebSocket',socketResponse.status===101);socketResponse.webSocket.accept();
 await runtime.db.prepare('UPDATE users SET discord_id=?1').bind(denied).run();
 check('web session loses access when identity leaves allowlist',(await api('/api/v2/auth/me',{headers:{authorization:'Bearer '+session.token}})).status===401);
 check('dashboard key loses access when identity leaves allowlist',(await api('/api/v2/runtime/push',post(key.dashboardKey,snapshot))).status===401);
 check('issued WebSocket token loses access',(await live('/ws?token='+encodeURIComponent(runtimeToken.token),{headers:{Upgrade:'websocket'}})).status===401);
 socketResponse.webSocket.close();
}finally{await runtime.mf.dispose();}
await writeFile(new URL('./access-results.json',import.meta.url),JSON.stringify(results,null,2));
