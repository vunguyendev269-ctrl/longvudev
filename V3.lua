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

-- Đồng bộ cấu hình Races giữa getgenv().Races và getgenv().Settings["Races"]
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

StarterGui:SetCore("SendNotification", {Title = "Executed", Text = "Loading… Please wait", Subtext = "Kaitun Races By Centramil", Duration = 5})
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

local KaitunGuiStatusLabel
local KaitunGuiBlur
local guiVisible = true

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

    local CoinCard_1 = Instance.new("ScreenGui")
    local DropShadowHolder_1 = Instance.new("Frame")
    local Main_1 = Instance.new("Frame")
    local UICorner_1 = Instance.new("UICorner")
    local UIStroke_1 = Instance.new("UIStroke")
    local Divider_1 = Instance.new("Frame")
    local CharacterLabel = Instance.new("TextLabel")
    local LevelLabel_1 = Instance.new("TextLabel")
    local RaceLabel_1 = Instance.new("TextLabel")
    local BeliLabel_1 = Instance.new("TextLabel")
    local FragLabel_1 = Instance.new("TextLabel")
    local Top_1 = Instance.new("TextLabel")
    local UIGradient_1 = Instance.new("UIGradient")
    local UnderStats_1 = Instance.new("TextLabel")
    local UIGradient_2 = Instance.new("UIGradient")
    local UnderRace_1 = Instance.new("TextLabel")
    local UIGradient_3 = Instance.new("UIGradient")
    local RaceContainer = Instance.new("Frame")
    local DropShadow_1 = Instance.new("ImageLabel")

    CoinCard_1.Name = "KaitunRacesBF"
    CoinCard_1.Parent = COREGUI
    CoinCard_1.ResetOnSpawn = false
    CoinCard_1.DisplayOrder = 20

    DropShadowHolder_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadowHolder_1.BackgroundColor3 = Color3.fromRGB(163, 163, 163)
    DropShadowHolder_1.BackgroundTransparency = 1
    DropShadowHolder_1.Name = "DropShadowHolder"
    DropShadowHolder_1.Parent = CoinCard_1
    DropShadowHolder_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropShadowHolder_1.Size = UDim2.new(0, 620, 0, 390)
    DropShadowHolder_1.ZIndex = 1

    Main_1.AnchorPoint = Vector2.new(0.5, 0.5)
    Main_1.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    Main_1.BackgroundTransparency = 0.5
    Main_1.Name = "Main"
    Main_1.Parent = DropShadowHolder_1
    Main_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    Main_1.Size = UDim2.new(1, -47, 1, -47)

    UICorner_1.CornerRadius = UDim.new(0, 8)
    UICorner_1.Parent = Main_1

    UIStroke_1.Color = Color3.fromRGB(255, 80, 80)
    UIStroke_1.Thickness = 2.5
    UIStroke_1.Parent = Main_1

    Divider_1.BorderSizePixel = 0
    Divider_1.BackgroundColor3 = Color3.fromRGB(210, 210, 210)
    Divider_1.Name = "Divider"
    Divider_1.Parent = Main_1
    Divider_1.Position = UDim2.new(0.05, 0, 0.205, 0)
    Divider_1.Size = UDim2.new(0.90, 0, 0, 2)

    Top_1.BackgroundTransparency = 1
    Top_1.Name = "Top"
    Top_1.Parent = Main_1
    Top_1.AnchorPoint = Vector2.new(0.5, 0)
    Top_1.Position = UDim2.new(0.5, 0, 0.055, 0)
    Top_1.Size = UDim2.new(0.8, 0, 0, 24)
    Top_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    Top_1.Text = "Kaitun Races BF"
    Top_1.TextColor3 = Color3.fromRGB(255, 80, 80)
    Top_1.TextSize = 22
    Top_1.TextXAlignment = Enum.TextXAlignment.Center

    UIGradient_1.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
    }
    UIGradient_1.Parent = Top_1

    UnderStats_1.BackgroundTransparency = 1
    UnderStats_1.Name = "UnderStats"
    UnderStats_1.Parent = Main_1
    UnderStats_1.AnchorPoint = Vector2.new(0.5, 0)
    UnderStats_1.Position = UDim2.new(0.5, 0, 0.225, 2)
    UnderStats_1.Size = UDim2.new(0.4, 0, 0, 18)
    UnderStats_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    UnderStats_1.Text = "Account Stats"
    UnderStats_1.TextColor3 = Color3.fromRGB(255, 255, 255)
    UnderStats_1.TextSize = 16
    UnderStats_1.TextXAlignment = Enum.TextXAlignment.Center

    UIGradient_2.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
    }
    UIGradient_2.Parent = UnderStats_1

    local function setupCenterStat(lbl, yPos)
        lbl.BackgroundTransparency = 1
        lbl.Parent = Main_1
        lbl.AnchorPoint = Vector2.new(0.5, 0)
        lbl.Position = UDim2.new(0.5, 0, yPos, 0)
        lbl.Size = UDim2.new(0.82, 0, 0, 18)
        lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.TextSize = 16
        lbl.TextXAlignment = Enum.TextXAlignment.Center
        lbl.RichText = true
    end

    CharacterLabel.Name = "CharacterLabel"
    setupCenterStat(CharacterLabel, 0.285)
    CharacterLabel.Text = "Character: N/A"

    LevelLabel_1.Name = "LevelLabel"
    setupCenterStat(LevelLabel_1, 0.355)
    LevelLabel_1.Text = ""

    RaceLabel_1.Name = "RaceLabel"
    setupCenterStat(RaceLabel_1, 0.425)
    RaceLabel_1.Text = "Race: N/A"

    BeliLabel_1.Name = "BeliLabel"
    setupCenterStat(BeliLabel_1, 0.495)
    BeliLabel_1.Text = "Beli: N/A"

    FragLabel_1.Name = "FragLabel"
    setupCenterStat(FragLabel_1, 0.565)
    FragLabel_1.Text = "Frag: N/A"

    UnderRace_1.BackgroundTransparency = 1
    UnderRace_1.Name = "UnderRace"
    UnderRace_1.Parent = Main_1
    UnderRace_1.AnchorPoint = Vector2.new(0.5, 0)
    UnderRace_1.Position = UDim2.new(0.5, 0, 0.67, 0)
    UnderRace_1.Size = UDim2.new(0.45, 0, 0, 18)
    UnderRace_1.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    UnderRace_1.Text = "Race Progress (V3)"
    UnderRace_1.TextColor3 = Color3.fromRGB(255, 255, 255)
    UnderRace_1.TextSize = 16
    UnderRace_1.TextXAlignment = Enum.TextXAlignment.Center

    UIGradient_3.Color = ColorSequence.new{
        ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
        ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 80))
    }
    UIGradient_3.Parent = UnderRace_1

    RaceContainer.Name = "RaceContainer"
    RaceContainer.Parent = Main_1
    RaceContainer.BackgroundTransparency = 1
    RaceContainer.AnchorPoint = Vector2.new(0.5, 0)
    RaceContainer.Position = UDim2.new(0.5, 0, 0.735, 0)
    RaceContainer.Size = UDim2.new(0.88, 0, 0, 90)

    local raceGrid = Instance.new("UIGridLayout")
    raceGrid.Parent = RaceContainer
    raceGrid.CellSize = UDim2.new(0, 150, 0, 24)
    raceGrid.CellPadding = UDim2.new(0, 12, 0, 6)
    raceGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
    raceGrid.VerticalAlignment = Enum.VerticalAlignment.Top
    raceGrid.SortOrder = Enum.SortOrder.LayoutOrder

    DropShadow_1.AnchorPoint = Vector2.new(0.5, 0.5)
    DropShadow_1.BackgroundTransparency = 1
    DropShadow_1.Name = "DropShadow"
    DropShadow_1.Parent = DropShadowHolder_1
    DropShadow_1.Position = UDim2.new(0.5, 0, 0.5, 0)
    DropShadow_1.Size = UDim2.new(1, 47, 1, 47)
    DropShadow_1.ZIndex = 0
    DropShadow_1.Image = "rbxassetid://6015897843"
    DropShadow_1.ImageTransparency = 0.25
    DropShadow_1.ImageColor3 = Color3.fromRGB(0, 0, 0)

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
    DropShadow2Holder2_1.Size = UDim2.new(0, 320, 0, 55)

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
    MainStatus.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
    MainStatus.BackgroundTransparency = 0.5
    MainStatus.Position = UDim2.new(0.5, 0, 0.5, 0)
    MainStatus.Size = UDim2.new(1, -50, 1, -40)

    local UIStrokeStatus = Instance.new("UIStroke")
    UIStrokeStatus.Parent = MainStatus
    UIStrokeStatus.Color = Color3.fromRGB(233, 80, 80)
    UIStrokeStatus.Thickness = 2.5

    local UICornerStatus = Instance.new("UICorner")
    UICornerStatus.Parent = MainStatus
    UICornerStatus.CornerRadius = UDim.new(0, 6)

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Name = "StatusLabel"
    StatusLabel.Parent = MainStatus
    StatusLabel.AnchorPoint = Vector2.new(0.5, 0)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Position = UDim2.new(0.5, 0, 0.06, 0)
    StatusLabel.Size = UDim2.new(1, -20, 0, 34)
    StatusLabel.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
    StatusLabel.Text = "Status: nil"
    StatusLabel.TextColor3 = Color3.fromRGB(233, 80, 80)
    StatusLabel.TextSize = 20
    StatusLabel.TextWrapped = true
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Center

    KaitunGuiStatusLabel = StatusLabel

    local allV3 = {
        "Human V3",
        "Rabbit V3",
        "Shark V3",
        "Angel V3",
        "Ghoul V3",
        "Cyborg V3"
    }

    local raceColors = {
        ["Angel V3"] = Color3.fromRGB(255, 204, 0),
        ["Human V3"] = Color3.fromRGB(255, 50, 50),
        ["Shark V3"] = Color3.fromRGB(0, 168, 255),
        ["Cyborg V3"] = Color3.fromRGB(204, 0, 255),
        ["Ghoul V3"] = Color3.fromRGB(160, 255, 80),
        ["Rabbit V3"] = Color3.fromRGB(0, 255, 60),
    }

    local raceLabels = {}

    local function createRaceLabel(raceName, order)
        local lbl = Instance.new("TextLabel")
        lbl.Name = raceName:gsub("%s+", "")
        lbl.Parent = RaceContainer
        lbl.BackgroundTransparency = 1
        lbl.Size = UDim2.new(0, 150, 0, 24)
        lbl.FontFace = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)
        lbl.TextSize = 16
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.TextYAlignment = Enum.TextYAlignment.Center
        lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
        lbl.LayoutOrder = order
        lbl.RichText = true
        return lbl
    end

    for i, race in ipairs(allV3) do
        raceLabels[race] = createRaceLabel(race, i)
    end

    task.spawn(function()
        while task.wait(0.4) do
            pcall(function()
                if plr:FindFirstChild("Data") then
                    if plr.Data:FindFirstChild("Beli") then
                        BeliLabel_1.Text = "Beli: " .. tostring(plr.Data.Beli.Value)
                    end
                    if plr.Data:FindFirstChild("Fragments") then
                        FragLabel_1.Text = "Frag: " .. tostring(plr.Data.Fragments.Value)
                    end
                    if plr.Data:FindFirstChild("Race") then
                        RaceLabel_1.Text = "Race: " .. tostring(plr.Data.Race.Value)
                    end
                end

                CharacterLabel.Text = '<font color="#FFFFFF">Character: ' .. tostring(plr.Name) .. '</font>'
                LevelLabel_1.Text = ""

                local unlockedMap = ScanV3Titles(false)

                for _, race in ipairs(allV3) do
                    local has = unlockedMap[race] == true
                    local dot = has and "🟢" or "🔴"
                    local color = raceColors[race] or Color3.fromRGB(255, 255, 255)
                    local hex = string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
                    raceLabels[race].Text = dot .. ' <font color="' .. hex .. '">' .. race .. '</font>'
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
    local text = tostring(newText)
    SetStatus(text)
end

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

function IfTableHaveIndex(j)
    for _ in j do return true end
end

local LastServersDataPulled, CachedServers
function GetServers()
    if LastServersDataPulled then
        if os.time() - LastServersDataPulled < 60 then return CachedServers end
    end
    for i = 1, 100, 1 do
        local data = game:GetService("ReplicatedStorage"):WaitForChild("__ServerBrowser"):InvokeServer(i)
        if IfTableHaveIndex(data) then
            LastServersDataPulled = os.time()
            CachedServers = data
            return data
        end
    end
end

HopServer = function(Reason, MaxPlayers, ForcedRegion)
    local Servers = GetServers()
    local ArrayServers = {}
    MaxPlayers = MaxPlayers or 5
    for i, v in Servers do
        if v.Count <= MaxPlayers then
            table.insert(ArrayServers, {
                JobId = i,
                Players = v.Count,
                LastUpdate = v.__LastUpdate,
                Region = v.Region
            })
        end
    end
    local ServerData
    for i = 1, #ArrayServers do
        while task.wait() do
            local Index = math.random(1, #ArrayServers)
            ServerData = ArrayServers[Index]
            if ServerData then
                if not ForcedRegion or ServerData.Regoin == ForcedRegion then break end
            end
        end
        ReplicatedStorage:WaitForChild("__ServerBrowser"):InvokeServer('teleport', ServerData.JobId)
    end
end

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
                            HopServer(8)
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
            HopServer(10)
        end
    end
end)

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

            -- 1. Khi tất cả race bật đều đã V3 -> Ghi file và đổi folder
            if #enabledRaces > 0 and #missingRaces == 0 then
                WriteCompletedRaces("Upgrade Race V3 | Completed configured races")
                return
            end

            local isCurrentEnabled = table.find(enabledRaces, CurrentRace) ~= nil
            local isCurrentDone = titleMap[CurrentRace] == true

            local missingStandard = GetMissingEnabledFromOrder(STANDARD_RACE_ORDER, titleMap)
            local missingSpecial = GetMissingEnabledFromOrder(SPECIAL_RACE_ORDER, titleMap)

            -- 2. Nếu race hiện tại đã V3 hoặc đang tắt -> Cần đổi sang race khác
            if isCurrentDone or not isCurrentEnabled then
                -- Ưu tiên 1: Đổi/reroll tìm 4 race thường trước (Human, Mink, Fishman, Skypiea)
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
                                        SetText("Hop for Katakuri") task.wait(5) HopServer()
                                    end
                                end
                            end
                        else
                            SetText("Travel To Sea 3 for Fragments")
                            COMMF_:InvokeServer("TravelZou") task.wait(2)
                        end
                    end
                -- Ưu tiên 2: 4 race thường đã xong/tắt -> Đổi trực tiếp sang race đặc biệt (Cyborg/Ghoul)
                elseif #missingSpecial > 0 then
                    local targetSpecial = missingSpecial[1]
                    ChangeToSpecialRace(targetSpecial, "Standard races completed/off. Changing to special race")
                    task.wait(2)
                else
                    ScanV3Titles(true)
                end
            else
                -- 3. Race hiện tại đang BẬT và CHƯA V3 -> Tiến hành làm Quest V2 / V3
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
                                    for _, v2 in next, {workspace.Enemies, ReplicatedStorage} do
                                        for _, v in next, v2:GetChildren() do
                                            if table.find({"Jeremy", "Orbitus", "Diamond"}, v.Name) then
                                                repeat task.wait() KillMonster(v.Name)
                                                until not v:FindFirstChild("Humanoid") or v.Humanoid.Health <= 0
                                            end
                                        end
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
                                        SetText("Finding Skypiea Player") HopServer(10)
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
                                                SetText("Not Found Fruit, Hop Server") task.wait(3)
                                                HopServer(10)
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
