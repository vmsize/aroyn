-- Actual library implementation, deterministic Roblox/input/tween doubles.
do
assert(Mock.connections==0)
local A=makeLibrary();local E=libraryEnvironment;local V=E.Vector2;local U=E.UDim2
local parent=Mock.Instance.new('PlayerGui')
local W=A:CreateWindow({Parent=parent,Id='advanced',Size=U.fromOffset(680,440)})
local P=W:CreatePage({Name='Advanced'});local S=P:CreateSection({Title='Values'})
local counts={slider=0,dropdown=0,multi=0}
local slider=S:CreateSlider({Name='Integer',Min=10,Max=30,Step=2,Default=17,Suffix=' ms',Callback=function(v) counts.slider+=1;counts.value=v end})
assert(slider:GetValue()==18 and slider.ValueLabel.Text=='18 ms' and counts.slider==0)
slider:SetValue(100);assert(slider:GetValue()==30 and counts.slider==0)
slider:SetValue(-100,true);assert(slider:GetValue()==10 and counts.slider==1)
slider:SetValue(10,true);assert(counts.slider==1)
slider:SetDisabled(true);slider:SetValue(24,true);assert(slider:GetValue()==24 and counts.slider==2 and not slider.Hitbox.Interactable)
slider:SetDisabled(false)
local decimal=S:CreateSlider({Name='Decimal',Min=-0.5,Max=1.03,Step=0.05,Default=0.28,Suffix=' s'})
assert(math.abs(decimal:GetValue()-0.3)<1e-8 and decimal.ValueLabel.Text=='0.30 s')
decimal:SetValue(1.03);assert(decimal:GetValue()==1.03 and decimal.ValueLabel.Text=='1.03 s')
local fixed=S:CreateSlider({Name='Fixed',Min=3,Max=3,Default=8});assert(fixed:GetValue()==3 and fixed.Thumb.Position.X.Offset==0)
local tiny=S:CreateSlider({Name='Tiny',Min=0,Max=1e-9,Step=1e-12,Default=5e-12});assert(tiny.ValueLabel.Text~='0.000000000')
pass('Slider clamps and quantizes nonzero minima, decimal steps, exact endpoints and fixed ranges; silent/changed callbacks and disabled setters')
local beforeComponents=#S.Components;local baseline=Mock.connections
for _,bad in ipairs({{Min=2,Max=1},{Step=0},{Step=-1},{Default='bad'},{Min=false},{Max=math.huge},{Step=0/0}}) do
    bad.Name='Invalid';assert(not pcall(function() S:CreateSlider(bad) end))
end
for _,bad in ipairs({{Options=false},{Options={'a',4}},{Options={[2]='a'}},{Multi=true,Default=false},{MaxVisibleOptions=0}}) do
    bad.Name='Invalid';assert(not pcall(function() S:CreateDropdown(bad) end))
