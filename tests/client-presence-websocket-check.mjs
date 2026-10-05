import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const source=(await fs.readFile(new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url),'utf8')).replaceAll('\r\n','\n');
function section(a,b){const x=source.indexOf(a),y=source.indexOf(b,x);assert(x>=0&&y>x);return source.slice(x,y);}
const functions=section('function AroynWeb.CleanExecutorText(','function AroynWeb.VerifyKey(')+section('function AroynWeb.DisconnectPresence()','function AroynWeb.Stop(');
const script=String.raw`
local AroynWeb,env={},{}
local state={running=true,generation=1}
local identifyexecutor=function()return 'Potassium','fixture-version' end
local LocalPlayer={UserId=900002}
local game={GameId=10440833423,PlaceId=74102906764176}
local clock=10
local os={clock=function() return clock end,time=function() return 1000+math.floor(clock) end}
local task={wait=function(s) clock+=s end,spawn=function(fn) return coroutine.create(fn) end}
local jsonFixtures={}
local HttpService={GenerateGUID=function()return string.rep('a',32) end,UrlEncode=function(_,s)return s end,JSONDecode=function(_,s)return jsonFixtures[s] end}
local requests,sockets={},{}
local mode='working'
local function signal()
 local s={callbacks={}}
 function s:Connect(fn)
  local c={active=true,fn=fn};self.callbacks[#self.callbacks+1]=c
  function c:Disconnect()self.active=false end
  return c
 end
 function s:Fire(data)
  if type(data)=='table' then local text=tostring(data);jsonFixtures[text]=data;data=text end
  for _,c in ipairs(self.callbacks) do if c.active then c.fn(data) end end
 end
 return s
end
local function pass(s) print('PASS '..s) end
`+functions+String.raw`
local actual=table.clone(AroynWeb)
local function reset(key)
 clock=10;requests={};sockets={};mode='working';state.running=true;state.generation+=1
 AroynWeb=table.clone(actual);AroynWeb.key=key;AroynWeb.sessionId='local-ws-client';AroynWeb.clientVersion='fixture'
 AroynWeb.liveHttpBase='https://live.example.test';AroynWeb.liveWsBase='wss://live.example.test'
 AroynWeb.ValidKey=function(k)return k=='valid-key' end
 AroynWeb.NormalizeKey=function(k)return tostring(k or '') end
 AroynWeb.DeviceType=function()return 'desktop' end
 AroynWeb.EncodePayload=function(p)return true,p end
 AroynWeb.ParseResponseBody=function(r)return r.Body end
 AroynWeb.ResolveRequest=function()return function(options)
  requests[#requests+1]=options
  return {StatusCode=200,Body={ok=true,presenceToken='http-token',dashboardLinked=options.Headers.Authorization~=nil,heartbeatSeconds=300}}
 end end
 AroynWeb.ResolveWebSocketConnect=function()
  if mode=='unsupported' then return nil end
  return function(url)
   if mode=='connect-error' then error('not supported') end
   local socket={url=url,OnMessage=signal(),OnClose=signal(),sent={}}
   function socket:Send(body)
    if mode=='send-error' then error('send failed') end
    self.sent[#self.sent+1]=body
    if body.type=='presence_disconnect' then self.OnMessage:Fire({type='presence_disconnected',ok=true,sequence=body.sequence});return end
    if mode=='stop' then state.running=false;return end
    if mode=='silent' then return end
    if mode=='reject' then self.OnMessage:Fire({type='presence_error',sequence=body.sequence,status=401});return end
    self.OnMessage:Fire({type='presence_ack',ok=true,sequence=body.sequence,presenceToken='ws-token',dashboardLinked=body.dashboardKey~=nil,heartbeatSeconds=300})
   end
   function socket:Close()self.closed=true;self.OnClose:Fire() end
   sockets[#sockets+1]=socket;return socket
  end
 end
end
reset(nil);assert(AroynWeb.PresenceOnce());assert(#requests==0 and #sockets==1)
assert(sockets[1].sent[1].executorName=='Potassium' and sockets[1].sent[1].executorVersion=='fixture-version')
assert(AroynWeb.presenceToken=='ws-token' and AroynWeb.presenceTransport=='websocket')
assert(sockets[1].sent[1].dashboardKey==nil and not sockets[1].url:find('token',1,true))
pass('unlinked first send uses acknowledged WebSocket without HTTPS or URL credentials')
clock+=5;assert(AroynWeb.PresenceOnce());assert(#requests==0 and #sockets[1].sent==1)
clock+=300;assert(AroynWeb.PresenceOnce());assert(#sockets[1].sent==2 and sockets[1].sent[2].presenceToken=='ws-token')
pass('healthy socket uses sparse signed heartbeats rather than HTTP polling')
reset(nil);mode='unsupported';assert(AroynWeb.PresenceOnce());assert(#requests==1 and #sockets==0)
assert(requests[1].Body.executorName=='Potassium' and requests[1].Body.executorVersion=='fixture-version')
clock+=5;assert(AroynWeb.PresenceOnce());assert(#requests==1)
clock+=300;assert(AroynWeb.PresenceOnce());assert(#requests==2 and requests[2].Headers['X-Presence-Token']=='http-token')
pass('executor without WebSocket uses signed HTTPS at the normal cadence')
reset(nil);mode='connect-error';assert(AroynWeb.PresenceOnce());assert(#requests==1 and AroynWeb.presenceRetryAt>clock)
pass('connection error uses HTTPS and bounded reconnect backoff')
reset(nil);mode='silent';assert(AroynWeb.PresenceOnce());assert(clock>=15 and #requests==1 and sockets[1].closed)
pass('missing ACK times out and falls back to HTTPS')
reset(nil);mode='send-error';assert(AroynWeb.PresenceOnce());assert(#requests==1 and sockets[1].closed)
pass('WebSocket send failure immediately falls back to HTTPS')
reset(nil);mode='reject';assert(AroynWeb.PresenceOnce());assert(#requests==1 and sockets[1].closed)
pass('server rejection never marks the socket healthy')
reset(nil);assert(AroynWeb.PresenceOnce());local old=sockets[1]
old.OnClose:Fire();mode='unsupported';assert(AroynWeb.PresenceOnce());assert(#requests==1 and AroynWeb.presenceTransport=='https')
mode='working';clock+=10;assert(AroynWeb.PresenceOnce());assert(#sockets==2 and #requests==1 and sockets[2].sent[1].presenceToken=='http-token')
pass('connection loss fails over and recovers using the same signed session')
old.OnMessage:Fire({type='presence_ack',ok=true,sequence=AroynWeb.presenceSequence,presenceToken='obsolete',heartbeatSeconds=15})
assert(AroynWeb.presenceToken=='ws-token')
pass('retired socket events cannot overwrite recovered state')
reset('valid-key');AroynWeb.liveSocket={};AroynWeb.liveConnected=true;AroynWeb.liveLastAckAt=os.time()
assert(AroynWeb.PresenceOnce());assert(#requests==1 and #sockets==0 and AroynWeb.presenceTransport=='live-websocket')
assert(AroynWeb.PresenceOnce());assert(#requests==1)
clock+=31;assert(AroynWeb.PresenceOnce());assert(#sockets==1)
pass('linked presence reuses fresh telemetry ACKs and recovers if they become stale')
reset('valid-key');assert(AroynWeb.PresenceOnce());assert(sockets[1].sent[1].dashboardKey=='valid-key')
AroynWeb.key=nil;clock+=5;assert(AroynWeb.PresenceOnce());assert(sockets[1].sent[2].dashboardKey==nil and not AroynWeb.presenceDashboardLinked)
pass('link changes update the same socket without URL keys')
reset(nil);assert(AroynWeb.PresenceOnce());assert(AroynWeb.DisconnectPresence())
assert(sockets[1].closed and sockets[1].sent[2].type=='presence_disconnect' and #requests==0)
pass('normal stop sends signed WebSocket disconnect and clears handlers')
reset(nil);mode='unsupported';assert(AroynWeb.PresenceOnce());assert(AroynWeb.DisconnectPresence());assert(#requests==2 and requests[2].Url:find('/disconnect',1,true))
pass('HTTPS-only executors retain signed stop')
reset(nil);mode='stop';assert(not AroynWeb.PresenceOnce());assert(#requests==0)
pass('stop during handshake prevents later HTTPS writes')
`;
const rt=await luauTestRuntime(),dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-presence-ws-')),file=path.join(dir,'check.luau');await fs.writeFile(file,script);
const compiled=spawnSync(rt.compiler,['--null',file],{encoding:'utf8'});assert.equal(compiled.status,0,compiled.stderr);
const run=spawnSync(rt.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);
const checks=run.stdout.split(/\r?\n/).filter(x=>x.startsWith('PASS ')).map(x=>x.slice(5));assert.equal(checks.length,14);console.log(run.stdout.trim());
await fs.writeFile(new URL('client-presence-websocket-results.json',import.meta.url),JSON.stringify({version:manifest.version,passed:checks.length,checks,scope:'Actual release Luau functions with fake clock/socket signals and HTTPS; no game execution.'},null,2)+'\n');
