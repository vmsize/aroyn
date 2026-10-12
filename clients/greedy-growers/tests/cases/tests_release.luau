-- Actual runtime/GUI/config bodies; real JSON codec; all transport/game input synthetic.
local JSON=require('./config-json-mock')
local core,E=Mock.install(CoreFactory,true)
local factory,UE=Mock.install(UIFactory,true)
local runtime,RE=Mock.install(RuntimeFactory,true)
local http=Mock.services.HttpService
http.JSONEncode=function(_,v) return JSON.encode(v) end
http.JSONDecode=function(_,s) return JSON.decode(s) end
local files=Mock.files
local writes={}
for _,env in ipairs({E,UE,RE}) do
    env.isfile=function(p) return files[p]~=nil end
    env.writefile=function(p,s) assert(p~='AroynHub/SeedAutoBuy/settings_v3.json' and p~='AroynHub/web_config.json','Legacy production write');files[p]=s;writes[p]=true end
end
local world=Mock.Instance.new('Workspace');world.CurrentCamera=E.workspace.CurrentCamera
UE.workspace=world;RE.workspace=world
local field=Mock.Instance.new('Folder');field.Name='BigField';field.Parent=world
local conveyor=Mock.Instance.new('Folder');conveyor.Name='ConveyorSeeds';conveyor.Parent=field
local plots=Mock.Instance.new('Folder');plots.Name='PlayerPlots';plots.Parent=field
local plot=Mock.Instance.new('Model');plot:SetAttribute('OwnerUserId',123);plot.Parent=plots
local packages=Mock.Instance.new('Folder');packages.Name='Packages';packages.Parent=Mock.services.ReplicatedStorage
local old='AroynHub/SeedAutoBuy/settings_v3.json';local v2='AroynHub/SeedAutoBuy/settings_v2.json'
local legacyWeb='AroynHub/web_config.json';local new='AroynHub/profiles/greedy-growers/main.json'
local function pass(s) print('PASS '..s) end
local function start(options)
    local library=core();library.IconAtlas='mock://local-navigation'
    local app;E.task.spawn(function() app=runtime(library,factory(),options or {DisableNetwork=true}) end)
    Mock.advance(.3);assert(app and app.Bootstrapped)
    return app,app.Integration,app.Integration.UI.Integration
end
local function close(app) app.Destroy();Mock.advance(1);assert(Mock.connections==0) end
local expected={version=4,selectedSeeds={Oak=true,Removed=true},selectedCompostSeeds={Pine=true},priorities={Oak=1},
    autoBuyEnabled=true,autoFeedPetsEnabled=true,autoMarketEnabled=true,autoCompostEnabled=true,
    autoCollectFruits=true,autoCollectLeaves=true,autoCollectPetSeeds=true,hidePlotVisuals=true,
    maxPrice=123,rateLimit=.25,oneShot=true,stopAfter=5,affordableOnly=true,cashReserve=321,
    petFeedThreshold=30,petFeedTarget=80,petFeedMaxValue=200,spawnAlerts=false,alertRarity='COMMON',
    diagnosticsEnabled=true,hotkey='H',ignored='old-extra-field'}
local bytes=JSON.encode(expected);files[old]=bytes;files[legacyWeb]='synthetic credential sentinel'
local app,C,U=start()
assert(C.State.cashReserve==321 and C.State.maxPrice==123 and C.State.rateLimit==.25)
assert(C.State.stopAfter==5 and C.State.oneShot and C.State.affordableOnly and C.State.hotkey==E.Enum.KeyCode.H)
assert(C.State.petFeedThreshold==30 and C.State.petFeedTarget==80 and C.State.petFeedMaxValue==200)
assert(C.State.selectedSeeds.Oak and not C.State.selectedSeeds.Removed and C.State.selectedCompostSeeds.Pine)
assert(not app.GetDiagnostics().automationEnabled and not C.State.hidePlotVisuals and files[old]==bytes and not files[new])
pass('V4 legacy preferences import from real JSON is deterministic, unknown seeds are removed, eight action flags stay off, old bytes remain untouched')
assert(C.Web.clientVersion=='4.3.96' and U.Controls.ClientUpdate:GetValue():find('Version 4.3.96',1,true))
assert(C.Web.IsRemoteVersionNewer('4.3.97',C.Web.clientVersion) and not C.Web.IsRemoteVersionNewer('4.3.95',C.Web.clientVersion))
pass('Authoritative proposed version is shared by startup metadata, diagnostics, snapshot and real semver update comparison')
local info=MetadataFactory();assert(info.ClientVersion==C.Web.clientVersion and info.DisplayVersion:find(C.Web.clientVersion,1,true) and info.Channel=='release-candidate')
C.Web.requestFn=function(opts)
    assert(opts.Method=='GET' and not opts.Headers.Authorization and opts.Url:find('/scripts/version.json',1,true))
    return {StatusCode=200,Body=JSON.encode({version='4.3.97'})} -- isolated future-version fixture, not release metadata
