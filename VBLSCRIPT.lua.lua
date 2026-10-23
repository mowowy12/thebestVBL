local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")
local SoundService = game:GetService("SoundService")

local function dbg(msg)
    if rconsoleprint then rconsoleprint("[SH] " .. tostring(msg) .. "\n")
    else print("[SH] " .. tostring(msg)) end
end
local function derr(msg)
    if rconsoleerror then rconsoleerror("[SH] " .. tostring(msg))
    else warn("[SH] " .. tostring(msg)) end
end

local TRACE = false
local function trace(msg) if TRACE then dbg(msg) end end

dbg("starting")
local lp = Players.LocalPlayer
local camera = Workspace.CurrentCamera
local rng
pcall(function() rng = Random.new() end)
local function pickRandom(t)
    if #t == 0 then return nil end
    if rng then return t[rng:NextInteger(1, #t)] end
    return t[math.random(#t)]
end

-- Filesystem / profiles

local ROOT = "scorehub"
local PROFILE_DIR = ROOT .. "/profiles"
local STATE_FILE = ROOT .. "/state_" .. tostring(lp.UserId) .. ".json"
local INDEX_FILE = ROOT .. "/profiles_" .. tostring(lp.UserId) .. ".json"

local fsOk = type(writefile) == "function" and type(readfile) == "function"
    and type(isfile) == "function"

local function ensureDirs()
    if not fsOk or type(makefolder) ~= "function" or type(isfolder) ~= "function" then return end
    pcall(function()
        if not isfolder(ROOT) then makefolder(ROOT) end
        if not isfolder(PROFILE_DIR) then makefolder(PROFILE_DIR) end
    end)
end

local function readJson(path, fallback)
    if not fsOk or not isfile(path) then return fallback end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(data) == "table" then return data end
    return fallback
end

local function writeJson(path, data)
    if not fsOk then return false end
    ensureDirs()
    local ok = pcall(function() writefile(path, HttpService:JSONEncode(data)) end)
    return ok
end

local function defaultConfig()
    return {
        effects = {},
        expand = false,
        mult = 3,
        chams = false,
        sound = true,
        volume = 1,
        chamsMat = "ForceField",
        chamsColor = "#4173FF",
        chamsColor2 = "#825AFF",
        chamsFill = 0.5,
        chamsOutline = true,
        touchFlash = true,
        touchColor = "#FF4DA6",
        pchams = false,
        pmode = "Highlight",
        pmat = "ForceField",
        pcolor = "#FF3F57",
        pcolor2 = "#825AFF",
        pfill = 0.6,
        poutline = true,
        pwalls = true,
        pteam = false,
        esp = false,
        espScope = "Enemies",
        espSound = true,
        lag = false,
        lagKey = "KC_T",
        lagMode = "Pulse",
        lagOnMs = 600,
        lagOffMs = 150,
        lagKbps = 3,
        lagCap = 12,
    }
end

local config = defaultConfig()
local state = readJson(STATE_FILE, { profile = "default", autoload = true })
local profileIndex = readJson(INDEX_FILE, { "default" })
local activeProfile = state.profile or "default"

local function profilePath(name)
    return PROFILE_DIR .. "/" .. tostring(lp.UserId) .. "_" .. name .. ".json"
end

local function saveState()
    state.profile = activeProfile
    writeJson(STATE_FILE, state)
end

local function indexHas(name)
    for _, n in ipairs(profileIndex) do if n == name then return true end end
    return false
end

local function saveProfile(name)
    name = name or activeProfile
    if not indexHas(name) then
        table.insert(profileIndex, name)
        writeJson(INDEX_FILE, profileIndex)
    end
    writeJson(profilePath(name), config)
    activeProfile = name
    saveState()
end

local saveToken = 0
local function saveSoon()
    saveToken = saveToken + 1
    local t = saveToken
    task.delay(0.4, function()
        if t == saveToken then saveProfile() end
    end)
end

local function loadProfile(name)
    local data = readJson(profilePath(name), nil)
    if not data then return false end
    config = defaultConfig()
    for k, v in pairs(data) do config[k] = v end
    config.expand = false
    activeProfile = name
    saveState()
    return true
end

local function deleteProfile(name)
    if name == "default" then return false end
    for i, n in ipairs(profileIndex) do
        if n == name then table.remove(profileIndex, i) break end
    end
    writeJson(INDEX_FILE, profileIndex)
    if type(delfile) == "function" then pcall(delfile, profilePath(name)) end
    if activeProfile == name then
        loadProfile("default")
    end
    return true
end

if state.autoload ~= false then
    if not loadProfile(activeProfile) then
        activeProfile = "default"
        saveProfile("default")
    end
    dbg("Profile: " .. activeProfile)
end

-- Game modules

local Knit, ContentItem, Entities, Maid, GameSound, InventoryService, BallService, equipRF, hitRE
do
local function req(module)
    local ok, res = pcall(require, module)
    if ok and res ~= nil then return res end
    pcall(function()
        local re = getrenv()
        if re and re.require then res = re.require(module) end
    end)
    return res
end

local function unwrap(x)
    if typeof(x) == "Instance" then return x end
    if type(x) ~= "table" then return nil end
    for _, k in ipairs({"_remote", "Remote", "Instance", "RE", "RF", "_r", "Signal"}) do
        local v = rawget(x, k)
        if typeof(v) == "Instance" then return v end
    end
    local ok, res = pcall(function()
        for _, v in pairs(x) do
            if typeof(v) == "Instance" then return v end
        end
    end)
    return ok and res or nil
end

local function path(root, ...)
    local cur = root
    for _, n in ipairs({ ... }) do
        if not cur then return nil end
        cur = cur:FindFirstChild(n)
    end
    return cur
end

local function findModule(name, ...)
    for _, root in ipairs({ ... }) do
        if root then
            local m = root:FindFirstChild(name, true)
            if m and m:IsA("ModuleScript") then return m end
        end
    end
    return nil
end

Knit = req(path(ReplicatedStorage, "Packages", "Knit") or ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Knit"))
ContentItem = req(path(ReplicatedStorage, "Content", "Item"))
Entities = path(ReplicatedStorage, "Content", "Item", "Entities")

Maid = req(path(ReplicatedStorage, "Packages", "Maid")
    or findModule("Maid", path(ReplicatedStorage, "Packages"), ReplicatedStorage))
if type(Maid) ~= "table" or type(Maid.new) ~= "function" then
    dbg("Maid not found, using fallback")
    Maid = {}
    Maid.__index = Maid
    function Maid.new() return setmetatable({ _t = {} }, Maid) end
    function Maid:GiveTask(t) table.insert(self._t, t) return t end
    function Maid:Destroy()
        for _, t in ipairs(self._t) do
            pcall(function()
                if typeof(t) == "RBXScriptConnection" then t:Disconnect()
                elseif typeof(t) == "Instance" then t:Destroy()
                elseif type(t) == "function" then t()
                elseif type(t) == "table" and t.Destroy then t:Destroy() end
            end)
        end
        self._t = {}
    end
    Maid.DoCleaning = Maid.Destroy
end

GameSound = req(path(ReplicatedStorage, "Tools", "Sound")
    or findModule("Sound", path(ReplicatedStorage, "Tools"), path(ReplicatedStorage, "Shared"),
        path(ReplicatedStorage, "Modules")))
dbg("modules: Knit=" .. tostring(Knit ~= nil) .. " Item=" .. tostring(ContentItem ~= nil)
    .. " Sound=" .. tostring(GameSound ~= nil))
if not Knit then derr("Knit missing, cannot continue") return end

local waited = 0
repeat
    pcall(function()
        InventoryService = InventoryService or Knit.GetService("InventoryService")
        BallService = BallService or Knit.GetService("BallService")
    end)
    if InventoryService and BallService then break end
    task.wait(0.2)
    waited = waited + 0.2
until waited > 15
if not (InventoryService and BallService) then
    derr("Knit services not ready after 15s: Inventory=" .. tostring(InventoryService ~= nil)
        .. " Ball=" .. tostring(BallService ~= nil))
    return
end

equipRF = unwrap(InventoryService.Equip)
hitRE = unwrap(BallService.HitGround)
pcall(function()
    local knitRoot = ReplicatedStorage.Packages._Index["sleitnick_knit@1.7.0"].knit.Services
    equipRF = equipRF or knitRoot.InventoryService.RF.Equip
    hitRE = hitRE or knitRoot.BallService.RE.HitGround
end)
end
dbg("Equip RF: " .. tostring(equipRF) .. " | HitGround RE: " .. tostring(hitRE))

local scoreAssets = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("ScoreEffect")
local effectIds, effectSet = {}, {}
for _, child in ipairs(scoreAssets:GetChildren()) do
    table.insert(effectIds, child.Name)
    effectSet[child.Name] = true
end
table.sort(effectIds)
dbg("Found " .. #effectIds .. " score effects")

local running = true
local hitConn
local chosen = {}
for _, id in ipairs(config.effects or {}) do
    if effectSet[id] then chosen[id] = true end
end

local function chosenList()
    local t = {}
    for _, id in ipairs(effectIds) do
        if chosen[id] then table.insert(t, id) end
    end
    return t
end

local function commitChosen()
    config.effects = chosenList()
    saveSoon()
end

local function loadModule(ms)
    if not (typeof(ms) == "Instance" and ms:IsA("ModuleScript")) then
        return nil, "not a ModuleScript"
    end
    local ok, res = pcall(require, ms)
    if ok and res ~= nil then return res end
    if getscriptclosure then
        local ok2, res2 = pcall(function() return getscriptclosure(ms)() end)
        if ok2 then return res2 end
        return nil, tostring(res2)
    end
    return nil, "require failed"
end

local itemCache = {}
local function getItem(id)
    if itemCache[id] then return itemCache[id] end
    local item
    local ok, res = pcall(function()
        local it = ContentItem:Get(id)
        if it then return it end
        local ent = Entities and Entities:FindFirstChild(id)
        if ent and ent:IsA("ModuleScript") then
            local ok2, res2 = pcall(require, ent)
            if ok2 then return res2 end
        end
    end)
    if ok and res then item = res end
    if not item then
        local asset
        pcall(function() asset = scoreAssets:FindFirstChild(id) end)
        item = { Id = id, Asset = asset, Metadata = { Sound = {} } }
    end
    itemCache[id] = item
    return item
end

local function makeActions(item)
    local md = item.Metadata
    if md and md.Handler then
        return { execute = function(e) md.Handler:Execute(e) end }
    end
    local mod, lerr = loadModule(item.Asset)
    if mod == nil then return nil, "load: " .. tostring(lerr) end
    if type(mod) == "function" then
        return {
            execute = function(e)
                return mod(e.Context.Origin, e.Context.Character, e.Context.Maid, e.Context.IsPreview)
            end,
        }
    end
    if type(mod) == "table" and mod.Execute then
        return { execute = mod.Execute, onInteracted = mod.OnInteracted }
    end
    return nil, "module returned " .. typeof(mod)
end

-- Sound

local function resolveSoundId(item)
    local sd = item.Metadata and item.Metadata.Sound
    if type(sd) == "table" then
        for _, k in ipairs({"SoundId", "Id", "Sound", "AssetId", "Asset"}) do
            local v = sd[k]
            if type(v) == "number" then return "rbxassetid://" .. v, sd end
            if type(v) == "string" and v ~= "" then
                return (v:find("rbxasset") and v or ("rbxassetid://" .. v)), sd
            end
        end
    end
    if typeof(item.Asset) == "Instance" then
        local s = item.Asset:FindFirstChildWhichIsA("Sound", true)
        if s and s.SoundId ~= "" then return s.SoundId, sd, s end
    end
    return nil, sd
end

local lastSoundName = "none"
local function playEffectSound(item, id)
    if config.sound == false then return end
    local sid, sd, template = resolveSoundId(item)
    local vol = tonumber(config.volume) or 1

    if sid then
        local s = template and template:Clone() or Instance.new("Sound")
        s.SoundId = sid
        s.Volume = (template and template.Volume > 0 and template.Volume or 1) * vol
        if type(sd) == "table" then
            local ps = sd.PlaybackSpeed
            if typeof(ps) == "NumberRange" then
                s.PlaybackSpeed = ps.Min + (ps.Max - ps.Min) * (rng and rng:NextNumber() or math.random())
            elseif type(ps) == "number" then
                s.PlaybackSpeed = ps
            end
            if type(sd.Volume) == "number" then s.Volume = sd.Volume * vol end
        end
        s.RollOffMode = Enum.RollOffMode.Linear
        s.RollOffMaxDistance = 1e6
        s.Parent = SoundService
        s.Ended:Connect(function() s:Destroy() end)
        task.delay(15, function() if s.Parent then s:Destroy() end end)
        s:Play()
        lastSoundName = id
        return
    end

    if GameSound and type(sd) == "table" then
        pcall(function()
            local sndId = item.Id or id
            if not GameSound.isRegistered(sndId) then
                local cfg = { PlaybackSpeed = NumberRange.new(0.95, 1.05) }
                for k, v in pairs(sd) do cfg[k] = v end
                cfg.Volume = (type(cfg.Volume) == "number" and cfg.Volume or 1) * vol
                GameSound.register(sndId, cfg)
            end
            GameSound.fromName(sndId)({ Origin = camera.CFrame })
            lastSoundName = id .. " (game tool)"
        end)
    end
end

-- Effects

local lastPlayed = "none"
local function playEffectAt(id, origin, char, duration)
    if not running then return end
    local item = getItem(id)
    local actions, aerr = makeActions(item)
    if not actions then derr("Failed: " .. id .. " | " .. aerr) return end

    local maid = Maid.new()
    local fake = {
        Actions = actions,
        Context = {
            Maid = maid, IsPreview = true, Origin = origin,
            Character = char, Asset = item.Asset,
            IsOwner = char == lp.Character,
            World = {}, Local = { InGame = false }, Custom = {},
        },
    }
    playEffectSound(item, id)
    task.spawn(function()
        local ok, err = pcall(actions.execute, fake)
        if not ok then derr("Execute failed " .. id .. " | " .. tostring(err))
        else lastPlayed = id end
        task.wait(duration or 5)
        maid:Destroy()
    end)
end

local function previewEffect(id)
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    playEffectAt(id, root and root.Position or Vector3.new(0, 5, 0), char, 5)
end

local function serverEquip(id)
    local ok, res
    if equipRF and equipRF:IsA("RemoteFunction") then
        ok, res = pcall(function() return equipRF:InvokeServer(id) end)
    else
        ok, res = pcall(function() return InventoryService.Equip:InvokeServer(id) end)
    end
    dbg("Equip " .. id .. " -> " .. tostring(ok) .. " " .. tostring(res))
end

local function setChosen(id, on)
    if on then
        chosen[id] = true
        serverEquip(id)
    else
        chosen[id] = nil
    end
    commitChosen()
end

-- Ball hitbox

local origSizes = {}
local cachedBall
local scanTimer = 1
local lastHitPos, lastHitTime = nil, 0
local lastTop = {}
local ACCENT = Color3.fromRGB(91, 127, 255)

local PALETTE = {
    { "Accent", ACCENT },
    { "White", Color3.fromRGB(255, 255, 255) },
    { "Red", Color3.fromRGB(255, 63, 87) },
    { "Orange", Color3.fromRGB(255, 150, 50) },
    { "Yellow", Color3.fromRGB(255, 230, 80) },
    { "Green", Color3.fromRGB(90, 230, 120) },
    { "Cyan", Color3.fromRGB(80, 220, 255) },
    { "Blue", Color3.fromRGB(91, 127, 255) },
    { "Purple", Color3.fromRGB(130, 90, 255) },
}
local PALETTE_NAMES = {}
for i, p in ipairs(PALETTE) do PALETTE_NAMES[i] = p[1] end
local function paletteColor(name)
    if typeof(name) == "Color3" then return name end
    if type(name) == "string" then
        local hex = name:match("^#?(%x%x%x%x%x%x)")
        if hex then
            local r = tonumber(hex:sub(1, 2), 16) or 91
            local g = tonumber(hex:sub(3, 4), 16) or 127
            local b = tonumber(hex:sub(5, 6), 16) or 255
            return Color3.fromRGB(r, g, b)
        end
    end
    for _, p in ipairs(PALETTE) do if p[1] == name then return p[2] end end
    return ACCENT
end
local function colorToHex(c, a)
    local r = math.clamp(math.floor(c.R * 255 + 0.5), 0, 255)
    local g = math.clamp(math.floor(c.G * 255 + 0.5), 0, 255)
    local b = math.clamp(math.floor(c.B * 255 + 0.5), 0, 255)
    if a ~= nil then
        local al = math.clamp(math.floor((1 - a) * 255 + 0.5), 0, 255)
        return string.format("#%02X%02X%02X%02X", r, g, b, al)
    end
    return string.format("#%02X%02X%02X", r, g, b)
end

-- Style name -> { Material, Reflectance } ; Rainbow/Pulse animate Color/Transparency
local MATERIALS = { "ForceField", "Neon", "Glass", "Metal", "Solid", "Rainbow", "Pulse" }
local STYLE_MAT = {
    ForceField = { Enum.Material.ForceField, 0 },
    Neon = { Enum.Material.Neon, 0 },
    Glass = { Enum.Material.Glass, 0 },
    Metal = { Enum.Material.Metal, 0.5 },
    Solid = { Enum.Material.SmoothPlastic, 0 },
    Rainbow = { Enum.Material.SmoothPlastic, 0 },
    Pulse = { Enum.Material.Neon, 0 },
}
local function materialEnum(name)
    local st = STYLE_MAT[name]
    if st then return st[1], st[2] end
    local ok, m = pcall(function() return Enum.Material[name] end)
    return (ok and m or Enum.Material.ForceField), 0
end

local function animColor()
    return Color3.fromHSV((os.clock() * 0.8) % 1, 1, 1)
end
local function animFill(base)
    return math.clamp(base + math.sin(os.clock() * 5) * 0.3, 0, 0.95)
end

local playerHis = {}
local playerConns = {}
local partOrig = {}
local paintLogged = {}
local clothKeep = {}

local chamHost = (gethui and gethui()) or game:GetService("CoreGui")

local ballHi = Instance.new("Highlight")
ballHi.Name = "ScorehubBallOutline"
ballHi.FillTransparency = 0.25
ballHi.OutlineTransparency = 0
ballHi.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
ballHi.Enabled = false
ballHi.Parent = chamHost

local hitboxVis = Instance.new("Part")
hitboxVis.Name = "ScorehubBallHitboxVis"
hitboxVis.Shape = Enum.PartType.Ball
hitboxVis.Anchored = true
hitboxVis.CanCollide = false
hitboxVis.CanTouch = false
hitboxVis.CanQuery = false
hitboxVis.CastShadow = false
hitboxVis.Material = Enum.Material.ForceField
hitboxVis.Color = Color3.fromRGB(65, 115, 255)
hitboxVis.Transparency = 1
hitboxVis.Size = Vector3.new(4, 4, 4)

local innerBallVis = Instance.new("Part")
innerBallVis.Name = "ScorehubBallCoreVis"
innerBallVis.Shape = Enum.PartType.Ball
innerBallVis.Anchored = true
innerBallVis.CanCollide = false
innerBallVis.CanTouch = false
innerBallVis.CanQuery = false
innerBallVis.CastShadow = false
innerBallVis.Material = Enum.Material.SmoothPlastic
innerBallVis.Color = Color3.fromRGB(88, 70, 210)
innerBallVis.Transparency = 1
innerBallVis.Size = Vector3.new(2.6, 2.6, 2.6)

local touchRing = Instance.new("Part")
touchRing.Name = "ScorehubBallTouchRing"
touchRing.Shape = Enum.PartType.Ball
touchRing.Anchored = true
touchRing.CanCollide = false
touchRing.CanTouch = false
touchRing.CanQuery = false
touchRing.CastShadow = false
touchRing.Material = Enum.Material.Neon
touchRing.Color = Color3.fromRGB(90, 230, 120)
touchRing.Transparency = 1
touchRing.Size = Vector3.new(3, 3, 3)

local lastBallTouchAt = 0
local ballTouchedByMe = false
local lastBallVel = nil
local wasInRange = false
local ballTouchConn

local function triggerBallTouch(pos)
    local now = os.clock()
    ballTouchedByMe = true
    if now - lastBallTouchAt < 0.16 then return end
    lastBallTouchAt = now
    if config.touchFlash == false then return end
    local tcol = paletteColor(config.touchColor or "#FF4DA6")
    touchRing.Color = tcol
    touchRing.Size = Vector3.new(3.2, 3.2, 3.2)
    touchRing.CFrame = CFrame.new(pos)
    touchRing.Transparency = 0.15
    if touchRing.Parent ~= camera then touchRing.Parent = camera end
    TweenService:Create(touchRing, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = Vector3.new(11, 11, 11),
        Transparency = 1,
    }):Play()
end

local function isBallTouchedState()
    if config.touchFlash == false then return false end
    return ballTouchedByMe or (os.clock() - lastBallTouchAt) < 0.9
end

local ballLook = {}

local function paintBall(ball, osz)
    if not ballLook[ball] then
        ballLook[ball] = {
            Material = ball.Material, Color = ball.Color, Transparency = ball.Transparency,
            Reflectance = ball.Reflectance,
        }
    end
    local touched = isBallTouchedState()
    local availCol = config.chamsMat == "Rainbow" and animColor() or paletteColor(config.chamsColor or "#4173FF")
    local tcol = paletteColor(config.touchColor or "#FF4DA6")
    local col = touched and tcol or availCol
    local ocol = touched and tcol or (config.chamsMat == "Rainbow" and col or paletteColor(config.chamsColor2 or config.chamsColor))
    local mat, refl = materialEnum(config.chamsMat)
    local fill = math.clamp(tonumber(config.chamsFill) or 0.3, 0, 0.9)
    if config.chamsMat == "Pulse" then fill = animFill(fill) end

    local useCore = (config.expand == true) or not ball:IsA("Part")
    if useCore then
        local coreSz = osz or origSizes[ball] or ball.Size
        local r = math.min(coreSz.X, coreSz.Y, coreSz.Z)
        if r < 1.5 or r > 5 then r = 2.6 end
        innerBallVis.Size = Vector3.new(r, r, r)
        innerBallVis.CFrame = ball.CFrame
        innerBallVis.Material = mat == Enum.Material.ForceField and Enum.Material.SmoothPlastic or mat
        innerBallVis.Color = col
        innerBallVis.Transparency = math.clamp(fill * 0.5, 0, 0.65)
        innerBallVis.Reflectance = refl
        if innerBallVis.Parent ~= camera then innerBallVis.Parent = camera end
        if ballHi.Adornee ~= innerBallVis then ballHi.Adornee = innerBallVis end
        ballHi.FillColor = col
        ballHi.FillTransparency = math.clamp(fill, 0.1, 0.85)
        ballHi.OutlineColor = Color3.fromRGB(15, 15, 20)
        ballHi.OutlineTransparency = 0
        local wantHi = config.chamsOutline ~= false
        if ballHi.Enabled ~= wantHi then ballHi.Enabled = wantHi end
    else
        if innerBallVis.Parent then innerBallVis.Parent = nil end
        if ball.Material ~= mat then ball.Material = mat end
        if ball.Color ~= col then ball.Color = col end
        if ball.Transparency ~= fill then ball.Transparency = fill end
        if ball.Reflectance ~= refl then ball.Reflectance = refl end
        if ballHi.Adornee ~= ball then ballHi.Adornee = ball end
        ballHi.FillColor = col
        ballHi.FillTransparency = fill
        ballHi.OutlineColor = ocol
        local wantHi = config.chamsOutline ~= false
        if ballHi.Enabled ~= wantHi then ballHi.Enabled = wantHi end
    end
end

local function unpaintBalls()
    ballHi.Enabled = false
    ballHi.Adornee = nil
    if innerBallVis.Parent then innerBallVis.Parent = nil end
    for ball, look in pairs(ballLook) do
        if ball.Parent then
            pcall(function()
                ball.Material, ball.Color = look.Material, look.Color
                ball.Transparency, ball.Reflectance = look.Transparency, look.Reflectance
            end)
        end
        ballLook[ball] = nil
    end
end

local origTrans = {}
local function restoreSizes()
    if hitboxVis.Parent then hitboxVis.Parent = nil end
    if not config.chams and innerBallVis.Parent then
        innerBallVis.Parent = nil
        ballHi.Enabled = false
        ballHi.Adornee = nil
    end
    for part, orig in pairs(origSizes) do
        if part.Parent then
            pcall(function()
                part.Size = orig
                if origTrans[part] ~= nil then
                    part.Transparency = origTrans[part]
                end
            end)
        end
        origSizes[part] = nil
        origTrans[part] = nil
    end
end

local function ballScore(d, hrp, plrs)
    if d == hitboxVis or d == innerBallVis then return -math.huge end
    for _, plr in ipairs(plrs) do
        if plr.Character and d:IsDescendantOf(plr.Character) then return -math.huge end
    end
    local n = d.Name
    local nl = n:lower()
    local s = 0
    local exact = n == "Ball" or n == "SoccerBall" or n == "Football" or n == "Volleyball" or n == "Hitbox"
    if exact then s = s + 200
    elseif nl:find("ball") then s = s + 40 end
    if d:IsA("Part") and d.Shape == Enum.PartType.Ball then s = s + 120 end
    if nl:find("shadow") or nl:find("marker") or nl:find("indicator") or nl:find("landing")
    or nl:find("target") or nl:find("ring") or nl:find("preview") or nl:find("trail")
    or nl:find("aura") or nl:find("vfx") or nl:find("effect") or nl:find("glow") then
        s = s - 500
    end
    local sz = origSizes[d] or d.Size
    if math.abs(sz.X - sz.Y) > 0.6 or math.abs(sz.X - sz.Z) > 0.6 then s = s - 250 end
    if sz.X < 0.8 or sz.X > 12 then s = s - 200 end
    local tr = origTrans[d] ~= nil and origTrans[d] or d.Transparency
    if tr >= 0.9 and not exact then s = s - 300 end
    if d.Anchored then s = s - (exact and 60 or 300) end
    local ok, vel = pcall(function() return d.AssemblyLinearVelocity.Magnitude end)
    if ok and vel and vel > 0.5 then s = s + 150 end
    local full = d:GetFullName()
    local fulll = full:lower()
    local _, depth = full:gsub("%.", "")
    s = s - depth * 4
    if fulll:find("client_ball") then s = s + 800 end
    if fulll:find("cannon") or fulll:find("prompt") or fulll:find("rack")
    or fulll:find("antenna") or fulll:find("shadow") then
        s = s - 500
    end
    local topName = full:match("^Workspace%.([^%.]+)")
    if topName == lp.Name then s = s + 300
    elseif topName and Players:FindFirstChild(topName) then s = s - 200 end
    if full:find("Decor") or full:find("Props") or full:find("Environment") or full:find("Lobby") then
        s = s - 300
    end
    if hrp then
        local dist = (d.Position - hrp.Position).Magnitude
        s = s + math.max(0, 300 - dist * 2)
        if dist > 250 then s = s - 300 end
    end
    if lastHitPos and os.clock() - lastHitTime < 4
    and (d.Position - lastHitPos).Magnitude < 20 then
        s = s + 400
    end
    return s
end

local function pickModelBallPart(m)
    if m.PrimaryPart then return m.PrimaryPart end
    for _, name in ipairs({ "Ball", "Hitbox", "RootPart", "Primary", "Core" }) do
        local c = m:FindFirstChild(name)
        if c and c:IsA("BasePart") then return c end
    end
    for _, c in ipairs(m:GetDescendants()) do
        if c:IsA("Part") and c.Shape == Enum.PartType.Ball then return c end
    end
    return m:FindFirstChildWhichIsA("BasePart", true)
end

local function rescanBall()
    local best, bestScore = nil, -math.huge
    local plrs = Players:GetPlayers()
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")

    local okSvc, svcBall = pcall(function()
        return BallService.Ball or BallService.CurrentBall
            or (BallService.GetBall and BallService:GetBall())
    end)
    if okSvc and typeof(svcBall) == "Instance" then
        if svcBall:IsA("BasePart") then best = svcBall
        elseif svcBall:IsA("Model") then best = pickModelBallPart(svcBall) end
        if best then bestScore = math.huge end
    end

    local top = {}
    if not best then
        local roots = { Workspace }
        if camera then table.insert(roots, camera) end
        for _, root in ipairs(roots) do
            for _, d in ipairs(root:GetDescendants()) do
                if d ~= hitboxVis and d ~= innerBallVis and d ~= touchRing then
                    local part
                    if d:IsA("BasePart") and (d.Name:lower():find("ball") or (d.Parent and d.Parent.Name:lower():find("client_ball"))) then
                        part = d
                    elseif d:IsA("Model") and d.Name:lower():find("ball") then
                        part = pickModelBallPart(d)
                    end
                    if part then
                        local s = ballScore(part, hrp, plrs)
                        table.insert(top, { part, s })
                        if s > bestScore then best, bestScore = part, s end
                    end
                end
            end
        end
        table.sort(top, function(a, b) return a[2] > b[2] end)
    end
    lastTop = top

    local keep = cachedBall and cachedBall:IsDescendantOf(Workspace)
    if keep and best ~= cachedBall then
        local cur = ballScore(cachedBall, hrp, plrs)
        if bestScore < cur + 250 then best = cachedBall bestScore = cur end
    end

    if cachedBall ~= best then
        restoreSizes()
        unpaintBalls()
        if ballTouchConn then pcall(function() ballTouchConn:Disconnect() end) ballTouchConn = nil end
        lastBallVel = nil
        wasInRange = false
        ballTouchedByMe = false
        if best then
            pcall(function()
                ballTouchConn = best.Touched:Connect(function(hit)
                    local ch = lp.Character
                    if ch and hit and hit:IsDescendantOf(ch) then
                        triggerBallTouch(best.Position)
                    end
                end)
            end)
            trace("Ball -> " .. best:GetFullName() .. " score=" .. math.floor(bestScore)
                .. " anchored=" .. tostring(best.Anchored) .. " class=" .. best.ClassName)
            for i = 2, math.min(3, #top) do
                trace(("  runner-up %d: %s score=%d"):format(i, top[i][1]:GetFullName(), math.floor(top[i][2])))
            end
        else
            trace("Ball -> none")
        end
    end
    cachedBall = best
end

local function ballInfo()
    local b = cachedBall
    if not (b and b.Parent) then return "no ball found", "" end
    local hrp = lp.Character and lp.Character:FindFirstChild("HumanoidRootPart")
    local dist = hrp and math.floor((b.Position - hrp.Position).Magnitude) or 0
    return b.Name, dist .. " studs"
end

local pendingScan = 0
local animAcc = 0
local addConn = Workspace.DescendantAdded:Connect(function(d)
    if d ~= hitboxVis and d ~= innerBallVis and d ~= touchRing and (d:IsA("BasePart") or d:IsA("Model")) and d.Name:lower():find("ball") then
        pendingScan = 0.15
    end
end)

local hbConn = RunService.Heartbeat:Connect(function(dt)
    if not running then return end
    local wantExpand = config.expand == true
    local wantChams = config.chams == true
    local wantTouch = config.touchFlash ~= false

    if pendingScan > 0 then
        pendingScan = pendingScan - dt
        if pendingScan <= 0 then scanTimer = 1 end
    end
    scanTimer = scanTimer + dt
    local interval = (wantExpand or wantChams or wantTouch) and 0.35 or 1.5
    if scanTimer >= interval then
        scanTimer = 0
        rescanBall()
    end

    if not (wantExpand or wantChams or wantTouch) then
        if next(origSizes) or hitboxVis.Parent then restoreSizes() end
        if next(ballLook) or innerBallVis.Parent then unpaintBalls() end
        return
    end
    local ball = cachedBall
    if not ball or not ball.Parent then
        if next(origSizes) or hitboxVis.Parent then restoreSizes() end
        if next(ballLook) or innerBallVis.Parent then unpaintBalls() end
        return
    end

    local osz = origSizes[ball] or ball.Size
    local baseD = math.min(osz.X, osz.Y, osz.Z)
    if baseD < 1.5 or baseD > 5 then baseD = 2.6 end
    local mult = tonumber(config.mult) or 3
    local d = wantExpand and (baseD * mult) or baseD

    local ch = lp.Character
    local hrp = ch and ch:FindFirstChild("HumanoidRootPart")
    if hrp then
        local bpos = ball.Position
        local dist = (bpos - hrp.Position).Magnitude
        local reach = (d * 0.5) + 4.5
        local inRange = dist <= reach
        local okV, vel = pcall(function() return ball.AssemblyLinearVelocity end)
        if okV and vel then
            if lastBallVel then
                local dv = (vel - lastBallVel).Magnitude
                if dist <= (reach + 4) then
                    if dv > 18 and vel.Magnitude > 8 then
                        triggerBallTouch(bpos)
                    end
                elseif ballTouchedByMe and (os.clock() - lastBallTouchAt) > 0.35 then
                    if dv > 16 or dist > (reach + 14) or vel.Magnitude < 2 then
                        ballTouchedByMe = false
                    end
                end
            end
            lastBallVel = vel
        end
        if inRange and not wasInRange then
            triggerBallTouch(bpos)
        end
        wasInRange = inRange
    end

    local touched = isBallTouchedState()
    local availCol = paletteColor(config.chamsColor or "#4173FF")
    local tcol = paletteColor(config.touchColor or "#FF4DA6")
    local activeCol = touched and tcol or availCol

    if wantExpand then
        if not origSizes[ball] then origSizes[ball] = ball.Size end
        if origTrans[ball] == nil then origTrans[ball] = ball.Transparency end
        local targetSz = Vector3.new(d, d, d)
        if ball.Size ~= targetSz then ball.Size = targetSz end
        if ball.Transparency < 0.98 then ball.Transparency = 1 end

        local parentModel = ball.Parent
        if parentModel and parentModel:IsA("Model") and parentModel ~= Workspace then
            for _, sib in ipairs(parentModel:GetDescendants()) do
                if sib:IsA("BasePart") and sib ~= ball then
                    if not origSizes[sib] then origSizes[sib] = sib.Size end
                    if origTrans[sib] == nil then origTrans[sib] = sib.Transparency end
                    local sn = sib.Name:lower()
                    if sn:find("ball") or sn:find("hitbox") or sn:find("root") then
                        if sib.Size ~= targetSz then sib.Size = targetSz end
                    end
                    if sib.Transparency < 0.98 then sib.Transparency = 1 end
                end
            end
        end

        hitboxVis.Size = targetSz
        hitboxVis.CFrame = ball.CFrame
        hitboxVis.Color = activeCol
        hitboxVis.Transparency = touched and 0.32 or 0.45
        if hitboxVis.Parent ~= camera then hitboxVis.Parent = camera end

        if not wantChams then
            innerBallVis.Size = Vector3.new(baseD, baseD, baseD)
            innerBallVis.CFrame = ball.CFrame
            innerBallVis.Material = Enum.Material.SmoothPlastic
            innerBallVis.Color = activeCol
            innerBallVis.Transparency = 0.15
            if innerBallVis.Parent ~= camera then innerBallVis.Parent = camera end
            if ballHi.Adornee ~= innerBallVis then ballHi.Adornee = innerBallVis end
            ballHi.FillColor = activeCol
            ballHi.FillTransparency = 0.3
            ballHi.OutlineColor = Color3.fromRGB(15, 15, 20)
            ballHi.OutlineTransparency = 0
            ballHi.Enabled = true
        end
    elseif next(origSizes) or hitboxVis.Parent then
        restoreSizes()
    end

    if wantChams then
        paintBall(ball, osz)
    elseif not wantExpand then
        if touched then
            paintBall(ball, osz)
        elseif next(ballLook) or innerBallVis.Parent then
            unpaintBalls()
        end
    end

    local pmat = config.pmat
    local animating = config.pchams and (pmat == "Rainbow" or pmat == "Pulse")
    if animating then animAcc = animAcc + dt else animAcc = 0 end
    if animAcc >= 0.066 then
        animAcc = 0
        local c = pmat == "Rainbow" and animColor() or nil
        local f = pmat == "Pulse" and animFill(tonumber(config.pfill) or 0.6) or nil
        for plr, hi in pairs(playerHis) do
            if plr.Character and hi.Parent == plr.Character then
                if c then hi.FillColor, hi.OutlineColor = c, c end
                if f and hi.FillTransparency < 1 then hi.FillTransparency = f end
            end
        end
        if next(partOrig) then
            for part in pairs(partOrig) do
                if part.Parent then
                    if c and part.Color ~= c then part.Color = c end
                    if f and part.Transparency ~= f then part.Transparency = f end
                end
            end
        end
    end
end)

-- Player chams

local function teamColor(plr)
    if plr.Team and plr.TeamColor then return plr.TeamColor.Color end
    return nil
end

local function paintPart(part, mat, col, trans)
    if not partOrig[part] then
        partOrig[part] = {
            part.Material, part.Color, part.Transparency,
            part:IsA("MeshPart") and part.TextureID or nil,
            part:FindFirstChildOfClass("SurfaceAppearance"),
        }
    end
    if part.Material ~= mat then part.Material = mat end
    if part.Color ~= col then part.Color = col end
    if trans and part.Transparency ~= trans then part.Transparency = trans end
    if part:IsA("MeshPart") and part.TextureID ~= "" then part.TextureID = "" end
    local sa = partOrig[part][5]
    if sa and sa.Parent == part then sa.Parent = nil end
    for _, c in ipairs(part:GetChildren()) do
        if c:IsA("Decal") or c:IsA("Texture") then
            if not partOrig[part][c] then partOrig[part][c] = c.Transparency end
            c.Transparency = 1
        end
    end
    local sm = part:FindFirstChildOfClass("SpecialMesh")
    if sm and sm.TextureId ~= "" then
        if not partOrig[part][6] then partOrig[part][6] = sm.TextureId end
        sm.TextureId = ""
    end
end

local function hideClothes(char)
    for _, c in ipairs(char:GetChildren()) do
        if (c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic")) and c.Parent == char then
            clothKeep[c] = char
            c.Parent = nil
        end
    end
end

local function showClothes(char)
    for c, p in pairs(clothKeep) do
        if p == char then
            if c and not c.Parent then c.Parent = p end
            clothKeep[c] = nil
        end
    end
end

local function unpaintAll(root)
    showClothes(root)
    for part, o in pairs(partOrig) do
        if not root or part:IsDescendantOf(root) then
            if part.Parent then
                pcall(function()
                    part.Material, part.Color, part.Transparency = o[1], o[2], o[3]
                    if part:IsA("MeshPart") and o[4] then part.TextureID = o[4] end
                    if o[5] then o[5].Parent = part end
                    if o[6] then
                        local sm = part:FindFirstChildOfClass("SpecialMesh")
                        if sm then sm.TextureId = o[6] end
                    end
                    for c, v in pairs(o) do
                        if typeof(c) == "Instance" and (c:IsA("Decal") or c:IsA("Texture")) then
                            c.Transparency = v
                        end
                    end
                end)
            end
            partOrig[part] = nil
        end
    end
end

local function applyPlayerCham(plr)
    local char = plr.Character
    if not char or plr == lp then return end
    local on = config.pchams == true
    local mode = config.pmode or "Highlight"
    local col = (config.pteam and teamColor(plr)) or paletteColor(config.pcolor)
    local ocol = (config.pteam and col) or paletteColor(config.pcolor2 or config.pcolor)

    local hi = playerHis[plr]
    if not hi or hi.Parent ~= char then
        if hi then hi:Destroy() end
        hi = Instance.new("Highlight")
        hi.Name = "ScorehubCham"
        hi.Adornee = char
        hi.Parent = char
        playerHis[plr] = hi
    end
    local useHi = on and mode ~= "Material"
    if config.pmat == "Rainbow" then col = animColor() ocol = col end
    hi.FillColor = col
    hi.OutlineColor = ocol
    hi.FillTransparency = mode == "Both" and 1 or (tonumber(config.pfill) or 0.6)
    hi.OutlineTransparency = config.poutline ~= false and 0 or 1
    hi.DepthMode = config.pwalls ~= false and Enum.HighlightDepthMode.AlwaysOnTop
        or Enum.HighlightDepthMode.Occluded
    hi.Enabled = useHi

    if on and mode ~= "Highlight" then
        hideClothes(char)
        local mat, refl = materialEnum(config.pmat)
        local n = 0
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
                pcall(paintPart, d, mat, col)
                if d.Reflectance ~= refl then d.Reflectance = refl end
                if config.pmat ~= "Pulse" and partOrig[d] and d.Transparency ~= partOrig[d][3] then
                    d.Transparency = partOrig[d][3]
                end
                n = n + 1
            end
        end
        if n > 0 and not paintLogged[plr] then
            paintLogged[plr] = true
            trace(("Painted %d parts on %s (%s)"):format(n, plr.Name, tostring(config.pmat)))
        end
    else
        unpaintAll(char)
    end
end

local function refreshPlayerChams()
    for _, plr in ipairs(Players:GetPlayers()) do applyPlayerCham(plr) end
end

local function clearPlayerChams()
    for plr, hi in pairs(playerHis) do
        pcall(function() hi:Destroy() end)
        playerHis[plr] = nil
    end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr.Character then unpaintAll(plr.Character) end
    end
end

task.spawn(function()
    while running do
        task.wait(2)
        if config.pchams and config.pmode ~= "Highlight" then refreshPlayerChams() end
        for part in pairs(partOrig) do
            if not part.Parent then partOrig[part] = nil end
        end
        for c, p in pairs(clothKeep) do
            if not p or not p.Parent then clothKeep[c] = nil end
        end
    end
end)

local function watchPlayer(plr)
    if plr == lp then return end
    playerConns[plr] = plr.CharacterAdded:Connect(function()
        task.wait(0.2)
        if running then applyPlayerCham(plr) end
        task.wait(1.0)
        if running then applyPlayerCham(plr) end
    end)
    applyPlayerCham(plr)
end

local espReady = {}
for _, plr in ipairs(Players:GetPlayers()) do watchPlayer(plr) end
playerConns.added = Players.PlayerAdded:Connect(watchPlayer)
playerConns.removing = Players.PlayerRemoving:Connect(function(plr)
    if playerConns[plr] then playerConns[plr]:Disconnect() playerConns[plr] = nil end
    if playerHis[plr] then playerHis[plr]:Destroy() playerHis[plr] = nil end
    espReady[plr] = nil
end)

-- Ability ESP

local abilitySvc
pcall(function()
    for _, n in ipairs({ "AbilityService", "SkillService", "PowerService" }) do
        local ok, s = pcall(Knit.GetService, n)
        if ok and s then abilitySvc = s break end
    end
end)

local ABILITY_ATTRS = { "Gameplay_Ability", "Ability", "AbilityId", "EquippedAbility",
    "AbilityName", "Skill", "SkillId", "EquippedSkill", "Power" }
local READY_ATTRS = { "AbilityReady", "Ready", "AbilityCooldownEnd", "CooldownEnd",
    "AbilityCooldown", "Cooldown", "AbilityCharges", "Charges" }

local function attrOf(plr, char, names)
    for _, n in ipairs(names) do
        local v = plr:GetAttribute(n)
        if v == nil and char then v = char:GetAttribute(n) end
        if v ~= nil then return v end
    end
end

local function valueChild(root, names)
    if not root then return nil end
    for _, n in ipairs(names) do
        local o = root:FindFirstChild(n)
        if o and o:IsA("ValueBase") and o.Value ~= nil then return o.Value end
    end
end

local function readAbility(plr, char)
    local name = attrOf(plr, char, ABILITY_ATTRS)
    if name == nil then name = valueChild(plr, ABILITY_ATTRS) end
    if name == nil then name = valueChild(char, ABILITY_ATTRS) end
    if type(name) ~= "string" or name == "" then name = nil end
    if not name and abilitySvc then
        for _, m in ipairs({ "GetAbility", "AbilityOf", "GetPlayerAbility", "GetSkill", "Ability" }) do
            local ok, v = pcall(function() return abilitySvc[m](abilitySvc, plr) end)
            if ok and type(v) == "string" and v ~= "" then name = v break end
            if ok and type(v) == "table" and type(v.Name) == "string" then name = v.Name break end
        end
    end
    local charge = plr:GetAttribute("Ability_Charge")
    if charge == nil and char then charge = char:GetAttribute("Ability_Charge") end
    if type(charge) == "number" then
        local frac = math.clamp(charge / 100, 0, 1)
        if charge >= 100 then
            return name, frac, "READY", Color3.fromRGB(90, 230, 120)
        end
        return name, frac, math.floor(charge + 0.5) .. "%", Color3.fromRGB(255, 180, 60)
    end
    local state = attrOf(plr, char, READY_ATTRS)
    if state == nil then state = valueChild(plr, READY_ATTRS) end
    if state == nil then state = valueChild(char, READY_ATTRS) end
    if state == nil and abilitySvc then
        for _, m in ipairs({ "IsReady", "CanUse", "GetCooldown", "Cooldown" }) do
            local ok, v = pcall(function() return abilitySvc[m](abilitySvc, plr) end)
            if ok and v ~= nil then state = v break end
        end
    end
    local stText, stCol = readyLabel(state)
    return name, nil, stText, stCol
end

local function readyLabel(state)
    if state == nil then return "?", Color3.fromRGB(140, 140, 150) end
    if state == true or state == "ready" or state == "READY" or state == "Ready" then
        return "READY", Color3.fromRGB(90, 230, 120)
    end
    if state == false then return "NOT READY", Color3.fromRGB(235, 87, 87) end
    local n = tonumber(state)
    if n then
        if n <= 0 then return "READY", Color3.fromRGB(90, 230, 120) end
        if n > 1e9 then n = n - os.time() * 1000 end
        if n > 1e7 then n = (n - os.clock() * 1000) / 1000 end
        return string.format("%.0fs", math.max(0, n)), Color3.fromRGB(255, 180, 60)
    end
    return tostring(state):upper(), Color3.fromRGB(140, 140, 150)
end

local espGui = Instance.new("ScreenGui")
espGui.Name = "ScorehubAlerts"
espGui.ResetOnSpawn = false
espGui.DisplayOrder = 999
espGui.Parent = chamHost

local toastCol = Instance.new("Frame")
toastCol.Name = "Toasts"
toastCol.AnchorPoint = Vector2.new(1, 0.5)
toastCol.Position = UDim2.new(1, -16, 0.5, 0)
toastCol.Size = UDim2.new(0, 230, 1, 0)
toastCol.BackgroundTransparency = 1
toastCol.Parent = espGui
local toastLayout = Instance.new("UIListLayout")
toastLayout.FillDirection = Enum.FillDirection.Vertical
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Center
toastLayout.Padding = UDim.new(0, 6)
toastLayout.Parent = toastCol

local notifySnd = Instance.new("Sound")
notifySnd.SoundId = "rbxassetid://6518811702"
notifySnd.Volume = 0.7
notifySnd.Parent = espGui

local function toast(plr, ab, tcol)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 0)
    card.BackgroundColor3 = Color3.fromRGB(14, 14, 17)
    card.BackgroundTransparency = 0.12
    card.BorderSizePixel = 0
    card.ClipsDescendants = true
    card.Parent = toastCol
    Instance.new("UICorner", card).CornerRadius = UDim.new(0, 7)
    local st = Instance.new("UIStroke", card)
    st.Thickness = 1 st.Color = tcol st.Transparency = 0.25
    st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    local av = Instance.new("ImageLabel")
    av.Size = UDim2.fromOffset(30, 30)
    av.Position = UDim2.new(0, 7, 0, 7)
    av.BackgroundColor3 = Color3.fromRGB(30, 30, 36)
    av.BorderSizePixel = 0
    av.Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100"):format(plr.UserId)
    av.Parent = card
    Instance.new("UICorner", av).CornerRadius = UDim.new(1, 0)
    local nameL = Instance.new("TextLabel")
    nameL.Size = UDim2.new(1, -48, 0, 13)
    nameL.Position = UDim2.new(0, 44, 0, 6)
    nameL.BackgroundTransparency = 1
    nameL.Font = Enum.Font.GothamBold
    nameL.TextSize = 11
    nameL.TextColor3 = Color3.new(1, 1, 1)
    nameL.TextXAlignment = Enum.TextXAlignment.Left
    nameL.TextTruncate = Enum.TextTruncate.AtEnd
    nameL.Text = plr.Name
    nameL.Parent = card
    local abL = nameL:Clone()
    abL.Position = UDim2.new(0, 44, 0, 20)
    abL.Size = UDim2.new(1, -48, 0, 18)
    abL.Font = Enum.Font.GothamMedium
    abL.TextSize = 10
    abL.TextColor3 = tcol
    abL.Text = ab .. "  READY"
    abL.Parent = card
    TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
        { Size = UDim2.new(1, 0, 0, 44) }):Play()
    task.delay(3.2, function()
        if not card.Parent then return end
        local t = TweenService:Create(card, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
            { Size = UDim2.new(1, 0, 0, 0) })
        t:Play()
        t.Completed:Wait()
        card:Destroy()
    end)
    if config.espSound ~= false then pcall(function() notifySnd:Play() end) end
end

local function updateEsp(plr)
    if plr == lp then return end
    local char = plr.Character
    if not char or not char.Parent then espReady[plr] = nil return end
    if config.espScope ~= "Everyone"
    and lp.Team and plr.Team and plr.Team == lp.Team then
        espReady[plr] = nil
        return
    end
    local ab, frac, stText = readAbility(plr, char)
    local ready = (type(frac) == "number" and frac >= 1) or stText == "READY"
    if ready and not espReady[plr] then
        espReady[plr] = true
        local tcol = plr.TeamColor and plr.TeamColor.Color or Color3.new(1, 1, 1)
        pcall(toast, plr, ab or "Ability", tcol)
    elseif not ready then
        espReady[plr] = nil
    end
end

task.spawn(function()
    while running do
        task.wait(0.5)
        if config.esp then
            for _, plr in ipairs(Players:GetPlayers()) do
                pcall(updateEsp, plr)
            end
        elseif next(espReady) then
            for plr in pairs(espReady) do espReady[plr] = nil end
        end
    end
end)

-- Lag switch

local refreshAll
local lagChip
local lagActive = false
local netClient = game:GetService("NetworkClient")

local function setLagLimit(kbps)
    pcall(function() netClient:SetOutgoingKBPSLimit(kbps) end)
end

local function setLag(on)
    if config.lag == on then return end
    config.lag = on
    if not on then lagActive = false setLagLimit(0) end
    saveSoon()
    if refreshAll then task.defer(refreshAll) end
end

local function lagKeyHit(input)
    local k = config.lagKey
    if type(k) ~= "string" or #k < 4 then return false end
    if k:sub(1, 3) == "KC_" then return input.KeyCode == Enum.KeyCode[k:sub(4)] end
    if k:sub(1, 3) == "UT_" then return input.UserInputType == Enum.UserInputType[k:sub(4)] end
    return false
end

local lagGhostCF, lagGhostFrozen, lagRealCF, lagChar, lagHist

RunService.Heartbeat:Connect(function()
    if not running or not config.lag then return end
    local mode = config.lagMode
    if mode ~= "Blink" and mode ~= "Trail" then return end
    local char = lp.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    if char ~= lagChar then lagChar, lagGhostCF, lagHist = char, nil, {} end
    lagRealCF = hrp.CFrame
    local ghost
    if mode == "Blink" then
        if lagGhostFrozen then
            if not lagGhostCF then lagGhostCF = lagRealCF end
            ghost = lagGhostCF
        end
    else
        lagHist = lagHist or {}
        local now = os.clock()
        table.insert(lagHist, { now, lagRealCF })
        local cut = now - math.max(0.05, (tonumber(config.lagOnMs) or 600) / 1000)
        while lagHist[2] and lagHist[2][1] < cut - 0.5 do table.remove(lagHist, 1) end
        for i = #lagHist, 1, -1 do
            if lagHist[i][1] <= cut then ghost = lagHist[i][2] break end
        end
        ghost = ghost or (lagHist[1] and lagHist[1][2]) or lagRealCF
    end
    if ghost then hrp.CFrame = ghost end
end)

RunService:BindToRenderStep("ScorehubLag", Enum.RenderPriority.Camera.Value - 1, function()
    if lagRealCF then
        local char = lp.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then hrp.CFrame = lagRealCF end
        lagRealCF = nil
    end
end)

task.spawn(function()
    while running do
        if config.lag then
            if config.lagMode == "Freeze" then
                lagActive = true
                setLagLimit(math.max(0.1, tonumber(config.lagKbps) or 3))
                local started = os.clock()
                local cap = tonumber(config.lagCap) or 12
                while running and config.lag and config.lagMode == "Freeze" do
                    if cap > 0 and os.clock() - started > cap then setLag(false) break end
                    task.wait(0.2)
                end
            elseif config.lagMode == "Blink" then
                local onMs  = math.max(0.05, (tonumber(config.lagOnMs) or 600) / 1000)
                local offMs = math.max(0.03, (tonumber(config.lagOffMs) or 150) / 1000)
                lagGhostFrozen = true
                task.wait(onMs)
                lagGhostFrozen = false
                task.wait(offMs)
            elseif config.lagMode == "Trail" then
                task.wait(0.2)
            else
                local onMs  = math.max(0.05, (tonumber(config.lagOnMs) or 600) / 1000)
                local offMs = math.max(0.03, (tonumber(config.lagOffMs) or 150) / 1000)
                lagActive = true
                setLagLimit(math.max(0.1, tonumber(config.lagKbps) or 3))
                task.wait(onMs)
                setLagLimit(0)
                lagActive = false
                task.wait(offMs)
            end
        else
            if lagActive then lagActive = false setLagLimit(0) end
            lagGhostFrozen = false
            task.wait(0.25)
        end
        if lagChip then lagChip.Visible = config.lag == true end
    end
end)

-- HitGround hook

do
    local sig = (hitRE and hitRE:IsA("RemoteEvent")) and hitRE.OnClientEvent or nil
    if sig then
        local logged = 0
        hitConn = sig:Connect(function(pos, a2, a3, a4, itemId, char)
            if typeof(pos) == "Vector3" then
                lastHitPos, lastHitTime = pos, os.clock()
                scanTimer = 1
            end
            if logged < 8 then
                logged = logged + 1
                trace(("HitGround a3=%s item=%s mine=%s"):format(
                    tostring(a3), tostring(itemId), tostring(char == lp.Character)))
            end
            local isGoal = (a3 == false) or (typeof(itemId) == "string" and itemId ~= "")
            if not (running and char == lp.Character and isGoal) then return end
            local pick = pickRandom(chosenList())
            if not pick then return end
            playEffectAt(pick, pos, char, 8)
        end)
        dbg("HitGround hooked")
    else
        derr("HitGround hook failed: " .. tostring(hitRE))
    end
end

-- UI

local function buildUI()

local C = {
    bg      = Color3.fromRGB(14, 15, 19),
    sidebar = Color3.fromRGB(11, 12, 16),
    header  = Color3.fromRGB(14, 15, 19),
    panel   = Color3.fromRGB(19, 21, 27),
    row     = Color3.fromRGB(19, 21, 27),
    rowHi   = Color3.fromRGB(26, 29, 38),
    pill    = Color3.fromRGB(27, 30, 39),
    border  = Color3.fromRGB(28, 31, 40),
    divider = Color3.fromRGB(24, 27, 35),
    off     = Color3.fromRGB(36, 40, 52),
    text    = Color3.fromRGB(238, 240, 246),
    dim     = Color3.fromRGB(130, 136, 152),
    muted   = Color3.fromRGB(90, 96, 112),
    accent  = ACCENT,
    danger  = Color3.fromRGB(255, 63, 87),
    pop     = Color3.fromRGB(20, 21, 28),
}

local function fnt(e, fb)
    local ok, v = pcall(function() return Enum.Font[e] end)
    return (ok and v) or fb
end
local F = {
    bold = fnt("GothamBold", Enum.Font.SourceSansBold),
    med  = fnt("GothamMedium", Enum.Font.SourceSansSemibold),
    reg  = fnt("Gotham", Enum.Font.SourceSans),
}

local function tw(o, t, props, style)
    TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quart, Enum.EasingDirection.Out), props):Play()
end

local function mk(class, parent, props)
    local o = Instance.new(class)
    for k, v in pairs(props or {}) do o[k] = v end
    o.Parent = parent
    return o
end
local function corner(o, r)
    mk("UICorner", o, { CornerRadius = UDim.new(0, r) })
    return o
end
local function stroke(o, col, trans)
    return mk("UIStroke", o, { Color = col or C.border, Thickness = 1,
        Transparency = trans or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end
local function label(parent, text, size, font, color, props)
    local p = {
        Text = text, TextSize = size, Font = font, TextColor3 = color,
        BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
    }
    for k, v in pairs(props or {}) do p[k] = v end
    return mk("TextLabel", parent, p)
end

local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
local screen = mk("ScreenGui", guiParent, { Name = "Scorehub", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local uiRefs = { swatchRefresh = {} }

local W, H = 880, 600
local SIDE_W = 192
local TOP_H = 54
local win = corner(mk("Frame", screen, {
    Size = UDim2.fromOffset(W, H),
    Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2),
    BackgroundColor3 = C.bg, BorderSizePixel = 0, Active = true, ClipsDescendants = true,
}), 12)
stroke(win, C.border)
local winScale = mk("UIScale", win, { Scale = 1 })
local menuOpen = true

local function toggleMenu()
    menuOpen = not menuOpen
    if menuOpen then
        win.Visible = true
        winScale.Scale = 0.94
        tw(winScale, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
    else
        if uiRefs.closePicker then uiRefs.closePicker() end
        local t = TweenService:Create(winScale, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 0.94 })
        t:Play()
        task.delay(0.16, function() if not menuOpen then win.Visible = false end end)
    end
end

local bindTarget
local bindEndAt = 0
UserInputService.InputBegan:Connect(function(input, gp)
    if bindTarget then
        if input.KeyCode == Enum.KeyCode.Escape then
            bindTarget = nil
        else
            local kind, name
            if input.KeyCode ~= Enum.KeyCode.Unknown then kind, name = "KC_", input.KeyCode.Name
            elseif input.UserInputType ~= Enum.UserInputType.None then kind, name = "UT_", input.UserInputType.Name end
            if name then
                config[bindTarget] = kind .. name
                saveSoon()
                bindTarget = nil
            end
        end
        bindEndAt = os.clock()
        if uiRefs.bindBtns then for _, f in pairs(uiRefs.bindBtns) do f() end end
        return
    end
    if not running then return end
    if lagKeyHit(input) then setLag(not config.lag) return end
    if gp then return end
    if input.KeyCode == Enum.KeyCode.RightShift then
        toggleMenu()
    elseif input.KeyCode == Enum.KeyCode.End then
        if uiRefs.unload then uiRefs.unload()
        else running = false screen:Destroy() end
    end
end)

local sidebar = mk("Frame", win, {
    Size = UDim2.new(0, SIDE_W, 1, 0), BackgroundColor3 = C.sidebar, BorderSizePixel = 0,
})
mk("Frame", sidebar, {
    Size = UDim2.new(0, 1, 1, 0), Position = UDim2.new(1, -1, 0, 0),
    BackgroundColor3 = C.border, BorderSizePixel = 0,
})

local brandBox = mk("Frame", sidebar, {
    Size = UDim2.new(1, 0, 0, 68), BackgroundTransparency = 1,
})
local logoBadge = corner(mk("Frame", brandBox, {
    Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0, 16, 0, 18),
    BackgroundColor3 = Color3.fromRGB(20, 26, 44), BorderSizePixel = 0,
}), 8)
stroke(logoBadge, Color3.fromRGB(45, 65, 120))
label(logoBadge, "SH", 13, F.bold, C.text, {
    Size = UDim2.new(1, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
})
label(brandBox, "ScoreHub", 14, F.bold, C.text, {
    Size = UDim2.new(1, -60, 0, 18), Position = UDim2.new(0, 56, 0, 17),
})
label(brandBox, "Volleyball Legends", 11, F.reg, C.dim, {
    Size = UDim2.new(1, -60, 0, 14), Position = UDim2.new(0, 56, 0, 34),
})

local navScroll = mk("Frame", sidebar, {
    Size = UDim2.new(1, -20, 1, -136), Position = UDim2.new(0, 10, 0, 72),
    BackgroundTransparency = 1,
})
mk("UIListLayout", navScroll, {
    Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder,
})

local footer = mk("Frame", sidebar, {
    Size = UDim2.new(1, 0, 0, 60), Position = UDim2.new(0, 0, 1, -60),
    BackgroundTransparency = 1,
})
mk("Frame", footer, {
    Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 0, 0),
    BackgroundColor3 = C.border, BorderSizePixel = 0,
})
local avImg = corner(mk("ImageLabel", footer, {
    Size = UDim2.fromOffset(32, 32), Position = UDim2.new(0, 14, 0.5, -16),
    BackgroundColor3 = C.panel, BorderSizePixel = 0,
    Image = ("rbxthumb://type=AvatarHeadShot&id=%d&w=100&h=100"):format(lp.UserId),
}), 16)
stroke(avImg, C.accent, 0.4)
label(footer, lp.Name, 12, F.bold, C.text, {
    Size = UDim2.new(1, -74, 0, 16), Position = UDim2.new(0, 54, 0, 14),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
local footerSub = label(footer, "lifetime access", 11, F.reg, C.dim, {
    Size = UDim2.new(1, -74, 0, 14), Position = UDim2.new(0, 54, 0, 30),
})
label(footer, "›", 16, F.med, C.dim, {
    Size = UDim2.new(0, 16, 1, 0), Position = UDim2.new(1, -24, 0, 0),
    TextXAlignment = Enum.TextXAlignment.Center,
})

local header = mk("Frame", win, {
    Size = UDim2.new(1, -SIDE_W, 0, TOP_H), Position = UDim2.new(0, SIDE_W, 0, 0),
    BackgroundColor3 = C.header, BorderSizePixel = 0,
})
mk("Frame", header, {
    Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, -1),
    BackgroundColor3 = C.border, BorderSizePixel = 0,
})

local profDropBtn = corner(mk("TextButton", header, {
    Size = UDim2.new(0, 150, 0, 32), Position = UDim2.new(0, 18, 0.5, -16),
    BackgroundColor3 = C.panel, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
}), 7)
stroke(profDropBtn, C.border)
local diskIcon = corner(mk("Frame", profDropBtn, {
    Size = UDim2.fromOffset(12, 12), Position = UDim2.new(0, 11, 0.5, -6),
    BackgroundColor3 = C.dim, BorderSizePixel = 0,
}), 2)
mk("Frame", diskIcon, {
    Size = UDim2.fromOffset(6, 4), Position = UDim2.new(0.5, -3, 0, 1),
    BackgroundColor3 = C.panel, BorderSizePixel = 0,
})
local chipProfile = label(profDropBtn, activeProfile, 12, F.med, C.text, {
    Size = UDim2.new(1, -52, 1, 0), Position = UDim2.new(0, 30, 0, 0),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
label(profDropBtn, "⌄", 13, F.bold, C.dim, {
    Size = UDim2.new(0, 20, 1, -4), Position = UDim2.new(1, -24, 0, 0),
    TextXAlignment = Enum.TextXAlignment.Center,
})

local content = mk("Frame", win, {
    Size = UDim2.new(1, -SIDE_W - 32, 1, -TOP_H - 28),
    Position = UDim2.new(0, SIDE_W + 16, 0, TOP_H + 14),
    BackgroundTransparency = 1,
})

local pages, tabButtons, subButtons, subContainers = {}, {}, {}, {}
local currentTab, currentSub
local navOrder = 0
local function nextNavOrder() navOrder = navOrder + 1 return navOrder end

local function addCategoryHeader(title)
    local h = mk("Frame", navScroll, {
        Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = nextNavOrder(),
    })
    label(h, title:upper(), 10, F.bold, C.muted, {
        Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 10, 0, 4),
    })
end

local TAB_ICONS = {
    ["Score Effects"] = "✦",
    ["Visuals"]       = "◈",
    ["Network"]       = "⚡",
    ["Profiles"]      = "❖",
    ["Settings"]      = "⚙",
}
local SUB_ICONS = {
    ["All"]      = "•",
    ["Equipped"] = "★",
    ["Ball"]     = "◉",
    ["Players"]  = "♟",
    ["Lag"]      = "⇄",
}

local function selectSub(tabName, subName)
    local page = pages[tabName]
    currentSub = subName
    for k, b in pairs(subButtons) do
        local on = (k == tabName .. "/" .. subName)
        tw(b, 0.16, {
            BackgroundTransparency = on and 0 or 1,
            BackgroundColor3 = on and C.rowHi or C.sidebar,
        })
        tw(b.Lbl, 0.16, { TextColor3 = on and C.text or C.dim })
        tw(b.Ico, 0.16, { TextColor3 = on and C.accent or C.dim })
    end
    if page.subs then
        for n, f in pairs(page.subs) do f.Visible = (n == subName) end
    end
end

local function selectTab(name, subOverride)
    currentTab = name
    if uiRefs.closePicker then uiRefs.closePicker() end
    for n, p in pairs(pages) do p.frame.Visible = (n == name) end
    for n, b in pairs(tabButtons) do
        local on = (n == name)
        tw(b, 0.16, {
            BackgroundTransparency = on and 0 or 1,
            BackgroundColor3 = on and C.rowHi or C.sidebar,
        })
        tw(b.Lbl, 0.16, { TextColor3 = on and C.text or C.dim })
        tw(b.Ico, 0.16, { TextColor3 = on and C.accent or C.dim })
    end
    for n, sc in pairs(subContainers) do
        local open = (n == name)
        local targetH = open and sc.fullH or 0
        sc.frame.Visible = true
        tw(sc.frame, 0.2, { Size = UDim2.new(1, 0, 0, targetH) })
    end
    local page = pages[name]
    if page.subs then
        selectSub(name, subOverride or page.defaultSub)
    else
        currentSub = nil
        for _, b in pairs(subButtons) do
            tw(b, 0.14, { BackgroundTransparency = 1 })
            tw(b.Lbl, 0.14, { TextColor3 = C.dim })
            tw(b.Ico, 0.14, { TextColor3 = C.dim })
        end
    end
end

local function makeNavButton(parent, name, iconText, indent, order)
    local b = corner(mk("TextButton", parent, {
        Size = UDim2.new(1, -indent, 0, 32),
        Position = UDim2.new(0, indent, 0, 0),
        Text = "", BackgroundColor3 = C.rowHi, BackgroundTransparency = 1,
        BorderSizePixel = 0, LayoutOrder = order, AutoButtonColor = false,
    }), 7)
    label(b, iconText or "•", 13, F.bold, C.dim, {
        Size = UDim2.new(0, 22, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Center, Name = "Ico",
    })
    label(b, name, 12, F.med, C.dim, {
        Size = UDim2.new(1, -38, 1, 0), Position = UDim2.new(0, 34, 0, 0), Name = "Lbl",
    })
    return b
end

local function addPage(name, order, opts)
    opts = opts or {}
    if opts.category then addCategoryHeader(opts.category) end
    local frame = mk("Frame", content, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false })
    local page = { frame = frame, search = opts.search, subs = nil, defaultSub = nil }
    local tb = makeNavButton(navScroll, name, TAB_ICONS[name] or "•", 0, nextNavOrder())
    tabButtons[name] = tb
    tb.MouseEnter:Connect(function() if currentTab ~= name then tw(tb.Lbl, 0.12, { TextColor3 = C.text }) end end)
    tb.MouseLeave:Connect(function() if currentTab ~= name then tw(tb.Lbl, 0.12, { TextColor3 = C.dim }) end end)
    tb.MouseButton1Click:Connect(function() selectTab(name) end)

    if opts.subs then
        page.subs = {}
        local scWrap = mk("Frame", navScroll, {
            Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1,
            ClipsDescendants = true, LayoutOrder = nextNavOrder(),
        })
        local scInner = mk("Frame", scWrap, {
            Size = UDim2.new(1, -14, 1, 0), Position = UDim2.new(0, 14, 0, 0),
            BackgroundTransparency = 1,
        })
        mk("UIListLayout", scInner, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        subContainers[name] = { frame = scWrap, fullH = #opts.subs * 34 }
        for i, sn in ipairs(opts.subs) do
            local sf = mk("Frame", frame, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Visible = false })
            page.subs[sn] = sf
            local sb = makeNavButton(scInner, sn, SUB_ICONS[sn] or "•", 0, i)
            subButtons[name .. "/" .. sn] = sb
            sb.MouseEnter:Connect(function()
                if currentTab ~= name or currentSub ~= sn then tw(sb.Lbl, 0.12, { TextColor3 = C.text }) end
            end)
            sb.MouseLeave:Connect(function()
                if currentTab ~= name or currentSub ~= sn then tw(sb.Lbl, 0.12, { TextColor3 = C.dim }) end
            end)
            sb.MouseButton1Click:Connect(function()
                if currentTab ~= name then selectTab(name, sn) else selectSub(name, sn) end
            end)
            if i == 1 then page.defaultSub = sn end
        end
    end
    pages[name] = page
    return page
end

profDropBtn.MouseButton1Click:Connect(function() selectTab("Profiles") end)
footer.InputBegan:Connect(function(i)
    if i.UserInputType == Enum.UserInputType.MouseButton1 then selectTab("Settings") end
end)

local groupTitles = {}
local function rowBase(g, height)
    local y = g:slot(height)
    local r = mk("Frame", g.body, {
        Size = UDim2.new(1, 0, 0, height), Position = UDim2.new(0, 0, 0, y),
        BackgroundColor3 = C.rowHi, BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    return r
end

local function group(parent, title, x, y, w, fixedH)
    local wrap = mk("Frame", parent, {
        Position = UDim2.new(0, x, 0, y), Size = UDim2.new(0, w, 0, fixedH or 60),
        BackgroundTransparency = 1,
    })
    local cap = label(wrap, title:upper(), 10, F.bold, C.muted, {
        Size = UDim2.new(1, -8, 0, 18), Position = UDim2.new(0, 4, 0, 0),
    })
    local g = corner(mk("Frame", wrap, {
        Position = UDim2.new(0, 0, 0, 20), Size = UDim2.new(1, 0, 1, -20),
        BackgroundColor3 = C.panel, BorderSizePixel = 0, ClipsDescendants = true,
    }), 9)
    stroke(g, C.border)
    local body = mk("Frame", g, {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1,
    })
    local h = 0
    local rows = 0
    local api = { frame = wrap, card = g, body = body, title = cap }
    function api:slot(height)
        if rows > 0 then
            mk("Frame", body, {
                Size = UDim2.new(1, -24, 0, 1), Position = UDim2.new(0, 12, 0, h),
                BackgroundColor3 = C.divider, BorderSizePixel = 0,
            })
            h = h + 1
        end
        rows = rows + 1
        local y0 = h
        h = h + height
        if not fixedH then wrap.Size = UDim2.new(0, w, 0, 20 + h) end
        return y0
    end
    return api
end

local function hoverable(r)
    r.MouseEnter:Connect(function() tw(r, 0.12, { BackgroundTransparency = 0.45 }) end)
    r.MouseLeave:Connect(function() tw(r, 0.12, { BackgroundTransparency = 1 }) end)
end

local function makeSwitch(parent, rightOffset, get)
    local track = corner(mk("Frame", parent, {
        Size = UDim2.fromOffset(36, 20), Position = UDim2.new(1, -rightOffset - 36, 0.5, -10),
        BackgroundColor3 = get() and C.accent or C.off, BorderSizePixel = 0,
    }), 10)
    local knob = corner(mk("Frame", track, {
        Size = UDim2.fromOffset(14, 14),
        Position = get() and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }), 7)
    local function refresh()
        local on = get()
        tw(track, 0.16, { BackgroundColor3 = on and C.accent or C.off })
        tw(knob, 0.16, { Position = on and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7) })
    end
    return track, refresh
end

local function toggleRow(g, text, get, set)
    local r = rowBase(g, 38)
    hoverable(r)
    local lbl = label(r, text, 12, F.med, get() and C.text or C.dim, {
        Size = UDim2.new(1, -110, 1, 0), Position = UDim2.new(0, 14, 0, 0), Name = "L",
    })
    local _, refreshSw = makeSwitch(r, 14, get)
    local function refresh()
        local on = get()
        refreshSw()
        tw(lbl, 0.14, { TextColor3 = on and C.text or C.dim })
    end
    local hit = mk("TextButton", r, {
        Size = UDim2.new(1, -40, 1, 0), BackgroundTransparency = 1, Text = "",
    })
    hit.MouseButton1Click:Connect(function()
        set(not get())
        refresh()
    end)
    return { refresh = refresh, frame = r }
end

local function sliderRow(g, text, min, max, step, get, set, fmt)
    local r = rowBase(g, 48)
    hoverable(r)
    fmt = fmt or function(v) return tostring(v) end
    label(r, text, 12, F.med, C.text, {
        Size = UDim2.new(0.6, 0, 0, 20), Position = UDim2.new(0, 14, 0, 5),
    })
    local val = label(r, fmt(get()), 11, F.bold, C.accent, {
        Size = UDim2.new(0.4, -14, 0, 20), Position = UDim2.new(0.6, 0, 0, 5),
        TextXAlignment = Enum.TextXAlignment.Right,
    })
    local bar = corner(mk("Frame", r, {
        Size = UDim2.new(1, -28, 0, 5), Position = UDim2.new(0, 14, 0, 32),
        BackgroundColor3 = C.off, BorderSizePixel = 0,
    }), 3)
    local fill = corner(mk("Frame", bar, {
        Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = C.accent, BorderSizePixel = 0,
    }), 3)
    local knob = corner(mk("Frame", bar, {
        Size = UDim2.fromOffset(12, 12), AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0), BackgroundColor3 = C.text, BorderSizePixel = 0,
    }), 6)
    mk("UIStroke", knob, { Color = C.accent, Thickness = 2 })
    local hit = mk("TextButton", r, {
        Size = UDim2.new(1, -28, 0, 22), Position = UDim2.new(0, 14, 0, 22),
        BackgroundTransparency = 1, Text = "",
    })
    local function render(v)
        local p = math.clamp((v - min) / (max - min), 0, 1)
        tw(fill, 0.08, { Size = UDim2.new(p, 0, 1, 0) })
        tw(knob, 0.08, { Position = UDim2.new(p, 0, 0.5, 0) })
        val.Text = fmt(v)
    end
    local function fromX(x)
        local p = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
        local v = min + p * (max - min)
        v = math.clamp(math.floor(v / step + 0.5) * step, min, max)
        set(v)
        render(v)
    end
    local sliding = false
    hit.MouseButton1Down:Connect(function(x) sliding = true fromX(x) end)
    UserInputService.InputChanged:Connect(function(i)
        if sliding and i.UserInputType == Enum.UserInputType.MouseMovement then fromX(i.Position.X) end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
    end)
    render(get())
    return { refresh = function() render(get()) end }
end

local function cycleRow(g, text, options, get, set)
    local r = rowBase(g, 38)
    hoverable(r)
    label(r, text, 12, F.med, C.text, { Size = UDim2.new(0.52, 0, 1, 0), Position = UDim2.new(0, 14, 0, 0) })
    local pill = corner(mk("Frame", r, {
        Size = UDim2.new(0, 122, 0, 24), Position = UDim2.new(1, -136, 0.5, -12),
        BackgroundColor3 = C.pill, BorderSizePixel = 0,
    }), 6)
    stroke(pill, C.border)
    local val = label(pill, tostring(get()), 11, F.med, C.text, {
        Size = UDim2.new(1, -24, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    label(pill, "⌄", 12, F.bold, C.dim, {
        Size = UDim2.new(0, 18, 1, -3), Position = UDim2.new(1, -20, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    local function idx()
        local cur = get()
        for i, o in ipairs(options) do if o == cur then return i end end
        return 1
    end
    local function step(dir)
        local i = idx() + dir
        if i > #options then i = 1 elseif i < 1 then i = #options end
        set(options[i])
        val.Text = options[i]
    end
    local hit = mk("TextButton", r, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" })
    hit.MouseButton1Click:Connect(function() step(1) end)
    hit.MouseButton2Click:Connect(function() step(-1) end)
    return { refresh = function() val.Text = tostring(get()) end }
end

local function infoRow(g, text, valueText)
    local r = rowBase(g, 38)
    label(r, text, 12, F.reg, C.dim, { Size = UDim2.new(0.48, 0, 1, 0), Position = UDim2.new(0, 14, 0, 0) })
    local v = label(r, valueText, 12, F.med, C.text, {
        Size = UDim2.new(0.52, -14, 1, 0), Position = UDim2.new(0.48, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
    })
    return v
end

local function inputRow(g, placeholder)
    local r = rowBase(g, 42)
    local wrap = corner(mk("Frame", r, {
        Size = UDim2.new(1, -28, 0, 28), Position = UDim2.new(0, 14, 0.5, -14),
        BackgroundColor3 = C.pill, BorderSizePixel = 0,
    }), 6)
    stroke(wrap, C.border)
    return mk("TextBox", wrap, {
        Size = UDim2.new(1, -20, 1, 0), Position = UDim2.new(0, 10, 0, 0),
        PlaceholderText = placeholder, Text = "", Font = F.reg, TextSize = 12,
        TextColor3 = C.text, PlaceholderColor3 = C.dim, BackgroundTransparency = 1,
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
    })
end

local function buttonRow(g, text, onClick, color)
    local r = rowBase(g, 38)
    hoverable(r)
    label(r, text, 12, F.med, color or C.text, {
        Size = UDim2.new(1, -36, 1, 0), Position = UDim2.new(0, 14, 0, 0),
    })
    label(r, "›", 15, F.bold, color or C.dim, {
        Size = UDim2.new(0, 20, 1, 0), Position = UDim2.new(1, -28, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Center,
    })
    mk("TextButton", r, { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "" })
        .MouseButton1Click:Connect(onClick)
    return r
end

local function wireScroll(sc)
    local dragStart, posStart
    sc.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            dragStart = i.Position.Y
            posStart = sc.CanvasPosition
        end
    end)
    UserInputService.InputChanged:Connect(function(i)
        if dragStart and i.UserInputType == Enum.UserInputType.MouseMovement then
            local max = math.max(0, sc.CanvasSize.Y.Offset - sc.AbsoluteSize.Y)
            sc.CanvasPosition = Vector2.new(0,
                math.clamp(posStart.Y - (i.Position.Y - dragStart), 0, max))
        end
    end)
    UserInputService.InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then dragStart = nil end
    end)
end

local contentW = W - SIDE_W - 32
local contentH = H - TOP_H - 28
local colW = math.floor((contentW - 14) / 2)
local refreshers = {}
local effectRows, effectScrolls = {}, {}
local chosenListLocal

local function addPageList(name, page, subList)
    local pageSubs = page.subs or {}
    local groups = {}
    for _, sub in ipairs(subList) do
        local sf = pageSubs[sub]
        sf.Size = UDim2.new(0, colW, 0, contentH - 160)
        local g = group(sf, sub == "All" and "Effects" or "Equipped effects", 0, 0, colW, contentH - 160)
        groups[sub] = g
        local sc = mk("ScrollingFrame", g.body, {
            Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4),
            BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.accent, CanvasSize = UDim2.new(0, 0, 0, 0),
        })
        mk("UIListLayout", sc, { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder })
        wireScroll(sc)
        effectScrolls[sub] = sc
    end
    return groups
end

local function infoBind(g, key, value)
    local r = rowBase(g, 38)
    label(r, key, 12, F.reg, C.dim, { Size = UDim2.new(0.48, 0, 1, 0), Position = UDim2.new(0, 14, 0, 0) })
    label(r, value, 12, F.med, C.text, {
        Size = UDim2.new(0.52, -14, 1, 0), Position = UDim2.new(0.48, 0, 0, 0),
        TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
    })
end

local pEffects = addPage("Score Effects", 1, { category = "INVENTORY", search = true, subs = { "All", "Equipped" } })
local groupsEffect = addPageList("Score Effects", pEffects, { "All", "Equipped" })

local pVis = addPage("Visuals", 2, { category = "COMMON", subs = { "Players", "Ball" } })
local pNet = addPage("Network", 3, { subs = { "Lag" } })
local pProf = addPage("Profiles", 4, { category = "MISCELLANEOUS" })
local pSet = addPage("Settings", 5)

local function refreshProfileUI()
    chipProfile.Text = activeProfile
end

refreshAll = function()
    refreshProfileUI()
    if pProf.frame.Visible then
        local activeLbl = pProf.frame:FindFirstChild("__active", true)
    end
end

selectTab("Score Effects")
end

local okUI, uiErr = pcall(buildUI)
if not okUI then
    derr("UI build failed: " .. tostring(uiErr))
    return
end

dbg("Loaded. RightShift toggles menu, End unloads.")
