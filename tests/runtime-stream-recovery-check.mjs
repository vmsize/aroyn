import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
import {LiveSnapshotAssembler} from '../apps/dashboard/assets/js/services/live-snapshot.js';
const source=(await fs.readFile(new URL('../apps/dashboard/assets/js/services/runtime-service.js',import.meta.url),'utf8'))
 .replace(/^import .*;\r?\n/gm,'').replace(/export const runtimeService = new AroynRuntimeService\(\);/,'globalThis.Service=AroynRuntimeService;').replace(/^export \{.*;\r?$/gm,'');
const checks=[];
const deferred=()=>{let resolve,reject;const promise=new Promise((a,b)=>{resolve=a;reject=b});return{resolve,reject,promise}};
const reply=(body,status=200)=>({ok:status<400,status,json:async()=>body});
const accounts=[{userId:'101',username:'alpha',online:false},{userId:'202',username:'beta',online:false}];
const payload=(value=12)=>({type:'snapshot',player:{userId:'101',name:'alpha'},session:{id:'synthetic',durationSeconds:20},stats:{},details:{compost:{seedsFed:value}},activity:[],logs:[],modules:[]});
const envelope=(online=false)=>({account:accounts[0],online,lastSeen:1,snapshot:payload(0)});
async function settle(){for(let i=0;i<25;i++)await Promise.resolve()}
function fixture(fetcher){
 let now=1791000000000,next=0;const timers=new Map(),sockets=[],calls=[];
 const auth={status:'authenticated',token:'synthetic-session',user:{id:'test-owner'}};
 class Socket{static OPEN=1;static CONNECTING=0;constructor(url){this.url=url;this.readyState=0;sockets.push(this)}close(){this.readyState=3;this.closed=true}}
 const context=vm.createContext({structuredClone,AbortController,URL,console,performance,WebSocket:Socket,LiveSnapshotAssembler,
  Date:class extends Date{static now(){return now}},setTimeout(fn,delay){const id=++next;timers.set(id,{fn,delay});return id},clearTimeout(id){timers.delete(id)},queueMicrotask(){},
  mockRuntime:{config:{},activity:[],logs:[],modules:[],session:{},system:{},connection:{}},
  API_BASE:'https://api.example.test',LIVE_BASE:'https://live.example.test',LIVE_WS_BASE:'wss://live.example.test/ws',
  storage:{getRaw:(k,f)=>f,setRaw(){}},authService:{getSnapshot:()=>auth,subscribe(){},init:async()=>auth,isAuthenticated:()=>auth.status==='authenticated'},
  fetch:async(url,opts)=>{calls.push(String(url));if(String(url).endsWith('/web-token'))return reply({token:'synthetic-web-token'});return fetcher(url,opts)}});
 vm.runInContext(source,context);const service=new context.Service();
 service.state.bridge={...service.state.bridge,account:auth.user,accounts:structuredClone(accounts),accountsLoaded:true,selectedRobloxUserId:'101'};
 service.accountsFetchedAt=now;
 return{service,auth,timers,sockets,calls,setNow(v){now=v},advance(ms){now+=ms},now:()=>now,
  async open(){await service.connectLive();const s=sockets.at(-1);s.readyState=1;s.onopen();return s},
  send(s,value=12){s.onmessage({data:JSON.stringify(payload(value))})},
  async tick(){const t=[...timers].find(([,v])=>v.delay===6000);assert(t,'Missing poll timer');timers.delete(t[0]);now+=6000;await t[1].fn();await settle()}};
}
async function check(name,fn){await fn();checks.push(name);console.log('PASS '+name)}
await check('late persisted stale response cannot overwrite newer live counters or Connected',async()=>{
 const body=deferred();const f=fixture(async()=>({ok:true,json:()=>body.promise}));const socket=await f.open();
 const pending=f.service.pollOnce();await settle();f.send(socket,12);body.resolve(envelope(false));await pending;
 assert.equal(f.service.state.connection.label,'Connected');assert.equal(f.service.state.live.details.compost.seedsFed,12);assert.equal(f.service.selectedAccount().online,true);
 f.service.disconnectAccount();assert.equal(f.timers.size,0);
});
await check('late HTTP failure cannot downgrade a stream that recovered during the request',async()=>{
 const body=deferred();const f=fixture(async()=>body.promise);const s=await f.open();const pending=f.service.pollOnce();await settle();f.send(s);body.reject(new Error('Old API outage'));await pending;
 assert.equal(f.service.state.connection.label,'Connected');assert.equal(f.service.state.bridge.error,null);f.service.disconnectAccount();
});
await check('healthy live data wins over an older API snapshot already pending at account lookup',async()=>{
 const f=fixture(async()=>reply(envelope(false)));const s=await f.open();f.send(s,20);await f.service.pollOnce();
 assert.equal(f.service.state.connection.label,'Connected');assert.equal(f.service.state.live.details.compost.seedsFed,20);f.service.disconnectAccount();
});
await check('stalled OPEN socket is replaced automatically and telemetry recovers without reload',async()=>{
 const f=fixture(async()=>reply(envelope(false)));const old=await f.open();f.send(old);f.service.startPolling();
 for(let i=0;i<6;i++)await f.tick();
 assert(old.closed,'Stalled socket stayed open indefinitely');assert.equal(f.sockets.length,2);
 const fresh=f.sockets[1];fresh.readyState=1;fresh.onopen();f.send(fresh,27);
 assert.equal(f.service.state.connection.label,'Connected');assert.equal(f.service.state.live.details.compost.seedsFed,27);assert.equal(f.service.selectedAccount().online,true);
 f.service.disconnectAccount();assert.equal(f.timers.size,0);
});
await check('healthy stream avoids extra snapshot requests and never reconnects',async()=>{
 const f=fixture(async()=>reply(envelope(false)));const s=await f.open();f.send(s);f.service.startPolling();
 for(let i=0;i<8;i++){f.send(s,i+1);await f.tick()}
 assert.equal(f.sockets.length,1);assert.equal(f.calls.filter(x=>x.includes('/runtime/snapshot')).length,0);f.service.disconnectAccount();
});
await check('online flag can return false when genuine stale HTTP data is the only source',async()=>{
 const f=fixture(async()=>reply(envelope(false)));f.service.state.bridge.accounts[0].online=true;await f.service.pollOnce();
 assert.equal(f.service.state.connection.label,'Runtime stale');assert.equal(f.service.selectedAccount().online,false);f.service.disconnectAccount();
});
await check('account-list refresh cannot mark selected healthy live account offline',async()=>{
 const f=fixture(async()=>reply({accounts}));const s=await f.open();f.send(s);await f.service.refreshAccounts(0,true);
 assert.equal(f.service.selectedAccount().online,true);assert.equal(f.service.state.bridge.accounts[1].online,false);f.service.disconnectAccount();
});
await check('switch invalidates the old stream and late callbacks cannot restore its account',async()=>{
 const f=fixture(async()=>reply({account:accounts[1],online:false,snapshot:null}));const s=await f.open();const callback=s.onmessage;
 await f.service.selectRobloxAccount('202');callback({data:JSON.stringify(payload(99))});
 assert.equal(f.service.state.bridge.selectedRobloxUserId,'202');assert.equal(f.service.state.live,null);f.service.disconnectAccount();
});
await fs.writeFile(new URL('runtime-stream-recovery-results.json',import.meta.url),JSON.stringify({passed:checks.length,checks,scope:'Actual runtime service with held HTTP, WebSocket callbacks and controlled timer ticks; no browser, game or cloud data.'},null,2)+'\n');
