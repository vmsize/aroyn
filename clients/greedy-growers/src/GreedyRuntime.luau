
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

