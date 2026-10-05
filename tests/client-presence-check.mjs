import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';

const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const source=(await fs.readFile(new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url),'utf8')).replaceAll('\r\n','\n');
function section(first,last){const a=source.indexOf(first),b=source.indexOf(last,a);assert(a>=0&&b>a);return source.slice(a,b);}
const functions=section('function AroynWeb.CleanExecutorText(','function AroynWeb.VerifyKey(')+
 section('function AroynWeb.DisconnectPresence()','function AroynWeb.Stop(')+
 section('function AroynWeb.Start()','function AroynWeb.LinkKey(')+
 section('function AroynWeb.Unlink()','function AroynWeb.CopyKey(');
const prelude=String.raw`
local AroynWeb={}
local state={running=true,generation=1}
local env={}
local identifyexecutor=function()return 'Potassium','fixture-version' end
local LocalPlayer={UserId=900002}
local game={GameId=10440833423,PlaceId=74102906764176}
local verificationOnly=true
local HttpService={GenerateGUID=function() return string.rep('a',32) end}
local activities,requests,queue,waits={}, {}, {}, {}
local response,decoded,failRequest,verifyOk
local task={spawn=function(fn) local co=coroutine.create(fn);table.insert(queue,co);return co end,
 wait=function(seconds) table.insert(waits,seconds);coroutine.yield() end}
local function addActivity(...) table.insert(activities,{...}) end
local function pass(name) print('PASS '..name) end
`+functions+String.raw`
local actual=table.clone(AroynWeb)
local function reset(key)
 state.running=true;state.generation+=1;env={};requests={};queue={};waits={};activities={}
 response={StatusCode=200,Body='fixture'};decoded={presenceToken='signed-fixture',dashboardLinked=false,heartbeatSeconds=300}
 failRequest=false;verifyOk=true
 AroynWeb=table.clone(actual);AroynWeb.key=key;AroynWeb.sessionId='local-presence-fixture';AroynWeb.clientVersion='fixture'
 AroynWeb.liveHttpBase='https://live.example.test';AroynWeb.presenceIntervalSeconds=300
 AroynWeb.ValidKey=function(value) return value=='valid-key' end
 AroynWeb.NormalizeKey=function(value) return tostring(value or '') end
 AroynWeb.ResolveWebSocketConnect=function() return nil end
 AroynWeb.ResolveRequest=function() return function(options)
  if failRequest then error('network unavailable') end
  table.insert(requests,options);return response
 end end
 AroynWeb.EncodePayload=function(body) return true,body end
 AroynWeb.ParseResponseBody=function() return decoded end
 AroynWeb.DeviceType=function() return 'desktop' end
 AroynWeb.LoadConfig=function() end;AroynWeb.SaveConfig=function() end
 AroynWeb.StartUpdateWatch=function() end
 AroynWeb.VerifyKey=function() if verifyOk then return true,{displayName='fixture'} end;return false,'expired' end
 AroynWeb.PushOnce=function() end;AroynWeb.Stop=function() AroynWeb.thread=nil end
end
reset(nil);assert(AroynWeb.PresenceHttpOnce());assert(#requests==1 and requests[1].Headers.Authorization==nil)
assert(requests[1].Body.executorName=='Potassium' and requests[1].Body.executorVersion=='fixture-version')
assert(requests[1].Body.robloxUserId=='900002' and requests[1].Body.gameSlug=='greedy-growers')
assert(AroynWeb.presenceToken=='signed-fixture' and not AroynWeb.presenceDashboardLinked)
pass('unlinked runtime sends only basic presence without dashboard authorization')
assert(AroynWeb.PresenceHttpOnce());assert(requests[2].Headers['X-Presence-Token']=='signed-fixture')
pass('unlinked heartbeat retains the signed presence token')
reset(nil);AroynWeb.Start();assert(AroynWeb.presenceThread and not AroynWeb.thread)
assert(coroutine.resume(AroynWeb.presenceThread));assert(#requests==1 and waits[1]==5)
state.running=false;assert(coroutine.resume(AroynWeb.presenceThread));assert(AroynWeb.presenceThread==nil and #requests==1)
pass('startup starts unlinked presence; loop stops with the client')
reset(nil);AroynWeb.StartPresence();AroynWeb.StartPresence();assert(#queue==1)
pass('repeat startup does not create duplicate presence loops')
reset('valid-key');AroynWeb.Start();assert(AroynWeb.thread and not AroynWeb.presenceThread)
pass('linked startup keeps presence behind successful HTTP bootstrap')
reset('valid-key');verifyOk=false;AroynWeb.Start();assert(AroynWeb.presenceThread and not AroynWeb.thread)
pass('expired saved dashboard credential does not hide the running script')
reset('valid-key');decoded.dashboardLinked=true;decoded.heartbeatSeconds=45
assert(AroynWeb.PresenceHttpOnce());assert(requests[1].Headers.Authorization=='Bearer valid-key')
assert(AroynWeb.presenceDashboardLinked and AroynWeb.presenceIntervalSeconds==45)
pass('linked runtime keeps authorization and the server heartbeat cadence')
AroynWeb.key=nil;decoded.dashboardLinked=false;decoded.heartbeatSeconds=300
assert(AroynWeb.PresenceHttpOnce());assert(requests[2].Headers.Authorization==nil and requests[2].Headers['X-Presence-Token']=='signed-fixture')
assert(not AroynWeb.presenceDashboardLinked and AroynWeb.presenceIntervalSeconds==300)
pass('unlink retains runtime presence while removing dashboard authorization')
reset(nil);AroynWeb.presenceToken='signed-fixture';assert(AroynWeb.DisconnectPresence())
assert(requests[1].Url:find('/disconnect',1,true) and requests[1].Headers.Authorization==nil)
assert(requests[1].Headers['X-Presence-Token']=='signed-fixture')
pass('unlinked stop uses signed disconnect without dashboard key')
reset(nil);response.StatusCode=503;assert(not AroynWeb.PresenceHttpOnce() and not AroynWeb.presenceLastOk)
response.StatusCode=200;assert(AroynWeb.PresenceHttpOnce() and AroynWeb.presenceLastError==nil)
failRequest=true;assert(not AroynWeb.PresenceHttpOnce())
pass('failed presence remains visible and retryable')
`;
const runtime=await luauTestRuntime();
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-presence-'));const file=path.join(dir,'check.luau');
await fs.writeFile(file,prelude);
const compile=spawnSync(runtime.compiler,['--null',file],{encoding:'utf8'});assert.equal(compile.status,0,compile.stderr);
const run=spawnSync(runtime.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);
const checks=run.stdout.split(/\r?\n/).filter(x=>x.startsWith('PASS '));assert.equal(checks.length,10);
console.log(run.stdout.trim());
await fs.writeFile(new URL('client-presence-results.json',import.meta.url),JSON.stringify({version:manifest.version,passed:checks.length,checks:checks.map(x=>x.slice(5)),scope:'Actual client presence/start/disconnect functions on Luau CLI with stubbed transport; no game or production sessions.'},null,2)+'\n');
