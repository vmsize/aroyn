import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {luauTestRuntime} from '../tools/luau-test-runtime.mjs';
const manifest=JSON.parse(await fs.readFile(new URL('../apps/dashboard/scripts/version.json',import.meta.url),'utf8'));
const source=await fs.readFile(new URL(`../apps/dashboard/releases/${manifest.version}/greedy-growers.luau`,import.meta.url),'utf8');
const a=source.indexOf('function ui.ScrollToDashboardConnect('),b=source.indexOf('function ui.InstallResponsive(',a);assert(a>=0&&b>a);
const handlerA=source.indexOf('    addConnection(R.connectDashboardButton.MouseButton1Click:Connect(function()');
const handlerB=source.indexOf('    addConnection(R.sessionTab.',handlerA);assert(handlerA>=0&&handlerB>handlerA);
const harness=String.raw`
local ui={IsCompact=true};local state={running=true,activeTab='Session'};local Vector2={new=function(x,y)return {X=x,Y=y}end}
local R={sessionView={Visible=true},webDashboardFrame={Parent=true,AbsolutePosition={Y=0}}};local ctx={R=R}
local scroll={Parent=true,CanvasPosition={Y=0},AbsolutePosition={Y=100},AbsoluteCanvasSize={Y=1104},AbsoluteSize={Y=220}}
local M={scroll=scroll,scrolls={},SyncTab=function()end};ui.Responsive=M
local function pass(name)print('PASS '..name)end
`+source.slice(a,b)+String.raw`
local function place(canvas,target,window,canvasSize)
 scroll.CanvasPosition=Vector2.new(0,canvas);scroll.AbsoluteSize.Y=window or 220;scroll.AbsoluteCanvasSize.Y=canvasSize or 1104
 R.webDashboardFrame.AbsolutePosition.Y=scroll.AbsolutePosition.Y+target-canvas
end
for _,canvas in ipairs({0,48,600,884}) do
 place(canvas,758);assert(ui.ScrollToDashboardConnect(ctx));assert(scroll.CanvasPosition.Y==750 and M.scrolls.Session==750)
 local top=758-scroll.CanvasPosition.Y;assert(top>=0 and top+190<=scroll.AbsoluteSize.Y)
end
pass('landscape scroll reaches entire nested mobile linking panel from any previous scroll position')
place(60,758,626);assert(ui.ScrollToDashboardConnect(ctx));assert(scroll.CanvasPosition.Y==478 and 758-478+190<=626)
pass('portrait clamps at canvas end while keeping the complete linking panel visible')
place(0,120,626,300);assert(ui.ScrollToDashboardConnect(ctx));assert(scroll.CanvasPosition.Y==0)
place(0,3,220);assert(ui.ScrollToDashboardConnect(ctx));assert(scroll.CanvasPosition.Y==0)
place(0,846,220);assert(ui.ScrollToDashboardConnect(ctx));assert(scroll.CanvasPosition.Y==838)
pass('short canvases, top targets and changed nested offsets use actual geometry without a fixed destination')
ui.IsCompact=false;place(44,758);assert(not ui.ScrollToDashboardConnect(ctx) and scroll.CanvasPosition.Y==44);ui.IsCompact=true
pass('desktop scroll stays unchanged')
for _,reason in ipairs({'stopped','other-tab','other-view','closed-page','closed-scroll','missing-responsive'}) do
 state.running=true;state.activeTab='Session';R.sessionView.Visible=true;R.webDashboardFrame.Parent=true;scroll.Parent=true;ui.Responsive=M
 if reason=='stopped' then state.running=false elseif reason=='other-tab' then state.activeTab='Pets' elseif reason=='other-view' then R.sessionView.Visible=false elseif reason=='closed-page' then R.webDashboardFrame.Parent=nil elseif reason=='closed-scroll' then scroll.Parent=nil else ui.Responsive=nil end
 place(31,758);assert(not ui.ScrollToDashboardConnect(ctx) and scroll.CanvasPosition.Y==31,reason)
end
pass('stopped, detached or switched-away UI cannot be moved by a late callback')
state.running=true;state.activeTab='Pets';R.sessionView.Visible=false;R.webDashboardFrame.Parent=true;scroll.Parent=true;ui.Responsive=M
local delayed,click,highlight;local task={delay=function(_,fn)delayed=fn end}
local function addConnection()end
R.connectDashboardButton={MouseButton1Click={Connect=function(_,fn)click=fn;return {}end}}
ui.SetMainTab=function(tab)state.activeTab=tab end
local function setRightMode(mode)R.sessionView.Visible=mode=='Session'end
ui.HighlightDashboardConnect=function()highlight=(highlight or 0)+1 end
`+source.slice(handlerA,handlerB)+String.raw`
place(0,758);click();assert(state.activeTab=='Session' and R.sessionView.Visible and delayed);delayed();assert(scroll.CanvasPosition.Y==750 and highlight==1)
pass('actual header click opens Session then scrolls and highlights the linking panel')
place(48,758);click();state.activeTab='Pets';delayed();assert(scroll.CanvasPosition.Y==48 and highlight==1)
state.activeTab='Session';click();R.sessionView.Visible=false;delayed();assert(scroll.CanvasPosition.Y==48 and highlight==1)
state.activeTab='Session';R.sessionView.Visible=true;click();state.running=false;delayed();assert(scroll.CanvasPosition.Y==48 and highlight==1)
pass('actual delayed header callback respects subsequent tab/view switches and shutdown')
`;
const dir=await fs.mkdtemp(path.join(os.tmpdir(),'aroyn-connect-scroll-'));const file=path.join(dir,'check.luau');await fs.writeFile(file,harness);
const rt=await luauTestRuntime();const run=spawnSync(rt.runtime,[file],{encoding:'utf8',timeout:30000});assert.equal(run.status,0,run.stderr+'\n'+run.stdout);
console.log(run.stdout.trim());await fs.writeFile(new URL('dashboard-connect-scroll-results.json',import.meta.url),JSON.stringify({passed:7,scope:'Actual scroll function and header click/delayed callback; synthetic nested positions, portrait/landscape/short canvases, desktop and cancellation. Physical phone tap requires user confirmation.'},null,2)+'\n');
