--[[
MIT License

Copyright (c) 2026 vmsize

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

# Aroyn brand notice

To the extent of the rights held by the project maintainer, permission is granted to copy and redistribute the unchanged supplied mark as part of this source package, including repository forks, with this notice retained. It may also be displayed to truthfully identify Aroyn in reviews, videos, documentation and links to the project. Resizing without otherwise altering its design is permitted.

This permission does not grant use of the mark as the brand of a separate product, permission to present a third-party project as an official Aroyn release or endorsed service, permission to adapt the mark into another brand, or permission to sell merchandise bearing it. Those uses require separate agreement with the maintainer. Source-code reuse remains governed by MIT; a separately presented product should use its own branding. The supplied mark and project names are excluded from the code's MIT license.

The owner reports that the reference was generated with ChatGPT; the original generation chat is unavailable. The supplied source file and Library links are retained privately as provenance evidence. The authorization above records the owner's permission; it does not establish independent clearance of third-party rights or registration of a trademark.

]]
-- Aroyn UI standalone approved stable artifact.
-- Loading returns the approved API; it does not create windows or input listeners.
local Aroyn=(function()
-- Aroyn UI, Phase 4A. Local module: opt-in executor files; no game automation or network.
local Aroyn = {}
local TweenService = game:GetService("TweenService")
local InputService = game:GetService("UserInputService")

Aroyn.Theme = {
    Colors = {
        Window=Color3.fromRGB(17,17,18), Header=Color3.fromRGB(23,23,25),
        Surface=Color3.fromRGB(23,23,25), Surface2=Color3.fromRGB(29,29,31),
        Surface3=Color3.fromRGB(37,37,39), Hover=Color3.fromRGB(37,37,39),
        Pressed=Color3.fromRGB(45,45,47), Selected=Color3.fromRGB(32,32,34),
        BorderSoft=Color3.fromRGB(49,49,51), Text=Color3.fromRGB(242,242,240),
        TextMuted=Color3.fromRGB(181,181,176), TextDim=Color3.fromRGB(151,151,146),
        Accent=Color3.fromRGB(222,222,218), AccentBright=Color3.fromRGB(242,242,240),
        AccentDark=Color3.fromRGB(68,68,65), AccentSoft=Color3.fromRGB(131,131,127),
    },
    Fonts = {
        Regular=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Regular,Enum.FontStyle.Normal),
        Medium=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.Medium,Enum.FontStyle.Normal),
        Semibold=Font.new("rbxasset://fonts/families/BuilderSans.json",Enum.FontWeight.SemiBold,Enum.FontStyle.Normal),
        Page=22, Section=14, Label=14, Description=13, Small=12, Brand=15,
    },
    Metrics={Radius=4, WindowRadius=7, Gap=8, Row=40, DescriptionRow=60,
        Control=30, ToggleWidth=44, TrackWidth=38, TrackHeight=22, Thumb=14,
        FieldWidth=224, ButtonWidth=144, Rail=64, Header=52, Icon=24, ThumbInset=4},
    Animation={Hover=0.10, Value=0.14},
    Borders={Thickness=1, Normal=0.45, Focus=0.10, Disabled=0.65},
}

local function options(value)
    assert(value==nil or type(value)=="table", "Aroyn: options must be a table")
    return value or {}
end
local function bool(value, name)
    assert(type(value)=="boolean", "Aroyn: "..name.." must be boolean")
    return value
end
local function name(value)
    assert(type(value)=="string" and value:match("%S"), "Aroyn: Name must be a nonempty string")
    return value
end
local function callback(value)
    assert(value==nil or type(value)=="function", "Aroyn: Callback must be a function")
    return value
end
local function remove(list, value)
    local index=table.find(list,value)
    if index then table.remove(list,index) end
end
local function create(class, props, parent)
    local object=Instance.new(class)
    for key,value in pairs(props) do object[key]=value end
    if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
        object.TextScaled=false;object.TextStrokeTransparency=1
        object.FontFace=props.FontFace or Aroyn.Theme.Fonts.Medium
    end
    object.Parent=parent
    return object
end
local function rounded(object, radius)
    create("UICorner",{CornerRadius=UDim.new(0,radius or Aroyn.Theme.Metrics.Radius)},object)
end
local function outline(object)
    return create("UIStroke",{Color=Aroyn.Theme.Colors.BorderSoft,
        Thickness=Aroyn.Theme.Borders.Thickness,Transparency=Aroyn.Theme.Borders.Normal,
        ApplyStrokeMode=Enum.ApplyStrokeMode.Border},object)
end
local function text(parent, content, size, face, color)
    return create("TextLabel",{BackgroundTransparency=1,BorderSizePixel=0,Text=content,
        TextSize=size,FontFace=face,TextColor3=color,TextXAlignment=Enum.TextXAlignment.Left,
        TextTruncate=Enum.TextTruncate.AtEnd,ZIndex=2},parent)
end

local Scope={};Scope.__index=Scope
function Scope.new() return setmetatable({Alive=true,Connections={},Animations={}},Scope) end
function Scope:Connect(signal, fn)
    local connection=signal:Connect(function(...) if self.Alive then fn(...) end end)
    self.Connections[connection]=true
    return connection
end
function Scope:Cancel(object)
    local previous=self.Animations[object]
    if previous then self.Animations[object]=nil;previous:Cancel() end
end
function Scope:Animate(object, properties, duration, finished, easing)
    if not self.Alive then return end
    self:Cancel(object)
    local animation=TweenService:Create(object,TweenInfo.new(duration or Aroyn.Theme.Animation.Hover,
        easing or Enum.EasingStyle.Quad,Enum.EasingDirection.Out),properties)
    self.Animations[object]=animation
    local done
    done=self:Connect(animation.Completed,function(playback)
        done:Disconnect();self.Connections[done]=nil
        if self.Animations[object]==animation then
            self.Animations[object]=nil
            if finished and playback==Enum.PlaybackState.Completed then finished() end
        end
    end)
    animation:Play()
end
function Scope:Destroy()
    if not self.Alive then return end
    self.Alive=false
    for connection in pairs(self.Connections) do connection:Disconnect() end
    table.clear(self.Connections)
    for _,animation in pairs(self.Animations) do animation:Cancel() end
    table.clear(self.Animations)
end
local function invoke(component, ...)
    if not component.Scope.Alive or not component.Callback then return end
    local ok,err=pcall(component.Callback,...)
    if not ok then warn("Aroyn callback ("..component.Name.."): "..tostring(err)) end
end

-- Internal motion helpers. Native Frame rendering; no offscreen compositing.
-- Embedded into Aroyn.luau by the local builder.
function Aroyn:_Surface(parent, props)
    local object = Instance.new("Frame")
    for key, value in pairs(props) do object[key] = value end
    object.BackgroundTransparency = 1; object.BorderSizePixel = 0; object.Active = false
    object.ClipsDescendants = true
    object:SetAttribute("AroynMotionEnabled",self.MotionEnabled ~= false)
    object.Parent = parent
    return object
end

local function shifted(position, y)
    return UDim2.new(position.X.Scale,position.X.Offset,position.Y.Scale,position.Y.Offset+y)
end
local function blocked(object)
    local current=object
    while current do
        if current:GetAttribute("AroynInputBlocked") then return true end
        current=current.Parent
    end
    return false
end
-- Interactable on a parent does NOT disable descendant buttons in Roblox.
-- Snapshot interactive properties once per boundary; never tween descendants.
local Gate={};Gate.__index=Gate
local inputLocks=setmetatable({},{__mode="k"})
function Aroyn:_DesiredValue(object,key)
    local record=inputLocks[object]
    if record and record.Properties[key]~=nil then return record.Properties[key] end
    return object[key]
end
function Aroyn:_DesiredProperty(object,key,value)
    local record=inputLocks[object]
    if record and record.Properties[key]~=nil then
        record.Properties[key]=value;object[key]=false
    else object[key]=value end
end
function Gate.new(root) return setmetatable({Root=root,Saved={}},Gate) end
function Gate:Set(value)
    if self.Locked==value then return end
    self.Locked=value;self.Root:SetAttribute("AroynInputBlocked",value)
    if value then
        for _,object in ipairs(self.Root:GetDescendants()) do
            local properties={}
            if object:IsA("TextButton") or object:IsA("ImageButton") then
                properties.Interactable=object.Interactable;object.Interactable=false
            elseif object:IsA("TextBox") then
                properties.TextEditable=object.TextEditable;object.TextEditable=false
            elseif object:IsA("ScrollingFrame") then
                properties.ScrollingEnabled=object.ScrollingEnabled;object.ScrollingEnabled=false
            end
            if next(properties) then
                local record=inputLocks[object]
                if not record then record={Count=0,Properties=properties};inputLocks[object]=record end
                record.Count+=1;self.Saved[object]=true
            end
        end
    else
        for object in pairs(self.Saved) do
            local record=inputLocks[object]
            if record then
                record.Count-=1
                if record.Count==0 then
                    inputLocks[object]=nil
                    if object.Parent then
                        for key,value in pairs(record.Properties) do
                            local disabled=object:GetAttribute("AroynDisabled")
                            if disabled~=nil and key~="ScrollingEnabled" then value=not disabled end
                            object[key]=value==true
                        end
                    end
                end
            end
        end
        table.clear(self.Saved)
    end
end

local PageMotion={};PageMotion.__index=PageMotion
function Aroyn:_PageMotion(surface)
    local motion=setmetatable({Surface=surface,Scope=Scope.new(),Gate=Gate.new(surface),Ticket=0,
        Origin=surface.Position,Supported=surface:GetAttribute("AroynMotionEnabled")==true},PageMotion)
    motion.Scope:Connect(surface.Destroying,function() motion:Destroy() end)
    return motion
end
function PageMotion:Select(key, apply, instant)
    self.Ticket+=1;local ticket=self.Ticket
    self.Scope:Cancel(self.Surface)
    self.Pending=apply;self.Requested=key
    local function show()
        if not self.Scope.Alive or ticket~=self.Ticket then return end
        self.Current=key;self.Pending=nil;apply()
        self.Surface.Position=shifted(self.Origin,7)
        self.Scope:Animate(self.Surface,{Position=self.Origin},0.13,function()
            if ticket==self.Ticket then
                self.Surface.Position=self.Origin
                self.Busy=false;self.Gate:Set(false)
            end
        end)
    end
    if instant or not self.Supported or self.Hidden or not self.Current then
        self.Current=key;self.Pending=nil;self.Busy=false;apply()
        self.Surface.Position=self.Origin
        self.Gate:Set(self.Hidden==true)
    else
        self.Busy=true;self.Gate:Set(true)
        if self.Current==key then show()
        else self.Scope:Animate(self.Surface,{Position=shifted(self.Origin,-2)},0.065,show) end
    end
end
function PageMotion:SetHidden(value)
    self.Ticket+=1;self.Scope:Cancel(self.Surface)
    self.Hidden=value;self.Busy=false
    if self.Pending then local apply=self.Pending;self.Pending=nil;self.Current=self.Requested;apply() end
    self.Surface.Position=self.Origin
    self.Gate:Set(value)
end
function PageMotion:Destroy()
    self.Ticket+=1;self.Scope:Destroy();self.Gate:Set(false)
end

local Collapse={};Collapse.__index=Collapse
function Aroyn:_Collapse(root, chrome, headerHeight, decorate, launcher, options)
    options=options or {}
    local motion=setmetatable({Root=root,Chrome=chrome,HeaderHeight=headerHeight,Decorate=decorate,
        Launcher=launcher,Options=options,Scope=Scope.new(),Gate=Gate.new(root),Ticket=0,Timers={},
        Supported=chrome:GetAttribute("AroynMotionEnabled")==true},Collapse)
    motion.Scope:Connect(root.Destroying,function() motion:Destroy() end)
    launcher.Visible=false;launcher.Interactable=false
    local function pointer(input)
        return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch
    end
    motion.Scope:Connect(launcher.InputBegan,function(input)
        if motion.Drag or not pointer(input) or motion.Busy or not motion.Minimized or not launcher.Visible then return end
        motion.Scope:Cancel(launcher)
        motion.Drag={Input=input,Start=input.Position,Position=motion.FloatingPosition,Moved=false}
    end)
    motion.Scope:Connect(InputService.InputChanged,function(input)
        local drag=motion.Drag
        if not drag or not (input==drag.Input or (drag.Input.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseMovement)) then return end
        local delta=input.Position-drag.Start
        if delta.X*delta.X+delta.Y*delta.Y>=49 then drag.Moved=true end
        if drag.Moved then motion:PlaceFloating(drag.Position.X+delta.X,drag.Position.Y+delta.Y) end
    end)
    motion.Scope:Connect(InputService.InputEnded,function(input)
        local drag=motion.Drag
        if not drag or not (input==drag.Input or (drag.Input.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseButton1)) then return end
        motion.Drag=nil
        if not drag.Moved and motion.Minimized and launcher.Visible and not motion.Busy then
            local p,s=launcher.AbsolutePosition,launcher.AbsoluteSize
            if input.Position.X>=p.X and input.Position.X<=p.X+s.X and input.Position.Y>=p.Y and input.Position.Y<=p.Y+s.Y then
                if options.Restore then options.Restore() else motion:Set(false) end
            end
        end
    end)
    -- Mouse/touch restoration is owned by InputEnded; Activated must not restore after a drag.
    motion.Scope:Connect(launcher.Activated,function(input)
        if input and not pointer(input) and launcher.Visible and motion.Minimized and not motion.Busy then
            if options.Restore then options.Restore() else motion:Set(false) end
        end
    end)
    motion.Scope:Connect(InputService.WindowFocusReleased,function() motion.Drag=nil end)
    motion.Scope:Connect(launcher.Parent:GetPropertyChangedSignal("AbsoluteSize"),function()
        motion:ClampFloating()
        if motion.Busy then motion:Set(motion.Minimized,true) end
    end)
    return motion
end
function Collapse:PlaceFloating(x,y)
    local bounds=self.Options.Bounds and self.Options.Bounds() or self.Launcher.Parent.AbsoluteSize
    local size=self.Launcher.Size
    x=math.floor(math.clamp(x,0,math.max(0,bounds.X-size.X.Offset))+0.5)
    y=math.floor(math.clamp(y,0,math.max(0,bounds.Y-size.Y.Offset))+0.5)
    self.FloatingPosition=Vector2.new(x,y)
    local position=self.Launcher.Position
    if position.X.Scale~=0 or position.Y.Scale~=0 or position.X.Offset~=x or position.Y.Offset~=y then
        self.Launcher.Position=UDim2.fromOffset(x,y)
    end
    if self.Options.PositionChanged then self.Options.PositionChanged(self.FloatingPosition) end
    return x,y
end
function Collapse:ClampFloating()
    if not self.Scope.Alive or not self.FloatingPosition then return end
    self:PlaceFloating(self.FloatingPosition.X,self.FloatingPosition.Y)
    -- A resize cancels the current gesture rather than treating it as a tap.
    if self.Drag then self.Drag=nil end
end
-- Only the shell, one header label and one logo are animated. Native pages stay mounted.
local function visualBounds(object,parent)
    local p,origin,size=object.AbsolutePosition,parent.AbsolutePosition,object.AbsoluteSize
    return UDim2.fromOffset(p.X-origin.X,p.Y-origin.Y),UDim2.fromOffset(size.X,size.Y)
end
function Collapse:_CancelMorph()
    for thread in pairs(self.Timers) do task.cancel(thread) end
    table.clear(self.Timers)
    if self.Proxy then
        for _,object in ipairs(self.Proxy.Parts) do self.Scope:Cancel(object) end
    end
end
function Collapse:_Delay(seconds,ticket,fn)
    local thread
    thread=task.delay(seconds,function()
        self.Timers[thread]=nil
        if self.Scope.Alive and self.Ticket==ticket then fn() end
    end)
    self.Timers[thread]=true
end
function Collapse:_RemoveProxy()
    if self.Proxy then
        for _,object in ipairs(self.Proxy.Parts) do self.Scope:Cancel(object) end
        self.Proxy.Root:Destroy();self.Proxy=nil
    end
end
function Collapse:_MakeProxy(value)
    if self.Proxy then return self.Proxy,false end
    local o,parent=self.Options,self.Launcher.Parent
    local source=value and self.Root or self.Launcher
    local position,size=visualBounds(source,parent)
    local zoom=self.Root:FindFirstChildOfClass("UIScale")
    local scale=zoom and zoom.Scale or 1
    local rootCorner=self.Root:FindFirstChildOfClass("UICorner")
    local launcherCorner=self.Launcher:FindFirstChildOfClass("UICorner")
    local windowRadius=UDim.new(0,(rootCorner and rootCorner.CornerRadius.Offset or 7)*scale)
    local iconRadius=launcherCorner and launcherCorner.CornerRadius or UDim.new(0,9)
    local rootEdge=self.Root:FindFirstChildOfClass("UIStroke")
    local iconEdge=self.Launcher:FindFirstChildOfClass("UIStroke")
    local z=self.Launcher.ZIndex+1
    local shell=create("Frame",{Name="AroynMorphProxy",Active=false,BackgroundColor3=source.BackgroundColor3,
        BackgroundTransparency=0,BorderSizePixel=0,ClipsDescendants=true,Position=position,Size=size,ZIndex=z},parent)
    local corner=create("UICorner",{CornerRadius=value and windowRadius or iconRadius},shell)
    local edge=create("UIStroke",{ApplyStrokeMode=Enum.ApplyStrokeMode.Border,
        Color=(value and rootEdge or iconEdge) and (value and rootEdge or iconEdge).Color or Aroyn.Theme.Colors.BorderSoft,
        Thickness=((value and rootEdge or iconEdge) and (value and rootEdge or iconEdge).Thickness or 1)*(value and scale or 1),
        Transparency=(value and rootEdge or iconEdge) and (value and rootEdge or iconEdge).Transparency or 0.45},shell)
    -- Every painted child is rounded or transparent. No rectangular header fill can leak out.
    local header=create("Frame",{Name="MorphHeader",Active=false,BorderSizePixel=0,
        BackgroundColor3=o.Header and o.Header.BackgroundColor3 or Aroyn.Theme.Colors.Header,
        BackgroundTransparency=0,Size=UDim2.new(1,0,0,self.HeaderHeight*scale),Visible=value,ZIndex=z+1},shell)
    local headerCorner=create("UICorner",{CornerRadius=value and windowRadius or iconRadius},header)
    local brand
    if o.BrandText then
        local bp,bs=visualBounds(o.BrandText,self.Root)
        brand=create("TextLabel",{Name="MorphBrand",Active=false,BackgroundTransparency=1,BorderSizePixel=0,
            Text=o.BrandText.Text,TextColor3=o.BrandText.TextColor3,FontFace=o.BrandText.FontFace,
            TextSize=o.BrandText.TextSize*scale,TextXAlignment=o.BrandText.TextXAlignment,
            TextTransparency=0,TextScaled=false,TextStrokeTransparency=1,Position=bp,Size=bs,Visible=value,ZIndex=z+2},shell)
    end
    local image=o.Logo or o.BrandLogo
    local logoHolder=create("Frame",{Name="MorphLogoBounds",Active=false,BackgroundTransparency=1,BorderSizePixel=0,
        AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(28,28),
        ZIndex=z+2},shell)
    local logo=create("ImageLabel",{Name="MorphLogo",Active=false,BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.fromScale(1,1),
        Image=image and image.Image or "",ImageColor3=image and image.ImageColor3 or Aroyn.Theme.Colors.Text,
        ImageRectOffset=image and image.ImageRectOffset or Vector2.new(),ImageRectSize=image and image.ImageRectSize or Vector2.new(),
        ImageTransparency=0,ScaleType=Enum.ScaleType.Fit,ZIndex=z+2},logoHolder)
    if value and o.BrandLogo then
        local bp,bs=visualBounds(o.BrandLogo,self.Root)
        logoHolder.Position=UDim2.fromOffset(bp.X.Offset+bs.X.Offset/2,bp.Y.Offset+bs.Y.Offset/2)
        logoHolder.Size=bs
    end
    local parts={shell,corner,edge,header,headerCorner,logo,logoHolder}
    if brand then table.insert(parts,brand) end
    self.Proxy={Root=shell,Corner=corner,Edge=edge,Header=header,HeaderCorner=headerCorner,Brand=brand,Logo=logo,LogoHolder=logoHolder,
        WindowRadius=windowRadius,IconRadius=iconRadius,WindowEdge=rootEdge,IconEdge=iconEdge,WindowScale=scale,Parts=parts}
    return self.Proxy,true
end
function Collapse:Set(value, instant)
    if not self.Scope.Alive or (self.Minimized==value and not instant) then return end
    self.Ticket+=1;local ticket=self.Ticket
    local wasBusy=self.Busy
    self:_CancelMorph()
    if self.Minimized==nil or (value and self.Minimized==false and not wasBusy) then
        self.ExpandedSize=self.Root.Size;self.ExpandedPosition=self.Root.Position
    end
    self.Minimized=value;self.Busy=true;self.Gate:Set(true);self.Drag=nil
    if value and not self.FloatingPosition then
        local p,parent=self.Root.AbsolutePosition,self.Launcher.Parent.AbsolutePosition
        self:PlaceFloating(p.X-parent.X,p.Y-parent.Y)
    elseif self.FloatingPosition then self:ClampFloating() end
    if self.Before then self.Before(value) end
    self.Decorate(value)
    local function current() return self.Scope.Alive and ticket==self.Ticket end
    local function finish()
        if not current() then return end
        self.Busy=false;self.Root.Visible=not value
        self.Launcher.Visible=value;self.Launcher.Interactable=value
        self:_RemoveProxy()
        self.Gate:Set(value)
        if self.After then self.After(value) end
    end
    if instant or not self.Supported then finish();return end
    local proxy,fresh=self:_MakeProxy(value)
    local target=value and self.Launcher or self.Root
    local targetPosition,targetSize=visualBounds(target,self.Launcher.Parent)
    self.Root.Visible=false;self.Launcher.Visible=false;self.Launcher.Interactable=false
    if not fresh then
        proxy.Header.Visible=false
        if proxy.Brand then proxy.Brand.Visible=false end
    end
    local curve=Enum.EasingStyle.Quart
    local edge=value and proxy.IconEdge or proxy.WindowEdge
    self.Scope:Animate(proxy.Corner,{CornerRadius=value and proxy.IconRadius or proxy.WindowRadius},0.32,nil,curve)
    self.Scope:Animate(proxy.HeaderCorner,{CornerRadius=value and proxy.IconRadius or proxy.WindowRadius},0.32,nil,curve)
    self.Scope:Animate(proxy.Edge,{Color=edge and edge.Color or Aroyn.Theme.Colors.BorderSoft,
        Thickness=(edge and edge.Thickness or 1)*(value and 1 or proxy.WindowScale),
        Transparency=edge and edge.Transparency or 0.45},0.32,nil,curve)
    self.Scope:Animate(proxy.LogoHolder,{Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(28,28)},0.32,nil,curve)
    if value then
        self.Scope:Animate(proxy.Header,{BackgroundTransparency=1},0.075,function()
            if current() then proxy.Header.Visible=false end
        end)
        if proxy.Brand then self.Scope:Animate(proxy.Brand,{TextTransparency=1},0.07) end
        if fresh then self.Scope:Animate(proxy.Logo,{ImageTransparency=1},0.065) end
        self:_Delay(0.09,ticket,function() self.Scope:Animate(proxy.Logo,{ImageTransparency=0},0.17) end)
    else
        self.Scope:Animate(proxy.Logo,{ImageTransparency=1},0.26)
    end
    -- ONE geometry tween owns both dimensions and position, including interrupted reversals.
    self.Scope:Animate(proxy.Root,{Position=targetPosition,Size=targetSize,BackgroundColor3=target.BackgroundColor3,
        BackgroundTransparency=0},0.32,function()
        if not current() then return end
        proxy.Root.Position=targetPosition;proxy.Root.Size=targetSize
        if value then
            proxy.Logo.ImageTransparency=0
            finish()
        else
            -- Bounds now exactly match. Reveal native UI behind the rounded shell, not a rasterized page.
            self.Root.Visible=true;proxy.Edge.Transparency=1
            self.Scope:Animate(proxy.Root,{BackgroundTransparency=1},0.035,finish)
        end
    end,curve)
end
function Collapse:Destroy()
    self.Ticket+=1;self:_CancelMorph();self.Scope:Destroy();self.Gate:Set(false)
    self:_RemoveProxy()
    if self.Launcher then self.Launcher:Destroy() end
end

-- One local line icon family. Coordinates are in a 24x24 optical grid.
-- ImageColor3 on the empty holder also lets the inherited UI animate tint.
Aroyn.Icons={
    cart={Lines={{3,4,6,4},{6,4,8,15},{8,15,19,15},{7,7,21,7},{21,7,19,12},{19,12,8,12}},Circles={{10,19,3},{18,19,3}}},
    plot={Lines={{12,21,12,9},{12,14,6,10},{6,10,4,4},{4,4,10,6},{10,6,12,11},{12,11,15,5},{15,5,21,3},{21,3,19,9},{19,9,12,14},{5,21,19,21}}},
    compost={Lines={{4,8,12,4},{12,4,20,8},{20,8,12,12},{12,12,4,8},{4,8,4,18},{4,18,12,22},{12,22,20,18},{20,18,20,8},{12,12,12,22}},Circles={}},
    market={Lines={{3,8,5,3},{5,3,19,3},{19,3,21,8},{3,8,21,8},{5,8,5,21},{5,21,19,21},{19,21,19,8},{9,21,9,14},{9,14,15,14},{15,14,15,21},{8,3,7,8},{16,3,17,8}}},
    settings={Lines={{3,6,21,6},{3,12,21,12},{3,18,21,18}},Circles={{8,6,4},{16,12,4},{10,18,4}}},
    pets={Lines={{6,17,9,13},{9,13,15,13},{15,13,18,17},{18,17,17,21},{17,21,7,21},{7,21,6,17}},Circles={{4,10,3},{9,6,3},{15,6,3},{20,10,3}}},
    components={Boxes={{3,3,7,7},{14,3,7,7},{3,14,7,7},{14,14,7,7}}},
}
function Aroyn:CreateIcon(parent, key, size, tint)
    assert(typeof(parent)=="Instance", "Aroyn: icon Parent must be an Instance")
    local definition=assert(self.Icons[key],"Aroyn: unknown icon "..tostring(key))
    size=size or self.Theme.Metrics.Icon
    local holder=create("ImageLabel",{Name="Icon_"..key,BackgroundTransparency=1,BorderSizePixel=0,
        Image="",ImageColor3=tint or self.Theme.Colors.TextMuted,Size=UDim2.fromOffset(size,size),ZIndex=parent.ZIndex+1},parent)
    local index=table.find({"cart","plot","compost","market","settings","pets","components"},key)
    if self.IconAtlas and self.IconAtlas~="" then
        holder.Image=self.IconAtlas
        holder.ImageRectOffset=Vector2.new((index-1)*128,0)
        holder.ImageRectSize=Vector2.new(128,128)
        holder.ResampleMode=Enum.ResamplerMode.Default
    else
        -- Explicit limitation, not another thin geometry substitute.
        holder:SetAttribute("AroynIconUnavailable",true)
        if not self.IconWarning then
            self.IconWarning=true
            warn("Aroyn: navigation atlas unavailable; supply Aroyn.IconAtlas. No HTTP fallback.")
        end
    end
    return holder
end

local Window={};Window.__index=Window
local Page={};Page.__index=Page
local Section={};Section.__index=Section
local Component={};Component.__index=Component
function Component:GetValue()
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    assert(self.Kind~="Button","Aroyn: buttons use GetText")
    if self.Kind=="Dropdown" and self.Multi then return table.clone(self.Value) end
    return self.Kind=="Input" and self.Control.Text or self.Value
end
function Component:SetValue(value, notify)
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    assert(self.Kind~="Button","Aroyn: buttons use SetText")
    if notify~=nil then bool(notify,"Notify") end
    if self.Kind=="Slider" then value=self:_NormalizeSlider(value)
    elseif self.Kind=="Dropdown" then value=self:_NormalizeDropdown(value)
    elseif self.Kind=="Toggle" then bool(value,"Value")
    else assert(type(value)=="string","Aroyn: input Value must be string") end
    local previous=self:GetValue()
    self.Value=value
    if self.Kind=="Input" then self.Control.Text=value end
    self:Render()
    local changed=self.Kind=="Dropdown" and not self:_SameValue(previous,value) or (self.Kind~="Dropdown" and previous~=value)
    if notify==true and changed then invoke(self,self:GetValue()) end
    return self
end
function Component:SetText(value)
    assert(self.Scope.Alive and self.Kind=="Button","Aroyn: SetText requires a live Button")
    assert(type(value)=="string","Aroyn: Text must be string")
    self.Control.Text=value
    return self
end
function Component:GetText()
    assert(self.Scope.Alive and self.Kind=="Button","Aroyn: GetText requires a live Button")
    return self.Control.Text
end
function Component:SetDisabled(value)
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    self.Disabled=bool(value,"Disabled")
    self.Hovered=false;self.Pressed=false
    if value and self.Kind=="Slider" then self:_StopDrag() end
    if value and self.Kind=="Dropdown" then self:Close(true) end
    if self.Kind=="Input" and value and self.Control:IsFocused() then self.Control:ReleaseFocus(false) end
    self:Render()
    return self
