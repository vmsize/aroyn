import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const sourcePath=new URL('../apps/dashboard/releases/4.3.83/greedy-growers.luau',import.meta.url);
const bytes=await fs.readFile(sourcePath),source=bytes.toString('utf8').replaceAll('\r\n','\n');
function between(a,b){const start=source.indexOf(a);const end=source.indexOf(b,start);if(start<0||end<0)throw new Error('Missing extraction boundary');return source.slice(start,end);}
// Extract the setter through its next function declaration; no rewritten product function.
const setterStart=source.indexOf('function FarmRuntime.setAutoCompost(value, explicitStatus)');
const setterEnd=source.indexOf('\nfunction FarmRuntime.',setterStart+1);
const feature=between('function FarmRuntime.featureOperationToken(', 'function FarmRuntime.beginCompostTeleport(');
const actual=feature+between('function FarmRuntime.waitForCompostProgressChange(', 'function FarmRuntime.setCompostStatus(')+between('function FarmRuntime.compostFeedStep(token)', 'function FarmRuntime.scheduleCompostWorker()')+source.slice(setterStart,setterEnd);
const harness=String.raw`
local state,FarmRuntime,CompostRuntime,ui,calls,now
local COMPOST_CAPACITY,COMPOST_CONFIRM_TIMEOUT=100,1
local task={wait=function(t) return coroutine.yield(t) end}
local os={clock=function() return now end}
local function fireproximityprompt() end
local function addActivity() end
local function scheduleSettingsSave() end
FarmRuntime={}
`+actual+String.raw`
local function reset()
 state={running=true,generation=1,autoCompostEnabled=true,compostAttempts=0,compostConfirmedActions=0,compostSeedsFed=0,wormsGranted=0}
 now=0;calls=0;ui={};FarmRuntime.AutomationRuntime={};CompostRuntime={workerRevision=1,workerScheduled=true,prompt={Parent=true,Enabled=true,ActionText='Give Seed'}}
 FarmRuntime.refreshCompostRefs=function() return true end
 FarmRuntime.getCompostProgress=function() return calls>0 and 1 or 0,100 end
 FarmRuntime.setCompostStatus=function(s) state.compostStatus=s end
 FarmRuntime.ensureCompostTeleport=function() return {} end
 FarmRuntime.releaseCompostTeleport=function() end
 FarmRuntime.scheduleCompostWorker=function() end
 FarmRuntime.findSelectedCompostStack=function() return {key='Oak',id='synthetic'} end
 FarmRuntime.equipCompostStack=function() return true end
 FarmRuntime.triggerCompostPrompt=function() calls+=1;return true end
end
for _,scenario in ipairs({'normal','disable','off-on','stop'}) do
 reset();local co=coroutine.create(FarmRuntime.compostFeedStep)
 local ok,delay=coroutine.resume(co);assert(ok,tostring(delay));assert(delay==0.1)
 if scenario=='disable' or scenario=='off-on' then FarmRuntime.setAutoCompost(false) end
 if scenario=='off-on' then FarmRuntime.setAutoCompost(true) end
 if scenario=='stop' then state.running=false;state.generation+=1 end
 ok=coroutine.resume(co);assert(ok);assert(calls==(scenario=='normal' and 1 or 0));assert(state.compostConfirmedActions==(scenario=='normal' and 1 or 0))
 print('PASS '..scenario..' promptCalls='..calls..' confirmed='..state.compostConfirmedActions..' status='..tostring(state.compostStatus))
end
for _,phase in ipairs({'feed-teleport','feed-equip','feed-replication','feed-confirmation','collect-teleport','collect-confirmation'}) do
 for _,scenario in ipairs({'disable','off-on','stop'}) do
  reset();local collect=phase:find('collect',1,true)~=nil
  if collect then CompostRuntime.prompt.ActionText='Collect' end
  FarmRuntime.getCompostProgress=function() return collect and 100 or 0,100 end
  FarmRuntime.ensureCompostTeleport=function() if phase:find('teleport',1,true) then task.wait(.28) end;return {} end
  FarmRuntime.equipCompostStack=function() if phase=='feed-equip' then task.wait(.08) end;return true end
  local wanted=phase:find('teleport',1,true) and .28 or phase=='feed-equip' and .08 or phase=='feed-replication' and .1 or collect and .04 or .035
  local co=coroutine.create(FarmRuntime.compostFeedStep);local ok,delay
  repeat ok,delay=coroutine.resume(co);assert(ok,tostring(delay));assert(coroutine.status(co)~='dead');now+=delay until delay==wanted
  local before=calls
  if scenario=='stop' then state.running=false;state.stopping=true;state.generation+=1
  else FarmRuntime.setAutoCompost(false);if scenario=='off-on' then FarmRuntime.setAutoCompost(true) end end
  local status=state.compostStatus
  repeat ok,delay=coroutine.resume(co);assert(ok,tostring(delay));now+=tonumber(delay) or 0 until coroutine.status(co)=='dead'
  assert(calls==before and state.compostConfirmedActions==0 and state.compostSeedsFed==0 and state.compostStatus==status)
  print('PASS '..phase..' '..scenario..' no additional send or stale confirmation')
 end
end
reset();CompostRuntime.prompt.ActionText='Collect'
FarmRuntime.getCompostProgress=function() return calls>0 and 0 or 100,100 end
assert(FarmRuntime.compostFeedStep());assert(calls==1);print('PASS normal collection remains successful')
`;
const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-stage23-'));const file=path.join(temp,'compost.luau');await fs.writeFile(file,harness);
const runtime=await luauTestRuntime();const run=spawnSync(runtime.runtime,[file],{encoding:'utf8',timeout:30000});
if(run.status!==0)throw new Error(run.stderr+'\n'+run.stdout);
const out={at:new Date().toISOString(),sourceHash:crypto.createHash('sha256').update(bytes).digest('hex'),sourceUnchanged:bytes.equals(await fs.readFile(sourcePath)),luauVersion:runtime.version,scope:'Actual feed/collection step, toggle, cancellation and progress confirmation functions; stubbed teleport/equip/prompt and deterministic yields at teleport, equip, replication and confirmation boundaries; no game connection.',observations:run.stdout.trim().split(/\r?\n/)};
await fs.writeFile(new URL('compost-cancellation-results.json',import.meta.url),JSON.stringify(out,null,2));console.log(JSON.stringify(out,null,2));
