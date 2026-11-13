--!nocheck
-- Egg Auto-Farm | Roblox executor | Lua
-- Edit CONFIG below for the target game. Everything else is generic.

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local VirtualUser       = game:GetService("VirtualUser")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")
local LP = Players.LocalPlayer

-- ============================================================
-- CONFIG — tune per game
-- ============================================================
local CONFIG = {
    autoEvent      = true,   -- fire the event egg remote when it spawns
    invisible      = true,   -- hide character from others (local noclip-ish)
    autoConveyor   = true,   -- ride/collect along the conveyor
    autoPlace      = true,   -- place collected egg at base
    scanInterval   = 0.25,   -- seconds between scans
    -- remote names — rename to match the live game
    remotes = {
        collectEgg = "CollectEgg",
        placeEgg   = "PlaceEgg",
        eventClaim = "ClaimEvent",
        getEggData = "GetEggInfo",
    },
    -- egg model naming pattern, used to enumerate spawns
    eggPrefix = "Egg",
    baseName  = "Base",
}
-- ============================================================

local remotes = {}
for _, name in pairs(CONFIG.remotes) do
    local ok, obj = pcall(function()
        return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(name)
    end)
    if ok and obj then remotes[name] = obj end
end

local eggCache = {}   -- [eggModel] = {value=, rarity=}
local knownEggs = {}

-- ---------- egg value / rarity read ----------
local function readEggData(eggModel)
    if eggCache[eggModel] then return eggCache[eggModel] end
    local data = { value = 0, rarity = "Common" }
    -- common patterns: attributes, Value objects, or a remote call
    local ok, v = pcall(function() return eggModel:GetAttribute("Value") end)
    if ok and v then data.value = v end
    local ok2, r = pcall(function() return eggModel:GetAttribute("Rarity") end)
    if ok2 and r then data.rarity = r end
    -- fallback: probe the data remote
    if remotes.getEggData then
        pcall(function()
            local res = remotes.getEggData:InvokeServer(eggModel.Name)
            if type(res) == "table" then
                data.value  = res.Value  or data.value
                data.rarity = res.Rarity or data.rarity
            end
        end)
    end
    eggCache[eggModel] = data
    return data
end

-- ---------- collect nearest egg ----------
local function findNearestEgg()
    local best, bestDist
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj.Name:sub(1, #CONFIG.eggPrefix) == CONFIG.eggPrefix then
            local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
            if part then
                local d = (part.Position - root.Position).Magnitude
                if not bestDist or d < bestDist then best, bestDist = obj, d end
            end
        end
    end
    return best
end

local function collect(eggModel)
    if not eggModel then return end
    local data = readEggData(eggModel)
    print(("[egg] collecting %s  value=%s rarity=%s"):format(eggModel.Name, tostring(data.value), data.rarity))
    if remotes.collectEgg then
        pcall(function() remotes.collectEgg:FireServer(eggModel) end)
    end
end

-- ---------- place egg at base ----------
local function placeAtBase()
    local base = Workspace:FindFirstChild(CONFIG.baseName, true)
    if not base or not remotes.placeEgg then return end
    pcall(function() remotes.placeEgg:FireServer(base) end)
end

-- ---------- invisibility (local-only visual hide) ----------
local function applyInvisible()
    if not CONFIG.invisible then return end
    local char = LP.Character
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") or d:IsA("Decal") then
            pcall(function() d.Transparency = 1 end)
        end
    end
end

-- ---------- auto event ----------
local function tryEvent()
    if not CONFIG.autoEvent or not remotes.eventClaim then return end
    -- event eggs often spawn under an "Event" folder or tagged
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("Model") and obj:GetAttribute("IsEvent") then
            pcall(function() remotes.eventClaim:FireServer(obj) end)
        end
    end
end

-- ---------- auto conveyor ----------
local function rideConveyor()
    if not CONFIG.autoConveyor then return end
    local root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    -- find a part tagged Conveyor and stand on it
    for _, obj in ipairs(Workspace:GetDescendants()) do
        if obj:IsA("BasePart") and (obj.Name:lower():find("conveyor") or obj:GetAttribute("Conveyor")) then
            pcall(function() root.CFrame = obj.CFrame + Vector3.new(0, 3, 0) end)
            break
        end
    end
end

-- ---------- anti-AFK ----------
LP.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ---------- main loop ----------
local lastScan = 0
RunService.Heartbeat:Connect(function()
    local now = tick()
    if now - lastScan < CONFIG.scanInterval then return end
    lastScan = now

    applyInvisible()
    tryEvent()
    rideConveyor()

    local egg = findNearestEgg()
    if egg then
        collect(egg)
        if CONFIG.autoPlace then placeAtBase() end
    end
end)

print("[egg-farm] loaded. remotes found:", (function()
    local n = 0
    for _ in pairs(remotes) do n = n + 1 end
    return n
end)())
