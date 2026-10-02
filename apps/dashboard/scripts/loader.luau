-- Aroyn Hub stable loader. Save this URL once; the manifest selects the release.
-- This free Pages address is fixed deliberately; no executor key is embedded.
local BASE = "https://aroyn-staging.pages.dev"
local MAX_SOURCE_BYTES = 900000
local MAX_MANIFEST_BYTES = 4096

if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 10440833423 then
    warn("[Aroyn] This release supports Greedy Growers only.")
    return
end
if type(loadstring) ~= "function" then
    warn("[Aroyn] Luau compilation is unavailable in this environment.")
    return
end

local manifestOk, manifest = pcall(function()
    local raw = game:HttpGet(BASE .. "/scripts/version.json?t=" .. tostring(os.time()))
    if type(raw) ~= "string" or #raw == 0 or #raw > MAX_MANIFEST_BYTES then
        error("invalid release manifest size")
    end
    return game:GetService("HttpService"):JSONDecode(raw)
end)
local RELEASE = manifestOk and type(manifest) == "table" and manifest.version or nil
if type(RELEASE) ~= "string" or #RELEASE > 32
    or not RELEASE:match("^%d+%.%d+%.%d+$") then
    warn("[Aroyn] Could not check the current release. Try again later.")
    return
end

local ok, source = pcall(function()
    return game:HttpGet(BASE .. "/releases/" .. RELEASE .. "/greedy-growers.luau")
end)
if not ok or type(source) ~= "string" or #source == 0 or #source > MAX_SOURCE_BYTES then
    warn("[Aroyn] Could not download this release. Try again later.")
    return
end
-- A missing asset may return the site's HTML fallback with HTTP 200.
if source:sub(1, 80):lower():find("<!doctype", 1, true)
    or source:sub(1, 80):lower():find("<html", 1, true) then
    warn("[Aroyn] The script release is not available at this address.")
    return
end
local fn, compileError = loadstring(source, "@AroynHub_" .. RELEASE)
if not fn then
    warn("[Aroyn] Could not compile the release: " .. tostring(compileError))
    return
end
local started, startupError = pcall(fn)
if not started then
    warn("[Aroyn] Startup failed: " .. tostring(startupError))
end
