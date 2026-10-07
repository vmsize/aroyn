import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const file=process.argv[2]||new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url);
const bytes=await fs.readFile(file),source=bytes.toString('utf8').replaceAll('\r\n','\n');
function section(a,b){const start=source.indexOf(a),end=source.indexOf(b,start);assert(start>=0&&end>start);return source.slice(start,end)}
const actual=section('-- Defined before settings loading;','local function loadSettings()')+section('function FarmRuntime.featureOperationToken(','function FarmRuntime.beginCompostTeleport(')+section('-- Pet feeding uses observed','ui.CreateWindowShell = function(ctx)');
const harness=String.raw`
local state,FarmRuntime,CompostRuntime,GameState,ownPlot,claimedFruits,queuedFruits,LocalPlayer
local now,workers,mode,sends,equips,collects,data,marker,fruit,prompt,stage
local PetSeedRuntime={revision=0};local ui={};local workspace={GetServerTimeNow=function()return 1000 end}
local ReplicatedStorage={};local function addActivity()end;local function scheduleSettingsSave()end
local os={clock=function()return now end}
local task={wait=function(t)return coroutine.yield(t or .05)end,spawn=function(fn)workers[#workers+1]={co=coroutine.create(fn),at=now}end}
local function fireproximityprompt(exact,...)
 assert(exact==prompt and select('#',...)==0,'direct exact prompt invocation')
 assert(not prompt.Enabled,'prompt visibility must remain unchanged')
 collects+=1
 local function arrive() data.Inventory.Hotbar[1]={itemType='Fruit',id='new',count=1,sellValue=5,seedType='Oak'} end
 if mode=='cancel-collection' then stage='collection';task.spawn(function()task.wait(.3);arrive()end) else arrive() end
end
FarmRuntime={}
`+actual+String.raw`
local methods=table.clone(FarmRuntime)
local function reset(m)
 FarmRuntime=table.clone(methods);mode=m;now=0;workers={};sends=0;equips=0;collects=0
 state={running=true,generation=1,autoFeedPetsEnabled=true,petFeedThreshold=25,petFeedTarget=80,petFeedMaxValue=0}
 FarmRuntime.PetFeed={revision=0,status='Off',scheduled=false,confirmed=0,spent=0,cooldown={},feeding={}}
 FarmRuntime.AutomationRuntime={};claimedFruits={};queuedFruits={};LocalPlayer={UserId=1}
 ownPlot={Parent=true};GameState={ownPlot=ownPlot,treesById={}}
 marker={Parent=ownPlot,Name='PlotPet_uid',attrs={OwnerUserId=1,Hunger=0,MaxHunger=400,PetType='Pig'}}
 function marker:IsA(c)return c=='Configuration'end;function marker:GetAttribute(k)return self.attrs[k]end
 function ownPlot:GetChildren()return {marker}end
 data={Inventory={Hotbar={{itemType='Fruit',id='held',count=2,sellValue=20,seedType='Oak'}},Storage={}}}
 FarmRuntime.getCurrentData=function()return data end
 FarmRuntime.acquireAutomation=function(kind)FarmRuntime.AutomationRuntime.owner=kind;return true end
 FarmRuntime.releaseAutomation=function()FarmRuntime.AutomationRuntime.owner=nil end
 FarmRuntime.LeafRuntime={revision=0}
 prompt={Parent=true,Enabled=false}
 fruit={Parent=true,attrs={FruitStartTime=0}};function fruit:GetAttribute(k)return self.attrs[k]end
 local tree={instance={Parent=true,IsDescendantOf=function(_,plot)return plot==ownPlot end},multiplier=1,fruits={}}
 local record={instance=fruit};tree.fruits[fruit]=record;GameState.treesById.one=tree
 FarmRuntime.PetFeed.seedConfig={GetFruitGrowthTime=function()return 100 end,PlotGrowthMult=function()return 1 end}
 FarmRuntime.refreshMarketPlotRecords=function()end
 FarmRuntime.liveFruitDisplay=function()return {sellValue=5,seedType='Oak',locked=fruit.attrs.FruitLocked,waxed=fruit.attrs.FruitWaxed}end
 FarmRuntime.findFruitPrompt=function()return prompt end;FarmRuntime.findFruitTeleportCFrame=function()return {}end
 FarmRuntime.petFeedMove=function()error('feeding must not move the character')end
 FarmRuntime.waitForSelectedItem=function(id)
  stage='equip';task.wait(.1)
  if mode=='owner-during-equip' then marker.attrs.OwnerUserId=2 end
  if mode=='favorite-during-equip' then data.Inventory.Hotbar[1].favorited=true end
  CompostRuntime.selectedItemId=id;return true
 end
 CompostRuntime={PlayerPlotService={FeedPet=function()
  sends+=1
  return {await=function()
   if mode=='timeout' then task.wait(5)end
   if mode=='cancel-confirm' or mode=='stop-confirm' then task.wait(.2)end
   if mode=='exception' then error('remote failed')end
   if mode=='unresolved' then return false,'rejected' end
   if mode=='refused' then return true,false end
   if mode=='favorite-no-consumption' then data.Inventory.Hotbar[1].favorited=true
   elseif mode~='no-consumption' then data.Inventory.Hotbar[1].count-=1 end
   if mode=='missing-inventory' then data=nil end
   if mode~='no-hunger' then marker.attrs.Hunger=18 end
   return true,true
  end}
 end},ToolService={ToggleEquip={Fire=function()equips+=1 end}},selectedItemId='none'}
 if m~='normal-plot' and m~='cancel-collection' and m~='wax-before-collection' and m~='cap-before-collection' then claimedFruits[fruit]=true end
 local choose=FarmRuntime.petFeedChoosePlotFruit
 FarmRuntime.petFeedChoosePlotFruit=function()
  local result=choose()
  if mode=='wax-before-collection' then fruit.attrs.FruitWaxed=true end
  if mode=='cap-before-collection' then state.petFeedMaxValue=1 end
  return result
 end
end
local function pass(s)print('PASS '..s)end
reset('unit')
local a,b,c=FarmRuntime.petFeedOptions(0/0,math.huge,-math.huge);assert(a==25 and b==80 and c==0)
a,b,c=FarmRuntime.petFeedOptions(101,-1,-5);assert(a==95 and b==96 and c==0);pass('finite options and ordered threshold limits')
assert(not FarmRuntime.petFeedValueAllowed(0/0) and not FarmRuntime.petFeedValueAllowed(math.huge) and not FarmRuntime.petFeedValueAllowed(-1));state.petFeedMaxValue=10;assert(FarmRuntime.petFeedValueAllowed(10) and not FarmRuntime.petFeedValueAllowed(11));pass('bounded fruit values and optional cap')
reset('unit');data.Inventory.Storage={{itemType='Fruit',id='cheap',sellValue=1,count=1},{itemType='Fruit',id='fav',sellValue=0,favorited=true},{itemType='Seed',id='seed',sellValue=0},{itemType='Fruit',id='bad',sellValue=math.huge}}
assert(FarmRuntime.petFeedInventory()[1].id=='cheap' and #FarmRuntime.petFeedInventory()==2);pass('cheapest inventory fruit excludes favorites seeds and invalid values')
data.Inventory.Hotbar[1].favorited=true;assert(FarmRuntime.petFeedRawCount('held')==2);data=nil;assert(FarmRuntime.petFeedRawCount('held')==nil);pass('confirmation uses raw inventory and distinguishes unavailable data')
reset('unit');marker.attrs.OwnerUserId=2;assert(#FarmRuntime.petFeedPets()==0);marker.attrs.OwnerUserId=1;GameState.ownPlot={};assert(#FarmRuntime.petFeedPets()==0);pass('only current own plot pets')
reset('unit');assert(FarmRuntime.petFeedChoosePet());marker.attrs.Hunger=120;assert(FarmRuntime.petFeedChoosePet());marker.attrs.Hunger=320;assert(not FarmRuntime.petFeedChoosePet());marker.attrs.Hunger=120;assert(not FarmRuntime.petFeedChoosePet());pass('25 to 80 percent hysteresis avoids toggling near threshold')
reset('normal-plot');assert(FarmRuntime.petFeedChoosePlotFruit());fruit.attrs.FruitStartTime=950;assert(not FarmRuntime.petFeedChoosePlotFruit());fruit.attrs.FruitStartTime=0;fruit.attrs.FruitWaxed=true;assert(not FarmRuntime.petFeedChoosePlotFruit());fruit.attrs.FruitWaxed=false;fruit.attrs.FruitLocked=true;assert(not FarmRuntime.petFeedChoosePlotFruit());pass('maturity uses growth time and protects waxed locked fruit despite disabled camera prompt')
reset('unit');local t={claimedFruit=fruit};claimedFruits[fruit]={};FarmRuntime.petFeedReleaseClaim(t);assert(claimedFruits[fruit]);claimedFruits[fruit]=t;FarmRuntime.petFeedReleaseClaim(t);assert(not claimedFruits[fruit]);pass('late claim cleanup cannot clear a newer owner')
local function drive(co,token)
 local cancelled=false
 for i=1,250 do
  if coroutine.status(co)=='dead' then break end
  local ok,delay=coroutine.resume(co,token);assert(ok,tostring(delay));now+=tonumber(delay) or 0
  if not cancelled and ((mode=='cancel-collection' and stage=='collection') or (mode=='cancel-equip' and stage=='equip') or (mode=='cancel-before-send' and #workers>0) or ((mode=='cancel-confirm' or mode=='stop-confirm') and sends>0)) then
   state.autoFeedPetsEnabled=false;FarmRuntime.PetFeed.revision+=1;cancelled=true
   FarmRuntime.PetFeed.status='cancelled sentinel'
   if mode=='stop-confirm' then state.running=false;state.generation+=1 end
  end
  for _,w in ipairs(workers) do if coroutine.status(w.co)~='dead' and w.at<=now then local success,wait=coroutine.resume(w.co);assert(success,tostring(wait));w.at=now+(tonumber(wait) or 0) end end
 end
 assert(coroutine.status(co)=='dead','unbounded operation')
end
for _,scenario in ipairs({'normal-inventory','normal-plot','refused','unresolved','exception','timeout','no-consumption','no-hunger','favorite-no-consumption','missing-inventory','wax-before-collection','cap-before-collection','owner-during-equip','favorite-during-equip','cancel-collection','cancel-equip','cancel-before-send','cancel-confirm','stop-confirm'}) do
 reset(scenario);stage=nil
 local token=FarmRuntime.featureOperationToken('feed');assert(FarmRuntime.acquireFeatureOperation(token));local co=coroutine.create(FarmRuntime.petFeedStep);drive(co,token)
 local normal=scenario=='normal-inventory' or scenario=='normal-plot'
 assert(FarmRuntime.PetFeed.confirmed==(normal and 1 or 0),scenario..' false confirmation')
 if scenario:find('during',1,true) or scenario:find('before-collection',1,true) or scenario=='cancel-collection' or scenario=='cancel-equip' or scenario=='cancel-before-send' then assert(sends==0,scenario..' sent')end
 if scenario=='wax-before-collection' or scenario=='cap-before-collection' then assert(collects==0,scenario..' collected')end
 if scenario=='cancel-collection' then assert(collects==1 and equips==0,'cancelled collection continued to equip')end
 if scenario=='normal-plot' then assert(collects==1 and not prompt.Enabled and FarmRuntime.PetFeed.spent==5)end
 if scenario=='normal-inventory' then assert(collects==0 and FarmRuntime.PetFeed.spent==20)end
 if scenario:find('cancel',1,true) or scenario=='stop-confirm' then assert(FarmRuntime.PetFeed.status=='cancelled sentinel','old continuation overwrote toggle status')end
 if scenario=='timeout' then
  assert(FarmRuntime.PetFeed.inFlight,'pending response must retain its fence')
  now+=6;for _,w in ipairs(workers)do if coroutine.status(w.co)~='dead'then local ok,err=coroutine.resume(w.co);assert(ok,tostring(err))end end
  assert(FarmRuntime.PetFeed.confirmed==0 and not FarmRuntime.PetFeed.inFlight,'late response mutated counters or retained completed fence')
 end
 pass(scenario..' sends='..sends..' confirmed='..FarmRuntime.PetFeed.confirmed)
end
reset('unit');FarmRuntime.PetFeed.inFlight={};local t=FarmRuntime.featureOperationToken('feed');assert(FarmRuntime.acquireFeatureOperation(t));assert(not FarmRuntime.petFeedStep(t) and sends==0);pass('pending feed blocks duplicate remote requests')
reset('unit');local token={claimedFruit=fruit};claimedFruits[fruit]=token;FarmRuntime.petFeedReleaseClaim(token);FarmRuntime.petFeedReleaseClaim(token);assert(not claimedFruits[fruit]);pass('claim cleanup is idempotent without movement restoration')
`;
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-pet-feed-')),probe=path.join(dir,'check.luau');await fs.writeFile(probe,harness);
const rt=await luauTestRuntime();
const embedded=source.match(/local __fa_source\s*=\s*\[===========\[([\s\S]*?)\]===========\]/);assert(embedded,'embedded client missing');assert(bytes.length<=900000,'stable loader byte limit');
for(const [name,text] of [['client',source],['embedded',embedded[1]],['check',harness]]){
 const target=path.join(dir,name+'.luau');await fs.writeFile(target,text);const c=spawnSync(rt.compiler,['--null',target],{encoding:'utf8'});assert.equal(c.status,0,c.stderr);
}
const run=spawnSync(rt.runtime,[probe],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);
const checks=run.stdout.trim().split(/\r?\n/);console.log(run.stdout.trim());
await fs.writeFile(new URL('pet-feed-results.json',import.meta.url),JSON.stringify({clientSha256:crypto.createHash('sha256').update(bytes).digest('hex'),passed:checks.length,checks,scope:'Actual pet feeding and feature token functions with deterministic inventory, plot, Promise and cancellation stubs; no game connection.'},null,2)+'\n');
