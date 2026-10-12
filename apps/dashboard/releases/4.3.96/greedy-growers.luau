-- Aroyn Hub 4.3.96 production candidate; NOT published.
-- Automation starts OFF; Dashboard resumes only confirmed persistent intent.
local HubStorage=(function()
-- Hub-only filesystem adapter. The reusable UI core remains unchanged.
local Storage={}
local Http=game:GetService("HttpService")
local function safeName(name)
    if type(name)~="string" or #name<1 or #name>64 or not name:match("^[a-zA-Z0-9][a-zA-Z0-9_-]*$") then return nil end
    return name:lower()
end
-- Tiny independent records: no keys, active automation or profile values here.
function Storage.Record(path,validate)
    local self={Path=path,Available=type(readfile)=="function" and type(writefile)=="function"}
    function self:Read()
        if not self.Available then return nil,"SessionOnly" end
        if type(isfile)=="function" then
            local checked,exists=pcall(isfile,path)
            if not checked then return nil,"ReadFailed" end
            if not exists then return nil,"Missing" end
        end
        local ok,raw=pcall(readfile,path)
        if not ok then return nil,"ReadFailed" end
        local parsed,data=pcall(Http.JSONDecode,Http,raw)
        if not parsed or type(data)~="table" or not validate(data) then return nil,"InvalidRecord" end
        return data
    end
    function self:Write(data)
        if not self.Available then return false,"SessionOnly" end
        if not validate(data) then return false,"InvalidRecord" end
        local ok=pcall(function()
            local folder=""
            for part in path:match("^(.*)/"):gmatch("[^/]+") do
                folder=folder=="" and part or folder.."/"..part
                if type(makefolder)=="function" and (type(isfolder)~="function" or not isfolder(folder)) then makefolder(folder) end
            end
            local raw=Http:JSONEncode(data)
            writefile(path,raw)
            assert(readfile(path)==raw,"Readback mismatch")
        end)
        if ok then return true end
        return false,"WriteFailed"
    end
    return self
end
function Storage.Preferences(window,info,warn)
    local cfg=window.Config
    local record=Storage.Record(info.StorageRoot.."/preferences-"..info.Namespace..".json",function(d)
        return d.SchemaVersion==1 and safeName(d.Profile)~=nil and type(d.AutoSave)=="boolean"
    end)
    local data,readError=record:Read()
    local self={Profile=data and data.Profile or "main",AutoSave=not data or data.AutoSave,Record=record}
    if readError and readError~="Missing" then warn("Preference metadata unavailable ("..readError..").") end
    function self:Remember()
        local ok,why=record:Write({SchemaVersion=1,Profile=self.Profile,AutoSave=self.AutoSave})
        if not ok then warn("Preference selection could not be saved ("..why..").") end
        return ok
    end
    function self:Select(name)
        name=safeName(name);if not name then return end
        self.Profile=name;cfg.AutoSaveName=name
        if data==nil or data.Profile~=name then self:Remember();data={Profile=name} end
    end
    function self:SetAutoSave(enabled)
        if cfg.SaveJob then self:Flush() end
        self.AutoSave=enabled;window:SetConfigAutoSave(enabled,self.Profile,.75);self:Remember()
    end
    function self:Flush()
        if cfg.Alive and cfg.SaveJob and self.AutoSave then
            cfg:_CancelSave();return cfg:Save(self.Profile)
        end
        return true
    end
    local save=cfg.Save
    cfg.Save=function(manager,name)
        local ok,result=save(manager,name)
        if not ok then warn("Preferences could not be saved ("..tostring(result.Code)..").")
        elseif safeName(name) then self:Select(name) end
        return ok,result
    end
    return self
end
function Storage.FileSystem(root,namespace)
    local fs={};local logical="AroynUILab/configs/"..namespace.."/";local physical=root.."/profiles/"..namespace.."/"
    local function map(path)
        if path=="AroynUILab" then return root end
        if path=="AroynUILab/configs" then return root.."/profiles" end
        if path:sub(1,#logical)==logical then return physical..path:sub(#logical+1) end
        if path==logical:sub(1,-2) then return physical:sub(1,-2) end
        return path
    end
    local functions={isfolder=isfolder,makefolder=makefolder,isfile=isfile,readfile=readfile,writefile=writefile,delfile=delfile,listfiles=listfiles}
    for key,fn in pairs(functions) do
        if type(fn)=="function" then
            fs[key]=function(path,...)
                local result=fn(map(path),...)
                if key=="listfiles" and type(result)=="table" then
                    local mapped={}
                    for _,p in pairs(result) do
                        if type(p)=="string" then
                            p=p:gsub("\\","/")
                            local start=p:find(physical,1,true)
                            if start and (start==1 or p:sub(start-1,start-1)=="/") then p=logical..p:sub(start+#physical) end
                            table.insert(mapped,p)
                        end
                    end
                    return mapped
                end
                return result
            end
        end
    end
    return fs
end
function Storage.Bind(window,info)
    local cfg=window.Config;local fs=cfg.FileSystem
    local write,read=fs.writefile,fs.readfile
    local backupRoot=info.StorageRoot.."/profile-backups/"..info.Namespace.."/"
    local self={Window=window,Config=cfg,BackupRoot=backupRoot}
    if cfg.Mode~="File" then
        function self:Restore() return false,{Code="SessionOnly",Message="Recovery copies require file storage"} end
        return self
    end
    local function decoded(raw)
        if type(raw)~="string" or #raw>262144 then return nil end
        local ok,data=pcall(Http.JSONDecode,Http,raw);return ok and type(data)=="table" and data or nil
    end
    local function valid(raw)
        local data=decoded(raw)
        if not data or data.SchemaVersion~=1 or data.Namespace~=info.Namespace or type(data.Values)~="table" then return false end
        local count=0
        for key,record in pairs(data.Values) do
            count+=1
            if count>512 or type(key)~="string" or type(record)~="table" then return false end
            local t,v=record.Type,record.Value
            if t=="Input" then if type(v)~="string" or #v>16384 then return false end
            elseif t=="Toggle" then if type(v)~="boolean" then return false end
            elseif t=="Slider" then if type(v)~="number" or v~=v or math.abs(v)==math.huge then return false end
            elseif t=="Dropdown" then
                if record.Multi then if type(v)~="table" then return false end;for _,x in pairs(v) do if type(x)~="string" then return false end end
                elseif type(v)~="string" and v~=false then return false end
            elseif t=="Keybind" then if type(v)~="table" or type(v.Key)~="string" or not table.find({"Toggle","Hold","Always"},v.Mode) then return false end
            else return false end
        end
        return true
    end
    local function get(path) local ok,raw=pcall(read,path);return ok and raw or nil end
    local function ensureBackup()
        if type(fs.makefolder)=="function" then
            for _,p in ipairs({info.StorageRoot,info.StorageRoot.."/profile-backups",backupRoot:sub(1,-2)}) do
                if type(fs.isfolder)~="function" or not fs.isfolder(p) then fs.makefolder(p) end
            end
        end
    end
    fs.writefile=function(path,raw)
        local name=path:sub(1,#cfg.Path)==cfg.Path and safeName(path:sub(#cfg.Path+1):match("^(.-)%.json$"))
        if not name then return write(path,raw) end -- __index and unrelated operations are core-owned.
        assert(valid(raw),"Profile payload failed validation")
        local old=get(path);local oldData=decoded(old)
        assert(old==nil or valid(old),"Existing profile is invalid; restore a backup or explicitly delete it")
        assert(not oldData or oldData.SchemaVersion==1,"Unsupported profile schema; existing file kept")
        assert(not oldData or oldData.Namespace==info.Namespace,"Profile namespace mismatch; existing file kept")
        local backup=backupRoot..name..".json"
        if valid(old) then
            ensureBackup();write(backup,old)
            assert(get(backup)==old,"Recovery copy could not be verified; profile kept")
        else old=get(backup);if not valid(old) then old=nil end end
        local ok,err=pcall(write,path,raw)
        if ok and get(path)==raw then return end
        if old then
            local restored=pcall(write,path,old)
            if restored and get(path)==old then error("Profile write failed; previous profile restored",0) end
            error("Profile write failed; recovery copy retained; restore required",0)
        end
        error("Profile write failed; no prior recovery copy: "..tostring(err or "readback mismatch"),0)
    end
    function self:Restore(name)
        return cfg:_Run(function()
            name=safeName(name);if not name then return cfg:_Result(false,"InvalidName","Invalid profile name") end
            cfg:_CancelSave()
            local raw=get(backupRoot..name..".json")
            if not valid(raw) then return cfg:_Result(false,"BackupUnavailable","A valid recovery copy is unavailable") end
            local names,code,detail=cfg:_Names()
            if not names then return cfg:_Result(false,code,detail) end
            local ready,err=cfg:_EnsureFolder();if not ready then return cfg:_Result(false,"FolderFailed",err) end
            local ok,why=pcall(write,cfg.Path..name..".json",raw)
            if not ok or get(cfg.Path..name..".json")~=raw then return cfg:_Result(false,"RestoreFailed",tostring(why or "Readback mismatch")) end
            if not table.find(names,name) then table.insert(names,name);table.sort(names) end
            local indexed,message=cfg:_WriteIndex(names)
            if not indexed then return cfg:_Result(false,"IndexWriteFailed",message,{FileSaved=true}) end
            return cfg:_Result(true,"Restored","Previous saved profile restored")
        end)
    end
    return self
end
return Storage

end)()
local function HubDashboardFactory(C)
local factory=(function()
-- Hub connection coordinator. Protocol primitives remain in GreedyRuntime.
-- No new endpoints, credentials in profiles, or fabricated runtime data.
return function(C)
    local W,options=C.Web,C.Options
    local store=options.Storage.Record(options.BuildInfo.CredentialPath:gsub("web_config%.json$","connection-intent.json"),function(d)
        return d.SchemaVersion==1 and type(d.Enabled)=="boolean" and (d.AccountId==nil or type(d.AccountId)=="string")
    end)
    local intent,readError=store:Read()
    local self={State="Disconnected",Enabled=intent and intent.Enabled==true or false,AccountId=intent and intent.AccountId,
        Ticket=0,Alive=true,Store=store,ReadError=readError}
    local request=W.Request
    -- Record only HTTP codes for classification. Never retain backend body/key in UI diagnostics.
    W.Request=function(...)
        if not self.Alive or not C.State.running then return false,"Cancelled" end
        local ticket=self.Ticket
        local ok,result=request(...)
        if not self.Alive or ticket~=self.Ticket then return false,"Cancelled" end
        if not ok then self.HttpStatus=tonumber(tostring(result):match("HTTP (%d+)")) end
        return ok,ok and result or (self.HttpStatus and "HTTP "..self.HttpStatus or "Network request failed")
    end
    local function active(ticket) return self.Alive and C.State.running and self.Ticket==ticket end
    local function cancel(thread) if thread and thread~=coroutine.running() then pcall(task.cancel,thread) end end
    function self:Changed(state,message)
        self.State=state;self.Message=message
        if self.OnChange then self.OnChange(state,message) end
    end
    function self:Warn(message) if self.OnWarning then self.OnWarning(message) end end
    function self:ReleasePresence()
        -- Best-effort bounded teardown, captured BEFORE local credentials/tokens clear.
        -- This existing Live endpoint is session-scoped, unlike /runtime/disconnect.
        if not W.presenceToken then return end
        local fn=W.ResolveRequest();if type(fn)~="function" then return end
        local encoded,body=W.EncodePayload({sessionId=W.sessionId},false);if not encoded then return end
        local headers={Accept="application/json",["Content-Type"]="application/json",["X-Presence-Token"]=W.presenceToken}
        if W.ValidKey(W.key) then headers.Authorization="Bearer "..W.NormalizeKey(W.key) end
        local done,timer=false,nil
        local thread=task.spawn(function()
            pcall(fn,{Url=W.liveHttpBase.."/runtime-presence/disconnect",Method="POST",Headers=headers,Body=body})
            done=true;if timer then pcall(task.cancel,timer) end
        end)
        if not done then timer=task.delay(3,function() pcall(task.cancel,thread) end) end
    end
    function self:Persist(enabled,account)
        self.Enabled=enabled;self.AccountId=account or self.AccountId
        local ok,why=store:Write({SchemaVersion=1,Enabled=enabled,AccountId=self.AccountId})
        if not ok then self:Warn("Dashboard auto-connect preference could not be saved ("..why..").") end
        return ok
    end
    function self:StopTransport()
        cancel(W.thread);W.thread=nil
        cancel(W.presenceThread);W.presenceThread=nil
        cancel(W.updateThread);W.updateThread=nil
        W.DisconnectLive();W.ClosePresenceSocket()
        W.presenceToken=nil;W.presenceLastOk=false;W.lastPushOk=false
        W.presenceHttpKey=nil;W.presenceHttpDueAt=0;W.liveLastAckAt=nil
        -- Do not send the legacy account-wide /runtime/disconnect during replacement:
        -- its backend contract ignores sessionId and could mark a newer runtime offline.
        -- Socket closure + existing server TTL expire genuine presence naturally.
    end
    function self:Cancel()
        self.Ticket+=1;cancel(self.Worker);self.Worker=nil
        cancel(self.Runner);self.Runner=nil
        self:StopTransport()
    end
    function self:Bounded(ticket,fn)
        local done,okay,a,b,c=false,false,nil,nil,nil
        local thread=task.spawn(function() okay,a,b,c=pcall(fn);done=true end)
        if not done then self.Worker=thread end
        local started=os.clock()
        while not done and active(ticket) and os.clock()-started<15 do task.wait(.05) end
        cancel(thread);if self.Worker==thread then self.Worker=nil end
        if not active(ticket) then return false,"Cancelled" end
        if not done then return false,"Network timeout" end
        if not okay then return false,"Network operation failed" end
        return a,b,c
    end
    function self:Error()
        local code=self.HttpStatus
        local permanent=code==400 or code==401 or code==403 or code==409
        return permanent and ("Authorization/session rejected (HTTP "..code.."); reconnect manually.")
            or "Dashboard unavailable or timed out; credentials retained.",permanent
    end
    function self:Authenticate(ticket,raw,manualLink)
        self.HttpStatus=nil
        if options.DisableNetwork then return false,"Dashboard connection unavailable",true end
        if type(W.ResolveRequest())~="function" then return false,"Executor request API unavailable",true end
        if raw==nil then W.LoadConfig();raw=W.key end
        if not W.ValidKey(raw) then return false,"Dashboard not linked or invalid key format",true end
        local verified,user,key=self:Bounded(ticket,function() return W.VerifyKey(raw) end)
        if not verified then local message,permanent=self:Error();return false,message,permanent end
        if type(user.id)~="string" or user.id=="" then return false,"Dashboard identity response was invalid",true end
        if not manualLink and self.AccountId and self.AccountId~=user.id then return false,"Saved account changed; Link explicitly to confirm.",true end
        if manualLink then
            local linked=self:Bounded(ticket,function() return W.RelinkRobloxAccount(key) end)
            if not linked then local message,permanent=self:Error();return false,message,permanent end
        end
        if not active(ticket) then return false,"Cancelled",true end
        W.key=key;W.account=user
        W.lastHttpPushClock=0;W.lastHttpAttemptClock=nil;W.runtimeRegistered=false
        local pushed=self:Bounded(ticket,W.PushOnce)
        if not active(ticket) then return false,"Cancelled",true end
        if not pushed or not W.runtimeRegistered then local message,permanent=self:Error();return false,message,permanent end
        if not W.SaveConfig() then self:Warn("Dashboard credential could not be saved; connection is available only for this execution.") end
        return true,user
    end
    function self:Run(raw,manualLink,remember)
        if not self.Alive or not C.State.running then return false,"Hub closed" end
        if self.Runner then return false,"Dashboard connection already in progress" end
        self:Cancel();local ticket=self.Ticket
        local finished,result,detail=false,false,nil
        local thread=task.spawn(function()
            self:Changed("Connecting")
            local attempts=0
            while active(ticket) do
                local okay,value,permanent=self:Authenticate(ticket,raw,manualLink)
                if not active(ticket) then break end
                if okay then
                    if remember then self.NoRetry=false;self:Persist(true,value.id) end
                    self:Changed("Connected");result=true;detail=value;finished=true
                    W.StartUpdateWatch()
                    W.thread=coroutine.running() -- single coordinator owns telemetry and retries
                    attempts=0
                    while active(ticket) do
                        task.wait(W.liveConnected and (W.liveNextPushDelaySeconds or W.pushIntervalSeconds or 5) or 5)
                        if not active(ticket) then break end
                        self.HttpStatus=nil
                        local sent=self:Bounded(ticket,W.PushOnce)
                        if not active(ticket) then break end
                        -- Socket Send alone is insufficient evidence; require fresh server ACK or HTTP acceptance.
                        local ack=tonumber(W.liveLastAckAt) or 0
                        local http=tonumber(W.lastHttpPushClock) or 0
                        local accepted=(W.runtimeRegistered and os.clock()-http<9) or (ack>0 and os.time()-ack<=9)
                        local _,rejected=self:Error()
                        if not sent or not accepted or rejected then break end
                    end
                    W.thread=nil
                    if not active(ticket) then break end
                    self:StopTransport();self:Changed("Reconnecting")
                    local _,rejected=self:Error();if rejected then permanent=true end
                    raw=nil;manualLink=false
                end
                local message,rejected=self:Error()
                if self.NoRetry or permanent or rejected or attempts>=5 then
                    self:StopTransport();self:Changed("Connection failed",value and not okay and tostring(value) or message)
                    self:Warn(self.Message);finished=true;detail=self.Message;break
                end
                self:StopTransport();attempts+=1;self:Changed("Reconnecting",message)
                task.wait(math.min(2^attempts,32))
            end
            if self.Ticket==ticket then self.Runner=nil;W.thread=nil end
        end)
        if active(ticket) and coroutine.status(thread)~="dead" then self.Runner=thread end
        -- Manual callers get the real auth + registration outcome, bounded by six attempts.
        while not finished and active(ticket) do task.wait(.05) end
        return result,detail or "Cancelled"
    end
    function self:Connect(raw) return self:Run(raw,raw~=nil,true) end
    function self:Resume()
        if self.ReadError and self.ReadError~="Missing" then self:Warn("Dashboard connection intent unavailable ("..self.ReadError..").") end
        if not self.Enabled or self.Runner or not self.Alive then return end
        task.defer(function() if self.Alive and self.Enabled then self:Run(nil,false,false) end end)
    end
    function self:SetEnabled(enabled)
        self:Persist(enabled)
        if not enabled then
            if self.State~="Connected" then self:Cancel();self:Changed("Disconnected") end
            self.NoRetry=true
        else self.NoRetry=false;self:Resume() end
    end
    function self:Disconnect()
        self:Persist(false);self:ReleasePresence();self:Cancel();self:Changed("Disconnected")
    end
    function self:Destroy()
        if not self.Alive then return end
        self:ReleasePresence();self.Alive=false;self:Cancel();self.OnChange=nil;self.OnWarning=nil
    end
    return self
end

end)()
return factory(C)
end
local function LoadAroyn()
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
        ScaleType=Enum.ScaleType.Fit,Position=UDim2.fromOffset(12,10),Size=UDim2.fromOffset(28,32)},header) end
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

end
local function AssetFactory()
return function(Aroyn,report)
local function stage(message) if report then report(message) end end
local function png(value) return type(value)=="string" and #value>24 and value:sub(1,8)=="\137PNG\r\n\26\n" end
local assetRoot=Aroyn.HubBuildInfo.AssetRoot
-- Optional local-file asset adapter; replace with a Roblox asset URI in Studio.
local __fa_env={}
local function __fa_decode(data)
    -- Prefer the executor's native decoder when available.
    local ok, result

    if crypt and type(crypt.base64decode)=="function" then
        ok,result=pcall(crypt.base64decode,data)
        if ok and png(result) then return result,"crypt.base64decode" end
    end

    if crypt and crypt.base64 and type(crypt.base64.decode)=="function" then
        ok,result=pcall(crypt.base64.decode,data)
        if ok and png(result) then return result,"crypt.base64.decode" end
    end

    if crypt and type(crypt.base64_decode)=="function" then
        ok,result=pcall(crypt.base64_decode,data)
        if ok and png(result) then return result,"crypt.base64_decode" end
    end

    if syn and syn.crypt and syn.crypt.base64 and type(syn.crypt.base64.decode)=="function" then
        ok,result=pcall(syn.crypt.base64.decode,data)
        if ok and png(result) then return result,"syn.crypt.base64.decode" end
    end

    if base64 and type(base64.decode)=="function" then
        ok,result=pcall(base64.decode,data)
        if ok and png(result) then return result,"base64.decode" end
    end

    if type(base64decode)=="function" then
        ok,result=pcall(base64decode,data)
        if ok and png(result) then return result,"base64decode" end
    end

    if type(decodebase64)=="function" then
        ok,result=pcall(decodebase64,data)
        if ok and png(result) then return result,"decodebase64" end
    end

    -- Pure-Luau fallback for mobile executors that expose getcustomasset/writefile
    -- but use a different or missing crypt/base64 API.
    local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local map={}
    for i=1,#alphabet do
        map[string.byte(alphabet,i)]=i-1
    end

    local output={}
    local outN=0

    for i=1,#data,4 do
        local a=map[string.byte(data,i)]
        local b=map[string.byte(data,i+1)]
        local cByte=string.byte(data,i+2)
        local dByte=string.byte(data,i+3)

        if a==nil or b==nil then break end

        local c=(cByte and cByte~=61 and map[cByte]) or 0
        local d=(dByte and dByte~=61 and map[dByte]) or 0
        local n=a*262144+b*4096+c*64+d

        outN=outN+1
        output[outN]=string.char(math.floor(n/65536)%256)

        if cByte and cByte~=61 then
            outN=outN+1
            output[outN]=string.char(math.floor(n/256)%256)
        end

        if dByte and dByte~=61 then
            outN=outN+1
            output[outN]=string.char(n%256)
        end

        -- Avoid one huge uninterrupted CPU burst on slower phones.
        if i%16384==1 then task.wait() end
    end

    result=table.concat(output)
    if png(result) then return result,"pure-luau" end
    return nil,"decode-failed"
end

local function __fa_asset_function()
    if type(getcustomasset)=="function" then return getcustomasset,"getcustomasset" end
    if type(getsynasset)=="function" then return getsynasset,"getsynasset" end
    return nil,"none"
end

local function __fa_ensure_asset_folders()
    if type(makefolder)~="function" then return end
    local root=assetRoot:match("^([^/]+)")
    for _,folder in ipairs({root,assetRoot}) do
        if type(isfolder)~="function" or not isfolder(folder) then makefolder(folder) end
    end
end
local function __fa_register_asset(envKey,fileName,b64)
    local label=envKey=="__FA_NAV_ICONS_ASSET" and "icon atlas" or envKey:match("^mobile_(.+)$") or "logo"
    stage("Checking "..label.." asset APIs…")
    local assetFn,assetApi=__fa_asset_function()

    if not assetFn then
        return nil,"custom asset API unavailable"
    end
    if type(writefile)~="function" then
        return nil,"writefile unavailable"
    end

    stage("Decoding "..label.." PNG…")
    local decoded,decoder=__fa_decode(b64)
    if not decoded then
        return nil,"base64 decode unavailable"
    end

    stage("Preparing local asset directory…")
    __fa_ensure_asset_folders()

    local path=assetRoot.."/"..fileName

    stage("Writing "..label.." PNG…")
    local writeOk,writeErr=pcall(writefile,path,decoded)
    if not writeOk then
        return nil,"writefile failed: "..tostring(writeErr)
    end

    if type(readfile)=="function" then
        stage("Verifying "..label.." PNG…")
        local readOk,actual=pcall(readfile,path)
        if not readOk or actual~=decoded then return nil,"PNG readback failed for "..label end
    end
    stage("Registering "..label.." ("..assetApi..")…")
    local assetOk,asset=pcall(assetFn,path)
    if not assetOk or type(asset)~="string" or asset=="" then
        return nil,assetApi.." failed: "..tostring(asset)
    end

    stage("Registered "..label.." local asset")
    -- IMPORTANT FOR MOBILE:
    -- Do NOT delete these PNG files after 5-8 seconds.
    -- Some Android executors resolve custom assets lazily; the old code deleted
    -- the backing file before the main GUI was built, leaving blank ImageLabels.
    __fa_env[envKey]=asset

    return asset,decoder.." + "..assetApi.." | "..path
end

-- BEGIN MOBILE PNG CATALOGUE: exact crops of the approved atlas, no redraw
local mobileKeys={"cart","plot","harvest","compost","market","pets","stats","gear"}
local mobilePng={
    cart="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",
    plot="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",
    harvest="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",
    compost="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",
    market="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",
    pets="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",
    stats="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",
    gear="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",
}
local function mobileDevice()
    local ok,input=pcall(function() return game:GetService("UserInputService") end)
    if not ok or input.TouchEnabled~=true then return false end
    local supported,platform=pcall(function()return input:GetPlatform()end)
    return supported and (platform==Enum.Platform.Android or platform==Enum.Platform.IOS)
        or input.MouseEnabled~=true or input.KeyboardEnabled~=true
end
Aroyn.MobileAssetPackage={Keys=mobileKeys,Prepare=function(onProgress)
    report=onProgress
    local result={Navigation={},Errors={}}
    local function register(key,file,pngData)
        local ok,uri,detail=pcall(__fa_register_asset,key,file,pngData)
        if ok and uri then return uri end
        result.Errors[key]=ok and tostring(detail) or tostring(uri)
    end
    -- The same authentic logo is used; the navigation images contain exact 128px cells.
    result.Logo=register("__FA_EMBEDDED_LOGO_ASSET","aroyn_existing_logo.png","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")
    for _,key in ipairs(mobileKeys) do
        result.Navigation[key]=register("mobile_"..key,"aroyn_nav_"..key.."_128.png",mobilePng[key])
    end
    return result
end}
if mobileDevice() then Aroyn.MobileAssetsPreferred=true;return end
-- END MOBILE PNG CATALOGUE
local iconAtlas,atlasDetail=__fa_register_asset("__FA_NAV_ICONS_ASSET","aroyn_navigation_phase6a_grid_v2_128.png","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GGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjDHGGGOMMcYYY4wxxhhjjPn/7cEBCQAAAICg/6/bEagAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANwEEv7dUhCjp3EAAAAASUVORK5CYII=")
assert(iconAtlas,"Aroyn icon atlas: "..tostring(atlasDetail))
Aroyn.IconAtlas=iconAtlas
local logo,logoDetail=__fa_register_asset("__FA_EMBEDDED_LOGO_ASSET","aroyn_existing_logo.png","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")
assert(logo,"Aroyn logo: "..tostring(logoDetail))
Aroyn.Logo=logo
stage("Local PNG assets registered")

end


end
local function UIFactory()
-- Only game bindings live here. The reusable approved UI core is embedded without edits.
-- BEGIN HUB RESPONSIVE ADAPTER (11C.1; approved core remains byte-identical)
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
local function installResponsive(Aroyn,w,startup)
    local scope=w.Scope;local screen=w.OwnRoot;local root=w.Root
    local textService=game:GetService("TextService")
    local originalRows={};local measurements={};local paramsInFlight={}
    local pending,working,dirty=false,false,false;local thread;local dead=false;local layoutRequested=false
    local function alive() return not dead and scope.Alive and root.Parent~=nil end
    local function safeBounds()
        return hubSafeBounds(w) -- same host-relative Core UI safe bounds as dialogs/toasts
    end
    local function geometry()
        if root:GetAttribute("AroynStartupBusy") then return end
        local left,top,right,bottom=safeBounds()
        local width=math.floor(math.min(1024,math.max(1,right-left-32)))
        local height=math.floor(math.min(600,math.max(1,bottom-top-32)))
        local x=root.AbsolutePosition.X-screen.AbsolutePosition.X
        local y=root.AbsolutePosition.Y-screen.AbsolutePosition.Y
        x=math.floor(math.clamp(x,left,math.max(left,right-width))+.5)
        y=math.floor(math.clamp(y,top,math.max(top,bottom-height))+.5)
        local changed=root.Size.X.Offset~=width or root.Size.Y.Offset~=height
            or root.Position.X.Scale~=0 or root.Position.Y.Scale~=0
            or root.Position.X.Offset~=x or root.Position.Y.Offset~=y
        if not changed then return end
        -- Viewport retarget settles an in-flight minimize/restore using the existing
        -- cancellation path. Ordinary minimize/restore curves and timings are untouched.
        if w.Collapse.Busy then w.Collapse:Set(w.Collapse.Minimized,true) end
        local constraint=root:FindFirstChildOfClass("UISizeConstraint")
        constraint.MinSize=Vector2.new(math.min(440,width),0)
        root.Size=UDim2.fromOffset(width,height);root.Position=UDim2.fromOffset(x,y)
        w.Collapse.ExpandedSize=root.Size;w.Collapse.ExpandedPosition=root.Position
    end
    local function measured(label,width)
        width=math.max(1,math.floor(width))
        local key=label.Text.."/"..label.TextSize.."/"..width.."/"..tostring(label.FontFace.Weight)
        if measurements[key] then return measurements[key] end
        local input=game:GetService("UserInputService")
        if Aroyn.MobileAssetsPreferred or input.TouchEnabled and not input.KeyboardEnabled then
            local ok,b=pcall(function() return textService:GetTextSize(label.Text,label.TextSize,Enum.Font.SourceSans,Vector2.new(width,1000000)) end)
            local height=ok and math.max(22,math.ceil(b.Y)+4) or math.max(22,math.ceil((utf8.len(label.Text) or #label.Text)*label.TextSize/width)*math.ceil(label.TextSize*1.4))
            measurements[key]=height;return height
        end
        local p=Instance.new("GetTextBoundsParams");paramsInFlight[p]=true
        p.Text=label.Text;p.Size=label.TextSize;p.Font=label.FontFace;p.Width=width;p.RichText=false
        local ok,b=pcall(function() return textService:GetTextBoundsAsync(p) end)
        paramsInFlight[p]=nil;p:Destroy()
        if not ok then b=textService:GetTextSize(label.Text,label.TextSize,Enum.Font.BuilderSans,Vector2.new(width,1000000)) end
        local height=math.max(22,math.ceil(b.Y));measurements[key]=height;return height
    end
    local function rows()
        for _,page in ipairs(w.Pages) do
            for _,section in ipairs(page.Sections) do
                for _,c in ipairs(section.Components) do
                    if c.Control and c.Scope.Alive then
                        local o=originalRows[c]
                        if not o then
                            o={Height=c.Root.Size.Y.Offset,LabelSize=c.Label.Size,LabelPosition=c.Label.Position,
                                ControlSize=c.Control.Size,ControlPosition=c.Control.Position,ControlAnchor=c.Control.AnchorPoint}
                            if c.Description then o.DescriptionSize=c.Description.Size;o.DescriptionPosition=c.Description.Position end
                            originalRows[c]=o
                        end
                        local width=math.max(1,math.floor(c.Root.AbsoluteSize.X))
                        -- Actual row width includes the native page's UIPadding. No global device breakpoint.
                        local stacked=width-o.ControlSize.X.Offset-Aroyn.Theme.Metrics.Gap<176
                        if stacked then
                            local labelHeight=measured(c.Label,width)
                            local descriptionHeight=c.Description and measured(c.Description,width) or 0
                            if not alive() or not c.Scope.Alive then return end
                            c.Label.TextWrapped=true;c.Label.Size=UDim2.new(1,0,0,labelHeight)
                            c.Label.Position=UDim2.fromOffset(0,0)
                            local y=labelHeight+6
                            if c.Description then
                                c.Description.TextWrapped=true;c.Description.Position=UDim2.fromOffset(0,y)
                                c.Description.Size=UDim2.new(1,0,0,descriptionHeight);y+=descriptionHeight+6
                            end
                            c.Control.AnchorPoint=Vector2.zero;c.Control.Position=UDim2.fromOffset(0,y)
                            local controlWidth=c.Kind=="Toggle" and math.min(width,o.ControlSize.X.Offset) or width
                            c.Control.Size=UDim2.fromOffset(controlWidth,math.max(40,o.ControlSize.Y.Offset))
                            c.Root.Size=UDim2.new(1,0,0,y+c.Control.Size.Y.Offset+4)
                        else
                            c.Label.TextWrapped=false;c.Label.Size=o.LabelSize;c.Label.Position=o.LabelPosition
                            if c.Description then c.Description.TextWrapped=false;c.Description.Size=o.DescriptionSize;c.Description.Position=o.DescriptionPosition end
                            c.Control.AnchorPoint=o.ControlAnchor;c.Control.Size=o.ControlSize;c.Control.Position=o.ControlPosition
                            c.Root.Size=UDim2.new(1,0,0,o.Height)
                        end
                        -- Slider track uses width-relative children; rerender after width changes.
                        if c.Kind=="Slider" then c:_RenderSlider() end
                    end
                end
                section:Reflow()
            end
        end
    end
    local function anchor()
        local page=w.Selected;if not page then return end
        local popup=w.PopupOwner
        if popup and popup.Opened and popup.Section.Page==page then
            local y=popup.Control.AbsolutePosition.Y-page.Root.AbsolutePosition.Y
            popup:Close(true);return popup,y,true
        end
        local focused=game:GetService("UserInputService"):GetFocusedTextBox()
        local first
        for _,section in ipairs(page.Sections) do for _,c in ipairs(section.Components) do
            local y=c.Control.AbsolutePosition.Y-page.Root.AbsolutePosition.Y
            if focused==c.Control then return c,y,false end
            if not first and y+c.Control.AbsoluteSize.Y>0 and y<page.Root.AbsoluteSize.Y then first={c,y} end
        end end
        if first then return first[1],first[2],false end
    end
    local function restoreAnchor(c,y,popup)
        if not alive() or not c or not c.Scope.Alive or w.Selected~=c.Section.Page then return end
        local page=c.Section.Page.Root
        local relative=c.Control.AbsolutePosition.Y-page.AbsolutePosition.Y
        page.CanvasPosition=Vector2.new(page.CanvasPosition.X,math.max(0,page.CanvasPosition.Y+relative-y))
        if popup and not w.Collapse.Minimized and not root:GetAttribute("AroynStartupBusy") then c:Open() end
    end
    -- BEGIN MOBILE SIDEBAR COMPACTION
    local input=game:GetService("UserInputService")
    local mobileNavigation=Aroyn.MobileAssetsPreferred or input.TouchEnabled and not input.KeyboardEnabled
    if mobileNavigation and w.Navigation then
        -- Keep the approved core and its selected/hover animations intact.
        -- Only this Hub window's rail geometry is adapted; targets never drop below 36px.
        w.ReflowNavigation=function(self)
            local rail=self.Navigation;local count=#self.Pages
            if count==0 then rail.CanvasSize=UDim2.fromOffset(0,0);return end
            local height=math.max(0,math.floor(rail.AbsoluteSize.Y))
            local padding,button,gap=6,38,4
            if count*button+(count-1)*gap+padding*2>height then
                padding=4
                button=math.clamp(math.floor((height-padding*2)/count),36,38)
                gap=math.clamp(math.floor((height-padding*2-count*button)/math.max(1,count-1)),0,4)
            end
            local x=math.max(0,math.floor((rail.AbsoluteSize.X-button)/2))
            for i,page in ipairs(self.Pages) do
                if page.Navigation then
                    page.Navigation.Size=UDim2.fromOffset(button,button)
                    page.Navigation.Position=UDim2.fromOffset(x,padding+(i-1)*(button+gap))
                    page.Icon.Size=UDim2.fromOffset(button-16,button-16)
                end
            end
            local extent=padding*2+count*button+(count-1)*gap
            rail.CanvasSize=UDim2.fromOffset(0,extent)
            rail.CanvasPosition=Vector2.new(rail.CanvasPosition.X,math.clamp(rail.CanvasPosition.Y,0,math.max(0,extent-height)))
        end
    end
    -- END MOBILE SIDEBAR COMPACTION
    local function request(layout)
        if not alive() then return end
        if layout~=false then layoutRequested=true end
        dirty=true;if pending or working then return end
        pending=true
        thread=task.defer(function()
            pending=false;working=true
            repeat
                dirty=false
                if alive() then
                    local c,y,popup
                    if layoutRequested and not root:GetAttribute("AroynStartupBusy") then c,y,popup=anchor() end
                    geometry()
                    -- BEGIN MOBILE SIDEBAR REFLOW
                    if mobileNavigation then w:ReflowNavigation() end
                    -- END MOBILE SIDEBAR REFLOW
                    if layoutRequested then layoutRequested=false;rows();restoreAnchor(c,y,popup) end
                    w.Collapse:ClampFloating()
                end
            until not dirty or not alive()
            working=false;thread=nil
        end)
    end
    -- Keep launcher inside safe areas as well as the existing physical viewport clamp.
    local place=w.Collapse.PlaceFloating
    w.Collapse.PlaceFloating=function(m,x,y)
        local left,top,right,bottom=safeBounds();local size=m.Launcher.AbsoluteSize
        return place(m,math.clamp(x,left,math.max(left,right-size.X)),math.clamp(y,top,math.max(top,bottom-size.Y)))
    end
    local function resized()
        request()
    end
    scope:Connect(screen:GetPropertyChangedSignal("AbsoluteSize"),resized)
    for _,property in ipairs({"ScreenInsets","IgnoreGuiInset","SafeAreaCompatibility"}) do
        local ok,signal=pcall(function() return screen:GetPropertyChangedSignal(property) end)
        if ok then scope:Connect(signal,resized) end
    end
    local ok,signal=pcall(function() return game:GetService("GuiService"):GetPropertyChangedSignal("TopbarInset") end)
    if ok then scope:Connect(signal,resized) end
    -- BEGIN MOBILE SIDEBAR RESIZE
    if mobileNavigation and w.Navigation then
        scope:Connect(w.Navigation:GetPropertyChangedSignal("AbsoluteSize"),function() request(false) end)
    end
    -- END MOBILE SIDEBAR RESIZE
    scope:Connect(w.Content:GetPropertyChangedSignal("AbsoluteSize"),request)
    scope:Connect(root:GetAttributeChangedSignal("AroynStartupBusy"),request)
    scope:Connect(root:GetPropertyChangedSignal("Position"),function() request(false) end)
    scope:Connect(root.DescendantAdded,request)
    -- Exactly one coalesced, cancellable task; no layout Heartbeat/RenderStepped.
    local destroy=w.Destroy
    w.Destroy=function(self)
        if not dead then
            dead=true;if thread and thread~=coroutine.running() then pcall(task.cancel,thread) end
            thread=nil;for p in pairs(paramsInFlight) do p:Destroy() end;table.clear(paramsInFlight)
            table.clear(originalRows);table.clear(measurements)
        end
        return destroy(self)
    end
    w.Chrome.Size=UDim2.fromScale(1,1)
    request()
end
-- END HUB RESPONSIVE ADAPTER
return function(Aroyn,C)
    -- Local atlas extension; use the core's same ImageLabel/tint animation path.
    -- 1024x512 padded grid avoids the native resize of the former 1280px strip.
    if not Aroyn.Phase6ANavigationIcons then
        local extras={harvest={Cell=7,Base="plot"},gear={Cell=8,Base="settings"},stats={Cell=9,Base="settings"}}
        local cells={cart=0,plot=1,compost=2,market=3,settings=4,pets=5,components=6,harvest=7,gear=8,stats=9}
        local originalCreateIcon=Aroyn.CreateIcon
        for key,spec in pairs(extras) do Aroyn.Icons[key]={AtlasCell=spec.Cell} end
        Aroyn.CreateIcon=function(self,parent,key,size,tint)
            local spec=extras[key]
            local icon=originalCreateIcon(self,parent,spec and spec.Base or key,size,tint)
            if spec then icon.Name="Icon_"..key end
            local cell=cells[key]
            if cell~=nil and self.IconAtlas and self.IconAtlas~="" then
                icon.ImageRectOffset=Vector2.new((cell%5)*160+16,math.floor(cell/5)*160+16)
                icon.ImageRectSize=Vector2.new(128,128)
            end
            -- BEGIN MOBILE NAVIGATION PRESENTATION
            if self.NavigationImages then
                local uri=self.NavigationImages[key]
                icon.Image=uri or "";icon.ImageRectOffset=Vector2.zero;icon.ImageRectSize=Vector2.zero
                if not uri then
                    local names={cart="Buy\nSeeds",plot="Plot",harvest="Collect",compost="Compost",market="Market",pets="Pets",stats="Session",gear="Settings"}
                    local label=Instance.new("TextLabel");label.Name="NativeAssetPageLabel"
                    label.Text=names[key] or key;label.TextWrapped=true;label.TextSize=9
                    label.Font=Enum.Font.SourceSansSemibold;label.TextColor3=icon.ImageColor3;label.ZIndex=icon.ZIndex
                    label.BackgroundTransparency=1;label.Size=UDim2.fromScale(1,1);label.Parent=parent
                    icon:SetAttribute("AroynNativeNavigation",true)
                    local tint=icon:GetPropertyChangedSignal("ImageColor3"):Connect(function() label.TextColor3=icon.ImageColor3 end)
                    local cleanup;cleanup=icon.Destroying:Connect(function() tint:Disconnect();cleanup:Disconnect() end)
                end
            end
            -- END MOBILE NAVIGATION PRESENTATION
            return icon
        end
        Aroyn.Phase6ANavigationIcons=true
    end
    local parent
    if type(gethui)=="function" then local ok,p=pcall(gethui);if ok and typeof(p)=="Instance" then parent=p end end
    parent=parent or game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui",5)
    assert(parent,"Aroyn: GUI parent unavailable")
    local ui={Controls={},Preferences={},Loading=true,Controller=C,Dead=false}
    local view=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1440,900)
    local w=C.Options.Startup and C.Options.Startup.Window or Aroyn:CreateWindow({Parent=parent,Id=C.Options.BuildInfo.Namespace,Title="AROYN · Greedy Growers",Logo=Aroyn.Logo,
        Size=UDim2.fromOffset(math.max(440,math.min(1024,view.X-32)),math.max(300,math.min(600,view.Y-32))),
        Config={Namespace=C.Options.BuildInfo.Namespace,FileSystem=C.Options.Storage.FileSystem(C.Options.BuildInfo.StorageRoot,C.Options.BuildInfo.Namespace),DefaultConfig="main",AutoLoad=false,AutoSave=false}})
    ui.Window=w
    ui.Persistence=C.Options.Storage.Bind(w,C.Options.BuildInfo)
    C.UI.ScreenGui=w.OwnRoot;C.UI.Window=w.Root -- lets App.Destroy clean partial UI construction
    local defaults=C.Preferences();local seeds={};for _,r in ipairs(C.Records) do table.insert(seeds,r.key) end
    local autoFields={AutoBuy="autoBuyEnabled",AutoCompost="autoCompostEnabled",AutoCollect="autoCollectFruits",
        AutoLeaves="autoCollectLeaves",AutoPetDrops="autoCollectPetSeeds",AutoMarket="autoMarketEnabled",AutoFeed="autoFeedPetsEnabled",HidePlot="hidePlotVisuals"}
    local function notify(title,description,kind)
        if w.Scope.Alive then w:Notify({Title=title,Description=description or "",Type=kind or "Info"}) end
    end
    local function action(fn)
        return function(...)
            if ui.Dead or not C.State.running or w.Root:GetAttribute("AroynStartupBusy") then return end
            local ok,err=pcall(fn,...)
            if not ok then notify("Action failed",tostring(err),"Error") end
            if not ui.Dead then ui:SyncPreferences();ui:Refresh() end
        end
    end
    local function networkAction(fn,updateCheck)
        assert(not C.NetworkThread,"Dashboard connection already in progress")
        local completed=false
        local thread=task.spawn(function()
            local protected,ok,detail=pcall(fn)
            completed=true;C.NetworkThread=nil
            if not ui.Dead then
                if not updateCheck then ui.DashboardKey:SetValue("") end
                notify(updateCheck and (ok and protected and "Update checked" or "Update check failed") or (ok and protected and "Dashboard connected" or "Dashboard unavailable"),
                    protected and (ok and "" or tostring(detail)) or tostring(ok),ok and protected and "Success" or "Warning")
                ui:Refresh()
            end
        end)
        if not completed then C.NetworkThread=thread end
    end
    local function page(name,icon,title) return w:CreatePage({Name=name,Icon=icon}):CreateSection({Title=title or name}) end
    local function pref(section,key,kind,name,extra)
        local options=extra or {};options.Name=name;options.Flag=key;options.Default=defaults[key]
        options.Callback=action(function(value) if not ui.Loading then C.SetPreference(key,value) end end)
        local c=section['Create'..kind](section,options);ui.Preferences[key]=c;ui.Controls[key]=c;return c
    end
    local function button(section,key,name,text,fn)
        local c=section:CreateButton({Name=name,Text=text or "Run",Callback=action(fn)})
        ui.Controls[key]=c;return c
    end
    local function automatic(section,key,name)
        local c=section:CreateToggle({Name=name,Default=false,Description="Starts only when you enable it.",Callback=action(function(v) C.Setters[key](v) end)})
        -- Deliberately no Flag: saved preferences must never activate gameplay.
        ui.Controls[key]=c;return c
    end
    local function info(section,key,name)
        local c=section:CreateTextInput({Name=name,Default="",Disabled=true});ui.Controls[key]=c;return c
    end
    local buy=page("Buy Seeds","cart","Conveyor purchases")
    automatic(buy,"AutoBuy","Auto Buy")
    ui.SeedSearch=buy:CreateTextInput({Name="Find seeds",Default="",Description="Name or rarity; selected seeds remain visible.",Callback=action(function() ui:SyncPreferences() end)})
    pref(buy,"Seeds","Dropdown","Selected seeds",{Multi=true,Options=seeds})
    button(buy,"SelectAll","Select all seeds","Select all",C.SelectAll)
    button(buy,"ClearSeeds","Clear seeds","Clear",C.ClearSeeds)
    local rarity=buy:CreateDropdown({Name="Select rarity",Options=C.Rarities,Default=C.Rarities[1]})
    button(buy,"Rarity","Add selected rarity","Add",function() C.SelectRarity(rarity:GetValue(),false) end)
    button(buy,"RarityPlus","Add rarity and higher","Add",function() C.SelectRarity(rarity:GetValue(),true) end)
    pref(buy,"PriorityOrder","TextInput","Priority order",{Description="Seed keys, comma separated. First key has highest priority."})
    ui.PrioritySeed=buy:CreateDropdown({Name="Edit priority seed",Options=seeds,Default=seeds[1]})
    button(buy,"EnablePriority","Enable priority","Enable",function() C.PriorityEnabled(ui.PrioritySeed:GetValue(),true) end)
    button(buy,"DisablePriority","Remove priority","Remove",function() C.PriorityEnabled(ui.PrioritySeed:GetValue(),false) end)
    button(buy,"PriorityUp","Move priority up","Up",function() C.MovePriority(ui.PrioritySeed:GetValue(),-1) end)
    button(buy,"PriorityDown","Move priority down","Down",function() C.MovePriority(ui.PrioritySeed:GetValue(),1) end)
    pref(buy,"Affordable","Toggle","Affordable only")
    pref(buy,"Reserve","TextInput","Cash reserve")
    pref(buy,"MaxPrice","TextInput","Maximum seed price",{Description="Empty means no cap; supports compact numbers."})
    pref(buy,"Rate","Dropdown","Trigger interval (s)",{Options={"0","0.15","0.25","0.5","1"}})
    pref(buy,"OneShot","Toggle","One shot")
    pref(buy,"StopAfter","TextInput","Stop after triggers",{Description="Empty means no trigger limit."})
    info(buy,"BuyStats","Attempts / confirmed")
    local plot=page("Plot","plot","Own plot and inventory")
    info(plot,"TreeCount","Trees / ready fruits");info(plot,"Inventory","Inventory summary")
    info(plot,"Weather","Current weather")
    ui.TreeChoice=plot:CreateDropdown({Name="Inspect tree",Options={},Callback=action(function(id) C.SetSelectedTree(id) end)})
    info(plot,"TreeDetail","Selected tree")
    button(plot,"InspectInventory","Inspect inventory contents","Show",function()
        local inventory=C.Inventory();local lines={}
        for key,count in pairs(inventory.seeds) do table.insert(lines,key.." seed × "..tostring(count)) end
        for key,item in pairs(inventory.fruits) do table.insert(lines,key.." fruit × "..tostring(item.count).." · $"..C.FormatNumber(item.totalValue)) end
        table.insert(lines,"Hotbar: "..tostring(inventory.usedHotbar).." / "..tostring(inventory.hotbarCapacity))
        table.sort(lines);w:Dialog({Title="Inventory",Description=table.concat(lines,"\n"),Type="Alert"})
    end)
    button(plot,"InspectTree","Inspect selected tree / fruits","Show",function()
        local tree=C.Game.treesById[C.GetSelectedTree()];assert(tree,"Select a tree first")
        local lines={tostring(tree.seedType).." · "..tostring(tree.multiplier).."x",tostring(tree.mutations or "No mutations")}
        for _,fruit in pairs(tree.fruits or {}) do
            local display=C.Farm.liveFruitDisplay(fruit)
            table.insert(lines,"Slot "..tostring(fruit.spawnIndex).." · "..tostring(display and display.sellValue or "Awaiting value").." · "..tostring(display and display.mutationText or ""))
        end
        w:Dialog({Title="Tree details",Description=table.concat(lines,"\n"),Type="Alert"})
    end)
    automatic(plot,"HidePlot","Hide plot visuals")
    local collect=page("Collect","harvest","Own-plot collection")
    automatic(collect,"AutoCollect","Auto collect fruits")
    automatic(collect,"AutoLeaves","Auto collect leaves")
    automatic(collect,"AutoPetDrops","Auto collect pet drops")
    info(collect,"CollectStats","Confirmed fruits / errors")
    info(collect,"LeafStatus","Leaf collector");info(collect,"DropStatus","Pet drop collector")
    local compost=page("Compost","compost","Compost selected seed stacks")
    automatic(compost,"AutoCompost","Auto compost")
    ui.CompostSearch=compost:CreateTextInput({Name="Find compost seeds",Default="",Description="Name or rarity; selected seeds remain visible.",Callback=action(function() ui:SyncPreferences() end)})
    pref(compost,"CompostSeeds","Dropdown","Compost seeds",{Multi=true,Options=seeds})
    button(compost,"SelectCompostAll","Select all compost seeds","Select all",C.SelectAllCompost)
    button(compost,"ClearCompost","Clear compost seeds","Clear",C.ClearCompost)
    info(compost,"CompostStatus","Compost status");info(compost,"CompostStats","Fed / cycles / worms")
    local market=page("Market","market","Existing market order worker")
    automatic(market,"AutoMarket","Auto market")
    button(market,"RefreshOffers","Refresh offers","Refresh",function() C.Farm.refreshMarketOffers(false) end)
    info(market,"MarketStatus","Market status");info(market,"MarketStats","Submitted / claims / tickets")
    button(market,"InspectOffers","Inspect market requirements","Show",function()
        local offers=C.Farm.MarketRuntime.offers;local lines={}
        for i,row in ipairs(offers and offers.rows or {}) do
            for j,cell in ipairs(row.cells or {}) do table.insert(lines,tostring(i).."."..tostring(j).." · "..C.Farm.marketRequirementText(cell)) end
        end
        w:Dialog({Title="Market offers",Description=#lines>0 and table.concat(lines,"\n") or "Offers unavailable.",Type="Alert"})
    end)
    local pets=page("Pets","pets","Pet feeding")
    automatic(pets,"AutoFeed","Auto feed pets")
    pref(pets,"PetStart","Slider","Start below (%)",{Min=1,Max=95,Step=1})
    pref(pets,"PetTarget","Slider","Stop at (%)",{Min=2,Max=100,Step=1})
    pref(pets,"PetCap","TextInput","Maximum fruit value",{Description="0 = no cap. Existing protections for favorites/locked fruit remain."})
    info(pets,"FeedStatus","Feeding status");info(pets,"FeedStats","Confirmed feeds / value used")
    ui.PetChoice=pets:CreateDropdown({Name="Inspect pet",Options={}});info(pets,"PetHunger","Selected pet hunger")
    local session=page("Session","stats","Session statistics")
    info(session,"Cash","Current cash");info(session,"SessionStatus","Status")
    info(session,"NetworkStatus","Dashboard / presence")
    button(session,"CopyReport","Copy full session report","Copy",function()
        local copy=type(setclipboard)=="function" and setclipboard or toclipboard
        assert(type(copy)=="function","Clipboard unavailable");copy(C.Report());notify("Session report copied")
    end)
    button(session,"ShowLog","View recent activity","Show",function()
        local lines={};for _,e in ipairs(C.State.activityLog) do table.insert(lines,e.time.." "..e.message) end
        w:Dialog({Title="Recent activity",Description=#lines>0 and table.concat(lines,"\n") or "No events yet.",Type="Alert"})
    end)
    button(session,"ClearLog","Clear activity","Clear",C.ClearActivity)
    button(session,"ResetStats","Reset session counters","Reset",function()
        w:Dialog({Title="Reset session counters?",Description="Saved preferences stay intact.",Type="Confirm",OnConfirm=action(C.ResetStats)})
    end)
    local settings=page("Settings","gear","Dashboard and preferences")
    ui.DashboardKey=settings:CreateTextInput({Name="Dashboard key",Default="",Description="Credential is stored separately from preferences; not included in reports."})
    button(settings,"LinkDashboard","Link dashboard key","Link",function()
        local key=ui.DashboardKey:GetValue()
        networkAction(function() return C.Web.LinkKey(key) end)
    end)
    button(settings,"ConnectSaved","Connect existing dashboard link","Connect",function()
        networkAction(C.Web.Start)
    end)
    button(settings,"DisconnectDashboard","Disconnect dashboard","Disconnect",function() C.CancelNetwork();C.Dashboard:Disconnect();notify("Dashboard disconnected") end)
    button(settings,"UnlinkDashboard","Remove saved dashboard link","Unlink",function() C.CancelNetwork();C.Web.Unlink();ui.DashboardKey:SetValue("") end)
    button(settings,"CopyWebsite","Copy dashboard website","Copy",function()
        local copy=type(setclipboard)=="function" and setclipboard or toclipboard
        assert(type(copy)=="function","Clipboard unavailable");copy(C.Web.siteUrl)
    end)
    ui.DashboardAutoConnect=settings:CreateToggle({Name="Auto-connect Dashboard",Default=C.Dashboard.Enabled,
        Description="Reconnect this saved link on the next launch. Gameplay always starts off.",Callback=action(function(v) C.Dashboard:SetEnabled(v) end)})
    info(settings,"DashboardStatus","Connection status")
    info(settings,"ClientUpdate","Client version / update status")
    button(settings,"CheckUpdates","Check for updates","Check",function() networkAction(C.Web.CheckUpdateOnce,true) end)
    pref(settings,"Alerts","Toggle","Seed spawn notifications")
    pref(settings,"AlertRarity","Dropdown","Notification rarity",{Options=C.Rarities})
    pref(settings,"Diagnostics","Toggle","Runtime diagnostics")
    button(settings,"ShowDiagnostics","Show runtime diagnostics","Show",function()
        local diagnostics=C.App.GetDiagnostics();local lines={}
        for key,value in pairs(diagnostics) do table.insert(lines,key..": "..tostring(value)) end
        table.sort(lines);w:Dialog({Title="Runtime diagnostics",Description=table.concat(lines,"\n"),Type="Alert"})
    end)
    local shortcutDown,suppressedKey
    ui.Preferences.Hotkey=settings:CreateKeybind({Name="Window minimize / restore key",Default=defaults.Hotkey,Flag="Hotkey",Mode="Toggle",
        Callback=action(function(v) shortcutDown=nil;suppressedKey=v;C.SetPreference("Hotkey",v) end)})
    -- Window-level release handling also works when page-bound controls are unavailable after minimize.
    -- Capturing a binding consumes that physical press; it never collapses the window.
    local input=game:GetService("UserInputService")
    local function canShortcut()
        return not ui.Dead and C.State.running and not w.Root:GetAttribute("AroynStartupBusy") and input.KeyboardEnabled and not input:GetFocusedTextBox()
            and not ui.Preferences.Hotkey:IsCapturing() and not (w.Overlays and w.Overlays.ActiveDialog)
    end
    w.Scope:Connect(input.InputBegan,function(event,processed)
        if event.UserInputType==Enum.UserInputType.Keyboard and not processed and canShortcut()
            and event.KeyCode==C.State.hotkey and event.KeyCode~=suppressedKey then shortcutDown=event.KeyCode end
    end)
    w.Scope:Connect(input.InputEnded,function(event)
        if event.UserInputType~=Enum.UserInputType.Keyboard then return end
        local matched=shortcutDown==event.KeyCode;shortcutDown=nil
        if event.KeyCode==suppressedKey then suppressedKey=nil;return end
        if matched and canShortcut() and event.KeyCode==C.State.hotkey then w:SetMinimized(not w.Collapse.Minimized) end
    end)
    w.Scope:Connect(input.WindowFocusReleased,function() shortcutDown=nil;suppressedKey=nil end)
    w.Scope:Connect(input.TextBoxFocused,function() shortcutDown=nil end)
    ui.AutoPreferences=C.Options.Storage.Preferences(w,C.Options.BuildInfo,function(message) notify("Preferences not saved",message,"Warning") end)
    ui.ConfigName=settings:CreateTextInput({Name="Configuration name",Default=ui.AutoPreferences.Profile})
    button(settings,"SaveConfig","Save preferences","Save",function()
        local ok,info=w:SaveConfig(ui.ConfigName:GetValue());notify(info.Code,info.Message,ok and "Success" or "Error")
    end)
    button(settings,"LoadConfig","Load preferences (automation stops)","Load",function()
        local ok,info=w:LoadConfig(ui.ConfigName:GetValue());notify(info.Code,info.Message,ok and "Success" or "Error")
    end)
    button(settings,"ResetConfig","Reset preference defaults","Reset",function()
        local ok,info=w:ResetConfig();notify(info.Code,info.Message,ok and "Success" or "Error")
    end)
    button(settings,"ListConfigs","List saved configurations","List",function()
        local ok,info=w:ListConfigs();notify(info.Code,ok and table.concat(info.Names,", ") or info.Message,ok and "Info" or "Error")
    end)
    button(settings,"DeleteConfig","Delete this configuration","Delete",function()
        local name=ui.ConfigName:GetValue()
        w:Dialog({Title="Delete configuration?",Description=name,Type="Confirm",OnConfirm=action(function()
            local ok,info=w:DeleteConfig(name);notify(info.Code,info.Message,ok and "Success" or "Error")
        end)})
    end)
    button(settings,"RestoreBackup","Restore previous saved profile","Restore",function()
        local name=ui.ConfigName:GetValue()
        w:Dialog({Title="Restore previous profile?",Description="Replaces this profile with its last verified recovery copy. Automation stays off.",Type="Confirm",OnConfirm=action(function()
            C.StopAutomation()
            local ok,result=ui.Persistence:Restore(name)
            if ok then ok,result=w:LoadConfig(name) end
            notify(result.Code,result.Message,ok and "Success" or "Error")
        end)})
    end)
    ui.AutoSave=settings:CreateToggle({Name="AutoSave preferences",Default=ui.AutoPreferences.AutoSave,Callback=action(function(v)
        ui.AutoPreferences:SetAutoSave(v)
    end)})
    info(settings,"ConfigStatus","Persistence / last result")
    button(settings,"StopAll","Stop all automation","Stop all",C.StopAutomation)
    local function equal(a,b)
        if type(a)~="table" or type(b)~="table" or typeof(a)=="EnumItem" or typeof(b)=="EnumItem" then return a==b end
        if #a~=#b then return false end
        for i,v in ipairs(a) do if v~=b[i] then return false end end
        return true
    end
    function ui:SyncPreferences(force)
        if self.Dead or self.Loading then return end
        local values=C.Preferences()
        for _,spec in ipairs({{"Seeds",self.SeedSearch},{"CompostSeeds",self.CompostSearch}}) do
            local control=self.Preferences[spec[1]];local query=spec[2]:GetValue():match("^%s*(.-)%s*$"):lower()
            local selected={};for _,key in ipairs(values[spec[1]]) do selected[key]=true end
            local options={}
            for _,r in ipairs(C.Records) do
                local haystack=table.concat({r.key,r.displaySeedName or "",r.displayName or "",r.rarity or ""}," "):lower()
                if query=="" or selected[r.key] or haystack:find(query,1,true) then table.insert(options,r.key) end
            end
            if not equal(control:GetOptions(),options) then control:SetOptions(options) end
        end
        for key,c in pairs(self.Preferences) do
            local focused=c.Control and c.Control:IsA("TextBox") and input:GetFocusedTextBox()==c.Control
            local current=c:GetValue();if key=="Hotkey" then current=current and current.Name or "None" end
            if values[key]~=nil and (force or not focused) and not equal(current,values[key]) then c:SetValue(values[key]) end
        end
    end
    local function readPreferences()
        local values={};for key,c in pairs(ui.Preferences) do values[key]=c:GetValue() end
        local key=ui.Preferences.Hotkey:GetValue();values.Hotkey=key and key.Name or "None"
        return values
    end
    local originalLoad,originalReset=w.LoadConfig,w.ResetConfig
    local function apply(operation,...)
        ui.Loading=true;shortcutDown=nil;suppressedKey=nil
        local protected,ok,info=pcall(function(...)
            C.StopAutomation()
            ui.SeedSearch:SetValue("");ui.CompostSearch:SetValue("")
            ui.Preferences.Seeds:SetOptions(seeds);ui.Preferences.CompostSeeds:SetOptions(seeds)
            local success,result=operation(w,...)
            if success then C.ApplyPreferences(readPreferences()) end
            return success,result
        end,...)
        if not protected then info={Code="IntegrationError",Message=tostring(ok)};ok=false end
        ui.Loading=false;ui:SyncPreferences(true);ui:Refresh()
        return ok,info
    end
    -- Guard even direct app.Window:LoadConfig calls; constructor flags never contain automation.
    w.LoadConfig=function(_,name)
        if type(name)=="string" and name:lower()~=ui.AutoPreferences.Profile then ui.AutoPreferences:Flush() end
        local ok,result=apply(originalLoad,name)
        if ok then ui.AutoPreferences:Select(name);ui.ConfigName:SetValue(ui.AutoPreferences.Profile) end
        return ok,result
    end
    local originalDelete=w.DeleteConfig
    w.DeleteConfig=function(_,name)
        local ok,result=originalDelete(w,name)
        if ok and name:lower()==ui.AutoPreferences.Profile then ui.AutoPreferences:SetAutoSave(false);ui.AutoSave:SetValue(false) end
        return ok,result
    end
    w.ResetConfig=function(_) return apply(originalReset) end
    local function updateOptions(control,values)
        local old=control:GetOptions();local same=#old==#values
        if same then for i,value in ipairs(values) do if old[i]~=value then same=false;break end end end
        if not same then control:SetOptions(values) end
    end
    local function update(key,text)
        local c=ui.Controls[key];if c and c:GetValue()~=text then c:SetValue(text) end
    end
    function ui:Refresh()
        if self.Dead or not w.Scope.Alive then return end
        local S,G,F=C.State,C.Game,C.Farm
        for key,field in pairs(autoFields) do if ui.Controls[key]:GetValue()~=(S[field]==true) then ui.Controls[key]:SetValue(S[field]==true) end end
        update("BuyStats",tostring(S.successfulTriggers).." / "..tostring(S.confirmedSeedPurchases))
        update("TreeCount",tostring(F.getTreeCount()).." trees · "..tostring(F.getReadyFruitCount()).." ready")
        local items=C.Inventory();local fruitCount,seedCount=0,0
        for _,entry in pairs(items.fruits) do fruitCount+=entry.count end
        for _,count in pairs(items.seeds) do seedCount+=count end
        update("Inventory",tostring(fruitCount).." fruit · "..tostring(seedCount).." seeds")
        update("Weather",tostring(C.UI.CurrentWeatherText()))
        local ids={};for id in pairs(G.treesById) do table.insert(ids,tostring(id)) end;table.sort(ids)
        updateOptions(ui.TreeChoice,ids)
        local selected=C.GetSelectedTree();local tree=selected and G.treesById[selected]
        update("TreeDetail",tree and tostring(tree.seedType or tree.seedKey or selected) or "No tree selected")
        update("CollectStats",tostring(S.fruitsCollected).." / "..tostring(S.collectErrors))
        update("LeafStatus",tostring(S.leafStatus));update("DropStatus",tostring(S.petSeedStatus))
        update("CompostStatus",tostring(S.compostStatus or "Idle"))
        update("CompostStats",tostring(S.compostSeedsFed).." / "..tostring(S.compostCycles).." / "..tostring(S.wormsGranted))
        update("MarketStatus",tostring(S.marketStatus));update("MarketStats",tostring(S.marketSubmitted).." / "..tostring(S.marketClaims).." / "..tostring(S.marketTickets))
        update("FeedStatus",tostring(F.PetFeed.status));update("FeedStats",tostring(F.PetFeed.confirmed).." / $"..C.FormatNumber(F.PetFeed.spent))
        local rows=F.petFeedPets();local names,byName={},{}
        for _,pet in ipairs(rows) do local label=pet.name.." · "..pet.uid;table.insert(names,label);byName[label]=pet end
        updateOptions(ui.PetChoice,names)
        local pet=byName[ui.PetChoice:GetValue()];update("PetHunger",pet and string.format("%.0f / %.0f · %.0f%%",pet.hunger,pet.max,pet.percent) or "Select an active pet")
        update("Cash",G.cash and "$"..C.FormatNumber(G.cash) or "Awaiting cash data")
        update("SessionStatus",tostring(S.statusMessage))
        update("NetworkStatus",C.Dashboard.State.." · presence "..tostring(C.Web.presenceLastOk))
        update("DashboardStatus",C.Dashboard.State..(C.Dashboard.Message and " · "..C.Dashboard.Message or ""))
        if ui.DashboardAutoConnect:GetValue()~=C.Dashboard.Enabled then ui.DashboardAutoConnect:SetValue(C.Dashboard.Enabled) end
        update("ClientUpdate",C.Options.BuildInfo.DisplayVersion.." · "..(C.Web.updateAvailable and ("Update available: "..tostring(C.Web.latestVersion).."; rerun the launcher to update") or C.Web.latestVersion and "No newer public version" or "Not checked (connection is opt-in)"))
        local cfg=w:GetConfigStatus();update("ConfigStatus",cfg.Mode.." · "..tostring(cfg.LastResult and cfg.LastResult.Code or "Ready"))
    end
    local refreshPending=false
    local refresh=function()
        if ui.Dead or refreshPending then return end
        refreshPending=true
        task.defer(function() refreshPending=false;if not ui.Dead then ui:Refresh() end end)
    end
    for _,name in ipairs({"RefreshHeader","UpdateHeader","RefreshSeedStats","RefreshSeedRow","RefreshPriorityRows","UpdateSelection","FlashSeedConfirmed",
        "RefreshBuyControls","UpdateAutoBuy","UpdateControlValues","RefreshCompostSeedRow","UpdateCompostSelection","RefreshCompost","RefreshMarket",
        "RefreshFarm","RefreshInventory","RefreshActivity","RefreshSession","RefreshIncoming","RefreshDiagnostics","UpdatePipeline","UpdateStats","RefreshUpdateStatus","RefreshPetFeed","TickSecond"}) do C.UI[name]=refresh end
    -- The old UI owned these retries. Reuse the existing one-second runtime tick;
    -- delayed prompts/backoff must be rescanned even without a new ChildAdded event.
    C.UI.TickSecond=function()
        if ui.Dead or not C.State.running then return end
        if C.State.autoCollectPetSeeds then C.Farm.scanPetSeeds() end
        if C.State.autoCollectLeaves then C.Farm.scanLeaves() end
        refresh()
    end
    C.UI.SetStatus=function(message,tone) C.State.statusMessage=tostring(message);refresh() end
    C.UI.Toast=function(message,tone) notify("Seed spawn",tostring(message),tone=="bad" and "Error" or "Info") end
    local oldDestroy=w.Destroy
    w.Destroy=function(self)
        if ui.Dead then return end
        ui.AutoPreferences:Flush();ui.Dead=true;C.CancelNetwork();C.Dashboard:Destroy();oldDestroy(self)
        if C.State.running then C.Destroy() end
    end
    function ui:Destroy() w:Destroy() end
    local oldMinimize=w.SetMinimized
    w.SetMinimized=function(self,v) C.State.minimized=v==true;return oldMinimize(self,v) end
    local oldSelect=w.SelectPage
    w.SelectPage=function(self,name,animated) C.State.activeTab=name;return oldSelect(self,name,animated) end
    C.State.activeTab=w.Selected and w.Selected.Name or "Buy Seeds"
    -- Load new namespace after flags exist; legacy preferences supplied defaults only.
    C.Dashboard.OnChange=function() refresh() end
    C.Dashboard.OnWarning=function(message) notify("Dashboard unavailable",message,"Warning") end
    local loaded,loadInfo=w:LoadConfig(ui.AutoPreferences.Profile)
    if not loaded and loadInfo.Code~="Missing" then notify("Preferences not loaded",loadInfo.Message,"Warning") end
    w:SetConfigAutoSave(ui.AutoPreferences.AutoSave,ui.AutoPreferences.Profile,.75)
    ui.Loading=false;ui:SyncPreferences();ui:Refresh()
    installResponsive(Aroyn,w,C.Options.Startup)
    if C.Options.Startup then C.Options.Startup:BindUI(w) end
    return ui
end

end
local function StartupFactory()
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

end
local function Runtime(Aroyn,BuildUI,Options)

-- Aroyn Hub - owner analytics + fast runtime presence + live WebSocket telemetry + anti-AFK
-- Authorized local testing utility.
-- Evolves the proven Farm Assistant V3 into a tabbed farm utility with Auto Compost.
-- Built on the current Seed Auto Buy V2 reliability implementation:
--   * authoritative workspace.BigField.ConveyorSeeds path
--   * per-Instance SeedHolder tracking
--   * live SeedConfig with embedded snapshot fallback
--   * bounded readiness retries
--   * event-driven conveyor watcher
--   * safe singleton unload / re-execution
--
-- Trigger terminology is intentionally precise:
-- "Trigger Attempt" means fireproximityprompt() was actually invoked.
-- It does NOT claim that the server accepted a purchase.


local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

-- V3 keeps the legacy singleton alias so either build cleanly unloads the other.
local GLOBAL_KEY = Options.BuildInfo.RuntimeId
local LEGACY_GLOBAL_KEY = GLOBAL_KEY.."_LEGACY"
local SETTINGS_FOLDER = "AroynHub/SeedAutoBuy"
local SETTINGS_FILE = SETTINGS_FOLDER .. "/settings_v3.json"
local LEGACY_SETTINGS_FILE = SETTINGS_FOLDER .. "/settings_v2.json"

local env
if type(getgenv) == "function" then
    local ok, result = pcall(getgenv)
    if ok and type(result) == "table" then
        env = result
    end
end
env = env or _G
local verificationOnly = Options.VerificationOnly == true
if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "MAIN 03 environment resolved") end

-- Coexistence would duplicate real workers. Refuse rather than unload production.
for _,key in ipairs({"__AROYN_FARM_SINGLETON","__AROYN_SEED_SINGLETON","__FARM_ASSISTANT_V3_SINGLETON","__SEED_AUTO_BUY_SINGLETON_V1","__AROYN_GREEDY_PHASE6A","__AROYN_PHASE9A_STARTUP","__AROYN_GREEDY_PHASE11A","__AROYN_PHASE11A_STARTUP","__AROYN_HUB_GREEDY","__AROYN_HUB_GREEDY_NATIVE"}) do
    local active=rawget(env,key)
    if key~=GLOBAL_KEY and type(active)=="table" and type(active.Destroy)=="function" then
        error("Close the existing Aroyn Hub before starting this build",0)
    end
end
local previous=rawget(env,GLOBAL_KEY)
if type(previous)=="table" and type(previous.Destroy)=="function" then previous.Destroy() end
if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "MAIN 04 singleton cleanup finished") end

-- Do not consume production verification flags.
local App = {}
env[GLOBAL_KEY] = App
if Options.Startup then Options.Startup:BindApp(App) end
env[LEGACY_GLOBAL_KEY] = App
-- Preserve the old alias so re-running an earlier client unloads this build.
-- Production aliases remain untouched.

local state = {
    running = true,
    generation = 1,

    autoBuyEnabled = false,
    autoFeedPetsEnabled = false,
    petFeedThreshold = 25,
    petFeedTarget = 80,
    petFeedMaxValue = 0,
    minimized = false,
    uiVisible = true,

    selectedSeeds = {},
    priorities = {},

    maxPrice = nil,
    rateLimit = 0,
    oneShot = false,
    stopAfter = nil,
    affordableOnly = false,
    cashReserve = 0,
    autoCollectFruits = false,

    -- Autumn event: own-plot leaf collector.
    autoCollectLeaves = false,
    leafAttempts = 0,
    leavesCollected = 0,
    leafErrors = 0,
    lastLeafError = nil,
    leafStatus = "Idle",

    -- Retired legacy flag. Kept internal only for compatibility.
    tpAutoCollectFruits = false,
    tpCollectTeleports = 0,
    lastTpCollectError = nil,

    autoCollectPetSeeds = false,
    petSeedAttempts = 0,
    petSeedsCollected = 0,
    petSeedErrors = 0,
    lastPetSeed = nil,
    lastPetSeedError = nil,
    petSeedStatus = "Idle",

    autoMarketEnabled = false,
    marketSubmitted = 0,
    marketClaims = 0,
    marketTickets = 0,
    marketCollected = 0,
    marketErrors = 0,
    marketStatus = "Idle",
    lastMarketFruit = nil,
    lastMarketError = nil,

    activeTab = "Buy Seeds",
    selectedCompostSeeds = {},
    autoCompostEnabled = false,
    compostAttempts = 0,
    compostConfirmedActions = 0,
    compostSeedsFed = 0,
    compostCycles = 0,
    wormsGranted = 0,
    lastCompostedSeed = nil,
    lastWorm = nil,
    wormHistory = {},
    lastCompostError = nil,
    compostStatus = "Idle",

    spawnAlerts = true,
    alertRarity = "MYTHIC",

    attempts = 0,
    successfulTriggers = 0,
    confirmedSeedPurchases = 0,
    confirmedSeedSpend = 0,
    errors = 0,
    unknown = 0,
    skipped = 0,

    collectAttempts = 0,
    collectTriggered = 0,
    collectConfirmed = 0,
    fruitsCollected = 0,
    collectErrors = 0,
    confirmedFruitValue = 0,
    fruitValueSamples = 0,
    fruitMultiplierSum = 0,
    highestFruitValue = 0,
    highestFruitMultiplier = 0,
    mutationCounts = {},
    sessionStartedAt = os.time(),
    lastAutoBuyError = nil,
    lastAutoCollectError = nil,

    lastSeenKey = nil,
    lastTriggeredKey = nil,
    perSeedStats = {},
    activityLog = {},

    diagnosticsEnabled = false,
    hidePlotVisuals = false,
    configSource = "Unknown",
    configFailure = nil,

    guiScale = 1,
    hotkey = Enum.KeyCode.RightShift,

    settingsAvailable = false,
    settingsFailure = nil,
    settingsMigrated = false,

    antiAfkEnabled = true,
    antiAfkMode = "Pending",
    antiAfkPulses = 0,
    antiAfkLastPulse = nil,
    antiAfkLastError = nil,
}

local connections = {}
local conveyorConnection = nil
local maintenanceThread = nil
local currentConveyor = nil
local bigField = nil
local SeedConfig = nil
local MutationConfig = nil

-- Weak-key tables ensure destroyed physical holders can be collected.
local triggeredHolders = setmetatable({}, { __mode = "k" })
local queuedHolders = setmetatable({}, { __mode = "k" })
local pendingHolders = setmetatable({}, { __mode = "k" })
local holderCache = setmetatable({}, { __mode = "k" })
local unknownCounted = setmetatable({}, { __mode = "k" })
local skippedReasons = setmetatable({}, { __mode = "k" })
local diagnosticResolvedLogged = setmetatable({}, { __mode = "k" })
local unavailablePromptCounted = setmetatable({}, { __mode = "k" })

local seedRows = {}
local seedRecords = {}
local seedByKey = {}
local seedOrderIndex = {}
local exactModelNameToSeedKey = {}
local normalizedModelNameToSeedKey = {}
local normalizedSeedTextToKey = {}
local rarityOrder = {}
local rarityIndex = {}

local triggerQueue = {}
local queueSequence = 0
local queueRevision = 0
local queueWorkerScheduled = false

local ui = {}
local compostSeedRows = {}
local resetV3SessionState = nil

local RETRY_DELAYS = { 0.10, 0.20, 0.35, 0.55, 0.80, 1.10 }
local ACTIVITY_LIMIT = 32

local FULL_SIZE = Vector2.new(1124, 520)
local MINI_SIZE = Vector2.new(590, 46)
local HEADER_HEIGHT = 46

local LIST_NORMAL_HEIGHT = 300
local LIST_DRAWER_HEIGHT = 148
local CONTROLS_NORMAL_Y = 424
local CONTROLS_DRAWER_Y = 272
local SUMMARY_NORMAL_Y = 562
local SUMMARY_DRAWER_Y = 410
local DRAWER_NORMAL_Y = 612
local DRAWER_DRAWER_Y = 456
local DRAWER_COLLAPSED_HEIGHT = 44
local DRAWER_EXPANDED_HEIGHT = 200

local COLORS = {
    Window = Color3.fromRGB(18, 19, 20),
    Header = Color3.fromRGB(22, 23, 25),
    Surface = Color3.fromRGB(26, 28, 30),
    Surface2 = Color3.fromRGB(31, 33, 36),
    Surface3 = Color3.fromRGB(36, 38, 41),
    Hover = Color3.fromRGB(40, 42, 45),
    Pressed = Color3.fromRGB(46, 44, 39),
    Selected = Color3.fromRGB(36, 35, 31),
    Border = Color3.fromRGB(52, 54, 58),
    BorderSoft = Color3.fromRGB(43, 45, 48),
    Text = Color3.fromRGB(235, 231, 221),
    TextMuted = Color3.fromRGB(178, 178, 174),
    TextDim = Color3.fromRGB(138, 140, 142),
    Accent = Color3.fromRGB(198, 158, 87),
    AccentBright = Color3.fromRGB(220, 181, 106),
    AccentSoft = Color3.fromRGB(104, 82, 48),
    AccentDark = Color3.fromRGB(62, 50, 34),
    Success = Color3.fromRGB(119, 177, 128),
    Danger = Color3.fromRGB(202, 104, 101),
    Warning = Color3.fromRGB(208, 166, 92),
}


-- Typography intentionally uses direct Enum.Font.SourceSans values in UI builders.
-- Do NOT reintroduce extra top-level font locals here: this main chunk is large and
-- keeping top-level register pressure low avoids silent compile failure.

local RARITY_COLORS = {
    COMMON = Color3.fromRGB(153, 156, 159),
    RARE = Color3.fromRGB(113, 151, 193),
    EPIC = Color3.fromRGB(154, 121, 187),
    LEGENDARY = Color3.fromRGB(207, 161, 87),
    MYTHIC = Color3.fromRGB(189, 106, 135),
    CELESTIAL = Color3.fromRGB(103, 176, 178),
    SECRET = Color3.fromRGB(190, 188, 182),
    DIVINE = Color3.fromRGB(221, 195, 116),
    TRANSCENDENT = Color3.fromRGB(131, 169, 197),
    ANCIENT = Color3.fromRGB(178, 140, 99),
    UNKNOWN = COLORS.TextDim,
}

local RATE_OPTIONS = { 0, 0.15, 0.25, 0.5, 1.0 }

local function addConnection(connection)
    connections[#connections + 1] = connection
    return connection
end

local function safeDisconnect(connection)
    if connection then
        pcall(function()
            connection:Disconnect()
        end)
    end
end

local function trim(value)
    return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function normalizeName(value)
    local s = trim(value):lower()
    s = s:gsub("[%s_%-%./]+", "")
    s = s:gsub("[^%w]", "")
    return s
end

local function normalizeSeedText(value)
    local s = trim(value):lower()
    s = s:gsub("%s+", " ")
    s = s:gsub("%s+seed%s*$", "")
    s = s:gsub("[^%w]", "")
    return s
end

local function setAmbiguitySafe(map, normalized, key)
    if normalized == "" then
        return
    end
    local current = map[normalized]
    if current == nil then
        map[normalized] = key
    elseif current ~= key then
        map[normalized] = false
    end
end

local function formatNumber(value)
    if type(value) ~= "number" or value ~= value then
        return "?"
    end
    if value == math.huge then
        return "∞"
    end
    if value == -math.huge then
        return "-∞"
    end

    local sign = value < 0 and "-" or ""
    local n = math.abs(value)
    if n < 1000 then
        if math.floor(n) == n then
            return sign .. tostring(math.floor(n))
        end
        return sign .. string.format("%.2f", n):gsub("0+$", ""):gsub("%.$", "")
    end

    local suffixes = {
        "", "K", "M", "B", "T", "Q", "Qi", "Sx", "Sp", "Oc", "No", "Dc",
        "Ud", "Dd", "Td", "Qad", "Qid", "Sxd", "Spd", "Ocd", "Nod", "Vg",
    }

    local group = math.floor(math.log10(n) / 3)
    if group < #suffixes then
        local scaled = n / (10 ^ (group * 3))
        local decimals = scaled >= 100 and 0 or (scaled >= 10 and 1 or 2)
        local text = string.format("%." .. decimals .. "f", scaled)
        text = text:gsub("(%..-)0+$", "%1"):gsub("%.$", "")
        return sign .. text .. suffixes[group + 1]
    end

    local exponent = math.floor(math.log10(n))
    local mantissa = n / (10 ^ exponent)
    return string.format("%s%.2f×10^%d", sign, mantissa, exponent)
end

local SUFFIX_MULTIPLIERS = {
    k = 1e3,
    m = 1e6,
    b = 1e9,
    t = 1e12,
    q = 1e15,
    qi = 1e18,
    sx = 1e21,
    sp = 1e24,
    oc = 1e27,
    no = 1e30,
    dc = 1e33,
}

local function parseCompactNumber(text)
    local s = trim(text):lower():gsub(",", ""):gsub("%s+", "")
    if s == "" or s == "off" or s == "none" or s == "nolimit" or s == "no-limit" then
        return nil
    end

    local direct = tonumber(s)
    if direct then
        return direct
    end

    local numberPart, suffix = s:match("^([%+%-]?[%d%.]+)([%a]+)$")
    if not numberPart then
        return nil, "invalid"
    end

    local base = tonumber(numberPart)
    local mult = SUFFIX_MULTIPLIERS[suffix]
    if not base or not mult then
        return nil, "invalid"
    end
    return base * mult
end

local function compactSeedName(key, data)
    if SeedConfig and type(SeedConfig.SeedDisplayName) == "function" then
        local ok, result = pcall(SeedConfig.SeedDisplayName, key)
        if ok and type(result) == "string" and trim(result) ~= "" then
            return trim(result)
        end
    end

    local display = type(data.displayName) == "string" and trim(data.displayName) or key
    display = display:gsub("%s+[Tt]ree$", "")
    display = display:gsub("%s+[Cc]actus$", "")
    if display:lower():match("seed$") then
        return display
    end
    return display .. " Seed"
end

local function embeddedSeedConfigSnapshot()
    -- Exact metadata snapshot from the supplied/decompiled SeedConfig.
    return {
        Seeds = {
            Oak = { displayName = "Oak Tree", rarity = "COMMON", plantCost = 0, requiredFarmLevel = 1 },
            Pine = { displayName = "Pine Tree", rarity = "COMMON", plantCost = 25, requiredFarmLevel = 1 },
            Apple = { displayName = "Apple Tree", rarity = "RARE", plantCost = 200, requiredFarmLevel = 2 },
            Peach = { displayName = "Peach Tree", rarity = "RARE", plantCost = 350, requiredFarmLevel = 2 },
            Fig = { displayName = "Fig Tree", rarity = "RARE", plantCost = 500, requiredFarmLevel = 2 },
            Orange = { displayName = "Orange Tree", rarity = "EPIC", plantCost = 15000, requiredFarmLevel = 3 },
            Lemon = { displayName = "Lemon Tree", rarity = "EPIC", plantCost = 35000, requiredFarmLevel = 3 },
            Avocado = { displayName = "Avocado Tree", rarity = "EPIC", plantCost = 50000, requiredFarmLevel = 3 },
            Cherry = { displayName = "Cherry Tree", rarity = "LEGENDARY", plantCost = 5000000, requiredFarmLevel = 4 },
            Mango = { displayName = "Mango Tree", rarity = "LEGENDARY", plantCost = 12500000, requiredFarmLevel = 4 },
            Coconut = { displayName = "Coconut Tree", rarity = "LEGENDARY", plantCost = 20000000, requiredFarmLevel = 4 },
            Banana = { displayName = "Banana Tree", rarity = "MYTHIC", plantCost = 3000000000, requiredFarmLevel = 5 },
            Starfruit = { displayName = "Starfruit Tree", rarity = "MYTHIC", plantCost = 4500000000, requiredFarmLevel = 5 },
            DragonFruit = { displayName = "Dragon Fruit Cactus", rarity = "MYTHIC", plantCost = 7000000000, requiredFarmLevel = 5 },
            Glowing = { displayName = "Glowing Tree", rarity = "CELESTIAL", plantCost = 500000000000, requiredFarmLevel = 6 },
            Blooming = { displayName = "Blooming Tree", rarity = "CELESTIAL", plantCost = 750000000000, requiredFarmLevel = 6 },
            Magic = { displayName = "Magic Tree", rarity = "SECRET", plantCost = 500000000000000, requiredFarmLevel = 6 },
            Pizza = { displayName = "Pizza Tree", rarity = "SECRET", plantCost = 850000000000000, requiredFarmLevel = 6 },
            Diamond = { displayName = "Diamond Tree", rarity = "DIVINE", plantCost = 1e18, requiredFarmLevel = 6 },
            Void = { displayName = "Void Tree", rarity = "DIVINE", plantCost = 1.75e18, requiredFarmLevel = 6 },
            Mushroom = { displayName = "Mushroom Tree", rarity = "TRANSCENDENT", plantCost = 7e21, requiredFarmLevel = 6 },
            Money = { displayName = "Money Tree", rarity = "TRANSCENDENT", plantCost = 1.4e22, requiredFarmLevel = 6 },
            Glowshroom = { displayName = "Glowshroom Tree", rarity = "ANCIENT", plantCost = 3.5e27, requiredFarmLevel = 6 },
            Elder = { displayName = "Elder Tree", rarity = "ANCIENT", plantCost = 5e27, requiredFarmLevel = 6 },
        },

        RARITY_WEIGHTS = {
            COMMON = 42.95,
            RARE = 32.5,
            EPIC = 20,
            LEGENDARY = 2.5,
            MYTHIC = 1,
            CELESTIAL = 0.4,
            SECRET = 0.25,
            DIVINE = 0.175,
            TRANSCENDENT = 0.125,
            ANCIENT = 0.1,
        },

        SEED_MODEL_NAMES = {
            Oak = "OakSeed",
            Pine = "PineSeed",
            Apple = "AppleSeed",
            Peach = "PeachSeed",
            Fig = "FigSeed",
            Orange = "OrangeSeed",
            Lemon = "LemonSeed",
            Avocado = "AvacadoSeed",
            Cherry = "CherrySeed",
            Mango = "MangoSeed",
            Coconut = "CoconutSeed",
            Banana = "BananaSeed",
            Starfruit = "StarfruitSeed",
            DragonFruit = "DragonfruitSeed",
            Magic = "MagicSeed",
            Divine = "DivineSeed",
            Mushroom = "MushroomSeed",
            Money = "MoneySeed",
            Glowshroom = "GlowshroomSeed",
            Elder = "ElderSeed",
        },
    }
end

local function acquireGameObjects()
    local foundBigField = workspace:WaitForChild("BigField", 8)
    assert(foundBigField, "workspace.BigField was not found within 8 seconds")
    bigField = foundBigField

    local conveyor = foundBigField:WaitForChild("ConveyorSeeds", 8)
    assert(conveyor, "workspace.BigField.ConveyorSeeds was not found within 8 seconds")

    -- Use the same shared SeedConfig table as the game's plot/controller code.
    -- Older Farm Assistant builds only checked workspace.SeedConfig, which is
    -- absent in the current game and forced the reduced embedded snapshot.
    -- That snapshot is enough for Auto Buy metadata, but it intentionally does
    -- not carry the live fruit-value helpers/sellPrice data, so Plot prices
    -- showed "$—". Prefer the authoritative replicated module first.
    local sharedFolder = ReplicatedStorage:FindFirstChild("Shared")
    local infoFolder = sharedFolder and sharedFolder:FindFirstChild("Info")
    local seedConfigCandidates = {
        { module = infoFolder and infoFolder:FindFirstChild("SeedConfig"), label = "ReplicatedStorage.Shared.Info.SeedConfig" },
        { module = workspace:FindFirstChild("SeedConfig"), label = "workspace.SeedConfig" },
        { module = ReplicatedStorage:FindFirstChild("SeedConfig", true), label = "ReplicatedStorage/**/SeedConfig" },
    }

    local liveOk = false
    local liveResult = nil
    local liveLabel = nil
    local failures = {}

    for _, candidate in ipairs(seedConfigCandidates) do
        local module = candidate.module
        if module and module:IsA("ModuleScript") then
            local ok, result = pcall(require, module)
            if ok and type(result) == "table" and type(result.Seeds) == "table" then
                liveOk = true
                liveResult = result
                liveLabel = candidate.label
                break
            end
            failures[#failures + 1] = candidate.label .. ": " .. tostring(result)
        elseif candidate.label ~= "ReplicatedStorage/**/SeedConfig" then
            failures[#failures + 1] = candidate.label .. ": not found"
        end
    end

    if liveOk then
        SeedConfig = liveResult
        state.configSource = "Live SeedConfig · " .. tostring(liveLabel)
        state.configFailure = nil
        local probeSeed = type(SeedConfig.Seeds) == "table" and (SeedConfig.Seeds.Money or SeedConfig.Seeds.Mushroom or SeedConfig.Seeds.Oak) or nil
    else
        state.configFailure = #failures > 0 and table.concat(failures, " | ") or "SeedConfig module not found"
        warn("[FA V4.3][CONFIG] Live SeedConfig unavailable; using embedded snapshot:", state.configFailure)
        SeedConfig = embeddedSeedConfigSnapshot()
        state.configSource = "Embedded Snapshot"
    end

    -- Fruit mutation calculations use the same shared config as the game's
    -- PlayerPlotController. Keep this optional so a config-path change can
    -- never prevent Farm Assistant from starting.
    local mutationModule = infoFolder and infoFolder:FindFirstChild("MutationConfig")
    if mutationModule and mutationModule:IsA("ModuleScript") then
        local mutationOk, mutationResult = pcall(require, mutationModule)
        if mutationOk and type(mutationResult) == "table" then
            MutationConfig = mutationResult
        else
            warn("[FA V4.3][FRUIT] MutationConfig unavailable:", mutationResult)
        end
    end

    return conveyor
end

local function getPerSeedStat(key)
    local stat = state.perSeedStats[key]
    if type(stat) ~= "table" then
        stat = {
            triggerCount = 0,
            confirmedCount = 0,
            triggerErrors = 0,
            lastTriggeredAt = nil,
            lastConfirmedAt = nil,
            sessionSpendConfirmed = 0,
            spawnCount = 0,
            petCollectedCount = 0,
        }
        state.perSeedStats[key] = stat
    end
    return stat
end

local function formatRelativeTime(lastTriggeredAt, now)
    if type(lastTriggeredAt) ~= "number" then
        return "Never"
    end

    local elapsed = math.max(0, math.floor((now or os.time()) - lastTriggeredAt))
    if elapsed <= 1 then
        return "just now"
    end
    if elapsed < 60 then
        return tostring(elapsed) .. "s ago"
    end
    if elapsed < 3600 then
        local minutes = math.floor(elapsed / 60)
        local seconds = elapsed % 60
        return string.format("%dm %02ds ago", minutes, seconds)
    end

    local hours = math.floor(elapsed / 3600)
    local minutes = math.floor((elapsed % 3600) / 60)
    return string.format("%dh %02dm ago", hours, minutes)
end

local function buildRarityOrder()
    rarityOrder = {}
    rarityIndex = {}

    local firstCost = {}
    for _, record in ipairs(seedRecords) do
        if not firstCost[record.rarity] or record.plantCost < firstCost[record.rarity] then
            firstCost[record.rarity] = record.plantCost
        end
    end

    local seen = {}
    local weights = type(SeedConfig.RARITY_WEIGHTS) == "table" and SeedConfig.RARITY_WEIGHTS or nil

    if weights then
        local weighted = {}
        for rarity, weight in pairs(weights) do
            if firstCost[rarity] ~= nil and type(rarity) == "string" and type(weight) == "number" then
                weighted[#weighted + 1] = { rarity = rarity, weight = weight }
            end
        end
        table.sort(weighted, function(a, b)
            if a.weight ~= b.weight then
                return a.weight > b.weight -- common -> rare progression
            end
            return a.rarity < b.rarity
        end)
        for _, entry in ipairs(weighted) do
            seen[entry.rarity] = true
            rarityOrder[#rarityOrder + 1] = entry.rarity
        end
    end

    -- Any actual Seeds rarity missing from RARITY_WEIGHTS is still represented,
    -- ordered by its lowest observed plant cost.
    local missing = {}
    for rarity, cost in pairs(firstCost) do
        if not seen[rarity] then
            missing[#missing + 1] = { rarity = rarity, cost = cost }
        end
    end
    table.sort(missing, function(a, b)
        if a.cost ~= b.cost then
            return a.cost < b.cost
        end
        return a.rarity < b.rarity
    end)
    for _, entry in ipairs(missing) do
        rarityOrder[#rarityOrder + 1] = entry.rarity
    end

    for i, rarity in ipairs(rarityOrder) do
        rarityIndex[rarity] = i
    end
end

local function buildSeedDatabase()
    local seeds = SeedConfig and SeedConfig.Seeds
    assert(type(seeds) == "table", "SeedConfig.Seeds is missing or not a table")

    local modelNames = type(SeedConfig.SEED_MODEL_NAMES) == "table" and SeedConfig.SEED_MODEL_NAMES or {}

    seedRecords = {}
    seedByKey = {}
    seedOrderIndex = {}
    exactModelNameToSeedKey = {}
    normalizedModelNameToSeedKey = {}
    normalizedSeedTextToKey = {}

    for key, data in pairs(seeds) do
        if type(key) == "string" and type(data) == "table" then
            local configModelName = type(modelNames[key]) == "string" and modelNames[key] or nil
            local record = {
                key = key,
                displayName = type(data.displayName) == "string" and data.displayName or key,
                displaySeedName = compactSeedName(key, data),
                rarity = type(data.rarity) == "string" and data.rarity or "UNKNOWN",
                plantCost = type(data.plantCost) == "number" and data.plantCost or 0,
                requiredFarmLevel = type(data.requiredFarmLevel) == "number" and data.requiredFarmLevel or math.huge,
                modelName = configModelName,
            }

            seedByKey[key] = record
            seedRecords[#seedRecords + 1] = record

            if configModelName then
                exactModelNameToSeedKey[configModelName] = key
                setAmbiguitySafe(normalizedModelNameToSeedKey, normalizeName(configModelName), key)
            end

            -- Robust fallback for Seeds entries not represented in SEED_MODEL_NAMES.
            setAmbiguitySafe(normalizedModelNameToSeedKey, normalizeName(key .. "Seed"), key)

            setAmbiguitySafe(normalizedSeedTextToKey, normalizeSeedText(key), key)
            setAmbiguitySafe(normalizedSeedTextToKey, normalizeSeedText(record.displayName), key)
            setAmbiguitySafe(normalizedSeedTextToKey, normalizeSeedText(record.displaySeedName), key)
            setAmbiguitySafe(normalizedSeedTextToKey, normalizeSeedText(key .. " Seed"), key)
        end
    end

    table.sort(seedRecords, function(a, b)
        if a.requiredFarmLevel ~= b.requiredFarmLevel then
            return a.requiredFarmLevel < b.requiredFarmLevel
        end
        if a.plantCost ~= b.plantCost then
            return a.plantCost < b.plantCost
        end
        return a.displaySeedName:lower() < b.displaySeedName:lower()
    end)

    for i, record in ipairs(seedRecords) do
        seedOrderIndex[record.key] = i
        getPerSeedStat(record.key)
    end

    buildRarityOrder()
end

local function resolveSeedFromBillboard(holder)
    local billboard = holder:FindFirstChild("BillboardGui")
    if not billboard then
        return nil
    end

    local frame = billboard:FindFirstChild("Frame")
    if not frame then
        return nil
    end

    local nameObject = frame:FindFirstChild("Name")
    if not nameObject then
        return nil
    end

    local text
    if nameObject:IsA("TextLabel") or nameObject:IsA("TextButton") or nameObject:IsA("TextBox") then
        text = nameObject.Text
    else
        local ok, value = pcall(function()
            return nameObject.Text
        end)
        if ok and type(value) == "string" then
            text = value
        end
    end

    if type(text) ~= "string" or trim(text) == "" then
        return nil
    end

    local key = normalizedSeedTextToKey[normalizeSeedText(text)]
    if type(key) == "string" then
        return key, "MEDIUM", "billboard name"
    end

    return nil
end

local function resolveSeedType(holder)
    local cached = holderCache[holder]
    if cached and seedByKey[cached.key] then
        return cached.key, cached.confidence, cached.reason
    end

    -- No machine-readable holder attribute has been confirmed, so none is invented.

    for _, child in ipairs(holder:GetChildren()) do
        local key = exactModelNameToSeedKey[child.Name]
        if type(key) == "string" and seedByKey[key] then
            local result = { key = key, confidence = "HIGH", reason = "model mapping" }
            holderCache[holder] = result
            return result.key, result.confidence, result.reason
        end
    end

    for _, child in ipairs(holder:GetChildren()) do
        if not child:IsA("ProximityPrompt")
            and not child:IsA("BillboardGui")
            and not child:IsA("WeldConstraint")
            and not child:IsA("Attachment")
            and not child:IsA("GuiObject") then
            local key = normalizedModelNameToSeedKey[normalizeName(child.Name)]
            if type(key) == "string" and seedByKey[key] then
                local result = { key = key, confidence = "HIGH", reason = "normalized model" }
                holderCache[holder] = result
                return result.key, result.confidence, result.reason
            end
        end
    end

    local key, confidence, reason = resolveSeedFromBillboard(holder)
    if key then
        local result = { key = key, confidence = confidence, reason = reason }
        holderCache[holder] = result
        return result.key, result.confidence, result.reason
    end

    return nil, "NONE", "unresolved"
end

local function findPrompt(holder)
    local direct = holder:FindFirstChildOfClass("ProximityPrompt")
    if direct then
        return direct
    end
    for _, descendant in ipairs(holder:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            return descendant
        end
    end
    return nil
end

local function getDirectChildSummary(holder)
    local names = {}
    local ok = pcall(function()
        for _, child in ipairs(holder:GetChildren()) do
            names[#names + 1] = child.Name
        end
    end)
    if not ok or #names == 0 then
        return "(none)"
    end
    table.sort(names)
    return table.concat(names, ", ")
end

-- ============================================================
-- Settings persistence
-- ============================================================

local function detectSettingsSupport()
    state.settingsAvailable=type(readfile)=="function" and type(isfile)=="function"
    state.settingsFailure=state.settingsAvailable and nil or "Legacy import unavailable"
end

local function settingsPayload()
    local selected = {}
    for key, value in pairs(state.selectedSeeds) do
        if value == true and seedByKey[key] then
            selected[key] = true
        end
    end

    local priorities = {}
    for key, value in pairs(state.priorities) do
        if seedByKey[key] and type(value) == "number" then
            priorities[key] = math.max(1, math.floor(value))
        end
    end

    local posX, posY
    if ui.Window then
        posX = ui.Window.Position.X.Offset
        posY = ui.Window.Position.Y.Offset
    end

    return {
        version = 4,
        selectedSeeds = selected,
        priorities = priorities,
        selectedCompostSeeds = (function()
            local result = {}
            for key, enabled in pairs(state.selectedCompostSeeds) do
                if enabled == true and seedByKey[key] then
                    result[key] = true
                end
            end
            return result
        end)(),
        activeTab = state.activeTab,
        autoBuyEnabled = state.autoBuyEnabled,
        autoCompostEnabled = state.autoCompostEnabled,
        autoFeedPetsEnabled = state.autoFeedPetsEnabled,
        petFeedThreshold = state.petFeedThreshold,
        petFeedTarget = state.petFeedTarget,
        petFeedMaxValue = state.petFeedMaxValue,
        maxPrice = state.maxPrice,
        rateLimit = state.rateLimit,
        oneShot = state.oneShot,
        stopAfter = state.stopAfter,
        affordableOnly = state.affordableOnly,
        cashReserve = state.cashReserve,
        autoCollectFruits = state.autoCollectFruits,
        autoCollectLeaves = state.autoCollectLeaves,
        autoCollectPetSeeds = state.autoCollectPetSeeds,
        autoMarketEnabled = state.autoMarketEnabled,
        spawnAlerts = state.spawnAlerts,
        alertRarity = state.alertRarity,
        diagnosticsEnabled = state.diagnosticsEnabled,
        hidePlotVisuals = state.hidePlotVisuals,
        guiScale = state.guiScale,
        minimized = state.minimized,
        windowX = posX,
        windowY = posY,
        hotkey = state.hotkey and state.hotkey.Name or "RightShift",
    }
end

local saveRevision = 0

local function saveSettingsNow()
    -- New manager saves only preferences; no writes to the production settings format.
    if ui.Integration and not ui.Integration.Loading then ui.Integration:SyncPreferences() end
    return true
end
local function scheduleSettingsSave() saveSettingsNow() end

-- Defined before settings loading; the runtime shares these validators.
function ui.PetFeedFinite(value,fallback)
    local n=tonumber(value)
    if not n or n~=n or math.abs(n)==math.huge then return fallback end
    return n
end
function ui.PetFeedOptions(start,target,cap)
    start=math.clamp(ui.PetFeedFinite(start,25),1,95)
    return start,math.clamp(ui.PetFeedFinite(target,80),start+1,100),math.max(0,ui.PetFeedFinite(cap,0))
end

local function loadSettings()
    detectSettingsSupport()
    if not state.settingsAvailable then
        return
    end

    local chosenFile = SETTINGS_FILE
    local existsOk, exists = pcall(isfile, SETTINGS_FILE)
    if not existsOk then
        return
    end
    if not exists then
        local legacyOk, legacyExists = pcall(isfile, LEGACY_SETTINGS_FILE)
        if legacyOk and legacyExists then
            chosenFile = LEGACY_SETTINGS_FILE
            state.settingsMigrated = true
        else
            chosenFile = nil
            for _, candidate in ipairs({
                "AroynStagingTest/SeedAutoBuy/settings_v3.json",
                "AroynStagingTest/SeedAutoBuy/settings_v2.json",
                "SeedAutoBuy/settings_v3.json", "SeedAutoBuy/settings_v2.json",
            }) do
                local foundOk, found = pcall(isfile, candidate)
                if foundOk and found then chosenFile = candidate; break end
            end
            if not chosenFile then return end
            state.settingsMigrated = true
        end
    end

    local readOk, raw = pcall(readfile, chosenFile)
    if not readOk or type(raw) ~= "string" then
        state.settingsFailure = "settings read failed"
        return
    end

    local decodeOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not decodeOk or type(data) ~= "table" then
        state.settingsFailure = "settings file is corrupt"
        return
    end

    if type(data.selectedSeeds) == "table" then
        for key, selected in pairs(data.selectedSeeds) do
            if selected == true and seedByKey[key] then
                state.selectedSeeds[key] = true
            end
        end
    end

    if type(data.priorities) == "table" then
        for key, priority in pairs(data.priorities) do
            if seedByKey[key] and type(priority) == "number" and priority >= 1 then
                state.priorities[key] = math.floor(priority)
            end
        end
    end

    if type(data.selectedCompostSeeds) == "table" then
        for key, selected in pairs(data.selectedCompostSeeds) do
            if selected == true and seedByKey[key] then
                state.selectedCompostSeeds[key] = true
            end
        end
    end

    if data.activeTab == "Buy Seeds"
        or data.activeTab == "Farm"
        or data.activeTab == "Session"
        or data.activeTab == "Compost"
        or data.activeTab == "Market"
        or data.activeTab == "Pets" then
        state.activeTab = data.activeTab
    end

    state.autoBuyEnabled = data.autoBuyEnabled == true
    state.autoCompostEnabled = data.autoCompostEnabled == true
    state.autoFeedPetsEnabled = data.autoFeedPetsEnabled == true
    state.petFeedThreshold,state.petFeedTarget,state.petFeedMaxValue = ui.PetFeedOptions(data.petFeedThreshold,data.petFeedTarget,data.petFeedMaxValue)

    if type(data.maxPrice) == "number" and data.maxPrice >= 0 then
        state.maxPrice = data.maxPrice
    end

    if type(data.rateLimit) == "number" then
        local allowed = false
        for _, option in ipairs(RATE_OPTIONS) do
            if math.abs(data.rateLimit - option) < 0.0001 then
                allowed = true
                break
            end
        end
        if allowed then
            state.rateLimit = data.rateLimit
        end
    end

    state.oneShot = data.oneShot == true

    if type(data.stopAfter) == "number" and data.stopAfter >= 1 then
        state.stopAfter = math.floor(data.stopAfter)
    end

    state.affordableOnly = data.affordableOnly == true
    if type(data.cashReserve) == "number" and data.cashReserve >= 0 then
        state.cashReserve = data.cashReserve
    end
    state.autoCollectFruits = data.autoCollectFruits == true
    state.autoCollectLeaves = data.autoCollectLeaves == true
    -- TP fruit auto-collect was retired in 4.3.65. Ignore legacy saved value.
    state.tpAutoCollectFruits = false
    state.autoCollectPetSeeds = data.autoCollectPetSeeds == true
    state.autoMarketEnabled = data.autoMarketEnabled == true
    if data.spawnAlerts ~= nil then
        state.spawnAlerts = data.spawnAlerts == true
    end
    if type(data.alertRarity) == "string" then
        state.alertRarity = data.alertRarity
    end

    state.diagnosticsEnabled = data.diagnosticsEnabled == true
    state.hidePlotVisuals = data.hidePlotVisuals == true

    if type(data.guiScale) == "number" then
        if data.guiScale >= 0.89 and data.guiScale <= 1.21 then
            if data.guiScale < 0.95 then
                state.guiScale = 0.9
            elseif data.guiScale < 1.05 then
                state.guiScale = 1.0
            elseif data.guiScale < 1.15 then
                state.guiScale = 1.1
            else
                state.guiScale = 1.2
            end
        end
    end

    state.minimized = false -- Always start expanded; minimize remains session-only until next launch.

    if type(data.windowX) == "number" and type(data.windowY) == "number" then
        state.savedWindowX = math.floor(data.windowX)
        state.savedWindowY = math.floor(data.windowY)
    end

    if type(data.hotkey) == "string" then
        local keyCode = Enum.KeyCode[data.hotkey]
        if keyCode and keyCode ~= Enum.KeyCode.Unknown then
            state.hotkey = keyCode
        end
    end
end

-- ============================================================
-- UI / telemetry bridge
-- ============================================================

local function setText(label, value)
    if label then
        label.Text = tostring(value)
    end
end

local function addActivity(message, tone)
    local entry = {
        time = os.date("%H:%M:%S"),
        ts = os.time() * 1000,
        message = tostring(message),
        tone = tone or "normal",
    }

    state.activityLog[#state.activityLog + 1] = entry
    while #state.activityLog > ACTIVITY_LIMIT do
        table.remove(state.activityLog, 1)
    end

    if ui.RefreshActivity then
        ui.RefreshActivity()
    end
end

local function clearActivity()
    table.clear(state.activityLog)
    if ui.RefreshActivity then
        ui.RefreshActivity()
    end
end

local function resetStats()
    state.attempts = 0
    state.successfulTriggers = 0
    state.confirmedSeedPurchases = 0
    state.confirmedSeedSpend = 0
    state.errors = 0
    state.unknown = 0
    state.skipped = 0
    state.collectAttempts = 0
    state.collectTriggered = 0
    state.collectConfirmed = 0
    state.fruitsCollected = 0
    state.collectErrors = 0
    state.leafAttempts = 0
    state.leavesCollected = 0
    state.leafErrors = 0
    state.lastLeafError = nil
    state.leafStatus = state.autoCollectLeaves and "Watching own plot" or "Idle"
    state.tpCollectTeleports = 0
    state.lastTpCollectError = nil
    state.petSeedAttempts = 0
    state.petSeedsCollected = 0
    state.petSeedErrors = 0
    state.lastPetSeed = nil
    state.lastPetSeedError = nil
    state.petSeedStatus = state.autoCollectPetSeeds and "Watching own plot" or "Idle"
    state.marketSubmitted = 0
    state.marketClaims = 0
    state.marketTickets = 0
    state.marketCollected = 0
    state.marketErrors = 0
    state.lastMarketFruit = nil
    state.lastMarketError = nil
    state.marketStatus = state.autoMarketEnabled and "Watching Farmers Market" or "Idle"
    state.compostAttempts = 0
    state.compostConfirmedActions = 0
    state.compostSeedsFed = 0
    state.compostCycles = 0
    state.wormsGranted = 0
    state.lastCompostedSeed = nil
    state.lastWorm = nil
    table.clear(state.wormHistory)
    state.lastCompostError = nil
    state.confirmedFruitValue = 0
    state.fruitValueSamples = 0
    state.fruitMultiplierSum = 0
    state.highestFruitValue = 0
    state.highestFruitMultiplier = 0
    table.clear(state.mutationCounts)
    state.lastSeenKey = nil
    state.lastTriggeredKey = nil
    table.clear(state.perSeedStats)
    for _, record in ipairs(seedRecords) do
        state.perSeedStats[record.key] = {
            triggerCount = 0,
            confirmedCount = 0,
            triggerErrors = 0,
            lastTriggeredAt = nil,
            lastConfirmedAt = nil,
            sessionSpendConfirmed = 0,
            spawnCount = 0,
            petCollectedCount = 0,
        }
    end
    clearActivity()
    if resetV3SessionState then
        resetV3SessionState()
    end

    if ui.RefreshSeedStats then
        ui.RefreshSeedStats()
    end
    if ui.UpdateStats then
        ui.UpdateStats()
    end
    if ui.UpdateHeader then
        ui.UpdateHeader()
    end
    if ui.SetStatus then
        ui.SetStatus("Session stats reset", "neutral")
    end
end

local function priorityOf(key)
    local value = state.priorities[key]
    return type(value) == "number" and value or math.huge
end

local function normalizePriorities()
    local ranked = {}
    for key, value in pairs(state.priorities) do
        if seedByKey[key]
            and state.selectedSeeds[key] == true
            and type(value) == "number" then
            ranked[#ranked + 1] = { key = key, rank = value }
        end
    end

    table.sort(ranked, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return (seedOrderIndex[a.key] or math.huge) < (seedOrderIndex[b.key] or math.huge)
    end)

    table.clear(state.priorities)
    for i, entry in ipairs(ranked) do
        state.priorities[entry.key] = i
    end
end

local function setPriorityEnabled(key, enabled)
    if not seedByKey[key] then
        return
    end

    if enabled then
        -- Priority belongs to selected seeds. Enabling priority also selects the seed.
        state.selectedSeeds[key] = true

        if not state.priorities[key] then
            local maxPriority = 0
            for _, value in pairs(state.priorities) do
                if type(value) == "number" and value > maxPriority then
                    maxPriority = value
                end
            end
            state.priorities[key] = maxPriority + 1
        end
    else
        state.priorities[key] = nil
    end

    normalizePriorities()

    if ui.RefreshPriorityRows then
        ui.RefreshPriorityRows()
    end
    if ui.UpdateSelection then
        ui.UpdateSelection()
    end

    scheduleSettingsSave()
end

local function movePriority(key, delta)
    normalizePriorities()

    local current = state.priorities[key]
    if not current then
        setPriorityEnabled(key, true)
        current = state.priorities[key]
    end

    local target = current + delta
    if target < 1 then
        return
    end

    local otherKey
    for candidateKey, value in pairs(state.priorities) do
        if value == target then
            otherKey = candidateKey
            break
        end
    end

    if not otherKey then
        return
    end

    state.priorities[key], state.priorities[otherKey] = target, current
    normalizePriorities()

    if ui.RefreshPriorityRows then
        ui.RefreshPriorityRows()
    end

    scheduleSettingsSave()
end


-- ============================================================
-- Conveyor watcher / readiness / queue
-- ============================================================

local scanExistingHolders
local processSeedHolder
local setAutoBuy
local resortQueue
local scheduleQueueWorker

-- ============================================================
-- V3 observed-data mirror / confirmation correlation
-- ============================================================

local GameState = {
    cash = nil,
    startingCash = nil,
    totalPositiveCashDelta = 0,
    totalNegativeCashDelta = 0,
    lastCashAt = nil,

    inventory = {
        hotbar = {},
        storage = {},
        knownHotbarSlots = {},
        hotbarSnapshotKnown = false,
        hotbarCapacity = nil,
    },

    ownPlot = nil,
    trees = setmetatable({}, { __mode = "k" }),
    treesById = {},

    weather = {
        current = nil,
        currentRawTime = nil,
        next = nil,
        nextStartTime = nil,
    },

    incoming = {},
    guarantee = nil,
    lastDataUpdatePath = "—",
    remoteStatus = {},
    lastSeedPurchasedPayload = nil,
    treeSoldEvents = 0,
}

local SEED_CONFIRM_TIMEOUT = 10
local pendingSeedConfirmations = {}
local recentFruitInventoryAdds = {}
local recentFruitCollectedEvents = {}

local function deepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deepCopy(key, seen)] = deepCopy(child, seen)
    end
    return copy
end

local function safeServerTimeNow()
    local ok, value = pcall(function()
        return workspace:GetServerTimeNow()
    end)
    if ok and type(value) == "number" then
        return value
    end
    return nil
end

local function tableValueFlexible(tbl, key)
    if type(tbl) ~= "table" then
        return nil
    end
    local value = tbl[key]
    if value ~= nil then
        return value
    end
    if type(key) == "number" then
        return tbl[tostring(key)]
    end
    if type(key) == "string" then
        local numberKey = tonumber(key)
        if numberKey ~= nil then
            return tbl[numberKey]
        end
    end
    return nil
end

local function getPayloadAtPath(payload, path)
    local value = payload
    if type(path) ~= "table" then
        return nil
    end
    for i = 1, #path do
        value = tableValueFlexible(value, path[i])
        if value == nil then
            return nil
        end
    end
    return value
end

local function normalizeSlotKey(key)
    local n = tonumber(key)
    if n and n >= 1 and n == math.floor(n) then
        return n
    end
    return tostring(key)
end

local function itemSeedCount(item, key)
    if type(item) ~= "table" or item.itemType ~= "Seed" or item.seedType ~= key then
        return 0
    end
    local count = tonumber(item.count)
    if count == nil then
        return 1
    end
    return math.max(0, count)
end

local function seedCountInHotbar(key)
    local total = 0
    for _, item in pairs(GameState.inventory.hotbar) do
        total += itemSeedCount(item, key)
    end
    return total
end

local function allSeedTotals(container)
    local result = {}
    local function visit(value)
        if type(value) ~= "table" then
            return
        end
        if value.itemType ~= nil then
            if value.itemType == "Seed" and type(value.seedType) == "string" then
                local count = tonumber(value.count) or 1
                result[value.seedType] = (result[value.seedType] or 0) + math.max(0, count)
            end
            return
        end
        for _, child in pairs(value) do
            visit(child)
        end
    end
    visit(container)
    return result
end

local function inventoryAggregate()
    local aggregate = {
        seeds = {},
        trees = {},
        fruits = {},
        fruitTotalValue = 0,
        usedHotbar = 0,
        emptyHotbar = 0,
        hotbarCapacity = GameState.inventory.hotbarCapacity,
    }

    local function visit(value, source)
        if type(value) ~= "table" then
            return
        end
        if value.itemType ~= nil then
            local itemType = tostring(value.itemType)
            if itemType == "Seed" and type(value.seedType) == "string" then
                local count = math.max(0, tonumber(value.count) or 1)
                aggregate.seeds[value.seedType] = (aggregate.seeds[value.seedType] or 0) + count
            elseif itemType == "Tree" then
                aggregate.trees[#aggregate.trees + 1] = {
                    source = source,
                    id = value.id,
                    seedType = value.seedType,
                    multiplier = tonumber(value.multiplier),
                    woodValue = tonumber(value.woodValue),
                    stageIndex = tonumber(value.stageIndex),
                    isDead = value.isDead == true,
                    mutations = deepCopy(value.mutations),
                }
            elseif itemType == "Fruit" then
                local count = math.max(0, tonumber(value.count) or 1)
                local sellValue = tonumber(value.sellValue) or 0
                local key = tostring(value.seedType or value.fruitName or "Unknown")
                local entry = aggregate.fruits[key]
                if not entry then
                    entry = { count = 0, totalValue = 0, maxMultiplier = 0, mutations = {} }
                    aggregate.fruits[key] = entry
                end
                entry.count += count
                entry.totalValue += sellValue * count
                entry.maxMultiplier = math.max(entry.maxMultiplier, tonumber(value.multiplier) or 0)
                if type(value.mutations) == "table" then
                    for _, mutation in pairs(value.mutations) do
                        if type(mutation) == "string" then
                            entry.mutations[mutation] = true
                        end
                    end
                end
                aggregate.fruitTotalValue += sellValue * count
            end
            return
        end
        for _, child in pairs(value) do
            visit(child, source)
        end
    end

    visit(GameState.inventory.storage, "Storage")
    for slot, item in pairs(GameState.inventory.hotbar) do
        if type(slot) == "number" and type(item) == "table" then
            if item.empty == true then
                aggregate.emptyHotbar += 1
            else
                aggregate.usedHotbar += 1
            end
        end
        visit(item, "Hotbar")
    end

    return aggregate
end

-- Forward-declare FarmRuntime before AroynWeb so telemetry closures
-- capture the local table instead of resolving a nil global.
local FarmRuntime = {}

-- ============================================================
-- Aroyn Web dashboard telemetry bridge
-- ============================================================
-- One top-level table keeps register pressure low in this already-large chunk.
-- The dashboard key is the bearer secret used by the Roblox runtime; the website uses the signed-in Aroyn account session.
local AroynWeb = {
    apiBase = "https://aroyn-api-staging.veyra-hub.workers.dev",
    key = nil,
    account = nil,
    sessionId = HttpService:GenerateGUID(false),
    thread = nil,
    requestFn = nil,
    pushLatencyMs = nil,
    lastPushOk = false,
    lastError = nil,
    configFile = Options.BuildInfo.CredentialPath,
    siteUrl = "https://aroyn.xyz/",
    wormConfig = nil,
    lastPushAt = nil,
    lastPushPayloadBytes = nil,
    lastReportedError = nil,
    pushIntervalSeconds = 5,
    httpFallbackIntervalSeconds = 300,
    lastHttpPushClock = 0,
    lastHttpAttemptClock = nil,
    liveHttpBase = "https://aroyn-live-staging.veyra-hub.workers.dev",
    liveWsBase = "wss://aroyn-live-staging.veyra-hub.workers.dev",
    liveSocket = nil,
    liveConnected = false,
    liveConnecting = false,
    liveLastConnectClock = 0,
    liveReconnectDelaySeconds = 5,
    liveLastMessageAt = nil,
    liveLastAckAt = nil,
    liveLastError = nil,
    liveAnnounced = false,
    liveConnectAttempt = 0,
    liveLastDisconnectSource = "initial",
    clientVersion = Options.BuildInfo.ClientVersion, -- authoritative generated local build metadata
    updateManifestUrl = "https://aroyn.xyz/scripts/version.json",
    latestVersion = nil,
    updateAvailable = false,
    updateMessage = nil,
    updateLastCheckAt = nil,
    updateLastError = nil,
    updateThread = nil,
    updateIntervalSeconds = 1800,
    presenceThread = nil,
    presenceIntervalSeconds = 300,
    presenceLastOk = false,
    presenceLastError = nil,
    presenceLastAt = nil,
    presenceDashboardLinked = false,
    presenceToken = nil,
}

function AroynWeb.ResolveRequest()
    if type(AroynWeb.requestFn) == "function" then return AroynWeb.requestFn end
    local fn = nil
    if type(request) == "function" then fn = request
    elseif type(http_request) == "function" then fn = http_request
    elseif type(syn) == "table" and type(syn.request) == "function" then fn = syn.request
    elseif type(http) == "table" and type(http.request) == "function" then fn = http.request
    elseif type(fluxus) == "table" and type(fluxus.request) == "function" then fn = fluxus.request
    end
    AroynWeb.requestFn = fn
    return fn
end

function AroynWeb.NormalizeKey(value)
    return trim(tostring(value or "")):upper():gsub("%s+", "")
end

function AroynWeb.ValidKey(value)
    value = AroynWeb.NormalizeKey(value)
    return value:match("^VY%-%x%x%x%x%x%x%-%x%x%x%x%x%x%-%x%x%x%x%x%x%-%x%x%x%x%x%x$") ~= nil
end

function AroynWeb.DeviceType()
    local touch = UserInputService.TouchEnabled == true
    local keyboard = UserInputService.KeyboardEnabled == true
    local gamepad = UserInputService.GamepadEnabled == true
    if touch and not keyboard then return "mobile" end
    if gamepad and not keyboard and not touch then return "console" end
    return "desktop"
end

function AroynWeb.LoadConfig()
    if AroynWeb.ValidKey(AroynWeb.key) then return AroynWeb.key end
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return nil end
    local ok, raw = pcall(function()
        if isfile(AroynWeb.configFile) then return readfile(AroynWeb.configFile) end
        local previous = "AroynHub/web_config.json" -- read-only credential import on explicit Connect
        if isfile(previous) then return readfile(previous) end
        return nil
    end)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local decodedOk, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if decodedOk and type(data) == "table" and AroynWeb.ValidKey(data.dashboardKey) then
        AroynWeb.key = AroynWeb.NormalizeKey(data.dashboardKey)
        env[Options.BuildInfo.RuntimeId.."_DASHBOARD_KEY"] = AroynWeb.key
        return AroynWeb.key
    end
    return nil
end

function AroynWeb.SaveConfig()
    if type(writefile) ~= "function" then return false end
    return pcall(function()
        if type(makefolder)=="function" then
            for _,folder in ipairs({Options.BuildInfo.StorageRoot,Options.BuildInfo.StorageRoot.."/GreedyGrowers"}) do
                if type(isfolder)~="function" or not isfolder(folder) then makefolder(folder) end
            end
        end
        writefile(AroynWeb.configFile, HttpService:JSONEncode({ dashboardKey = AroynWeb.ValidKey(AroynWeb.key) and AroynWeb.key or nil }))
    end)
end

function AroynWeb.CurrentTask()
    local tasks = {}
    if state.autoBuyEnabled then tasks[#tasks + 1] = "Auto Buy" end
    if state.autoCollectFruits then tasks[#tasks + 1] = "Auto Collect All Fruits" end
    if state.autoCollectLeaves then tasks[#tasks + 1] = "Auto Collect Leaves" end
    if state.autoCollectPetSeeds then tasks[#tasks + 1] = "Auto Collect Pet Drops" end
    if state.autoMarketEnabled then tasks[#tasks + 1] = "Auto Farmers Market" end
    if state.autoCompostEnabled then tasks[#tasks + 1] = "Auto Compost" end
    if state.autoFeedPetsEnabled then tasks[#tasks + 1] = "Auto Feed Pets" end
    if #tasks == 0 then return nil end
    return table.concat(tasks, " + ")
end

function AroynWeb.GetWormConfig()
    if AroynWeb.wormConfig ~= nil then
        return AroynWeb.wormConfig or nil
    end
    local result = false
    pcall(function()
        local info = ReplicatedStorage:FindFirstChild("Shared")
        info = info and info:FindFirstChild("Info")
        local module = info and info:FindFirstChild("WormConfig")
        if module and module:IsA("ModuleScript") then
            local loaded = require(module)
            if type(loaded) == "table" then result = loaded end
        end
    end)
    AroynWeb.wormConfig = result
    return result or nil
end

function AroynWeb.CaptureWorm(worm, rollData)
    if type(worm) ~= "table" then return end
    local config = AroynWeb.GetWormConfig()
    local wormType = tostring(worm.wormType or "Worm")
    local mutations = {}
    local mutationSeen = {}
    local function addMutation(value)
        if type(value) ~= "string" or value == "" or mutationSeen[value] then return end
        mutationSeen[value] = true
        mutations[#mutations + 1] = value
    end

    -- WormConfig.GetMutations is the authoritative path and also supports
    -- multi-mutated worms through worm.mutations.
    if config and type(config.GetMutations) == "function" then
        local ok, value = pcall(config.GetMutations, worm)
        if ok and type(value) == "table" then
            for _, mutation in pairs(value) do addMutation(mutation) end
        end
    end

    -- Keep the raw mutation list as a second source in case an executor/runtime
    -- cannot call one of WormConfig's helper functions.
    if type(worm.mutations) == "table" then
        for _, mutation in pairs(worm.mutations) do addMutation(mutation) end
    end

    -- Each mutated worm type in Greedy Growers maps to a mutation in
    -- WormConfig.Worms (DewyWorm -> Dewy, FrostedWorm -> Frosted, etc.).
    -- Read this dynamically so newly-added worm mutations are picked up too.
    if config and type(config.Worms) == "table" then
        local wormInfo = config.Worms[wormType]
        if type(wormInfo) == "table" then addMutation(wormInfo.mutation) end
    end

    -- Final runtime fallback: all current mutated worm types use the
    -- <Mutation>Worm naming scheme. Validate the prefix against MutationConfig,
    -- which lets this cover every mutation known by the live game config rather
    -- than maintaining a fragile hard-coded list.
    local typeMutation = string.match(wormType, "^(.+)Worm$")
    if typeMutation and typeMutation ~= "" and MutationConfig and type(MutationConfig.Mutations) == "table" then
        if MutationConfig.Mutations[typeMutation] ~= nil then addMutation(typeMutation) end
    end
    table.sort(mutations)

    local displayName = wormType
    if config and type(config.DisplayName) == "function" then
        local ok, value = pcall(config.DisplayName, worm)
        if ok and type(value) == "string" and value ~= "" then displayName = value end
    elseif #mutations == 1 then
        displayName = mutations[1] .. " Worm"
    end

    local chance = type(rollData) == "table" and tonumber(rollData.odds) or nil
    if chance == nil and config and type(config.Worms) == "table" then
        local item = config.Worms[wormType]
        if type(item) == "table" and type(item.weight) == "number" then
            local total = 0
            for _, data in pairs(config.Worms) do
                if type(data) == "table" and type(data.weight) == "number" then total += data.weight end
            end
            if total > 0 then chance = item.weight / total end
        end
    end

    state.wormHistory[#state.wormHistory + 1] = {
        id = worm.id,
        wormType = wormType,
        displayName = displayName,
        mult = tonumber(worm.mult),
        mutations = mutations,
        chance = chance,
        receivedAt = os.time() * 1000,
    }
    while #state.wormHistory > 120 do
        table.remove(state.wormHistory, 1)
    end
end

function AroynWeb.SeedStats()
    local rows = {}
    local totalSpawns = 0
    for _, record in ipairs(seedRecords) do
        local stat = getPerSeedStat(record.key)
        local spawned = tonumber(stat.spawnCount) or 0
        local purchased = tonumber(stat.confirmedCount) or 0
        local petCollected = tonumber(stat.petCollectedCount) or 0
        totalSpawns += spawned
        if spawned > 0 or purchased > 0 or petCollected > 0 then
            rows[#rows + 1] = {
                key = record.key,
                name = record.displaySeedName or record.key,
                rarity = record.rarity,
                unitPrice = tonumber(record.plantCost) or 0,
                spawned = spawned,
                purchased = purchased,
                petCollected = petCollected,
                spent = tonumber(stat.sessionSpendConfirmed) or 0,
                lastPurchasedAt = stat.lastConfirmedAt and (stat.lastConfirmedAt * 1000) or nil,
            }
        end
    end
    table.sort(rows, function(a, b)
        if a.purchased ~= b.purchased then return a.purchased > b.purchased end
        if a.spawned ~= b.spawned then return a.spawned > b.spawned end
        return tostring(a.name) < tostring(b.name)
    end)
    return rows, totalSpawns
end

function AroynWeb.TreeStats()
    local trees = {}
    for id, data in pairs(GameState.treesById) do
        if data and data.instance and data.instance.Parent then
            local fruits = {}
            local fruitValue = 0
            local readyFruitValue = 0
            for _, fruitData in pairs(data.fruits or {}) do
                local live = FarmRuntime.liveFruitDisplay(fruitData)
                if live then
                    local sellValue = tonumber(live.sellValue) or 0
                    fruitValue += sellValue
                    if live.ready == true then readyFruitValue += sellValue end
                    fruits[#fruits + 1] = {
                        spawnIndex = live.spawnIndex,
                        name = live.fruitName,
                        seedType = data.seedType,
                        sizeMult = live.sizeMult,
                        multiplier = live.multiplier,
                        mutations = deepCopy(live.mutations),
                        sellValue = live.sellValue,
                        ready = live.ready == true,
                        locked = live.locked == true,
                        waxed = live.waxed == true,
                    }
                end
            end
            table.sort(fruits, function(a, b)
                return (tonumber(a.spawnIndex) or 999999) < (tonumber(b.spawnIndex) or 999999)
            end)

            local mutationList = FarmRuntime.parseFruitMutationList(data.mutations)
            local treeValue = nil
            if type(data.seedType) == "string" and SeedConfig then
                if data.isDead == true and type(SeedConfig.CalcDeadWoodValue) == "function" then
                    local ok, value = pcall(
                        SeedConfig.CalcDeadWoodValue,
                        data.seedType,
                        tonumber(data.multiplier) or 1,
                        mutationList
                    )
                    if ok and type(value) == "number" then treeValue = value end
                elseif type(SeedConfig.CalcTotalTreeValue) == "function" then
                    local ok, value = pcall(
                        SeedConfig.CalcTotalTreeValue,
                        data.seedType,
                        tonumber(data.multiplier) or 1,
                        mutationList
                    )
                    if ok and type(value) == "number" then treeValue = value end
                end
            end

            trees[#trees + 1] = {
                id = tostring(id),
                seedType = data.seedType,
                multiplier = tonumber(data.multiplier),
                mutations = FarmRuntime.mutationsToText(data.mutations),
                mutationList = mutationList,
                isDead = data.isDead == true,
                value = treeValue,
                fruitCount = #fruits,
                readyFruitCount = tonumber(data.readyFruitCount) or 0,
                fruitValue = fruitValue,
                readyFruitValue = readyFruitValue,
                fruits = fruits,
            }
        end
    end
    table.sort(trees, function(a, b)
        local an, bn = tostring(a.seedType or ""), tostring(b.seedType or "")
        if an ~= bn then return an < bn end
        return tostring(a.id) < tostring(b.id)
    end)
    return trees
end

function AroynWeb.InventorySnapshot()
    local currentData = nil
    if type(FarmRuntime.getCurrentData) == "function" then
        local ok, value = pcall(FarmRuntime.getCurrentData)
        if ok and type(value) == "table" then currentData = value end
    end

    local liveInventory = currentData and currentData.Inventory or nil
    local hotbar = type(liveInventory) == "table" and liveInventory.Hotbar or GameState.inventory.hotbar
    local storage = type(liveInventory) == "table" and liveInventory.Storage or GameState.inventory.storage

    local result = {
        items = {},
        worms = {},
        summary = {
            itemStacks = 0,
            totalUnits = 0,
            hotbarUsed = 0,
            hotbarCapacity = tonumber(GameState.inventory.hotbarCapacity),
            storageStacks = 0,
            seedUnits = 0,
            treeItems = 0,
            fruitUnits = 0,
            fruitValue = 0,
            treeWoodValue = 0,
            seedCatalogCost = 0,
            gearUnits = 0,
            pets = 0,
            worms = 0,
            otherUnits = 0,
            byType = {},
        },
    }

    local function itemMutations(value)
        return FarmRuntime.parseFruitMutationList(type(value) == "table" and value.mutations or nil)
    end

    local function seedRecordFor(key)
        if type(key) ~= "string" then return nil end
        return seedByKey[key]
    end

    local function pushItem(value, source, slot)
        if type(value) ~= "table" or value.empty == true then return end
        local itemType = tostring(value.itemType or "Unknown")
        local count = math.max(1, tonumber(value.count) or 1)
        local row = {
            id = value.id and tostring(value.id) or nil,
            itemType = itemType,
            source = source,
            slot = tonumber(slot) or tostring(slot),
            count = count,
            favorited = value.favorited == true,
            mutations = itemMutations(value),
        }

        if itemType == "Seed" then
            local record = seedRecordFor(value.seedType)
            row.seedType = value.seedType
            row.name = record and (record.displaySeedName or record.displayName) or ((tostring(value.seedType or "Unknown")) .. " Seed")
            row.rarity = record and record.rarity or value.rarity
            row.unitPrice = record and tonumber(record.plantCost) or nil
            row.stackValue = row.unitPrice and (row.unitPrice * count) or nil
            result.summary.seedUnits += count
            result.summary.seedCatalogCost += tonumber(row.stackValue) or 0
        elseif itemType == "Tree" then
            row.seedType = value.seedType
            row.name = tostring(value.seedType or "Unknown") .. " Tree"
            row.multiplier = tonumber(value.multiplier)
            row.woodValue = tonumber(value.woodValue)
            row.stageIndex = tonumber(value.stageIndex)
            row.isDead = value.isDead == true
            row.generation = tonumber(value.generation)
            result.summary.treeItems += count
            result.summary.treeWoodValue += (tonumber(row.woodValue) or 0) * count
        elseif itemType == "Fruit" then
            row.seedType = value.seedType
            row.fruitName = value.fruitName
            row.name = tostring(value.fruitName or value.seedType or "Fruit")
            row.multiplier = tonumber(value.multiplier)
            row.sellValue = tonumber(value.sellValue)
            row.stackValue = row.sellValue and (row.sellValue * count) or nil
            result.summary.fruitUnits += count
            result.summary.fruitValue += tonumber(row.stackValue) or 0
        elseif itemType == "Gear" then
            row.gearId = value.gearId
            row.name = tostring(value.gearId or "Gear")
            result.summary.gearUnits += count
        elseif itemType == "Pet" then
            row.petKey = value.petKey
            row.petType = value.petType
            row.petName = value.petName
            row.name = tostring(value.petName or value.petType or "Pet")
            row.rarity = value.rarity
            row.level = tonumber(value.level)
            row.xp = tonumber(value.xp)
            row.hunger = tonumber(value.hunger)
            row.isRainbow = value.isRainbow == true
            row.variant = tonumber(value.variant)
            result.summary.pets += count
        elseif itemType == "Axe" then
            row.name = "Axe"
            result.summary.otherUnits += count
        else
            row.name = tostring(value.name or value.displayName or value.gearId or value.petName or itemType)
            result.summary.otherUnits += count
        end

        -- Preserve useful scalar metadata for future/unknown item types without
        -- serializing arbitrary nested tables into the runtime payload.
        local meta = {}
        local metaCount = 0
        for key, scalar in pairs(value) do
            if key ~= "id" and key ~= "itemType" and key ~= "count"
                and key ~= "mutations" and key ~= "empty"
                and type(key) == "string"
                and (type(scalar) == "string" or type(scalar) == "number" or type(scalar) == "boolean") then
                if row[key] == nil and metaCount < 10 then
                    meta[key] = scalar
                    metaCount += 1
                end
            end
        end
        if metaCount > 0 then row.meta = meta end

        result.summary.itemStacks += 1
        result.summary.totalUnits += count
        result.summary.byType[itemType] = (result.summary.byType[itemType] or 0) + count
        if source == "Hotbar" then
            result.summary.hotbarUsed += 1
        elseif source == "Storage" then
            result.summary.storageStacks += 1
        end
        result.items[#result.items + 1] = row
    end

    if type(hotbar) == "table" then
        local maxSlot = 0
        for slot, item in pairs(hotbar) do
            local numericSlot = tonumber(slot)
            if numericSlot then maxSlot = math.max(maxSlot, numericSlot) end
            pushItem(item, "Hotbar", slot)
        end
        if not result.summary.hotbarCapacity and maxSlot > 0 then
            result.summary.hotbarCapacity = maxSlot
        end
    end
    if type(storage) == "table" then
        for slot, item in pairs(storage) do
            pushItem(item, "Storage", slot)
        end
    end

    table.sort(result.items, function(a, b)
        if a.itemType ~= b.itemType then return a.itemType < b.itemType end
        if tostring(a.name) ~= tostring(b.name) then return tostring(a.name) < tostring(b.name) end
        if a.source ~= b.source then return a.source < b.source end
        return tostring(a.slot) < tostring(b.slot)
    end)

    local wormData = currentData and currentData.Worms or nil
    local wormConfig = AroynWeb.GetWormConfig()
    if type(wormData) == "table" then
        for slot, worm in pairs(wormData) do
            if type(worm) == "table" then
                local wormType = tostring(worm.wormType or "Worm")
                local mutations = {}
                if wormConfig and type(wormConfig.GetMutations) == "function" then
                    local ok, value = pcall(wormConfig.GetMutations, worm)
                    if ok and type(value) == "table" then mutations = value end
                elseif type(worm.mutations) == "table" then
                    mutations = deepCopy(worm.mutations)
                end

                local displayName = wormType
                if wormConfig and type(wormConfig.DisplayName) == "function" then
                    local ok, value = pcall(wormConfig.DisplayName, worm)
                    if ok and type(value) == "string" and value ~= "" then displayName = value end
                end

                local chance = nil
                if wormConfig and type(wormConfig.Worms) == "table" then
                    local info = wormConfig.Worms[wormType]
                    if type(info) == "table" and type(info.weight) == "number" then
                        local total = 0
                        for _, data in pairs(wormConfig.Worms) do
                            if type(data) == "table" and type(data.weight) == "number" then
                                total += data.weight
                            end
                        end
                        if total > 0 then chance = info.weight / total end
                    end
                end

                result.worms[#result.worms + 1] = {
                    slot = tonumber(slot) or tostring(slot),
                    id = worm.id and tostring(worm.id) or nil,
                    wormType = wormType,
                    displayName = displayName,
                    mult = tonumber(worm.mult),
                    mutations = mutations,
                    chance = chance,
                }
            end
        end
    end
    result.summary.worms = #result.worms

    table.sort(result.worms, function(a, b)
        local am, bm = tonumber(a.mult) or 1, tonumber(b.mult) or 1
        if am ~= bm then return am > bm end
        return tostring(a.displayName) < tostring(b.displayName)
    end)

    return result
end

function AroynWeb.BuildSnapshot()
    local aggregate = inventoryAggregate()
    local net = GameState.cash and GameState.startingCash and (GameState.cash - GameState.startingCash) or nil
    local seedStats, totalSeedSpawns = AroynWeb.SeedStats()
    local activity = {}
    local startIndex = math.max(1, #state.activityLog - 19)
    for i = startIndex, #state.activityLog do
        local entry = state.activityLog[i]
        activity[#activity + 1] = { id = i, time = entry.time, ts = entry.ts or (os.time() * 1000), message = entry.message, tone = entry.tone }
    end
    local modules = {
        { name = "SeedConfig", type = "Config", status = SeedConfig and "Ready" or "Warning", loaded = tostring(state.configSource or "Unknown") },
        { name = "MutationConfig", type = "Config", status = MutationConfig and "Ready" or "Idle", loaded = MutationConfig and "Runtime" or "Unavailable" },
        { name = "ObservedData", type = "Stream", status = GameState.lastDataUpdatePath ~= "—" and "Running" or "Idle", loaded = tostring(GameState.lastDataUpdatePath or "—") },
        { name = "OwnPlot", type = "Runtime", status = GameState.ownPlot and "Ready" or "Idle", loaded = GameState.ownPlot and "Detected" or "Waiting" },
        { name = "TelemetryBridge", type = "Bridge", status = AroynWeb.lastPushOk and "Running" or "Idle", loaded = AroynWeb.liveConnected and "WebSocket + HTTP fallback" or (AroynWeb.ResolveRequest() and "HTTP fallback" or "Unavailable") },
    }
    return {
        type = "snapshot",
        schemaVersion = 1,
        sentAt = os.time() * 1000,
        executor = AroynWeb.ExecutorInfo(),
        product = { name = "Aroyn Hub", version = tostring(AroynWeb.clientVersion or "0.0.0"), mode = "Greedy Growers" },
        player = { userId = LocalPlayer and LocalPlayer.UserId or 0, name = LocalPlayer and LocalPlayer.Name or "Unknown", displayName = LocalPlayer and LocalPlayer.DisplayName or "Unknown" },
        session = { id = AroynWeb.sessionId, startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", state.sessionStartedAt), durationSeconds = math.max(0, os.time() - state.sessionStartedAt) },
        runtime = { state = "running", currentTask = AroynWeb.CurrentTask(), taskDetail = state.activeTab and ("Aroyn Hub · " .. tostring(state.activeTab)) or "", pushLatencyMs = AroynWeb.pushLatencyMs },
        stats = {
            cash = GameState.cash, startingCash = GameState.startingCash, netCash = net, seedSpend = state.confirmedSeedSpend,
            fruitsCollected = state.fruitsCollected, collectedFruitValue = state.confirmedFruitValue, fruitInventoryValue = aggregate.fruitTotalValue,
            avgFruitMultiplier = state.fruitValueSamples > 0 and (state.fruitMultiplierSum / state.fruitValueSamples) or nil,
            highestFruitValue = state.highestFruitValue, highestFruitMultiplier = state.highestFruitMultiplier,
            compostSeedsFed = state.compostSeedsFed, compostCycles = state.compostCycles, wormsObtained = state.wormsGranted, petSeedsCollected = state.petSeedsCollected,
            errors = state.errors + state.collectErrors + state.petSeedErrors,
        },
        details = {
            seeds = {
                totalPurchased = state.confirmedSeedPurchases,
                totalSpend = state.confirmedSeedSpend,
                totalSpawns = totalSeedSpawns,
                totalPetCollected = state.petSeedsCollected,
                items = seedStats,
            },
            compost = {
                seedsFed = state.compostSeedsFed,
                cycles = state.compostCycles,
                wormsObtained = state.wormsGranted,
            },
            worms = deepCopy(state.wormHistory),
            trees = AroynWeb.TreeStats(),
            inventory = AroynWeb.InventorySnapshot(),
        },
        activity = activity, logs = activity, modules = modules,
    }
end

function AroynWeb.JsonSafe(value, depth, seen)
    depth = depth or 0
    seen = seen or {}
    if depth > 10 then return tostring(value) end

    local kind = type(value)
    if kind == "nil" or kind == "string" or kind == "boolean" then return value end
    if kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then return nil end
        return value
    end
    if kind ~= "table" then return tostring(value) end
    if seen[value] then return "<cycle>" end
    seen[value] = true

    local numeric, maxIndex, count = true, 0, 0
    for key in pairs(value) do
        count += 1
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            numeric = false
            break
        end
        if key > maxIndex then maxIndex = key end
    end

    local out = {}
    if numeric and maxIndex <= count + 4 then
        for i = 1, maxIndex do
            out[i] = AroynWeb.JsonSafe(value[i], depth + 1, seen)
        end
    else
        for key, item in pairs(value) do
            local safeKey = type(key) == "string" and key or tostring(key)
            out[safeKey] = AroynWeb.JsonSafe(item, depth + 1, seen)
        end
    end
    seen[value] = nil
    return out
end

function AroynWeb.CompactSnapshot(snapshot)
    if type(snapshot) ~= "table" then return snapshot end
    -- Activity and logs contain the same recent entries. Keep activity and use a
    -- shorter log copy when a session becomes unusually large.
    if type(snapshot.logs) == "table" and #snapshot.logs > 10 then
        local trimmed = {}
        for i = math.max(1, #snapshot.logs - 9), #snapshot.logs do trimmed[#trimmed + 1] = snapshot.logs[i] end
        snapshot.logs = trimmed
    end
    local details = snapshot.details
    if type(details) == "table" and type(details.worms) == "table" and #details.worms > 80 then
        local trimmed = {}
        for i = math.max(1, #details.worms - 79), #details.worms do trimmed[#trimmed + 1] = details.worms[i] end
        details.worms = trimmed
    end
    if type(details) == "table" and type(details.trees) == "table" then
        for _, tree in ipairs(details.trees) do
            if type(tree) == "table" and type(tree.fruits) == "table" and #tree.fruits > 24 then
                local trimmed = {}
                for i = 1, 24 do trimmed[i] = tree.fruits[i] end
                tree.fruits = trimmed
                tree.fruitsTruncated = true
            end
        end
    end
    return snapshot
end

function AroynWeb.EncodePayload(payload, compactIfLarge)
    if payload == nil then return true, "", 0 end
    local safe = AroynWeb.JsonSafe(payload)
    local ok, body = pcall(HttpService.JSONEncode, HttpService, safe)
    if not ok then return false, "JSON encode failed: " .. tostring(body), 0 end
    if compactIfLarge and #body > 220 * 1024 then
        safe = AroynWeb.CompactSnapshot(safe)
        ok, body = pcall(HttpService.JSONEncode, HttpService, safe)
        if not ok then return false, "JSON encode failed after compact: " .. tostring(body), 0 end
    end
    return true, body, #body
end

function AroynWeb.ResolveWebSocketConnect()
    local api = rawget(env, "WebSocket")
    if type(api) == "table" and type(api.connect) == "function" then
        return api.connect
    end
    if type(WebSocket) == "table" and type(WebSocket.connect) == "function" then
        return WebSocket.connect
    end
    return nil
end

function AroynWeb.FetchLiveToken()
    local fn = AroynWeb.ResolveRequest()
    if type(fn) ~= "function" then return false, "Executor request API unavailable" end
    local key = AroynWeb.NormalizeKey(AroynWeb.key)
    if not AroynWeb.ValidKey(key) then return false, "Dashboard key is not linked" end
    local robloxUserId = LocalPlayer and LocalPlayer.UserId or nil
    if not robloxUserId then return false, "Roblox user ID unavailable" end

    local encodeOk, body = AroynWeb.EncodePayload({ robloxUserId = tostring(robloxUserId) }, false)
    if not encodeOk then return false, body end

    local ok, response = pcall(fn, {
        Url = AroynWeb.liveHttpBase .. "/token",
        Method = "POST",
        Headers = {
            ["Authorization"] = "Bearer " .. key,
            ["Accept"] = "application/json",
            ["Content-Type"] = "application/json",
        },
        Body = body,
    })
    if not ok then return false, "Executor request failed" end

    local statusCode = tonumber(response and (response.StatusCode or response.Status or response.status_code)) or 0
    if statusCode < 200 or statusCode >= 300 then
        local responseBody = tostring(response and (response.Body or response.body) or "")
        if #responseBody > 180 then responseBody = responseBody:sub(1, 177) .. "..." end
        return false, "Live token HTTP " .. tostring(statusCode)
    end

    local decoded = AroynWeb.ParseResponseBody(response)
    if type(decoded) ~= "table" or decoded.ok ~= true or type(decoded.token) ~= "string" or decoded.token == "" then
        return false, "Live token response was invalid"
    end
    return true, decoded.token
end

function AroynWeb.DisconnectLive()
    local socket = AroynWeb.liveSocket
    AroynWeb.liveLastDisconnectSource = "explicit-disconnect"
    AroynWeb.liveSocket = nil
    AroynWeb.liveConnected = false
    AroynWeb.liveConnecting = false
    if socket then
        pcall(function() socket:Close() end)
    end
end

function AroynWeb.ConnectLive(connectReason)
    if AroynWeb.liveConnected and AroynWeb.liveSocket then return true end
    if AroynWeb.liveConnecting then return false, "Live WebSocket is connecting" end

    local now = os.clock()
    if now - (AroynWeb.liveLastConnectClock or 0) < (AroynWeb.liveReconnectDelaySeconds or 5) then
        return false, AroynWeb.liveLastError or "Live WebSocket reconnect backoff"
    end

    local connect = AroynWeb.ResolveWebSocketConnect()
    if type(connect) ~= "function" then
        AroynWeb.liveLastError = "Executor WebSocket.connect unavailable"
        return false, AroynWeb.liveLastError
    end

    AroynWeb.liveConnecting = true
    AroynWeb.liveLastConnectClock = now

    local tokenOk, tokenOrError = AroynWeb.FetchLiveToken()
    if not tokenOk then
        AroynWeb.liveConnecting = false
        AroynWeb.liveLastError = tostring(tokenOrError)
        return false, AroynWeb.liveLastError
    end

    AroynWeb.liveConnectAttempt = (tonumber(AroynWeb.liveConnectAttempt) or 0) + 1
    local attempt = AroynWeb.liveConnectAttempt
    local reason = tostring(AroynWeb.liveLastDisconnectSource or connectReason or "unknown")
    local wsUrl = AroynWeb.liveWsBase .. "/ws?token=" .. tostring(tokenOrError)
        .. "&sid=" .. HttpService:UrlEncode(tostring(AroynWeb.sessionId))
        .. "&attempt=" .. tostring(attempt)
        .. "&reason=" .. HttpService:UrlEncode(reason)

    local connected, socketOrError = pcall(connect, wsUrl)
    if not connected or not socketOrError then
        AroynWeb.liveConnecting = false
        AroynWeb.liveLastError = "WebSocket connection failed"
        return false, AroynWeb.liveLastError
    end

    local socket = socketOrError
    AroynWeb.liveSocket = socket
    AroynWeb.liveConnected = true
    AroynWeb.liveConnecting = false
    AroynWeb.liveLastError = nil
    AroynWeb.liveLastConnectReason = reason

    pcall(function()
        socket.OnMessage:Connect(function(message)
            if AroynWeb.liveSocket ~= socket then return end
            AroynWeb.liveLastMessageAt = os.time()
            local ok, decoded = pcall(HttpService.JSONDecode, HttpService, tostring(message or ""))
            if ok and type(decoded) == "table" then
                if decoded.type == "relay_ack" then
                    AroynWeb.liveLastAckAt = os.time()
                elseif decoded.type == "connected" then
                    AroynWeb.liveConnected = true
                elseif decoded.type == "update_available"
                    or decoded.type == "version_update"
                    or decoded.type == "update" then

                    local latest = trim(tostring(decoded.version or decoded.latestVersion or ""))
                    if latest ~= "" then
                        local previousLatest = AroynWeb.latestVersion

                        AroynWeb.latestVersion = latest
                        AroynWeb.updateMessage = type(decoded.message) == "string"
                            and decoded.message
                            or AroynWeb.updateMessage
                        AroynWeb.updateAvailable =
                            AroynWeb.IsRemoteVersionNewer(latest, AroynWeb.clientVersion)
                        AroynWeb.updateLastError = nil
                        AroynWeb.updateLastCheckAt = os.time()
                        AroynWeb.RefreshUpdateIndicator()

                        if AroynWeb.updateAvailable and previousLatest ~= latest then
                            addActivity(
                                "Aroyn update available · v" .. tostring(latest),
                                "warning"
                            )
                        end
                    end
                end
            end
        end)
    end)

    pcall(function()
        socket.OnClose:Connect(function()
            if AroynWeb.liveSocket == socket then
                AroynWeb.liveLastDisconnectSource = "onclose"
                AroynWeb.liveSocket = nil
                AroynWeb.liveConnected = false
                AroynWeb.liveLastError = "Live WebSocket closed"
            end
        end)
    end)

    if not AroynWeb.liveAnnounced then
        AroynWeb.liveAnnounced = true
        addActivity("Web dashboard live stream connected", "success")
    end
    return true
end

function AroynWeb.BuildLiveMessages(snapshot)
    local ok, body, bytes = AroynWeb.EncodePayload(snapshot, true)
    if not ok then return false, body end
    if bytes <= 48 * 1024 then return true, { body }, bytes end
    if bytes > 256 * 1024 then return false, "Live snapshot exceeds 256 KiB" end

    -- Some executor transports close on large frames even though the relay
    -- accepts them. Reassemble the original JSON in the dashboard; no rows,
    -- counters or inventory entries are discarded and HTTP stays unchanged.
    local chunks, cursor = {}, 1
    while cursor <= bytes do
        local last = math.min(bytes, cursor + 32 * 1024 - 1)
        -- Keep every chunk valid UTF-8 before encoding it as a JSON string.
        while last < bytes do
            local nextByte = string.byte(body, last + 1)
            if nextByte < 128 or nextByte >= 192 then break end
            last -= 1
        end
        chunks[#chunks + 1] = string.sub(body, cursor, last)
        cursor = last + 1
    end
    if #chunks > 16 then return false, "Too many live snapshot fragments" end
    local transferId = HttpService:GenerateGUID(false)
    local messages = {}
    for index, chunk in ipairs(chunks) do
        local encoded, frame, frameBytes = AroynWeb.EncodePayload({
            type = "snapshot", schemaVersion = 1,
            product = snapshot.product, player = snapshot.player, session = snapshot.session,
            transport = { encoding = "json-fragments-v1", id = transferId,
                index = index, count = #chunks, bytes = bytes, data = chunk },
        }, false)
        if not encoded then return false, frame end
        if frameBytes > 60 * 1024 then return false, "Live fragment exceeds transport budget" end
        messages[#messages + 1] = frame
    end
    return true, messages, bytes
end

function AroynWeb.SendLiveSnapshot(snapshot)
    if not AroynWeb.liveConnected or not AroynWeb.liveSocket then
        local connected, connectError = AroynWeb.ConnectLive("snapshot-no-socket")
        if not connected then return false, connectError end
    end

    local encodeOk, messages, bodyBytes = AroynWeb.BuildLiveMessages(snapshot)
    if not encodeOk then return false, messages end

    local socket = AroynWeb.liveSocket
    local generation = state.generation
    local started = os.clock()
    local sent, sendError = pcall(function()
        for index, frame in ipairs(messages) do
            if not state.running or state.generation ~= generation or AroynWeb.liveSocket ~= socket then
                error("Live snapshot cancelled")
            end
            socket:Send(frame)
            -- Yield between parts: executor Send can enqueue asynchronously.
            -- A synchronous burst disconnected in the real game; paced parts
            -- preserve the complete inventory on that same connection.
            if index < #messages then task.wait(0.15) end
        end
    end)
    local elapsed = os.clock() - started
    -- Keep even 16-part snapshots below the relay's 120 messages/min limit,
    -- with headroom for initial/recovery messages. Small snapshots retain 5s.
    AroynWeb.liveNextPushDelaySeconds = math.max(AroynWeb.pushIntervalSeconds or 5, #messages * 0.625 - elapsed)
    AroynWeb.pushLatencyMs = math.max(0, (os.clock() - started) * 1000)

    if not sent then
        if AroynWeb.liveSocket == socket then
            AroynWeb.liveSocket = nil
            AroynWeb.liveConnected = false
        end
        AroynWeb.liveLastDisconnectSource = "send-failed"
        AroynWeb.liveLastError = "Live send failed"
        pcall(function() socket:Close() end)
        return false, AroynWeb.liveLastError
    end

    AroynWeb.lastPushPayloadBytes = bodyBytes
    AroynWeb.liveLastError = nil
    return true
end

function AroynWeb.Request(path, method, payload, keyOverride)
    local fn = AroynWeb.ResolveRequest()
    if type(fn) ~= "function" then return false, "Executor request API unavailable" end
    local key = AroynWeb.NormalizeKey(keyOverride or AroynWeb.key)
    if not AroynWeb.ValidKey(key) then return false, "Dashboard key is not linked" end

    local httpMethod = string.upper(tostring(method or "GET"))
    local encodeOk, body, bodyBytes = AroynWeb.EncodePayload(payload, path == "/api/v2/runtime/push")
    if not encodeOk then return false, body end
    if path == "/api/v2/runtime/push" then AroynWeb.lastPushPayloadBytes = bodyBytes end

    local options = {
        Url = AroynWeb.apiBase .. path,
        Method = httpMethod,
        Headers = {
            ["Authorization"] = "Bearer " .. key,
            ["Accept"] = "application/json",
        },
    }
    if httpMethod ~= "GET" and httpMethod ~= "HEAD" then
        options.Headers["Content-Type"] = "application/json"
        options.Body = body
    end

    local started = os.clock()
    local ok, response = pcall(fn, options)
    AroynWeb.pushLatencyMs = math.max(0, (os.clock() - started) * 1000)
    if not ok then return false, tostring(response) end
    local statusCode = tonumber(response and (response.StatusCode or response.Status or response.status_code)) or 0
    if statusCode >= 200 and statusCode < 300 then return true, response end
    local responseBody = tostring(response and (response.Body or response.body) or "")
    if #responseBody > 180 then responseBody = responseBody:sub(1, 177) .. "..." end
    return false, "HTTP " .. tostring(statusCode) .. (responseBody ~= "" and (" · " .. responseBody) or "")
end

function AroynWeb.ParseResponseBody(response)
    local body = response and (response.Body or response.body)
    if type(body) ~= "string" or body == "" then return nil end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, body)
    return ok and decoded or nil
end

function AroynWeb.IsRemoteVersionNewer(remoteVersion, currentVersion)
    local remote = {}
    local current = {}

    for part in tostring(remoteVersion or ""):gmatch("%d+") do
        remote[#remote + 1] = tonumber(part) or 0
    end
    for part in tostring(currentVersion or ""):gmatch("%d+") do
        current[#current + 1] = tonumber(part) or 0
    end

    local count = math.max(#remote, #current)
    if count == 0 then return false end

    for i = 1, count do
        local a = remote[i] or 0
        local b = current[i] or 0
        if a ~= b then
            return a > b
        end
    end

    return false
end

function AroynWeb.RefreshUpdateIndicator()
    if ui.RefreshUpdateStatus then
        pcall(ui.RefreshUpdateStatus)
    end
end

function AroynWeb.CheckUpdateOnce()
    if not state.running then return false, "client stopped" end
    local generation = state.generation
    local fn = AroynWeb.ResolveRequest()
    if type(fn) ~= "function" then
        AroynWeb.updateLastError = "request API unavailable"
        AroynWeb.RefreshUpdateIndicator()
        return false, AroynWeb.updateLastError
    end

    local url = tostring(AroynWeb.updateManifestUrl or "")
    if url == "" then
        AroynWeb.updateLastError = "update manifest URL missing"
        AroynWeb.RefreshUpdateIndicator()
        return false, AroynWeb.updateLastError
    end

    local separator = url:find("?", 1, true) and "&" or "?"
    local ok, response = pcall(fn, {
        Url = url .. separator .. "t=" .. tostring(os.time()),
        Method = "GET",
        Headers = {
            ["Accept"] = "application/json",
            ["Cache-Control"] = "no-cache",
        },
    })

    if not state.running or state.generation ~= generation then return false, "client stopped" end
    AroynWeb.updateLastCheckAt = os.time()

    if not ok then
        AroynWeb.updateLastError = tostring(response)
        AroynWeb.RefreshUpdateIndicator()
        return false, AroynWeb.updateLastError
    end

    local statusCode = tonumber(response and (response.StatusCode or response.Status or response.status_code)) or 0
    if statusCode < 200 or statusCode >= 300 then
        AroynWeb.updateLastError = "HTTP " .. tostring(statusCode)
        AroynWeb.RefreshUpdateIndicator()
        return false, AroynWeb.updateLastError
    end

    local decoded = AroynWeb.ParseResponseBody(response)
    if type(decoded) ~= "table" then
        AroynWeb.updateLastError = "invalid update manifest"
        AroynWeb.RefreshUpdateIndicator()
        return false, AroynWeb.updateLastError
    end

    local latest = trim(tostring(decoded.version or decoded.latestVersion or ""))
    if latest == "" then
        AroynWeb.updateLastError = "manifest version missing"
        AroynWeb.RefreshUpdateIndicator()
        return false, AroynWeb.updateLastError
    end

    local previousLatest = AroynWeb.latestVersion
    AroynWeb.latestVersion = latest
    AroynWeb.updateMessage = type(decoded.message) == "string" and decoded.message or nil
    AroynWeb.updateAvailable = AroynWeb.IsRemoteVersionNewer(latest, AroynWeb.clientVersion)
    AroynWeb.updateLastError = nil
    AroynWeb.RefreshUpdateIndicator()
    if AroynWeb.updateAvailable and previousLatest ~= latest then
        addActivity("Aroyn update available · v" .. tostring(latest), "warning")
    end
    return true, decoded
end

function AroynWeb.StartUpdateWatch()
    if AroynWeb.updateThread then return end

    local generation = state.generation
    AroynWeb.updateThread = task.spawn(function()
        task.wait(0.20)
        while state.running and state.generation == generation do
            pcall(AroynWeb.CheckUpdateOnce)

            local deadline = os.clock() + math.max(60, tonumber(AroynWeb.updateIntervalSeconds) or 1800)
            while state.running
                and state.generation == generation
                and os.clock() < deadline do
                task.wait(1)
            end
        end
        AroynWeb.updateThread = nil
    end)
end

function AroynWeb.CleanExecutorText(value, limit)
    if type(value) ~= "string" then return nil end
    local text = value:sub(1, 256):gsub("[^ -~]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
    local lower = text:lower()
    if text == "" or lower == "unknown" or lower == "nil" or lower == "null" or lower == "undefined" then return nil end
    return text:sub(1, limit)
end

function AroynWeb.ExecutorInfo()
    if AroynWeb.executorInfo then return AroynWeb.executorInfo end
    local function probe(fn)
        if type(fn) ~= "function" then return nil end
        local ok, name, version = pcall(fn)
        if not ok then return nil end
        name = AroynWeb.CleanExecutorText(name, 64)
        if not name then return nil end
        return { name = name, version = AroynWeb.CleanExecutorText(version, 32) }
    end
    AroynWeb.executorInfo = probe(identifyexecutor) or probe(getexecutorname) or { name = "Unknown" }
    return AroynWeb.executorInfo
end

function AroynWeb.PresencePayload()
    if not AroynWeb.presenceResumeNonce then
        AroynWeb.presenceResumeNonce = (HttpService:GenerateGUID(false) .. HttpService:GenerateGUID(false)):gsub("-", ""):lower()
    end
    local executor = AroynWeb.ExecutorInfo()
    return {
        executorName = executor.name, executorVersion = executor.version,
        type = "presence", sessionId = tostring(AroynWeb.sessionId),
        robloxUserId = tostring(LocalPlayer and LocalPlayer.UserId or ""),
        version = tostring(AroynWeb.clientVersion or "0.0.0"),
        gameId = tostring(game.GameId), placeId = tostring(game.PlaceId),
        gameSlug = "greedy-growers", device = AroynWeb.DeviceType(),
        dashboardKey = AroynWeb.ValidKey(AroynWeb.key) and AroynWeb.NormalizeKey(AroynWeb.key) or nil,
        presenceToken = AroynWeb.presenceToken, resumeNonce = AroynWeb.presenceResumeNonce,
    }
end

function AroynWeb.ClosePresenceSocket()
    local socket = AroynWeb.presenceSocket
    AroynWeb.presenceSocket = nil
    AroynWeb.presenceWsAck = nil
    for _, connection in ipairs(AroynWeb.presenceConnections or {}) do
        pcall(function() connection:Disconnect() end)
    end
    AroynWeb.presenceConnections = nil
    if socket then pcall(function() socket:Close() end) end
end

function AroynWeb.PresenceSocketFailed(reason)
    AroynWeb.ClosePresenceSocket()
    AroynWeb.presenceWsLastError = tostring(reason or "Presence WebSocket closed")
    local delay = math.min(300, AroynWeb.presenceReconnectDelaySeconds or 5)
    AroynWeb.presenceRetryAt = os.clock() + delay
    AroynWeb.presenceReconnectDelaySeconds = math.min(300, delay * 2)
    -- The last HTTPS heartbeat may be several minutes old. Failover is due now.
    AroynWeb.presenceHttpDueAt = nil
end

function AroynWeb.ConnectPresenceSocket()
    if AroynWeb.presenceSocket then return true end
    if os.clock() < (AroynWeb.presenceRetryAt or 0) then return false end
    local connect = AroynWeb.ResolveWebSocketConnect()
    if type(connect) ~= "function" then return false end
    local generation = state.generation
    local ok, socket = pcall(connect, AroynWeb.liveWsBase .. "/runtime-presence/ws?sid=" .. HttpService:UrlEncode(tostring(AroynWeb.sessionId)))
    if not ok or not socket then AroynWeb.PresenceSocketFailed("Presence WebSocket connect failed"); return false end
    if not state.running or state.generation ~= generation then pcall(function() socket:Close() end); return false end
    AroynWeb.presenceSocket = socket
    local connections = {}
    local handlersOk = pcall(function()
        connections[#connections + 1] = socket.OnMessage:Connect(function(message)
            if AroynWeb.presenceSocket ~= socket or state.generation ~= generation then return end
            local decodedOk, decoded = pcall(HttpService.JSONDecode, HttpService, tostring(message or ""))
            if not decodedOk or type(decoded) ~= "table" then return end
            if decoded.sequence ~= AroynWeb.presenceSequence then return end
            if decoded.type == "presence_disconnected" and decoded.ok == true then
                AroynWeb.presenceDisconnectAck = decoded.sequence
                return
            end
            if not state.running then return end
            if decoded.type == "presence_ack" and decoded.ok == true and type(decoded.presenceToken) == "string" then
                AroynWeb.presenceToken = decoded.presenceToken
                AroynWeb.presenceWsAck = decoded.sequence
                AroynWeb.presenceWsLastAckClock = os.clock()
                AroynWeb.presenceIntervalSeconds = math.clamp(tonumber(decoded.heartbeatSeconds) or 300, 15, 300)
                AroynWeb.presenceDashboardLinked = decoded.dashboardLinked == true
                AroynWeb.presenceLastOk = true
                AroynWeb.presenceLastError = nil
                AroynWeb.presenceLastAt = os.time()
                AroynWeb.presenceTransport = "websocket"
                AroynWeb.presenceReconnectDelaySeconds = 5
                AroynWeb.presenceWsLastError = nil
            elseif decoded.type == "presence_error" then
                AroynWeb.PresenceSocketFailed("Presence server rejected the message")
            end
        end)
        connections[#connections + 1] = socket.OnClose:Connect(function()
            if AroynWeb.presenceSocket == socket then AroynWeb.PresenceSocketFailed("Presence WebSocket closed") end
        end)
    end)
    AroynWeb.presenceConnections = connections
    if not handlersOk then AroynWeb.PresenceSocketFailed("Executor presence events unavailable"); return false end
    return true
end

function AroynWeb.PresenceWebSocketOnce()
    if not AroynWeb.ConnectPresenceSocket() then return false end
    local socket = AroynWeb.presenceSocket
    local key = AroynWeb.NormalizeKey(AroynWeb.key)
    local due = AroynWeb.presenceWsLastAckClock == nil
        or os.clock() - AroynWeb.presenceWsLastAckClock >= (AroynWeb.presenceIntervalSeconds or 300)
        or AroynWeb.presenceWsKey ~= key or AroynWeb.presenceWsAck == nil
    if not due then return true end
    AroynWeb.presenceSequence = (AroynWeb.presenceSequence or 0) + 1
    local sequence = AroynWeb.presenceSequence
    local payload = AroynWeb.PresencePayload()
    payload.sequence = sequence
    local encoded, body = AroynWeb.EncodePayload(payload, false)
    if not encoded then AroynWeb.PresenceSocketFailed("Presence encode failed"); return false end
    local sent = pcall(function() socket:Send(body) end)
    if not sent then AroynWeb.PresenceSocketFailed("Presence send failed"); return false end
    local generation, started = state.generation, os.clock()
    while state.running and state.generation == generation and AroynWeb.presenceSocket == socket
        and AroynWeb.presenceWsAck ~= sequence and os.clock() - started < 5 do task.wait(0.1) end
    if AroynWeb.presenceWsAck == sequence and AroynWeb.presenceSocket == socket then
        AroynWeb.presenceWsKey = key
        return true
    end
    if AroynWeb.presenceSocket == socket then AroynWeb.PresenceSocketFailed("Presence acknowledgement timed out") end
    return false
end

function AroynWeb.PresenceHttpOnce()
    -- Basic online/session accounting is independent of dashboard linking.
    -- Inventory, activity and detailed snapshots still require a valid key.
    local fn = AroynWeb.ResolveRequest()
    if type(fn) ~= "function" then
        AroynWeb.presenceLastOk = false
        AroynWeb.presenceLastError = "Executor request API unavailable"
        return false, AroynWeb.presenceLastError
    end

    local robloxUserId = LocalPlayer and LocalPlayer.UserId or nil
    if not robloxUserId then
        AroynWeb.presenceLastOk = false
        AroynWeb.presenceLastError = "Roblox user ID unavailable"
        return false, AroynWeb.presenceLastError
    end

    local payload = AroynWeb.PresencePayload()
    local encodeOk, body = AroynWeb.EncodePayload({
        resumeNonce = payload.resumeNonce,
        executorName = payload.executorName, executorVersion = payload.executorVersion,
        sessionId = tostring(AroynWeb.sessionId),
        robloxUserId = tostring(robloxUserId),
        version = tostring(AroynWeb.clientVersion or "0.0.0"),
        gameId = tostring(game.GameId),
        placeId = tostring(game.PlaceId),
        gameSlug = "greedy-growers",
        device = AroynWeb.DeviceType(),
    }, false)
    if not encodeOk then
        AroynWeb.presenceLastOk = false
        AroynWeb.presenceLastError = tostring(body)
        return false, AroynWeb.presenceLastError
    end

    local headers = {
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
    }
    local key = AroynWeb.NormalizeKey(AroynWeb.key)
    if AroynWeb.ValidKey(key) then
        headers["Authorization"] = "Bearer " .. key
    end
    if type(AroynWeb.presenceToken) == "string" and AroynWeb.presenceToken ~= "" then
        headers["X-Presence-Token"] = AroynWeb.presenceToken
    end

    local ok, response = pcall(fn, {
        Url = AroynWeb.liveHttpBase .. "/runtime-presence",
        Method = "POST",
        Headers = headers,
        Body = body,
    })
    if not ok then
        AroynWeb.presenceLastOk = false
        AroynWeb.presenceLastError = "Executor presence request failed"
        return false, AroynWeb.presenceLastError
    end

    local statusCode = tonumber(response and (response.StatusCode or response.Status or response.status_code)) or 0
    if statusCode < 200 or statusCode >= 300 then
        local responseBody = tostring(response and (response.Body or response.body) or "")
        if #responseBody > 180 then responseBody = responseBody:sub(1, 177) .. "..." end
        AroynWeb.presenceLastOk = false
        AroynWeb.presenceLastError = "Presence HTTP " .. tostring(statusCode)
        return false, AroynWeb.presenceLastError
    end

    local decoded = AroynWeb.ParseResponseBody(response)
    if type(decoded) == "table" and type(decoded.presenceToken) == "string" then
        AroynWeb.presenceToken = decoded.presenceToken
    end
    AroynWeb.presenceTransport = "https"
    AroynWeb.presenceLastOk = true
    AroynWeb.presenceLastError = nil
    AroynWeb.presenceLastAt = os.time()
    AroynWeb.presenceDashboardLinked = type(decoded) == "table" and decoded.dashboardLinked == true or false

    local serverHeartbeat = type(decoded) == "table" and tonumber(decoded.heartbeatSeconds) or nil
    if serverHeartbeat then
        AroynWeb.presenceIntervalSeconds = math.clamp(serverHeartbeat, 15, 300)
    else
        AroynWeb.presenceIntervalSeconds = 300
    end

    return true, decoded
end

function AroynWeb.PresenceOnce()
    if not state.running then return false end
    -- The authenticated telemetry socket already checkpoints linked presence.
    -- Reuse it only while actual relay acknowledgements remain fresh.
    local ackAge = os.time() - (tonumber(AroynWeb.liveLastAckAt) or 0)
    if AroynWeb.ValidKey(AroynWeb.key) and AroynWeb.liveConnected and AroynWeb.liveSocket
        and AroynWeb.liveLastAckAt and ackAge >= 0 and ackAge <= 30 then
        -- Obtain a scoped presence token once, so later unlink/failover can
        -- continue without the dashboard credential or a second live socket.
        if not AroynWeb.presenceToken then
            local registered = AroynWeb.PresenceHttpOnce()
            if not registered then return false end
        end
        AroynWeb.ClosePresenceSocket()
        AroynWeb.presenceTransport = "live-websocket"
        AroynWeb.presenceLastOk = true
        AroynWeb.presenceLastError = nil
        AroynWeb.presenceLastAt = os.time()
        AroynWeb.presenceDashboardLinked = true
        return true
    end
    local generation = state.generation
    if AroynWeb.PresenceWebSocketOnce() then return true end
    if not state.running or state.generation ~= generation then return false end
    local key = AroynWeb.NormalizeKey(AroynWeb.key)
    if key == AroynWeb.presenceHttpKey and os.clock() < (AroynWeb.presenceHttpDueAt or 0) then
        return AroynWeb.presenceLastOk == true
    end
    local ok, result = AroynWeb.PresenceHttpOnce()
    AroynWeb.presenceHttpKey = key
    AroynWeb.presenceHttpDueAt = os.clock() + (ok and (AroynWeb.presenceIntervalSeconds or 300) or 15)
    return ok, result
end

function AroynWeb.StartPresence()
    if AroynWeb.presenceThread then return true end
    if type(AroynWeb.ResolveRequest()) ~= "function" and type(AroynWeb.ResolveWebSocketConnect()) ~= "function" then
        AroynWeb.presenceLastOk = false
        AroynWeb.presenceLastError = "Executor transport API unavailable"
        return false, AroynWeb.presenceLastError
    end
    local generation = state.generation
    AroynWeb.presenceThread = task.spawn(function()
        while state.running and state.generation == generation do
            local ok, err = pcall(AroynWeb.PresenceOnce)
            if not ok then AroynWeb.presenceLastOk = false; AroynWeb.presenceLastError = tostring(err) end
            task.wait(5)
        end
        AroynWeb.ClosePresenceSocket()
        AroynWeb.presenceThread = nil
    end)
    return true
end

function AroynWeb.VerifyKey(rawKey)
    local key = AroynWeb.NormalizeKey(rawKey)
    if not AroynWeb.ValidKey(key) then return false, "Invalid dashboard key format" end
    local ok, responseOrError = AroynWeb.Request("/api/v2/runtime/verify", "GET", nil, key)
    if not ok then return false, responseOrError end
    local decoded = AroynWeb.ParseResponseBody(responseOrError)
    if type(decoded) ~= "table" or decoded.ok ~= true or type(decoded.user) ~= "table" then
        return false, "Dashboard account response was invalid"
    end
    return true, decoded.user, key
end

function AroynWeb.RelinkRobloxAccount(key)
    local robloxUserId = LocalPlayer and LocalPlayer.UserId or nil
    if not robloxUserId then return false, "Roblox user ID unavailable" end
    local ok, responseOrError = AroynWeb.Request("/api/v2/runtime/link", "POST", { robloxUserId = robloxUserId }, key)
    if not ok then return false, responseOrError end
    local decoded = AroynWeb.ParseResponseBody(responseOrError)
    if type(decoded) ~= "table" or decoded.ok ~= true then return false, "Dashboard relink response was invalid" end
    return true, decoded
end

function AroynWeb.PushOnce()
    if not AroynWeb.ValidKey(AroynWeb.key) then
        AroynWeb.lastPushOk = false
        AroynWeb.lastError = "Dashboard key is not linked"
        return false, AroynWeb.lastError
    end

    local snapshotOk, snapshot = pcall(AroynWeb.BuildSnapshot)
    if not snapshotOk then
        AroynWeb.lastPushOk = false
        AroynWeb.lastError = "Snapshot error: " .. tostring(snapshot)
        if AroynWeb.lastReportedError ~= AroynWeb.lastError then
            AroynWeb.lastReportedError = AroynWeb.lastError
            addActivity("Web dashboard push failed · " .. AroynWeb.lastError, "warning")
        end
        return false, AroynWeb.lastError
    end

    -- Bootstrap the account and session over HTTP before requesting a live
    -- token or presence. os.clock() can be below 300 in a fresh executor.
    -- Fresh relay ACKs allow the usual persistence interval. Without them,
    -- accepted HTTP snapshots every 5 seconds stay below the API 9-second TTL.
    local httpOk, httpErr = false, nil
    local bootstrapped = AroynWeb.runtimeRegistered == true or (tonumber(AroynWeb.lastHttpPushClock) or 0) > 0
    local ack = tonumber(AroynWeb.liveLastAckAt) or 0
    local healthyLive = AroynWeb.liveConnected and ack > 0 and os.time() - ack <= 9
    local httpInterval = bootstrapped and (healthyLive and (tonumber(AroynWeb.httpFallbackIntervalSeconds) or 300) or 5) or 15
    local httpDue = AroynWeb.lastHttpAttemptClock == nil or (os.clock() - AroynWeb.lastHttpAttemptClock) >= httpInterval

    if httpDue then
        AroynWeb.lastHttpAttemptClock = os.clock()
        httpOk, httpErr = AroynWeb.Request("/api/v2/runtime/push", "POST", snapshot)
        if httpOk then
            local response = AroynWeb.ParseResponseBody(httpErr)
            httpOk = type(response) == "table" and response.ok == true
        end
        if httpOk then
            AroynWeb.lastHttpPushClock = os.clock()
            AroynWeb.runtimeRegistered = true
            bootstrapped = true
            AroynWeb.StartPresence()
        end
    end
    local liveOk, liveErr = false, nil
    if bootstrapped then
        liveOk, liveErr = AroynWeb.SendLiveSnapshot(snapshot)
    else
        liveErr = httpErr or "Waiting for initial HTTP snapshot"
    end

    local ok = liveOk or httpOk
    local err = nil
    if not ok then
        err = tostring(liveErr or "") .. (liveErr and httpErr and " · " or "") .. tostring(httpErr or "")
    end
    AroynWeb.lastPushOk = ok
    AroynWeb.lastError = err

    if ok then
        AroynWeb.lastPushAt = os.time()
        AroynWeb.lastReportedError = nil
    elseif AroynWeb.lastReportedError ~= AroynWeb.lastError then
        AroynWeb.lastReportedError = AroynWeb.lastError
        addActivity("Web dashboard push failed · " .. tostring(AroynWeb.lastError), "warning")
    end
    return ok, err
end

function AroynWeb.DisconnectPresence()
    local socket = AroynWeb.presenceSocket
    if socket and type(AroynWeb.presenceToken) == "string" then
        local payload = AroynWeb.PresencePayload()
        payload.type = "presence_disconnect"
        AroynWeb.presenceSequence = (AroynWeb.presenceSequence or 0) + 1
        payload.sequence = AroynWeb.presenceSequence
        local encoded, body = AroynWeb.EncodePayload(payload, false)
        local sent = encoded and pcall(function() socket:Send(body) end)
        local started = os.clock()
        while sent and AroynWeb.presenceSocket == socket and AroynWeb.presenceDisconnectAck ~= payload.sequence
            and os.clock() - started < 2 do task.wait(0.05) end
        local confirmed = AroynWeb.presenceDisconnectAck == payload.sequence
        AroynWeb.ClosePresenceSocket()
        if confirmed then return true end
    else
        AroynWeb.ClosePresenceSocket()
    end
    local fn = AroynWeb.ResolveRequest()
    if type(fn) ~= "function" then return false end
    local encodeOk, body = AroynWeb.EncodePayload({ sessionId = AroynWeb.sessionId }, false)
    if not encodeOk then return false end
    local headers = {
        ["Accept"] = "application/json",
        ["Content-Type"] = "application/json",
    }
    if AroynWeb.ValidKey(AroynWeb.key) then
        headers["Authorization"] = "Bearer " .. AroynWeb.NormalizeKey(AroynWeb.key)
    end
    if type(AroynWeb.presenceToken) == "string" and AroynWeb.presenceToken ~= "" then
        headers["X-Presence-Token"] = AroynWeb.presenceToken
    end
    local ok = pcall(fn, {
        Url = AroynWeb.liveHttpBase .. "/runtime-presence/disconnect",
        Method = "POST",
        Headers = headers,
        Body = body,
    })
    return ok
end

function AroynWeb.Stop(stopPresence)
    AroynWeb.DisconnectLive()
    if type(AroynWeb.ResolveRequest()) == "function" and AroynWeb.ValidKey(AroynWeb.key) then
        pcall(function() AroynWeb.Request("/api/v2/runtime/disconnect", "POST", { sessionId = AroynWeb.sessionId, robloxUserId = LocalPlayer and LocalPlayer.UserId or nil }) end)
    end
    if stopPresence == true then
        pcall(AroynWeb.DisconnectPresence)
        if AroynWeb.presenceThread and type(task.cancel) == "function" then pcall(task.cancel, AroynWeb.presenceThread) end
        AroynWeb.presenceThread = nil
        if AroynWeb.updateThread and type(task.cancel) == "function" then pcall(task.cancel, AroynWeb.updateThread) end
        AroynWeb.updateThread = nil
    end
    if AroynWeb.thread and type(task.cancel) == "function" then pcall(task.cancel, AroynWeb.thread) end
    AroynWeb.thread = nil
end

function AroynWeb.Start()
    AroynWeb.StartUpdateWatch()
    if AroynWeb.thread then return true end
    AroynWeb.LoadConfig()
    if not AroynWeb.ValidKey(AroynWeb.key) then
        AroynWeb.StartPresence()
        AroynWeb.lastPushOk = false
        AroynWeb.lastError = nil
        return false, "Dashboard not linked"
    end
    if type(AroynWeb.ResolveRequest()) ~= "function" then
        AroynWeb.lastPushOk = false
        AroynWeb.lastError = "Executor request API unavailable"
        addActivity("Web dashboard unavailable: executor has no request API", "warning")
        return false, AroynWeb.lastError
    end
    local verified, userOrError = AroynWeb.VerifyKey(AroynWeb.key)
    if not verified then
        AroynWeb.StartPresence()
        AroynWeb.lastPushOk = false
        AroynWeb.lastError = tostring(userOrError)
        addActivity("Saved dashboard key is invalid or expired", "warning")
        return false, AroynWeb.lastError
    end
    AroynWeb.account = userOrError
    if not verificationOnly then AroynWeb.SaveConfig() end
    local displayName = tostring(userOrError.displayName or userOrError.username or "Aroyn account")
    addActivity("Web dashboard linked · " .. displayName, "success")
    local generation = state.generation
    AroynWeb.thread = task.spawn(function()
        while state.running and state.generation == generation and AroynWeb.ValidKey(AroynWeb.key) do
            local ok, err = pcall(AroynWeb.PushOnce)
            if not ok then AroynWeb.lastPushOk = false; AroynWeb.lastError = tostring(err) end
            -- Include fragment cost in the live cadence; HTTP persistence and
            -- presence checkpoints remain unchanged.
            task.wait(AroynWeb.liveNextPushDelaySeconds or AroynWeb.pushIntervalSeconds or 5)
        end
        AroynWeb.thread = nil
    end)
    return true
end

function AroynWeb.LinkKey(rawKey)
    local candidate = AroynWeb.NormalizeKey(rawKey)
    local verified, userOrError, normalized = AroynWeb.VerifyKey(candidate)
    if not verified then return false, tostring(userOrError) end
    local relinked, relinkError = AroynWeb.RelinkRobloxAccount(normalized)
    if not relinked then return false, tostring(relinkError) end
    if AroynWeb.ValidKey(AroynWeb.key) and AroynWeb.key ~= normalized then AroynWeb.Stop() end
    AroynWeb.key = normalized
    AroynWeb.account = userOrError
    env[Options.BuildInfo.RuntimeId.."_DASHBOARD_KEY"] = normalized
    AroynWeb.SaveConfig()
    AroynWeb.lastError = nil
    AroynWeb.lastHttpPushClock = 0
    AroynWeb.lastHttpAttemptClock = nil
    AroynWeb.Start()
    return true, userOrError
end

function AroynWeb.Unlink()
    AroynWeb.Stop()
    AroynWeb.key = nil
    AroynWeb.account = nil
    env[Options.BuildInfo.RuntimeId.."_DASHBOARD_KEY"] = nil
    AroynWeb.lastPushOk = false
    AroynWeb.lastError = nil
    AroynWeb.SaveConfig()
    return true
end

function AroynWeb.CopyKey()
    if not AroynWeb.ValidKey(AroynWeb.key) then return false, "Dashboard not linked" end
    local fn = type(setclipboard) == "function" and setclipboard or (type(toclipboard) == "function" and toclipboard or nil)
    if type(fn) ~= "function" then return false, "Clipboard unavailable" end
    return pcall(fn, AroynWeb.key)
end

local function pendingSeedConfirmationCount()
    local count = 0
    for _, queue in pairs(pendingSeedConfirmations) do
        count += #queue
    end
    return count
end

local function createPendingSeedConfirmation(key)
    if not seedByKey[key] then
        return
    end
    local queue = pendingSeedConfirmations[key]
    if not queue then
        queue = {}
        pendingSeedConfirmations[key] = queue
    end
    queue[#queue + 1] = {
        key = key,
        createdClock = os.clock(),
        triggeredAt = os.time(),
        cost = seedByKey[key].plantCost or 0,
    }
    if ui.RefreshDiagnostics then
        ui.RefreshDiagnostics()
    end
end

local function confirmSeedPurchase(key)
    local queue = pendingSeedConfirmations[key]
    if not queue or #queue == 0 then
        return false
    end

    local pending = table.remove(queue, 1)
    if #queue == 0 then
        pendingSeedConfirmations[key] = nil
    end

    local stat = getPerSeedStat(key)
    stat.confirmedCount += 1
    stat.lastConfirmedAt = os.time()
    stat.sessionSpendConfirmed += pending.cost or 0

    state.confirmedSeedPurchases += 1
    state.confirmedSeedSpend += pending.cost or 0

    local record = seedByKey[key]
    addActivity((record and record.displaySeedName or key) .. " purchase confirmed", "success")

    if ui.RefreshSeedStats then
        ui.RefreshSeedStats(key)
    end
    if ui.RefreshSession then
        ui.RefreshSession()
    end
    if ui.RefreshDiagnostics then
        ui.RefreshDiagnostics()
    end
    if ui.FlashSeedConfirmed then
        ui.FlashSeedConfirmed(key)
    end
    return true
end

local function expirePendingSeedConfirmations()
    local now = os.clock()
    for key, queue in pairs(pendingSeedConfirmations) do
        local i = 1
        while i <= #queue do
            local pending = queue[i]
            if now - pending.createdClock >= SEED_CONFIRM_TIMEOUT then
                table.remove(queue, i)
                local record = seedByKey[key]
                addActivity((record and record.displaySeedName or key) .. " confirmation timed out", "warning")
            else
                i += 1
            end
        end
        if #queue == 0 then
            pendingSeedConfirmations[key] = nil
        end
    end
end

local function recordCash(value)
    if type(value) ~= "number" then
        return
    end
    local previous = GameState.cash
    if previous == nil then
        GameState.startingCash = value
    elseif value ~= previous then
        local delta = value - previous
        if delta > 0 then
            GameState.totalPositiveCashDelta += delta
        elseif delta < 0 then
            GameState.totalNegativeCashDelta += -delta
        end
        if math.abs(delta) > 0 then
            addActivity(string.format("Cash %s$%s", delta > 0 and "+" or "-", formatNumber(math.abs(delta))), "normal")
        end
    end
    GameState.cash = value
    GameState.lastCashAt = os.time()

    -- If Affordable Only was restored from settings before the first live cash
    -- value arrived, existing holders may have been classified as cash-unknown.
    -- That classification is informational only, but clear it when cash becomes
    -- authoritative so the next scan starts from a clean affordability state.
    if previous == nil then
        skippedReasons = setmetatable({}, { __mode = "k" })
    end

    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshSession then ui.RefreshSession() end
    if ui.UpdatePipeline then ui.UpdatePipeline() end

    if state.autoBuyEnabled and scanExistingHolders then
        scanExistingHolders()
    end
end

-- Affordable Only can be restored from settings before DataService.DataUpdate has
-- emitted any Currency.COINS event in the current client. In that state
-- GameState.cash is nil and every holder is correctly rejected as cash-unknown,
-- but nothing necessarily causes a future rescan until cash changes. Hydrate the
-- current authoritative client snapshot up front and retry briefly if Knit/DataClient
-- is not ready yet.
local cashHydrationRevision = 0

local function hydrateInitialCashSnapshot(allowRetry)
    if GameState.cash ~= nil then
        return true, "already-known"
    end

    local callOk, readyOrErr, detail = pcall(function()
        local Knit = require(ReplicatedStorage.Packages.Knit)
        local dataClient = Knit.GetController("DataClient")
        local data = dataClient and dataClient.currentData
        local currency = data and data.Currency
        local coins = currency and currency.COINS

        if type(coins) ~= "number" then
            return false, "DataClient.currentData.Currency.COINS unavailable"
        end

        recordCash(coins)
        return true, "DataClient.currentData"
    end)

    if callOk and readyOrErr == true then
        return true, detail
    end

    local reason = callOk and tostring(detail or "cash snapshot unavailable") or tostring(readyOrErr)

    if allowRetry then
        cashHydrationRevision += 1
        local revision = cashHydrationRevision
        local generation = state.generation
        local retryDelays = { 0.08, 0.16, 0.30, 0.50, 0.80, 1.20 }

        task.spawn(function()
            for _, delaySeconds in ipairs(retryDelays) do
                task.wait(delaySeconds)

                if not state.running
                    or state.generation ~= generation
                    or cashHydrationRevision ~= revision
                    or GameState.cash ~= nil then
                    return
                end

                local ready = hydrateInitialCashSnapshot(false)
                if ready then
                    -- recordCash() performs the rescan when Auto Buy is enabled.
                    return
                end
            end

            if state.running
                and state.generation == generation
                and cashHydrationRevision == revision
                and state.autoBuyEnabled
                and state.affordableOnly
                and GameState.cash == nil then
                state.lastAutoBuyError = "Initial cash snapshot unavailable"
                if ui.SetStatus then ui.SetStatus("Waiting for cash data", "warning") end
                if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
                if ui.UpdatePipeline then ui.UpdatePipeline() end
            end
        end)
    end

    return false, reason
end

local function registerFruitInventoryAdd(item, quantity)
    quantity = math.max(0, math.floor(tonumber(quantity) or 0))
    if quantity <= 0 or type(item) ~= "table" or item.itemType ~= "Fruit" then
        return
    end
    recentFruitInventoryAdds[#recentFruitInventoryAdds + 1] = {
        createdClock = os.clock(),
        seedType = item.seedType,
        fruitName = item.fruitName,
        sellValue = tonumber(item.sellValue) or 0,
        multiplier = tonumber(item.multiplier) or 0,
        mutations = deepCopy(item.mutations),
        quantity = quantity,
    }
end

local function applyConfirmedFruitValue(add)
    if not add or (add.quantity or 0) <= 0 then
        return false
    end
    add.quantity -= 1
    state.confirmedFruitValue += add.sellValue or 0
    state.fruitValueSamples += 1
    state.fruitMultiplierSum += add.multiplier or 0
    state.highestFruitValue = math.max(state.highestFruitValue, add.sellValue or 0)
    state.highestFruitMultiplier = math.max(state.highestFruitMultiplier, add.multiplier or 0)
    if ui.RefreshSession then ui.RefreshSession() end
    return true
end

local function matchFruitInventoryAndCollection()
    local now = os.clock()
    local eventIndex = 1
    while eventIndex <= #recentFruitCollectedEvents do
        local event = recentFruitCollectedEvents[eventIndex]
        if now - event.createdClock > 3 then
            table.remove(recentFruitCollectedEvents, eventIndex)
        else
            local matched = false
            for addIndex, add in ipairs(recentFruitInventoryAdds) do
                local age = math.abs(add.createdClock - event.createdClock)
                local seedMatches = not event.seedType or not add.seedType or event.seedType == add.seedType
                if age <= 2.5 and seedMatches and (add.quantity or 0) > 0 then
                    applyConfirmedFruitValue(add)
                    table.remove(recentFruitCollectedEvents, eventIndex)
                    if add.quantity <= 0 then
                        table.remove(recentFruitInventoryAdds, addIndex)
                    end
                    matched = true
                    break
                end
            end
            if not matched then
                eventIndex += 1
            end
        end
    end

    local i = 1
    while i <= #recentFruitInventoryAdds do
        local add = recentFruitInventoryAdds[i]
        if add.quantity <= 0 or now - add.createdClock > 4 then
            table.remove(recentFruitInventoryAdds, i)
        else
            i += 1
        end
    end
end

local function itemPositiveFruitDelta(oldItem, newItem)
    if type(newItem) ~= "table" or newItem.itemType ~= "Fruit" then
        return nil, 0
    end
    local newCount = math.max(0, tonumber(newItem.count) or 1)
    if type(oldItem) == "table" and oldItem.itemType == "Fruit" and oldItem.id == newItem.id then
        local oldCount = math.max(0, tonumber(oldItem.count) or 1)
        return newItem, math.max(0, newCount - oldCount)
    end
    return newItem, newCount
end

local function confirmSeedDeltaForSlot(oldItem, newItem)
    local keys = {}
    if type(oldItem) == "table" and oldItem.itemType == "Seed" and type(oldItem.seedType) == "string" then
        keys[oldItem.seedType] = true
    end
    if type(newItem) == "table" and newItem.itemType == "Seed" and type(newItem.seedType) == "string" then
        keys[newItem.seedType] = true
    end
    for key in pairs(keys) do
        local oldCount = itemSeedCount(oldItem, key)
        local newCount = itemSeedCount(newItem, key)
        local delta = math.floor(newCount - oldCount)
        for _ = 1, math.max(0, delta) do
            if not confirmSeedPurchase(key) then
                break
            end
        end
    end
end

local function normalizeHotbarSnapshot(raw)
    local result = {}
    local maxSlot = 0
    if type(raw) == "table" then
        for key, item in pairs(raw) do
            local slot = normalizeSlotKey(key)
            result[slot] = deepCopy(item)
            if type(slot) == "number" then
                maxSlot = math.max(maxSlot, slot)
            end
        end
    end
    return result, maxSlot > 0 and maxSlot or nil
end

local function applyHotbarUpdate(payload, path)
    local inventory = GameState.inventory
    local pathLength = #path

    if pathLength == 2 then
        local raw = getPayloadAtPath(payload, path)
        if type(raw) ~= "table" then
            return
        end

        local oldHotbar = inventory.hotbar
        local oldKnown = inventory.hotbarSnapshotKnown
        local newHotbar, capacity = normalizeHotbarSnapshot(raw)
        inventory.hotbar = newHotbar
        inventory.hotbarCapacity = capacity or inventory.hotbarCapacity

        if oldKnown then
            local keys = {}
            local oldTotals = allSeedTotals(oldHotbar)
            local newTotals = allSeedTotals(newHotbar)
            for key in pairs(oldTotals) do keys[key] = true end
            for key in pairs(newTotals) do keys[key] = true end
            for key in pairs(keys) do
                local delta = math.floor((newTotals[key] or 0) - (oldTotals[key] or 0))
                for _ = 1, math.max(0, delta) do
                    if not confirmSeedPurchase(key) then break end
                end
            end

            for slot, newItem in pairs(newHotbar) do
                local fruitItem, delta = itemPositiveFruitDelta(oldHotbar[slot], newItem)
                if delta > 0 then registerFruitInventoryAdd(fruitItem, delta) end
            end
        end

        inventory.knownHotbarSlots = {}
        for slot in pairs(newHotbar) do
            inventory.knownHotbarSlots[slot] = true
        end
        inventory.hotbarSnapshotKnown = true
        return
    end

    local slot = normalizeSlotKey(path[3])
    local oldItem = inventory.hotbar[slot]
    local wasKnown = inventory.knownHotbarSlots[slot] == true
    local incoming = getPayloadAtPath(payload, { path[1], path[2], path[3] })

    if #path == 3 then
        inventory.hotbar[slot] = deepCopy(incoming)
    else
        local base = type(oldItem) == "table" and deepCopy(oldItem) or {}
        local cursor = base
        for i = 4, #path - 1 do
            local key = path[i]
            local nextValue = tableValueFlexible(cursor, key)
            if type(nextValue) ~= "table" then
                nextValue = {}
                cursor[key] = nextValue
            end
            cursor = nextValue
        end
        cursor[path[#path]] = deepCopy(getPayloadAtPath(payload, path))
        inventory.hotbar[slot] = base
    end

    inventory.knownHotbarSlots[slot] = true
    if type(slot) == "number" then
        inventory.hotbarCapacity = math.max(inventory.hotbarCapacity or 0, slot)
    end

    local newItem = inventory.hotbar[slot]
    if wasKnown then
        confirmSeedDeltaForSlot(oldItem, newItem)
        local fruitItem, delta = itemPositiveFruitDelta(oldItem, newItem)
        if delta > 0 then registerFruitInventoryAdd(fruitItem, delta) end
    end
end

local function applyStorageUpdate(payload, path)
    local raw = getPayloadAtPath(payload, path)
    if #path == 2 then
        GameState.inventory.storage = type(raw) == "table" and deepCopy(raw) or {}
        return
    end

    local storage = GameState.inventory.storage
    local cursor = storage
    for i = 3, #path - 1 do
        local key = path[i]
        local nextValue = tableValueFlexible(cursor, key)
        if type(nextValue) ~= "table" then
            nextValue = {}
            cursor[key] = nextValue
        end
        cursor = nextValue
    end
    cursor[path[#path]] = deepCopy(raw)
end

local function pathToText(path)
    if type(path) ~= "table" then
        return "(invalid)"
    end
    local parts = {}
    for i = 1, #path do
        parts[#parts + 1] = tostring(path[i])
    end
    return table.concat(parts, ".")
end

local function applyDataUpdate(payload, path)
    if type(payload) ~= "table" or type(path) ~= "table" or #path == 0 then
        return
    end

    GameState.lastDataUpdatePath = pathToText(path)

    if path[1] == "Currency" and path[2] == "COINS" then
        recordCash(getPayloadAtPath(payload, path))
    elseif path[1] == "Inventory" and path[2] == "Hotbar" then
        applyHotbarUpdate(payload, path)
        matchFruitInventoryAndCollection()
        if ui.RefreshInventory then ui.RefreshInventory() end
        if ui.RefreshSession then ui.RefreshSession() end
        if ui.RefreshCompost then ui.RefreshCompost() end
        if ui.RefreshMarket then ui.RefreshMarket() end
        if ui.UpdatePipeline then ui.UpdatePipeline() end
    elseif path[1] == "Inventory" and path[2] == "Storage" then
        applyStorageUpdate(payload, path)
        if ui.RefreshInventory then ui.RefreshInventory() end
        if ui.RefreshCompost then ui.RefreshCompost() end
        if ui.UpdatePipeline then ui.UpdatePipeline() end
    elseif path[1] == "Worms" or path[1] == "UsedCompost" then
        if ui.RefreshCompost then ui.RefreshCompost() end
    end

    if ui.RefreshDiagnostics then
        ui.RefreshDiagnostics()
    end
end


local function clearPending(holder)
    local pending = pendingHolders[holder]
    if pending then
        safeDisconnect(pending.childAdded)
        pendingHolders[holder] = nil
    end
end

local function markUnknown(holder)
    if unknownCounted[holder] then
        return
    end
    unknownCounted[holder] = true
    state.unknown += 1
    addActivity("Unknown SeedHolder ignored", "warning")

    if state.diagnosticsEnabled then
        addActivity("Unknown children: " .. getDirectChildSummary(holder), "diagnostic")
    end

    if ui.UpdateStats then
        ui.UpdateStats()
    end
end

local function markSkipped(holder, key, reason, message)
    local existing = skippedReasons[holder]
    if existing == reason then
        return
    end
    skippedReasons[holder] = reason
    state.skipped += 1

    local record = seedByKey[key]
    addActivity((record and record.displaySeedName or key) .. " skipped — " .. message, "warning")

    if ui.UpdateStats then
        ui.UpdateStats()
    end
end

local function ensureRetry(holder)
    if not state.running or not holder or holder.Parent ~= currentConveyor then
        return
    end

    if triggeredHolders[holder] or queuedHolders[holder] then
        clearPending(holder)
        return
    end

    local pending = pendingHolders[holder]
    if pending then
        return
    end

    pending = {
        attempt = 0,
        generation = state.generation,
        childAdded = nil,
    }
    pendingHolders[holder] = pending

    pending.childAdded = holder.ChildAdded:Connect(function()
        if state.running
            and state.generation == pending.generation
            and pendingHolders[holder] == pending
            and holder.Parent == currentConveyor then

            task.defer(function()
                if state.running
                    and state.generation == pending.generation
                    and pendingHolders[holder] == pending
                    and holder.Parent == currentConveyor then
                    processSeedHolder(holder, true)
                end
            end)
        end
    end)

    local function step()
        if not state.running
            or state.generation ~= pending.generation
            or pendingHolders[holder] ~= pending then
            clearPending(holder)
            return
        end

        if holder.Parent ~= currentConveyor then
            clearPending(holder)
            return
        end

        if triggeredHolders[holder] or queuedHolders[holder] then
            clearPending(holder)
            return
        end

        pending.attempt += 1
        processSeedHolder(holder, true)

        if pendingHolders[holder] ~= pending then
            return
        end

        if pending.attempt >= #RETRY_DELAYS then
            clearPending(holder)
            local key = resolveSeedType(holder)
            if not key then
                markUnknown(holder)
            end
            return
        end

        task.delay(RETRY_DELAYS[pending.attempt + 1], step)
    end

    task.delay(RETRY_DELAYS[1], step)
end

local function queueSort(a, b)
    local pa = priorityOf(a.key)
    local pb = priorityOf(b.key)
    if pa ~= pb then
        return pa < pb
    end

    local oa = seedOrderIndex[a.key] or math.huge
    local ob = seedOrderIndex[b.key] or math.huge
    if oa ~= ob then
        return oa < ob
    end

    return a.sequence < b.sequence
end

resortQueue = function()
    table.sort(triggerQueue, queueSort)
end

local function invalidateQueue()
    queueRevision += 1
    queueWorkerScheduled = false

    for _, entry in ipairs(triggerQueue) do
        if entry.holder then
            queuedHolders[entry.holder] = nil
        end
    end

    table.clear(triggerQueue)
end

local function eligibility(holder, key)
    if not state.running then
        return false, "stopped"
    end

    if not currentConveyor or holder.Parent ~= currentConveyor then
        return false, "gone"
    end

    if holder.Name ~= "SeedHolder" then
        return false, "not-holder"
    end

    if triggeredHolders[holder] then
        return false, "triggered"
    end

    if not state.autoBuyEnabled then
        return false, "disabled"
    end

    if state.selectedSeeds[key] ~= true then
        return false, "deselected"
    end

    local record = seedByKey[key]
    if not record then
        return false, "unknown-key"
    end

    if state.maxPrice ~= nil and record.plantCost > state.maxPrice then
        return false, "price"
    end

    if state.affordableOnly then
        if GameState.cash == nil then
            return false, "cash-unknown"
        end
        if GameState.cash < (record.plantCost + math.max(0, state.cashReserve or 0)) then
            return false, "cash"
        end
    end

    if state.stopAfter ~= nil and state.successfulTriggers >= state.stopAfter then
        return false, "limit"
    end

    return true
end

local function setStatus(message, tone)
    if ui.SetStatus then
        ui.SetStatus(message, tone)
    end
end

local function invokeEntry(entry)
    local holder = entry.holder
    local key = entry.key

    queuedHolders[holder] = nil

    local eligible, reason = eligibility(holder, key)
    if not eligible then
        if reason == "price" then
            markSkipped(holder, key, "price", "price limit")
        elseif reason == "cash-unknown" then
            markSkipped(holder, key, "cash-unknown", "waiting for cash data")
        elseif reason == "cash" then
            markSkipped(holder, key, "cash", "cash reserve / affordability")
        elseif reason == "limit" and state.autoBuyEnabled then
            setAutoBuy(false, "Trigger limit reached")
        end
        return false, false
    end

    local prompt = entry.prompt
    if not prompt or not prompt.Parent or not prompt:IsDescendantOf(holder) then
        processSeedHolder(holder, true)
        return false, false
    end

    local firePrompt = fireproximityprompt
    if type(firePrompt) ~= "function" then
        if not unavailablePromptCounted[holder] then
            unavailablePromptCounted[holder] = true
            state.errors += 1
            addActivity("Prompt activation unavailable", "error")
            setStatus("fireproximityprompt unavailable", "bad")
            if ui.UpdateStats then
                ui.UpdateStats()
            end
        end
        return false, false
    end

    -- Final race check and physical-holder claim happen immediately before invocation.
    -- Luau callbacks are non-preemptive here: no yielding occurs between the check,
    -- claim, attempt increment, and pcall invocation.
    if triggeredHolders[holder] then
        return false, false
    end

    -- A leaf may have appeared after the queue worker acquired the Buy slot but
    -- before it reached this exact prompt. Never let Auto Buy equip a seed over
    -- the Rake while leaf collection is active/pending.
    if (FarmRuntime.LeafRuntime and FarmRuntime.LeafRuntime.buyPaused)
        or (FarmRuntime.hasPendingLeafWork and FarmRuntime.hasPendingLeafWork()) then
        processSeedHolder(holder, true)
        return false, false
    end

    triggeredHolders[holder] = true
    clearPending(holder)

    local record = seedByKey[key]
    local displayName = record and record.displaySeedName or key

    -- Trigger Attempt means fireproximityprompt is actually being invoked.
    state.attempts += 1

    local ok, err = pcall(firePrompt, prompt)

    if ok then
        -- Triggered semantics remain exactly V2: only a non-throwing executor invocation counts.
        local seedStat = getPerSeedStat(key)
        seedStat.triggerCount += 1
        seedStat.lastTriggeredAt = os.time()
        if ui.RefreshSeedStats then
            ui.RefreshSeedStats(key)
        end

        state.successfulTriggers += 1
        state.lastTriggeredKey = key
        createPendingSeedConfirmation(key)

        addActivity(displayName .. " triggered", "success")
        setStatus(displayName .. " triggered", "accent")

        if ui.UpdateStats then
            ui.UpdateStats()
        end
        if ui.UpdateHeader then
            ui.UpdateHeader()
        end

        if state.oneShot then
            setAutoBuy(false, "One Shot complete")
        elseif state.stopAfter ~= nil and state.successfulTriggers >= state.stopAfter then
            setAutoBuy(false, "Trigger limit reached")
        end

        return true, true
    end

    state.errors += 1
    state.lastAutoBuyError = tostring(err)
    local seedStat = getPerSeedStat(key)
    seedStat.triggerErrors += 1
    addActivity(displayName .. " trigger failed", "error")
    setStatus(displayName .. " trigger error: " .. tostring(err), "bad")
    if ui.RefreshSeedStats then
        ui.RefreshSeedStats(key)
    end

    if ui.UpdateStats then
        ui.UpdateStats()
    end
    if ui.UpdateHeader then
        ui.UpdateHeader()
    end

    return true, false
end

local function queueWorkerStep(revision, generation)
    queueWorkerScheduled = false

    if not state.running
        or state.generation ~= generation
        or queueRevision ~= revision
        or not state.autoBuyEnabled then
        return
    end

    local acquired = FarmRuntime.acquireAutomation("buy")
    if not acquired then
        queueWorkerScheduled = true
        task.delay(0.08, function()
            if state.running
                and state.generation == generation
                and queueRevision == revision
                and state.autoBuyEnabled then
                queueWorkerStep(revision, generation)
            end
        end)
        return
    end

    resortQueue()

    local entry = table.remove(triggerQueue, 1)
    if not entry then
        FarmRuntime.releaseAutomation("buy")
        return
    end

    local invoked = false
    local ok, resultInvoked = pcall(function()
        local didInvoke = invokeEntry(entry)
        return didInvoke
    end)

    if ok then
        invoked = resultInvoked == true
    else
        queuedHolders[entry.holder] = nil
        warn("[Seed Auto Buy V2] Queue worker error:", resultInvoked)
        addActivity("Internal queue error", "error")
        setStatus("Internal queue error: " .. tostring(resultInvoked), "bad")
    end

    FarmRuntime.releaseAutomation("buy")

    if not state.running
        or state.generation ~= generation
        or queueRevision ~= revision
        or not state.autoBuyEnabled then
        return
    end

    if #triggerQueue > 0 then
        local delaySeconds = invoked and state.rateLimit or 0
        queueWorkerScheduled = true

        if delaySeconds > 0 then
            task.delay(delaySeconds, function()
                if state.running
                    and state.generation == generation
                    and queueRevision == revision then
                    queueWorkerStep(revision, generation)
                end
            end)
        else
            task.defer(function()
                if state.running
                    and state.generation == generation
                    and queueRevision == revision then
                    queueWorkerStep(revision, generation)
                end
            end)
        end
    end
end

scheduleQueueWorker = function()
    if queueWorkerScheduled or #triggerQueue == 0 or not state.autoBuyEnabled then
        return
    end

    queueWorkerScheduled = true
    local revision = queueRevision
    local generation = state.generation

    -- Give the current event burst a tiny non-blocking batching window so
    -- simultaneous holders can be ordered by priority deterministically.
    task.delay(0.02, function()
        if state.running
            and state.generation == generation
            and queueRevision == revision then
            queueWorkerStep(revision, generation)
        end
    end)
end

local function enqueueHolder(holder, key, prompt)
    if triggeredHolders[holder] or queuedHolders[holder] then
        return
    end

    local eligible, reason = eligibility(holder, key)
    if not eligible then
        if reason == "price" then
            markSkipped(holder, key, "price", "price limit")
        elseif reason == "cash-unknown" then
            markSkipped(holder, key, "cash-unknown", "waiting for cash data")
        elseif reason == "cash" then
            markSkipped(holder, key, "cash", "cash reserve / affordability")
        elseif reason == "limit" and state.autoBuyEnabled then
            setAutoBuy(false, "Trigger limit reached")
        end
        return
    end

    queuedHolders[holder] = true
    clearPending(holder)

    queueSequence += 1
    triggerQueue[#triggerQueue + 1] = {
        holder = holder,
        key = key,
        prompt = prompt,
        sequence = queueSequence,
    }

    resortQueue()
    scheduleQueueWorker()
end

processSeedHolder = function(holder, fromRetry)
    if not state.running or not currentConveyor then
        return
    end

    if typeof(holder) ~= "Instance" or holder.Name ~= "SeedHolder" then
        return
    end

    if holder.Parent ~= currentConveyor then
        clearPending(holder)
        queuedHolders[holder] = nil
        return
    end

    if triggeredHolders[holder] or queuedHolders[holder] then
        clearPending(holder)
        return
    end

    local ok, err = pcall(function()
        local key, confidence, reason = resolveSeedType(holder)
        if not key then
            ensureRetry(holder)
            return
        end

        state.lastSeenKey = key

        local record = seedByKey[key]
        local displayName = record and record.displaySeedName or key

        if ui.UpdateStats then
            ui.UpdateStats()
        end

        if state.diagnosticsEnabled and not diagnosticResolvedLogged[holder] then
            diagnosticResolvedLogged[holder] = true
            addActivity(string.format("%s · %s · %s", displayName, reason, confidence), "diagnostic")
        elseif not fromRetry and state.autoBuyEnabled and state.selectedSeeds[key] == true then
            addActivity(displayName .. " detected", "normal")
        end

        if not state.autoBuyEnabled or state.selectedSeeds[key] ~= true then
            clearPending(holder)
            return
        end

        if state.maxPrice ~= nil and record and record.plantCost > state.maxPrice then
            clearPending(holder)
            markSkipped(holder, key, "price", "price limit")
            return
        end

        local prompt = findPrompt(holder)
        if not prompt then
            ensureRetry(holder)
            return
        end

        enqueueHolder(holder, key, prompt)
    end)

    if not ok and state.running then
        warn("[Seed Auto Buy V2] SeedHolder processing error:", err)
    end
end

scanExistingHolders = function()
    if not state.running or not currentConveyor then
        return
    end

    for _, child in ipairs(currentConveyor:GetChildren()) do
        if child.Name == "SeedHolder" then
            task.defer(processSeedHolder, child, false)
        end
    end
end

local function attachConveyor(conveyor)
    if not state.running or not conveyor then
        return
    end

    safeDisconnect(conveyorConnection)
    conveyorConnection = nil

    invalidateQueue()
    currentConveyor = conveyor

    conveyorConnection = conveyor.ChildAdded:Connect(function(child)
        if state.running and currentConveyor == conveyor and child.Name == "SeedHolder" then
            task.defer(processSeedHolder, child, false)
        end
    end)

    -- Listener first, scan second: no initialization gap.
    scanExistingHolders()
end

local function updateAllSeedRows()
    if not ui.RefreshSeedRow then
        return
    end
    for _, record in ipairs(seedRecords) do
        ui.RefreshSeedRow(record.key)
    end
end

local function setSeedSelected(key, value, skipRescan)
    if not seedByKey[key] then
        return
    end

    state.selectedSeeds[key] = value == true or nil

    if value ~= true and state.priorities[key] then
        state.priorities[key] = nil
        normalizePriorities()
        if ui.RefreshPriorityRows then
            ui.RefreshPriorityRows()
        end
    end

    if ui.RefreshSeedRow then
        ui.RefreshSeedRow(key)
    end
    if ui.UpdateSelection then
        ui.UpdateSelection()
    end

    scheduleSettingsSave()

    if state.running and state.autoBuyEnabled and not skipRescan then
        if value == true then
            scanExistingHolders()
        else
            -- Queued entries are intentionally not fired after deselection.
            -- The worker revalidates selection before invocation.
        end
    end
end

local function setSeedsByRarity(targetRarity, includeRarer)
    local startIndex = rarityIndex[targetRarity]
    if not startIndex then
        return
    end

    for _, record in ipairs(seedRecords) do
        local index = rarityIndex[record.rarity]
        local match = includeRarer and index and index >= startIndex or record.rarity == targetRarity
        if match then
            state.selectedSeeds[record.key] = true
        end
    end

    updateAllSeedRows()

    if ui.UpdateSelection then
        ui.UpdateSelection()
    end

    scheduleSettingsSave()

    if state.autoBuyEnabled then
        scanExistingHolders()
    end
end

local function clearSeedSelection()
    table.clear(state.selectedSeeds)
    table.clear(state.priorities)
    updateAllSeedRows()
    if ui.UpdateSelection then
        ui.UpdateSelection()
    end
    if ui.RefreshPriorityRows then
        ui.RefreshPriorityRows()
    end
    resortQueue()
    scheduleSettingsSave()
end

local function selectAllSeeds()
    for _, record in ipairs(seedRecords) do
        state.selectedSeeds[record.key] = true
    end
    updateAllSeedRows()
    if ui.UpdateSelection then
        ui.UpdateSelection()
    end
    scheduleSettingsSave()

    if state.autoBuyEnabled then
        scanExistingHolders()
    end
end

local function updateAllCompostSeedRows()
    if not ui.RefreshCompostSeedRow then
        return
    end
    for _, record in ipairs(seedRecords) do
        ui.RefreshCompostSeedRow(record.key)
    end
end

local function setCompostSeedSelected(key, value)
    if not seedByKey[key] then
        return
    end

    state.selectedCompostSeeds[key] = value == true or nil

    if ui.RefreshCompostSeedRow then
        ui.RefreshCompostSeedRow(key)
    end
    if ui.UpdateCompostSelection then
        ui.UpdateCompostSelection()
    end
    if ui.RefreshCompost then
        ui.RefreshCompost()
    end

    scheduleSettingsSave()
end

local function clearCompostSeedSelection()
    table.clear(state.selectedCompostSeeds)
    updateAllCompostSeedRows()
    if ui.UpdateCompostSelection then
        ui.UpdateCompostSelection()
    end
    if ui.RefreshCompost then
        ui.RefreshCompost()
    end
    scheduleSettingsSave()
end

local function selectAllCompostSeeds()
    for _, record in ipairs(seedRecords) do
        state.selectedCompostSeeds[record.key] = true
    end
    updateAllCompostSeedRows()
    if ui.UpdateCompostSelection then
        ui.UpdateCompostSelection()
    end
    if ui.RefreshCompost then
        ui.RefreshCompost()
    end
    scheduleSettingsSave()
end

setAutoBuy = function(value, explicitStatus)
    local newValue = value == true

    if newValue
        and state.stopAfter ~= nil
        and state.successfulTriggers >= state.stopAfter then

        state.autoBuyEnabled = false
        invalidateQueue()

        if ui.UpdateAutoBuy then
            ui.UpdateAutoBuy()
        end
        if ui.UpdateHeader then
            ui.UpdateHeader()
        end

        setStatus("Trigger limit already reached — reset stats or change limit", "warning")
        return
    end

    if state.autoBuyEnabled == newValue then
        if explicitStatus then
            setStatus(explicitStatus, newValue and "good" or "neutral")
        end
        return
    end

    state.autoBuyEnabled = newValue

    if not newValue then
        invalidateQueue()
    elseif state.affordableOnly and GameState.cash == nil then
        -- Settings can restore Affordable Only before we have observed a cash
        -- DataUpdate. Seed the cash mirror from DataClient immediately; if that
        -- controller is still starting, a bounded retry will rescan once ready.
        hydrateInitialCashSnapshot(true)
    end

    if ui.UpdateAutoBuy then
        ui.UpdateAutoBuy()
    end
    if ui.UpdateHeader then
        ui.UpdateHeader()
    end

    if explicitStatus then
        setStatus(explicitStatus, newValue and "good" or "neutral")
    else
        setStatus(newValue and "Watching conveyor" or "Auto Buy disabled", newValue and "good" or "neutral")
    end

    scheduleSettingsSave()

    if newValue then
        scanExistingHolders()
    end
end

local function setMaxPrice(value)
    if value ~= nil then
        value = math.max(0, value)
    end

    state.maxPrice = value
    skippedReasons = setmetatable({}, { __mode = "k" })

    if ui.UpdateControlValues then
        ui.UpdateControlValues()
    end

    scheduleSettingsSave()

    if state.autoBuyEnabled then
        scanExistingHolders()
    end
end

local function setRateLimit(value)
    state.rateLimit = value
    if ui.UpdateControlValues then
        ui.UpdateControlValues()
    end
    scheduleSettingsSave()
end

local function setOneShot(value)
    state.oneShot = value == true
    if ui.UpdateControlValues then
        ui.UpdateControlValues()
    end
    scheduleSettingsSave()

    if state.autoBuyEnabled then
        resortQueue()
        scanExistingHolders()
    end
end

local function setStopAfter(value)
    if value ~= nil then
        value = math.max(1, math.floor(value))
    end

    state.stopAfter = value
    if ui.UpdateControlValues then
        ui.UpdateControlValues()
    end
    scheduleSettingsSave()

    if state.autoBuyEnabled then
        if state.stopAfter ~= nil and state.successfulTriggers >= state.stopAfter then
            setAutoBuy(false, "Trigger limit reached")
        else
            scanExistingHolders()
        end
    end
end



-- ============================================================
-- V3 farm monitor / observed RemoteEvent listeners / fruit collector
-- ============================================================

-- FarmRuntime was forward-declared above for AroynWeb telemetry.

local playerPlots = nil
local ownPlot = nil
local ownPlotConnections = {}
local plotCandidateConnections = setmetatable({}, { __mode = "k" })
local treeDataByInstance = setmetatable({}, { __mode = "k" })
local fruitDataByInstance = setmetatable({}, { __mode = "k" })
local selectedTreeId = nil

local claimedFruits = setmetatable({}, { __mode = "k" })
local queuedFruits = setmetatable({}, { __mode = "k" })
local collectQueue = {}
local collectSequence = 0
local collectRevision = 0
local collectWorkerScheduled = false
local COLLECT_RATE_LIMIT = 0.18
local pendingFruitTriggers = {}
local recentFruitConfirmationDedupe = {}

-- Pet drop collector ---------------------------------------------------
-- Pets periodically spawn PlotFind_<uuid> objects inside the player's own
-- plot. The collector never guesses/remotes the mechanic: it approaches the
-- replicated FindPrompt and uses one teleport with at most two prompt fires per target.
local PetSeedRuntime = {
    queued = setmetatable({}, { __mode = "k" }),
    claimed = setmetatable({}, { __mode = "k" }),
    retryAfter = setmetatable({}, { __mode = "k" }),
    queue = {},
    revision = 0,
    workerScheduled = false,
    activeTicket = nil,

    -- One teleport per collection attempt. The first fire gets a full
    -- confirmation window; only if the exact PlotFind still exists do we
    -- fire the SAME prompt a second time without teleporting again.
    secondConfirmTimeout = 1.50,
    retryCooldown = 5.00,
}

local PET_SEED_RATE_LIMIT = 0.30
local PET_SEED_CONFIRM_TIMEOUT = 1.00
local PET_SEED_TELEPORT_SETTLE = 0.30

local remoteCache = {}


local CompostRuntime = {
    Knit = nil,
    DataClient = nil,
    ToolService = nil,
    PlayerPlotService = nil,
    WormService = nil,

    selectedItemId = nil,
    selectedItemUnsubscribe = nil,
    connections = {},

    bin = nil,
    model = nil,
    compostPart = nil,
    promptPart = nil,
    prompt = nil,
    amountLabel = nil,

    workerRevision = 0,
    workerScheduled = false,
    lastProgress = 0,
    lastCapacity = 100,
    lastPromptAction = "Give Seed",
    lastCollectRequestClock = nil,
    batchTeleportTicket = nil,
}

local COMPOST_CAPACITY = 100
local COMPOST_STEP_DELAY = 0.16
local COMPOST_CONFIRM_TIMEOUT = 2.5
local COMPOST_EQUIP_TIMEOUT = 1.25

-- Farmers Market ------------------------------------------------------
-- The server owns all validation. Aroyn only chooses a qualifying fruit from
-- the player's own plot / inventory, equips it, then invokes the same
-- FarmersMarketService RemoteFunctions used by the game UI.
FarmRuntime.MarketRuntime = {
    GetOffers = nil,
    GiveFruit = nil,
    ClaimRow = nil,

    offers = nil,
    lastRefreshClock = 0,
    workerRevision = 0,
    workerScheduled = false,
    activeTeleport = nil,
    candidateCooldown = setmetatable({}, { __mode = "k" }),
    confirmedFruitKeys = {},

    STEP_DELAY = 0.05,
    RETRY_DELAY = 1.25,
    CONFIRM_TIMEOUT = 1.25,
    EQUIP_TIMEOUT = 0.35,
    TELEPORT_SETTLE = 0.10,
    DIRECT_CONFIRM_TIMEOUT = 2.00,
    DIRECT_RETRY_TIMEOUT = 1.75,
    DIRECT_LATE_CONFIRM_GRACE = 1.00,
    FAILED_CANDIDATE_COOLDOWN = 8.00,

    ROW_BURST_COLLECT_STAGGER = 0.025,
    ROW_BURST_GIVE_STAGGER = 0.020,
    ROW_BURST_WAIT_TIMEOUT = 6.00,
}

-- Autumn event leaf collector -----------------------------------------
-- Uses the dynamically resolved ownPlot (OwnerUserId), never PlayerPlot1.
FarmRuntime.LeafRuntime = {
    queued = setmetatable({}, { __mode = "k" }),
    claimed = setmetatable({}, { __mode = "k" }),
    queue = {},
    revision = 0,
    workerScheduled = false,
    activeTicket = nil,
    buyPaused = false,
    RATE_LIMIT = 0.30,
    CONFIRM_TIMEOUT = 2.50,
    TELEPORT_SETTLE = 0.22,
    EQUIP_TIMEOUT = 1.00,
    RETRY_DELAY = 1.00,
}

-- Shared automation arbiter -------------------------------------------------
-- Only one of these automation families is allowed to perform an interaction
-- at a time. Priority is intentionally strict:
--   leaves > pet drops > compost > normal seed buying
-- This prevents teleports, held-tool changes and prompt activations from
-- fighting each other when several features become ready at once.
FarmRuntime.AutomationRuntime = {
    owner = nil,
    since = 0,
}

function FarmRuntime.hasPendingLeafWork()
    if not state.autoCollectLeaves then
        return false
    end

    if FarmRuntime.AutomationRuntime.owner == "leaf"
        or FarmRuntime.LeafRuntime.activeTicket ~= nil
        or FarmRuntime.LeafRuntime.workerScheduled
        or #FarmRuntime.LeafRuntime.queue > 0 then
        return true
    end

    -- Strict priority means "leaves first" is based on the actual plot,
    -- not only on the current queue. A LeafPile can briefly fall between
    -- queue/retry windows; Pet Drops must not steal that gap.
    if ownPlot and ownPlot.Parent then
        for _, child in ipairs(ownPlot:GetChildren()) do
            if FarmRuntime.isLeafPile(child) then
                return true
            end
        end
    end

    return false
end

function FarmRuntime.hasPendingPetSeedWork()
    return state.autoCollectPetSeeds
        and (
            FarmRuntime.AutomationRuntime.owner == "pet"
            or PetSeedRuntime.activeTicket ~= nil
            or PetSeedRuntime.workerScheduled
            or #PetSeedRuntime.queue > 0
        )
end

function FarmRuntime.hasImmediateCompostWork()
    if not state.autoCompostEnabled then return false end

    local prompt = CompostRuntime.prompt
    if not prompt or not prompt.Parent then return false end

    local enabledOk, enabled = pcall(function() return prompt.Enabled end)
    if enabledOk and enabled == false then return false end

    if tostring(prompt.ActionText or "") == "Collect" then
        return true
    end

    local ok, candidate = pcall(FarmRuntime.findSelectedCompostStack)
    return ok and candidate ~= nil
end

function FarmRuntime.automationBlockedByHigherPriority(kind)
    if kind ~= "leaf" and FarmRuntime.hasPendingLeafWork() then
        return true, "leaf"
    end

    if (kind == "compost" or kind == "buy") and FarmRuntime.hasPendingPetSeedWork() then
        return true, "pet"
    end

    if kind == "buy" and FarmRuntime.hasImmediateCompostWork() then
        return true, "compost"
    end

    return false, nil
end

function FarmRuntime.acquireAutomation(kind)
    local runtime = FarmRuntime.AutomationRuntime
    local now = os.clock()

    -- Safety valve: a worker should never hold this for anywhere near 10 sec.
    -- If an unexpected runtime error killed a worker, do not deadlock every
    -- other automation forever.
    if runtime.owner and now - (runtime.since or 0) > 10 then
        local operation = runtime.operation
        if operation then
            operation.cancelled = true
            FarmRuntime.cancelFeatureClaim(operation)
            runtime.operation = nil
            if operation.kind == "compost" then FarmRuntime.releaseCompostTeleport()
            elseif operation.kind == "pet" then FarmRuntime.finishPetSeedTeleport(PetSeedRuntime.activeTicket)
            elseif operation.kind == "leaf" then FarmRuntime.finishLeafTeleport(FarmRuntime.LeafRuntime.activeTicket)
            elseif operation.kind == "feed" then FarmRuntime.petFeedReleaseClaim(operation) end
        end
        if runtime.owner == "leaf" and FarmRuntime.LeafRuntime then
            FarmRuntime.LeafRuntime.buyPaused = false
        end
        runtime.owner = nil
        runtime.since = 0
    end

    if runtime.owner and runtime.owner ~= kind then
        return false, runtime.owner
    end

    local blocked, reason = FarmRuntime.automationBlockedByHigherPriority(kind)
    if blocked then
        return false, reason
    end

    runtime.owner = kind
    runtime.since = now
    return true
end

function FarmRuntime.releaseAutomation(kind)
    local runtime = FarmRuntime.AutomationRuntime

    if kind == "leaf" and FarmRuntime.LeafRuntime then
        FarmRuntime.LeafRuntime.buyPaused = false
    end

    if runtime.owner == kind then
        runtime.owner = nil
        runtime.since = 0
    end

    task.defer(function()
        if not state.running or FarmRuntime.AutomationRuntime.owner then return end

        if state.autoCollectLeaves and FarmRuntime.hasPendingLeafWork() then
            FarmRuntime.scanLeaves()
            FarmRuntime.scheduleLeafWorker()
            return
        end

        if state.autoCollectPetSeeds and #PetSeedRuntime.queue > 0 then
            FarmRuntime.schedulePetSeedWorker()
            return
        end

        if state.autoCompostEnabled and FarmRuntime.hasImmediateCompostWork() then
            FarmRuntime.scheduleCompostWorker()
            return
        end

        if state.autoBuyEnabled and #triggerQueue > 0 and scheduleQueueWorker then
            scheduleQueueWorker()
        end
    end)
end

function FarmRuntime.marketRequirementText(cell)
    if type(cell) ~= "table" then return "Unknown fruit" end
    local name = tostring(cell.fruitName or cell.seedType or "Fruit")
    local mutation = type(cell.mutation) == "string" and trim(cell.mutation) or ""
    local size = tonumber(cell.size) or 0

    if mutation ~= "" then
        name = mutation .. " " .. name
    end
    if size > 0 then
        name ..= " · " .. tostring(math.floor(size * 100 + 0.5) / 100) .. "+ size"
    end
    return name
end

function FarmRuntime.marketNormalizeFruitName(value)
    local name = tostring(value or ""):lower()
    name = name:gsub("[%s%p_]+", "")
    -- Some internal names/config fallbacks append "Fruit" while the Farmers
    -- Market response uses the short display name (e.g. Pear vs Pear Fruit).
    name = name:gsub("fruit$", "")
    return name
end

function FarmRuntime.marketItemSize(item)
    if type(item) ~= "table" then return 0 end
    return tonumber(
        item.multiplier
        or item.effectiveMultiplier
        or item.size
        or item.sizeMultiplier
        or item.sizeMult
    ) or 0
end

function FarmRuntime.marketHasMutation(mutations, required)
    if type(required) ~= "string" or trim(required) == "" then
        return true
    end
    for _, mutation in ipairs(FarmRuntime.parseFruitMutationList(mutations)) do
        if mutation == required then
            return true
        end
    end
    return false
end

function FarmRuntime.marketFruitMatches(item, cell)
    if type(item) ~= "table" or type(cell) ~= "table" then
        return false
    end

    local itemSeed = tostring(item.seedType or "")
    local requiredSeed = tostring(cell.seedType or "")

    local seedMatches = itemSeed ~= ""
        and requiredSeed ~= ""
        and itemSeed == requiredSeed

    local itemName = FarmRuntime.marketNormalizeFruitName(
        item.fruitName or FarmRuntime.fruitNameForSeed(item.seedType)
    )
    local requiredName = FarmRuntime.marketNormalizeFruitName(
        cell.fruitName or FarmRuntime.fruitNameForSeed(cell.seedType)
    )
    local nameMatches = itemName ~= ""
        and requiredName ~= ""
        and itemName == requiredName

    if not seedMatches and not nameMatches then
        return false
    end

    if not FarmRuntime.marketHasMutation(item.mutations, cell.mutation) then
        return false
    end

    local requiredSize = tonumber(cell.size) or 0
    if requiredSize > 0 then
        local itemSize = FarmRuntime.marketItemSize(item)
        if itemSize + 1e-6 < requiredSize then
            return false
        end
    end

    return true
end

function FarmRuntime.marketCandidateScore(item, cell)
    local mutations = FarmRuntime.parseFruitMutationList(item and item.mutations or nil)
    local requiredMutation = type(cell) == "table" and cell.mutation or nil
    local requiredSize = type(cell) == "table" and (tonumber(cell.size) or 0) or 0
    local itemSize = FarmRuntime.marketItemSize(item)
    local sellValue = tonumber(item and item.sellValue) or 0

    local extraMutationPenalty = #mutations
    if type(requiredMutation) == "string" and requiredMutation ~= "" then
        extraMutationPenalty = math.max(0, #mutations - 1)
    end

    local sizePenalty
    if requiredSize > 0 then
        sizePenalty = math.max(0, itemSize - requiredSize)
    else
        sizePenalty = itemSize
    end

    -- Prefer the least-special / least-valuable fruit that still satisfies
    -- the offer so Auto Market does not burn a better fruit unnecessarily.
    return extraMutationPenalty * 1e12 + sizePenalty * 1e7 + math.max(0, sellValue)
end

function FarmRuntime.findMarketInventoryFruit(cell, excludedIds)
    local data = FarmRuntime.getCurrentData()
    local inventory = data and data.Inventory
    if type(inventory) ~= "table" then return nil end

    local candidates = {}
    local function collect(container, hotbar)
        if type(container) ~= "table" then return end
        for slot, item in pairs(container) do
            if type(item) == "table"
                and item.itemType == "Fruit"
                and item.empty ~= true
                and item.favorited ~= true
                and item.id ~= nil
                and FarmRuntime.marketFruitMatches(item, cell) then

                local idKey = tostring(item.id)
                if not excludedIds or not excludedIds[idKey] then
                    candidates[#candidates + 1] = {
                        id = item.id,
                        item = item,
                        slot = tonumber(slot) or slot,
                        hotbar = hotbar,
                        score = FarmRuntime.marketCandidateScore(item, cell),
                    }
                end
            end
        end
    end

    collect(inventory.Hotbar, true)
    collect(inventory.Storage, false)

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        if a.hotbar ~= b.hotbar then return a.hotbar end
        return tostring(a.slot) < tostring(b.slot)
    end)

    return candidates[1]
end

function FarmRuntime.refreshMarketPlotRecords()
    if not ownPlot or not ownPlot.Parent then return end

    for _, child in ipairs(ownPlot:GetChildren()) do
        if child.Name:match("^PlotTree_") then
            FarmRuntime.attachTree(child)
            local treeData = treeDataByInstance[child]
            if treeData then
                for _, descendant in ipairs(child:GetDescendants()) do
                    if descendant:GetAttribute("SpawnIndex") ~= nil then
                        FarmRuntime.attachFruit(descendant, treeData)
                    elseif descendant:IsA("ProximityPrompt") then
                        local fruit = FarmRuntime.findFruitOwnerFromDescendant(descendant, child)
                        if fruit then
                            FarmRuntime.attachFruit(fruit, treeData)
                        end
                    end
                end
            end
        end
    end
end

function FarmRuntime.marketReleaseFromCollectQueue(fruit)
    if not fruit then return end

    for i = #collectQueue, 1, -1 do
        local entry = collectQueue[i]
        if entry and entry.fruit == fruit then
            table.remove(collectQueue, i)
        end
    end

    queuedFruits[fruit] = nil

    -- If the fruit still physically exists, a stale collector claim must not
    -- block Farmers Market from using it.
    if fruit.Parent then
        claimedFruits[fruit] = nil
    end
end

function FarmRuntime.findMarketPlotFruit(cell, excludedFruits)
    if not ownPlot or ownPlot ~= GameState.ownPlot or not ownPlot.Parent then
        return nil
    end

    FarmRuntime.refreshMarketPlotRecords()

    local candidates = {}
    for _, treeData in pairs(GameState.treesById) do
        if treeData.instance
            and treeData.instance.Parent
            and treeData.instance:IsDescendantOf(ownPlot) then

            for _, fruitData in pairs(treeData.fruits) do
                local fruit = fruitData.instance
                local cooldown = fruit and FarmRuntime.MarketRuntime.candidateCooldown[fruit]
                if cooldown and cooldown <= os.clock() then
                    FarmRuntime.MarketRuntime.candidateCooldown[fruit] = nil
                    cooldown = nil
                end

                if fruit
                    and fruit.Parent
                    and not cooldown
                    and (not excludedFruits or not excludedFruits[fruit])
                    and fruit:GetAttribute("FruitLocked") ~= true then

                    if claimedFruits[fruit] and not queuedFruits[fruit] then
                        local livePrompt = FarmRuntime.findFruitPrompt(fruit)
                        if livePrompt and livePrompt.Parent then
                            claimedFruits[fruit] = nil
                        end
                    end

                    local live = FarmRuntime.liveFruitDisplay(fruitData)
                    if live
                        and not claimedFruits[fruit]
                        and fruit:GetAttribute("FruitLocked") ~= true
                        and FarmRuntime.marketFruitMatches(live, cell) then

                        -- Do not require live.ready here. Fruit prompts can be
                        -- disabled while the player is far away. Market pickup
                        -- teleports to the fruit and force-enables the prompt,
                        -- exactly like TP Auto Collect.
                        FarmRuntime.marketReleaseFromCollectQueue(fruit)

                        candidates[#candidates + 1] = {
                            fruitData = fruitData,
                            fruit = fruit,
                            treeData = treeData,
                            live = live,
                            score = FarmRuntime.marketCandidateScore(live, cell),
                        }
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.score ~= b.score then return a.score < b.score end
        return tostring(a.treeData and a.treeData.id or "") < tostring(b.treeData and b.treeData.id or "")
    end)

    return candidates[1]
end

function FarmRuntime.setMarketStatus(value, isError)
    state.marketStatus = tostring(value or "Idle")
    if isError then
        state.lastMarketError = state.marketStatus
        state.marketErrors += 1
    else
        state.lastMarketError = nil
    end
    if ui.RefreshMarket then ui.RefreshMarket() end
    if ui.RefreshHeader then ui.RefreshHeader() end
end

function FarmRuntime.locateMarketRemotes()
    local packages = ReplicatedStorage:FindFirstChild("Packages")
    local index = packages and packages:FindFirstChild("_Index")
    local knitPackage = index and index:FindFirstChild("sleitnick_knit@1.6.0")
    local knitFolder = knitPackage and knitPackage:FindFirstChild("knit")
    local services = knitFolder and knitFolder:FindFirstChild("Services")
    local service = services and services:FindFirstChild("FarmersMarketService")
    local rf = service and service:FindFirstChild("RF")

    if not rf then
        local fallbackService = ReplicatedStorage:FindFirstChild("FarmersMarketService", true)
        rf = fallbackService and fallbackService:FindFirstChild("RF")
    end

    FarmRuntime.MarketRuntime.GetOffers = rf and rf:FindFirstChild("GetOffers") or nil
    FarmRuntime.MarketRuntime.GiveFruit = rf and rf:FindFirstChild("GiveFruit") or nil
    FarmRuntime.MarketRuntime.ClaimRow = rf and rf:FindFirstChild("ClaimRow") or nil

    return FarmRuntime.MarketRuntime.GetOffers ~= nil
        and FarmRuntime.MarketRuntime.GiveFruit ~= nil
        and FarmRuntime.MarketRuntime.ClaimRow ~= nil
end

-- Each Auto Market operation belongs to one enable cycle and client instance.
-- A sent server request cannot be undone; cancelled continuations send nothing new.
function FarmRuntime.marketOperationToken()
    return { generation = state.generation, revision = FarmRuntime.MarketRuntime.workerRevision }
end

function FarmRuntime.marketOperationCurrent(token)
    return state.running and not state.stopping
        and (token == nil or (not token.cancelled and state.autoMarketEnabled
            and state.generation == token.generation
            and FarmRuntime.MarketRuntime.workerRevision == token.revision))
end

function FarmRuntime.refreshMarketOffers(silent, token)
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not FarmRuntime.MarketRuntime.GetOffers or not FarmRuntime.MarketRuntime.GetOffers.Parent then
        if not FarmRuntime.locateMarketRemotes() then
            if not silent then
                FarmRuntime.setMarketStatus("FarmersMarketService unavailable", true)
            end
            return false, "FarmersMarketService unavailable"
        end
    end

    local ok, result = pcall(function()
        return FarmRuntime.MarketRuntime.GetOffers:InvokeServer()
    end)

    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not ok or type(result) ~= "table" or type(result.rows) ~= "table" then
        local err = ok and "invalid GetOffers response" or tostring(result)
        if not silent then
            FarmRuntime.setMarketStatus("GetOffers failed: " .. err, true)
        end
        return false, err
    end

    FarmRuntime.MarketRuntime.offers = result
    FarmRuntime.MarketRuntime.lastRefreshClock = os.clock()
    if ui.RefreshMarket then ui.RefreshMarket() end
    return true, result
end

function FarmRuntime.marketWaitForSelectedItem(itemId, timeout, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    local deadline = os.clock() + (timeout or FarmRuntime.MarketRuntime.EQUIP_TIMEOUT)
    while FarmRuntime.marketOperationCurrent(token)
        and os.clock() < deadline do

        if tostring(CompostRuntime.selectedItemId) == tostring(itemId) then
            return true
        end
        task.wait(0.03)
    end
    return FarmRuntime.marketOperationCurrent(token) and tostring(CompostRuntime.selectedItemId) == tostring(itemId)
end

function FarmRuntime.equipMarketFruit(candidate, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not candidate or candidate.id == nil then
        return false, "invalid fruit"
    end

    if tostring(CompostRuntime.selectedItemId) == tostring(candidate.id) then
        return true
    end

    local service = CompostRuntime.ToolService
    local toggle = service and service.ToggleEquip
    if not toggle or type(toggle.Fire) ~= "function" then
        return false, "ToolService.ToggleEquip unavailable"
    end

    local ok, err = pcall(function()
        toggle:Fire(candidate.hotbar, candidate.slot)
    end)
    if not ok then
        return false, tostring(err)
    end

    if not FarmRuntime.marketWaitForSelectedItem(candidate.id, FarmRuntime.MarketRuntime.EQUIP_TIMEOUT, token) then
        return false, "fruit equip confirmation timed out"
    end

    return true
end

function FarmRuntime.beginMarketTeleport(candidate, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return nil, "cancelled" end
    local fruit = candidate and candidate.fruit
    if not fruit or not fruit.Parent then
        return nil, "fruit unavailable"
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then
        return nil, "HumanoidRootPart unavailable"
    end

    local deadline = os.clock() + 2.0
    while FarmRuntime.marketOperationCurrent(token)
        and (FarmRuntime.teleportOwner or CompostRuntime.batchTeleportTicket)
        and os.clock() < deadline do
        task.wait(0.04)
    end

    if not FarmRuntime.marketOperationCurrent(token) then return nil, "cancelled" end
    if FarmRuntime.teleportOwner or CompostRuntime.batchTeleportTicket then
        return nil, "teleport busy"
    end

    local targetCFrame = FarmRuntime.findFruitTeleportCFrame(
        fruit,
        FarmRuntime.findFruitPrompt(fruit)
    )
    if not targetCFrame then
        return nil, "fruit target unavailable"
    end

    local ticket = {
        owner = "market",
        root = root,
        cframe = root.CFrame,
        linearVelocity = root.AssemblyLinearVelocity,
        angularVelocity = root.AssemblyAngularVelocity,
        anchored = root.Anchored,
    }

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        ticket.humanoid = humanoid
        ticket.autoRotate = humanoid.AutoRotate
    end

    FarmRuntime.teleportOwner = ticket.owner
    FarmRuntime.MarketRuntime.activeTeleport = ticket

    local ok, err = pcall(function()
        root.Anchored = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if humanoid then humanoid.AutoRotate = false end

        local targetPosition = targetCFrame.Position
        local hoverPosition = (targetCFrame * CFrame.new(0, 1.8, 1.1)).Position
        root.CFrame = CFrame.new(hoverPosition, targetPosition)
    end)
    if not ok then
        FarmRuntime.MarketRuntime.activeTeleport = nil
        if FarmRuntime.teleportOwner == ticket.owner then
            FarmRuntime.teleportOwner = nil
        end
        return nil, tostring(err)
    end

    task.wait(FarmRuntime.MarketRuntime.TELEPORT_SETTLE)
    if not FarmRuntime.marketOperationCurrent(token) then
        FarmRuntime.finishMarketTeleport(ticket)
        return nil, "cancelled"
    end
    return ticket
end

function FarmRuntime.finishMarketTeleport(ticket)
    ticket = ticket or FarmRuntime.MarketRuntime.activeTeleport
    if not ticket or ticket.finished then return end
    ticket.finished = true
    local ownsTeleport = FarmRuntime.MarketRuntime.activeTeleport == ticket
    if ownsTeleport then FarmRuntime.MarketRuntime.activeTeleport = nil end

    if ticket and ticket.root and ticket.root.Parent and ticket.cframe then
        pcall(function()
            ticket.root.CFrame = ticket.cframe
            ticket.root.AssemblyLinearVelocity = Vector3.zero
            ticket.root.AssemblyAngularVelocity = Vector3.zero
            ticket.root.Anchored = ticket.anchored == true

            if ticket.humanoid and ticket.humanoid.Parent and ticket.autoRotate ~= nil then
                ticket.humanoid.AutoRotate = ticket.autoRotate
            end

            if ticket.root.Anchored ~= true then
                ticket.root.AssemblyLinearVelocity = ticket.linearVelocity or Vector3.zero
                ticket.root.AssemblyAngularVelocity = ticket.angularVelocity or Vector3.zero
            end
        end)
    end

    if ownsTeleport and FarmRuntime.teleportOwner == ticket.owner then
        FarmRuntime.teleportOwner = nil
    end
end

function FarmRuntime.collectMarketFruit(candidate, cell, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    local fruit = candidate and candidate.fruit
    local treeData = candidate and candidate.treeData
    if not fruit or not fruit.Parent or not treeData then
        return false, "fruit unavailable"
    end

    if type(fireproximityprompt) ~= "function" then
        return false, "fireproximityprompt unavailable"
    end

    local spawnIndex = fruit:GetAttribute("SpawnIndex")
    local treeId = tostring(treeData.id or "")
    local logicalKey = (treeId ~= "" and spawnIndex ~= nil)
        and (treeId .. ":" .. tostring(spawnIndex))
        or nil

    if logicalKey then
        FarmRuntime.MarketRuntime.confirmedFruitKeys[logicalKey] = nil
    end

    claimedFruits[fruit] = true

    local function isConfirmed()
        -- Preferred signal: the exact server FruitCollected(treeId, spawnIndex).
        if logicalKey
            and FarmRuntime.MarketRuntime.confirmedFruitKeys[logicalKey] then
            return true
        end

        -- Keep the old fallbacks in case DataClient / event delivery is late.
        if not fruit.Parent then
            return true
        end

        if FarmRuntime.findMarketInventoryFruit(cell) then
            return true
        end

        return false
    end

    local function waitForConfirmation(timeout)
        local deadline = os.clock() + timeout

        -- IMPORTANT:
        -- Do not care whether the original prompt disappears during this wait.
        -- A disappearing/replaced FruitSpawn can happen while the server is
        -- already processing the first fire. We keep waiting for FruitCollected.
        while FarmRuntime.marketOperationCurrent(token)
            and os.clock() < deadline do

            if isConfirmed() then
                return true
            end

            task.wait(0.03)
        end

        return FarmRuntime.marketOperationCurrent(token) and isConfirmed()
    end

    local function currentPrompt()
        local prompt = fruit.Parent and FarmRuntime.findFruitPrompt(fruit) or nil

        if prompt and prompt.Parent then
            return fruit, prompt
        end

        -- Re-resolve the exact current FruitSpawn by treeId + SpawnIndex.
        local reacquiredFruit, reacquiredPrompt =
            FarmRuntime.reacquireFruitSpawn(treeData, spawnIndex)

        if reacquiredFruit and reacquiredPrompt then
            fruit = reacquiredFruit
            candidate.fruit = reacquiredFruit
            claimedFruits[reacquiredFruit] = true
            return reacquiredFruit, reacquiredPrompt
        end

        return nil, nil
    end

    local activeFruit, prompt = currentPrompt()

    if not activeFruit or not prompt then
        claimedFruits[fruit] = nil
        return false, "fruit prompt unavailable"
    end

    -- Proven by the standalone test:
    -- exact FruitSpawn prompts can be fired remotely while Enabled=false.
    -- No teleport and no prompt property edits.
    local fired, fireErr = pcall(fireproximityprompt, prompt)

    if not fired then
        claimedFruits[fruit] = nil
        return false, tostring(fireErr)
    end

    -- The clean standalone Pear test needed roughly ~1 second before the
    -- server's FruitCollected arrived, so 0.70s was too aggressive.
    local success = waitForConfirmation(
        FarmRuntime.MarketRuntime.DIRECT_CONFIRM_TIMEOUT
    )

    if not success
        and FarmRuntime.marketOperationCurrent(token) then

        activeFruit, prompt = currentPrompt()

        if activeFruit and prompt then
            -- Exact SpawnIndex still exists: retry it once.
            local retryFired = pcall(fireproximityprompt, prompt)

            if retryFired then
                success = waitForConfirmation(
                    FarmRuntime.MarketRuntime.DIRECT_RETRY_TIMEOUT
                )
            end
        else
            -- If the prompt vanished, DO NOT instantly fail.
            -- The first fire may already be processing server-side.
            success = waitForConfirmation(
                FarmRuntime.MarketRuntime.DIRECT_LATE_CONFIRM_GRACE
            )
        end
    end

    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if success then
        state.marketCollected += 1
        state.lastMarketFruit = FarmRuntime.marketRequirementText(cell)

        if logicalKey then
            FarmRuntime.MarketRuntime.confirmedFruitKeys[logicalKey] = nil
        end

        addActivity(
            "Market · instant collected "
                .. tostring(cell.fruitName or cell.seedType or "fruit"),
            "success"
        )

        return true
    end

    if logicalKey then
        FarmRuntime.MarketRuntime.confirmedFruitKeys[logicalKey] = nil
    end

    claimedFruits[fruit] = nil
    FarmRuntime.MarketRuntime.candidateCooldown[fruit] =
        os.clock() + FarmRuntime.MarketRuntime.FAILED_CANDIDATE_COOLDOWN

    return false, logicalKey
        and ("no FruitCollected confirmation for " .. logicalKey)
        or "fruit pickup confirmation timed out after retry"
end

function FarmRuntime.marketCellIsGiven(offers, rowIndex, cellIndex)
    local row = offers and offers.rows and offers.rows[rowIndex]
    local cell = row and row.cells and row.cells[cellIndex]
    return type(cell) == "table" and cell.given == true
end

function FarmRuntime.marketRowClaimed(offers, rowIndex)
    return offers
        and type(offers.claimed) == "table"
        and offers.claimed[rowIndex] == true
end

function FarmRuntime.confirmMarketCell(rowIndex, cellIndex, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    local deadline = os.clock() + FarmRuntime.MarketRuntime.CONFIRM_TIMEOUT
    while FarmRuntime.marketOperationCurrent(token)
        and os.clock() < deadline do

        task.wait(0.06)
        if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
        local ok, offers = FarmRuntime.refreshMarketOffers(true, token)
        if ok and FarmRuntime.marketCellIsGiven(offers, rowIndex, cellIndex) then
            return true, offers
        end
    end
    return false, FarmRuntime.MarketRuntime.offers
end

function FarmRuntime.confirmMarketClaim(rowIndex, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    local deadline = os.clock() + FarmRuntime.MarketRuntime.CONFIRM_TIMEOUT
    while FarmRuntime.marketOperationCurrent(token)
        and os.clock() < deadline do

        task.wait(0.06)
        if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
        local ok, offers = FarmRuntime.refreshMarketOffers(true, token)
        if ok and FarmRuntime.marketRowClaimed(offers, rowIndex) then
            return true, offers
        end
    end
    return false, FarmRuntime.MarketRuntime.offers
end

function FarmRuntime.giveMarketFruit(rowIndex, cellIndex, candidate, row, cell, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    -- FarmersMarketService does not require the fruit Tool to be visibly
    -- equipped. Avoid ToolService.ToggleEquip entirely; this removes the
    -- equip-confirmation wait and makes consecutive submissions much faster.
    local ok, result = pcall(function()
        return FarmRuntime.MarketRuntime.GiveFruit:InvokeServer(rowIndex, cellIndex)
    end)
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not ok then
        return false, "GiveFruit failed: " .. tostring(result)
    end

    local confirmed = FarmRuntime.confirmMarketCell(rowIndex, cellIndex, token)
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not confirmed then
        return false, "GiveFruit was not confirmed"
    end

    state.marketSubmitted += 1
    state.lastMarketFruit = FarmRuntime.marketRequirementText(cell)
    addActivity(
        "Market · submitted " .. tostring(cell.fruitName or cell.seedType or "fruit")
            .. " · row " .. tostring(rowIndex),
        "success"
    )

    if ui.RefreshMarket then ui.RefreshMarket() end
    return true
end

function FarmRuntime.claimMarketRow(rowIndex, row, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    local ok, result = pcall(function()
        return FarmRuntime.MarketRuntime.ClaimRow:InvokeServer(rowIndex)
    end)
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not ok then
        return false, "ClaimRow failed: " .. tostring(result)
    end

    local confirmed = FarmRuntime.confirmMarketClaim(rowIndex, token)
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not confirmed then
        return false, "reward claim was not confirmed"
    end

    local reward = math.max(0, tonumber(row and row.reward) or 0)
    state.marketClaims += 1
    state.marketTickets += reward
    addActivity(
        "Market · claimed " .. tostring(math.floor(reward)) .. " Tickets · row " .. tostring(rowIndex),
        "success"
    )

    if ui.RefreshMarket then ui.RefreshMarket() end
    return true
end

function FarmRuntime.marketFindAction(offers)
    if type(offers) ~= "table" or type(offers.rows) ~= "table" then
        return nil
    end

    -- Claim completed rows first.
    for rowIndex, row in ipairs(offers.rows) do
        if not FarmRuntime.marketRowClaimed(offers, rowIndex) then
            local complete = true
            for _, cell in ipairs(row.cells or {}) do
                if type(cell) == "table" and cell.given ~= true then
                    complete = false
                    break
                end
            end
            if complete then
                return {
                    kind = "claim",
                    rowIndex = rowIndex,
                    row = row,
                }
            end
        end
    end

    -- Prefer fruits already in inventory so no teleport is needed.
    for rowIndex, row in ipairs(offers.rows) do
        if not FarmRuntime.marketRowClaimed(offers, rowIndex) then
            for cellIndex, cell in ipairs(row.cells or {}) do
                if type(cell) == "table" and cell.given ~= true then
                    local inventoryFruit = FarmRuntime.findMarketInventoryFruit(cell)
                    if inventoryFruit then
                        return {
                            kind = "give",
                            rowIndex = rowIndex,
                            cellIndex = cellIndex,
                            row = row,
                            cell = cell,
                            inventoryFruit = inventoryFruit,
                        }
                    end
                end
            end
        end
    end

    -- No matching inventory fruit: walk outstanding requirements in stable
    -- Farmers Market order. Candidate scoring is applied only within the same
    -- requirement. This prevents a valid mutated/oversized fruit from being
    -- starved forever by cheaper fruit for unrelated rows.
    for rowIndex, row in ipairs(offers.rows) do
        if not FarmRuntime.marketRowClaimed(offers, rowIndex) then
            for cellIndex, cell in ipairs(row.cells or {}) do
                if type(cell) == "table" and cell.given ~= true then
                    local plotFruit = FarmRuntime.findMarketPlotFruit(cell)
                    if plotFruit then
                        return {
                            kind = "collect",
                            rowIndex = rowIndex,
                            cellIndex = cellIndex,
                            row = row,
                            cell = cell,
                            plotFruit = plotFruit,
                        }
                    end
                end
            end
        end
    end

    return nil
end


function FarmRuntime.marketBuildRowBurstPlan(offers)
    if type(offers) ~= "table" or type(offers.rows) ~= "table" then
        return nil
    end

    for rowIndex, row in ipairs(offers.rows) do
        if not FarmRuntime.marketRowClaimed(offers, rowIndex) then
            local reservedInventory = {}
            local reservedPlot = setmetatable({}, { __mode = "k" })
            local entries = {}
            local actionable = 0
            local outstanding = 0

            for cellIndex, cell in ipairs(row.cells or {}) do
                if type(cell) == "table" and cell.given ~= true then
                    outstanding += 1

                    local entry = {
                        rowIndex = rowIndex,
                        cellIndex = cellIndex,
                        row = row,
                        cell = cell,
                    }

                    local inventoryFruit =
                        FarmRuntime.findMarketInventoryFruit(cell, reservedInventory)

                    if inventoryFruit then
                        entry.inventoryFruit = inventoryFruit
                        reservedInventory[tostring(inventoryFruit.id)] = true
                        actionable += 1
                    else
                        local plotFruit =
                            FarmRuntime.findMarketPlotFruit(cell, reservedPlot)

                        if plotFruit then
                            entry.plotFruit = plotFruit
                            reservedPlot[plotFruit.fruit] = true
                            actionable += 1
                        end
                    end

                    entries[#entries + 1] = entry
                end
            end

            if actionable > 0 then
                return {
                    rowIndex = rowIndex,
                    row = row,
                    entries = entries,
                    actionable = actionable,
                    outstanding = outstanding,
                }
            end
        end
    end

    return nil
end

function FarmRuntime.marketRunRowBurst(plan, token)
    token = token or FarmRuntime.marketOperationToken()
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    -- This burst owns its children; a timeout also cancels their continuations.
    token = { generation = token.generation, revision = token.revision }
    if type(plan) ~= "table"
        or type(plan.entries) ~= "table"
        or not plan.rowIndex then
        return false, "invalid row burst plan"
    end

    local collectJobs = {}
    local collectDone = 0

    -- Collect every missing physical fruit almost simultaneously.
    for _, entry in ipairs(plan.entries) do
        if entry.plotFruit and not entry.inventoryFruit then
            collectJobs[#collectJobs + 1] = entry
        end
    end

    if #collectJobs > 0 then
        FarmRuntime.setMarketStatus(
            "Row " .. tostring(plan.rowIndex)
                .. " · collecting " .. tostring(#collectJobs)
                .. " fruit" .. (#collectJobs == 1 and "" or "s")
                .. " in parallel",
            false
        )

        for jobIndex, entry in ipairs(collectJobs) do
            task.spawn(function()
                task.wait(
                    (jobIndex - 1)
                    * FarmRuntime.MarketRuntime.ROW_BURST_COLLECT_STAGGER
                )

                if not FarmRuntime.marketOperationCurrent(token) then collectDone += 1; return end
                local ok, collected, collectErr = pcall(
                    FarmRuntime.collectMarketFruit,
                    entry.plotFruit,
                    entry.cell,
                    token
                )

                if not FarmRuntime.marketOperationCurrent(token) then collectDone += 1; return end
                entry.collectFinished = true
                entry.collectSuccess = ok and collected == true
                entry.collectError = ok and collectErr or tostring(collected)
                collectDone += 1
            end)
        end

        local collectDeadline =
            os.clock() + FarmRuntime.MarketRuntime.ROW_BURST_WAIT_TIMEOUT

        while FarmRuntime.marketOperationCurrent(token)
            and collectDone < #collectJobs
            and os.clock() < collectDeadline do
            task.wait(0.03)
        end
        if collectDone < #collectJobs then
            token.cancelled = true
            return false, "collect burst cancelled or timed out"
        end
    end

    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end

    -- Resolve one distinct matching inventory fruit per cell after the
    -- parallel pickup phase. This also includes cells that already had fruit.
    local reservedInventory = {}
    local readyEntries = {}

    for _, entry in ipairs(plan.entries) do
        if entry.inventoryFruit then
            local idKey = tostring(entry.inventoryFruit.id)
            if not reservedInventory[idKey] then
                reservedInventory[idKey] = true
                readyEntries[#readyEntries + 1] = entry
            end
        elseif entry.collectSuccess then
            local deadline = os.clock() + 1.75
            local inventoryFruit = nil

            while FarmRuntime.marketOperationCurrent(token)
                and os.clock() < deadline do

                inventoryFruit =
                    FarmRuntime.findMarketInventoryFruit(
                        entry.cell,
                        reservedInventory
                    )

                if inventoryFruit then
                    break
                end

                task.wait(0.03)
            end

            if inventoryFruit then
                entry.inventoryFruit = inventoryFruit
                reservedInventory[tostring(inventoryFruit.id)] = true
                readyEntries[#readyEntries + 1] = entry
            else
                entry.collectSuccess = false
                entry.collectError = "collected fruit did not enter inventory"
            end
        end
    end

    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end

    -- Fire GiveFruit for every ready cell in the row almost at once.
    local giveDone = 0

    if #readyEntries > 0 then
        FarmRuntime.setMarketStatus(
            "Row " .. tostring(plan.rowIndex)
                .. " · submitting " .. tostring(#readyEntries)
                .. "/" .. tostring(plan.outstanding)
                .. " cells in parallel",
            false
        )

        for giveIndex, entry in ipairs(readyEntries) do
            task.spawn(function()
                task.wait(
                    (giveIndex - 1)
                    * FarmRuntime.MarketRuntime.ROW_BURST_GIVE_STAGGER
                )

                if not FarmRuntime.marketOperationCurrent(token) then giveDone += 1; return end
                local ok, given, giveErr = pcall(
                    FarmRuntime.giveMarketFruit,
                    plan.rowIndex,
                    entry.cellIndex,
                    entry.inventoryFruit,
                    plan.row,
                    entry.cell,
                    token
                )

                if not FarmRuntime.marketOperationCurrent(token) then giveDone += 1; return end
                entry.giveFinished = true
                entry.giveSuccess = ok and given == true
                entry.giveError = ok and giveErr or tostring(given)
                giveDone += 1
            end)
        end

        local giveDeadline =
            os.clock() + FarmRuntime.MarketRuntime.ROW_BURST_WAIT_TIMEOUT

        while FarmRuntime.marketOperationCurrent(token)
            and giveDone < #readyEntries
            and os.clock() < giveDeadline do
            task.wait(0.03)
        end
        if giveDone < #readyEntries then
            token.cancelled = true
            return false, "give burst cancelled or timed out"
        end
    end

    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end

    -- One final refresh tells us the actual server state of the row.
    local refreshed, offers = FarmRuntime.refreshMarketOffers(true, token)
    if not FarmRuntime.marketOperationCurrent(token) then return false, "cancelled" end
    if not refreshed then
        return false, "row burst finished but GetOffers refresh failed"
    end

    local currentRow = offers.rows and offers.rows[plan.rowIndex]
    if type(currentRow) ~= "table" then
        return false, "row disappeared after burst"
    end

    local givenCount = 0
    local totalCount = 0

    for _, cell in ipairs(currentRow.cells or {}) do
        if type(cell) == "table" then
            totalCount += 1
            if cell.given == true then
                givenCount += 1
            end
        end
    end

    if givenCount >= totalCount and totalCount > 0 then
        FarmRuntime.setMarketStatus(
            "Row " .. tostring(plan.rowIndex)
                .. " complete · claiming "
                .. tostring(math.floor(tonumber(currentRow.reward) or 0))
                .. " Tickets",
            false
        )

        local claimed, claimErr =
            FarmRuntime.claimMarketRow(plan.rowIndex, currentRow, token)

        if not claimed then
            return false, tostring(claimErr)
        end

        return true
    end

    local failedCollects = 0
    local failedGives = 0

    for _, entry in ipairs(plan.entries) do
        if entry.plotFruit and entry.collectFinished
            and entry.collectSuccess ~= true then
            failedCollects += 1
        end
        if entry.inventoryFruit and entry.giveFinished
            and entry.giveSuccess ~= true then
            failedGives += 1
        end
    end

    FarmRuntime.setMarketStatus(
        "Row " .. tostring(plan.rowIndex)
            .. " · " .. tostring(givenCount) .. "/" .. tostring(totalCount)
            .. " given"
            .. (failedCollects > 0
                and (" · " .. tostring(failedCollects) .. " pickup miss")
                or "")
            .. (failedGives > 0
                and (" · " .. tostring(failedGives) .. " submit miss")
                or ""),
        false
    )

    return true
end

function FarmRuntime.marketOutstandingCount(offers)
    local rowsLeft, cellsLeft = 0, 0
    if type(offers) ~= "table" or type(offers.rows) ~= "table" then
        return rowsLeft, cellsLeft
    end

    for rowIndex, row in ipairs(offers.rows) do
        if not FarmRuntime.marketRowClaimed(offers, rowIndex) then
            rowsLeft += 1
            for _, cell in ipairs(row.cells or {}) do
                if type(cell) == "table" and cell.given ~= true then
                    cellsLeft += 1
                end
            end
        end
    end
    return rowsLeft, cellsLeft
end

function FarmRuntime.scheduleMarketWorker(delaySeconds)
    if not state.running or state.stopping or FarmRuntime.MarketRuntime.workerScheduled or not state.autoMarketEnabled then
        return
    end

    FarmRuntime.MarketRuntime.workerScheduled = true
    local revision = FarmRuntime.MarketRuntime.workerRevision
    local generation = state.generation
    local token = FarmRuntime.marketOperationToken()

    task.delay(math.max(0, tonumber(delaySeconds) or 0), function()
        if not state.running
            or not state.autoMarketEnabled
            or state.generation ~= generation
            or FarmRuntime.MarketRuntime.workerRevision ~= revision then
            return
        end
        if not FarmRuntime.marketOperationCurrent(token) then return end
        FarmRuntime.MarketRuntime.workerScheduled = false

        local nextDelay = FarmRuntime.MarketRuntime.STEP_DELAY
        local ok, err = pcall(function()
            local offers = FarmRuntime.MarketRuntime.offers
            if not offers or os.clock() - FarmRuntime.MarketRuntime.lastRefreshClock > 2.0 then
                local refreshed, fresh = FarmRuntime.refreshMarketOffers(true, token)
                if not FarmRuntime.marketOperationCurrent(token) then return end
                if not refreshed then
                    nextDelay = FarmRuntime.MarketRuntime.RETRY_DELAY
                    FarmRuntime.setMarketStatus("Waiting for Farmers Market service", false)
                    return
                end
                offers = fresh
            end

            local rowsLeft, cellsLeft = FarmRuntime.marketOutstandingCount(offers)
            if rowsLeft == 0 then
                FarmRuntime.setMarketStatus("All current offers claimed", false)
                nextDelay = 12
                return
            end

            -- Completed rows still get claimed immediately.
            local action = FarmRuntime.marketFindAction(offers)
            if action and action.kind == "claim" then
                FarmRuntime.setMarketStatus(
                    "Claiming row " .. tostring(action.rowIndex)
                        .. " · " .. tostring(math.floor(tonumber(action.row.reward) or 0))
                        .. " Tickets",
                    false
                )

                local claimed, claimErr =
                    FarmRuntime.claimMarketRow(action.rowIndex, action.row, token)

                if not FarmRuntime.marketOperationCurrent(token) then return end
                if not claimed then
                    FarmRuntime.setMarketStatus(tostring(claimErr), true)
                    nextDelay = FarmRuntime.MarketRuntime.RETRY_DELAY
                else
                    nextDelay = 0.05
                end

                return
            end

            -- Experimental row-burst mode:
            -- reserve up to one matching fruit per unfinished cell, collect all
            -- missing plot fruits in parallel, then submit every ready cell in
            -- the row almost simultaneously.
            local plan = FarmRuntime.marketBuildRowBurstPlan(offers)

            if not plan then
                FarmRuntime.setMarketStatus(
                    "Waiting for matching fruit · " .. tostring(cellsLeft) .. " needed",
                    false
                )
                nextDelay = FarmRuntime.MarketRuntime.RETRY_DELAY
                return
            end

            local burstOk, burstErr = FarmRuntime.marketRunRowBurst(plan, token)

            if not FarmRuntime.marketOperationCurrent(token) then return end
            if not burstOk then
                FarmRuntime.setMarketStatus(
                    "Row burst issue: " .. tostring(burstErr),
                    true
                )
                nextDelay = FarmRuntime.MarketRuntime.RETRY_DELAY
            else
                nextDelay = 0.08
            end
        end)

        if not FarmRuntime.marketOperationCurrent(token) then return end
        if not ok then
            FarmRuntime.setMarketStatus("Market worker error: " .. tostring(err), true)
            nextDelay = FarmRuntime.MarketRuntime.RETRY_DELAY
        end

        if state.running
            and state.autoMarketEnabled
            and state.generation == generation
            and FarmRuntime.MarketRuntime.workerRevision == revision then
            FarmRuntime.scheduleMarketWorker(nextDelay)
        end
    end)
end

function FarmRuntime.setAutoMarket(value)
    if not state.running or state.stopping then return end
    local enabled = value == true
    if state.autoMarketEnabled == enabled then
        if enabled then FarmRuntime.scheduleMarketWorker(0) end
        return
    end

    state.autoMarketEnabled = enabled
    FarmRuntime.MarketRuntime.workerRevision += 1
    FarmRuntime.MarketRuntime.workerScheduled = false

    local token = FarmRuntime.marketOperationToken()
    if enabled then
        state.lastMarketError = nil
        FarmRuntime.setMarketStatus("Checking Farmers Market", false)
        FarmRuntime.refreshMarketOffers(true, token)
        if not FarmRuntime.marketOperationCurrent(token) then return end
        FarmRuntime.scheduleMarketWorker(0)
    else
        FarmRuntime.finishMarketTeleport()
        FarmRuntime.setMarketStatus("Auto Market off", false)
    end

    scheduleSettingsSave()
    if ui.RefreshMarket then ui.RefreshMarket() end
    if ui.RefreshHeader then ui.RefreshHeader() end
end

function FarmRuntime.initializeMarket()
    if not FarmRuntime.locateMarketRemotes() then
        FarmRuntime.setMarketStatus("FarmersMarketService unavailable", true)
        return false
    end

    local ok, offers = FarmRuntime.refreshMarketOffers(true)
    if ok then
        FarmRuntime.MarketRuntime.offers = offers
        FarmRuntime.setMarketStatus(
            state.autoMarketEnabled and "Auto Market active" or "Ready",
            false
        )
    end

    if state.autoMarketEnabled then
        FarmRuntime.scheduleMarketWorker(0)
    end

    return ok
end

function FarmRuntime.getCurrentData()
    return CompostRuntime.DataClient and CompostRuntime.DataClient.currentData or nil
end

function FarmRuntime.getLiveSeedTotals()
    local result = {}
    local data = FarmRuntime.getCurrentData()
    local inventory = data and data.Inventory

    local function visit(container)
        if type(container) ~= "table" then return end
        for _, item in pairs(container) do
            if type(item) == "table" and item.itemType == "Seed" and type(item.seedType) == "string" then
                local count = math.max(0, tonumber(item.count) or 1)
                result[item.seedType] = (result[item.seedType] or 0) + count
            end
        end
    end

    visit(inventory and inventory.Hotbar)
    visit(inventory and inventory.Storage)

    if next(result) == nil then
        return inventoryAggregate().seeds
    end

    return result
end

function FarmRuntime.parseCompostProgress(text)
    if type(text) ~= "string" then return nil, nil end
    local current, capacity = text:match("^%s*(%d+)%s*/%s*(%d+)%s*$")
    current, capacity = tonumber(current), tonumber(capacity)
    if not current or not capacity or capacity <= 0 then return nil, nil end
    return current, capacity
end

function FarmRuntime.getCompostProgress()
    local labelObject = CompostRuntime.amountLabel
    if labelObject and labelObject.Parent then
        local ok, textValue = pcall(function() return labelObject.Text end)
        if ok then
            local current, capacity = FarmRuntime.parseCompostProgress(textValue)
            if current then
                CompostRuntime.lastProgress = current
                CompostRuntime.lastCapacity = capacity
                return current, capacity, textValue
            end
        end
    end
    return CompostRuntime.lastProgress or 0, CompostRuntime.lastCapacity or COMPOST_CAPACITY, nil
end

function FarmRuntime.refreshCompostRefs()
    CompostRuntime.bin = nil
    CompostRuntime.model = nil
    CompostRuntime.compostPart = nil
    CompostRuntime.promptPart = nil
    CompostRuntime.prompt = nil
    CompostRuntime.amountLabel = nil

    if not ownPlot or not ownPlot.Parent then
        return false
    end

    -- Current game hierarchy:
    -- workspace.BigField.PlayerPlots.<OwnPlot>.CompostBin.Compost
    -- <OwnPlot> is resolved dynamically from OwnerUserId, so this is NOT
    -- hardcoded to PlayerPlot1.
    local bin = ownPlot:FindFirstChild("CompostBin")
    local model = bin and bin:FindFirstChild("Model")
    local compostPart = bin and bin:FindFirstChild("Compost")

    if compostPart and not compostPart:IsA("BasePart") then
        compostPart = nil
    end

    -- Current prompt hierarchy:
    -- workspace.BigField.PlayerPlots.<OwnPlot>.CompostBin.PromptPart.CompostPrompt
    -- <OwnPlot> is resolved dynamically from OwnerUserId.
    local promptPart = bin and bin:FindFirstChild("PromptPart")
    local prompt = promptPart and promptPart:FindFirstChild("CompostPrompt")

    if prompt and not prompt:IsA("ProximityPrompt") then
        prompt = nil
    end

    -- Fallback discovery in case the game moves the prompt again later.
    if not prompt and bin then
        local namedPrompt = bin:FindFirstChild("CompostPrompt", true)
        if namedPrompt and namedPrompt:IsA("ProximityPrompt") then
            prompt = namedPrompt
            promptPart = namedPrompt.Parent
        end
    end

    if not prompt and bin then
        for _, descendant in ipairs(bin:GetDescendants()) do
            if descendant:IsA("ProximityPrompt") then
                local action = tostring(descendant.ActionText or "")
                if descendant.Name == "CompostPrompt"
                    or action == "Give Seed"
                    or action == "Collect" then
                    prompt = descendant
                    promptPart = descendant.Parent
                    break
                end
            end
        end
    end

    if not prompt and bin then
        prompt = bin:FindFirstChildWhichIsA("ProximityPrompt", true)
        if prompt then
            promptPart = prompt.Parent
        end
    end

    -- UI/progress objects may also be nested now.
    local amount = bin and bin:FindFirstChild("Amount", true)
    local frame = amount and (
        amount:FindFirstChild("Frame")
        or amount:FindFirstChildWhichIsA("Frame", true)
    )
    local identifier = frame and (
        frame:FindFirstChild("Identifier", true)
        or frame:FindFirstChildWhichIsA("TextLabel", true)
    )

    CompostRuntime.bin = bin
    CompostRuntime.model = model
    CompostRuntime.compostPart = compostPart
    CompostRuntime.promptPart = promptPart
    CompostRuntime.prompt = prompt
    CompostRuntime.amountLabel = identifier

    if prompt then
        CompostRuntime.lastPromptAction = prompt.ActionText
    end

    FarmRuntime.getCompostProgress()

    if ui.RefreshCompost then
        ui.RefreshCompost()
    end

    return compostPart ~= nil and prompt ~= nil
end

-- A yielding action belongs to one feature enable cycle and client instance.
-- Cancellation prevents new sends; an already sent request cannot be recalled.
function FarmRuntime.featureOperationToken(kind)
    local revision = kind == "compost" and CompostRuntime.workerRevision
        or kind == "pet" and PetSeedRuntime.revision
        or kind == "feed" and FarmRuntime.PetFeed.revision or FarmRuntime.LeafRuntime.revision
    return { kind = kind, generation = state.generation, revision = revision }
end

function FarmRuntime.cancelFeatureClaim(token)
    if token and token.kind == "feed" then FarmRuntime.petFeedReleaseClaim(token) end
    local runtime, instance = token and token.claimRuntime, token and token.claimInstance
    if runtime and instance and runtime.claimed[instance] == token then runtime.claimed[instance] = nil end
end

function FarmRuntime.featureOperationCurrent(token)
    if not token or token.cancelled or not state.running or state.stopping or state.generation ~= token.generation then return false end
    local enabled, revision
    if token.kind == "compost" then enabled, revision = state.autoCompostEnabled, CompostRuntime.workerRevision
    elseif token.kind == "pet" then enabled, revision = state.autoCollectPetSeeds, PetSeedRuntime.revision
    elseif token.kind == "feed" then enabled, revision = state.autoFeedPetsEnabled, FarmRuntime.PetFeed.revision
    else enabled, revision = state.autoCollectLeaves, FarmRuntime.LeafRuntime.revision end
    return enabled and revision == token.revision
        and (not token.claimed or (FarmRuntime.AutomationRuntime.operation == token and FarmRuntime.AutomationRuntime.owner == token.kind))
end

function FarmRuntime.acquireFeatureOperation(token)
    if not FarmRuntime.featureOperationCurrent(token) then return false end
    local runtime = FarmRuntime.AutomationRuntime
    if runtime.operation == token and runtime.owner == token.kind then runtime.since = os.clock(); return true end
    if runtime.operation and os.clock() - (runtime.since or 0) <= 10 then return false end
    if not FarmRuntime.acquireAutomation(token.kind) then return false end
    token.claimed = true
    FarmRuntime.AutomationRuntime.operation = token
    return true
end

function FarmRuntime.releaseFeatureOperation(token)
    if not FarmRuntime.featureOperationCurrent(token) then FarmRuntime.cancelFeatureClaim(token) end
    if FarmRuntime.AutomationRuntime.operation ~= token then return end
    FarmRuntime.AutomationRuntime.operation = nil
    token.claimed = false
    FarmRuntime.releaseAutomation(token.kind)
end

function FarmRuntime.beginCompostTeleport(token)
    if not FarmRuntime.featureOperationCurrent(token) then return nil, "cancelled" end
    if not ownPlot or not ownPlot.Parent then
        return nil, "own plot unavailable"
    end

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then
        return nil, "HumanoidRootPart unavailable"
    end

    local bin = CompostRuntime.bin or ownPlot:FindFirstChild("CompostBin")
    local compostPart = CompostRuntime.compostPart or (bin and bin:FindFirstChild("Compost"))

    -- Teleport to the exact Compost part on the LOCAL PLAYER'S plot:
    -- workspace.BigField.PlayerPlots.<OwnPlot>.CompostBin.Compost
    local target = compostPart
    if target and not target:IsA("BasePart") then
        target = nil
    end

    -- Fallback only if a future update removes/renames Compost.
    if not target and CompostRuntime.prompt then
        target = CompostRuntime.prompt:FindFirstAncestorWhichIsA("BasePart")
    end

    if not target then
        return nil, "ownPlot.CompostBin.Compost unavailable"
    end

    local pivotOk, pivot = pcall(function()
        return target:GetPivot()
    end)
    if not pivotOk or typeof(pivot) ~= "CFrame" then
        return nil, "Compost target pivot unavailable"
    end

    local ticket = { root = root }
    local savedOk, savedErr = pcall(function()
        ticket.cframe = root.CFrame
        ticket.linearVelocity = root.AssemblyLinearVelocity
        ticket.angularVelocity = root.AssemblyAngularVelocity
        local targetPosition = pivot.Position
        local standPosition = (pivot * CFrame.new(0, 2.25, 2.5)).Position
        root.CFrame = CFrame.new(
            standPosition,
            targetPosition + Vector3.new(0, 1, 0)
        )
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if not savedOk then
        return nil, tostring(savedErr)
    end

    CompostRuntime.batchTeleportTicket = ticket
    task.wait(0.28)
    if not FarmRuntime.featureOperationCurrent(token) then
        FarmRuntime.finishCompostTeleport(ticket)
        return nil, "cancelled"
    end
    return ticket
end

function FarmRuntime.finishCompostTeleport(ticket)
    if not ticket or ticket.finished then return end
    ticket.finished = true
    if CompostRuntime.batchTeleportTicket == ticket then CompostRuntime.batchTeleportTicket = nil end
    if not ticket.root or not ticket.root.Parent or not ticket.cframe then
        return
    end
    pcall(function()
        ticket.root.CFrame = ticket.cframe
        ticket.root.AssemblyLinearVelocity = ticket.linearVelocity or Vector3.zero
        ticket.root.AssemblyAngularVelocity = ticket.angularVelocity or Vector3.zero
    end)
end

function FarmRuntime.ensureCompostTeleport(token)
    if not FarmRuntime.featureOperationCurrent(token) then return nil, "cancelled" end
    local ticket = CompostRuntime.batchTeleportTicket
    if ticket and ticket.root and ticket.root.Parent and ticket.cframe then
        return ticket
    end
    CompostRuntime.batchTeleportTicket = nil
    local newTicket, err = FarmRuntime.beginCompostTeleport(token)
    if newTicket then
        CompostRuntime.batchTeleportTicket = newTicket
    end
    return newTicket, err
end

function FarmRuntime.releaseCompostTeleport()
    local ticket = CompostRuntime.batchTeleportTicket
    CompostRuntime.batchTeleportTicket = nil
    FarmRuntime.finishCompostTeleport(ticket)
end

function FarmRuntime.triggerCompostPrompt(prompt, attempt, token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not prompt or not prompt.Parent then
        return false, "prompt unavailable"
    end

    attempt = math.max(1, tonumber(attempt) or 1)

    -- The game has changed the compost interaction more than once.
    -- Do not rely on the replicated prompt properties being automation-friendly.
    pcall(function()
        prompt.Enabled = true
        prompt.RequiresLineOfSight = false
        prompt.MaxActivationDistance = math.huge
        prompt.HoldDuration = 0
    end)

    if type(fireproximityprompt) == "function" then
        -- Try both common executor signatures.
        local ok, err = pcall(fireproximityprompt, prompt, 0)
        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        if ok then
            return true
        end

        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        ok, err = pcall(fireproximityprompt, prompt)
        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        if ok then
            return true
        end

        warn("[FA V4.3][COMPOST] fireproximityprompt failed:", err)
    end

    -- Fallback to an actual prompt hold.
    local holdDuration = math.max(0.05, tonumber(prompt.HoldDuration) or 0)

    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    local holdStarted = false
    local holdOk, holdErr = pcall(function()
        if not FarmRuntime.featureOperationCurrent(token) then return end
        holdStarted = true
        prompt:InputHoldBegin()
        task.wait(holdDuration + 0.08)
    end)
    if holdStarted then
        local releaseOk, releaseErr = pcall(function() prompt:InputHoldEnd() end)
        if not releaseOk then holdOk, holdErr = false, releaseErr end
    end
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if holdOk then
        return true
    end

    if prompt.KeyboardKeyCode == Enum.KeyCode.E
        and type(keypress) == "function"
        and type(keyrelease) == "function" then

        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        local keyStarted = false
        local keyOk, keyErr = pcall(function()
            if not FarmRuntime.featureOperationCurrent(token) then return end
            keyStarted = true
            keypress(0x45)
            task.wait(holdDuration + 0.08)
        end)
        if keyStarted then
            local releaseOk, releaseErr = pcall(keyrelease, 0x45)
            if not releaseOk then keyOk, keyErr = false, releaseErr end
        end

        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        if keyOk then
            return true
        end

        return false, tostring(keyErr)
    end

    return false, tostring(holdErr)
end

function FarmRuntime.compostPositionMatches(position)
    if typeof(position) ~= "Vector3" then return true end

    local part = CompostRuntime.compostPart
    if part and part.Parent and part:IsA("BasePart") then
        return (part.Position - position).Magnitude <= 18
    end

    part = CompostRuntime.promptPart
    if not part or not part.Parent then return false end

    local origin = nil
    if part:IsA("BasePart") then
        origin = part.Position
    elseif CompostRuntime.prompt and CompostRuntime.prompt.Parent and CompostRuntime.prompt.Parent:IsA("BasePart") then
        origin = CompostRuntime.prompt.Parent.Position
    end

    return origin == nil or (origin - position).Magnitude <= 18
end

function FarmRuntime.findSelectedCompostStack()
    local data = FarmRuntime.getCurrentData()
    local inventory = data and data.Inventory
    if type(inventory) ~= "table" then
        return nil
    end

    local candidates = {}

    local function collect(container, isHotbar)
        if type(container) ~= "table" then return end
        for slot, item in pairs(container) do
            if type(item) == "table"
                and item.itemType == "Seed"
                and type(item.seedType) == "string"
                and state.selectedCompostSeeds[item.seedType] == true
                and item.id ~= nil
                and (tonumber(item.count) or 1) > 0 then

                candidates[#candidates + 1] = {
                    key = item.seedType,
                    count = math.max(1, tonumber(item.count) or 1),
                    id = item.id,
                    slot = tonumber(slot) or slot,
                    hotbar = isHotbar,
                    item = item,
                }
            end
        end
    end

    collect(inventory.Hotbar, true)
    collect(inventory.Storage, false)

    table.sort(candidates, function(a, b)
        local ar = seedByKey[a.key]
        local br = seedByKey[b.key]
        local ac = ar and ar.plantCost or math.huge
        local bc = br and br.plantCost or math.huge

        if ac ~= bc then return ac < bc end
        if a.count ~= b.count then return a.count > b.count end
        if a.hotbar ~= b.hotbar then return a.hotbar end
        return tostring(a.slot) < tostring(b.slot)
    end)

    return candidates[1]
end

function FarmRuntime.waitForSelectedItem(itemId, timeout, token)
    local deadline = os.clock() + (timeout or COMPOST_EQUIP_TIMEOUT)
    while FarmRuntime.featureOperationCurrent(token)
        and os.clock() < deadline do

        if tostring(CompostRuntime.selectedItemId) == tostring(itemId) then
            return true
        end
        task.wait(0.03)
    end
    return FarmRuntime.featureOperationCurrent(token) and tostring(CompostRuntime.selectedItemId) == tostring(itemId)
end

function FarmRuntime.equipCompostStack(candidate, token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not candidate or candidate.id == nil then
        return false, "invalid seed stack"
    end

    if tostring(CompostRuntime.selectedItemId) == tostring(candidate.id) then
        return true
    end

    local service = CompostRuntime.ToolService
    local toggle = service and service.ToggleEquip
    if not toggle or type(toggle.Fire) ~= "function" then
        return false, "ToolService.ToggleEquip unavailable"
    end

    local ok, err = pcall(function()
        toggle:Fire(candidate.hotbar, candidate.slot)
    end)
    if not ok then
        return false, tostring(err)
    end

    if not FarmRuntime.waitForSelectedItem(candidate.id, COMPOST_EQUIP_TIMEOUT, token) then
        return false, "seed equip confirmation timed out"
    end

    return true
end

function FarmRuntime.waitForCompostProgressChange(before, timeout, prompt, token)
    local deadline = os.clock() + (timeout or COMPOST_CONFIRM_TIMEOUT)
    local retryAttempt = 1
    local nextRetry = os.clock() + 0.75
    while FarmRuntime.featureOperationCurrent(token)
        and os.clock() < deadline do

        local current = FarmRuntime.getCompostProgress()
        if current ~= before then
            return current
        end
        if prompt and retryAttempt < 3 and os.clock() >= nextRetry then
            retryAttempt += 1
            state.compostAttempts += 1
            FarmRuntime.triggerCompostPrompt(prompt, retryAttempt, token)
            nextRetry = os.clock() + 0.75
        end
        task.wait(0.035)
    end

    if not FarmRuntime.featureOperationCurrent(token) then return nil end
    local current = FarmRuntime.getCompostProgress()
    return current ~= before and current or nil
end

function FarmRuntime.setCompostStatus(text, isError)
    state.compostStatus = tostring(text or "Idle")
    if isError then
        state.lastCompostError = state.compostStatus
    end
    if ui.RefreshCompost then ui.RefreshCompost() end
end

function FarmRuntime.compostFeedStep(token)
    token = token or FarmRuntime.featureOperationToken("compost")
    if not FarmRuntime.featureOperationCurrent(token) then
        return false, "stopped"
    end

    if not FarmRuntime.refreshCompostRefs() then
        FarmRuntime.setCompostStatus("Waiting for own Compost Bin")
        return false, "plot"
    end

    local prompt = CompostRuntime.prompt
    if not prompt or not prompt.Parent then
        FarmRuntime.setCompostStatus("Compost prompt unavailable", true)
        return false, "prompt"
    end

    if not prompt.Enabled then
        FarmRuntime.setCompostStatus("Compost prompt disabled")
        return false, "disabled"
    end

    if type(fireproximityprompt) ~= "function" then
        FarmRuntime.setCompostStatus("fireproximityprompt unavailable", true)
        return false, "fire_unavailable"
    end

    local progress, capacity = FarmRuntime.getCompostProgress()
    capacity = capacity or COMPOST_CAPACITY

    -- At 100/100 the same prompt becomes "Collect". No held seed is needed.
    if progress >= capacity and prompt.ActionText ~= "Collect" then
        FarmRuntime.setCompostStatus("100/100 · waiting for Collect prompt")
        return false, "waiting_collect"
    end

    if prompt.ActionText == "Collect" then
        FarmRuntime.setCompostStatus("Collecting worm…")

        local beforeWorms = state.wormsGranted
        CompostRuntime.lastCollectRequestClock = os.clock()
        local teleportTicket, teleportErr = FarmRuntime.ensureCompostTeleport(token)
        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        if not teleportTicket then
            FarmRuntime.setCompostStatus("Compost teleport failed: " .. tostring(teleportErr), true)
            return false, "teleport"
        end
        local ok, err = FarmRuntime.triggerCompostPrompt(prompt, 1, token)
        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        if not ok then
            FarmRuntime.setCompostStatus("Collect failed: " .. tostring(err), true)
            return false, "collect_fire"
        end

        state.compostAttempts += 1
        local confirmationOk, confirmed = pcall(function()
            local deadline = os.clock() + 3
            local retryAttempt = 1
            local nextRetry = os.clock() + 0.75
            while FarmRuntime.featureOperationCurrent(token)
                and os.clock() < deadline do

                local nowProgress = FarmRuntime.getCompostProgress()
                if state.wormsGranted > beforeWorms or nowProgress < progress then
                    return true
                end
                if retryAttempt < 3 and os.clock() >= nextRetry then
                    retryAttempt += 1
                    state.compostAttempts += 1
                    FarmRuntime.triggerCompostPrompt(prompt, retryAttempt, token)
                    nextRetry = os.clock() + 0.75
                end
                task.wait(0.04)
            end
            return false
        end)
        if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
        if not confirmationOk then
            FarmRuntime.setCompostStatus("Collect confirmation failed: " .. tostring(confirmed), true)
            return false, "collect_confirm"
        end
        if confirmed then
            if ui.RefreshCompost then ui.RefreshCompost() end
            return true, "collected"
        end
        FarmRuntime.setCompostStatus("Worm collect confirmation timed out", true)
        return false, "collect_timeout"
    end

    local candidate = FarmRuntime.findSelectedCompostStack()
    if not candidate then
        FarmRuntime.setCompostStatus("Waiting for selected seeds")
        return false, "no_seeds"
    end

    -- Validate/perform the teleport BEFORE touching the held seed. If the
    -- compost path changes again, Auto Compost fails cleanly instead of
    -- repeatedly equipping the cheapest selected seed (often Oak Seed).
    local preTeleportTicket, preTeleportErr = FarmRuntime.ensureCompostTeleport(token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not preTeleportTicket then
        FarmRuntime.setCompostStatus("Compost teleport failed: " .. tostring(preTeleportErr), true)
        return false, "teleport"
    end

    local equipped, equipErr = FarmRuntime.equipCompostStack(candidate, token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not equipped then
        FarmRuntime.setCompostStatus("Equip failed: " .. tostring(equipErr), true)
        return false, "equip"
    end

    -- Revalidate the exact prompt and progress after equipping.
    -- Do NOT require ActionText == "Give Seed": that text changed in a game update.
    FarmRuntime.refreshCompostRefs()
    prompt = CompostRuntime.prompt
    local before = FarmRuntime.getCompostProgress()

    if not prompt or not prompt.Parent then
        FarmRuntime.setCompostStatus("Compost prompt disappeared", true)
        return false, "prompt_changed"
    end

    if not prompt.Enabled then
        pcall(function() prompt.Enabled = true end)
    end

    -- If the bin flipped to collection state while equipping, let the next
    -- worker iteration use the collection branch instead of feeding a seed.
    if prompt.ActionText == "Collect" then
        FarmRuntime.setCompostStatus("Ready to collect worm")
        return false, "prompt_changed"
    end

    -- Let the selected seed replicate into the character/server state before
    -- the prompt is fired.
    task.wait(0.10)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end

    state.lastCompostedSeed = candidate.key
    state.compostAttempts += 1
    FarmRuntime.setCompostStatus("Feeding " .. tostring(candidate.key) .. "…")

    local teleportTicket, teleportErr = FarmRuntime.ensureCompostTeleport(token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not teleportTicket then
        FarmRuntime.setCompostStatus("Compost teleport failed: " .. tostring(teleportErr), true)
        return false, "teleport"
    end
    local ok, err = FarmRuntime.triggerCompostPrompt(prompt, 1, token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not ok then
        FarmRuntime.setCompostStatus("Compost prompt failed: " .. tostring(err), true)
        return false, "feed_fire"
    end

    local waitOk, after = pcall(FarmRuntime.waitForCompostProgressChange, before, COMPOST_CONFIRM_TIMEOUT, prompt, token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    if not waitOk then
        FarmRuntime.setCompostStatus("Feed confirmation failed: " .. tostring(after), true)
        return false, "feed_confirm"
    end
    if after == nil then
        FarmRuntime.setCompostStatus("Feed confirmation timed out", true)
        return false, "feed_timeout"
    end

    local delta = math.max(0, after - before)
    if after < before then
        delta = 0 -- reset belongs to worm collection, not seed contribution
    end

    state.compostConfirmedActions += 1
    state.compostSeedsFed += delta
    state.lastCompostError = nil

    addActivity(
        string.format("%s composted · +%d · %d/%d", candidate.key, delta, after, capacity),
        "success"
    )

    if after >= capacity then
        FarmRuntime.setCompostStatus("Ready to collect worm")
    else
        FarmRuntime.setCompostStatus(string.format("%d/%d · continuing", after, capacity))
    end

    if ui.RefreshCompost then ui.RefreshCompost() end
    if ui.RefreshInventory then ui.RefreshInventory() end
    return true, "fed"
end

function FarmRuntime.scheduleCompostWorker()
    if CompostRuntime.workerScheduled or not state.autoCompostEnabled or not state.running then
        return
    end

    CompostRuntime.workerScheduled = true
    CompostRuntime.workerRevision += 1
    local revision = CompostRuntime.workerRevision
    local generation = state.generation
    local token = FarmRuntime.featureOperationToken("compost")

    task.spawn(function()
        while state.running
            and state.generation == generation
            and state.autoCompostEnabled
            and CompostRuntime.workerRevision == revision do

            local acquired = FarmRuntime.acquireFeatureOperation(token)
            if acquired then
                -- One visit to the compost bin now drains the whole currently
                -- available set of selected seed stacks. The teleport ticket is
                -- intentionally reused between feed steps, so we do not bounce
                -- back to the old position after every single seed.
                local transitionRetries = 0

                while state.running
                    and state.generation == generation
                    and state.autoCompostEnabled
                    and CompostRuntime.workerRevision == revision do

                    local callOk, stepOk, stepReason = pcall(FarmRuntime.compostFeedStep, token)

                    if not FarmRuntime.featureOperationCurrent(token) then break end
                    if not callOk then
                        state.lastCompostError = tostring(stepOk)
                        FarmRuntime.setCompostStatus("Auto Compost error: " .. tostring(stepOk), true)
                        warn("[Farm Assistant V4.1] Auto Compost worker:", stepOk)
                        break
                    end

                    -- Refresh the arbiter watchdog after every bounded compost
                    -- operation. A large inventory batch can legitimately take
                    -- longer than the generic 10-second stale-lock threshold.
                    if FarmRuntime.AutomationRuntime.owner == "compost" then
                        FarmRuntime.AutomationRuntime.since = os.clock()
                    end

                    -- Leaves and Pet Drops remain higher priority. Finish the
                    -- current seed interaction, then immediately return from the
                    -- compost visit so their worker can take over.
                    if FarmRuntime.hasPendingLeafWork()
                        or FarmRuntime.hasPendingPetSeedWork() then
                        break
                    end

                    if stepOk then
                        transitionRetries = 0
                        task.wait(stepReason == "collected" and 0.14 or 0.05)
                        if stepReason == "collected" then
                            FarmRuntime.refreshCompostRefs()
                        end

                        if not FarmRuntime.hasImmediateCompostWork() then
                            break
                        end
                    elseif stepReason == "waiting_collect"
                        or stepReason == "prompt_changed" then

                        -- The bin can take a short moment to flip from feeding
                        -- to Collect (or back after collecting a worm). Stay at
                        -- the same compost position for a few quick rechecks.
                        transitionRetries += 1
                        if transitionRetries > 5 then
                            break
                        end

                        task.wait(0.08)
                        FarmRuntime.refreshCompostRefs()

                        if not FarmRuntime.hasImmediateCompostWork()
                            and stepReason ~= "waiting_collect" then
                            break
                        end
                    else
                        -- No selected seeds left, prompt unavailable, disabled,
                        -- equip failed, etc. End this visit and return once.
                        break
                    end
                end

                -- Return to the original position exactly once after the entire
                -- batch, or earlier when a higher-priority task appears.
                if FarmRuntime.featureOperationCurrent(token) then FarmRuntime.releaseCompostTeleport() end
                FarmRuntime.releaseFeatureOperation(token)
                task.wait(COMPOST_STEP_DELAY)
            else
                -- A higher-priority task is ready or another automation owns
                -- the interaction slot. Make sure no stale compost TP remains.
                if FarmRuntime.featureOperationCurrent(token) then FarmRuntime.releaseCompostTeleport() end
                task.wait(0.08)
            end
        end

        if FarmRuntime.featureOperationCurrent(token) then FarmRuntime.releaseCompostTeleport() end
        FarmRuntime.releaseFeatureOperation(token)
        if CompostRuntime.workerRevision == revision then
            CompostRuntime.workerScheduled = false
        end
    end)
end

function FarmRuntime.setAutoCompost(value, explicitStatus)
    local enabled = value == true
    if state.autoCompostEnabled == enabled then
        if enabled then FarmRuntime.scheduleCompostWorker() end
        return
    end

    state.autoCompostEnabled = enabled
    CompostRuntime.workerRevision += 1
    CompostRuntime.workerScheduled = false

    if enabled then
        state.lastCompostError = nil
        FarmRuntime.setCompostStatus(explicitStatus or "Auto Compost active")
        FarmRuntime.scheduleCompostWorker()
    else
        FarmRuntime.releaseCompostTeleport()
        FarmRuntime.setCompostStatus(explicitStatus or "Auto Compost off")
    end

    if ui.RefreshCompost then ui.RefreshCompost() end
    if ui.RefreshHeader then ui.RefreshHeader() end
    scheduleSettingsSave()
end

function FarmRuntime.initializeCompost()
    local ok, result = pcall(function()
        local Knit = require(ReplicatedStorage.Packages.Knit)
        CompostRuntime.Knit = Knit
        CompostRuntime.DataClient = Knit.GetController("DataClient")
        CompostRuntime.ToolService = Knit.GetService("ToolService")
        CompostRuntime.PlayerPlotService = Knit.GetService("PlayerPlotService")
        CompostRuntime.WormService = Knit.GetService("WormService")
    end)

    if not ok then
        state.lastCompostError = tostring(result)
        FarmRuntime.setCompostStatus("Compost init failed", true)
        return false
    end

    local integrationReady = true
    local function runStage(stage, callback)
        local stageOk, stageErr = pcall(callback)
        if not stageOk then
            integrationReady = false
            state.lastCompostError = stage .. ": " .. tostring(stageErr)
            warn("[FA V4.3][COMPOST] " .. stage .. " unavailable:", stageErr)
        end
        return stageOk
    end

    runStage("SelectedItemID observer", function()
        local selectedProperty = CompostRuntime.ToolService and CompostRuntime.ToolService.SelectedItemID
        if selectedProperty and type(selectedProperty.Observe) == "function" then
            local unsubscribe = selectedProperty:Observe(function(itemId)
                CompostRuntime.selectedItemId = itemId
                if state.running and ui.RefreshCompost then ui.RefreshCompost() end
            end)
            if type(unsubscribe) == "function" then
                CompostRuntime.selectedItemUnsubscribe = unsubscribe
            end
        end
    end)

    runStage("CompostFed signal", function()
        if CompostRuntime.PlayerPlotService and CompostRuntime.PlayerPlotService.CompostFed then
            CompostRuntime.connections[#CompostRuntime.connections + 1] =
                CompostRuntime.PlayerPlotService.CompostFed:Connect(function(position)
                    if not state.running or not FarmRuntime.compostPositionMatches(position) then return end
                    local progress = FarmRuntime.getCompostProgress()
                    CompostRuntime.lastProgress = progress
                    if ui.RefreshCompost then ui.RefreshCompost() end
                end)
        end
    end)

    runStage("WormGranted signal", function()
        if CompostRuntime.WormService and CompostRuntime.WormService.WormGranted then
            CompostRuntime.connections[#CompostRuntime.connections + 1] =
                CompostRuntime.WormService.WormGranted:Connect(function(worm, rollData)
                    if not state.running then return end

                    local requestedAt = CompostRuntime.lastCollectRequestClock
                    local belongsToAutoCompost = requestedAt ~= nil and os.clock() - requestedAt <= 5
                    if not belongsToAutoCompost then
                        if ui.RefreshCompost then ui.RefreshCompost() end
                        return
                    end
                    CompostRuntime.lastCollectRequestClock = nil

                    state.wormsGranted += 1
                    state.compostCycles += 1
                    pcall(AroynWeb.CaptureWorm, worm, rollData)

                    if type(worm) == "table" then
                        local wormName = tostring(worm.wormType or "Worm")
                        if worm.mult ~= nil then
                            wormName = wormName .. " " .. tostring(worm.mult) .. "x"
                        end
                        state.lastWorm = wormName
                    else
                        state.lastWorm = "Worm"
                    end

                    state.lastCompostError = nil
                    FarmRuntime.setCompostStatus("Worm collected · " .. tostring(state.lastWorm))
                    addActivity("Compost reward: " .. tostring(state.lastWorm), "success")

                    if ui.Toast then
                        ui.Toast("Worm: " .. tostring(state.lastWorm), "accent")
                    end
                    if ui.RefreshCompost then ui.RefreshCompost() end
                end)
        end
    end)

    runStage("Compost references", FarmRuntime.refreshCompostRefs)
    if state.autoCompostEnabled then
        FarmRuntime.scheduleCompostWorker()
    end
    if state.autoCollectLeaves then
        FarmRuntime.scanLeaves()
        FarmRuntime.scheduleLeafWorker()
    end

    if not integrationReady then
        pcall(FarmRuntime.setCompostStatus, "Compost partially unavailable", true)
    end
    return integrationReady
end

function FarmRuntime.destroyCompost()
    CompostRuntime.workerRevision += 1
    CompostRuntime.workerScheduled = false
    FarmRuntime.releaseCompostTeleport()

    if CompostRuntime.selectedItemUnsubscribe then
        pcall(CompostRuntime.selectedItemUnsubscribe)
        CompostRuntime.selectedItemUnsubscribe = nil
    end

    for i = #CompostRuntime.connections, 1, -1 do
        safeDisconnect(CompostRuntime.connections[i])
        CompostRuntime.connections[i] = nil
    end
end

function FarmRuntime.disconnectList(list)
    for i = #list, 1, -1 do
        safeDisconnect(list[i])
        list[i] = nil
    end
end

function FarmRuntime.treeIdFromInstance(tree)
    if not tree then return nil end
    return tree.Name:match("^PlotTree_(.+)$")
end

function FarmRuntime.findFruitPrompt(fruit)
    if not fruit or not fruit.Parent then return nil end
    local direct = fruit:FindFirstChildOfClass("ProximityPrompt")
    if direct then return direct end
    for _, descendant in ipairs(fruit:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") then
            return descendant
        end
    end
    return nil
end

local FRUIT_MUTATION_MULT_FALLBACK = {
    Dewy = 2,
    Shocked = 2.5,
    Dusty = 3,
    Frosted = 3,
    Charged = 7.5,
    Infested = 5,
    Radioactive = 5,
    Slimy = 10,
    Golden = 25,
    Scaled = 50,
    Ivory = 75,
    Cosmic = 100,
    Huge = 1,
}

function FarmRuntime.parseFruitMutationList(value)
    local result = {}
    local seen = {}

    local function push(name)
        if type(name) ~= "string" then return end
        name = trim(name)
        if name == "" or seen[name] then return end
        seen[name] = true
        result[#result + 1] = name
    end

    if type(value) == "string" then
        for name in value:gmatch("[^,]+") do
            push(name)
        end
    elseif type(value) == "table" then
        for _, name in pairs(value) do
            push(name)
        end
    end

    if MutationConfig and type(MutationConfig.Sanitize) == "function" then
        local ok, sanitized = pcall(MutationConfig.Sanitize, result)
        if ok and type(sanitized) == "table" then
            return sanitized
        end
    end

    return result
end

function FarmRuntime.fruitMutationProduct(mutations)
    if MutationConfig and type(MutationConfig.ProductMult) == "function" then
        local ok, product = pcall(MutationConfig.ProductMult, mutations)
        if ok and type(product) == "number" then
            return product
        end
    end

    local product = 1
    for _, mutation in ipairs(mutations or {}) do
        product *= FRUIT_MUTATION_MULT_FALLBACK[mutation] or 1
    end
    return product
end

function FarmRuntime.fruitEffectiveMultiplier(treeMultiplier, sizeMult)
    local treeMult = tonumber(treeMultiplier) or 1
    local fruitSizeMult = tonumber(sizeMult) or 1

    if SeedConfig and type(SeedConfig.FruitSize) == "function" then
        local ok, value = pcall(SeedConfig.FruitSize, treeMult, fruitSizeMult)
        if ok and type(value) == "number" then
            return value
        end
    end

    return math.floor(treeMult * fruitSizeMult * 100) / 100
end

function FarmRuntime.fruitNameForSeed(seedType)
    if type(seedType) ~= "string" then return "Fruit" end

    if SeedConfig then
        if type(SeedConfig.GetSeed) == "function" then
            local ok, seed = pcall(SeedConfig.GetSeed, seedType)
            if ok and type(seed) == "table" and type(seed.fruitName) == "string" then
                return seed.fruitName
            end
        end

        local seed = type(SeedConfig.Seeds) == "table" and SeedConfig.Seeds[seedType] or nil
        if type(seed) == "table" and type(seed.fruitName) == "string" then
            return seed.fruitName
        end
    end

    return seedType == "Oak" and "Acorn"
        or (seedType == "Pine" and "Pinecone")
        or (seedType .. (seedType:find("Fruit", 1, true) and "" or " Fruit"))
end

function FarmRuntime.hasLiveFruitPricing()
    return SeedConfig
        and type(SeedConfig.FruitSize) == "function"
        and (
            type(SeedConfig.CalcPlotFruitValue) == "function"
            or type(SeedConfig.Seeds) == "table"
        )
end

function FarmRuntime.liveFruitDisplay(data)
    if not data or not data.instance or not data.instance.Parent then
        return nil
    end

    local treeData = data.treeData
    local seedType = treeData and treeData.seedType or nil
    local treeMultiplier = treeData and treeData.multiplier or 1

    -- Read directly from the replicated FruitSpawn each time so the UI stays
    -- correct when a slot is reused immediately after collection.
    local sizeMult = tonumber(data.instance:GetAttribute("FruitSizeMult")) or tonumber(data.sizeMult) or 1
    local mutationRaw = data.instance:GetAttribute("FruitMutations")
    if mutationRaw == nil then mutationRaw = data.mutations end
    local mutations = FarmRuntime.parseFruitMutationList(mutationRaw)
    local effectiveMultiplier = FarmRuntime.fruitEffectiveMultiplier(treeMultiplier, sizeMult)

    local sellValue = nil
    if type(seedType) == "string" then
        local baseValue = nil

        if SeedConfig and type(SeedConfig.CalcPlotFruitValue) == "function" then
            local ok, value = pcall(SeedConfig.CalcPlotFruitValue, seedType, effectiveMultiplier)
            if ok and type(value) == "number" then
                baseValue = value
            end
        end

        if baseValue == nil and SeedConfig and type(SeedConfig.Seeds) == "table" then
            local seed = SeedConfig.Seeds[seedType]
            if type(seed) == "table" and type(seed.sellPrice) == "number" then
                baseValue = math.max(1, math.floor(seed.sellPrice * effectiveMultiplier / 10))
            end
        end

        if baseValue ~= nil then
            sellValue = math.floor(baseValue * FarmRuntime.fruitMutationProduct(mutations))
        end
    end

    return {
        spawnIndex = tonumber(data.instance:GetAttribute("SpawnIndex")) or tonumber(data.spawnIndex),
        seedType = seedType,
        fruitName = FarmRuntime.fruitNameForSeed(seedType),
        sizeMult = sizeMult,
        multiplier = effectiveMultiplier,
        mutations = mutations,
        mutationText = #mutations > 0 and table.concat(mutations, ", ") or "No mutations",
        sellValue = sellValue,
        locked = data.instance:GetAttribute("FruitLocked") == true,
        waxed = data.instance:GetAttribute("FruitWaxed") == true,
        ready = FarmRuntime.fruitIsReady(data),
    }
end

function FarmRuntime.fruitIsReady(data)
    if not data or not data.instance or not data.instance.Parent then
        return false
    end
    if data.instance:GetAttribute("FruitLocked") == true then
        return false
    end
    local prompt = FarmRuntime.findFruitPrompt(data.instance)
    if not prompt then return false end
    local ok, enabled = pcall(function() return prompt.Enabled end)
    if ok and enabled == false then return false end
    return true
end

function FarmRuntime.refreshTreeRecord(data)
    if not data or not data.instance or not data.instance.Parent then return end
    local tree = data.instance
    data.seedType = tree:GetAttribute("SeedType")
    data.multiplier = tonumber(tree:GetAttribute("Multiplier"))
    data.mutations = tree:GetAttribute("Mutations")
    data.isDead = tree:GetAttribute("IsDead") == true

    local total, ready = 0, 0
    for fruit, fruitData in pairs(data.fruits) do
        if fruit and fruit.Parent and fruit:IsDescendantOf(tree) then
            total += 1
            if FarmRuntime.fruitIsReady(fruitData) then ready += 1 end
        else
            data.fruits[fruit] = nil
        end
    end
    data.fruitCount = total
    data.readyFruitCount = ready

    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.UpdatePipeline then ui.UpdatePipeline() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.fruitLogicalKey(data)
    if not data or not data.treeData then return nil end
    local index = data.instance and data.instance:GetAttribute("SpawnIndex")
    if index == nil then return nil end
    return tostring(data.treeData.id or "?") .. ":" .. tostring(index)
end

function FarmRuntime.invalidateCollectQueue()
    collectRevision += 1
    collectWorkerScheduled = false
    for _, entry in ipairs(collectQueue) do
        if entry.fruit then queuedFruits[entry.fruit] = nil end
    end
    table.clear(collectQueue)
    FarmRuntime.releaseFruitTeleportBatch()
    if state.running and ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.reacquireFruitSpawn(treeData, spawnIndex)
    local tree = treeData and treeData.instance
    if not tree or not tree.Parent or spawnIndex == nil then
        return nil, nil
    end

    for _, descendant in ipairs(tree:GetDescendants()) do
        if descendant:GetAttribute("SpawnIndex") == spawnIndex
            and descendant:GetAttribute("FruitLocked") ~= true then

            local prompt = FarmRuntime.findFruitPrompt(descendant)
            if prompt and prompt.Parent then
                return descendant, prompt
            end
        end
    end

    return nil, nil
end

function FarmRuntime.collectEligibility(entry)
    if not state.running then return false, "stopped" end
    if not state.autoCollectFruits then return false, "disabled" end
    if not ownPlot or ownPlot ~= GameState.ownPlot or not ownPlot.Parent then return false, "plot" end

    local fruit = entry.fruit
    local treeData = entry.treeData
    if not fruit or not fruit.Parent or not treeData or not treeData.instance or not treeData.instance.Parent then
        return false, "gone"
    end
    if not fruit:IsDescendantOf(treeData.instance) or not treeData.instance:IsDescendantOf(ownPlot) then
        return false, "ownership"
    end
    if claimedFruits[fruit] then return false, "claimed" end
    if fruit:GetAttribute("FruitLocked") == true then return false, "locked" end

    if state.autoCollectFruits and FarmRuntime.tpFruitCooldown then
        local retryAt = FarmRuntime.tpFruitCooldown[fruit]
        if retryAt and retryAt > os.clock() then return false, "cooldown" end
        if retryAt then FarmRuntime.tpFruitCooldown[fruit] = nil end
    end

    local prompt = FarmRuntime.findFruitPrompt(fruit)
    if not prompt or not prompt.Parent or not prompt:IsDescendantOf(fruit) then
        -- All-fruit collection can reacquire the FruitSpawn by
        -- treeId + SpawnIndex on the retry pass.
        if state.autoCollectFruits then
            entry.prompt = nil
            return true
        end
        return false, "prompt"
    end
    -- Tested in-game: FruitSpawn prompts can be triggered remotely even while
    -- Enabled=false, so collection does not depend on the local hover state.
    entry.prompt = prompt
    return true
end

function FarmRuntime.findFruitTeleportCFrame(fruit, prompt)
    if not fruit or not fruit.Parent then return nil end

    if prompt and prompt.Parent then
        local parent = prompt.Parent
        if parent:IsA("Attachment") then
            return parent.WorldCFrame
        end
        if parent:IsA("BasePart") then
            return parent.CFrame
        end

        local promptPart = parent:FindFirstAncestorWhichIsA("BasePart")
        if promptPart then return promptPart.CFrame end
    end

    if fruit:IsA("BasePart") then
        return fruit.CFrame
    end
    local part = fruit:FindFirstChildWhichIsA("BasePart", true)
    if part then return part.CFrame end

    local ok, pivot = pcall(function() return fruit:GetPivot() end)
    return ok and pivot or nil
end

function FarmRuntime.beginFruitTeleportBatch()
    local existing = FarmRuntime.fruitTeleportBatchTicket
    if existing and existing.root and existing.root.Parent and existing.cframe then
        return existing
    end
    FarmRuntime.fruitTeleportBatchTicket = nil

    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then
        return nil, "HumanoidRootPart unavailable"
    end

    local deadline = os.clock() + 1.5
    while state.running and FarmRuntime.teleportOwner and FarmRuntime.teleportOwner ~= "fruit" and os.clock() < deadline do
        task.wait(0.04)
    end
    if FarmRuntime.teleportOwner and FarmRuntime.teleportOwner ~= "fruit" then
        return nil, "teleport busy"
    end

    local ticket = {
        root = root,
        owner = "fruit",
        cframe = root.CFrame,
        linearVelocity = root.AssemblyLinearVelocity,
        angularVelocity = root.AssemblyAngularVelocity,
        anchored = root.Anchored,
    }

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        ticket.humanoid = humanoid
        ticket.autoRotate = humanoid.AutoRotate
    end

    FarmRuntime.teleportOwner = ticket.owner
    FarmRuntime.fruitTeleportBatchTicket = ticket

    local ok, err = pcall(function()
        -- Keep the character suspended for the entire sweep. We only restore
        -- the original position after the last collectable fruit is handled.
        root.Anchored = true
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if humanoid then humanoid.AutoRotate = false end
    end)
    if not ok then
        FarmRuntime.fruitTeleportBatchTicket = nil
        if FarmRuntime.teleportOwner == ticket.owner then FarmRuntime.teleportOwner = nil end
        return nil, tostring(err)
    end

    return ticket
end

function FarmRuntime.moveFruitTeleport(ticket, entry)
    if not ticket or not ticket.root or not ticket.root.Parent then
        return false, "fruit teleport batch unavailable"
    end
    if not entry or not entry.fruit or not entry.fruit.Parent then
        return false, "fruit unavailable"
    end

    local targetCFrame = FarmRuntime.findFruitTeleportCFrame(entry.fruit, entry.prompt)
    if not targetCFrame then
        return false, "fruit target unavailable"
    end

    local ok, err = pcall(function()
        local targetPosition = targetCFrame.Position
        -- Stay close enough for MaxActivationDistance while remaining above /
        -- slightly behind the fruit instead of dropping onto tree geometry.
        local hoverPosition = (targetCFrame * CFrame.new(0, 1.8, 1.1)).Position
        ticket.root.CFrame = CFrame.new(hoverPosition, targetPosition)
        ticket.root.AssemblyLinearVelocity = Vector3.zero
        ticket.root.AssemblyAngularVelocity = Vector3.zero
        ticket.root.Anchored = true
    end)
    if not ok then return false, tostring(err) end

    state.tpCollectTeleports += 1
    state.lastTpCollectError = nil

    -- A distant fruit can replicate before its ProximityPrompt does. After
    -- arriving, allow a short bounded window for the prompt to appear.
    local deadline = os.clock() + 0.85
    repeat
        if not state.running or not state.autoCollectFruits or not entry.fruit.Parent then
            return false, "cancelled"
        end

        local prompt = FarmRuntime.findFruitPrompt(entry.fruit)
        if prompt and prompt.Parent then
            -- Fruit prompts are normally toggled by the game's local
            -- cursor/hover controller. Legacy teleport helper remains unused by instant pickup.
            pcall(function()
                prompt.Enabled = true
                prompt.HoldDuration = 0
                prompt.MaxActivationDistance = math.huge
                prompt.RequiresLineOfSight = false
            end)
            entry.prompt = prompt
            return true, prompt
        end
        task.wait(0.05)
    until os.clock() >= deadline

    FarmRuntime.tpFruitCooldown = FarmRuntime.tpFruitCooldown or setmetatable({}, { __mode = "k" })
    FarmRuntime.tpFruitCooldown[entry.fruit] = os.clock() + 2.0
    return false, "prompt unavailable after teleport"
end

function FarmRuntime.releaseFruitTeleportBatch()
    local ticket = FarmRuntime.fruitTeleportBatchTicket
    FarmRuntime.fruitTeleportBatchTicket = nil

    if ticket and ticket.root and ticket.root.Parent and ticket.cframe then
        pcall(function()
            ticket.root.CFrame = ticket.cframe
            ticket.root.AssemblyLinearVelocity = Vector3.zero
            ticket.root.AssemblyAngularVelocity = Vector3.zero
            ticket.root.Anchored = ticket.anchored == true

            if ticket.humanoid and ticket.humanoid.Parent and ticket.autoRotate ~= nil then
                ticket.humanoid.AutoRotate = ticket.autoRotate
            end

            if ticket.root.Anchored ~= true then
                ticket.root.AssemblyLinearVelocity = ticket.linearVelocity or Vector3.zero
                ticket.root.AssemblyAngularVelocity = ticket.angularVelocity or Vector3.zero
            end
        end)
    end

    if ticket and FarmRuntime.teleportOwner == ticket.owner then
        FarmRuntime.teleportOwner = nil
    elseif FarmRuntime.teleportOwner == "fruit" then
        FarmRuntime.teleportOwner = nil
    end
end

function FarmRuntime.runInstantFruitBurst(revision, generation)
    local batch = {}
    local firePrompt = fireproximityprompt

    if type(firePrompt) ~= "function" then
        state.collectErrors += 1
        state.lastAutoCollectError = "fireproximityprompt unavailable"
        state.lastTpCollectError = "fireproximityprompt unavailable"
        addActivity("Instant fruit prompt unavailable", "error")
        return
    end

    -- First pass: trigger the whole current queue as a fast burst.
    while #collectQueue > 0
        and state.running
        and state.autoCollectFruits
        and state.generation == generation
        and collectRevision == revision do

        local entry = table.remove(collectQueue, 1)
        queuedFruits[entry.fruit] = nil

        local eligible = FarmRuntime.collectEligibility(entry)
        if eligible then
            if not entry.prompt or not entry.prompt.Parent then
                local spawnIndex = entry.fruit and entry.fruit:GetAttribute("SpawnIndex")
                local reacquiredFruit, reacquiredPrompt =
                    FarmRuntime.reacquireFruitSpawn(entry.treeData, spawnIndex)

                if reacquiredFruit and reacquiredPrompt then
                    entry.fruit = reacquiredFruit
                    entry.prompt = reacquiredPrompt
                else
                    eligible = false
                end
            end
        end

        if eligible
            and entry.prompt
            and entry.prompt.Parent
            and not claimedFruits[entry.fruit] then

            claimedFruits[entry.fruit] = true
            state.collectAttempts += 1

            local logicalKey = FarmRuntime.fruitLogicalKey(entry)
            local ok, err = pcall(firePrompt, entry.prompt)

            if ok then
                state.collectTriggered += 1
                state.tpCollectTeleports += 1 -- legacy counter now means instant fires
                state.lastTpCollectError = nil

                if logicalKey then
                    local queue = pendingFruitTriggers[logicalKey] or {}
                    pendingFruitTriggers[logicalKey] = queue
                    queue[#queue + 1] = {
                        createdClock = os.clock(),
                        fruit = entry.fruit,
                    }
                end

                batch[#batch + 1] = {
                    entry = entry,
                    logicalKey = logicalKey,
                }
            else
                claimedFruits[entry.fruit] = nil
                state.collectErrors += 1
                state.lastAutoCollectError = tostring(err)
                state.lastTpCollectError = tostring(err)
            end
        end

        FarmRuntime.refreshTreeRecord(entry.treeData)

        -- Proven reliable at four FruitSpawns per tree while still effectively
        -- instant to the player.
        task.wait(0.010)
    end

    local function confirmed(item)
        local entry = item.entry
        if not entry or not entry.fruit or not entry.fruit.Parent then
            return true
        end
        if item.logicalKey and pendingFruitTriggers[item.logicalKey] == nil then
            return true
        end
        return false
    end

    -- Give the server a short window to acknowledge the burst.
    local firstDeadline = os.clock() + 0.70
    while state.running
        and state.autoCollectFruits
        and state.generation == generation
        and collectRevision == revision
        and os.clock() < firstDeadline do

        local allConfirmed = true
        for _, item in ipairs(batch) do
            if not confirmed(item) then
                allConfirmed = false
                break
            end
        end
        if allConfirmed then break end
        task.wait(0.03)
    end

    -- Retry only dropped/unconfirmed FruitSpawns. Reacquire by SpawnIndex so a
    -- replaced prompt/object does not poison the retry.
    local retried = {}
    for _, item in ipairs(batch) do
        if not confirmed(item)
            and state.running
            and state.autoCollectFruits
            and state.generation == generation
            and collectRevision == revision then

            local entry = item.entry
            local spawnIndex = entry.fruit and entry.fruit:GetAttribute("SpawnIndex")
            local retryFruit, retryPrompt =
                FarmRuntime.reacquireFruitSpawn(entry.treeData, spawnIndex)

            if retryFruit and retryPrompt then
                entry.fruit = retryFruit
                entry.prompt = retryPrompt
                claimedFruits[retryFruit] = true
                state.collectAttempts += 1

                local ok, err = pcall(firePrompt, retryPrompt)
                if ok then
                    state.collectTriggered += 1
                    state.tpCollectTeleports += 1
                    retried[#retried + 1] = item
                else
                    state.collectErrors += 1
                    state.lastAutoCollectError = tostring(err)
                    state.lastTpCollectError = tostring(err)
                end
            end

            task.wait(0.025)
        end
    end

    if #retried > 0 then
        local retryDeadline = os.clock() + 0.90
        while state.running
            and state.autoCollectFruits
            and state.generation == generation
            and collectRevision == revision
            and os.clock() < retryDeadline do

            local allConfirmed = true
            for _, item in ipairs(retried) do
                if not confirmed(item) then
                    allConfirmed = false
                    break
                end
            end
            if allConfirmed then break end
            task.wait(0.03)
        end
    end

    for _, item in ipairs(batch) do
        if not confirmed(item) then
            local entry = item.entry
            if entry and entry.fruit and entry.fruit.Parent then
                claimedFruits[entry.fruit] = nil
                FarmRuntime.tpFruitCooldown =
                    FarmRuntime.tpFruitCooldown
                    or setmetatable({}, { __mode = "k" })
                FarmRuntime.tpFruitCooldown[entry.fruit] = os.clock() + 0.8
            end
        end
    end

    if ui.RefreshSession then ui.RefreshSession() end
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.scheduleCollectWorker()
    if collectWorkerScheduled
        or #collectQueue == 0
        or not state.autoCollectFruits then
        return
    end

    collectWorkerScheduled = true
    local revision = collectRevision
    local generation = state.generation

    task.defer(function()
        if not state.running
            or state.generation ~= generation
            or collectRevision ~= revision
            or not state.autoCollectFruits then
            collectWorkerScheduled = false
            return
        end

        if state.autoCollectFruits then
            FarmRuntime.runInstantFruitBurst(revision, generation)
            collectWorkerScheduled = false

            if state.running
                and state.autoCollectFruits
                and state.generation == generation
                and collectRevision == revision then
                -- Pick up newly appeared FruitSpawns and retry cooldown-expired
                -- misses on future sweeps. Market-needed fruits are filtered by
                -- enqueueFruit before they enter this queue.
                FarmRuntime.queueReadyFruits()
            end
            return
        end

        -- Normal Auto Collect keeps the original conservative behavior: only
        -- prompts that the game currently exposes as enabled are triggered.
        local entry = table.remove(collectQueue, 1)
        if not entry then
            collectWorkerScheduled = false
            return
        end

        queuedFruits[entry.fruit] = nil
        local eligible = FarmRuntime.collectEligibility(entry)
        local invoked = false

        if eligible then
            local firePrompt = fireproximityprompt
            if type(firePrompt) ~= "function" then
                state.collectErrors += 1
                state.lastAutoCollectError = "fireproximityprompt unavailable"
                addActivity("Fruit prompt unavailable", "error")
            elseif entry.prompt
                and entry.prompt.Parent
                and not claimedFruits[entry.fruit] then

                claimedFruits[entry.fruit] = true
                state.collectAttempts += 1
                invoked = true

                local logicalKey = FarmRuntime.fruitLogicalKey(entry)
                local ok, err = pcall(firePrompt, entry.prompt)

                if ok then
                    state.collectTriggered += 1
                    if logicalKey then
                        local queue = pendingFruitTriggers[logicalKey] or {}
                        pendingFruitTriggers[logicalKey] = queue
                        queue[#queue + 1] = {
                            createdClock = os.clock(),
                            fruit = entry.fruit,
                        }
                    end
                    addActivity(
                        (entry.treeData.seedType or "Fruit") .. " fruit trigger sent",
                        "success"
                    )
                else
                    claimedFruits[entry.fruit] = nil
                    state.collectErrors += 1
                    state.lastAutoCollectError = tostring(err)
                    addActivity("Fruit prompt error", "error")
                end
            end
        end

        FarmRuntime.refreshTreeRecord(entry.treeData)
        if ui.RefreshSession then ui.RefreshSession() end
        if ui.RefreshHeader then ui.RefreshHeader() end
        if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end

        collectWorkerScheduled = false

        if state.running
            and state.generation == generation
            and collectRevision == revision
            and state.autoCollectFruits
            and #collectQueue > 0 then

            task.delay(invoked and COLLECT_RATE_LIMIT or 0.03, function()
                if state.running
                    and state.generation == generation
                    and collectRevision == revision
                    and state.autoCollectFruits then
                    FarmRuntime.scheduleCollectWorker()
                end
            end)
        end
    end)
end

function FarmRuntime.enqueueFruit(data)
    if not data or not data.instance or claimedFruits[data.instance] or queuedFruits[data.instance] then return end

    -- Collect All mode intentionally does not reserve Market-needed fruit on
    -- the tree. Everything is picked into inventory; Farmers Market then uses
    -- matching inventory fruit first.

    local entry = { fruit = data.instance, treeData = data.treeData, sequence = collectSequence + 1 }
    local eligible = FarmRuntime.collectEligibility(entry)
    if not eligible then return end

    collectSequence += 1
    entry.sequence = collectSequence
    queuedFruits[data.instance] = true
    collectQueue[#collectQueue + 1] = entry
    FarmRuntime.scheduleCollectWorker()
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.refreshFruitData(data)
    if not data or not data.instance or not data.instance.Parent then return end
    data.spawnIndex = data.instance:GetAttribute("SpawnIndex")
    data.locked = data.instance:GetAttribute("FruitLocked") == true
    data.mutations = data.instance:GetAttribute("FruitMutations")
    data.sizeMult = tonumber(data.instance:GetAttribute("FruitSizeMult"))
    local prompt = FarmRuntime.findFruitPrompt(data.instance)
    if prompt ~= data.prompt then
        if data.promptConnection then
            safeDisconnect(data.promptConnection)
            data.promptConnection = nil
        end
        data.prompt = prompt
        if prompt then
            data.promptConnection = prompt:GetPropertyChangedSignal("Enabled"):Connect(function()
                if state.running and data.instance and data.instance.Parent then
                    FarmRuntime.refreshFruitData(data)
                end
            end)
            data.connections[#data.connections + 1] = data.promptConnection
        end
    end

    if state.autoCollectFruits then
        if data.instance:GetAttribute("FruitLocked") ~= true then
            FarmRuntime.enqueueFruit(data)
        end
    end
    FarmRuntime.refreshTreeRecord(data.treeData)
end

function FarmRuntime.detachFruit(fruit)
    local data = fruitDataByInstance[fruit]
    if not data then return end
    FarmRuntime.disconnectList(data.connections)
    if data.treeData then data.treeData.fruits[fruit] = nil end
    queuedFruits[fruit] = nil
    fruitDataByInstance[fruit] = nil
end

function FarmRuntime.attachFruit(fruit, treeData)
    if not fruit or not fruit.Parent or fruitDataByInstance[fruit] then return end
    if fruit:GetAttribute("SpawnIndex") == nil then return end

    local data = {
        instance = fruit,
        treeData = treeData,
        connections = {},
    }
    fruitDataByInstance[fruit] = data
    treeData.fruits[fruit] = data

    local function connect(signal, fn)
        data.connections[#data.connections + 1] = signal:Connect(fn)
    end

    connect(fruit:GetAttributeChangedSignal("FruitLocked"), function()
        if state.running then FarmRuntime.refreshFruitData(data) end
    end)
    connect(fruit:GetAttributeChangedSignal("FruitMutations"), function()
        if state.running then FarmRuntime.refreshFruitData(data) end
    end)
    connect(fruit:GetAttributeChangedSignal("FruitSizeMult"), function()
        if state.running then FarmRuntime.refreshFruitData(data) end
    end)
    connect(fruit.DescendantAdded, function(descendant)
        if state.running and descendant:IsA("ProximityPrompt") then
            task.defer(function()
                if state.running and fruit.Parent then FarmRuntime.refreshFruitData(data) end
            end)
        end
    end)
    connect(fruit.DescendantRemoving, function(descendant)
        if state.running and descendant:IsA("ProximityPrompt") then
            task.defer(function()
                if state.running and fruit.Parent then FarmRuntime.refreshFruitData(data) end
            end)
        end
    end)

    FarmRuntime.refreshFruitData(data)
end

function FarmRuntime.findFruitOwnerFromDescendant(descendant, tree)
    local current = descendant
    while current and current ~= tree do
        if current:GetAttribute("SpawnIndex") ~= nil then
            return current
        end
        current = current.Parent
    end
    return nil
end

function FarmRuntime.detachTree(tree)
    local data = treeDataByInstance[tree]
    if not data then return end
    FarmRuntime.disconnectList(data.connections)
    for fruit in pairs(data.fruits) do
        FarmRuntime.detachFruit(fruit)
    end
    GameState.trees[tree] = nil
    if data.id and GameState.treesById[data.id] == data then
        GameState.treesById[data.id] = nil
    end
    treeDataByInstance[tree] = nil
    if selectedTreeId == data.id then selectedTreeId = nil end
end

function FarmRuntime.attachTree(tree)
    if not tree or not tree.Parent or treeDataByInstance[tree] then return end
    local id = FarmRuntime.treeIdFromInstance(tree)
    if not id then return end

    local data = {
        instance = tree,
        id = id,
        connections = {},
        fruits = setmetatable({}, { __mode = "k" }),
        fruitCount = 0,
        readyFruitCount = 0,
    }
    treeDataByInstance[tree] = data
    GameState.trees[tree] = data
    GameState.treesById[id] = data
    selectedTreeId = selectedTreeId or id

    local function connect(signal, fn)
        data.connections[#data.connections + 1] = signal:Connect(fn)
    end
    for _, attributeName in ipairs({ "SeedType", "Multiplier", "Mutations", "IsDead" }) do
        connect(tree:GetAttributeChangedSignal(attributeName), function()
            if state.running then FarmRuntime.refreshTreeRecord(data) end
        end)
    end
    connect(tree.DescendantAdded, function(descendant)
        if not state.running then return end
        local fruit = descendant:GetAttribute("SpawnIndex") ~= nil and descendant or FarmRuntime.findFruitOwnerFromDescendant(descendant, tree)
        if fruit then
            FarmRuntime.attachFruit(fruit, data)
            return
        end
        -- Replication can construct a fruit before its attributes are visible. Recheck
        -- a couple of bounded times; this is not a polling loop.
        for _, delaySeconds in ipairs({ 0.05, 0.20 }) do
            task.delay(delaySeconds, function()
                if not state.running or not tree.Parent or not descendant.Parent then return end
                local lateFruit = descendant:GetAttribute("SpawnIndex") ~= nil and descendant or FarmRuntime.findFruitOwnerFromDescendant(descendant, tree)
                if lateFruit then FarmRuntime.attachFruit(lateFruit, data) end
            end)
        end
    end)
    connect(tree.DescendantRemoving, function(descendant)
        if not state.running then return end
        if fruitDataByInstance[descendant] then
            FarmRuntime.detachFruit(descendant)
            task.defer(function()
                if state.running then FarmRuntime.refreshTreeRecord(data) end
            end)
        else
            local fruit = FarmRuntime.findFruitOwnerFromDescendant(descendant, tree)
            if fruit and fruitDataByInstance[fruit] then
                task.defer(function()
                    if state.running and fruit.Parent then FarmRuntime.refreshFruitData(fruitDataByInstance[fruit]) end
                end)
            end
        end
    end)

    for _, descendant in ipairs(tree:GetDescendants()) do
        if descendant:GetAttribute("SpawnIndex") ~= nil then
            FarmRuntime.attachFruit(descendant, data)
        end
    end
    FarmRuntime.refreshTreeRecord(data)
    addActivity((data.seedType or "Tree") .. " tree detected", "normal")
end


function FarmRuntime.isPetSeedFind(instance)
    return instance ~= nil
        and instance.Parent ~= nil
        and type(instance.Name) == "string"
        and instance.Name:match("^PlotFind_") ~= nil
end

function FarmRuntime.findPetSeedPrompt(plotFind)
    if not plotFind or not plotFind.Parent then return nil end

    local exact = plotFind:FindFirstChild("FindPrompt", true)
    if exact and exact:IsA("ProximityPrompt") then
        return exact
    end

    for _, descendant in ipairs(plotFind:GetDescendants()) do
        if descendant:IsA("ProximityPrompt") and descendant.Name == "FindPrompt" then
            return descendant
        end
    end
    return nil
end

function FarmRuntime.inferPetSeedName(plotFind)
    if not plotFind then return nil end

    local attribute = plotFind:GetAttribute("SeedType")
    if type(attribute) == "string" and attribute ~= "" then
        return attribute
    end

    for _, child in ipairs(plotFind:GetChildren()) do
        if child.Name:match("Seed$") then
            return child.Name:gsub("Seed$", "")
        end
    end

    for _, descendant in ipairs(plotFind:GetDescendants()) do
        if (descendant:IsA("Model") or descendant:IsA("Folder")) and descendant.Name:match("Seed$") then
            return descendant.Name:gsub("Seed$", "")
        end
    end

    return nil
end

function FarmRuntime.inferPetDropName(plotFind, prompt)
    if not plotFind then return nil end

    prompt = prompt or FarmRuntime.findPetSeedPrompt(plotFind)
    if prompt and prompt.Parent then
        local ok, objectText = pcall(function() return prompt.ObjectText end)
        objectText = ok and trim(tostring(objectText or "")) or ""
        if objectText ~= "" then
            return objectText
        end
    end

    local kind = plotFind:GetAttribute("FindKind")
    if type(kind) == "string" and trim(kind) ~= "" then
        return trim(kind)
    end

    return FarmRuntime.inferPetSeedName(plotFind) or "Pet Drop"
end

function FarmRuntime.getPetSeedCount()
    if not ownPlot or not ownPlot.Parent then return 0 end
    local count = 0
    for _, child in ipairs(ownPlot:GetChildren()) do
        if FarmRuntime.isPetSeedFind(child) then
            count += 1
        end
    end
    return count
end

function FarmRuntime.setPetSeedStatus(textValue, isError)
    state.petSeedStatus = tostring(textValue or "Idle")
    if isError then
        state.lastPetSeedError = state.petSeedStatus
    end
    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.findPetSeedTarget(plotFind, prompt)
    if prompt and prompt.Parent and prompt.Parent:IsA("BasePart") then
        return prompt.Parent
    end

    local base = plotFind and plotFind:FindFirstChild("Base", true)
    if base and base:IsA("BasePart") then
        return base
    end

    if plotFind then
        return plotFind:FindFirstChildWhichIsA("BasePart", true)
    end
    return nil
end

function FarmRuntime.beginPetSeedTeleport(plotFind, prompt, token)
    if not FarmRuntime.featureOperationCurrent(token) then return nil, "cancelled" end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then
        return nil, "HumanoidRootPart unavailable"
    end

    local deadline = os.clock() + 1.5
    while FarmRuntime.featureOperationCurrent(token) and FarmRuntime.teleportOwner and os.clock() < deadline do
        task.wait(0.04)
    end
    if not FarmRuntime.featureOperationCurrent(token) then return nil, "cancelled" end
    if FarmRuntime.teleportOwner then
        return nil, "teleport busy"
    end

    local target = FarmRuntime.findPetSeedTarget(plotFind, prompt)
    if not target or not target.Parent then
        return nil, "pet drop target part unavailable"
    end

    local ticket = { root = root, owner = "pet-seed" }
    FarmRuntime.teleportOwner = ticket.owner
    local ok, err = pcall(function()
        ticket.cframe = root.CFrame
        ticket.linearVelocity = root.AssemblyLinearVelocity
        ticket.angularVelocity = root.AssemblyAngularVelocity

        -- Match the isolated Pet Drop tester: stand directly above Base.
        -- This consistently settled around 2 studs from the prompt even when
        -- teleporting from 250-350+ studs away.
        root.CFrame = target.CFrame * CFrame.new(0, 3, 0)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
    if not ok then
        if FarmRuntime.teleportOwner == ticket.owner then FarmRuntime.teleportOwner = nil end
        return nil, tostring(err)
    end

    PetSeedRuntime.activeTicket = ticket
    task.wait(PET_SEED_TELEPORT_SETTLE)
    if not FarmRuntime.featureOperationCurrent(token) then
        FarmRuntime.finishPetSeedTeleport(ticket)
        return nil, "cancelled"
    end
    return ticket
end

function FarmRuntime.finishPetSeedTeleport(ticket)
    if not ticket or ticket.finished then return end
    ticket.finished = true
    if PetSeedRuntime.activeTicket == ticket then PetSeedRuntime.activeTicket = nil end
    if ticket.root and ticket.root.Parent and ticket.cframe then
        pcall(function()
            ticket.root.CFrame = ticket.cframe
            ticket.root.AssemblyLinearVelocity = ticket.linearVelocity or Vector3.zero
            ticket.root.AssemblyAngularVelocity = ticket.angularVelocity or Vector3.zero
        end)
    end
    if ticket and FarmRuntime.teleportOwner == ticket.owner then
        FarmRuntime.teleportOwner = nil
    end
end

function FarmRuntime.invalidatePetSeedQueue()
    PetSeedRuntime.revision += 1
    PetSeedRuntime.workerScheduled = false
    for _, entry in ipairs(PetSeedRuntime.queue) do
        if entry.instance then PetSeedRuntime.queued[entry.instance] = nil end
    end
    table.clear(PetSeedRuntime.claimed)
    table.clear(PetSeedRuntime.queue)
    table.clear(PetSeedRuntime.retryAfter)

    local ticket = PetSeedRuntime.activeTicket
    PetSeedRuntime.activeTicket = nil
    FarmRuntime.finishPetSeedTeleport(ticket)
end

function FarmRuntime.petSeedEligibility(instance)
    if not state.running then return false, "stopped" end
    if not state.autoCollectPetSeeds then return false, "disabled" end
    if not ownPlot or not ownPlot.Parent or ownPlot ~= GameState.ownPlot then return false, "plot" end
    if not instance or not instance.Parent or instance.Parent ~= ownPlot then return false, "gone" end
    if not FarmRuntime.isPetSeedFind(instance) then return false, "not-find" end
    if PetSeedRuntime.claimed[instance] then return false, "claimed" end

    local prompt = FarmRuntime.findPetSeedPrompt(instance)
    if not prompt or not prompt.Parent or not prompt:IsDescendantOf(instance) then
        return false, "prompt"
    end

    local ok, enabled = pcall(function() return prompt.Enabled end)
    if ok and enabled == false then
        return false, "prompt-disabled"
    end

    return true, prompt
end

function FarmRuntime.enqueuePetSeed(instance)
    if not state.autoCollectPetSeeds
        or not instance
        or PetSeedRuntime.queued[instance]
        or PetSeedRuntime.claimed[instance] then
        return
    end

    local retryAt = PetSeedRuntime.retryAfter[instance]
    if retryAt then
        if os.clock() < retryAt then
            return
        end
        PetSeedRuntime.retryAfter[instance] = nil
    end

    local eligible = FarmRuntime.petSeedEligibility(instance)
    if not eligible then return end

    PetSeedRuntime.queued[instance] = true
    PetSeedRuntime.queue[#PetSeedRuntime.queue + 1] = { instance = instance }
    FarmRuntime.schedulePetSeedWorker()

    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.scanPetSeeds()
    if not state.autoCollectPetSeeds or not ownPlot or not ownPlot.Parent then return end
    for _, child in ipairs(ownPlot:GetChildren()) do
        if FarmRuntime.isPetSeedFind(child) then
            FarmRuntime.enqueuePetSeed(child)
        end
    end
end

function FarmRuntime.schedulePetSeedWorker()
    if PetSeedRuntime.workerScheduled
        or #PetSeedRuntime.queue == 0
        or not state.autoCollectPetSeeds
        or not state.running then
        return
    end

    PetSeedRuntime.workerScheduled = true
    local revision = PetSeedRuntime.revision
    local generation = state.generation
    local token = FarmRuntime.featureOperationToken("pet")

    task.defer(function()
        local function step()
            if not FarmRuntime.featureOperationCurrent(token) then return end
            PetSeedRuntime.workerScheduled = false

            if not state.running
                or state.generation ~= generation
                or PetSeedRuntime.revision ~= revision
                or not state.autoCollectPetSeeds then
                return
            end

            local acquired = FarmRuntime.acquireFeatureOperation(token)
            if not acquired then
                PetSeedRuntime.workerScheduled = true
                task.delay(0.07, function()
                    if state.running
                        and state.generation == generation
                        and PetSeedRuntime.revision == revision
                        and state.autoCollectPetSeeds then
                        step()
                    end
                end)
                return
            end

            local entry = table.remove(PetSeedRuntime.queue, 1)
            if not entry then
                FarmRuntime.releaseFeatureOperation(token)
                return
            end
            local instance = entry.instance
            PetSeedRuntime.queued[instance] = nil

            local eligible, promptOrReason = FarmRuntime.petSeedEligibility(instance)
            local invoked = false

            if eligible then
                local prompt = promptOrReason
                local seedName = FarmRuntime.inferPetSeedName(instance)
                local dropName = FarmRuntime.inferPetDropName(instance, prompt) or seedName or "Pet Drop"

                if type(fireproximityprompt) ~= "function" then
                    state.petSeedErrors += 1
                    state.lastPetSeedError = "fireproximityprompt unavailable"
                    FarmRuntime.setPetSeedStatus("Pet drop prompt unavailable", true)
                else
                    PetSeedRuntime.claimed[instance] = token
                        token.claimRuntime, token.claimInstance = PetSeedRuntime, instance
                    state.petSeedAttempts += 1
                    FarmRuntime.setPetSeedStatus("Collecting " .. dropName .. "…")

                    local ticket, teleportErr = FarmRuntime.beginPetSeedTeleport(instance, prompt, token)
                    if not FarmRuntime.featureOperationCurrent(token) then
                        FarmRuntime.finishPetSeedTeleport(ticket)
                        FarmRuntime.releaseFeatureOperation(token)
                        return
                    end
                    if not ticket then
                        state.petSeedErrors += 1
                        state.lastPetSeedError = tostring(teleportErr)
                        if PetSeedRuntime.claimed[instance] == token then PetSeedRuntime.claimed[instance] = nil end
                        PetSeedRuntime.retryAfter[instance] = os.clock() + PetSeedRuntime.retryCooldown
                        FarmRuntime.setPetSeedStatus("Teleport failed: " .. tostring(teleportErr), true)
                    else
                        PetSeedRuntime.activeTicket = ticket

                        -- FIRST FIRE -------------------------------------------------
                        -- Teleport happened exactly once above. Stay at this same
                        -- location for the entire attempt.
                        local firstOk, firstErr = pcall(fireproximityprompt, prompt)
                        invoked = firstOk

                        if not firstOk then
                            state.petSeedErrors += 1
                            state.lastPetSeedError = tostring(firstErr)
                            if PetSeedRuntime.claimed[instance] == token then PetSeedRuntime.claimed[instance] = nil end
                            PetSeedRuntime.retryAfter[instance] = os.clock() + PetSeedRuntime.retryCooldown
                            FarmRuntime.setPetSeedStatus("FindPrompt error: " .. tostring(firstErr), true)
                        else
                            local firstDeadline = os.clock() + PET_SEED_CONFIRM_TIMEOUT
                            while FarmRuntime.featureOperationCurrent(token)
                                and instance.Parent
                                and os.clock() < firstDeadline do
                                task.wait(0.05)
                            end

                            -- SECOND FIRE --------------------------------------------
                            -- The tester showed that some drops are accepted by the
                            -- first fire but replicate their removal late, while an
                            -- occasional drop genuinely needs a second prompt fire.
                            -- Never teleport again here: re-find the current prompt
                            -- and fire it from the same settled position.
                            if instance.Parent and FarmRuntime.featureOperationCurrent(token) then

                                local secondPrompt = FarmRuntime.findPetSeedPrompt(instance)
                                local secondEnabled = false

                                if secondPrompt and secondPrompt.Parent then
                                    local enabledOk, enabledValue = pcall(function()
                                        return secondPrompt.Enabled
                                    end)
                                    secondEnabled = not enabledOk or enabledValue ~= false
                                end

                                if secondPrompt and secondEnabled then
                                    local secondOk, secondErr = pcall(fireproximityprompt, secondPrompt)
                                    invoked = invoked or secondOk

                                    if not secondOk then
                                        state.lastPetSeedError = tostring(secondErr)
                                    end
                                end

                                local secondDeadline = os.clock() + PetSeedRuntime.secondConfirmTimeout
                                while FarmRuntime.featureOperationCurrent(token)
                                    and instance.Parent
                                    and os.clock() < secondDeadline do
                                    task.wait(0.05)
                                end
                            end

                            if not FarmRuntime.featureOperationCurrent(token) then
                                FarmRuntime.finishPetSeedTeleport(ticket)
                                FarmRuntime.releaseFeatureOperation(token)
                                return
                            end
                            if not instance.Parent then
                                state.petSeedsCollected += 1
                                PetSeedRuntime.retryAfter[instance] = nil

                                -- Preserve the old per-seed stat accounting only when
                                -- this PlotFind actually resolves to a seed.
                                if type(seedName) == "string" and seedName ~= "" then
                                    local petNormalized = normalizeSeedText(seedName)
                                    local petKey = normalizedSeedTextToKey[petNormalized]
                                    if type(petKey) ~= "string" then
                                        local compactPetName = normalizeName(seedName):gsub("seed$", "")
                                        petKey = normalizedSeedTextToKey[compactPetName]
                                    end
                                    if type(petKey) == "string" and seedByKey[petKey] then
                                        local petStat = getPerSeedStat(petKey)
                                        petStat.petCollectedCount = (tonumber(petStat.petCollectedCount) or 0) + 1
                                    end
                                end

                                state.lastPetSeed = dropName
                                state.lastPetSeedError = nil
                                addActivity(dropName .. " pet drop collected", "success")
                                FarmRuntime.setPetSeedStatus("Collected " .. dropName)
                            elseif not state.running
                                or not state.autoCollectPetSeeds
                                or state.generation ~= generation
                                or PetSeedRuntime.revision ~= revision then
                                -- User disabled the feature / script unloaded while we
                                -- were waiting. This is cancellation, not an error.
                                if PetSeedRuntime.claimed[instance] == token then PetSeedRuntime.claimed[instance] = nil end
                            else
                                state.petSeedErrors += 1
                                state.lastPetSeedError = "FindPrompt confirmation timed out"
                                if PetSeedRuntime.claimed[instance] == token then PetSeedRuntime.claimed[instance] = nil end
                                PetSeedRuntime.retryAfter[instance] =
                                    os.clock() + PetSeedRuntime.retryCooldown
                                FarmRuntime.setPetSeedStatus("Pet drop confirmation timed out", true)
                            end
                        end

                        if PetSeedRuntime.activeTicket == ticket then
                            PetSeedRuntime.activeTicket = nil
                        end
                        FarmRuntime.finishPetSeedTeleport(ticket)
                    end
                end
            end

            if ui.RefreshFarm then ui.RefreshFarm() end
            if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
            if ui.RefreshInventory then ui.RefreshInventory() end

            FarmRuntime.releaseFeatureOperation(token)

            if not state.running
                or state.generation ~= generation
                or PetSeedRuntime.revision ~= revision
                or not state.autoCollectPetSeeds then
                return
            end

            if #PetSeedRuntime.queue > 0 then
                PetSeedRuntime.workerScheduled = true
                task.delay(invoked and PET_SEED_RATE_LIMIT or 0.05, function()
                    if state.running
                        and state.generation == generation
                        and PetSeedRuntime.revision == revision
                        and state.autoCollectPetSeeds then
                        step()
                    end
                end)
            end
        end

        step()
    end)
end

function FarmRuntime.setAutoCollectPetSeeds(value)
    local enabled = value == true
    if state.autoCollectPetSeeds == enabled then
        if enabled then
            FarmRuntime.scanPetSeeds()
            FarmRuntime.schedulePetSeedWorker()
        end
        return
    end

    state.autoCollectPetSeeds = enabled
    state.lastPetSeedError = nil

    if enabled then
        FarmRuntime.setPetSeedStatus("Watching own plot")
        FarmRuntime.scanPetSeeds()
        FarmRuntime.schedulePetSeedWorker()
    else
        FarmRuntime.invalidatePetSeedQueue()
        FarmRuntime.setPetSeedStatus("Auto pet drop collect off")
    end

    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
    scheduleSettingsSave()
end

function FarmRuntime.isLeafPile(instance)
    return instance ~= nil
        and instance.Parent ~= nil
        and type(instance.Name) == "string"
        and instance.Name:match("^LeafPile_") ~= nil
end

function FarmRuntime.findLeafPrompt(leafPile)
    if not leafPile or not leafPile.Parent then return nil end

    local exact = leafPile:FindFirstChild("LeafPileCollectPrompt", true)
    if exact and exact:IsA("ProximityPrompt") then
        return exact
    end

    for _, descendant in ipairs(leafPile:GetDescendants()) do
        if descendant:IsA("ProximityPrompt")
            and descendant.Name == "LeafPileCollectPrompt" then
            return descendant
        end
    end
    return nil
end

function FarmRuntime.getLeafCount()
    if not ownPlot or not ownPlot.Parent then return 0 end
    local count = 0
    for _, child in ipairs(ownPlot:GetChildren()) do
        if FarmRuntime.isLeafPile(child) then count += 1 end
    end
    return count
end

function FarmRuntime.setLeafStatus(message, isError)
    state.leafStatus = tostring(message or "Idle")
    if isError then state.lastLeafError = state.leafStatus end
    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.leafItemLooksLikeRake(item)
    if type(item) ~= "table" or item.empty == true then return false end
    local fields = {
        item.itemType,
        item.gearId,
        item.name,
        item.displayName,
        item.itemName,
        item.toolName,
        item.gearType,
        item.toolId,
        item.key,
        item.title,
    }
    for _, value in ipairs(fields) do
        if value ~= nil then
            local name = tostring(value):lower()
            if name:find("rake", 1, true)
                or name:find("collect leaves", 1, true)
                or name:find("collectleaves", 1, true) then
                return true
            end
        end
    end
    return false
end

function FarmRuntime.findLeafRakeCandidate()
    local data = FarmRuntime.getCurrentData()
    local inventory = data and data.Inventory

    local function scan(container, isHotbar)
        if type(container) ~= "table" then return nil end
        for slot, item in pairs(container) do
            if FarmRuntime.leafItemLooksLikeRake(item) and item.id ~= nil then
                return {
                    id = item.id,
                    item = item,
                    slot = tonumber(slot) or slot,
                    hotbar = isHotbar,
                }
            end
        end
        return nil
    end

    local candidate = scan(inventory and inventory.Hotbar, true)
    if candidate then return candidate end
    candidate = scan(inventory and inventory.Storage, false)
    if candidate then return candidate end
    candidate = scan(GameState.inventory.hotbar, true)
    if candidate then return candidate end
    return scan(GameState.inventory.storage, false)
end

function FarmRuntime.findPhysicalRakeTool()
    local character = LocalPlayer.Character
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
        or LocalPlayer:FindFirstChild("Backpack")

    local function scan(container)
        if not container then return nil end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") then
                local name = tostring(child.Name):lower()
                if name:find("rake", 1, true)
                    or name:find("collect leaves", 1, true)
                    or name:find("collectleaves", 1, true) then
                    return child
                end
            end
        end
        return nil
    end

    return scan(character) or scan(backpack)
end

function FarmRuntime.equipLeafRake(token)
    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    local physical = FarmRuntime.findPhysicalRakeTool()
    local character = LocalPlayer.Character
    if physical and character and physical.Parent == character then return true end

    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    local candidate = FarmRuntime.findLeafRakeCandidate()
    if candidate then
        if tostring(CompostRuntime.selectedItemId) ~= tostring(candidate.id) then
            local service = CompostRuntime.ToolService
            local toggle = service and service.ToggleEquip
            if toggle and type(toggle.Fire) == "function" then
                local ok, err = pcall(function()
                    toggle:Fire(candidate.hotbar, candidate.slot)
                end)
                if not ok then return false, tostring(err) end

                local deadline = os.clock() + FarmRuntime.LeafRuntime.EQUIP_TIMEOUT
                while FarmRuntime.featureOperationCurrent(token) and os.clock() < deadline do
                    if tostring(CompostRuntime.selectedItemId) == tostring(candidate.id) then
                        task.wait(0.05)
                        return FarmRuntime.featureOperationCurrent(token)
                    end
                    physical = FarmRuntime.findPhysicalRakeTool()
                    if physical and character and physical.Parent == character then
                        return FarmRuntime.featureOperationCurrent(token)
                    end
                    task.wait(0.03)
                end
            end
        else
            return true
        end
    end

    if not FarmRuntime.featureOperationCurrent(token) then return false, "cancelled" end
    -- Fallback for executors where the event gear is exposed as a normal Tool.
    physical = FarmRuntime.findPhysicalRakeTool()
    character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if physical and humanoid then
        local ok, err = pcall(function() humanoid:EquipTool(physical) end)
        if not ok then return false, tostring(err) end
        task.wait(0.08)
        if physical.Parent == character then return FarmRuntime.featureOperationCurrent(token) end
    end

    if candidate then
        return false, "Rake equip confirmation timed out"
    end
    return false, "Rake (Collect Leaves) not found/equipped"
end

function FarmRuntime.findLeafTargetPart(leafPile, prompt)
    if prompt and prompt.Parent then
        if prompt.Parent:IsA("BasePart") then return prompt.Parent end
        local ancestor = prompt.Parent:FindFirstAncestorWhichIsA("BasePart")
        if ancestor then return ancestor end
    end

    local promptPart = leafPile and leafPile:FindFirstChild("PromptPart", true)
    if promptPart and promptPart:IsA("BasePart") then return promptPart end
    return leafPile and leafPile:FindFirstChildWhichIsA("BasePart", true) or nil
end

function FarmRuntime.beginLeafTeleport(leafPile, prompt, token)
    if not FarmRuntime.featureOperationCurrent(token) then return nil, "cancelled" end
    local character = LocalPlayer.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    if not root or not root.Parent then
        return nil, "HumanoidRootPart unavailable"
    end

    -- Same movement lock/wait strategy as Auto Collect Pet Drops.
    local deadline = os.clock() + 1.5
    while FarmRuntime.featureOperationCurrent(token) and FarmRuntime.teleportOwner and os.clock() < deadline do
        task.wait(0.04)
    end
    if not FarmRuntime.featureOperationCurrent(token) then return nil, "cancelled" end
    if FarmRuntime.teleportOwner then
        return nil, "teleport busy"
    end

    local target = FarmRuntime.findLeafTargetPart(leafPile, prompt)
    if not target or not target.Parent then
        return nil, "leaf target part unavailable"
    end

    local ticket = { root = root, owner = "leaf" }
    FarmRuntime.teleportOwner = ticket.owner

    local ok, err = pcall(function()
        ticket.cframe = root.CFrame
        ticket.linearVelocity = root.AssemblyLinearVelocity
        ticket.angularVelocity = root.AssemblyAngularVelocity

        -- Deliberately identical to Auto Collect Pet Drops.
        local targetPosition = target.Position
        local standPosition = (target.CFrame * CFrame.new(0, 2.25, 2.5)).Position
        root.CFrame = CFrame.new(standPosition, targetPosition + Vector3.new(0, 1, 0))
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    if not ok then
        if FarmRuntime.teleportOwner == ticket.owner then
            FarmRuntime.teleportOwner = nil
        end
        return nil, tostring(err)
    end

    FarmRuntime.LeafRuntime.activeTicket = ticket
    task.wait(FarmRuntime.LeafRuntime.TELEPORT_SETTLE)
    if not FarmRuntime.featureOperationCurrent(token) then
        FarmRuntime.finishLeafTeleport(ticket)
        return nil, "cancelled"
    end
    return ticket
end

function FarmRuntime.finishLeafTeleport(ticket)
    if not ticket or ticket.finished then return end
    ticket.finished = true
    if FarmRuntime.LeafRuntime.activeTicket == ticket then FarmRuntime.LeafRuntime.activeTicket = nil end
    if ticket.root and ticket.root.Parent and ticket.cframe then
        pcall(function()
            ticket.root.CFrame = ticket.cframe
            ticket.root.AssemblyLinearVelocity = ticket.linearVelocity or Vector3.zero
            ticket.root.AssemblyAngularVelocity = ticket.angularVelocity or Vector3.zero
        end)
    end

    if FarmRuntime.LeafRuntime.activeTicket == ticket then
        FarmRuntime.LeafRuntime.activeTicket = nil
    end

    if ticket and FarmRuntime.teleportOwner == ticket.owner then
        FarmRuntime.teleportOwner = nil
    end
end

function FarmRuntime.invalidateLeafQueue()
    FarmRuntime.LeafRuntime.revision += 1
    FarmRuntime.LeafRuntime.workerScheduled = false
    FarmRuntime.LeafRuntime.buyPaused = false
    for _, entry in ipairs(FarmRuntime.LeafRuntime.queue) do
        if entry.instance then FarmRuntime.LeafRuntime.queued[entry.instance] = nil end
    end
    table.clear(FarmRuntime.LeafRuntime.claimed)
    table.clear(FarmRuntime.LeafRuntime.queue)
    local ticket = FarmRuntime.LeafRuntime.activeTicket
    FarmRuntime.LeafRuntime.activeTicket = nil
    FarmRuntime.finishLeafTeleport(ticket)
end

function FarmRuntime.leafEligibility(instance)
    if not state.running then return false, "stopped" end
    if not state.autoCollectLeaves then return false, "disabled" end
    if not ownPlot or not ownPlot.Parent or ownPlot ~= GameState.ownPlot then
        return false, "plot"
    end
    if not instance or not instance.Parent or instance.Parent ~= ownPlot then
        return false, "gone"
    end
    if not FarmRuntime.isLeafPile(instance) then return false, "not-leaf" end
    if FarmRuntime.LeafRuntime.claimed[instance] then return false, "claimed" end

    local prompt = FarmRuntime.findLeafPrompt(instance)
    if not prompt or not prompt.Parent or not prompt:IsDescendantOf(instance) then
        return false, "prompt"
    end

    -- LeafPileCollectPrompt is normally disabled until the Rake is equipped.
    -- Do NOT reject the leaf here: the worker equips the Rake after eligibility
    -- succeeds, then re-checks/enables the live prompt immediately before firing.
    return true, prompt
end

function FarmRuntime.enqueueLeaf(instance)
    if not state.autoCollectLeaves
        or not instance
        or FarmRuntime.LeafRuntime.queued[instance]
        or FarmRuntime.LeafRuntime.claimed[instance] then
        return
    end

    local eligible = FarmRuntime.leafEligibility(instance)
    if not eligible then return end
    FarmRuntime.LeafRuntime.queued[instance] = true
    FarmRuntime.LeafRuntime.queue[#FarmRuntime.LeafRuntime.queue + 1] = { instance = instance }
    FarmRuntime.scheduleLeafWorker()
    if ui.RefreshFarm then ui.RefreshFarm() end
end

function FarmRuntime.scanLeaves()
    if not state.autoCollectLeaves or not ownPlot or not ownPlot.Parent then return end
    for _, child in ipairs(ownPlot:GetChildren()) do
        if FarmRuntime.isLeafPile(child) then FarmRuntime.enqueueLeaf(child) end
    end
end

function FarmRuntime.scheduleLeafWorker()
    if FarmRuntime.LeafRuntime.workerScheduled
        or #FarmRuntime.LeafRuntime.queue == 0
        or not state.autoCollectLeaves
        or not state.running then
        return
    end

    FarmRuntime.LeafRuntime.workerScheduled = true
    local revision = FarmRuntime.LeafRuntime.revision
    local generation = state.generation
    local token = FarmRuntime.featureOperationToken("leaf")

    task.defer(function()
        local function step()
            if not FarmRuntime.featureOperationCurrent(token) then return end
            FarmRuntime.LeafRuntime.workerScheduled = false

            if not state.running
                or state.generation ~= generation
                or FarmRuntime.LeafRuntime.revision ~= revision
                or not state.autoCollectLeaves then
                return
            end

            local acquired = FarmRuntime.acquireFeatureOperation(token)
            if not acquired then
                FarmRuntime.LeafRuntime.workerScheduled = true
                task.delay(0.05, function()
                    if state.running
                        and state.generation == generation
                        and FarmRuntime.LeafRuntime.revision == revision
                        and state.autoCollectLeaves then
                        step()
                    end
                end)
                return
            end

            -- Auto Buy must stay completely paused while a leaf action is in
            -- progress. Buying a conveyor seed equips it immediately and can
            -- knock the Rake out of the player's hands.
            FarmRuntime.LeafRuntime.buyPaused = true

            -- If a buy prompt was fired a fraction of a second before the leaf
            -- appeared, let that already-in-flight equip settle first. The Rake
            -- is equipped after this grace period, so the leaf action wins.
            if state.autoBuyEnabled then
                task.wait(0.14)
            end

            if not FarmRuntime.featureOperationCurrent(token) then FarmRuntime.releaseFeatureOperation(token); return end
            local entry = table.remove(FarmRuntime.LeafRuntime.queue, 1)
            if not entry then
                FarmRuntime.LeafRuntime.buyPaused = false
                FarmRuntime.releaseFeatureOperation(token)
                return
            end
            local instance = entry.instance
            FarmRuntime.LeafRuntime.queued[instance] = nil

            local eligible, promptOrReason = FarmRuntime.leafEligibility(instance)
            local invoked = false

            if eligible then
                local prompt = promptOrReason

                if type(fireproximityprompt) ~= "function" then
                    state.leafErrors += 1
                    state.lastLeafError = "fireproximityprompt unavailable"
                    FarmRuntime.setLeafStatus("Leaf prompt unavailable", true)
                else
                    -- Leaves still require the event rake, but collection itself
                    -- follows the exact Pet Drop flow after this point.
                    local rakeReady, rakeErr = FarmRuntime.equipLeafRake(token)
                    if not FarmRuntime.featureOperationCurrent(token) then FarmRuntime.releaseFeatureOperation(token); return end
                    if not rakeReady then
                        if tostring(rakeErr):find("not found/equipped", 1, true) then
                            state.lastLeafError = nil
                            FarmRuntime.setLeafStatus(
                                "Rake required · waiting on " .. tostring(ownPlot.Name),
                                false
                            )
                        else
                            state.leafErrors += 1
                            state.lastLeafError = tostring(rakeErr)
                            FarmRuntime.setLeafStatus(
                                "Rake equip failed: " .. tostring(rakeErr),
                                true
                            )
                        end

                        task.delay(FarmRuntime.LeafRuntime.RETRY_DELAY, function()
                            if FarmRuntime.featureOperationCurrent(token)
                                and instance.Parent == ownPlot then
                                FarmRuntime.enqueueLeaf(instance)
                            end
                        end)
                    else
                        FarmRuntime.LeafRuntime.claimed[instance] = token
                        token.claimRuntime, token.claimInstance = FarmRuntime.LeafRuntime, instance
                        state.leafAttempts += 1
                        FarmRuntime.setLeafStatus("Collecting leaf · " .. tostring(ownPlot.Name), false)

                        local ticket, teleportErr = FarmRuntime.beginLeafTeleport(instance, prompt, token)
                        if not FarmRuntime.featureOperationCurrent(token) then
                            FarmRuntime.finishLeafTeleport(ticket)
                            FarmRuntime.releaseFeatureOperation(token)
                            return
                        end
                        if not ticket then
                            state.leafErrors += 1
                            state.lastLeafError = tostring(teleportErr)
                            if FarmRuntime.LeafRuntime.claimed[instance] == token then FarmRuntime.LeafRuntime.claimed[instance] = nil end
                            FarmRuntime.setLeafStatus("Teleport failed: " .. tostring(teleportErr), true)
                        else
                            FarmRuntime.LeafRuntime.activeTicket = ticket

                            -- Same as Pet Drops: fire the current prompt exactly once,
                            -- then wait for the replicated object to disappear.
                            local livePrompt = FarmRuntime.findLeafPrompt(instance)
                            if livePrompt and livePrompt.Parent then
                                prompt = livePrompt
                            end

                            -- Equipping the Rake is what normally makes this prompt
                            -- usable. Give the game's local state a short moment to
                            -- update, then make sure the executor can fire it.
                            local enableDeadline = os.clock() + 0.45
                            while FarmRuntime.featureOperationCurrent(token)
                                and prompt and prompt.Parent
                                and prompt.Enabled == false
                                and os.clock() < enableDeadline do
                                task.wait(0.05)
                            end

                            if not FarmRuntime.featureOperationCurrent(token) then
                                FarmRuntime.finishLeafTeleport(ticket)
                                FarmRuntime.releaseFeatureOperation(token)
                                return
                            end
                            if prompt and prompt.Parent and prompt.Enabled == false then
                                pcall(function()
                                    prompt.Enabled = true
                                    prompt.HoldDuration = 0
                                end)
                            end

                            local ok, err = pcall(fireproximityprompt, prompt)
                            invoked = ok

                            if not ok then
                                state.leafErrors += 1
                                state.lastLeafError = tostring(err)
                                if FarmRuntime.LeafRuntime.claimed[instance] == token then FarmRuntime.LeafRuntime.claimed[instance] = nil end
                                FarmRuntime.setLeafStatus("Leaf prompt error: " .. tostring(err), true)
                            else
                                local deadline = os.clock() + FarmRuntime.LeafRuntime.CONFIRM_TIMEOUT
                                while FarmRuntime.featureOperationCurrent(token)
                                    and instance.Parent
                                    and os.clock() < deadline do
                                    task.wait(0.05)
                                end

                                if not FarmRuntime.featureOperationCurrent(token) then
                                    FarmRuntime.finishLeafTeleport(ticket)
                                    FarmRuntime.releaseFeatureOperation(token)
                                    return
                                end
                                if not instance.Parent then
                                    state.leavesCollected += 1
                                    state.lastLeafError = nil
                                    addActivity(
                                        "Autumn leaf collected · " .. tostring(ownPlot.Name),
                                        "success"
                                    )
                                    FarmRuntime.setLeafStatus(
                                        "Collected · " .. tostring(ownPlot.Name),
                                        false
                                    )
                                elseif not state.running
                                    or not state.autoCollectLeaves
                                    or state.generation ~= generation
                                    or FarmRuntime.LeafRuntime.revision ~= revision then
                                    if FarmRuntime.LeafRuntime.claimed[instance] == token then FarmRuntime.LeafRuntime.claimed[instance] = nil end
                                else
                                    state.leafErrors += 1
                                    state.lastLeafError = "Leaf collection confirmation timed out"
                                    if FarmRuntime.LeafRuntime.claimed[instance] == token then FarmRuntime.LeafRuntime.claimed[instance] = nil end
                                    FarmRuntime.setLeafStatus("Leaf collection timed out", true)

                                    -- Same retry behavior as Auto Collect Pet Drops.
                                    task.delay(FarmRuntime.LeafRuntime.RETRY_DELAY, function()
                                        if FarmRuntime.featureOperationCurrent(token)
                                            and instance.Parent == ownPlot then
                                            FarmRuntime.enqueueLeaf(instance)
                                        end
                                    end)
                                end
                            end

                            if FarmRuntime.LeafRuntime.activeTicket == ticket then
                                FarmRuntime.LeafRuntime.activeTicket = nil
                            end
                            FarmRuntime.finishLeafTeleport(ticket)
                        end
                    end
                end
            elseif promptOrReason == "prompt" and instance and instance.Parent == ownPlot then
                task.delay(0.30, function()
                    if FarmRuntime.featureOperationCurrent(token) and instance.Parent == ownPlot then
                        FarmRuntime.enqueueLeaf(instance)
                    end
                end)
            end

            if ui.RefreshFarm then ui.RefreshFarm() end
            if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
            if ui.RefreshInventory then ui.RefreshInventory() end

            if not FarmRuntime.featureOperationCurrent(token) then
                FarmRuntime.releaseFeatureOperation(token)
                return
            end

            -- Re-scan the real plot before yielding priority. This catches any
            -- LeafPile that appeared while the current leaf was being collected
            -- or that briefly missed an earlier queue pass.
            FarmRuntime.scanLeaves()

            if #FarmRuntime.LeafRuntime.queue > 0 then
                -- Keep ownership of the shared automation slot for the whole
                -- leaf batch. Pet Drops / Compost / Auto Buy cannot run between
                -- leaf #1 and leaf #2 anymore.
                FarmRuntime.AutomationRuntime.owner = "leaf"
                FarmRuntime.AutomationRuntime.since = os.clock()
                FarmRuntime.LeafRuntime.buyPaused = true
                FarmRuntime.LeafRuntime.workerScheduled = true

                task.delay(invoked and FarmRuntime.LeafRuntime.RATE_LIMIT or 0.05, function()
                    if state.running
                        and state.generation == generation
                        and FarmRuntime.LeafRuntime.revision == revision
                        and state.autoCollectLeaves then
                        step()
                    else
                        FarmRuntime.releaseFeatureOperation(token)
                    end
                end)

                return
            end

            -- Queue is empty after a fresh plot scan: the leaf batch is truly
            -- drained, so lower-priority automation may continue now.
            FarmRuntime.LeafRuntime.buyPaused = false
            FarmRuntime.releaseFeatureOperation(token)
        end

        step()
    end)
end

function FarmRuntime.setAutoCollectLeaves(value)
    local enabled = value == true
    if state.autoCollectLeaves == enabled then
        if enabled then
            FarmRuntime.scanLeaves()
            FarmRuntime.scheduleLeafWorker()
        end
        return
    end

    state.autoCollectLeaves = enabled
    state.lastLeafError = nil
    if enabled then
        FarmRuntime.setLeafStatus(
            ownPlot and ("Watching " .. tostring(ownPlot.Name)) or "Waiting for own plot",
            false
        )
        FarmRuntime.scanLeaves()
        FarmRuntime.scheduleLeafWorker()
    else
        FarmRuntime.invalidateLeafQueue()
        FarmRuntime.setLeafStatus("Auto leaf collect off", false)
    end

    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
    scheduleSettingsSave()
end

function FarmRuntime.clearOwnPlotConnections()
    FarmRuntime.disconnectList(ownPlotConnections)
    for tree in pairs(treeDataByInstance) do
        FarmRuntime.detachTree(tree)
    end
    FarmRuntime.invalidateCollectQueue()
    FarmRuntime.invalidatePetSeedQueue()
    FarmRuntime.invalidateLeafQueue()
    ownPlot = nil
    GameState.ownPlot = nil
    CompostRuntime.bin = nil
    CompostRuntime.model = nil
    CompostRuntime.compostPart = nil
    CompostRuntime.promptPart = nil
    CompostRuntime.prompt = nil
    CompostRuntime.amountLabel = nil
    if state.running and ui.RefreshCompost then ui.RefreshCompost() end
end

function FarmRuntime.attachOwnPlot(plot)
    if ownPlot == plot then return end
    FarmRuntime.clearOwnPlotConnections()
    ownPlot = plot
    GameState.ownPlot = plot

    FarmRuntime.refreshCompostRefs()

    if not plot then
        if ui.RefreshFarm then ui.RefreshFarm() end
        if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
        if ui.UpdatePipeline then ui.UpdatePipeline() end
        return
    end

    ownPlotConnections[#ownPlotConnections + 1] = plot.ChildAdded:Connect(function(child)
        if not state.running or ownPlot ~= plot then return end

        if child.Name:match("^PlotTree_") then
            task.defer(function()
                if state.running and child.Parent == plot then FarmRuntime.attachTree(child) end
            end)
        elseif child.Name:match("^PlotFind_") then
            -- PlotFind may replicate before FindPrompt/Base. Try a few bounded
            -- rechecks instead of inventing a remote or polling forever.
            for _, delaySeconds in ipairs({ 0, 0.12, 0.40 }) do
                task.delay(delaySeconds, function()
                    if state.running and state.autoCollectPetSeeds and child.Parent == plot then
                        FarmRuntime.enqueuePetSeed(child)
                    end
                end)
            end
        elseif child.Name:match("^LeafPile_") then
            -- Autumn leaf piles can replicate before PromptPart/prompt.
            for _, delaySeconds in ipairs({ 0, 0.10, 0.30, 0.70 }) do
                task.delay(delaySeconds, function()
                    if state.running and state.autoCollectLeaves and child.Parent == plot then
                        FarmRuntime.enqueueLeaf(child)
                    end
                end)
            end
        end
    end)
    ownPlotConnections[#ownPlotConnections + 1] = plot.ChildRemoved:Connect(function(child)
        if treeDataByInstance[child] then
            local data = treeDataByInstance[child]
            addActivity((data.seedType or "Tree") .. " tree removed", "normal")
            FarmRuntime.detachTree(child)
            if ui.RefreshFarm then ui.RefreshFarm() end
            if ui.UpdatePipeline then ui.UpdatePipeline() end
        elseif child.Name:match("^PlotFind_") then
            PetSeedRuntime.queued[child] = nil
            PetSeedRuntime.claimed[child] = nil
            PetSeedRuntime.retryAfter[child] = nil
            if ui.RefreshFarm then ui.RefreshFarm() end
            if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
        elseif child.Name:match("^LeafPile_") then
            FarmRuntime.LeafRuntime.queued[child] = nil
            FarmRuntime.LeafRuntime.claimed[child] = nil
            if ui.RefreshFarm then ui.RefreshFarm() end
            if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
        end
    end)

    for _, child in ipairs(plot:GetChildren()) do
        if child.Name:match("^PlotTree_") then
            FarmRuntime.attachTree(child)
        elseif child.Name:match("^PlotFind_") and state.autoCollectPetSeeds then
            FarmRuntime.enqueuePetSeed(child)
        elseif child.Name:match("^LeafPile_") and state.autoCollectLeaves then
            FarmRuntime.enqueueLeaf(child)
        end
    end

    addActivity("Own plot acquired", "success")
    FarmRuntime.refreshCompostRefs()
    if state.autoCompostEnabled then FarmRuntime.scheduleCompostWorker() end
    if state.autoCollectPetSeeds then
        FarmRuntime.setPetSeedStatus("Watching own plot")
        FarmRuntime.scanPetSeeds()
    end
    if state.autoCollectLeaves then
        FarmRuntime.setLeafStatus("Watching " .. tostring(plot.Name), false)
        FarmRuntime.scanLeaves()
    end
    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
    if ui.UpdatePipeline then ui.UpdatePipeline() end
end

function FarmRuntime.findOwnPlot()
    if not playerPlots or not playerPlots.Parent then return nil end
    for _, plot in ipairs(playerPlots:GetChildren()) do
        local ok, owner = pcall(function() return plot:GetAttribute("OwnerUserId") end)
        if ok and owner == LocalPlayer.UserId then
            return plot
        end
    end
    return nil
end

function FarmRuntime.reacquireOwnPlot()
    local found = FarmRuntime.findOwnPlot()
    if found ~= ownPlot then FarmRuntime.attachOwnPlot(found) end
end

function FarmRuntime.watchPlotCandidate(plot)
    if not plot or plotCandidateConnections[plot] then return end
    local conn = plot:GetAttributeChangedSignal("OwnerUserId"):Connect(function()
        if state.running then FarmRuntime.reacquireOwnPlot() end
    end)
    plotCandidateConnections[plot] = conn
end

-- Session performance option ------------------------------------------------
-- FPS detach mode for PlotTree_* visuals under BigField.PlayerPlots.
-- Safe visual branches are removed from Workspace locally (Parent = nil) and
-- held by strong references so they can be restored. Functional fruit/prompt
-- parts stay in the plot as a lightweight invisible skeleton.
FarmRuntime.plotVisualOptimization = {
    rootConnection = nil,
    rootRemovingConnection = nil,
    root = nil,
    records = {},
    hiddenCount = 0,
    detachedCount = 0,
    fallbackCount = 0,
}

function FarmRuntime.findPlotTreeRoot(inst)
    if not inst or not playerPlots then return nil end
    local node = inst
    while node and node ~= playerPlots do
        if node:IsA("Model") and node.Name:match("^PlotTree_") then
            return node
        end
        node = node.Parent
    end
    return nil
end

function FarmRuntime.isPlotTreeVisualInstance(inst)
    return FarmRuntime.findPlotTreeRoot(inst) ~= nil
end

function FarmRuntime.canDetachPlotBasePart(inst)
    if not inst or not inst:IsA("BasePart") then return false end

    -- Fruit slot roots carry gameplay attributes and must remain descendants of
    -- the tree so Auto Collect / pricing / remote correlation continue working.
    if inst:GetAttribute("SpawnIndex") ~= nil
        or inst:GetAttribute("FruitLocked") ~= nil
        or inst:GetAttribute("FruitSizeMult") ~= nil
        or inst:GetAttribute("FruitMutations") ~= nil then
        return false
    end

    -- Never detach a part that owns an interaction object or another fruit root.
    -- Those parts stay as a zero-render/zero-physics skeleton instead.
    for _, descendant in ipairs(inst:GetDescendants()) do
        if descendant:IsA("ProximityPrompt")
            or descendant:IsA("ClickDetector")
            or descendant:GetAttribute("SpawnIndex") ~= nil then
            return false
        end
    end

    return true
end

function FarmRuntime.recountPlotVisualOptimization()
    local runtime = FarmRuntime.plotVisualOptimization
    local hidden, detached, fallback = 0, 0, 0
    for inst, record in pairs(runtime.records) do
        if inst and type(record) == "table" then
            hidden += 1
            if record.kind == "Detached" then detached += 1 else fallback += 1 end
        end
    end
    runtime.hiddenCount = hidden
    runtime.detachedCount = detached
    runtime.fallbackCount = fallback
end

function FarmRuntime.applyPlotVisualInstance(inst)
    if not state.hidePlotVisuals or not inst then return end

    local runtime = FarmRuntime.plotVisualOptimization
    local existing = runtime.records[inst]
    if existing then
        -- If replication puts a detached visual back into the tree while FPS
        -- mode is active, remember the newest parent and detach it again.
        if existing.kind == "Detached" and inst.Parent and FarmRuntime.isPlotTreeVisualInstance(inst) then
            existing.originalParent = inst.Parent
            existing.tree = FarmRuntime.findPlotTreeRoot(inst) or existing.tree
            pcall(function() inst.Parent = nil end)
        end
        return
    end

    if not inst.Parent then return end
    local treeRoot = FarmRuntime.findPlotTreeRoot(inst)
    if not treeRoot then return end

    local record = nil

    if inst:IsA("BasePart") then
        if FarmRuntime.canDetachPlotBasePart(inst) then
            local originalParent = inst.Parent
            local ok = pcall(function() inst.Parent = nil end)
            if ok then
                record = {
                    kind = "Detached",
                    originalParent = originalParent,
                    tree = treeRoot,
                }
            end
        else
            record = {
                kind = "SkeletonPart",
                tree = treeRoot,
                localTransparencyModifier = inst.LocalTransparencyModifier,
                castShadow = inst.CastShadow,
                canCollide = inst.CanCollide,
                canTouch = inst.CanTouch,
                canQuery = inst.CanQuery,
            }
            pcall(function()
                inst.LocalTransparencyModifier = 1
                inst.CastShadow = false
                inst.CanCollide = false
                inst.CanTouch = false
                inst.CanQuery = false
            end)
        end
    elseif inst:IsA("Decal")
        or inst:IsA("Texture")
        or inst:IsA("BillboardGui")
        or inst:IsA("SurfaceGui")
        or inst:IsA("ParticleEmitter")
        or inst:IsA("Trail")
        or inst:IsA("Beam")
        or inst:IsA("Smoke")
        or inst:IsA("Fire")
        or inst:IsA("Sparkles")
        or inst:IsA("PointLight")
        or inst:IsA("SpotLight")
        or inst:IsA("SurfaceLight")
        or inst:IsA("Highlight") then

        local originalParent = inst.Parent
        local ok = pcall(function() inst.Parent = nil end)
        if ok then
            record = {
                kind = "Detached",
                originalParent = originalParent,
                tree = treeRoot,
            }
        end
    end

    if record then
        runtime.records[inst] = record
        runtime.hiddenCount += 1
        if record.kind == "Detached" then
            runtime.detachedCount += 1
        else
            runtime.fallbackCount += 1
        end
    end
end

function FarmRuntime.hideExistingPlotVisuals()
    local runtime = FarmRuntime.plotVisualOptimization
    if not playerPlots or not playerPlots.Parent then return 0 end

    local processed = 0
    for _, plot in ipairs(playerPlots:GetChildren()) do
        for _, tree in ipairs(plot:GetChildren()) do
            if tree:IsA("Model") and tree.Name:match("^PlotTree_") then
                local descendants = tree:GetDescendants()
                for _, inst in ipairs(descendants) do
                    FarmRuntime.applyPlotVisualInstance(inst)
                    processed += 1
                    if processed % 90 == 0 then
                        task.wait()
                    end
                end
            end
        end
        task.wait()
    end

    return runtime.hiddenCount
end

function FarmRuntime.restorePlotVisuals()
    local runtime = FarmRuntime.plotVisualOptimization
    local processed = 0

    -- Detached records are strongly referenced intentionally. Restoring works
    -- even when a visual's original parent is itself temporarily detached.
    for inst, record in pairs(runtime.records) do
        if inst and type(record) == "table" then
            pcall(function()
                if record.kind == "Detached" then
                    if record.originalParent and record.originalParent.Parent then
                        inst.Parent = record.originalParent
                    else
                        inst:Destroy()
                    end
                elseif record.kind == "SkeletonPart" and inst:IsA("BasePart") and inst.Parent then
                    inst.LocalTransparencyModifier = record.localTransparencyModifier or 0
                    inst.CastShadow = record.castShadow ~= false
                    inst.CanCollide = record.canCollide == true
                    inst.CanTouch = record.canTouch == true
                    inst.CanQuery = record.canQuery == true
                end
            end)
        end
        processed += 1
        if processed % 90 == 0 then task.wait() end
    end

    runtime.records = {}
    runtime.hiddenCount = 0
    runtime.detachedCount = 0
    runtime.fallbackCount = 0
end

function FarmRuntime.bindPlotVisualOptimizationRoot()
    local runtime = FarmRuntime.plotVisualOptimization

    safeDisconnect(runtime.rootConnection)
    safeDisconnect(runtime.rootRemovingConnection)
    runtime.rootConnection = nil
    runtime.rootRemovingConnection = nil
    runtime.root = playerPlots

    if not playerPlots or not playerPlots.Parent then return end

    runtime.rootConnection = playerPlots.DescendantAdded:Connect(function(inst)
        if state.running and state.hidePlotVisuals then
            task.defer(function()
                if state.running and state.hidePlotVisuals and inst.Parent then
                    FarmRuntime.applyPlotVisualInstance(inst)
                end
            end)
        end
    end)

    runtime.rootRemovingConnection = playerPlots.DescendantRemoving:Connect(function(inst)
        if not state.running or not state.hidePlotVisuals then return end
        if not inst:IsA("Model") or not inst.Name:match("^PlotTree_") then return end

        task.defer(function()
            -- Ignore temporary moves that still leave the tree under PlayerPlots.
            if inst.Parent and inst:IsDescendantOf(playerPlots) then return end

            for visual, record in pairs(runtime.records) do
                if type(record) == "table" and record.tree == inst then
                    if record.kind == "Detached" and visual then
                        pcall(function() visual:Destroy() end)
                    end
                    runtime.records[visual] = nil
                end
            end
            FarmRuntime.recountPlotVisualOptimization()
            if ui.RefreshSession then ui.RefreshSession() end
        end)
    end)

    if state.hidePlotVisuals then
        FarmRuntime.hideExistingPlotVisuals()
    end
end

function FarmRuntime.setHidePlotVisuals(value, silent)
    local newValue = value == true
    if state.hidePlotVisuals == newValue then
        if newValue then FarmRuntime.hideExistingPlotVisuals() end
        return
    end

    state.hidePlotVisuals = newValue

    if newValue then
        FarmRuntime.hideExistingPlotVisuals()
    else
        FarmRuntime.restorePlotVisuals()
    end

    if ui.RefreshSession then ui.RefreshSession() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
    scheduleSettingsSave()

    if not silent then
        if newValue then
            ui.SetStatus("Tree + fruit visuals unloaded locally", "good")
            addActivity("FPS mode: heavy plot visuals detached", "normal")
        else
            ui.SetStatus("Tree + fruit visuals restored", "neutral")
            addActivity("FPS mode: plot visuals restored", "normal")
        end
    end
end

function FarmRuntime.destroyPlotVisualOptimization()
    local runtime = FarmRuntime.plotVisualOptimization
    safeDisconnect(runtime.rootConnection)
    safeDisconnect(runtime.rootRemovingConnection)
    runtime.rootConnection = nil
    runtime.rootRemovingConnection = nil
    runtime.root = nil
    FarmRuntime.restorePlotVisuals()
end

function FarmRuntime.initializeOwnPlotMonitor()
    playerPlots = bigField:FindFirstChild("PlayerPlots")
    if not playerPlots then
        playerPlots = bigField:WaitForChild("PlayerPlots", 5)
    end
    if not playerPlots then
        addActivity("PlayerPlots unavailable", "warning")
        return
    end

    FarmRuntime.bindPlotVisualOptimizationRoot()

    for _, plot in ipairs(playerPlots:GetChildren()) do FarmRuntime.watchPlotCandidate(plot) end
    addConnection(playerPlots.ChildAdded:Connect(function(plot)
        if state.running then
            FarmRuntime.watchPlotCandidate(plot)
            task.defer(function() if state.running then FarmRuntime.reacquireOwnPlot() end end)
        end
    end))
    addConnection(playerPlots.ChildRemoved:Connect(function(plot)
        local conn = plotCandidateConnections[plot]
        if conn then safeDisconnect(conn); plotCandidateConnections[plot] = nil end
        if state.running and plot == ownPlot then
            FarmRuntime.attachOwnPlot(nil)
            task.defer(function() if state.running then FarmRuntime.reacquireOwnPlot() end end)
        end
    end))
    FarmRuntime.reacquireOwnPlot()
end

function FarmRuntime.queueReadyFruits()
    if state.autoCollectFruits
        and ownPlot
        and ownPlot.Parent then

        -- Full own-plot sweep. FruitSpawn prompts do not need to be locally
        -- enabled/hovered and no teleport is required.
        for _, child in ipairs(ownPlot:GetChildren()) do
            if child.Name:match("^PlotTree_") then
                FarmRuntime.attachTree(child)
                local treeData = treeDataByInstance[child]

                if treeData then
                    for _, descendant in ipairs(child:GetDescendants()) do
                        if descendant:GetAttribute("SpawnIndex") ~= nil then
                            FarmRuntime.attachFruit(descendant, treeData)
                        elseif descendant:IsA("ProximityPrompt") then
                            local fruit =
                                FarmRuntime.findFruitOwnerFromDescendant(
                                    descendant,
                                    child
                                )
                            if fruit then
                                FarmRuntime.attachFruit(fruit, treeData)
                            end
                        end
                    end
                end
            end
        end
    end

    for _, treeData in pairs(GameState.treesById) do
        for _, fruitData in pairs(treeData.fruits) do
            if fruitData.instance
                and fruitData.instance.Parent
                and fruitData.instance:GetAttribute("FruitLocked") ~= true then
                FarmRuntime.enqueueFruit(fruitData)
            end
        end
    end
end

function FarmRuntime.setAutoCollect(value)
    local newValue = value == true
    if state.autoCollectFruits == newValue then return end
    state.autoCollectFruits = newValue
    if not newValue then
        FarmRuntime.invalidateCollectQueue()
    elseif newValue then
        FarmRuntime.queueReadyFruits()
    end
    if ui.RefreshFarm then ui.RefreshFarm() end
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.UpdatePipeline then ui.UpdatePipeline() end
    scheduleSettingsSave()
end

function FarmRuntime.setTpAutoCollect(_value)
    -- Retired in 4.3.65. Compatibility no-op only.
    state.tpAutoCollectFruits = false
end

function FarmRuntime.setAffordableOnly(value)
    state.affordableOnly = value == true
    skippedReasons = setmetatable({}, { __mode = "k" })
    if ui.RefreshBuyControls then ui.RefreshBuyControls() end
    if ui.UpdatePipeline then ui.UpdatePipeline() end
    scheduleSettingsSave()
    if state.autoBuyEnabled and scanExistingHolders then scanExistingHolders() end
end

function FarmRuntime.setCashReserve(value)
    state.cashReserve = math.max(0, tonumber(value) or 0)
    skippedReasons = setmetatable({}, { __mode = "k" })
    if ui.RefreshBuyControls then ui.RefreshBuyControls() end
    scheduleSettingsSave()
    if state.autoBuyEnabled and scanExistingHolders then scanExistingHolders() end
end

function FarmRuntime.setSpawnAlerts(value)
    state.spawnAlerts = value == true
    if ui.RefreshIncoming then ui.RefreshIncoming() end
    scheduleSettingsSave()
end

function FarmRuntime.setAlertRarity(rarity)
    if rarityIndex[rarity] then
        state.alertRarity = rarity
        if ui.RefreshIncoming then ui.RefreshIncoming() end
        scheduleSettingsSave()
    end
end

function FarmRuntime.remoteHasServiceAncestor(remote, serviceName)
    local parent = remote.Parent
    while parent and parent ~= ReplicatedStorage do
        if parent.Name == serviceName then return true end
        parent = parent.Parent
    end
    return false
end

function FarmRuntime.discoverObservedRemotes()
    local wanted = {
        SeedConveyorService = { "SeedPurchased", "SeedSpawned", "GuaranteedUpdated" },
        PlayerPlotService = { "PlotAssigned", "TreePlanted", "TreeRemoved", "FruitCollected", "FruitMutated" },
        WeatherService = { "WeatherChanged", "NextWeatherChanged" },
        DataService = { "DataUpdate" },
        SellStandService = { "TreeSold" },
    }

    local descendants = ReplicatedStorage:GetDescendants()
    for serviceName, names in pairs(wanted) do
        remoteCache[serviceName] = remoteCache[serviceName] or {}
        for _, remoteName in ipairs(names) do
            local found = nil
            for _, instance in ipairs(descendants) do
                if instance.Name == remoteName and instance:IsA("RemoteEvent") and FarmRuntime.remoteHasServiceAncestor(instance, serviceName) then
                    found = instance
                    break
                end
            end
            remoteCache[serviceName][remoteName] = found
            GameState.remoteStatus[serviceName .. "." .. remoteName] = found and "connected" or "missing"
        end
    end
end

function FarmRuntime.connectObservedRemote(serviceName, remoteName, callback)
    local remote = remoteCache[serviceName] and remoteCache[serviceName][remoteName]
    if not remote then return false end
    addConnection(remote.OnClientEvent:Connect(function(...)
        if state.running then
            local ok, err = pcall(callback, ...)
            if not ok then
                warn("[Farm Assistant V4.1] Remote listener error", serviceName, remoteName, err)
            end
        end
    end))
    return true
end

function FarmRuntime.mutationsToText(value)
    if type(value) == "string" then return value end
    if type(value) ~= "table" then return "" end
    local parts = {}
    for _, mutation in pairs(value) do
        if type(mutation) == "string" then parts[#parts + 1] = mutation end
    end
    table.sort(parts)
    return table.concat(parts, ", ")
end

function FarmRuntime.onSeedSpawned(payload)
    if type(payload) ~= "table" or type(payload.seedKey) ~= "string" then return end
    local seedStat = getPerSeedStat(payload.seedKey)
    seedStat.spawnCount = (tonumber(seedStat.spawnCount) or 0) + 1
    local entry = {
        seedKey = payload.seedKey,
        rarity = type(payload.rarity) == "string" and payload.rarity or "UNKNOWN",
        spawnId = payload.spawnId,
        startTime = tonumber(payload.startTime),
        travelDuration = tonumber(payload.travelDuration),
        mutation = deepCopy(payload.mutation),
        receivedClock = os.clock(),
    }
    if entry.startTime and entry.travelDuration then
        local now = safeServerTimeNow()
        local finish = entry.startTime + entry.travelDuration
        if now and math.abs(now - entry.startTime) < 15 then
            entry.endTime = finish
        end
    end
    GameState.incoming[#GameState.incoming + 1] = entry
    while #GameState.incoming > 10 do table.remove(GameState.incoming, 1) end

    local threshold = rarityIndex[state.alertRarity] or math.huge
    local rarityRank = rarityIndex[entry.rarity] or 0
    local mutationText = FarmRuntime.mutationsToText(entry.mutation)
    local shouldAlert = state.spawnAlerts and (
        state.selectedSeeds[entry.seedKey] == true
        or rarityRank >= threshold
        or mutationText ~= ""
    )
    if shouldAlert and ui.Toast then
        local text = mutationText ~= "" and (mutationText .. " " .. entry.seedKey .. " spawned")
            or (entry.rarity .. " " .. entry.seedKey .. " spawned")
        ui.Toast(text, mutationText ~= "" and "mutation" or "accent")
    end
    if ui.RefreshIncoming then ui.RefreshIncoming() end
end

function FarmRuntime.onGuaranteedUpdated(payload)
    if type(payload) == "table" then
        GameState.guarantee = deepCopy(payload)
        if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
        if ui.RefreshIncoming then ui.RefreshIncoming() end
    end
end

function FarmRuntime.onWeatherChanged(key, rawTime, third)
    if type(key) ~= "string" then return end
    GameState.weather.current = key
    GameState.weather.currentRawTime = tonumber(rawTime)
    GameState.weather.currentThird = third
    addActivity("Weather changed: " .. key, "normal")
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshSession then ui.RefreshSession() end
    if ui.Toast then ui.Toast("Weather: " .. key, "weather") end
end

function FarmRuntime.onNextWeatherChanged(payload)
    if type(payload) ~= "table" or type(payload.key) ~= "string" then return end
    GameState.weather.next = payload.key
    GameState.weather.nextStartTime = tonumber(payload.startTime)
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshSession then ui.RefreshSession() end
end

function FarmRuntime.onFruitCollected(_, treeId, spawnIndex)
    if type(treeId) ~= "string" or spawnIndex == nil then return end
    local logicalKey = treeId .. ":" .. tostring(spawnIndex)
    local now = os.clock()
    if recentFruitConfirmationDedupe[logicalKey] and now - recentFruitConfirmationDedupe[logicalKey] < 0.35 then
        return
    end

    local treeData = GameState.treesById[treeId]
    local pending = pendingFruitTriggers[logicalKey]
    local belongsToOwnPlot = treeData ~= nil or (pending and #pending > 0)
    if not belongsToOwnPlot then return end

    recentFruitConfirmationDedupe[logicalKey] = now

    if FarmRuntime.MarketRuntime and FarmRuntime.MarketRuntime.confirmedFruitKeys then
        FarmRuntime.MarketRuntime.confirmedFruitKeys[logicalKey] = now
    end

    state.fruitsCollected += 1
    local autoConfirmed = false
    if pending and #pending > 0 then
        table.remove(pending, 1)
        if #pending == 0 then pendingFruitTriggers[logicalKey] = nil end
        state.collectConfirmed += 1
        autoConfirmed = true
    end

    local seedType = treeData and treeData.seedType or nil
    recentFruitCollectedEvents[#recentFruitCollectedEvents + 1] = {
        createdClock = now,
        treeId = treeId,
        spawnIndex = spawnIndex,
        seedType = seedType,
    }
    matchFruitInventoryAndCollection()

    addActivity((seedType or "Fruit") .. (autoConfirmed and " fruit collect confirmed" or " fruit collected"), "success")
    if ui.RefreshSession then ui.RefreshSession() end
    if ui.RefreshHeader then ui.RefreshHeader() end
    if ui.RefreshFarm then ui.RefreshFarm() end
end

function FarmRuntime.onFruitMutated(_, treeId, spawnIndex, mutations)
    if type(treeId) ~= "string" or not GameState.treesById[treeId] then return end
    if type(mutations) ~= "table" then return end
    local names = {}
    for _, mutation in pairs(mutations) do
        if type(mutation) == "string" then
            state.mutationCounts[mutation] = (state.mutationCounts[mutation] or 0) + 1
            names[#names + 1] = mutation
        end
    end
    if #names > 0 then
        table.sort(names)
        addActivity(table.concat(names, ", ") .. " mutation appeared", "normal")
        if ui.Toast then ui.Toast(table.concat(names, ", ") .. " mutation", "mutation") end
        if ui.RefreshSession then ui.RefreshSession() end
        if ui.RefreshFarm then ui.RefreshFarm() end
    end
end

function FarmRuntime.onTreePlanted(_, payload)
    if type(payload) ~= "table" or type(payload.id) ~= "string" then return end
    local treeId = payload.id
    task.delay(0.05, function()
        if not state.running or not ownPlot then return end
        local tree = ownPlot:FindFirstChild("PlotTree_" .. treeId)
        if tree then
            FarmRuntime.attachTree(tree)
            addActivity(tostring(payload.seedType or "Tree") .. " tree planted", "success")
        end
    end)
end

function FarmRuntime.onTreeRemoved(_, treeId)
    if type(treeId) ~= "string" then return end
    local data = GameState.treesById[treeId]
    if data then
        addActivity((data.seedType or "Tree") .. " tree removed", "normal")
        if data.instance then FarmRuntime.detachTree(data.instance) end
        if ui.RefreshFarm then ui.RefreshFarm() end
        if ui.UpdatePipeline then ui.UpdatePipeline() end
    end
end

function FarmRuntime.initializeObservedRemotes()
    FarmRuntime.discoverObservedRemotes()
    FarmRuntime.connectObservedRemote("DataService", "DataUpdate", applyDataUpdate)
    FarmRuntime.connectObservedRemote("SeedConveyorService", "SeedSpawned", FarmRuntime.onSeedSpawned)
    FarmRuntime.connectObservedRemote("SeedConveyorService", "GuaranteedUpdated", FarmRuntime.onGuaranteedUpdated)
    FarmRuntime.connectObservedRemote("SeedConveyorService", "SeedPurchased", function(...)
        local args = { ... }
        GameState.lastSeedPurchasedPayload = type(args[1]) .. " / " .. tostring(args[1])
        if state.diagnosticsEnabled then addActivity("SeedPurchased event observed", "diagnostic") end
        if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
    end)
    FarmRuntime.connectObservedRemote("PlayerPlotService", "PlotAssigned", function()
        task.defer(function() if state.running then FarmRuntime.reacquireOwnPlot() end end)
    end)
    FarmRuntime.connectObservedRemote("PlayerPlotService", "TreePlanted", FarmRuntime.onTreePlanted)
    FarmRuntime.connectObservedRemote("PlayerPlotService", "TreeRemoved", FarmRuntime.onTreeRemoved)
    FarmRuntime.connectObservedRemote("PlayerPlotService", "FruitCollected", FarmRuntime.onFruitCollected)
    FarmRuntime.connectObservedRemote("PlayerPlotService", "FruitMutated", FarmRuntime.onFruitMutated)
    FarmRuntime.connectObservedRemote("WeatherService", "WeatherChanged", FarmRuntime.onWeatherChanged)
    FarmRuntime.connectObservedRemote("WeatherService", "NextWeatherChanged", FarmRuntime.onNextWeatherChanged)
    FarmRuntime.connectObservedRemote("SellStandService", "TreeSold", function(...)
        local args = { ... }
        GameState.treeSoldEvents += 1
        local parts = {}
        for i = 1, math.min(3, #args) do
            local value = args[i]
            parts[#parts + 1] = type(value) .. ":" .. tostring(value)
        end
        GameState.lastTreeSoldPayload = #parts > 0 and table.concat(parts, " | ") or "(no args)"
        addActivity("TreeSold event observed", "normal")
        if ui.RefreshSession then ui.RefreshSession() end
        if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
    end)
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end

function FarmRuntime.expireV3TransientState()
    expirePendingSeedConfirmations()
    matchFruitInventoryAndCollection()

    local nowClock = os.clock()
    for logicalKey, timestamp in pairs(recentFruitConfirmationDedupe) do
        if nowClock - timestamp > 60 then
            recentFruitConfirmationDedupe[logicalKey] = nil
        end
    end

    if FarmRuntime.MarketRuntime and FarmRuntime.MarketRuntime.confirmedFruitKeys then
        for logicalKey, timestamp in pairs(FarmRuntime.MarketRuntime.confirmedFruitKeys) do
            if nowClock - timestamp > 10 then
                FarmRuntime.MarketRuntime.confirmedFruitKeys[logicalKey] = nil
            end
        end
    end
    for key, queue in pairs(pendingFruitTriggers) do
        local i = 1
        while i <= #queue do
            if nowClock - queue[i].createdClock > 8 then
                table.remove(queue, i)
            else
                i += 1
            end
        end
        if #queue == 0 then pendingFruitTriggers[key] = nil end
    end

    local serverNow = safeServerTimeNow()
    local i = 1
    while i <= #GameState.incoming do
        local entry = GameState.incoming[i]
        local expired = nowClock - entry.receivedClock > 90
        if serverNow and entry.endTime and serverNow > entry.endTime + 5 then expired = true end
        if expired then table.remove(GameState.incoming, i) else i += 1 end
    end
end

function FarmRuntime.getTreeCount()
    local count = 0
    for _ in pairs(GameState.treesById) do count += 1 end
    return count
end

function FarmRuntime.getReadyFruitCount()
    local count = 0
    for _, treeData in pairs(GameState.treesById) do
        count += treeData.readyFruitCount or 0
    end
    return count
end

function FarmRuntime.getTotalFruitCount()
    local count = 0
    for _, treeData in pairs(GameState.treesById) do
        count += treeData.fruitCount or 0
    end
    return count
end

function FarmRuntime.currentSelectedTree()
    if selectedTreeId and GameState.treesById[selectedTreeId] then
        return GameState.treesById[selectedTreeId]
    end
    for id, data in pairs(GameState.treesById) do
        selectedTreeId = id
        return data
    end
    return nil
end

resetV3SessionState = function()
    table.clear(pendingSeedConfirmations)
    table.clear(recentFruitInventoryAdds)
    table.clear(recentFruitCollectedEvents)
    table.clear(pendingFruitTriggers)
    table.clear(recentFruitConfirmationDedupe)
    GameState.startingCash = GameState.cash
    GameState.totalPositiveCashDelta = 0
    GameState.totalNegativeCashDelta = 0
    GameState.treeSoldEvents = 0
    state.sessionStartedAt = os.time()
    if ui.RefreshSession then ui.RefreshSession() end
    if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
end


-- ============================================================
-- UI primitives
-- ============================================================

ui.GetGuiParent = function()
    local executorName = ""
    if type(identifyexecutor) == "function" then
        local executorOk, executorResult = pcall(identifyexecutor)
        if executorOk then executorName = tostring(executorResult or "") end
    end
    if executorName:lower():find("potassium", 1, true) then
        return LocalPlayer:WaitForChild("PlayerGui")
    end
    if type(gethui) == "function" then
        local ok, result = pcall(gethui)
        if ok and typeof(result) == "Instance" then return result end
    end
    local ok, core = pcall(function() return CoreGui end)
    if ok and core then return core end
    return LocalPlayer:WaitForChild("PlayerGui")
end

ui.PointInside = function(guiObject, point)
    if not guiObject or not guiObject.Visible then return false end
    local p, s = guiObject.AbsolutePosition, guiObject.AbsoluteSize
    return point.X >= p.X and point.Y >= p.Y and point.X <= p.X + s.X and point.Y <= p.Y + s.Y
end

ui.FormatDuration = function(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    if seconds < 60 then return tostring(seconds) .. "s" end
    if seconds < 3600 then return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60) end
    return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60))
end

ui.SignedMoney = function(value)
    if type(value) ~= "number" then return "—" end
    if value == 0 then return "$0" end
    return (value > 0 and "+$" or "-$") .. formatNumber(math.abs(value))
end

ui.CurrentWeatherText = function()
    local name = GameState.weather.current
    if not name then return "Weather —" end
    local raw = GameState.weather.currentRawTime
    local now = safeServerTimeNow()
    if now and type(raw) == "number" and raw > now and raw - now < 7200 then
        return name .. " · " .. ui.FormatDuration(raw - now)
    end
    return name
end

ui.NextWeatherText = function()
    if not GameState.weather.next then return "Next —" end
    local startTime = GameState.weather.nextStartTime
    local now = safeServerTimeNow()
    if now and type(startTime) == "number" and startTime > now and startTime - now < 7200 then
        return "Next: " .. GameState.weather.next .. " · " .. ui.FormatDuration(startTime - now)
    end
    return "Next: " .. GameState.weather.next
end

ui.CountMap = function(map)
    local count = 0
    for _ in pairs(map or {}) do count += 1 end
    return count
end

ui.TopMutationText = function()
    local best, bestCount = nil, 0
    for mutation, count in pairs(state.mutationCounts) do
        if count > bestCount or (count == bestCount and tostring(mutation) < tostring(best or "~")) then
            best, bestCount = mutation, count
        end
    end
    if not best then return "—" end
    return tostring(best) .. " ×" .. tostring(bestCount)
end

ui.BuildSessionReport = function()
    local runtime = os.time() - state.sessionStartedAt
    local net = GameState.cash and GameState.startingCash and (GameState.cash - GameState.startingCash) or nil
    local lines = {
        "Aroyn Hub Session",
        "Runtime: " .. ui.FormatDuration(runtime),
        "Starting Cash: " .. (GameState.startingCash and ("$" .. formatNumber(GameState.startingCash)) or "Unknown"),
        "Current Cash: " .. (GameState.cash and ("$" .. formatNumber(GameState.cash)) or "Unknown"),
        "Net Cash: " .. (net and ui.SignedMoney(net) or "Unknown"),
        "Confirmed Seed Spend: $" .. formatNumber(state.confirmedSeedSpend),
        "Fruits Collected: " .. tostring(state.fruitsCollected),
        "Confirmed Fruit Value: $" .. formatNumber(state.confirmedFruitValue),
        "Average Fruit Multiplier: " .. (state.fruitValueSamples > 0 and string.format("%.2fx", state.fruitMultiplierSum / state.fruitValueSamples) or "—"),
        "Highest Fruit Value: $" .. formatNumber(state.highestFruitValue),
        "Highest Fruit Multiplier: " .. (state.highestFruitMultiplier > 0 and string.format("%.2fx", state.highestFruitMultiplier) or "—"),
        "Observed Cash Increases: +$" .. formatNumber(GameState.totalPositiveCashDelta),
        "Observed Cash Decreases: -$" .. formatNumber(GameState.totalNegativeCashDelta),
        "Top Mutation: " .. ui.TopMutationText(),
        "Compost Seeds Fed: " .. tostring(state.compostSeedsFed),
        "Compost Cycles: " .. tostring(state.compostCycles),
        "Worms Obtained: " .. tostring(state.wormsGranted),
        "Last Worm: " .. tostring(state.lastWorm or "—"),
        "Seed triggers / confirmed:",
    }
    local entries = {}
    for key, stat in pairs(state.perSeedStats) do
        local t = tonumber(stat.triggerCount) or 0
        local c = tonumber(stat.confirmedCount) or 0
        if t > 0 or c > 0 then
            entries[#entries + 1] = { key = key, trigger = t, confirmed = c }
        end
    end
    table.sort(entries, function(a, b)
        if a.trigger ~= b.trigger then return a.trigger > b.trigger end
        return a.key < b.key
    end)
    if #entries == 0 then
        lines[#lines + 1] = "  —"
    else
        for _, entry in ipairs(entries) do
            lines[#lines + 1] = string.format("  %s %d / %d", entry.key, entry.trigger, entry.confirmed)
        end
    end
    lines[#lines + 1] = "Trigger Errors: " .. tostring(state.errors)
    lines[#lines + 1] = "Collect Errors: " .. tostring(state.collectErrors)
    return table.concat(lines, "\n")
end

-- Pet feeding uses observed PlotPet_<uid> markers and PlayerPlotService.FeedPet(uid).
FarmRuntime.PetFeed = { revision=0, scheduled=false, status="Off", confirmed=0, spent=0, cooldown={}, feeding={}, inFlight=nil, activeTicket=nil }
FarmRuntime.petFeedFinite=ui.PetFeedFinite
FarmRuntime.petFeedOptions=ui.PetFeedOptions
function FarmRuntime.petFeedReleaseClaim(token)
    if token and token.claimedFruit and claimedFruits[token.claimedFruit]==token then claimedFruits[token.claimedFruit]=nil end
end
function FarmRuntime.petFeedStatus(text)
    FarmRuntime.PetFeed.status=tostring(text)
    if ui.RefreshPetFeed then ui.RefreshPetFeed() end
end
function FarmRuntime.petFeedValueAllowed(value)
    local n=tonumber(value)
    if not n or n~=n or n==math.huge or n<0 then return false end
    local cap=FarmRuntime.petFeedFinite(state.petFeedMaxValue,0)
    return cap<=0 or n<=cap
end
function FarmRuntime.petFeedPets()
    local rows={}
    if not ownPlot or ownPlot~=GameState.ownPlot or not ownPlot.Parent then return rows end
    local now=os.clock()
    for _,marker in ipairs(ownPlot:GetChildren()) do
        if marker:IsA("Configuration") and marker.Name:match("^PlotPet_.+") and tonumber(marker:GetAttribute("OwnerUserId"))==LocalPlayer.UserId then
            local hunger,max=tonumber(marker:GetAttribute("Hunger")),tonumber(marker:GetAttribute("MaxHunger"))
            if hunger and max and max>0 and hunger==hunger and max==max and math.abs(hunger)~=math.huge and max~=math.huge then
                local uid=marker.Name:sub(9)
                rows[#rows+1]={uid=uid,marker=marker,hunger=math.clamp(hunger,0,max),max=max,percent=math.clamp(hunger/max*100,0,100),name=tostring(marker:GetAttribute("PetName") or marker:GetAttribute("PetType") or "Pet"),petType=tostring(marker:GetAttribute("PetType") or "Pet"),cooldown=(FarmRuntime.PetFeed.cooldown[uid] or 0)>now}
            end
        end
    end
    table.sort(rows,function(a,b) if a.percent~=b.percent then return a.percent<b.percent end return a.uid<b.uid end)
    return rows
end
function FarmRuntime.petFeedInventory()
    local data=FarmRuntime.getCurrentData()
    local inv=data and data.Inventory
    local rows={}
    if type(inv)~="table" then return rows end
    for _,part in ipairs({{key="Hotbar",hotbar=true},{key="Storage",hotbar=false}}) do
        for slot,item in pairs(type(inv[part.key])=="table" and inv[part.key] or {}) do
            if type(item)=="table" and item.itemType=="Fruit" and item.empty~=true and item.favorited~=true and item.id~=nil and (tonumber(item.count) or 1)>0 and FarmRuntime.petFeedValueAllowed(item.sellValue) then
                rows[#rows+1]={id=item.id,item=item,slot=tonumber(slot) or slot,hotbar=part.hotbar,value=tonumber(item.sellValue),count=math.max(1,tonumber(item.count) or 1)}
            end
        end
    end
    table.sort(rows,function(a,b) if a.value~=b.value then return a.value<b.value end return tostring(a.id)<tostring(b.id) end)
    return rows
end
function FarmRuntime.petFeedFruitById(id)
    for _,item in ipairs(FarmRuntime.petFeedInventory()) do if tostring(item.id)==tostring(id) then return item end end
end
function FarmRuntime.petFeedRawCount(id)
    local data=FarmRuntime.getCurrentData()
    local inv=data and data.Inventory
    if type(inv)~="table" then return nil end
    local count=0
    for _,key in ipairs({"Hotbar","Storage"}) do
        for _,item in pairs(type(inv[key])=="table" and inv[key] or {}) do
            if type(item)=="table" and item.empty~=true and tostring(item.id)==tostring(id) then
                count+=math.max(0,FarmRuntime.petFeedFinite(item.count,1))
            end
        end
    end
    return count
end
function FarmRuntime.petFeedChoosePet()
    local runtime=FarmRuntime.PetFeed
    local rows=FarmRuntime.petFeedPets()
    local present={}
    for _,pet in ipairs(rows) do
        present[pet.uid]=true
        if pet.percent>=(tonumber(state.petFeedTarget) or 80) then runtime.feeding[pet.uid]=nil end
        if not pet.cooldown and (pet.percent<(tonumber(state.petFeedThreshold) or 25) or runtime.feeding[pet.uid]) then runtime.feeding[pet.uid]=true;return pet end
    end
    for uid in pairs(runtime.feeding) do if not present[uid] then runtime.feeding[uid]=nil end end
end
function FarmRuntime.petFeedFruitMature(record,tree)
    local fruit=record and record.instance
    if not fruit or not fruit.Parent or not tree or not tree.instance or not tree.instance:IsDescendantOf(ownPlot) then return false end
    local start=tonumber(fruit:GetAttribute("FruitStartTime"))
    if not start or start~=start or math.abs(start)==math.huge then return false end
    local C=FarmRuntime.PetFeed.seedConfig
    if not C then
        local info=ReplicatedStorage:FindFirstChild("Shared")
        info=info and info:FindFirstChild("Info")
        local module=info and info:FindFirstChild("SeedConfig")
        if not module then return false end
        local ok,value=pcall(require,module)
        if not ok or type(value)~="table" then return false end
        C=value;FarmRuntime.PetFeed.seedConfig=C
    end
    if type(C.GetFruitGrowthTime)~="function" or type(C.PlotGrowthMult)~="function" then return false end
    local ok,duration=pcall(function() return C.GetFruitGrowthTime(tree.multiplier or 1,C.PlotGrowthMult(ownPlot)) end)
    duration=tonumber(duration)
    return ok and duration and duration>0 and duration<math.huge and workspace:GetServerTimeNow()-start>=duration
end
function FarmRuntime.petFeedChoosePlotFruit()
    if not ownPlot or ownPlot~=GameState.ownPlot or not ownPlot.Parent then return nil end
    FarmRuntime.refreshMarketPlotRecords()
    local best
    for _,tree in pairs(GameState.treesById) do
        if tree.instance and tree.instance.Parent and tree.instance:IsDescendantOf(ownPlot) then
            for fruit,record in pairs(tree.fruits or {}) do
                if fruit and fruit.Parent and not claimedFruits[fruit] and not queuedFruits[fruit] then
                    local live=FarmRuntime.liveFruitDisplay(record)
                    if live and FarmRuntime.petFeedFruitMature(record,tree) and not live.locked and not live.waxed and FarmRuntime.petFeedValueAllowed(live.sellValue) and (not best or live.sellValue<best.value) then
                        best={fruit=fruit,record=record,value=live.sellValue,seedType=live.seedType,tree=tree}
                    end
                end
            end
        end
    end
    return best
end
function FarmRuntime.petFeedPrepareFruit(token)
    local inventory=FarmRuntime.petFeedInventory()
    local held=inventory[1]
    local plot=FarmRuntime.petFeedChoosePlotFruit()
    if held and (not plot or held.value<=plot.value) then return held end
    if not plot then return nil,"No usable fruit · check value limit and favorites" end
    if type(fireproximityprompt)~="function" then return nil,"Fruit collection unavailable in this executor" end
    local before={}
    for _,item in ipairs(inventory) do before[tostring(item.id)]=item.count end
    local prompt=FarmRuntime.findFruitPrompt(plot.fruit)
    if not prompt or not prompt.Parent then return nil,"Fruit prompt unavailable" end
    local live=FarmRuntime.liveFruitDisplay(plot.record)
    if not FarmRuntime.featureOperationCurrent(token) or not live or live.locked or live.waxed or not FarmRuntime.petFeedValueAllowed(live.sellValue) or claimedFruits[plot.fruit] or queuedFruits[plot.fruit] or not FarmRuntime.petFeedFruitMature(plot.record,plot.tree) then return nil,"Fruit changed or operation cancelled" end
    token.claimedFruit=plot.fruit;claimedFruits[plot.fruit]=token
    -- Same direct FruitSpawn prompt path as Auto Collect All Fruits.
    -- Keep the character position and prompt properties unchanged.
    local triggered,triggerError=pcall(fireproximityprompt,prompt)
    if not triggered then return nil,"Fruit collection failed: "..tostring(triggerError) end
    local deadline=os.clock()+2
    while FarmRuntime.featureOperationCurrent(token) and os.clock()<deadline do
        for _,item in ipairs(FarmRuntime.petFeedInventory()) do
            if item.item.seedType==plot.seedType and (not before[tostring(item.id)] or item.count>before[tostring(item.id)]) then return item end
        end
        task.wait(0.05)
    end
    return nil,FarmRuntime.featureOperationCurrent(token) and "Fruit collection not confirmed" or "cancelled"
end
function FarmRuntime.petFeedStep(token)
    if not FarmRuntime.featureOperationCurrent(token) then return false end
    local pet=FarmRuntime.petFeedChoosePet()
    if not pet then FarmRuntime.petFeedStatus(#FarmRuntime.petFeedPets()==0 and "No active pets on your plot" or "Pets are above the hunger threshold");return false end
    local service=CompostRuntime.PlayerPlotService
    if not service or type(service.FeedPet)~="function" then FarmRuntime.petFeedStatus("FeedPet service unavailable");return false end
    if FarmRuntime.PetFeed.inFlight then FarmRuntime.petFeedStatus("Waiting for previous feed response");return false end
    local fruit,reason=FarmRuntime.petFeedPrepareFruit(token)
    if not FarmRuntime.featureOperationCurrent(token) then return false end
    if not fruit then FarmRuntime.petFeedStatus(reason);FarmRuntime.PetFeed.cooldown[pet.uid]=os.clock()+5;return false end
    if not FarmRuntime.featureOperationCurrent(token) then return false end
    local current=FarmRuntime.petFeedFruitById(fruit.id)
    if not current then FarmRuntime.petFeedStatus("Fruit changed before equip");return false end
    local toggle=CompostRuntime.ToolService and CompostRuntime.ToolService.ToggleEquip
    if not toggle or type(toggle.Fire)~="function" then FarmRuntime.petFeedStatus("Fruit equip unavailable");return false end
    if tostring(CompostRuntime.selectedItemId)~=tostring(current.id) then
        toggle:Fire(current.hotbar,current.slot)
        if not FarmRuntime.waitForSelectedItem(current.id,1.2,token) then
            if FarmRuntime.featureOperationCurrent(token) then FarmRuntime.petFeedStatus("Fruit equip not confirmed") end
            return false
        end
    end
    if not FarmRuntime.featureOperationCurrent(token) then return false end
    local fresh=FarmRuntime.petFeedFruitById(current.id)
    if not fresh or tostring(CompostRuntime.selectedItemId)~=tostring(fresh.id) or not pet.marker.Parent or pet.marker.Parent~=ownPlot or tonumber(pet.marker:GetAttribute("OwnerUserId"))~=LocalPlayer.UserId then FarmRuntime.petFeedStatus("Pet or selected fruit changed");return false end
    local beforeHunger=tonumber(pet.marker:GetAttribute("Hunger"))
    if not beforeHunger or beforeHunger/pet.max*100>=state.petFeedTarget then return false end
    if not FarmRuntime.featureOperationCurrent(token) or tostring(CompostRuntime.selectedItemId)~=tostring(fresh.id) or not FarmRuntime.petFeedFruitById(fresh.id) then return false end
    local call={done=false}
    FarmRuntime.PetFeed.inFlight=call
    FarmRuntime.petFeedStatus("Feeding "..pet.name.." with "..tostring(fresh.item.fruitName or fresh.item.seedType or "fruit"))
    task.spawn(function()
        if not FarmRuntime.featureOperationCurrent(token) then if FarmRuntime.PetFeed.inFlight==call then FarmRuntime.PetFeed.inFlight=nil end;call.done=true;return end
        call.ok,call.resolved,call.accepted=pcall(function() return service:FeedPet(pet.uid):await() end)
        -- :await() returns promise success and then the server boolean.
        if FarmRuntime.PetFeed.inFlight==call then FarmRuntime.PetFeed.inFlight=nil end
        call.done=true
    end)
    local deadline=os.clock()+3
    while FarmRuntime.featureOperationCurrent(token) and os.clock()<deadline do
        local after=FarmRuntime.petFeedRawCount(fresh.id)
        local consumed=after~=nil and after<fresh.count
        local hunger=pet.marker.Parent and tonumber(pet.marker:GetAttribute("Hunger"))
        if call.done and call.ok and call.resolved and call.accepted==true and consumed and hunger and hunger>beforeHunger then
            FarmRuntime.PetFeed.confirmed+=1;FarmRuntime.PetFeed.spent+=fresh.value
            FarmRuntime.PetFeed.cooldown[pet.uid]=os.clock()+1
            FarmRuntime.petFeedStatus("Fed "..pet.name.." · "..math.floor(hunger/pet.max*100+0.5).."%")
            addActivity("Pet fed · "..pet.name.." · "..tostring(fresh.item.fruitName or "fruit"),"success")
            return true
        end
        if call.done and (not call.ok or not call.resolved or call.accepted~=true) then break end
        task.wait(0.05)
    end
    FarmRuntime.PetFeed.cooldown[pet.uid]=os.clock()+10
    if FarmRuntime.featureOperationCurrent(token) then FarmRuntime.petFeedStatus("Feed not confirmed · retry paused") end
    return false
end
function FarmRuntime.schedulePetFeed()
    local r=FarmRuntime.PetFeed
    if r.scheduled or not state.autoFeedPetsEnabled or not state.running or state.stopping then return end
    local token=FarmRuntime.featureOperationToken("feed")
    r.scheduled=token
    task.spawn(function()
        if FarmRuntime.acquireFeatureOperation(token) then
            local ok,err=pcall(FarmRuntime.petFeedStep,token)
            if not ok and FarmRuntime.featureOperationCurrent(token) then FarmRuntime.petFeedStatus("Feed error: "..tostring(err)) end
            FarmRuntime.petFeedReleaseClaim(token)
            FarmRuntime.releaseFeatureOperation(token)
        end
        if r.scheduled==token then r.scheduled=false end
    end)
end
function FarmRuntime.setAutoFeedPets(enabled)
    local r=FarmRuntime.PetFeed
    state.autoFeedPetsEnabled=enabled==true;r.revision+=1
    if r.scheduled then r.scheduled.cancelled=true;FarmRuntime.petFeedReleaseClaim(r.scheduled);FarmRuntime.releaseFeatureOperation(r.scheduled);r.scheduled=false end
    table.clear(r.feeding)
    FarmRuntime.petFeedStatus(state.autoFeedPetsEnabled and "Checking active pets" or "Off")
    scheduleSettingsSave()
    if state.autoFeedPetsEnabled then FarmRuntime.schedulePetFeed() end
end


-- Game-specific controller bridge; inserted after all existing gameplay definitions.
-- The Aroyn core remains independent and unmodified.
local IntegrationController={State=state,Game=GameState,Farm=FarmRuntime,Web=AroynWeb,App=App,
    Records=seedRecords,Rarities=rarityOrder,UI=ui,Options=Options}
App.Integration=IntegrationController
IntegrationController.ParseNumber=parseCompactNumber
IntegrationController.FormatNumber=formatNumber
IntegrationController.Report=ui.BuildSessionReport
IntegrationController.ResetStats=resetStats
IntegrationController.ClearActivity=clearActivity
IntegrationController.Inventory=inventoryAggregate
IntegrationController.SetSelectedTree=function(id)
    selectedTreeId=nil
    for key in pairs(GameState.treesById) do if tostring(key)==tostring(id) then selectedTreeId=key;break end end
end
IntegrationController.GetSelectedTree=function() return selectedTreeId end
IntegrationController.SelectSeed=setSeedSelected
IntegrationController.SelectAll=selectAllSeeds
IntegrationController.ClearSeeds=clearSeedSelection
IntegrationController.SelectRarity=setSeedsByRarity
IntegrationController.PriorityEnabled=setPriorityEnabled
IntegrationController.MovePriority=movePriority
IntegrationController.SelectCompost=setCompostSeedSelected
IntegrationController.SelectAllCompost=selectAllCompostSeeds
IntegrationController.ClearCompost=clearCompostSeedSelection
IntegrationController.PetOptions=ui.PetFeedOptions
IntegrationController.Setters={AutoBuy=setAutoBuy,AutoCompost=FarmRuntime.setAutoCompost,
    AutoCollect=FarmRuntime.setAutoCollect,AutoLeaves=FarmRuntime.setAutoCollectLeaves,
    AutoPetDrops=FarmRuntime.setAutoCollectPetSeeds,AutoMarket=FarmRuntime.setAutoMarket,
    AutoFeed=FarmRuntime.setAutoFeedPets,HidePlot=FarmRuntime.setHidePlotVisuals,
    Affordable=FarmRuntime.setAffordableOnly,Reserve=FarmRuntime.setCashReserve,
    MaxPrice=setMaxPrice,Rate=setRateLimit,OneShot=setOneShot,StopAfter=setStopAfter,
    Alerts=FarmRuntime.setSpawnAlerts,AlertRarity=FarmRuntime.setAlertRarity}
-- Verify credential writes without exposing their contents in errors.
local originalCredentialSave=AroynWeb.SaveConfig
AroynWeb.SaveConfig=function()
    if not originalCredentialSave() or type(readfile)~="function" then return false end
    local ok,data=pcall(function() return HttpService:JSONDecode(readfile(AroynWeb.configFile)) end)
    return ok and type(data)=="table" and data.dashboardKey==(AroynWeb.ValidKey(AroynWeb.key) and AroynWeb.key or nil)
end
-- One Hub coordinator owns auth, registration, telemetry and reconnect cancellation.
local dashboardFactory=Options.DashboardFactory or HubDashboardFactory
IntegrationController.Dashboard=dashboardFactory(IntegrationController)
AroynWeb.Start=function() return IntegrationController.Dashboard:Connect() end
AroynWeb.LinkKey=function(key) return IntegrationController.Dashboard:Connect(key) end
AroynWeb.Stop=function() IntegrationController.Dashboard:Destroy() end -- normal runtime teardown keeps persistent intent
AroynWeb.Unlink=function()
    local dashboard=IntegrationController.Dashboard
    dashboard:Disconnect();AroynWeb.key=nil;AroynWeb.account=nil
    env[Options.BuildInfo.RuntimeId.."_DASHBOARD_KEY"]=nil
    if not AroynWeb.SaveConfig() then dashboard:Warn("Dashboard credential removal could not be saved.") end
    return true
end
function IntegrationController.CancelNetwork()
    local thread=IntegrationController.NetworkThread
    IntegrationController.NetworkThread=nil
    if thread and thread~=coroutine.running() then pcall(task.cancel,thread) end
end
function IntegrationController.StopAutomation()
    for _,key in ipairs({"AutoBuy","AutoCompost","AutoCollect","AutoLeaves","AutoPetDrops","AutoMarket","AutoFeed","HidePlot"}) do
        IntegrationController.Setters[key](false)
    end
end
function IntegrationController.Preferences()
    local selected,compost,priority={},{},{}
    for _,record in ipairs(seedRecords) do
        local k=record.key
        if state.selectedSeeds[k] then table.insert(selected,k) end
        if state.selectedCompostSeeds[k] then table.insert(compost,k) end
        if state.priorities[k] then table.insert(priority,{Key=k,Rank=state.priorities[k]}) end
    end
    table.sort(priority,function(a,b) return a.Rank==b.Rank and a.Key<b.Key or a.Rank<b.Rank end)
    local order={};for _,item in ipairs(priority) do table.insert(order,item.Key) end
    return {Seeds=selected,CompostSeeds=compost,PriorityOrder=table.concat(order,", "),
        MaxPrice=state.maxPrice and tostring(state.maxPrice) or "",Rate=tostring(state.rateLimit),
        OneShot=state.oneShot,StopAfter=state.stopAfter and tostring(state.stopAfter) or "",
        Affordable=state.affordableOnly,Reserve=tostring(state.cashReserve),
        PetStart=state.petFeedThreshold,PetTarget=state.petFeedTarget,PetCap=tostring(state.petFeedMaxValue),
        Alerts=state.spawnAlerts,AlertRarity=state.alertRarity,Diagnostics=state.diagnosticsEnabled,
        Hotkey=state.hotkey and state.hotkey.Name or "None"}
end
function IntegrationController.ApplyPreferences(values)
    -- Call existing validation/setters; input must not activate any automation flag.
    table.clear(state.selectedSeeds);table.clear(state.priorities)
    for _,k in ipairs(values.Seeds or {}) do if seedByKey[k] then state.selectedSeeds[k]=true end end
    local rank=0
    for k in tostring(values.PriorityOrder or ""):gmatch('[^,]+') do
        k=trim(k)
        if seedByKey[k] and state.selectedSeeds[k] and not state.priorities[k] then rank+=1;state.priorities[k]=rank end
    end
    table.clear(state.selectedCompostSeeds)
    for _,k in ipairs(values.CompostSeeds or {}) do if seedByKey[k] then state.selectedCompostSeeds[k]=true end end
    local function number(value,fallback)
        local n,err=parseCompactNumber(tostring(value or ""))
        return not err and n and n==n and math.abs(n)~=math.huge and n>=0 and n or fallback
    end
    state.maxPrice=number(values.MaxPrice,nil);state.cashReserve=number(values.Reserve,0)
    local rate=number(values.Rate,0);state.rateLimit=0
    for _,allowed in ipairs(RATE_OPTIONS) do if math.abs(rate-allowed)<.0001 then state.rateLimit=allowed end end
    state.stopAfter=number(values.StopAfter,nil);if state.stopAfter then state.stopAfter=math.max(1,math.floor(state.stopAfter)) end
    state.affordableOnly=values.Affordable==true;state.oneShot=values.OneShot==true
    state.petFeedThreshold,state.petFeedTarget,state.petFeedMaxValue=ui.PetFeedOptions(values.PetStart,values.PetTarget,values.PetCap)
    state.spawnAlerts=values.Alerts==true
    if rarityIndex[values.AlertRarity] then state.alertRarity=values.AlertRarity end
    state.diagnosticsEnabled=values.Diagnostics==true
    if values.Hotkey=="None" then state.hotkey=nil
    elseif type(values.Hotkey)=='string' then
        local ok,key=pcall(function() return Enum.KeyCode[values.Hotkey] end)
        if ok and key and key~=Enum.KeyCode.Unknown then state.hotkey=key end
    end
    normalizePriorities();invalidateQueue();FarmRuntime.invalidateCollectQueue()
    if state.running and state.autoBuyEnabled then scanExistingHolders() end
    saveSettingsNow()
end
IntegrationController.Destroy=function() App.Destroy() end
function IntegrationController.SetPreference(key,value)
    local function positive(raw,empty)
        if trim(tostring(raw))=="" then return empty end
        local n,err=parseCompactNumber(tostring(raw))
        assert(not err and n and n==n and math.abs(n)~=math.huge and n>=0,"Invalid nonnegative number")
        return n
    end
    if key=="Seeds" then
        local nextSet={};for _,k in ipairs(value) do if seedByKey[k] then nextSet[k]=true end end
        for _,r in ipairs(seedRecords) do setSeedSelected(r.key,nextSet[r.key]==true,true) end
        if state.autoBuyEnabled then scanExistingHolders() end
    elseif key=="CompostSeeds" then
        local nextSet={};for _,k in ipairs(value) do nextSet[k]=true end
        for _,r in ipairs(seedRecords) do setCompostSeedSelected(r.key,nextSet[r.key]==true) end
    elseif key=="PriorityOrder" then
        local nextRanks={};local rank=0
        for k in tostring(value):gmatch('[^,]+') do
            k=trim(k);assert(seedByKey[k],"Unknown seed priority: "..k)
            if not nextRanks[k] then rank+=1;nextRanks[k]=rank end
        end
        state.priorities=nextRanks
        for k in pairs(nextRanks) do state.selectedSeeds[k]=true end
        normalizePriorities();resortQueue();if state.autoBuyEnabled then scanExistingHolders() end
    elseif key=="MaxPrice" then setMaxPrice(positive(value,nil))
    elseif key=="Reserve" then FarmRuntime.setCashReserve(positive(value,0))
    elseif key=="StopAfter" then setStopAfter(positive(value,nil))
    elseif key=="Rate" then setRateLimit(tonumber(value) or 0)
    elseif key=="OneShot" then setOneShot(value)
    elseif key=="Affordable" then FarmRuntime.setAffordableOnly(value)
    elseif key=="PetStart" or key=="PetTarget" or key=="PetCap" then
        local start,target,cap=state.petFeedThreshold,state.petFeedTarget,state.petFeedMaxValue
        if key=="PetStart" then start=value elseif key=="PetTarget" then target=value else cap=positive(value,0) end
        state.petFeedThreshold,state.petFeedTarget,state.petFeedMaxValue=ui.PetFeedOptions(start,target,cap)
        if state.autoFeedPetsEnabled then FarmRuntime.schedulePetFeed() end
    elseif key=="Alerts" then FarmRuntime.setSpawnAlerts(value)
    elseif key=="AlertRarity" then FarmRuntime.setAlertRarity(value)
    elseif key=="Diagnostics" then state.diagnosticsEnabled=value==true
    elseif key=="Hotkey" then
        if value==nil or value=="None" then state.hotkey=nil
        elseif typeof(value)=="EnumItem" and value.EnumType==Enum.KeyCode then state.hotkey=value
        else state.hotkey=Enum.KeyCode[value] end
    else error("Unknown preference: "..tostring(key)) end
    saveSettingsNow()
end
ui.CreateGui=function()
    IntegrationController.Records=seedRecords;IntegrationController.Rarities=rarityOrder
    ui.Integration=BuildUI(Aroyn,IntegrationController)
    ui.ScreenGui=ui.Integration.Window.OwnRoot;ui.Window=ui.Integration.Window.Root
    App.Window=ui.Integration.Window
end

-- Anti-AFK
-- ============================================================
-- Uses two independent guards:
--   1) LocalPlayer.Idled -> immediate synthetic input.
--   2) Periodic keepalive pulse before Roblox reaches the idle kick window.
-- VirtualUser is preferred; VirtualInputManager is a fallback.
-- Everything is attached to the existing Aroyn lifecycle, so re-execution
-- disconnects the old Idled listener and old loops stop on generation change.

function FarmRuntime.antiAfkPulse(reason)
    if not state.running or not state.antiAfkEnabled then
        return false
    end

    local camera = workspace.CurrentCamera
    local cameraCFrame = camera and camera.CFrame or CFrame.new()
    local point = Vector2.new(0, 0)

    local vuOk, virtualUser = pcall(function()
        return game:GetService("VirtualUser")
    end)
    if vuOk and virtualUser then
        local pulseOk, pulseErr = pcall(function()
            virtualUser:CaptureController()
            virtualUser:Button2Down(point, cameraCFrame)
            task.wait(0.04)
            virtualUser:Button2Up(point, cameraCFrame)
        end)

        if pulseOk then
            state.antiAfkMode = "VirtualUser"
            state.antiAfkPulses += 1
            state.antiAfkLastPulse = os.time()
            state.antiAfkLastError = nil
            return true
        end

        state.antiAfkLastError = tostring(pulseErr)
    end

    local vimOk, virtualInput = pcall(function()
        return game:GetService("VirtualInputManager")
    end)
    if vimOk and virtualInput then
        local pulseOk, pulseErr = pcall(function()
            virtualInput:SendKeyEvent(true, Enum.KeyCode.LeftShift, false, game)
            task.wait(0.04)
            virtualInput:SendKeyEvent(false, Enum.KeyCode.LeftShift, false, game)
        end)

        if pulseOk then
            state.antiAfkMode = "VirtualInputManager"
            state.antiAfkPulses += 1
            state.antiAfkLastPulse = os.time()
            state.antiAfkLastError = nil
            return true
        end

        state.antiAfkLastError = tostring(pulseErr)
    end

    state.antiAfkMode = "Unavailable"
    if not state.antiAfkLastError then
        state.antiAfkLastError = "VirtualUser and VirtualInputManager unavailable"
    end
    warn("[FA V4.3][ANTI-AFK] pulse failed:", tostring(reason), state.antiAfkLastError)
    return false
end

function FarmRuntime.initializeAntiAfk()
    if not LocalPlayer then
        state.antiAfkMode = "Unavailable"
        state.antiAfkLastError = "LocalPlayer unavailable"
        return false
    end

    state.antiAfkEnabled = true
    state.antiAfkMode = "Armed"
    state.antiAfkLastError = nil
    FarmRuntime.antiAfkGeneration = (FarmRuntime.antiAfkGeneration or 0) + 1

    local generation = state.generation
    local antiAfkGeneration = FarmRuntime.antiAfkGeneration

    local idledConnection = LocalPlayer.Idled:Connect(function()
        if state.running
            and state.antiAfkEnabled
            and state.generation == generation
            and FarmRuntime.antiAfkGeneration == antiAfkGeneration then
            task.spawn(FarmRuntime.antiAfkPulse, "Idled")
        end
    end)
    connections[#connections + 1] = idledConnection

    task.spawn(function()
        while state.running
            and state.antiAfkEnabled
            and state.generation == generation
            and FarmRuntime.antiAfkGeneration == antiAfkGeneration do
            -- Roblox's idle kick window is much longer than this; pulsing every
            -- eight minutes gives a large safety margin without spamming input.
            task.wait(480)

            if not state.running
                or not state.antiAfkEnabled
                or state.generation ~= generation
                or FarmRuntime.antiAfkGeneration ~= antiAfkGeneration then
                break
            end

            FarmRuntime.antiAfkPulse("Keepalive")
        end
    end)

    return true
end

-- ============================================================
-- Cleanup / bootstrap
-- ============================================================
App.ClearAllPending = function()
    for holder, pending in pairs(pendingHolders) do
        if pending then safeDisconnect(pending.childAdded) end
        pendingHolders[holder] = nil
    end
end

function App.GetDiagnostics()
    return {
        running = state.running == true,
        version = AroynWeb.clientVersion,
        linked = AroynWeb.ValidKey(AroynWeb.key),
        liveConnected = AroynWeb.liveConnected == true,
        pushSucceeded = AroynWeb.lastPushOk == true,
        serverAckReceived = type(AroynWeb.liveLastAckAt) == "number",
        httpSnapshotAccepted = (tonumber(AroynWeb.lastHttpPushClock) or 0) > 0,
        presenceSucceeded = AroynWeb.presenceLastOk == true,
        verificationOnly = verificationOnly,
        cash = tonumber(GameState.cash),
        petFeedStatus = FarmRuntime.PetFeed.status,
        petFeedConfirmed = FarmRuntime.PetFeed.confirmed,
        compactGui = ui.IsCompact == true,
        automationEnabled = state.autoBuyEnabled or state.autoCompostEnabled or state.autoFeedPetsEnabled
            or state.autoCollectFruits or state.autoCollectLeaves
            or state.autoCollectPetSeeds or state.autoMarketEnabled,
    }
end

function App.Destroy()
    if not state.running or state.stopping then return end
    state.stopping = true
    if Options.Startup then Options.Startup:OnRuntimeDestroy() end

    pcall(saveSettingsNow)
    if ui.Integration and ui.Integration.AutoPreferences then ui.Integration.AutoPreferences:Flush() end
    state.antiAfkEnabled = false
    FarmRuntime.antiAfkGeneration = (FarmRuntime.antiAfkGeneration or 0) + 1
    state.hidePlotVisuals = false
    pcall(FarmRuntime.destroyPlotVisualOptimization)
    IntegrationController.CancelNetwork()
    state.running = false
    state.generation += 1
    saveRevision += 1
    -- Return movement ownership before network disconnect can yield. A new
    -- client must not inherit a later position restore from this instance.
    pcall(FarmRuntime.releaseCompostTeleport)
    pcall(function() FarmRuntime.finishPetSeedTeleport(PetSeedRuntime.activeTicket) end)
    pcall(function() FarmRuntime.finishLeafTeleport(FarmRuntime.LeafRuntime.activeTicket) end)
    pcall(FarmRuntime.finishMarketTeleport)
    local operation = FarmRuntime.AutomationRuntime.operation
    if operation then
        operation.cancelled = true
        FarmRuntime.cancelFeatureClaim(operation)
        FarmRuntime.AutomationRuntime.operation = nil
    end
    FarmRuntime.AutomationRuntime.owner = nil
    FarmRuntime.AutomationRuntime.since = 0
    pcall(function() AroynWeb.Stop(true) end)

    queueRevision += 1
    queueWorkerScheduled = false
    for _, entry in ipairs(triggerQueue) do
        if entry.holder then queuedHolders[entry.holder] = nil end
    end
    table.clear(triggerQueue)

    collectRevision += 1
    collectWorkerScheduled = false
    for _, entry in ipairs(collectQueue) do
        if entry.fruit then queuedFruits[entry.fruit] = nil end
    end
    table.clear(collectQueue)
    table.clear(pendingSeedConfirmations)
    table.clear(pendingFruitTriggers)
    table.clear(recentFruitInventoryAdds)
    table.clear(recentFruitCollectedEvents)
    pcall(FarmRuntime.invalidatePetSeedQueue)

    FarmRuntime.MarketRuntime.workerRevision += 1
    FarmRuntime.MarketRuntime.workerScheduled = false
    pcall(FarmRuntime.finishMarketTeleport)

    safeDisconnect(conveyorConnection)
    conveyorConnection = nil

    if maintenanceThread then
        if type(task.cancel) == "function" then pcall(task.cancel, maintenanceThread) end
        maintenanceThread = nil
    end

    pcall(App.ClearAllPending)
    pcall(FarmRuntime.destroyCompost)
    pcall(FarmRuntime.clearOwnPlotConnections)
    for plot, conn in pairs(plotCandidateConnections) do
        safeDisconnect(conn)
        plotCandidateConnections[plot] = nil
    end

    for i = #connections, 1, -1 do
        safeDisconnect(connections[i])
        connections[i] = nil
    end

    if ui.Integration then
        local owned=ui.Integration;ui.Integration=nil;pcall(function() owned:Destroy() end)
    end
    if ui.ScreenGui then pcall(function() ui.ScreenGui:Destroy() end) end
    env.__AROYN_HUB_REVEAL_MAIN_GUI = nil

    currentConveyor = nil
    bigField = nil
    ownPlot = nil
    playerPlots = nil

    if rawget(env, GLOBAL_KEY) == App then rawset(env, GLOBAL_KEY, nil) end
    if rawget(env, LEGACY_GLOBAL_KEY) == App then rawset(env, LEGACY_GLOBAL_KEY, nil) end
    for _, key in ipairs({"__FARM_ASSISTANT_V3_SINGLETON", "__SEED_AUTO_BUY_SINGLETON_V1"}) do
        if rawget(env, key) == App then rawset(env, key, nil) end
    end
end

if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "MAIN 06 definitions loaded") end

local function startupStage(id,label)
    if Options.Startup then Options.Startup:Complete(id,label) end
end
App.Bootstrap = function()
    if App.Bootstrapped then return true end
    assert(not App.Bootstrapping and state.running,"Client startup is already running or was cancelled")
    App.Bootstrapping=true
    if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "BOOT 00 bootstrap entered") end

    local ok, err = pcall(function()
            local initialConveyor = acquireGameObjects()
            startupStage("game","Game objects acquired")
            if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "BOOT 02 acquireGameObjects OK") end

            buildSeedDatabase()
            startupStage("seeds","Seed database prepared")
        task.wait()
    
            loadSettings() -- read-only migration defaults
            -- Every launch requires explicit consent for gameplay automation.
            for _,key in ipairs({"autoBuyEnabled","autoCompostEnabled","autoCollectFruits","autoCollectLeaves","autoCollectPetSeeds","autoMarketEnabled","autoFeedPetsEnabled","hidePlotVisuals"}) do state[key]=false end
        -- Explicit verification mode suppresses restored farming controls and
        -- skips settings writes. Anti-AFK and telemetry remain available.
        if verificationOnly then
            state.autoBuyEnabled = false
            state.autoCompostEnabled = false
            state.autoCollectFruits = false
            state.autoCollectLeaves = false
            state.autoCollectPetSeeds = false
            state.autoMarketEnabled = false
            state.autoFeedPetsEnabled = false
            state.tpAutoCollectFruits = false
            state.hidePlotVisuals = false
        end
        task.wait()
    
            startupStage("preferences","Legacy preferences restored; automation off")
            normalizePriorities()
            if not rarityIndex[state.alertRarity] then
            state.alertRarity = rarityIndex.MYTHIC and "MYTHIC" or (rarityOrder[1] or "COMMON")
        end

            local cashReady, cashSource = hydrateInitialCashSnapshot(true)
    
            ui.CreateGui()
            startupStage("interface","Interface and preferences prepared")
        task.wait()
            if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "BOOT 10 createGui OK") end

            attachConveyor(initialConveyor)
        task.wait()
    
            addConnection(bigField.ChildAdded:Connect(function(child)
            if state.running and child.Name == "ConveyorSeeds" then
                task.defer(function()
                    if state.running and child.Parent == bigField then
                        App.ClearAllPending()
                        attachConveyor(child)
                        setStatus("Watching replacement conveyor", state.autoBuyEnabled and "good" or "neutral")
                    end
                end)
            elseif state.running and child.Name == "PlayerPlots" and child ~= playerPlots then
                task.defer(function()
                    if state.running then FarmRuntime.initializeOwnPlotMonitor() end
                end)
            end
        end))
        addConnection(bigField.ChildRemoved:Connect(function(child)
            if state.running and child == currentConveyor then
                safeDisconnect(conveyorConnection)
                conveyorConnection = nil
                invalidateQueue()
                App.ClearAllPending()
                currentConveyor = nil
                setStatus("Conveyor unavailable", "bad")
            elseif state.running and child == playerPlots then
                FarmRuntime.clearOwnPlotConnections()
                for plot, conn in pairs(plotCandidateConnections) do
                    safeDisconnect(conn)
                    plotCandidateConnections[plot] = nil
                end
                playerPlots = nil
                if ui.RefreshFarm then ui.RefreshFarm() end
                if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
            end
        end))

    
            FarmRuntime.initializeOwnPlotMonitor()
        task.wait()
    
            FarmRuntime.initializeObservedRemotes()
        task.wait()
    
            local compostReady = FarmRuntime.initializeCompost()
        task.wait()

            local marketReady = FarmRuntime.initializeMarket()
        task.wait()

        if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then
            pcall(
                env.__AROYN_HUB_STARTUP_EMIT,
                (compostReady and marketReady)
                    and "BOOT 20 runtime systems initialized"
                    or "BOOT 20 one or more runtime integrations degraded; continuing"
            )
        end

        local antiAfkReady = FarmRuntime.initializeAntiAfk()
        startupStage("observers",(compostReady and marketReady) and "Runtime observers prepared" or "Runtime observers prepared; optional integrations degraded")
        addActivity(
            antiAfkReady and "Anti-AFK armed · dual guard" or "Anti-AFK unavailable",
            antiAfkReady and "success" or "warning"
        )

        if state.configSource == "Embedded Snapshot" then
            addActivity("Config: Embedded Snapshot", "warning")
        else
            addActivity("Config: Live SeedConfig", "success")
        end
        if state.settingsMigrated then
            addActivity("Legacy preferences imported; automation stays off", "normal")
            -- Migration is not saved until the user explicitly saves or enables AutoSave.
        elseif state.settingsAvailable then
            addActivity("Preferences ready; Save is explicit", "normal")
        end

        if state.settingsAvailable and (
            state.autoBuyEnabled
            or state.autoCompostEnabled
            or state.autoCollectFruits
            or state.autoCollectLeaves
            or state.autoCollectPetSeeds
            or state.autoMarketEnabled
        ) then
            addActivity("Last session automation restored", "success")
        end

            if ui.RefreshHeader then ui.RefreshHeader() end
        if ui.RefreshFarm then ui.RefreshFarm() end
        if ui.RefreshInventory then ui.RefreshInventory() end
        task.wait()
        if ui.RefreshSession then ui.RefreshSession() end
        if ui.RefreshIncoming then ui.RefreshIncoming() end
        if ui.RefreshDiagnostics then ui.RefreshDiagnostics() end
        task.wait()
        if ui.RefreshCompost then ui.RefreshCompost() end
        if ui.UpdatePipeline then ui.UpdatePipeline() end
        if ui.RefreshBuyControls then ui.RefreshBuyControls() end
    
        local updaterGeneration = state.generation
        maintenanceThread = task.spawn(function()
            while state.running and state.generation == updaterGeneration do
                task.wait(1)
                if not state.running or state.generation ~= updaterGeneration then break end
                FarmRuntime.expireV3TransientState()
                if ui.TickSecond then ui.TickSecond() end
                if ui.RefreshPetFeed then ui.RefreshPetFeed() end
                if state.autoFeedPetsEnabled then FarmRuntime.schedulePetFeed() end
            end
        end)

        setStatus("Aroyn Hub ready", "good")
        startupStage("ready","Ready · Dashboard connection is optional")
        if not Options.Startup then IntegrationController.Dashboard:Resume() end
            if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "BOOT 23 READY") end
    end)

    App.Bootstrapping=false
    if not ok then
        if Options.Startup then return false,err end
        warn("[FA V4.3][BOOT FAIL] Initialization failed:", err)
        if type(env.__AROYN_HUB_STARTUP_EMIT) == "function" then pcall(env.__AROYN_HUB_STARTUP_EMIT, "BOOT FAIL " .. tostring(err)) end
        App.Destroy()
        error("[FA V4.3] " .. tostring(err), 0)
    end
    App.Bootstrapped=true
    return true
end

if not Options.DeferBootstrap then App.Bootstrap() end
return App


end
local function MetadataFactory()
return {Namespace="greedy-growers",StorageRoot="AroynHub",CredentialPath="AroynHub/GreedyGrowers/web_config.json",AssetRoot="AroynHub/ui-assets",RuntimeId="__AROYN_HUB_GREEDY",StartupId="__AROYN_HUB_STARTUP",DisplayVersion="Version 4.3.96",Phase="11C.1-mobile-sidebar-polish",BaselineVersion="4.3.95",ClientVersion="4.3.96",Channel="release-candidate",Flavor="production"}
end
return StartupFactory().Run(LoadAroyn(),MetadataFactory(),AssetFactory(),Runtime,UIFactory(),{DashboardAutoConnect=false,Storage=HubStorage})
