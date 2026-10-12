-- Actual current UI/startup/controller sources; input/viewport/measurement doubles.
local JSON=require('./config-json-mock')
local core,E=Mock.install(CoreFactory,true)
local sf,SE=Mock.install(StartupFactory,true)
local uf,UE=Mock.install(UIFactory,true)
local rt,RE=Mock.install(RuntimeFactory,true)
local http=Mock.services.HttpService
http.JSONEncode=function(_,v)return JSON.encode(v)end;http.JSONDecode=function(_,v)return JSON.decode(v)end
local world=Mock.Instance.new('Workspace');world.CurrentCamera=E.workspace.CurrentCamera
UE.workspace=world;RE.workspace=world
for _,env in ipairs({E,SE,UE,RE})do env.isfile=function(p)return Mock.files[p]~=nil end end
local field=Mock.Instance.new('Folder');field.Name='BigField';field.Parent=world
local conveyor=Mock.Instance.new('Folder');conveyor.Name='ConveyorSeeds';conveyor.Parent=field
local plots=Mock.Instance.new('Folder');plots.Name='PlayerPlots';plots.Parent=field
local plot=Mock.Instance.new('Model');plot:SetAttribute('OwnerUserId',123);plot.Parent=plots
local packages=Mock.Instance.new('Folder');packages.Name='Packages';packages.Parent=Mock.services.ReplicatedStorage
Mock.services.ContentProvider={PreloadAsync=function(_,assets,cb)for _,a in ipairs(assets)do cb(a,E.Enum.AssetFetchStatus.Success)end end}
Mock.asyncTweens=true;Mock.input.TouchEnabled=true;Mock.input.KeyboardEnabled=false
local Startup=sf();local build=uf();local cases,measurements={},{}
local function check(id,condition,detail)
    table.insert(cases,{Id=id,Status=condition and 'PASS' or 'FAIL',Detail=detail or ''})
    print((condition and 'PASS ' or 'FAIL ')..id..(detail and ' | '..detail or ''))
end
local function start(width,height)
    local s=Startup.Run(core(),BuildInfoFactory(),function(A) A.Logo='mock://logo';A.IconAtlas='mock://atlas' end,rt,build,{DisableNetwork=true})
    s.Screen._p.absoluteOverride=E.Vector2.new(width,height);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
    Mock.advance(1.2);assert(s.State=='Ready')
    return s,s.App.Integration,s.App.Integration.UI.Integration
