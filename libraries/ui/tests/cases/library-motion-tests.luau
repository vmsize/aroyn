Mock.asyncTweens=true
Aroyn.IconAtlas='mock-local-atlas'
local animated=Aroyn:CreateWindow({Parent=parent,Id='motion'})
local one=animated:CreatePage({Name='One',Icon='plot'})
local controls=one:CreateSection({Title='Animated controls'})
local switch=controls:CreateToggle({Name='Switch'})
local field=controls:CreateTextInput({Name='Field',Default='keep'})
local action=controls:CreateButton({Name='Action'})
local two=animated:CreatePage({Name='Two',Icon='compost'})
Mock.advance(0.3)
local full=animated.Root.Size
local startPosition=animated.Root.Position
for _,object in ipairs(animated.Root:GetDescendants()) do assert(not object:IsA('CanvasGroup')) end
for n=1,80 do
    animated:SelectPage(n%2==0 and 'One' or 'Two')
    switch:SetValue(n%3==0)
    action.Control.MouseEnter:Fire();action.Control.MouseButton1Down:Fire();action.Control.MouseButton1Up:Fire()
    Mock.advance(0.015)
end
animated:SelectPage('One');switch:SetValue(true);field:SetDisabled(true)
Mock.advance(0.3)
assert(one.Root.Visible and not two.Root.Visible and switch:GetValue())
assert(switch.Thumb.Position.X.Scale==1 and not field.Control.TextEditable)
field:SetDisabled(false);field.Control:CaptureFocus();Mock.advance(0.12)
assert(field.Edge.Transparency==Aroyn.Theme.Borders.Focus)
field.Control:ReleaseFocus(false);Mock.advance(0.12)
assert(field.Edge.Transparency==Aroyn.Theme.Borders.Normal)
animated:SelectPage('Two');Mock.advance(0.02);animated:SetMinimized(true)
Mock.advance(0.4)
assert(not animated.Root.Visible and animated.Root.Size==full and animated.Root.Position==startPosition and animated.Restore.Visible)
assert(animated.Restore.Interactable and not field.Control.TextEditable)
-- Floating dragging owns an independent persistent position; header never moves.
local float=animated.Restore
local p=float.AbsolutePosition
local touch={UserInputType=Mock.Enum.UserInputType.Touch,Position=libraryEnvironment.Vector2.new(p.X+24,p.Y+24)}
float.InputBegan:Fire(touch)
touch.Position=libraryEnvironment.Vector2.new(touch.Position.X+28.2,touch.Position.Y+18.2)
Mock.input.InputChanged:Fire(touch);Mock.input.InputEnded:Fire(touch);float.Activated:Fire(touch)
local floatingPosition=float.Position
assert(animated.Minimized and not animated.Root.Visible and animated.Root.Position==startPosition)
animated:SetMinimized(false);Mock.advance(0.4)
assert(animated.Root.Size==full and animated.Root.Position==startPosition)
assert(animated.Selected==two and field:GetValue()=='keep' and field.Control.TextEditable)
animated:SetMinimized(true);Mock.advance(0.4)
assert(float.Position==floatingPosition)
local tap={UserInputType=Mock.Enum.UserInputType.MouseButton1,Position=float.AbsolutePosition+libraryEnvironment.Vector2.new(24,24)}
float.InputBegan:Fire(tap);Mock.input.InputEnded:Fire(tap);Mock.advance(0.4)
assert(animated.Root.Visible and not float.Visible)
for n=1,60 do animated:SetMinimized(n%2==1);Mock.advance(0.012) end
animated:SetMinimized(false);Mock.advance(0.4)
assert(animated.Root.Size==full and switch.Control.Interactable and field.Control.TextEditable)
pass('standalone timed transitions, rapid control tweens, animated focus, persistent floating drag/tap and 60 reversals retain state')
animated:SelectPage('One');animated:SetMinimized(true);animated:Destroy()
Mock.advance(1)
assert(Mock.connections==0 and #parent:GetChildren()==0)
local fallback=makeLibrary()
fallback.MotionEnabled=false
local basic=fallback:CreateWindow({Parent=parent,Id='reduced-motion'})
basic:CreatePage({Name='A'});local page=basic:CreatePage({Name='B'});page:Select()
assert(page.Root.Visible and basic.PageSurface:IsA('Frame') and not basic.PageMotion.Busy)
basic:SetMinimized(true);assert(not basic.Root.Visible and basic.Restore.Visible)
basic:SetMinimized(false);assert(basic.Root.Visible and not basic.Restore.Visible)
basic:Destroy();Mock.advance(1)
assert(Mock.connections==0 and #parent:GetChildren()==0)
Mock.asyncTweens=false
pass('destruction cancels pending completions; reduced-motion Frame fallback remains usable without CanvasGroup')
