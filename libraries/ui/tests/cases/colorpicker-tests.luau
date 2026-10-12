do
assert(Mock.connections==0)
local E=libraryEnvironment;local U=E.UDim2;local V=E.Vector2;local C=E.Color3
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui')
local W=A:CreateWindow({Parent=parent,Id='colorpicker-tests',Size=U.fromOffset(680,440)})
local P=W:CreatePage({Name='Controls'});local S=P:CreateSection({Title='Colors'})
local events=0
local picker=S:CreateColorPicker({Name='Color',Default=C.fromRGB(128,64,255),Callback=function() events+=1 end})
local other=S:CreateColorPicker({Name='Other',Default=C.fromRGB(255,0,0)})
local d=S:CreateDropdown({Name='Dropdown',Options={'A','B'},Default='A'})
local function near(a,b) assert(math.abs(a-b)<1e-6,tostring(a)..' != '..tostring(b)) end
local function same(a,b) near(a.R,b.R);near(a.G,b.G);near(a.B,b.B) end
assert(picker:GetHex()=='#8040FF' and events==0)
picker:SetValue(C.fromRGB(10,20,30));assert(picker:GetHex()=='#0A141E' and events==0)
picker:SetValue(C.fromRGB(10,20,30),true);assert(events==0)
picker:SetValue(C.new(-1,2,0.5),true);assert(picker:GetHex()=='#00FF80' and events==1)
assert(not pcall(function() picker:SetValue('red') end))
assert(not pcall(function() picker:SetValue(C.new(0/0,0,0)) end))
local _,valid=picker:SetHex(' #f80 ',true);assert(valid and picker:GetHex()=='#FF8800' and events==2)
_,valid=picker:SetHex('ff8800',true);assert(valid and events==2)
for _,s in ipairs({'#12','#12345g','#11223344','garbage','', '12 34 56'}) do
    _,valid=picker:SetHex(s,true);assert(not valid and picker:GetHex()=='#FF8800' and events==2)
end
for i=0,60 do
    local color=C.fromHSV(i/60,0.73,0.81);picker:SetValue(color)
    same(C.fromHSV(picker.H,picker.S,picker.V),color)
end
pass('Color3 validation/clamping, precise HSV roundtrips, 3/6-digit HEX formatting and invalid input preserve state with deduplicated callbacks')
Mock.advance(1);W.Root.Position=U.fromOffset(100,80);Mock.asyncTweens=true
local function place(c,up) c.Root.Position=U.fromOffset(0,up and 295 or 28) end
local function press(c,kind)
    local p,s=c.Control.AbsolutePosition,c.Control.AbsoluteSize
    local input={UserInputType=kind or Mock.Enum.UserInputType.MouseButton1,Position=V.new(p.X+s.X/2,p.Y+s.Y/2)}
    Mock.input.InputBegan:Fire(input,false);Mock.input.InputEnded:Fire(input);c.Control.Activated:Fire(input,1)
end
for _,up in ipairs({false,true}) do
    place(picker,up);press(picker)
    local pop=picker.Popup;assert(pop and pop.Root.AnchorPoint.Y==(up and 1 or 0))
    local anchored=picker.Control.AbsolutePosition.Y+(up and -5 or picker.Control.AbsoluteSize.Y+5)
    near(pop.Root.AbsolutePosition.Y+(up and pop.Root.AbsoluteSize.Y or 0),anchored)
    assert(not pop.Portal.Active and pop.Root.ZIndex>W.Root.ZIndex and pop.Root.ClipsDescendants)
    Mock.advance(0.2);assert(pop.SV.AbsoluteSize.X==pop.SV.AbsoluteSize.Y and pop.Scroll.CanvasSize.Y.Offset>=pop.Scroll.AbsoluteSize.Y)
    local size=pop.Root.Size;press(picker)
    assert(not picker:IsOpen() and pop.Closing and pop.Root.Size==size)
    pop.Root.Size=U.fromOffset(pop.Root.Size.X.Offset,70);local top=pop.Root.AbsolutePosition.Y
    press(picker,Mock.Enum.UserInputType.Touch)
    assert(picker:IsOpen() and picker.Popup==pop and not pop.Closing and pop.Hex.TextEditable)
    near(pop.Root.AbsolutePosition.Y,top);assert(pop.Root.Size.Y.Offset==70)
    Mock.advance(0.2);press(picker);Mock.advance(0.17);assert(not picker.Popup)
