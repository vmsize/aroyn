import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const source=(await fs.readFile(new URL('../apps/dashboard/assets/js/services/auth-service.js',import.meta.url),'utf8')).replace(/^import .*;\r?\n/gm,'').replace('export const authService=new AroynAuthService();','globalThis.service=new AroynAuthService();').replace(/^export \{.*$/gm,'');
const storageSource=(await fs.readFile(new URL('../apps/dashboard/assets/js/core/storage.js',import.meta.url),'utf8')).replace('export const storage','const storage');
const hold=()=>{let resolve;return{promise:new Promise(r=>resolve=r),resolve:v=>resolve(v)}};
function fixture({saved='session-A',exchange=false}={}){
  const body=hold(),handlers={},events=[],writes=[],records=new Map([['aroyn.auth.session',saved],['veyra.auth.session',saved]]);
  const localStorage={getItem:k=>records.get(k)??null,setItem:(k,v)=>{records.set(k,String(v));writes.push([k,String(v)])},removeItem:k=>records.delete(k)};
  const context=vm.createContext({URL,console,AbortSignal,CustomEvent:class{constructor(type){this.type=type}},API_BASE:'https://synthetic.invalid',localStorage,sessionStorage:{removeItem(){}},location:{href:'https://synthetic.invalid/dashboard/'+(exchange?'?aroyn_auth=synthetic-code':'')},history:{replaceState(){}},window:{addEventListener:(k,fn)=>handlers[k]=fn,dispatchEvent:e=>events.push(e.type)},fetch:async()=>({ok:true,json:()=>body.promise})});
  vm.runInContext(storageSource+source,context);
  return{service:context.service,body,handlers,records,writes,events,localStorage,change(key,value,oldValue=records.get(key)??null){if(key===null)records.clear();else if(value===null)records.delete(key);else records.set(key,value);handlers.storage({key,oldValue,newValue:value,storageArea:localStorage})}};
}
const checks=[];async function check(name,fn){await fn();checks.push(name)}
for(const key of ['aroyn.auth.session','veyra.auth.session'])for(const op of ['init','refresh','exchange','key'])for(const value of ['session-B','']){
  await check(`${key}: ${op} rejects late response after ${value?'replacement':'logout'}`,async()=>{
    const f=fixture({exchange:op==='exchange',saved:op==='exchange'?'':'session-A'});
    if(op!=='init'&&op!=='exchange'){f.service.user={id:'A'};f.service.status='authenticated'}
    const pending=op==='refresh'?f.service.refreshUser():op==='key'?f.service.generateDashboardKey():f.service.init();
    const done=(op==='refresh'||op==='key')?assert.rejects(pending,e=>e.code==='AUTH_CHANGED'):pending;
    f.change(key,value);
    f.body.resolve({user:{id:'stale-A'},token:'late-exchange',dashboardKey:'synthetic-late-key'});
    await done;
    assert.equal(f.service.status,'guest');assert.equal(f.service.user,null);assert.equal(f.service.token,'');assert.equal(f.service.generation,1);
    assert(!f.events.includes('aroyn:auth-login'));assert.equal(f.records.get('aroyn.auth.session'),value);assert(!f.writes.some(([,v])=>v==='late-exchange'));
  });
}
for(const key of ['aroyn.auth.session','veyra.auth.session'])await check(`${key}: same nonempty token preserves an ordinary refresh`,async()=>{
  const f=fixture();f.service.user={id:'A'};f.service.status='authenticated';const p=f.service.refreshUser();f.change(key,'session-A');f.body.resolve({user:{id:'A'}});await p;assert.equal(f.service.generation,0);assert(f.service.isAuthenticated());assert.equal(f.events.length,0);
});
await check('storage.clear invalidates tokenless exchange',async()=>{
  const f=fixture({saved:'',exchange:true});const p=f.service.init();f.change(null,null);f.body.resolve({user:{id:'late'},token:'late-token'});await p;assert.equal(f.service.status,'guest');assert.equal(f.records.size,0);
});
await check('null removal invalidates tokenless exchange',async()=>{
  const f=fixture({saved:'',exchange:true});const p=f.service.init();f.change('aroyn.auth.session',null);f.body.resolve({user:{id:'late'},token:'late-token'});await p;assert.equal(f.service.status,'guest');assert(!f.records.has('aroyn.auth.session'));
});
await check('legacy update preserves a newer canonical session',async()=>{
  const f=fixture();const p=f.service.init();f.records.set('aroyn.auth.session','session-C');f.change('veyra.auth.session','session-B');f.body.resolve({user:{id:'stale-A'}});await p;assert.equal(f.records.get('aroyn.auth.session'),'session-C');assert.equal(f.service.status,'guest');assert.equal(f.writes.length,0);
});
await check('obsolete queued storage event cannot erase a later session',async()=>{
  const f=fixture();const p=f.service.init();f.records.set('aroyn.auth.session','session-C');f.handlers.storage({key:'aroyn.auth.session',oldValue:'session-A',newValue:'',storageArea:f.localStorage});assert.equal(f.service.generation,0);f.change('aroyn.auth.session','session-C','session-B');f.body.resolve({user:{id:'stale-A'}});await p;assert.equal(f.service.status,'guest');assert.equal(f.records.get('aroyn.auth.session'),'session-C');
});
await check('sessionStorage and unrelated keys do not invalidate local auth',async()=>{
  const f=fixture();const p=f.service.init();f.handlers.storage({key:'aroyn.auth.session',newValue:'',storageArea:{}});f.change('aroyn.theme','light');f.body.resolve({user:{id:'A'}});await p;assert(f.service.isAuthenticated());assert.equal(f.service.generation,0);
});
await check('cleared then reused token cannot revive an old refresh',async()=>{
  const f=fixture();f.service.user={id:'A'};f.service.status='authenticated';const p=f.service.refreshUser();const done=assert.rejects(p,e=>e.code==='AUTH_CHANGED');f.change('aroyn.auth.session','');f.change('aroyn.auth.session','session-A');f.body.resolve({user:{id:'stale-A'}});await done;assert.equal(f.service.status,'guest');assert.equal(f.records.get('aroyn.auth.session'),'session-A');
});
const report={passed:checks.length,checks,scope:'Actual auth and storage modules in VM; synthetic browser-like storage events and deferred JSON. No real sessions or network.'};
console.log(JSON.stringify(report));await fs.writeFile(new URL('auth-storage-results.json',import.meta.url),JSON.stringify(report,null,2)+'\n');
