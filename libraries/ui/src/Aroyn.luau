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
