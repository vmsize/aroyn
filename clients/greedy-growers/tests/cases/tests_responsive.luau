-- Additional actual-source checks; same assertions also execute on frozen 11C.
local function resize(s,width,height)
    s.Screen._p.absoluteOverride=E.Vector2.new(width,height)
    s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
    Mock.advance(.5)
    -- Native Roblox propagates parent AbsoluteSize changes; the ScreenGui override
    -- itself does not in this double. Publish those native property notifications.
    for _,object in ipairs(s.Screen:GetDescendants()) do
        object:GetPropertyChangedSignal('AbsoluteSize'):Fire()
        object:GetPropertyChangedSignal('AbsolutePosition'):Fire()
    end
    Mock.advance(.3)
end
local function rowCheck(w,padding)
    local ok,why,count=true,'',0
    for _,page in ipairs(w.Pages) do for _,section in ipairs(page.Sections) do
        for _,c in ipairs(section.Components) do
            count+=1
            if padding then
                local size=c.Root.AbsoluteSize
                c.Root._p.absoluteOverride=E.Vector2.new(math.max(1,size.X-12),size.Y)
            end
        end
    end end
    if padding then w.Content:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(.1) end
    for _,page in ipairs(w.Pages) do for _,section in ipairs(page.Sections) do
        local previousBottom=28
        for _,c in ipairs(section.Components) do
            local width=c.Root.AbsoluteSize.X;local cs=c.Control.AbsoluteSize
            local x=c.Control.Position.X.Scale*width+c.Control.Position.X.Offset-cs.X*c.Control.AnchorPoint.X
            local labelWidth=c.Label.Size.X.Scale*width+c.Label.Size.X.Offset
            local y=c.Control.Position.Y.Offset
            local stack=c.Control.AnchorPoint.X==0 and y>=22
            local labelBottom=c.Label.Position.Y.Offset+c.Label.Size.Y.Offset
            local descBottom=c.Description and c.Description.Position.Y.Offset+c.Description.Size.Y.Offset or labelBottom
            local good=width>=1 and labelWidth>=120 and x>=0 and x+cs.X<=width+1
                and c.Root.Position.Y.Offset>=previousBottom
                and c.Root.Size.Y.Offset>=y+cs.Y
                and (not stack or (y>=descBottom+5 and cs.Y>=40 and c.Label.TextWrapped))
            if not good then ok=false;why=c.Name..' row='..width..' label='..labelWidth..' fieldLeft='..x;break end
            previousBottom=c.Root.Position.Y.Offset+c.Root.Size.Y.Offset
        end
    end end
    return ok,why..'; '..count..' controls across all 8 pages; native padding allowance='..tostring(padding)
end
local function headers(w,width,height)
    return inside(w.Close,width,height) and inside(w.Minimize,width,height)
        and w.Navigation.AbsoluteSize.Y>0 and w.Navigation.CanvasSize.Y.Offset>=w.Pages[8].Navigation.Position.Y.Offset+w.Pages[8].Navigation.Size.Y.Offset
end
for _,v in ipairs({{320,568},{360,640},{390,844},{412,915},{768,1024},{844,390},{640,360},{1024,768},{1440,900},{1920,1080}}) do
    local width,height=v[1],v[2];local s,C,U=start(width,height);local w=s.Window
    local ok,why=rowCheck(w,true)
    check('matrix-all-rows-'..width..'x'..height,ok and inside(w.Root,width,height) and headers(w,width,height),why)
    local reserve=U.Preferences.Reserve
    table.insert(measurements,{Matrix=true,ViewportWidth=width,ViewportHeight=height,WindowWidth=w.Root.AbsoluteSize.X,
        WindowHeight=w.Root.AbsoluteSize.Y,RowWidth=reserve.Root.AbsoluteSize.X,FieldWidth=reserve.Control.AbsoluteSize.X,
        LabelWidth=reserve.Label.AbsoluteSize.X,ControlY=reserve.Control.Position.Y.Offset,RowHeight=reserve.Root.Size.Y.Offset})
    if width>=768 then
        local metrics=core().Theme.Metrics
        check('desktop-fixed-layout-'..width..'x'..height,reserve.Control.Size.X.Offset==metrics.FieldWidth
            and reserve.Control.Size.Y.Offset==metrics.Control and reserve.Control.Position.Y.Offset==0
            and reserve.Control.AnchorPoint.X==1 and reserve.Root.Size.Y.Offset==metrics.Row,
            'original field224x30/row40/right alignment; native page padding model applied')
    end
    close(s)
end
local s,C,U=start(390,844);local w=s.Window
w:SelectPage('Settings');Mock.advance(.3);local selected=w.Selected
U.Preferences.Reserve:SetValue('789',true);Mock.advance(1)
local files=table.clone(Mock.files);local initialConnections=Mock.connections
local rotations=true
for _,v in ipairs({{844,390},{390,844},{844,390},{390,844}}) do
    resize(s,v[1],v[2])
    rotations=rotations and inside(w.Root,v[1],v[2]) and headers(w,v[1],v[2])
        and w.Selected==selected and U.Preferences.Reserve:GetValue()=='789' and not C.App.GetDiagnostics().automationEnabled