end
function Component:IsDisabled() return self.Disabled end
function Component:Render()
    if not self.Scope.Alive then return end
    local C=Aroyn.Theme.Colors;local B=Aroyn.Theme.Borders
    self.Label.TextColor3=self.Disabled and C.TextDim or C.Text
    if self.Description then self.Description.TextColor3=self.Disabled and C.TextDim or C.TextMuted end
    self.Control:SetAttribute("AroynDisabled",self.Disabled)
    Aroyn:_DesiredProperty(self.Control,"Interactable",not self.Disabled)
    self.Control.Active=not self.Disabled;self.Control.Selectable=not self.Disabled
    if self.Kind=="Slider" then
        Aroyn:_DesiredProperty(self.Hitbox,"Interactable",not self.Disabled)
        self.Hitbox.Active=not self.Disabled
        self:_RenderSlider()
    elseif self.Kind=="Toggle" then
        local M=Aroyn.Theme.Metrics
        self.Scope:Animate(self.Track,{BackgroundColor3=self.Value and C.AccentDark or C.Surface3},Aroyn.Theme.Animation.Value)
        self.Scope:Animate(self.Thumb,{Position=self.Value and UDim2.new(1,-(M.Thumb+M.ThumbInset),0.5,0) or UDim2.new(0,M.ThumbInset,0.5,0),
            BackgroundColor3=self.Disabled and C.TextDim or (self.Value and C.AccentBright or C.TextMuted)},Aroyn.Theme.Animation.Value)
        self.Edge.Transparency=self.Disabled and B.Disabled or B.Normal
    else
        local primary=self.Kind=="Button" and self.Variant=="Primary"
        local background=primary and C.Accent or C.Surface2
        if self.Disabled then background=C.Surface
        elseif self.Pressed then background=primary and C.TextMuted or C.Pressed
        elseif self.Hovered then background=primary and C.AccentBright or C.Hover end
        self.Scope:Animate(self.Control,{BackgroundColor3=background,
            TextColor3=self.Disabled and C.TextDim or (self.Kind=="Input" and C.Text or (primary and C.Window or C.TextMuted))})
        self.Scope:Animate(self.Edge,{Color=self.Focused and not self.Disabled and C.AccentSoft or C.BorderSoft,
            Transparency=self.Disabled and B.Disabled or (self.Focused and B.Focus or B.Normal)},0.12)
        if self.Kind=="Input" then
            Aroyn:_DesiredProperty(self.Control,"TextEditable",not self.Disabled)
        elseif self.Kind=="Dropdown" then self:_RenderDropdown() end
    end
end
function Component:Destroy()
    if not self.Scope.Alive then return end
    if self.Kind=="Slider" then self:_StopDrag() end
    if self.Kind=="Dropdown" then self:Close(true) end
    self.Scope:Destroy()
    if self.Kind=="Input" and self.Control:IsFocused() then self.Control:ReleaseFocus(false) end
    remove(self.Section.Components,self)
    self.Root:Destroy()
    if self.Section.Scope.Alive then self.Section:Reflow() end
end
local function component(section, kind, raw)
    assert(section.Scope.Alive,"Aroyn: section is destroyed")
    local o=options(raw);local M=Aroyn.Theme.Metrics;local F=Aroyn.Theme.Fonts;local C=Aroyn.Theme.Colors
    local title=name(o.Name);callback(o.Callback)
    assert(o.Description==nil or type(o.Description)=="string","Aroyn: Description must be string")
    if o.Disabled~=nil then bool(o.Disabled,"Disabled") end
    local hasDescription=o.Description and o.Description~=""
    local c=setmetatable({Section=section,Name=title,Kind=kind,Disabled=o.Disabled==true,Callback=o.Callback,
        Scope=Scope.new(),Height=hasDescription and M.DescriptionRow or M.Row},Component)
    c.Root=create("Frame",{Name=kind.."_"..title,BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.new(1,0,0,c.Height)},section.Root)
    c.Label=text(c.Root,title,F.Label,F.Medium,C.Text)
    local fieldWidth=kind=="Toggle" and M.ToggleWidth or (kind=="Button" and M.ButtonWidth or M.FieldWidth)
    c.Label.Position=UDim2.fromOffset(0,4);c.Label.Size=UDim2.new(1,-(fieldWidth+M.Gap),0,22)
    if hasDescription then
        c.Description=text(c.Root,o.Description,F.Description,F.Regular,C.TextMuted)
        c.Description.Position=UDim2.fromOffset(0,28);c.Description.Size=UDim2.new(1,-(fieldWidth+M.Gap),0,20)
    end
    table.insert(section.Components,c)
    c.Scope:Connect(c.Root.Destroying,function() c:Destroy() end)
    section:Reflow()
    return c,o
end
function Section:CreateToggle(raw)
    local o=options(raw)
    if o.Default~=nil then bool(o.Default,"Default") end
    local c=component(self,"Toggle",o);local M=Aroyn.Theme.Metrics;local C=Aroyn.Theme.Colors
    c.Value=o.Default==true
    c.Control=create("TextButton",{Name="Toggle",AutoButtonColor=false,Text="",BackgroundTransparency=1,BorderSizePixel=0,
        AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.ToggleWidth,M.Control),ZIndex=3},c.Root)
    c.Track=create("Frame",{BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),
        Size=UDim2.fromOffset(M.TrackWidth,M.TrackHeight),BackgroundColor3=C.Surface3,ZIndex=3},c.Control)
    rounded(c.Track,M.TrackHeight);c.Edge=outline(c.Track)
    c.Thumb=create("Frame",{BorderSizePixel=0,AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,4,0.5,0),
        Size=UDim2.fromOffset(M.Thumb,M.Thumb),BackgroundColor3=C.TextMuted,ZIndex=4},c.Track)
    rounded(c.Thumb,M.Thumb)
    c.Scope:Connect(c.Control.Activated,function() if not c.Disabled and not blocked(c.Control) then c:SetValue(not c.Value,true) end end)
    c:Render()
    return c
end
local function hover(c)
    c.Scope:Connect(c.Control.MouseEnter,function() if not c.Disabled and not blocked(c.Control) then c.Hovered=true;c:Render() end end)
    c.Scope:Connect(c.Control.MouseLeave,function() c.Hovered=false;c.Pressed=false;c:Render() end)
end
function Section:CreateButton(raw)
    local o=options(raw)
    assert(o.Variant==nil or o.Variant=="Primary" or o.Variant=="Secondary","Aroyn: unknown Button Variant")
    assert(o.Text==nil or type(o.Text)=="string","Aroyn: Button Text must be string")
    local c=component(self,"Button",o);local M=Aroyn.Theme.Metrics;local C=Aroyn.Theme.Colors
    c.Variant=o.Variant or "Secondary"
    c.Control=create("TextButton",{Name="Button",AutoButtonColor=false,BorderSizePixel=0,
        BackgroundColor3=C.Surface2,Text=o.Text or o.Name,TextSize=Aroyn.Theme.Fonts.Description,
        TextColor3=C.TextMuted,TextTruncate=Enum.TextTruncate.AtEnd,TextXAlignment=Enum.TextXAlignment.Center,
        AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.ButtonWidth,M.Control),ZIndex=3},c.Root)
    rounded(c.Control);c.Edge=outline(c.Control);hover(c)
    c.Scope:Connect(c.Control.MouseButton1Down,function() if not c.Disabled and not blocked(c.Control) then c.Pressed=true;c:Render() end end)
    c.Scope:Connect(c.Control.MouseButton1Up,function() c.Pressed=false;c:Render() end)
    c.Scope:Connect(c.Control.Activated,function() if not c.Disabled and not blocked(c.Control) then invoke(c) end end)
    c:Render()
    return c
end
function Section:CreateTextInput(raw)
    local o=options(raw)
    assert(o.Default==nil or type(o.Default)=="string","Aroyn: input Default must be string")
    assert(o.Placeholder==nil or type(o.Placeholder)=="string","Aroyn: Placeholder must be string")
    if o.SubmitOnEnter~=nil then bool(o.SubmitOnEnter,"SubmitOnEnter") end
    local c=component(self,"Input",o);local M=Aroyn.Theme.Metrics;local C=Aroyn.Theme.Colors
    c.Value=o.Default or ""
    c.Control=create("TextBox",{Name="TextInput",BorderSizePixel=0,ClearTextOnFocus=false,
        BackgroundColor3=C.Surface2,Text=c.Value,PlaceholderText=o.Placeholder or "",
        PlaceholderColor3=C.TextDim,TextSize=Aroyn.Theme.Fonts.Description,TextColor3=C.Text,
        TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,
        AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.FieldWidth,M.Control),ZIndex=3},c.Root)
    rounded(c.Control);c.Edge=outline(c.Control)
    create("UIPadding",{PaddingLeft=UDim.new(0,M.Gap),PaddingRight=UDim.new(0,M.Gap)},c.Control)
    hover(c)
    c.Scope:Connect(c.Control.Focused,function() c.Focused=true;c:Render() end)
    c.Scope:Connect(c.Control.FocusLost,function(enterPressed)
        c.Focused=false;c:Render()
        if not c.Disabled and not blocked(c.Control) and (not o.SubmitOnEnter or enterPressed) then c.Value=c.Control.Text;invoke(c,c.Value) end
    end)
    c:Render()
    return c
end
-- BEGIN ADVANCED COMPONENTS
-- Phase 3A fragment; embedded by refine.py into the import-free library.
local function finite(value, key)
    assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Aroyn: "..key.." must be finite")
    return value