end
assert(C.Web.CheckUpdateOnce());Mock.advance(.05)
assert(U.Controls.ClientUpdate:GetValue():find('Update available: 4.3.97',1,true))
C.Web.requestFn=function()return {StatusCode=503,Body='unavailable fixture'} end
assert(not C.Web.CheckUpdateOnce() and C.State.running)
pass('Restored GUI update notice uses actual update-check callback; manifest error does not stop the Hub')
local snap=C.Web.BuildSnapshot();local raw=JSON.encode(snap);local decoded=JSON.decode(raw)
assert(decoded.schemaVersion==1 and decoded.type=='snapshot' and decoded.product.version=='4.3.96')
assert(decoded.player.userId and decoded.session.id and not raw:find('synthetic credential sentinel',1,true))
pass('Actual Dashboard snapshot serializes and roundtrips real JSON schemaVersion=1 with candidate version and no credential')
assert(app.Window:SaveConfig('main'));local saved=files[new];local config=JSON.decode(saved)
assert(config.SchemaVersion==1 and config.Namespace=='greedy-growers')
for _,k in ipairs({'AutoBuy','AutoFeed','AutoCompost','AutoCollect','AutoLeaves','AutoPetDrops','AutoMarket','HidePlot','DashboardKey'}) do assert(config.Values[k]==nil) end
for p in pairs(writes) do assert(p:find('greedy-growers',1,true)) end
assert(files[old]==bytes and files[legacyWeb]=='synthetic credential sentinel')
pass('Actual Save writes an isolated SchemaVersion=1 file and index, excludes gameplay flags and credentials, retains production files as untouched backup')
local petScan,leafScan=C.Farm.scanPetSeeds,C.Farm.scanLeaves;local petTicks,leafTicks=0,0
C.Farm.scanPetSeeds=function()petTicks+=1 end;C.Farm.scanLeaves=function()leafTicks+=1 end
C.State.autoCollectPetSeeds=true;C.State.autoCollectLeaves=true
local p,l=petTicks,leafTicks;Mock.advance(1.05)
assert(petTicks==p+1 and leafTicks==l+1,'Existing maintenance loop lost periodic collection scans or duplicated tick')
C.State.autoCollectPetSeeds=false;C.State.autoCollectLeaves=false
p,l=petTicks,leafTicks;Mock.advance(1.05);assert(petTicks==p and leafTicks==l)
C.Farm.scanPetSeeds=petScan;C.Farm.scanLeaves=leafScan
pass('Existing maintenance tick rescans enabled pet drops and leaves exactly once, skips disabled features, and adds no second timer')
U.SeedSearch:SetValue('pine',true);U.CompostSearch:SetValue('oak',true)
assert(table.find(U.Preferences.Seeds:GetOptions(),'Oak') and table.find(U.Preferences.Seeds:GetOptions(),'Pine'))
assert(C.State.selectedSeeds.Oak and C.State.selectedCompostSeeds.Pine)
U.SeedSearch:SetValue('no-match fixture',true);assert(#U.Preferences.Seeds:GetOptions()==1 and U.Preferences.Seeds:GetOptions()[1]=='Oak')
U.CompostSearch:SetValue('no-match fixture',true);assert(#U.Preferences.CompostSeeds:GetOptions()==1 and U.Preferences.CompostSeeds:GetOptions()[1]=='Pine')
assert(app.Window:LoadConfig('main'));assert(U.SeedSearch:GetValue()=='' and U.CompostSearch:GetValue()=='')
assert(#U.Preferences.Seeds:GetOptions()==#C.Records and C.State.selectedSeeds.Oak and C.State.selectedCompostSeeds.Pine)
pass('Restored name/rarity searches preserve hidden selections and config loading resets filters before normalizing full seed options')
U.Preferences.Reserve:SetValue('789',true);C.Setters.AutoBuy(true)
assert(app.Window:LoadConfig('main'));assert(C.State.cashReserve==321 and not app.GetDiagnostics().automationEnabled)
close(app)
app,C,U=start();assert(C.State.cashReserve==321 and not app.GetDiagnostics().automationEnabled)
pass('Fresh manager loads saved preferences across executions and never restores enabled automation')
local reserve=C.State.cashReserve;files[new]='{broken JSON'
assert(not app.Window:LoadConfig('main') and C.State.cashReserve==reserve and C.State.running)
files[new]=JSON.encode({SchemaVersion=999,Namespace='greedy-growers',Values={Reserve={Type='Input',Value='900'}}})
assert(not app.Window:LoadConfig('main') and C.State.cashReserve==reserve)
files[new]=saved;assert(app.Window:LoadConfig('main'))
pass('Corrupt and unsupported config schemas fail without overwriting files or losing prior preferences; valid backup can be reloaded')
local fs=app.Window.Config.FileSystem;local writer=fs.writefile
fs.writefile=function()error('isolated disk failure fixture')end
assert(not app.Window:SaveConfig('main') and files[new]==saved)
fs.writefile=writer;assert(app.Window:SaveConfig('main'))
pass('Failed profile write preserves the previous valid file and manager recovers on subsequent Save')
close(app);files[new]=nil;files[old]=nil;files[v2]=bytes
app,C,U=start();assert(C.State.cashReserve==321 and C.State.settingsMigrated and files[v2]==bytes)
close(app);files[v2]=nil;files[old]='invalid legacy JSON'
app,C,U=start();assert(C.State.settingsFailure=='settings file is corrupt' and C.State.running and not app.GetDiagnostics().automationEnabled)
assert(files[old]=='invalid legacy JSON');close(app)
pass('V2 fallback import and malformed legacy JSON failure retain originals and allow safe default startup')
files[old]=bytes
local calls=0;RE.request=function() calls+=1;error('No live network permitted') end
app,C,U=start({DisableNetwork=true})
assert(not app.GetDiagnostics().automationEnabled and not C.State.hidePlotVisuals)
assert(app.Window:SaveConfig('main'))
local fields={AutoBuy='autoBuyEnabled',AutoCompost='autoCompostEnabled',AutoCollect='autoCollectFruits',AutoLeaves='autoCollectLeaves',AutoPetDrops='autoCollectPetSeeds',AutoMarket='autoMarketEnabled',AutoFeed='autoFeedPetsEnabled',HidePlot='hidePlotVisuals'}
for key,field in pairs(fields) do
    E.task.spawn(function() U.Controls[key]:SetValue(true,true) end);Mock.advance(.4)
    assert(C.State[field] and U.Controls[key]:GetValue(),'Normal user action was blocked: '..key)
    E.task.spawn(function() U.Controls[key]:SetValue(false,true) end);Mock.advance(.4);assert(not C.State[field])
end
assert(app.Window:LoadConfig('main'));assert(not app.GetDiagnostics().automationEnabled)
assert(app.Window:ResetConfig());assert(not app.GetDiagnostics().automationEnabled)
U.Controls.ConnectSaved.Control.Activated:Fire();Mock.advance(.05)
assert(calls==0 and not C.NetworkThread) -- injected DisableNetwork boundary, not a bundled policy
pass('Normal candidate permits every user action without diagnostic flags; Boot/Load/Reset still keep automation off')
close(app)
assert(files[old]==bytes and files[legacyWeb]=='synthetic credential sentinel')
pass('Candidate cleanup disconnects all listeners and preserves every production settings/credential fixture')
local unloaded=0;local previous={Destroy=function()unloaded+=1 end}
Mock.shared.__AROYN_GREEDY_PHASE6A=previous
local okay,err=pcall(function()runtime(core(),factory(),{DisableNetwork=true})end)
assert(not okay and tostring(err):find('Close the existing',1,true) and unloaded==0 and Mock.shared.__AROYN_GREEDY_PHASE6A==previous)
Mock.shared.__AROYN_GREEDY_PHASE6A=nil
Mock.shared.__AROYN_PHASE9A_STARTUP=previous
okay,err=pcall(function()runtime(core(),factory(),{DisableNetwork=true})end)
assert(not okay and unloaded==0);Mock.shared.__AROYN_PHASE9A_STARTUP=nil
assert(Mock.connections==0)
pass('Candidate refuses a running predecessor integration or in-progress predecessor startup without destroying them or duplicating game workers')