end
local function close(s)
    s:Destroy();Mock.advance(481)
    assert(Mock.connections==0 and #Mock.jobs==0,'Leaked resources')
end
local function show(s,c)
    s.Window:SelectPage(c.Section.Page.Name);Mock.advance(.3)
    local page=c.Section.Page.Root
    page.CanvasPosition=E.Vector2.new(0,math.max(0,c.Control.AbsolutePosition.Y-page.AbsolutePosition.Y-80))
end
local function inside(o,width,height)
    local p,size=o.AbsolutePosition,o.AbsoluteSize
    return p.X>=0 and p.Y>=0 and p.X+size.X<=width+1 and p.Y+size.Y<=height+1
end
local widths={{320,844},{390,844},{768,1024},{844,390},{1024,768},{1440,900},{1920,1080}}
for _,v in ipairs(widths)do
    local width,height=v[1],v[2];local s,C,U=start(width,height)
    local w=s.Window
    check('shell-'..width,inside(w.Root,width,height) and not C.App.GetDiagnostics().automationEnabled,'touch viewport '..width..'x'..height..'; full actual runtime')
    for _,name in ipairs({'Buy Seeds','Plot','Collect','Compost','Market','Pets','Session','Settings'})do
        w.ByName[name].Navigation.Activated:Fire({UserInputType=E.Enum.UserInputType.Touch});Mock.advance(.3)
        assert(w.Selected.Name==name and w.ByName[name].Root.Visible)
    end
    check('navigation-'..width,w.Navigation.Active and w.Navigation.CanvasSize.Y.Offset>=w.Pages[8].Navigation.Position.Y.Offset+w.Pages[8].Navigation.Size.Y.Offset,'all 8 actual navigation handlers work; rail canvas covers all eight buttons with overflow when needed')
    local c=U.Preferences.Reserve
    local labelWidth=c.Label.Size.X.Scale*c.Root.AbsoluteSize.X+c.Label.Size.X.Offset
    local fieldLeft=c.Control.Position.X.Scale*c.Root.AbsoluteSize.X+c.Control.Position.X.Offset-c.Control.AbsoluteSize.X*c.Control.AnchorPoint.X
    table.insert(measurements,{ViewportWidth=width,ViewportHeight=height,WindowWidth=w.Root.AbsoluteSize.X,RowWidth=c.Root.AbsoluteSize.X,LabelWidth=labelWidth,FieldWidth=c.Control.AbsoluteSize.X,FieldLeftWithinRow=fieldLeft})
    check('ordinary-row-fit-'..width,labelWidth>=0 and fieldLeft>=0,'labelWidth='..labelWidth..' fieldLeft='..fieldLeft..'; native text measurement not modelled')
    show(s,c);c.Control:CaptureFocus();c.Control.Text='321';c.Control:ReleaseFocus(true)
    check('text-focus-'..width,C.State.cashReserve==321 and not C.App.GetDiagnostics().automationEnabled,'actual TextBox focus/lost callback; not physical OS keyboard')
    local d=U.Preferences.AlertRarity;show(s,d);d.Control.Activated:Fire();Mock.advance(.3)
    assert(d.Popup,'Dropdown did not open')
    check('popup-bounds-'..width,inside(d.Popup.Root,width,height),'actual Dropdown portal placement; native clipping/touch hit testing pending')
    d:Close(true)
    local h=w:Dialog({Title='Phone audit',Description=string.rep('Actual dialog layout test. ',30),Type='Confirm'})
    Mock.advance(.3)
    check('dialog-bounds-'..width,inside(h.Root,width,height),'actual measured layout with mock TextService; not font/render approval')
    h:Close();Mock.advance(.3)
    assert(w.ByName.Settings.Root.Active and w.ByName.Settings.Root.AutomaticCanvasSize==E.Enum.AutomaticSize.Y)
    check('scroll-structure-'..width,w.ByName.Settings.Root.ScrollingDirection==E.Enum.ScrollingDirection.Y,'long page uses native ScrollingFrame; real inertia/scroll gestures pending')
    close(s)
end
local s,C,U=start(390,844);local w=s.Window
w:SelectPage('Buy Seeds');Mock.advance(.3)
local header=w.Root:FindFirstChild('Header');local pos=w.Root.Position
local touch={UserInputType=E.Enum.UserInputType.Touch,Position=E.Vector2.new(w.Root.AbsolutePosition.X+100,w.Root.AbsolutePosition.Y+20)}
header.InputBegan:Fire(touch);touch.Position=touch.Position+E.Vector2.new(12,14);Mock.input.InputChanged:Fire(touch);Mock.input.InputEnded:Fire(touch)
check('main-window-touch-drag',w.Root.Position.X.Offset==pos.X.Offset+12 and w.Root.Position.Y.Offset==pos.Y.Offset+14,'actual touch InputBegan/Changed/Ended')
w:SetMinimized(true);Mock.advance(.5)
local floating=w.Collapse.FloatingPosition
touch={UserInputType=E.Enum.UserInputType.Touch,Position=w.Restore.AbsolutePosition+E.Vector2.new(20,20)}
w.Restore.InputBegan:Fire(touch);touch.Position=touch.Position+E.Vector2.new(20,20);Mock.input.InputChanged:Fire(touch);Mock.input.InputEnded:Fire(touch)
check('launcher-touch-drag',w.Collapse.Minimized and w.Collapse.FloatingPosition~=floating and inside(w.Restore,390,844),'drag does not become tap; floating bounds clamped')
touch={UserInputType=E.Enum.UserInputType.Touch,Position=w.Restore.AbsolutePosition+E.Vector2.new(20,20)}
w.Restore.InputBegan:Fire(touch);Mock.input.InputEnded:Fire(touch);Mock.advance(.5)
check('launcher-touch-restore',not w.Collapse.Minimized and w.Root.Visible,'actual touch tap/morph handlers')
s.Screen._p.absoluteOverride=E.Vector2.new(844,390);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(.5)
check('ready-portrait-to-landscape',inside(w.Root,844,390),'Ready root size='..w.Root.Size.X.Offset..'x'..w.Root.Size.Y.Offset..'; startup Resize observer is disposed at Finish')
close(s)
print('MOBILE_AUDIT_JSON '..JSON.encode({Cases=cases,Measurements=measurements,PhysicalDevice=false,ActualSource=true,TouchEvents=true,MockGeometry=true}))
