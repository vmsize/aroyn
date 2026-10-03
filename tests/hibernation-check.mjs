import assert from 'node:assert/strict';
import {createHash,randomBytes} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {createRuntime} from './runtime.mjs';
import {LiveSnapshotAssembler} from '../apps/dashboard/assets/js/services/live-snapshot.js';
const runtime=await createRuntime({mock:true});
const WebSocket=createRequire(new URL('../package.json',import.meta.url))('ws');
const direct=await runtime.mf.ready; // The harness's first (public) Worker is live.
const sockets=[],checks=[];
const hash=s=>createHash('sha256').update(s).digest('hex');
const post=(token,body)=>({method:'POST',headers:{authorization:'Bearer '+token,'content-type':'application/json'},body:JSON.stringify(body)});
const api=(path,options)=>runtime.api.fetch('http://local'+path,options);
const live=(path,options)=>runtime.live.fetch('http://local'+path,options);
const pass=name=>{checks.push({name,pass:true});console.log('PASS '+name);};
async function until(test,label,timeout=6000){const begin=Date.now();while(!test()&&Date.now()-begin<timeout)await new Promise(r=>setTimeout(r,20));assert(test(),label);}
// Bound the native client's close-handshake wait: the local hibernation proxy
// forwards the server's 1008 Close frame but can keep the TCP tunnel open.
// The client does not initiate revocation; an absent server Close frame fails.
async function open(token){const url=new URL('/ws',direct);url.protocol='ws:';url.searchParams.set('token',token);const ws=new WebSocket(url,{closeTimeout:1000});const item={ws,messages:[],closed:null};ws.on('message',data=>{try{item.messages.push(JSON.parse(data));}catch{}});ws.on('close',code=>{item.closed=code});sockets.push(item);await new Promise((done,reject)=>{const timer=setTimeout(()=>reject(new Error('Socket open timeout')),6000);ws.once('open',()=>{clearTimeout(timer);done()});ws.once('error',error=>{clearTimeout(timer);reject(error)})});return item;}
async function session(id){const token='VS_'+randomBytes(32).toString('hex'),now=Date.now();await runtime.db.prepare('INSERT INTO web_sessions(token_hash,user_id,created_at,expires_at) VALUES(?1,?2,?3,?4)').bind(hash(token),id,now,now+3600000).run();return token;}
async function fixture(i){
 const now=Date.now(),id='usr_hibernation_'+i,robloxId=String(900100+i);
 await runtime.db.prepare('INSERT INTO users(id,discord_id,discord_username,discord_display_name,created_at,updated_at,last_login_at) VALUES(?1,?2,?3,?3,?4,?4,?4)').bind(id,String(900100+i),'fixture'+i,now).run();
 const token=await session(id);const key=(await (await api('/api/v2/dashboard-key/generate',post(token,{}))).json()).dashboardKey;
 const snapshot={schemaVersion:1,type:'snapshot',player:{userId:Number(robloxId),name:'fixture'+i},session:{id:'hibernation-fixture-session-'+i},cash:i*100};
 assert.equal((await api('/api/v2/runtime/push',post(key,snapshot))).status,200);
 const rt=(await (await live('/token',post(key,{robloxUserId:robloxId}))).json()).token;
 const wt=(await (await live('/web-token',post(token,{robloxUserId:robloxId}))).json()).token;
 return {id,robloxId,token,key,snapshot,rt,wt,runtime:await open(rt),viewer:await open(wt)};
}
const evict=f=>runtime.mf.unsafeEvictDurableObject('live','VeyraLiveSession',{name:`user:${f.id}:roblox:${f.robloxId}`,webSockets:'hibernate'});
async function push(f,cash){const before=f.runtime.messages.filter(m=>m.type==='relay_ack').length;f.runtime.ws.send(JSON.stringify({...f.snapshot,cash}));await until(()=>f.runtime.messages.filter(m=>m.type==='relay_ack').length>before,'runtime acknowledgment');}
try{
 const a=await fixture(1),b=await fixture(2);
 await push(a,111);await push(b,222);
 const largeBody=JSON.stringify({...a.snapshot,details:{compost:{seedsFed:12},transportFixture:'x'.repeat(180000)}});
 const largeAckCount=a.runtime.messages.filter(m=>m.type==='relay_ack').length;
 a.runtime.ws.send(largeBody);
 await until(()=>a.runtime.messages.filter(m=>m.type==='relay_ack').length>largeAckCount,'large snapshot acknowledgment');
 await until(()=>a.viewer.messages.some(m=>m.details?.compost?.seedsFed===12),'large snapshot relay');
 assert.equal(a.runtime.ws.readyState,1);pass('180 KB JSON snapshot relays with counters and acknowledgment');
 const checkpoints=await runtime.db.prepare('SELECT o.last_seen_at AS owner_at,p.last_seen_at AS presence_at FROM runtime_session_owners o JOIN runtime_presence p USING(session_id) WHERE o.session_id=?1').bind(a.snapshot.session.id).first();
 const beforeFragments=a.viewer.messages.length,chunks=[];
 for(let i=0;i<largeBody.length;i+=32768)chunks.push(largeBody.slice(i,i+32768));
 for(let i=0;i<chunks.length;i++){
  if(i===2)await evict(a);
  const beforeAck=a.runtime.messages.filter(m=>m.type==='relay_ack').length;
  a.runtime.ws.send(JSON.stringify({...a.snapshot,transport:{encoding:'json-fragments-v1',id:'native-fragment-transfer-001',index:i+1,count:chunks.length,bytes:Buffer.byteLength(largeBody),data:chunks[i]}}));
  await until(()=>a.runtime.messages.filter(m=>m.type==='relay_ack').length>beforeAck,'fragment acknowledgment');
 }
 await until(()=>a.viewer.messages.slice(beforeFragments).filter(m=>m.transport).length===chunks.length,'all fragment relays');
 const assembler=new LiveSnapshotAssembler();let assembled;
 for(const m of a.viewer.messages.slice(beforeFragments))assembled=assembler.accept(m,a.robloxId)||assembled;
 assert.deepEqual(assembled,JSON.parse(largeBody));pass('small frames preserve the full snapshot through actual relay and mid-transfer hibernation');
 assert.deepEqual(await runtime.db.prepare('SELECT o.last_seen_at AS owner_at,p.last_seen_at AS presence_at FROM runtime_session_owners o JOIN runtime_presence p USING(session_id) WHERE o.session_id=?1').bind(a.snapshot.session.id).first(),checkpoints);
 pass('fragment burst preserves coarse ownership and presence timestamp checkpoints');
 await evict(a);await evict(b);
 assert(sockets.every(s=>s.ws.readyState===1));pass('forced hibernation preserves four accepted sockets');
 const before=a.viewer.messages.length;await push(a,333);
 await until(()=>a.viewer.messages.slice(before).some(m=>m.cash===333),'relay after object recreation');pass('recreated object restores runtime/viewer attachments and relay');
 assert(!b.viewer.messages.some(m=>m.cash===333));pass('account isolation survives object recreation');
 const bRtBefore=b.runtime.messages.length;b.viewer.ws.send(JSON.stringify({...b.snapshot,cash:999}));await until(()=>b.viewer.messages.some(m=>m.type==='dashboard_ack'),'viewer role response');assert.equal(b.runtime.messages.length,bRtBefore);pass('viewer role cannot become runtime after hibernation');
 assert.equal((await api('/api/v2/auth/logout',post(a.token,{}))).status,200);await evict(a);await push(a,444);await until(()=>a.viewer.closed===1008,'revoked viewer closed');assert.equal(a.runtime.ws.readyState,1);assert(!a.viewer.messages.some(m=>m.cash===444));pass('logout after hibernation revokes viewer without leaking new data');
 const old=b.key;b.key=(await (await api('/api/v2/dashboard-key/generate',post(b.token,{confirm:true}))).json()).dashboardKey;
 await evict(b);b.runtime.ws.send(JSON.stringify({...b.snapshot,cash:555}));await until(()=>b.runtime.closed===1008,'old runtime closed');assert(!b.viewer.messages.some(m=>m.cash===555));assert.equal((await live('/token',post(old,{robloxUserId:b.robloxId}))).status,401);pass('key rotation remains revoked after object recreation');
 b.rt=(await (await live('/token',post(b.key,{robloxUserId:b.robloxId}))).json()).token;b.runtime=await open(b.rt);await evict(b);await push(b,666);await until(()=>b.viewer.messages.some(m=>m.cash===666),'new runtime relays');pass('new credential reconnects and relays after another hibernation');
 const countAck=()=>b.viewer.messages.filter(m=>m.type==='dashboard_ack').length;
 // One viewer message was already sent above. Use 59, then 60 after eviction.
 for(let i=0;i<59;i++)b.viewer.ws.send('{"type":"ping"}');await until(()=>countAck()===60,'first rate window batch');await evict(b);
 for(let i=0;i<60;i++)b.viewer.ws.send('{"type":"ping"}');await until(()=>countAck()===120,'counter restored');b.viewer.ws.send('{"type":"ping"}');await until(()=>b.viewer.closed===1008,'rate exceeded');pass('message counter survives hibernation and rejects message 121');
 a.token=await session(a.id);const wt=(await (await live('/web-token',post(a.token,{robloxUserId:a.robloxId}))).json()).token;a.viewer=await open(wt);
 await evict(a);assert.equal((await api('/api/v2/account/delete',post(a.token,{confirmation:'DELETE'}))).status,200);
 await until(()=>a.viewer.closed===1008&&a.runtime.closed===1008,'idle authorization alarm after hibernation',22000);pass('persisted alarm closes idle viewer/runtime after deletion');
 await writeFile(new URL('./hibernation-results.json',import.meta.url),JSON.stringify({date:'2026-10-01',environment:'local Miniflare 5 forced eviction with webSockets=hibernate; native ws closeTimeout=1000 bounds proxy TCP close-handshake wait; no real accounts',checks,passed:true,cloudHibernationObserved:false},null,2)+'\n');
}finally{console.log(JSON.stringify({socketDiagnostics:sockets.map(s=>({closed:s.closed,readyState:s.ws.readyState,messages:s.messages.length}))}));for(const s of sockets)try{s.ws.close()}catch{}await runtime.mf.dispose();}
