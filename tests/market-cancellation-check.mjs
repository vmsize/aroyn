import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const root=fileURLToPath(new URL('../',import.meta.url));
const candidate=path.join(root,'apps/dashboard/releases/4.3.82/greedy-growers.luau');
const source=(await fs.readFile(candidate,'utf8')).replaceAll('\r\n','\n');
const inner=source.split('local __fa_source=[===========[',2)[1]?.split(']===========]',1)[0];assert.ok(inner);
const runtime=await luauTestRuntime();const temp=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-market-'));
const innerPath=path.join(temp,'inner.luau');await fs.writeFile(innerPath,inner);
for(const file of [candidate,innerPath]){const r=spawnSync(runtime.compiler,['--null',file],{encoding:'utf8'});assert.equal(r.status,0,r.stderr);}
const between=(a,b)=>inner.slice(inner.indexOf(a),inner.indexOf(b,inner.indexOf(a)));
const table=between('FarmRuntime.MarketRuntime = {','-- Autumn event leaf collector');
const functions=between('function FarmRuntime.marketOperationToken()', 'function FarmRuntime.initializeMarket()');
const destroy=between('function App.Destroy()', 'if type(env.__FA_STARTUP_EMIT) == "function" then pcall(env.__FA_STARTUP_EMIT, "MAIN 06');
const harness=String.raw`
local now, order, jobs = 0, 0, {}
local task = {}
local os = {clock = function() return now end}
local function enqueue(co, delay)
    order += 1; jobs[#jobs + 1] = {co=co, at=now + (delay or 0), order=order}
end
function task.spawn(fn) enqueue(coroutine.create(fn),0) end
function task.delay(delay,fn) enqueue(coroutine.create(fn),delay) end
function task.wait(delay) return coroutine.yield(delay or 0.001) end
local function step()
    table.sort(jobs,function(a,b) return a.at < b.at or (a.at == b.at and a.order < b.order) end)
    local job=table.remove(jobs,1); if not job then return false end
    now=job.at; local ok,delay=coroutine.resume(job.co);assert(ok,tostring(delay))
    if coroutine.status(job.co)~='dead' then enqueue(job.co,delay) end
    return true
end
local function drain(limit)
    local n=0;while #jobs>0 do n+=1;assert(n<(limit or 10000),'scheduler runaway');step() end
end
local state, FarmRuntime, ui, CompostRuntime, calls, offers, activities
local claimedFruits, queuedFruits = {}, {}
local Vector3={zero=0}
local App, AroynWeb = {}, {}
local saveRevision, queueRevision, collectRevision = 0,0,0
local queueWorkerScheduled, collectWorkerScheduled = false,false
local triggerQueue, collectQueue, pendingSeedConfirmations = {},{},{}
local pendingFruitTriggers, recentFruitInventoryAdds, recentFruitCollectedEvents = {},{},{}
local plotCandidateConnections, connections, env = {},{},{}
local GLOBAL_KEY, LEGACY_GLOBAL_KEY = 'new','old'
local function safeDisconnect() end
local function saveSettingsNow() end
local function scheduleSettingsSave() end
local function addActivity() activities+=1 end
local function fireproximityprompt(prompt) calls.pickup+=1 end
local function requireCount(a,b,why) assert(a==b,(why or '')..' expected '..b..' got '..tostring(a)) end
local function pass(name) print('PASS '..name) end
FarmRuntime={}
`+table+functions+destroy+String.raw`
local original=table.clone(FarmRuntime)
local defaults=table.clone(FarmRuntime.MarketRuntime)
local function reset()
 now,order,jobs=0,0,{}
 state={running=true,generation=1,autoMarketEnabled=true,marketSubmitted=0,marketClaims=0,marketCollected=0,marketTickets=0,marketErrors=0}
 FarmRuntime=table.clone(original);FarmRuntime.MarketRuntime=table.clone(defaults)
 ui={};CompostRuntime={selectedItemId='x'};activities=0;calls={give=0,claim=0,get=0,pickup=0};claimedFruits={};queuedFruits={}
 offers={rows={{reward=10,cells={{given=false},{given=false},{given=false}}}},claimed={}}
 FarmRuntime.setMarketStatus=function(value,isError) state.marketStatus=value;if isError then state.marketErrors+=1 end end
 FarmRuntime.marketRequirementText=function() return 'fruit' end
 FarmRuntime.MarketRuntime.GetOffers={Parent=true,InvokeServer=function() calls.get+=1;task.wait(0.01);return offers end}
 FarmRuntime.MarketRuntime.GiveFruit={InvokeServer=function(_,row,cell) calls.give+=1;offers.rows[row].cells[cell].given=true;task.wait(0.04);return true end}
 FarmRuntime.MarketRuntime.ClaimRow={InvokeServer=function(_,row) calls.claim+=1;offers.claimed[row]=true;task.wait(0.01);return true end}
 FarmRuntime.MarketRuntime.offers=offers;FarmRuntime.MarketRuntime.lastRefreshClock=now
 FarmRuntime.findMarketInventoryFruit=function() return nil end
 AroynWeb.Stop=function() task.wait(0.2) end
 return {rowIndex=1,row=offers.rows[1],outstanding=3,entries={
   {cellIndex=1,cell={},inventoryFruit={id='a'}},
   {cellIndex=2,cell={},inventoryFruit={id='b'}},
   {cellIndex=3,cell={},inventoryFruit={id='c'}}}}
end
local function disable() state.autoMarketEnabled=false;FarmRuntime.MarketRuntime.workerRevision+=1 end
local function enable() state.autoMarketEnabled=true;FarmRuntime.MarketRuntime.workerRevision+=1 end

local plan=reset();task.spawn(function() assert(FarmRuntime.marketRunRowBurst(plan)) end);drain()
requireCount(calls.give,3);requireCount(calls.claim,1);requireCount(state.marketSubmitted,3);pass('normal row burst submits and claims unchanged')

plan=reset();task.spawn(function() FarmRuntime.marketRunRowBurst(plan) end);step();disable();drain()
requireCount(calls.give,0);requireCount(calls.claim,0);pass('disable during stagger prevents all queued submissions')

plan=reset();task.spawn(function() FarmRuntime.marketRunRowBurst(plan) end);step();disable();enable();drain()
requireCount(calls.give,0);requireCount(calls.get,0);pass('off then on cannot revive old burst jobs')

plan=reset();task.spawn(function() FarmRuntime.marketRunRowBurst(plan) end);step();disable();enable()
task.spawn(function() assert(FarmRuntime.marketRunRowBurst(plan)) end);drain()
requireCount(calls.give,3);requireCount(calls.claim,1);pass('new enable cycle completes while old queued work stays cancelled')

plan=reset();task.spawn(function() FarmRuntime.marketRunRowBurst(plan) end);while calls.give==0 do step() end;disable();enable();drain()
requireCount(calls.give,1);requireCount(calls.claim,0);requireCount(state.marketSubmitted,0);requireCount(calls.get,0);pass('an already sent request gets no stale confirmation or claim continuation')

plan=reset();task.spawn(function() FarmRuntime.marketRunRowBurst(plan) end);step();task.spawn(App.Destroy);step()
-- First child may have run before Destroy; no new sends while disconnect yields.
while state.running do step() end
local before=calls.give;assert(state.stopping);drain();requireCount(calls.give,before);requireCount(calls.claim,0)
state.running=true;state.stopping=false;state.generation+=1;state.autoMarketEnabled=true;drain()
pass('actual Destroy invalidates market before yielding network disconnect and restart')

plan=reset();local old=FarmRuntime.marketOperationToken();disable();enable()
task.spawn(function() local ok=FarmRuntime.giveMarketFruit(1,1,nil,nil,{},old);assert(not ok);local claimed=FarmRuntime.claimMarketRow(1,{},old);assert(not claimed) end);drain()
requireCount(calls.give,0);requireCount(calls.claim,0);pass('remote action entry points reject stale tokens')

reset();local token=FarmRuntime.marketOperationToken();local result
task.spawn(function() result=FarmRuntime.refreshMarketOffers(true,token) end);step();disable();enable();local current={rows={},claimed={}};FarmRuntime.MarketRuntime.offers=current;drain()
assert(result==false and FarmRuntime.MarketRuntime.offers==current);pass('late GetOffers reply does not replace current offers')

reset();local token=FarmRuntime.marketOperationToken()
task.spawn(function() FarmRuntime.confirmMarketCell(1,1,token) end);step();disable();enable();drain();requireCount(calls.get,0)
pass('disable during confirmation wait prevents subsequent offer request')

plan=reset();local fruit={Parent=true,GetAttribute=function() return 1 end};local prompt={Parent=true}
FarmRuntime.findFruitPrompt=function() return prompt end;FarmRuntime.reacquireFruitSpawn=function() return fruit,prompt end
plan.entries={{cellIndex=1,cell={},plotFruit={fruit=fruit,treeData={id='tree'}}}};plan.outstanding=1
task.spawn(function() FarmRuntime.marketRunRowBurst(plan) end);step();disable();enable();drain();requireCount(calls.pickup,0)
pass('disable during collection stagger prevents queued prompt calls')

reset();fruit={Parent=true,GetAttribute=function() return 1 end};prompt={Parent=true}
FarmRuntime.findFruitPrompt=function() return prompt end;FarmRuntime.reacquireFruitSpawn=function() return fruit,prompt end
task.spawn(function() FarmRuntime.collectMarketFruit({fruit=fruit,treeData={id='tree'}},{}) end);step();disable();enable();drain()
requireCount(calls.pickup,1);requireCount(state.marketCollected,0);pass('cancelled collection confirmation cannot retry pickup or update counters')

plan=reset();FarmRuntime.MarketRuntime.ROW_BURST_WAIT_TIMEOUT=0.04
FarmRuntime.MarketRuntime.GiveFruit.InvokeServer=function() calls.give+=1;task.wait(0.2);return true end
task.spawn(function() local ok=FarmRuntime.marketRunRowBurst(plan);assert(not ok) end);drain()
requireCount(calls.claim,0);requireCount(calls.get,0);requireCount(state.marketSubmitted,0);pass('burst timeout invalidates pending children and prevents later continuations')

plan=reset();FarmRuntime.MarketRuntime.ROW_BURST_WAIT_TIMEOUT=0.04
fruit={Parent=true,GetAttribute=function() return 1 end};prompt={Parent=true}
FarmRuntime.findFruitPrompt=function() return prompt end;FarmRuntime.reacquireFruitSpawn=function() return fruit,prompt end
plan.entries={{cellIndex=1,cell={},plotFruit={fruit=fruit,treeData={id='tree'}}}};plan.outstanding=1
task.spawn(function() local ok=FarmRuntime.marketRunRowBurst(plan);assert(not ok) end);drain()
requireCount(calls.pickup,1);requireCount(calls.give,0);requireCount(calls.claim,0);pass('collection timeout prevents pending pickup retries and submission')

reset();FarmRuntime.scheduleMarketWorker(1);disable();enable();FarmRuntime.MarketRuntime.workerScheduled=true;drain()
assert(FarmRuntime.MarketRuntime.workerScheduled);requireCount(calls.get,0);pass('old worker timer cannot clear a newer scheduled flag')

reset();task.spawn(function() FarmRuntime.setAutoMarket(false);FarmRuntime.setAutoMarket(true) end);step();disable();enable();drain()
requireCount(#jobs,0);requireCount(calls.give,0);requireCount(calls.claim,0);assert(not FarmRuntime.MarketRuntime.workerScheduled)
pass('initial toggle refresh cannot schedule an obsolete enable cycle')

reset();FarmRuntime.finishMarketTeleport();local ticket={root={Parent=true,CFrame='new',AssemblyLinearVelocity=0,AssemblyAngularVelocity=0,Anchored=false},cframe='old',anchored=false,owner='market'}
FarmRuntime.MarketRuntime.activeTeleport=ticket;FarmRuntime.teleportOwner='market';FarmRuntime.finishMarketTeleport(ticket)
assert(ticket.root.CFrame=='old' and ticket.root.Anchored==false)
local newer={};ticket.root.CFrame='new-run';FarmRuntime.MarketRuntime.activeTeleport=newer;FarmRuntime.teleportOwner='market';FarmRuntime.finishMarketTeleport(ticket)
assert(ticket.root.CFrame=='new-run')
assert(FarmRuntime.MarketRuntime.activeTeleport==newer and FarmRuntime.teleportOwner=='market');pass('repeated old teleport cleanup preserves a newer owner')
`;
const file=path.join(temp,'market-check.luau');await fs.writeFile(file,harness);
const result=spawnSync(runtime.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(result.status,0,result.stderr+'\n'+result.stdout);
const groups=result.stdout.split(/\r?\n/).filter(s=>s.startsWith('PASS '));assert.equal(groups.length,16);console.log(result.stdout.trim());
const previous=await fs.readFile(path.join(root,'apps/dashboard/releases/4.3.80/greedy-growers.luau'));
assert.equal(crypto.createHash('sha256').update(previous).digest('hex'),'ece5e3a123ee4a9f4024eec909cf0a5fb37fccc773a7eba6bf2f88ab1adb3b8a');
assert.equal(crypto.createHash('sha256').update(await fs.readFile(path.join(root,'apps/dashboard/releases/4.3.81/greedy-growers.luau'))).digest('hex'),'6c65f4c0f03adadfb9fda06d34173cb90b452ed5a58db4eba5f66a6c1cfb77df');
console.log('PASS both candidate chunks compile; immutable 4.3.80 release unchanged');
await fs.writeFile(new URL('market-cancellation-results.json',import.meta.url),JSON.stringify({date:'2026-10-02',passed:17,luauVersion:runtime.version,checks:groups.map(s=>s.slice(5)),scope:'Actual extracted Luau functions with deterministic coroutines and stubbed remotes; full outer and embedded chunks compile. No Roblox execution.'},null,2)+'\n');
