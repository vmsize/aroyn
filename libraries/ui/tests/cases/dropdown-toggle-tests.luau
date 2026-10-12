-- Regression: emulate native InputBegan -> InputEnded -> Activated with nonzero topbar inset.
-- InputObject.Position and AbsolutePosition share CoreUISafeInsets coordinates.
do
assert(Mock.connections==0)
local E=libraryEnvironment;local V=E.Vector2;local U=E.UDim2
local gui=Mock.services.GuiService
local originalInset=gui.GetGuiInset
gui.GetGuiInset=function() return V.new(0,58),V.zero end
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui')
local W=A:CreateWindow({Parent=parent,Id='dropdown-toggle-regression',Size=U.fromOffset(680,440)})
W.OwnRoot.IgnoreGuiInset=false
local P=W:CreatePage({Name='Controls'});local S=P:CreateSection({Title='Dropdowns'})
local callbackCount=0
local first=S:CreateDropdown({Name='First',Options={'One','Two'},Default='One',Callback=function() callbackCount+=1 end})
local second=S:CreateDropdown({Name='Second',Options={'Three','Four'},Default='Three'})
local multi=S:CreateDropdown({Name='Multi',Options={'A','B'},Default={'A'},Multi=true})
local function press(component,kind,controlFirst)
    local p,s=component.Control.AbsolutePosition,component.Control.AbsoluteSize
    local input={UserInputType=kind or Mock.Enum.UserInputType.MouseButton1,Position=V.new(p.X+s.X/2,p.Y+s.Y/2)}
    if controlFirst then component.Control.InputBegan:Fire(input) end
    Mock.input.InputBegan:Fire(input,false)
    if not controlFirst then component.Control.InputBegan:Fire(input) end
    Mock.input.InputEnded:Fire(input)
    component.Control.Activated:Fire(input,1)
end
Mock.asyncTweens=true
press(first);assert(first:IsOpen());Mock.advance(0.2)
local originalPopup=first.Popup
press(first)
assert(not first:IsOpen(),'second trigger click must close, not close in InputBegan and reopen in Activated')
assert(first.Popup==originalPopup and originalPopup.Closing,'same popup must finish its closing animation')
Mock.advance(0.17);assert(not first.Popup)
press(first);assert(first:IsOpen());Mock.advance(0.2)
assert(first.Popup~=originalPopup and first:GetValue()=='One' and callbackCount==0)
pass('Dropdown actual pointer event sequence at 58px inset: closed/open/closed/open; second click preserves one closing animation')
for _,kind in ipairs({Mock.Enum.UserInputType.MouseButton1,Mock.Enum.UserInputType.Touch}) do
    first:Close(true)
    for n=1,30 do
        press(first,kind,n%2==0)
        assert(first:IsOpen()==(n%2==1),'same trigger must alternate for mouse and touch')
        Mock.advance(0.22)
    end
    assert(not first.Popup)
end
W.OwnRoot.IgnoreGuiInset=true
press(first);press(first);assert(not first:IsOpen());Mock.advance(0.2)
W.OwnRoot.IgnoreGuiInset=false
pass('Repeated mouse/touch trigger clicks alternate reliably with both IgnoreGuiInset settings and no selection callbacks')
press(first);Mock.advance(0.2)
local popup=first.Popup
local option=popup.Rows[2].Button
local p,s=option.AbsolutePosition,option.AbsoluteSize
local choice={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(p.X+s.X/2,p.Y+s.Y/2)}
Mock.input.InputBegan:Fire(choice,false)
assert(first:IsOpen() and first.Popup==popup,'option press must not be treated as outside')
Mock.input.InputEnded:Fire(choice);option.Activated:Fire(choice,1)
assert(not first:IsOpen() and first:GetValue()=='Two' and callbackCount==1)
Mock.advance(0.2);assert(not first.Popup)
press(first);Mock.advance(0.2)
local outside={UserInputType=Mock.Enum.UserInputType.MouseButton1,Position=V.new(1,1)}
Mock.input.InputBegan:Fire(outside,false);Mock.input.InputEnded:Fire(outside)
assert(not first:IsOpen());Mock.advance(0.2);assert(not first.Popup and first:GetValue()=='Two')
press(multi,Mock.Enum.UserInputType.Touch);Mock.advance(0.2)
local row=multi.Popup.Rows[2].Button;p,s=row.AbsolutePosition,row.AbsoluteSize
local touch={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(p.X+s.X/2,p.Y+s.Y/2)}
Mock.input.InputBegan:Fire(touch,false);Mock.input.InputEnded:Fire(touch);row.Activated:Fire(touch,1)
assert(multi:IsOpen() and #multi:GetValue()==2)
press(multi,Mock.Enum.UserInputType.Touch);assert(not multi:IsOpen());Mock.advance(0.2)
pass('Outside press closes without reopening; inset-aware option touch selects/ closes single and preserves multi close-on-trigger behavior')
press(first);Mock.advance(0.2)
press(second);assert(not first:IsOpen() and second:IsOpen() and W.PopupOwner==second)
Mock.advance(0.2);assert(not first.Popup)
press(first,Mock.Enum.UserInputType.Touch);assert(first:IsOpen() and not second:IsOpen() and W.PopupOwner==first)
Mock.advance(0.2);assert(not second.Popup)
first:Close(true);Mock.advance(1)
local baseline=Mock.connections
for n=1,101 do
    press(first,n%2==1 and Mock.Enum.UserInputType.MouseButton1 or Mock.Enum.UserInputType.Touch)
    assert(first:IsOpen()==(n%2==1))
    Mock.advance(0.009)
end
assert(first:IsOpen());W:SetMinimized(true)
assert(not first:IsOpen() and not first.Popup and not W.PopupOwner)
Mock.advance(0.4);W:SetMinimized(false);Mock.advance(0.4)
assert(first:GetValue()=='Two' and not first.Popup and Mock.connections==baseline)
press(first);Mock.advance(0.2);press(first)
local closing=first.Popup
assert(closing and closing.Closing)
for _,row in ipairs(closing.Rows) do assert(not row.Button.Interactable) end
W:Destroy();Mock.advance(1)
assert(Mock.connections==0 and #parent:GetChildren()==0)
Mock.asyncTweens=false;gui.GetGuiInset=originalInset
pass('Two-dropdown arbitration, 101 interrupted toggles, minimize and destruction cancel popups without leaked listeners or blocking controls')
end
