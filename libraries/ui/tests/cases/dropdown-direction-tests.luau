-- Deterministic geometry checks. Mock tweens defer goals, so set intermediate sizes
-- explicitly to model a native interpolated frame without pretending to render it.
do
assert(Mock.connections==0)
local E=libraryEnvironment;local U=E.UDim2;local V=E.Vector2
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui')
local W=A:CreateWindow({Parent=parent,Id='dropdown-direction-regression',Size=U.fromOffset(680,440)})
local P=W:CreatePage({Name='Controls'});local S=P:CreateSection({Title='Dropdowns'})
local first=S:CreateDropdown({Name='First',Options={'One','Two'},Default='One'})
local options={};for i=1,30 do table.insert(options,'Option '..i) end
local long=S:CreateDropdown({Name='Long',Options=options,MaxVisibleOptions=8})
local multi=S:CreateDropdown({Name='Multi',Multi=true,Options=options,Default={'Option 1'}})
Mock.advance(1);W.Root.Position=U.fromOffset(100,80)
Mock.asyncTweens=true
local function edge(root,up) return root.AbsolutePosition.Y+(up and root.AbsoluteSize.Y or 0) end
local function near(a,b,message) assert(math.abs(a-b)<0.001,message) end
local function place(c,up) c.Root.Position=U.fromOffset(0,up and 295 or 28) end
local function press(c,kind)
    local p,s=c.Control.AbsolutePosition,c.Control.AbsoluteSize
    local input={UserInputType=kind or Mock.Enum.UserInputType.MouseButton1,Position=V.new(p.X+s.X/2,p.Y+s.Y/2)}
    Mock.input.InputBegan:Fire(input,false);Mock.input.InputEnded:Fire(input);c.Control.Activated:Fire(input,1)
end
for _,up in ipairs({false,true}) do
    place(first,up);press(first)
    local pop=first.Popup;assert(pop and first:IsOpen())
    local anchored=first.Control.AbsolutePosition.Y+(up and -5 or first.Control.AbsoluteSize.Y+5)
    near(edge(pop.Root,up),anchored,'initial popup must originate at trigger-facing edge')
    assert(pop.Root.AnchorPoint.Y==(up and 1 or 0) and pop.Root.Size.Y.Offset==0)
    local tween=pop.Scope.Animations[pop.Root]
    assert(tween.Goals.Size.Y.Offset==84 and tween.Info[1]==0.18)
    pop.Root.Size=U.fromOffset(pop.Root.Size.X.Offset,39)
    near(edge(pop.Root,up),anchored,'opening intermediate size must preserve anchored edge')
    press(first);assert(pop.Closing and not first:IsOpen())
    tween=pop.Scope.Animations[pop.Root]
    assert(tween.Goals.Size.Y.Offset==0 and tween.Info[1]==0.16)
    assert(pop.Root.Size.Y.Offset==39,'interrupted opening must not jump before closing')
    pop.Root.Size=U.fromOffset(pop.Root.Size.X.Offset,17)
    near(edge(pop.Root,up),anchored,'closing intermediate size must preserve anchored edge')
    Mock.advance(0.17);assert(not first.Popup and not pop.Portal.Parent)
end
pass('Below/above short lists expand from their top/bottom trigger-facing edge and reverse closing without geometry jumps')
for _,up in ipairs({false,true}) do
    place(long,up);long:Open();Mock.advance(0.19)
    local pop=long.Popup;local root=pop.Root
    assert(root.AnchorPoint.Y==(up and 1 or 0))
    assert(pop.List.CanvasSize.Y.Offset==1080 and pop.List.AbsoluteSize.Y<1080)
    pop.List.CanvasPosition=V.new(0,144)
    local anchored=edge(root,up)
    long:Close();root.Size=U.fromOffset(root.Size.X.Offset,61)
    local top=root.AbsolutePosition;local size=root.AbsoluteSize
    press(long,Mock.Enum.UserInputType.Touch)
    assert(long.Popup==pop and long:IsOpen() and not pop.Closing)
    near(root.AbsolutePosition.Y,top.Y,'reopening must preserve current rectangle')
    near(root.AbsoluteSize.Y,size.Y,'reopening must preserve interpolated height')
    near(edge(root,up),anchored,'reopening retains anchored edge')
    assert(pop.List.CanvasPosition.Y==144 and pop.List.Active and pop.List.ScrollingEnabled)
    for _,row in ipairs(pop.Rows) do assert(row.Button.Interactable and row.Button.Active) end
    Mock.advance(0.2);assert(long.Popup==pop and root.Size.Y.Offset>61)
    press(long);Mock.advance(0.17);assert(not long.Popup)
