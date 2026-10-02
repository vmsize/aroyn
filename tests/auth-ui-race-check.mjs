import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=(await fs.readFile(new URL('../apps/dashboard/assets/js/services/auth-service.js',import.meta.url),'utf8')).replace(/^import .*;\r?\n/gm,'').replace('export const authService=new AroynAuthService();','globalThis.service=new AroynAuthService();').replace(/^export \{.*$/gm,'');
const hold=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return {promise,resolve,reject}};
const response=body=>({ok:true,json:async()=>body});
function fixture(fetcher,{exchange=false,saved=false}={}){
 const records=new Map(saved?[['auth.session','synthetic-session']]:[]),handlers={},events=[],signals=[];
 const context=vm.createContext({URL,console,AbortSignal,CustomEvent:class {constructor(type){this.type=type}},API_BASE:'https://synthetic.invalid',location:{href:'https://site.invalid/dashboard/'+(exchange?'?aroyn_auth=synthetic-exchange':'')},history:{replaceState(){}},storage:{getRaw:(k,d)=>records.get(k)||d,setRaw:(k,v)=>records.set(k,v)},localStorage:{removeItem(){}},sessionStorage:{removeItem(){}},window:{addEventListener:(name,fn)=>handlers[name]=fn,dispatchEvent:event=>events.push(event.type)},fetch:(...args)=>{signals.push(args[1]?.signal);return fetcher(...args)}});
 vm.runInContext(source,context);return {service:context.service,handlers,events,records,signals};
}
function signed(service){service.token='synthetic-session';service.user={id:'synthetic-user'};service.status='authenticated'}
const checks=[];async function check(name,fn){await fn();checks.push(name)}
await check('late profile body while logout POST waits cannot restore user or status',async()=>{
 const body=hold(),logout=hold();const f=fixture(url=>url.endsWith('/auth/me')?{ok:true,json:()=>body.promise}:logout.promise);signed(f.service);
 const refresh=f.service.refreshUser();const rejected=assert.rejects(refresh,e=>e.code==='AUTH_CHANGED');const exiting=f.service.logout();assert.equal(f.service.status,'guest');body.resolve({user:{id:'synthetic-user'}});await rejected;
 assert.equal(f.service.user,null);assert.equal(f.service.token,'');assert.equal(f.service.status,'guest');assert(!f.service.isAuthenticated());logout.resolve(response({}));await exiting;assert(f.events.includes('aroyn:auth-logout'));assert(f.signals.every(Boolean));
});
await check('local deletion invalidates pending profile body even if same token is later reused',async()=>{
 const body=hold();const f=fixture(()=>({ok:true,json:()=>body.promise}));signed(f.service);const task=f.service.refreshUser();const rejected=assert.rejects(task,e=>e.code==='AUTH_CHANGED');f.service.clearLocalAccountData();signed(f.service);body.resolve({user:{id:'stale'}});await rejected;assert.equal(f.service.user.id,'synthetic-user');
});
await check('cross-tab logout invalidates pending profile refresh',async()=>{
 const body=hold();const f=fixture(()=>({ok:true,json:()=>body.promise}));signed(f.service);const task=f.service.refreshUser();const rejected=assert.rejects(task,e=>e.code==='AUTH_CHANGED');f.handlers.storage({key:'aroyn.auth.session',newValue:null});body.resolve({user:{id:'stale'}});await rejected;assert.equal(f.service.user,null);
});
await check('late initial me reply cannot restore a locally cleared profile',async()=>{
 const body=hold();const f=fixture(()=>({ok:true,json:()=>body.promise}),{saved:true});const task=f.service.init();f.service.clearLocalAccountData();body.resolve({user:{id:'stale'}});await task;assert.equal(f.service.status,'guest');assert.equal(f.service.user,null);
});
await check('late exchange reply cannot save a new token after local clear',async()=>{
 const body=hold();const f=fixture(()=>({ok:true,json:()=>body.promise}),{exchange:true});const task=f.service.init();f.service.clearLocalAccountData();body.resolve({user:{id:'stale'},token:'synthetic-stale'});await task;assert.equal(f.service.token,'');assert.equal(f.service.status,'guest');assert(!f.events.includes('aroyn:auth-login'));
});
await check('late key response is discarded before profile refresh and key reveal',async()=>{
 const body=hold();let reads=0;const f=fixture(url=>url.endsWith('/generate')?{ok:true,json:()=>body.promise}:(reads++,response({user:{id:'synthetic-user'}})));signed(f.service);
 const task=f.service.generateDashboardKey(true);const rejected=assert.rejects(task,e=>e.code==='AUTH_CHANGED');f.service.clearLocalAccountData();body.resolve({dashboardKey:'synthetic-new-key'});await rejected;assert.equal(reads,0);assert.equal(f.service.user,null);
});
await check('logout during key refresh discards late key and profile',async()=>{
 const body=hold(),started=hold();const f=fixture(url=>url.endsWith('/generate')?response({dashboardKey:'synthetic-new-key'}):url.endsWith('/auth/me')?(started.resolve(),{ok:true,json:()=>body.promise}):response({}));signed(f.service);
 const task=f.service.generateDashboardKey();const rejected=assert.rejects(task,e=>e.code==='AUTH_CHANGED');await started.promise;await f.service.logout();body.resolve({user:{id:'stale'}});await rejected;assert.equal(f.service.user,null);
});
await check('ordinary initial profile, refresh and key generation still complete',async()=>{
 const f=fixture(url=>response(url.endsWith('/generate')?{dashboardKey:'synthetic-key'}:{user:{id:'synthetic-user'}}),{saved:true});await f.service.init();assert(f.service.isAuthenticated());await f.service.refreshUser();assert.equal((await f.service.generateDashboardKey()).dashboardKey,'synthetic-key');assert.equal(f.service.status,'authenticated');
});
console.log(JSON.stringify({passed:checks.length,checks}));await fs.writeFile(new URL('auth-ui-race-results.json',import.meta.url),JSON.stringify({passed:checks.length,checks,scope:'Actual auth class in VM with synthetic deferred bodies; no real sessions or requests.'},null,2));
