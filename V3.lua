local MeleeData = {
    ["Black Leg"] = "Dark Step Teacher";
    ["Electro"] = "Mad Scientist";
    ["Fishman Karate"] = "Water Kung-fu Teacher";
    ["Dragon Claw"] = "Sabi";
    ["Superhuman"] = "Martial Arts Master";
    ["Death Step"] = "Phoeyu, the Reformed";
    ["Sharkman Karate"] = "Sharkman Teacher";
    ["Electric Claw"] = "Previous Hero";
    ["Dragon Talon"] = "Uzoth";
    ["Godhuman"] = "Ancient Monk";
    ["Sanguine Art"] = "Shafi";
};

getgenv().Settings = getgenv().Settings or {
    ["API"] = {
        ["URL"] = "";
        ["Method"] = "GET";
        ["Headers"] = {
            ["Content-Type"] = "application/json";
        };
        ["Body"] = {
            ["Player"] = "";
            ["PlayerId"] = "";
        };
    };
    ["Focus Melee"] = "Sharkman Karate";
    ["Races"] = {
        ["Human"] = true;
        ["Mink"] = false;      
        ["Fishman"] = false;   
        ["Skypiea"] = false;   
        ["Cyborg"] = false;
        ["Ghoul"] = false;
    };
    ["Max Chests"] = 50;
    ["Skip Chest Delay"] = 1;
    ["Black Screen"] = false;
    ["Reset After Collect Chests"] = 10;
    ["Katakuri Progress"] = 300;
    ["Fragments"] = 5000;
    ["Chest Touch Radius"] = 8;
    ["Flower Touch Radius"] = 8;
}

getgenv().Races = getgenv().Races or getgenv().Settings["Races"]
getgenv().ChangeFolderOnCompleted = getgenv().ChangeFolderOnCompleted ~= false
getgenv().id1 = getgenv().id1 or "........."
getgenv().id2 = getgenv().id2 or "........."

local SeaMelee = {
    [2] = {"Dragon Claw", "Superhuman", "Death Step", "Sharkman Karate"};
    [3] = {"Electric Claw", "Dragon Talon", "Godhuman", "Sanguine Art"};
}
local function GetMeleeTargetSea(meleeName)
    if type(meleeName) ~= "string" then return 1 end
    for sea, list in pairs(SeaMelee) do
        for _, n in ipairs(list) do
            if n == meleeName then return sea end
        end
    end
    return 1
end

repeat task.wait(0.5) until game:IsLoaded() and time() >= 10
cloneref = cloneref or clonereference or function(x) return x end
isnetworkowner = isnetworkowner or isNetworkOwner or function() return true end
workspace = cloneref(workspace) or cloneref(Workspace) or (getrenv and (getrenv().workspace or getrenv().Workspace)) or cloneref(game:GetService("Workspace"))
PlaceId, JobId = game.PlaceId, game.JobId
getfenv = getfenv or _G or _ENV or shared or function() return {} end
IsOnMobile = false
Services = setmetatable({}, {__index = function(self, name)
    local s, c = pcall(function() return cloneref(game:GetService(name)) end)
    if s then rawset(self, name, c) return c
    else error("Invalid Roblox Service: " .. tostring(name))
    end
end})
COREGUI = Services.CoreGui
RunService = Services.RunService
VirtualUser = Services.VirtualUser
TweenService = Services.TweenService
HttpService = Services.HttpService
Players = Services.Players
ReplicatedStorage = Services.ReplicatedStorage
Lighting = Services.Lighting
CollectionService = Services.CollectionService
UserInputService = Services.UserInputService
VirtualInputManager = Services.VirtualInputManager
ReplicatedFirst = Services.ReplicatedFirst
StarterGui = Services.StarterGui
GuiService = Services.GuiService
TeleportService = Services.TeleportService
NeedSit = false
COMMF_ = ReplicatedStorage:WaitForChild("Remotes") and ReplicatedStorage.Remotes:WaitForChild("CommF_")
ServerBrowser = ReplicatedStorage:WaitForChild("__ServerBrowser")
LocalPlayer = Players.LocalPlayer
LocalPlayer.CharacterAdded:Connect(function(v)
    Character = v Humanoid = v:WaitForChild("Humanoid")
    HumanoidRootPart = v:WaitForChild("HumanoidRootPart")
end)
if LocalPlayer.Character then
    Character = LocalPlayer.Character
    Humanoid = Character:FindFirstChildWhichIsA("Humanoid") or Character:WaitForChild("Humanoid")
    HumanoidRootPart = Character:FindFirstChild("HumanoidRootPart") or Character:WaitForChild("HumanoidRootPart")
end

StarterGui:SetCore("SendNotification", {Title = "Executed", Text = "Loading… Please wait", Subtext = "VuNguyen KaitunV3 Premium", Duration = 5})
if not game:IsLoaded() or workspace.DistributedGameTime <= 10 then
    local WFGTL = COREGUI:FindFirstChild("WFGTL") or Instance.new("Hint", COREGUI)
    WFGTL.Text = "Just a moment... Waiting while the game loads - This won't take long!"
    task.wait(10 - workspace.DistributedGameTime)
    WFGTL:Destroy()
end
if not COMMF_ then repeat task.wait(1) until COMMF_ end
task.spawn(function()
    xpcall(function()
        if not LocalPlayer.Team then
            if LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen") then
                repeat task.wait(1) until not LocalPlayer.PlayerGui:FindFirstChild("LoadingScreen")
            end
            xpcall(function() COMMF_:InvokeServer("SetTeam", "Pirates")
            end, function() firesignal(LocalPlayer.PlayerGui["Main (minimal)"].ChooseTeam.Container.Pirates) end)
            task.wait(2)
        end
    end, function(err) warn("????", err) end)
end)
repeat task.wait(2) until Character and Character:FindFirstChild("HumanoidRootPart") and Character:FindFirstChildWhichIsA("Humanoid") and Character:IsDescendantOf(workspace.Characters) 

-- ============================================================
-- [ EXACT TITLE NAME V3 CHECKER ]
-- ============================================================
local TITLE_FAST_SCAN_INTERVAL = 5
local TITLE_FAST_SCAN_LIMIT = 3
local TITLE_SCAN_INTERVAL = 30

local TITLE_TARGETS = {
    { title = "Full Power", configRace = "Human", raceV3 = "Human V3" },
    { title = "Godspeed", configRace = "Mink", raceV3 = "Rabbit V3" },
    { title = "Warrior of the Sea", configRace = "Fishman", raceV3 = "Shark V3" },
    { title = "Perfect Being", configRace = "Skypiea", raceV3 = "Angel V3" },
    { title = "War Machine", configRace = "Cyborg", raceV3 = "Cyborg V3" },
    { title = "Hell Hound", configRace = "Ghoul", raceV3 = "Ghoul V3" },
}

local TITLE_FIELDS = {
    title = true,
    name = true,
    titlename = true,
    displayname = true,
}

local titleCache = {
    initialized = false,
    scanning = false,
    lastScan = 0,
    scanCount = 0,
    currentInterval = TITLE_FAST_SCAN_INTERVAL,
    map = {},
}

local function GetTitleScanInterval()
    if titleCache.scanCount < TITLE_FAST_SCAN_LIMIT then
        return TITLE_FAST_SCAN_INTERVAL
    end
    return TITLE_SCAN_INTERVAL
end

local function NormalizeText(value)
    return tostring(value or ""):lower():gsub("[^%w]", "")
end

local function ExactTitleMatch(targetTitle, value)
    return NormalizeText(targetTitle) == NormalizeText(value)
end

local function WalkTables(value, path, depth, visited, callback)
    if type(value) ~= "table" or depth > 10 then return end
    if visited[value] then return end
    visited[value] = true
    callback(value, path)

    for key, child in pairs(value) do
        if type(child) == "table" then
            WalkTables(child, path .. "[" .. tostring(key) .. "]", depth + 1, visited, callback)
        end
    end
end

local function NodeHasExactTitle(node, targetTitle)
    for key, value in pairs(node) do
        local normalizedKey = NormalizeText(key)
        if type(value) ~= "table" and TITLE_FIELDS[normalizedKey] and ExactTitleMatch(targetTitle, value) then
            return true
        end
        if type(key) == "string" and ExactTitleMatch(targetTitle, key) then
            return true
        end
    end
    return false
end

local function InvokeGetTitles(timeoutSeconds)
    local completed = false
    local okResult = false
    local dataResult = nil

    task.spawn(function()
        local ok, data = pcall(function()
            return COMMF_:InvokeServer("getTitles")
        end)
        okResult = ok
        dataResult = ok and data or nil
        completed = true
    end)

    local deadline = tick() + (tonumber(timeoutSeconds) or 2)
    repeat task.wait(0.05) until completed or tick() >= deadline

    return okResult, dataResult
end

local function ScanV3Titles(force)
    if titleCache.scanning then return titleCache.map end

    local requiredInterval = GetTitleScanInterval()
    if not force and titleCache.initialized and tick() - titleCache.lastScan < requiredInterval then
        return titleCache.map
    end

    titleCache.scanning = true
    local foundMap = {}
    local remoteOk, remoteData = InvokeGetTitles(2)

    for _, target in ipairs(TITLE_TARGETS) do
        local found = false
        if remoteOk and type(remoteData) == "table" then
            WalkTables(remoteData, "getTitles", 0, {}, function(node)
                if NodeHasExactTitle(node, target.title) then
                    found = true
                end
            end)
        end
        foundMap[target.configRace] = found
        foundMap[target.raceV3] = found
    end

    titleCache.map = foundMap
    titleCache.lastScan = tick()
    titleCache.scanCount = titleCache.scanCount + 1
    titleCache.currentInterval = GetTitleScanInterval()
    titleCache.initialized = true
    titleCache.scanning = false

    return titleCache.map
end

-- ============================================================
-- [ MODERN UI (VuNguyen KaitunV3 Premium) ]
-- ============================================================
local KaitunGuiStatusLabel
local KaitunGuiBlur
local guiVisible = true

local function formatNumber(n)
    local str = tostring(math.floor(tonumber(n) or 0))
    return str:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

