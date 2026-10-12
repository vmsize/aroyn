-- Purpose-built test doubles. Does not simulate native rendering or OS input.
local Mock={tweens={},warnings={},connections=0,instances={},files={},folders={},now=0,jobs={},serial=0}
local function copy(t) if type(t)~="table" or t.__type then return t end; local r={}; for k,v in pairs(t) do r[k]=copy(v) end; return r end
local function signal()
    local s={listeners={}}
    function s:Connect(fn)
        local c={Connected=true}; self.listeners[c]=fn; Mock.connections+=1
        function c:Disconnect() if self.Connected then self.Connected=false; s.listeners[self]=nil; Mock.connections-=1 end end
        return c
    end
    function s:Fire(...)
        local snapshot={}; for c,f in pairs(self.listeners) do table.insert(snapshot,{c,f}) end
        for _,p in ipairs(snapshot) do if p[1].Connected then p[2](...) end end
    end
    return s
end
Mock.signal=signal
local function schedule(thread,due)
    Mock.serial+=1; table.insert(Mock.jobs,{thread=thread,due=due,order=Mock.serial}); return thread
end
local task={}
function task.spawn(fn,...) local args={...}; return schedule(coroutine.create(function() fn(table.unpack(args)) end),Mock.now) end
function task.defer(fn) return schedule(coroutine.create(fn),Mock.now) end
function task.delay(delay,fn) return schedule(coroutine.create(fn),Mock.now+delay) end
function task.wait(delay) return coroutine.yield(delay or 0) end
function task.cancel(thread)
    for i=#Mock.jobs,1,-1 do if Mock.jobs[i].thread==thread then table.remove(Mock.jobs,i) end end
    if coroutine.status(thread)~="dead" then coroutine.close(thread) end
end
function Mock.advance(dt)
    local untilTime=Mock.now+(dt or 0); local count=0
    while true do
        table.sort(Mock.jobs,function(a,b) return a.due==b.due and a.order<b.order or a.due<b.due end)
        local job=Mock.jobs[1]; if not job or job.due>untilTime then break end
        table.remove(Mock.jobs,1); Mock.now=job.due; count+=1; assert(count<10000,"Scheduler runaway")
        local ok,delay=coroutine.resume(job.thread); assert(ok,delay)
        if coroutine.status(job.thread)~="dead" then schedule(job.thread,Mock.now+(delay or 0)) end
    end
    Mock.now=untilTime
end
local Vector2={zero={X=0,Y=0}}; local vecMt={}
function Vector2.new(x,y) return setmetatable({X=x or 0,Y=y or 0,__type="Vector2"},vecMt) end
function vecMt.__add(a,b) return Vector2.new(a.X+b.X,a.Y+b.Y) end
function vecMt.__sub(a,b) return Vector2.new(a.X-b.X,a.Y-b.Y) end
local UDim={new=function(s,o) return {Scale=s or 0,Offset=o or 0,__type="UDim"} end}
local UDim2={}
function UDim2.new(a,b,c,d) return {X=UDim.new(a,b),Y=UDim.new(c,d),__type="UDim2"} end
function UDim2.fromOffset(x,y) return UDim2.new(0,x,0,y) end
function UDim2.fromScale(x,y) return UDim2.new(x,0,y,0) end
local Enum=setmetatable({},{__index=function(self,key)
    local group={}
    setmetatable(group,{__index=function(t,name)
        if key=="KeyCode" and not table.find({"F","G","LeftShift","ButtonA","End","Unknown","RightShift","Escape","Backspace","Delete","H","J","K","A","B","C","Space"},name) then error("Invalid KeyCode") end
        local item={Name=name,EnumType=group,__type="EnumItem"}; rawset(t,name,item); return item
    end}); rawset(self,key,group); return group
end})
local Color3={}; local colorMt={__index=Color3}
function Color3.new(r,g,b) return setmetatable({R=r,G=g,B=b,__type="Color3"},colorMt) end
function Color3.fromRGB(r,g,b) return Color3.new(r/255,g/255,b/255) end
function Color3.fromHSV(h,s,v)
    h=h%1; local i=math.floor(h*6); local f=h*6-i; local p=v*(1-s); local q=v*(1-f*s); local t=v*(1-(1-f)*s)
    local rgb=({{v,t,p},{q,v,p},{p,v,t},{p,q,v},{t,p,v},{v,p,q}})[i+1]; return Color3.new(table.unpack(rgb))