end
check('rotation-roundtrip-twice',rotations,'390x844 -> 844x390 -> 390x844, two cycles; page/value preserved and workers OFF')
local unchanged=true;for p,v in pairs(files) do if Mock.files[p]~=v then unchanged=false end end
for p in pairs(Mock.files) do if files[p]==nil then unchanged=false end end
check('resize-does-not-save-or-connect',unchanged and C.Dashboard.State=='Disconnected' and Mock.connections==initialConnections,
    'layout changes do not invoke config/game/Dashboard callbacks or add listeners')
local dropdown=U.Preferences.AlertRarity;show(s,dropdown);dropdown:Open();Mock.advance(.3)
resize(s,844,390)
check('open-popup-rotation',dropdown.Popup and inside(dropdown.Popup.Root,844,390),'existing popup portal follows changed native bounds')
dropdown:Close(true)
local dialog=w:Dialog({Title='Responsive dialog',Description=string.rep('Readable content. ',60),Type='Confirm'});Mock.advance(.3)
resize(s,390,844)
check('open-dialog-rotation',dialog.Root and inside(dialog.Root,390,844),'existing adaptive modal remains bounded')
dialog:Close();Mock.advance(.3)
w:SetMinimized(true);Mock.advance(.5);w.Collapse:PlaceFloating(10000,10000)
resize(s,640,360)
check('minimized-resize',w.Collapse.Minimized and not w.Root.Visible and inside(w.Restore,640,360),'hidden expanded geometry and launcher clamp')
w:SetMinimized(false);Mock.advance(.5)
check('restore-after-resize',inside(w.Root,640,360) and w.Root.Visible and not w.Collapse.Busy and w.Selected==selected,'same existing Collapse transition')
w:SetMinimized(true);Mock.advance(.1);resize(s,320,568);Mock.advance(.5)
check('resize-during-minimize',w.Collapse.Minimized and not w.Collapse.Proxy and inside(w.Restore,320,568),'existing morph cancellation settles safely')
w:SetMinimized(false);Mock.advance(.1);resize(s,844,390);Mock.advance(.5)
check('resize-during-restore',not w.Collapse.Minimized and not w.Collapse.Proxy and inside(w.Root,844,390),'restored content visible, input gate released')
close(s)
s,C,U=start(1920,1080);w=s.Window
for _,v in ipairs({{800,600},{1920,1080}}) do
    resize(s,v[1],v[2]);local ok,why=rowCheck(w,false)
    check('desktop-resize-'..v[1],inside(w.Root,v[1],v[2]) and headers(w,v[1],v[2]) and ok,why)
end
close(s)
-- Actual touch handlers for constrained controls, including drag cancellation by a modal.
s,C,U=start(320,568);w=s.Window
for _,input in ipairs({U.SeedSearch,U.CompostSearch}) do
    show(s,input);input.Control:CaptureFocus();input.Control.Text='COMMON';input.Control:ReleaseFocus(true)
    check('touch-search-'..input.Name,input:GetValue()=='COMMON' and Mock.input:GetFocusedTextBox()==nil
        and not C.App.GetDiagnostics().automationEnabled,'textbox release and actual filter callback; OS keyboard SKIP')
