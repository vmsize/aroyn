-- Actual runtime + actual UI library; game hierarchy/network remain deterministic doubles.
local core,E=Mock.install(CoreFactory,true)
local uiFactory=Mock.install(UIFactory,true)
local runtime,RE=Mock.install(RuntimeFactory,true)
RE.isfile=function(path) return Mock.files[path]~=nil end
E.isfile=RE.isfile
local workspace=Mock.Instance.new('Workspace');workspace.CurrentCamera={ViewportSize=E.Vector2.new(1440,900)}
local field=Mock.Instance.new('Folder');field.Name='BigField';field.Parent=workspace
local conveyor=Mock.Instance.new('Folder');conveyor.Name='ConveyorSeeds';conveyor.Parent=field
local plots=Mock.Instance.new('Folder');plots.Name='PlayerPlots';plots.Parent=field
local plot=Mock.Instance.new('Model');plot.Name='PlayerPlot1';plot:SetAttribute('OwnerUserId',123);plot.Parent=plots
RE.workspace=workspace
local uiEnv=getfenv(uiFactory);uiEnv.workspace=workspace
local packages=Mock.Instance.new('Folder');packages.Name='Packages';packages.Parent=Mock.services.ReplicatedStorage
local function remote(service,name)
    local folder=Mock.Instance.new('Folder');folder.Name=service;folder.Parent=Mock.services.ReplicatedStorage
    local event=Mock.Instance.new('RemoteEvent');event.Name=name;event.Parent=folder;return event
end
local spawned=remote('SeedConveyorService','SeedSpawned')
local dataUpdate=remote('DataService','DataUpdate')
local weather=remote('WeatherService','WeatherChanged')
local fruitCollected=remote('PlayerPlotService','FruitCollected')
local oldKey='AroynHub/SeedAutoBuy/settings_v3.json'
local http=Mock.services.HttpService
local oldJson=http:JSONEncode({version=4,autoBuyEnabled=true,autoFeedPetsEnabled=true,autoCompostEnabled=true,
    selectedSeeds={Oak=true,Pine=true},priorities={Oak=1,Pine=2},cashReserve=50,petFeedThreshold=20,petFeedTarget=75})
Mock.files[oldKey]=oldJson
local oldWeb='AroynHub/web_config.json';Mock.files[oldWeb]='unchanged credential sentinel'
local requests=0;RE.request=function() requests+=1;error('Unexpected network request') end
local build=uiFactory();local results={}
local function pass(message) table.insert(results,message);print('PASS '..message) end
local function start()
    local library=core();library.IconAtlas='mock://local-navigation-atlas'
    local out;E.task.spawn(function() out=runtime(library,build,{DisableNetwork=true}) end)
    Mock.advance(.5);assert(out,'Full bootstrap did not finish')
    return out,out.Integration,out.Integration.UI.Integration
