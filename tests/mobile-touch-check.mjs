import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const m=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const source=(await fs.readFile(new URL(`../apps/dashboard/releases/${m.version}/greedy-growers.luau`,import.meta.url),'utf8')).replaceAll('\r\n','\n');
function section(a,b){const start=source.indexOf(a),end=source.indexOf(b,start);assert(start>=0&&end>start);return source.slice(start,end)}
const popup=section('    R.popupLayer = new("Frame", {','    local function popupFrame(');
const pets=section('function ui.ConfigureCompactPetScroll(','function ui.InstallResponsive(');
const record=section('    local function set(obj, values)','    M.set = set');
const restore=source.match(/for obj,props in pairs\(M\.originals\) do if obj\.Parent then for key,v in pairs\(props\) do obj\[key\]=v\[1\] end end end/);assert(restore);
assert(source.includes('ui.ConfigureCompactPetScroll(ctx, set)'), 'compact layout must install the fix');
const harness=String.raw`
local R={body={}};local ctx={R=R};local M={originals={}};local ui={}
local Vector2={zero={X=0,Y=0}};local UDim2={fromScale=function(x,y)return {x,y}end}
local function new(kind,props,parent)props.Parent=parent;return props end
local function pass(name)print('PASS '..name)end
`+popup+String.raw`
assert(R.popupLayer.Visible==false);pass('initial closed popup layer does not cover pages')
local a,b={Visible=false},{Visible=false}
showPopup(a);assert(R.popupLayer.Visible and a.Visible and ctx.openPopup==a);pass('opening a popup shows its layer')
showPopup(b);assert(R.popupLayer.Visible and not a.Visible and b.Visible and ctx.openPopup==b);pass('switching popups retains only current popup')
closePopup();closePopup();assert(not R.popupLayer.Visible and not b.Visible and ctx.openPopup==nil);pass('closing including repeated close removes overlay')
showPopup(a);showPopup(a);assert(not R.popupLayer.Visible and not a.Visible and ctx.openPopup==nil);pass('same popup button toggles overlay off')
`+pets+record+String.raw`
local restore=function() `+restore[0]+String.raw` end
local position={X=0,Y=48};local list={ScrollingEnabled=true,Active=true}
local scroll={Parent=true,ScrollingEnabled=true,Active=true,CanvasPosition=position}
ctx.petFeedUI={scroll=scroll,list=list}
for _=1,2 do
 ui.ConfigureCompactPetScroll(ctx,set)
 assert(not scroll.ScrollingEnabled and not scroll.Active and scroll.CanvasPosition==Vector2.zero)
 assert(list.ScrollingEnabled and list.Active,'inner pet list must still scroll')
 restore()
 assert(scroll.ScrollingEnabled and scroll.Active and scroll.CanvasPosition==position,'desktop scroll must restore')
end
pass('compact page owns scrolling; pet list preserved; desktop state restores across rotations')
ui.ConfigureCompactPetScroll({},set);pass('layout tolerates absent Pets page')
`;
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-touch-check-')),file=path.join(dir,'check.luau');await fs.writeFile(file,harness);
const rt=await luauTestRuntime();const run=spawnSync(rt.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);
console.log(run.stdout.trim());
await fs.writeFile(new URL('mobile-touch-results.json',import.meta.url),JSON.stringify({passed:run.stdout.trim().split(/\r?\n/).length,scope:'Actual popup lifecycle, compact Pets scroll setup and responsive desktop restoration functions with deterministic GUI stubs; native phone gestures require physical confirmation.'},null,2)+'\n');
