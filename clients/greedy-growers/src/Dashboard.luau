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