do
    local plr = LocalPlayer
    pcall(function()
        if COREGUI:FindFirstChild("KaitunRacesBF") then COREGUI.KaitunRacesBF:Destroy() end
        if COREGUI:FindFirstChild("Status") then COREGUI.Status:Destroy() end
        if COREGUI:FindFirstChild("KaitunRacesBtn") then COREGUI.KaitunRacesBtn:Destroy() end
        local oldBlur = Lighting:FindFirstChild("CameraBlur")
        if oldBlur then oldBlur:Destroy() end
    end)

    KaitunGuiBlur = Instance.new("BlurEffect")
    KaitunGuiBlur.Name = "CameraBlur"
    KaitunGuiBlur.Size = 24
    KaitunGuiBlur.Parent = Lighting

    local Status = Instance.new("ScreenGui")
    Status.Name = "Status"
    Status.Parent = COREGUI
    Status.ResetOnSpawn = false
    Status.DisplayOrder = 10

    local DropShadow2Holder2_1 = Instance.new("Frame")
    DropShadow2Holder2_1.Name = "DropShadow2Holder2"
    DropShadow2Holder2_1.Parent = Status
    DropShadow2Holder2_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadow2Holder2_1.BackgroundTransparency = 1
    DropShadow2Holder2_1.Position = UDim2.new(0.5, 0, 0.05, 0)
    DropShadow2Holder2_1.Size = UDim2.new(0, 360, 0, 56)

    local DropShadow2_1 = Instance.new("ImageLabel")
    DropShadow2_1.Name = "DropShadow2"
    DropShadow2_1.Parent = DropShadow2Holder2_1
    DropShadow2_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadow2_1.BackgroundTransparency = 1
    DropShadow2_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropShadow2_1.Size = UDim2.new(1, 47, 1, 47)
    DropShadow2_1.Image = "rbxassetid://6015897843"
    DropShadow2_1.ImageColor3 = Color3.fromRGB(0, 0, 0)
    DropShadow2_1.ImageTransparency = 0.5

    local MainStatus = Instance.new("Frame")
    MainStatus.Name = "Main"
    MainStatus.Parent = DropShadow2_1
    MainStatus.AnchorPoint = Vector2.new(0.5, 0.5)
    MainStatus.BackgroundColor3 = Color3.fromRGB(15, 15, 20)
    MainStatus.BackgroundTransparency = 0.25
    MainStatus.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainStatus.Size = UDim2.new(1, -48, 1, -38)

    local UIStrokeStatus = Instance.new("UIStroke")
    UIStrokeStatus.Parent = MainStatus
    UIStrokeStatus.Color = Color3.fromRGB(255, 75, 75)
    UIStrokeStatus.Thickness = 2.2

    local UICornerStatus = Instance.new("UICorner")
    UICornerStatus.Parent = MainStatus
    UICornerStatus.CornerRadius = UDim.new(0, 8)

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Name = "StatusLabel"
    StatusLabel.Parent = MainStatus
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0.5)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
    StatusLabel.Size = UDim2.new(1, -20, 1, -10)
    StatusLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    StatusLabel.Text = "Status: Starting..."
    StatusLabel.TextColor3 = Color3.fromRGB(255, 90, 90)
    StatusLabel.TextSize = 17
    StatusLabel.TextWrapped = true
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Center

    KaitunGuiStatusLabel = StatusLabel

    local CoinCard_1 = Instance.new("ScreenGui")
    CoinCard_1.Name = "KaitunRacesBF"
    CoinCard_1.Parent = COREGUI
    CoinCard_1.ResetOnSpawn = false
    CoinCard_1.DisplayOrder = 20

    local DropShadowHolder_1 = Instance.new("Frame")
    DropShadowHolder_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadowHolder_1.BackgroundTransparency = 1
    DropShadowHolder_1.Name = "DropShadowHolder"
    DropShadowHolder_1.Parent = CoinCard_1
    DropShadowHolder_1.Position = UDim2.new(0.5, 0, 0.53, 0)
    DropShadowHolder_1.Size = UDim2.new(0, 600, 0, 420)
    DropShadowHolder_1.ZIndex = 1

    local Main_1 = Instance.new("Frame")
    Main_1.AnchorPoint = Vector2.new(0.5, 0.5)
    Main_1.BackgroundColor3 = Color3.fromRGB(16, 17, 24)
    Main_1.BackgroundTransparency = 0.15
    Main_1.Name = "Main"
    Main_1.Parent = DropShadowHolder_1
    Main_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    Main_1.Size = UDim2.new(1, -40, 1, -40)

    local UICorner_1 = Instance.new("UICorner")
    UICorner_1.CornerRadius = UDim.new(0, 12)
    UICorner_1.Parent = Main_1

    local UIStroke_1 = Instance.new("UIStroke")
    UIStroke_1.Color = Color3.fromRGB(255, 75, 75)
    UIStroke_1.Thickness = 2.5
    UIStroke_1.Parent = Main_1

    local HeaderFrame = Instance.new("Frame")
    HeaderFrame.Name = "HeaderFrame"
    HeaderFrame.Parent = Main_1
    HeaderFrame.BackgroundTransparency = 1
    HeaderFrame.Position = UDim2.new(0, 0, 0, 12)
    HeaderFrame.Size = UDim2.new(1, 0, 0, 32)

    local Top_1 = Instance.new("TextLabel")
    Top_1.BackgroundTransparency = 1
    Top_1.Name = "Top"
    Top_1.Parent = HeaderFrame
    Top_1.Size = UDim2.new(1, 0, 1, 0)
    Top_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Heavy)
    Top_1.Text = 'VuNguyen KaitunV3  <font color="#FFD700">[ PREMIUM ]</font>'
    Top_1.TextColor3 = Color3.fromRGB(255, 80, 80)
    Top_1.TextSize = 22
    Top_1.RichText = true
    Top_1.TextXAlignment = Enum.TextXAlignment.Center

    local Divider_1 = Instance.new("Frame")
    Divider_1.BorderSizePixel = 0
    Divider_1.BackgroundColor3 = Color3.fromRGB(255, 75, 75)
    Divider_1.BackgroundTransparency = 0.5
    Divider_1.Name = "Divider"
    Divider_1.Parent = Main_1
    Divider_1.Position = UDim2.new(0.06, 0, 0, 50)
    Divider_1.Size = UDim2.new(0.88, 0, 0, 1.5)

    local StatsCard = Instance.new("Frame")
    StatsCard.Name = "StatsCard"
    StatsCard.Parent = Main_1
    StatsCard.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
    StatsCard.BackgroundTransparency = 0.35
    StatsCard.Position = UDim2.new(0.06, 0, 0, 60)
    StatsCard.Size = UDim2.new(0.88, 0, 0, 110)

    local StatsCardCorner = Instance.new("UICorner")
    StatsCardCorner.CornerRadius = UDim.new(0, 8)
    StatsCardCorner.Parent = StatsCard

    local StatsCardStroke = Instance.new("UIStroke")
    StatsCardStroke.Color = Color3.fromRGB(60, 65, 85)
    StatsCardStroke.Thickness = 1
    StatsCardStroke.Parent = StatsCard

    local UnderStats_1 = Instance.new("TextLabel")
    UnderStats_1.BackgroundTransparency = 1
    UnderStats_1.Name = "UnderStats"
    UnderStats_1.Parent = StatsCard
    UnderStats_1.Position = UDim2.new(0, 16, 0, 8)
    UnderStats_1.Size = UDim2.new(1, -32, 0, 18)
    UnderStats_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    UnderStats_1.Text = "ACCOUNT OVERVIEW"
    UnderStats_1.TextColor3 = Color3.fromRGB(255, 110, 110)
    UnderStats_1.TextSize = 13
    UnderStats_1.TextXAlignment = Enum.TextXAlignment.Left

    local CharacterLabel = Instance.new("TextLabel")
    CharacterLabel.Name = "CharacterLabel"
    CharacterLabel.BackgroundTransparency = 1
    CharacterLabel.Parent = StatsCard
    CharacterLabel.Position = UDim2.new(0, 16, 0, 32)
    CharacterLabel.Size = UDim2.new(0.48, 0, 0, 20)
    CharacterLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    CharacterLabel.Text = "Character: N/A"
    CharacterLabel.TextColor3 = Color3.fromRGB(230, 230, 235)
    CharacterLabel.TextSize = 14
    CharacterLabel.TextXAlignment = Enum.TextXAlignment.Left
    CharacterLabel.RichText = true

    local RaceLabel_1 = Instance.new("TextLabel")
    RaceLabel_1.Name = "RaceLabel"
    RaceLabel_1.BackgroundTransparency = 1
    RaceLabel_1.Parent = StatsCard
    RaceLabel_1.Position = UDim2.new(0.52, 0, 0, 32)
    RaceLabel_1.Size = UDim2.new(0.46, 0, 0, 20)
    RaceLabel_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    RaceLabel_1.Text = "Current Race: N/A"
    RaceLabel_1.TextColor3 = Color3.fromRGB(230, 230, 235)
    RaceLabel_1.TextSize = 14
    RaceLabel_1.TextXAlignment = Enum.TextXAlignment.Left
    RaceLabel_1.RichText = true

    local BeliLabel_1 = Instance.new("TextLabel")
    BeliLabel_1.Name = "BeliLabel"
    BeliLabel_1.BackgroundTransparency = 1
    BeliLabel_1.Parent = StatsCard
    BeliLabel_1.Position = UDim2.new(0, 16, 0, 58)
    BeliLabel_1.Size = UDim2.new(0.48, 0, 0, 20)
    BeliLabel_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    BeliLabel_1.Text = "Beli: 0"
    BeliLabel_1.TextColor3 = Color3.fromRGB(100, 255, 140)
    BeliLabel_1.TextSize = 14
    BeliLabel_1.TextXAlignment = Enum.TextXAlignment.Left

    local FragLabel_1 = Instance.new("TextLabel")
    FragLabel_1.Name = "FragLabel"
    FragLabel_1.BackgroundTransparency = 1
    FragLabel_1.Parent = StatsCard
    FragLabel_1.Position = UDim2.new(0.52, 0, 0, 58)
    FragLabel_1.Size = UDim2.new(0.46, 0, 0, 20)
    FragLabel_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    FragLabel_1.Text = "Fragments: 0"
    FragLabel_1.TextColor3 = Color3.fromRGB(175, 150, 255)
    FragLabel_1.TextSize = 14
    FragLabel_1.TextXAlignment = Enum.TextXAlignment.Left

    local GoalLabel = Instance.new("TextLabel")
    GoalLabel.Name = "GoalLabel"
    GoalLabel.BackgroundTransparency = 1
    GoalLabel.Parent = StatsCard
    GoalLabel.Position = UDim2.new(0, 16, 0, 84)
    GoalLabel.Size = UDim2.new(1, -32, 0, 18)
    GoalLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
    GoalLabel.Text = "Server: -- | Job: --"
    GoalLabel.TextColor3 = Color3.fromRGB(150, 155, 175)
    GoalLabel.TextSize = 12
    GoalLabel.TextXAlignment = Enum.TextXAlignment.Left

    local UnderRace_1 = Instance.new("TextLabel")
    UnderRace_1.BackgroundTransparency = 1
    UnderRace_1.Name = "UnderRace"
    UnderRace_1.Parent = Main_1
    UnderRace_1.Position = UDim2.new(0.06, 0, 0, 180)
    UnderRace_1.Size = UDim2.new(0.88, 0, 0, 22)
    UnderRace_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    UnderRace_1.Text = "RACE V3 PROGRESSION (CONFIG SYNCED)"
    UnderRace_1.TextColor3 = Color3.fromRGB(255, 110, 110)
    UnderRace_1.TextSize = 13
    UnderRace_1.TextXAlignment = Enum.TextXAlignment.Left

    local RaceContainer = Instance.new("Frame")
    RaceContainer.Name = "RaceContainer"
    RaceContainer.Parent = Main_1
    RaceContainer.BackgroundTransparency = 1
    RaceContainer.Position = UDim2.new(0.06, 0, 0, 208)
    RaceContainer.Size = UDim2.new(0.88, 0, 0, 150)

    local raceGrid = Instance.new("UIGridLayout")
    raceGrid.Parent = RaceContainer
    raceGrid.CellSize = UDim2.new(0.485, 0, 0, 42)
    raceGrid.CellPadding = UDim2.new(0.03, 0, 0, 8)
    raceGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    raceGrid.VerticalAlignment = Enum.VerticalAlignment.Top
    raceGrid.SortOrder = Enum.SortOrder.LayoutOrder

    local raceDataList = {
        { config = "Human", v3 = "Human V3", color = Color3.fromRGB(255, 75, 75) },
        { config = "Mink", v3 = "Rabbit V3", color = Color3.fromRGB(60, 255, 120) },
        { config = "Fishman", v3 = "Shark V3", color = Color3.fromRGB(0, 185, 255) },
        { config = "Skypiea", v3 = "Angel V3", color = Color3.fromRGB(255, 215, 0) },
        { config = "Cyborg", v3 = "Cyborg V3", color = Color3.fromRGB(210, 80, 255) },
        { config = "Ghoul", v3 = "Ghoul V3", color = Color3.fromRGB(160, 255, 80) },
    }

    local raceCardElements = {}

    local function createRaceCard(info, order)
        local card = Instance.new("Frame")
        card.Name = info.config
        card.Parent = RaceContainer
        card.BackgroundColor3 = Color3.fromRGB(22, 24, 34)
        card.BackgroundTransparency = 0.3
        card.LayoutOrder = order

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 7)
        corner.Parent = card

        local stroke = Instance.new("UIStroke")
        stroke.Thickness = 1.2
        stroke.Color = Color3.fromRGB(50, 55, 72)
        stroke.Parent = card

        local titleLabel = Instance.new("TextLabel")
        titleLabel.Name = "Title"
        titleLabel.Parent = card
        titleLabel.BackgroundTransparency = 1
        titleLabel.Position = UDim2.new(0, 10, 0, 4)
        titleLabel.Size = UDim2.new(0.6, 0, 0, 18)
        titleLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        titleLabel.Text = info.v3
        titleLabel.TextColor3 = info.color
        titleLabel.TextSize = 14
        titleLabel.TextXAlignment = Enum.TextXAlignment.Left

        local stateLabel = Instance.new("TextLabel")
        stateLabel.Name = "State"
        stateLabel.Parent = card
        stateLabel.BackgroundTransparency = 1
        stateLabel.Position = UDim2.new(0, 10, 0, 22)
        stateLabel.Size = UDim2.new(0.6, 0, 0, 16)
        stateLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium)
        stateLabel.Text = "🔴 MISSING"
        stateLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
        stateLabel.TextSize = 12
        stateLabel.TextXAlignment = Enum.TextXAlignment.Left

        local cfgBadge = Instance.new("TextLabel")
        cfgBadge.Name = "CfgBadge"
        cfgBadge.Parent = card
        cfgBadge.AnchorPoint = Vector2.new(1, 0.5)
        cfgBadge.Position = UDim2.new(1, -10, 0.5, 0)
        cfgBadge.Size = UDim2.new(0, 52, 0, 22)
        cfgBadge.BackgroundColor3 = Color3.fromRGB(30, 33, 46)
        cfgBadge.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        cfgBadge.Text = "OFF"
        cfgBadge.TextColor3 = Color3.fromRGB(150, 150, 160)
        cfgBadge.TextSize = 11

        local badgeCorner = Instance.new("UICorner")
        badgeCorner.CornerRadius = UDim.new(0, 5)
        badgeCorner.Parent = cfgBadge

        return {
            Card = card,
            Stroke = stroke,
            Title = titleLabel,
            State = stateLabel,
            Badge = cfgBadge,
            Info = info
        }
    end

    for i, info in ipairs(raceDataList) do
        raceCardElements[info.config] = createRaceCard(info, i)
    end

    task.spawn(function()
        while task.wait(0.4) do
            pcall(function()
                if plr:FindFirstChild("Data") then
                    if plr.Data:FindFirstChild("Beli") then
                        BeliLabel_1.Text = "Beli: " .. formatNumber(plr.Data.Beli.Value)
                    end
                    if plr.Data:FindFirstChild("Fragments") then
                        FragLabel_1.Text = "Fragments: " .. formatNumber(plr.Data.Fragments.Value)
                    end
                    if plr.Data:FindFirstChild("Race") then
                        RaceLabel_1.Text = 'Current Race: <font color="#FFD700">' .. tostring(plr.Data.Race.Value) .. '</font>'
                    end
                end

                CharacterLabel.Text = 'Character: <font color="#FFFFFF">' .. tostring(plr.Name) .. '</font>'
                GoalLabel.Text = string.format("Players: %d/%d | Job: %s", #Players:GetPlayers(), Players.MaxPlayers, string.sub(game.JobId, 1, 12))

                local unlockedMap = ScanV3Titles(false)
                local cfgRaces = getgenv().Races or (getgenv().Settings and getgenv().Settings["Races"]) or {}

                for _, item in pairs(raceCardElements) do
                    local isDone = unlockedMap[item.Info.config] == true or unlockedMap[item.Info.v3] == true
                    local isEnabled = cfgRaces[item.Info.config] == true

                    if isDone then
                        item.State.Text = "🟢 DONE"
                        item.State.TextColor3 = Color3.fromRGB(80, 255, 140)
                        item.Stroke.Color = Color3.fromRGB(40, 160, 80)
                    else
                        item.State.Text = "🔴 MISSING"
                        item.State.TextColor3 = Color3.fromRGB(255, 100, 100)
                        item.Stroke.Color = isEnabled and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(50, 55, 72)
                    end

                    if isEnabled then
                        item.Badge.Text = "ON"
                        item.Badge.TextColor3 = Color3.fromRGB(80, 255, 140)
                        item.Badge.BackgroundColor3 = Color3.fromRGB(20, 45, 30)
                    else
                        item.Badge.Text = "OFF"
                        item.Badge.TextColor3 = Color3.fromRGB(150, 150, 160)
                        item.Badge.BackgroundColor3 = Color3.fromRGB(28, 30, 40)
                    end
                end
            end)
        end
    end)
end

function SetStatus(text)
    pcall(function()
        if KaitunGuiStatusLabel then
            KaitunGuiStatusLabel.Text = "Status: " .. tostring(text)
        end
    end)
end

local function SetText(newText)
    SetStatus(newText)
end

pcall(function() LocalPlayer.PlayerGui:FindFirstChild("Blank"):Destroy() end)
local BlankScreen = LocalPlayer.PlayerGui:FindFirstChild("Blank") or Instance.new("ScreenGui", LocalPlayer.PlayerGui)
BlankScreen.Name = "Blank" BlankScreen.ResetOnSpawn = false BlankScreen.DisplayOrder = -math.huge BlankScreen.IgnoreGuiInset = true

local Black = BlankScreen:FindFirstChild("Black Screen") or Instance.new("Frame", BlankScreen)
Black.Name = "Black Screen"
Black.Size = UDim2.new(1, 0, 1, 0)
Black.BackgroundColor3 = Color3.new(0, 0, 0)
Black.ZIndex = -math.huge
Black.Visible = getgenv().Settings["Black Screen"]

RunService:Set3dRenderingEnabled(not Black.Visible)

local leftButton = Instance.new("TextButton", BlankScreen)
leftButton.Name = "LeftButton"
leftButton.AnchorPoint = Vector2.new(0, 0)
leftButton.Position = UDim2.new(0, 20, 0, 90)
leftButton.Size = UDim2.new(0, 90, 0, 38)
leftButton.Text = "ON"
leftButton.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
leftButton.TextColor3 = Color3.fromRGB(255, 80, 80)
leftButton.TextSize = 22
leftButton.Font = Enum.Font.GothamBlack
leftButton.TextStrokeTransparency = 0.1
leftButton.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
leftButton.AutoButtonColor = true
leftButton.Active = true
leftButton.Draggable = true

local leftButtonCorner = Instance.new("UICorner")
leftButtonCorner.CornerRadius = UDim.new(0, 8)
leftButtonCorner.Parent = leftButton

local leftButtonStroke = Instance.new("UIStroke")
leftButtonStroke.Color = Color3.fromRGB(255, 80, 80)
leftButtonStroke.Thickness = 2
leftButtonStroke.Parent = leftButton

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.F4 then
        Black.Visible = not Black.Visible
        RunService:Set3dRenderingEnabled(not Black.Visible)
        StarterGui:SetCore("SendNotification", {
            Title = "Black Screen",
            Text = Black.Visible and "Đã BẬT màn hình đen (Tắt Render 3D)" or "Đã TẮT màn hình đen (Bật Render 3D)",
            Duration = 2
        })
    end
end)

