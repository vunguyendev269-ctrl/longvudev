--[[
    BANANAHUB RACE V2-V3 TITLE CONTROLLER
    Build: TITLE-CONTROLLER-UI-R4-COMPLETED-PREFIX

    Chức năng:
      1. Chọn/load team trước khi gọi BananaHub.
      2. Truyền getgenv().Key và getgenv().Config vào BananaHub.
      3. Check V3 bằng đúng phương pháp Title Name từ getTitles.
      4. Race true + chưa V3: giữ nguyên race để BananaHub làm V2-V3.
      5. Race false hoặc race true đã V3: đổi tiếp sang race true còn thiếu V3.
      6. Ưu tiên Human/Mink/Fishman/Skypiea; sau đó mới đổi trực tiếp Cyborg/Ghoul.
      7. Cyborg dùng CyborgTrainer Buy; Ghoul dùng Ectoplasm Change, không reroll.
      8. Khi tất cả race true đều V3:
         tạo <PlayerName>.txt theo số race được bật:
           - 1 race: Completed-<Race>
           - 2 race: Completed-2racev3
           - 3 race: Completed-3racev3
           - tương tự tới Completed-6racev3.
]]


-- [ CONTROLLER ]
-- ============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local CommF_ =
    ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CommF_")

-- Bảo vệ config khi loader bên ngoài chưa khởi tạo đủ table.
getgenv().Config = getgenv().Config or {}
getgenv().Races = getgenv().Races or {}

repeat
    task.wait(0.2)
until LocalPlayer:FindFirstChild("Data")
    and LocalPlayer.Data:FindFirstChild("Race")
    and LocalPlayer.Data:FindFirstChild("Fragments")

-- Dừng controller cũ nếu người dùng execute lại file.
if getgenv().__BANANA_RACE_V3_CONTROLLER_STOP then
    pcall(getgenv().__BANANA_RACE_V3_CONTROLLER_STOP)
end

local controllerRunning = true
local controllerCompleted = false
local lastStatus = nil

local ControllerUI = {
    ScreenGui = nil,
    MainFrame = nil,
    StatusLabel = nil,
    CurrentRaceLabel = nil,
    FragmentLabel = nil,
    PlayerV3Label = nil,
    RaceLabels = {},
}

local PlayerV3Loop = {
    status = "Waiting 30s",
    runCount = 0,
    lastRunAt = 0,
    nextRunAt = 0,
    stopped = false,
}

getgenv().__BANANA_RACE_V3_CONTROLLER_STOP = function()
    controllerRunning = false
end

local function SetControllerStatus(text)
    text = tostring(text)

    if lastStatus == text then
        return
    end

    lastStatus = text
    warn("[Race V3 Controller] " .. text)

    getgenv().BananaRaceV3ControllerStatus = text

    pcall(function()
        if ControllerUI.StatusLabel then
            ControllerUI.StatusLabel.Text = "Status: " .. text
        end
    end)
end

-- ============================================================
-- [ TEAM ]
-- BananaHub dùng Pirate/Marine.
-- Remote SetTeam dùng Pirates/Marines.
-- ============================================================

local function NormalizeBananaTeam(value)
    local normalized =
        tostring(value or "Pirate"):lower():gsub("[^%a]", "")

    if normalized == "marine" or normalized == "marines" then
        return "Marine", "Marines"
    end

    return "Pirate", "Pirates"
end

local bananaTeam, remoteTeam = NormalizeBananaTeam(getgenv().Team)
getgenv().Team = bananaTeam
getgenv().Config["Select Team"] = bananaTeam

local function ChooseTeam()
    if LocalPlayer.Team then
        return true
    end

    for attempt = 1, 20 do
        if LocalPlayer.Team then
            return true
        end

        pcall(function()
            CommF_:InvokeServer("SetTeam", remoteTeam)
        end)

        task.wait(0.5)

        if LocalPlayer.Team then
            return true
        end

        pcall(function()
            local main =
                PlayerGui:FindFirstChild("Main")
                or PlayerGui:FindFirstChild("Main (minimal)")
            local choose =
                main and main:FindFirstChild("ChooseTeam", true)
            local container =
                choose and choose:FindFirstChild("Container")
            local teamFrame =
                container and container:FindFirstChild(remoteTeam)
            local button =
                teamFrame
                and teamFrame:FindFirstChildWhichIsA(
                    "GuiButton",
                    true
                )

            if button then
                if firesignal then
                    firesignal(button.Activated)
                else
                    button:Activate()
                end
            end
        end)

        task.wait(0.5)
    end

    return LocalPlayer.Team ~= nil
