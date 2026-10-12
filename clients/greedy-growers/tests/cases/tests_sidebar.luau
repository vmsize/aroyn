-- Actual Hub startup/GameUI; viewport/input/property doubles, not visual approval.
local af,AE=Mock.install(AssetsFactory,true)
AE.getcustomasset=function(path)return 'mock://sidebar/'..path end
local function result(name) print('SIDEBAR_PASS '..name) end
local function resize(s,width,height)
    s.Screen._p.absoluteOverride=E.Vector2.new(width,height)
    s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(.5)
    for _,o in ipairs(s.Screen:GetDescendants()) do o:GetPropertyChangedSignal('AbsoluteSize'):Fire() end
    Mock.advance(.3)
end
local function begin(mobile,width,height,failure)
    Mock.input.TouchEnabled=mobile;Mock.input.KeyboardEnabled=not mobile;Mock.input.MouseEnabled=not mobile
    Mock.services.ContentProvider={PreloadAsync=function(_,images,cb)
        for _,image in ipairs(images) do cb(type(image)=='string' and image or image.Image,
            failure and E.Enum.AssetFetchStatus.Failure or E.Enum.AssetFetchStatus.Success) end
    end}
    local s=start(nil,af())
    s.Screen._p.absoluteOverride=E.Vector2.new(width,height);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
    return s
end
local function railCheck(s,mobile)
    local w=s.Window;local nav=w.Navigation;local height=nav.AbsoluteSize.Y
    assert(#w.Pages==8 and nav.Active and nav.ScrollingEnabled)
    local lastBottom=0
    for i,page in ipairs(w.Pages) do
        local button=page.Navigation;local b=button.Size.X.Offset
        assert(button.Size.Y.Offset==b and button.Position.Y.Offset>=lastBottom)
        assert(button.Position.X.Offset+b<=nav.AbsoluteSize.X and button.Position.X.Offset>=0)
        assert(page.Icon.AnchorPoint.X==.5 and page.Icon.AnchorPoint.Y==.5 and page.Icon.Position.X.Scale==.5 and page.Icon.Position.Y.Scale==.5)
        if mobile then
            assert(b>=36 and b<=38 and page.Icon.Size.X.Offset==b-16 and page.Icon.Size.Y.Offset==b-16)
            if i>1 then assert(button.Position.Y.Offset-lastBottom<=4) end
        else
            assert(b==40 and page.Icon.Size.X.Offset==24 and page.Icon.Size.Y.Offset==24)
            assert(button.Position.X.Offset==12 and button.Position.Y.Offset==8+(i-1)*48)
        end
        lastBottom=button.Position.Y.Offset+b
    end
    assert(nav.CanvasSize.Y.Offset>=lastBottom)
    if mobile then
        if height>=296 then assert(nav.CanvasSize.Y.Offset<=height and nav.CanvasPosition.Y==0,'All eight tabs should fit')
        else assert(nav.CanvasSize.Y.Offset>height,'Short screen must retain scrolling') end
    else assert(nav.CanvasSize.Y.Offset==400) end
end
for _,v in ipairs({{568,320},{640,360},{740,360},{844,390},{854,393},{915,412},{1024,400},{680,400},{378,436},{320,568},{390,844}}) do
    local s=begin(true,v[1],v[2]);Mock.advance(1.5);assert(s.State=='Ready');railCheck(s,true)
    for _,page in ipairs(s.Window.Pages) do
        page.Navigation.Activated:Fire({UserInputType=E.Enum.UserInputType.Touch});Mock.advance(.3)
        assert(s.Window.Selected==page and page.Root.Visible and page.Indicator.BackgroundTransparency==0)
        assert(page.Indicator.Position.Y.Offset==6 and page.Indicator.Size.Y.Offset==-12)
    end
    assert(not s.App.GetDiagnostics().automationEnabled);clean(s)
    result('Mobile '..v[1]..'x'..v[2]..': comfortable complete targets, fit-or-scroll, centered icons and eight selected-tab handlers')
end
for _,v in ipairs({{640,360},{1024,768},{1440,900},{1920,1080}}) do
    local s=begin(false,v[1],v[2]);Mock.advance(1.5);assert(s.State=='Ready');railCheck(s,false)
    resize(s,390,844);railCheck(s,false);resize(s,v[1],v[2]);railCheck(s,false);clean(s)
    result('Desktop '..v[1]..'x'..v[2]..': original 40px buttons/24px icons/48px pitch, including narrow resize')
end
local s=begin(true,640,360);Mock.advance(1.5)
s.Window:SelectPage('Settings');Mock.advance(.3);local selected=s.Window.Selected
s.Window.Navigation.CanvasPosition=E.Vector2.new(0,28)
local listeners=Mock.connections
for _,v in ipairs({{844,390},{390,844},{640,360},{844,390}}) do resize(s,v[1],v[2]);railCheck(s,true);assert(s.Window.Selected==selected) end
assert(Mock.connections==listeners and s.Window.Navigation.CanvasPosition.Y==0)
clean(s);result('Rotation/resize clamps stale rail scrolling, preserves selection and does not add listeners')
s=begin(true,844,390);Mock.advance(1.5);s.Window:SelectPage('Pets');Mock.advance(.3)
s.Window:SetMinimized(true);Mock.advance(.5);resize(s,640,360)
s.Window:SetMinimized(false);Mock.advance(.5);railCheck(s,true);assert(s.Window.Selected.Name=='Pets' and not s.Window.Collapse.Busy)
clean(s);result('Minimize/restore after viewport change retains responsive rail and existing morph state')
for _,time in ipairs({.1,.4}) do
    s=begin(true,390,844);Mock.advance(time);resize(s,844,390);Mock.advance(1)
    assert(s.State=='Ready' and not s.Window.Root:GetAttribute('AroynStartupBusy'));railCheck(s,true)
    clean(s);result('Viewport change during startup at '..time..'s settles all eight tabs at final geometry')
end
s=begin(true,844,390,true);Mock.advance(1.5);assert(s.State=='Ready');railCheck(s,true)
for _,page in ipairs(s.Window.Pages) do
    local label=page.Navigation:FindFirstChild('NativeAssetPageLabel')
    assert(label and label.Text~='' and label.TextSize==9 and label.Size.X.Scale==1 and label.Size.Y.Scale==1)
end
clean(s);result('Native page-name fallback remains readable and centered inside compact mobile targets')
s=begin(true,844,390);Mock.advance(1.5);local replacement=begin(false,1440,900);Mock.advance(1.5)
assert(s.State=='Destroyed' and screens()==1);railCheck(replacement,false);clean(replacement)
result('Mobile re-execution into desktop creates one window with no compact-geometry leakage')
-- Windows touch laptops retain desktop geometry unless the actual asset detector selects mobile.
Mock.input.TouchEnabled=true;Mock.input.KeyboardEnabled=true;Mock.input.MouseEnabled=true
Mock.services.ContentProvider={PreloadAsync=function(_,images,cb)for _,image in ipairs(images)do cb(image,E.Enum.AssetFetchStatus.Success)end end}
s=start();Mock.advance(1.5);railCheck(s,false);clean(s)
result('Touch laptop with keyboard keeps the desktop sidebar')