end
local function array(value, key)
    assert(type(value)=="table","Aroyn: "..key.." must be an array")
    local count=0
    for k in pairs(value) do
        assert(type(k)=="number" and k>=1 and k%1==0,"Aroyn: "..key.." must be an array")
        count+=1
    end
    assert(count==#value,"Aroyn: "..key.." cannot have holes")
    return value
end
local function optionList(raw)
    local values,seen={},{}
    for _,value in ipairs(array(raw,"Options")) do
        assert(type(value)=="string" and value~="","Aroyn: options must be nonempty strings")
        if not seen[value] then seen[value]=true;table.insert(values,value) end
    end
    return values
end
local function normalizedSelection(value, list, multi)
    if not multi then
        assert(value==nil or type(value)=="string","Aroyn: dropdown Value must be string or nil")
        return table.find(list,value) and value or nil
    end
    local requested={}
    for _,item in ipairs(array(value==nil and {} or value,"Value")) do
        assert(type(item)=="string","Aroyn: multi Value must contain strings")
        requested[item]=true
    end
    local result={}
    for _,item in ipairs(list) do if requested[item] then table.insert(result,item) end end
    return result
end
function Component:_NormalizeDropdown(value)
    return normalizedSelection(value,self.Options,self.Multi)
end
function Component:_NormalizeSlider(value)
    value=math.clamp(finite(value,"Value"),self.Min,self.Max)
    if value==self.Min or value==self.Max then return value end
    local steps=math.floor((value-self.Min)/self.Step+0.5)
    return math.clamp(self.Min+steps*self.Step,self.Min,self.Max)
end
function Component:_SameValue(a,b)
    if not self.Multi then return a==b end
    if #a~=#b then return false end
    for i,value in ipairs(a) do if b[i]~=value then return false end end
    return true
end
local function screenFor(object)
    local node=object
    while node do if node:IsA("ScreenGui") then return node end;node=node.Parent end
    return nil
end
local function pointFor(c,input)
    local point=input.Position
    local screen=screenFor(c.Control)
    if screen and not screen.IgnoreGuiInset then
        local inset=game:GetService("GuiService"):GetGuiInset()
        return Vector2.new(point.X-inset.X,point.Y-inset.Y)
    end
    return Vector2.new(point.X,point.Y)
end
local function contains(object,point)
    local p,s=object.AbsolutePosition,object.AbsoluteSize
    return point.X>=p.X and point.X<=p.X+s.X and point.Y>=p.Y and point.Y<=p.Y+s.Y
end
local function available(c)
    if not c.Scope.Alive or c.Disabled or blocked(c.Control) then return false end
    local node=c.Control
    while node do
        if node:IsA("GuiObject") and not node.Visible then return false end
        if node:IsA("ScreenGui") and node.Enabled==false then return false end
        node=node.Parent
    end
    return c.Root.Parent~=nil
end
-- No polling. Existing visibility/input gates close portals and end drags.
local function watchAvailability(c)
    local node=c.Root
    while node do
        local function check()
            if not available(c) then
                if c.Kind=="Slider" then c:_StopDrag() else c:Close(true) end
            end
        end
        c.Scope:Connect(node:GetAttributeChangedSignal("AroynInputBlocked"),check)
        c.Scope:Connect(node:GetAttributeChangedSignal("AroynModalBlocked"),check)
        if node:IsA("GuiObject") then c.Scope:Connect(node:GetPropertyChangedSignal("Visible"),check) end
        if node:IsA("ScreenGui") then c.Scope:Connect(node:GetPropertyChangedSignal("Enabled"),check) end
        node=node.Parent
    end
    c.Scope:Connect(c.Root.AncestryChanged,function() if not c.Root.Parent then c:Destroy() end end)
end
function Component:_StopDrag()
    self.Drag=nil
    for object,value in pairs(self.DragScroll or {}) do
        if object.Parent then Aroyn:_DesiredProperty(object,"ScrollingEnabled",value) end
    end
    self.DragScroll=nil
end
function Component:_RenderSlider()
    local C=Aroyn.Theme.Colors
    local ratio=self.Max==self.Min and 0 or (self.Value-self.Min)/(self.Max-self.Min)
    local width=math.max(0,math.floor(self.Track.AbsoluteSize.X+0.5))
    local x=math.floor(width*ratio+0.5)
    -- Direct placement, including drag: no high-frequency TweenService work.
    self.Fill.Size=UDim2.new(0,x,1,0)
    self.Thumb.Position=UDim2.new(0,x,0.5,0)
    self.Track.BackgroundColor3=C.Surface3
    self.Fill.BackgroundColor3=self.Disabled and C.TextDim or C.AccentSoft
    self.Thumb.BackgroundColor3=self.Disabled and C.TextDim or C.AccentBright
    local rendered=self.Step<1e-9 and string.format("%.12g",self.Value) or string.format("%."..self.Decimals.."f",self.Value)
    if tonumber(rendered)==0 then rendered=string.format("%."..self.Decimals.."f",0) end
    self.ValueLabel.Text=rendered..self.Suffix
    self.ValueLabel.TextColor3=self.Disabled and C.TextDim or C.TextMuted
end
function Section:CreateSlider(raw)
    local o=options(raw)
    local minimum=finite(o.Min==nil and 0 or o.Min,"Min");local maximum=finite(o.Max==nil and 100 or o.Max,"Max")
    local step=finite(o.Step==nil and 1 or o.Step,"Step")
    assert(maximum>=minimum and step>0 and maximum-minimum<math.huge,"Aroyn: invalid slider range or Step")
    assert((maximum-minimum)/step<1e15,"Aroyn: slider Step is too small for this range")
    assert(o.Suffix==nil or type(o.Suffix)=="string","Aroyn: Suffix must be string")
    local initial=finite(o.Default==nil and minimum or o.Default,"Default")
    local c=component(self,"Slider",o);local M=Aroyn.Theme.Metrics;local C=Aroyn.Theme.Colors
    c.Min=minimum;c.Max=maximum;c.Step=step;c.Suffix=o.Suffix or ""
    c.Decimals=0
    for _,v in ipairs({minimum,maximum,step}) do
        local digits=0
        while digits<9 and math.abs(v*10^digits-math.round(v*10^digits))>1e-7 do digits+=1 end
        c.Decimals=math.max(c.Decimals,digits)
    end
    c.Value=c:_NormalizeSlider(initial)
    c.Control=create("TextButton",{Name="Slider",Text="",AutoButtonColor=false,BackgroundTransparency=1,
        BorderSizePixel=0,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.FieldWidth,M.Control),ZIndex=3},c.Root)
    c.Track=create("Frame",{Name="Track",BackgroundColor3=C.Surface3,BorderSizePixel=0,
        Position=UDim2.new(0,8,0.5,-2),Size=UDim2.new(1,-84,0,4),ZIndex=3},c.Control)
    rounded(c.Track,3)
    c.Fill=create("Frame",{Name="Fill",BorderSizePixel=0,BackgroundColor3=C.AccentSoft,Size=UDim2.fromScale(0,1),ZIndex=4},c.Track)
    rounded(c.Fill,3)
    c.Thumb=create("Frame",{Name="Thumb",BorderSizePixel=0,BackgroundColor3=C.AccentBright,
        AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(14,14),ZIndex=5},c.Track)
    rounded(c.Thumb,14)
    c.ValueLabel=text(c.Control,"",Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Medium,C.TextMuted)
    c.ValueLabel.AnchorPoint=Vector2.new(1,0);c.ValueLabel.Position=UDim2.fromScale(1,0)
    c.ValueLabel.Size=UDim2.new(0,66,1,0);c.ValueLabel.TextXAlignment=Enum.TextXAlignment.Right;c.ValueLabel.ZIndex=4
    c.Hitbox=create("TextButton",{Name="SliderHitbox",Text="",AutoButtonColor=false,BackgroundTransparency=1,
        BorderSizePixel=0,AnchorPoint=Vector2.new(0,0.5),Position=UDim2.fromScale(0,0.5),Size=UDim2.new(1,-68,0,40),ZIndex=6},c.Control)
    local function update(input)
        local width=c.Track.AbsoluteSize.X
        if width<=0 then return end
        local fraction=math.clamp((pointFor(c,input).X-c.Track.AbsolutePosition.X)/width,0,1)
        c:SetValue(c.Min+(c.Max-c.Min)*fraction,true)
    end
    c.Scope:Connect(c.Hitbox.InputBegan,function(input)
        if not available(c) or c.Drag then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        c.Drag=input;c.DragScroll={}
        local node=c.Root.Parent
        while node do
            if node:IsA("ScrollingFrame") then
                c.DragScroll[node]=Aroyn:_DesiredValue(node,"ScrollingEnabled")
                Aroyn:_DesiredProperty(node,"ScrollingEnabled",false)
            end
            node=node.Parent
        end
        update(input)
    end)
    c.Scope:Connect(InputService.InputChanged,function(input)
        if not c.Drag then return end
        if not available(c) then c:_StopDrag();return end
        if input==c.Drag or (c.Drag.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then update(input) end
    end)
    c.Scope:Connect(InputService.InputEnded,function(input)
        if c.Drag and (input==c.Drag or (c.Drag.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1)) then c:_StopDrag() end
    end)
    c.Scope:Connect(InputService.WindowFocusReleased,function() c:_StopDrag() end)
    c.Scope:Connect(c.Track:GetPropertyChangedSignal("AbsoluteSize"),function() c:_RenderSlider() end)
    watchAvailability(c);c:Render()
    return c
end
function Component:_RenderDropdown()
    local summary=self.Value
    if self.Multi then
        summary=#self.Value==1 and self.Value[1] or (#self.Value>1 and (tostring(#self.Value).." selected") or nil)
    end
    self.ValueLabel.Text=summary or (#self.Options==0 and "No options" or self.Placeholder)
    self.ValueLabel.TextColor3=self.Disabled and Aroyn.Theme.Colors.TextDim or (summary and Aroyn.Theme.Colors.Text or Aroyn.Theme.Colors.TextMuted)
    self.Scope:Animate(self.Arrow,{Rotation=self.Opened and 180 or 0},0.16)
    local popup=self.Popup
    if popup and not popup.Closing then
        for _,row in ipairs(popup.Rows) do
            local selected=self.Multi and table.find(self.Value,row.Value)~=nil or self.Value==row.Value
            row.Mark.Text=selected and "✓" or ""
            row.Button.BackgroundColor3=selected and Aroyn.Theme.Colors.Selected or Aroyn.Theme.Colors.Surface
        end
    end
end
function Component:GetOptions()
    assert(self.Scope.Alive and self.Kind=="Dropdown","Aroyn: GetOptions requires a live Dropdown")
    return table.clone(self.Options)
end
function Component:SetOptions(raw,notify)
    assert(self.Scope.Alive and self.Kind=="Dropdown","Aroyn: SetOptions requires a live Dropdown")
    if notify~=nil then bool(notify,"Notify") end
    local list=optionList(raw);local previous=self:GetValue();local reopen=self.Opened
    self:Close(true);self.Options=list
    self.Value=normalizedSelection(previous,list,self.Multi);self:Render()
    if reopen then self:Open() end
    if notify and not self:_SameValue(previous,self.Value) then invoke(self,self:GetValue()) end
    return self
end
function Component:Clear(notify)
    assert(self.Scope.Alive and self.Kind=="Dropdown","Aroyn: Clear requires a live Dropdown")
    return self:SetValue(self.Multi and {} or nil,notify)
end
function Component:IsOpen() return self.Opened==true end
function Component:Close(instant)
    assert(self.Kind=="Dropdown","Aroyn: Close requires Dropdown")
    local popup=self.Popup
    self.Opened=false
    if self.Section.Page.Window.PopupOwner==self then self.Section.Page.Window.PopupOwner=nil end
    if not popup then return self end
    local function dispose()
        popup.Scope:Destroy();popup.Portal:Destroy()
        if self.Popup==popup then self.Popup=nil end
    end
    popup.Dispose=dispose
    if instant or not self.Scope.Alive or Aroyn.MotionEnabled==false then dispose()
    elseif not popup.Closing then
        popup.Closing=true
        popup.List.Active=false;popup.List.ScrollingEnabled=false
        for _,row in ipairs(popup.Rows) do
            popup.Scope:Cancel(row.Button);row.Button.Interactable=false;row.Button.Active=false
        end
        if popup.Clear then popup.Clear.Interactable=false;popup.Clear.Active=false end
        popup.Root.Active=false
        -- AnchorPoint fixes the trigger-facing edge; cancel continues from current geometry.
        popup.Scope:Animate(popup.Root,{Position=popup.Placement and popup.Placement.Position or popup.Root.Position,
            Size=UDim2.fromOffset(popup.Root.Size.X.Offset,0)},0.16,dispose)
    end
    if self.Scope.Alive then self:_RenderDropdown() end
    return self
end
function Component:_PositionPopup(popup,animate)
    if self.Popup~=popup then return end
    if not available(self) then self:Close(true);return end
    local rp,rs=self.Section.Page.Window.Root.AbsolutePosition,self.Section.Page.Window.Root.AbsoluteSize
    local origin,screenSize=popup.Portal.AbsolutePosition,popup.Portal.AbsoluteSize
    local left,top=math.max(rp.X+8,origin.X+8),math.max(rp.Y+8,origin.Y+8)
    local right,bottom=math.min(rp.X+rs.X-8,origin.X+screenSize.X-8),math.min(rp.Y+rs.Y-8,origin.Y+screenSize.Y-8)
    local p,s=self.Control.AbsolutePosition,self.Control.AbsoluteSize
    -- A portal must not linger when its trigger has scrolled completely away.
    local node=self.Control.Parent
    while node and node~=popup.Portal.Parent do
        if node:IsA("GuiObject") and (node.ClipsDescendants or node:IsA("ScrollingFrame")) then
            local cp,cs=node.AbsolutePosition,node.AbsoluteSize
            if p.Y+s.Y<=cp.Y or p.Y>=cp.Y+cs.Y or p.X+s.X<=cp.X or p.X>=cp.X+cs.X then self:Close(true);return end
        end
        node=node.Parent
    end
    if right-left<48 or bottom-top<40 then self:Close(true);return end
    local width=math.floor(math.min(math.max(s.X,160),right-left))
    local below,above=math.max(0,bottom-(p.Y+s.Y+5)),math.max(0,p.Y-5-top)
    local desired=math.min(self.MaxVisibleOptions,math.max(1,#self.Options))*36+12+(self.Multi and 36 or 0)
    local upwards=below<desired and above>below
    local height=math.floor(math.min(desired,upwards and above or below))
    if height<(self.Multi and 84 or 40) then self:Close(true);return end
    local x=math.floor(math.clamp(p.X,left,right-width)+0.5)
    local y=math.floor(math.clamp(upwards and p.Y-5-height or p.Y+s.Y+5,top,bottom-height)+0.5)
    local edgeY=y+(upwards and height or 0)
    local destination=UDim2.fromOffset(x-origin.X,edgeY-origin.Y)
    local previous=popup.Placement
    local directionChanged=previous and previous.Upwards~=upwards
    local changed=not previous or directionChanged or previous.X~=x or previous.EdgeY~=edgeY
        or previous.Width~=width or previous.Height~=height
    if not changed and not animate then return end
    local running=popup.Scope.Animations[popup.Root]~=nil
    popup.Scope:Cancel(popup.Root)
    if not previous then
        popup.Root.AnchorPoint=Vector2.new(0,upwards and 1 or 0)
        popup.Root.Position=destination;popup.Root.Size=UDim2.fromOffset(width,0)
    elseif directionChanged then
        -- Changing the anchor must preserve the current rectangle, even mid-tween.
        local currentPosition,currentSize=popup.Root.AbsolutePosition,popup.Root.AbsoluteSize
        popup.Root.AnchorPoint=Vector2.new(0,upwards and 1 or 0)
        popup.Root.Position=UDim2.fromOffset(currentPosition.X-origin.X,
            currentPosition.Y-origin.Y+(upwards and currentSize.Y or 0))
    end
    popup.Placement={Upwards=upwards,X=x,EdgeY=edgeY,Width=width,Height=height,Position=destination}
    popup.List.Size=UDim2.new(1,-12,1,-12-(self.Multi and 36 or 0))
    local goalSize=UDim2.fromOffset(width,popup.Closing and 0 or height)
    if Aroyn.MotionEnabled~=false and (animate or directionChanged or running or popup.Closing) then
        popup.Scope:Animate(popup.Root,{Position=destination,Size=goalSize},popup.Closing and 0.16 or 0.18,
            popup.Closing and popup.Dispose or nil)
    else popup.Root.Position=destination;popup.Root.Size=goalSize end
end
function Component:Open()
    assert(self.Scope.Alive and self.Kind=="Dropdown","Aroyn: Open requires a live Dropdown")
    if not available(self) or self.Opened then return self end
    local screen=screenFor(self.Control)
    assert(screen,"Aroyn: Dropdown requires a ScreenGui ancestor")
    local window=self.Section.Page.Window
    if window.PopupOwner then window.PopupOwner:Close(true) end
    local existing=self.Popup
    if existing and existing.Closing then
        -- Reverse the same panel in place; its lifetime listeners survive closing.
        existing.Scope:Cancel(existing.Root);existing.Closing=false
        self.Opened=true;window.PopupOwner=self
        existing.Root.Active=true;existing.List.Active=true;existing.List.ScrollingEnabled=true
        for _,row in ipairs(existing.Rows) do row.Button.Interactable=true;row.Button.Active=true end
        if existing.Clear then existing.Clear.Interactable=true;existing.Clear.Active=true end
        self:_RenderDropdown();self:_PositionPopup(existing,true)
        return self
    end
    self:Close(true)
    local z=window.Root.ZIndex+100
    for _,object in ipairs(window.Root:GetDescendants()) do if object:IsA("GuiObject") then z=math.max(z,object.ZIndex+10) end end
    local popup={Scope=Scope.new(),Rows={}}
    popup.Portal=create("Frame",{Name="AroynDropdownPortal",BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.fromScale(1,1),Active=false,ZIndex=z},screen)
    popup.Root=create("Frame",{Name="Options",BorderSizePixel=0,BackgroundColor3=Aroyn.Theme.Colors.Surface,
        Active=true,ClipsDescendants=true,ZIndex=z+1},popup.Portal)
    rounded(popup.Root);outline(popup.Root)
    popup.List=create("ScrollingFrame",{Name="OptionsScroll",BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.fromOffset(6,6),Size=UDim2.fromScale(1,1),Active=true,ScrollingEnabled=true,
        CanvasSize=UDim2.fromOffset(0,math.max(1,#self.Options)*36),ScrollBarThickness=3,
        ScrollBarImageColor3=Aroyn.Theme.Colors.TextDim,ScrollingDirection=Enum.ScrollingDirection.Y,
        ClipsDescendants=true,ZIndex=z+2},popup.Root)
    self.Popup=popup;self.Opened=true;window.PopupOwner=self
    if #self.Options==0 then
        local empty=text(popup.List,"No options available",Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Regular,Aroyn.Theme.Colors.TextDim)
        empty.Size=UDim2.new(1,-8,0,36);empty.ZIndex=z+3
    end
    for i,value in ipairs(self.Options) do
        local button=create("TextButton",{Name="Option_"..i,Text="",AutoButtonColor=false,BorderSizePixel=0,
            BackgroundColor3=Aroyn.Theme.Colors.Surface,Position=UDim2.fromOffset(0,(i-1)*36),Size=UDim2.new(1,-5,0,34),ZIndex=z+3},popup.List)
        rounded(button)
        local label=text(button,value,Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Medium,Aroyn.Theme.Colors.Text)
        label.Position=UDim2.fromOffset(8,0);label.Size=UDim2.new(1,-38,1,0);label.ZIndex=z+4
        local mark=text(button,"",Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Medium,Aroyn.Theme.Colors.TextMuted)
        mark.Position=UDim2.new(1,-26,0,0);mark.Size=UDim2.new(0,20,1,0);mark.ZIndex=z+4
        table.insert(popup.Rows,{Button=button,Mark=mark,Value=value})
        popup.Scope:Connect(button.MouseEnter,function()
            if not popup.Closing then popup.Scope:Animate(button,{BackgroundColor3=Aroyn.Theme.Colors.Hover}) end
        end)
        popup.Scope:Connect(button.MouseLeave,function()
            popup.Scope:Cancel(button);self:_RenderDropdown()
        end)
        popup.Scope:Connect(button.Activated,function()
            if not available(self) or self.Popup~=popup or popup.Closing then return end
            if self.Multi then
                local selections=self:GetValue();local at=table.find(selections,value)
                if at then table.remove(selections,at) else table.insert(selections,value) end
                self:SetValue(selections,true)
            else self:Close();self:SetValue(value,true) end
        end)
    end
    if self.Multi then
        popup.Clear=create("TextButton",{Name="ClearSelections",Text="Clear selections",TextSize=Aroyn.Theme.Fonts.Description,
            TextColor3=Aroyn.Theme.Colors.TextMuted,BackgroundColor3=Aroyn.Theme.Colors.Surface2,AutoButtonColor=false,BorderSizePixel=0,
            AnchorPoint=Vector2.new(0,1),Position=UDim2.new(0,6,1,-6),Size=UDim2.new(1,-12,0,30),ZIndex=z+3},popup.Root)
        rounded(popup.Clear)
        popup.Scope:Connect(popup.Clear.Activated,function() if available(self) then self:Clear(true) end end)
    end
    popup.Scope:Connect(InputService.InputBegan,function(input)
        if popup.Closing or self.Popup~=popup then return end
        if input.KeyCode==Enum.KeyCode.Escape then self:Close();return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            -- InputObject.Position and AbsolutePosition share CoreUISafeInsets coordinates.
            -- Subtracting GetGuiInset again misclassifies the trigger before Activated toggles it.
            local point=Vector2.new(input.Position.X,input.Position.Y)
            if not contains(popup.Root,point) and not contains(self.Control,point) then self:Close() end
        end
    end)
    popup.Scope:Connect(InputService.WindowFocusReleased,function() self:Close(true) end)
    popup.Scope:Connect(popup.Portal.Destroying,function() self:Close(true) end)
    local function position() self:_PositionPopup(popup,false) end
    -- Respond to actual geometry/scroll changes, never a per-frame loop.
    local node=self.Control
    while node do
        if node:IsA("GuiObject") then
            for _,property in ipairs({"AbsolutePosition","AbsoluteSize"}) do popup.Scope:Connect(node:GetPropertyChangedSignal(property),position) end
            if node:IsA("ScrollingFrame") then popup.Scope:Connect(node:GetPropertyChangedSignal("CanvasPosition"),position) end
        end
        node=node.Parent
    end
    popup.Scope:Connect(popup.Portal:GetPropertyChangedSignal("AbsoluteSize"),position)
    self:_RenderDropdown();self:_PositionPopup(popup,true)
    return self
end
function Section:CreateDropdown(raw)
    local o=options(raw)
    if o.Multi~=nil then bool(o.Multi,"Multi") end
    local list=optionList(o.Options==nil and {} or o.Options)
    local multi=o.Multi==true;local initial=normalizedSelection(o.Default,list,multi)
    assert(o.Placeholder==nil or type(o.Placeholder)=="string","Aroyn: Placeholder must be string")
    local visible=finite(o.MaxVisibleOptions==nil and 6 or o.MaxVisibleOptions,"MaxVisibleOptions")
    assert(visible>=1 and visible%1==0 and visible<=20,"Aroyn: MaxVisibleOptions must be 1..20")
    local c=component(self,"Dropdown",o);local M=Aroyn.Theme.Metrics;local C=Aroyn.Theme.Colors
    c.Options=list;c.Value=initial;c.Multi=multi;c.Placeholder=o.Placeholder or "Select an option";c.MaxVisibleOptions=visible
    c.Control=create("TextButton",{Name="Dropdown",Text="",AutoButtonColor=false,BorderSizePixel=0,
        BackgroundColor3=C.Surface2,TextSize=Aroyn.Theme.Fonts.Description,TextColor3=C.TextMuted,
        AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.FieldWidth,M.Control),ZIndex=3},c.Root)
    rounded(c.Control);c.Edge=outline(c.Control);hover(c)
    c.ValueLabel=text(c.Control,"",Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Medium,C.TextMuted)
    c.ValueLabel.Position=UDim2.fromOffset(8,0);c.ValueLabel.Size=UDim2.new(1,-36,1,0);c.ValueLabel.ZIndex=4
    c.Arrow=text(c.Control,"⌄",Aroyn.Theme.Fonts.Label,Aroyn.Theme.Fonts.Medium,C.TextDim)
    c.Arrow.AnchorPoint=Vector2.new(0.5,0.5);c.Arrow.Position=UDim2.new(1,-16,0.5,0);c.Arrow.Size=UDim2.fromOffset(20,20)
    c.Arrow.TextXAlignment=Enum.TextXAlignment.Center;c.Arrow.ZIndex=4
    c.Scope:Connect(c.Control.Activated,function() if c.Opened then c:Close() else c:Open() end end)
    watchAvailability(c);c:Render()
    return c
end

-- END ADVANCED COMPONENTS
-- BEGIN ADVANCED 3B COMPONENTS
-- Phase 3B.1. Additive component types; approved Dropdown/Slider code is unchanged.
local Keybind=setmetatable({}, {__index=Component});Keybind.__index=Keybind
local ColorPicker=setmetatable({}, {__index=Component});ColorPicker.__index=ColorPicker
local Keys={Members={},Pressed={},Focused=true}
local function watch3B(c,refresh)
    local function observe()
        if not c.Scope.Alive then return end
        if c.AvailabilityScope then c.AvailabilityScope:Destroy() end
        c.AvailabilityScope=Scope.new()
        local node=c.Control
        while node do
            c.AvailabilityScope:Connect(node:GetAttributeChangedSignal("AroynInputBlocked"),refresh)
            c.AvailabilityScope:Connect(node:GetPropertyChangedSignal("Parent"),observe)
            if node:IsA("GuiObject") then c.AvailabilityScope:Connect(node:GetPropertyChangedSignal("Visible"),refresh) end
            if node:IsA("ScreenGui") then c.AvailabilityScope:Connect(node:GetPropertyChangedSignal("Enabled"),refresh) end
            node=node.Parent
        end
        refresh()
    end
    c.Scope:Connect(c.Root.AncestryChanged,function() if not c.Root.Parent then c:Destroy() else observe() end end)
    observe()
end
local function activation(c,active)
    if not c.Scope.Alive or not c.OnActivate then return end
    local ok,err=pcall(c.OnActivate,active,c.Value,c.Mode)
    if not ok then warn("Aroyn activation ("..c.Name.."): "..tostring(err)) end
end
local function keyValue(raw)
    if raw==nil or raw=="None" then return nil,true end
    local key=raw
    if type(raw)=="string" then
        local ok,value=pcall(function() return Enum.KeyCode[raw] end)
        if not ok then return nil,false end
        key=value
    end
    if typeof(key)~="EnumItem" or key.EnumType~=Enum.KeyCode then return nil,false end
    local n=key.Name
    if n=="Unknown" or n=="Escape" or n=="Backspace" or n=="Delete" or n:match("^Button")
        or n:match("^DPad") or n:match("^Thumbstick") then return nil,false end
    return key,true
end
function Keybind:_SetActive(value,notify)
    if self.Active==value then return end
    self.Active=value
    if self.Scope.Alive and self.ModeLabel then self.ModeLabel.Text=self.Mode..(value and " · On" or " · Off") end
    if notify~=false then activation(self,value) end
end
function Keybind:GetActive() return self.Active==true end
function Keybind:GetMode() return self.Mode end
function Keybind:IsCapturing() return Keys.Capture==self end
function Keybind:CancelCapture()
    if Keys.Capture==self then Keys.Capture=nil;self.CaptureError=nil;self:Render() end
    return self
end
function Keybind:BeginCapture()
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    if not available(self) or not InputService.KeyboardEnabled or not Keys.Focused or InputService:GetFocusedTextBox() then return false end
    if Keys.Capture==self then self:CancelCapture();return false end
    if Keys.Capture then Keys.Capture:CancelCapture() end
    -- Capture is exclusive across this library instance. Release any active Hold first.
    local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
    for _,c in ipairs(snapshot) do if c.Scope.Alive and c.Mode=="Hold" then c:_SetActive(false) end end
    if not available(self) then return false end -- A release callback may destroy the host.
    Keys.Capture=self;self.CaptureError=nil;self:Render()
    return true
end
function Keybind:GetValue()
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    return self.Value
end
function Keybind:SetValue(raw,notify)
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    if notify~=nil then bool(notify,"Notify") end
    local key,valid=keyValue(raw)
    if not valid then return self,false end
    self:CancelCapture()
    local changed=self.Value~=key
    if changed and self.Mode~="Always" then self:_SetActive(false) end
    if not self.Scope.Alive then return self,true end
    self.Value=key;self:Render()
    if changed and notify==true then invoke(self,key) end
    return self,true
end
function Keybind:Close()
    self:CancelCapture();self:_SetActive(false)
    return self
end
function Keybind:SetDisabled(value)
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    bool(value,"Disabled")
    if value then self:Close() end
    if not self.Scope.Alive then return self end -- Release callback may destroy this control/window.
    return Component.SetDisabled(self,value)
end
function Keybind:Render()
    if not self.Scope.Alive then return end
    Component.Render(self)
    local capture=self:IsCapturing()
    self.KeyLabel.Text=capture and (self.CaptureError or "Press a key...")
        or (InputService.KeyboardEnabled and (self.Value and self.Value.Name or "None") or "Keyboard required")
    self.KeyLabel.TextColor3=self.Disabled and Aroyn.Theme.Colors.TextDim or Aroyn.Theme.Colors.TextMuted
    self.ModeLabel.Text=self.Mode..(self.Active and " · On" or " · Off")
    if capture then self.Scope:Animate(self.Edge,{Transparency=Aroyn.Theme.Borders.Focus,Color=Aroyn.Theme.Colors.AccentSoft},0.14) end
    if self.Mode=="Always" then self:_SetActive(available(self) and Keys.Focused,not self.Initializing) end
end
function Keybind:Destroy()
    if not self.Scope.Alive or self.Destroying then return end
    self.Destroying=true;self:Close();Keys.Members[self]=nil
    if self.AvailabilityScope then self.AvailabilityScope:Destroy() end
    Component.Destroy(self)
    if not next(Keys.Members) and Keys.Scope then
        Keys.Scope:Destroy();Keys.Scope=nil;Keys.Capture=nil;table.clear(Keys.Pressed)
    end
end
local function keyHub()
    if Keys.Scope then return end
    Keys.Scope=Scope.new();Keys.Focused=true
    Keys.Scope:Connect(InputService.InputBegan,function(input,processed)
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        local key=input.KeyCode
        if Keys.Pressed[key] then return end
        Keys.Pressed[key]=true
        local capture=Keys.Capture
        if capture then
            if not available(capture) or InputService:GetFocusedTextBox() or not Keys.Focused then capture:CancelCapture();return end
            if key==Enum.KeyCode.Escape then capture:CancelCapture()
            elseif key==Enum.KeyCode.Backspace or key==Enum.KeyCode.Delete then capture:SetValue(nil,true)
            else
                local _,valid=keyValue(key)
                if valid then capture:SetValue(key,true)
                else capture.CaptureError="Unsupported key";capture:Render() end
            end
            return -- The capture key never activates any binding on this press.
        end
        if processed or not Keys.Focused or InputService:GetFocusedTextBox() then return end
        local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
        for _,c in ipairs(snapshot) do
            if available(c) and c.Value==key then
                if c.Mode=="Toggle" then c:_SetActive(not c.Active)
                elseif c.Mode=="Hold" then c:_SetActive(true) end
            end
        end
    end)
    Keys.Scope:Connect(InputService.InputEnded,function(input)
        if input.UserInputType~=Enum.UserInputType.Keyboard then return end
        Keys.Pressed[input.KeyCode]=nil
        local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
        for _,c in ipairs(snapshot) do if c.Scope.Alive and c.Mode=="Hold" and c.Value==input.KeyCode then c:_SetActive(false) end end
    end)
    Keys.Scope:Connect(InputService.TextBoxFocused,function()
        if Keys.Capture then Keys.Capture:CancelCapture() end
        local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
        for _,c in ipairs(snapshot) do if c.Scope.Alive and c.Mode=="Hold" then c:_SetActive(false) end end
    end)
    Keys.Scope:Connect(InputService.WindowFocusReleased,function()
        Keys.Focused=false;table.clear(Keys.Pressed)
        local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
        for _,c in ipairs(snapshot) do if c.Scope.Alive then c:Close() end end
    end)
    Keys.Scope:Connect(InputService.WindowFocused,function()
        Keys.Focused=true
        local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
        for _,c in ipairs(snapshot) do if c.Scope.Alive then c:Render() end end
    end)
    Keys.Scope:Connect(InputService:GetPropertyChangedSignal("KeyboardEnabled"),function()
        if not InputService.KeyboardEnabled then
            table.clear(Keys.Pressed)
            if Keys.Capture then Keys.Capture:CancelCapture() end
        end
        local snapshot={};for c in pairs(Keys.Members) do table.insert(snapshot,c) end
        for _,c in ipairs(snapshot) do
            if c.Scope.Alive then
                if not InputService.KeyboardEnabled and c.Mode~="Always" then c:_SetActive(false) end
                if c.Scope.Alive then c:Render() end
            end
        end
    end)
end
function Section:CreateKeybind(raw)
    local o=options(raw)
    local key,valid=keyValue(o.Default);assert(valid,"Aroyn: unsupported Keybind Default")
    local mode=o.Mode==nil and "Toggle" or o.Mode
    assert(mode=="Toggle" or mode=="Hold" or mode=="Always","Aroyn: invalid Keybind Mode")
    callback(o.OnActivate)
    local c=component(self,"Keybind",o);setmetatable(c,Keybind)
    c.Value=key;c.Mode=mode;c.OnActivate=o.OnActivate;c.Active=false;c.Initializing=true
    local C=Aroyn.Theme.Colors;local M=Aroyn.Theme.Metrics
    c.Control=create("TextButton",{Name="Keybind",Text="",AutoButtonColor=false,BorderSizePixel=0,
        BackgroundColor3=C.Surface2,AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.FieldWidth,M.Control),ZIndex=3},c.Root)
    rounded(c.Control);c.Edge=outline(c.Control)
    c.KeyLabel=text(c.Control,"",Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Medium,C.TextMuted)
    c.KeyLabel.Position=UDim2.fromOffset(8,0);c.KeyLabel.Size=UDim2.new(0.64,-8,1,0);c.KeyLabel.ZIndex=4
    c.ModeLabel=text(c.Control,"",Aroyn.Theme.Fonts.Small,Aroyn.Theme.Fonts.Regular,C.TextDim)
    c.ModeLabel.Position=UDim2.fromScale(0.64,0);c.ModeLabel.Size=UDim2.new(0.36,-8,1,0);c.ModeLabel.TextXAlignment=Enum.TextXAlignment.Right;c.ModeLabel.ZIndex=4
    Keys.Members[c]=true;keyHub();hover(c)
    c.Scope:Connect(c.Control.Activated,function() c:BeginCapture() end)
    watch3B(c,function()
        if not c.Scope.Alive then return end
        if not available(c) then c:Close()
        elseif c.Mode=="Always" then c:_SetActive(Keys.Focused,not c.Initializing) end
    end)
    c:Render();c.Initializing=false
    return c
end

local function colorValue(value)
    assert(typeof(value)=="Color3","Aroyn: color Value must be Color3")
    return Color3.new(math.clamp(finite(value.R,"Red"),0,1),math.clamp(finite(value.G,"Green"),0,1),math.clamp(finite(value.B,"Blue"),0,1))
end
local function channel(value) return math.floor(math.clamp(value,0,1)*255+0.5) end
local function hexColor(value) return string.format("#%02X%02X%02X",channel(value.R),channel(value.G),channel(value.B)) end
local function parseHex(raw)
    if type(raw)~="string" then return nil end
    local s=raw:match("^%s*#?(%x+)%s*$")
    if not s or (#s~=6 and #s~=3) then return nil end
    if #s==3 then s=s:gsub("(.)","%1%1") end
    return Color3.fromRGB(tonumber(s:sub(1,2),16),tonumber(s:sub(3,4),16),tonumber(s:sub(5,6),16))
end
function ColorPicker:GetValue()
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    return self.Value
end
function ColorPicker:GetHex() return hexColor(self:GetValue()) end
function ColorPicker:SetHex(raw,notify)
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    if notify~=nil then bool(notify,"Notify") end
    local color=parseHex(raw)
    if not color then return self,false end
    return self:SetValue(color,notify),true
end
function ColorPicker:_SetColor(color,notify,keepHSV)
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    if notify~=nil then bool(notify,"Notify") end
    color=colorValue(color)
    local previous=self.Value
    local changed=math.abs(previous.R-color.R)>1e-7 or math.abs(previous.G-color.G)>1e-7 or math.abs(previous.B-color.B)>1e-7
    self.Value=color
    if not keepHSV then
        local h,s,v=color:ToHSV()
        if s>0 then self.H=h end -- Keep the hue when gray/black has no defined hue.
        self.S=s;self.V=v
    end
    self:_RenderColor()
    if changed and notify==true then invoke(self,color) end
    return self
end
function ColorPicker:SetValue(color,notify) return self:_SetColor(color,notify,false) end
function ColorPicker:Render()
    if not self.Scope.Alive then return end
    Component.Render(self);self:_RenderColor()
end
function ColorPicker:_RenderColor()
    self.Swatch.BackgroundColor3=self.Value
    self.HexLabel.Text=hexColor(self.Value)
    self.HexLabel.TextColor3=self.Disabled and Aroyn.Theme.Colors.TextDim or Aroyn.Theme.Colors.TextMuted
    local pop=self.Popup
    if not pop or pop.Closing then return end
    pop.SV.BackgroundColor3=Color3.fromHSV(self.H,1,1)
    local size=pop.SV.AbsoluteSize
    pop.SVMarker.Position=UDim2.fromOffset(math.floor(self.S*size.X+0.5),math.floor((1-self.V)*size.Y+0.5))
    pop.HueMarker.Position=UDim2.new(0,math.floor(self.H*pop.Hue.AbsoluteSize.X+0.5),0.5,0)
    pop.Preview.BackgroundColor3=self.Value
    if not pop.Hex:IsFocused() then pop.Hex.Text=hexColor(self.Value) end
    for i,key in ipairs({"R","G","B"}) do if not pop.RGB[i]:IsFocused() then pop.RGB[i].Text=tostring(channel(self.Value[key])) end end
end
function ColorPicker:_StopColorDrag()
    self.Drag=nil
    for object,value in pairs(self.DragScroll or {}) do if object.Parent then Aroyn:_DesiredProperty(object,"ScrollingEnabled",value) end end
    self.DragScroll=nil
end
function ColorPicker:Close(instant)
    self.Opened=false;self:_StopColorDrag()
    local window=self.Section.Page.Window
    if window.PopupOwner==self then window.PopupOwner=nil end
    local pop=self.Popup
    if not pop then return self end
    local function dispose()
        pop.Scope:Destroy();pop.Portal:Destroy()
        if self.Popup==pop then self.Popup=nil end
    end
    pop.Dispose=dispose
    if instant or not self.Scope.Alive or Aroyn.MotionEnabled==false then
        pop.Closing=true
        if pop.Hex:IsFocused() then pop.Hex:ReleaseFocus(false) end
        for _,field in ipairs(pop.RGB) do if field:IsFocused() then field:ReleaseFocus(false) end end
        dispose()
    elseif not pop.Closing then
        pop.Closing=true
        for _,obj in ipairs(pop.Root:GetDescendants()) do
            if obj:IsA("GuiObject") then obj.Active=false end
            if obj:IsA("TextButton") then obj.Interactable=false end
            if obj:IsA("TextBox") then obj.TextEditable=false;if obj:IsFocused() then obj:ReleaseFocus(false) end end
        end
        pop.Root.Active=false;pop.Scroll.ScrollingEnabled=false
        pop.Scope:Animate(pop.Root,{Position=pop.Placement.Position,Size=UDim2.fromOffset(pop.Placement.Width,0)},0.16,dispose)
    end
    return self
end
function ColorPicker:IsOpen() return self.Opened==true end
function ColorPicker:SetDisabled(value)
    bool(value,"Disabled");if value then self:Close(true) end
    return Component.SetDisabled(self,value)
end
function ColorPicker:Destroy()
    if not self.Scope.Alive then return end
    if self.AvailabilityScope then self.AvailabilityScope:Destroy() end
    self:Close(true);Component.Destroy(self)
end
function ColorPicker:_PositionColorPopup(pop,animate)
    if self.Popup~=pop then return end
    if not available(self) then self:Close(true);return end
    local window=self.Section.Page.Window
    local rp,rs=window.Root.AbsolutePosition,window.Root.AbsoluteSize
    local origin,screenSize=pop.Portal.AbsolutePosition,pop.Portal.AbsoluteSize
    local left,top=math.max(rp.X+8,origin.X+8),math.max(rp.Y+8,origin.Y+8)
    local right,bottom=math.min(rp.X+rs.X-8,origin.X+screenSize.X-8),math.min(rp.Y+rs.Y-8,origin.Y+screenSize.Y-8)
    local p,s=self.Control.AbsolutePosition,self.Control.AbsoluteSize
    local node=self.Control.Parent
    while node do
        if node:IsA("GuiObject") and (node.ClipsDescendants or node:IsA("ScrollingFrame")) then
            local cp,cs=node.AbsolutePosition,node.AbsoluteSize
            if p.Y+s.Y<=cp.Y or p.Y>=cp.Y+cs.Y or p.X+s.X<=cp.X or p.X>=cp.X+cs.X then self:Close(true);return end
        end
        node=node.Parent
    end
    local width=math.floor(math.min(math.max(s.X,240),right-left))
    if width<192 then self:Close(true);return end
    local square=math.min(180,width-24);local desired=square+126
    local below,above=math.max(0,bottom-(p.Y+s.Y+5)),math.max(0,p.Y-5-top)
    local upwards=below<desired and above>below
    local height=math.floor(math.min(desired,upwards and above or below))
    if height<100 then self:Close(true);return end
    local x=math.floor(math.clamp(p.X,left,right-width)+0.5)
    local y=math.floor(math.clamp(upwards and p.Y-5-height or p.Y+s.Y+5,top,bottom-height)+0.5)
    local edgeY=y+(upwards and height or 0)
    local destination=UDim2.fromOffset(x-origin.X,edgeY-origin.Y)
    local previous=pop.Placement
    local directionChanged=previous and previous.Upwards~=upwards
    local changed=not previous or directionChanged or previous.X~=x or previous.EdgeY~=edgeY or previous.Width~=width or previous.Height~=height
    if not changed and not animate then return end
    local running=pop.Scope.Animations[pop.Root]~=nil;pop.Scope:Cancel(pop.Root)
    if not previous then
        pop.Root.AnchorPoint=Vector2.new(0,upwards and 1 or 0);pop.Root.Position=destination;pop.Root.Size=UDim2.fromOffset(width,0)
    elseif directionChanged then
        local currentPosition,currentSize=pop.Root.AbsolutePosition,pop.Root.AbsoluteSize
        pop.Root.AnchorPoint=Vector2.new(0,upwards and 1 or 0)
        pop.Root.Position=UDim2.fromOffset(currentPosition.X-origin.X,currentPosition.Y-origin.Y+(upwards and currentSize.Y or 0))
    end
    pop.Placement={Upwards=upwards,X=x,EdgeY=edgeY,Width=width,Height=height,Position=destination}
    -- Fixed-size color area: a short viewport scrolls content rather than distorting it.
    local offset=math.floor((width-square)/2)
    pop.Scroll.CanvasSize=UDim2.fromOffset(0,desired)
    pop.SV.Position=UDim2.fromOffset(offset,12);pop.SV.Size=UDim2.fromOffset(square,square)
    pop.Hue.Position=UDim2.fromOffset(offset,square+28);pop.Hue.Size=UDim2.fromOffset(square,12)
    pop.Preview.Position=UDim2.fromOffset(offset,square+56)
    pop.Hex.Position=UDim2.fromOffset(offset+34,square+52);pop.Hex.Size=UDim2.fromOffset(square-34,30)
    for i,field in ipairs(pop.RGB) do
        local column=math.floor(square/3);local px=offset+(i-1)*column
        pop.RGBLabels[i].Position=UDim2.fromOffset(px,square+90);pop.RGBLabels[i].Size=UDim2.fromOffset(14,30)
        field.Position=UDim2.fromOffset(px+15,square+90);field.Size=UDim2.fromOffset(column-19,30)
    end
    self:_RenderColor()
    local goal=UDim2.fromOffset(width,pop.Closing and 0 or height)
    if Aroyn.MotionEnabled~=false and (animate or directionChanged or running or pop.Closing) then
        pop.Scope:Animate(pop.Root,{Position=destination,Size=goal},pop.Closing and 0.16 or 0.18,pop.Closing and pop.Dispose or nil)
    else pop.Root.Position=destination;pop.Root.Size=goal end
end
function ColorPicker:Open()
    assert(self.Scope.Alive,"Aroyn: component is destroyed")
    if not available(self) or self.Opened then return self end
    local screen=assert(screenFor(self.Control),"Aroyn: ColorPicker requires a ScreenGui ancestor")
    local window=self.Section.Page.Window
    if window.PopupOwner then window.PopupOwner:Close(true) end
    if Keys.Capture then Keys.Capture:CancelCapture() end
    local pop=self.Popup
    if pop and pop.Closing then
        pop.Scope:Cancel(pop.Root);pop.Closing=false;self.Opened=true;window.PopupOwner=self
        pop.Root.Active=true;pop.Scroll.Active=true;pop.Scroll.ScrollingEnabled=true
        pop.SV.Active=true;pop.SV.Interactable=true;pop.HueHit.Active=true;pop.HueHit.Interactable=true
        pop.Hex.Active=true;pop.Hex.TextEditable=true
        for _,field in ipairs(pop.RGB) do field.Active=true;field.TextEditable=true end
        self:_RenderColor();self:_PositionColorPopup(pop,true);return self
    end
    self:Close(true)
    local z=window.Root.ZIndex+100
    for _,obj in ipairs(window.Root:GetDescendants()) do if obj:IsA("GuiObject") then z=math.max(z,obj.ZIndex+10) end end
    pop={Scope=Scope.new(),RGB={},RGBLabels={}}
    pop.Portal=create("Frame",{Name="AroynColorPickerPortal",BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),Active=false,ZIndex=z},screen)
    pop.Root=create("Frame",{Name="ColorPicker",BackgroundColor3=Aroyn.Theme.Colors.Surface,BorderSizePixel=0,ClipsDescendants=true,Active=true,ZIndex=z+1},pop.Portal)
    rounded(pop.Root);outline(pop.Root)
    pop.Scroll=create("ScrollingFrame",{Name="PickerScroll",BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),
        Active=true,ScrollingEnabled=true,CanvasSize=UDim2.fromOffset(0,306),ScrollBarThickness=3,ScrollBarImageColor3=Aroyn.Theme.Colors.TextDim,
        ScrollingDirection=Enum.ScrollingDirection.Y,ClipsDescendants=true,ZIndex=z+2},pop.Root)
    pop.SV=create("TextButton",{Name="SaturationValue",Text="",AutoButtonColor=false,BorderSizePixel=0,Active=true,ZIndex=z+3},pop.Scroll)
    rounded(pop.SV)
    local white=create("Frame",{Name="Saturation",BorderSizePixel=0,BackgroundColor3=Color3.new(1,1,1),Size=UDim2.fromScale(1,1),ZIndex=z+4},pop.SV);rounded(white)
    create("UIGradient",{Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,0),NumberSequenceKeypoint.new(1,1)})},white)
    local black=create("Frame",{Name="Value",BorderSizePixel=0,BackgroundColor3=Color3.new(0,0,0),Size=UDim2.fromScale(1,1),ZIndex=z+5},pop.SV);rounded(black)
    create("UIGradient",{Rotation=90,Transparency=NumberSequence.new({NumberSequenceKeypoint.new(0,1),NumberSequenceKeypoint.new(1,0)})},black)
    pop.SVMarker=create("Frame",{Name="ColorCursor",BackgroundColor3=Aroyn.Theme.Colors.Window,BackgroundTransparency=0.6,BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(10,10),ZIndex=z+6},pop.SV)
    rounded(pop.SVMarker,10);create("UIStroke",{Thickness=2,Color=Aroyn.Theme.Colors.Text,Transparency=0},pop.SVMarker)
    pop.Hue=create("Frame",{Name="Hue",BorderSizePixel=0,BackgroundColor3=Color3.new(1,1,1),ZIndex=z+3},pop.Scroll);rounded(pop.Hue,3)
    local hueKeys={};for i=0,6 do table.insert(hueKeys,ColorSequenceKeypoint.new(i/6,Color3.fromHSV(i/6,1,1))) end
    create("UIGradient",{Color=ColorSequence.new(hueKeys)},pop.Hue)
    pop.HueHit=create("TextButton",{Name="HueHitbox",Text="",AutoButtonColor=false,BackgroundTransparency=1,BorderSizePixel=0,Active=true,
        AnchorPoint=Vector2.new(0,0.5),Position=UDim2.fromScale(0,0.5),Size=UDim2.new(1,0,0,28),ZIndex=z+5},pop.Hue)
    pop.HueMarker=create("Frame",{Name="HueCursor",BackgroundColor3=Aroyn.Theme.Colors.Text,BorderSizePixel=0,AnchorPoint=Vector2.new(0.5,0.5),Size=UDim2.fromOffset(4,18),ZIndex=z+6},pop.Hue)
    rounded(pop.HueMarker,2);outline(pop.HueMarker)
    pop.Preview=create("Frame",{Name="Preview",BackgroundColor3=self.Value,BorderSizePixel=0,Size=UDim2.fromOffset(26,22),ZIndex=z+3},pop.Scroll);rounded(pop.Preview);outline(pop.Preview)
    local function field(label)
        local box=create("TextBox",{Name=label,Text="",PlaceholderText=label,ClearTextOnFocus=false,TextSize=Aroyn.Theme.Fonts.Description,
            TextColor3=Aroyn.Theme.Colors.Text,BackgroundColor3=Aroyn.Theme.Colors.Surface2,BorderSizePixel=0,TextXAlignment=Enum.TextXAlignment.Center,ZIndex=z+3},pop.Scroll)
        rounded(box);local stroke=outline(box)
        pop.Scope:Connect(box.Focused,function() pop.Scope:Animate(stroke,{Transparency=Aroyn.Theme.Borders.Focus},0.12) end)
        pop.Scope:Connect(box.FocusLost,function() pop.Scope:Animate(stroke,{Transparency=Aroyn.Theme.Borders.Normal},0.12) end)
        return box
    end
    pop.Hex=field("HEX")
    pop.Scope:Connect(pop.Hex.FocusLost,function()
        if self.Popup~=pop or pop.Closing then return end
        self:SetHex(pop.Hex.Text,true);self:_RenderColor()
    end)
    for i,key in ipairs({"R","G","B"}) do
        pop.RGBLabels[i]=text(pop.Scroll,key,Aroyn.Theme.Fonts.Small,Aroyn.Theme.Fonts.Regular,Aroyn.Theme.Colors.TextDim);pop.RGBLabels[i].ZIndex=z+3
        local box=field(key);pop.RGB[i]=box
        pop.Scope:Connect(box.FocusLost,function()
            if self.Popup~=pop or pop.Closing then return end
            local value=tonumber(box.Text)
            if value and value==value and math.abs(value)<math.huge then
                local channels={self.Value.R,self.Value.G,self.Value.B};channels[i]=math.clamp(math.floor(value+0.5),0,255)/255
                self:SetValue(Color3.new(channels[1],channels[2],channels[3]),true)
            end
            self:_RenderColor()
        end)
    end
    self.Popup=pop;self.Opened=true;window.PopupOwner=self
    local function drag(input,kind)
        if not available(self) or pop.Closing or self.Popup~=pop or self.Drag then return end
        if input.UserInputType~=Enum.UserInputType.MouseButton1 and input.UserInputType~=Enum.UserInputType.Touch then return end
        if InputService:GetFocusedTextBox() then InputService:GetFocusedTextBox():ReleaseFocus(false) end
        if self.Popup~=pop or pop.Closing then return end
        self.Drag={Input=input,Kind=kind};self.DragScroll={}
        for _,start in ipairs({pop.Scroll,self.Control}) do
            local node=start
            while node do
                if node:IsA("ScrollingFrame") and self.DragScroll[node]==nil then
                    self.DragScroll[node]=Aroyn:_DesiredValue(node,"ScrollingEnabled");Aroyn:_DesiredProperty(node,"ScrollingEnabled",false)
                end
                node=node.Parent
            end
        end
        self:_UpdateColorPointer(input)
    end
    pop.Scope:Connect(pop.SV.InputBegan,function(input) drag(input,"SV") end)
    pop.Scope:Connect(pop.HueHit.InputBegan,function(input) drag(input,"Hue") end)
    pop.Scope:Connect(InputService.InputChanged,function(input)
        if not self.Drag then return end
        if not available(self) or pop.Closing then self:_StopColorDrag();return end
        local owner=self.Drag.Input
        if input==owner or (owner.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement) then self:_UpdateColorPointer(input) end
    end)
    pop.Scope:Connect(InputService.InputEnded,function(input)
        local d=self.Drag
        if d and (input==d.Input or (d.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1)) then self:_StopColorDrag() end
    end)
    pop.Scope:Connect(InputService.InputBegan,function(input)
        if pop.Closing or self.Popup~=pop then return end
        if input.KeyCode==Enum.KeyCode.Escape then self:Close();return end
        if input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch then
            local point=Vector2.new(input.Position.X,input.Position.Y)
            if not contains(pop.Root,point) and not contains(self.Control,point) then self:Close() end
        end
    end)
    pop.Scope:Connect(InputService.WindowFocusReleased,function() self:Close(true) end)
    pop.Scope:Connect(pop.Portal.Destroying,function() self:Close(true) end)
    local function position() self:_PositionColorPopup(pop,false) end
    local node=self.Control
    while node do
        if node:IsA("GuiObject") then
            for _,prop in ipairs({"AbsolutePosition","AbsoluteSize"}) do pop.Scope:Connect(node:GetPropertyChangedSignal(prop),position) end
            if node:IsA("ScrollingFrame") then pop.Scope:Connect(node:GetPropertyChangedSignal("CanvasPosition"),position) end
        end
        node=node.Parent
    end
    pop.Scope:Connect(pop.Portal:GetPropertyChangedSignal("AbsoluteSize"),position)
    pop.Scope:Connect(pop.SV:GetPropertyChangedSignal("AbsoluteSize"),function() self:_RenderColor() end)
    self:_PositionColorPopup(pop,true)
    return self
