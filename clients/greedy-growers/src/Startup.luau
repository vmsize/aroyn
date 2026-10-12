-- Local Hub adapter. The approved UI core and its Collapse implementation are unchanged.
local function hubSafeBounds(w)
    local screen=w.OwnRoot or w.Root.Parent
    local b=screen.AbsoluteSize;local left,top,right,bottom=0,0,math.max(1,b.X),math.max(1,b.Y)
    local gui=game:GetService("GuiService")
    local ok,safe,area=pcall(function()
        return gui:GetInsetArea(Enum.ScreenInsets.CoreUISafeInsets),gui:GetInsetArea(screen.ScreenInsets
            or (screen.IgnoreGuiInset and Enum.ScreenInsets.None or Enum.ScreenInsets.CoreUISafeInsets))
    end)
    if ok then
        left=math.clamp(math.ceil(safe.Min.X-area.Min.X),0,right-1)
        top=math.clamp(math.ceil(safe.Min.Y-area.Min.Y),0,bottom-1)
        right=math.clamp(math.floor(safe.Max.X-area.Min.X),left+1,right)
        bottom=math.clamp(math.floor(safe.Max.Y-area.Min.Y),top+1,bottom)
    elseif screen.IgnoreGuiInset then
        local insetOK,tl,br=pcall(function() return gui:GetGuiInset() end)
        if insetOK then
            left=math.clamp(math.ceil(tl.X),0,right-1);top=math.clamp(math.ceil(tl.Y),0,bottom-1)
            right=math.clamp(right-math.ceil(br.X),left+1,right);bottom=math.clamp(bottom-math.ceil(br.Y),top+1,bottom)
        end
    end
    return left,top,right,bottom
end
local Startup={};Startup.__index=Startup
local STAGES={"assets","game","seeds","preferences","interface","observers","ready"}
local Storage=HubStorage
local TweenService=game:GetService("TweenService")
local TIMING={Entry=.30,Exit=.18,Morph=.48,Reveal=.20,RevealAt=.28,Retarget=.18}
local function envTable()
    if type(getgenv)=="function" then local ok,e=pcall(getgenv);if ok and type(e)=="table" then return e end end
    return _G
end
local function node(class,properties,parent)
    local o=Instance.new(class);for k,v in pairs(properties) do o[k]=v end;o.Parent=parent;return o
end
local function round(o,r) return node("UICorner",{CornerRadius=UDim.new(0,r)},o) end
-- Startup-only direction support; the approved shared Scope/Collapse stay intact.
-- Independent keys let progress size and logo position coexist with opacity.
function Startup:Animate(object,properties,duration,finished,style,direction,key)
    local scope=self.Scope;if not scope.Alive then return end
    key=key or object;scope:Cancel(key)
    local animation=TweenService:Create(object,TweenInfo.new(duration,
        style or Enum.EasingStyle.Sine,direction or Enum.EasingDirection.InOut),properties)
    scope.Animations[key]=animation
    local done
    done=scope:Connect(animation.Completed,function(playback)
        done:Disconnect();scope.Connections[done]=nil
        if scope.Animations[key]==animation then
            scope.Animations[key]=nil
            if finished and playback==Enum.PlaybackState.Completed then finished() end
        end
    end)
    animation:Play();return animation
end
function Startup:AssertCurrent()
    assert(self.State~="Destroyed" and self.State~="Failed" and self.Window.Root.Parent,"Startup was cancelled")
end
function Startup:Delay(seconds,callback)
    local thread
    thread=task.delay(seconds,function() self.Timers[thread]=nil;if self.Scope.Alive then callback() end end)
    self.Timers[thread]=true;return thread
end
function Startup:CancelTasks()
    self:StopAssetPreload()
    for thread in pairs(self.Timers) do pcall(task.cancel,thread) end;table.clear(self.Timers)
    local thread=self.Thread;self.Thread=nil
    if thread and thread~=coroutine.running() then pcall(task.cancel,thread) end
end
function Startup:AssetStatus(message)
    self:AssertCurrent();self.AssetStep=message;self.Status.Text=message
end
function Startup:StopAssetPreload()
    self.AssetLoadRecord=nil
    self.AssetRegisterRecord=nil
    for _,probe in ipairs(self.AssetProbes or {}) do probe:Destroy() end;self.AssetProbes=nil
    if self.AssetProbe then self.AssetProbe:Destroy();self.AssetProbe=nil end
    local worker=self.AssetWorker;self.AssetWorker=nil
    if worker and worker~=coroutine.running() then pcall(task.cancel,worker) end
