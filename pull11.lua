if not LPH_OBFUSCATED then
    LPH_ENCSTR = LPH_ENCSTR or function(...) return ... end
    LPH_NO_VIRTUALIZE = LPH_NO_VIRTUALIZE or function(...) return ... end
end

getgenv().PullLeverConfig = getgenv().PullLeverConfig or {
    ["Enabled"]            = true,
    ["Team"]               = "Pirates",
    ["Hop Mirage"]         = true,
    ["Boost FPS"]          = true,
    ["FPS"]                = 20,
    ["Black Screen"]       = true,

    ["Use Mirage API"]     = true,
    ["Mirage API"]         = "https://baorph.pythonanywhere.com/token?api_key=baorapi&token=LH8UzJvtTZfmndW1&key=mirage",
    ["Avoid Full Server"]  = true,
    ["Max Players"]        = 11,

    -- Lay DUNG 5 server Mirage usable MOI NHAT; thu JobId cach nhau 2 giay
    ["Fetch Count"]        = 5,
}

-- PullLever V5.3 - __ServerBrowser ONLY | 5 newest / 2s | anti-rubberband | Completed-pull
LPH_NO_VIRTUALIZE(function()

local PlayerGui
local _statusLabel, _raceLabel, _seaLabel, _mirrorLabel, _valkLabel, _doorLabel, _progressLabel, _mirageLabel

local _lastStatus = ""

local function SetStatus(text)
    text = tostring(text or "")
    _lastStatus = text

    print("[PullLever] " .. text)

    if _statusLabel then
        -- Ghi vao CoreGui/gethui co the loi neu thread dang o identity
        -- thap (sau khi require module game) -> khong de no giet script.
        pcall(function() _statusLabel.Text = "Status: " .. text end)
    end
end

local function DebugStatus(tag, err)
    local msg = "[" .. tostring(tag) .. "] " .. tostring(err)
    warn("[PullLever] " .. msg)
    SetStatus(msg)
end

local function MakeUI()
    local ok, parent = pcall(function()
        return (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not ok or not parent then return end

    local old = parent:FindFirstChild("PullLeverUI")
    if old then old:Destroy() end

    local gui = Instance.new("ScreenGui")
    gui.Name = "PullLeverUI"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 999999
    gui.Parent = parent

    local main = Instance.new("Frame")
    main.Name = "StatusContainer"
    main.AnchorPoint = Vector2.new(0.5, 0.5)
    main.Position = UDim2.fromScale(0.5, 0.5)
    main.Size = UDim2.new(0.8, 0, 0, 390)
    main.BackgroundTransparency = 1
    main.BorderSizePixel = 0
    main.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.Padding = UDim.new(0, 7)
    layout.Parent = main

    local function row(order, size, height, bold)
        local label = Instance.new("TextLabel")
        label.Name = "StatusRow" .. tostring(order)
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.Size = UDim2.new(1, 0, 0, height)
        label.Font = bold and Enum.Font.GothamBold or Enum.Font.GothamMedium
        label.TextSize = size
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.TextWrapped = true
        label.LayoutOrder = order
        label.Text = ""
        label.Parent = main
        return label
    end

    _statusLabel = row(1, 34, 52, true)
    _seaLabel = row(2, 25, 34, false)
    _raceLabel = row(3, 25, 34, false)
    _mirrorLabel = row(4, 25, 34, false)
    _valkLabel = row(5, 25, 34, false)
    _mirageLabel = row(6, 25, 34, false)
    _doorLabel = row(7, 25, 34, false)
    _progressLabel = row(8, 25, 34, false)

    _statusLabel.Text = "Status: " .. tostring(_lastStatus ~= "" and _lastStatus or "init")
    _seaLabel.Text = "Sea: ?"
    _raceLabel.Text = "Race V3: ?"
    _mirrorLabel.Text = "Mirror Fractal: ?"
    _valkLabel.Text = "Valkyrie Helm: ?"
    _mirageLabel.Text = "Mirage Island: ?"
    _doorLabel.Text = "Temple Door: ?"
    _progressLabel.Text = "RaceV4 Check: ?"

    _G.__PullLeverUIBuilt = true
end

getgenv().PullLeverConfig = getgenv().PullLeverConfig or {}

local Config = getgenv().PullLeverConfig

Config["Enabled"]           = Config["Enabled"] ~= false
Config["Team"]              = Config["Team"] or "Pirates"
Config["Hop Mirage"]        = Config["Hop Mirage"] ~= false
Config["Use Mirage API"]    = Config["Use Mirage API"] ~= false

-- Endpoint thuc te duoc goi bang key=mirage.
-- API envelope hien tai van co the tra data.key == "island"; day la binh thuong.
-- Khong rewrite URL dua theo data.key.
Config["Avoid Full Server"] = Config["Avoid Full Server"] ~= false
Config["Max Players"]       = Config["Max Players"] or 11
Config["Fetch Count"]       = 5
Config["Boost FPS"]         = Config["Boost FPS"] ~= false
Config["FPS"]               = Config["FPS"] or 20
Config["Black Screen"]      = Config["Black Screen"] or false

SetStatus("Waiting game loaded...")
if not game:IsLoaded() then
    repeat task.wait(0.5) until game:IsLoaded()
end
SetStatus("Game loaded")

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Workspace         = game:GetService("Workspace")
local Lighting          = game:GetService("Lighting")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local HttpService       = game:GetService("HttpService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local StarterPlayer     = game:GetService("StarterPlayer")

local LocalPlayer = Players.LocalPlayer
local Character, Humanoid, HumanoidRootPart

-- ============================================================
-- MIRAGE LOCAL STATE ONLY
--
-- JOIN JOBID CHI DUNG:
--   ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", JobId)
--
-- KHONG TeleportService.
-- KHONG shared blacklist / claim / join_fail file.
-- JoinedMirageJobs chi ton tai trong RAM cua session hien tai de
-- khong lap lai ngay JobId vua thu that bai.
-- ============================================================
local JoinedMirageJobs = {}

local function FindMirageIsland()
    local map = workspace:FindFirstChild("Map")
    return map and map:FindFirstChild("MysticIsland") or nil
end

local function GetServerBrowser()
    return ReplicatedStorage:FindFirstChild("__ServerBrowser")
end

SetStatus("Creating UI...")
pcall(MakeUI)
SetStatus("UI ready")

SetStatus("Waiting PlayerGui...")
PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 30)
if not PlayerGui then
    SetStatus("PlayerGui timeout")
else
    SetStatus("PlayerGui ready")
end

-- ============================================================
-- TEAM SELECTOR - KATA COORDINATOR FLOW
-- ============================================================

getgenv().Config = getgenv().Config or {}
local TeamConfig = getgenv().Config

local function NormalizeTeam(value)
    local key = tostring(value or "Pirates")
        :lower()
        :gsub("[^%a]", "")

    if key == "marine" or key == "marines" then
        return "Marines"
    end

    return "Pirates"
end

-- PullLeverConfig is the authority for this script.
-- Stale globals from another script are not allowed to override it.
local RequestedTeam =
    NormalizeTeam(Config["Team"] or "Pirates")

Config["Team"] = RequestedTeam
TeamConfig.TEAM = RequestedTeam
TeamConfig["Select Team"] = RequestedTeam

-- Compatibility for Banana-style consumers.
getgenv().Team =
    RequestedTeam == "Marines"
    and "Marine"
    or "Pirate"

repeat task.wait() until Players.LocalPlayer
repeat task.wait() until Players.LocalPlayer:FindFirstChild("PlayerGui")

-- Same principle as Kata: wait for CommF_ and force through SetTeam first.
local TeamCommF =
    ReplicatedStorage
        :WaitForChild("Remotes")
        :WaitForChild("CommF_")

local function CurrentTeamName()
    return LocalPlayer.Team
        and tostring(LocalPlayer.Team.Name)
        or "NONE"
end

local function ClickRequestedTeamButton()
    local pg =
        LocalPlayer:FindFirstChildOfClass("PlayerGui")

    if not pg then
        return false
    end

    local main =
        pg:FindFirstChild("Main (minimal)")
        or pg:FindFirstChild("Main")

    if not main then
        for _, child in ipairs(pg:GetChildren()) do
            if tostring(child.Name):find("Main", 1, true) then
                main = child
                break
            end
        end
    end

    local choose =
        main and main:FindFirstChild(
            "ChooseTeam",
            true
        )

    local container =
        choose and choose:FindFirstChild(
            "Container"
        )

    if not container then
        return false
    end

    local teamFrame =
        container:FindFirstChild(
            RequestedTeam
        )

    if not teamFrame then
        return false
    end

    -- Kata-style fallback: do not depend on a fixed .Frame.TextButton path.
    if teamFrame:IsA("GuiButton") then
        local ok = pcall(function()
            if type(firesignal) == "function" then
                firesignal(
                    teamFrame.Activated
                )
            else
                teamFrame:Activate()
            end
        end)

        if ok then
            return true
        end
    end

    for _, obj in ipairs(
        teamFrame:GetDescendants()
    ) do
        if obj:IsA("GuiButton") then
            local ok = pcall(function()
                if type(firesignal) == "function" then
                    firesignal(
                        obj.Activated
                    )
                else
                    obj:Activate()
                end
            end)

            if ok then
                return true
            end
        end
    end

    return false
end

local function EnsureTeam()
    if CurrentTeamName()
        == RequestedTeam
    then
        return true
    end

    SetStatus(
        "Choosing "
        .. RequestedTeam
        .. "..."
    )

    -- Same cadence/structure as Kata Coordinator.
    for _ = 1, 20 do
        if CurrentTeamName()
            == RequestedTeam
        then
            return true
        end

        pcall(function()
            TeamCommF:InvokeServer(
                "SetTeam",
                RequestedTeam
            )
        end)

        task.wait(0.35)

        if CurrentTeamName()
            == RequestedTeam
        then
            return true
        end

        pcall(
            ClickRequestedTeamButton
        )

        task.wait(0.35)
    end

    return CurrentTeamName()
        == RequestedTeam
end

-- Hard gate: do not let PullLever proceed until the requested team exists.
while not EnsureTeam() do
    SetStatus(
        "Unable to choose "
        .. RequestedTeam
        .. " | retrying..."
    )

    task.wait(0.75)
end

SetStatus(
    "Team selected: "
    .. RequestedTeam
)

-- ============================================================
-- CHARACTER BINDER
-- Chống race-condition sau respawn/hop:
-- callback Character cũ không được phép ghi đè Root/Humanoid của Character mới.
-- ============================================================
local CharacterGeneration = 0

local function BindCharacter(character)
    CharacterGeneration += 1
    local generation = CharacterGeneration

    Character = character
    Humanoid = character and character:FindFirstChildOfClass("Humanoid") or nil
    HumanoidRootPart = character and character:FindFirstChild("HumanoidRootPart") or nil

    if not character then
        return
    end

    task.spawn(function()
        local deadline = os.clock() + 20

        while os.clock() < deadline
            and generation == CharacterGeneration
            and LocalPlayer.Character == character
        do
            local hum = character:FindFirstChildOfClass("Humanoid")
            local root = character:FindFirstChild("HumanoidRootPart")

            if hum and root then
                if generation == CharacterGeneration
                    and LocalPlayer.Character == character
                then
                    Character = character
                    Humanoid = hum
                    HumanoidRootPart = root
                end
                return
            end

            task.wait(0.1)
        end
    end)
end

local function RefreshCharacter()
    local current = LocalPlayer.Character

    if current ~= Character then
        BindCharacter(current)
    elseif current then
        Humanoid = current:FindFirstChildOfClass("Humanoid")
        HumanoidRootPart = current:FindFirstChild("HumanoidRootPart")
    end

    return Character, Humanoid, HumanoidRootPart
end

SetStatus("Waiting character...")
while true do
    RefreshCharacter()

    if Character
        and Character.Parent
        and Humanoid
        and HumanoidRootPart
        and Humanoid.Health > 0
    then
        break
    end

    task.wait(0.15)
end
SetStatus("Character ready")

LocalPlayer.CharacterAdded:Connect(function(character)
    BindCharacter(character)
end)

LocalPlayer.CharacterRemoving:Connect(function(character)
    if Character == character then
        CharacterGeneration += 1
        Character = nil
        Humanoid = nil
        HumanoidRootPart = nil
    end
end)


-- ============================================================
-- CHARACTER NOCLIP
-- Keep character body parts non-collidable while PullLever is running.
-- Proxy tween already has directional obstacle noclip; this adds the
-- character-side noclip from the older PullLever source as a second layer.
-- ============================================================

local function ApplyCharacterNoclip()
    local character = LocalPlayer.Character
    if not character then
        return
    end

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart")
            and part.CanCollide
        then
            part.CanCollide = false
        end
    end
end

local CharacterNoclipConnection =
    RunService.Stepped:Connect(function()
        pcall(ApplyCharacterNoclip)
    end)

SetStatus("Waiting Data/Race...")
repeat
    task.wait(1)
until LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Race")
SetStatus("Data/Race ready: " .. tostring(LocalPlayer.Data.Race.Value))

local Remotes = {}
setmetatable(Remotes, {
    __index = function(_, Key)
        return ReplicatedStorage:WaitForChild("Remotes"):WaitForChild(Key, 30)
    end
})
local CommF_ = Remotes.CommF_
local CommE  = Remotes.CommE

local Sea, SeaIndex = "Unknown", 0

local function GetSeaIndex()
    local placeId = game.PlaceId

    if placeId == 85211729168715 or placeId == 2753915549 then
        return 1, "Main"
    elseif placeId == 79091703265657 or placeId == 4442272183 then
        return 2, "Dressrosa"
    elseif placeId == 100117331123089 or placeId == 7449423635 then
        return 3, "Zou"
    end

    local ok, mapAttr = pcall(function() return workspace:GetAttribute("MAP") end)
    if ok and mapAttr ~= nil then
        local mapNum = tostring(mapAttr):match("%d+")
        if mapNum then
            local n = tonumber(mapNum)
            if n == 1 then return 1, "Main" end
            if n == 2 then return 2, "Dressrosa" end
            if n == 3 then return 3, "Zou" end
        end
    end

    return 0, "Unknown"
end

local function RefreshSea()
    SeaIndex, Sea = GetSeaIndex()
    return SeaIndex, Sea
end

local function EnsureSea3()
    RefreshSea()

    if SeaIndex == 3 then
        return true
    end

    SetStatus("Not Sea 3 | Current: " .. tostring(Sea) .. " -> TravelZou")

    pcall(function()
        CommF_:InvokeServer("TravelZou")
    end)

    task.wait(8)

    RefreshSea()

    if SeaIndex ~= 3 then
        SetStatus("Still not Sea 3 (" .. tostring(Sea) .. ") -> cho server xu ly, retry vong sau")
        return false
    end

    SetStatus("Now in Sea 3")
    return true
end

RefreshSea()

local ConChoChisiti36 = {
    PlayerData = {},
    Backpack   = {},
}

local function RefreshPlayerData()
    local data = LocalPlayer:FindFirstChild("Data")
    if not data then return end
    for _, c in data:GetChildren() do
        pcall(function() ConChoChisiti36.PlayerData[c.Name] = c.Value end)
    end
end

-- ============================================================
-- THREAD IDENTITY
-- require(...) module cua game se ha identity cua thread hien tai
-- xuong muc script game -> sau do ghi vao CoreGui/gethui bi loi
-- "cannot access 'Instance' (lacking capability Plugin)".
-- Boc lai de luon tra identity ve muc cao sau khi require.
-- ============================================================
local _setidentity = setthreadidentity or setidentity or set_thread_identity
    or (syn and syn.set_thread_identity)
local _getidentity = getthreadidentity or getidentity or get_thread_identity
    or (syn and syn.get_thread_identity)

local function RaiseIdentity()
    if not _setidentity then return nil end
    local prev
    if _getidentity then
        local ok, v = pcall(_getidentity)
        if ok then prev = v end
    end
    pcall(_setidentity, 8)
    return prev
end

local function RestoreIdentity(prev)
    if not _setidentity then return end
    pcall(_setidentity, prev or 8)
end

-- ============================================================
-- INVENTORY (update moi): doc qua ItemReplicationService +
-- Inventory controller + ItemConfig thay cho CommF_ getInventory
-- (getInventory khong con tra Mirror Fractal sau update).
--   Backpack[<Display.Name>] = { Name=, Count=, Category=, ItemId= }
-- ============================================================
local InvModules = {
    Inventory   = nil,
    ItemConfig  = nil,
    ItemService = nil,
    KEYS        = nil,
    Ready       = false,
}

-- Tim node theo duong dan, khong index truc tiep de loi bao ro rang
-- thay vi treo hoac "attempt to index nil".
local function ResolvePath(root, path)
    local node = root
    for _, name in ipairs(path) do
        if typeof(node) ~= "Instance" then return nil, name end
        local child = node:FindFirstChild(name)
        if not child then return nil, name end
        node = child
    end
    return node
end

local _invLoadWarned = false
local _invTilesWarned = false

local function LoadInventoryModules()
    if InvModules.Ready then return true end

    local paths = {
        Inventory   = { "Controllers", "UI", "Inventory" },
        ItemConfig  = { "ItemConfig" },
        ItemService = { "ItemReplicationService" },
        KEYS        = { "ItemReplicationService", "KEYS" },
    }

    local nodes = {}
    for key, path in pairs(paths) do
        local node, missing = ResolvePath(ReplicatedStorage, path)
        if not node then
            if not _invLoadWarned then
                _invLoadWarned = true
                warn("[Inventory] Khong tim thay ReplicatedStorage."
                    .. table.concat(path, ".")
                    .. " (thieu '" .. tostring(missing) .. "')")
            end
            return false
        end
        nodes[key] = node
    end

    -- require module cua game co the doi identity khac nhau tuy
    -- executor. Thu lan luot 2 (script game) -> 8 -> giu nguyen.
    -- Dung `false` lam sentinel "khong doi identity": neu de nil trong
    -- table constructor thi ipairs se cat mat phan tu do.
    local candidates = _setidentity and {2, 8, false} or {false}
    local lastErr

    for _, ident in ipairs(candidates) do
        local prev = RaiseIdentity()
        if ident and _setidentity then pcall(_setidentity, ident) end
        local ok, err = pcall(function()
            InvModules.Inventory   = require(nodes.Inventory)
            InvModules.ItemConfig  = require(nodes.ItemConfig)
            InvModules.ItemService = require(nodes.ItemService)
            InvModules.KEYS        = require(nodes.KEYS)
        end)

        RestoreIdentity(prev)

        if ok and type(InvModules.Inventory) == "table"
            and type(InvModules.ItemService) == "table" then
            InvModules.Ready = true
            return true
        end

        lastErr = err
        InvModules.Inventory, InvModules.ItemConfig = nil, nil
        InvModules.ItemService, InvModules.KEYS = nil, nil
    end

    if not _invLoadWarned then
        _invLoadWarned = true
        warn("[Inventory] require that bai: " .. tostring(lastErr))
    end
    return false
end

local function InventoryModulesInitialized()
    if not InvModules.Ready then return false end
    local ok, res = pcall(function()
        return InvModules.Inventory:GetIfInitialized()
            and InvModules.ItemService.IsInitialized == true
    end)
    return ok and res == true
end

local function _RefreshInventoryInner()
    -- LoadInventoryModules da tu warn mot lan roi, khong warn lai o day
    -- vi main loop goi moi 1s -> spam console.
    if not LoadInventoryModules() then
        return
    end

    if not InventoryModulesInitialized() then
        return
    end

    local Inventory   = InvModules.Inventory
    local ItemConfig  = InvModules.ItemConfig
    local ItemService  = InvModules.ItemService
    local KEYS        = InvModules.KEYS

    -- So luong theo ItemId
    local amounts = {}
    local okQty, qtyList = pcall(function()
        return ItemService:GetItems(KEYS.QUANTITY)
    end)
    if okQty and type(qtyList) == "table" then
        for _, item in pairs(qtyList) do
            if type(item) == "table" and item.ItemId then
                amounts[item.ItemId] = (amounts[item.ItemId] or 0)
                    + (tonumber(item.Value) or 0)
            end
        end
    end

    local okTiles, tiles = pcall(function() return Inventory:GetTiles() end)
    if not okTiles or type(tiles) ~= "table" then
        -- Chi warn mot lan: main loop goi moi 1s.
        if not _invTilesWarned then
            _invTilesWarned = true
            warn("[Inventory] GetTiles that bai: " .. tostring(tiles))
        end
        return
    end
    _invTilesWarned = false

    local backpack, seen, total = {}, {}, 0

    for _, tile in pairs(tiles) do
        local id = type(tile) == "table" and tile.ItemId or nil

        if id and not seen[id] then
            seen[id] = true

            local okCfg, config = pcall(function()
                return ItemConfig.match(id):unwrap()
            end)

            if okCfg and type(config) == "table" and config.Display then
                local name = config.Display.Name
                    or (config.Index and config.Index.StorageKey)
                    or tostring(id)

                backpack[tostring(name)] = {
                    Name     = tostring(name),
                    Count    = amounts[id] or 1,
                    Category = config.Display.Category,
                    ItemId   = id,
                }
                total = total + 1
            end
        end
    end

    -- Chi ghi de khi doc duoc it nhat 1 item, tranh xoa trang cache
    -- khi inventory chua replicate xong.
    if total > 0 then
        ConChoChisiti36.Backpack = backpack
    end
end

-- Goi vao module cua game co the ha identity giua duong. Luon tra
-- identity ve muc cao sau khi doc xong, ke ca khi loi.
local function RefreshInventory()
    local prev = RaiseIdentity()
    local ok, err = pcall(_RefreshInventoryInner)
    RestoreIdentity(prev)
    if not ok then
        warn("[Inventory] RefreshInventory loi: " .. tostring(err))
    end
end

CommE.OnClientEvent:Connect(function(...)
    local t = {...}
    if type(t[1]) == "string" and t[1]:find("Item") then
        RefreshInventory()
    end
end)

RefreshPlayerData()
RefreshInventory()

local function IfTableHaveIndex(t)
    if type(t) ~= "table" then return false end
    for _ in t do return true end
end

local CachedServers, LastServersDataPulled

local function GetServers()
    if LastServersDataPulled
        and CachedServers
        and os.time() - LastServersDataPulled < 15
    then
        return CachedServers
    end

    local browser = ReplicatedStorage:FindFirstChild("__ServerBrowser")
    if not browser then
        warn("[ServerBrowser] __ServerBrowser missing")
        return nil
    end

    for i = 1, 100 do
        local ok, data = pcall(function()
            return browser:InvokeServer(i)
        end)

        if ok and IfTableHaveIndex(data) then
            CachedServers = data
            LastServersDataPulled = os.time()
            return data
        end

        task.wait()
    end

    return nil
end

local function Hop(Reason)
    print("[PullLever] Fallback Hop: " .. tostring(Reason))

    local Servers = GetServers()
    if not Servers then
        SetStatus("Fallback ServerBrowser empty")
        return false
    end

    local maxPlayers = tonumber(Config["Max Players"] or 11) or 11
    local avoidFull = Config["Avoid Full Server"] ~= false
    local List = {}

    for JobId, v in Servers do
        local players = tonumber(v and v.Count) or 0
        local notSame = tostring(JobId) ~= tostring(game.JobId)
        local notFull = (not avoidFull) or players <= maxPlayers

        if notSame and notFull then
            table.insert(List, {
                JobId = JobId,
                Players = players,
                Region = v and v.Region,
            })
        end
    end

    if #List == 0 then
        SetStatus("Fallback no usable server")
        return false
    end

    local data = List[math.random(1, #List)]
    local browser = ReplicatedStorage:FindFirstChild("__ServerBrowser")

    if not browser then
        return false
    end

    local ok, err = pcall(function()
        browser:InvokeServer("teleport", data.JobId)
    end)

    if not ok then
        warn("[ServerBrowser] Fallback teleport failed: " .. tostring(err))
        return false
    end

    return true
end

local JoinJobIdByServerBrowser

local function HttpRequest(opts)

    local req = request or http_request
        or (syn and syn.request)
        or (fluxus and fluxus.request)

    if type(req) ~= "function" then
        return false, "executor does not support request"
    end

    local lastErr
    for attempt = 1, 3 do
        local ok, res = pcall(function() return req(opts) end)
        if ok and type(res) == "table" then
            return true, res
        end
        lastErr = res
        warn("[MirageAPI] request attempt " .. tostring(attempt) .. " failed: " .. tostring(res))
        task.wait(2)
    end
    return false, lastErr
end

local function JsonDecodeSafe(body)
    if type(body) ~= "string" then return nil end
    local ok, data = pcall(function() return HttpService:JSONDecode(body) end)
    if ok and type(data) == "table" then
        return data
    end
    return nil
end

-- ============================================================
-- MIRAGE API (baorph): query key=mirage, envelope key=island
--
-- Vi du:
-- {
--   "api_url": "https://baorph.pythonanywhere.com/token",
--   "count": 29,
--   "items": [
--     "job id: <GUID>; type: mirage; player: 4; placeid: 100117331123089",
--     ...
--   ],
--   "key": "island",
--   "ok": true
-- }
--
-- QUAN TRONG:
-- API sap xep DU LIEU CU O TREN, MOI O DUOI.
-- Vi vay ExtractServerList() doc items TU CUOI LEN DAU.
-- list[1] = server moi nhat.
--
-- Query URL dung key=mirage, nhung payload co the tron nhieu type:
--   mirage / mysticisland / prehistoricisland
-- Nen loc CHINH XAC Type == "mirage" trong items.
-- ============================================================
local function NormalizeServerEntry(v)
    if type(v) == "string" then
        local jobId = v:match("[Jj][Oo][Bb]%s*[Ii][Dd]%s*:%s*([%x%-]+)")
        local serverType = v:match("[Tt][Yy][Pp][Ee]%s*:%s*([^;]+)")
        local players = tonumber(v:match("[Pp][Ll][Aa][Yy][Ee][Rr]%s*:%s*(%d+)")) or 0
        local placeId = tonumber(v:match("[Pp][Ll][Aa][Cc][Ee][Ii][Dd]%s*:%s*(%d+)"))

        if not jobId or jobId == "" then
            return nil
        end

        if serverType then
            serverType = tostring(serverType):match("^%s*(.-)%s*$")
        end

        return {
            JobId = jobId,
            PlaceId = placeId,
            Players = players,
            Type = serverType,
            Raw = v,
        }
    end

    -- Fallback object schema cu.
    if type(v) ~= "table" then
        return nil
    end

    local jobId =
        v.raw_job_id
        or v.job_id
        or v.jobid
        or v.JobId
        or v.id

    if not jobId or tostring(jobId) == "" then
        return nil
    end

    return {
        JobId = tostring(jobId),
        PlaceId = tonumber(v.place_id or v.placeid or v.PlaceId),
        Players = tonumber(v.players or v.player or v.Players) or 0,
        Type = tostring(v.type or v.Type or v.server_type or ""),
        Raw = v,
    }
end

local function ExtractServerList(data)
    local list = {}

    if type(data) ~= "table" then
        return list
    end

    if data.ok == false then
        warn("[MirageAPI] API returned ok=false")
        return list
    end

    local source = data.items or data.data or data.servers
    if type(source) ~= "table" then
        return list
    end

    -- API: tren = cu, duoi = moi.
    -- Doc nguoc de uu tien server moi nhat.
    for i = #source, 1, -1 do
        local one = NormalizeServerEntry(source[i])

        if one then
            local tp = tostring(one.Type or ""):lower()

            -- Payload key=mirage van co the chua mysticisland/prehistoricisland.
            -- Schema string hien tai: CHI lay type=mirage.
            -- Schema object cu khong co Type: van cho phep de backward-compatible.
            if type(one.Raw) == "string" then
                if tp == "mirage" then
                    list[#list + 1] = one
                end
            elseif tp == "" or tp == "mirage" then
                list[#list + 1] = one
            end
        end
    end

    return list
end

local LastMirageApiFetch = 0
local CachedMirageServers = nil
local CachedMiragePlaceId = nil

local function GetMirageServersFromAPI(forceRefresh)
    local cfg = getgenv().PullLeverConfig or {}
    local url = tostring(cfg["Mirage API"] or "")

    if url == "" then
        warn("[MirageAPI] Mirage API url rong -> bo qua")
        return {}, "url_empty"
    end

    local currentPlaceId = tonumber(game.PlaceId)

    if CachedMirageServers
        and CachedMiragePlaceId == currentPlaceId
        and os.time() - LastMirageApiFetch < 20 then
        return CachedMirageServers, "cache"
    end

    SetStatus("Fetching Mirage API...")

    local ok, res = HttpRequest({
        Url = url,
        Method = "GET",
        Headers = {
            ["Accept"]     = "application/json",
            ["User-Agent"] = "Roblox/WinInet",
        },
    })

    if not ok then
        warn("[MirageAPI] Request failed: " .. tostring(res))
        return {}, "request_failed"
    end

    local statusCode = tonumber(res.StatusCode or res.status_code or res.Status or 0)
    local body = res.Body or res.body or ""

    print("[MirageAPI] Status=" .. tostring(statusCode) .. " BodyLen=" .. tostring(#body))

    if statusCode ~= 0 and (statusCode < 200 or statusCode >= 300) then
        warn("[MirageAPI] Bad status: " .. tostring(statusCode))
        return {}, "http_" .. tostring(statusCode)
    end

    local data = JsonDecodeSafe(body)
    if not data then
        warn("[MirageAPI] JSON decode failed. Body head: " .. tostring(body):sub(1, 300))
        return {}, "json_decode_failed"
    end

    -- Luu y: URL query dang la key=mirage, nhung API envelope hien tai
    -- tra data.key = "island". Khong dung data.key de suy ra query selector.
    local responseKey = tostring(data.key or "")
    if responseKey ~= "" then
        print("[MirageAPI] Response envelope key=" .. responseKey)
    end

    local servers = ExtractServerList(data)

    if #servers > 0 then
        LastMirageApiFetch = os.time()
        CachedMiragePlaceId = currentPlaceId
        CachedMirageServers = servers
    end

    print(
        "[MirageAPI] Parsed " .. tostring(#servers)
        .. " server(s) | key=" .. tostring(data.key)
        .. " | bottom->top | newest first"
    )
    SetStatus("Mirage API servers: " .. tostring(#servers))

    if #servers <= 0 then
        return {}, "parsed_empty"
    end

    return servers, "ok"
end

JoinJobIdByServerBrowser = function(jobId)
    if not jobId or tostring(jobId) == "" then
        return false, "invalid_job"
    end

    jobId = tostring(jobId)

    if jobId == tostring(game.JobId) then
        return false, "same_job"
    end

    local browser = GetServerBrowser()
    if not browser then
        warn("[ServerBrowser] Khong tim thay __ServerBrowser")
        return false, "browser_missing"
    end

    -- "teleport" o day CHI la action name cua __ServerBrowser remote.
    -- Khong lien quan TeleportService.
    local ok, result = pcall(function()
        return browser:InvokeServer("teleport", jobId)
    end)

    if not ok then
        warn(
            "[ServerBrowser] Join JobId loi | "
            .. jobId
            .. " | "
            .. tostring(result)
        )
        return false, tostring(result)
    end

    print(
        "[ServerBrowser] SENT JobId="
        .. jobId
        .. " | result="
        .. tostring(result)
    )

    return true, result
end

-- Lay toi 30 server Mirage moi nhat theo thu tu API TU DUOI LEN TREN.
-- Moi thoi diem chi co 1 teleport pending; khong spam nhieu JobId lien tiep.
local MIRAGE_BATCH_SIZE = 5
local MIRAGE_JOB_DELAY = 2.0

local function HopMirageByAPI()
    local cfg = getgenv().PullLeverConfig or {}

    if cfg["Use Mirage API"] == false then
        return false, "disabled"
    end

    -- Neu server hien tai da co Mirage: TUYET DOI KHONG HOP.
    if FindMirageIsland() then
        return false, "mirage_present"
    end

    -- Chay lien tuc theo batch:
    -- fetch API -> 5 newest usable -> #1..#5 cach 2s
    -- -> het 5 thi fetch API moi ngay.
    while cfg["Use Mirage API"] ~= false do
        if FindMirageIsland() then
            return false, "mirage_present"
        end

        CachedMirageServers = nil
        CachedMiragePlaceId = nil
        LastMirageApiFetch = 0

        local servers, fetchReason = GetMirageServersFromAPI(true)

        if type(servers) ~= "table" or #servers <= 0 then
            SetStatus(
                "Mirage API empty | "
                .. tostring(fetchReason)
                .. " -> refetch"
            )
            task.wait(1)
            continue
        end

        -- API request co the mat thoi gian; check lai Mirage truoc khi join.
        if FindMirageIsland() then
            return false, "mirage_present"
        end

        local currentPlaceId = tonumber(game.PlaceId)
        local maxPlayers = tonumber(cfg["Max Players"] or 11) or 11
        local avoidFull = cfg["Avoid Full Server"] ~= false

        local candidates = {}
        local stats = {
            total = #servers,
            full = 0,
            wrongPlace = 0,
            sameJob = 0,
            visited = 0,
        }

        -- ExtractServerList da reverse:
        -- index 1 = item DUOI CUNG API = MOI NHAT.
        for _, server in ipairs(servers) do
            local jobId = tostring(server.JobId or "")
            local placeId = tonumber(server.PlaceId)
            local players = tonumber(server.Players) or 0

            local samePlace =
                (placeId == nil)
                or (placeId == currentPlaceId)

            local notSameJob =
                jobId ~= ""
                and jobId ~= tostring(game.JobId)

            local notFull =
                (not avoidFull)
                or players <= maxPlayers

            local notVisited =
                not JoinedMirageJobs[jobId]

            if not samePlace then stats.wrongPlace += 1 end
            if not notSameJob then stats.sameJob += 1 end
            if not notFull then stats.full += 1 end
            if not notVisited then stats.visited += 1 end

            if samePlace
                and notSameJob
                and notFull
                and notVisited
            then
                candidates[#candidates + 1] = server

                if #candidates >= MIRAGE_BATCH_SIZE then
                    break
                end
            end
        end

        print(
            "[ServerBrowser][MirageAPI]"
            .. " total=" .. tostring(stats.total)
            .. " newestUsable=" .. tostring(#candidates)
            .. " full=" .. tostring(stats.full)
            .. " visited=" .. tostring(stats.visited)
            .. " wrongPlace=" .. tostring(stats.wrongPlace)
        )

        if #candidates == 0 then
            -- API co data nhung tat ca candidate hien tai da thu/khong usable.
            -- Nghi ngan roi fetch lai API; KHONG random fallback server.
            SetStatus(
                "Mirage API no new usable -> refetch"
                .. " | full=" .. tostring(stats.full)
                .. " visited=" .. tostring(stats.visited)
            )
            task.wait(1)
            continue
        end

        -- ====================================================
        -- DUNG 5 NEWEST USABLE:
        -- #1 -> 2s -> #2 -> 2s -> ... -> #5.
        -- Join CHI qua __ServerBrowser.
        -- ====================================================
        for i, server in ipairs(candidates) do
            if FindMirageIsland() then
                SetStatus("Mirage vua replicate -> dung ServerBrowser")
                return false, "mirage_present"
            end

            local jobId = tostring(server.JobId or "")

            if jobId ~= "" then
                SetStatus(
                    "ServerBrowser "
                    .. tostring(i)
                    .. "/"
                    .. tostring(#candidates)
                    .. " | Players="
                    .. tostring(server.Players)
                    .. " | "
                    .. jobId:sub(1, 8)
                    .. " | next=2s"
                )

                print(
                    "[ServerBrowser] TRY "
                    .. tostring(i)
                    .. "/"
                    .. tostring(#candidates)
                    .. " | JobId="
                    .. jobId
                    .. " | Players="
                    .. tostring(server.Players)
                    .. " | Type="
                    .. tostring(server.Type or "?")
                )

                local ok, result =
                    JoinJobIdByServerBrowser(jobId)

                -- Neu Invoke loi thi bo qua JobId nay.
                -- Neu Invoke accepted nhung client chua roi session sau 2s,
                -- script se tiep tuc JobId tiep theo dung yeu cau.
                if not ok then
                    warn(
                        "[ServerBrowser] FAILED "
                        .. jobId
                        .. " | "
                        .. tostring(result)
                    )
                end

                task.wait(MIRAGE_JOB_DELAY)

                -- Neu code con chay o session nay thi coi JobId vua thu la da dung.
                JoinedMirageJobs[jobId] = true
            end
        end

        -- Het 5 -> force fetch 5 newest usable MOI ngay trong ham nay.
        CachedMirageServers = nil
        CachedMiragePlaceId = nil
        LastMirageApiFetch = 0

        SetStatus(
            "Het "
            .. tostring(#candidates)
            .. " ServerBrowser JobId -> fetch 5 moi"
        )

        task.wait(0.15)
    end

    return false, "disabled"
end

local function ConvertTo(Type, Data)
    if typeof(Data) ~= "table" then
        return Type.new(Data.x, Data.y, Data.z)
    end
    return Type.new(Data.x, Data.y, Data.z)
end

local function CaculateDistance(Origin, Destination)
    RefreshCharacter()

    if not HumanoidRootPart or not HumanoidRootPart.Parent then
        return math.huge
    end

    Origin = Origin or HumanoidRootPart.CFrame
    Destination = Destination or HumanoidRootPart.CFrame

    local a =
        typeof(Origin) == "CFrame" and Origin.Position
        or (typeof(Origin) == "Vector3" and Origin or ConvertTo(Vector3, Origin))

    local b =
        typeof(Destination) == "CFrame" and Destination.Position
        or (typeof(Destination) == "Vector3" and Destination or ConvertTo(Vector3, Destination))

    return (a - b).Magnitude
end

-- ============================================================
-- TWEEN MODULE - KATA COORDINATOR PROXY CORE
-- ============================================================
-- Fixed speed = 150, exactly like the Kata reference.
-- No external speed override.
--
-- Proxy path:
--   TweenService -> anchored proxy
--   PreSimulation -> HumanoidRootPart follows proxy
--   BodyVelocity + AssemblyLinearVelocity
--   normal rubber-band does not pull proxy backwards
--   AntiMover/Teleporting pauses movement and resumes from server position
--   travel -> settle -> release
-- ============================================================

local TWEEN_SPEED = 150

local TWEEN_CFG = {
    SettleMin       = 1.8,
    QuietNeed       = 1.25,
    ReleaseConfirm  = 2.5,
    MaxReleaseRetry = 4,
    PushSnap        = 28,
    SettlePull      = 4,
    ReleasePull     = 6,
    StuckSec        = 8,
    AlreadyThere    = 6,
    StreamTimeout   = 5,
    SnapLogGap      = 5,
}

local TweenMovementId = 0
local CurrentTweenMovement = nil

pcall(function()
    local stale =
        workspace:FindFirstChild(
            "PullKataMoveProxy"
        )

    if stale then
        stale:Destroy()
    end

    local root0 =
        LocalPlayer.Character
        and LocalPlayer.Character:FindFirstChild(
            "HumanoidRootPart"
        )

    if root0 then
        local old =
            root0:FindFirstChild(
                "PullKataMoveStabilizer"
            )

        if old then
            old:Destroy()
        end
    end
end)

local function TweenSetVelocity(
    root,
    velocity
)
    if not root
        or not root.Parent
    then
        return
    end

    pcall(function()
        root.AssemblyLinearVelocity =
            velocity

        root.AssemblyAngularVelocity =
            Vector3.zero
    end)

    pcall(function()
        root.Velocity = velocity
        root.RotVelocity = Vector3.zero
    end)
end

local function MovementLocked(char)
    if not char then
        return true
    end

    if char:FindFirstChild(
        "AntiMover"
    ) then
        return true
    end

    local ok, tagged =
        pcall(function()
            return CollectionService:HasTag(
                char,
                "Teleporting"
            )
        end)

    return ok
        and tagged == true
end

local function RequestTweenStreaming(
    position
)
    task.spawn(function()
        pcall(function()
            LocalPlayer:RequestStreamAroundAsync(
                position,
                TWEEN_CFG.StreamTimeout
            )
        end)
    end)
end

local function RestoreTweenNoclip(
    data,
    force
)
    if not data
        or not data.noclipParts
    then
        return
    end

    local now = os.clock()

    for part, info in pairs(
        data.noclipParts
    ) do
        if not part
            or not part.Parent
        then
            data.noclipParts[part] =
                nil

        elseif force
            or now - info.seenAt
                > 0.28
        then
            pcall(function()
                part.CanCollide =
                    info.canCollide
            end)

            data.noclipParts[part] =
                nil
        end
    end
end

local function ApplyTweenNoclip(
    data,
    fromPosition,
    toPosition
)
    if not data
        or not data.rayParams
        or not data.root
        or not data.root.Parent
    then
        return
    end

    local motion =
        toPosition - fromPosition

    local distance =
        motion.Magnitude

    local now =
        os.clock()

    if distance <= 0.02 then
        RestoreTweenNoclip(
            data,
            false
        )
        return
    end

    local direction =
        motion.Unit

    local up =
        Vector3.new(0, 1, 0)

    local right =
        direction:Cross(up)

    if right.Magnitude < 0.05 then
        right =
            Vector3.new(1, 0, 0)
    else
        right =
            right.Unit
    end

    local offsets = {
        Vector3.zero,
        up * 1.55,
        up * -1.05,
        right * 1.75,
        right * -1.75,
    }

    local castVector =
        direction
        * (distance + 4.5)

    for _, offset in ipairs(
        offsets
    ) do
        for _ = 1, 3 do
            local result =
                workspace:Raycast(
                    fromPosition + offset,
                    castVector,
                    data.rayParams
                )

            if not result then
                break
            end

            local part =
                result.Instance

            if not part
                or not part:IsA("BasePart")
                or not part.Anchored
                or not part.CanCollide
                or part:IsDescendantOf(
                    data.character
                )
            then
                break
            end

            local normalY =
                math.abs(
                    result.Normal.Y
                )

            if normalY >= 0.72
                and direction.Y <= 0.35
            then
                break
            end

            local info =
                data.noclipParts[part]

            if not info then
                info = {
                    canCollide =
                        part.CanCollide,

                    seenAt = now,
                }

                data.noclipParts[part] =
                    info
            else
                info.seenAt =
                    now
            end

            part.CanCollide =
                false
        end
    end

    RestoreTweenNoclip(
        data,
        false
    )
end

local function CleanupTweenMovement(
    data
)
    if not data
        or data.cleaned
    then
        return
    end

    data.cleaned = true

    if data.tween then
        pcall(function()
            data.tween:Cancel()
        end)
    end

    if data.stepConnection then
        data.stepConnection:Disconnect()
    end

    if data.characterConnection then
        data.characterConnection:Disconnect()
    end

    RestoreTweenNoclip(
        data,
        true
    )

    if data.humanoid
        and data.humanoid.Parent
    then
        pcall(function()
            data.humanoid.AutoRotate =
                data.autoRotate
        end)
    end

    for _, instance in ipairs(
        data.instances or {}
    ) do
        if instance
            and instance.Parent
        then
            instance:Destroy()
        end
    end

    if data.root
        and data.root.Parent
    then
        TweenSetVelocity(
            data.root,
            Vector3.zero
        )

        if data.humanoid
            and data.humanoid.Parent
            and data.humanoid.Health > 0
        then
            pcall(function()
                data.humanoid:ChangeState(
                    Enum.HumanoidStateType.GettingUp
                )
            end)
        end
    end
end

local function ForceStopTweenMovement()
    TweenMovementId += 1

    local data =
        CurrentTweenMovement

    CurrentTweenMovement =
        nil

    if data
        and not data.outcome
    then
        data.outcome =
            "cancelled"
    end

    CleanupTweenMovement(
        data
    )
end

local function FinishTweenMovement(
    id,
    data
)
    if id ~= TweenMovementId
        or CurrentTweenMovement ~= data
        or data.finishing
    then
        return
    end

    data.finishing =
        true

    if not data.outcome then
        data.outcome =
            "arrived"
    end

    CurrentTweenMovement =
        nil

    CleanupTweenMovement(
        data
    )
end

local function LaunchTweenProxy(
    data
)
    local remaining =
        (
            data.proxy.Position
            - data.target.Position
        ).Magnitude

    if remaining <= 1 then
        return
    end

    if data.tween then
        pcall(function()
            data.tween:Cancel()
        end)
    end

    local tw =
        TweenService:Create(
            data.proxy,

            TweenInfo.new(
                math.max(
                    remaining
                        / TWEEN_SPEED,
                    0.05
                ),

                Enum.EasingStyle.Linear,
                Enum.EasingDirection.Out
            ),

            {
                CFrame =
                    data.target
            }
        )

    data.tween = tw
    tw:Play()
end

local function StartTweenSession(
    targetCFrame
)
    ForceStopTweenMovement()
    RefreshCharacter()

    local character =
        LocalPlayer.Character

    local root =
        character
        and character:FindFirstChild(
            "HumanoidRootPart"
        )

    local humanoid =
        character
        and character:FindFirstChildOfClass(
            "Humanoid"
        )

    if not root
        or not humanoid
        or humanoid.Health <= 0
        or typeof(targetCFrame)
            ~= "CFrame"
    then
        return nil
    end

    TweenMovementId += 1

    local id =
        TweenMovementId

    local target =
        targetCFrame

    local distance =
        (
            root.Position
            - target.Position
        ).Magnitude

    if distance
        <= TWEEN_CFG.AlreadyThere
    then
        return true
    end

    RequestTweenStreaming(
        target.Position
    )

    local proxy =
        Instance.new("Part")

    proxy.Name =
        "PullKataMoveProxy"

    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanQuery = false
    proxy.CanTouch = false
    proxy.Transparency = 1
    proxy.Size =
        Vector3.new(1, 1, 1)

    proxy.CFrame =
        root.CFrame

    proxy.Parent =
        workspace

    local stabilizer =
        Instance.new(
            "BodyVelocity"
        )

    stabilizer.Name =
        "PullKataMoveStabilizer"

    stabilizer.MaxForce =
        Vector3.new(
            1e9,
            1e9,
            1e9
        )

    stabilizer.P =
        1000000

    stabilizer.Velocity =
        Vector3.zero

    stabilizer.Parent =
        root

    local rayParams =
        RaycastParams.new()

    rayParams.FilterType =
        Enum.RaycastFilterType.Exclude

    rayParams.FilterDescendantsInstances = {
        character,
        proxy,
    }

    rayParams.IgnoreWater =
        true

    pcall(function()
        rayParams.RespectCanCollide =
            true
    end)

    local rotation =
        target
        - target.Position

    local now =
        os.clock()

    local data = {
        id = id,

        character = character,
        root = root,
        humanoid = humanoid,

        proxy = proxy,
        stabilizer = stabilizer,
        rayParams = rayParams,

        target = target,
        rotation = rotation,

        t0 = now,
        distance = distance,

        phase = "travel",
        phaseStartedAt = now,
        lastCorrectionAt = now,

        lastApplied =
            root.Position,

        noclipParts = {},

        corrections = 0,
        releaseRetries = 0,
        snaps = 0,
        maxDev = 0,

        bestRemaining =
            distance,

        lastNetAt =
            now,

        lastSnapLogAt =
            0,

        lastRemaining =
            distance,

        lockedSeen =
            false,

        autoRotate =
            humanoid.AutoRotate,

        instances = {
            proxy,
            stabilizer,
        },
    }

    CurrentTweenMovement =
        data

    humanoid.AutoRotate =
        false

    humanoid.Sit =
        false

    LaunchTweenProxy(
        data
    )

    print(string.format(
        "[PullTween] START dist=%.0f speed=%d",
        distance,
        TWEEN_SPEED
    ))

    data.characterConnection =
        LocalPlayer.CharacterAdded:Connect(
            function()
                if id
                        == TweenMovementId
                    and CurrentTweenMovement
                        == data
                then
                    ForceStopTweenMovement()
                end
            end
        )

    data.stepConnection =
        RunService.PreSimulation:Connect(
            function(dt)
                if id
                        ~= TweenMovementId
                    or CurrentTweenMovement
                        ~= data
                    or data.cleaned
                then
                    return
                end

                if not root
                    or not root.Parent
                    or not humanoid
                    or humanoid.Health <= 0
                    or not data.proxy
                    or not data.proxy.Parent
                then
                    ForceStopTweenMovement()
                    return
                end

                dt =
                    math.clamp(
                        dt or 0.016,
                        0.001,
                        0.1
                    )

                local frameNow =
                    os.clock()

                humanoid.Sit =
                    false

                -- Same as Kata Coordinator:
                -- while AntiMover/Teleporting owns the character, stop writing
                -- movement but DO NOT zero the current velocity/stabilizer.
                -- Zeroing here can make the player fall during a brief lock.
                if MovementLocked(
                    character
                ) then
                    if not data.lockedSeen then
                        data.lockedSeen =
                            true

                        if data.tween then
                            pcall(function()
                                data.tween:Cancel()
                            end)
                        end
                    end

                    return
                end

                -- Resume after the game owns a teleport.
                if data.lockedSeen then
                    data.lockedSeen =
                        false

                    local newPos =
                        root.Position

                    data.proxy.CFrame =
                        CFrame.new(newPos)
                        * data.rotation

                    data.lastApplied =
                        newPos

                    data.bestRemaining =
                        (
                            newPos
                            - data.target.Position
                        ).Magnitude

                    data.lastNetAt =
                        frameNow

                    LaunchTweenProxy(
                        data
                    )
                end

                local serverPos =
                    root.Position

                local proxyPos =
                    data.proxy.Position

                -- Critical fix: real proxy remaining distance.
                local remaining =
                    (
                        proxyPos
                        - data.target.Position
                    ).Magnitude

                local push =
                    (
                        serverPos
                        - data.lastApplied
                    ).Magnitude

                data.maxDev =
                    math.max(
                        data.maxDev,
                        push
                    )

                if push
                    > TWEEN_CFG.PushSnap
                then
                    data.snaps += 1

                    if frameNow
                        - data.lastSnapLogAt
                        >= TWEEN_CFG.SnapLogGap
                    then
                        data.lastSnapLogAt =
                            frameNow

                        print(string.format(
                            "[PullTween] WARN server pull %.0f studs (snap %d) - keep proxy",
                            push,
                            data.snaps
                        ))
                    end
                end

                ApplyTweenNoclip(
                    data,
                    serverPos,
                    proxyPos
                )

                local velocity =
                    Vector3.zero

                if dt > 0 then
                    velocity =
                        (
                            proxyPos
                            - data.lastApplied
                        ) / dt

                    local maxVelocity =
                        TWEEN_SPEED * 1.03

                    if velocity.Magnitude
                        > maxVelocity
                    then
                        velocity =
                            velocity.Unit
                            * maxVelocity
                    end
                end

                if stabilizer
                    and stabilizer.Parent
                then
                    stabilizer.Velocity =
                        data.phase
                            == "travel"
                        and velocity
                        or Vector3.zero
                end

                root.CFrame =
                    CFrame.new(
                        proxyPos
                    )
                    * data.rotation

                TweenSetVelocity(
                    root,
                    velocity
                )

                data.lastApplied =
                    proxyPos

                data.lastRemaining =
                    remaining

                local srvOff =
                    (
                        serverPos
                        - data.target.Position
                    ).Magnitude

                local quietFor =
                    frameNow
                    - data.lastCorrectionAt

                local settleNeed =
                    math.min(
                        TWEEN_CFG.SettleMin
                            + data.releaseRetries
                                * 1.25,
                        7
                    )

                local quietNeed =
                    math.min(
                        TWEEN_CFG.QuietNeed
                            + data.releaseRetries
                                * 1.1,
                        6
                    )

                if data.phase
                    == "travel"
                then
                    if remaining <= 1.5 then
                        data.phase =
                            "settle"

                        data.phaseStartedAt =
                            frameNow

                        data.lastCorrectionAt =
                            frameNow

                        if data.tween then
                            pcall(function()
                                data.tween:Cancel()
                            end)
                        end

                        data.proxy.CFrame =
                            data.target

                        TweenSetVelocity(
                            root,
                            Vector3.zero
                        )
                    else
                        if push
                                > TWEEN_CFG.PushSnap
                            and frameNow
                                - data.lastCorrectionAt
                                > 0.5
                        then
                            data.corrections += 1

                            data.lastCorrectionAt =
                                frameNow
                        end

                        if remaining
                            < data.bestRemaining
                                - 3
                        then
                            data.bestRemaining =
                                remaining

                            data.lastNetAt =
                                frameNow

                        elseif frameNow
                            - data.lastNetAt
                            > TWEEN_CFG.StuckSec
                        then
                            data.outcome =
                                "stuck"

                            FinishTweenMovement(
                                id,
                                data
                            )

                            return
                        end
                    end

                elseif data.phase
                    == "settle"
                then
                    root.CFrame =
                        data.target

                    TweenSetVelocity(
                        root,
                        Vector3.zero
                    )

                    if srvOff
                        > TWEEN_CFG.SettlePull
                    then
                        data.lastCorrectionAt =
                            frameNow
                    end

                    if quietFor
                            >= quietNeed
                        and frameNow
                            - data.phaseStartedAt
                            >= settleNeed
                    then
                        data.phase =
                            "release"

                        data.phaseStartedAt =
                            frameNow
                    end

                elseif data.phase
                    == "release"
                then
                    if srvOff
                        > TWEEN_CFG.ReleasePull
                    then
                        data.releaseRetries += 1

                        if data.releaseRetries
                            > TWEEN_CFG.MaxReleaseRetry
                        then
                            data.outcome =
                                "release-fail"

                            FinishTweenMovement(
                                id,
                                data
                            )

                            return
                        end

                        data.phase =
                            "settle"

                        data.phaseStartedAt =
                            frameNow

                        data.lastCorrectionAt =
                            frameNow

                        data.proxy.CFrame =
                            data.target

                        root.CFrame =
                            data.target

                    elseif frameNow
                        - data.phaseStartedAt
                        >= TWEEN_CFG.ReleaseConfirm
                    then
                        FinishTweenMovement(
                            id,
                            data
                        )

                        return
                    end
                end
            end
        )

    return data
end

local function CancelTween()
    ForceStopTweenMovement()
end

local function ConvertTweenTarget(
    value
)
    if not value then
        return nil
    end

    if typeof(value)
        == "CFrame"
    then
        return value
    end

    if typeof(value)
        == "Vector3"
    then
        return CFrame.new(
            value
        )
    end

    if typeof(value)
        ~= "Instance"
    then
        return nil
    end

    if value:IsA(
        "BasePart"
    ) then
        return value.CFrame
    end

    if value:IsA(
        "Model"
    ) then
        local ok, cf =
            pcall(function()
                return value:GetPivot()
            end)

        if ok then
            return cf
        end
    end

    if value:IsA(
        "CFrameValue"
    ) then
        return value.Value
    end

    if value:IsA(
        "Vector3Value"
    ) then
        return CFrame.new(
            value.Value
        )
    end

    return nil
end

local function Tween(
    targetCFrame,
    targetObject
)
    if targetCFrame == false then
        CancelTween()
        return false
    end

    local target =
        ConvertTweenTarget(
            targetCFrame
        )

    if not target then
        return false
    end

    RefreshCharacter()

    local root =
        HumanoidRootPart

    if targetObject ~= nil
        and targetObject ~= root
    then
        return false
    end

    local active =
        CurrentTweenMovement

    -- Repeated Mirage/main-loop calls do not restart the same movement.
    if active
        and not active.cleaned
        and (
            active.target.Position
            - target.Position
        ).Magnitude <= 3
    then
        return false
    end

    return StartTweenSession(
        target
    ) ~= nil
end

local function IsTweening()
    return CurrentTweenMovement ~= nil
        and not CurrentTweenMovement.cleaned
end

local MirageHoldTarget =
    nil

function TweenTo(Position)
    MirageHoldTarget =
        nil

    if Position == false then
        CancelTween()
        return
    end

    if not Position then
        return
    end

    Position =
        typeof(Position)
            ~= "CFrame"
        and ConvertTo(
            CFrame,
            Position
        )
        or Position

    if typeof(Position)
        == "CFrame"
    then
        local p =
            Position.Position

        Position =
            CFrame.new(
                p.X,
                math.max(
                    p.Y,
                    5
                ),
                p.Z
            )
    end

    Tween(
        Position
    )
end

local MIRAGE_TWEEN_SPEED =
    TWEEN_SPEED

local MIRAGE_SNAP_DISTANCE =
    6

local MirageMovement = {}

function MirageMovement.cancel()
    MirageHoldTarget =
        nil

    CancelTween()
end

task.spawn(function()
    while task.wait(0.3) do
        local target =
            MirageHoldTarget

        if target then
            RefreshCharacter()

            local root =
                HumanoidRootPart

            if root
                and root.Parent
                and (
                    root.Position
                    - target.Position
                ).Magnitude
                    > MIRAGE_SNAP_DISTANCE
            then
                local active =
                    CurrentTweenMovement

                if not active
                    or active.cleaned
                    or (
                        active.target.Position
                        - target.Position
                    ).Magnitude > 3
                then
                    pcall(
                        Tween,
                        target
                    )
                end
            end
        end
    end
end)

function MirageMovement.moveTo(
    targetCFrame
)
    RefreshCharacter()

    local root =
        HumanoidRootPart

    local hum =
        Humanoid

    if not root
        or not root.Parent
        or not hum
        or hum.Health <= 0
        or typeof(targetCFrame)
            ~= "CFrame"
    then
        MirageMovement.cancel()
        return false
    end

    MirageHoldTarget =
        targetCFrame

    local dist =
        (
            root.Position
            - targetCFrame.Position
        ).Magnitude

    if dist
        <= MIRAGE_SNAP_DISTANCE
    then
        return true
    end

    local active =
        CurrentTweenMovement

    if not active
        or active.cleaned
        or (
            active.target.Position
            - targetCFrame.Position
        ).Magnitude > 3
    then
        Tween(
            targetCFrame
        )
    end

    return false
end

local function TweenToMirage(
    targetCFrame
)
    return MirageMovement.moveTo(
        targetCFrame
    )
end

function GetBlueGear()
    local mi = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MysticIsland")
    if not mi then return nil end
    for _, v in mi:GetDescendants() do
        if v:IsA("MeshPart") and v.MeshId == "rbxassetid://10153114969" and v.Transparency ~= 1 then
            return v.CFrame
        end
    end
    return nil
end

local function HasMirrorFractal()
    return ConChoChisiti36.Backpack["Mirror Fractal"] ~= nil
end
local function HasValkyrieHelm()
    return ConChoChisiti36.Backpack["Valkyrie Helm"] ~= nil
end
local function IsTempleDoorOpened()
    local ok, v = pcall(function() return CommF_:InvokeServer("CheckTempleDoor") end)
    return ok and v == true
end

-- ============================================================
-- COMPLETED PULL MARKER
-- Khi CheckTempleDoor == true:
--   <PlayerName>.txt = Completed-pull
-- ============================================================
local function WriteCompletedPull()
    local outputFile = tostring(LocalPlayer.Name) .. ".txt"
    local content = "Completed-pull"

    if type(writefile) ~= "function" then
        warn("[PullLever] writefile unavailable -> cannot create " .. outputFile)
        return false
    end

    local ok, err = pcall(function()
        writefile(outputFile, content)
    end)

    if not ok then
        warn("[PullLever] Completed-pull write failed: " .. tostring(err))
        return false
    end

    local verified = true

    if type(isfile) == "function" then
        local vok, exists = pcall(isfile, outputFile)
        if vok and exists ~= true then
            verified = false
        end
    end

    if verified and type(readfile) == "function" then
        local rok, body = pcall(readfile, outputFile)
        if rok and tostring(body or "") ~= content then
            verified = false
        end
    end

    if verified then
        print(
            "[PullLever] CREATED "
            .. outputFile
            .. " = "
            .. content
        )
        return true
    end

    warn("[PullLever] Completed-pull verify failed: " .. outputFile)
    return false
end
local function IsCurrentRaceV3()
    local ok, v = pcall(function()
        return CommF_:InvokeServer("Wenlocktoad", "3")
    end)
    return ok and v == -2
end
local function GetRaceV4Progress()
    local ok, value = pcall(function()
        return CommF_:InvokeServer(
            "RaceV4Progress",
            "Check"
        )
    end)

    if not ok then
        return nil
    end

    return tonumber(value) or value
end

local function IsRaceV4ProgressReady()
    return GetRaceV4Progress() == 4
end

-- Wait for a normal proxy tween to physically reach its target.
local function WaitArrive(target, timeout, tolerance)
    tolerance = tolerance or 12

    local startDistance =
        CaculateDistance(target)

    if timeout == nil then
        timeout = math.max(
            12,
            (startDistance / TWEEN_SPEED) + 12
        )
    end

    local deadline =
        os.clock() + timeout

    while os.clock() < deadline do
        local distance =
            CaculateDistance(target)

        if distance <= tolerance then
            return true
        end

        -- Do not sit in free-fall if movement died unexpectedly.
        if not IsTweening()
            and distance > tolerance
        then
            return false
        end

        task.wait(0.15)
    end

    return CaculateDistance(target)
        <= tolerance
end

-- Working V4 reference:
--   Check == 1 -> Check + Begin
--   Check == 2 -> Teleport from Great Tree gate until server puts us in Temple
--   other intermediate state -> Check + Continue
--   Check == 4 -> ready for Mirage
--
-- IMPORTANT:
-- Do NOT manually tween from Great Tree to the Temple coordinate.
-- Do NOT call TeleportBack here.
-- Main RaceV4 NPC/gate position + 10 studs above the NPC.
local RACEV4_NPC =
    CFrame.new(
        3028,
        2281,
        -7325
    )

local RACEV4_GATE =
    RACEV4_NPC
    * CFrame.new(
        0,
        10,
        0
    )

local RACEV4_TEMPLE_ANCHOR =
    CFrame.new(
        28286.35546875,
        14896.5078125,
        102.62469482422
    )

local function IsInsideRaceV4Temple()
    RefreshCharacter()

    local root =
        HumanoidRootPart

    if not root
        or not root.Parent
    then
        return false
    end

    return (
        root.Position
        - RACEV4_TEMPLE_ANCHOR.Position
    ).Magnitude <= 120
end

local function DoRaceV4Progress()
    local progress =
        GetRaceV4Progress()

    SetStatus(
        "Temple RaceV4 Check: "
        .. tostring(progress)
    )

    if progress == 4 then
        return true
    end

    -- Same first stage as the old working V4 script.
    if progress == 1 then
        SetStatus(
            "Temple Check=1 -> Begin"
        )

        pcall(function()
            CommF_:InvokeServer(
                "RaceV4Progress",
                "Check"
            )
        end)

        task.wait(0.25)

        pcall(function()
            CommF_:InvokeServer(
                "RaceV4Progress",
                "Begin"
            )
        end)

        task.wait(0.75)

        return false
    end

    -- This is the state shown in the user's screenshot.
    -- The correct action is to reach the Great Tree gate and let
    -- RaceV4Progress.Teleport perform the REAL server transition.
    if progress == 2 then
        if IsInsideRaceV4Temple() then
            CancelTween()
            SetStatus(
                "Temple Check=2 -> inside Temple"
            )
            return false
        end

        local gateDistance =
            CaculateDistance(
                RACEV4_GATE
            )

        if gateDistance > 12 then
            SetStatus(
                "Temple Check=2 -> tween gate"
                .. " | dist="
                .. tostring(
                    math.floor(
                        gateDistance
                    )
                )
            )

            TweenTo(
                RACEV4_GATE
            )

            local arrived =
                WaitArrive(
                    RACEV4_GATE,
                    nil,
                    10
                )

            if not arrived then
                SetStatus(
                    "Temple Check=2 -> gate retry"
                )
                return false
            end
        end

        -- We are at the gate. Release client movement before asking
        -- the server to perform the real Temple teleport.
        CancelTween()

        SetStatus(
            "Temple Check=2 -> Teleport"
        )

        local deadline =
            os.clock() + 12

        while os.clock() < deadline do
            if IsInsideRaceV4Temple() then
                SetStatus(
                    "Temple entered successfully"
                )
                return false
            end

            pcall(function()
                CommF_:InvokeServer(
                    "RaceV4Progress",
                    "Teleport"
                )
            end)

            -- Give the server time to apply the real teleport.
            task.wait(0.45)

            if IsInsideRaceV4Temple() then
                SetStatus(
                    "Temple entered successfully"
                )
                return false
            end
        end

        SetStatus(
            "Temple Check=2 -> Teleport retry"
        )

        return false
    end

    -- Old working V4 source uses Continue for the stage after Check=2.
    -- Most importantly, there is NO TeleportBack before Continue.
    SetStatus(
        "Temple Check="
        .. tostring(progress)
        .. " -> Continue"
    )

    pcall(function()
        CommF_:InvokeServer(
            "RaceV4Progress",
            "Check"
        )
    end)

    task.wait(1)

    pcall(function()
        CommF_:InvokeServer(
            "RaceV4Progress",
            "Continue"
        )
    end)

    -- Poll briefly so UI/main loop can see 4 as soon as server updates.
    local deadline =
        os.clock() + 4

    while os.clock() < deadline do
        local nowProgress =
            GetRaceV4Progress()

        if nowProgress == 4 then
            SetStatus(
                "RaceV4 Check=4 -> READY"
            )
            return true
        end

        task.wait(0.35)
    end

    return false
end

local function DoMirageBlueGear()
    local mirage = FindMirageIsland()

    -- Replication settle:
    -- tranh vua vao server, UI/Map sap replicate ma da gui API teleport mat.
    if not mirage then
        for _ = 1, 10 do
            task.wait(0.1)
            mirage = FindMirageIsland()
            if mirage then
                break
            end
        end
    end

    if not mirage then
        MirageMovement.cancel()

        if Config["Hop Mirage"] then
            SetStatus("Khong co Mirage -> Hop Mirage API")

            local apiStarted, apiReason =
                HopMirageByAPI()

            -- Neu API guard phat hien Mirage vua replicate:
            -- KHONG fallback server hop; main loop se tween ngay tick tiep.
            if apiReason == "mirage_present" then
                SetStatus("Mirage vua spawn/replicate -> GIU SERVER")
                return
            end

            if not apiStarted and apiReason ~= "mirage_present" then
                SetStatus(
                    "Mirage API stopped | "
                    .. tostring(apiReason)
                )
            end
        else
            SetStatus("Khong co Mirage (Hop Mirage = false)")
        end

        return
    end

    -- ========================================================
    -- CO MIRAGE = TUYET DOI KHONG HOP SERVER.
    -- Luon di ra Mirage truoc.
    -- ========================================================
    local blue = GetBlueGear()

    if blue then
        SetStatus("Mirage YES + Blue Gear -> Tween")
        TweenToMirage(blue)
        return
    end

    local top =
        mirage:GetModelCFrame()
        + Vector3.new(0, 300, 0)

    SetStatus(
        "Mirage YES -> Tween ra island"
        .. " | speed="
        .. tostring(MIRAGE_TWEEN_SPEED)
    )
    TweenToMirage(top)

    if CaculateDistance(top) >= 20 then
        return
    end

    -- Da o tren Mirage.
    -- Gio sai thi DUNG TAI MIRAGE cho den dung gio, KHONG hop.
    local hour = math.floor(Lighting.ClockTime)

    if not (hour >= 12 or hour < 5) then
        SetStatus(
            "Da o Mirage -> doi dung gio | Clock="
            .. tostring(math.floor(Lighting.ClockTime))
        )
        return
    end

    -- Dung gio: quay camera ve moon + activate race ability.
    SetStatus("Mirage OK -> ActivateAbility")

    pcall(function()
        LocalPlayer.CameraMaxZoomDistance = 0.5
        LocalPlayer.CameraMaxZoomDistance = 200

        workspace.CurrentCamera.CFrame =
            CFrame.new(
                workspace.CurrentCamera.CFrame.Position,
                Lighting:GetMoonDirection()
                    + workspace.CurrentCamera.CFrame.Position
            )
    end)

    pcall(function()
        ReplicatedStorage
            :WaitForChild("Remotes")
            :WaitForChild("CommE")
            :FireServer("ActivateAbility")
    end)
end

if Config["Boost FPS"] then
    spawn(function()
        while task.wait(30) do pcall(function() setfpscap(Config["FPS"]) end) end
    end)
end
if Config["Black Screen"] then
    pcall(function() StarterPlayer:FindFirstChild("PlayerScripts") end)
    spawn(function()
        local gui = game:GetService("CoreGui")
        local players = LocalPlayer:FindFirstChild("PlayerGui")
        if players then
            pcall(function()
                local m = players:FindFirstChild("Main")
                if m then m.Enabled = false end
            end)
        end
    end)
end

pcall(MakeUI)

local _lastUiRefresh = 0

local function _UIUpdateTickInner()
    local now = os.time()
    if now - _lastUiRefresh < 1 then return end
    _lastUiRefresh = now
    if not _statusLabel then return end
    _seaLabel.Text     = "Sea: " .. tostring(Sea)
    do
        local raceName = tostring(ConChoChisiti36.PlayerData.Race or "?")
        local raceV3 = IsCurrentRaceV3()
        _raceLabel.Text = "Race V3: " .. (raceV3 and "YES" or "NO") .. " | Race: " .. raceName
    end
    _mirrorLabel.Text  = "Mirror Fractal: "  .. (HasMirrorFractal() and "YES" or "NO")
    _valkLabel.Text    = "Valkyrie Helm: "   .. (HasValkyrieHelm()   and "YES" or "NO")
    do
        local mi = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("MysticIsland")
        if mi then
            local okd, dist = pcall(function()
                return math.floor(CaculateDistance(mi:GetModelCFrame()))
            end)
            _mirageLabel.Text = "Mirage Island: YES (" .. (okd and tostring(dist) or "?") .. " studs)"
        else
            _mirageLabel.Text = "Mirage Island: NO"
        end
    end
    local ok, door = pcall(function() return CommF_:InvokeServer("CheckTempleDoor") end)
    _doorLabel.Text    = "Temple Door: "     .. (ok and tostring(door) or "?")
    local prog = GetRaceV4Progress()
    _progressLabel.Text = "RaceV4 Check: " .. tostring(prog or "?")
end

-- Ghi vao label o CoreGui/gethui can identity cao. Neu mot require
-- truoc do da ha identity thi day la cho no no ra loi, nen luon
-- raise identity + pcall: UI loi khong duoc lam chet main loop.
local function UIUpdateTick()
    local prev = RaiseIdentity()
    local ok, err = pcall(_UIUpdateTickInner)
    RestoreIdentity(prev)
    if not ok then
        warn("[UI] UIUpdateTick loi: " .. tostring(err))
    end
end

while task.wait(1) do
    if not Config["Enabled"] then
        SetStatus("Disabled"); task.wait(5); continue
    end

    -- Same as Kata main state machine: team is a permanent gate.
    if not EnsureTeam() then
        SetStatus(
            "Unable to choose "
            .. RequestedTeam
            .. " | retrying..."
        )

        task.wait(1)
        continue
    end

    pcall(function() RefreshPlayerData() end)
    pcall(function() RefreshInventory() end)
    RefreshSea()
    UIUpdateTick()

    if not EnsureSea3() then
        task.wait(5)
        continue
    end

    if IsTempleDoorOpened() then
        MirageMovement.cancel()
        local wrote = WriteCompletedPull()

        if wrote then
            SetStatus("Temple Door da mo -> Completed-pull")
        else
            SetStatus("Temple Door da mo -> DONE (marker write failed)")
        end

        break
    end

    if not HasMirrorFractal() then
        SetStatus("Missing Mirror Fractal -> waiting")
        task.wait(3)
        continue
    end

    if not HasValkyrieHelm() then
        SetStatus("Missing Valkyrie Helm -> waiting")
        task.wait(3)
        continue
    end

    if not IsCurrentRaceV3() then
        SetStatus("Race chua V3 -> waiting (Auto UpRace da bo)")
        task.wait(3)
        continue
    end

    if not IsRaceV4ProgressReady() then
        local ok, err = pcall(DoRaceV4Progress)
        if not ok then
            DebugStatus("RaceV4Progress", err)
        end
        task.wait(3)
        continue
    end

    local ok, err = pcall(DoMirageBlueGear)
    if not ok then
        DebugStatus("MirageBlueGear", err)
    end
    task.wait(3)
end


pcall(function()
    if CharacterNoclipConnection then
        CharacterNoclipConnection:Disconnect()
    end
end)

end)()
