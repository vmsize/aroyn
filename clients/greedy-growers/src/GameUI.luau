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