end
pass('ColorPicker native portal chooses both directions, anchors correct edge, scrolls short viewports and reverses trigger closing without recreating popup')
place(picker,false);picker:Open();Mock.advance(0.2)
local moved=picker.Popup;local top,height=moved.Root.AbsolutePosition.Y,moved.Root.AbsoluteSize.Y
place(picker,true)
assert(moved.Placement.Upwards and moved.Root.AnchorPoint.Y==1)
near(moved.Root.AbsolutePosition.Y,top);near(moved.Root.AbsoluteSize.Y,height)
Mock.advance(0.2);near(moved.Root.AbsolutePosition.Y+moved.Root.AbsoluteSize.Y,picker.Control.AbsolutePosition.Y-5)
picker:Close();moved.Root.Size=U.fromOffset(moved.Root.Size.X.Offset,60)
top,height=moved.Root.AbsolutePosition.Y,moved.Root.AbsoluteSize.Y;place(picker,false)
assert(moved.Closing and not moved.Placement.Upwards and moved.Root.AnchorPoint.Y==0)
near(moved.Root.AbsolutePosition.Y,top);near(moved.Root.AbsoluteSize.Y,height)
Mock.advance(0.17);assert(not picker.Popup)
place(picker,false);picker:Open();Mock.advance(0.2)
local pop=picker.Popup;local svp,svs=pop.SV.AbsolutePosition,pop.SV.AbsoluteSize
local input={UserInputType=Mock.Enum.UserInputType.MouseButton1,Position=V.new(svp.X+svs.X/2,svp.Y+svs.Y/4)}
local baselineTweens=#Mock.tweens;local baselineListeners=Mock.connections
pop.SV.InputBegan:Fire(input);near(picker.S,0.5);near(picker.V,0.75)
assert(picker.Drag and not pop.Scroll.ScrollingEnabled and not P.Root.ScrollingEnabled)
for i=1,200 do
    Mock.input.InputChanged:Fire({UserInputType=Mock.Enum.UserInputType.MouseMovement,Position=V.new(svp.X+svs.X*i/200,svp.Y+svs.Y/2)})
