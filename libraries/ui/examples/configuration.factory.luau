-- Application-owned example: no gameplay, telemetry or automatic loading.
return function(Aroyn, parent)
    local window=Aroyn:CreateWindow({Parent=parent,Id="config-example",Title="AROYN",Logo=Aroyn.Logo,
        Config={Namespace="config-example",AutoLoad=false,AutoSave=false}})
    local section=window:CreatePage({Name="Preferences",Icon="components"}):CreateSection({Title="Local settings"})
    section:CreateToggle({Name="Enabled",Flag="enabled",Default=false})
    section:CreateSlider({Name="Volume",Flag="volume",Min=0,Max=100,Default=40})
    section:CreateButton({Name="Save",Text="Save",Callback=function() window:SaveConfig("main") end})
    section:CreateButton({Name="Load",Text="Load",Callback=function() window:LoadConfig("main") end})
    section:CreateButton({Name="Reset",Text="Reset",Callback=function() window:ResetConfig() end})
    section:CreateButton({Name="Close",Text="Destroy",Callback=function() window:Destroy() end})
    return window
end