end
function Startup:Bounds()
    local b=self.Window.OwnRoot and self.Window.OwnRoot.AbsoluteSize or self.Screen.AbsoluteSize
    return Vector2.new(math.max(1,b.X),math.max(1,b.Y))
end
function Startup:Geometry(compact)
    local left,top,right,bottom=hubSafeBounds(self.Window)
    local width=math.floor(math.min(compact and 356 or 1024,math.max(1,right-left-(compact and 24 or 32))))
    local height=math.floor(math.min(compact and 196 or 600,math.max(1,bottom-top-(compact and 24 or 32))))
    return UDim2.fromOffset(width,height),UDim2.fromOffset(left+math.floor((right-left-width)/2),top+math.floor((bottom-top-height)/2))
end
function Startup:Resize()
    if self.State=="Loading" or self.State=="FadingLoading" or self.State=="Failed" then
        self.Window.Root.Size,self.Window.Root.Position=self:Geometry(true)
    elseif self.State=="Expanding" then self:ExpandGeometry(self.Reduced and .08 or TIMING.Retarget,true) end
end
function Startup:Text(name,value,size,color,position,dimensions)
    return node("TextLabel",{Name=name,Text=value,FontFace=self.Aroyn.Theme.Fonts.Regular,TextSize=size,
        TextColor3=color,TextTransparency=1,TextStrokeTransparency=1,TextScaled=false,BackgroundTransparency=1,
        BorderSizePixel=0,TextXAlignment=Enum.TextXAlignment.Left,Position=position,Size=dimensions,ZIndex=112},self.Loading)
