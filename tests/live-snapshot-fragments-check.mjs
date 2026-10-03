import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {LiveSnapshotAssembler} from '../apps/dashboard/assets/js/services/live-snapshot.js';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const checks=[];const pass=name=>{checks.push(name);console.log('PASS '+name)};
const snapshot={type:'snapshot',schemaVersion:1,player:{userId:'101'},product:{version:'4.3.86'},session:{id:'test-session-001'},stats:{compostSeedsFed:12},details:{compost:{seedsFed:12},inventory:{summary:{worms:940},worms:Array.from({length:940},(_,i)=>({slot:i,displayName:'Червь 🦊 "test"',mult:i/10,mutations:['漢字'],id:'fixture-'+i+'x'.repeat(90)}))}}};
const body=JSON.stringify(snapshot);
assert(Buffer.byteLength(body)>48*1024);
const client=await fs.readFile(new URL('../apps/dashboard/releases/4.3.86/greedy-growers.luau',import.meta.url),'utf8');
const code=client.slice(client.indexOf('function AroynWeb.BuildLiveMessages('),client.indexOf('function AroynWeb.Request('));
const prelude=String.raw`
local snapshot={type='snapshot',schemaVersion=1,player={userId='101'},product={version='4.3.86'},session={id='test-session-001'}}
local body=[==[`+body+String.raw`]==]
local function quote(s)
 return '"'..s:gsub('[%z\1-\31\\"]',function(c)
  if c=='"' then return '\\"' end
  if c=='\\' then return '\\\\' end
  return string.format('\\u%04x',string.byte(c))
 end)..'"'
end
local function encode(v)
 if type(v)=='string' then return quote(v) end
 if type(v)=='number' or type(v)=='boolean' then return tostring(v) end
 if v==nil then return 'null' end
 local out={} for k,x in pairs(v) do out[#out+1]=quote(tostring(k))..':'..encode(x) end
 return '{'..table.concat(out,',')..'}'
end
local HttpService={GenerateGUID=function() return 'fixture-transfer-001' end}
local clock=0
local os={clock=function() return clock end}
local state={running=true,generation=1}
local task={wait=function(delay) clock+=delay end}
local AroynWeb={EncodePayload=function(v)
 local text=v==snapshot and body or encode(v) return true,text,#text
end,liveConnected=true,lastPushPayloadBytes=0}
`+code+String.raw`
local ok,frames,bytes=AroynWeb.BuildLiveMessages(snapshot)
assert(ok and #frames>1 and bytes==#body)
for _,frame in ipairs(frames) do assert(#frame<=60*1024);print('FRAME '..frame) end
local sent,closed,lastSend=0,0,nil
local socket={Send=function(self,frame)
 if lastSend then assert(clock-lastSend>=0.149,'executor queue requires a yield between sends') end
 lastSend=clock;sent+=1
end,Close=function() closed+=1 end}
AroynWeb.liveSocket=socket
assert(AroynWeb.SendLiveSnapshot(snapshot));assert(sent==#frames and AroynWeb.lastPushPayloadBytes==#body)
socket.Send=function() error('transport failure') end
assert(not AroynWeb.SendLiveSnapshot(snapshot));assert(closed==1 and AroynWeb.liveSocket==nil and not AroynWeb.liveConnected)
-- An unload or socket replacement during the yield must cancel remaining parts.
for _,replacement in ipairs({false,true}) do
 sent=0;closed=0;state.running=true;state.generation=1
 local newSocket={Close=function() error('replacement socket must remain open') end}
 socket.Send=function() sent+=1 end
 AroynWeb.liveSocket=socket;AroynWeb.liveConnected=true
 task.wait=function(delay)
  clock+=delay
  if replacement then AroynWeb.liveSocket=newSocket else state.generation+=1 end
 end
 assert(not AroynWeb.SendLiveSnapshot(snapshot));assert(sent==1 and closed==1)
 if replacement then assert(AroynWeb.liveSocket==newSocket) end
end
task.wait=function(delay) clock+=delay end
state.running=true
AroynWeb.liveSocket=socket;AroynWeb.liveConnected=true
local build=AroynWeb.BuildLiveMessages
AroynWeb.BuildLiveMessages=function() local f={} for i=1,16 do f[i]='{}' end return true,f,32 end
local start=clock
assert(AroynWeb.SendLiveSnapshot(snapshot))
assert(clock-start+AroynWeb.liveNextPushDelaySeconds>=10,'16 frames must respect the minute rate budget')
AroynWeb.BuildLiveMessages=build
body=string.rep('x',256*1024+1);assert(not AroynWeb.BuildLiveMessages(snapshot))
body='{}';local good,one=AroynWeb.BuildLiveMessages(snapshot);assert(good and #one==1 and one[1]=='{}')
`;
const runtime=await luauTestRuntime(),temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-fragments-')),file=path.join(temp,'check.luau');await fs.writeFile(file,prelude);
const compile=spawnSync(runtime.compiler,['--null',file],{encoding:'utf8'});assert.equal(compile.status,0,compile.stderr);
const run=spawnSync(runtime.runtime,[file],{encoding:'utf8',maxBuffer:2*1024*1024,timeout:30000});assert.equal(run.status,0,run.stderr);
const frames=run.stdout.split(/\r?\n/).filter(s=>s.startsWith('FRAME ')).map(s=>JSON.parse(s.slice(6)));
assert(frames.length>1 && frames.length<=16);assert.equal(frames.map(x=>x.transport.data).join(''),body);
assert(frames.every(x=>Buffer.byteLength(JSON.stringify(x))<=60*1024));pass('actual Luau chunking preserves UTF-8, quotes, 940 inventory rows and counters within bounded frames');
pass('actual sender uses every frame and cleans up on send failure; oversized snapshot is rejected and small snapshot stays unchanged');
pass('actual sender yields between frames, cancels on unload/socket replacement and bounds the largest snapshot cadence');
let a=new LiveSnapshotAssembler(),result;
for(const f of [...frames].reverse()) result=a.accept(f,'101',1000)||result;
assert.deepEqual(result,snapshot);pass('out-of-order parts reassemble losslessly');
assert.equal(a.accept(frames[0],'101',1001),null);pass('completed transfer replay is ignored');
a=new LiveSnapshotAssembler();for(const f of frames.slice(1))assert.equal(a.accept(f,'101',1000),null);pass('missing part never produces partial counters or inventory');
assert.deepEqual(a.accept(frames[0],'101',1001),snapshot);pass('missing part arrival completes the same transfer');
for(const bad of [{count:17},{index:0},{bytes:262145},{data:'x'.repeat(32769)},{encoding:'unknown'}]){
 a=new LiveSnapshotAssembler();assert.equal(a.accept({...frames[0],transport:{...frames[0].transport,...bad}},'101',1000),null);assert.equal(a.pending,null);
}pass('frame count, position, byte budget and encoding are bounded');
a=new LiveSnapshotAssembler();assert.equal(a.accept(frames[0],'202',1000),null);assert.equal(a.pending,null);pass('other account fragments never enter assembly');
a=new LiveSnapshotAssembler();a.accept(frames[0],'101',1000);a.accept({...frames[0],transport:{...frames[0].transport,data:'conflicting'}},'101',1000);assert.equal(a.pending,null);pass('conflicting duplicate discards partial transfer');
a=new LiveSnapshotAssembler();a.accept(frames[0],'101',0);for(const f of frames.slice(1))assert.equal(a.accept(f,'101',16000),null);pass('expired partial transfer cannot be completed by late remaining parts');
a=new LiveSnapshotAssembler();let recovered;for(const f of frames)recovered=a.accept({...f,transport:{...f.transport,id:'next-transfer-002'}},'101',17000)||recovered;assert.deepEqual(recovered,snapshot);pass('next complete transfer recovers after expiry');
function wrapped(value,header={}){const data=JSON.stringify(value);return{...frames[0],...header,transport:{encoding:'json-fragments-v1',id:'single-transfer-003',index:1,count:1,bytes:Buffer.byteLength(data),data}}}
for(const value of [{...snapshot,player:{userId:'202'}},{...snapshot,session:{id:'different'}},{...snapshot,schemaVersion:2},{...snapshot,transport:{}}])assert.equal(new LiveSnapshotAssembler().accept(wrapped(value),'101',0),null);
pass('decoded identity, session and schema are checked before application');
await fs.writeFile(new URL('live-snapshot-fragments-results.json',import.meta.url),JSON.stringify({passed:checks.length,checks,frameCount:frames.length,logicalBytes:Buffer.byteLength(body),scope:'Actual Luau chunk builder/sender and dashboard assembler. Synthetic Unicode inventory; no game or cloud account.'},null,2)+'\n');
