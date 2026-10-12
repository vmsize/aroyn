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
