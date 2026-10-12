-- Actual startup and embedded PNG adapter; fake executor/renderer/network only.
local count=0
local function assetPass(name) count+=1;print('ASSET_PASS '..name) end
local oldProvider=Mock.services.ContentProvider
local function hangProvider()
    Mock.services.ContentProvider={PreloadAsync=function() E.task.wait(60) end}
end
local function markImages(s,logo,atlas)
    s.Logo.IsLoaded=logo
    if s.AssetProbe then s.AssetProbe.IsLoaded=atlas end
end
hangProvider();s=start();Mock.advance(.1);markImages(s,true,true);Mock.advance(1.2)
assert(s.State=='Ready' and s.Completed==7 and s.AssetVerification=='ImageLabel.IsLoaded')
assert(not s.AssetWorker and not s.AssetProbe and not s.AssetLoadRecord);clean(s)
assetPass('Hanging preload does not block actually loaded logo AND atlas; owned preload/probe cleaned')
Mock.services.ContentProvider={PreloadAsync=function(_,urls,cb)
    for _,url in ipairs(urls) do cb(url,E.Enum.AssetFetchStatus.Success) end
    E.task.wait(60)
end}
s=start();Mock.advance(1.2);assert(s.State=='Ready' and s.AssetVerification=='ContentProvider.Success');clean(s)
assetPass('Both genuine success callbacks suffice even if PreloadAsync completion stalls')
hangProvider();s=start();Mock.advance(.1);markImages(s,true,false);Mock.advance(44.99)
assert(s.State=='Failed' and s.Completed==0 and s.Error:find('Loading logo',1,true) and s.Status.Text:find('timed out',1,true))
assert(s.CloseButton and s.RetryButton and not s.AssetProbe);clean(s)
assetPass('Only one loaded image never fabricates success; visible detailed timeout at 45s')
Mock.services.ContentProvider={PreloadAsync=function() end}
s=start();Mock.advance(1.2);assert(s.Completed==0 and s.State=='Loading');Mock.advance(44)
assert(s.State=='Failed' and s.Completed==0);clean(s)
assetPass('Preload return without callbacks or IsLoaded is not asset readiness')
Mock.services.ContentProvider={PreloadAsync=function(_,urls,cb) cb(urls[1],E.Enum.AssetFetchStatus.Success) end}
s=start();Mock.advance(45.2);assert(s.State=='Failed' and s.Completed==0);clean(s)
assetPass('Partial preload acknowledgement cannot advance the seven real stages')
Mock.services.ContentProvider={PreloadAsync=function() error('fixture unsupported preload') end}
s=start();Mock.advance(.2);assert(s.State=='Failed' and s.Error:find('preload failed',1,true));clean(s)
assetPass('Thrown preload error reaches error card and cleans worker/probe')
local late
Mock.services.ContentProvider={PreloadAsync=function(_,urls,cb) late=function()for _,url in ipairs(urls)do cb(url,E.Enum.AssetFetchStatus.Success)end end;E.task.wait(60)end}
s=start();Mock.advance(.1);s:Destroy();late();Mock.advance(.2)
assert(s.State=='Destroyed' and not s.AssetLoadRecord);clean(s)
assetPass('Late native callbacks after Close cannot advance or recreate startup')
Mock.services.ContentProvider=oldProvider
local factory,AE=Mock.install(AssetsFactory,true)
AE.getcustomasset=function(path)return 'mock://registered/'..path end
AE.crypt={base64decode=function()return 'wrong native decoder result' end}
local reports={}
s=start(nil,function(A,report)
    factory()(A,function(message) reports[message]=true;report(message) end)
end);Mock.advance(1.5);assert(s.State=='Ready')
local atlas=Mock.files[info.AssetRoot..'/aroyn_navigation_phase6a_grid_v2_128.png']
local logo=Mock.files[info.AssetRoot..'/aroyn_existing_logo.png']
assert(atlas:sub(1,8)=='\137PNG\r\n\26\n' and logo:sub(1,8)=='\137PNG\r\n\26\n')
assert(reports['Decoding icon atlas PNG…'] and reports['Verifying logo PNG…']);clean(s)
assetPass('Invalid native decoder falls back to actual embedded PNG decoding with real substage reporting')
local read=AE.readfile;AE.readfile=function()return 'truncated' end
s=start(nil,factory());Mock.advance(.4)
assert(s.State=='Failed' and s.Completed==0 and s.Error:find('readback failed',1,true));clean(s);AE.readfile=read
assetPass('Binary PNG write/readback corruption is rejected before custom asset registration')
local custom=AE.getcustomasset;AE.getcustomasset=nil
s=start(nil,factory());Mock.advance(.2);assert(s.State=='Failed' and s.Error:find('custom asset API unavailable',1,true));clean(s);AE.getcustomasset=custom
assetPass('Missing custom asset API identifies the actual capability failure on the card')
AE.getcustomasset=function(path) E.task.wait(60);return 'mock://'..path end
s=start(nil,factory());Mock.advance(.2)
assert(s.Status.Text=='Registering icon atlas (getcustomasset)…' and s.Completed==0)
Mock.advance(45.1)
assert(s.State=='Failed' and s.Error:find('Registering icon atlas',1,true) and s.Status.Text:find('Registering icon atlas',1,true));clean(s)
AE.getcustomasset=custom
assetPass('Yielded native getcustomasset has a visible precise register-stage timeout; no gameplay bootstrap')
AE.readfile=nil
s=start(nil,factory());Mock.advance(1.5);assert(s.State=='Ready');clean(s);AE.readfile=read
assetPass('Optional missing PNG readback API keeps existing write/customasset compatibility')
local write=AE.writefile;AE.writefile=function()error('fixture write failure')end
s=start(nil,factory());Mock.advance(.2);assert(s.State=='Failed' and s.Error:find('writefile failed',1,true));clean(s);AE.writefile=write
assetPass('Filesystem write failure is shown instead of staying at an ambiguous 0/7')
-- Rejected native cancellation does not fabricate readiness or let a late callback own a new session.
local normalTask=SE.task;local rejected=0
hangProvider();s=start();Mock.advance(.1);local nativeWorker=s.AssetWorker
SE.task=setmetatable({cancel=function(t)if t==nativeWorker then rejected+=1;error('fixture cannot cancel native worker')end;return normalTask.cancel(t)end},{__index=normalTask})
markImages(s,true,true);Mock.advance(1.2)
assert(s.State=='Ready' and rejected==1 and not s.AssetProbe and not s.AssetLoadRecord)
s:Destroy();Mock.advance(61);SE.task=normalTask;clean(s)
assetPass('Rejected native-worker cancellation does not block normal UI and late completion has no ownership')
s=start(nil,function(A) A.Logo='mock://duplicate';A.IconAtlas=A.Logo end);Mock.advance(.2)
assert(s.State=='Failed' and s.Completed==0 and s.Error:find('share one custom asset URI',1,true));clean(s)
assetPass('One duplicated custom asset URI cannot impersonate two distinct required PNGs')
print('ASSET_CASES '..count)
