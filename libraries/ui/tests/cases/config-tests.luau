do
assert(Mock.connections==0)
local JSON=require('../config-json-mock')
local E=libraryEnvironment;local http=Mock.services.HttpService
local oldEncode,oldDecode=http.JSONEncode,http.JSONDecode
http.JSONEncode=function(_,v) return JSON.encode(v) end
http.JSONDecode=function(_,v) return JSON.decode(v) end
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui')
local fs,files,folders,writes={}, {}, {},0
fs.isfile=function(p) return files[p]~=nil end
fs.readfile=function(p) assert(files[p],'No such file');return files[p] end
fs.writefile=function(p,v) files[p]=v;writes+=1 end
fs.isfolder=function(p) return folders[p]==true end
fs.makefolder=function(p) folders[p]=true end
fs.delfile=function(p) assert(files[p],'No such file');files[p]=nil end
fs.listfiles=function(p) local out={};for f in pairs(files) do if f:sub(1,#p+1)==p..'/' then table.insert(out,f) end end;return out end
local callbacks,activations=0,0
local function callback() callbacks+=1 end
local function build(id,adapter,autoLoad)
    local w=A:CreateWindow({Parent=parent,Id=id,Config={Namespace='persistence-tests',FileSystem=adapter,AutoLoad=autoLoad}})
    local page=w:CreatePage({Name='General'});local s=page:CreateSection({Title='Settings'})
    local c={}
    c.t=s:CreateToggle({Name='Toggle',Flag='t',Default=false,Callback=callback})
    c.n=s:CreateSlider({Name='Number',Flag='n',Min=0,Max=100,Step=5,Default=20,Callback=callback})
    c.d=s:CreateDropdown({Name='Single',Flag='d',Options={'A','B','C'},Default='A',Callback=callback})
    c.m=s:CreateDropdown({Name='Multi',Flag='m',Multi=true,Options={'A','B','C'},Default={'A'},Callback=callback})
    c.i=s:CreateTextInput({Name='Text',Flag='i',Default='original',Callback=callback})
    c.k=s:CreateKeybind({Name='Key',Flag='k',Default='H',Mode='Hold',Callback=callback,OnActivate=function() activations+=1 end})
    c.color=s:CreateColorPicker({Name='Color',Flag='color',Default=E.Color3.new(.1,.2,.3),Callback=callback})
    c.unflag=s:CreateToggle({Name='Unflagged',Default=false})
    c.secret=s:CreateTextInput({Name='Private',Flag='private',Sensitive=true,Default='never-save-me'})
    c.excluded=s:CreateTextInput({Name='Excluded',Flag='excluded',Persist=false,Default='also-private'})
    return w,c,s,page
end
local W,c,s,page=build('config',fs);Mock.advance(1)
W:RegisterConfig(c.secret,'private_again');W:RegisterConfig(c.excluded,'excluded_again')
assert(not c.secret.Flag and not c.excluded.Flag)
c.t:SetValue(true);c.n:SetValue(75);c.d:SetValue('B');c.m:SetValue({'C','A'});c.i:SetValue('line\n"quote" \\ путь');c.k:SetValue('K');c.k:SetMode('Toggle');c.color:SetValue(E.Color3.new(.8,.6,.4))
local ok,info=W:SaveConfig('Main');assert(ok and info.Mode=='File' and info.Name=='main')
local path='AroynUILab/configs/persistence-tests/main.json';local json=assert(files[path])
assert(json:sub(1,1)=='{' and json:find('"SchemaVersion":1',1,true) and not json:find('never-save-me',1,true))
local doc=JSON.decode(json);assert(doc.Values.k.Value.Key=='K' and doc.Values.k.Value.Mode=='Toggle')
assert(doc.Values.color.Value.R==.8 and doc.Values.i.Value==c.i:GetValue() and not doc.Values.private and not doc.Values.excluded)
assert(doc.Values.unflag==nil and doc.Values.k.Value.Active==nil)
local exposed=W:GetConfigState();exposed.Values.m.Value[1]='corrupted';assert(c.m:GetValue()[1]=='A')
print('CONFIG_JSON '..json)
pass('Config saves actual JSON with schema/namespace, RGB and stable key/mode; state copies exclude unflagged/sensitive/nonpersistent and transient values')
assert(W:ResetConfig());assert(not c.t:GetValue() and c.n:GetValue()==20 and c.d:GetValue()=='A' and c.k:GetMode()=='Hold')
assert(callbacks==0 and activations==0)
assert(W:LoadConfig('MAIN'));assert(c.t:GetValue() and c.n:GetValue()==75 and c.d:GetValue()=='B' and #c.m:GetValue()==2)
assert(c.k:GetMode()=='Toggle' and c.k:GetValue()==E.Enum.KeyCode.K and math.abs(c.color:GetValue().B-.4)<1e-7)
assert(callbacks==0 and activations==0 and c.i.Control.Text==doc.Values.i.Value)
c.k:SetMode('Always');local activationBefore=activations;assert(W:LoadConfig('Main'));assert(activations==activationBefore and callbacks==0)
assert(W:SaveConfig('Second'));ok,info=W:ListConfigs();assert(ok and #info.Names==2 and info.Names[1]=='main' and info.Names[2]=='second')
assert(W:DeleteConfig('Second'));ok,info=W:ListConfigs();assert(ok and #info.Names==1)
pass('Config load/reset restore visual/internal values silently including key mode; multiple named files list/delete without invoking callbacks or activations')
ok,info=W:LoadConfig('missing');assert(not ok and info.Code=='Missing')
files[path]='';ok,info=W:LoadConfig('main');assert(not ok and info.Code=='Empty')
files[path]='{broken';ok,info=W:LoadConfig('main');assert(not ok and info.Code=='Corrupt')
files[path]='{"SchemaVersion":999,"Namespace":"persistence-tests","Values":{}}';ok,info=W:LoadConfig('main');assert(not ok and info.Code=='SchemaUnsupported')
files[path]='{"SchemaVersion":1,"Namespace":"another-script","Values":{}}';assert(not W:LoadConfig('main'))
files[path]=json
local privateDoc=JSON.decode(json);privateDoc.Values.private={Type='Input',Value='do-not-resave'}
privateDoc.Values.excluded={Type='Input',Value='do-not-restore'}
privateDoc.Values.button={Type='Button',Value='do-not-save-button'}
privateDoc.Values.broken_unknown={Type='Slider',Value='not-a-number'}
files[path]=JSON.encode(privateDoc);assert(W:LoadConfig('main'));assert(c.secret:GetValue()=='never-save-me')
assert(W:SaveConfig('filtered'));assert(not JSON.decode(files['AroynUILab/configs/persistence-tests/filtered.json']).Values.private)
assert(not W:GetConfigState().Values.button and not W:GetConfigState().Values.broken_unknown)
files[path]=json
pass('Excluded/sensitive flags in imported files are skipped and never re-saved through deferred values')
for _,name in ipairs({'../main','a/b','a\\b','.hidden','main.json','NUL.','NUL','con','COM1','lpt9',string.rep('a',65),'a:b'}) do assert(not W:SaveConfig(name)) end
pass('Missing/empty/corrupted files, future schema and foreign namespace return clear failures without changes; traversal and unsafe names rejected')
doc=JSON.decode(json);doc.Values.t.Value='true';doc.Values.n.Value=999;doc.Values.d.Value='removed';doc.Values.m.Value={'B','removed','B'}
doc.Values.color.Value.R=-1;doc.Values.k.Value.Key='Unknown';doc.Values.i.Value=42;doc.Values.later={Type='Toggle',Value=true}
files[path]=JSON.encode(doc);local oldColor=c.color:GetHex()
ok,info=W:LoadConfig('main');assert(ok and info.Skipped==4 and info.Deferred==1 and #info.Warnings>=7)
assert(c.n:GetValue()==100 and c.d:GetValue()=='A' and #c.m:GetValue()==1 and c.m:GetValue()[1]=='B' and c.color:GetHex()==oldColor)
local late=s:CreateToggle({Name='Added later',Flag='later',Default=false});assert(late:GetValue())
local beforeConnections=Mock.connections;local count=#s.Components
assert(not pcall(function() s:CreateToggle({Name='Duplicate',Flag='t'}) end));assert(#s.Components==count and Mock.connections==beforeConnections)
assert(not pcall(function() s:CreateToggle({Name='Invalid flag',Flag='../bad'}) end))
c.unflag:SetValue(true);assert(W:ResetConfig());assert(c.unflag:GetValue() and not late:GetValue())
files[path]=json
pass('Partially valid configs skip invalid values, clamp sliders, filter removed selections, defer unknown flags, reject duplicates before allocation and reset only registered controls')
local missingDefault=s:CreateDropdown({Name='Empty default',Flag='empty',Options={'A'}})
doc=JSON.decode(json);doc.Values.empty={Type='Dropdown',Multi=false,Value='removed'};files[path]=JSON.encode(doc)
assert(W:LoadConfig('main'));assert(missingDefault:GetValue()==nil);assert(W:SaveConfig('null-selection'));assert(JSON.decode(files['AroynUILab/configs/persistence-tests/null-selection.json']).Values.empty.Value==false)
files[path]=json
local noisyBefore=callbacks;assert(W:LoadConfig('main',{InvokeCallbacks=true}));assert(callbacks>=noisyBefore)
assert(W:ResetConfig());noisyBefore=callbacks;assert(W:LoadConfig('main',{InvokeCallbacks=true}));assert(callbacks==noisyBefore+7 and activations==activationBefore)
local connectionBefore=Mock.connections
for _=1,50 do assert(W:LoadConfig('main'));assert(W:ResetConfig()) end
assert(Mock.connections==connectionBefore)
c.t.Control.Activated:Fire();assert(c.t:GetValue() and callbacks>noisyBefore)
pass('Nil single selection roundtrips explicitly, opt-in change callbacks fire once, 50 repeated loads/resets do not leak and normal interactions still work')
assert(W:SetConfigAutoSave(true,'automatic',.5));local startWrites=writes
for i=1,100 do c.n:SetValue(i);Mock.advance(.001) end
assert(writes==startWrites);Mock.advance(.49);assert(writes==startWrites);Mock.advance(.02);assert(writes==startWrites+1)
startWrites=writes;c.n:SetValue(c.n:GetValue());Mock.advance(1);assert(writes==startWrites)
c.i.Control.Text='typed without Enter';Mock.advance(.51);assert(writes==startWrites+1)
assert(JSON.decode(files['AroynUILab/configs/persistence-tests/automatic.json']).Values.i.Value=='typed without Enter')
startWrites=writes;c.color:_SetColor(E.Color3.new(.7,.5,.3),true,true);Mock.advance(.51);assert(writes==startWrites+1)
c.k:SetMode('Hold');Mock.advance(.51);assert(JSON.decode(files['AroynUILab/configs/persistence-tests/automatic.json']).Values.k.Value.Mode=='Hold')
startWrites=writes;c.n:SetValue(35);assert(W:LoadConfig('main'));Mock.advance(1);assert(writes==startWrites)
c.n:SetValue(40);assert(W:ResetConfig());Mock.advance(1);assert(writes==startWrites)
assert(W:DeleteConfig('automatic'));assert(not W:GetConfigStatus().AutoSave)
assert(not W:SetConfigAutoSave(true,'../bad'));assert(not W:SetConfigAutoSave(true,'main',.01))
pass('Opt-in AutoSave debounces 100 slider changes, text typing, HSV changes and key mode; unchanged values do not write and load/reset/delete cancel pending saves')
local oldFlag=c.t.Flag;c.t:Destroy();assert(not W:GetConfigState().Values[oldFlag])
local replacement=s:CreateToggle({Name='Replacement',Flag=oldFlag,Default=false});assert(not replacement:GetValue())
assert(W:SetConfigAutoSave(true,'destroyed',.5));replacement:SetValue(true);startWrites=writes
W:Destroy();Mock.advance(1);assert(writes==startWrites and Mock.connections==0)
pass('Component destruction unregisters flags and permits reuse; window destruction cancels pending saves, listeners and retained registry entries')
local restored,rc,rs=build('config-reexecuted',fs,'Main');Mock.advance(1)
assert(rc.t:GetValue() and rc.n:GetValue()==75 and rc.k:GetMode()=='Toggle' and callbacks>0)
local status=restored:GetConfigStatus();assert(status.Mode=='File')
-- Reordering/display names do not affect flags. Added controls retain defaults; early state includes pending flags.
restored:Destroy();local early=A:CreateWindow({Parent=parent,Id='early',Config={Namespace='persistence-tests',FileSystem=fs}})
assert(early:LoadConfig('main'));assert(early:SaveConfig('early-save'))
assert(JSON.decode(files['AroynUILab/configs/persistence-tests/early-save.json']).Values.color)
local es=early:CreatePage({Name='Renamed'}):CreateSection({Title='Different order'})
local ei=es:CreateTextInput({Name='Completely new label',Flag='i'});local et=es:CreateToggle({Name='Last',Flag='t'});local en=es:CreateToggle({Name='New',Flag='new',Default=true})
assert(ei:GetValue()==JSON.decode(json).Values.i.Value and et:GetValue() and en:GetValue())
early:Destroy();Mock.advance(1);assert(Mock.connections==0)
pass('File adapter re-execution and AutoLoad restore controls registered later; reorder/rename/new controls preserve stable flags and early saves preserve deferred values')
local session,sc=build('session',{});Mock.advance(1)
assert(session:GetConfigStatus().Mode=='Session');sc.t:SetValue(true);assert(session:SaveConfig('main'));sc.t:SetValue(false);assert(session:LoadConfig('main'));assert(sc.t:GetValue())
assert(session:DeleteConfig('main'));assert(not session:LoadConfig('main'));assert(session:SaveConfig('main'))
session:Destroy();local clean,cc=build('session-new',{});Mock.advance(1);assert(not clean:LoadConfig('main') and not cc.t:GetValue())
clean:Destroy();Mock.advance(1)
for _,partial in ipairs({{readfile=fs.readfile},{writefile=fs.writefile}}) do local w=build('partial',partial);assert(w:GetConfigStatus().Mode=='Session');w:Destroy() end
pass('Missing and partial filesystem APIs degrade to explicit session-only save/load/list/delete; a new window never claims restoration from discarded memory')
local minimal=table.clone(fs);minimal.listfiles=nil;minimal.isfile=nil;minimal.isfolder=nil;minimal.makefolder=nil
local indexed,ic=build('indexed',minimal);Mock.advance(1);assert(indexed:SaveConfig('IndexedOne'));assert(indexed:SaveConfig('IndexedTwo'))
ok,info=indexed:ListConfigs();assert(ok and table.find(info.Names,'indexedone') and table.find(info.Names,'indexedtwo'))
indexed:Destroy();local indexedAgain=build('indexed-again',minimal);assert(indexedAgain:LoadConfig('indexedone'));assert(indexedAgain:DeleteConfig('indexedtwo'))
ok,info=indexedAgain:ListConfigs();assert(ok and not table.find(info.Names,'indexedtwo'));indexedAgain:Destroy();Mock.advance(1)
pass('Read/write adapters without listfiles/isfile/folder checks use a JSON index in a pre-provisioned directory and restore across fresh managers')
local failing=table.clone(fs);failing.writefile=function() error('disk full') end
local bad,bc=build('write-failed',failing);assert(not bad:SaveConfig('main') and bad:GetConfigStatus().LastResult.Code=='WriteFailed');bad:Destroy()
failing=table.clone(fs);failing.readfile=function() error('permission denied') end
bad=build('read-failed',failing);assert(not bad:LoadConfig('main') and bad:GetConfigStatus().LastResult.Code=='ReadFailed');bad:Destroy()
failing=table.clone(fs);failing.delfile=nil
bad=build('delete-unsupported',failing);assert(not bad:DeleteConfig('main') and bad:GetConfigStatus().LastResult.Code=='DeleteUnsupported');bad:Destroy()
failing=table.clone(fs);failing.delfile=function() error('permission denied') end
bad=build('delete-failed',failing);assert(not bad:DeleteConfig('main') and bad:GetConfigStatus().LastResult.Code=='DeleteFailed');bad:Destroy()
failing=table.clone(fs);failing.listfiles=function() error('permission denied') end
bad=build('list-failed',failing);assert(not bad:ListConfigs() and bad:GetConfigStatus().LastResult.Code=='ListFailed');bad:Destroy()
failing=table.clone(fs);failing.isfolder=function() return false end;failing.makefolder=function() error('blocked') end
bad=build('folder-failed',failing);assert(not bad:SaveConfig('main') and bad:GetConfigStatus().LastResult.Code=='FolderFailed');bad:Destroy();Mock.advance(1)
pass('Write/read/delete/list/folder exceptions and unsupported deletion report distinct failures without pretending persistence succeeded')
local fullPaths=table.clone(fs)
fullPaths.listfiles=function(p)
    local list={};for _,f in ipairs(fs.listfiles(p)) do table.insert(list,'C:\\executor\\workspace\\'..f:gsub('/','\\')) end
    table.insert(list,'C:/executor/workspace/AroynUILab/configs/foreign/main.json')
    return list
end
local full=build('absolute-list',fullPaths);ok,info=full:ListConfigs();assert(ok and table.find(info.Names,'main'));full:Destroy()
local other=A:CreateWindow({Parent=parent,Id='namespace-other',Config={Namespace='different-game',FileSystem=fs}})
local os=other:CreatePage({Name='Other'}):CreateSection({Title='Other'});os:CreateToggle({Name='Same flag',Flag='t',Default=false})
assert(other:SaveConfig('main'));assert(files['AroynUILab/configs/different-game/main.json'] and JSON.decode(files[path]).Namespace=='persistence-tests')
assert(not other:ConfigureConfig({Namespace='overwrite'}));other:Destroy();Mock.advance(1)
pass('Absolute Windows listfiles paths work, namespace separation isolates same names/flags and an existing manager cannot be silently reconfigured')
local indexFail=table.clone(minimal)
indexFail.writefile=function(p,v) if p:find('__index.json',1,true) then error('index write denied') end;fs.writefile(p,v) end
local partial=build('partial-write',indexFail)
ok,info=partial:SaveConfig('partial-file');assert(not ok and info.Code=='IndexWriteFailed' and info.FileSaved and files['AroynUILab/configs/persistence-tests/partial-file.json'])
assert(partial:SetConfigAutoSave(true,'partial-file',.5));partial.Config.Members.t.Component:SetValue(true)
ok,info=partial:DeleteConfig('partial-file');assert(not ok and info.FileDeleted and not partial:GetConfigStatus().AutoSave)
Mock.advance(1);assert(not files['AroynUILab/configs/persistence-tests/partial-file.json']);partial:Destroy()
files['AroynUILab/configs/persistence-tests/__index.json']='{broken'
local corruptIndex=build('index-corrupt',minimal);ok,info=corruptIndex:SaveConfig('must-not-write');assert(not ok and info.Code=='IndexInvalid')
assert(not files['AroynUILab/configs/persistence-tests/must-not-write.json']);corruptIndex:Destroy()
files['AroynUILab/configs/persistence-tests/__index.json']=JSON.encode({SchemaVersion=1,Names={'main'}})
pass('Non-atomic index failures explicitly report partial file writes/deletes; deletion cancels autosave even on index failure and corrupt indexes are not overwritten')
local reentrant=table.clone(fs);local busyWindow,innerResult
reentrant.writefile=function(p,v)
    local innerOk,innerInfo=busyWindow:LoadConfig('main');assert(not innerOk);innerResult=innerInfo.Code;fs.writefile(p,v)
end
busyWindow=build('busy-save',reentrant);assert(busyWindow:SaveConfig('busy'));assert(innerResult=='Busy');busyWindow:Destroy();Mock.advance(1)
pass('Reentrant storage callbacks receive Busy instead of racing a second configuration operation')
local mw,mc=build('morph-config',fs);Mock.advance(1);Mock.asyncTweens=true
assert(mw:LoadConfig('main'));local savedPosition=mw.Root.Position
for _=1,5 do mw:SetMinimized(true);Mock.advance(1);mw:SetMinimized(false);Mock.advance(1) end
assert(mc.t:GetValue() and mc.n:GetValue()==75 and mw.Root.Position.X.Offset==savedPosition.X.Offset)
assert(mw:LoadConfig('main'));mw:Destroy();Mock.advance(1);Mock.asyncTweens=false;assert(Mock.connections==0)
http.JSONEncode,http.JSONDecode=oldEncode,oldDecode
pass('Configuration restoration preserves five native window morph cycles, selected page/control state and complete final cleanup')
end
