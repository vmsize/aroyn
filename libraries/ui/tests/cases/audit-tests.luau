-- Phase 4B: actual module regressions, using independent deterministic doubles.
do
assert(Mock.connections==0)
local JSON=require('../config-json-mock')
local http=Mock.services.HttpService
local encode,decode=http.JSONEncode,http.JSONDecode
http.JSONEncode=function(_,v) return JSON.encode(v) end
http.JSONDecode=function(_,v) return JSON.decode(v) end
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui');local failures={}
local function check(title,fn)
    local ok,err=pcall(fn)
    if ok then pass(title) else table.insert(failures,title..': '..tostring(err));print('FAIL '..title..': '..tostring(err)) end
end
local function build(id)
    local w=A:CreateWindow({Parent=parent,Id=id,Config={Namespace='audit',FileSystem={}}})
    local s=w:CreatePage({Name='Audit'}):CreateSection({Title='Settings'})
    return w,s
end
check('4B valid Toggle/Input config load and reset produce no false warnings',function()
    local w,s=build('warnings');s:CreateToggle({Name='Toggle',Flag='toggle'});s:CreateTextInput({Name='Text',Flag='text'})
    assert(w:SaveConfig('main'));local ok,info=w:LoadConfig('main');assert(ok and #info.Warnings==0)
    ok,info=w:ResetConfig();assert(ok and #info.Warnings==0);w:Destroy()
end)
-- Clean failed probes too, so all four defects can be reproduced in one run.
for _,g in ipairs(parent:GetChildren()) do g:Destroy() end
check('4B manual excluded Flag registration rejects duplicates and retains exclusion ownership',function()
    local w,s=build('excluded');local a=s:CreateTextInput({Name='A',Sensitive=true});local b=s:CreateTextInput({Name='B',Sensitive=true})
    w:RegisterConfig(a,'secret');local count=Mock.connections
    assert(not pcall(function() w:RegisterConfig(b,'secret') end));assert(Mock.connections==count)
    a:Destroy();w:RegisterConfig(b,'secret');a:Destroy()
    assert(w.Config.Excluded.secret==b)
    w:Destroy()
end)
for _,g in ipairs(parent:GetChildren()) do g:Destroy() end
check('4B overlong persisted text is rejected before overwriting an existing snapshot',function()
    local w,s=build('long-text');local c=s:CreateTextInput({Name='Text',Flag='text',Default='safe'})
    assert(w:SaveConfig('main'));c:SetValue(string.rep('x',16385))
    local ok,info=w:SaveConfig('main');assert(not ok and info.Code=='InvalidState')
    assert(w:LoadConfig('main'));assert(c:GetValue()=='safe');w:Destroy()
end)
for _,g in ipairs(parent:GetChildren()) do g:Destroy() end
check('4B combined deferred/live entries cannot save a document beyond the load limit',function()
    local w,s=build('entries');local values={}
    for i=1,512 do values['deferred'..i]={Type='Toggle',Value=true} end
    -- Inject through the same JSON boundary as an on-disk file, not through Pending.
    w.Config.Memory.main=JSON.encode({SchemaVersion=1,Namespace='audit',Values=values})
    assert(w:LoadConfig('main'));s:CreateToggle({Name='New',Flag='new'})
    local ok,info=w:SaveConfig('main');assert(not ok and info.Code=='InvalidState')
    assert(w:LoadConfig('main'));assert(w:GetConfigState().Values.deferred512.Value)
    w:Destroy()
end)
for _,g in ipairs(parent:GetChildren()) do g:Destroy() end
http.JSONEncode,http.JSONDecode=encode,decode
Mock.advance(20);assert(Mock.connections==0)
assert(#failures==0,table.concat(failures,'\n'))
end
