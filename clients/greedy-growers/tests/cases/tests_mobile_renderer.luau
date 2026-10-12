-- Actual mobile asset catalogue, image probes and native page-label rendering adapter.
Mock.input.TouchEnabled=true;Mock.input.KeyboardEnabled=false
local af,AE=Mock.install(AssetsFactory,true)
AE.getcustomasset=function(path)return 'mock://mobile/'..path end
local mobileAssets=af();local count=0
local function mobilePass(name) count+=1;print('RENDER_PASS '..name) end
local function run(provider,options,runtimeFn)
    Mock.services.ContentProvider=provider
    return start(options,mobileAssets,runtimeFn)
end
local function success(_,instances,cb)
    assert(#instances==9,'Logo and 8 navigation images required')
    for _,image in ipairs(instances) do
        assert(image.ClassName=='ImageLabel' and image.Image~='')
        if image.Name:find('MobileAssetProbe_',1,true) then
            assert(image.Visible and image.ImageTransparency<1 and image.Size.X.Offset>=24)
        end
        cb(image.Image,E.Enum.AssetFetchStatus.Success)
    end
end
local s=run({PreloadAsync=success});Mock.advance(1.5)
assert(s.State=='Ready' and s.Aroyn.AssetDiagnostics.Mode=='individual-png' and s.Aroyn.AssetDiagnostics.NavigationLoaded==8)
for _,page in ipairs(s.Window.Pages) do assert(page.Icon.ImageRectOffset.X==0 and page.Icon.ImageRectSize.X==0 and page.Icon.Image:find('aroyn_nav_',1,true)) end
assert(not s.AssetProbes and not s.AssetWorker);clean(s)
mobilePass('Actual mobile factory loads authentic small PNG cells; all 8 exact complete icon images use zero atlas rects')
local renderer={PreloadAsync=function(_,images)
    E.task.wait(.4) -- native entry fade makes the existing logo drawable
    for _,image in ipairs(images) do
        if image.ImageTransparency<1 and image.Visible and image.AbsoluteSize.X>=24 then image.IsLoaded=true end
    end
    E.task.wait(60)
end}
s=run(renderer);Mock.advance(1.5)
assert(s.State=='Ready' and s.Aroyn.AssetDiagnostics.NavigationLoaded==8);clean(s)
mobilePass('Renderer requiring visible nonzero-alpha 24px probes loads without a returning URI preload')
local never={PreloadAsync=function()E.task.wait(60)end}
s=run(never);Mock.advance(8)
assert(s.State=='Ready' and s.Completed==7 and s.Aroyn.AssetDiagnostics.Mode=='native-page-label-fallback')
assert(s.Aroyn.AssetDiagnostics.NavigationLoaded==0 and not s.Aroyn.AssetDiagnostics.LogoLoaded)
local names={'Buy Seeds','Plot','Collect','Compost','Market','Pets','Session','Settings'}
for _,name in ipairs(names) do
    local page=s.Window.ByName[name];local label=page.Navigation:FindFirstChild('NativeAssetPageLabel')
    assert(label and label.Text:gsub('\n',' ')==name and page.Icon:GetAttribute('AroynNativeNavigation'))
    page.Navigation.Activated:Fire({UserInputType=E.Enum.UserInputType.Touch});Mock.advance(.3)
    assert(s.Window.Selected==page and page.Root.Visible)
end
assert(not s.App.GetDiagnostics().automationEnabled and s.App.Integration.UI.Integration.AutoSave:GetValue())
s.Window:SetMinimized(true);Mock.advance(.5);s.Window:SetMinimized(false);Mock.advance(.5)
assert(s.Window.Root.Visible and s.Window.Selected.Name=='Settings');clean(s)
mobilePass('Unconfirmed custom graphics use all 8 real native page labels; touch navigation/minimize work and gameplay stays OFF')
s=run({PreloadAsync=function(_,images,cb)
    for _,image in ipairs(images) do
        cb(image.Image,image.Image:find('_gear_',1,true) and E.Enum.AssetFetchStatus.Failure or E.Enum.AssetFetchStatus.Success)
    end
end});Mock.advance(1.5)
assert(s.State=='Ready' and s.Aroyn.AssetDiagnostics.NavigationLoaded==7)
assert(s.Window.ByName.Settings.Navigation:FindFirstChild('NativeAssetPageLabel'))
assert(not s.Window.ByName.Plot.Navigation:FindFirstChild('NativeAssetPageLabel'));clean(s)
mobilePass('One failed cell degrades only its own page to a native label; other authentic PNGs remain')
local get=AE.getcustomasset;AE.getcustomasset=nil
s=run(never);Mock.advance(1.5)
assert(s.State=='Ready' and s.Aroyn.AssetDiagnostics.NavigationLoaded==0 and s.Window.Restore:FindFirstChild('Logo'):FindFirstChild('NativeBrandWordmark'))
clean(s);AE.getcustomasset=get
mobilePass('Missing custom asset API has a validated native navigation/wordmark fallback, not a false image success')
local oldRead=AE.readfile;AE.readfile=function()return 'bad PNG readback' end
s=run(never);Mock.advance(1.5)
assert(s.State=='Ready' and s.Aroyn.AssetDiagnostics.NavigationLoaded==0 and next(s.Aroyn.AssetDiagnostics.RegistrationErrors))
clean(s);AE.readfile=oldRead
mobilePass('Corrupt PNG readback is rejected and native GUI fallback remains functional')
AE.getcustomasset=function(path)E.task.wait(60);return 'mock://late/'..path end
s=run(never);Mock.advance(8)
assert(s.State=='Ready' and s.Aroyn.AssetDiagnostics.RegistrationTimedOut and s.Aroyn.AssetDiagnostics.NavigationLoaded==0)
clean(s);AE.getcustomasset=get
mobilePass('Yielded getcustomasset registration is bounded at6s and cannot block native interface fallback')
s=run(never);Mock.advance(.1);s:Destroy();Mock.advance(1)
assert(not s.AssetWorker and not s.AssetProbes);clean(s)
mobilePass('Close during mobile rendering clears all probes, preload work and ownership')
AE.getcustomasset=function(path)E.task.wait(60);return 'mock://'..path end
s=run(never);Mock.advance(.1);s:Destroy();clean(s);AE.getcustomasset=get
mobilePass('Close during mobile PNG registration cancels the worker and prevents late catalogue ownership')
s=run(never);Mock.advance(.2);local nextSession=run({PreloadAsync=success});Mock.advance(1.5)
assert(s.State=='Destroyed' and nextSession.State=='Ready' and screens()==1)
clean(nextSession)
mobilePass('Rerun replaces a mobile asset attempt safely with one fully initialized window')
field.Parent=nil;s=run(never);Mock.advance(8)
assert(s.State=='Failed' and s.Completed==1 and s.Error:find('BigField',1,true))
field.Parent=workspace;clean(s)
mobilePass('Optional image fallback never suppresses a critical gameplay initialization error')
Mock.measureDelay=60
s=run({PreloadAsync=success});Mock.advance(1.5)
assert(s.State=='Ready');s.Screen._p.absoluteOverride=E.Vector2.new(320,568);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(.3)
local reserve=s.App.Integration.UI.Integration.Preferences.Reserve
assert(reserve.Control.AbsoluteSize.X<=reserve.Root.AbsoluteSize.X and reserve.Label.AbsoluteSize.X>=176)
Mock.measureDelay=nil;clean(s)
mobilePass('Mobile narrow layout does not await a hanging FontFace measurement after the reported font temp-read warning')
s=run({PreloadAsync=success});Mock.advance(1.5);local prefs=s.App.Integration.UI.Integration
prefs.Preferences.Reserve:SetValue('817',true);Mock.advance(1);clean(s)
s=run({PreloadAsync=success});Mock.advance(1.5)
assert(s.App.Integration.UI.Integration.Preferences.Reserve:GetValue()=='817' and not s.App.GetDiagnostics().automationEnabled)
clean(s)
mobilePass('Actual mobile PNG candidate preserves AutoSave across separate executions and automation OFF')
Mock.input.TouchEnabled=false;Mock.input.KeyboardEnabled=true
print('MOBILE_RENDER_CASES '..count)
