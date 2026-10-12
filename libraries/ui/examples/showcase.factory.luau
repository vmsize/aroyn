-- Full local example. Load Aroyn separately; the caller chooses Parent.
-- Returns Window and named handles for integration/testing. No gameplay/network.
return function(Aroyn, parent)
    local window=Aroyn:CreateWindow({
        Parent=parent,Id="complete-example",Title="AROYN",Logo=Aroyn.Logo,
        Size=UDim2.fromOffset(680,500),
        Config={Namespace="complete-demo",AutoSave=false,AutoLoad=false},
    })
    local controls={}
    local function report(ok,info)
        window:Notify({Title=ok and "Configuration updated" or "Configuration error",
            Description=info.Message..(info.Mode=="Session" and " (this window only)" or ""),
            Type=ok and "Success" or "Error"})
        return ok,info
    end
    local general=window:CreatePage({Name="General",Icon="settings"})
    local preferences=general:CreateSection({Title="Preferences"})
    controls.Enabled=preferences:CreateToggle({Name="Enable local example",Flag="enabled",
        Callback=function(value) print("Local enabled:",value) end})
    controls.Note=preferences:CreateTextInput({Name="Note",Flag="note",Default="Aroyn",
        Placeholder="Local note",SubmitOnEnter=true,Callback=function(value) print("Note:",value) end})
    controls.Volume=preferences:CreateSlider({Name="Volume",Flag="volume",Min=0,Max=100,
        Step=5,Default=40,Suffix="%",Callback=function(value) print("Volume:",value) end})
    controls.Mode=preferences:CreateDropdown({Name="Display mode",Flag="mode",
        Options={"Quiet","Detailed"},Default="Quiet",Callback=function(value) print("Mode:",value) end})
    controls.Categories=preferences:CreateDropdown({Name="Categories",Flag="categories",Multi=true,
        Options={"UI","Documentation","Tests"},Default={"UI"},Callback=function(values) print(table.concat(values,", ")) end})
    local shortcuts=general:CreateSection({Title="Shortcuts and appearance"})
    controls.Key=shortcuts:CreateKeybind({Name="Local shortcut",Flag="shortcut",Default="H",Mode="Toggle",
        Callback=function(key) print("Binding:",key and key.Name or "None") end,
        OnActivate=function(active,key,mode) print("Local activation:",active,key,mode) end})
    controls.Color=shortcuts:CreateColorPicker({Name="Preview color",Flag="color",
        Default=Color3.fromRGB(164,184,169),Callback=function(color) print("Color:",color) end})
    controls.Update=shortcuts:CreateButton({Name="Change values",Text="Update locally",Callback=function()
        controls.Enabled:SetValue(not controls.Enabled:GetValue(),true)
        controls.Volume:SetValue(65) -- silent binding callback; AutoSave still sees this change
        controls.Note:SetValue("Updated locally")
    end})
    local feedback=window:CreatePage({Name="Feedback",Icon="components"})
    local toasts=feedback:CreateSection({Title="Notifications"})
    controls.Info=toasts:CreateButton({Name="Single notification",Text="Show info",Callback=function()
        window:Notify({Title="Local example",Description="No game actions are performed.",Type="Info"})
    end})
    controls.Queue=toasts:CreateButton({Name="Stack and FIFO",Text="Show five",Callback=function()
        for i=1,5 do window:Notify({Title="Message "..i,Type=i%2==0 and "Success" or "Info",Duration=2}) end
    end})
    local persistent
    controls.Persistent=toasts:CreateButton({Name="Persistent notification",Text="Show / dismiss",Callback=function()
        if persistent and persistent:GetState()~="Dismissed" then persistent:Dismiss();persistent=nil
        else persistent=window:Notify({Title="Persistent example",Description="Press this button again or use X.",Duration=0}) end
    end})
    local dialogs=feedback:CreateSection({Title="Dialogs"})
    controls.Alert=dialogs:CreateButton({Name="Alert",Text="Show alert",Callback=function()
        window:Dialog({Title="Local alert",Description="Acknowledge this demonstration.",
            OnAcknowledge=function() print("Acknowledged") end})
    end})
    controls.Confirm=dialogs:CreateButton({Name="Confirmation",Text="Show confirm",Callback=function()
        window:Dialog({Type="Confirm",Title="Confirm example?",Description="Only a local message is printed.",
            OnConfirm=function() print("Confirmed locally") end,OnCancel=function(reason) print("Cancelled:",reason) end})
    end})
    controls.Custom=dialogs:CreateButton({Name="Custom decision",Text="Choose action",Callback=function()
        window:Dialog({Type="Custom",Title="Choose a local action",Actions={
            {Id="print",Text="Print",Primary=true,Callback=function() print(controls.Note:GetValue()) end},
            {Id="skip",Text="Skip",Callback=function() print("Skipped") end},
        },OnDismiss=function(reason,action) print("Dialog closed:",reason,action) end})
    end})
    local configs=window:CreatePage({Name="Configurations",Icon="compost"})
    local storage=configs:CreateSection({Title="Local storage"})
    controls.Storage=storage:CreateTextInput({Name="Storage mode",Disabled=true,Persist=false})
    controls.ConfigName=storage:CreateTextInput({Name="Configuration name",Default="main",Persist=false,
        Callback=function(value)
            if controls.AutoSave:GetValue() then report(window:SetConfigAutoSave(true,value)) end
        end})
    controls.ConfigSelection=storage:CreateDropdown({Name="Saved configuration",Options={},Persist=false,
        Callback=function(value) if value then controls.ConfigName:SetValue(value) end end})
    local function refresh(selected)
        local ok,info=window:ListConfigs()
        if ok then
            controls.ConfigSelection:SetOptions(info.Names)
            if selected then controls.ConfigSelection:SetValue(selected) end
        end
        local status=window:GetConfigStatus()
        controls.Storage:SetValue(status.Mode=="File" and "Local files" or "Session only")
        controls.AutoSave:SetValue(status.AutoSave)
        return ok,info
    end
    local actions=configs:CreateSection({Title="Save and restore"})
    controls.Save=actions:CreateButton({Name="Save current values",Text="Save",Variant="Primary",Callback=function()
        local ok,info=report(window:SaveConfig(controls.ConfigName:GetValue()));refresh(ok and info.Name or nil)
    end})
    controls.Load=actions:CreateButton({Name="Restore values silently",Text="Load",Callback=function()
        local name=controls.ConfigSelection:GetValue() or controls.ConfigName:GetValue()
        local ok,info=report(window:LoadConfig(name));if ok then controls.ConfigName:SetValue(info.Name);refresh(info.Name) end
    end})
    controls.Delete=actions:CreateButton({Name="Delete saved configuration",Text="Delete",Callback=function()
        local name=controls.ConfigSelection:GetValue() or controls.ConfigName:GetValue()
        window:Dialog({Type="Confirm",Title="Delete configuration?",Description="Delete '"..name.."' from local storage.",
            OnConfirm=function() report(window:DeleteConfig(name));refresh() end})
    end})
    controls.Reset=actions:CreateButton({Name="Restore construction defaults",Text="Reset defaults",Callback=function()
        report(window:ResetConfig());refresh()
    end})
    controls.AutoSave=actions:CreateToggle({Name="AutoSave",Persist=false,Callback=function(value)
        local ok=report(window:SetConfigAutoSave(value,controls.ConfigName:GetValue(),0.75))
        if not ok then controls.AutoSave:SetValue(false) end
    end})
    controls.Refresh=actions:CreateButton({Name="Refresh saved names",Text="Refresh",Callback=function() report(refresh()) end})
    local lifecycle=configs:CreateSection({Title="Window lifecycle"})
    controls.Minimize=lifecycle:CreateButton({Name="Floating launcher",Text="Minimize",Callback=function() window:SetMinimized(true) end})
    controls.Cleanup=lifecycle:CreateButton({Name="Remove this demo",Text="Destroy window",Callback=function() window:Destroy() end})
    refresh()
    -- For startup restoration, call LoadConfig after all controls have been registered.
    -- Alternatively Config.AutoLoad="main" restores matching flags as they are created.
    window:SelectPage("General",false)
    return window,controls
end
