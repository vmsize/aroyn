local groups=0
local function pass(message) groups+=1;print("PASS "..message) end
assert(Mock.connections==0)
local source=Mock.install(SourceFactory)()
local load,env=Mock.install(BundleFactory)
local playerGui=Mock.services.Players.LocalPlayer:WaitForChild("PlayerGui")
local before=#playerGui:GetChildren()
local bundled=load()
assert(type(bundled.CreateWindow)=="function" and #playerGui:GetChildren()==before and Mock.connections==0)
assert(bundled.Distribution.Version=="0.1.0" and bundled.Distribution.Assets.Status=="Unavailable")
pass("Library load creates no window, input connections or global registry; explicit missing-capability report")
for key,value in pairs(source) do assert(type(bundled[key])==type(value),key) end
for key in pairs(bundled) do assert(source[key]~=nil or key=="Distribution",key) end
pass("Returned source/bundle API keys and value kinds match; only distribution metadata is additive")
local full,fullEnv=Mock.install(BundleFactory,true)
local writes=0;local write=fullEnv.writefile
fullEnv.writefile=function(path,value) writes+=1;write(path,value) end
fullEnv.getcustomasset=function(path)
    assert(path:match("^AroynUI/assets/%x+%.png$") and Mock.files[path]:sub(1,8)=="\137PNG\13\10\26\10")
    return "rbxasset://local-test/"..path
end
local images=full();assert(images.Distribution.Assets.Status=="Ready" and writes==2)
local again=full();assert(again.Logo==images.Logo and writes==2 and Mock.connections==0)
pass("Both embedded PNGs register; repeated loading verifies cached bytes without rewriting or adding listeners")
local parent=Mock.Instance.new("PlayerGui")
do
    local window=images:CreateWindow({Parent=parent,Id="header-logo-hotfix",Logo=images.Logo})
    local logo=window.Collapse.Options.BrandLogo
    local wordmark=window.Collapse.Options.BrandText
    assert(logo.Size.X.Offset==32 and logo.Size.Y.Offset==32)
    assert(logo.Position.X.Offset==12 and logo.Position.Y.Offset==10)
    assert(logo.Position.Y.Offset+logo.Size.Y.Offset/2==images.Theme.Metrics.Header/2)
    assert(logo.ScaleType==fullEnv.Enum.ScaleType.Fit and logo.Image==images.Logo)
    assert(wordmark.Position.X.Offset==48 and wordmark.Position.Y.Offset==14)
    assert(window.Restore.Size.X.Offset==48 and window.Restore.Size.Y.Offset==48)
    assert(window.Restore:FindFirstChild("Logo").Size.X.Offset==28)
    Mock.advance(0) -- Settle the constructor's deferred viewport positioning before capturing geometry.
    local expandedSize,expandedPosition=window.Root.Size,window.Root.Position
    Mock.asyncTweens=true
    window:SetMinimized(true)
    assert(window.Collapse.Proxy.LogoHolder.Size.X.Offset==32 and window.Collapse.Proxy.LogoHolder.Size.Y.Offset==32)
    Mock.advance(1);assert(window.Restore.Visible and not window.Collapse.Proxy)
    window:SetMinimized(false);Mock.advance(1)
    assert(window.Root.Visible and window.Root.Size==expandedSize and window.Root.Position==expandedPosition)
    assert(logo.Size.X.Offset==32 and logo.Size.Y.Offset==32)
    window:SetMinimized(true);window:SetMinimized(false);window:SetMinimized(true);window:SetMinimized(false)
    Mock.advance(1);assert(window.Root.Visible and not window.Collapse.Proxy)
    window:Destroy();Mock.advance(10);Mock.asyncTweens=false;assert(Mock.connections==0)
end
pass("Header logo 32px square, exact vertical center, unchanged wordmark/launcher and existing morph/reversal cleanup in mocks")
for i,key in ipairs({"cart","plot","compost","market","settings","pets","components"}) do
    local icon=images:CreateIcon(parent,key)
    assert(icon.ImageRectOffset.X==(i-1)*128 and icon.ImageRectOffset.Y==0)
    assert(icon.ImageRectSize.X==128 and icon.ImageRectSize.Y==128 and icon.Image==images.IconAtlas)
    icon:Destroy()
end
pass("All seven original icon cells use correct native atlas offsets, dimensions and no scaling adapter")
local missing,missingEnv=Mock.install(BundleFactory,true)
missingEnv.getcustomasset=function() error("Expected asset failure") end
assert(missing().Distribution.Assets.Status=="Unavailable")
local partial,partialEnv=Mock.install(BundleFactory,true)
local n=0;partialEnv.getcustomasset=function() n+=1;if n==1 then error("Expected single-image failure") end;return "rbxasset://local/logo" end
assert(partial().Distribution.Assets.Status=="Partial")
local noFolder,noFolderEnv=Mock.install(BundleFactory,true)
noFolderEnv.makefolder=nil;noFolderEnv.getcustomasset=fullEnv.getcustomasset
assert(noFolder().Distribution.Assets.Status=="Ready")
pass("Failed/partial custom assets and absent folder API report honest capability states without throwing")
local makeShowcase=Mock.install(ShowcaseFactory)()
local function exercise(api,disk)
    local window,controls=makeShowcase(api,parent)
    local changed=0;controls.Enabled.Callback=function() changed+=1 end
    controls.Enabled:SetValue(true,true);assert(changed==1)
    controls.Volume:SetValue(65);assert(controls.Volume:GetValue()==65)
    controls.Mode:SetValue("Detailed");controls.Categories:SetValue({"UI","Tests"})
    local values=controls.Categories:GetValue();values[1]="bad";assert(controls.Categories:GetValue()[1]=="UI")
    assert(window:SaveConfig("roundtrip"));controls.Enabled:SetValue(false)
    assert(window:LoadConfig("roundtrip"));assert(controls.Enabled:GetValue() and changed==1)
    assert(window:ListConfigs());assert(window:ResetConfig());assert(window:DeleteConfig("roundtrip"))
    window:SelectPage("General");Mock.advance(1)
    controls.Mode:Open();assert(controls.Mode:IsOpen());controls.Mode:Close();Mock.advance(1)
    controls.Color:Open();assert(controls.Color:IsOpen());controls.Color:Close();Mock.advance(1)
    local toast=window:Notify({Title="Distribution test",Duration=0});toast:Dismiss();Mock.advance(1)
    local dialog=window:Dialog({Title="Distribution test",Type="Confirm"});dialog:Close();Mock.advance(1)
    window:SetMinimized(true);Mock.advance(1);window:SetMinimized(false);Mock.advance(1)
    assert(window.Scope.Alive)
    controls.Note:Destroy();window:Destroy();Mock.advance(10);assert(Mock.connections==0)
end
exercise(source);exercise(bundled)
pass("Same complete example works with source and HTTP-downloaded bundle: all controls, callbacks, copies, Session configuration, popups, overlays, morph and destruction")
-- Configure the example factory with disk capabilities, just like a real executor.
local diskShowcase,diskEnv=Mock.install(ShowcaseFactory,true)
diskEnv.isfile=function(path)return Mock.files[path]~=nil end
diskEnv.listfiles=function(path)local files={};for name in pairs(Mock.files) do if name:sub(1,#path)==path then files[#files+1]=name end end;return files end
diskShowcase=diskShowcase()
local firstWindow,firstControls=diskShowcase(images,parent)
assert(firstWindow:GetConfigStatus().Mode=="File");firstControls.Volume:SetValue(75)
assert(firstWindow:SaveConfig("fresh"));firstWindow:Destroy();Mock.advance(10)
local secondWindow,secondControls=diskShowcase(again,parent)
assert(secondWindow:LoadConfig("fresh") and secondControls.Volume:GetValue()==75)
assert(secondWindow:DeleteConfig("fresh"));secondWindow:Destroy();Mock.advance(10)
assert(Mock.connections==0)
pass("Filesystem Save and fresh-manager Load across separate bundle objects preserve the existing namespace/schema")
local unrelated=Mock.Instance.new("ScreenGui");unrelated.Name="Unrelated";unrelated.Parent=parent
local w=images:CreateWindow({Parent=parent,Id="reexecution",Logo=images.Logo})
local replacement=again:CreateWindow({Parent=parent,Id="reexecution",Logo=again.Logo})
assert(not w.Scope.Alive and replacement.Scope.Alive and unrelated.Parent==parent)
replacement:Destroy();Mock.advance(10);assert(Mock.connections==0)
pass("Separate loads retain same-Id owned-window replacement without destroying unrelated GUI; clean input lifecycle")
print("TOTAL "..groups)