end
function Startup.new(Aroyn,info,options)
    local KEY=info.StartupId
    local e=envTable();local previous=rawget(e,KEY)
    if previous and type(previous.Destroy)=="function" then previous:Destroy() end
    local parent
    if type(gethui)=="function" then local ok,p=pcall(gethui);if ok and typeof(p)=="Instance" then parent=p end end
    parent=parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui",5)
    assert(parent,"Aroyn startup: GUI parent unavailable")
    local w=Aroyn:CreateWindow({Parent=parent,Id=info.Namespace,Title="AROYN · Greedy Growers",Logo="",
        Size=UDim2.fromOffset(1024,600),Config={Namespace=info.Namespace,FileSystem=Storage.FileSystem(info.StorageRoot,info.Namespace),DefaultConfig="main",AutoLoad=false,AutoSave=false}})
    local self=setmetatable({Aroyn=Aroyn,Window=w,Screen=w.OwnRoot,State="Loading",Completed=0,Stages={},
        Timers={},ProgressKey={},LogoFadeKey={},Environment=e,Options=options or {},Info=info,Key=KEY},Startup)
    self.Scope=getmetatable(w.Scope).new();e[KEY]=self
    self.Reduced=self.Options.ReducedMotion==true or Aroyn.MotionEnabled==false
    local ok,gui=pcall(function() return game:GetService("GuiService") end)
    if ok then local supported,value=pcall(function() return gui.ReducedMotionEnabled end);self.Reduced=self.Reduced or (supported and value==true) end
    self.Header=w.Root:FindFirstChild("Header");self.Header.Visible=false;w.Chrome.Visible=false
    self.HeaderInteractive=self.Header.Interactable;self.Header.Interactable=false
    -- Chrome follows this same shell during startup; no fixed desktop-sized child.
    w.Chrome.Size=UDim2.fromScale(1,1)
    w.Root:SetAttribute("AroynStartupBusy",true);w.Collapse.Gate:Set(true)
    self.Constraint=w.Root:FindFirstChildOfClass("UISizeConstraint");self.OriginalMin=self.Constraint.MinSize
    self.Constraint.MinSize=Vector2.new(0,0)
    self.Corner=w.Root:FindFirstChildOfClass("UICorner");self.Corner.CornerRadius=UDim.new(0,12)
    self.Edge=w.Root:FindFirstChildOfClass("UIStroke");self.Edge.Transparency=1
    w.Root.Size,w.Root.Position=self:Geometry(true);w.Root.BackgroundTransparency=1
    self.Mask=node("Frame",{Name="StartupRevealMask",BackgroundColor3=Aroyn.Theme.Colors.Window,BackgroundTransparency=0,
        BorderSizePixel=0,Active=false,Size=UDim2.fromScale(1,1),ZIndex=110},w.Root);round(self.Mask,12);self.Mask.Visible=false
    self.Loading=node("Frame",{Name="StartupContent",BackgroundTransparency=1,BorderSizePixel=0,Active=false,
        Size=UDim2.fromScale(1,1),ZIndex=111},w.Root)
    local C=Aroyn.Theme.Colors
    self.Brand=self:Text("Brand","AROYN",16,C.Text,UDim2.fromOffset(68,25),UDim2.new(1,-92,0,22));self.Brand.FontFace=Aroyn.Theme.Fonts.Semibold
    self.Build=self:Text("Build",info.DisplayVersion,11,C.TextDim,UDim2.fromOffset(24,0),UDim2.new(1,-48,0,20))
    self.Build.Position=UDim2.new(0,24,1,-30)
    self.Status=self:Text("Status","Preparing UI assets…",13,C.TextMuted,UDim2.fromOffset(24,82),UDim2.new(1,-48,0,42));self.Status.TextWrapped=true;self.Status.TextYAlignment=Enum.TextYAlignment.Top
    self.Count=self:Text("Stages","0 / "..#STAGES.." steps",10,C.TextDim,UDim2.new(0,24,1,-72),UDim2.new(1,-48,0,18))
    self.Track=node("Frame",{Name="ProgressTrack",BackgroundColor3=C.BorderSoft,BackgroundTransparency=1,BorderSizePixel=0,
        Position=UDim2.new(0,24,1,-50),Size=UDim2.new(1,-48,0,2),ZIndex=112},self.Loading)
    self.Fill=node("Frame",{Name="Progress",BackgroundColor3=C.TextMuted,BackgroundTransparency=1,BorderSizePixel=0,
        Size=UDim2.fromScale(0,1),ZIndex=113},self.Track)
    self.Logo=w.Collapse.Options.BrandLogo;self.LogoParent=self.Logo.Parent;self.LogoPosition=self.Logo.Position;self.LogoSize=self.Logo.Size;self.LogoZ=self.Logo.ZIndex
    self.Logo.Parent=w.Root;self.Logo.Position=UDim2.fromOffset(24,19);self.Logo.Size=UDim2.fromOffset(32,38);self.Logo.ZIndex=113;self.Logo.ImageTransparency=1
    local duration=self.Reduced and .05 or TIMING.Entry
    self:Animate(w.Root,{BackgroundTransparency=0},duration,function() self.EntryDone=true;if self.PendingReady then self:BeginMorph() end end)
    self:Animate(self.Edge,{Transparency=Aroyn.Theme.Borders.Normal},duration)
    for _,o in ipairs({self.Brand,self.Build,self.Status,self.Count}) do self:Animate(o,{TextTransparency=0},duration) end
    self:Animate(self.Track,{BackgroundTransparency=0},duration);self:Animate(self.Fill,{BackgroundTransparency=0},duration)
    self.Scope:Connect(self.Screen:GetPropertyChangedSignal("AbsoluteSize"),function() self:Resize() end)
    for _,property in ipairs({"ScreenInsets","IgnoreGuiInset","SafeAreaCompatibility"}) do
        local supported,signal=pcall(function() return self.Screen:GetPropertyChangedSignal(property) end)
        if supported then self.Scope:Connect(signal,function() self:Resize() end) end
    end
    local supported,signal=pcall(function() return game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset") end)
    if supported then self.Scope:Connect(signal,function() self:Resize() end) end
    self.Scope:Connect(self.Screen.DescendantAdded,function(o)
        if o.Name=="AroynOverlays" and self.State~="Ready" then o.Visible=false end
    end)
    self.Scope:Connect(w.Root.Destroying,function() self:Destroy() end)
    return self
end
-- Mobile rendering is capability-driven; optional graphics never masquerade as loaded.
function Startup:MobileAssets(package)
    local registration={Done=false};self.AssetRegisterRecord=registration
    self:AssetStatus("Preparing small mobile navigation images…")
    local worker=task.spawn(function()
        local ok,result=pcall(package.Prepare,function(message)
            self:AssertCurrent();assert(self.AssetRegisterRecord==registration,"Asset preparation cancelled")
            self:AssetStatus(message)
        end)
        if self.AssetRegisterRecord==registration and self.State=="Loading" then
            registration.Done=true;registration.Result=ok and result or {};registration.Error=not ok and tostring(result) or nil
        end
    end)
    if not registration.Done then self.AssetWorker=worker end
    self:Delay(6,function() registration.Expired=true end)
    while not registration.Done and not registration.Expired do self:AssertCurrent();task.wait(.05) end
    self:AssertCurrent()
    local result=registration.Result or {};result.Navigation=result.Navigation or {}
    self:StopAssetPreload()
    self.Aroyn.AssetDiagnostics={Mobile=true,RegistrationDone=registration.Done,RegistrationTimedOut=registration.Expired==true,
        RegistrationError=registration.Error,RegistrationErrors=result.Errors or {},NavigationLoaded=0,NavigationTotal=#package.Keys}
    local record={Loaded={},Failures={},Done=false};self.AssetLoadRecord=record
    local probes,byKey,uris={},{},{};self.AssetProbes=probes
    local duplicate={};local counts={}
    for _,key in ipairs(package.Keys) do
        local uri=result.Navigation[key]
        if type(uri)=="string" and uri~="" then counts[uri]=(counts[uri] or 0)+1 end
    end
    if result.Logo then counts[result.Logo]=(counts[result.Logo] or 0)+1 end
    for uri,count in pairs(counts) do if count>1 then duplicate[uri]=true end end
    local function probe(key,uri,index)
        if type(uri)~="string" or uri=="" or duplicate[uri] then return end
        local image
        if key=="logo" then
            image=self.Logo;image.Image=uri
            self:Animate(image,{ImageTransparency=0},self.Reduced and .05 or TIMING.Entry,nil,nil,nil,self.LogoFadeKey)
        else
            -- A nonzero-alpha, on-screen native ImageLabel really participates in
            -- rendering. The former fully transparent 1px probe could be culled.
            image=node("ImageLabel",{Name="MobileAssetProbe_"..key,BackgroundTransparency=1,ImageTransparency=.99,
                Visible=true,Size=UDim2.fromOffset(24,24),Image=uri,
                Position=UDim2.new(1,-(#package.Keys-index+1)*26-16,0,54),ZIndex=114},self.Loading)
            table.insert(probes,image)
        end
        byKey[key]=image;uris[key]=uri
    end
    probe("logo",result.Logo,0)
    for index,key in ipairs(package.Keys) do probe(key,result.Navigation[key],index) end
    local function loaded(key)
        local image=byKey[key];return image and (image.IsLoaded==true or record.Loaded[uris[key]]==true) or false
    end
    local ok,provider=pcall(function()return game:GetService("ContentProvider")end)
    if ok and provider and next(byKey) then
        local instances={};for _,image in pairs(byKey) do table.insert(instances,image) end
        local preload=task.spawn(function()
            local success,detail=pcall(function()
                provider:PreloadAsync(instances,function(asset,status)
                    if self.State~="Loading" or self.AssetLoadRecord~=record then return end
                    local uri=typeof(asset)=="Instance" and asset.Image or asset
                    if status==Enum.AssetFetchStatus.Success then record.Loaded[uri]=true
                    else record.Failures[uri]=tostring(status.Name) end
                end)
            end)
            if self.AssetLoadRecord==record then record.Done=true;record.Error=not success and tostring(detail) or nil end
        end)
        if not record.Done then self.AssetWorker=preload end
    else record.Done=true;record.Error="Image preload service unavailable" end
    self:Delay(6,function()record.Expired=true end)
    local last
    while true do
        self:AssertCurrent()
        local ready=0;for _,key in ipairs(package.Keys) do if loaded(key) then ready+=1 end end
        local logo=loaded("logo")
        local status="Mobile navigation "..ready.." / "..#package.Keys.." · logo "..(logo and "ready" or "pending")
        if status~=last then last=status;self:AssetStatus(status) end
        if ready==#package.Keys and logo or record.Expired or not next(byKey) then break end
        -- Definitive preload failures permit an immediate honest native fallback.
        if record.Done and (record.Error or next(record.Failures)) then break end
        task.wait(.05)
    end
    local navigation={};local missing={};local ready=0
    for _,key in ipairs(package.Keys) do
        if loaded(key) then navigation[key]=uris[key];ready+=1 else missing[key]=true end
    end
    local logo=loaded("logo")
    self.Aroyn.NavigationImages=navigation
    self.Aroyn.NativeAssetFallback={Navigation=next(missing)~=nil,Missing=missing,Logo=not logo}
    local usableLogo=type(result.Logo)=="string" and not duplicate[result.Logo] and result.Logo or ""
    self.Aroyn.Logo=usableLogo;self.Aroyn.IconAtlas=navigation.cart or ""
    self.Logo.Image=self.Aroyn.Logo;self.Window.Collapse.Options.Logo.Image=self.Aroyn.Logo
    local diagnostics=self.Aroyn.AssetDiagnostics
    diagnostics.NavigationLoaded=ready;diagnostics.LogoLoaded=logo;diagnostics.PreloadError=record.Error
    diagnostics.Mode=next(missing) and "native-page-label-fallback" or "individual-png"
    self.AssetVerification=diagnostics.Mode
    self:StopAssetPreload()
    if self.Aroyn.Logo=="" then
        local floating=self.Window.Collapse.Options.Logo
        node("TextLabel",{Name="NativeBrandWordmark",Text="AROYN",TextSize=8,
            Font=Enum.Font.SourceSansSemibold,TextColor3=self.Aroyn.Theme.Colors.Text,ZIndex=floating.ZIndex+1,
            BackgroundTransparency=1,Size=UDim2.fromScale(1,1)},floating)
    end
    if next(missing) or not logo then
        warn("[Aroyn assets] "..diagnostics.Mode.."; logo="..tostring(logo).."; navigation="..ready.."/"..#package.Keys..
            "; PNG APIs returned="..tostring(registration.Done).."; continuing with verified native UI fallback")
    end
    self:AssetStatus(next(missing) and "Native page navigation fallback prepared" or "Small navigation PNGs ready")
end
function Startup:SetAssets()
    if self.Aroyn.MobileAssetsPreferred and self.Aroyn.MobileAssetPackage then return self:MobileAssets(self.Aroyn.MobileAssetPackage) end
    self:AssertCurrent()
    assert(type(self.Aroyn.Logo)=="string" and self.Aroyn.Logo~="","Aroyn logo unavailable: executor needs writefile and getcustomasset/getsynasset")
    assert(type(self.Aroyn.IconAtlas)=="string" and self.Aroyn.IconAtlas~="","Navigation atlas unavailable: check executor custom asset support")
    assert(self.Aroyn.Logo~=self.Aroyn.IconAtlas,"Logo and icon atlas share one custom asset URI; executor asset registration failed")
    self.Logo.Image=self.Aroyn.Logo;self.Window.Collapse.Options.Logo.Image=self.Aroyn.Logo
    self:Animate(self.Logo,{ImageTransparency=0},self.Reduced and .05 or TIMING.Entry,
        nil,nil,nil,self.LogoFadeKey)
    local ok,provider=pcall(function() return game:GetService("ContentProvider") end)
    assert(ok and provider,"ContentProvider unavailable; cannot validate required UI assets")
    self:AssetStatus("Loading logo and navigation images…")
    -- Preload must not own the coordinator's execution thread. Some custom URI
    -- adapters can display images while their PreloadAsync request never returns.
    local probe=node("ImageLabel",{Name="AssetLoadProbe",BackgroundTransparency=1,ImageTransparency=1,
        Visible=true,Size=UDim2.fromOffset(1,1),Image=self.Aroyn.IconAtlas},self.Loading)
    self.AssetProbe=probe
    local record={Loaded={},Done=false};self.AssetLoadRecord=record
    local worker=task.spawn(function()
        local success,detail=pcall(function()
            provider:PreloadAsync({self.Aroyn.Logo,self.Aroyn.IconAtlas},function(asset,status)
                if self.State~="Loading" or self.AssetLoadRecord~=record then return end
                if status==Enum.AssetFetchStatus.Success then record.Loaded[asset]=true
                else
                    record.Error="Required UI asset could not load ("..tostring(status.Name)..")"
                    if not (self.Logo.IsLoaded==true and probe.IsLoaded==true) then self:Fail(record.Error) end
                end
            end)
        end)
        if self.AssetLoadRecord==record then
            record.Done=true;if not success then record.Error="UI image preload failed: "..tostring(detail) end
        end
    end)
    if not record.Done then self.AssetWorker=worker end
    while true do
        self:AssertCurrent()
        local rendered=self.Logo.IsLoaded==true and probe.IsLoaded==true
        local confirmed=record.Loaded[self.Aroyn.Logo] and record.Loaded[self.Aroyn.IconAtlas]
        if rendered or confirmed then
            self.AssetVerification=rendered and "ImageLabel.IsLoaded" or "ContentProvider.Success"
            self:StopAssetPreload();self.AssetLoadRecord=nil;return
        end
        if record.Error then
            probe:Destroy();self.AssetProbe=nil;error(record.Error,0)
        end
        -- A bounded startup-only wait for real readiness, never simulated progress
        -- or a permanent frame listener. The independent 45s watchdog remains active.
        task.wait(.05)
    end
end
function Startup:Complete(stage,label)
    self:AssertCurrent();assert(STAGES[self.Completed+1]==stage,"Unexpected startup stage: "..tostring(stage))
    self.Completed+=1;table.insert(self.Stages,{Id=stage,Label=label});self.Status.Text=label
    self.Count.Text=tostring(self.Completed).." / "..#STAGES.." steps"
    self:Animate(self.Fill,{Size=UDim2.fromScale(self.Completed/#STAGES,1)},self.Reduced and .03 or .12,
        nil,Enum.EasingStyle.Quad,Enum.EasingDirection.Out,self.ProgressKey)
end
function Startup:BindApp(app) self:AssertCurrent();self.App=app end
function Startup:BindUI(window)
    assert(window==self.Window,"Startup must reuse its actual Window shell")
    self:AssertCurrent()
    if self.Aroyn.NativeAssetFallback and self.Aroyn.NativeAssetFallback.Navigation then
        assert(#window.Pages==8,"Native fallback requires all eight Hub pages")
        for _,page in ipairs(window.Pages) do
            assert(page.Scope.Alive and page.Navigation:IsA("TextButton"),"Native page navigation unavailable")
            if page.Icon:GetAttribute("AroynNativeNavigation") then
                local label=page.Navigation:FindFirstChild("NativeAssetPageLabel")
                assert(label and label.Text~="" and label.Parent==page.Navigation,"Native fallback page label unavailable")
            end
        end
    end
    window.Collapse.Gate:Set(false);window.Collapse.Gate:Set(true)
    self.SavedMinimize=window.SetMinimized
    window.SetMinimized=function() return false end -- restored exactly after startup; Collapse itself is untouched
end
function Startup:Ready()
    self:AssertCurrent();assert(self.Completed==#STAGES,"Initialization is incomplete")
    if self.EntryDone then self:BeginMorph() else self.PendingReady=true end
end
function Startup:BeginMorph()
    if self.State~="Loading" then return end
    self.State="FadingLoading";self.PendingReady=nil
    local duration=self.Reduced and .04 or TIMING.Exit
    -- Final real progress can finish its 120ms update during the 180ms fade.
    for _,o in ipairs({self.Brand,self.Build,self.Status,self.Count}) do self:Animate(o,{TextTransparency=1},duration) end
    self:Animate(self.Track,{BackgroundTransparency=1},duration)
    self:Animate(self.Fill,{BackgroundTransparency=1},duration,function()
        if self.State~="FadingLoading" then return end
        self.Loading.Visible=false;self.State="Expanding";self.Mask.Visible=true
        local d=self.Reduced and .08 or TIMING.Morph
        self:Animate(self.Corner,{CornerRadius=UDim.new(0,self.Aroyn.Theme.Metrics.WindowRadius)},d,nil,Enum.EasingStyle.Cubic)
        self:Animate(self.Mask:FindFirstChildOfClass("UICorner"),
            {CornerRadius=UDim.new(0,self.Aroyn.Theme.Metrics.WindowRadius)},d,nil,Enum.EasingStyle.Cubic)
        self:Animate(self.Logo,{Position=self.LogoPosition,Size=self.LogoSize},d,nil,Enum.EasingStyle.Cubic)
        self:ExpandGeometry(d)
        self:Delay(self.Reduced and .04 or TIMING.RevealAt,function() self:Reveal() end)
    end)
end
function Startup:ExpandGeometry(duration,retarget)
    self.GeometryDone=false
    local size,position=self:Geometry(false)
    self:Animate(self.Window.Root,{Size=size,Position=position,BackgroundTransparency=0},duration,function()
        self.GeometryDone=true;if self.RevealDone then self:Finish() end
    end,retarget and Enum.EasingStyle.Quad or Enum.EasingStyle.Cubic,
        retarget and Enum.EasingDirection.Out or Enum.EasingDirection.InOut)
end
function Startup:Reveal()
    if self.State~="Expanding" or self.Revealing then return end
    self.Revealing=true;self.Header.Visible=true;self.Window.Chrome.Visible=true
    -- One ordinary rounded Frame blends native content into view. No CanvasGroup,
    -- UIScale, descendant opacity fan-out, input shield or copied window shell.
    self:Animate(self.Mask,{BackgroundTransparency=1},self.Reduced and .04 or TIMING.Reveal,function()
        self.RevealDone=true;if self.GeometryDone then self:Finish() end
    end)
end
function Startup:Finish()
    if self.State~="Expanding" then return end
    local w=self.Window;w.Root.Size,w.Root.Position=self:Geometry(false)
    self.Constraint.MinSize=Vector2.new(math.min(self.OriginalMin.X,w.Root.Size.X.Offset),self.OriginalMin.Y)
    self.Corner.CornerRadius=UDim.new(0,self.Aroyn.Theme.Metrics.WindowRadius)
    self.Logo.Parent=self.LogoParent;self.Logo.Position=self.LogoPosition;self.Logo.Size=self.LogoSize;self.Logo.ZIndex=self.LogoZ;self.Logo.ImageTransparency=0
    self.Loading:Destroy();self.Mask:Destroy();self.State="Ready"
    self.Header.Interactable=self.HeaderInteractive
    if self.SavedMinimize then w.SetMinimized=self.SavedMinimize end
    w.Collapse.Gate:Set(false);w.Root:SetAttribute("AroynStartupBusy",nil)
    if w.Overlays then w.Overlays.Portal.Visible=true end
    self:CancelTasks();self.Scope:Destroy()
    if rawget(self.Environment,self.Key)==self then self.Environment[self.Key]=nil end
    if self.App and self.App.Integration then self.App.Integration.Dashboard:Resume() end
end
function Startup:OnRuntimeDestroy()
    if not self.Cleaning then self:Destroy() end
end
function Startup:ClearPartialSingleton()
    -- A factory can fail after claiming its local singleton but before defining
    -- Destroy. Clear only this attempt's identity, never another/production App.
    for _,key in ipairs({self.Info.RuntimeId,self.Info.RuntimeId.."_LEGACY"}) do
        if self.App and rawget(self.Environment,key)==self.App then self.Environment[key]=nil end
    end
end
function Startup:Fail(message)
    if self.State=="Destroyed" or self.State=="Failed" then return end
    self.State="Failed";self.Error=tostring(message)
    self.Scope:Cancel(self.ProgressKey);self.Scope:Cancel(self.LogoFadeKey)
    for _,o in ipairs({self.Window.Root,self.Corner,self.Edge,self.Logo,self.Mask,self.Brand,self.Build,self.Status,self.Count,self.Track,self.Fill}) do self.Scope:Cancel(o) end
    self.Header.Visible=false;self.Window.Chrome.Visible=false;self.Mask.Visible=false;self.Loading.Visible=true
    self.Window.Root.BackgroundTransparency=0;self.Edge.Transparency=self.Aroyn.Theme.Borders.Normal
    self.Window.Root.Size,self.Window.Root.Position=self:Geometry(true)
    self.Brand.TextTransparency=0;self.Brand.Text="AROYN · Startup failed"
    self.Status.Text=self.Error:gsub("^.-:%d+: ","");self.Status.TextTransparency=0;self.Status.TextSize=12
    self.Build.TextTransparency=0;self.Count.Visible=false;self.Track.Visible=false
    self:CancelTasks()
    self.Cleaning=true
    -- Keep this exact shell for the error state while normal App.Destroy cleans
    -- all real observers, config managers, pages and workers. No new screen swap.
    if self.App and self.App.Integration then
        local ui=self.App.Integration.UI;ui.ScreenGui=nil
    end
    self.Window.OwnRoot=nil
    if self.App and type(self.App.Destroy)=="function" then pcall(self.App.Destroy) end
    self:ClearPartialSingleton()
    if self.Window.Scope.Alive then self.Window:Destroy() end
    self.Cleaning=false
    self.Scope:Cancel(self.ProgressKey);self.Scope:Cancel(self.LogoFadeKey)
    for _,o in ipairs({self.Window.Root,self.Corner,self.Edge,self.Logo,self.Mask,self.Brand,self.Build,self.Status,self.Count,self.Track,self.Fill}) do self.Scope:Cancel(o) end
    self.Header.Visible=false;self.Window.Chrome.Visible=false;self.Mask.Visible=false;self.Loading.Visible=true
    self.Window.Root.BackgroundTransparency=0;self.Edge.Transparency=self.Aroyn.Theme.Borders.Normal
    self.Window.Root.Size,self.Window.Root.Position=self:Geometry(true);self.Corner.CornerRadius=UDim.new(0,12)
    self.Brand.TextTransparency=0;self.Brand.Text="AROYN · Startup failed";self.Build.TextTransparency=0
    self.Status.Text=self.Error:gsub("^.-:%d+: ","");self.Status.TextTransparency=0;self.Status.TextSize=12
    warn("[Aroyn startup] "..self.Error)
    self.Count.Visible=false;self.Track.Visible=false
    local function button(label,x,fn)
        local b=node("TextButton",{Text=label,FontFace=self.Aroyn.Theme.Fonts.Medium,TextSize=12,TextColor3=self.Aroyn.Theme.Colors.Text,
            BackgroundColor3=self.Aroyn.Theme.Colors.Surface3,AutoButtonColor=false,BorderSizePixel=0,Size=UDim2.fromOffset(80,28),
            Position=UDim2.new(0,x,1,-64),ZIndex=115},self.Loading);round(b,4);self.Scope:Connect(b.Activated,fn);return b
    end
    if self.Restart then self.RetryButton=button("Retry",24,function() local restart=self.Restart;self:Destroy();restart() end) end
    self.CloseButton=button("Close",self.Restart and 112 or 24,function() self:Destroy() end)
end
function Startup:Destroy()
    if self.State=="Destroyed" then return end
    self.State="Destroyed";self:CancelTasks();self.Scope:Destroy()
    if rawget(self.Environment,self.Key)==self then self.Environment[self.Key]=nil end
    self.Cleaning=true
    if self.App and type(self.App.Destroy)=="function" then pcall(self.App.Destroy) end
    self:ClearPartialSingleton()
    self.Cleaning=false
    if self.Window.Scope.Alive then self.Window:Destroy() end
    if self.Screen.Parent then self.Screen:Destroy() end
end
function Startup.Run(Aroyn,info,assets,runtime,ui,options)
    options=table.clone(options or {});options.Storage=options.Storage or Storage
    Aroyn.HubBuildInfo=info
    local self=Startup.new(Aroyn,info,options)
    self.Restart=function() return Startup.Run(Aroyn,info,assets,runtime,ui,options) end
    self:Delay(45,function() if self.State=="Loading" then self:Fail("Initialization timed out at: "..tostring(self.Completed==0 and self.AssetStep or self.Status.Text).."; check executor asset support") end end)
    local completed=false
    local thread=task.spawn(function()
        local ok,err=pcall(function()
            for _,key in ipairs({"__AROYN_FARM_SINGLETON","__AROYN_SEED_SINGLETON","__FARM_ASSISTANT_V3_SINGLETON","__SEED_AUTO_BUY_SINGLETON_V1","__AROYN_GREEDY_PHASE6A","__AROYN_PHASE9A_STARTUP","__AROYN_GREEDY_PHASE11A","__AROYN_PHASE11A_STARTUP","__AROYN_HUB_GREEDY","__AROYN_HUB_GREEDY_NATIVE"}) do
                local active=rawget(self.Environment,key)
                assert(key==info.RuntimeId or not(type(active)=="table" and type(active.Destroy)=="function"),"Close the existing Aroyn Hub before starting this build")
            end
            assets(Aroyn,function(message) self:AssetStatus(message) end);self:SetAssets();self:Complete("assets",self.AssetVerification=="native-page-label-fallback" and "Native navigation fallback ready" or "UI assets ready")
            local opts=table.clone(options or {});opts.Startup=self;opts.BuildInfo=info;opts.DeferBootstrap=true;opts.DashboardAutoConnect=false
            local app=runtime(Aroyn,ui,opts);self:BindApp(app)
            local booted,detail=app.Bootstrap();assert(booted,detail or "Client initialization failed")
            self:Ready()
        end)
        completed=true;self.Thread=nil;if not ok and self.State~="Destroyed" then self:Fail(err) end
    end)
    -- Bounded critical startup; optional Dashboard never participates in readiness.
    if not completed then self.Thread=thread end
    return self
end
return Startup