end
assert(#S.Components==beforeComponents and Mock.connections==baseline)
assert(not pcall(function() slider:SetValue(0/0) end))
assert(not pcall(function() slider:SetValue(math.huge) end))
pass('Advanced options reject invalid numbers, ranges, steps and malformed lists before allocating controls/listeners')
local track=slider.Track;local p,size=track.AbsolutePosition,track.AbsoluteSize
local mouse={UserInputType=Mock.Enum.UserInputType.MouseButton1,Position=V.new(p.X+size.X/2,p.Y)}
local tweenCount=#Mock.tweens
slider.Hitbox.InputBegan:Fire(mouse)
assert(slider.Drag==mouse and slider:GetValue()==20 and not P.Root.ScrollingEnabled)
for n=1,150 do Mock.input.InputChanged:Fire({UserInputType=Mock.Enum.UserInputType.MouseMovement,Position=V.new(p.X+size.X*n/150,p.Y)}) end
assert(slider:GetValue()==30 and #Mock.tweens==tweenCount)
Mock.input.InputEnded:Fire(mouse);assert(not slider.Drag and P.Root.ScrollingEnabled)
local touch={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(p.X,p.Y)}
slider.Hitbox.InputBegan:Fire(touch)
local foreign={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(p.X+size.X,p.Y)}
Mock.input.InputChanged:Fire(foreign);assert(slider:GetValue()==10)
touch.Position=foreign.Position;Mock.input.InputChanged:Fire(touch);assert(slider:GetValue()==30)
Mock.input.InputEnded:Fire(foreign);assert(slider.Drag==touch)
slider:SetDisabled(true);assert(not slider.Drag and P.Root.ScrollingEnabled)
slider:SetDisabled(false);slider.Hitbox.InputBegan:Fire(touch)
Mock.input.WindowFocusReleased:Fire();assert(not slider.Drag and P.Root.ScrollingEnabled)
slider.Hitbox.InputBegan:Fire(touch);slider:Destroy();assert(P.Root.ScrollingEnabled)
Mock.input.InputChanged:Fire(touch)
for _,c in ipairs(S.Components) do c.Root.Size=U.new(1,0,0,c.Height+34) end
S:Reflow();decimal:Destroy()
assert(fixed.Root.Position.Y.Offset==28 and tiny.Root.Position.Y.Offset==28+fixed.Root.Size.Y.Offset+A.Theme.Metrics.Gap)
pass('150 drag updates create zero tweens; track click, mouse/touch ownership, disabled/focus interruption and drag destruction restore scrolling')
local d=S:CreateDropdown({Name='Single',Options={'One','Two','Two','Three'},Default='One',Callback=function(v) counts.dropdown+=1;counts.choice=v end})
d.Root.Position=U.fromOffset(0,28)
assert(d:GetValue()=='One' and #d:GetOptions()==3 and counts.dropdown==0)
d:SetValue('Two');assert(counts.dropdown==0)
d:SetValue('Three',true);assert(counts.dropdown==1)
d:SetValue('Three',true);assert(counts.dropdown==1)
d:SetValue('invalid',true);assert(d:GetValue()==nil and counts.dropdown==2)
d:SetValue('One');d.Control.Activated:Fire();assert(d:IsOpen())
local pop=d.Popup
assert(pop.Portal.Parent==W.OwnRoot and not pop.Root:IsDescendantOf(W.Root))
assert(not pop.Portal.Active and pop.Root.ZIndex>W.Root.ZIndex and pop.Rows[1].Mark.Text=='✓')
pop.Rows[2].Button.Activated:Fire()
assert(not d:IsOpen() and not d.Popup and d:GetValue()=='Two' and counts.choice=='Two')
pass('Single Dropdown deduplicates options, preserves silent/changed callback semantics and opens above clipped pages in a nonblocking ScreenGui portal')
d:Open();local stable=Mock.connections
for _=1,100 do
    d.Popup.Rows[1].Button.MouseEnter:Fire();d.Popup.Rows[1].Button.MouseLeave:Fire()
end
assert(Mock.connections==stable)
Mock.input.InputBegan:Fire({UserInputType=Mock.Enum.UserInputType.Touch,Position=d.Popup.Rows[1].Button.AbsolutePosition+V.new(10,10)})
assert(d:IsOpen())
Mock.input.InputBegan:Fire({UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(1,1)})
assert(not d:IsOpen() and not d.Popup)
d:Open();Mock.input.InputBegan:Fire({KeyCode=Mock.Enum.KeyCode.Escape});assert(not d:IsOpen())
d:Open();d:SetDisabled(true);assert(not d.Popup and not d:IsOpen())
d.Control.Activated:Fire();assert(not d:IsOpen());d:SetDisabled(false)
pass('Dropdown dismisses outside touch, Escape and disabled state; inside taps and repeated hover keep correct ownership without listener growth')
local opts={};for i=1,30 do table.insert(opts,'Option '..i) end
d:SetOptions(opts);d:Open();pop=d.Popup
assert(pop.List.CanvasSize.Y.Offset==1080 and pop.List.AbsoluteSize.Y<1080)
local rp,rs=W.Root.AbsolutePosition,W.Root.AbsoluteSize;local pp,ps=pop.Root.AbsolutePosition,pop.Root.AbsoluteSize
assert(pp.X>=rp.X and pp.Y>=rp.Y and pp.X+ps.X<=rp.X+rs.X and pp.Y+ps.Y<=rp.Y+rs.Y)
W.Root.Position=U.fromOffset(60,70)
assert(d.Popup and d.Popup.Root.AbsolutePosition.X>=60)
local copied=d:GetOptions();copied[1]='external mutation';assert(d:GetOptions()[1]=='Option 1')
d:SetValue('Option 2');local events=counts.dropdown
d:SetOptions({'Option 2','New'},true);assert(d:IsOpen() and d:GetValue()=='Option 2' and counts.dropdown==events)
d:SetOptions({'New'},true);assert(d:IsOpen() and d:GetValue()==nil and counts.dropdown==events+1)
d:SetOptions({});assert(d:IsOpen() and #d.Popup.Rows==0 and d.ValueLabel.Text=='No options')
d:Close(true)
pass('Long Dropdown scrolls internally, stays within moving window bounds, copies options defensively and refreshes selections/empty lists without leaks')
d:SetOptions(opts);d.Root.Position=U.fromOffset(0,295);d:Open()
assert(d:IsOpen() and d.Popup.Root.AbsolutePosition.Y<d.Control.AbsolutePosition.Y)
P.Root.CanvasPosition=V.new(0,1000);assert(not d:IsOpen() and not d.Popup)
P.Root.CanvasPosition=V.zero;d.Root.Position=U.fromOffset(0,28);d:Open()
local Q=W:CreatePage({Name='Other'});Q:Select();assert(not d:IsOpen() and not d.Popup)
P:Select();d:Open();W:SetMinimized(true);assert(not d.Popup)
W:SetMinimized(false);assert(d:GetOptions()[1]=='Option 1')
pass('Popup chooses above when needed; scrolling trigger out of view, page navigation and minimize close it without resetting values')
local values={'C','A','A','Unknown'}
local multi=S:CreateDropdown({Name='Multi',Multi=true,Options={'A','B','C'},Default=values,Callback=function(v) counts.multi+=1;v[1]='callback mutation' end})
multi.Root.Position=U.fromOffset(0,64)
values[1]='changed';assert(table.concat(multi:GetValue(),',')=='A,C' and multi.ValueLabel.Text=='2 selected')
local selection=multi:GetValue();selection[1]='changed';assert(multi:GetValue()[1]=='A')
multi:SetValue({'C','A'},true);assert(counts.multi==0)
multi:Open();multi.Popup.Rows[2].Button.Activated:Fire()
assert(multi:IsOpen() and table.concat(multi:GetValue(),',')=='A,B,C' and counts.multi==1)
multi.Popup.Rows[1].Button.Activated:Fire();assert(table.concat(multi:GetValue(),',')=='B,C')
multi.Popup.Clear.Activated:Fire();assert(multi:IsOpen() and #multi:GetValue()==0)
local eventCount=counts.multi;multi:Clear(true);assert(counts.multi==eventCount)
multi:SetValue({'B'});assert(multi.ValueLabel.Text=='B')
multi:SetOptions({'C'},true);assert(#multi:GetValue()==0)
d:Open();assert(d:IsOpen() and not multi:IsOpen() and not multi.Popup)
pass('Multi Dropdown reuses the portal, toggles/clears selections, orders/deduplicates values and isolates returned/callback arrays; only one popup per window')
Mock.asyncTweens=true
d:Close(true);Mock.advance(1);local baselineCount=Mock.connections
for n=1,60 do d:Open();Mock.advance(0.012);d:Close();Mock.advance(0.012) end
d:Close(true);Mock.advance(1)
assert(not d.Popup and Mock.connections==baselineCount)
for _,obj in ipairs(W.OwnRoot:GetDescendants()) do
    assert(not obj:IsA('CanvasGroup') and not obj:IsA('UIScale'))
    assert(obj.Name~='AroynDropdownPortal')
end
d:Open();Mock.advance(0.18);assert(d:IsOpen() and d.Popup.Root.Size.Y.Offset>0)
d:Close();local closing=d.Popup;assert(not d:IsOpen() and not closing.Root.Active)
for _,row in ipairs(closing.Rows) do assert(not row.Button.Interactable) end
Mock.advance(0.16);assert(not d.Popup and not closing.Portal.Parent)
pass('60 interrupted popup open/close cycles cancel safely; completed close removes all portal listeners and never adds scaling/compositing')
Mock.asyncTweens=false
local dying=S:CreateDropdown({Name='Destroy on choice',Options={'Destroy'},Callback=function() W:Destroy() end})
dying.Root.Position=U.fromOffset(0,28);dying:Open();dying.Popup.Rows[1].Button.Activated:Fire()
Mock.advance(1);assert(Mock.connections==0 and #parent:GetChildren()==0)
pass('Dropdown callback can destroy its window during selection without orphan portals, tweens or input listeners')
end