leftButton.MouseButton1Click:Connect(function()
    guiVisible = not guiVisible
    leftButton.Text = guiVisible and "ON" or "OFF"
    leftButton.TextColor3 = guiVisible and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 80, 80)
    leftButtonStroke.Color = guiVisible and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 80, 80)

    local kaitunGui = COREGUI:FindFirstChild("KaitunRacesBF")
    if kaitunGui then kaitunGui.Enabled = guiVisible end

    local statusGui = COREGUI:FindFirstChild("Status")
    if statusGui then statusGui.Enabled = guiVisible end

    if KaitunGuiBlur then
        KaitunGuiBlur.Size = guiVisible and 24 or 0
    end
end)

function CheckSea(v: number) return v == tonumber(workspace:GetAttribute("MAP"):match("%d+")) end
local remoteAttack, idremote
local seed = ReplicatedStorage.Modules.Net.seed:InvokeServer()
task.spawn((function() for _, v in next, ({ReplicatedStorage.Util, ReplicatedStorage.Common, ReplicatedStorage.Remotes, ReplicatedStorage.Assets, ReplicatedStorage.FX}) do
    for _, n in next, v:GetChildren() do if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id") end
    end v.ChildAdded:Connect(function(n) if n:IsA("RemoteEvent") and n:GetAttribute("Id") then remoteAttack, idremote = n, n:GetAttribute("Id")
    end end) end
end))
CheckLocation = (function(v)return LocalPlayer:GetAttribute("CurrentLocation") == v end)
CheckMap = (function(v) return workspace.Map:FindFirstChild(v) or false end)
CheckTool = (function(v)
    for _, x in next, {LocalPlayer.Backpack, Character} do
    for _, v2 in next, x:GetChildren() do if v2:IsA("Tool") and (v2.Name == v or v2.Name:find(v)) then return true end
    end end return false
end)
CheckMaterial = (function(x)
    for _, v in pairs(COMMF_:InvokeServer("getInventory")) do if v.Type == "Material" then if v.Name == x then return v.Count end end
    end return 0
end)
CheckInventory = (function(...)
    for _, v in pairs(COMMF_:InvokeServer("getInventory")) do
    for _, n in next, {...} do if v.Name == n then return true end end
    end return false
end)