end

SetControllerStatus("Choosing team: " .. remoteTeam)
ChooseTeam()

-- ============================================================
-- [ TITLE NAME V3 CHECKER - METHOD 02 ]
--
-- Chỉ kiểm tra exact title name trong getTitles:
--   Full Power
--   Godspeed
--   Warrior of the Sea
--   Perfect Being
--   Hell Hound
--   War Machine
--
-- Không dùng STT, obtainment, GUI, Wenlock hoặc scoring.
-- 3 lần scan đầu cách nhau 5 giây; sau đó cache 30 giây.
-- ============================================================

local TITLE_FAST_SCAN_INTERVAL = 5
local TITLE_FAST_SCAN_LIMIT = 3
local TITLE_SCAN_INTERVAL = 30

local TITLE_TARGETS = {
    {
        title = "Full Power",
        configRace = "Human",
        raceV3 = "Human V3",
    },
    {
        title = "Godspeed",
        configRace = "Mink",
        raceV3 = "Rabbit V3",
    },
    {
        title = "Warrior of the Sea",
        configRace = "Fishman",
        raceV3 = "Shark V3",
    },
    {
        title = "Perfect Being",
        configRace = "Skypiea",
        raceV3 = "Angel V3",
    },
    {
        title = "War Machine",
        configRace = "Cyborg",
        raceV3 = "Cyborg V3",
    },
    {
        title = "Hell Hound",
        configRace = "Ghoul",
        raceV3 = "Ghoul V3",
    },
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
    status = {},
    paths = {},
    remoteOk = false,
    remoteError = nil,
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
    if type(value) ~= "table" or depth > 10 then
        return
    end

    if visited[value] then
        return
    end

    visited[value] = true
    callback(value, path)

    for key, child in pairs(value) do
        if type(child) == "table" then
            WalkTables(
                child,
                path .. "[" .. tostring(key) .. "]",
                depth + 1,
                visited,
                callback
            )
        end
    end
end

local function NodeHasExactTitle(node, targetTitle)
    for key, value in pairs(node) do
        local normalizedKey = NormalizeText(key)

        if type(value) ~= "table"
            and TITLE_FIELDS[normalizedKey]
            and ExactTitleMatch(targetTitle, value)
        then
            return true
        end

        if type(key) == "string"
            and ExactTitleMatch(targetTitle, key)
        then
            return true
        end
    end

    return false
end

local function InvokeGetTitles(timeoutSeconds)
    local completed = false
    local okResult = false
    local dataResult = nil
    local errorResult = nil

    task.spawn(function()
        local ok, data = pcall(function()
            return CommF_:InvokeServer("getTitles")
        end)

        okResult = ok
        dataResult = ok and data or nil
        errorResult = ok and nil or tostring(data)
        completed = true
    end)

    local deadline = tick() + (tonumber(timeoutSeconds) or 2)

    repeat
        task.wait(0.05)
    until completed or tick() >= deadline

    if not completed then
        return false, nil, "getTitles timeout"
    end

    return okResult, dataResult, errorResult
end

local function ScanV3Titles(force)
    if titleCache.scanning then
        return titleCache.map
    end

    local requiredInterval = GetTitleScanInterval()

    if not force
        and titleCache.initialized
        and tick() - titleCache.lastScan < requiredInterval
    then
        return titleCache.map
    end

    titleCache.scanning = true

    local foundMap = {}
    local foundStatus = {}
    local foundPaths = {}

    local remoteOk, remoteData, remoteError =
        InvokeGetTitles(2)

    titleCache.remoteOk = remoteOk
    titleCache.remoteError = remoteError

    for _, target in ipairs(TITLE_TARGETS) do
        local paths = {}

        if remoteOk and type(remoteData) == "table" then
            WalkTables(
                remoteData,
                "getTitles",
                0,
                {},
                function(node, path)
                    if NodeHasExactTitle(node, target.title) then
                        table.insert(paths, path)
                    end
                end
            )
        end

        if #paths > 0 then
            foundMap[target.configRace] = true
            foundStatus[target.configRace] = "FOUND"
            foundPaths[target.configRace] = paths[1]
        else
            foundMap[target.configRace] = false
            foundStatus[target.configRace] = "NOT_FOUND"
        end
    end

    titleCache.map = foundMap
    titleCache.status = foundStatus
    titleCache.paths = foundPaths
    titleCache.lastScan = tick()
    titleCache.scanCount = titleCache.scanCount + 1
    titleCache.currentInterval = GetTitleScanInterval()
    titleCache.initialized = true
    titleCache.scanning = false

    getgenv().BananaRaceV3TitleDebug = {
        method = "EXACT_CHECKER_02_TITLE_NAME",
        fastScanInterval = TITLE_FAST_SCAN_INTERVAL,
        fastScanLimit = TITLE_FAST_SCAN_LIMIT,
        normalInterval = TITLE_SCAN_INTERVAL,
        scanCount = titleCache.scanCount,
        nextInterval = titleCache.currentInterval,
        lastScan = titleCache.lastScan,
        map = titleCache.map,
        status = titleCache.status,
        paths = titleCache.paths,
        remoteOk = titleCache.remoteOk,
        remoteError = titleCache.remoteError,
    }

    return titleCache.map
end

-- ============================================================
-- [ RACE CONTROLLER ]
-- ============================================================

local RACE_ORDER = {
    "Human",
    "Mink",
    "Fishman",
    "Skypiea",
    "Cyborg",
    "Ghoul",
}

-- Bốn race thường được ưu tiên hoàn thành trước.
-- Cyborg/Ghoul là race đặc biệt: khi cần tới chúng phải gọi remote đổi race,
-- tuyệt đối không reroll để mong ngẫu nhiên trúng.
local STANDARD_RACE_ORDER = {
    "Human",
    "Mink",
    "Fishman",
    "Skypiea",
}

local SPECIAL_RACE_ORDER = {
    "Cyborg",
    "Ghoul",
}

local RACE_ALIASES = {
    human = "Human",
    mink = "Mink",
    rabbit = "Mink",
    fishman = "Fishman",
    shark = "Fishman",
    skypiea = "Skypiea",
    angel = "Skypiea",
    cyborg = "Cyborg",
    ghoul = "Ghoul",
}

local function NormalizeRaceName(value)
    local normalized =
        tostring(value or ""):lower():gsub("[^%a]", "")

    return RACE_ALIASES[normalized] or tostring(value or "")
end

local function GetCurrentRace()
    local raceValue =
        LocalPlayer.Data
        and LocalPlayer.Data:FindFirstChild("Race")

    return NormalizeRaceName(raceValue and raceValue.Value or "")
end

local function GetFragments()
    local value =
        LocalPlayer.Data
        and LocalPlayer.Data:FindFirstChild("Fragments")

    return tonumber(value and value.Value) or 0
end

local function GetEnabledRaces()
    local result = {}

    for _, raceName in ipairs(RACE_ORDER) do
        if getgenv().Races[raceName] == true then
            table.insert(result, raceName)
        end
    end

    return result
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
    local missing = {}

    for _, raceName in ipairs(order) do
        if getgenv().Races[raceName] == true
            and titleMap[raceName] ~= true
        then
            missing[#missing + 1] = raceName
        end
    end

    return missing
end

local function JoinRaceNames(races)
    if type(races) ~= "table" or #races == 0 then
        return "none"
    end

    return table.concat(races, ", ")
end

-- ============================================================
-- [ UI HIỂN THỊ RACE V3 ]
-- ============================================================

local RACE_UI_NAMES = {
    Human = "Human V3",
    Mink = "Rabbit V3",
    Fishman = "Shark V3",
    Skypiea = "Angel V3",
    Cyborg = "Cyborg V3",
    Ghoul = "Ghoul V3",
}

local function GetControllerGuiParent()
    local ok, guiParent = pcall(function()
        if type(gethui) == "function" then
            return gethui()
        end

        return game:GetService("CoreGui")
    end)

    if ok and guiParent then
        return guiParent
    end

    return PlayerGui
end

local function CreateControllerUI()
    local guiParent = GetControllerGuiParent()

    pcall(function()
        local old = guiParent:FindFirstChild(
            "BananaRaceV3ControllerUI"
        )

        if old then
            old:Destroy()
        end
    end)

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BananaRaceV3ControllerUI"
    screenGui.ResetOnSpawn = false
    screenGui.DisplayOrder = 50
    screenGui.IgnoreGuiInset = false
    screenGui.Parent = guiParent

    local frame = Instance.new("Frame")
    frame.Name = "Main"
    frame.AnchorPoint = Vector2.new(1, 0.5)
    frame.Position = UDim2.new(1, -20, 0.5, 0)
    frame.Size = UDim2.fromOffset(310, 354)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = screenGui

    local frameCorner = Instance.new("UICorner")
    frameCorner.CornerRadius = UDim.new(0, 10)
    frameCorner.Parent = frame

    local frameStroke = Instance.new("UIStroke")
    frameStroke.Color = Color3.fromRGB(255, 190, 40)
    frameStroke.Thickness = 2
    frameStroke.Parent = frame

    local title = Instance.new("TextLabel")
    title.Name = "Title"
    title.Position = UDim2.fromOffset(12, 8)
    title.Size = UDim2.new(1, -52, 0, 30)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.Text = "BananaHub Race V3"
    title.TextSize = 19
    title.TextColor3 = Color3.fromRGB(255, 210, 70)
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local minimize = Instance.new("TextButton")
    minimize.Name = "Minimize"
    minimize.AnchorPoint = Vector2.new(1, 0)
    minimize.Position = UDim2.new(1, -8, 0, 8)
    minimize.Size = UDim2.fromOffset(32, 28)
    minimize.BackgroundColor3 = Color3.fromRGB(35, 35, 42)
    minimize.BorderSizePixel = 0
    minimize.Font = Enum.Font.GothamBold
    minimize.Text = "—"
    minimize.TextSize = 18
    minimize.TextColor3 = Color3.fromRGB(255, 255, 255)
    minimize.Parent = frame

    local minimizeCorner = Instance.new("UICorner")
    minimizeCorner.CornerRadius = UDim.new(0, 6)
    minimizeCorner.Parent = minimize

    local content = Instance.new("Frame")
    content.Name = "Content"
    content.Position = UDim2.fromOffset(10, 44)
    content.Size = UDim2.new(1, -20, 1, -54)
    content.BackgroundTransparency = 1
    content.Parent = frame

    local playerLabel = Instance.new("TextLabel")
    playerLabel.Name = "Player"
    playerLabel.Size = UDim2.new(1, 0, 0, 22)
    playerLabel.BackgroundTransparency = 1
    playerLabel.Font = Enum.Font.GothamSemibold
    playerLabel.Text =
        "Player: " .. tostring(LocalPlayer.Name)
    playerLabel.TextSize = 14
    playerLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
    playerLabel.TextXAlignment = Enum.TextXAlignment.Left
    playerLabel.Parent = content

    local currentRaceLabel = Instance.new("TextLabel")
    currentRaceLabel.Name = "CurrentRace"
    currentRaceLabel.Position = UDim2.fromOffset(0, 24)
    currentRaceLabel.Size = UDim2.new(1, 0, 0, 22)
    currentRaceLabel.BackgroundTransparency = 1
    currentRaceLabel.Font = Enum.Font.GothamSemibold
    currentRaceLabel.Text = "Current Race: ..."
    currentRaceLabel.TextSize = 14
    currentRaceLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
    currentRaceLabel.TextXAlignment = Enum.TextXAlignment.Left
    currentRaceLabel.Parent = content

    local fragmentLabel = Instance.new("TextLabel")
    fragmentLabel.Name = "Fragments"
    fragmentLabel.Position = UDim2.fromOffset(0, 48)
    fragmentLabel.Size = UDim2.new(1, 0, 0, 22)
    fragmentLabel.BackgroundTransparency = 1
    fragmentLabel.Font = Enum.Font.GothamSemibold
    fragmentLabel.Text = "Fragments: ..."
    fragmentLabel.TextSize = 14
    fragmentLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
    fragmentLabel.TextXAlignment = Enum.TextXAlignment.Left
    fragmentLabel.Parent = content

    local playerV3Label = Instance.new("TextLabel")
    playerV3Label.Name = "PlayerV3"
    playerV3Label.Position = UDim2.fromOffset(0, 72)
    playerV3Label.Size = UDim2.new(1, 0, 0, 22)
    playerV3Label.BackgroundTransparency = 1
    playerV3Label.Font = Enum.Font.GothamSemibold
    playerV3Label.Text = "PlayerV3: ..."
    playerV3Label.TextSize = 14
    playerV3Label.TextColor3 = Color3.fromRGB(150, 210, 255)
    playerV3Label.TextXAlignment = Enum.TextXAlignment.Left
    playerV3Label.Parent = content

    local divider = Instance.new("Frame")
    divider.Position = UDim2.fromOffset(0, 100)
    divider.Size = UDim2.new(1, 0, 0, 1)
    divider.BackgroundColor3 = Color3.fromRGB(75, 75, 85)
    divider.BorderSizePixel = 0
    divider.Parent = content

    local raceHeader = Instance.new("TextLabel")
    raceHeader.Position = UDim2.fromOffset(0, 108)
    raceHeader.Size = UDim2.new(1, 0, 0, 22)
    raceHeader.BackgroundTransparency = 1
    raceHeader.Font = Enum.Font.GothamBold
    raceHeader.Text = "Race V3 title status"
    raceHeader.TextSize = 15
    raceHeader.TextColor3 = Color3.fromRGB(255, 210, 70)
    raceHeader.TextXAlignment = Enum.TextXAlignment.Left
    raceHeader.Parent = content

    local raceLabels = {}

    for index, raceName in ipairs(RACE_ORDER) do
        local label = Instance.new("TextLabel")
        label.Name = raceName
        label.Position =
            UDim2.fromOffset(0, 132 + (index - 1) * 25)
        label.Size = UDim2.new(1, 0, 0, 23)
        label.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
        label.BackgroundTransparency = 0.25
        label.BorderSizePixel = 0
        label.Font = Enum.Font.GothamSemibold
        label.Text = "⚪ " .. RACE_UI_NAMES[raceName]
        label.TextSize = 14
        label.TextColor3 = Color3.fromRGB(200, 200, 205)
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = content

        local padding = Instance.new("UIPadding")
        padding.PaddingLeft = UDim.new(0, 8)
        padding.Parent = label

        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 5)
        corner.Parent = label

        raceLabels[raceName] = label
    end

    local statusLabel = Instance.new("TextLabel")
    statusLabel.Name = "Status"
    statusLabel.Position = UDim2.fromOffset(0, 286)
    statusLabel.Size = UDim2.new(1, 0, 0, 55)
    statusLabel.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    statusLabel.BackgroundTransparency = 0.2
    statusLabel.BorderSizePixel = 0
    statusLabel.Font = Enum.Font.GothamSemibold
    statusLabel.Text = "Status: Starting..."
    statusLabel.TextWrapped = true
    statusLabel.TextSize = 13
    statusLabel.TextColor3 = Color3.fromRGB(245, 245, 245)
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Center
    statusLabel.Parent = content

    local statusPadding = Instance.new("UIPadding")
    statusPadding.PaddingLeft = UDim.new(0, 8)
    statusPadding.PaddingRight = UDim.new(0, 8)
    statusPadding.Parent = statusLabel

    local statusCorner = Instance.new("UICorner")
    statusCorner.CornerRadius = UDim.new(0, 6)
    statusCorner.Parent = statusLabel

    local minimized = false

    minimize.MouseButton1Click:Connect(function()
        minimized = not minimized
        content.Visible = not minimized
        frame.Size =
            minimized
            and UDim2.fromOffset(310, 46)
            or UDim2.fromOffset(310, 354)
        minimize.Text = minimized and "+" or "—"
    end)

    ControllerUI.ScreenGui = screenGui
    ControllerUI.MainFrame = frame
    ControllerUI.StatusLabel = statusLabel
    ControllerUI.CurrentRaceLabel = currentRaceLabel
    ControllerUI.FragmentLabel = fragmentLabel
    ControllerUI.PlayerV3Label = playerV3Label
    ControllerUI.RaceLabels = raceLabels
end

local function UpdateControllerUI()
    if not ControllerUI.ScreenGui
        or not ControllerUI.ScreenGui.Parent
    then
        CreateControllerUI()
    end

    local currentRace = GetCurrentRace()
    local fragments = GetFragments()
    local titleMap = titleCache.map or {}

    if ControllerUI.CurrentRaceLabel then
        ControllerUI.CurrentRaceLabel.Text =
            "Current Race: " .. tostring(currentRace)
    end

    if ControllerUI.FragmentLabel then
        ControllerUI.FragmentLabel.Text =
            "Fragments: " .. tostring(fragments)
    end

    if ControllerUI.PlayerV3Label then
        local text = "PlayerV3: " .. tostring(PlayerV3Loop.status)

        if not PlayerV3Loop.stopped
            and PlayerV3Loop.nextRunAt > 0
        then
            local remain =
                math.max(0, math.floor(PlayerV3Loop.nextRunAt - tick()))

            text = text
                .. string.format(
                    " | next %d:%02d",
                    math.floor(remain / 60),
                    remain % 60
                )
        end

        if PlayerV3Loop.runCount > 0 then
            text = text .. " | ran " .. tostring(PlayerV3Loop.runCount)
        end

        ControllerUI.PlayerV3Label.Text = text
        ControllerUI.PlayerV3Label.TextColor3 =
            PlayerV3Loop.stopped
            and Color3.fromRGB(170, 170, 180)
            or Color3.fromRGB(150, 210, 255)
    end

    for _, raceName in ipairs(RACE_ORDER) do
        local label = ControllerUI.RaceLabels[raceName]

        if label then
            local done = titleMap[raceName] == true
            local enabled = getgenv().Races[raceName] == true
            local stateText = done and "DONE" or "MISSING"
            local configText = enabled and "ON" or "OFF"
            local icon = done and "🟢" or "🔴"

            label.Text =
                icon
                .. " "
                .. tostring(RACE_UI_NAMES[raceName])
                .. " | "
                .. stateText
                .. " | "
                .. configText

            label.TextColor3 =
                done
                and Color3.fromRGB(90, 255, 130)
                or (
                    enabled
                    and Color3.fromRGB(255, 100, 100)
                    or Color3.fromRGB(170, 170, 180)
                )
        end
    end

    if ControllerUI.StatusLabel then
        ControllerUI.StatusLabel.Text =
            "Status: "
            .. tostring(
                getgenv().BananaRaceV3ControllerStatus
                or "Starting..."
            )
    end
end

CreateControllerUI()

task.spawn(function()
    while controllerRunning do
        pcall(UpdateControllerUI)
        task.wait(0.5)
    end
end)

local completionFileWritten = false

local function GetCompletionFileContent()
    local enabledRaces = GetEnabledRaces()
    local enabledCount = #enabledRaces

    -- Nội dung file luôn phải bắt đầu bằng "Completed-".
    if enabledCount == 1 then
        return "Completed-" .. tostring(enabledRaces[1])
    end

    if enabledCount >= 2 then
        return "Completed-"
            .. tostring(enabledCount)
            .. "racev3"
    end

    return nil
end

local function WriteCompletedFile()
    if completionFileWritten then
        return true
    end

    local fileName = LocalPlayer.Name .. ".txt"
    local completionContent = GetCompletionFileContent()

    if not completionContent then
        SetControllerStatus(
            "Cannot write completion file: no enabled race"
        )
        return false
    end

    local ok, err = pcall(function()
        assert(
            type(writefile) == "function",
            "Executor does not support writefile"
        )

        writefile(fileName, completionContent)
    end)

    if ok then
        completionFileWritten = true
        controllerCompleted = true

        SetControllerStatus(
            "ALL ENABLED RACES COMPLETED | "
            .. fileName
            .. " = "
            .. completionContent
        )

        getgenv().BananaRaceV3ControllerCompleted = true
        getgenv().BananaRaceV3ControllerCompletionContent =
            completionContent
        return true
    end

    SetControllerStatus(
        "Failed to create completion file: " .. tostring(err)
    )

    return false
end

local lastRerollAt = 0
local REROLL_COOLDOWN = 3
local REROLL_COST = 3000

local function WaitForExactRace(targetRace, oldRace, timeoutSeconds)
    local deadline = tick() + (tonumber(timeoutSeconds) or 8)

    repeat
        task.wait(0.25)
    until not controllerRunning
        or GetCurrentRace() == targetRace
        or (
            oldRace ~= nil
            and GetCurrentRace() ~= oldRace
        )
        or tick() >= deadline

    return GetCurrentRace()
end

local function RerollRace(reason)
    if tick() - lastRerollAt < REROLL_COOLDOWN then
        return false
    end

    local fragments = GetFragments()

    if fragments < REROLL_COST then
        SetControllerStatus(
            tostring(reason)
            .. " | Need "
            .. tostring(REROLL_COST)
            .. " fragments | Current: "
            .. tostring(fragments)
        )
        return false
    end

    local oldRace = GetCurrentRace()
    lastRerollAt = tick()

    SetControllerStatus(
        tostring(reason)
        .. " | Rerolling standard race from "
        .. tostring(oldRace)
    )

    local ok, result = pcall(function()
        return CommF_:InvokeServer(
            "BlackbeardReward",
            "Reroll",
            "2"
        )
    end)

    if not ok then
        SetControllerStatus(
            "Reroll error: " .. tostring(result)
        )
        return false
    end

    local newRace = WaitForExactRace(nil, oldRace, 8)

    SetControllerStatus(
        "Reroll result: "
        .. tostring(oldRace)
        .. " -> "
        .. tostring(newRace)
    )

    return newRace ~= oldRace
end

local lastSpecialChangeAt = 0
local SPECIAL_CHANGE_COOLDOWN = 5
local specialChangeRunning = false

local function ChangeToSpecialRace(targetRace, reason)
    if targetRace ~= "Cyborg" and targetRace ~= "Ghoul" then
        return false
    end

    if specialChangeRunning then
        return false
    end

    if tick() - lastSpecialChangeAt < SPECIAL_CHANGE_COOLDOWN then
        return false
    end

    local oldRace = GetCurrentRace()
    if oldRace == targetRace then
        return true
    end

    specialChangeRunning = true
    lastSpecialChangeAt = tick()

    SetControllerStatus(
        tostring(reason)
        .. " | Changing "
        .. tostring(oldRace)
        .. " -> "
        .. tostring(targetRace)
    )

    local ok, resultA, resultB = pcall(function()
        if targetRace == "Cyborg" then
            -- Cyborg là race đặc biệt. Dùng trainer để mua/đổi sang Cyborg,
            -- KHÔNG dùng BlackbeardReward Reroll.
            return CommF_:InvokeServer("CyborgTrainer", "Buy"), nil
        end

        -- Ghoul đã mở thì BuyCheck xác nhận và Change đổi về Ghoul.
        -- Không gọi Buy ở controller V3 vì controller chỉ cần đổi race đã sở hữu.
        local buyCheck = CommF_:InvokeServer(
            "Ectoplasm",
            "BuyCheck",
            4
        )
        task.wait(0.35)
        local changeResult = CommF_:InvokeServer(
            "Ectoplasm",
            "Change",
            4
        )
        return buyCheck, changeResult
    end)

    if not ok then
        specialChangeRunning = false
        SetControllerStatus(
            "Change "
            .. tostring(targetRace)
            .. " error: "
            .. tostring(resultA)
        )
        return false
    end

    local newRace = WaitForExactRace(targetRace, oldRace, 8)
    specialChangeRunning = false

    if newRace == targetRace then
        SetControllerStatus(
            "Changed race successfully: "
            .. tostring(oldRace)
            .. " -> "
            .. tostring(newRace)
            .. " | Waiting BananaHub V2-V3"
        )
        return true
    end

    SetControllerStatus(
        "Could not change to "
        .. tostring(targetRace)
        .. " | Current: "
        .. tostring(newRace)
        .. " | Remote: "
        .. tostring(resultA)
        .. (
            resultB ~= nil
            and (" / " .. tostring(resultB))
            or ""
        )
    )

    return false
end

local function ControllerTick()
    local titleMap = ScanV3Titles(false)
    local enabled, missing =
        GetMissingEnabledRaces(titleMap)

    if #enabled == 0 then
        SetControllerStatus(
            "No race is enabled in getgenv().Races"
        )
        return
    end

    -- Giữ nguyên completion logic đã có sẵn.
    if #missing == 0 then
        WriteCompletedFile()
        return
    end

    local currentRace = GetCurrentRace()
    local currentEnabled =
        getgenv().Races[currentRace] == true
    local currentDone =
        titleMap[currentRace] == true

    local missingStandard =
        GetMissingEnabledFromOrder(
            STANDARD_RACE_ORDER,
            titleMap
        )
    local missingSpecial =
        GetMissingEnabledFromOrder(
            SPECIAL_RACE_ORDER,
            titleMap
        )

    getgenv().BananaRaceV3ControllerDebug = {
        currentRace = currentRace,
        currentEnabled = currentEnabled,
        currentDone = currentDone,
        enabled = enabled,
        missing = missing,
        missingStandard = missingStandard,
        missingSpecial = missingSpecial,
        fragments = GetFragments(),
        titleMap = titleMap,
        specialChangeRunning = specialChangeRunning,
    }

    -- Quy tắc trung tâm:
    -- Race ON + chưa V3 = đúng target, giữ nguyên để BananaHub nâng.
    if currentEnabled and not currentDone then
        SetControllerStatus(
            "TARGET RACE: "
            .. tostring(currentRace)
            .. " | Enabled + Missing V3"
            .. " | BananaHub upgrading"
        )
        return
    end

    -- Nếu còn race thường ON + thiếu V3, chỉ reroll để tìm một trong bốn
    -- Human/Mink/Fishman/Skypiea. Cyborg/Ghoul hiện tại dù OFF hay DONE
    -- cũng phải rời đi bằng reroll ở giai đoạn này.
    if #missingStandard > 0 then
        RerollRace(
            "Seeking enabled standard race missing V3: "
            .. JoinRaceNames(missingStandard)
            .. " | Current "
            .. tostring(currentRace)
            .. (
                currentEnabled and currentDone
                and " is enabled but already V3"
                or " is disabled"
            )
        )
        return
    end

    -- Bốn race đầu đã OFF hoặc DONE. Bây giờ mới xử lý race đặc biệt
    -- theo thứ tự Cyborg -> Ghoul. Không reroll ở giai đoạn này.
    local targetSpecial = missingSpecial[1]
    if targetSpecial then
        ChangeToSpecialRace(
            targetSpecial,
            "All enabled standard races are completed/off"
        )
        return
    end

    -- Trường hợp title map thay đổi giữa hai lần đọc: scan lại sớm thay vì
    -- reroll sai race hoặc ghi completion sai.
    ScanV3Titles(true)
end

pcall(function()
    ScanV3Titles(true)
end)

-- ============================================================
-- [ HUMAN V2 PLAYER SCRIPT LOOP ]
--
-- Race Human + đã V2 (Data.Race.Evolved) + chưa có title Full Power
-- => execute playerv3.lua.
-- Lần đầu 30 giây sau khi script khởi động, sau đó mỗi 5 phút.
-- Lượt nào không thỏa điều kiện thì bỏ qua nhưng vẫn poll tiếp,
-- cho tới khi Human đạt V3 thì dừng hẳn.
-- ============================================================

local PLAYER_V3_URL =
    "https://raw.githubusercontent.com/longvu26092007-eng/hellobeo/refs/heads/main/playerv3.lua"
local PLAYER_V3_FIRST_DELAY = 30
local PLAYER_V3_INTERVAL = 300

local function IsRaceEvolved()
    local raceValue =
        LocalPlayer.Data
        and LocalPlayer.Data:FindFirstChild("Race")

    return raceValue ~= nil
        and raceValue:FindFirstChild("Evolved") ~= nil
end

local function SetPlayerV3Status(text)
    PlayerV3Loop.status = tostring(text)
    warn("[PlayerV3 Loop] " .. PlayerV3Loop.status)

    getgenv().BananaPlayerV3LoopDebug = {
        url = PLAYER_V3_URL,
        status = PlayerV3Loop.status,
        runCount = PlayerV3Loop.runCount,
        lastRunAt = PlayerV3Loop.lastRunAt,
        nextRunAt = PlayerV3Loop.nextRunAt,
        stopped = PlayerV3Loop.stopped,
    }
end

local function ExecutePlayerV3()
    local ok, err = pcall(function()
        loadstring(game:HttpGet(PLAYER_V3_URL))()
    end)

    PlayerV3Loop.lastRunAt = tick()

    if ok then
        PlayerV3Loop.runCount = PlayerV3Loop.runCount + 1
        SetPlayerV3Status(
            "Executed #" .. tostring(PlayerV3Loop.runCount)
        )
    else
        SetPlayerV3Status("Execute error: " .. tostring(err))
    end
end

task.spawn(function()
    PlayerV3Loop.nextRunAt = tick() + PLAYER_V3_FIRST_DELAY
    SetPlayerV3Status("Armed, first check in 30s")

    while controllerRunning do
        while controllerRunning and tick() < PlayerV3Loop.nextRunAt do
            task.wait(1)
        end

        if not controllerRunning then
            break
        end

        PlayerV3Loop.nextRunAt = tick() + PLAYER_V3_INTERVAL

        local currentRace = GetCurrentRace()

        if currentRace ~= "Human" then
            SetPlayerV3Status(
                "Skip: current race is " .. tostring(currentRace)
            )
        elseif (titleCache.map or {})["Human"] == true then
            PlayerV3Loop.stopped = true
            SetPlayerV3Status("Stopped: Human V3 completed")
            break
        elseif not IsRaceEvolved() then
            SetPlayerV3Status("Skip: Human is still V1")
        else
            SetPlayerV3Status("Human V2 detected, executing")
            ExecutePlayerV3()
        end
    end

    if not PlayerV3Loop.stopped then
        PlayerV3Loop.stopped = true
        SetPlayerV3Status("Stopped: controller ended")
    end
end)

-- ============================================================
-- [ LOAD BANANAHUB ]
-- ============================================================

task.spawn(function()
    SetControllerStatus(
        "Loading BananaHub | Team: "
        .. bananaTeam
    )

    local ok, err = pcall(function()
        -- BananaHub nhận trực tiếp:
        -- getgenv().Team
        -- getgenv().Key
        -- getgenv().Config
        getgenv().__BANANA_SCRIPT_ROUTE = "bf_main"
        return loadstring(game:HttpGet(
            "https://banana-hub.xyz/loader/banana.lua"
        ))()
    end)

    if ok then
        SetControllerStatus("BananaHub loaded")
    else
        SetControllerStatus(
            "BananaHub load error: " .. tostring(err)
        )
    end
end)

task.wait(3)

task.spawn(function()
    while controllerRunning and not controllerCompleted do
        local ok, err = xpcall(
            ControllerTick,
            function(message)
                return debug.traceback(tostring(message))
            end
        )

        if not ok then
            SetControllerStatus(
                "Controller error: " .. tostring(err)
            )
        end

        task.wait(1)
    end
end)
