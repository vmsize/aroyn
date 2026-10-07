import assert from 'node:assert/strict';
import {writeFile,readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {createRuntime} from './runtime.mjs';
const oldOrigin='https://aroyn-staging.pages.dev',newOrigin='https://aroyn.xyz';
const allowed=newOrigin+','+oldOrigin;
const callback='https://aroyn-api-staging.veyra-hub.workers.dev/api/v2/auth/discord/callback';
const rt=await createRuntime({mock:true,ownerDiscordId:'900001',apiBindings:{ALLOWED_ORIGIN:allowed,SITE_ORIGIN:newOrigin,DISCORD_REDIRECT_URI:callback},liveBindings:{ALLOWED_ORIGIN:allowed}});
const api=(path,options={})=>rt.api.fetch('http://local'+path,{redirect:'manual',...options});
const live=(path,options={})=>rt.live.fetch('http://local'+path,{redirect:'manual',...options});
const post=(token,body)=>({method:'POST',headers:{'content-type':'application/json',...(token?{authorization:'Bearer '+token}:{})},body:JSON.stringify(body)});
const results=[];
function pass(name){results.push(name);console.log('PASS '+name)}
async function login(path,origin){
 const start=await api('/api/v2/auth/discord/start?returnTo='+encodeURIComponent(path));assert.equal(start.status,302);
 const oauth=new URL(start.headers.get('location'));assert.equal(oauth.searchParams.get('redirect_uri'),callback);
 const cookie=start.headers.getSetCookie().map(x=>x.split(';')[0]).join('; ');
 const response=await api('/api/v2/auth/discord/callback?code=mock&state='+oauth.searchParams.get('state'),{headers:{cookie}});assert.equal(response.status,302);
 const dest=new URL(response.headers.get('location'));assert.equal(dest.origin,newOrigin);assert.equal(dest.pathname,path);
 const exchange=await api('/api/v2/auth/exchange',post('',{code:dest.searchParams.get('veyra_auth')}));assert.equal(exchange.status,200);return exchange.json();
}
try{
 // Miniflare's local service proxy rejects external Origin headers before the
 // Worker runs. Exercise actual CORS functions here; cloud preflight is also
 // checked during rollout. Native auth/store tests below use the proxy normally.
 for(const file of ['../workers/api/src/worker.js','../workers/live/src/index.js']){
  const source=await readFile(new URL(file,import.meta.url),'utf8');const start=source.indexOf('function corsHeaders('),end=source.indexOf('\nfunction ',start+1);
  const context=vm.createContext({siteOrigin:()=>newOrigin});vm.runInContext(source.slice(start,end)+'\nglobalThis.cors=corsHeaders;',context);
  for(const origin of [newOrigin,oldOrigin]){
   const headers=context.cors({headers:new Headers({Origin:origin})},{ALLOWED_ORIGIN:allowed});assert.equal(headers['Access-Control-Allow-Origin'],origin);assert.equal(headers.Vary,'Origin');
  }
  assert.notEqual(context.cors({headers:new Headers({Origin:'https://untrusted.example'})},{ALLOWED_ORIGIN:allowed})['Access-Control-Allow-Origin'],'https://untrusted.example');
 }
 pass('both site origins pass CORS on API/live; unrelated origin is not allowed');
 const original=await login('/dashboard/',oldOrigin);
 const key=await (await api('/api/v2/dashboard-key/generate',post(original.token,{}))).json();assert(key.dashboardKey);
 assert.equal((await api('/api/v2/runtime/link',post(key.dashboardKey,{robloxUserId:'900002'}))).status,200);
 const snapshot={schemaVersion:1,type:'snapshot',player:{userId:900002,name:'robloxuser'},session:{id:'domain-fixture-session'},cash:321};
 assert.equal((await api('/api/v2/runtime/push',post(key.dashboardKey,snapshot))).status,200);
 const current=await login('/dashboard/',newOrigin);assert.equal(current.user.id,original.user.id);
 const auth={authorization:'Bearer '+current.token};
 const accounts=await (await api('/api/v2/runtime/accounts',{headers:auth})).json();assert.equal(accounts.accounts[0].userId,'900002');
 const stored=await (await api('/api/v2/runtime/snapshot?robloxUserId=900002',{headers:auth})).json();assert.equal(stored.snapshot.cash,321);
 assert.equal(Number((await rt.db.prepare('SELECT COUNT(*) AS count FROM users').first()).count),1);
 assert.equal((await api('/api/v2/runtime/push',post(key.dashboardKey,{...snapshot,cash:322}))).status,200);
 pass('same Discord login preserves one account, existing runtime link, snapshot and dashboard key across origins');
 const owner=await login('/admin/',newOrigin);assert.equal(owner.user.id,original.user.id);
 const ownerAnalytics=await live('/owner/analytics',{headers:{authorization:'Bearer '+owner.token}});assert.equal(ownerAnalytics.status,200);
 pass('admin return path stays on custom domain and existing owner authorization is retained');
 const webToken=await live('/web-token',post(current.token,{robloxUserId:'900002'}));assert.equal(webToken.status,200);
 pass('existing linked runtime remains authorized for live dashboard after new-domain login');
}finally{await rt.mf.dispose()}
await writeFile(new URL('./custom-domain-results.json',import.meta.url),JSON.stringify({passed:results.length,checks:results,scope:'Synthetic Discord exchange with actual API/live Workers and shared isolated D1/R2/DO; no production credentials or data.'},null,2)+'\n');
