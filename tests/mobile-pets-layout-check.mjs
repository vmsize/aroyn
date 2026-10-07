import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const source=await fs.readFile(new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url),'utf8');
const geometry=source.slice(source.indexOf('function ui.PetFeedLayout('),source.indexOf('function ui.BuildPetFeedPage('));
assert(geometry.includes('function ui.ApplyPetFeedLayout('));
const save=source.slice(source.indexOf('    local function set(obj, values)'),source.indexOf('    M.set = set'));
const seeds=source.slice(source.indexOf('function ui.ConfigureCompactSeedRow('),source.indexOf('function ui.ConfigureCompactPetScroll('));
const harness=String.raw`
local ui={}; local UDim2={fromOffset=function(x,y)return {X={Offset=x},Y={Offset=y}}end,new=function(xs,x,ys,y)return {X={Scale=xs,Offset=x},Y={Scale=ys,Offset=y}}end}
local Vector2={zero={},new=function(x,y)return {X=x,Y=y}end}; local Enum={TextXAlignment={Center='center'}}
`+geometry+String.raw`
local function pass(name)print('PASS '..name)end
for _,w in ipairs({240,290,360,479,480,690,940}) do
 for _,n in ipairs({0,1,3,10,100}) do
  for _,compact in ipairs({true,false}) do
   local L=ui.PetFeedLayout(w,compact,n)
   assert(L.cardWidth*L.columns+8*(L.columns-1)<=w+0.01)
   assert(L.cardWidth>=128 and L.cardHeight>=48)
   local bottom=44+(L.columns==3 and L.cardHeight or L.cardHeight*3+16)
   assert(L.hintY>=bottom+8 and L.summaryY>=L.hintY+L.hintHeight+8)
   assert(L.headerY>=L.summaryY+62 and L.listY>=L.headerY+22)
   assert(L.listHeight>0 and L.height>=L.listY+L.listHeight+12)
   assert(L.listHeight<=(compact and 240 or 270))
  end
 end
end
pass('portrait, landscape and desktop controls stay inside bounds without section overlap')
local empty=ui.PetFeedLayout(690,true,0);local one=ui.PetFeedLayout(690,true,1);local three=ui.PetFeedLayout(690,true,3);local many=ui.PetFeedLayout(690,true,100)
assert(empty.listHeight<one.listHeight and one.listHeight<three.listHeight and three.listHeight<many.listHeight)
assert(many.listHeight==240 and three.height<660)
pass('pet count sizes the list and caps large collections instead of leaving fixed empty space')
local P={cards={},hint={},summary={},listHeader={},list={},scroll={},petCount=3};for i=1,3 do P.cards[i]={frame={},caption={},field={}}end
local desktopSize=UDim2.fromOffset(940,400)
local ctx={petFeedUI=P,R={petFeedPage={Size=desktopSize}}};local calls=0
local M={originals={}}
`+save+String.raw`
ui.Responsive={set=set,pages={Pets={ctx.R.petFeedPage,660}},SyncTab=function()calls+=1 end}
local wide=ui.ApplyPetFeedLayout(ctx,690,true)
assert(P.cards[2].frame.Position.X.Offset>0 and P.cards[2].frame.Position.Y.Offset==44)
assert(P.cards[1].field.Size.X.Scale==1 and P.cards[1].field.Size.Y.Offset==36)
assert(ui.Responsive.pages.Pets[2]==wide.height and P.scroll.CanvasSize.Y.Offset==wide.height and ctx.R.petFeedPage.Size.Y.Offset==wide.height)
local narrow=ui.ApplyPetFeedLayout(ctx,290,true)
assert(P.cards[2].frame.Position.X.Offset==0 and P.cards[2].frame.Position.Y.Offset>44)
assert(P.cards[1].field.Size.X.Offset==88 and P.cards[1].caption.Size.X.Offset==-112)
P.petCount=1;local small=ui.ApplyPetFeedLayout(ctx,290,true);assert(small.height<narrow.height and ui.Responsive.pages.Pets[2]==small.height)
for obj,props in pairs(M.originals) do for key,v in pairs(props) do obj[key]=v[1] end end
local desktop=ui.ApplyPetFeedLayout(ctx,940,false);assert(P.cards[2].frame.Position.Y.Offset==44 and P.layoutWidth==940 and P.scroll.CanvasSize.Y.Offset==desktop.height and calls==3)
assert(ctx.R.petFeedPage.Size==desktopSize,'desktop page size restores rather than saving first mobile size as baseline')
assert(P.listHeader.Text=='ACTIVE PETS · 1')
pass('rotation, count changes and desktop return update actual GUI properties and outer page canvas')
`+seeds+String.raw`
local original={};local function set(obj,props) if not original[obj] then original[obj]={} end;for k,v in pairs(props) do if not original[obj][k] then original[obj][k]={obj[k]} end;obj[k]=v end end
local function restore()for obj,props in pairs(original) do for k,v in pairs(props) do obj[k]=v[1] end end end
local row={};for _,key in ipairs({'Frame','Check','Button','NameLabel','RarityLabel','StatLabel','PriceLabel','PriorityButton','Up','Down'}) do row[key]={AnchorPoint=Vector2.new(1,0.5),Size=UDim2.fromOffset(34,22),Visible=true}end
for _,width in ipairs({290,360,690}) do
 ui.ConfigureCompactSeedRow(row,width,set)
 assert(row.Frame.Size.Y.Offset==42 and row.Frame.ClipsDescendants)
 local last=0
 for _,key in ipairs({'PriceLabel','PriorityButton','Up','Down'}) do
  local obj=row[key];local left=width+obj.Position.X.Offset-obj.Size.X.Offset
  local top=obj.Position.Y.Offset-obj.AnchorPoint.Y*obj.Size.Y.Offset
  assert(left>=last and top>=0 and top+obj.Size.Y.Offset<=42,key..' lies outside its seed row')
  last=left+obj.Size.X.Offset
 end
 assert(row.StatLabel.Visible==(width>=520))
 assert(34+width+row.NameLabel.Size.X.Offset<=width-162)
end
pass('seed cards match Compost height and price/priority/arrows remain in their own row')
restore();assert(row.PriorityButton.AnchorPoint.Y==0.5 and row.Frame.Size.Y.Offset==22 and row.StatLabel.Visible)
pass('desktop seed anchors and original row properties restore after compact mode')
`;
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-pets-layout-'));const file=path.join(dir,'check.luau');await fs.writeFile(file,harness);
const rt=await luauTestRuntime();const run=spawnSync(rt.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);
console.log(run.stdout.trim());await fs.writeFile(new URL('mobile-pets-layout-results.json',import.meta.url),JSON.stringify({passed:5,scope:'Actual layout/apply functions: geometry across seven widths, five counts and both modes; GUI properties and canvas updates with stubs. Physical mobile appearance requires confirmation.'},null,2)+'\n');