end
function Color3:ToHSV()
    local high=math.max(self.R,self.G,self.B); local low=math.min(self.R,self.G,self.B); local d=high-low; local h=0
    if d~=0 then if high==self.R then h=((self.G-self.B)/d)%6 elseif high==self.G then h=(self.B-self.R)/d+2 else h=(self.R-self.G)/d+4 end; h/=6 end
    return h,high==0 and 0 or d/high,high
end
local methods={}; local instMt={}; local Instance={}
local guiClasses={CanvasGroup=true,Frame=true,TextLabel=true,TextButton=true,TextBox=true,ScrollingFrame=true,ImageLabel=true}
local events={DescendantAdded=true,MouseButton1Click=true,MouseButton1Down=true,MouseButton1Up=true,InputChanged=true,Activated=true,MouseEnter=true,MouseLeave=true,InputBegan=true,InputEnded=true,Focused=true,FocusLost=true,AncestryChanged=true,Destroying=true}
local input
function Instance.new(class)
    local x=setmetatable({_p={ClassName=class,Name=class,Visible=true,Text="",Position=UDim2.new(),Size=UDim2.new(),AnchorPoint=Vector2.new(),Scale=1,Interactable=true,TextEditable=true,ScrollingEnabled=true,GroupTransparency=0,ZIndex=1,TextSize=14,BackgroundTransparency=0,ImageTransparency=0,Rotation=0,CanvasPosition=Vector2.new()},_children={},_events={},_properties={},__type="Instance"},instMt)
    table.insert(Mock.instances,x); return x
end
function methods:IsA(class) return self.ClassName==class or class=="Instance" or (class=="GuiObject" and guiClasses[self.ClassName]==true) end
function methods:GetAttributeChangedSignal(name) return self:GetPropertyChangedSignal("attr_"..name) end
function methods:SetAttribute(name,value)
    local key="attr_"..name;local old=self._p[key];self._p[key]=value
    if old~=value and self._properties[key] then self._properties[key]:Fire() end
end
function methods:GetAttribute(name) return self._p["attr_"..name] end
function methods:FindFirstChild(name,recursive)
    for _,child in ipairs(recursive and self:GetDescendants() or self._children) do if child.Name==name then return child end end
end
function methods:GetChildren() return table.clone(self._children) end
function methods:GetDescendants()
    local out={}; for _,c in ipairs(self._children) do table.insert(out,c); for _,d in ipairs(c:GetDescendants()) do table.insert(out,d) end end; return out
end
function methods:IsDescendantOf(parent) local p=self.Parent; while p do if p==parent then return true end; p=p.Parent end; return false end
function methods:FindFirstChildOfClass(class) for _,c in ipairs(self._children) do if c.ClassName==class then return c end end end
function methods:WaitForChild(name) for _,c in ipairs(self._children) do if c.Name==name then return c end end end
function methods:GetPropertyChangedSignal(prop) if not self._properties[prop] then self._properties[prop]=signal() end; return self._properties[prop] end
function methods:IsFocused() return input.focused==self end
function methods:CaptureFocus() input.focused=self; input.TextBoxFocused:Fire(self); self.Focused:Fire() end
function methods:ReleaseFocus(enter) if input.focused==self then input.focused=nil; self.FocusLost:Fire(enter or false) end end
function methods:Destroy()
    if self._p.dead then return end
    self._p.dead=true; self.Destroying:Fire()
    for _,c in ipairs(table.clone(self._children)) do c:Destroy() end
    self.Parent=nil
    for _,s in pairs(self._events) do for c in pairs(s.listeners) do c:Disconnect() end end
    for _,s in pairs(self._properties) do for c in pairs(s.listeners) do c:Disconnect() end end
end
local function effectiveScale(x)
    local n=1; local p=x
    while p do for _,c in ipairs(p._children) do if c.ClassName=="UIScale" then n*=c.Scale end end; p=p.Parent end
    return n