end
function ColorPicker:_UpdateColorPointer(input)
    local d=self.Drag;local pop=self.Popup
    if not d or not pop or pop.Closing then return end
    local area=d.Kind=="Hue" and pop.Hue or pop.SV
    local p,s=area.AbsolutePosition,area.AbsoluteSize
    if s.X<=0 or s.Y<=0 then return end
    -- Same native pointer coordinate space as AbsolutePosition; no second inset subtraction.
    local x=math.clamp((input.Position.X-p.X)/s.X,0,1)
    if d.Kind=="Hue" then self.H=x else self.S=x;self.V=1-math.clamp((input.Position.Y-p.Y)/s.Y,0,1) end
    self:_SetColor(Color3.fromHSV(self.H,self.S,self.V),true,true)
end
function Section:CreateColorPicker(raw)
    local o=options(raw);local initial=colorValue(o.Default==nil and Aroyn.Theme.Colors.Text or o.Default)
    local c=component(self,"ColorPicker",o);setmetatable(c,ColorPicker)
    c.Value=initial;c.H,c.S,c.V=initial:ToHSV()
    local C=Aroyn.Theme.Colors;local M=Aroyn.Theme.Metrics
    c.Control=create("TextButton",{Name="ColorPicker",Text="",AutoButtonColor=false,BackgroundColor3=C.Surface2,BorderSizePixel=0,
        AnchorPoint=Vector2.new(1,0),Position=UDim2.new(1,0,0,0),Size=UDim2.fromOffset(M.FieldWidth,M.Control),ZIndex=3},c.Root)
    rounded(c.Control);c.Edge=outline(c.Control)
    c.Swatch=create("Frame",{Name="ColorSwatch",BorderSizePixel=0,BackgroundColor3=initial,Position=UDim2.fromOffset(7,6),Size=UDim2.fromOffset(22,18),ZIndex=4},c.Control)
    rounded(c.Swatch);outline(c.Swatch)
    c.HexLabel=text(c.Control,"",Aroyn.Theme.Fonts.Description,Aroyn.Theme.Fonts.Medium,C.TextMuted)
    c.HexLabel.Position=UDim2.fromOffset(38,0);c.HexLabel.Size=UDim2.new(1,-48,1,0);c.HexLabel.ZIndex=4
    hover(c)
    c.Scope:Connect(c.Control.Activated,function() if c.Opened then c:Close() else c:Open() end end)
    watch3B(c,function() if c.Scope.Alive and not available(c) then c:Close(true) end end);c:Render()
    return c
end

-- END ADVANCED 3B COMPONENTS
function Section:Reflow()
    local y=28
    for _,c in ipairs(self.Components) do c.Root.Position=UDim2.fromOffset(0,y);y+=c.Root.Size.Y.Offset+Aroyn.Theme.Metrics.Gap end
    self.Root.Size=UDim2.new(1,0,0,math.max(28,y-Aroyn.Theme.Metrics.Gap))
end
function Section:Destroy()
    if not self.Scope.Alive then return end
    self.Scope:Destroy()
    for _,c in ipairs(table.clone(self.Components)) do c:Destroy() end
    remove(self.Page.Sections,self);self.Root:Destroy()