IsDied = function(v)
    local ok, r = xpcall(function()
        if not v then return true end
        local h = v:FindFirstChild("Humanoid") or v:FindFirstChildWhichIsA("Humanoid")
        local hrp = v:FindFirstChild("HumanoidRootPart")
        if not h or not hrp then return true end
        if h:IsA("Humanoid") then return h.Health <= 0 end
        if h:IsA("ValueBase") and type(h.Value) == "number" then return h.Value <= 0 end
        return false
    end, function() return false end)
    return ok and r or false
end

CheckMonster = (function(...) local args = {...}
    local v2 = {workspace.Enemies, ReplicatedStorage}
    for i = 1, #args do local n = args[i]
        local m = workspace.Enemies:FindFirstChild(n) or ReplicatedStorage:FindFirstChild(n)
        if m and m:IsA("Model") and m.Name ~= "Blank Buddy" then
            local h = m:FindFirstChildWhichIsA("Humanoid") local r = m:FindFirstChild("HumanoidRootPart")
            if h and r and not IsDied(m) then return m end
        end
    end
    for c = 1, #v2 do local container = v2[c] local ms = container:GetChildren()
        for m = 1, #ms do local m = ms[m] local h = m:FindFirstChildWhichIsA("Humanoid")
            local r = m:FindFirstChild("HumanoidRootPart")
            if m:IsA("Model") and h and r and not IsDied(m) and m.Name ~= "Blank Buddy" then
                for i = 1, #args do local n = args[i]
                    if m.Name == n or m.Name:lower():find(n:lower()) then
                        return m
                    end
                end
            end
        end
    end
    return false
end)

local lastEquip = tick()
EquipWeapon = (function(v)
    if tick() - lastEquip <= 0.2 then return end
    lastEquip = tick()
    if not Character then return end
    local tool = Character:FindFirstChildWhichIsA("Tool")
    if tool and (tool.ToolTip and tool.ToolTip == v) then return end
    for _, x in next, LocalPlayer.Backpack:GetChildren() do
        if x:IsA("Tool") and x.ToolTip == v then
            Humanoid:EquipTool(x)
            return
        end
    end
end)

function GetPosition(v)
    if not v then return nil
    elseif typeof(v) == "Vector3" then return v
    elseif typeof(v) == "CFrame" then return v.Position
    elseif v:IsA("BasePart") then return v.Position
    elseif v:IsA("Player") then
        local c = v.Character
        local hrp = c and c:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position
    elseif typeof(v) == "Instance" then
        local hrp = v:FindFirstChild("HumanoidRootPart")
        if hrp then return hrp.Position end
        local bp = v:FindFirstChildWhichIsA("BasePart")
        if bp then return bp.Position end
        if v.WorldPivot then return v.WorldPivot.Position end
    end
    return nil
end

local function getCFrame(v)
    if not v then return nil end
    if typeof(v) == "CFrame" then return v end
    if typeof(v) == "Vector3" then return CFrame.new(v) end
    if typeof(v) ~= "Instance" then return end
    if v:IsA("BasePart") then return v.CFrame end
    if v:IsA("Model") then
        if v.GetPivot then return v:GetPivot() end
        local root = v.PrimaryPart or v:FindFirstChild("HumanoidRootPart")
        if root then return root.CFrame end
    end
    if v:IsA("CFrameValue") then return v.Value end
    if v:IsA("Vector3Value") then return CFrame.new(v.Value) end
end

GetCFrameByNPC = function(x)
    local npc = workspace.NPCs:FindFirstChild(x) or ReplicatedStorage.NPCs:FindFirstChild(x)
    if npc and npc:IsA("Model") then
        return GetPosition(npc), CheckDistance(npc)
    end
    return nil, math.huge
end

GetNPCMelee = function(xn)
    return (type(xn)=="string" and MeleeData[xn] and (function(n)
        return (function(p) return p and {Name = n, Position = p} end)(GetCFrameByNPC(n))
    end)(MeleeData[xn])) or nil
end

local lastCallFA = tick()
FastAttack = (function(x)
    if not HumanoidRootPart or not Character:FindFirstChildWhichIsA("Humanoid") or Character.Humanoid.Health <= 0 or not Character:FindFirstChildWhichIsA("Tool") then return end
    local FAD = 0.01
    if FAD ~= 0 and tick() - lastCallFA <= FAD then return end
    local t = {}
    for _, u in next, {workspace.Characters, workspace.Enemies} do
        for _, e in next, u:GetChildren() do
            local h = e:FindFirstChildWhichIsA("Humanoid") local hrp = e:FindFirstChild("HumanoidRootPart")
            if e ~= Character and (x and e.Name == x or not x) and h and hrp and not IsDied(e) and (hrp.Position - HumanoidRootPart.Position).Magnitude <= 65 then t[#t + 1] = e end
        end
    end
    local n = ReplicatedStorage.Modules.Net
    local h = {[2] = {}}
    local last
    for i = 1, #t do local v = t[i]
        local part = v:FindFirstChild("Head") or v:FindFirstChild("HumanoidRootPart")
        if not h[1] then h[1] = part end
        h[2][#h[2] + 1] = {v, part} last = v
    end
    n:FindFirstChild("RE/RegisterAttack"):FireServer()
    n:FindFirstChild("RE/RegisterHit"):FireServer(unpack(h))
    cloneref(remoteAttack):FireServer(string.gsub("RE/RegisterHit", ".",function(c)
        return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow()/10%10)+1))
    end), bit32.bxor(idremote+909090, seed*2), unpack(h))
    lastCallFA = tick()
end)

CheckDistance = function(a, b) b = b or Character
    local pa, pb = GetPosition(a), GetPosition(b)
    if pa and pb then return (pa - pb).Magnitude end
    return math.huge
end

local function ExitTheChar()
    local Humanoid = game.Players.LocalPlayer.Character:FindFirstChild("Humanoid")
    if Humanoid and Humanoid.Sit then
        repeat task.wait()
            VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.Space, false, game)
            task.wait()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.Space, false, game)
        until not game.Players.LocalPlayer.Character:FindFirstChild("Humanoid").Sit
    end
end

-- ============================================================
-- PROXY TWEEN SYSTEM (Speed: 160 studs/s)
-- ============================================================
local TWEEN_SPEED = 160
local ACTIVE_PROXY_MOVE = nil
local PROXY_MOVE_SERIAL = 0

local function stopVelocity(root)
    if not root or not root.Parent then return end
    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function cleanupProxyMove(move)
    if not move or move.cleaned then return end
    move.cleaned = true

    if move.tween then pcall(function() move.tween:Cancel() end) end
    if move.syncConn then pcall(function() move.syncConn:Disconnect() end) end
    if move.charConn then pcall(function() move.charConn:Disconnect() end) end
    if move.proxy and move.proxy.Parent then pcall(function() move.proxy:Destroy() end) end

    if LocalPlayer.Character == move.character then
        for part, oldState in pairs(move.oldCollide or {}) do
            if part and part.Parent then
                pcall(function() part.CanCollide = oldState end)
            end
        end
    end

    if move.root and move.root.Parent then stopVelocity(move.root) end
end

local function cancelProxyTween()
    PROXY_MOVE_SERIAL += 1
    local move = ACTIVE_PROXY_MOVE
    ACTIVE_PROXY_MOVE = nil
    cleanupProxyMove(move)
end

local function tweenToCFrame(targetCFrame, arriveDistance, stopCondition)
    assert(typeof(targetCFrame) == "CFrame", "targetCFrame must be CFrame")
    arriveDistance = tonumber(arriveDistance) or 5

    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local root = char and char:FindFirstChild("HumanoidRootPart")

    if not (char and hum and root and hum.Health > 0) then
        cancelProxyTween()
        return false, "Character missing"
    end

    if hum.Sit and not NeedSit then
        ExitTheChar()
    end

    cancelProxyTween()

    local distance = (root.Position - targetCFrame.Position).Magnitude
    if distance <= arriveDistance then
        root.CFrame = targetCFrame
        stopVelocity(root)
        return true, distance
    end

    PROXY_MOVE_SERIAL += 1
    local moveId = PROXY_MOVE_SERIAL

    local proxy = Instance.new("Part")
    proxy.Name = "_V3_PROXY_TWEEN_" .. tostring(moveId)
    proxy.Size = Vector3.new(1, 1, 1)
    proxy.Transparency = 1
    proxy.Anchored = true
    proxy.CanCollide = false
    proxy.CanQuery = false
    proxy.CanTouch = false
    proxy.CFrame = root.CFrame
    proxy.Parent = workspace

    local oldCollide = {}
    for _, obj in ipairs(char:GetDescendants()) do
        if obj:IsA("BasePart") then
            oldCollide[obj] = obj.CanCollide
            obj.CanCollide = false
        end
    end

    local move = {
        id = moveId,
        character = char,
        humanoid = hum,
        root = root,
        proxy = proxy,
        oldCollide = oldCollide,
        cleaned = false,
    }

    ACTIVE_PROXY_MOVE = move

    move.charConn = LocalPlayer.CharacterAdded:Connect(function(newCharacter)
        if ACTIVE_PROXY_MOVE == move and newCharacter ~= char then
            cancelProxyTween()
        end
    end)

    move.syncConn = RunService.Heartbeat:Connect(function()
        if ACTIVE_PROXY_MOVE ~= move or move.cleaned or move.id ~= PROXY_MOVE_SERIAL then
            return
        end

        local current = LocalPlayer.Character
        local currentHum = current and current:FindFirstChildOfClass("Humanoid")
        local currentRoot = current and current:FindFirstChild("HumanoidRootPart")

        if current ~= char or not currentHum or currentHum.Health <= 0 or not currentRoot or not currentRoot.Parent or not proxy.Parent then
            cancelProxyTween()
            return
        end

        if not NeedSit then
            currentHum.Sit = false
        end

        for _, obj in ipairs(current:GetDescendants()) do
            if obj:IsA("BasePart") then
                obj.CanCollide = false
            end
        end

        currentRoot.CFrame = proxy.CFrame
        stopVelocity(currentRoot)
    end)

    local duration = math.max(distance / TWEEN_SPEED, 0.05)
    move.tween = TweenService:Create(
        proxy,
        TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
        { CFrame = targetCFrame }
    )
    move.tween:Play()

    local deadline = os.clock() + duration + 5
    while os.clock() < deadline do
        if ACTIVE_PROXY_MOVE ~= move or move.cleaned or moveId ~= PROXY_MOVE_SERIAL then
            return false, "Proxy tween cancelled"
        end

        if stopCondition and stopCondition() then
            cancelProxyTween()
            return false, "Stop condition met"
        end

        if LocalPlayer.Character ~= char or hum.Health <= 0 or not root.Parent or not proxy.Parent then
            cancelProxyTween()
            return false, "Character changed/died during proxy tween"
        end

        local remaining = (proxy.Position - targetCFrame.Position).Magnitude
        if remaining <= arriveDistance then
            pcall(function() move.tween:Cancel() end)
            proxy.CFrame = targetCFrame
            root.CFrame = targetCFrame
            stopVelocity(root)
            ACTIVE_PROXY_MOVE = nil
            cleanupProxyMove(move)
            return true, remaining
        end

        task.wait(0.03)
    end

    local remaining = proxy.Parent and (proxy.Position - targetCFrame.Position).Magnitude or math.huge
    ACTIVE_PROXY_MOVE = nil
    cleanupProxyMove(move)
    return false, "Proxy tween timeout; proxyDistance=" .. tostring(remaining)