end
function instMt.__index(x,k)
    if methods[k] then return methods[k] end
    if events[k] then if not x._events[k] then x._events[k]=signal() end; return x._events[k] end
    if k=="AbsoluteCanvasSize" then return Vector2.new(x.CanvasSize and x.CanvasSize.X.Offset or 0, x.CanvasSize and x.CanvasSize.Y.Offset or 0) end
    if k=="AbsoluteContentSize" then return Vector2.new(0,300) end
    if k=="AbsoluteSize" then
        if x._p.absoluteOverride then return x._p.absoluteOverride end
        if x.ClassName=="ScreenGui" or not x.Parent then return Vector2.new(1024,768) end
        local p=x.Parent.AbsoluteSize; local sc=effectiveScale(x); return Vector2.new(p.X*x.Size.X.Scale+x.Size.X.Offset*sc,p.Y*x.Size.Y.Scale+x.Size.Y.Offset*sc)
    end
    if k=="AbsolutePosition" then
        if not x.Parent or x.ClassName=="ScreenGui" then return Vector2.new() end
        local canvas=x.Parent:IsA("ScrollingFrame") and x.Parent.CanvasPosition or Vector2.new(); local pos=x.Parent.AbsolutePosition-canvas; local size=x.Parent.AbsoluteSize; local own=x.AbsoluteSize; local sc=effectiveScale(x)
        return Vector2.new(pos.X+size.X*x.Position.X.Scale+x.Position.X.Offset*sc-own.X*x.AnchorPoint.X,pos.Y+size.Y*x.Position.Y.Scale+x.Position.Y.Offset*sc-own.Y*x.AnchorPoint.Y)
    end
    return x._p[k]
end
function instMt.__newindex(x,k,v)
    local old=x._p[k]
    if k=="Parent" then
        if old then local i=table.find(old._children,x); if i then table.remove(old._children,i) end end
        if v then table.insert(v._children,x) end
    end
    x._p[k]=v
    if old~=v then
        if x._properties[k] then x._properties[k]:Fire() end
        if k=="Parent" and v then
            local ancestor=v
            while ancestor do
                if ancestor._events.DescendantAdded then ancestor._events.DescendantAdded:Fire(x) end
                ancestor=ancestor.Parent
            end
        end
        if k=="Position" or k=="Size" or k=="CanvasPosition" then
            local descendants=x:GetDescendants()
            for _,node in ipairs(descendants) do
                for _,prop in ipairs({"AbsolutePosition","AbsoluteSize"}) do
                    if node._properties[prop] then node._properties[prop]:Fire() end
                end
            end
        end
        if k=="Parent" and x._events.AncestryChanged then x.AncestryChanged:Fire(x,v) end
    end
