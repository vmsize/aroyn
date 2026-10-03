import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const src=(await fs.readFile(new URL('../apps/dashboard/releases/4.3.86/greedy-growers.luau',import.meta.url),'utf8')).replaceAll('\r\n','\n');
const cut=(a,b)=>{const i=src.indexOf(a),j=src.indexOf(b,i+1);if(i<0||j<0)throw Error('Extraction failed');return src.slice(i,j)};
const functions=cut('function FarmRuntime.featureOperationToken(', 'function FarmRuntime.beginCompostTeleport(')+cut('function FarmRuntime.schedulePetSeedWorker()','function FarmRuntime.isLeafPile(')+cut('function FarmRuntime.scheduleLeafWorker()','function FarmRuntime.clearOwnPlotConnections()')+cut('function FarmRuntime.invalidatePetSeedQueue()','function FarmRuntime.petSeedEligibility(')+cut('function FarmRuntime.invalidateLeafQueue()','function FarmRuntime.leafEligibility(');
const harness=String.raw`
local jobs,now,calls={},0,0
local task={defer=function(fn) jobs[#jobs+1]=coroutine.create(fn) end,delay=function() end,wait=function(t) return coroutine.yield(t) end}
local os={clock=function() return now end}
local state,PetSeedRuntime,ui,ownPlot
local FarmRuntime={}
local PET_SEED_CONFIRM_TIMEOUT,PET_SEED_RATE_LIMIT=1,0.1
local function fireproximityprompt() calls+=1 end
local function addActivity() end
local function scheduleSettingsSave() end
`+functions+String.raw`
for _,kind in ipairs({'pet','leaf'}) do
 for _,phase in ipairs({'settle','confirmation'}) do
 for _,scenario in ipairs({'normal','disable','off-on','stop'}) do
  jobs={};now=0;calls=0;ui={};ownPlot={Name='synthetic',Parent=true}
  state={running=true,generation=1,autoCollectPetSeeds=true,autoCollectLeaves=true,petSeedAttempts=0,petSeedErrors=0,leafAttempts=0,leafErrors=0,petSeedsCollected=0,leavesCollected=0}
  local instance={Parent=ownPlot};local prompt={Parent=instance,Enabled=true}
  PetSeedRuntime={revision=1,queue={{instance=instance}},queued={},claimed={},retryAfter={},secondConfirmTimeout=.2,retryCooldown=1}
  FarmRuntime.LeafRuntime={revision=1,queue={{instance=instance}},queued={},claimed={},retryAfter={},CONFIRM_TIMEOUT=1}
  FarmRuntime.AutomationRuntime={}
  FarmRuntime.acquireAutomation=function(kind) FarmRuntime.AutomationRuntime.owner=kind;FarmRuntime.AutomationRuntime.since=now;return true end;FarmRuntime.releaseAutomation=function() FarmRuntime.AutomationRuntime.owner=nil end
  FarmRuntime.petSeedEligibility=function() return true,prompt end;FarmRuntime.leafEligibility=function() return true,prompt end
  FarmRuntime.inferPetSeedName=function() return nil end;FarmRuntime.inferPetDropName=function() return 'synthetic drop' end
  FarmRuntime.findLeafPrompt=function() return prompt end;FarmRuntime.findPetSeedPrompt=function() return prompt end
  FarmRuntime.setPetSeedStatus=function() end;FarmRuntime.setLeafStatus=function() end
  FarmRuntime.equipLeafRake=function() return true end
  FarmRuntime.beginPetSeedTeleport=function() task.wait(.28);return {} end
  FarmRuntime.beginLeafTeleport=function() task.wait(.28);return {} end
  FarmRuntime.finishPetSeedTeleport=function() end;FarmRuntime.finishLeafTeleport=function() end
  FarmRuntime.scanPetSeeds=function() end;FarmRuntime.scanLeaves=function() end
  local schedule=kind=='pet' and FarmRuntime.schedulePetSeedWorker or FarmRuntime.scheduleLeafWorker
  local toggle=kind=='pet' and FarmRuntime.setAutoCollectPetSeeds or FarmRuntime.setAutoCollectLeaves
  schedule();local co=jobs[1];local ok,delay=coroutine.resume(co);assert(ok,tostring(delay));assert(delay==.28)
  if phase=='confirmation' then ok,delay=coroutine.resume(co);assert(ok and delay==.05 and calls==1) end
  if scenario=='disable' or scenario=='off-on' then toggle(false) end
  if scenario=='off-on' then toggle(true) end
  if scenario=='stop' then state.running=false;state.generation+=1 end
  if scenario~='normal' and phase=='confirmation' then instance.Parent=nil end
  local before=calls
  repeat now+=.1;ok,delay=coroutine.resume(co);assert(ok,tostring(delay)) until coroutine.status(co)=='dead'
  assert(calls==(scenario=='normal' and (kind=='pet' and 2 or 1) or before));assert(state.petSeedsCollected==0 and state.leavesCollected==0)
  if scenario~='normal' then local rt=kind=='pet' and PetSeedRuntime or FarmRuntime.LeafRuntime;assert(rt.claimed[instance]==nil) end
  print('PASS '..kind..' '..phase..' '..scenario..' promptCalls='..calls)
 end
 end
end
`;
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-stage23-neighbor-')),file=path.join(dir,'neighbors.luau');await fs.writeFile(file,harness);
const rt=await luauTestRuntime(),result=spawnSync(rt.runtime,[file],{encoding:'utf8',timeout:30000});if(result.status!==0)throw Error(result.stderr+'\n'+result.stdout);
const cleanupFunctions=cut('function FarmRuntime.acquireAutomation(kind)','function FarmRuntime.releaseAutomation(kind)')+cut('function FarmRuntime.featureOperationToken(', 'function FarmRuntime.triggerCompostPrompt(')+cut('function FarmRuntime.beginPetSeedTeleport(', 'function FarmRuntime.petSeedEligibility(')+cut('function FarmRuntime.beginLeafTeleport(', 'function FarmRuntime.leafEligibility(');
const cleanupHarness=String.raw`
local now,state,CompostRuntime,PetSeedRuntime,LocalPlayer,ownPlot,root
local task={wait=function(t) return coroutine.yield(t) end}
local os={clock=function() return now end}
local Vector3={zero=0,new=function() return 0 end}
local CFrame={}
function CFrame.new() return setmetatable({Position=0,syntheticCFrame=true},{__mul=function() return CFrame.new() end}) end
local function typeof(value) return type(value)=='table' and value.syntheticCFrame and 'CFrame' or type(value) end
local FarmRuntime={}
local PET_SEED_TELEPORT_SETTLE=.28
local App,AroynWeb={}, {Stop=function() task.wait(.2) end}
local saveRevision=0
local function saveSettingsNow() end
`+cleanupFunctions+cut('function App.Destroy()', 'if type(env.__FA_STARTUP_EMIT) == "function" then pcall(env.__FA_STARTUP_EMIT, "MAIN 06')+String.raw`
local function reset()
 now=0;state={running=true,generation=1,autoCompostEnabled=true,autoCollectPetSeeds=true,autoCollectLeaves=true}
 root={Parent=true,CFrame='home',AssemblyLinearVelocity=2,AssemblyAngularVelocity=3}
 LocalPlayer={Character={FindFirstChild=function() return root end}}
 ownPlot={Parent=true};local target={Parent=true,Position=0,CFrame=CFrame.new(),IsA=function() return true end,GetPivot=function(self) return self.CFrame end}
 CompostRuntime={workerRevision=1,bin={},compostPart=target,claimed={}};PetSeedRuntime={revision=1,claimed={}}
 FarmRuntime.LeafRuntime={revision=1,TELEPORT_SETTLE=.28,claimed={}};FarmRuntime.AutomationRuntime={};FarmRuntime.teleportOwner=nil
 FarmRuntime.findPetSeedTarget=function() return target end;FarmRuntime.findLeafTargetPart=function() return target end
 FarmRuntime.automationBlockedByHigherPriority=function() return false end
 FarmRuntime.releaseAutomation=function(kind) if FarmRuntime.AutomationRuntime.owner==kind then FarmRuntime.AutomationRuntime.owner=nil end end
end
local function helpers(kind)
 if kind=='compost' then return FarmRuntime.beginCompostTeleport,FarmRuntime.finishCompostTeleport,function() return CompostRuntime.batchTeleportTicket end end
 if kind=='pet' then return function(token) return FarmRuntime.beginPetSeedTeleport({}, {}, token) end,FarmRuntime.finishPetSeedTeleport,function() return PetSeedRuntime.activeTicket end end
 return function(token) return FarmRuntime.beginLeafTeleport({}, {}, token) end,FarmRuntime.finishLeafTeleport,function() return FarmRuntime.LeafRuntime.activeTicket end
end
for _,kind in ipairs({'compost','pet','leaf'}) do
 for _,scenario in ipairs({'normal','disable','off-on','stop','watchdog','destroy'}) do
  reset();local begin,finish,active=helpers(kind);local old=FarmRuntime.featureOperationToken(kind);assert(FarmRuntime.acquireFeatureOperation(old))
  assert(FarmRuntime.acquireFeatureOperation(old),'same leaf batch must retain its own slot')
  local claimRuntime=kind=='compost' and CompostRuntime or kind=='pet' and PetSeedRuntime or FarmRuntime.LeafRuntime
  local instance={};claimRuntime.claimed[instance]=old;old.claimRuntime=claimRuntime;old.claimInstance=instance
  local co=coroutine.create(function() return begin(old) end);local ok,delay=coroutine.resume(co);assert(ok,tostring(delay));assert(delay==.28);local ticket=active();assert(ticket and root.CFrame~='home')
  if scenario=='normal' then
   local returned;ok,returned=coroutine.resume(co);assert(ok and returned==ticket);finish(ticket);assert(root.CFrame=='home');root.CFrame='new-position';finish(ticket);assert(root.CFrame=='new-position')
  else
   if scenario=='destroy' then local dying=coroutine.create(App.Destroy);ok,delay=coroutine.resume(dying);assert(ok,tostring(delay));assert(delay==.2 and state.stopping and not state.running and ticket.finished and root.CFrame=='home')
   elseif scenario=='watchdog' then now=11;assert(FarmRuntime.acquireAutomation('buy'));assert(old.cancelled);assert(not FarmRuntime.featureOperationCurrent(old));FarmRuntime.releaseAutomation('buy')
   else
    if kind=='compost' then state.autoCompostEnabled=false;CompostRuntime.workerRevision+=1
    elseif kind=='pet' then state.autoCollectPetSeeds=false;PetSeedRuntime.revision+=1
    else state.autoCollectLeaves=false;FarmRuntime.LeafRuntime.revision+=1 end
    if scenario=='stop' then state.stopping=true;state.running=false;state.generation+=1 end
    finish(ticket);FarmRuntime.releaseFeatureOperation(old)
   end
   assert(root.CFrame=='home' and ticket.finished)
   state.running=true;state.stopping=false;state.autoCompostEnabled=true;state.autoCollectPetSeeds=true;state.autoCollectLeaves=true
   local current=FarmRuntime.featureOperationToken(kind);assert(FarmRuntime.acquireFeatureOperation(current))
   assert(claimRuntime.claimed[instance]==nil);claimRuntime.claimed[instance]=current
   local nextCo=coroutine.create(function() return begin(current) end);ok,delay=coroutine.resume(nextCo);assert(ok and delay==.28)
   local nextTicket,nextPosition=active(),root.CFrame;assert(nextTicket~=ticket)
   ok=coroutine.resume(co);assert(ok);assert(active()==nextTicket and root.CFrame==nextPosition and FarmRuntime.AutomationRuntime.operation==current)
   finish(ticket);FarmRuntime.releaseFeatureOperation(old);assert(active()==nextTicket and root.CFrame==nextPosition and FarmRuntime.AutomationRuntime.operation==current and claimRuntime.claimed[instance]==current)
   ok=coroutine.resume(nextCo);assert(ok);finish(nextTicket);FarmRuntime.releaseFeatureOperation(current);assert(root.CFrame=='home')
  end
  print('PASS real '..kind..' teleport '..scenario..' cleanup preserves ownership')
 end
end
`;
const cleanupFile=path.join(dir,'cleanup.luau');await fs.writeFile(cleanupFile,cleanupHarness);
const cleanup=spawnSync(rt.runtime,[cleanupFile],{encoding:'utf8',timeout:30000});if(cleanup.status!==0)throw Error(cleanup.stderr+'\n'+cleanup.stdout);
const output={at:new Date().toISOString(),luauVersion:rt.version,scope:'Actual worker, toggle, invalidation, arbiter and teleport/cleanup functions. Stubbed Roblox objects and remotes; deterministic settle/confirmation waits and watchdog expiration; no game execution.',observations:(result.stdout.trim()+'\n'+cleanup.stdout.trim()).split(/\r?\n/)};
await fs.writeFile(new URL('neighbor-cancellation-results.json',import.meta.url),JSON.stringify(output,null,2));console.log(JSON.stringify(output,null,2));