end

function Tween(targetCFrame, targetInstanceOrDist)
    if targetCFrame == false then
        cancelProxyTween()
        return
    end

    if not Character or not Humanoid or Humanoid.Health <= 0 then
        cancelProxyTween()
        return
    end

    local cf = getCFrame(targetCFrame)
    if not cf then return end

    local arriveDistance = 5
    if typeof(targetInstanceOrDist) == "number" then
        arriveDistance = targetInstanceOrDist
    elseif typeof(targetInstanceOrDist) == "Instance" and targetInstanceOrDist:IsA("BasePart") then
        cf = targetInstanceOrDist.CFrame
    end

    return tweenToCFrame(cf, arriveDistance)
end

local function TweenChest(chest, stopCondition)
    if not chest or not chest:IsA("BasePart") or not chest.Parent or not chest.CanTouch then
        return false
    end

    local radius = tonumber(getgenv().Settings["Chest Touch Radius"]) or 8
    local targetCF = chest.CFrame * CFrame.new(0, 2, 0)
    
    local moved, _ = tweenToCFrame(targetCF, radius, function()
        return not chest.Parent or not chest.CanTouch or (stopCondition and stopCondition()) or IsDied(Character)
    end)

    if moved or (HumanoidRootPart and (HumanoidRootPart.Position - chest.Position).Magnitude <= radius) then
        pcall(function()
            firetouchinterest(HumanoidRootPart, chest, 0)
            task.wait(0.08)
            firetouchinterest(HumanoidRootPart, chest, 1)
        end)
        task.wait(0.15)
        return true
    end

    return false
end

local function TweenFlower(flower, flowerName)
    if not flower or not flower:IsA("BasePart") or not flower.Parent then
        return false
    end

    SetText("Upgrade Race V2 | Tweening " .. tostring(flowerName))
    local radius = tonumber(getgenv().Settings["Flower Touch Radius"]) or 8
    local targetCF = flower.CFrame * CFrame.new(0, 2, 0)

    local moved, _ = tweenToCFrame(targetCF, radius, function()
        return CheckTool(flowerName) or flower.Transparency ~= 0 or IsDied(Character)
    end)

    if moved or (HumanoidRootPart and (HumanoidRootPart.Position - flower.Position).Magnitude <= radius) then
        pcall(function()
            firetouchinterest(HumanoidRootPart, flower, 0)
            task.wait(0.08)
            firetouchinterest(HumanoidRootPart, flower, 1)
        end)
        task.wait(0.15)
        return true
    end

    return false
end

KillMonster=(function(x)
    xpcall(function()
        if workspace.Enemies:FindFirstChild(x) then
            for _,v in next,workspace.Enemies:GetChildren() do
                local vh=v:FindFirstChildWhichIsA("Humanoid") local vhrp=v:FindFirstChild("HumanoidRootPart")
                if vh and vhrp and v.Name==x and not IsDied(v) then
                    local dx,dy,dz=HumanoidRootPart.Position.X-vhrp.Position.X, HumanoidRootPart.Position.Y-vhrp.Position.Y, HumanoidRootPart.Position.Z-vhrp.Position.Z
                    local sqrMag=dx*dx+dy*dy+dz*dz
                    if sqrMag<=4900 then
                        FastAttack(x)
                        Tween(CFrame.new(vhrp.Position + (vhrp.CFrame.LookVector * 20) + Vector3.new(0, vhrp.Position.Y > 60 and -20 or 20, 0)))
                        EquipWeapon("Melee")
                        return
                    end
                    Tween(vhrp.CFrame) return
                end
            end
        end
        for _,v in next,ReplicatedStorage:GetChildren() do
            local vhrp=v:FindFirstChild("HumanoidRootPart")
            if v:IsA("Model") and vhrp and v.Name==x and not IsDied(v) then Tween(vhrp.CFrame) return end
        end
    end,function(e) warn("Modules ERROR:",e) end)
end)

local lastCheckSkill, MSkills = tick(), LocalPlayer.PlayerGui:WaitForChild("Main"):WaitForChild("Skills")
CheckCooldownSkill = function (key, n) if tick() - lastCheckSkill <= 0.2 then return false end lastCheckSkill = tick()
    n = n or (function(t) return t and t.Name end)(Character:FindFirstChildOfClass("Tool"))
    local keyfr = n and MSkills:FindFirstChild(n) and MSkills[n]:FindFirstChild(key) and MSkills[n][key]
    local cd = keyfr and keyfr:FindFirstChild("Cooldown")
    local txl = keyfr and keyfr:FindFirstChildWhichIsA("TextLabel")
    return cd and txl and cd.Size.X.Scale <= 0 and table.find({1, 255}, txl.TextColor3.R)
end

getgenv().AimbotTarget = false
SetAimbotTarget = function(a) getgenv().AimbotTarget = not a and nil or GetPosition(a) end
local mt = getrawmetatable(game)
local oldNamecall = mt.__namecall
setreadonly(mt, false)
mt.__namecall = newcclosure(function(self, ...)
    if not checkcaller() then
        local method = getnamecallmethod()
        if method == "FireServer" or method == "InvokeServer" then
            local args = {...}
            local t = getgenv().AimbotTarget
            if t and t ~= "" then
                if typeof(args[1]) ~= "boolean" then
                    local p = GetPosition(t)
                    if typeof(p) == "Vector3" then
                        for i = 1, #args do
                            if typeof(args[i]) == "Vector3" then
                                args[i] = p break
                            end
                        end
                    end
                end
                return oldNamecall(self, unpack(args))
            end
        end
    end
    return oldNamecall(self, ...)
end)

CheckOwnerBoat = function() if workspace.Boats:GetChildren() == 0 then return false end
    for _, v in next, workspace.Boats:GetChildren() do
        if v:IsA("Model") and v:FindFirstChild("Owner") and tostring(v.Owner.Value) == LocalPlayer.Name and v.Humanoid.Value > 0 and CheckDistance(v) <= 6000 then
            return v
        end
    end
    return false
end

local canPress = true
PressKeyEvent = (function(k, d)
    if not canPress then return end
    canPress = false
    task.spawn(function()
        VirtualInputManager:SendKeyEvent(true, k, false, game) task.wait(d or 0)
        VirtualInputManager:SendKeyEvent(false, k, false, game)
        canPress = true
    end)
end)

function CheckSafeZone(x)
	for _, v in workspace._WorldOrigin.SafeZones:GetChildren() do
		if (v.CFrame.Position - x).Magnitude < (v.Mesh.Scale.Magnitude / 2) then
			return true
		end
	end
	return false
end

local all = 0;
FarmBeli = (function(stopConditionFunc, ignoreY, ignoreFistStop)
    if type(stopConditionFunc) ~= "function" then stopConditionFunc = function() return false end end

    local chests, c = {}, 0
    local hasFist = CheckTool("Fist of Darkness")

    if not Character or IsDied(Character) then return end
    Tween(false)

    if all < getgenv().Settings["Max Chests"] and (ignoreFistStop or not hasFist) then
        for _, v in next, CollectionService:GetTagged("_ChestTagged") do
            if v and v.CanTouch then
                local dist = (v.Position - HumanoidRootPart.Position).Magnitude
                table.insert(chests, {obj = v, dist = dist})
            end
        end

        table.sort(chests, function(a, b) return a.dist < b.dist end)

        if ignoreFistStop or not CheckTool("Fist of Darkness") then
            for i, t in next, chests do
                local v = t.obj
                if v:IsA("BasePart") and v.Name:find("Chest") then
                    if v.CanTouch then
                        repeat task.wait()
                            SetText("Collect Chests | Collected: " .. c .. "/" .. all .. "/" .. getgenv().Settings["Max Chests"] .. " Chests")
                            local touched = TweenChest(v, function()
                                return (not ignoreFistStop and CheckTool("Fist of Darkness")) or IsDied(Character) or stopConditionFunc()
                            end)

                            if v and v.Parent and v.CanTouch then
                                task.wait(tonumber(getgenv().Settings["Skip Chest Delay"]) or 1)
                                if v and v.Parent and v.CanTouch then
                                    v.CanTouch = false
                                end
                            end
                        until not v.CanTouch or (not ignoreFistStop and CheckTool("Fist of Darkness")) or IsDied(Character) or stopConditionFunc()

                        if all >= getgenv().Settings["Max Chests"] then
                            SetText("Stopped: Max Chests reached")
                            HopServerBrowser()
                            break
                        elseif not ignoreFistStop and CheckTool("Fist of Darkness") then
                            SetText("Stopped: Fist of Darkness detected")
                            break
                        elseif not ignoreFistStop and CheckMonster("Darkbeard") then
                            break
                        elseif stopConditionFunc() then
                            break
                        end

                        if not IsDied(Character) then
                            c += 1
                            all += 1

                            if c >= getgenv().Settings["Reset After Collect Chests"] and (ignoreFistStop or not CheckTool("Fist of Darkness")) then
                                if Character and Character:FindFirstChildWhichIsA("Humanoid") then
                                    Character:FindFirstChildWhichIsA("Humanoid"):ChangeState(Enum.HumanoidStateType.Dead)
                                    SetText("Collect Chests | Reset: Collected: " .. tostring(getgenv().Settings["Reset After Collect Chests"]) .. " Chests")
                                end
                                c = 0
                                task.wait(1)
                            end
                        else
                            break
                        end
                    end
                    if i % 250 == 0 then task.wait(0.1) end
                end
            end
        else
            Tween(false)
            SetText("Stopped: Found Special Item")
        end

        if (ignoreFistStop or not CheckTool("Fist of Darkness")) and not CheckMonster("Darkbeard") and not stopConditionFunc() then
            HopServerBrowser()
        end
    end
end)

-- ============================================================
-- [ SERVER BROWSER V5.5 - 20 PAGES BATCH + 4/5/6 PLAYERS ]
-- ============================================================
local BROWSER_BATCH_PAGES = 20
local BROWSER_WORKERS = 4
local PAGES_PER_WORKER = 5
local BROWSER_BATCH_MAX_WAIT = 3.0
local BROWSER_MAX_PAGES = 100
local CANDIDATE_BLACKLIST_SECONDS = 90

local VISITED_FILE = "RaceV3Visited_" .. tostring(LocalPlayer.UserId) .. ".json"
local Visited = {}

local function loadVisited()
    if type(isfile) ~= "function" or type(readfile) ~= "function" then return end
    if not isfile(VISITED_FILE) then return end
    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(readfile(VISITED_FILE))
    end)
    if ok and type(decoded) == "table" then Visited = decoded end
end

local function saveVisited()
    if type(writefile) ~= "function" then return end
    pcall(function() writefile(VISITED_FILE, HttpService:JSONEncode(Visited)) end)
