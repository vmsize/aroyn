-- Aroyn is the return value of the local library; caller chooses the GUI parent.
return function(Aroyn, parent)
    local window=Aroyn:CreateWindow({
        Parent=parent,Id="basic-example",Title="AROYN",Size=UDim2.fromOffset(680,440),Logo=Aroyn.Logo,
    })
    local page=window:CreatePage({Name="General",Icon="settings"})
    local section=page:CreateSection({Title="Local examples"})
    local enabled=section:CreateToggle({Name="Enable example",Description="Only local state changes.",Default=false,
        Callback=function(value) print("Example:",value) end})
    local input=section:CreateTextInput({Name="Note",Placeholder="Type a note",Default="Aroyn",SubmitOnEnter=true,
        Callback=function(value) print("Note:",value) end})
    section:CreateButton({Name="Update locally",Text="Update values",Variant="Secondary",
        Callback=function()
            enabled:SetValue(not enabled:GetValue()) -- silent by default
            input:SetValue(enabled:GetValue() and "Enabled" or "Disabled")
        end})
    section:CreateSlider({Name="Percentage",Min=0,Max=100,Step=5,Default=40,Suffix="%",
        Callback=function(value) print("Percentage:",value) end})
    section:CreateDropdown({Name="Mode",Options={"Balanced","Quiet","Detailed"},Default="Balanced",
        Callback=function(value) print("Mode:",value) end})
    section:CreateKeybind({Name="Local shortcut",Default="H",Mode="Toggle",
        Callback=function(key) print("Binding:",key and key.Name or "None") end,
        OnActivate=function(active) print("Shortcut:",active) end})
    section:CreateColorPicker({Name="Preview color",Default=Color3.fromRGB(164,184,169),
        Callback=function(color) print("Color:",color) end})
    -- BEGIN OVERLAY EXAMPLE
    local overlays=page:CreateSection({Title="Notifications and dialogs"})
    overlays:CreateButton({Name="Notification",Text="Show toast",Callback=function()
        window:Notify({Title="Settings saved",Description="Local API demonstration.",Type="Success",Duration=4})
    end})
    overlays:CreateButton({Name="Confirmation",Text="Show dialog",Callback=function()
        window:Dialog({Type="Confirm",Title="Confirm example?",Description="Only prints the chosen result.",
            OnConfirm=function() print("Confirmed") end,OnCancel=function(reason) print("Cancelled:",reason) end})
    end})
    -- END OVERLAY EXAMPLE
    -- BEGIN CONFIG EXAMPLE
    window:ConfigureConfig({Namespace="basic-demo"})
    for _,part in ipairs(section.Components) do
        if part.Kind~="Button" then window:RegisterConfig(part,({Toggle="enabled",Input="note",Slider="percentage",
            Dropdown="mode",Keybind="shortcut",ColorPicker="color"})[part.Kind]) end
    end
    local buildConfigs=(function()
-- Demo adapter only. All storage/restoration is performed by the reusable Window API.
return function(window,page)
    local section=page:CreateSection({Title="Configurations"})
    local demo={}
    local function feedback(ok,info)
        window:Notify({Title=ok and "Configuration updated" or "Configuration error",Type=ok and "Success" or "Error",
            Description=info.Message..(info.Mode=="Session" and " · this window only" or ""),Duration=4})
    end
    local function refresh(selected)
        local ok,info=window:ListConfigs()
        if ok then demo.Selection:SetOptions(info.Names);if selected then demo.Selection:SetValue(selected) end end
        local status=window:GetConfigStatus()
        demo.Storage:SetValue(status.Mode=="File" and "Local files · "..status.Namespace or "Session only · no filesystem")
        demo.AutoSave:SetValue(status.AutoSave)
        return ok,info
    end
    demo.Storage=section:CreateTextInput({Name="Storage",Default="",Disabled=true,Persist=false})
    demo.Selection=section:CreateDropdown({Name="Saved configuration",Options={},Persist=false,Callback=function(value)
        if value then demo.Name:SetValue(value) end
    end})
    demo.Name=section:CreateTextInput({Name="Configuration name",Default="main",Placeholder="main",Persist=false,
        Callback=function(value)
            if demo.AutoSave:GetValue() then feedback(window:SetConfigAutoSave(true,value)) end
        end})
    demo.Save=section:CreateButton({Name="Save current values",Text="Save",Callback=function()
        local ok,info=window:SaveConfig(demo.Name:GetValue());feedback(ok,info);refresh(ok and info.Name or nil)
    end})
    demo.Load=section:CreateButton({Name="Restore UI values silently",Text="Load",Callback=function()
        local n=demo.Selection:GetValue() or demo.Name:GetValue()
        local ok,info=window:LoadConfig(n);feedback(ok,info)
        if ok then demo.Name:SetValue(info.Name);refresh(info.Name) end
    end})
    demo.Delete=section:CreateButton({Name="Remove saved configuration",Text="Delete",Callback=function()
        local n=demo.Selection:GetValue() or demo.Name:GetValue()
        demo.LastDialog=window:Dialog({Type="Confirm",Title="Delete configuration?",Description="Remove the saved configuration '"..n.."'.",
            OnConfirm=function() feedback(window:DeleteConfig(n));refresh() end})
    end})
    demo.Reset=section:CreateButton({Name="Restore construction defaults",Text="Reset defaults",Callback=function()
        feedback(window:ResetConfig());refresh()
    end})
    demo.AutoSave=section:CreateToggle({Name="AutoSave",Default=false,Persist=false,Callback=function(value)
        local ok,info=window:SetConfigAutoSave(value,demo.Name:GetValue(),0.75)
        if not ok then feedback(ok,info);demo.AutoSave:SetValue(false) end
    end})
    demo.Refresh=section:CreateButton({Name="Refresh configuration list",Text="Refresh",Callback=function() feedback(refresh()) end})
    refresh()
    return demo
end

    end)()
    buildConfigs(window,page)
    -- END CONFIG EXAMPLE
    return window
end
