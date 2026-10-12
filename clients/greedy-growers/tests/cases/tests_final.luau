-- Additional final-release negative cases; real adapter/core/runtime, isolated files/transport.
files[new]=nil;files[old]=bytes;files[v2]=nil
app,C,U=start({DisableNetwork=true})
assert(not files[new] and not next(app.Window.Config.Known) and not app.GetDiagnostics().automationEnabled)
assert(C.Options.BuildInfo.Namespace=='greedy-growers' and C.Web.configFile=='AroynHub/GreedyGrowers/web_config.json')
assert(U.Controls.ClientUpdate:GetValue():find('Version 4.3.96',1,true) and not U.Controls.ClientUpdate:GetValue():find('LOCAL',1,true))
pass('Production-intended metadata/namespace is normal and launch performs no profile migration writes or auto-start')
U.Preferences.Reserve:SetValue('111',true);assert(app.Window:SaveConfig('main'));local firstProfile=files[new]
U.Preferences.Reserve:SetValue('222',true);assert(app.Window:SaveConfig('main'));local secondProfile=files[new]
local backup='AroynHub/profile-backups/greedy-growers/main.json'
assert(files[backup]==firstProfile and files[new]==secondProfile and files[old]==bytes)
pass('Second explicit Save verifies a separate last-valid recovery copy before replacing the profile; legacy source retained')
U.Preferences.Reserve:SetValue('333',true)
Mock.writeFault=function(p,s)if p==backup then error('backup write fixture')end;files[p]=s end
local okay,detail=app.Window:SaveConfig('main');assert(not okay and files[new]==secondProfile and detail.Code=='WriteFailed')
Mock.writeFault=nil
pass('Backup-write failure aborts Save before changing the current valid profile and returns a genuine error')
local attempts=0
Mock.writeFault=function(p,s)
    if p==new then attempts+=1;if attempts==1 then files[p]='{partial';error('partial write fixture')end end
    files[p]=s
end
okay,detail=app.Window:SaveConfig('main');assert(not okay and attempts==2 and files[new]==secondProfile and files[backup]==secondProfile)
Mock.writeFault=nil
pass('Partial profile write failure restores verified prior bytes when executor writes recover; no false Save success')
Mock.writeFault=function(p,s)if p==new then files[p]='{partial';error('persistent disk fault')end;files[p]=s end
okay,detail=app.Window:SaveConfig('main');assert(not okay and files[new]=='{partial' and files[backup]==secondProfile)
Mock.writeFault=nil
assert(U.Persistence:Restore('main'));assert(app.Window:LoadConfig('main') and C.State.cashReserve==222 and not app.GetDiagnostics().automationEnabled)
pass('Persistent write failure retains the valid recovery copy; explicit Restore + Load recovers preferences with actions off')
Mock.writeFault=function(p,s)if p==new then files[p]='{silent-truncation';return end;files[p]=s end
okay,detail=app.Window:SaveConfig('main');assert(not okay and files[backup]==secondProfile)
Mock.writeFault=nil;assert(U.Persistence:Restore('main'));assert(app.Window:LoadConfig('main'))
pass('Readback detects silent truncation instead of reporting success; recovery remains explicitly available')
files[new]=JSON.encode({SchemaVersion=999,Namespace='greedy-growers',Values={}});local future=files[new]
assert(not app.Window:SaveConfig('main') and files[new]==future and files[backup]==secondProfile)
files[new]=JSON.encode({SchemaVersion=1,Namespace='unrelated-game',Values={}});local foreign=files[new]
assert(not app.Window:SaveConfig('main') and files[new]==foreign and files[backup]==secondProfile)
files[new]=secondProfile
assert(not U.Persistence:Restore('../outside') and files[old]==bytes)
pass('Unsupported future schema is not overwritten even by Save; recovery names reject path traversal')
local indexed=JSON.decode(files['AroynHub/profiles/greedy-growers/__index.json'])
assert(table.find(indexed.Names,'main') and not table.find(indexed.Names,'backup'))
local listed,listInfo=app.Window:ListConfigs();assert(listed and table.find(listInfo.Names,'main'))
for _,name in ipairs(listInfo.Names)do assert(not name:find('backup',1,true))end
pass('Recovery storage stays outside normal profile enumeration and restore maintains the library index')
local malicious=JSON.decode(secondProfile);malicious.Values.AutoBuy={Type='Toggle',Value=true};malicious.Values.AutoFeed={Type='Toggle',Value=true}
files[new]=JSON.encode(malicious);close(app);app,C,U=start({DisableNetwork=true})
assert(not app.GetDiagnostics().automationEnabled and not C.State.hidePlotVisuals)
U.Controls.AutoBuy:SetValue(true,true);assert(C.State.autoBuyEnabled)
assert(app.Window:LoadConfig('main') and not C.State.autoBuyEnabled)
assert(app.Window:ResetConfig() and not app.GetDiagnostics().automationEnabled)
pass('Even injected saved ON records cannot activate actions on automatic restore, Load or Reset; deliberate GUI Auto Buy still works')
files[new]=secondProfile
close(app);app,C,U=start({DisableNetwork=false})
local requestsSeen=0;local starts,stops=0,0
C.Web.requestFn=function(opts)
    requestsSeen+=1
    if opts.Url:find('/scripts/version.json',1,true) then return {StatusCode=200,Body=JSON.encode({version='4.3.95'})} end
    return {StatusCode=503,Body='failed native-connection fixture'}