end
local app,C,U=start()
assert(C.State.running and #C.Records>0 and #C.Rarities>0)
assert(#app.Window.Pages==8 and app.Window.ByName['Buy Seeds'] and not app.Window.ByName['Planting'])
assert(C.Game.ownPlot==plot and Mock.files[oldKey]==oldJson and Mock.files[oldWeb]=='unchanged credential sentinel')
assert(C.State.selectedSeeds.Oak and C.State.cashReserve==50 and C.State.priorities.Oak==1)
assert(not app.GetDiagnostics().automationEnabled and not C.State.hidePlotVisuals and requests==0)
assert(next(app.Window:GetConfigState().Values)~=nil)
pass('Full real-source bootstrap builds 8 library pages, imports legacy preferences read-only and keeps automation/network off')

local navigation={{'Buy Seeds','cart',0},{'Plot','plot',1},{'Collect','harvest',7},{'Compost','compost',2},
    {'Market','market',3},{'Pets','pets',5},{'Session','stats',9},{'Settings','gear',8}}
local used={}
for i,spec in ipairs(navigation) do
    local page=app.Window.Pages[i];local icon=page.Icon
    assert(page.Name==spec[1] and icon.Name=='Icon_'..spec[2])
    assert(icon.Image=='mock://local-navigation-atlas' and icon.ImageRectOffset.X==(spec[3]%5)*160+16 and icon.ImageRectOffset.Y==math.floor(spec[3]/5)*160+16)
    assert(icon.ImageRectSize.X==128 and icon.ImageRectSize.Y==128 and icon.Size.X.Offset==24 and icon.Size.Y.Offset==24)
    assert(icon.AnchorPoint.X==.5 and icon.AnchorPoint.Y==.5 and icon.Position.X.Scale==.5 and icon.Position.Y.Scale==.5)
    assert(icon.ResampleMode==E.Enum.ResamplerMode.Default and not used[spec[3]])
    used[spec[3]]=true
end
pass('All eight navigation pages use distinct correctly mapped atlas cells with unchanged dimensions, alignment and native image sampling')

U.Preferences.Reserve:SetValue('123',true)
assert(C.State.cashReserve==123)
U.Preferences.Seeds:SetValue({'Oak'},true);assert(C.State.selectedSeeds.Oak and not C.State.selectedSeeds.Pine)
U.PrioritySeed:SetValue('Oak');U.Controls.EnablePriority.Control.Activated:Fire()
assert(C.State.priorities.Oak)
U.Preferences.PetStart:SetValue(30,true);assert(C.State.petFeedThreshold==30 and not C.State.autoFeedPetsEnabled)
U.Preferences.PetCap:SetValue('200',true);assert(C.State.petFeedMaxValue==200)
assert(Mock.files[oldKey]==oldJson and not Mock.files['AroynHub/profiles/greedy-growers/main.json'])
pass('Real UI callbacks reach original preference/selection/priority/pet controllers without implicit saving')

app.Window:SelectPage('Settings');Mock.advance(.3)
U.Preferences.Hotkey:SetValue(E.Enum.KeyCode.H,true);assert(C.State.hotkey==E.Enum.KeyCode.H)
local key=Mock.key('H')
Mock.input.InputBegan:Fire(key,false);Mock.input.InputEnded:Fire(key);Mock.advance(.4)
assert(not app.Window.Collapse.Minimized,'Binding capture press activated shortcut')
Mock.input.InputBegan:Fire(key,false);Mock.input.InputEnded:Fire(key);Mock.advance(.4)
assert(app.Window.Collapse.Minimized)
Mock.input.InputBegan:Fire(key,false);Mock.input.InputEnded:Fire(key);Mock.advance(.4)
assert(not app.Window.Collapse.Minimized and C.State.running)
pass('Physical-key event simulation preserves binding capture and toggles minimize/restore from any page, including minimized state')

app.Window:SelectPage('Buy Seeds');Mock.advance(.3)
local reserve=U.Preferences.Reserve.Control
reserve:CaptureFocus();reserve.Text='2k'
U.Controls.AutoCollect:SetValue(true,true);U.Controls.AutoCollect:SetValue(false,true)
assert(reserve.Text=='2k','Gameplay refresh wiped focused text')
reserve:ReleaseFocus(true);assert(C.State.cashReserve==2000)
assert(app.Window:SaveConfig('compact'));U.Preferences.Reserve:SetValue('10',true)
assert(app.Window:LoadConfig('compact'));assert(C.State.cashReserve==2000)
assert(app.Window:DeleteConfig('compact'))
U.Preferences.Reserve:SetValue('123',true)
pass('Focused editing survives gameplay refresh and compact numeric preferences roundtrip through the real configuration manager')

app.Window:SelectPage('Session');Mock.advance(.3)
spawned.OnClientEvent:Fire({seedKey='Oak',rarity='COMMON',spawnId='synthetic-event'})
dataUpdate.OnClientEvent:Fire({Currency={COINS=10000}},{'Currency','COINS'})
weather.OnClientEvent:Fire('Sunny')
C.Game.treesById['observed-tree']={id='observed-tree',seedType='Oak',fruits={}}
local before=C.State.fruitsCollected
fruitCollected.OnClientEvent:Fire(nil,'observed-tree',1);fruitCollected.OnClientEvent:Fire(nil,'observed-tree',1)
Mock.advance(.1)
assert(#C.Game.incoming==1 and C.Game.cash==10000 and C.State.fruitsCollected==before+1)
assert(U.Controls.Cash:GetValue()=='$10.0K' or U.Controls.Cash:GetValue()=='$10K',U.Controls.Cash:GetValue())
assert(C.Web.BuildSnapshot().runtime.taskDetail:find('Session',1,true))
C.Game.treesById[42]={id=42,seedType='Pine',fruits={}}
app.Window:SelectPage('Plot');Mock.advance(.3);U:Refresh()
U.TreeChoice:SetValue('42',true);assert(C.GetSelectedTree()==42 and U.Controls.TreeDetail:GetValue()=='Pine')
pass('Synthetic real RemoteEvent listeners update cash/spawns/weather/fruit confirmation and snapshots; numeric tree IDs reach inspection')

-- No plot fruit/prompt: these enable handlers change actual runtime state but no fake purchase is asserted.
local autoFields={AutoBuy='autoBuyEnabled',AutoCollect='autoCollectFruits',AutoLeaves='autoCollectLeaves',AutoPetDrops='autoCollectPetSeeds',AutoCompost='autoCompostEnabled',AutoFeed='autoFeedPetsEnabled',AutoMarket='autoMarketEnabled'}
for key,fieldName in pairs(autoFields) do
    local control=U.Controls[key]
    app.Window:SelectPage(control.Section and control.Section.Page.Name or 'Collect')
    Mock.advance(.3)
    -- Use library SetValue notify to exercise Callback even when the control is scrolled out of view.
    control:SetValue(true,true);assert(C.State[fieldName]==true,key..' enable failed');Mock.advance(.3)
    control:SetValue(false,true);assert(C.State[fieldName]==false,key..' disable failed');Mock.advance(.3)
end
assert(not app.GetDiagnostics().automationEnabled)
pass('All seven automation callbacks call real enable/disable paths; missing game services degrade without pretending gameplay success')

assert(app.Window:SaveConfig('main'))
local prefPath='AroynHub/profiles/greedy-growers/main.json'
local doc=http:JSONDecode(Mock.files[prefPath]);assert(doc.Namespace=='greedy-growers')
assert(not doc.Values.AutoBuy and not doc.Values.AutoFeed and not doc.Values.HidePlot)
U.Preferences.Reserve:SetValue('999',true)
U.Controls.AutoBuy:SetValue(true,true);assert(C.State.autoBuyEnabled)
assert(app.Window:LoadConfig('main'));assert(C.State.cashReserve==123 and not app.GetDiagnostics().automationEnabled)
assert(app.Window:ResetConfig());assert(C.State.cashReserve==50 and not app.GetDiagnostics().automationEnabled)
assert(Mock.files[oldKey]==oldJson and Mock.files[oldWeb]=='unchanged credential sentinel')
pass('New Config Save/Load/Reset safely synchronize runtime preferences, exclude automation/credentials and preserve old files')

U.Preferences.Reserve:SetValue('321',true);assert(app.Window:SaveConfig('main'))
local first=app;local second,CC,UU=start()
assert(not first.Integration.State.running and CC.State.running and CC.State.cashReserve==321)
assert(not second.GetDiagnostics().automationEnabled and first.Window.OwnRoot.Parent==nil)
app,C,U=second,CC,UU
pass('Separate runtime initialization replaces only the local singleton and restores preferences with all automation off')

app.Window:SelectPage('Pets');Mock.advance(.3)
local selected=app.Window.Selected
U.Preferences.PetStart:SetValue(31,true)
for _=1,8 do app.Window:SetMinimized(true);app.Window:SetMinimized(false) end
Mock.advance(1)
assert(app.Window.Selected==selected and C.State.petFeedThreshold==31 and C.State.running)
app.Window:SelectPage('Plot');Mock.advance(.3)
U.TreeChoice:SetOptions({'same'});U.TreeChoice:SetValue('same')
C.Game.treesById.same={id='same',seedType='Oak',fruits={}}
U:Refresh();U.TreeChoice:Open();local popup=U.TreeChoice.Popup
U:Refresh();assert(U.TreeChoice.Popup==popup)
pass('Approved morph/navigation preserve gameplay state and refresh does not reopen unchanged dynamic Dropdowns')

local replacement=Mock.Instance.new('Folder');replacement.Name='ConveyorSeeds'
conveyor.Parent=nil;field.ChildRemoved:Fire(conveyor)
replacement.Parent=field;field.ChildAdded:Fire(replacement);Mock.advance(.1)
local count=0;for _ in pairs(replacement.ChildAdded.listeners) do count+=1 end
assert(count==1 and next(conveyor.ChildAdded.listeners)==nil)
field.ChildAdded:Fire(replacement);Mock.advance(.1)
count=0;for _ in pairs(replacement.ChildAdded.listeners) do count+=1 end
assert(count==1)
pass('Existing replacement-conveyor handlers reconnect once and disconnect the stale listener')

local snapshot=C.Web.BuildSnapshot();assert(type(snapshot)=='table' and C.Web.siteUrl=='https://aroyn.xyz/')
assert(C.Web.apiBase:find('aroyn',1,true) and C.Web.configFile=='AroynHub/GreedyGrowers/web_config.json',tostring(C.Web.apiBase)..' / '..tostring(C.Web.configFile))
assert(requests==0)
pass('Existing Dashboard snapshot functions and endpoints remain wired; local launch never auto-connects network')

local credential=http:JSONEncode({dashboardKey='VY-ABCDEF-123456-ABCDEF-123456'})
Mock.files[oldWeb]=credential
assert(C.Web.LoadConfig()=='VY-ABCDEF-123456-ABCDEF-123456')
assert(not Mock.files[C.Web.configFile] and Mock.files[oldWeb]==credential)
assert(C.Web.SaveConfig() and http:JSONDecode(Mock.files[C.Web.configFile]).dashboardKey==C.Web.key)
assert(Mock.files[oldWeb]==credential and requests==0)
Mock.files[oldWeb]='unchanged credential sentinel'
pass('Existing credential is imported read-only and saved only under the local Dashboard path, separately from UI flags')

local simulatedRequests,verifiedAfterClose=0,0
C.Options.DisableNetwork=false
C.Web.requestFn=function(request)
    simulatedRequests+=1
    if request.Url:find('/api/v2/runtime/verify',1,true) then
        E.task.wait(1);verifiedAfterClose+=1
        return {StatusCode=200,Body=http:JSONEncode({ok=true,user={displayName='Simulated'}})}
    end
    return {StatusCode=200,Body=http:JSONEncode({ok=true})}
end
app.Window:SelectPage('Settings');Mock.advance(.3)
U.Controls.ConnectSaved.Control.Activated:Fire();Mock.advance(.05)
assert(C.NetworkThread and simulatedRequests>0)

U.AutoSave:SetValue(true,true);U.Preferences.Reserve:SetValue('444',true)
app.Window.Close.Activated:Fire();Mock.advance(2)
assert(not C.State.running and Mock.connections==0,'Connections remain after Close: '..Mock.connections)
assert(not Mock.shared.__AROYN_HUB_GREEDY and not Mock.shared.__AROYN_FARM_SINGLETON)
assert(http:JSONDecode(Mock.files[prefPath]).Values.Reserve.Value=='444','Pending AutoSave was not flushed at Close')
assert(not C.NetworkThread and not C.Web.thread and not C.Web.updateThread and verifiedAfterClose==0)
pass('Close destroys actual runtime, library portals, listeners and flushed AutoSave; no production singleton ownership')
pass('Close cancels an in-flight explicit Dashboard verification over a simulated transport before it can save or restart telemetry')

local destroyed=0
Mock.shared.__AROYN_FARM_SINGLETON={Destroy=function() destroyed+=1 end}
local ok,err=pcall(function() runtime(core(),build,{DisableNetwork=true}) end)
assert(not ok and tostring(err):find('Close the existing',1,true) and destroyed==0)
assert(Mock.connections==0 and Mock.shared.__AROYN_FARM_SINGLETON)
Mock.shared.__AROYN_FARM_SINGLETON=nil
pass('Active production singleton causes clean refusal without unloading it or starting duplicate workers')

field.Parent=nil
local bootOk,bootErr=pcall(function() runtime(core(),build,{DisableNetwork=true}) end)
assert(not bootOk and tostring(bootErr):find('BigField',1,true))
Mock.advance(1)
assert(Mock.connections==0 and not Mock.shared.__AROYN_HUB_GREEDY and requests==0)
field.Parent=workspace
pass('Missing game hierarchy fails initialization and cleans singleton/listeners without opening network or production resources')
print('TOTAL '..#results)
