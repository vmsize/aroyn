do
assert(Mock.connections==0)
local E=libraryEnvironment;local U,V=E.UDim2,E.Vector2
local A=makeLibrary();local parent=Mock.Instance.new('PlayerGui')
local W=A:CreateWindow({Parent=parent,Id='overlay-polish',Size=U.fromOffset(680,440)})
local P=W:CreatePage({Name='General'});W:CreatePage({Name='Other'});Mock.advance(1);Mock.asyncTweens=true
local function notify(i) return W:Notify({Title='Notification '..i,Description='Screen-anchored',Duration=0}) end
local one=notify(1)
assert(one.Root.Position.X.Offset==700 and one.Root.Position.Y.Offset==768-20-86)
Mock.advance(0.21)
assert(one.Root.Position.X.Offset==692 and one.Root.Position.Y.Offset+one.Height==748)
local two,three=notify(2),notify(3);Mock.advance(0.21)
assert(one.Root.Position.Y.Offset+one.Height+8==two.Root.Position.Y.Offset)
assert(two.Root.Position.Y.Offset+two.Height+8==three.Root.Position.Y.Offset)
assert(three.Root.Position.Y.Offset+three.Height==748)
for _,h in ipairs({one,two,three}) do assert(h.Root.Position.X.Offset+h.Root.Size.X.Offset==1004) end
local four,five=notify(4),notify(5);assert(four.State=='Queued' and five.State=='Queued')
local stableX,stableY=three.Root.Position.X.Offset,three.Root.Position.Y.Offset
local tweenCount=#Mock.tweens
W.Root.Position=U.fromOffset(333,117);W.Root.Size=U.fromOffset(610,390)
assert(#Mock.tweens==tweenCount and three.Root.Position.X.Offset==stableX and three.Root.Position.Y.Offset==stableY)
W:SelectPage('Other',false);Mock.advance(0.4);assert(three.Root.Position.Y.Offset==stableY)
two:Dismiss();local last=Mock.tweens[#Mock.tweens]
local exit;for i=#Mock.tweens,1,-1 do if Mock.tweens[i].Object==two.Root then exit=Mock.tweens[i];break end end
assert(exit.Goals.Position.X.Offset==two.Root.Position.X.Offset+6 and exit.Goals.Position.Y.Offset==two.Root.Position.Y.Offset)
Mock.advance(0.4)
assert(two.State=='Dismissed' and four.State=='Visible' and five.State=='Queued')
assert(W.Overlays.Toasts[1]==one and W.Overlays.Toasts[2]==three and W.Overlays.Toasts[3]==four)
assert(four.Root.Position.Y.Offset+four.Height==748 and not W.Overlays.Portal.Active)
W:SetMinimized(true);Mock.advance(1);assert(#W.Overlays.Toasts==0 and #W.Overlays.ToastQueue==0)
W:SetMinimized(false);Mock.advance(1);W:SelectPage('General',false);Mock.advance(0.4)
pass('Bottom-right toast entrance/exit, newest at bottom, middle dismissal/FIFO and window drag/size/page independence preserve minimize cleanup')
local function rect(x,y,w,h) return {Min=V.new(x,y),Max=V.new(x+w,y+h)} end
W.OwnRoot._p.absoluteOverride=V.new(844,390)
W.OwnRoot.ScreenInsets=Mock.Enum.ScreenInsets.None
Mock.insetAreas={None=rect(-24,-58,844,390),CoreUISafeInsets=rect(0,0,800,312),DeviceSafeInsets=rect(0,-58,800,370)}
local n=notify(6);Mock.advance(0.21)
assert(n.Root.Position.X.Offset==492 and n.Root.Position.Y.Offset+n.Height==350)
local l,t,r,b=W.Overlays:_SafeBounds();assert(l==24 and t==58 and r==824 and b==370)
assert(n.Root.Position.Y.Offset>=t+20 and n.Root.Position.X.Offset+n.Root.Size.X.Offset==r-20)
W.OwnRoot.ScreenInsets=Mock.Enum.ScreenInsets.CoreUISafeInsets
W.OwnRoot._p.absoluteOverride=V.new(800,312);W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire();Mock.advance(0.3)
assert(n.Root.Position.X.Offset==468 and n.Root.Position.Y.Offset+n.Height==292)
Mock.insetAreas.CoreUISafeInsets=rect(0,0,800,292)
Mock.services.GuiService:GetPropertyChangedSignal('TopbarInset'):Fire();Mock.advance(0.3)
assert(n.Root.Position.Y.Offset+n.Height==272)
n:Dismiss();Mock.advance(0.3)
Mock.insetAreas=nil;W.OwnRoot.ScreenInsets=nil;W.OwnRoot._p.absoluteOverride=V.new(1024,768)
W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire()
pass('Safe-area rectangles convert host inset coordinates once; notch/topbar/bottom edges and screen inset changes keep toasts inside mobile bounds')
local ack,confirmed,cancelled=0,0,0
local alert=W:Dialog({Title='Local example',Description='This dialog only demonstrates acknowledgment.',OnAcknowledge=function() ack+=1 end})
assert(alert.Root.Visible and alert.Root.Size.Y.Offset<160 and alert.Root.Size.X.Offset<=440)
local shortHeight=alert.Height
local contentBottom=alert.Scroll.Position.Y.Offset+alert.Scroll.Size.Y.Offset
assert(alert.Buttons[1].Position.Y.Offset-contentBottom==16)
assert(alert.Height-alert.Buttons[1].Position.Y.Offset-alert.Buttons[1].Size.Y.Offset==16)
assert(alert.Root.Position.Y.Offset==alert.Target.Y.Offset+6 and alert.Root.BackgroundTransparency==1)
Mock.advance(0.2);assert(alert.Root.Position.Y.Offset==math.floor((768-alert.Height)/2) and alert.Blocker.BackgroundTransparency==0.65)
alert.Buttons[1].Activated:Fire();Mock.advance(0.2);assert(ack==1)
local confirm=W:Dialog({Type='Confirm',Title='Confirm local example?',Description='No configuration or game data will be changed.',
    OnConfirm=function() confirmed+=1 end,OnCancel=function() cancelled+=1 end})
assert(confirm.Height<170 and confirm.Scroll.Size.Y.Offset==confirm.DescriptionFullHeight)
confirm.Buttons[2].Activated:Fire();confirm.Buttons[2].Activated:Fire();Mock.advance(0.2);assert(confirmed==1 and cancelled==0)
local tiny=W:Dialog({Title='OK'})
assert(tiny.Width==280 and tiny.Height<shortHeight and not tiny.Scroll.Visible)
tiny:Close();Mock.advance(0.2)
pass('Measured short Alert/Confirm and title-only dialogs are compact, centered before opening, preserve padding/dimming and execute callbacks once')
local multiline=W:Dialog({Title='Multiple lines',Description='First line\nSecond line\nThird line\nFourth line'})
assert(multiline.Height>shortHeight and multiline.Scroll.Size.Y.Offset==multiline.DescriptionFullHeight)
multiline:Close();Mock.advance(0.2)
local long=W:Dialog({Title='Long description',Description=string.rep('A long line for wrapping and scrolling.\n',80)})
assert(long.Height==560 and long.DescriptionFullHeight>long.Scroll.Size.Y.Offset)
assert(long.Scroll.AutomaticCanvasSize==Mock.Enum.AutomaticSize.Y and long.Scroll.ScrollingEnabled)
assert(long.Buttons[1].Position.Y.Offset+30<=long.Height-16)
local beforeMeasure=Mock.measureCalls
W.Overlays:_Layout();Mock.advance(0.2);assert(Mock.measureCalls==beforeMeasure)
long:Close();Mock.advance(0.2)
local custom=W:Dialog({Type='Custom',Title='Choose',Description='Three actions',Actions={{Id='a',Text='One'},{Id='b',Text='Two'},{Id='c',Text='Three'}}})
assert(custom.Buttons[1].Position.Y.Offset<custom.Buttons[2].Position.Y.Offset and custom.Height<260)
custom:Close();Mock.advance(0.2)
pass('Multiline content grows naturally, long descriptions cap at 560px and scroll, three actions fit and repeated layout reuses FontFace measurements')
for _,viewport in ipairs({V.new(390,844),V.new(844,390),V.new(280,190),V.new(600,240)}) do
    W.OwnRoot._p.absoluteOverride=viewport;W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire()
    local h=W:Dialog({Type='Custom',Title='Mobile decision',Description=string.rep('Readable long mobile text. ',60),
        Actions={{Id='a',Text='One'},{Id='b',Text='Two'},{Id='c',Text='Three'}}})
    assert(h.Root.Position.X.Offset>=0 and h.Root.Position.Y.Offset>=0)
    assert(h.Root.Position.X.Offset+h.Width<=viewport.X and h.Target.Y.Offset+h.Height<=viewport.Y)
    for _,button in ipairs(h.Buttons) do
        assert(button.Size.X.Offset>=64 and button.Size.Y.Offset==30)
        assert(button.Position.Y.Offset>=h.Scroll.Position.Y.Offset+h.Scroll.Size.Y.Offset+16)
        assert(button.Position.Y.Offset+30<=h.Height-16)
    end
    assert(h.Title.Size.Y.Offset>=14 and h.Scroll.Size.Y.Offset>=13)
    h:Close();Mock.advance(0.2)
end
W.OwnRoot._p.absoluteOverride=V.new(1024,768);W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire()
pass('Adaptive dialogs at four portrait/landscape resolutions preserve readable content, horizontal fallback and accessible action/footer geometry')
Mock.measureDelay=0.05
local delayed
E.task.spawn(function() delayed=W:Dialog({Title='Measured before display',Description='Pending layout'}) end)
Mock.advance(0)
local pending=W.Overlays.ActiveDialog
assert(pending.LayoutBusy and not pending.Root.Visible)
W.OwnRoot._p.absoluteOverride=V.new(390,844);W.Overlays.Portal:GetPropertyChangedSignal('AbsoluteSize'):Fire()
Mock.advance(1)
assert(delayed==pending and delayed.Root.Visible and delayed.Width<=366 and delayed.Target.Y.Offset==math.floor((844-delayed.Height)/2))
delayed:Close();Mock.advance(0.2)
local reason
E.task.spawn(function() W:Dialog({Title='Destroy while measuring',OnCancel=function(r) reason=r end}) end)
Mock.advance(0);assert(W.Overlays.ActiveDialog.LayoutBusy)
W:Destroy();Mock.advance(1);assert(reason=='destroyed' and Mock.connections==0)
Mock.measureDelay=nil
pass('Delayed FontFace measurement keeps panel hidden, recalculates latest viewport before opening and safely ignores results after destruction')
local fresh=A:CreateWindow({Parent=parent,Id='fallback-measure'});fresh:CreatePage({Name='General'});Mock.advance(1)
Mock.measureError=true
local fallback=fresh:Dialog({Title='Legacy measurement',Description='Fallback example'})
assert(fallback.MeasurementFallback and fallback.Root.Visible and fallback.Height<160)
fallback:Close();Mock.advance(0.2);Mock.measureError=nil
local baseline=Mock.connections
for i=1,30 do local h=fresh:Dialog({Title='Rapid '..i,Description=i%2==0 and 'Short' or string.rep('Long ',80)});h:Close();Mock.advance(0.2) end
assert(Mock.connections==baseline)
fresh:Destroy();Mock.advance(1);assert(Mock.connections==0);Mock.asyncTweens=false
pass('Legacy text measurement fallback and 30 varied-size rapid open/close cycles preserve cleanup and native unscaled rendering')
end