end

local function blockJob(jobId, seconds)
    if type(jobId) ~= "string" or jobId == "" then return end
    Visited[jobId] = os.time() + (tonumber(seconds) or CANDIDATE_BLACKLIST_SECONDS)
    saveVisited()
end

local function jobBlocked(jobId)
    if type(jobId) ~= "string" or jobId == "" or jobId == game.JobId then return true end
    local expires = tonumber(Visited[jobId])
    if not expires then return false end
    if expires <= os.time() then
        Visited[jobId] = nil
        return false
    end
    return true
end

loadVisited()

local function makeCandidate(jobId, info)
    if type(jobId) ~= "string" or jobId == "" or jobId == game.JobId then return nil end
    if jobBlocked(jobId) then return nil end

    local count = type(info) == "table" and tonumber(info.Count) or nil
    if count ~= 4 and count ~= 5 and count ~= 6 then return nil end

    return {
        jobId = jobId,
        players = count,
        region = info.Region,
        lastUpdate = info.__LastUpdate,
    }
end

local function shuffleForAccount(list)
    local seed = (LocalPlayer.UserId % 2147483647) + #list * 97
    for i = #list, 2, -1 do
        seed = (seed * 1103515245 + 12345) % 2147483647
        local j = (seed % i) + 1
        list[i], list[j] = list[j], list[i]
    end
end

