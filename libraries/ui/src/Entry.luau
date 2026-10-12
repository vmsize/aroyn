-- Aroyn UI standalone local development artifact. No public release or endpoint.
-- Loading returns the approved API; it does not create windows or input listeners.
local Aroyn=(function()
@@CORE@@
end)()
local attachAssets=(function()
@@ADAPTER@@
end)()
Aroyn.Distribution={Library="aroyn-ui",Version=@@VERSION@@,Channel="development",CoreSHA256=@@CORE_HASH@@}
Aroyn.Distribution.Assets=attachAssets(Aroyn,{
@@PAYLOAD@@
})
return Aroyn