end
input={KeyboardEnabled=true,TouchEnabled=false,MouseEnabled=true,OnScreenKeyboardVisible=false,OnScreenKeyboardPosition=Vector2.new(0,500),_properties={}}
for _,name in ipairs({"InputBegan","InputEnded","InputChanged","WindowFocused","WindowFocusReleased","TextBoxFocused"}) do input[name]=signal() end
function input:GetFocusedTextBox() return self.focused end
function input:GetPropertyChangedSignal(prop) if not self._properties[prop] then self._properties[prop]=signal() end; return self._properties[prop] end
local text={}; function text:GetTextSize(value,size,_,bounds) return Vector2.new(math.min(#value*size*.53,bounds.X),math.ceil(math.max(1,#value*size*.53/bounds.X))*size) end
Mock.measureCalls=0
function text:GetTextBoundsAsync(params)
    Mock.measureCalls+=1
    assert(params.Font.Family and params.Font.Weight and params.Width>0)
    if Mock.measureDelay then task.wait(Mock.measureDelay) end
    if Mock.measureError then error("Expected FontFace measurement failure") end
    local width,height=0,0
    local glyph=params.Size*.53
    local lineHeight=math.ceil(params.Size*1.2)
    for line in (params.Text.."\n"):gmatch("([^\n]*)\n") do
        local natural=(utf8.len(line) or #line)*glyph
        width=math.max(width,math.min(natural,params.Width))
        height+=math.max(1,math.ceil(natural/params.Width))*lineHeight
    end
    return Vector2.new(width,height)
end
local tween={}
function tween:Create(x,info,props)
    local tw={Completed=signal(),Object=x,Goals=props,Info=info};table.insert(Mock.tweens,tw)
    function tw:Play()
        local function finish()
            self.job=nil
            for k,v in pairs(props) do x[k]=v end
            self.Completed:Fire(Enum.PlaybackState.Completed)
        end
        if Mock.asyncTweens then self.job=task.delay(info[1],finish) else finish() end
    end
    function tw:Cancel()
        if self.job then task.cancel(self.job);self.job=nil end
        self.Completed:Fire(Enum.PlaybackState.Cancelled)
    end
    return tw
end
local http={saved={},next=0}; function http:GenerateGUID() return "lab-mock-guid" end
function http:JSONEncode(value) self.next+=1; local s="MOCK_JSON_"..self.next; self.saved[s]=copy(value); return s end
function http:JSONDecode(s) assert(self.saved[s],"Malformed JSON (mock boundary)"); return copy(self.saved[s]) end
local gui={GetGuiInset=function() return Vector2.new(),Vector2.new() end};
function gui:GetPropertyChangedSignal(prop)
    self._signals=self._signals or {};self._signals[prop]=self._signals[prop] or signal();return self._signals[prop]
end
function gui:GetInsetArea(kind)
    if Mock.insetAreas then return assert(Mock.insetAreas[kind.Name]) end
    error("No simulated inset areas")
end
 local core=Instance.new("CoreGui"); local player=Instance.new("Player"); local playerGui=Instance.new("PlayerGui"); playerGui.Parent=player
local services={UserInputService=input,TweenService=tween,TextService=text,HttpService=http,Players={LocalPlayer=player},GuiService=gui,CoreGui=core}
services.RunService={RenderStepped=signal(),Heartbeat=signal()}
services.ReplicatedStorage=Instance.new("ReplicatedStorage")
player.UserId=123;player.Name="LocalPreview";player.DisplayName="Local Preview"
Mock.services=services; Mock.input=input; Mock.Instance=Instance; Mock.Enum=Enum
local environment={game={GetService=function(_,name) assert(services[name],"Unknown service"); return services[name] end},
    task=task,Vector2=Vector2,UDim=UDim,UDim2=UDim2,Enum=Enum,Color3=Color3,Instance=Instance,TweenInfo={new=function(...) return {...} end},
    NumberSequence={new=function(values) return {Keypoints=values,__type="NumberSequence"} end},
    NumberSequenceKeypoint={new=function(time,value) return {Time=time,Value=value} end},
    ColorSequence={new=function(values) return {Keypoints=values,__type="ColorSequence"} end},
    ColorSequenceKeypoint={new=function(time,value) return {Time=time,Value=value} end},
    typeof=function(x) return type(x)=="table" and x.__type or type(x) end,
    warn=function(...) table.insert(Mock.warnings,table.concat({...}," ")) end,
    Font={new=function(family,weight,style) return {Family=family,Weight=weight,Style=style} end},
    workspace={CurrentCamera={ViewportSize=Vector2.new(1440,900),GetPropertyChangedSignal=function() return signal() end},FindFirstChild=function() return nil end},
    shared={}, getgenv=function() return Mock.shared end,
}
Mock.shared={}; environment.shared=Mock.shared
function Mock.install(fn,disk)
    local env=setmetatable(table.clone(environment),{__index=getfenv()})
    if disk then
        env.writefile=function(p,v) Mock.files[p]=v end
        env.readfile=function(p) assert(Mock.files[p],"No such file"); return Mock.files[p] end
        env.delfile=function(p) assert(Mock.files[p],"No such file"); Mock.files[p]=nil end
        env.makefolder=function(p) Mock.folders[p]=true end
        env.isfolder=function(p) return Mock.folders[p]==true end
    end
    setfenv(fn,env); return fn,env
end
function Mock.buttons(root,text)
    local list={}; for _,x in ipairs(root:GetDescendants()) do if x:IsA("TextButton") and (text==nil or x.Text==text) then table.insert(list,x) end end; return list
end
function Mock.key(key) return {KeyCode=Enum.KeyCode[key],UserInputType=Enum.UserInputType.Keyboard,Position={X=0,Y=0}} end
return Mock