local function fetch20PageBatch(batchStart, rawTotals, usableTotals)
    local batchEnd = math.min(BROWSER_MAX_PAGES, batchStart + BROWSER_BATCH_PAGES - 1)
    local batch = { [4] = {}, [5] = {}, [6] = {} }
    local pendingWorkers = 0
    local batchOpen = true

    for worker = 1, BROWSER_WORKERS do
        local workerStart = batchStart + ((worker - 1) * PAGES_PER_WORKER)
        local workerEnd = math.min(workerStart + PAGES_PER_WORKER - 1, batchEnd)

        if workerStart <= batchEnd then
            pendingWorkers += 1
            task.spawn(function()
                for page = workerStart, workerEnd do
                    if not batchOpen then break end
                    local ok, data = pcall(function()
                        return ServerBrowser:InvokeServer(page)
                    end)
                    if batchOpen and ok and type(data) == "table" then
                        for jobId, info in pairs(data) do
                            local count = type(info) == "table" and tonumber(info.Count) or nil
                            if count == 4 or count == 5 or count == 6 then
                                rawTotals[count] += 1
                                local cand = makeCandidate(jobId, info)
                                if cand then
                                    batch[count][#batch[count] + 1] = cand
                                    usableTotals[count] += 1
                                end
                            end
                        end
                    end
                    task.wait()
                end
                pendingWorkers -= 1
            end)
        end
    end

    local deadline = os.clock() + BROWSER_BATCH_MAX_WAIT
    while pendingWorkers > 0 and os.clock() < deadline do
        task.wait(0.02)
    end
    batchOpen = false
    return batch, batchEnd
end

local isHopping = false
function HopServerBrowser()
    if isHopping then return false end
    isHopping = true
    cancelProxyTween()

    local raw = { [4] = 0, [5] = 0, [6] = 0 }
    local usable = { [4] = 0, [5] = 0, [6] = 0 }

    for batchStart = 1, BROWSER_MAX_PAGES, BROWSER_BATCH_PAGES do
        local batchEnd = math.min(BROWSER_MAX_PAGES, batchStart + BROWSER_BATCH_PAGES - 1)
        SetText(string.format("Scanning Server Browser (4-6p)... batch %d-%d", batchStart, batchEnd))
        
        local batch, _ = fetch20PageBatch(batchStart, raw, usable)

        for _, playersCount in ipairs({4, 5, 6}) do
            if #batch[playersCount] > 0 then
                shuffleForAccount(batch[playersCount])
                for _, candidate in ipairs(batch[playersCount]) do
                    if not jobBlocked(candidate.jobId) then
                        blockJob(candidate.jobId, CANDIDATE_BLACKLIST_SECONDS)
                        SetText(string.format("Hopping to %dp server | %s", candidate.players, string.sub(candidate.jobId, 1, 10)))
                        
                        pcall(function()
                            ServerBrowser:InvokeServer("teleport", candidate.jobId)
                        end)
                        task.wait(4)
                    end
                end
            end
        end
        task.wait(0.05)
    end

    isHopping = false
    SetText("Rescanning Server Browser...")
    return false
end

-- ============================================================
-- [ RACE PRIORITIES & SWITCHING HELPERS ]
-- ============================================================
local STANDARD_RACE_ORDER = { "Human", "Mink", "Fishman", "Skypiea" }
local SPECIAL_RACE_ORDER = { "Cyborg", "Ghoul" }
local RACE_ORDER = { "Human", "Mink", "Fishman", "Skypiea", "Cyborg", "Ghoul" }

local raceAlias = {
    human = "Human",
    mink = "Mink",
    rabbit = "Mink",
    fishman = "Fishman",
    shark = "Fishman",
    skypiea = "Skypiea",
    angel = "Skypiea",
    ghoul = "Ghoul",
    cyborg = "Cyborg",
    draco = "Draco",
}

local function NormalizeRaceName(name)
    local s = tostring(name or ""):lower():gsub("%s+", "")
    return raceAlias[s] or tostring(name or "")
end

local function GetCurrentRace()
    local raceVal = LocalPlayer.Data and LocalPlayer.Data:FindFirstChild("Race")
    return NormalizeRaceName(raceVal and raceVal.Value or "")
end

local function GetFragments()
    local fragVal = LocalPlayer.Data and LocalPlayer.Data:FindFirstChild("Fragments")
    return tonumber(fragVal and fragVal.Value) or 0
end

local function GetEnabledRaces()
    local cfg = getgenv().Races or (getgenv().Settings and getgenv().Settings["Races"]) or {}
    local wanted = {}
    for _, raceName in ipairs(RACE_ORDER) do
        if cfg[raceName] == true then
            table.insert(wanted, raceName)
        end
    end
    return wanted
end

local function GetMissingEnabledRaces(titleMap)
    local enabled = GetEnabledRaces()
    local missing = {}
    for _, raceName in ipairs(enabled) do
        if titleMap[raceName] ~= true then
            table.insert(missing, raceName)
        end
    end
    return enabled, missing
end

local function GetMissingEnabledFromOrder(order, titleMap)
    local cfg = getgenv().Races or (getgenv().Settings and getgenv().Settings["Races"]) or {}
    local missing = {}
    for _, raceName in ipairs(order) do
        if cfg[raceName] == true and titleMap[raceName] ~= true then
            table.insert(missing, raceName)
        end
    end
    return missing
end

local lastRerollAt = 0
local function RerollRace(reason)
    if tick() - lastRerollAt < 3 then return false end
    if GetFragments() < 3000 then
        SetText(tostring(reason) .. " | Need 3000 Frags | Has: " .. tostring(GetFragments()))
        return false
    end

    local oldRace = GetCurrentRace()
    lastRerollAt = tick()
    SetText(tostring(reason) .. " | Rerolling standard race from " .. tostring(oldRace))

    local ok, res = pcall(function()
        return COMMF_:InvokeServer("BlackbeardReward", "Reroll", "2")
    end)

    task.wait(2)
    local newRace = GetCurrentRace()
    return newRace ~= oldRace
end

local lastSpecialChangeAt = 0
local specialChangeRunning = false
local function ChangeToSpecialRace(targetRace, reason)
    if targetRace ~= "Cyborg" and targetRace ~= "Ghoul" then return false end
    if specialChangeRunning or tick() - lastSpecialChangeAt < 5 then return false end

    local oldRace = GetCurrentRace()
    if oldRace == targetRace then return true end

    specialChangeRunning = true
    lastSpecialChangeAt = tick()
    SetText(tostring(reason) .. " | Switching to " .. tostring(targetRace))

    pcall(function()
        if targetRace == "Cyborg" then
            COMMF_:InvokeServer("CyborgTrainer", "Buy")
        elseif targetRace == "Ghoul" then
            COMMF_:InvokeServer("Ectoplasm", "BuyCheck", 4)
            task.wait(0.35)
            COMMF_:InvokeServer("Ectoplasm", "Change", 4)
        end
    end)

    task.wait(2.5)
    specialChangeRunning = false
    local newRace = GetCurrentRace()
    return newRace == targetRace
end

-- ============================================================
-- [ DYNAMIC COMPLETION FILE SYSTEM ]
-- ============================================================
local CompletedFolderLock = false

local function NormalizeFolderId(value, allowNil)
    if value == nil then return nil, allowNil end
    local s = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" or s == "........." or s:match("^%.+$") or s:lower() == "nil" then
        return nil, allowNil
    end
    return s, true
end

local function ChangeFolderAfterCompleted(reason)
    if CompletedFolderLock then return false end
    if getgenv().ChangeFolderOnCompleted == false or not getgenv().client or typeof(getgenv().client.ChangeToFolder) ~= "function" then
        return false
    end

    local id1, ok1 = NormalizeFolderId(getgenv().id1, false)
    local id2, ok2 = NormalizeFolderId(getgenv().id2, false)
    local id3, ok3 = NormalizeFolderId(getgenv().id3, true)
    if not ok1 or not ok2 then return false end

    CompletedFolderLock = true
    local ok, changed = pcall(function()
        return getgenv().client:ChangeToFolder(id1, id2, true, id3)
    end)

    if ok and changed then
        pcall(function() getgenv().client:Disconnect() end)
        task.wait(5)
        pcall(function() game:Shutdown() end)
        return true
    end
    CompletedFolderLock = false
    return false
end

local function GetCompletionFileContent()
    local enabledRaces = GetEnabledRaces()
    local count = #enabledRaces
    if count == 1 then
        return "Completed-" .. tostring(enabledRaces[1])
    elseif count >= 2 then
        return "Completed-" .. tostring(count) .. "racev3"
    end
    return "Completed-RACES"
end

local didWriteCompletedRaces = false
local function WriteCompletedRaces(reason)
    if didWriteCompletedRaces then return end

    local content = GetCompletionFileContent()
    SetText(reason or content)

    local okWrite, errWrite = pcall(function()
        writefile(LocalPlayer.Name .. ".txt", content)
    end)

    if not okWrite then
        warn("[Completed-RACES] Lỗi ghi file: " .. tostring(errWrite))
        return
    end

    didWriteCompletedRaces = true
    warn("[Completed-RACES] Đã tạo: " .. LocalPlayer.Name .. ".txt -> " .. content)
    ChangeFolderAfterCompleted(content)
end

-- ============================================================
-- [ VÒNG LẶP RIÊNG: AUTO SPAM WENLOCKTOAD CHO SKYPIEA & GHOUL V2 -> V3 ]
-- ============================================================
task.spawn(function()
    while task.wait(1) do
        pcall(function()
            local currentRace = GetCurrentRace()
            local isV2 = LocalPlayer.Data 
                and LocalPlayer.Data:FindFirstChild("Race") 
                and LocalPlayer.Data.Race:FindFirstChild("Evolved") ~= nil
            local titleMap = ScanV3Titles(false)

            if (currentRace == "Skypiea" and not titleMap["Skypiea"])
                or (currentRace == "Ghoul" and not titleMap["Ghoul"]) then
                local beli = (LocalPlayer.Data:FindFirstChild("Beli") and LocalPlayer.Data.Beli.Value) or 0
                if beli >= 2000000 and isV2 then
                    local ven1 = COMMF_:InvokeServer("Wenlocktoad", "1")
                    if ven1 == 0 then
                        COMMF_:InvokeServer("Wenlocktoad", "2")
                        ScanV3Titles(true)
                    elseif ven1 == 2 then
                        COMMF_:InvokeServer("Wenlocktoad", "3")
                        ScanV3Titles(true)
                    end
                end
            end
        end)
    end
end)

-- ============================================================
-- [ HUMAN V2 PLAYER SCRIPT LOOP ]
-- Tự động chạy playerv3.lua khi là Human V2 chưa đạt Full Power
-- ============================================================
local PLAYER_V3_URL = "https://raw.githubusercontent.com/longvu26092007-eng/hellobeo/refs/heads/main/playerv3.lua"
local PLAYER_V3_FIRST_DELAY = 30
local PLAYER_V3_INTERVAL = 300
local playerV3NextRun = tick() + PLAYER_V3_FIRST_DELAY

task.spawn(function()
    while task.wait(2) do
        pcall(function()
            if tick() >= playerV3NextRun then
                local currentRace = GetCurrentRace()
                local isV2 = LocalPlayer.Data 
                    and LocalPlayer.Data:FindFirstChild("Race") 
                    and LocalPlayer.Data.Race:FindFirstChild("Evolved") ~= nil
                local isV3 = ScanV3Titles(false)["Human"] == true

                if currentRace == "Human" and isV2 and not isV3 then
                    playerV3NextRun = tick() + PLAYER_V3_INTERVAL
                    loadstring(game:HttpGet(PLAYER_V3_URL))()
                end
            end
        end)
    end
end)

-- ============================================================
-- [ HUMAN V3 BOSS TRACKING LOGIC ]
-- ============================================================
local HumanBossKills = {}
local HumanServerLocked = false

local function CountAliveHumanBosses()
    local count = 0
    for _, name in ipairs({"Jeremy", "Orbitus", "Diamond"}) do
        local m = CheckMonster(name)
        if m and not IsDied(m) then
            count += 1
        end
    end
    return count
end

-- ============================================================
-- [ MAIN CONTROLLER & WORKER LOOP ]
-- ============================================================
task.spawn(function()
    ScanV3Titles(true)
    task.wait(1)

    while task.wait(0.5) do
        xpcall(function()
            local CurrentRace = GetCurrentRace()
            local titleMap = ScanV3Titles(false)
            local enabledRaces, missingRaces = GetMissingEnabledRaces(titleMap)

            if #enabledRaces > 0 and #missingRaces == 0 then
                WriteCompletedRaces("Upgrade Race V3 | Completed configured races")
                return
            end

            local isCurrentEnabled = table.find(enabledRaces, CurrentRace) ~= nil
            local isCurrentDone = titleMap[CurrentRace] == true

            local missingStandard = GetMissingEnabledFromOrder(STANDARD_RACE_ORDER, titleMap)
            local missingSpecial = GetMissingEnabledFromOrder(SPECIAL_RACE_ORDER, titleMap)

            if isCurrentDone or not isCurrentEnabled then
                if #missingStandard > 0 then
                    if GetFragments() >= 3000 then
                        RerollRace("Seeking standard race missing V3: " .. table.concat(missingStandard, ", "))
                    else
                        if CheckSea(3) then
                            if CheckMonster("Dough King") or CheckMonster("rip_indra") or CheckMonster("Cake Prince") then
                                for _, v2 in next, {workspace.Enemies, ReplicatedStorage} do
                                    for _, v in next, v2:GetChildren() do
                                        if v.Name == "Dough King" or v.Name == "Cake Prince" or v.Name:find("rip_indra") then
                                            if v.Name ~= "rip_indra" and not CheckLocation("Dimensional Shift") then
                                                xpcall(function()
                                                    firetouchinterest(LocalPlayer.Character.HumanoidRootPart, workspace.Map.CakeLoaf.BigMirror.Main, 0)
                                                    task.wait(3)
                                                end, function(e) warn(e) end)
                                            end
                                            if v:FindFirstChildWhichIsA("Humanoid") and v.Humanoid.Health > 0 and v.HumanoidRootPart then
                                                repeat task.wait()
                                                    SetText("Killing ".. v.Name.. " | Health: ".. math.floor(v.Humanoid.Health / v.Humanoid.MaxHealth * 100).. "%")
                                                    KillMonster(v.Name)
                                                until not v or not v:FindFirstChildWhichIsA("Humanoid") or v.Humanoid.Health <= 0 or not v.HumanoidRootPart
                                            end
                                        end
                                    end
                                end
                            else
                                local currentProgress = tonumber(COMMF_:InvokeServer("CakePrinceSpawner"):match("%d+") or 500)
                                if currentProgress <= getgenv().Settings["Katakuri Progress"] then
                                    for _, v in next, workspace.Enemies:GetChildren() do
                                        if table.find({"Cookie Crafter", "Cake Guard", "Baking Staff", "Head Baker"}, v.Name) then
                                            if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChildWhichIsA("Humanoid") and v.Humanoid.Health > 0 then
                                                repeat task.wait()
                                                    SetText("Killing 500 monsters | Progress: ".. currentProgress.. "/500")
                                                    KillMonster(v.Name)
                                                until not v or not v:FindFirstChildWhichIsA("Humanoid") or v.Humanoid.Health <= 0
                                            end
                                        end
                                    end
                                else
                                    if not CheckMonster("Dough King") and not CheckMonster("Cake Prince") then
                                        SetText("Hop for Katakuri (4-6p)...")
                                        task.wait(2)
                                        HopServerBrowser()
                                    end
                                end
                            end
                        else
                            SetText("Travel To Sea 3 for Fragments")
                            COMMF_:InvokeServer("TravelZou") task.wait(2)
                        end
                    end
                elseif #missingSpecial > 0 then
                    local targetSpecial = missingSpecial[1]
                    ChangeToSpecialRace(targetSpecial, "Standard races completed/off. Changing to special race")
                    task.wait(2)
                else
                    ScanV3Titles(true)
                end
            else
                if CheckSea(2) or (not CheckTool(getgenv().Settings["Focus Melee"]) and CurrentRace == "Fishman") then
                    local SetRaceStatus = function(x) SetText(string.format("Upgrade Race V%s | Current: %s", x, CurrentRace)) end
                    if not LocalPlayer.Data.Race:FindFirstChild("Evolved") then
                        SetRaceStatus(2)
                        if LocalPlayer.Data.Beli.Value >= 500000 then
                            local alch = COMMF_:InvokeServer("Alchemist", "2")
                            if alch == "Come back when you find them." then
                                if not CheckTool("Flower 2") and workspace.Flower2.Transparency == 0 then
                                    Tween(false)
                                    SetText("Collecting Flower 2")
                                    repeat
                                        task.wait(0.1)
                                        if workspace:FindFirstChild("Flower2") then
                                            TweenFlower(workspace.Flower2, "Flower 2")
                                        end
                                    until (CheckTool("Flower 2") or workspace.Flower2.Transparency ~= 0 or IsDied(Character))
                                elseif not CheckTool("Flower 3") then
                                    for _, v in next, workspace.Enemies:GetChildren() do
                                        if v.Name == "Swan Pirate" and v:FindFirstChildWhichIsA("Humanoid") and v.Humanoid.Health > 0 then
                                            repeat task.wait() KillMonster(v.Name) SetText("Collecting Flower 3")
                                            until not v or v.Humanoid.Health <= 0 or CheckTool("Flower 3")
                                        else
                                            Tween(CFrame.new(980, 120, 1290))
                                        end
                                    end
                                elseif not CheckTool("Flower 1") then
                                    if workspace.Flower1.Transparency == 0 then
                                        Tween(false)
                                        SetText("Collecting Flower 1")
                                        repeat
                                            task.wait(0.1)
                                            if workspace:FindFirstChild("Flower1") then
                                                TweenFlower(workspace.Flower1, "Flower 1")
                                            end
                                        until (CheckTool("Flower 1") or workspace.Flower1.Transparency ~= 0 or IsDied(Character))
                                    else
                                        xpcall(function() Tween(workspace._WorldOrigin.SafeZones:GetChildren()[1].CFrame) end, function() end)
                                    end
                                else
                                    if CheckTool("Flower 1") and CheckTool("Flower 2") and CheckTool("Flower 3") then
                                        COMMF_:InvokeServer("Alchemist", "3")
                                    end
                                end
                            end
                        else
                            FarmBeli(function() return LocalPlayer.Data.Beli.Value >= 500000 end)
                        end
                    elseif COMMF_:InvokeServer("Wenlocktoad") == nil then
                        SetRaceStatus(3)
                        if LocalPlayer.Data.Beli.Value >= 2000000 then
                            local ven1 = COMMF_:InvokeServer("Wenlocktoad", "1")
                            if ven1 == 0 then COMMF_:InvokeServer("Wenlocktoad", "2")
                            elseif ven1 == 2 then COMMF_:InvokeServer("Wenlocktoad", "3")
                            else
                                if CurrentRace == "Human" then
                                    local aliveBosses = CountAliveHumanBosses()
                                    local killedCount = 0
                                    for _ in pairs(HumanBossKills) do killedCount += 1 end

                                    if aliveBosses >= 2 or killedCount >= 2 then
                                        HumanServerLocked = true
                                    end

                                    if HumanServerLocked or aliveBosses > 0 then
                                        local foundAny = false
                                        for _, v2 in next, {workspace.Enemies, ReplicatedStorage} do
                                            for _, v in next, v2:GetChildren() do
                                                if table.find({"Jeremy", "Orbitus", "Diamond"}, v.Name) then
                                                    local hum = v:FindFirstChildWhichIsA("Humanoid")
                                                    if hum and hum.Health > 0 then
                                                        foundAny = true
                                                        repeat task.wait()
                                                            SetText(string.format("Killing %s (Human V3: %d/3)", v.Name, killedCount))
                                                            KillMonster(v.Name)
                                                        until not v or not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
                                                        
                                                        HumanBossKills[v.Name] = true
                                                        killedCount = 0
                                                        for _ in pairs(HumanBossKills) do killedCount += 1 end
                                                        if killedCount >= 2 then
                                                            HumanServerLocked = true
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                        if not foundAny and HumanServerLocked then
                                            SetText(string.format("Human V3: Killed %d/3 -> Waiting 3rd boss to respawn...", killedCount))
                                            task.wait(2)
                                        end
                                    else
                                        SetText(string.format("Human V3: Only %d boss alive -> Hopping Server (4-6p)...", aliveBosses))
                                        task.wait(1.5)
                                        HopServerBrowser()
                                    end
                                elseif CurrentRace == "Mink" then
                                    FarmBeli(function() return (ScanV3Titles(false)["Mink"] == true) end, nil, true)
                                elseif CurrentRace == "Fishman" then
                                    local TargetMelee = getgenv().Settings["Focus Melee"]
                                    if CheckTool(TargetMelee) then
                                        local function CE(x) return workspace.Enemies:FindFirstChild(x) or workspace.SeaBeasts:FindFirstChild(x) end
                                        local e = CE("Piranha") or CE("Shark") or CE("Fish Crew Member")
                                        local v = CE("SeaBeast1")
                                        if e then Character.Humanoid.Sit = false
                                            repeat task.wait() KillMonster(e.Name)
                                            until not e or e.Humanoid.Health <= 0 or not Character:FindFirstChild("Humanoid") or Character.Humanoid.Health <= 0
                                        elseif v then Character.Humanoid.Sit = false
                                            repeat task.wait()
                                                FastAttack()
                                                SetAimbotTarget(v.HumanoidRootPart)
                                                Tween(v.HumanoidRootPart.CFrame * CFrame.new(0, (v.HumanoidRootPart.Position.Y > -300 and 500 or 1000), 0))
                                                EquipWeapon(({"Melee", "Sword", "Gun", "Blox Fruit"})[math.random(4)])
                                                local k = ({"Z", "X", "C", "V", "F"})[math.random(5)]
                                                if not Character:FindFirstChild("Portal-Portal") then
                                                    if CheckCooldownSkill(k) then
                                                        PressKeyEvent(k, 0.5)
                                                    end
                                                end
                                            until not v or not v:FindFirstChild("Health") or v.Health.Value <= 0 or not Character:FindFirstChild("Humanoid") or Character.Humanoid.Health <= 0
                                        else
                                            local BOAT = CheckOwnerBoat()
                                            if BOAT then
                                                if not Character.Humanoid.Sit then Tween(BOAT.VehicleSeat.CFrame)
                                                    NeedSit = true
                                                else Tween(CFrame.new(-1000000, 49, 1000000), BOAT:FindFirstChild("Engine"))
                                                task.delay(5, function() Tween(false) end)
                                                end
                                            else
                                                local PlaceNPC = Vector3.new(-1, 10, 2960)
                                                if (HumanoidRootPart.Position - PlaceNPC).Magnitude < 50 then
                                                    COMMF_:InvokeServer("BuyBoat", LocalPlayer.Team.Name == "Marine" and "PirateSloop" or "PirateBrigade")
                                                else
                                                    Character.Humanoid.Sit = false
                                                    Tween(CFrame.new(PlaceNPC))
                                                end
                                            end
                                        end
                                    else Character.Humanoid.Sit = false
                                        local npcName = MeleeData[TargetMelee] or TargetMelee
                                        local x, d = GetCFrameByNPC(npcName)
                                        if x then
                                            if d < 50 then
                                                if TargetMelee == "Dragon Claw" then
                                                    COMMF_:InvokeServer("BlackbeardReward", "DragonClaw", "2")
                                                elseif TargetMelee == "Sharkman Karate" then
                                                    local hasSharkman = CheckTool("Sharkman Karate") or CheckInventory("Sharkman Karate")
                                                    if not hasSharkman and COMMF_:InvokeServer("BuySharkmanKarate", true) == 1 then
                                                        local pos = CFrame.new(-2599.621826171875, 238.19833374023438, -10315.998046875)
                                                        repeat task.wait() Tween(pos) until CheckDistance(pos) <= 30
                                                        COMMF_:InvokeServer("BuySharkmanKarate")
                                                    end
                                                else
                                                    COMMF_:InvokeServer("Buy"..TargetMelee:gsub("%s+", ""))
                                                end
                                            else
                                                SetText("Travel To ".. npcName.. " NPC")
                                                Tween(x)
                                            end
                                        else
                                            SetText("Can't find ".. npcName.. " NPC")
                                            Character.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
                                            LocalPlayer.CharacterAdded:Wait()
                                            local needSea = GetMeleeTargetSea(TargetMelee)
                                            if needSea == 2 then COMMF_:InvokeServer("TravelDressrosa")
                                            elseif needSea == 3 then COMMF_:InvokeServer("TravelZou") end
                                        end
                                     end
                                elseif CurrentRace == "Skypiea" then
                                    local x = nil
                                    for _, v in next, Players:GetPlayers() do
                                        if v.Name ~= LocalPlayer.Name and v:FindFirstChild("Data") and v.Data.Race.Value == "Skypiea" then
                                            if not CheckSafeZone(v.Character.HumanoidRootPart.Position) and v:GetAttribute("DangerLevel") == 0 then
                                                x = v.Character break
                                            end
                                        end
                                    end
                                    
                                    local lastPvpEnable = 0
                                    if x then
                                        repeat task.wait()
                                            SetText("Killing Skypiea Player | Health: ".. math.floor(x.Humanoid.Health / x.Humanoid.MaxHealth * 100).. "%")
                                            if LocalPlayer.PlayerGui.Main.PvpDisabled.Visible and (tick() - lastPvpEnable > 3) then
                                                lastPvpEnable = tick()
                                                pcall(function() COMMF_:InvokeServer("EnablePvp") end)
                                            end
                                            Tween(x.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
                                            if (x.HumanoidRootPart.Position - HumanoidRootPart.Position).Magnitude < 100 then
                                                FastAttack() SetAimbotTarget(x.HumanoidRootPart)
                                                EquipWeapon(({"Melee", "Sword", "Gun", "Blox Fruit"})[math.random(4)])
                                            end
                                        until not x or x.Humanoid.Health <= 0
                                    else
                                        SetText("Finding Skypiea Player (4-6p)...")
                                        task.wait(2)
                                        HopServerBrowser()
                                    end
                                elseif CurrentRace == "Ghoul" then
                                    -- Nhiệm vụ Ghoul V3: Tiêu diệt 5 người chơi
                                    local targetPlr = nil
                                    for _, v in next, Players:GetPlayers() do
                                        if v.Name ~= LocalPlayer.Name and v.Character and v.Character:FindFirstChild("HumanoidRootPart") then
                                            local hum = v.Character:FindFirstChildOfClass("Humanoid")
                                            if hum and hum.Health > 0 and not CheckSafeZone(v.Character.HumanoidRootPart.Position) then
                                                targetPlr = v.Character
                                                break
                                            end
                                        end
                                    end

                                    local lastPvpEnable = 0
                                    if targetPlr then
                                        repeat task.wait()
                                            SetText(string.format("Killing Player for Ghoul V3: %s | HP: %d%%", targetPlr.Name, math.floor(targetPlr.Humanoid.Health / targetPlr.Humanoid.MaxHealth * 100)))
                                            if LocalPlayer.PlayerGui.Main.PvpDisabled.Visible and (tick() - lastPvpEnable > 3) then
                                                lastPvpEnable = tick()
                                                pcall(function() COMMF_:InvokeServer("EnablePvp") end)
                                            end
                                            Tween(targetPlr.HumanoidRootPart.CFrame * CFrame.new(0, 20, 0))
                                            if (targetPlr.HumanoidRootPart.Position - HumanoidRootPart.Position).Magnitude < 100 then
                                                FastAttack() SetAimbotTarget(targetPlr.HumanoidRootPart)
                                                EquipWeapon(({"Melee", "Sword", "Gun", "Blox Fruit"})[math.random(4)])
                                            end
                                        until not targetPlr or not targetPlr:FindFirstChildOfClass("Humanoid") or targetPlr.Humanoid.Health <= 0
                                        
                                        task.wait(1)
                                        COMMF_:InvokeServer("Wenlocktoad", "2")
                                    else
                                        SetText("Finding Players for Ghoul V3 (4-6p)...")
                                        task.wait(2)
                                        HopServerBrowser()
                                    end
                                elseif CurrentRace == "Cyborg" then
                                    local venlock = COMMF_:InvokeServer("Wenlocktoad", "2")
                                    if typeof(venlock) == "string" then 
                                        SetText("Upgrade Race V3")
                                        if venlock:find("haven't completed") ~= nil or venlock:find("Talk to me again") ~= nil then
                                            for _, v in pairs(workspace:GetChildren()) do
                                                pcall(function()
                                                    if v:IsA("Model") and v.Name:find("Fruit") and v:FindFirstChild("Handle") and v.Handle:FindFirstChildWhichIsA("TouchTransmitter", true) then
                                                        firetouchinterest(v.Handle, Character:FindFirstChild("HumanoidRootPart"), 0) task.wait(1)
                                                        firetouchinterest(v.Handle, Character:FindFirstChild("HumanoidRootPart"), 1)
                                                    end
                                                end)
                                            end
                                            if CheckTool("Fruit") then
                                                local t = math.huge
                                                local n
                                                for _, v in next, COMMF_:InvokeServer("getInventory") do
                                                    if v.Type == "Blox Fruit" and v.Value < t then
                                                        t = v.Value
                                                        n = v.Name
                                                    end
                                                end
                                                COMMF_:InvokeServer("LoadFruit", n)
                                            end
                                            if CheckTool("Fruit") then
                                                COMMF_:InvokeServer("Wenlocktoad", "3")
                                            else
                                                SetText("Not Found Fruit, Hopping (4-6p)...")
                                                task.wait(2)
                                                HopServerBrowser()
                                            end
                                        end
                                    end
                                end
                            end
                        else
                            FarmBeli(function() return LocalPlayer.Data.Beli.Value >= 2000000 end)
                        end
                    else
                        SetText("Race V3 confirmed: " .. tostring(CurrentRace))
                    end
                else
                    SetText("Travel To Sea 2 for Upgrade Race V2")
                    COMMF_:InvokeServer("TravelDressrosa") task.wait(1)
                end
            end
        end, function(err) warn("[Main Worker Error]:", err) end)
    end
end)

task.spawn(function()
    while task.wait(4) do 
        PressKeyEvent("T") PressKeyEvent("Y") PressKeyEvent("Q")
        xpcall(function() 
            ReplicatedStorage.Remotes.CommE:FireServer("Ken", true)
            if not Character.Humanoid or Character.Humanoid.Health <= 0 then cancelProxyTween() return end
            if not Character:FindFirstChild("HasBuso") then COMMF_:InvokeServer("Buso") end
            for _, v in next, {"Buso", "Geppo", "Soru"} do
                if not CollectionService:HasTag(Character, v) then
                    if LocalPlayer.Data.Beli.Value >= ((function(t)
                        return t == "Geppo" and 1e4 or t == "Buso" and 2.5e4 or t == "Soru" and 1e5 or 0
                    end)(v)) then SetText("Buy Abilies: ".. v) COMMF_:InvokeServer("BuyHaki", v) end
                end
            end
        end, function(err) warn("LL:", err) end)
    end
end)

GuiService.ErrorMessageChanged:Connect(newcclosure(function()
    if GuiService:GetErrorType() == Enum.ConnectionError.DisconnectErrors then
        while true do ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer('teleport', JobId) task.wait(5) end
    end
end))