end
pass('Scrollable long lists reverse closing in the same portal for mouse/touch, retaining current rectangle and scroll position')
place(long,false);long:Open();Mock.advance(0.19)
local pop=long.Popup;local root=pop.Root
local top,size=root.AbsolutePosition,root.AbsoluteSize
place(long,true)
assert(long.Popup==pop and pop.Placement.Upwards and root.AnchorPoint.Y==1)
near(root.AbsolutePosition.Y,top.Y,'changing placement must retain visible top before tween')
near(root.AbsoluteSize.Y,size.Y,'changing placement must retain visible size before tween')
assert(pop.Scope.Animations[root].Goals.Position.Y.Offset==long.Control.AbsolutePosition.Y-5-pop.Portal.AbsolutePosition.Y)
Mock.advance(0.2)
near(edge(root,true),long.Control.AbsolutePosition.Y-5,'new above placement anchors to trigger')
long:Close();root.Size=U.fromOffset(root.Size.X.Offset,50)
top,size=root.AbsolutePosition,root.AbsoluteSize
place(long,false)
assert(pop.Closing and not pop.Placement.Upwards and root.AnchorPoint.Y==0)
near(root.AbsolutePosition.Y,top.Y,'placement change during closing must retain current rectangle')
near(root.AbsoluteSize.Y,size.Y,'placement change during closing must retain current height')
assert(pop.Scope.Animations[root].Goals.Size.Y.Offset==0)
Mock.advance(0.17);assert(not long.Popup and not pop.Portal.Parent)
pass('Available-space changes recalculate direction and re-anchor the existing rectangle safely during opening and closing')
place(first,true);press(first);Mock.advance(0.19)
Mock.input.InputBegan:Fire({UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(1,1)},false)
assert(not first:IsOpen() and first.Popup.Closing);Mock.advance(0.17)
press(first);Mock.advance(0.19);pop=first.Popup
pop.Rows[2].Button.Activated:Fire()
assert(first:GetValue()=='Two' and not first:IsOpen() and pop.Closing)
assert(pop.Scope.Animations[pop.Root].Goals.Size.Y.Offset==0 and pop.Root.AnchorPoint.Y==1)
Mock.advance(0.17)
place(multi,true);press(multi,Mock.Enum.UserInputType.Touch);Mock.advance(0.19)
pop=multi.Popup;assert(pop.Root.AnchorPoint.Y==1 and pop.Clear and pop.List.CanvasSize.Y.Offset==1080)
pop.Rows[2].Button.Activated:Fire();assert(multi:IsOpen() and #multi:GetValue()==2)
place(first,false);press(first)
assert(first:IsOpen() and not multi.Popup and not multi:IsOpen() and W.PopupOwner==first)
first:Close(true);Mock.advance(1)
pass('Above-popup outside touch and selection close downward; multi selection, clear footer and cross-dropdown ownership stay intact')
local baseline=Mock.connections
for _,up in ipairs({false,true}) do
    place(first,up)
    for n=1,41 do
        press(first,n%2==0 and Mock.Enum.UserInputType.Touch or Mock.Enum.UserInputType.MouseButton1)
        assert(first:IsOpen()==(n%2==1))
        if first.Popup then
            assert(first.Popup.Root.AnchorPoint.Y==(up and 1 or 0))
            assert(first.Popup.Root.ClipsDescendants and not first.Popup.Portal.Active)
        end
        Mock.advance(0.008)
    end
    W:SetMinimized(true);assert(not first.Popup and not W.PopupOwner)
    Mock.advance(0.4);W:SetMinimized(false);Mock.advance(0.4)
    assert(first:GetValue()=='Two' and Mock.connections==baseline)
end
for _,object in ipairs(W.OwnRoot:GetDescendants()) do assert(not object:IsA('CanvasGroup') and not object:IsA('UIScale')) end
W:Destroy();Mock.advance(1);assert(Mock.connections==0 and #parent:GetChildren()==0)
Mock.asyncTweens=false
pass('82 rapid directional trigger toggles and minimize preserve selection, clipping and cleanup without scales or compositing')
end
