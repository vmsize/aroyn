do
assert(Mock.connections==0)
local E=libraryEnvironment;local U,V=E.UDim2,E.Vector2
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui')
local function newWindow(id)
    local w=A:CreateWindow({Parent=parent,Id=id,Size=U.fromOffset(680,440)})
    local p=w:CreatePage({Name='General'});local s=p:CreateSection({Title='Controls'})
    Mock.advance(1);return w,p,s
end
local W,P,S=newWindow('overlay-tests');Mock.asyncTweens=true
local dismissals={}
local function toast(kind,duration)
    return W:Notify({Title=kind,Type=kind,Description='Local notification',Duration=duration or 0,
        OnDismiss=function(reason,id) dismissals[id]=reason end})
end
local t={};for _,kind in ipairs({'Info','Success','Warning','Error'}) do table.insert(t,toast(kind)) end
assert(#W.Overlays.Toasts==3 and #W.Overlays.ToastQueue==1 and t[4]:GetState()=='Queued',tostring(#W.Overlays.Toasts)..' / '..#W.Overlays.ToastQueue..' / '..t[1].State..' / '..tostring(t[1].Reason))
assert(t[1].Id~=t[2].Id and not W.Overlays.Portal.Active)
for i=1,3 do assert(not t[i].Root.Active and t[i].CloseButton.Interactable) end
Mock.advance(0.21)
assert(t[1].Root.BackgroundTransparency==0 and t[1].Labels[1].TextTransparency==0)
local oldY=t[2].Root.Position.Y.Offset
t[1].CloseButton.Activated:Fire();t[1].CloseButton.Activated:Fire()
assert(t[1]:GetState()=='Closing' and t[4]:GetState()=='Queued')
Mock.advance(0.4)
assert(t[1]:GetState()=='Dismissed' and dismissals[t[1].Id]=='manual')
assert(t[4]:GetState()=='Visible' and t[2].Root.Position.Y.Offset<oldY)
for i=2,4 do t[i]:Dismiss() end;Mock.advance(1)
pass('Toast four types, unique IDs, three visible, FIFO promotion, nonblocking portal and animated reposition/manual close')
local timed=toast('Info',0.5);Mock.advance(0.69);assert(timed:GetState()=='Visible')
Mock.advance(0.02);assert(timed:GetState()=='Closing' and timed.Timer==nil)
Mock.advance(0.18);assert(timed:GetState()=='Dismissed' and timed:GetDismissReason()=='timeout')
local manual=toast('Success',8);assert(manual.Timer);manual:Dismiss();assert(not manual.Timer)
Mock.advance(10);assert(manual:GetDismissReason()=='programmatic')
local persistent=W:Notify({Title='Persistent',Duration=0,Dismissible=false})
assert(not persistent.CloseButton and not persistent.Timer);persistent:Dismiss();Mock.advance(1)
pass('Toast durations begin after entrance, timeout exits, manual cancellation removes timer and persistent nondismissible API still closes')
local burst={};for i=1,75 do table.insert(burst,W:Notify({Title='Burst '..i,Duration=0})) end
assert(#W.Overlays.Toasts==3 and #W.Overlays.ToastQueue==64)
for i=68,75 do assert(burst[i]:GetDismissReason()=='overflow') end
burst[7]:Dismiss();assert(burst[7]:GetState()=='Dismissed')
burst[1]:Dismiss();Mock.advance(0.2);assert(burst[4]:GetState()=='Visible')
W:SetMinimized(true);assert(#W.Overlays.Toasts==0 and #W.Overlays.ToastQueue==0)
for i=2,67 do assert(burst[i]:GetState()=='Dismissed') end
local suppressed=W:Notify({Title='Hidden'});assert(suppressed:GetDismissReason()=='minimized')
Mock.advance(1);W:SetMinimized(false);Mock.advance(1)
pass('75 rapid toasts respect bounded FIFO, queued dismissal, overflow and deterministic minimize/no-resurrection policy')
local toggle=S:CreateToggle({Name='Preserved',Default=true})
local disabled=S:CreateButton({Name='Disabled',Disabled=true})
local field=S:CreateTextInput({Name='Text',Default='Retained'})
local d=S:CreateDropdown({Name='Choices',Options={'A','B'},Default='A'})
local color=S:CreateColorPicker({Name='Color',Default=E.Color3.fromRGB(1,2,3)})
local key=S:CreateKeybind({Name='Always',Mode='Always'})
local toggleKey=S:CreateKeybind({Name='Toggle',Default='H',Mode='Toggle'})
field.Control:CaptureFocus();d:Open();Mock.advance(0.2)
local ack=0;local alert=W:Dialog({Title='Alert',Description=string.rep('Long readable description. ',100),Type='Alert',OnAcknowledge=function() ack+=1 end})
assert(not d.Popup and W.Root:GetAttribute('AroynModalBlocked'))
assert(not toggle.Control.Interactable and not field.Control.TextEditable and not P.Root.ScrollingEnabled)
assert(not key:GetActive() and not field.Control:IsFocused())
Mock.input.InputBegan:Fire({UserInputType=Mock.Enum.UserInputType.Keyboard,KeyCode=Mock.Enum.KeyCode.H},false)
toggle.Control.Activated:Fire();assert(toggle:GetValue() and not toggleKey:GetActive())
local late=S:CreateButton({Name='Created while modal'});assert(not late.Control.Interactable)
Mock.input.InputBegan:Fire({KeyCode=Mock.Enum.KeyCode.Escape});assert(alert:GetState()=='Open')
assert(alert.Scroll.AutomaticCanvasSize==Mock.Enum.AutomaticSize.Y and alert.Scroll.ScrollingEnabled)
alert.Buttons[1].Activated:Fire({UserInputType=Mock.Enum.UserInputType.Touch})
for _=1,20 do alert.Buttons[1].Activated:Fire() end
assert(ack==1 and alert:GetState()=='Closing' and not toggle.Control.Interactable)
Mock.advance(0.2)
assert(alert:GetState()=='Closed' and alert:GetAction()=='acknowledge' and not W.Root:GetAttribute('AroynModalBlocked'))
assert(toggle.Control.Interactable and field.Control.TextEditable and P.Root.ScrollingEnabled and key:GetActive())
assert(not disabled.Control.Interactable and late.Control.Interactable and field:GetValue()=='Retained')
pass('Alert touch acknowledgment executes once; modal closes Dropdown, releases focus/Keybinds and gates old/new background controls while long text scrolls')
local confirms,cancels=0,{}
local function confirm(outside)
    return W:Dialog({Type='Confirm',Title='Confirm?',OutsideDismiss=outside==true,
        OnConfirm=function() confirms+=1 end,OnCancel=function(reason) table.insert(cancels,reason) end})
end
local h=confirm();h.Buttons[2].Activated:Fire();h.Buttons[1].Activated:Fire();h:Close()
Mock.advance(0.2);assert(confirms==1 and #cancels==0 and h:GetAction()=='confirm')
h=confirm();h.Buttons[1].Activated:Fire();Mock.advance(0.2)
assert(confirms==1 and #cancels==1 and cancels[1]=='cancel' and h:GetDismissReason()=='cancel')
h=confirm();Mock.input.InputBegan:Fire({KeyCode=Mock.Enum.KeyCode.Escape});Mock.advance(0.2)
assert(cancels[2]=='escape' and confirms==1)
local outside={UserInputType=Mock.Enum.UserInputType.Touch,Position=V.new(1,1)}
h=confirm(false);h.Blocker.InputBegan:Fire(outside);assert(h:GetState()=='Open');h:Close();Mock.advance(0.2)
h=confirm(true);h.Blocker.InputBegan:Fire({UserInputType=Mock.Enum.UserInputType.Touch,Position=h.Root.AbsolutePosition+V.new(10,10)})
assert(h:GetState()=='Open');h.Blocker.InputBegan:Fire(outside);Mock.advance(0.2)
assert(h:GetDismissReason()=='outside' and cancels[#cancels]=='outside' and confirms==1)
pass('Confirm/Cancel, Escape, configurable outside mouse/touch and repeated action clicks preserve exactly-once semantics')
local customCalls=0
local custom=W:Dialog({Type='Custom',Title='Decision',Actions={{Id='first',Text='First'},
    {Id='second',Text='Second',Primary=true,Callback=function() customCalls+=1 end},{Id='third',Text='Third'}}})
local queued1=confirm();local queued2=confirm()
assert(custom:GetState()=='Open' and queued1:GetState()=='Queued' and queued2:GetState()=='Queued')
custom.Buttons[2].Activated:Fire();Mock.advance(0.2)
assert(customCalls==1 and custom:GetAction()=='second' and queued1:GetState()=='Open' and not toggle.Control.Interactable)
queued2:Close('queued_cancel');assert(queued2:GetState()=='Closed')
queued1:Close();Mock.advance(0.2);assert(not W.Overlays.ActiveDialog and toggle.Control.Interactable)
pass('Custom 1–3 actions, explicit action result, one active/FIFO handoff and queued cancellation retain modal input gate')
color:Open();Mock.advance(0.2);h=confirm();assert(not color.Popup)
toggle:SetDisabled(true);field:SetDisabled(true)
local other=W:CreatePage({Name='Other'});W:SelectPage('Other',false)
assert(h:GetDismissReason()=='page_changed' and h:GetState()=='Closed' and confirms==1)
Mock.advance(0.4);W:SelectPage('General',false);Mock.advance(0.4)
assert(not toggle.Control.Interactable and not field.Control.TextEditable)
toggle:SetDisabled(false);field:SetDisabled(false)
h=confirm();local q=confirm();W:SetMinimized(true)
assert(h:GetDismissReason()=='minimized' and q:GetDismissReason()=='minimized' and confirms==1)
assert(not W.Root:GetAttribute('AroynModalBlocked') and W.Root:GetAttribute('AroynInputBlocked'))
Mock.advance(1);W:SetMinimized(false);Mock.advance(1);assert(toggle.Control.Interactable and not W.Overlays.ActiveDialog)
h=confirm();W.OwnRoot.Enabled=false;assert(h:GetDismissReason()=='hidden');W.OwnRoot.Enabled=true
h=confirm();P.Root.Visible=false;assert(h:GetDismissReason()=='page_changed');P.Root.Visible=true
pass('Modal lifecycle closes ColorPicker, preserves changed disabled states, cancels page/ScreenGui/minimize with reasons and never confirms implicitly')
local geometryToast={};for i=1,3 do geometryToast[i]=toast('Info') end
W.OwnRoot._p.absoluteOverride=V.new(280,190)
W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(0.3)
assert(#W.Overlays.Toasts==1 and #W.Overlays.ToastQueue==2)
local g=geometryToast[1];assert(g.Root.Position.X.Offset>=0 and g.Root.Position.X.Offset+g.Root.Size.X.Offset<=280)
assert(g.Root.Position.Y.Offset+g.Root.Size.Y.Offset<=190)
h=confirm();Mock.advance(0.2)
assert(h.Root.Position.X.Offset>=0 and h.Root.Position.Y.Offset>=0)
assert(h.Root.Position.X.Offset+h.Root.Size.X.Offset<=280 and h.Root.Position.Y.Offset+h.Root.Size.Y.Offset<=190)
for _,b in ipairs(h.Buttons) do assert(b.Position.Y.Offset>=0 and b.Position.Y.Offset+b.Size.Y.Offset<=h.Root.Size.Y.Offset) end
W.OwnRoot._p.absoluteOverride=V.new(1024,768);W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(0.3)
assert(#W.Overlays.Toasts==3 and geometryToast[2]:GetState()=='Visible')
h:Close();Mock.advance(0.2);for _,g2 in ipairs(geometryToast) do g2:Dismiss() end;Mock.advance(0.3)
pass('Viewport shrink requeues toast tail in order; mobile dialog actions stack, long text remains scrollable and pixel-aligned bounds restore')
local baseline=Mock.connections
for i=1,100 do
    local rapid=confirm();rapid.Buttons[2].Activated:Fire();rapid:Close();Mock.advance(0.21)
    local n=toast('Success',0.1);n:Dismiss();Mock.advance(0.4)
end
assert(Mock.connections==baseline,'overlay listeners grow: '..Mock.connections..' vs '..baseline)
local warnings=#Mock.warnings
local err=W:Dialog({Title='Callback errors',OnAcknowledge=function() error('Expected local test error') end})
err.Buttons[1].Activated:Fire();Mock.advance(0.2);assert(#Mock.warnings==warnings+1 and err:GetState()=='Closed')
for _,o in ipairs({{Title='Bad',Type='Invalid'},{Title='Bad',Duration=-1},{Title='Bad',Duration=0/0},{Title='Bad',Dismissible='yes'}}) do assert(not pcall(function() W:Notify(o) end)) end
for _,o in ipairs({{Title='Bad',Type='Invalid'},{Title='Bad',Type='Custom',Actions={}},{Title='Bad',Type='Custom',Actions={{Id='same',Text='A'},{Id='same',Text='B'}}},{Title='Bad',OutsideDismiss=true}}) do assert(not pcall(function() W:Dialog(o) end)) end
assert(Mock.connections==baseline)
pass('100 modal/toast interruptions, invalid options and callback errors clean tweens/timers/listeners without changing existing components')
local pending=toast('Warning',60);local destroy=W:Dialog({Type='Confirm',Title='Destroy',OnConfirm=function() W:Destroy() end})
local never=0;local after=W:Dialog({Type='Confirm',Title='Never confirm',OnConfirm=function() never+=1 end})
destroy.Buttons[2].Activated:Fire();Mock.advance(100)
assert(destroy:GetState()=='Closed' and after:GetDismissReason()=='destroyed' and never==0)
assert(not pending.Timer and pending:GetDismissReason()=='destroyed' and not W.Overlays.Portal.Parent and Mock.connections==0)
local fresh=newWindow('destroy-active');fresh:Notify({Title='Active timer',Duration=20})
local canceled=0;local active=fresh:Dialog({Type='Confirm',Title='Cancel at destroy',OnCancel=function(reason) assert(reason=='destroyed');canceled+=1 end})
fresh.OwnRoot:Destroy();Mock.advance(30);assert(canceled==1 and active:GetState()=='Closed' and Mock.connections==0)
Mock.asyncTweens=false
pass('Destruction with queued/active overlays and from explicit action callbacks removes portals, timers and listeners with no pending implicit confirmation')
end