end
function Page:CreateSection(raw)
    assert(self.Scope.Alive,"Aroyn: page is destroyed")
    local o=options(raw);local title=name(o.Title)
    local section=setmetatable({Page=self,Components={},Scope=Scope.new()},Section)
    section.Root=create("Frame",{Name="Section_"..title,BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.new(1,0,0,28),LayoutOrder=#self.Sections+1},self.Root)
    section.Title=text(section.Root,title,Aroyn.Theme.Fonts.Section,Aroyn.Theme.Fonts.Semibold,Aroyn.Theme.Colors.Text)
    section.Title.Size=UDim2.new(1,0,0,22)
    section.Scope:Connect(section.Root.Destroying,function() section:Destroy() end)
    table.insert(self.Sections,section)
    return section
end
function Page:Select() self.Window:SelectPage(self.Name);return self end
function Page:Destroy()
    if not self.Scope.Alive then return end
    self.Scope:Destroy()
    for _,section in ipairs(table.clone(self.Sections)) do section:Destroy() end
    remove(self.Window.Pages,self);self.Window.ByName[self.Name]=nil
    if self.Navigation then self.Navigation:Destroy() end
    self.Root:Destroy()
    self.Window:ReflowNavigation()
    if self.Window.Scope.Alive and self.Window.Selected==self then
        self.Window.Selected=nil
        if self.Window.Pages[1] then self.Window:SelectPage(self.Window.Pages[1].Name) end
    end
end
function Window:ReflowNavigation()
    for i,page in ipairs(self.Pages) do if page.Navigation then page.Navigation.Position=UDim2.fromOffset(12,8+(i-1)*48) end end
    if self.Navigation then self.Navigation.CanvasSize=UDim2.fromOffset(0,#self.Pages*48+16) end
end
function Window:CreatePage(raw)
    assert(self.Scope.Alive,"Aroyn: window is destroyed")
    local o=options(raw);local title=name(o.Name)
    assert(not self.ByName[title],"Aroyn: duplicate page "..title)
    local icon=o.Icon or "components"
    assert(Aroyn.Icons[icon],"Aroyn: unknown icon "..tostring(icon))
    local page=setmetatable({Window=self,Name=title,Sections={},Scope=Scope.new()},Page)
    page.Root=create("ScrollingFrame",{Name="Page_"..title,BackgroundTransparency=1,BorderSizePixel=0,
        Position=self.PagePosition,Size=self.PageSize,Visible=false,Active=true,
        AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.fromOffset(0,0),
        ScrollBarThickness=3,ScrollBarImageColor3=Aroyn.Theme.Colors.TextDim,ScrollingDirection=Enum.ScrollingDirection.Y},self.PageSurface or self.Content)
    create("UIPadding",{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,8),PaddingBottom=UDim.new(0,8)},page.Root)
    create("UIListLayout",{Padding=UDim.new(0,12),SortOrder=Enum.SortOrder.LayoutOrder},page.Root)
    if self.PageHeader then
        local heading=text(page.Root,title,Aroyn.Theme.Fonts.Page,Aroyn.Theme.Fonts.Semibold,Aroyn.Theme.Colors.Text)
        heading.LayoutOrder=0;heading.Size=UDim2.new(1,0,0,32)
    end
    if self.Navigation then
        page.Navigation=create("TextButton",{Name="Navigate_"..title,Text="",AutoButtonColor=false,BorderSizePixel=0,
            BackgroundColor3=Aroyn.Theme.Colors.Hover,BackgroundTransparency=1,Size=UDim2.fromOffset(40,40)},self.Navigation)
        rounded(page.Navigation,7)
        page.Icon=Aroyn:CreateIcon(page.Navigation,icon)
        page.Icon.AnchorPoint=Vector2.new(0.5,0.5);page.Icon.Position=UDim2.fromScale(0.5,0.5)
        page.Indicator=create("Frame",{BorderSizePixel=0,BackgroundColor3=Aroyn.Theme.Colors.Text,
            BackgroundTransparency=1,Position=UDim2.fromOffset(0,6),Size=UDim2.new(0,2,1,-12)},page.Navigation)
        rounded(page.Indicator,1)
        page.Scope:Connect(page.Navigation.Activated,function() self:SelectPage(title) end)
        page.Scope:Connect(page.Navigation.MouseEnter,function()
            if self.Selected~=page then page.Scope:Animate(page.Navigation,{BackgroundTransparency=0.55}) end
        end)
        page.Scope:Connect(page.Navigation.MouseLeave,function() self:RenderNavigation() end)
    end
    table.insert(self.Pages,page);self.ByName[title]=page
    page.Scope:Connect(page.Root.Destroying,function() page:Destroy() end)
    self:ReflowNavigation()
    if not self.Selected then self:SelectPage(title,false) end
    return page
end
function Window:RenderNavigation()
    for _,page in ipairs(self.Pages) do
        if page.Navigation then
            page.Scope:Animate(page.Navigation,{BackgroundTransparency=self.Selected==page and 0.45 or 1})
            page.Scope:Animate(page.Icon,{ImageColor3=self.Selected==page and Aroyn.Theme.Colors.Text or Aroyn.Theme.Colors.TextDim},0.15)
            page.Scope:Animate(page.Indicator,{BackgroundTransparency=self.Selected==page and 0 or 1,
                Position=UDim2.fromOffset(0,self.Selected==page and 6 or 12),
                Size=UDim2.new(0,2,1,self.Selected==page and -12 or -24)},0.15)
        end
    end
end
function Window:SelectPage(title, notify)
    assert(self.Scope.Alive,"Aroyn: window is destroyed")
    local page=assert(self.ByName[title],"Aroyn: unknown page "..tostring(title))
    if self.PopupOwner then self.PopupOwner:Close(true) end
    self.Selected=page
    local function apply() for _,item in ipairs(self.Pages) do item.Root.Visible=item==page end end
    if self.PageMotion then self.PageMotion:Select(title,apply,self.PageMotion.Current==nil) else apply() end
    self:RenderNavigation()
    if notify~=false and self.OnSelectPage then
        local ok,err=pcall(self.OnSelectPage,title)
        if not ok then warn("Aroyn page callback: "..tostring(err)) end
    end
    return page
end
function Window:Destroy()
    if not self.Scope.Alive then return end
    self.Scope:Destroy()
    for _,page in ipairs(table.clone(self.Pages)) do page:Destroy() end
    self.Selected=nil
    if self.PageMotion then self.PageMotion:Destroy() end
    if self.Collapse then self.Collapse:Destroy() end
    if self.PageSurface then self.PageSurface:Destroy() end
    if self.Owner.Mounts[self.Root]==self then self.Owner.Mounts[self.Root]=nil end
    if self.OwnRoot then self.OwnRoot:Destroy() end
end
function Aroyn:AttachWindow(raw)
    local o=options(raw)
    assert(typeof(o.Root)=="Instance" and o.Root:IsA("GuiObject"),"Aroyn: Root must be GuiObject")
    assert(typeof(o.Content)=="Instance" and o.Content:IsA("GuiObject"),"Aroyn: Content must be GuiObject")
    callback(o.OnSelectPage)
    assert(o.Navigation==nil or (typeof(o.Navigation)=="Instance" and o.Navigation:IsA("ScrollingFrame")),"Aroyn: Navigation must be ScrollingFrame")
    assert(o.PagePosition==nil or typeof(o.PagePosition)=="UDim2","Aroyn: PagePosition must be UDim2")
    assert(o.PageSize==nil or typeof(o.PageSize)=="UDim2","Aroyn: PageSize must be UDim2")
    if o.PageHeader~=nil then bool(o.PageHeader,"PageHeader") end
    self.Mounts=self.Mounts or setmetatable({},{__mode="k"})
    local previous=self.Mounts[o.Root]
    if previous and previous.Scope.Alive then
        assert(not previous.OwnRoot,"Aroyn: cannot attach twice to a library-owned window")
        previous:Destroy()
    end
    local window=setmetatable({Owner=self,Root=o.Root,Content=o.Content,Navigation=o.Navigation,Pages={},ByName={},
        Scope=Scope.new(),OnSelectPage=o.OnSelectPage,PagePosition=o.PagePosition or UDim2.fromOffset(12,12),
        PageSize=o.PageSize or UDim2.new(1,-24,1,-24),PageHeader=o.PageHeader~=false},Window)
    window.Scope:Connect(o.Root.Destroying,function() window:Destroy() end)
    self.Mounts[o.Root]=window
    return window
end
function Window:SetMinimized(value)
    assert(self.Scope.Alive and self.Restore,"Aroyn: attached window owns its minimize behavior")
    self.Minimized=bool(value,"Minimized")
    if value and self.PopupOwner then self.PopupOwner:Close(true) end
    self.Collapse:Set(value)
    return self
end
function Aroyn:CreateWindow(raw)
    local o=options(raw);local C=self.Theme.Colors;local M=self.Theme.Metrics
    assert(typeof(o.Parent)=="Instance","Aroyn: Parent is required (choose it outside the library)")
    assert(o.Size==nil or typeof(o.Size)=="UDim2","Aroyn: Size must be UDim2")
    local title=o.Title or "AROYN";name(title)
    local id=o.Id or "AroynUI";name(id)
    assert(o.Logo==nil or type(o.Logo)=="string","Aroyn: Logo must be string")
    local guiName="AroynUI_"..id
    local previous=o.Parent:FindFirstChild(guiName)
    if previous then
        assert(previous:GetAttribute("AroynUIOwned")==true,"Aroyn: another object uses Id "..id)
        previous:Destroy()
    end
    local screen=create("ScreenGui",{Name=guiName,ResetOnSpawn=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling,
        DisplayOrder=1000001},o.Parent)
    screen:SetAttribute("AroynUIOwned",true)
    local root=create("Frame",{Name="Window",BackgroundColor3=C.Window,BorderSizePixel=0,
        AnchorPoint=Vector2.zero,Size=o.Size or UDim2.fromOffset(680,440),ClipsDescendants=true},screen)
    root.Position=UDim2.new(0.5-root.Size.X.Scale/2,-root.Size.X.Offset/2,0.5-root.Size.Y.Scale/2,-root.Size.Y.Offset/2)
    -- Preserve centering/scale-based positioning, but settle on whole screen pixels.
    local function snapPosition()
        if not root.Parent then return end
        local p,position=root.AbsolutePosition,root.Position
        root.Position=UDim2.new(position.X.Scale,position.X.Offset+math.floor(p.X+0.5)-p.X,
            position.Y.Scale,position.Y.Offset+math.floor(p.Y+0.5)-p.Y)
    end
    task.defer(snapPosition)
    rounded(root,M.WindowRadius);outline(root)
    local sizeConstraint=create("UISizeConstraint",{MinSize=Vector2.new(440,0)},root)
    local header=create("Frame",{Name="Header",Active=true,BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.new(1,0,0,M.Header)},root)
    local cap=create("Frame",{BorderSizePixel=0,BackgroundColor3=C.Header,Size=UDim2.new(1,0,0,M.Header)},header)
    rounded(cap,M.WindowRadius)
    local bottomFill=create("Frame",{BorderSizePixel=0,BackgroundColor3=C.Header,Position=UDim2.fromOffset(0,M.WindowRadius),
        Size=UDim2.new(1,0,0,M.Header-M.WindowRadius)},header)
    local wordmark=text(header,title,self.Theme.Fonts.Brand,self.Theme.Fonts.Semibold,C.Text)
    wordmark.Position=UDim2.fromOffset(o.Logo and 48 or 16,14);wordmark.Size=UDim2.new(1,-150,0,24)
    local headerLogo
    if o.Logo then headerLogo=create("ImageLabel",{BackgroundTransparency=1,Image=o.Logo,ImageColor3=C.Text,
        ScaleType=Enum.ScaleType.Fit,Position=UDim2.fromOffset(12,10),Size=UDim2.fromOffset(32,32)},header) end
    local chrome=self:_Surface(root,{Name="WindowChrome",Size=root.Size})
    rounded(chrome,M.WindowRadius)
    local nav=create("ScrollingFrame",{Name="Navigation",BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.fromOffset(0,M.Header),Size=UDim2.new(0,M.Rail,1,-M.Header-8),
        Active=true,CanvasSize=UDim2.fromOffset(0,0),ScrollBarThickness=0,ScrollingDirection=Enum.ScrollingDirection.Y},chrome)
    local content=create("Frame",{Name="Content",BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.fromOffset(M.Rail,M.Header),Size=UDim2.new(1,-M.Rail,1,-M.Header)},chrome)
    local window=self:AttachWindow({Root=root,Content=content,Navigation=nav})
    window.OwnRoot=screen
    window.Chrome=chrome
    window.PageSurface=self:_Surface(content,{Name="PageMotion",Size=UDim2.fromScale(1,1)})
    window.PageMotion=self:_PageMotion(window.PageSurface)
    local floating=create("ImageButton",{Name="MinimizedLauncher",Active=true,AutoButtonColor=false,
        BackgroundColor3=C.Window,BackgroundTransparency=0,BorderSizePixel=0,Image="",
        Size=UDim2.fromOffset(48,48),Visible=false,ZIndex=20},screen)
    rounded(floating,9);outline(floating)
    local floatingLogo=create("ImageLabel",{Name="Logo",BackgroundTransparency=1,Image=o.Logo or "",ImageColor3=C.Text,
        Position=UDim2.fromOffset(10,10),Size=UDim2.fromOffset(28,28),ScaleType=Enum.ScaleType.Fit,ZIndex=21},floating)
    window.Restore=floating
    window.Collapse=self:_Collapse(root,chrome,M.Header,function() bottomFill.Visible=true end,floating,{
        Restore=function() window:SetMinimized(false) end,Logo=floatingLogo,
        BrandLogo=headerLogo,BrandText=wordmark,Header=cap})
    window.Collapse.Before=function() window.PageMotion:SetHidden(true) end
    window.Collapse.After=function(value) if not value then window.PageMotion:SetHidden(false) end end
    window.Scope:Connect(screen.Destroying,function() window:Destroy() end)
    local function titleControl(label,x)
        local button=create("TextButton",{Text=label,TextSize=16,TextColor3=C.TextMuted,AutoButtonColor=false,
            BackgroundColor3=C.Hover,BackgroundTransparency=1,BorderSizePixel=0,AnchorPoint=Vector2.new(1,0),
            Position=UDim2.new(1,x,0,10),Size=UDim2.fromOffset(34,32),ZIndex=3},header)
        rounded(button)
        window.Scope:Connect(button.MouseEnter,function() window.Scope:Animate(button,{BackgroundTransparency=0}) end)
        window.Scope:Connect(button.MouseLeave,function() window.Scope:Animate(button,{BackgroundTransparency=1}) end)
        return button
    end
    window.Minimize=titleControl("—",-44);window.Close=titleControl("×",-6)
    window.Scope:Connect(window.Minimize.Activated,function() window:SetMinimized(true) end)
    window.Scope:Connect(window.Close.Activated,function() window:Destroy() end)
    local drag
    local function inside(object,point)
        if not object.Visible then return false end
        local p,s=object.AbsolutePosition,object.AbsoluteSize
        return point.X>=p.X and point.X<=p.X+s.X and point.Y>=p.Y and point.Y<=p.Y+s.Y
    end
    window.Scope:Connect(header.InputBegan,function(input)
        if (input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch)
            and root.Visible and not window.Collapse.Minimized and not InputService:GetFocusedTextBox()
            and not window.Collapse.Busy and not inside(window.Close,input.Position) and not inside(window.Minimize,input.Position) then
            drag={Input=input,Start=input.Position,Position=root.Position}
        end
    end)
    window.Scope:Connect(InputService.InputChanged,function(input)
        if drag and (input==drag.Input or (drag.Input.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseMovement)) then
            local delta=input.Position-drag.Start
            root.Position=UDim2.new(drag.Position.X.Scale,drag.Position.X.Offset+delta.X,drag.Position.Y.Scale,drag.Position.Y.Offset+delta.Y)
        end
    end)
    window.Scope:Connect(InputService.InputEnded,function(input)
        if drag and (input==drag.Input or (drag.Input.UserInputType==Enum.UserInputType.MouseButton1
            and input.UserInputType==Enum.UserInputType.MouseButton1)) then drag=nil;snapPosition() end
    end)
    window.Scope:Connect(InputService.WindowFocusReleased,function() if drag then drag=nil;snapPosition() end end)
    return window
end
-- BEGIN OVERLAYS
-- Phase 3B.3: screen-anchored toasts and measured dialogs. Native rendering only.
do
local Manager={};Manager.__index=Manager
local Toast={};Toast.__index=Toast
local Dialog={};Dialog.__index=Dialog
local serial=0
local C,F=Aroyn.Theme.Colors,Aroyn.Theme.Fonts
local GuiService=game:GetService("GuiService")
local TextService=game:GetService("TextService")
local function slideRight(position,x)
    return UDim2.new(position.X.Scale,position.X.Offset+x,position.Y.Scale,position.Y.Offset)
end
local function measure(h,value,size,face,width)
    h.Measurements=h.Measurements or {}
    local key=tostring(size).."/"..tostring(face.Weight).."/"..width.."/"..value
    if h.Measurements[key] then return h.Measurements[key] end
    if value=="" then return Vector2.zero end
    local params=Instance.new("GetTextBoundsParams")
    params.Text=value;params.Size=size;params.Font=face;params.Width=width;params.RichText=false
    local ok,bounds=pcall(function() return TextService:GetTextBoundsAsync(params) end)
    params:Destroy()
    if not ok then
        -- Older clients may lack FontFace measurement. The native legacy API remains the fallback.
        bounds=TextService:GetTextSize(value,size,Enum.Font.BuilderSans,Vector2.new(width,1000000))
        h.MeasurementFallback=true
    end
    h.Measurements[key]=bounds
    return bounds
end
local types={Info={"i",C.TextMuted},Success={"✓",Color3.fromRGB(145,173,151)},
    Warning={"!",Color3.fromRGB(186,166,125)},Error={"×",Color3.fromRGB(186,141,141)}}
local function call(fn,...)
    if not fn then return end
    local ok,err=pcall(fn,...);if not ok then warn("Aroyn overlay callback: "..tostring(err)) end
end
local function pointer(input)
    return input.UserInputType==Enum.UserInputType.MouseButton1 or input.UserInputType==Enum.UserInputType.Touch
end
local function cancelTimer(h)
    if h.Timer then pcall(task.cancel,h.Timer);h.Timer=nil end
end
local function optionalString(value,label)
    assert(value==nil or type(value)=="string","Aroyn: "..label.." must be a string")
    return value or ""
end
-- Modal and morph own independent boundary attributes, sharing reference-counted property locks.
local beforeModalBlocked=blocked
blocked=function(object)
    if beforeModalBlocked(object) then return true end
    while object do
        if object:GetAttribute("AroynModalBlocked") then return true end
        object=object.Parent
    end
    return false
end
function Manager:_LockObject(object)
    if not self.Alive or not self.Locked or self.LockedObjects[object] then return end
    local properties={}
    if object:IsA("TextButton") or object:IsA("ImageButton") then properties.Interactable=object.Interactable
    elseif object:IsA("TextBox") then properties.TextEditable=object.TextEditable
    elseif object:IsA("ScrollingFrame") then properties.ScrollingEnabled=object.ScrollingEnabled end
    if not next(properties) then return end
    local record=inputLocks[object]
    if not record then record={Count=0,Properties=properties};inputLocks[object]=record end
    record.Count+=1;self.LockedObjects[object]=true
    for key in pairs(properties) do object[key]=false end
    if object:IsA("TextBox") and InputService:GetFocusedTextBox()==object then object:ReleaseFocus() end
end
function Manager:_Gate(value)
    if self.Locked==value then return end
    self.Locked=value;self.Window.Root:SetAttribute("AroynModalBlocked",value)
    if value then
        for _,object in ipairs(self.Window.Root:GetDescendants()) do self:_LockObject(object) end
        if not self.Alive or not self.Locked then return end
        local keys={};for k in pairs(Keys.Members) do if k.Section.Page.Window==self.Window then table.insert(keys,k) end end
        for _,k in ipairs(keys) do if k.Scope.Alive then k:Close() end end
    else
        for object in pairs(self.LockedObjects) do
            local record=inputLocks[object]
            if record then
                record.Count-=1
                if record.Count==0 then
                    inputLocks[object]=nil
                    if object.Parent then
                        for key,v in pairs(record.Properties) do
                            local disabled=object:GetAttribute("AroynDisabled")
                            if disabled~=nil and key~="ScrollingEnabled" then v=not disabled end
                            object[key]=v==true
                        end
                    end
                end
            end
        end
        table.clear(self.LockedObjects)
        local keys={};for k in pairs(Keys.Members) do if k.Section.Page.Window==self.Window then table.insert(keys,k) end end
        for _,k in ipairs(keys) do if self.Alive and not self.Cancelling and k.Scope.Alive and k.Mode=="Always" then k:_SetActive(available(k) and Keys.Focused) end end
    end
end
function Manager:_Reason()
    if not self.Alive or not self.Window.Scope.Alive or not self.Window.Root.Parent then return "destroyed" end
    if self.Window.Minimized then return "minimized" end
    local node=self.Window.Root
    while node do
        if node:IsA("GuiObject") and not node.Visible or node:IsA("ScreenGui") and node.Enabled==false then return "hidden" end
        if node:GetAttribute("AroynInputBlocked") then return "input_blocked" end
        node=node.Parent
    end
    return nil
end
function Manager:_Observe()
    if self.Watch then self.Watch:Destroy() end
    self.Watch=Scope.new()
    local function refresh()
        local reason=self:_Reason()
        if reason then self:_Lifecycle(reason) else self:_Layout() end
    end
    local node=self.Window.Root
    while node do
        self.Watch:Connect(node:GetPropertyChangedSignal("Parent"),function() self:_Observe();refresh() end)
        self.Watch:Connect(node:GetAttributeChangedSignal("AroynInputBlocked"),refresh)
        if node:IsA("GuiObject") then self.Watch:Connect(node:GetPropertyChangedSignal("Visible"),refresh) end
        if node:IsA("ScreenGui") then self.Watch:Connect(node:GetPropertyChangedSignal("Enabled"),refresh) end
        node=node.Parent
    end
    local screen=screenFor(self.Window.Root)
    if screen then
        self.Portal.Parent=screen
        for _,property in ipairs({"ScreenInsets","IgnoreGuiInset"}) do
            self.Watch:Connect(screen:GetPropertyChangedSignal(property),function() self:_Layout();self:_PumpToasts() end)
        end
    end
end
function Manager.new(window)
    local screen=screenFor(window.Root);assert(screen,"Aroyn: overlays need a ScreenGui")
    local self=setmetatable({Window=window,Scope=Scope.new(),Toasts={},ToastQueue={},DialogQueue={},
        LockedObjects={},Locked=false,Alive=true},Manager)
    self.Portal=create("Frame",{Name="AroynOverlays",BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.fromScale(1,1),Active=false,ClipsDescendants=false,ZIndex=200},screen)
    self.Scope:Connect(self.Portal:GetPropertyChangedSignal("AbsoluteSize"),function() self:_Layout();self:_PumpToasts() end)
    self.Scope:Connect(self.Portal:GetPropertyChangedSignal("AbsolutePosition"),function() self:_Layout();self:_PumpToasts() end)
    local ok,insetsChanged=pcall(function() return GuiService:GetPropertyChangedSignal("TopbarInset") end)
    if ok then self.Scope:Connect(insetsChanged,function() self:_Layout();self:_PumpToasts() end) end
    self.Scope:Connect(window.Root.DescendantAdded,function(object) if self.Locked then self:_LockObject(object) end end)
    self.Scope:Connect(InputService.InputBegan,function(input)
        local h=self.ActiveDialog
        if h and input.KeyCode==Enum.KeyCode.Escape and h.Options.Cancelable then h:Close("escape") end
    end)
    self.Scope:Connect(window.Root.Destroying,function() self:Destroy() end)
    self:_Observe()
    return self
end
function Manager:_Bounds()
    local s=self.Portal.AbsoluteSize
    return math.max(1,math.floor(s.X)),math.max(1,math.floor(s.Y))
end
function Manager:_ToastGeometry()
    local left,top,right,bottom=self:_SafeBounds()
    local padding=math.min(20,math.floor(math.min(right-left,bottom-top)/4))
    local w=math.min(312,math.max(1,right-left-padding*2))
    return w,right-padding-w,bottom-padding,math.max(1,bottom-top-padding*2)
end
function Manager:_SafeBounds()
    local sw,sh=self:_Bounds();local left,top,right,bottom=0,0,sw,sh
    local screen=self.Portal.Parent
    local ok,safe,area=pcall(function()
        return GuiService:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets),GuiService:GetInsetArea(screen.ScreenInsets
            or (screen.IgnoreGuiInset and Enum.ScreenInsets.None or Enum.ScreenInsets.CoreUISafeInsets))
    end)
    if ok then
        -- GetInsetArea rectangles share Core UI coordinates; subtract the host's origin once.
        left=math.clamp(math.ceil(safe.Min.X-area.Min.X),0,sw-1)
        top=math.clamp(math.ceil(safe.Min.Y-area.Min.Y),0,sh-1)
        right=math.clamp(math.floor(safe.Max.X-area.Min.X),left+1,sw)
        bottom=math.clamp(math.floor(safe.Max.Y-area.Min.Y),top+1,sh)
    elseif screen.IgnoreGuiInset then
        local insetOK,tl,br=pcall(function() return GuiService:GetGuiInset() end)
        if insetOK then
            left=math.clamp(math.ceil(tl.X),0,sw-1);top=math.clamp(math.ceil(tl.Y),0,sh-1)
            right=math.clamp(sw-math.ceil(br.X),left+1,sw);bottom=math.clamp(sh-math.ceil(br.Y),top+1,sh)
        end
    end
    return left,top,right,bottom
end
function Manager:_Layout()
    if not self.Alive then return end
    if self.LayingOut then
        if self.ActiveDialog and self.ActiveDialog.LayoutBusy then self.ActiveDialog.LayoutPending=true end
        return
    end
    self.LayingOut=true
    local w,x,bottom,sh=self:_ToastGeometry()
    for _,h in ipairs(self.Toasts) do h.Height=math.min(h.Options.Description~="" and 86 or 52,sh) end
    local total=0;for _,h in ipairs(self.Toasts) do total+=h.Height+8 end
    -- A viewport shrink queues the tail again in its original order; no hidden active toasts.
    while #self.Toasts>1 and total-8>sh do
        local h=table.remove(self.Toasts);total-=h.Height+8
        if h.State=="Closing" then self:_FinishToast(h,h.Reason)
        else
            cancelTimer(h);h.Scope:Destroy();h.Root:Destroy();h.Root=nil;h.State="Queued"
            table.insert(self.ToastQueue,1,h)
        end
    end
    local y=bottom-total+8
    for _,h in ipairs(self.Toasts) do
        if h.Root then
            h.Root.Size=UDim2.fromOffset(w,h.Height)
            h.Target=UDim2.fromOffset(x,y)
            if h.State~="Closing" then h.Scope:Animate(h.Root,{Position=h.Target,BackgroundTransparency=0},0.2) end
            y+=h.Height+8
        end
    end
    if self.ActiveDialog and self.ActiveDialog.Root then self:_DialogLayout(self.ActiveDialog) end
    self.LayingOut=false
end
function Toast:GetState() return self.State end
function Toast:GetDismissReason() return self.Reason end
function Toast:Dismiss(reason) self.Manager:_DismissToast(self,reason or "programmatic",false);return self end
function Manager:_FinishToast(h,reason)
    if h.State=="Dismissed" then return end
    cancelTimer(h);h.State="Dismissed";h.Reason=reason
    remove(self.Toasts,h);remove(self.ToastQueue,h)
    if h.Scope then h.Scope:Destroy() end
    if h.Root then h.Root:Destroy();h.Root=nil end
    call(h.Options.OnDismiss,reason,h.Id)
    self:_Layout();self:_PumpToasts()
end
function Manager:_DismissToast(h,reason,instant)
    if h.State=="Dismissed" or h.State=="Closing" and not instant then return end
    cancelTimer(h)
    if instant or not h.Root then self:_FinishToast(h,reason);return end
    h.State="Closing";h.Reason=reason
    if h.CloseButton then h.CloseButton.Interactable=false end
    h.Scope:Animate(h.Root,{Position=slideRight(h.Root.Position,6),BackgroundTransparency=1},0.17,function() self:_FinishToast(h,reason) end)
    h.Scope:Animate(h.Edge,{Transparency=1},0.17)
    for _,label in ipairs(h.Labels) do h.Scope:Animate(label,{TextTransparency=1},0.17) end
    if h.Icon then h.Scope:Animate(h.Icon,{ImageTransparency=1},0.17) end
    h.Scope:Animate(h.Indicator,{BackgroundTransparency=1},0.17)
end
function Manager:_ShowToast(h)
    h.State="Visible";h.Scope=Scope.new();table.insert(self.Toasts,h)
    local w,x,bottom,sh=self:_ToastGeometry()
    h.Height=math.min(h.Options.Description~="" and 86 or 52,sh)
    h.Root=create("Frame",{Name=h.Id,BackgroundColor3=C.Surface2,BackgroundTransparency=1,BorderSizePixel=0,
        Active=false,ClipsDescendants=true,Size=UDim2.fromOffset(w,h.Height),Position=UDim2.fromOffset(x+8,bottom-h.Height),ZIndex=210},self.Portal)
    rounded(h.Root,6);h.Edge=outline(h.Root);h.Edge.Transparency=1
    local spec=types[h.Options.Type]
    local indicator=create("Frame",{BackgroundColor3=spec[2],BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromOffset(2,math.max(1,h.Height-24)),
        Position=UDim2.fromOffset(8,12),ZIndex=211},h.Root);rounded(indicator,1);h.Indicator=indicator
    h.Scope:Animate(indicator,{BackgroundTransparency=0},0.2)
    h.Labels={}
    if h.Options.Icon~="" then
        h.Icon=create("ImageLabel",{Image=h.Options.Icon,ImageColor3=spec[2],ImageTransparency=1,BackgroundTransparency=1,
            Position=UDim2.fromOffset(18,14),Size=UDim2.fromOffset(22,22),ScaleType=Enum.ScaleType.Fit,ZIndex=211},h.Root)
    else
        local icon=text(h.Root,spec[1],18,F.Semibold,spec[2]);icon.Position=UDim2.fromOffset(18,14);icon.Size=UDim2.fromOffset(22,22)
        icon.TextXAlignment=Enum.TextXAlignment.Center;table.insert(h.Labels,icon)
    end
    local title=text(h.Root,h.Options.Title,F.Label,F.Semibold,C.Text)
    title.Position=UDim2.fromOffset(48,13);title.Size=UDim2.new(1,h.Options.Dismissible and -80 or -60,0,22);table.insert(h.Labels,title)
    if h.Options.Description~="" then
        local desc=text(h.Root,h.Options.Description,F.Description,F.Regular,C.TextMuted)
        desc.Position=UDim2.fromOffset(48,37);desc.Size=UDim2.new(1,-60,0,36);desc.TextWrapped=true
        desc.TextYAlignment=Enum.TextYAlignment.Top;table.insert(h.Labels,desc)
    end
    if h.Options.Dismissible then
        h.CloseButton=create("TextButton",{Text="×",TextColor3=C.TextDim,TextSize=18,BackgroundTransparency=1,
            AutoButtonColor=false,BorderSizePixel=0,Position=UDim2.new(1,-32,0,10),Size=UDim2.fromOffset(26,28),ZIndex=213},h.Root)
        table.insert(h.Labels,h.CloseButton)
        h.Scope:Connect(h.CloseButton.Activated,function() h:Dismiss("manual") end)
    end
    for _,label in ipairs(h.Labels) do label.ZIndex=212;label.TextTransparency=1;h.Scope:Animate(label,{TextTransparency=0},0.2) end
    if h.Icon then h.Scope:Animate(h.Icon,{ImageTransparency=0},0.2) end
    h.Scope:Animate(h.Edge,{Transparency=Aroyn.Theme.Borders.Normal},0.2)
    h.Scope:Animate(h.Root,{BackgroundTransparency=0},0.2)
    self:_Layout()
    if h.Options.Duration>0 then
        h.Timer=task.delay(0.2+h.Options.Duration,function() h.Timer=nil;if self.Alive then h:Dismiss("timeout") end end)
    end
end
function Manager:_PumpToasts()
    if not self.Alive or self.Cancelling or self.LayingOut or self:_Reason() then return end
    local _,_,_,sh=self:_ToastGeometry()
    local occupied=0;for _,h in ipairs(self.Toasts) do occupied+=h.Height+8 end
    while #self.Toasts<3 and #self.ToastQueue>0 do
        local h=self.ToastQueue[1];local height=h.Options.Description~="" and 86 or 52
        if #self.Toasts>0 and occupied+height>sh then break end
        table.remove(self.ToastQueue,1);self:_ShowToast(h);occupied+=height+8
    end
end
function Manager:Notify(raw)
    local o=options(raw);local kind=o.Type or "Info";assert(types[kind],"Aroyn: invalid notification Type")
    local duration=o.Duration==nil and 4 or o.Duration
    assert(type(duration)=="number" and duration>=0 and duration<math.huge,"Aroyn: Duration must be finite and nonnegative")
    local dismissible=o.Dismissible==nil or bool(o.Dismissible,"Dismissible")
    local config={Title=name(o.Title),Description=optionalString(o.Description,"Description"),Icon=optionalString(o.Icon,"Icon"),
        Type=kind,Duration=duration,Dismissible=dismissible,OnDismiss=callback(o.OnDismiss)}
    serial+=1;local h=setmetatable({Id="AroynToast-"..serial,Manager=self,Options=config,State="Queued"},Toast)
    local reason=self.Cancelling and self.CancelReason or self:_Reason()
    if reason or #self.ToastQueue>=64 then self:_FinishToast(h,reason or "overflow")
    else table.insert(self.ToastQueue,h);self:_PumpToasts() end
    return h
end
function Dialog:GetState() return self.State end
function Dialog:GetDismissReason() return self.Reason end
function Dialog:GetAction() return self.Action end
function Dialog:Close(reason) self.Manager:_CloseDialog(self,reason or "programmatic",nil,false);return self end
function Manager:_DialogLayout(h)
    if h.LayoutBusy then h.LayoutPending=true;return false end
    h.LayoutBusy=true
    local left,top,right,bottom,width,vertical,actions,actionHeight,height,titleHeight,descriptionHeight,textWidth
    repeat
        h.LayoutPending=false
        left,top,right,bottom=self:_SafeBounds()
        local maxWidth=math.min(440,math.max(1,right-left-24))
        local naturalTitle=measure(h,h.Options.Title,F.Label,F.Semibold,1000000)
        local naturalDescription=measure(h,h.Options.Description,F.Description,F.Regular,1000000)
        actions=#h.Options.Actions
        width=math.min(maxWidth,math.ceil(math.max(280,naturalTitle.X+36,naturalDescription.X+38)))
        vertical=width<340
        -- Short landscape screens favour a horizontal row when every button still fits comfortably.
        if vertical and bottom-top-24<actions*38+80 and width>=32+actions*64+(actions-1)*8 then vertical=false end
        actionHeight=vertical and actions*30+(actions-1)*8 or 30
        textWidth=math.max(1,width-32)
        local title=measure(h,h.Options.Title,F.Label,F.Semibold,textWidth)
        local description=measure(h,h.Options.Description,F.Description,F.Regular,math.max(1,textWidth-6))
        if not self.Alive or not h.Scope.Alive or not h.Root.Parent or h.State=="Closed" then h.LayoutBusy=false;return false end
        titleHeight=math.max(F.Label,math.ceil(title.Y)+2)
        local fullDescription=h.Options.Description~="" and math.ceil(description.Y)+2 or 0
        local descriptionGap=fullDescription>0 and 10 or 0
        local fixed=16+descriptionGap+16+actionHeight+16
        local maxHeight=math.max(1,math.min(560,bottom-top-24))
        -- Keep actions reachable first; title and description get the remaining content budget.
        titleHeight=math.min(titleHeight,math.max(1,maxHeight-fixed-(fullDescription>0 and F.Description or 0)))
        descriptionHeight=math.min(fullDescription,math.max(0,maxHeight-fixed-titleHeight))
        height=math.min(maxHeight,fixed+titleHeight+descriptionHeight)
        h.DescriptionGap=descriptionGap;h.DescriptionFullHeight=fullDescription
    until not h.LayoutPending
    h.LayoutBusy=false
    h.Width=width;h.Height=height;h.Target=UDim2.fromOffset(left+math.floor((right-left-width)/2),top+math.floor((bottom-top-height)/2))
    h.Root.Size=UDim2.fromOffset(width,height)
    if h.Root.Visible and h.State~="Closing" then h.Scope:Animate(h.Root,{Position=h.Target,BackgroundTransparency=0},0.18) end
    h.Title.Size=UDim2.new(1,-32,0,titleHeight)
    h.Title.Position=UDim2.fromOffset(16,16)
    h.Scroll.Visible=h.Options.Description~=""
    h.Scroll.Position=UDim2.fromOffset(16,16+titleHeight+h.DescriptionGap);h.Scroll.Size=UDim2.new(1,-32,0,descriptionHeight)
    local gap=8;local bw=math.floor((width-32-gap*(actions-1))/actions)
    for i,b in ipairs(h.Buttons) do
        b.Size=UDim2.fromOffset(vertical and math.max(1,width-32) or math.max(1,bw),30)
        b.Position=UDim2.fromOffset(vertical and 16 or 16+(i-1)*(bw+gap),height-16-actionHeight+(vertical and (i-1)*38 or 0))
    end
    return true
end
function Manager:_FinishDialog(h)
    if h.State=="Closed" then return end
    h.State="Closed";remove(self.DialogQueue,h)
    if self.ActiveDialog==h then self.ActiveDialog=nil end
    if h.Scope then h.Scope:Destroy() end
    if h.Blocker then h.Blocker:Destroy();h.Blocker=nil;h.Root=nil end
    -- Retain the gate throughout callbacks and FIFO handoff, including callbacks that enqueue more dialogs.
    self.Finishing=true;call(h.Options.OnDismiss,h.Reason,h.Action);self.Finishing=false
    if self.Alive and not self.Cancelling then self:_PumpDialogs() end
    if not self.ActiveDialog then self:_Gate(false) end
end
function Manager:_CloseDialog(h,reason,action,instant)
    if h.State=="Closed" or h.State=="Closing" and not instant then return end
    local first=h.State~="Closing"
    h.Reason=h.Reason or reason;h.Action=h.Action or (action and action.Id)
    h.State="Closing"
    for _,b in ipairs(h.Buttons or {}) do b.Interactable=false end
    if first then
        -- Latch before calling user code. No confirmation is deferred to a timer or lifecycle event.
        if action then call(action.Callback)
        else call(h.Options.OnCancel,reason) end
    end
    if h.State=="Closed" then return end -- Callback may destroy the host.
    if instant or not h.Root then self:_FinishDialog(h);return end
    h.Scope:Animate(h.Edge,{Transparency=1},0.16)
    for _,label in ipairs(h.Labels) do
        local properties={TextTransparency=1}
        if label:IsA("TextButton") then properties.BackgroundTransparency=1 end
        h.Scope:Animate(label,properties,0.16)
    end
    for _,edge in ipairs(h.ButtonEdges) do h.Scope:Animate(edge,{Transparency=1},0.16) end
    h.Scope:Animate(h.Blocker,{BackgroundTransparency=1},0.16)
    h.Scope:Animate(h.Root,{Position=shifted(h.Root.Position,6),BackgroundTransparency=1},0.16,function() self:_FinishDialog(h) end)
end
function Manager:_ShowDialog(h)
    if self.Window.PopupOwner then self.Window.PopupOwner:Close(true) end
    self.ActiveDialog=h;h.State="Open";h.Scope=Scope.new();self:_Gate(true)
    if not self.Alive or h.State=="Closed" then return end
    h.Blocker=create("TextButton",{Name="ModalBlocker",Text="",AutoButtonColor=false,Active=true,
        BackgroundColor3=Color3.new(0,0,0),BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1),ZIndex=300},self.Portal)
    h.Root=create("Frame",{Name=h.Id,BackgroundColor3=C.Surface2,BackgroundTransparency=1,
        Active=true,Visible=false,ClipsDescendants=true,BorderSizePixel=0,ZIndex=301},h.Blocker)
    rounded(h.Root,7);h.Edge=outline(h.Root);h.Edge.Transparency=1
    h.Title=text(h.Root,h.Options.Title,F.Label,F.Semibold,C.Text)
    h.Title.Position=UDim2.fromOffset(16,12);h.Title.TextWrapped=true;h.Title.TextYAlignment=Enum.TextYAlignment.Top
    h.Scroll=create("ScrollingFrame",{Name="Description",BackgroundTransparency=1,BorderSizePixel=0,Active=true,
        ScrollingDirection=Enum.ScrollingDirection.Y,ScrollBarThickness=3,ScrollBarImageColor3=C.TextDim,
        CanvasSize=UDim2.fromOffset(0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y,ZIndex=302},h.Root)
    local desc=text(h.Scroll,h.Options.Description,F.Description,F.Regular,C.TextMuted)
    desc.Size=UDim2.new(1,-6,0,0);desc.AutomaticSize=Enum.AutomaticSize.Y;desc.TextWrapped=true
    desc.TextTruncate=Enum.TextTruncate.None;desc.TextYAlignment=Enum.TextYAlignment.Top
    h.Buttons={};h.ButtonEdges={};h.Labels={h.Title,desc}
    for _,action in ipairs(h.Options.Actions) do
        local b=create("TextButton",{Name=action.Id,Text=action.Text,TextSize=F.Description,AutoButtonColor=false,
            BorderSizePixel=0,BackgroundColor3=action.Primary and C.Accent or C.Surface3,
            TextColor3=action.Primary and C.Window or C.TextMuted,ZIndex=304},h.Root)
        rounded(b);local edge=outline(b);edge.Transparency=1;table.insert(h.ButtonEdges,edge)
        h.Scope:Animate(edge,{Transparency=Aroyn.Theme.Borders.Normal},0.18)
        table.insert(h.Buttons,b);table.insert(h.Labels,b)
        h.Scope:Connect(b.Activated,function() if h.State=="Open" then self:_CloseDialog(h,h.Options.Type=="Confirm" and action.Id=="cancel" and "cancel" or "action",action,false) end end)
        h.Scope:Connect(b.MouseEnter,function() if h.State=="Open" then h.Scope:Animate(b,{BackgroundColor3=action.Primary and C.Text or C.Hover},0.1) end end)
        h.Scope:Connect(b.MouseLeave,function() if h.State=="Open" then h.Scope:Animate(b,{BackgroundColor3=action.Primary and C.Accent or C.Surface3},0.1) end end)
    end
    if not self:_DialogLayout(h) or h.State~="Open" then return end
    h.Scope:Cancel(h.Root);h.Root.Position=shifted(h.Target,6);h.Root.Visible=true
    for _,label in ipairs(h.Labels) do label.ZIndex=304;label.TextTransparency=1;h.Scope:Animate(label,{TextTransparency=0},0.18) end
    h.Scope:Animate(h.Edge,{Transparency=Aroyn.Theme.Borders.Normal},0.18)
    h.Scope:Animate(h.Blocker,{BackgroundTransparency=0.65},0.18)
    h.Scope:Animate(h.Root,{Position=h.Target,BackgroundTransparency=0},0.18)
    h.Scope:Connect(h.Blocker.InputBegan,function(input)
        if pointer(input) and h.Options.OutsideDismiss and not contains(h.Root,input.Position) then h:Close("outside") end
    end)
end
function Manager:_PumpDialogs()
    if not self.Alive or self.Cancelling or self.Finishing or self.ActiveDialog or self:_Reason() then return end
    if #self.DialogQueue>0 then self:_ShowDialog(table.remove(self.DialogQueue,1)) end
end
function Manager:Dialog(raw)
    local o=options(raw);local kind=o.Type or "Alert"
    assert(kind=="Alert" or kind=="Confirm" or kind=="Custom","Aroyn: invalid dialog Type")
    local config={Title=name(o.Title),Description=optionalString(o.Description,"Description"),Type=kind,
        OnCancel=callback(o.OnCancel),OnDismiss=callback(o.OnDismiss),Actions={}}
    local function action(id,label,fn,primary)
        table.insert(config.Actions,{Id=name(id),Text=name(label),Callback=callback(fn),Primary=primary==true})
    end
    if kind=="Alert" then action("acknowledge",o.ButtonText or "OK",o.OnAcknowledge,true)
    elseif kind=="Confirm" then
        action("cancel",o.CancelText or "Cancel",function() call(config.OnCancel,"cancel") end,false)
        action("confirm",o.ConfirmText or "Confirm",o.OnConfirm,true)
    else
        assert(type(o.Actions)=="table" and #o.Actions>=1 and #o.Actions<=3,"Aroyn: Custom needs 1–3 Actions")
        local ids={}
        for _,a in ipairs(o.Actions) do
            options(a);assert(not ids[a.Id],"Aroyn: duplicate action Id");ids[name(a.Id)]=true
            if a.Primary~=nil then bool(a.Primary,"Primary") end
            action(a.Id,a.Text,a.Callback,a.Primary)
        end
    end
    config.Cancelable=o.Cancelable==nil and kind~="Alert" or o.Cancelable==true
    if o.Cancelable~=nil then bool(o.Cancelable,"Cancelable") end
    config.OutsideDismiss=o.OutsideDismiss==true
    if o.OutsideDismiss~=nil then bool(o.OutsideDismiss,"OutsideDismiss") end
    assert(not config.OutsideDismiss or config.Cancelable,"Aroyn: outside dismissal requires Cancelable")
    serial+=1;local h=setmetatable({Id="AroynDialog-"..serial,Manager=self,Options=config,State="Queued"},Dialog)
    -- Observe all current pages once: attached demos can change visibility without SelectPage.
    self.Pages=self.Pages or {}
    for _,page in ipairs(self.Window.Pages) do
        if not self.Pages[page] then
            self.Pages[page]=true
            self.Scope:Connect(page.Root:GetPropertyChangedSignal("Visible"),function()
                if not page.Root.Visible and self.ActiveDialog and self.ActiveDialog.Page==page then self:_CancelDialogs("page_changed") end
            end)
        end
        if page.Root.Visible then h.Page=page end
    end
    local reason=self.Cancelling and self.CancelReason or self:_Reason()
    if reason or #self.DialogQueue>=64 then self:_CloseDialog(h,reason or "overflow",nil,true)
    else table.insert(self.DialogQueue,h);self:_PumpDialogs() end
    return h
end
function Manager:_CancelDialogs(reason)
    local prior=self.Cancelling;self.Cancelling=true;self.CancelReason=reason
    local list=table.clone(self.DialogQueue);if self.ActiveDialog then table.insert(list,1,self.ActiveDialog) end
    for _,h in ipairs(list) do self:_CloseDialog(h,reason,nil,true) end
    self.Cancelling=prior;self.CancelReason=nil
end
function Manager:_Lifecycle(reason)
    if self.Cancelling then return end
    self.Cancelling=true;self.CancelReason=reason
    local list=table.clone(self.Toasts);for _,h in ipairs(self.ToastQueue) do table.insert(list,h) end
    for _,h in ipairs(list) do self:_DismissToast(h,reason,true) end
    self:_CancelDialogs(reason);self.Cancelling=false;self.CancelReason=nil
end
function Manager:Destroy()
    if not self.Alive then return end
    self.Alive=false;self:_Lifecycle("destroyed")
    self:_Gate(false);self.Scope:Destroy();if self.Watch then self.Watch:Destroy() end
    self.Portal:Destroy()
end
local function manager(window)
    assert(window.Scope.Alive,"Aroyn: window is destroyed")
    if not window.Overlays then window.Overlays=Manager.new(window) end
    return window.Overlays
end
function Window:Notify(raw) return manager(self):Notify(raw) end
function Window:Dialog(raw) return manager(self):Dialog(raw) end
local originalSelectPage=Window.SelectPage
function Window:SelectPage(title,notify)
    assert(self.Scope.Alive and self.ByName[title],"Aroyn: unknown page or destroyed window")
    if self.Overlays and self.Selected and self.Selected.Name~=title then self.Overlays:_CancelDialogs("page_changed") end
    return originalSelectPage(self,title,notify)
end
local originalSetMinimized=Window.SetMinimized
function Window:SetMinimized(value)
    bool(value,"Minimized")
    if value and self.Overlays then self.Overlays:_Lifecycle("minimized") end
    return originalSetMinimized(self,value)
end
local originalDestroy=Window.Destroy
function Window:Destroy()
    if self.Overlays then self.Overlays:Destroy() end
    return originalDestroy(self)
end
end

-- END OVERLAYS
-- BEGIN CONFIGURATION
-- Phase 4A. Central opt-in configuration layer; no UI, game logic or network.
-- Embedded after the approved components/overlays. Old constructors remain intact.
do
local Http=game:GetService("HttpService")
local Config={};Config.__index=Config
local MAX_BYTES,MAX_ENTRIES=262144,512
local function copy(value)
    if type(value)~="table" then return value end
    local out={};for k,v in pairs(value) do out[k]=copy(v) end;return out
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end
    return true
end
local function number(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function identifier(v)
    return type(v)=="string" and #v>=1 and #v<=64 and v:match("^[A-Za-z0-9][A-Za-z0-9_-]*$")~=nil
end
local function configName(v)
    if not identifier(v) then return nil end
    local n=v:lower()
    if n=="con" or n=="prn" or n=="aux" or n=="nul" or n:match("^com[1-9]$") or n:match("^lpt[1-9]$") then return nil end
    return n
end
local function mode(v) return v=="Toggle" or v=="Hold" or v=="Always" end
local function current(c)
    local value=c:GetValue()
    if c.Kind=="Keybind" then value={Key=value and value.Name or "None",Mode=c:GetMode()}
    elseif c.Kind=="ColorPicker" then value={R=value.R,G=value.G,B=value.B}
    elseif c.Kind=="Dropdown" and not c.Multi and value==nil then value=false end
    return {Type=c.Kind,Multi=c.Kind=="Dropdown" and c.Multi==true or nil,Value=copy(value)}
end
local function configOptions(raw)
    local o=options(raw)
    assert(o.Namespace==nil or configName(o.Namespace),"Aroyn: Config Namespace must be a safe identifier")
    assert(o.FileSystem==nil or type(o.FileSystem)=="table","Aroyn: Config FileSystem must be a table")
    assert(o.DefaultConfig==nil or configName(o.DefaultConfig),"Aroyn: invalid DefaultConfig")
    assert(o.AutoLoad==nil or type(o.AutoLoad)=="boolean" or configName(o.AutoLoad),"Aroyn: invalid AutoLoad")
    if o.AutoSave~=nil then bool(o.AutoSave,"AutoSave") end
    assert(o.AutoSaveConfig==nil or configName(o.AutoSaveConfig),"Aroyn: invalid AutoSaveConfig")
    assert(o.AutoSaveDelay==nil or (number(o.AutoSaveDelay) and o.AutoSaveDelay>=0.2 and o.AutoSaveDelay<=60),
        "Aroyn: AutoSaveDelay must be 0.2..60 seconds")
    return o
end
function Config.new(window,raw)
    local o=configOptions(raw)
    local fs=o.FileSystem or {isfolder=isfolder,makefolder=makefolder,isfile=isfile,
        readfile=readfile,writefile=writefile,delfile=delfile,listfiles=listfiles}
    local caps={};for _,key in ipairs({"isfolder","makefolder","isfile","readfile","writefile","delfile","listfiles"}) do caps[key]=type(fs[key])=="function" end
    local namespace=(o.Namespace or "default"):lower()
    local self=setmetatable({Window=window,Alive=true,Members={},Excluded={},Memory={},Known={},FileSystem=table.clone(fs),Capabilities=caps,
        Namespace=namespace,Path="AroynUILab/configs/"..namespace.."/",Mode=caps.readfile and caps.writefile and "File" or "Session",
        AutoSave=o.AutoSave==true,AutoSaveName=(o.AutoSaveConfig or o.DefaultConfig or "main"):lower(),Delay=o.AutoSaveDelay or 0.75},Config)
    window.Config=self
    if o.AutoLoad then self:Load(type(o.AutoLoad)=="string" and o.AutoLoad or o.DefaultConfig or "main",{}) end
    return self
end
function Config:_Result(ok,code,message,extra)
    local info=extra or {};info.Success=ok;info.Code=code;info.Message=message;info.Mode=self.Mode
    self.LastResult=copy(info);return ok,info
end
function Config:_Run(fn)
    if not self.Alive or not self.Window.Scope.Alive then return self:_Result(false,"Destroyed","Window is destroyed") end
    if self.Busy then return self:_Result(false,"Busy","Another configuration operation is in progress") end
    self.Busy=true;local ok,a,b=pcall(fn);self.Busy=false
    if not ok then return self:_Result(false,"OperationFailed",tostring(a)) end
    return a,b
end
function Config:_CancelSave()
    self.Revision=(self.Revision or 0)+1
    if self.SaveJob then pcall(task.cancel,self.SaveJob);self.SaveJob=nil end
end
function Config:_Changed(c)
    if not self.Alive or self.Applying or not self.Members[c.Flag] or not c.Scope.Alive then return end
    local record=self.Members[c.Flag];local value=current(c)
    if same(value,record.Last) then return end
    record.Last=value
    if not self.AutoSave then return end
    self:_ScheduleSave()
end
function Config:_ScheduleSave()
    self:_CancelSave();local revision=self.Revision
    self.SaveJob=task.delay(self.Delay,function()
        self.SaveJob=nil
        if not self.Alive or revision~=self.Revision then return end
        if self.Busy then self:_ScheduleSave();return end
        self:Save(self.AutoSaveName)
    end)
end
function Config:_EnsureFolder()
    local fs=self.FileSystem
    for _,p in ipairs({"AroynUILab","AroynUILab/configs",self.Path:sub(1,-2)}) do
        local exists=false
        if self.Capabilities.isfolder then
            local ok,v=pcall(fs.isfolder,p);if not ok then return false,"Folder check failed: "..tostring(v) end
            exists=v==true
        end
        if not exists and self.Capabilities.makefolder then
            local ok,err=pcall(fs.makefolder,p)
            if not ok then return false,"Folder creation failed: "..tostring(err) end
        elseif not exists and self.Capabilities.isfolder then return false,"Folder unavailable and makefolder is unsupported" end
        -- With neither folder API, use an already provisioned directory; writefile reports errors.
    end
    return true
end
function Config:_Read(path)
    if self.Capabilities.isfile then
        local ok,exists=pcall(self.FileSystem.isfile,path)
        if not ok then return nil,"ReadFailed",tostring(exists) end
        if not exists then return nil,"Missing","Configuration file does not exist" end
    end
    local ok,data=pcall(self.FileSystem.readfile,path)
    if not ok then
        local err=tostring(data);local lower=err:lower()
        if lower:find("no such file",1,true) or lower:find("does not exist",1,true) or lower:find("not found",1,true) then
            return nil,"Missing",err
        end
        return nil,"ReadFailed",err
    end
    if type(data)~="string" or data=="" then return nil,"Empty","Configuration file is empty" end
    if #data>MAX_BYTES then return nil,"TooLarge","Configuration exceeds 256 KiB" end
    return data
end
function Config:_Decode(data)
    local ok,v=pcall(Http.JSONDecode,Http,data)
    if not ok or type(v)~="table" then return nil,"Invalid JSON" end
    return v
end
function Config:_Names()
    if self.Mode=="Session" then
        local names={};for n in pairs(self.Memory) do table.insert(names,n) end;table.sort(names);return names
    end
    local found={}
    if self.Capabilities.listfiles then
        local ok,list=pcall(self.FileSystem.listfiles,self.Path:sub(1,-2))
        if not ok then
            if self.Capabilities.isfolder then
                local checked,exists=pcall(self.FileSystem.isfolder,self.Path:sub(1,-2))
                if checked and not exists then return {} end
            end
            return nil,"ListFailed",tostring(list)
        end
        if type(list)~="table" then return nil,"ListFailed","listfiles returned a non-table" end
        for _,path in pairs(list) do
            if type(path)=="string" then
                local p=path:gsub("\\","/"):gsub("^%./","")
                local leaf=p:match("([^/]+)$")
                local n=leaf and leaf:match("^([a-z0-9][a-z0-9_-]*)%.json$")
                local directory=leaf and p:sub(1,#p-#leaf):lower() or ""
                local wanted=self.Path:lower()
                if n and configName(n)==n and (p==leaf or directory==wanted or directory:sub(-(#wanted+1))=="/"..wanted) then found[n]=true end
            end
        end
    else
        local data,code,err=self:_Read(self.Path.."__index.json")
        if data then
            local index=self:_Decode(data)
            if not index or index.SchemaVersion~=1 or type(index.Names)~="table" then return nil,"IndexInvalid","Configuration index is corrupt" end
            for _,n in ipairs(index.Names) do if configName(n)==n then found[n]=true end end
        elseif code~="Missing" then return nil,code,err end
    end
    local names={};for n in pairs(found) do table.insert(names,n) end;table.sort(names);return names
end
function Config:_WriteIndex(names)
    if self.Capabilities.listfiles then return true end
    local ok,data=pcall(Http.JSONEncode,Http,{SchemaVersion=1,Names=names})
    if not ok then return false,tostring(data) end
    local wrote,err=pcall(self.FileSystem.writefile,self.Path.."__index.json",data)
    return wrote,wrote and nil or tostring(err)
end
function Config:State()
    local entries=copy(self.Pending or {})
    for flag,r in pairs(self.Members) do if r.Component.Scope.Alive then entries[flag]=current(r.Component) end end
    return {SchemaVersion=1,Namespace=self.Namespace,Values=entries}
end
local deferredRecord
function Config:Save(rawName)
    return self:_Run(function()
        local n=configName(rawName);if not n then return self:_Result(false,"InvalidName","Use 1..64 ASCII letters, digits, hyphen or underscore; start with a letter/digit") end
        self:_CancelSave()
        local state=self:State();local count=0
        for _,record in pairs(state.Values) do
            count+=1
            if count>MAX_ENTRIES or not deferredRecord(record) then
                return self:_Result(false,"InvalidState","State must contain at most 512 valid records; persisted text is limited to 16 KiB")
            end
        end
        local ok,data=pcall(Http.JSONEncode,Http,state)
        if not ok or type(data)~="string" or #data>MAX_BYTES then return self:_Result(false,"EncodeFailed","State cannot be encoded within 256 KiB") end
        if self.Mode=="Session" then self.Memory[n]=data;return self:_Result(true,"Saved","Saved in this window's memory only",{Name=n}) end
        local ready,err=self:_EnsureFolder();if not ready then return self:_Result(false,"FolderFailed",err) end
        local names,code,detail=self:_Names();if not names then return self:_Result(false,code,detail) end
        local wrote,why=pcall(self.FileSystem.writefile,self.Path..n..".json",data)
        if not wrote then return self:_Result(false,"WriteFailed",tostring(why)) end
        self.Known[n]=true;if not table.find(names,n) then table.insert(names,n);table.sort(names) end
        local indexed,errorText=self:_WriteIndex(names)
        if not indexed then return self:_Result(false,"IndexWriteFailed",errorText,{Name=n,FileSaved=true}) end
        return self:_Result(true,"Saved","Configuration saved to local file",{Name=n,Path=self.Path..n..".json"})
    end)
end
local function validRecord(c,r)
    if type(r)~="table" or r.Type~=c.Kind then return false,nil,"Component type mismatch" end
    local v=r.Value
    if c.Kind=="Toggle" then
        if type(v)~="boolean" then return false,nil,"Expected boolean" end
        return true,v
    elseif c.Kind=="Input" then
        if type(v)~="string" or #v>16384 then return false,nil,"Expected text up to 16 KiB" end
        return true,v
    elseif c.Kind=="Slider" then
        if not number(v) then return false,nil,"Expected finite number" end
        local value=c:_NormalizeSlider(v);return true,value,value~=v and "Slider clamped/quantized" or nil
    elseif c.Kind=="Dropdown" then
        if (r.Multi==true)~=c.Multi then return false,nil,"Dropdown selection mode mismatch" end
        if c.Multi then
            local ok,list=pcall(array,v,"Config selection")
            if not ok then return false,nil,"Expected selection array" end
            for _,item in ipairs(list) do if type(item)~="string" then return false,nil,"Expected string selections" end end
            local normalized=c:_NormalizeDropdown(v);return true,normalized,not same(v,normalized) and "Removed/duplicate options discarded" or nil
        end
        if v==false then return true,nil end
        if type(v)~="string" then return false,nil,"Expected selection string or false" end
        if not table.find(c.Options,v) then
            local default=c.ConfigDefault.Value;if default==false then default=nil end
            return true,c:_NormalizeDropdown(default),"Removed option reset to available default"
        end
        return true,v
    elseif c.Kind=="ColorPicker" then
        if type(v)~="table" then return false,nil,"Expected RGB object" end
        for _,k in ipairs({"R","G","B"}) do if not number(v[k]) or v[k]<0 or v[k]>1 then return false,nil,"RGB channels must be finite 0..1" end end
        return true,Color3.new(v.R,v.G,v.B)
    elseif c.Kind=="Keybind" then
        if type(v)~="table" or type(v.Key)~="string" or not mode(v.Mode) then return false,nil,"Expected stable key name and mode" end
        local key,ok=keyValue(v.Key);if not ok then return false,nil,"Unsupported key name" end
        return true,{Key=key,Mode=v.Mode}
    end
    return false,nil,"Unsupported component"
end
deferredRecord=function(r)
    if type(r)~="table" then return false end
    local v=r.Value
    if r.Type=="Toggle" then return type(v)=="boolean" end
    if r.Type=="Input" then return type(v)=="string" and #v<=16384 end
    if r.Type=="Slider" then return number(v) end
    if r.Type=="Dropdown" then
        if r.Multi==true then
            local ok,list=pcall(array,v,"Config selection");if not ok then return false end
            for _,item in ipairs(list) do if type(item)~="string" then return false end end
            return true
        end
        return v==false or type(v)=="string"
    end
    if r.Type=="Keybind" then
        if type(v)~="table" or type(v.Key)~="string" or not mode(v.Mode) then return false end
        local _,valid=keyValue(v.Key);return valid
    end
    if r.Type=="ColorPicker" then
        if type(v)~="table" then return false end
        for _,k in ipairs({"R","G","B"}) do if not number(v[k]) or v[k]<0 or v[k]>1 then return false end end
        return true
    end
    return false
end
function Config:_Apply(c,r,notify)
    local valid,value,warning=validRecord(c,r)
    if not valid then return false,warning end
    local before=current(c);local cb,activate=c.Callback,c.OnActivate
    c.Callback=nil;c.OnActivate=nil
    self.Applying=(self.Applying or 0)+1
    local ok,err=pcall(function()
        if c.Kind=="Keybind" then
            c:CancelCapture();c:_SetActive(false,false);c.Mode=value.Mode;c:SetValue(value.Key,false);c:Render()
        else c:SetValue(value,false) end
    end)
    self.Applying-=1;if self.Applying==0 then self.Applying=nil end
    c.Callback=cb;c.OnActivate=activate
    if not ok then return false,tostring(err) end
    if c.Scope.Alive and self.Members[c.Flag] then self.Members[c.Flag].Last=current(c) end
    if notify and c.Scope.Alive and not same(before,current(c)) then invoke(c,c:GetValue()) end
    return true,warning
end
function Config:Load(rawName,rawOptions)
    return self:_Run(function()
        local n=configName(rawName);if not n then return self:_Result(false,"InvalidName","Invalid configuration name") end
        local o=options(rawOptions);if o.InvokeCallbacks~=nil then bool(o.InvokeCallbacks,"InvokeCallbacks") end
        local data,code,err
        if self.Mode=="Session" then data=self.Memory[n];code="Missing";err="No configuration in this window's memory"
        else data,code,err=self:_Read(self.Path..n..".json") end
        if not data then return self:_Result(false,code,err) end
        local doc,decodeError=self:_Decode(data)
        if not doc then return self:_Result(false,"Corrupt",decodeError) end
        if doc.SchemaVersion~=1 then return self:_Result(false,"SchemaUnsupported","Only schema version 1 is supported") end
        if doc.Namespace~=self.Namespace or type(doc.Values)~="table" then return self:_Result(false,"InvalidDocument","Namespace or Values is invalid") end
        local count=0;for flag in pairs(doc.Values) do
            count+=1;if not identifier(flag) or count>MAX_ENTRIES then return self:_Result(false,"InvalidDocument","Invalid flags or too many values") end
        end
        self:_CancelSave();self.Pending={};self.PendingNotify=o.InvokeCallbacks==true
        local warnings,applied,deferred,skipped={},0,0,0
        for flag,r in pairs(doc.Values) do
            local member=self.Members[flag]
            if member then
                local loaded,warning=self:_Apply(member.Component,r,o.InvokeCallbacks==true)
                if loaded then applied+=1 else skipped+=1 end
                if warning then table.insert(warnings,flag..": "..warning) end
            elseif self.Excluded[flag] then
                skipped+=1;table.insert(warnings,flag..": excluded from persistence")
            elseif not deferredRecord(r) then
                skipped+=1;table.insert(warnings,flag..": unsupported or invalid deferred record")
            else
                -- Bounded decoded JSON only; preserved for controls registered after this call.
                self.Pending[flag]=copy(r);deferred+=1;table.insert(warnings,flag..": deferred (unregistered flag)")
            end
            if not self.Alive then break end
        end
        self.LoadedName=n;self.Known[n]=true
        return self:_Result(true,"Loaded","Restored UI state",{Name=n,Applied=applied,Deferred=deferred,Skipped=skipped,Warnings=warnings})
    end)
end
function Config:List()
    return self:_Run(function()
        local names,code,err=self:_Names()
        if not names then return self:_Result(false,code,err) end
        return self:_Result(true,"Listed","Configurations listed",{Names=names})
    end)
end
function Config:Delete(rawName)
    return self:_Run(function()
        local n=configName(rawName);if not n then return self:_Result(false,"InvalidName","Invalid configuration name") end
        if self.Mode=="Session" then
            if not self.Memory[n] then return self:_Result(false,"Missing","No such session configuration") end
            self.Memory[n]=nil
        else
            if not self.Capabilities.delfile then return self:_Result(false,"DeleteUnsupported","delfile is unavailable") end
            local names,code,err=self:_Names();if not names then return self:_Result(false,code,err) end
            local data,readCode,readError=self:_Read(self.Path..n..".json")
            if not data and readCode=="Missing" then return self:_Result(false,readCode,readError) end
            local ok,why=pcall(self.FileSystem.delfile,self.Path..n..".json")
            if not ok then return self:_Result(false,"DeleteFailed",tostring(why)) end
            if self.AutoSaveName==n then self:_CancelSave();self.AutoSave=false end
            if self.LoadedName==n then self.Pending=nil;self.LoadedName=nil end
            remove(names,n);self.Known[n]=nil
            local indexed,indexError=self:_WriteIndex(names)
            if not indexed then return self:_Result(false,"IndexWriteFailed",indexError,{Name=n,FileDeleted=true}) end
        end
        if self.AutoSaveName==n then self:_CancelSave();self.AutoSave=false end
        if self.LoadedName==n then self.Pending=nil;self.LoadedName=nil end
        return self:_Result(true,"Deleted","Configuration deleted",{Name=n})
    end)
end
function Config:Reset(rawOptions)
    return self:_Run(function()
        local o=options(rawOptions);if o.InvokeCallbacks~=nil then bool(o.InvokeCallbacks,"InvokeCallbacks") end
        self:_CancelSave();self.Pending=nil;self.LoadedName=nil
        local applied,warnings=0,{}
        local snapshot={};for flag,r in pairs(self.Members) do snapshot[flag]=r end
        for flag,r in pairs(snapshot) do
            if r.Component.Scope.Alive then
                local ok,err=self:_Apply(r.Component,r.Default,o.InvokeCallbacks==true)
                if ok then applied+=1 end;if err then table.insert(warnings,flag..": "..err) end
            end
        end
        -- Reset is not an autosave: saved configurations remain untouched until explicit save/edit.
        return self:_Result(true,"Reset","Registered controls reset to construction defaults",{Applied=applied,Warnings=warnings})
    end)
end
function Config:Register(c,flag)
    assert(not self.Members[flag] and not self.Excluded[flag],"Aroyn: duplicate configuration Flag "..flag)
    c.Flag=flag;c.ConfigDefault=current(c)
    local record={Component=c,Default=copy(c.ConfigDefault),Last=current(c)};self.Members[flag]=record
    local function wrap(method)
        local old=c[method]
        c[method]=function(control,...)
            local result=table.pack(old(control,...))
            if self.Alive and control.Scope.Alive then self:_Changed(control) end
            return table.unpack(result,1,result.n)
        end
    end
    wrap(c.Kind=="ColorPicker" and "_SetColor" or "SetValue")
    if c.Kind=="Dropdown" then wrap("SetOptions") end
    if c.Kind=="Keybind" then wrap("SetMode") end
    if c.Kind=="Input" then c.Scope:Connect(c.Control:GetPropertyChangedSignal("Text"),function() self:_Changed(c) end) end
    local oldDestroy=c.Destroy
    c.Destroy=function(control)
        if self.Members[flag]==record then
            self.Members[flag]=nil
            if self.Pending then self.Pending[flag]=nil end
        end
        control.ConfigDefault=nil
        return oldDestroy(control)
    end
    if self.Pending and self.Pending[flag]~=nil then
        local pending=self.Pending[flag];self.Pending[flag]=nil
        local ok,warning=self:_Apply(c,pending,self.PendingNotify)
        if not ok or warning then self:_Result(ok,"DeferredValue","Deferred flag "..flag,{Warnings={warning or "Skipped"}}) end
    end
end
function Config:Exclude(c,flag)
    assert(not self.Members[flag] and not self.Excluded[flag],"Aroyn: duplicate configuration Flag "..flag)
    self.Excluded[flag]=c
    if self.Pending then self.Pending[flag]=nil end
    local oldDestroy=c.Destroy
    c.Destroy=function(control)
        if self.Excluded[flag]==control then self.Excluded[flag]=nil end
        return oldDestroy(control)
    end
end
function Config:Destroy()
    if not self.Alive then return end
    self.Alive=false;self:_CancelSave();table.clear(self.Members);table.clear(self.Excluded);table.clear(self.Memory);self.Pending=nil;self.Window=nil
end
local function manager(window)
    assert(window.Scope.Alive,"Aroyn: window is destroyed")
    return window.Config or Config.new(window,{})
end
function Window:ConfigureConfig(raw)
    if self.Config then return self.Config:_Result(false,"AlreadyConfigured","Configure before creating flagged controls") end
    local ok,result=pcall(Config.new,self,raw)
    if not ok then return false,{Success=false,Code="InvalidOptions",Message=tostring(result)} end
    return result:_Result(true,"Configured","Configuration manager ready")
end
function Window:GetConfigState() return manager(self):State() end
function Window:RegisterConfig(control,flag,raw)
    assert(type(control)=="table" and control.Scope and control.Scope.Alive and control.Section.Page.Window==self,
        "Aroyn: register a live control owned by this window")
    assert(control.Kind~="Button" and not control.Flag and identifier(flag),"Aroyn: invalid/already registered control or Flag")
    local o=options(raw)
    if o.Persist~=nil then bool(o.Persist,"Persist") end
    if o.Sensitive~=nil then bool(o.Sensitive,"Sensitive") end
    if control.ConfigExcluded or o.Persist==false or o.Sensitive==true then manager(self):Exclude(control,flag);return control end
    local m=manager(self);local count=0;for _ in pairs(m.Members) do count+=1 end
    assert(count<MAX_ENTRIES,"Aroyn: configuration limit is 512 controls")
    m:Register(control,flag);return control
end
function Window:GetConfigStatus()
    local m=manager(self)
    return {Mode=m.Mode,Namespace=m.Namespace,Path=m.Mode=="File" and m.Path or nil,
        Capabilities=table.clone(m.Capabilities),AutoSave=m.AutoSave,AutoSaveConfig=m.AutoSaveName,
        AutoSaveDelay=m.Delay,LastResult=copy(m.LastResult)}
end
function Window:SaveConfig(n) return manager(self):Save(n) end
function Window:LoadConfig(n,o) return manager(self):Load(n,o) end
function Window:ListConfigs() return manager(self):List() end
function Window:DeleteConfig(n) return manager(self):Delete(n) end
function Window:ResetConfig(o) return manager(self):Reset(o) end
function Window:SetConfigAutoSave(enabled,n,delay)
    local m=manager(self)
    if type(enabled)~="boolean" or (n~=nil and not configName(n)) or (delay~=nil and (not number(delay) or delay<0.2 or delay>60)) then
        return m:_Result(false,"InvalidOptions","Invalid AutoSave option")
    end
    m:_CancelSave();m.AutoSave=enabled;m.AutoSaveName=n and n:lower() or m.AutoSaveName;m.Delay=delay or m.Delay
    return m:_Result(true,"AutoSaveChanged","AutoSave settings changed")
end
function Keybind:SetMode(value,notify)
    assert(self.Scope.Alive and mode(value),"Aroyn: invalid Keybind Mode")
    if notify~=nil then bool(notify,"Notify") end
    if self.Mode==value then return self end
    self:CancelCapture();self:_SetActive(false,notify==true);self.Mode=value
    local activate=self.OnActivate;if notify~=true then self.OnActivate=nil end
    self:Render();self.OnActivate=activate
    if notify==true then invoke(self,self:GetValue()) end
    return self
end
-- Validate/reserve a Flag before allocating the control. No Flag means no registration or added listeners.
for _,method in ipairs({"CreateToggle","CreateSlider","CreateDropdown","CreateTextInput","CreateKeybind","CreateColorPicker"}) do
    local old=Section[method]
    Section[method]=function(section,raw)
        local o=options(raw)
        assert(o.Flag==nil or identifier(o.Flag),"Aroyn: Flag must be a safe explicit identifier")
        if o.Persist~=nil then bool(o.Persist,"Persist") end
        if o.Sensitive~=nil then bool(o.Sensitive,"Sensitive") end
        local m,flag
        if o.Flag then
            m=manager(section.Page.Window);flag=o.Flag
            assert(not m.Members[flag] and not m.Excluded[flag] and not (m.Reserved and m.Reserved[flag]),"Aroyn: duplicate configuration Flag "..flag)
            local count=0;for _ in pairs(m.Members) do count+=1 end
            assert(count<MAX_ENTRIES,"Aroyn: configuration limit is 512 controls")
            m.Reserved=m.Reserved or {};m.Reserved[flag]=true
        end
        local ok,c=pcall(old,section,raw)
        if flag then m.Reserved[flag]=nil end
        if not ok then error(c,2) end
        c.ConfigExcluded=o.Persist==false or o.Sensitive==true
        if flag and c.Scope.Alive then
            if c.ConfigExcluded then m:Exclude(c,flag) else m:Register(c,flag) end
        end
        return c
    end
end
local attach=Aroyn.AttachWindow
function Aroyn:AttachWindow(raw)
    local o=options(raw);if o.Config~=nil then configOptions(o.Config) end
    local w=attach(self,raw);if o.Config~=nil then Config.new(w,o.Config) end;return w
end
local createWindow=Aroyn.CreateWindow
function Aroyn:CreateWindow(raw)
    local o=options(raw);if o.Config~=nil then configOptions(o.Config) end
    local w=createWindow(self,raw);if o.Config~=nil and not w.Config then Config.new(w,o.Config) end;return w
end
local destroyWindow=Window.Destroy
function Window:Destroy()
    if self.Config then self.Config:Destroy() end
    return destroyWindow(self)
end
end

-- END CONFIGURATION
return Aroyn

end)()
local attachAssets=(function()
-- Generic local embedded-image adapter. No GUI, global registry or network.
return function(Aroyn, payload)
    local register=type(getcustomasset)=="function" and getcustomasset or getsynasset
    local report={Status="Unavailable",Images={},Errors={}}
    local function decode(s)
        local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
        local values={};for i=1,#alphabet do values[alphabet:sub(i,i)]=i-1 end
        local chunks={}
        for i=1,#s,4 do
            local a,b=values[s:sub(i,i)],values[s:sub(i+1,i+1)]
            local c,d=values[s:sub(i+2,i+2)],values[s:sub(i+3,i+3)]
            assert(a and b,"Aroyn distribution: corrupt embedded base64")
            local n=a*262144+b*4096+(c or 0)*64+(d or 0)
            chunks[#chunks+1]=string.char(math.floor(n/65536)%256)
            if c then chunks[#chunks+1]=string.char(math.floor(n/256)%256) end
            if d then chunks[#chunks+1]=string.char(n%256) end
        end
        return table.concat(chunks)
    end
    if type(writefile)~="function" or type(register)~="function" then
        report.Errors[1]="Embedded images require writefile and getcustomasset/getsynasset. Icon slots remain empty; supply ready Aroyn.IconAtlas and Logo URIs before construction."
    else
        local directory="AroynUI/assets"
        local ok,reason=pcall(function()
            if type(makefolder)=="function" then
                for _,folder in ipairs({"AroynUI",directory}) do
                    local exists=false
                    if type(isfolder)=="function" then local success,result=pcall(isfolder,folder);exists=success and result==true end
                    if not exists then
                        local made,problem=pcall(makefolder,folder)
                        if not made and not (type(isfolder)=="function" and isfolder(folder)) then error(problem) end
                    end
                end
            end
        end)
        if not ok then report.Errors[#report.Errors+1]="Asset directory unavailable: "..tostring(reason) end
        for _,image in ipairs(payload) do
            local success,uri=pcall(function()
                assert(ok,reason)
                local bytes=decode(image.Base64)
                assert(bytes:sub(1,8)=="\137PNG\13\10\26\10","Invalid embedded PNG")
                local path=directory.."/"..image.SHA256..".png"
                local cached=false
                if type(readfile)=="function" then local read,value=pcall(readfile,path);cached=read and value==bytes end
                if not cached then writefile(path,bytes) end
                local value=register(path)
                assert(type(value)=="string" and value~="","Custom asset registration returned no URI")
                return value
            end)
            if success then Aroyn[image.Field]=uri;report.Images[image.Field]=uri
            else report.Errors[#report.Errors+1]=image.Field..": "..tostring(uri) end
        end
        if #report.Errors==0 then report.Status="Ready"
        elseif next(report.Images) then report.Status="Partial" end
    end
    if report.Status~="Ready" then warn("Aroyn UI distribution: "..table.concat(report.Errors," | ")) end
    return report
end

end)()
Aroyn.Distribution={Library="aroyn-ui",Version="0.1.0",Channel="stable",CoreSHA256="bfac3be339f13c7e86e0933e679e65826a3ebf0a60cc6f688ba7c15f26b83320"}
Aroyn.Distribution.Assets=attachAssets(Aroyn,{
{Field="IconAtlas",SHA256="37df1077953b470f527c87e0e78697e90b5aa81eb326ae538841d857f8acce5d",Base64="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"},
{Field="Logo",SHA256="8b03a7b8c10780fd09c2fcf78253a2a071e6056834d87473e36612b1682e9633",Base64="iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAABRbklEQVR42u29d5xdVbk+/rzv2vucmclMJtMJBogYauhgpElvCUWwX69d9KvXgtcriNjwqgh2REANQSliw5/KVS6iVwX1UpQSQKSEEkiZmTNzpp855+y91vv7Y63dJtzqVSfJevKBSWZOm3P2+663Pg/g4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4eHh4bF1gNx/Hh4eHh5bE5R/Czz+jJMffX197WEYtjUajbp/S7Y+sH8LPP6Xxs8AoLX5glKti/315B2Ax/YVOerOrp4LBfRWomjCvyVbJwL/Fnj8L4w/7uzuPkGBPiaCyVjHJf+2+AjAY/u4XkxfX98OivhqEAkzCXwXwDsAj+0m9xdtsIaIdgKgjYgCIP6t8Q7AY9tPF3V3d+85RLTKGGmS/Z4QtXoH4B2Axzaf93d2HgTgYjESExGLCwqIGt4BbMVe3cPjvwz7u7q6OonVNQC1ABIBxEQAEUQMGf82+QjAY9s9/Q1YrSHifQBpAqQS3yAgEhF/HXkH4LGNRohxZ3f3G5noZSKmSUBASVwAAQRUKpX8deRTAI9t8HCIOzp6d1eELwDQACkQ4TmK/r4N6CMAj20s76clS5a0BiFuIOIuCIQoM3QSgv2n4bqIdwDeAXhsY3m/rtXqn1eKDxaRpqTXioAKZz5BvAPwDsBjmzL+uLO7+2XE/A6RtN9PAIhAECrYuxCRbwN6B+CxjVwPurOzc6kivhKAFgGD8jU/VwJwNCAE+AjAOwCPbSXvB6BUEFzDzH0iYpJrRFzcLxCICCCS5ANU8m3ArRa+C+BRCP27urs/TayOMkaaRAhE7IlPBAEJkmDffl9gMwI/COQdgMfWb/y9vasYdL4YiYgksPadi+5d6C+Sxgy2IEA+BfApgMfWfA2Yvr6+HchgjbNmEtg2X2rrlCT8aTUw8QpsjPHUct4BeGyleT8DEK3NVcS8gxGJBWB72tvzn5gQRZE98t0CQBIRCMSnAN4BeGzNoX9PT895rNSpbtQ3f5pTEIY0OzuLzoWdtvi3JbwD8A7AY2s1/t7e3heD+CJjJCK35EMAiQipQGF0dAR/9+pX0/kfPB8T42M2AhCxdQDbGfDLQN4BeGyFob90d3cvFME3rDMQ2wYkW+gPwwAjlQqOOfoYfPWrVyKKIjJGQERJdpAUBb0wiHcAHlvh6W9E6IvE/AIRNAFiV+GXMAikVpvFfvvui+uvvxZKKYyOjEKFYXENiAgQTwfmHYDH1oQAQNzV1fMOVurNyagvwYb1RIRmFKFzUSeuv/46DAwMAAAmJsYhxrijPrV6gUsX/NvqHYDH1vF5x52dfQcQ0+chEicrvgICEcDMmJycxBc+91ksX74ctdosAGB4eBhJD5CoMB1AQMk7AO8APLaCvB99fX3tQYDribhVshPchgZBiOpYFe961zvxyle+Es1mE+VSCACYnpkR5lyDICEEhEgTTZ8GeAfgsTXk/bHBl4hpuYg0QaSS9d4gCGh8fJyOPuoouvjTF1EURWBiEDOMMZianIJSnLYCsxSAqOSLgN4BeMz/vL+7u+8NivgtRiRKqb0ExIopipro7e3FlVdcgZaWljRmYGY0Gg1MT09BKZW2AIly3CAS+utoK74wPLaDvL+7u3tvAJcJjCaAhUD5nL5Wm8VVq1dj9913Q7PZRKCC9LSPmk3UG01wNiCIrAdI4uN/HwF4zN+8n5YsWdIKUtcRUwcEBgI7uyeCMAgxOlrFO97+//DSl56FZjOCYlXo7s3UaqjNzIAUI2/tlCYDvgbgHYDHfM379cxs4yJmPshReykAEBIEKsDU1BSOOOIIfOpTn0Qcx1DMILbBgXHWPjk1iZnaDDE/JyGoZwTyDsBjnhp/3NXbeyoTnSNioizlE2JmNKMIbQsW4IrLL0NbW1t6uovYBSB2aX5tpoZGvQFmJssFYvsH7guJhL4I6B2Axzz7XHVXV9fOJFhDgNhhHbfgTwSlFGq1GXz2kkuwfPlyRFEEpdgtAgAs2d7/5NQUGs2m7QogxxFgv/hdAO8APOZb3g+AwWoNMw8IRBMRA0RiBEoFqI6N4W1vfSve+MbXo9m0LT8RSff+DbIUYKw6Bh3HrvKfbwOKAGAR44vJ3gF4zKe8v7u398OK1QnGmKZItuIbBAEmJyew37774aKLPgVtNBRz4YIQVylM0v2JyQlore3YD4gkiSRcE0ECHwF4B+Axb/L+RYt6j4LQR42YGICC4+9jJhhj0Nraiq9eeTk6OjogWkBMaV9fS8IFlIb4GKtW02jAsgElPycA4NBfR1stfOi2bTlz09fXt4MxuB4EFhFNrkRvBCixwtjEBL56xeU45JBD0Gw0oZRKQ/8kt7eEn9m8/8jIqLN1ghR+IgICa01l5KsCHj4C8Pir5/2O2gtfJ+adRCQmECc/DMMAQ8NDePMb34g3vemNiOMYgQoykxXYQZ+UBji7NEarYyBiEBUmAN29CMym5D8CHwF4/I1D/56e/n9iptONmCaAwG762Dn/qekpHHLwIbjkkouhtU4NOb/XZ8Rk/oSMnQcAMD4+Dk4dguStP6EN9Se/jwA8/pbG39098CIQLhKRGIBKJn1BoCiK0LloEa6+eg0WLuyA1ibh9EeRz0dAUCCxjiNxEpMTE2DFhXPfBQo5zSAPHwF4/C1Cf+nu7l4I6G8SuCQicVKls5odhPHJCVx/+Vew7777IGpGCNyob+IDMvslCIwl+nF1gTiOMTk1iUApiElP+/zIkI8AfATg8Tc8/Q0RX8aK9zRiklFfAoTCUohqtYr3vvccvPrVr3LDPvk5fyvzJanxS+EwZ8Wo1WqYmpwEM+f3A4iK6YOPALwD8PgbRG9xT0/P24n59cZIk0CBPZftks/4+DhWrlyJT3/qU4jjyLXusw3ALIiwQgCFLoDD1PQ0JienwEolYX/OBaS27yMA7wA8/sqfW9zT03MIiC81RmIiKFBG61WbreF5z1uCKy7/CsJSCDFIC3mJIyBC2ifQ+bzCpQAAMD42jumZaTsmLAIhAbKhYmf7iv+D9MTDOwCPv0Dej8WLF7cJaDVAJXfouxkd6wSiOMYVV3wFO++8M6KmDf2LRH6EZLGHMOf7iQIwgNrMDBqNRtoRSKzfhQnkIobnuo58WuAdgMdfKu9vNJuXEvMBItK0p7+1xEAFGB+fwIUf/RhOOvFERM0IrGz+LsW8PV3sYTAoLei7eoBzABOTE4iiGIwsekgzAEnsXAr5RF9f3w4DAwP9gNcM8A7A4//a+OPu7t63MKmzYaQJIEhqd2EpxMjoKM4680ycd977pdmM0pObkF/kkcLfDUw6BGQk1yIEUK2OIU4XgZzBp9KA1ksIS5B3ACKyuBnHL3VP4q8x7wA8/o8+K93d3b03EX8JEA1AJdocSjFNT89gz732xJe//CXAAIpZ7AovPUcWQfleAIwYGw0QF6b9RkerMMbMiQ6KgiAiUlAHFpFZAr1+8eLFbbCLhT4K8A7A48/M+2nZsmVlQH2TGO0CGEvIJ2BSpLVGGAZYs/rrGBgYQDNukt0DkIKop7gpnqz553YAOPfzHCojlTR5SNIMtw+YqoKxqMI8iTGlGoBD6vXodBcFePlw7wA8/szQX1er459nRS8UQQS75UdERKwIU1PT+NxnP4sVK1ag0WgWeP2IEr1vJNOBW8JKfbtEIYvcx8bGrKHnBUElUQVzVQAp7gIEQRxCoITwbvdAXj3YOwCPPyfv7+rqfSUrfqfV8YNyW7sIwxCVkRGcffZb8OY3vwlRM0IYBE7FN031oZGM9yIjBoLlBiye+m4uwDmJkZFKShKS+A9J24RpElE44bXWZSMyy0RHdPb0HOMcgI8CvAPw+N/k/b29vbuzoq8C0Mio+lzFfxxHv/gofO6zl9hiHSfDPNmsv8wd3sn7Bkk6AcWMI2kOjo2N2ynApM+YEgJRGg4Ip8adFAGZQMJECIjflcUYHt4BePyP8n4AJRFcS8RdIjBkwEaElGLM1uvYYfFirFmzGm1tC1LBDjvkk1l5IultxEBy+785E3aVuuSYFzADcRxjbGzMcQYU6wNZUECA8JykIiQiKLGBx6qurv59XRTgrzfvADz+J3l/d3fvp4j5RSKmSYBK83RjoLXG16+8Ervuuqvt9ydGnxppFrozqCjq6W7HSuG5yL6VUpiensbE+ASCQDnuj1zQL9kQMM8J71164ghJuEws7y7kFx7eAXj813l/T0/PS4j5/UYkgpvzB4GCMMDo2Bg+fuHHcOJJJ6LZaNp13TTkFwiksPTj7upa/JSmAUZrMAgKbIlBc/ebnp7G9PR0ukDkFIQlKQImi8AiUugCkJMdISIldoXw5f39/QNJKcJ/vN4BePwXeX/nwMBSgL8OwJAktiYIghCjo6P4+9f8Pf7pn97nJv3UnMwh/y8CxFotJ5SfUiz6aQh0sg2Q8IcBGJ+YwExtBszpFKDkawjp06m5Rt0USbIKQcREXXFsXp1zbh7eAXj8J3l/OdDmO0TcDxEtAIsxYFY0NTWJgw4+GF/5ypdhjAETFbn6k/wf2Zhv8iMDUxjOVchup0jBwKT1AgCYGB/H7Oxs4gDE2n/+mdz/9BbpQxk2XZHEawjw9l122aXFRwHeAXj8F3l/T0/vx5hs3g8i5VR6qdlsor2jA1et/jo6Fy6EMQbEnIb9ad6PbPRXQyfBe9oOIDe6n2/OGzEJ4UdqnsPDFasZwJw0ECklEpHcRjAXacGNMSERFNmZIyUiMTPvOTU1uxJ+PNg7AI//NO8/npjPMyJRouPHIGJmzNZncflll2HfffZBFEX2ZKZE7Mf173PRvRT+bi02v/STz/fFVe6Esv7+0NAwjDGSFg+zuaIiLYDN+fOQvCMhIrEFSTm78HMP7wA8sry/q2vHncDBdQDYSnnZwfsgCDBareL8887Dy1/+Mlv0I0vRlc/nCQS9pXxvOrlXtM3sT8INALbRQRLkD1cquYeQjAGQEs4A52R0cRAoLxbq1pMVrDrRSd3d3YfCDwZ5B+CxRd6vSEXfZKLFxkhMdhjPVvyro3jZS8/CRz/6EcRx7Ip+kgv1MafqP+eIJTxHV0C2GP5JHkcbe6CPjVUBSlaDKUf+U/QmROy6AHsn0YSjGslFGwJDRAGg3u0/cu8APObk/d29vR9i4uOM1s2E3Ucphanpaeyxxx64/PKvQCnlNvZyE30imYECIFbFfB9zi4T2/iL2GJYcFVjiH5J0YnRkJB0oEpFc9iCEXDJhjCmUAUVUQG64kFKRUWFADDGdsWjRDrvAFgP99ecdgM/7Ozt7jiHQh43oWCAqMVKtNdpa2/CNq69Gb28v4sjt9+fL8AWRHgBW1Q9zs/y0fk9W/itfOMzfGgIw2+h8ZHQUzHb3jyiVA0xDhmQWiJlC+62mLRUoqxdOTj2QUhVhxEpxu1L6zf768w7Av/eAGRgY6A9DdS1AAYRARAyxf5mp1XDZZZfikEMOtnk/q+TYdgU95Bm9bcnACBQ44+3N7fan0YJkGn+pm0i+T4QgUIjjGOPjE0kLMJ1DyGUQmVKQojYAwDLn1cQ6MQLBiHE6BPZ3NkZEgNcPDAwsgG8Jegewnef9iI35Boh2EpGIiFgECMIAIyMVvO99/4hXv8rSebPT8Muf18mjJCIgiYFq0XadJxnby53+ieFLvkiX/Iyy1GFycgrjY2MIgiBrD0oWNYg9/4kIYKFSzv4BBCC2EUxLuYy2NusfmIiNMTEzL40i8zJ4rgDvALbvvL//g0y8Soxp2gKZIAgUqtUxnH7aabjwYx9FHMXuFJbcaW2K4Tg5cU+hnGuxxbukqp8uCLm/K6g0IkhDf6RDgJiamnJswOo5q4pOHVicMwgBoFQqJZ6CiAjNqIn29gU4/PDDEEWxnVlwD8aMd7r3wXMFeAew/eX93d39hzLhQmMkBiEAQIoV1Wo17LbbMnz9619DGIY5m8uMe45AJzKWDklnAhKjBlk68LTQ5+6fTP2lf4hsdpGQgY6PozZTc8QiucZ+lnfYJxCCiFUHbjaTGgBYxCBQCjO1WRx91NFoaW2F1jHZDAExK7Wir6/vRPiWoHcA21noL52dnV0guVZEQrgVm0SGSwUBrlq92tJ6NZsg4pwgd9KAp5y0HzmmHkpbdiyMfMcvEf1M5gbmFv9seM5ZKQHA5NRUjg5cUvIQEkAo6xoIBCS6KDEnQiKACkLUajUcdNCB2HPP3TE9PY0g4HROwAidg+eILzy8A9iWT38TBKUrmWk3EbHsPhAwM6amp/DFz38Bhx12KJrNyMp3O/tI23mSkHAn1X3J6vG5rkCiD1CoODjHoZRCvnMncHsCuQhgZKRiaw/E6URh8tw0x16FKCzavx0MCpRCs9lEuVzGySefhEa9IUoFIIIyRjSAE3t6dnihjwK8A9geEACIu3sH3sPMrzJGmiAKRARBEGBkZATv/Id34k1vegOazSZUki+nSjyZHiflCT+AouQXyG72pX04AYRhxEApIAgUvve972NqeiZbIc5tCCamPTI6Cq31FikIZR6FxJKDAcYWAaMoIgAImUNmBjEkipoYGRnBGWecgY6FC2G0SeYCNDErgX6rvzS8A9gu8v7e3t6DCPIZI8ZKeQkQBAHGxsZw4okn4OKLL7KTfi4ct8U6ymi9nJCnSM5Uc04Ac2f/2UYCUWyjCQ3gTW9+C+677350dS1CFEX2xblQweT0ACrDw9mCUSFITwhCs3AjKQKGYSgAoFzlUATQscbw8BD2Wb4c+++3H2q1WvJ4yiUvZ7W3t/fC04d7B7At5/22703fJELZ8WmSUgqzs3UsXboUa65ajXK5bHN45jR8N874yFX2bWhPzzGVC2SJAdI7x3GMcjnEhg0bcPrpp+NffnIz3ve+9+aMGTBzVH8AuwmYEozkyABpzi+Wv4jWpc6HOak1EFvGYgA4ZeUpNFObIVekJGMkVkr1lsttL4dvCXoHsC3n/XGsLyPifa2UFzHspB8FQYCr16zB8573PLfkk8l45Xv72Zc5fP6UMfsKkgKBNWwda5RKJfz7HXfghBNPwr/efDPe+553oa+vz+oFUiIG4BgBKVsaqoyMZqvFQsXnp/xyUYZlqQOIVSolQJRGGitPORntHR2IdEyWXcDyCzPjHCci4geDvAPYBvP+vr43EKs3GWMi9z0EgaLJyQl85pKLccQRh6PZaKZFv3R6P2dlxMmqbmaEoKJxAgTijBE4LIW4/vobcMYZZ+Kpp57C8563E173utdar+TyfynoA2VkItXqKJQKXIdBiuPHc/4qQsEcn8eJ4zDGoNlsAgDts8++OOzQQ9GYrYOVAgPKGBMTqz3jOPaDQd4BbHPvbdzdvcNeTPwVgWP2EVAQBDQ6WsV73vVunH32W9BsNFP1XnKtvGRIN1HxSUd1k3VdmZP/uzqdjo0l8STC+R+8AG9929tcagH8/Wv/HrvssguiOAJIFXgBEsMPiNFsNlGtVhEoVSAVSIlAc/bvfhwAwLp1xR8mv0ez2QAAlEohzjjjdESxG24ido8hYoTe5k5/PxjkHcA2kfcTgJBYX01AO0QMESgMQ1SrozjuuOPw6Ysvgo51Suwh+Wm/OcF+cqrPJe6U3DJAHGuEJasV8MpXvgqXXPxpLFzYgTiKsHjHxXjnP7wDMLBCoEZnYX3eshVjYmIC1eoYVKAyWbB0f2DO7V35MF8FsG1A51SIMDs7a29lDE44/ngsWtQpURS5VWJSxhhDRIf39vYeCd8S9A5gG8n7dU9P32eZ+FBjTNPqdyrMztawbNluuPqq1SiVSvb0ZXJRNqXruTktTrsCzOwKdqYo8e0KgjqOUSqFeOiPf8TJp6zCT/7lJ+jr3wEigurYGF7/2tdh5513RjOOtigYJqSfSdV/fGICU1NTNiXJdRzSoIPcRFA+P8lVAYwx5SxqkLQI2Gg0sfvuu+Owww53XIPp76GJiI3QP/hLxzuAbcH4476+vlew4nOMSARBQMwUxzExK1x99Ro8b8nzLKNvcsLn13MpW99NiT0lNwKcEO+7+xhtUCqX8JOf/BQnn7QSf/zjH9Hd0w1jDOIowk4774S3v/1tgMlxBlI2Apye5u4gH6tWUavZOYEk/ZBcWFOQFcp+59xVJUG2cGR3ApIUBQBeetZLyBhHQGqfU4kYA+CMzs6B58NzBXgHsBW/n3pgYOD5IvQ1EdEQYcC2/GZqNXzpi1/EoS9aYavwSqEwrkeZceVPeZPs+CcW6IZyYmNAihCWAnzp0kvxyle9ClNTk2hb0OYmCRWmZ2bw9re9zXYZ4igjE8md0Mi3HGElwa3QCANSGC9MKw7pODAEhKIuAIOZiEGA5TWIdSHSOO6449Hb14t6vZEsCCUtwTYVyuv8tekdwNac96s4lmtB1AWBEQIHYYBKpYJz3vMevOENr3O7/WxF/rIdnVxYnxXd8g+OnBpPHGsEQYCoEeHtb/8HvP/956GtrQ2lcindIJyZrWHpLktx9tlvsRTiynYJ6DmcQF7ss1KpINbaRSIkLkBBngiAcrsGIuLUgdclhUFOogbkioAQoNmIsNNOS/DiI4+k2dnZdAWZrJKQEOTNfX197fAtQe8AttK8/yPMdKQxpikEVQ5LGB8fx6pVK/GJT3wcURRBBSrb4Zc8pXfC9edGeLnI6CMigBHEsUapFOKZZ57BaaedgdVXXYXenh6bShhbfAvDEI16A+855z3o7u5GHMWuZUi5R0QxBXBfR0ZGIMZkpB+5l4TiTd0cQroLkLgu5aYFBQTU6w07xsTZ5XbmS85AKlRo6xwsIjErtQuAl8K3BL0D2Nry/p6e/uOJ6cNGTASIUqwwM1vD7nvsgTWu6JcN8MicfpddySnw+qfpgKu+Q2CMQakU4rbbbsdxx5+I2267Db09PYjjOA3nlVKYmZnBihUvxJvf9EZHJOrm/kXSwmG6MpxGHvZy2LhxYzZrkNxE7HaRJPyAKHiA0pyIQiWMRUSMKI5dCkD2dQA4+qijsHjHHdBsNimflpAARuj/oZiVeHgHMK/fQ9PVteNOQrg2zdKJKWo20FJuwTevvhr9/f2ImpbTL5nnT/v9OTqvZNeuUPgjwGh3spdCfPOb1+AlZ56JocHN6OruQuSM34ikj9toNHD+B2xakCkIJUzjUtgdSJ4jGQwcrVbn8AdkLoq2yHoE5HYBMJc2hGyDoOkmAZNyQ9SIsMPixTjuuGPRqDfArBLeQaXFxER0WFdX38nwLUHvALaCvJ8BCKtoDRPtCEFMxMxs++lf/MLncdBBB6LZbKZFsELFICur5U5/wJBJnUUcawShtYMPfOB8vO1t/w9MjNbWNnu6M6UcgUoxxsaqOOmkk7Bq1SrE2tYKkhheKMcJQPnR3mzysDI8DBUEyCg9yU0dS0JHmDiOhJmwqAwEIyIGRqwqcWO2nvu1s4nGM04/PT//QJKGJSBm+afncioe3gHMu9C/t3fgPczqRBHTFCAolUoYGx/D+eefT695zd8hakY2/KdkoEa24PPPrv2sMAcAWtv+fqVSwUtf+nJ87vOfx6KuRVBKQRud0nwREYgZIoJyuYwPf+gC63B0Ue4rX/XP2oxIOw9xHGNsbBxKcdZ5yBlisX6Y1hEUnmNPKFEjiqImtNYJl4mdVARw5JFHYqclS9BoNOBmmIkAZQcD6dhF/f37uSjAX6feAcxP4+/r6zuCCJcYY2IRuwlbqVTwile8Ap/4xD/bsN9RfCPPwf8fHGx5RxDHMUqlEh5Y+wBOOnklbv7Xm9HX2wejNUzCC5hVCFEqhZiansbZZ5+NFSteaJ9bUUbmKShIiSURQfLMrBgTkxOYmBhHEIQuUsi/VipKgiWVC1PUBiShMIsdCLHWSPr+9k6EZrOJ3t5eHH/C8ajVZu1MQ+YKY8UcBAZvLxYXPbwDmD+hv168eHGvEbpeIC2W0DOg8bEx7LfvPnTl5V9JK9+puAaQGhwXxLmsOu/cGf9SqYQf/ujHOPmUlXjssUfR092NKI7mFu0hsOnCbL2OpbssxQUfPB/GmOKp7054TjcALQ+AlRMDtCu3TU5MYnJyCiphIc7qCpQPJIq8QHbWAalOAIK8g4uj2L4eVwjIFx9PPXVV7p6UtD6V6yK+qr+/f8BHAd4BzEcHEDaj6EoiWmqMNJmViuOY+vv76ZprrkFnZ6ctvjGlhBv5Q18jt+SDTLrbmBgqUFBK4dOfvhiv+bvXYLY+iwULFiCK44zGO7MaiNgdgampKfzjP56DgYEBaK2LNYec8yEAwtl983Tf4+PjqKVjuoIC0XCub5c3YstonL0gEetlEj3SZtS070WOd8DWJYDDDjsMz1+6FM0ogmJ2bGdEIhIRc7fW8np4RWHvAOZZ6G8WLeo9nIhfLmIiZwCo1+u49NIvYfnyvVGfbaQhryEUOPxTlZ58HUBsyB+WSpiZmcEb3vgmfOjDH8GC9naEYcmKa6Q6fUUuEMWM8YlxvPCQQ/DGN7zBGr+awwSMLBUQ50RMwSllDqBer7tIQQrDR9kJLZQfDCJ7HT1HdUDSukIca4BzugIQNBpN9HR346STTkJ9tm5fc9quEBYxAtBb4bkCvAOYRzC2ONd4yIhsIuYgsZRGo45arQZjjN23N1aALym8UZ5N106/QblxwCTff/TRx3DyKatwww03oK+vzx6rxjhNbkkP2owGIGEQIlz4sY+hpaUFxkjaWUg3/khSFmFyKYF9XUWmn8GhYURRMyURzUhC8nqE2WvJCQ1x7qpK/56wHWsdp8WDTIXIfuuMM86AChSMcZqDLnkyRmJi2q07iv4OfjDIO4B5AgGgpqamRiH4jqX0hk5C2x/9+CZrkJzo+xaqe6lRJNp8WgTGaJTLJfzyl7/CKStX4p4//AE9Pb3QOnaFuuJYsOSUeoMgwNj4GF73utfh5JNPcqxClCvgIecEcivHuZVelQsnNm3ciDjW6WssxhoFfWFKfhcB8ZIlS1LJYtGkkgJl4gBiNwyU4zO3fAMADn3RCuy2bBnq9Xr62oiQ21ugd7hrVfvLzzuA+eIEQDCrjdENEQQQmPaOdrnjjjuwfv0zCIIgtZ+kW55W3cme2AlDbhiGuPyKK/Gyl70cY2Nj6FzUKXEcpfX9Yuswzw4MRFGMgYEBXPDB8+0HqrIiX3poM2W1AymO8RLIpigOGzZs2GIvIU1UclOJyUCRKxSS1pqKEYBLD4gkakaIo6LtkluEipoROjo6XDdgJl8IJWJSAGImPrinp+eYXArm4R3A3zwN4NHR0UcEcqvdZRdTLpdp08YN+NnPbrWFPmPA7N7kpMpvCCIaWmuEJdtqe897zsE557wXQRCgVCpJdloiXdIpavm5D8/l/ueddy6e//znI2pGCDgAORuhNGSX3L4BkJ/mkUQTzP17uFIBK5XkBlLIIpBlFeQKAe5RVKPRSDcCSXLbgQREcYRYRwWnw+71J7/MqpUrEQZhoeLofndjoxF+F/xQkHcA8whuBC74qrtayRhBWCrj1p/fmst/k1kcAyg77xJHMcIwxODgEM466yxcfsUV6O3tETvya+g/fcYkbA8CTE1PY8ULX4iz3/KWtPCnjbaRMm1pLQKT4xVw/TayisNJe7BSqdgKvRsXtis9WeVRCNkmoPNGRBRqrVXOQJXkwgxjTNoGTJyS1jrtVBhtsGLFCuy9fG80mw3LRYik/WgHgwh0cn9//67wXAHeAcwTaAC0fPket4qR+wgIdBzrjvZ23HXX3Xjq6aedsq6GGIEx9h7GGJRbyrjrrrtx/PEn4Oc//wX6+vokjuK0xue0P9IYnLBlGxEQhKUQF3/602htbbWDNsi6DsmwT96bSI40OA3/xbiiIdCo1zE+Po7AzQBkUiO5s9tFD8ner6QGLzn3lFEIERUdAPKzDsn0YRSjo6Mdq1atQr3eSIuayeQEIDExtxk/GOQdwDyDuu2222Jh+objvzNhKZTh4WH86Ec/tsZokuha0rn8H/7oRzjjJWdi/fr16OruliiO03XfOUW2HPkWpUU8pRRGR6t4/Wtfh2OOORpR5OjEk25DQieePJ7kJMJdBV/lKcXFTgGOT0xgfHwCQRDYxaLUAAvzP8i1/+xzGZAxJpUwNpAgZTVyp30UxWmBT5BjPnLaAQCwcuUpKLe0FJ2FfSAllizgtZ2dnV3wIiLeAcyjKAAByfcEMsbMoRiRUhjixht/gEa9CYZKE+9SKcRXv/o1vOY1lpq7vb0dUdTMxLbzcl9ZoT9txZHLm+v1Bp6/dCkuuOB8N2LLxXMxd8hSMo2T6XpBxBUxOHEKyQzABKamJsHMiRzIFgeuPEckAhZCe47GUBDmOx5aa0m0AVDIHgjEBBXYNOTAAw7AXnvtiVqtVihCWjVRiQm0WKnwdfAtQe8A5gkEgBoeHh4C8Q+YiYwY3dLagnvvuQd33n0XwhaGMSYtws3OzqLRaICZEOvYdb2z1hzNVfvJtQ+Tib/pmWl87KMfwY477mgFPJlBKYNvtuRjI4Hcrj2ysT7LJVg05rGxMUxPz9gTWXITQHPVhyht/yUtSZapNs5SDat6nNUAJNEGKLAZMyEtkkZxhNbWVhx/3LGYmZnORpaz4IMswQi9DUAI3xL0DmA+IVT0dcsBCMXE0mg2cOONN6ZHYjIEdNKJJ2Lhwg7U6430iJNcxx3paK4buKUsgQ+UwvjEBFauPAWv+fvXIIqs5p8YAYxxHH65zkGy5y+5CcJclJEnIQWAarWKeqOeGvcWFcgkb5dcUcEiaGnR2YlMEuRnHY0xyEcAaa1CAKOTIqlLA04+BS2trZkzlDQFYUA0My3v7u4/zb1Tgb/yvAOYD2kADw4O/l4EvxZAxVrrhQs75ZZbfoZKpWLbW2Kr/7vtvhv23WfflB9Aklw6iXdzHIGSnuL2O1rHaGtrxSf/+RNw+pvZUJGRLQL2tNE3R9mH8oXFXAgwODQEo7UrICYEQtmqslDGTCQiRJyw/pDKswQJckpBbhMyiQCSPQLlhEmSWgWzJQ895JBDcMD+B6DRaBAzU0qFhrxEkbzbPZhnDPIOYF6A7NVornBHMLW0lPHss8/ipz+9GYA1fq2tVt/RRx/liDyUNfDcPL4UwoHspFZBgLGxcZxzzjk44MD9iwQjc8g98kv7czsIqTEjuU+6gYfhoaF0ei/dHqZs7y9JKQqPSel1lKsBcMA5chMRk00CJnUB0fksISU+aWltwemnnYpmNOf3s3dTgBhienFXV/++vhbgHcB8gQFA3Z2dP4XIw6yUEhGjlJJrrr3OSn+xSqvdRx39YpRKJZlL+5vs3idbgumyj6P3PvCgg/BP7/vHbNMvv5wv7lW4DkDSCbDnZm7oRwpbfHYM2P17cHBzOpyTRQDZxmBijIJMkESSQYFcBMAsKt1VcGPJsdsFIBQXgvK+LpliXLVqJdrb2xFHMTJm0mQ6CDEBASnzBvjBIO8A5lMxcN26dQ2o4MvMTEYbWbCgDf/+u9/htttvR9gSpnWAgw86GDvttBNm6/XCKU85+Y10cSgXCVxyycXo6OiA0S7fJxRz+zlpOyWneVKDKPgbKzhicmd3ZWQEKl0hLjonyn2l3OGfrgdLRgqS3zK0NQChRBtARLZ45wSWMFQpWzBdvnw59tlnX0xPTyPRF3C7BQSIEoiB0Ju7u7uXwHMFeAcwj2oB1N5a/q6IDIMQEEiiOMK3vvWtLPTVMXp6erD3XntRbWbGUmVL3vAzuxYIAhVgbGwMr3vta3H8ccemVX/kwniIFE7TfD2Bs4m+wl6PQCwHgUk2EoFKZcSqAbn2/9zHF8nVKaRgzCRS5i19orjlQ5OrAaAofJIfNYJAu1mJY489BvV6fY54SvJciJm5Cxy8GZ4rwDuAeRQF8Pr168cFciMA0lrrzs5F+OWvfo0NGzYgCALEsa1bvehFKxDHzdzGW0rDLRlDADA9M41dli7Fxz76Ycfuy0UxEdfnz6cDkkb6tEWvLJsQJIhLGVQQYHa2jupo1UmCZ4M45Cr0RLnpPHHNC0srJhCwMTooJET5N0Zgef9QpB8oRDmJv3DfW7XyFHQuWgRjdKaUnGYujkBQ8PpddtmlBZ4rwDuA+VUR0FeJSCyAKpfLMjw8jO9//wf2R8aa5BFHHIEF7R2W248zuu603m2NTnQc4xMfvxCLFy+G1nG62Sdb9OiluH1ILqWQIiVYznO412OtdWJyAmPjjgzUSMEun4PpYw7/tygpiSp4GUFOe1AQuQggP4vAYChSYMk2GEnsaPD++++Pgw8+CLOzdRDbWYLcSgKLSEyMF0xN1TxXgHcA8yoN4JGRkfsA/ErZYqBuaSnjhm9/G9NT0wg4hI419ttvX+y+++5oNpppnptm1ER2UCiOsPPOO8uqVSvth0UqqxfkRgWTkD+b0ssJiOdm/yVXYEzLcDkqsOnpaShWhZFkmqsIms4WJAk8gYi4JAViUMoToBgxab0j1SSApUHTom0qgqzVqLVGGIY4+eSTLLHploTDlLETmXc74/eDQd4BzJ/3VIXB5YoZYgyVyy1y33334l9vuQVhOUCj2UR7ezsOP+xQNGw7z23cSWaUApTCEJs2b6b77rvfehetcyewpJ2DTEkY6RBRsY84JwWQLfPvarWKWq2Wzhdkd6OMEShVNEnp+13gIoWgnzhhGnebCEbSFCCZI0h3F5xTMO4hiNxoMCCnnHwy2toXoOm4EDkpkNimgAJEE/MBvb29h/sowDuA+YIYAPV2df2rQB4EIRCxO+3XXnsdgIwX/5hjjs0Td+Y652T1gIkxPTWF2267PTUUAFBu49/m8pLVAtIUAFsU3PI6BPYxVNohAIChwaF0RDnfUZhLDZ7UB6k4a6CMCXJ8AMSutpHWCZNloCRy0UluL7mQAdm+A4zBXnvthX2WL8fM9HTWnnTaJu5emonJgN7uLzvvAOYT1MMPP9zUsblURKB1LAsXLsTvfvc7PLD2QZRKVkrvhSteiJ7ubjQaDcrGbyWxa4gISuWy3P37uy3PoHMcjmrQ5ur5TaG8iedzcOLCDL6QpGF3crdnnn3WDuskIX7OmYjkigw5PgBKgwMKJDBh3ufkRU+tmnFUqDmAAJPbUrTCJlkLJIo1hWGIU09dBW3Vj1Jeguz3gzIQA8FLurq6dobnCvAOYB7VAhBF9R9obYaIKAyDUGZqNVx3/fXuRIywy5Il2H2P3VGrzaSDPZQ7zEUEC9oW4LFHH8PQ8LBd0zUGkm/K55g/HGFvdtKmHIAmNx783MIkmzdvRipcQtktJbeIlHGR5oaNnZRhUKwBOFu1YTsRpduAxeykGJVkoVAWXaxaeQp6+3pTxyFFxVSCbQkuAAfvLTyoh3cAf0MIADUxMTHORN9lYmhj4gULFsiPb/oxhocrYFYAM44++mhEzShdGc6dcZSQfgwODeF+VwcwSe8uxxwgBbLO3JSdoMgOXEgHsnYhAAwPV6A4x8STIy/HXKMlQZH/A2wM5yIACZzYJ4EIipVTRiqmJUxkBUlpSyfAzIiaMfbaa2/sv//+qNVmi/UJV4+gtOAoY/6y8w5gvjkBBAGvNmJiiKhyuYT169fjxhtvtLThAI568ZEolUu2352EwZnZEgE0OzuL22//TeEEn7uSTzKn2JfjAWQUaT2YGDLnOJ4YH7e1idzGX0Leka9NJE9i13QK04VZMUNQSoVOnXEnEUCeX5iJrUKSUm4uIRMutcKoBkGgcNxxx6FWqxEzuzXh9D0wIApE5PHqyMhn3A/8gpB3APMCBgAPDQ09BNAviFkZY3SgAlxz7bWo1WZhImDffffFrrvuiiiK04JgugwkNk8ulUq48847EceJ2g9lRB7OS7hQOxvyQXayxpLM/as5DP7i2o1xygWYzekn/88tBVBxADjviESyOQAilJPbGGONP+sCZMM+WjS02FVm5H5nG+RIthuwciU6OzvdbkCh5GFXHbR8CkADtgvg9wO8A5g3IAAIVHCFHQM21LagTe6991788pe/BIdAT08PDj/scETNppXjSsZujQgBYoyR1tYWeXzdOjz77LNQgYIYU8jzIZQee1nvn9KTPNEJ0KLt/L826VKPChSmpqZRrVbBirOtHpJ0LdhN7RUHiVOxAkmMugUAuroW7yygAx2VKBtjEKiA9t9/vy3io8QZ5BWLs6jBvm5jDPbeey+sWLECU9NTeWZ0TUShMea+arVyg7uWY3/JeQcw34qBtGTJ4luMiR+ESEAgI0bk2muvTW901FEvRqx10r+3nbZcdB0GIUZHR3HvffelxcFkWCcp2kmOSUQSzj8g0x90D2bEZPm2O+3HxscwPj5u+QnE7f1LfsOX8tU9KrQCbBaviXgcADjUK4moW0RiABRFTeyyyy449thj09x+C3GSOR2DVEzV2DVqpRSOO+4YNJtRTl/BsiAQzPsARL745x3AfIW65557otiYr9qWoJbORZ24/Te/lT898ggA4OCDD0Z7RzuaUTM/8Z7ZKAHNZkPuvOOOwim/5cagrSFYtt8cN0Axfc+N49o7jo+NYXpmGoqV+64zcEq6AjltAsrVIAmabVJ+R7U69Afr8sxZyekeBAoztRodccQR6OvrQxRF6etLtQZR3FRMoppkdZqYMTMzg5/dcivaO9ohlhosZqIAgmtHR0d/DT8J6B3AfI8CTNT6HYEMEVNQKpVkfGIcN9zwbQDAC16wK/ZZvhzNZlOU4tysv7M3Y+sAd9/9e0ckks3O22o/F2oCAoEkBiTFgzEt7BG5ZNuuAdfr9XTYJtvyo2J1XlwDIOd0XM3hmwB058DA843w4Y7HK6EctRLgAESbAnNRQbvsOSTURARhGOBLl34Zv77tNixoWwAjYpg5EJERIvlg0bV5eAcw/yAAeHJyQ1WxulYpRUYb3drSgu985zsYHBxCa2srXnzkEYiiKGMGzikCiQhaWlrpiSefxIYNGxEEKqMAB0FSsfEcP0BqwzYdoDkRMufsb2hwEDrRA8xt5OUNMrfGn/xYyFbgn21pCX8IgFjr41mhQ0RikO1e7LzzzjguCf8DN32YHvdS7Ggia18abRCEAZ544gl86UuXonPhQsRxBCIIETOBPl6pVAbdr+Ir/94BzHsngFIpWAOgaUSCUqmMp556Cj/96U8BACtWvCi58LM+YMLcL0JhGKA6Ooq1ax+Y88A5g6eilp9rkDuioCIfQP4g3rBhkyPl4MKmYLEXQAWVYBFoshtI396wYUPVliLp9OT2ihVqszWceMKJ6OntsTwGNJdsJDfbn/sjEBj3Aj/5qU9jYmJCwlIoxogm4kCMWVupDH3VG793AFsLDADetGnToxD5JZFluC2XyrjuuusRRTEOOugg9A/0oxlFSCdobAAvCQVXo9nEnXfdlRXQDOYs9hRNN68JmB8CyqcYgKUCy5/MlPcUlAmbOE+T3CgwIjGRfBsA9fX17QDBEbBdBwYE5XILveQlZxRSD+RSljw3QfIaWVlNxVI5xE9/ejO+993vobtrEbQ2SV5ggoDfA7dz4cN/7wC2FljiUKbLAILRhhcsaMOdd92F2267HTvttAQHH3wwoiiCYs7N8yVLNSKlUknuvuvudB5AcrlzkV0ve0KF4mgwE8DCIMooCSsjI5YHoEj+hy16c1mirpmYBXJ7pVJZC0CMwYnM3ANIBCKana3j+Ut3waGHHgpjkNYtJP+wSfU/12zQ2vb/Z6an8ZGPfhSO6RxE0Db3x1WDg4O3+8KfdwBbZTFwZHDwZ8bIWgEYzFpE8K0bLGXY0UcfjWajmTcQyog7BC3lMtY9uQ6DQ4NQqX5f/tTmdBKG0tDD3oaRrN3aPXwjYjn4tMbQ0JBjAiqmFYVHSkkCshfHoKsy30OvgQjE2ALj1PQ0HX/c8Vi0qBNa2/A/mXQkV2hkYsf1l6UnWhsESuHLl30F9917H9oXtMMYI0SsRGSwHvKHkhKGv6S8A9jaoABoJqxhZhJjTEdHu/zi57+Q4eEKjj3mGJTKIXQcJ5JYuXPd7gWMVCp44P4HCgWzbDrGFETzEmZeBYKGQLl1+WSCQNk2HUZHRxEotaV6aC6WsBGEiO29UygizxgT/xQABgYGni+CI0VEiIhFDNraWnHWWWdmtQr3Elk49SuGsvQ94QQolUI8+uhjuPTLl6GruyvZIRBmYiY+f3rz5hH4kV/vALbmKCAM1Q1i9BCBwiAIZeOmjbj++m9h//33w7Jly9CMolTvj6wunmMBYszO1nHHXXemUUG29Yc5tKCUymgYFyFo6LQ4mBT6x6pVjI+PQyllOQjmlPwz2bL0R8ZKh+HGarU6CQCxyEnM1A4gYmaq1xvYa6+9sWLFCqddSOmAknbS5UTkWoKZalJypl944ccxPj6GMAxhxGgCBSLmtkpl8BrnRL3xewewVUJcMXCUiL9OTGSM0e3t7fj2d74DZsZRRx2FRqMpzCR2SjbryhtjKAwD3HPPvTacCIo0fDSX8iunAzhn+C8tDo5Wq5iYmAQrTqW/Mafin3/xRAiMMZHWdE36DIK/Q6YWRDO1GTrh+OPQ1tZaqP4XRn+TjUCQLeVrY5WTf/gj/Pimm9C1qAtaawGIRMyMYn5Hvr7pLyXvALZmJ0BA6RoRmQUkWLBggTz44EO4/fbf4KSTTkKz0Ug344B0EI/cPAAef/xxu7yjVI6uW3LtOkpn/VmUzbmpqAOYXwOuz87afYFc9TDPAmS3+wUANIFYDG4fHx9+EID09PTsAcGhYkRAUHGssaC1DWeccbq9wFhlg0c5800KmBpAbKzkebVaxUc++lGU7MkPItKsWAH0mcHBwT/50987gG0BBgBVKs8+AaKfETGLiNY6ltWrr8JBBx2I3r5eN/SSb8U5ifFyiM2bNuGBBx60D6Yd2YdL+JOCH6XbhFlVIGMIyox706ZNiOLYpRy5FGBOHTAV5yECs6zJvIM6lQhlEYmYFer1Og448EAcfPDBlsZcJZuLmeFbjS+VzSQYA1aMz3zmc3js0cfQ2tYKY4whooAEj4ah+hx8z987gG0IBABazOVijGht1MKODtx6663SbDTk0Be9CPVGI8cXSOlJz8RSm63J73//h0IoDyRG6vgEU+HxRG9wy7HexAE8R7Sfm/lNQgIYEAJANmq98ObcA52eeBdmQr1exyknn4RSqYQojm0kk5MJyjMC201gW/i78867cMWVV2LRokUSx9ruJBETAj5n8+bNNfiev3cA21oxsDo8/CsD3E8EFZZCPTI6iptvvgXHHHss6vV67uSUbA3X2Fx57QO2E8CKUy7cdPgnb+FkjdlRb+ROYovBwcHi4lHiSYSy1r/j3yYwGcENY2NPTgBAX1/fMhBWAHY8N9YaCzs6cOqqVWnEkfkbKYqSOrJRYkIURbjgQx9G1GyCmCFiYmYOCHJDZfPmn8H3/L0D2Ebfe00i17jBILS0lPGtb30Luy17AcrlloxGa46ATmtLCx555E8yNTVlSTzi3BiQpBxZhehAi84d5tmBPzQ0BGZyXYYs96fchqErKAZiTJ1EX50+ldAZRNwqRiJmptlaDQcdfBD22XdfS2LKbIlK8n8SngIiiNie/+rVV+E3v/kNFnUtEq21sTsGZiwKg/P8ye8dwLZcC0CjFFxvjBkUIFiwYIE88OCDmJyawj777GPTALcdmBKAC1AqlbF+/Xo8/vg6+0DJQFCuJQjXNiTKR/F2UCdh2zHGoDIygkAFubFhykUI7lkJBsRsILePjo4+4q4bBdArkuuIidBsNrFq5UoEgbLLRYGCJQblVAnIPr9VSArDAOufeQYXX3IJFnZ0QGuTLvsI4YLqhg0bfe7vHcC2CgGgpjZtGiXgWiIiItZaa/z2t7/DfvvtZ8UxWWUBvQiMCLFSNDkxSffdv9aF7iYL77MzO1HnmJPb258qpTAzM4ORkRGoIMitH8uchaC0JACBJCwmuq+vb1+QHCJiDIg4jmP09fXj9NNOy9IIbWylXzTE2BkAYrLjSi6rufDCj2N4eBilUgijtSaiEJDfjA4Pf82H/t4BbA9OAMbwNcaYpjEmaGttldtuuw0LFrRZGnCXK+cZcxIiwAfWri0WCXNDO+KOTSa1xSpwgmq1ionxiXQKkMDpxF6OatwApIzo9Qq4yRklhNQZRBTAknNgamYaL1qxgnbfY3dorVMasjzRR1JOEBEEpQA//tFN8t3vfFe6Fi2SWGtjlYSlgdC824f93gFsL2kAV6uDD4vIrQRwEATmmWeewUhlBDvuuKNtB6bTe3a6zxhBuVzC/fffj6gZIVDhc4h/Jk9gcqKa5KzX/ntkZASTU5N2Ecj9obwEuAs6bHBC14+Ojk65Rw9I5CXuyZiIEEcRJRqGWuvCNHFCRiqw5CZKKVRHq/jgBRcgDAMYG3QYpVRAoM9VNlbW+tPfO4DtBa4LZ1anZzsRnnhiHQYG+tGM4kyCJ8nxxaClXMZjjz+O9evXg1VRcCPPvJtt29koQecihaGhYTsExCrdJyh0EGwvIBAxNQa+4Z4h7u7vP0SAA0TEEBNHUUT9/f048cQTM4NHtqNg0oe0JJ/MjIsuvhiPPf44tS1YAGO0IeJARB4LAr7I5/3eAWxvUQC1t7ffKmIeBaBaWlrNxk2bMDk5BcU8ZynP/qeCEGNj1bQdmOhzJtt1c3kAFOVoxNyPBgcHEcVxjt4/2xFwRQdDVpHz9kql8gSAAADY4Cw4iW5mxmx9Fi9+8Yvx/OcvRRxFBXJu25rU7qvd87/jzjuxevVV6O7uRhzHcOPOBCbf8/cOYPssBq5fv74ugqtcTC2NRgOVSgVhGGKLuN6d8lEUIxkIyp/2+VRAsWPYyanvJpweGzduRD5Wz0uOF0yQcX3+tQrkFBEDMZLWGc8680zrzYxsQSXgYn+Q6xR86EMfRrPZsItKluUnNMZcWxkcvMWH/t4BbK9RAJhxPUSqAgQiInaTLqHkR4HV1xJmhlj7gC0EMucHfaQYXuSmABmwrCAAnn12g7sfMoXhzHANMQUisq6k1A+dYca9vb0HANg7qQ00Gg3aackSHH/8cfbxiQoS5kn/37jc/4orrsRvfvNbLFzYidj2/BUIg4Gic+H3/L0D2I4dgLIkl3Kj49rTxUM/L9Nli2nlljKefPJJVCojdp3XmIQzP71NunjjHIGBpJTbmzdvtnp7Oe6BnKPRRAQj8q3NmzfXlixZUnKXzGlEFAASs1I0PT2Nww8/HP39/Zb2W3EahSSOR4tGWArxyCOP4pLPfBadnZ22dUkkzMxE+ODQ0NAw/J6/dwDbeSpAIma1ER2DSCWncjo2m3cGYlAKSxgaGsIjTl/ATvPNWfyZ0x2wijuMZrNZGAJKNcZcs46IAmOkwTDfAYANGzY0AbBATsmCCSEiSkd/IQApAikq0IuTU/i54IIPuz3/ACKiFXNgjPy2MjR0rQ/9vQPwUQCA0dHRe0TkLiIoy+BFyK3pQ3K6f0oxZmZq+P0ffj/39C7EDYCrzDvKLmbG5MQkxsbHnNSY5MuDQkTaknfJrW7yLwCgu7u7DwFwCCBasVLNRhNLly7FscccCxhYaTOTDSAJHMVXEODb3/4ufvKTf0FnZyeiyKoVGjGziuUf3O/uQ3/vAPznYY9fXOMYgSSby3cLOrloXaw8Nu6+yzoA4kS1i4qLN+lsb1YLGKmOYmJiAkHAuZ9nLGQCwBj6BgAsW7bMrRsFLydQIIBhJszW6zjh+BPQ19+LKI7SO+s4kyoLAoXNmzbjYxdeiNa2NsSxhoixub/gU8PDww/C7/l7B+CRRQG62fIDrfUwgCBpoyeyPJkzcKu05TIefvhhTE9Pp+q++eJbkhKY3MO4SAMz0zNgVkiGh92kXiK5/URbW+kWALRu3bomgJBIVtnJRCGrWhzizDNztN9GErGh9HmZGR/68Efw9NNPo6WlBWKM6/mbPy1Y0Pp5b/zeAXgUA3g1ObmhCqEb2VqRTkk5M2lM6wOMoFwuY9PmTXjiiSetoTv+/PzabSEdcNHD5s2b0Wg0wHZoR1JGIBHjCEC/u2HDhtm99947BCD9/f0Hg7AXIBpEXK/Xseuuu+Kwww6zF1JaTLSOSmuNIAhw07/8BNd/61vo7u6C1rGQpTqLIebt69evr8NTfHkH4LElNJurjJgItuKeo+zOZesEBEEg09PTsnbt2vQkzivsJgXBfHwPABuf3QCjdX7qN7lxoI1uwJjrAODhh1vdvoK8nImZiHTgFomOPOJILFy4EFEzAjM5AhNK6wxjY2O44IIPoVwuJd1Jq+wDumxkZOR2V1vwp793AB552wfAEyMj90FwG9liQJye4HN0NAGB1ga//8MfcsLClKsRZOatkI0IbNi0MWkHpiqEzkCZBP/min8KuCdatmxZ2QhOd6yDLCIohSWcfnpu8w+OdITgNAcUPvGJT+KRP/0JbW1tyaZfADFPx82Wf3bXnq/6ewfg8R99LsbI6qx6J0IgEbev6yJ2McYOBN1/3/2Ioggld9q607xYYMgp/wwPV8DMkvL0SBYqCONqe4+9FQBMTU0dQES72ak9G/7vtfdeOPLII+yuoGMQMjDQWqNUCvGrX/0aX/v6anR1d0PHWojI9gzB75qYWD8OP+7rHYDHfxoF0NjYyE3GmD8CFAhZ+3V7+ZLx9AvKpRKeeuppGtw8aE9+Y2W4KRHfdH+M5RR0DmAYgQqS2mJSBwhEzLMK+Jl9GQ/boqSWl9gJYtFEhHq9QStXnoL29nZEcdNuKIqNRJgZ09PTOPfccxOOQgGgmTgUyPdHRoZ+Ct/z9w7A4z+FOCOpQ/Btl88bIsk2A21YYJWDSyFVx6r44x8fdg4A2Yh/yu5r7xSoANPT09i8yU4BGjFWnZegyUp1fbdSqUy7/DwGEAjkNJd6sDEG5ZYyTl11qnsRDDC5uX4DpRQu+cxncd9996OjvQPGaCEmFpHRchz8kz/5vQPw+O8h2Q/4vjGmbsdvC916yi/xNJtN3HPvPS73N2kNIB0DJjvzD7YtwJHRUTsEJClXdyBimsbwN/IJRG9v7/4A9hIRo5Tien0We+6xJw488EBbV1AMUvYhyuUS7rjjTlx22VfQ09ODWGsQkWFiBdAHNo1tehZ+1dc7AI//tgPgkZGRxwD8GxGxwHFpJ8NBuWpgECjce+999kNVqvBABIKQdjUAm/9PTk7aFMC6E+PUfm+tVgcfzhupAb/SOZ+YFaNRb+DUVavQ2tqCRqNh15O1dUL1eh3nn38+dBw71SLRzBwayC0jI0NrfOjvHYDH/+bzEVrjpIIz6j/JwnojgnK5BY88+gjGx8YRBKq4AwBAScYSPDg4iGazaRd3kKwbCkC0Jve8etmyZWUAZzjSUY5jjfaFHTj9NBv+J5uEOtZQSuHSSy/Db//939He0Y44jkWsmtEUiXl3LrXx8A7A478Jqx9QVj8zRh53J7FJhTxIUqntUhhi44aNePSxxwrhP+WYgJIe4KZNm6BteO4qBhSIyEYW+UX+yavVqQMI2B0imllxbbZG++6zD+23/37QlgvUTSOGePDBB/H5z3/BCXvEAkGsFCsQPlWpVNbBT/x5B+DxP4YtBm7eXGOi692J7hZnKJ+qQwUK0zMzuPfe+xz1nknnARJZ8ERx+JlnnoEYgzzLgICudsW/NH9glpcSEUPsanDUjHDqqlOtaq/WaTUviiKce94HMD0zjTAIAIFmpUqA/PvOS5Z8wRu/dwAef14tAE2SG4yYGtnqfEq7QzkmYCLIH/7whySvzx6ATGEkYNOmTXbXz+YEgRGZMrFanXM68TIsKwvhTFdv4CiKqKOjA6edZld/E9bfMAxw5Ve/hp//4hfoXNiBONYCAokxDYi8/Z577ongx329A/D4sxwAT1Yq6wT4hdXOyk5TcVK+xhiUyy209oEHqFarURiWsgcwJlspBjA4NARleQA0ERMTfj2WVegJACb6agcTsJuIaBUEPDs7iwMO2B977rknjDEwIgjCAH/60yP49EWfxqLOTmhtBIBh5gDAZ/2mn3cAHv83SFb6rnH/ork/FbGLQU8//TSefvrpnOFLSiEWhAFqtRoGBwcRhoHjBiEwqTXuOVIHAOhVALnhH4bWGqefdhqUUoiiGEQErTU+cP4HMTY+hjAIYUQ0M4XGyANtbS2f8sbvHYDH/2EaUC4Ht4iYJ4k4t0QjKQ+gUgqTkxOpdHgyDUhMINcxGKuOYXx8HEEQGgABjPnTTjvtmKj9avcfi8jJrmvAURSht68Xp7rqv3EkH1dddTVuueUWdC3qQqzjjH9M6N1u0w8+9PcOwOPPhwBQmzdvrkH4O07EU8MVAzNRX3vSP/jgg1kEYJLZIUcEMjqC6ekZCZRyYwF0ncvTlTv9ZYcddthTRPZzwz9Uq9XwwkNeiN132w3NZoTWlhb86U+P4MKPfxwdHe1WCETIMKtQRC4fGRm8Hb7n7x2Ax/+5EwAQXycidSIEiUoAkRsPEkEYlrB27QMw2oCV2kLqY2hoCFNTk0JMISC1traWb+drDQAQRfpUYioJJBYBNZtNnOpUf0QMtGi8//3nYnR0BGEQQkQMK1Ii8qQx8Yfgp/28A/D4i6QBPDo6+giEfkbELAKTHw4WMVIqleSRRx/FcKWCMAyKCkEANm7cJI1GQ4OIlFK/WL9+/dPI6Lg1ACail5MtEHDUbGLRok4cd+yxMAYol8v45jevwa233oquLifs4aaIhOQfq9XqJPy8v3cAHn+5z0tEvpGfDMzH+GEYYNOmjXj00UfdyS8pOad1ABvBrJjBKIXBVcmdE6MdGBjYWyAHGhGjFHO9XseLVqzAri/YFczA008/jU9edBEWdnYm3QVNRIEYff3o8PBNPvT3DsDjLwcNAKWS+rkx5gkQFarsIgJmhdnaLB5IJcOc4Kdj6Xx2w0ZTKpWDUjl8bPny5bci4+JnANBaTgIoTGS/QEQvOfMlpJRCHMU499wPYPPmzSiVQrGz/sSAbArD4B/hhT28A/D4i9cBAlsMxDeYKRdqi1X4FqEgDLB27QPZPQhQgaX/Wb9+vSmVQixoa/3GLbfc0pgT/hMzn+UYB6jRaKC/vw8nnnACAOCqq6/GjTfeiM6FnYhjDQKEiZkg7928efMIvLCHdwAef5VaAIyJr9fGTNk5/kwE2IhBa2sbHnroIdRqNYAUtDYIwxCzs7MyODgYAjK54447XpevLQCQHXbYZU8BXgSQKFZqcmICBx5wgCxduhRPPPkkPvnJT7nQP6H25lDEfK9SqXzfh/7eAXj89RwAj4+PryeRn1PKHIx0hKelXMaTTz2JJ554EmHIKVPw+Pi4mZqaoiAMfvzLX/5yIzIdXwaAOJ49BZAQQMTKDv+cduqpYGace+55qFaraG1thTFiiIiNmDGtQ0/y4R2Ax18ZrmjH1zk5MM4IAgisGNXqGO697z5363QNWE1PT5uunp6vosgYaKm/xJxi7JIQaa2xeMfn4RWvfAVdtWYNfvzjm7BoUae4LUJjl4To/dXqxg3wbT/vADz+6lGAtLe33gIx64gQkF0TTtk9jdZYe//9tgxgW4Bmw4YNPD09fe+6Rx65wz2OTvL2nXbaaUcGHWqXiognJ6ew6tRVNDExiXPPPU862tslimIAiJk5NCI3j4wMXe1Df+8APP76EADB+vXr6yB83wUAxhX7xRgj5XJZ/vjHh2GMcXz9ME89vR612dn/TymVcA7CfaVGIz6WlVpIQASAdBzTMUcdjfM/+EHMzMygVC5DRISsKOhYwPQuH/p7B+Dxt40CAJFrRUwd6ZqwZQVuaW3FE088gaGhIZRKJQEQjIyMTsPEN7ibmZwzERF9BmBZfhrNJu29fG/85re/wY9vugk9PT0wWkOsprcSI+cPDQ095UN/7wA8/rYOgEdHRx8RyL9Ztg8x4sbyyuUSbR4awgMPPJSG+n293d8DsF5rk8wPEAC968Cu/QKcYMmBoIIgQKPRxE03/QtaymWJYw1i0kqpUIz59cjI8Gof+nsH4DFPPj/R+IYdAkgnf0FEmK3V4AhCuNlsyqGHHnotAPr+97+PfPg/g/oxzNxtRCJjLNPvyMgIoiiCUgoixo76GlMzht8JT/DhHYDHvIAGgGpb+WYxZh2IAhAZAGK0CDPJAw88YACoKIqm2tvbHwMgr3jFKwrhv5H4JFcoFKc1AMXJ1DEAkLHLR/iIYw32e/7eAXjMAwiAABs2zILYFgMFBhAYo1Eul/HgQw9Jo9FEGATDl1xyyVjuvgRA77HHHh0QnOwMXQkV9QQAWJIPLbeOjAx/0Yf+3gF4zD8nAM34joiJBQjgdMRaWlrw7LPP4KmnnkKpXB665ppr6iJCTq6LAWB8fOpoYl4CkTgREkvmCaziH9gYqRGZd/nQ3zsAj/mZBvD48PADAH7DRCwQDQBBEGBmekYeeughABjOnfwpjNGniz3uLXOokBDIbhXYTT9FMBeNjIw8Di/n7R2Ax/z9HMVgTZ78080EidMMfDp3WwKgBwYGFhhL/UUgcEY2Lpbam6lkxNy9yy4jn/Ghv3cAHvM7CgCgbxKRDUQUWvlwQalUxv1r12JiYvopAPj1r3+d/9xXMNMugGgRsBMiT8cJjUhEkHfccw+ifLrh4R2Ax/yrA6jR0dEpiHzfnePaMQXTnx55BN/73veGAKBSqSRJPozBCbCxvqZkqM9V/Zk4gJFLRkZG7nWhvz/9t0GQfwu2KWduFvX17c8GdxORcrJhQsRBW8eCE5558sl/Q9bC477+gbsBOsgYE2eHgWgiCgW4b7TSeyjwsEaqRuThIwCP+Qq7JlyprAXklyBSItBELETAzMSMO8EPZljqr4MB7C9iNGDz/7RqAIiBvAt4uOlDf+8APLayz5Mg15Fl9XH/ZdHesmUTdvff4HQAygp/AMQAJaG/4LNjlcq/+9DfOwCPrQsaAOI4vtkY2QwgFGMkf4CvW7cutj7CJNN/7hogA6LQGLm/v7/3I/BVf+8APLY6CAA1MTExTpAfuIkfpwwuyfqv7uoaWE5EB1qNQXKcgAJAIkC/9eGHfejvHYDH1u0JxFwHq9Wn3GBARiCu5AxiDgWIXeaviSiANl8YHR39gw/9vQPw2LrTAKpWq78XyJ0AleYc5ESClen2IGCIUNLGPBqWw39214Q3fu8APLZiKABC4OsAqxFIZJlBu7u79xTIC7U2lg3YxgVaCGdv3ry5Bs/y4x2AxzYRBSAI6IfGmIqIII5tZECkjmXmMgBtRDSIAjFy6Vil8lsf+nsH4LGNlAAAqKGhoWGB/BggGCWz9vtynM0DoJmoZLSsY8bH4Kv+3gF4bHsgMd8gwLDmZk9PT4cAR1tFYWIAWkO/tVKpTOcch4d3AB7bSBpAY2NjdwrkQaNMSWs6moh7RTBLxCWBuWJidPTXPvTffhH4t2Cbd/AaghuUcImVHOtO+RajzRMi5sM+9PcXiMe2CwMAzLieWTUAPokIcLx//1CtVid96O8dgMe2i2RNeJOmuJ0IexMRacGXq9XKrT709/AOYNsHwbJ9HklEHMfmUYb5CPzAj4evAWwX0ABEIMcbY6Bh3j02Wp2Cp/b28Ng+IryFC/te0N3TK4sWdX/dO34PnwJsZ5+vUualIjLCjPf70N/DO4DtB0mIfyLEvNNV/f2sv4fHdgACgI6O3t07u3o+4b6n/Nvi4SOA7cgBALq3SfI1929f9PPw2M5Q8m+Bh4ePBjw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PDw8PP6i+P8BZkeghlJGjBoAAAAASUVORK5CYII="}
})
return Aroyn