end
local toggle=U.AutoSave;show(s,toggle);local prior=toggle:GetValue();toggle.Control.Activated:Fire({UserInputType=E.Enum.UserInputType.Touch})
check('touch-settings-toggle',toggle:GetValue()~=prior and toggle.Control.AbsoluteSize.Y>=40,'actual constrained settings toggle')
local multi=U.Preferences.Seeds;show(s,multi);multi:Open();Mock.advance(.3)
local priorCount=#multi:GetValue();if multi.Popup.Rows[1] then multi.Popup.Rows[1].Button.Activated:Fire({UserInputType=E.Enum.UserInputType.Touch}) end
check('touch-multi-selection',#multi:GetValue()~=priorCount and not C.App.GetDiagnostics().automationEnabled,'actual option callback; selection does not enable Auto Buy')
multi:Close(true)
local slider=U.Preferences.PetStart;show(s,slider)
local touch={UserInputType=E.Enum.UserInputType.Touch,Position=slider.Track.AbsolutePosition+E.Vector2.new(slider.Track.AbsoluteSize.X*.5,2)}
slider.Hitbox.InputBegan:Fire(touch)
check('touch-slider-capture',slider.Drag==touch and not slider.Section.Page.Root.ScrollingEnabled,'native slider width-relative hitbox')
local modal=w:Dialog({Title='Cancel touch drag',Type='Confirm'});Mock.advance(.3)
local released=slider.Drag==nil and not slider.Section.Page.Root.ScrollingEnabled
modal:Close();Mock.advance(.3);Mock.input.InputEnded:Fire(touch)
check('modal-releases-touch-slider',released and slider.Section.Page.Root.ScrollingEnabled,'modal correctly locks scrolling while open, restores it on Close; drag capture released')
close(s)
-- Startup state resize, including the previously uncovered fading-loading interval.
local function begin(width,height)
    local a=Startup.Run(core(),BuildInfoFactory(),function(A) A.Logo='mock://logo';A.IconAtlas='mock://atlas' end,rt,build,{DisableNetwork=true})
    a.Screen._p.absoluteOverride=E.Vector2.new(width,height);a.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
    return a
end
for _,test in ipairs({{Time=0,Name='loading'},{Time=.35,Name='fade-loading'},{Time=.55,Name='expansion'}}) do
    s=begin(390,844);Mock.advance(test.Time)
    s.Screen._p.absoluteOverride=E.Vector2.new(640,360);s.Screen:GetPropertyChangedSignal('AbsoluteSize'):Fire()
    Mock.advance(1.2)
    check('startup-resize-'..test.Name,s.State=='Ready' and inside(s.Window.Root,640,360) and headers(s.Window,640,360)
        and not s.Window.Root:GetAttribute('AroynStartupBusy'),'actual startup stage='..test.Name..'; final latest target')
    close(s)
end
-- Host-relative safe inset rectangles (not real Android notch verification).
local gui=Mock.services.GuiService;local getInset=gui.GetInsetArea
s,C,U=start(390,844);w=s.Window
w.OwnRoot.ScreenInsets=E.Enum.ScreenInsets.None
local function rect(x,y,right,bottom)return {Min=E.Vector2.new(x,y),Max=E.Vector2.new(right,bottom)} end
gui.GetInsetArea=function(_,mode)
    if mode==E.Enum.ScreenInsets.CoreUISafeInsets then return rect(20,44,370,824) end
    return rect(0,0,390,844)
end
gui:GetPropertyChangedSignal('TopbarInset'):Fire();Mock.advance(.3)
local pos,size=w.Root.AbsolutePosition,w.Root.AbsoluteSize
check('ready-safe-insets',pos.X>=20 and pos.Y>=44 and pos.X+size.X<=370 and pos.Y+size.Y<=824,'screen origin subtracted exactly once')
w:SetMinimized(true);Mock.advance(.5);w.Collapse:PlaceFloating(-1000,-1000)
pos=w.Restore.AbsolutePosition
check('launcher-safe-insets',pos.X>=20 and pos.Y>=44,'existing floating position clamp with host safe rectangle')
close(s);gui.GetInsetArea=getInset
-- Measurement fallback/yield cancellation use actual adapter task cleanup.
Mock.measureError=true;s,C,U=start(320,568);local ok,why=rowCheck(s.Window,false)
check('font-measurement-fallback',ok,why);close(s);Mock.measureError=nil
Mock.measureDelay=.4;s=begin(320,568);Mock.advance(.01);s:Destroy();Mock.measureDelay=nil;Mock.advance(481)
check('cleanup-during-responsive-measurement',Mock.connections==0 and #Mock.jobs==0,'pending measurement task and unparented parameters owned by window cleanup')

s,C,U=start(390,844);w=s.Window
local input=U.SeedSearch;show(s,input);input.Control:CaptureFocus();input.Control.Text='not submitted'
local before=C.State.cashReserve
resize(s,390,480)
check('focused-editor-viewport-shrink',Mock.input:GetFocusedTextBox()==input.Control and input.Control.Text=='not submitted'
    and inside(w.Root,390,480) and C.State.cashReserve==before,'real focus retained; no FocusLost callback; physical keyboard occlusion SKIP')
input.Control:ReleaseFocus(true)
local toast=w:Notify({Title='Resize',Description='Local model',Duration=0});Mock.advance(.3)
resize(s,320,568)
check('toast-resize-bounds',toast.Root and inside(toast.Root,320,568),'existing screen-anchored notification manager')
toast:Dismiss();Mock.advance(.3)
local slider=U.Preferences.PetStart;show(s,slider)
local touch={UserInputType=E.Enum.UserInputType.Touch,Position=slider.Track.AbsolutePosition+E.Vector2.new(slider.Track.AbsoluteSize.X*.5,2)}
slider.Hitbox.InputBegan:Fire(touch);local value=slider:GetValue()
resize(s,640,360)
check('resize-during-slider-capture',slider.Drag==touch and slider:GetValue()==value and not slider.Section.Page.Root.ScrollingEnabled,
    'layout rerender does not invoke value callback or steal current touch')
Mock.input.InputEnded:Fire(touch)
check('slider-release-after-resize',slider.Drag==nil and slider.Section.Page.Root.ScrollingEnabled,'scroll ownership restored once')
close(s)
local unparentedClean=true
for _,instance in ipairs(Mock.instances) do
    if instance.ClassName=='GetTextBoundsParams' and not instance._p.dead then unparentedClean=false end
end
check('no-orphan-measurement-parameters',unparentedClean and Mock.connections==0 and #Mock.jobs==0,'all tested lifetime scopes/tasks/parameter instances cleaned')

s,C,U=start(320,568)
check('initial-narrow-page-scroll-origin',s.Window.Selected.Root.CanvasPosition.Y==0,'responsive loading reflow must not move the initial page scroll before Ready')
close(s)