end
U.Controls.CheckUpdates.Control.Activated:Fire();Mock.advance(.05)
assert(requestsSeen==1 and not C.NetworkThread and C.Web.latestVersion=='4.3.95')
assert(U.Controls.ClientUpdate:GetValue():find('No newer public version',1,true))
U.DashboardKey:SetValue('VY-ABCDEF-123456-ABCDEF-123456');U.Controls.LinkDashboard.Control.Activated:Fire();Mock.advance(.1)
assert(requestsSeen>1 and C.NetworkThread and C.Dashboard.State=='Reconnecting' and C.State.running and not C.Web.liveConnected)
U.Controls.DisconnectDashboard.Control.Activated:Fire();Mock.advance(.1)
assert(not C.Web.thread and not C.Web.presenceThread and not C.Web.updateThread)
pass('Normal GUI can check updates and initiate real verification over a mock transport without flag edits; 503 is not success; Disconnect cleans owned transport')
close(app)
assert(files[old]==bytes and files[legacyWeb]=='synthetic credential sentinel')
pass('Final normal-mode cleanup retains original credentials/settings and releases every mock listener')
Mock.advance(481)
local nativeFactory,NE=Mock.install(NativeBundleFactory,true)
NE.workspace=world;NE.isfile=function(p)return files[p]~=nil end
NE.getcustomasset=function(p)assert(files[p]:sub(1,8)=='\137PNG\13\10\26\10');return 'mock://native/'..p end
local nativeRequests=0;NE.request=function()nativeRequests+=1;error('Unexpected native startup request')end
Mock.services.ContentProvider={PreloadAsync=function(_,assets,callback)for _,asset in ipairs(assets)do callback(asset,E.Enum.AssetFetchStatus.Success)end end}
local loader=nativeFactory();Mock.advance(1.2)
assert(loader.State=='Ready' and loader.Info.Flavor=='native' and loader.Info.DisplayVersion=='4.3.96 · Native verification')
assert(not loader.App.GetDiagnostics().automationEnabled and nativeRequests==0 and #loader.Window.Pages==8)
local NC=loader.App.Integration;local NU=NC.UI.Integration
NU.Preferences.Reserve:SetValue('456',true);assert(loader.Window:SaveConfig('main'))
assert(files['AroynHubVerification/profiles/greedy-growers-native/main.json'] and files[new]==secondProfile)
NU.Controls.AutoBuy:SetValue(true,true);assert(NC.State.autoBuyEnabled)
assert(loader.Window:LoadConfig('main') and not NC.State.autoBuyEnabled)
loader:Destroy();Mock.advance(1)
assert(Mock.connections==0 and not Mock.shared.__AROYN_HUB_GREEDY_NATIVE and not Mock.shared.__AROYN_HUB_STARTUP_NATIVE)
pass('Entire native artifact executes embedded sources/assets, exposes normal controls, saves only isolated profiles and cleans lifecycle without startup network')