end
assert(#Mock.tweens==baselineTweens and Mock.connections==baselineListeners)
Mock.input.InputChanged:Fire({UserInputType=Mock.Enum.UserInputType.MouseMovement,Position=V.new(svp.X-20,svp.Y+svs.Y+20)})
near(picker.S,0);near(picker.V,0)
Mock.input.InputEnded:Fire(input);assert(not picker.Drag and pop.Scroll.ScrollingEnabled and P.Root.ScrollingEnabled)
local hp,hs=pop.Hue.AbsolutePosition,pop.Hue.AbsoluteSize
local touch={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(hp.X+hs.X*0.65,hp.Y)}
pop.HueHit.InputBegan:Fire(touch);near(picker.H,0.65);same(picker:GetValue(),C.new(0,0,0))
local foreign={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(hp.X,hp.Y)}
Mock.input.InputChanged:Fire(foreign);near(picker.H,0.65)
touch.Position=V.new(hp.X+hs.X+50,hp.Y);Mock.input.InputChanged:Fire(touch);near(picker.H,1)
Mock.input.InputEnded:Fire(foreign);assert(picker.Drag);Mock.input.InputEnded:Fire(touch);assert(not picker.Drag)
input.Position=V.new(svp.X+svs.X,svp.Y);pop.SV.InputBegan:Fire(input)
same(picker:GetValue(),C.fromHSV(1,1,1));Mock.input.InputEnded:Fire(input)
pass('200 mouse SV updates allocate no tweens/connections; out-of-bounds clamping, hue on black and touch ownership restore page/popup scrolling')
pop.Hex:CaptureFocus();pop.Hex.Text='#abcdef';pop.Hex:ReleaseFocus(true)
assert(picker:GetHex()=='#ABCDEF' and pop.Hex.Text=='#ABCDEF')
local count=events;pop.Hex:CaptureFocus();pop.Hex.Text='wrong';pop.Hex:ReleaseFocus(false)
assert(picker:GetHex()=='#ABCDEF' and pop.Hex.Text=='#ABCDEF' and events==count)
pop.RGB[1]:CaptureFocus();pop.RGB[1].Text='400';pop.RGB[1]:ReleaseFocus(false)
assert(picker:GetHex()=='#FFCDEF' and pop.RGB[1].Text=='255')
pop.RGB[2]:CaptureFocus();pop.RGB[2].Text='-4';pop.RGB[2]:ReleaseFocus(false)
assert(picker:GetHex()=='#FF00EF' and pop.RGB[2].Text=='0')
pop.RGB[3]:CaptureFocus();pop.RGB[3].Text='invalid';pop.RGB[3]:ReleaseFocus(false)
assert(picker:GetHex()=='#FF00EF' and pop.RGB[3].Text=='239')
picker:SetValue(C.fromRGB(20,30,40));assert(pop.Hex.Text=='#141E28' and pop.RGB[2].Text=='30')
same(pop.Preview.BackgroundColor3,picker:GetValue());same(picker.Swatch.BackgroundColor3,picker:GetValue())
pop.Hex:CaptureFocus();picker:SetDisabled(true)
assert(not picker.Popup and not picker:IsOpen() and not Mock.input:GetFocusedTextBox())
picker.Control.Activated:Fire();assert(not picker.Popup);picker:SetDisabled(false)
pass('HEX/RGB editable fields validate and restore invalid input, clamp channels, sync dynamic values and release focus when disabled')
place(picker,true);picker:Open();Mock.advance(0.2)
Mock.input.InputBegan:Fire({UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(1,1)},false)
assert(not picker:IsOpen());Mock.advance(0.17)
picker:Open();Mock.advance(0.2);place(other,false);other:Open()
assert(not picker.Popup and other:IsOpen() and W.PopupOwner==other)
place(d,false);d:Open();assert(not other.Popup and d:IsOpen())
picker:Open();assert(not d.Popup and picker:IsOpen())
local Q=W:CreatePage({Name='Other'});Q:Select();assert(not picker.Popup)
Mock.advance(0.3);P:Select();Mock.advance(0.3);picker:Open();W:SetMinimized(true);assert(not picker.Popup)
Mock.advance(0.4);W:SetMinimized(false);Mock.advance(0.4)
local remembered=picker:GetHex();local baseline=Mock.connections
place(picker,false)
for i=1,101 do press(picker);assert(picker:IsOpen()==(i%2==1));Mock.advance(0.008) end
picker:Close(true);Mock.advance(1);assert(Mock.connections==baseline and picker:GetHex()==remembered)
picker:Open();Mock.advance(0.2);pop=picker.Popup
input.Position=pop.SV.AbsolutePosition;pop.SV.InputBegan:Fire(input)
assert(picker.Drag);picker:Destroy();assert(not picker.Drag and P.Root.ScrollingEnabled)
W:Destroy();Mock.advance(1);assert(Mock.connections==0 and not Mock.input:GetFocusedTextBox())
Mock.asyncTweens=false
pass('Outside touch, Dropdown/ColorPicker arbitration, navigation/minimize, 101 rapid toggles and destruction during dragging clean every portal/listener')
local W2=A:CreateWindow({Parent=parent,Id='colorpicker-error',Size=U.fromOffset(680,440)})
local S2=W2:CreatePage({Name='Test'}):CreateSection({Title='Color'})
local connections=Mock.connections;local children=#S2.Root:GetChildren()
assert(not pcall(function() S2:CreateColorPicker({Name='Bad',Default='red'}) end))
assert(not pcall(function() S2:CreateColorPicker({Name='Bad',Default=false}) end))
assert(Mock.connections==connections and #S2.Root:GetChildren()==children)
local dying=S2:CreateColorPicker({Name='Destroy on color',Default=C.new(1,0,0),Callback=function() W2:Destroy() end})
dying.Root.Position=U.fromOffset(0,28);dying:Open()
local hit={UserInputType=Mock.Enum.UserInputType.Touch,Position=dying.Popup.SV.AbsolutePosition}
dying.Popup.SV.InputBegan:Fire(hit);Mock.advance(1)
assert(not dying.Scope.Alive and Mock.connections==0 and #parent:GetChildren()==0)
pass('ColorPicker rejects invalid defaults without allocation; a color-change callback may destroy its window mid-drag without leaks')
end
