-- Real integration sources, scheduler/property/input doubles. No visual approval.
local core,E=Mock.install(CoreFactory,true)
local startupFactory,SE=Mock.install(StartupFactory,true)
local uiFactory,UE=Mock.install(UIFactory,true)
local runtime,RE=Mock.install(RuntimeFactory,true)
local info=BuildInfoFactory();local Startup=startupFactory();local build=uiFactory()
for _,env in ipairs({E,SE,UE,RE}) do env.isfile=function(p) return Mock.files[p]~=nil end end
local workspace=Mock.Instance.new('Workspace');workspace.CurrentCamera=E.workspace.CurrentCamera
UE.workspace=workspace;RE.workspace=workspace
local field=Mock.Instance.new('Folder');field.Name='BigField';field.Parent=workspace
local conveyor=Mock.Instance.new('Folder');conveyor.Name='ConveyorSeeds';conveyor.Parent=field
local plots=Mock.Instance.new('Folder');plots.Name='PlayerPlots';plots.Parent=field
local plot=Mock.Instance.new('Model');plot:SetAttribute('OwnerUserId',123);plot.Parent=plots
local packages=Mock.Instance.new('Folder');packages.Name='Packages';packages.Parent=Mock.services.ReplicatedStorage
local requests=0;RE.request=function() requests+=1;error('Dashboard unavailable fixture') end
local preloadDelay,preloadFail=0,false;local preloads=0
Mock.services.ContentProvider={PreloadAsync=function(_,assets,callback)
    preloads+=1;assert(#assets==2)
    if preloadDelay>0 then E.task.wait(preloadDelay) end
    for _,asset in ipairs(assets) do callback(asset,preloadFail and E.Enum.AssetFetchStatus.Failure or E.Enum.AssetFetchStatus.Success) end
end}
local results={}
local function pass(s) table.insert(results,s);print('PASS '..s) end
local function assets(A) A.Logo='mock://actual-logo-boundary';A.IconAtlas='mock://actual-atlas-boundary' end
local function start(options,assetFn,runtimeFn,uiFn)
    return Startup.Run(core(),info,assetFn or assets,runtimeFn or runtime,uiFn or build,options or {})
end
local function screens()
    local n=0;for _,o in ipairs(Mock.instances) do if o.ClassName=='ScreenGui' and o.Parent and o:GetAttribute('AroynUIOwned') then n+=1 end end;return n
end
local function clean(s)
    s:Destroy();Mock.advance(.6)
    assert(screens()==0 and Mock.connections==0,'Leaked GUI/listeners: '..screens()..' / '..Mock.connections)
    assert(not Mock.shared.__AROYN_HUB_STARTUP and not Mock.shared.__AROYN_HUB_GREEDY and not Mock.shared.__AROYN_HUB_GREEDY_LEGACY)
    assert(not next(s.Timers) and not s.Thread and not s.Scope.Alive,'Startup resources survived cleanup')
    -- Unchanged baseline Anti-AFK has a generation-guarded 480s sleep, not a
    -- stored cancel handle. Verify eventual exit without altering gameplay.
    Mock.advance(481)
    assert(#Mock.jobs==0,'Leaked scheduled jobs after baseline sleepers exit: '..#Mock.jobs)
end
Mock.asyncTweens=true
preloadDelay=.6
local s=start();local shell=s.Window.Root;local logo=s.Logo
assert(s.State=='Loading' and s.Completed==0 and screens()==1)
assert(shell.Size.X.Offset==356 and shell.Size.Y.Offset==196 and shell.BackgroundTransparency==1)
assert(not s.Header.Visible and not s.Window.Chrome.Visible and s.Build.Text==info.DisplayVersion)
assert(info.BaselineVersion=='4.3.95' and info.DisplayVersion=='Version 4.3.96')
assert(s.Mask.Active==false and s.Loading.Active==false and not s.Mask.Visible)
assert(s.Window.Collapse.Gate.Locked and shell:GetAttribute('AroynStartupBusy'))
local function tweenInfo(o,duration,style,direction,key)
    local t=s.Scope.Animations[key or o];assert(t,'Missing live animation')
    assert(t.Info[1]==duration and t.Info[2]==E.Enum.EasingStyle[style] and t.Info[3]==E.Enum.EasingDirection[direction])
    return t
end
for _,o in ipairs({shell,s.Edge,s.Brand,s.Build,s.Status,s.Count,s.Track,s.Fill}) do tweenInfo(o,.30,'Sine','InOut') end
Mock.advance(.35)
assert(s.State=='Loading' and s.Completed==0 and shell.BackgroundTransparency==0 and s.EntryDone)
assert(s.Status.Text=='Loading logo and navigation images…' and s.Count.Text=='0 / 7 steps')
pass('Compact same-shell construction, native fade-in, real build identifier and input gating')
Mock.advance(.3)
assert(s.Completed==7 and s.App.Bootstrapped and s.State=='FadingLoading')
local ids={'assets','game','seeds','preferences','interface','observers','ready'}
for i,id in ipairs(ids) do assert(s.Stages[i].Id==id) end
assert(not s.App.GetDiagnostics().automationEnabled and requests==0)
assert(s.Stages[6].Label:find('degraded',1,true),'Unavailable optional game services were presented as fully ready')
assert(s.App.Window==s.Window and s.App.Integration.UI.Window==shell)
assert(not pcall(function() s:Complete('ready','Duplicate') end))
pass('Seven actual bootstrap milestones; held preload does not invent progress; optional Dashboard/services never block readiness')
for _,o in ipairs({s.Brand,s.Build,s.Status,s.Count,s.Track,s.Fill}) do tweenInfo(o,.18,'Sine','InOut') end
tweenInfo(s.Fill,.12,'Quad','Out',s.ProgressKey)
Mock.advance(.18)
assert(s.State=='Expanding' and not s.Loading.Visible and s.Mask.Visible and shell.Parent==s.Screen)
assert(logo.Parent==shell and not s.Window.Restore.Visible and screens()==1)
assert(s.Fill.Size.X.Scale==1 and not s.Scope.Animations[s.ProgressKey])
assert(s.Window.Chrome.Size.X.Scale==1 and s.Window.Chrome.Size.Y.Scale==1)
local maskCorner=s.Mask:FindFirstChildOfClass('UICorner')
local radiusTween=s.Scope.Animations[maskCorner]
assert(radiusTween and radiusTween.Goals.CornerRadius.Offset==s.Aroyn.Theme.Metrics.WindowRadius)
assert(maskCorner.CornerRadius.Offset==s.Corner.CornerRadius.Offset,'Reveal mask corner jumped ahead of shell')
for _,o in ipairs({shell,s.Logo,s.Corner,maskCorner}) do tweenInfo(o,.48,'Cubic','InOut') end
assert(s.Window.Close.Interactable==false)
local U=s.App.Integration.UI.Integration
U.Controls.AutoBuy.Control.Activated:Fire();assert(not s.App.GetDiagnostics().automationEnabled)
Mock.advance(.29)
assert(s.Revealing and s.Header.Visible and s.Window.Chrome.Visible and not s.RevealDone)
tweenInfo(s.Mask,.20,'Sine','InOut')
assert(s.Header.Interactable==false and s.Window.Close.Interactable==false)
pass('Loading content fades out; single original logo/shell expands; final native mask reveal remains noninteractive')
Mock.advance(.2)
assert(s.State=='Ready' and shell==s.Window.Root and s.Window.Root.Size.X.Offset==992 and s.Window.Root.Size.Y.Offset==600)
assert(shell.Position.X.Offset==16 and shell.Position.Y.Offset==84 and shell.Position.X.Scale==0)
assert(logo.Parent==s.Header and logo.Position.X.Offset==12 and logo.Position.Y.Offset==10 and logo.ImageTransparency==0)
assert(s.Mask.Parent==nil and s.Loading.Parent==nil and not s.Scope.Alive and not s.Window.Collapse.Gate.Locked)
assert(s.Header.Interactable and s.Window.Close.Interactable and not shell:GetAttribute('AroynStartupBusy'))
assert(not Mock.shared.__AROYN_HUB_STARTUP and #s.Window.Pages==8)
for _,o in ipairs(s.Screen:GetDescendants()) do assert(not o:IsA('CanvasGroup') and (not o:IsA('UIScale') or o.Scale==1)) end
pass('Exact final integer geometry, original title-bar logo ownership, mask removal and input activation without scaling/compositing')
s.Window:SelectPage('Pets');Mock.advance(.3);local selected=s.Window.Selected
U.Preferences.PetStart:SetValue(31,true)
s.Window:SetMinimized(true);Mock.advance(.5);assert(s.Window.Collapse.Minimized)
s.Window:SetMinimized(false);Mock.advance(.5)
assert(not s.Window.Collapse.Minimized and s.Window.Selected==selected and s.App.Integration.State.petFeedThreshold==31)
for _=1,20 do s.Window:SetMinimized(true);s.Window:SetMinimized(false) end
Mock.advance(.6)
assert(not s.Window.Collapse.Minimized and s.Window.Selected==selected and s.Window.Root.Visible)
assert(not s.Window.Collapse.Proxy and not s.Window.Restore.Visible)
assert(s.Window:SaveConfig('startup-test'));U.Preferences.PetStart:SetValue(44,true)
assert(s.Window:LoadConfig('startup-test'));assert(s.App.Integration.State.petFeedThreshold==31)
assert(s.Window:DeleteConfig('startup-test'))
pass('Approved minimize/restore, selected page, values and real configuration roundtrip survive startup')
clean(s);pass('Normal cleanup cancels startup resources/listeners; unchanged generation-guarded baseline sleepers eventually exit')

preloadDelay=0;preloadFail=true
s=start();Mock.advance(.1)
assert(s.State=='Failed' and s.Completed==0 and s.Error:find('asset',1,true))
assert(s.Screen.Parent and s.Window.Root.BackgroundTransparency==0 and not s.Track.Visible)
assert(s.RetryButton and s.CloseButton and not s.Mask.Visible and screens()==1)
preloadFail=false;s.RetryButton.Activated:Fire();local retry=Mock.shared.__AROYN_HUB_STARTUP
assert(s.State=='Destroyed' and retry~=s);Mock.advance(1.2);assert(retry.State=='Ready' and screens()==1)
clean(retry);pass('Failed asset preload keeps honest compact error shell; Retry replaces and initializes safely')
s=start(nil,function() end);Mock.advance(.1)
assert(s.State=='Failed' and s.Error:find('logo unavailable',1,true) and s.Completed==0)
s.CloseButton.Activated:Fire();clean(s)
pass('Missing custom asset capability produces meaningful Close/Retry state without false completion')
local provider=Mock.services.ContentProvider;Mock.services.ContentProvider=nil
s=start();Mock.advance(.1);assert(s.State=='Failed' and s.Completed==0 and s.Error:find('ContentProvider',1,true))
Mock.services.ContentProvider=provider;clean(s)
pass('Missing required asset service fails gracefully and cleans all resources')

field.Parent=nil;s=start();Mock.advance(.1)
assert(s.State=='Failed' and s.Completed==1 and s.Error:find('BigField',1,true))
assert(not Mock.shared.__AROYN_HUB_GREEDY and not s.App.Integration.State.running)
assert(s.Screen.Parent and s.Header.Visible==false and s.Window.Scope.Alive==false)
field.Parent=workspace;clean(s)
pass('Actual required game-object initialization failure preserves error shell and stops partial runtime')
s=start(nil,nil,nil,function(A,C) build(A,C);error('Required interface failure fixture') end)
Mock.advance(.1);assert(s.State=='Failed' and s.Completed==4 and not s.App.Integration.State.running)
assert(screens()==1 and not Mock.shared.__AROYN_HUB_GREEDY);clean(s)
pass('Failure after actual UI construction cleans pages/config/observers while retaining only error card')
s=start(nil,nil,function(_,_,opts)
    local partial={};Mock.shared.__AROYN_HUB_GREEDY=partial;opts.Startup:BindApp(partial)
    error('Early definitions failed fixture')
end)
Mock.advance(.1);assert(s.State=='Failed' and not Mock.shared.__AROYN_HUB_GREEDY);clean(s)
pass('Early factory error before Destroy is defined clears only owned partial local singleton')

preloadDelay=5;s=start();Mock.advance(.1);local replacement=start()
assert(s.State=='Destroyed' and screens()==1);Mock.advance(.2)
replacement:Destroy();Mock.advance(6);clean(replacement)
assert(preloads>0 and requests==0)
pass('Repeated execution during asset loading cancels stale attempt and leaves exactly one replacement shell')
preloadDelay=0;s=start();Mock.advance(.5);assert(s.State=='Expanding')
replacement=start();assert(s.State=='Destroyed');Mock.advance(1.2)
assert(replacement.State=='Ready' and screens()==1 and not s.App.Integration.State.running)
clean(replacement);pass('Repeated execution during active morph safely cancels tweens and original workers')
s=start();Mock.advance(.1);assert(s.App and s.State=='Loading')
s.App.Destroy();clean(s);pass('Runtime destruction during entry/loading cancels startup and all integration services')
s=start();Mock.advance(.5);assert(s.State=='Expanding')
s.Window:Destroy();clean(s);pass('Window destruction during expansion cancels owned tweens/timers without orphaned overlays')

s=start();Mock.advance(.50);assert(s.State=='Expanding')
s.Screen._p.absoluteOverride=E.Vector2.new(390,844);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
tweenInfo(s.Window.Root,.18,'Quad','Out')
Mock.advance(.3)
s.Screen._p.absoluteOverride=E.Vector2.new(768,1024);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
assert(not s.GeometryDone);Mock.advance(.25)
assert(s.State=='Ready' and s.Window.Root.Size.X.Offset==736 and s.Window.Root.Size.Y.Offset==600)
assert(s.Window.Root.Position.X.Offset==16 and s.Window.Root.Position.Y.Offset==212)
assert(s.Window.Chrome.AbsoluteSize.X==736)
clean(s);pass('Viewport changes during interrupted/replaced geometry tweens resolve latest target before activation')

-- Fast/late actual asset registration cannot cancel opacity with size/position.
s=start();Mock.advance(.05);assert(s.Completed==7 and s.PendingReady and not s.EntryDone)
tweenInfo(s.Fill,.30,'Sine','InOut')
tweenInfo(s.Logo,.30,'Sine','InOut',s.LogoFadeKey)
assert(not s.Window.Close.Interactable and not s.Revealing)
Mock.advance(.43);assert(s.State=='Expanding' and s.Logo.ImageTransparency==0)
Mock.advance(.30);assert(s.Revealing and not s.RevealDone and not s.Window.Close.Interactable)
Mock.advance(.20);assert(s.State=='Ready');clean(s)
pass('Fast bootstrap preserves entry opacity independently of real progress and gates controls through the full InOut reveal')
s=start(nil,function(A) E.task.wait(.65);assets(A) end);Mock.advance(.89)
assert(s.State=='Expanding' and s.Scope.Animations[s.LogoFadeKey] and s.Scope.Animations[s.Logo])
tweenInfo(s.Logo,.30,'Sine','InOut',s.LogoFadeKey)
tweenInfo(s.Logo,.48,'Cubic','InOut')
Mock.advance(.13);assert(s.Logo.ImageTransparency==0 and s.State=='Expanding')
clean(s)
pass('Late asset fade coexists with logo geometry and cancellation cleans both animation channels')
for _,width in ipairs({320,390,768,1024,1440,1920}) do
    s=start({ReducedMotion=true});s.Screen._p.absoluteOverride=E.Vector2.new(width,844)
    s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(.3)
    assert(s.State=='Ready' and s.Window.Root.Size.X.Offset==math.min(1024,width-32))
    assert(s.Window.Root.Position.X.Offset>=0 and s.Window.Root.Position.X.Offset+s.Window.Root.Size.X.Offset<=width)
    assert(s.Constraint.MinSize.X<=s.Window.Root.Size.X.Offset);clean(s)
end
pass('Reduced-motion path and six simulated viewport widths keep loader/final shell bounded; physical mobile remains untested')
preloadDelay=50;s=start();Mock.advance(45.2)
assert(s.State=='Failed' and s.Completed==0 and s.Error:find('timed out',1,true))
assert(not s.Thread and not next(s.Timers));clean(s);preloadDelay=0
pass('Bounded required-stage timeout cancels yielded startup instead of hanging or fabricating success')
local productionDestroyed=0;local production={Destroy=function() productionDestroyed+=1 end}
Mock.shared.__AROYN_FARM_SINGLETON=production;s=start();Mock.advance(.1)
assert(s.State=='Failed' and s.Completed==0 and Mock.shared.__AROYN_FARM_SINGLETON==production and productionDestroyed==0)
clean(s);Mock.shared.__AROYN_FARM_SINGLETON=nil
pass('Active production runtime is preserved and local duplicate workers are refused')

s=start();Mock.advance(1.2);local first=s.App
local prefs=s.App.Integration.UI.Integration.Preferences;prefs.Reserve:SetValue('123',true)
assert(s.Window:SaveConfig('main'));replacement=start();Mock.advance(1.2)
assert(replacement.State=='Ready' and not first.Integration.State.running and replacement.App.Integration.State.cashReserve==123)
assert(not replacement.App.GetDiagnostics().automationEnabled and requests==0)
replacement.Window.Close.Activated:Fire();clean(replacement)
pass('Ready-session rerun preserves actual saved preferences, automation off, explicit Dashboard and normal Close lifecycle')
local bundleFactory,BE=Mock.install(BundleFactory,true)
BE.workspace=workspace;BE.isfile=function(p) return Mock.files[p]~=nil end
local customAssets=0
BE.getcustomasset=function(path)
    assert(Mock.files[path] and Mock.files[path]:sub(1,8)=='\137PNG\13\10\26\10','Actual embedded asset was not decoded/written as PNG')
    customAssets+=1;return 'mock://registered/'..path
end
BE.request=function() requests+=1;error('No startup Dashboard request allowed') end
s=bundleFactory();Mock.advance(1.2)
assert(s.State=='Ready' and customAssets==2 and s.Info.DisplayVersion==info.DisplayVersion and screens()==1)
assert(s.Logo.Image:find('registered/',1,true) and #s.Window.Pages==8 and requests==0)
assert(not s.App.GetDiagnostics().automationEnabled);clean(s)
pass('Entire runnable production-intended Phase11B candidate bundle executes with actual embedded PNG decoding/registration, core, startup, UI and game runtime')
s=start();Mock.advance(1.2);local C=s.App.Integration;U=C.UI.Integration
local failedRequests=0
C.Web.requestFn=function()
    failedRequests+=1;return {StatusCode=503,Body=Mock.services.HttpService:JSONEncode({ok=false,error='Dashboard unavailable fixture'})}
end
s.Window:SelectPage('Settings');Mock.advance(.3)
U.DashboardKey:SetValue('VY-ABCDEF-123456-ABCDEF-123456');U.Controls.LinkDashboard.Control.Activated:Fire();Mock.advance(.4)
assert(failedRequests>0 and s.State=='Ready' and C.State.running and C.Dashboard.State=='Reconnecting' and C.NetworkThread and not C.Web.thread)
assert(s.Window.Close.Interactable and not s.Window.Root:GetAttribute('AroynStartupBusy'))
clean(s);pass('Explicit Dashboard 503 over simulated transport after startup keeps main Hub interactive and cleans connection attempt')
print('TOTAL '..#results)
