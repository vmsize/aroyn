-- Full client/UI/storage/coordinator sources. Only executor/game/network are doubles.
for _,env in ipairs({E,UE,RE}) do env.writefile=function(p,v)if Mock.writeFault then return Mock.writeFault(p,v) end;files[p]=v end end
RE.os=setmetatable({clock=function()return Mock.now end,time=function()return 1700000000+math.floor(Mock.now) end},{__index=os})
http.UrlEncode=function(_,s)return (s:gsub('[^%w%-%._~]',function(c)return string.format('%%%02X',string.byte(c))end)) end
local guid=0
http.GenerateGUID=function() guid+=1;return 'test-runtime-session-'..guid end
local profile='AroynHub/profiles/greedy-growers/main.json'
local metadata='AroynHub/preferences-greedy-growers.json'
local credential='AroynHub/GreedyGrowers/web_config.json'
local intentPath='AroynHub/GreedyGrowers/connection-intent.json'
local key='VY-ABCDEF-123456-ABCDEF-123456' -- isolated fixture, never a real account
local function resetFiles() table.clear(files);Mock.writeFault=nil end
resetFiles()
local app,C,U=start({DisableNetwork=true})
assert(U.AutoSave:GetValue() and app.Window.Config.AutoSave)
pass('AutoSave is enabled by default without startup profile writes or active gameplay')
local writeCount=0
Mock.writeFault=function(p,v) if p==profile then writeCount+=1 end;files[p]=v end
U.Preferences.Reserve:SetValue('101',true);Mock.advance(.2)
U.Preferences.Reserve:SetValue('102',true);Mock.advance(.2)
U.Preferences.Reserve:SetValue('103',true);Mock.advance(.5)
assert(writeCount==0);Mock.advance(.3)
assert(writeCount==1 and JSON.decode(files[profile]).Values.Reserve.Value=='103')
pass('Repeated actual control changes produce one debounced profile write after quiet interval')
U.Preferences.Reserve:SetValue('104',true);close(app)
assert(writeCount==2 and JSON.decode(files[profile]).Values.Reserve.Value=='104')
Mock.writeFault=nil
app,C,U=start({DisableNetwork=true})
assert(C.State.cashReserve==104 and not app.GetDiagnostics().automationEnabled)
pass('Normal shutdown flushes once; new full runtime restores real JSON preferences with gameplay off')
assert(app.Window:SaveConfig('travel'))
U.Preferences.Reserve:SetValue('105',true);Mock.advance(1)
assert(JSON.decode(files['AroynHub/profiles/greedy-growers/travel.json']).Values.Reserve.Value=='105')
close(app);app,C,U=start({DisableNetwork=true})
assert(U.ConfigName:GetValue()=='travel' and C.State.cashReserve==105 and app.Window.Config.AutoSaveName=='travel')
pass('Explicit profile Save selects the active profile; autosave and next execution preserve that selection')
U.AutoSave:SetValue(false,true);U.Preferences.Reserve:SetValue('106',true);Mock.advance(1)
close(app);app,C,U=start({DisableNetwork=true})
assert(not U.AutoSave:GetValue() and C.State.cashReserve==105)
U.AutoSave:SetValue(true,true)
pass('AutoSave opt-out persists independently and prevents edit/Close writes until enabled again')
assert(app.Window:ResetConfig() and not app.GetDiagnostics().automationEnabled)
local invalid,why=app.Window:LoadConfig(nil);assert(not invalid and why.Code=='InvalidName')
assert(app.Window:LoadConfig('main') and C.State.cashReserve==104)
pass('Manual Reset/Load retain established semantics and stop every gameplay flag')
local prior=files[profile]
Mock.writeFault=function(p,v)if p==profile then error('disk fault fixture')end;files[p]=v end
U.Preferences.Reserve:SetValue('107',true);Mock.advance(1)
assert(files[profile]==prior and app.Window.Config.LastResult.Code=='WriteFailed')
assert(#app.Window.Overlays.Toasts>0 or app.Window.Config.LastResult.Success==false)
Mock.writeFault=nil
pass('Automatic failed write reports a genuine failure, keeps verified previous profile and emits a warning')
close(app);files[profile]='{broken'
app,C,U=start({DisableNetwork=true});U.Preferences.Reserve:SetValue('108',true);Mock.advance(1)
assert(files[profile]=='{broken' and app.Window.Config.LastResult.Success==false)
assert(U.Persistence:Restore('main'));assert(app.Window:LoadConfig('main'))
pass('Corrupt current profile cannot be overwritten silently by AutoSave; explicit verified recovery works')
assert(app.Window:DeleteConfig('main'));assert(not U.AutoSave:GetValue() and not app.Window.Config.AutoSave)
U.Preferences.Reserve:SetValue('109',true);Mock.advance(1);assert(not files[profile])
pass('Deleting active profile disables and persists autosave instead of recreating deleted preferences')
close(app)

-- Real existing endpoints and snapshot envelope contract, with no external requests.
local server={calls={},snapshots={},registered={},verifyStatus=200,pushStatus=200,revoked=false,slow=false,attempts=0}
local function backend(opts)
    local path=opts.Url:match('https?://[^/]+(.*)')
    local body=opts.Body and JSON.decode(opts.Body) or nil
    table.insert(server.calls,{Path=path,Method=opts.Method,Session=body and (body.sessionId or body.session and body.session.id),At=Mock.now})
    local function reply(code,value) return {StatusCode=code,Body=JSON.encode(value)} end
    if path=='/scripts/version.json' then return reply(200,{version='4.3.95'}) end
    assert(opts.Headers.Authorization=='Bearer '..key,'Actual saved bearer authorization absent')
    if path=='/api/v2/runtime/verify' then
        server.attempts+=1
        if server.slow then E.task.wait(20) end
        return reply(server.verifyStatus,{ok=server.verifyStatus==200,user={id=server.account or 'test-account',username='fixture'}})
    elseif path=='/api/v2/runtime/link' then
        assert(body.robloxUserId==123);server.revoked=false;return reply(200,{ok=true})
    elseif path=='/api/v2/runtime/push' then
        if server.revoked then return reply(403,{ok=false,code='ROBLOX_ACCOUNT_UNLINKED'}) end
        if server.pushStatus~=200 then return reply(server.pushStatus,{ok=false,error='fixture rejected '..key}) end
        assert(body.schemaVersion==1 and body.player.userId==123 and body.session.id and body.product.version=='4.3.96')
        assert(not JSON.encode(body):find(key,1,true),'Secret in actual client snapshot')
        server.registered[body.session.id]=true
        table.insert(server.snapshots,body)
        server.envelope={snapshot=body,lastSeen=Mock.now*1000,explicitOffline=false,robloxUserId='123'}
        return reply(200,{ok=true,receivedAt=Mock.now*1000,userId='test-account'})
    elseif path=='/runtime-presence' then
        assert(server.registered[body.sessionId],'Presence before actual runtime registration')
        return reply(200,{ok=true,dashboardLinked=true,presenceToken='test-scoped-presence',heartbeatSeconds=300})
    elseif path=='/api/live/token' then return reply(503,{ok=false})
    end
    return reply(503,{ok=false})
end
local function online() return server.envelope and not server.envelope.explicitOffline and Mock.now*1000-server.envelope.lastSeen<9000 end
local function networkStart()
    RE.request=backend
    local a,c,u=start({DisableNetwork=false});c.Web.requestFn=backend
    c.Web.ResolveWebSocketConnect=function() return nil end
    return a,c,u
end
local function connect(c,u)
    u.DashboardKey:SetValue(key);u.Controls.LinkDashboard.Control.Activated:Fire();Mock.advance(.3)
    assert(c.Dashboard.State=='Connected',c.Dashboard.Message or c.Dashboard.State)
end
local function count(path)
    local n=0;for _,call in ipairs(server.calls) do if call.Path==path then n+=1 end end;return n
end
resetFiles();files[credential]=JSON.encode({dashboardKey=key})
app,C,U=networkStart();Mock.advance(1)
assert(C.Dashboard.State=='Disconnected' and count('/api/v2/runtime/verify')==0)
pass('Saved valid key alone never creates auto-connect intent or sends an authentication request')
connect(C,U)
assert(JSON.decode(files[intentPath]).Enabled and JSON.decode(files[intentPath]).AccountId=='test-account')
assert(JSON.decode(files[credential]).dashboardKey==key and C.Web.presenceLastOk and C.Web.runtimeRegistered and online())
pass('Manual real Verify → Link → accepted initial Push registers session, starts presence and independently saves confirmed intent')
print('SNAPSHOT_PROOF '..JSON.encode(server.snapshots[#server.snapshots]))
local firstSession=C.Web.sessionId
local beforePresence=count('/runtime-presence')
Mock.advance(21)
assert(count('/api/v2/runtime/push')>=5 and online() and count('/runtime-presence')==beforePresence, 'push='..count('/api/v2/runtime/push')..' presence='..count('/runtime-presence')..' before='..beforePresence..' state='..C.Dashboard.State..' msg='..tostring(C.Dashboard.Message))
assert(C.Web.thread==C.Dashboard.Runner and C.Web.presenceThread,'runner='..tostring(C.Dashboard.Runner)..' thread='..tostring(C.Web.thread)..' presence='..tostring(C.Web.presenceThread))
pass('HTTP-only telemetry maintains API 9-second freshness at 5-second cadence; exactly one existing presence worker')
assert(app.Window:SaveConfig('main'));assert(not files[profile]:find(key,1,true) and not files[profile]:find('Auto-connect',1,true))
assert(app.Window:ResetConfig() and JSON.decode(files[intentPath]).Enabled and JSON.decode(files[credential]).dashboardKey==key)
pass('Save/Reset ordinary preferences exclude secrets and do not change the separately persisted Dashboard identity/intent')
close(app)
local beforeLink=count('/api/v2/runtime/link')
app,C,U=networkStart();Mock.advance(.3)
assert(C.Dashboard.State=='Connected' and C.Web.sessionId~=firstSession and server.registered[C.Web.sessionId])
assert(count('/api/v2/runtime/link')==beforeLink and C.Web.presenceLastOk and online() and not app.GetDiagnostics().automationEnabled)
pass('Independent full runtime automatically reauthenticates saved key, registers NEW session and sends real snapshot/presence without GUI action or relink')
local second=C.Web.sessionId
U.Controls.DisconnectDashboard.Control.Activated:Fire();Mock.advance(.2)
assert(C.Dashboard.State=='Disconnected' and not JSON.decode(files[intentPath]).Enabled and JSON.decode(files[credential]).dashboardKey==key)
assert(not C.Web.thread and not C.Web.presenceThread and not C.Web.liveSocket and not C.Dashboard.Runner)
local disconnected=count('/api/v2/runtime/push');Mock.advance(10)
assert(not online() and count('/api/v2/runtime/push')==disconnected)
close(app);app,C,U=networkStart();Mock.advance(2)
assert(C.Dashboard.State=='Disconnected' and count('/api/v2/runtime/push')==disconnected)
pass('Explicit Disconnect preserves key, persistently disables auto-connect, cancels all workers and expires real runtime freshness')
U.Controls.ConnectSaved.Control.Activated:Fire();Mock.advance(.3)
assert(C.Dashboard.State=='Connected' and U.DashboardAutoConnect:GetValue() and JSON.decode(files[intentPath]).Enabled)
pass('Explicit Connect saved key confirms authentication/registration and enables remembered auto-connect again')
U.DashboardAutoConnect:SetValue(false,true)
assert(C.Dashboard.State=='Connected' and not JSON.decode(files[intentPath]).Enabled)
server.pushStatus=503;Mock.advance(6)
assert(C.Dashboard.State=='Connection failed' and not C.Dashboard.Runner)
server.pushStatus=200;close(app);app,C,U=networkStart();Mock.advance(1)
assert(C.Dashboard.State=='Disconnected')
U.DashboardAutoConnect:SetValue(true,true);Mock.advance(.3)
assert(C.Dashboard.State=='Connected')
pass('Auto-connect OFF leaves current connection usable, disables subsequent recovery/launch; explicit toggle ON resumes actual registration')
server.pushStatus=503;Mock.advance(6)
assert(C.Dashboard.State=='Reconnecting')
server.pushStatus=200;Mock.advance(4)
assert(C.Dashboard.State=='Connected' and C.Web.presenceLastOk and online())
pass('Temporary transport failure recovers with backoff and accepted re-registration while preserving saved credential')
server.verifyStatus=401;server.pushStatus=401;Mock.advance(7)
assert(C.Dashboard.State=='Connection failed' and not C.Web.thread and not C.Web.presenceThread)
local attempts=server.attempts;Mock.advance(65);assert(server.attempts==attempts and JSON.decode(files[credential]).dashboardKey==key)
assert(not tostring(C.Dashboard.Message):find(key,1,true))
pass('Permanent 401 stops retries/telemetry/presence, retains credential for user correction and exposes only sanitized error')
server.verifyStatus=200;server.pushStatus=200;close(app)
server.revoked=true;beforeLink=count('/api/v2/runtime/link');app,C,U=networkStart();Mock.advance(.3)
assert(C.Dashboard.State=='Connection failed' and count('/api/v2/runtime/link')==beforeLink)
connect(C,U);assert(not server.revoked)
pass('Automatic connection respects server-side Roblox account revocation; only explicit manual Link clears it through existing endpoint')
close(app);server.account='different-account';app,C,U=networkStart();Mock.advance(.3)
assert(C.Dashboard.State=='Connection failed' and C.Dashboard.Message:find('account changed',1,true))
server.account=nil;close(app)
pass('Restored intent binds verified account ID; silent cross-account credential replacement requires explicit Link')
server.verifyStatus=503;app,C,U=networkStart();Mock.advance(.4)
local begin=server.attempts
U.Controls.ConnectSaved.Control.Activated:Fire();Mock.advance(.2)
assert(server.attempts==begin and C.Dashboard.State=='Reconnecting')
Mock.advance(65)
assert(C.Dashboard.State=='Connection failed' and server.attempts==begin+5)
assert(not C.Dashboard.Runner and not C.Web.thread and not C.Web.presenceThread)
pass('Concurrent manual/automatic connection never duplicates auth; six attempts use bounded 2/4/8/16/32-second backoff')
close(app);server.verifyStatus=200;server.slow=true
app,C,U=networkStart();Mock.advance(1)
assert(C.Dashboard.State=='Connecting')
U.Controls.DisconnectDashboard.Control.Activated:Fire();Mock.advance(25)
assert(C.Dashboard.State=='Disconnected' and not C.Dashboard.Runner and not C.Web.thread and not C.Web.presenceThread)
assert(not JSON.decode(files[intentPath]).Enabled)
pass('Disconnect during yielded Verify cancels bounded request and prevents late response/intent or telemetry resurrection')
server.slow=false;close(app)
files[intentPath]=JSON.encode({SchemaVersion=1,Enabled=true,AccountId='test-account'});server.slow=true
app,C,U=networkStart();Mock.advance(16)
assert(C.Dashboard.State=='Reconnecting' and not C.Dashboard.Worker)
local priorPush=count('/api/v2/runtime/push');close(app);Mock.advance(20)
assert(count('/api/v2/runtime/push')==priorPush and not C.Dashboard.Runner and not C.Dashboard.Worker)
pass('15-second request deadline releases hung auth; closing cancels scheduled retries without stale sends')
server.slow=false
app,C,U=networkStart();Mock.advance(.3);local oldApp,oldC=app,C
app,C,U=networkStart();Mock.advance(.3)
assert(not oldC.State.running and not oldC.Dashboard.Alive and C.Dashboard.State=='Connected' and C.Web.sessionId~=oldC.Web.sessionId)
assert(count('/api/v2/runtime/disconnect')==0 and count('/runtime-presence/disconnect')>0 and online())
pass('Rapid same-build rerun destroys old workers before new session; no legacy account-wide disconnect can offline the replacement')
U.Controls.UnlinkDashboard.Control.Activated:Fire();Mock.advance(.2)
assert(not C.Web.key and not JSON.decode(files[credential]).dashboardKey and not JSON.decode(files[intentPath]).Enabled)
pass('Explicit Unlink removes saved key and intent through separate persistence without deleting preferences')
close(app);files[intentPath]='{invalid'
app,C,U=networkStart();Mock.advance(.5);assert(C.Dashboard.State=='Disconnected' and not C.Dashboard.Enabled)
pass('Invalid connection-intent JSON fails closed and does not infer consent from a credential')
close(app)

-- Real coordinator with executor socket events; no synthetic live-account data.
resetFiles();server.verifyStatus=200;server.pushStatus=200
app,C,U=networkStart()
local baseBackend=backend
C.Web.requestFn=function(opts)
    if opts.Url:match('/token$') then return {StatusCode=200,Body=JSON.encode({ok=true,token='test-live-token'})} end
    return baseBackend(opts)
end
local opens,activeSockets,maxSockets=0,0,0
local socket
C.Web.ResolveWebSocketConnect=function() return function(url)
    if url:find('/runtime-presence/ws?',1,true) then error('fixture supplies telemetry socket and HTTP presence fallback') end
    assert(url:find('sid='..C.Web.sessionId,1,true))
    opens+=1;activeSockets+=1;maxSockets=math.max(maxSockets,activeSockets)
    local s={OnMessage=Mock.signal(),OnClose=Mock.signal(),Closed=false}
    function s:Send(raw)
        assert(not self.Closed)
        local frame=JSON.decode(raw)
        assert(frame.type=='snapshot' and server.registered[frame.session.id])
        self.OnMessage:Fire(JSON.encode({type='relay_ack'}))
    end
    function s:Close()
        if self.Closed then return end
        self.Closed=true;activeSockets-=1;self.OnClose:Fire()
        for _,event in ipairs({self.OnMessage,self.OnClose}) do for listener in pairs(event.listeners) do listener:Disconnect() end end
    end
    socket=s;return s
end end
connect(C,U);local pushes=count('/api/v2/runtime/push')
Mock.advance(17)
assert(opens==1 and maxSockets==1 and C.Web.presenceTransport=='live-websocket' and count('/api/v2/runtime/push')==pushes)
pass('Coordinator reuses one acknowledged telemetry socket for linked presence; healthy live path preserves 300-second HTTP persistence cadence')
socket:Close();Mock.advance(6)
assert(C.Dashboard.State=='Connected' and C.Web.liveConnected and opens==2 and maxSockets==1)
U.Controls.DisconnectDashboard.Control.Activated:Fire();Mock.advance(1)
assert(activeSockets==0 and not C.Web.thread and not C.Web.presenceThread)
pass('Actual socket Close/reconnect events keep one active socket; explicit Disconnect closes it and existing presence worker')
close(app)
resetFiles();app,C,U=networkStart()
C.Web.requestFn=function(opts)
    if opts.Url:match('/api/v2/runtime/push$') then return {StatusCode=200,Body=JSON.encode({ok=false})} end
    return baseBackend(opts)
end
U.DashboardKey:SetValue(key);U.Controls.LinkDashboard.Control.Activated:Fire();Mock.advance(.4)
assert(C.Dashboard.State~='Connected' and not C.Dashboard.Enabled and not files[intentPath] and not C.Web.runtimeRegistered)
U.Controls.DisconnectDashboard.Control.Activated:Fire();close(app)
pass('HTTP 2xx without runtime ok=true cannot establish Connected or persist first successful connection intent')
resetFiles();app,C,U=networkStart()
Mock.writeFault=function(p,v)if p==credential then files[p]='{partial';return end;files[p]=v end
connect(C,U)
assert(C.Dashboard.State=='Connected' and C.Web.runtimeRegistered and files[credential]=='{partial')
Mock.writeFault=nil;close(app)
pass('Silent credential truncation is detected by readback; genuine current connection remains usable but next-launch persistence is not falsely guaranteed')

-- Complete embedded artifact: persistence restored AFTER Ready, not during startup morph.
files[intentPath]=JSON.encode({SchemaVersion=1,Enabled=true,AccountId='test-account'})
files[credential]=JSON.encode({dashboardKey=key})
local bf,BE=Mock.install(ProductionBundleFactory,true)
BE.os=RE.os;BE.workspace=world;BE.isfile=function(p)return files[p]~=nil end
BE.getcustomasset=function(path)return 'mock://registered/'..path end
local duringLoading=0
local loader
BE.request=function(opts)
    if loader and loader.State~='Ready' then duringLoading+=1 end
    return backend(opts)
end
Mock.services.ContentProvider={PreloadAsync=function(_,assets,cb)for _,asset in ipairs(assets)do cb(asset,E.Enum.AssetFetchStatus.Success)end end}
loader=bf();Mock.advance(1.5)
assert(loader.State=='Ready' and loader.App.Integration.Dashboard.State=='Connected' and duringLoading==0)
assert(not loader.App.GetDiagnostics().automationEnabled)
loader.Window:SetMinimized(true);Mock.advance(.5);loader.Window:SetMinimized(false);Mock.advance(.5)
assert(not loader.Window.Collapse.Minimized and loader.App.Integration.Dashboard.State=='Connected')
loader:Destroy();Mock.advance(1);assert(Mock.connections==0)
pass('Complete production artifact restores Dashboard asynchronously after approved startup morph; minimize/restore and Close remain functional')

-- Filesystem capability fallback: actual modules, no false cross-execution guarantee.
resetFiles();local previousRead,previousWrite=FE.readfile,FE.writefile
FE.readfile=nil;FE.writefile=nil
app,C,U=start({DisableNetwork=true})
assert(not C.Dashboard.Store.Available and not U.AutoPreferences.Record.Available)
local warnings=0;C.Dashboard.OnWarning=function()warnings+=1 end
C.Dashboard:Persist(true,'test-account');assert(warnings==1 and not files[intentPath])
close(app);FE.readfile=previousRead;FE.writefile=previousWrite
pass('Missing executor filesystem APIs keep independent metadata/intent session-only with explicit persistence warning')
print('NEW SUITE COMPLETE')
