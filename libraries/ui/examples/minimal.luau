-- Copy dist/Aroyn.lua into this path in the executor's filesystem first.
assert(type(readfile)=="function" and type(loadstring)=="function","Local installation requires readfile and loadstring")
local Aroyn=assert(loadstring(readfile("AroynUI/Aroyn.lua")))()
local parent=game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
local window=Aroyn:CreateWindow({Parent=parent,Id="distribution-minimal",Title="AROYN",Logo=Aroyn.Logo})
local page=window:CreatePage({Name="General",Icon="components"})
local section=page:CreateSection({Title="Preferences"})
section:CreateToggle({Name="Enabled",Default=false,Callback=function(value) print("Enabled:",value) end})
section:CreateButton({Name="Cleanup",Text="Destroy window",Callback=function() window:Destroy() end})
return window
