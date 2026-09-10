--[[
================================================================================
 KaitunV4 — CLEAN MAX (BEHAVIOR-PRESERVING) — PORT ĐẦY ĐỦ HÀNH VI TỪ FILE A
================================================================================
 NGUYÊN TẮC: File A (KaitunV4(2).lua) là SOURCE OF TRUTH về hành vi.
 File này GIỮ nguyên RUỘT (logic) từ bản đã kiểm thử, đồng thời dọn dead code và state nội bộ
 File A — cùng luồng, cùng điều kiện, cùng cách đọc/ghi file sync, cùng cách
 active ability (CommE:FireServer("ActivateAbility")), cùng trial/training/
 post-trial. Chỉ KHÁC ở chỗ: code gọn hơn, ít lỗi hơn, hot-path không HTTP,
 mọi InvokeServer quan trọng có timeout, không WaitForChild vô hạn, không tween
 leak, không spawn loop trong mỗi tick, mọi loop nền check Runtime.alive.

 NGUỒN TRỌNG TÀI: /curmain (server-side) chốt thứ tự main cho MỌI account.
 ĐỒNG BỘ ABILITY: file-based trong folder racev4_vunguyen/ (giờ Hà Nội UTC+7) —
 GIỐNG HỆT File A (KHÔNG dùng /firesignal /donedoor).
================================================================================
]]

--[[ ============================================================================
 [00] SERVICES
============================================================================ ]]
local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local TeleportService      = game:GetService("TeleportService")
local HttpService          = game:GetService("HttpService")
local Lighting             = game:GetService("Lighting")
local TweenService         = game:GetService("TweenService")
local RunService           = game:GetService("RunService")
local CollectionService    = game:GetService("CollectionService")
local VirtualInputManager  = game:GetService("VirtualInputManager")
local VirtualUser          = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer   -- có thể nil nếu executor inject trước khi player replicate (Ally2 load chậm)

--[[ ============================================================================
 [01] BOOTSTRAP — chờ client load, KHÔNG treo vô hạn (timeout 30s). (File A 5-12)
============================================================================ ]]
do
    if not game:IsLoaded() then game.Loaded:Wait() end
    local t0 = tick()
    repeat
        task.wait(0.1)
        -- FIX (user 2026-07-02): LocalPlayer cache ở trên có thể nil khi inject sớm → PHẢI gán lại
        -- CHÍNH biến module-level (trước đây chỉ gán vào biến 'lp' cục bộ → LocalPlayer kẹt nil vĩnh viễn
        -- → crash :99 LocalPlayer.Name, :850 OnTeleport). Refresh mỗi vòng cho tới khi có.
        LocalPlayer = Players.LocalPlayer or LocalPlayer
        local rem  = ReplicatedStorage:FindFirstChild("Remotes")
        local gui  = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
        local loadingScreen = gui and gui:FindFirstChild("LoadingScreen")
        if rem and LocalPlayer and gui and not loadingScreen then break end
    until (tick() - t0) > 30
    -- Chốt chặn cuối: KHÔNG cho chạy tiếp với LocalPlayer nil (nếu timeout mà vẫn chưa có → chờ dứt điểm).
    -- Poll thuần Players.LocalPlayer (KHÔNG dùng PlayerAdded:Wait vì nó trả player bất kỳ, không chắc là mình).
    while not LocalPlayer do
        task.wait(0.2)
        LocalPlayer = Players.LocalPlayer
    end
end

--[[ ============================================================================
 [02] CONFIG — sanitize + validate. CHỈ module này được sửa Config. (File A 46-60)
============================================================================ ]]
local Config = {}
do
    if not getgenv().Config then
        getgenv().Config = {
            ["Allies"]              = { LocalPlayer.Name },
            ["MainAccount"]         = { LocalPlayer.Name },
            ["Method"]              = "Kill Players After Trial",
            ["ResetAfterTrial"]     = true,
            ["Team"]                = "Marines",
            ["Gear"]                = "A-B-B",
            ["VIPServer"]           = false,
            ["Kick Moon"]           = true,
            ["Hop Server FullMoon"] = true,
        }
    end
    local raw = getgenv().Config

    -- File A: Gear phải đúng "X-Y-Z" (5 ký tự). Sai → "A-B-B".
    if not raw["Gear"] or #tostring(raw["Gear"]) ~= 5 then raw["Gear"] = "A-B-B" end

    local function cleanList(t)
        local out = {}
        for _, v in ipairs(t or {}) do
            if type(v) == "string" and v ~= "" then table.insert(out, v) end
        end
        return out
    end
    raw["Allies"]      = cleanList(raw["Allies"])
    raw["MainAccount"] = cleanList(raw["MainAccount"])
    if #raw["Allies"] == 0 then raw["Allies"] = { LocalPlayer.Name } end
    if #raw["MainAccount"] == 0 then raw["MainAccount"] = { LocalPlayer.Name } end

    -- File A 315: Team chỉ Marines/Pirates, mặc định Marines.
    if raw["Team"] ~= "Marines" and raw["Team"] ~= "Pirates" then raw["Team"] = "Marines" end

    Config.raw             = raw
    Config.allies          = raw["Allies"]
    Config.mains           = raw["MainAccount"]
    Config.team            = raw["Team"]
    Config.gear            = raw["Gear"]
    Config.method          = raw["Method"] or "Kill Players After Trial"
    Config.resetAfterTrial = raw["ResetAfterTrial"] ~= false
    Config.vipServer       = raw["VIPServer"] == true
    Config.kickMoon        = raw["Kick Moon"] ~= false
    Config.hopFullMoon     = raw["Hop Server FullMoon"] ~= false
    -- File A 65: mặc định server LOCAL.
    Config.baseUrl         = getgenv().API_URL or "http://127.0.0.1:20425"
    Config.myName          = LocalPlayer.Name

    -- [STANDARD PATCH] Expose geometry-derived FFA observer margins without changing defaults/flow.
    -- Loader may set:
    --   getgenv().FFA_ZONE = { innerMargin=70, outerMargin=160, innerMarginY=40, outerMarginY=90 }
    -- Invalid/missing values fall back to the exact previous defaults; outer is always > inner.
    do
        local rawZone = getgenv().FFA_ZONE
        if type(rawZone) ~= "table" then rawZone = {} end
        local inner  = tonumber(rawZone.innerMargin)  or 70
        local outer  = tonumber(rawZone.outerMargin)  or 160
        local innerY = tonumber(rawZone.innerMarginY) or 40
        local outerY = tonumber(rawZone.outerMarginY) or 90
        if inner <= 0 then inner = 70 end
        if innerY <= 0 then innerY = 40 end
        if outer <= inner then outer = math.max(160, inner + 1) end
        if outerY <= innerY then outerY = math.max(90, innerY + 1) end
        Config.ffaZone = {
            innerMargin = inner,
            outerMargin = outer,
            innerMarginY = innerY,
            outerMarginY = outerY,
        }
    end

    -- File A 16-17
    Config.SEA3_PLACEIDS = { [7449423635] = true, [100117331123089] = true }
    Config.SEA2_PLACEIDS = { [4442272183] = true, [79091703265657] = true }

    -- hằng số nhịp (gom 1 chỗ cho dễ chỉnh)
    Config.HOP_THROTTLE       = 5      -- File A TeleportManager throttle jobid
    Config.JOB_REVISIT_TTL    = 3600   -- File A 2185
    Config.FULLMOON_TTL       = 5      -- File A 2159
    Config.STATUS_TTL         = 3      -- File A 319
    Config.CURMAIN_INTERVAL   = 0.7    -- File A 517
    Config.HEARTBEAT_INTERVAL = 5      -- File A 388-396
    Config.MAIN_TICK          = 0.35   -- File A 1678
    Config.UI_THROTTLE        = 0.2    -- File A live status 0.2s
    Config.DEAD_JOB_TTL       = 1800   -- File A 2175
    Config.MAIN_TURN_TIMEOUT  = 300    -- File A 1752
    Config.TRIAL_ACTIVE_TIMEOUT = 60   -- timeout riêng cho một lần Trial Race (không phải toàn lượt Main)
    Config.TRAIN_WINDOW       = 300    -- File A 1612
    Config.HELPRESET_TIMEOUT  = 25     -- File A 2005
    -- CLEAN JOIN: fullmoon-join LUÔN do server + 2 Ally điều phối (bỏ tự-hop). Method chỉ là hành vi sau trial.
    Config.scout              = true
    Config.RALLY_HOP_THROTTLE = 5      -- giây: chống spam teleport tới 1 jobid
    Config.FM_JOIN_BACKOFF    = 8      -- giây: sau khi hop vào FM gặp GameFull (server đầy) → ngừng spam join, chờ slot
    Config.MOON_CONCURRENT_MAX = 5     -- stt tối đa được "moon"/spam-join cùng lúc (stt1=Main1 ready; stt2-5 moon). >5 → waiting chờ slot

    -- ===== FEATURE FLAGS CLIENT — protocol V2 MẶC ĐỊNH BẬT =====
    -- Event protocol client (gửi /event critical FIFO + /sync long-poll). MẶC ĐỊNH BẬT.
    --   Client tự fallback route cũ (/curmain 0.7s + /helpreset + /lockmoon) nếu server trả disabled/404/lỗi liên tục.
    --   Tắt tay: getgenv().ENABLE_EVENT_PROTOCOL=false.
    Config.enableEventProtocol = getgenv().ENABLE_EVENT_PROTOCOL ~= false  -- MẶC ĐỊNH true
    Config.enableLongPoll       = getgenv().ENABLE_LONG_POLL ~= false       -- MẶC ĐỊNH true
end

--[[ ============================================================================
 [02b] URL/QUERY HELPER + nonEmpty — encode query an toàn; chuẩn hoá jobid từ server.
============================================================================ ]]
local function urlEncode(v)
    return HttpService:UrlEncode(tostring(v or ""))
end
local function makeQuery(params)
    local parts = {}
    for k, v in pairs(params or {}) do
        table.insert(parts, urlEncode(k) .. "=" .. urlEncode(v))
    end
    return table.concat(parts, "&")
end
local function endpoint(path, params)
    if params then
        return Config.baseUrl .. path .. "?" .. makeQuery(params)
    end
    return Config.baseUrl .. path
end
local function nonEmpty(v)
    v = tostring(v or "")
    if v == "" or v == "nil" or v == "null" then return nil end
    return v
end

--[[ ============================================================================
 [03] DIAGNOSTICS / LOGGER
============================================================================ ]]
-- Diagnostics là state quan sát nội bộ. Mỗi lần ghi vẫn mirror sang _G để giữ
-- tương thích UI/executor cũ, nhưng core không còn phụ thuộc trực tiếp vào _G.
local _diagnosticsData = {}
local Diagnostics = setmetatable({}, {
    __index = function(_, key)
        return _diagnosticsData[key]
    end,
    __newindex = function(_, key, value)
        _diagnosticsData[key] = value
        rawset(_G, key, value)
    end,
})

local DIAGNOSTIC_KEYS = {
    "dbgLog", "dbgSeq", "statusnow", "lastRaceI", "lastDoorDist",
    "lastDoorSrc", "lastSameSrv", "lastDoorName", "lastDoorTouchReason",
    "netDiag", "netGetOk", "netPostOk", "fullStatus",
}
for _, key in ipairs(DIAGNOSTIC_KEYS) do
    Diagnostics[key] = rawget(_G, key)
end

-- RuntimeState owns mutable coordination flags that used to be scattered across _G.
-- The bridge mirrors writes to the legacy global names and observes external writes,
-- preserving compatibility while giving the core one explicit state owner.
local _runtimeStateData = {}
local RuntimeState = setmetatable({}, {
    __index = function(_, key)
        local externalValue = rawget(_G, key)
        if externalValue ~= nil and externalValue ~= _runtimeStateData[key] then
            _runtimeStateData[key] = externalValue
        end
        return _runtimeStateData[key]
    end,
    __newindex = function(_, key, value)
        _runtimeStateData[key] = value
        rawset(_G, key, value)
    end,
})

local RUNTIME_STATE_KEYS = {
    "teamReadyAt", "trainKills", "trialableStreak", "fmJoinBackoffUntil",
    "trainWinStart", "trainNeedStreak", "inTrial", "allyLastFire",
    "uncertainStreak", "allyHopArmedT", "myFireEpoch", "syncStart",
    "allyKillReset", "teamLostAt", "myTurnStart", "_tsCacheValue",
    "trainHopArmedT", "rallyHopArmedT", "myDoorReady", "myStartEpoch",
    "didTrialInFM", "checkDoneForJob", "trainCheckLastT",
    "_deathGuardConnection", "_tsCacheTime", "lastTempleReparent",
    "lastReqEntrance", "lastRallyJob", "trainGrindLastT", "templeDoorOK",
    "isAllyLeader", "__leaderOnFmLost", "__leaderSetTarget",
    "trainingHopped", "changeFileWritten", "mainDoneValidatedRace", "loopTick", "loopLastT",
    "minkLastTrial", "minkStartPoint", "skyFinish", "checkJobId",
    "firstLoopHit", "jobidinput", "gameReady", "isScoutAlly",
}
for _, key in ipairs(RUNTIME_STATE_KEYS) do
    RuntimeState[key] = rawget(_G, key)
end

--[[ ============================================================================
 [03] LOGGER / DEBUG — ring buffer 200 dòng, chống spam cùng key 15s. (File A 1331-1368)
============================================================================ ]]
local Logger = {}
do
    Logger.logs = {}
    Diagnostics.dbgLog = Logger.logs
    Diagnostics.dbgSeq = 0
    Logger._lastKey = {}
    local MAX, SPAM_TTL = 200, 15

    -- giờ: mặc định os.time; ServerSync gắn clock server sau khi init (serverNow).
    Logger.timeFn = function() return (os and os.time and os.time()) or tick() end

    function Logger.log(msg, level, key)
        level = level or "info"
        key   = key or tostring(msg)
        local t = tick()
        if Logger._lastKey[key] and (t - Logger._lastKey[key]) < SPAM_TTL then return end
        Logger._lastKey[key] = t
        Diagnostics.dbgSeq = Diagnostics.dbgSeq + 1
        local hm = "--:--:--"
        pcall(function()
            local base = Logger.timeFn()
            local s = math.floor(base + 7 * 3600) % 86400   -- giờ Việt Nam (UTC+7)
            hm = string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
        end)
        Logger.logs[#Logger.logs + 1] = { seq = Diagnostics.dbgSeq, text = "[" .. hm .. "] " .. tostring(msg), level = level }
        while #Logger.logs > MAX do table.remove(Logger.logs, 1) end
        if level == "err" or level == "warn" then warn("[KaitunV4] " .. tostring(msg)) end
    end
    function Logger.info(m, k) Logger.log(m, "info", k) end
    function Logger.ok(m, k)   Logger.log(m, "ok", k) end
    function Logger.warn(m, k) Logger.log(m, "warn", k) end
    function Logger.err(m, k)  Logger.log(m, "err", k) end
end

-- DBG/status: tương thích tên File A (một số chỗ port giữ nguyên cách gọi).
local function DBG(msg, level, key) Logger.log(msg, level, key) end

local Safe = {}
function Safe.call(label, fn, ...)
    local ok, result = pcall(fn, ...)
    if not ok then
        Logger.warn("[SAFE] " .. tostring(label) .. ": " .. tostring(result), "safe_" .. tostring(label))
        return false, result
    end
    return true, result
end
function Safe.disconnect(connection, label)
    if not connection then return true end
    local ok, err = pcall(function() connection:Disconnect() end)
    if not ok then
        Logger.warn("[SAFE] disconnect " .. tostring(label or "connection") .. ": " .. tostring(err),
            "safe_disconnect_" .. tostring(label or "connection"))
    end
    return ok
end

--[[ ============================================================================
 [04] RUNTIME / LIFECYCLE — alive flag, teleport guard, offline-once. (File A 362-456)
============================================================================ ]]
local Runtime = {
    alive        = true,
    teleporting  = false,
    startedAt    = tick(),
    _offlineSent = false,
    _started     = false,
    startedModules = {},
}
function Runtime.stop(reason)
    Runtime.alive = false
    Logger.warn("Runtime.stop: " .. tostring(reason), "runtime_stop")
end

--[[ ============================================================================
 [05] STATUS — Diagnostics.statusnow + đẩy vào Debug log (File A 1357-1368)
============================================================================ ]]
local function status(v)
    Diagnostics.statusnow = tostring(v)
        .. ((Diagnostics.lastRaceI ~= nil) and ("  [i=" .. tostring(Diagnostics.lastRaceI) .. "]") or "")
        .. ((Diagnostics.lastDoorDist ~= nil) and ("  [d=" .. tostring(math.floor(Diagnostics.lastDoorDist))
            .. (Diagnostics.lastDoorSrc or "?") .. (Diagnostics.lastSameSrv and "/same" or "/diff") .. "]") or "")
    local sv = tostring(v)
    local lvl = "info"
    if sv:find("Lỗi") or sv:find("⚠") or sv:find("FAIL") or sv:find("Died") then lvl = "err"
    elseif sv:find("Doing trial") or sv:find("DONE") or sv:find("Ready") or sv:find("Kill Players") then lvl = "ok" end
    DBG(sv, lvl, sv)
end

--[[ ============================================================================
 [06] FILESTORE — read/write JSON an toàn, reset file khi decode fail.
============================================================================ ]]
local FileStore = {}
function FileStore.readJson(path, default)
    if not (isfile and isfile(path)) then return default end
    local ok, data = pcall(function() return HttpService:JSONDecode(readfile(path)) end)
    if ok and type(data) == "table" then return data end
    pcall(function() writefile(path, "{}") end)
    Logger.warn("FileStore decode fail, reset: " .. path, "fs_reset_" .. path)
    return default
end
function FileStore.writeJson(path, tbl)
    local ok = pcall(function() writefile(path, HttpService:JSONEncode(tbl or {})) end)
    if not ok then Logger.err("FileStore write fail: " .. path, "fs_write_" .. path) end
    return ok
end

--[[ ============================================================================
 [06b] LEGACY CLEANUP
============================================================================ ]]
-- ChangeFolder/Disconnect/Shutdown sau khi DONE đã bị loại khỏi runtime.
-- Không giữ dead hook trong core để tránh vô tình bật lại flow cũ.

-- File A 1-3: xoá cache module cũ (giờ module nhúng thẳng).
pcall(function()
    if isfile and isfile("kaitun_module_bf.lua") and delfile then delfile("kaitun_module_bf.lua") end
end)

--[[ ============================================================================
 [07] NETCLIENT — production HTTP: semaphore GET/POST riêng, retry, cache,
      POST queue O(1) qHead/qTail + coalesce theo key. (File A 75-257)
============================================================================ ]]
local Net = {}
do
    local httprequest = (syn and syn.request)
        or (http and http.request)
        or http_request
        or request
        or (fluxus and fluxus.request)
        or (krnl and krnl.request)
    Net.hasReq = httprequest ~= nil

    Net.logs = {}
    function Net.log(level, msg)
        local line = ("[NET][%s] %s"):format(level, tostring(msg))
        table.insert(Net.logs, line)
        if #Net.logs > 200 then table.remove(Net.logs, 1) end
        if level == "ERR" or level == "WARN" then Logger.warn(line, "net_" .. line:sub(1, 24)) end
    end

    -- 2 semaphore RIÊNG cho GET và POST (File A 97-112)
    local function makeSem(max)
        local cur = 0
        local function acquire()
            local guard = 0
            while cur >= max do
                task.wait(0.03)
                guard = guard + 1
                if guard > 400 then break end -- ~12s thì thôi chờ
            end
            cur = cur + 1
        end
        local function release() cur = math.max(0, cur - 1) end
        return acquire, release
    end
    local acquireGet, releaseGet   = makeSem(4)
    local acquirePost, releasePost = makeSem(4)

    -- request thô: trả ok(bool), status(number), body(string), err (File A 115-143)
    local function rawRequest(method, url, bodyStr)
        if httprequest then
            local res
            local ok, err = pcall(function()
                res = httprequest({
                    Url = url,
                    Method = method,
                    Headers = (method == "POST") and { ["Content-Type"] = "application/json" } or nil,
                    Body = (method == "POST") and bodyStr or nil,
                })
            end)
            if not ok then return false, 0, nil, tostring(err) end
            if type(res) ~= "table" then return false, 0, nil, "no response table" end
            local code = res.StatusCode or res.status_code or res.Status or 0
            local body = res.Body or res.body
            local success = res.Success
            if success == nil then success = (code >= 200 and code < 300) end
            if success then return true, code, body, nil end
            return false, code, body, "http " .. tostring(code)
        else
            if method ~= "GET" then return false, 0, nil, "executor không có hàm request cho POST" end
            local body
            local ok, err = pcall(function() body = game:HttpGet(url) end)
            if ok and body then return true, 200, body, nil end
            return false, 0, nil, tostring(err)
        end
    end
    Net.raw = rawRequest

    -- GET đồng bộ + retry + cache (File A 145-186)
    local cache = {}
    local GET_RETRIES = 3
    function Net.getRaw(url)
        acquireGet()
        local ok, status_, body, err
        for attempt = 1, GET_RETRIES do
            ok, status_, body, err = rawRequest("GET", url, nil)
            if ok then break end
            Net.log("WARN", ("GET fail %d/%d %s : %s"):format(attempt, GET_RETRIES, url, tostring(err)))
            task.wait(0.2 * attempt)
        end
        releaseGet()
        if not ok then Net.log("ERR", "GET bỏ cuộc: " .. url) end
        return ok, body, status_
    end
    function Net.getJSON(url, ttl)
        ttl = ttl or 0
        if ttl > 0 then
            local c = cache[url]
            if c and c.decoded ~= nil and (tick() - c.t) < ttl then return c.decoded end
        end
        local ok, body = Net.getRaw(url)
        if not ok or not body then return nil end
        local good, decoded = pcall(function() return HttpService:JSONDecode(body) end)
        if not good then Net.log("ERR", "JSON decode fail: " .. url); return nil end
        if ttl > 0 then cache[url] = { t = tick(), decoded = decoded } end
        return decoded
    end
    function Net.text(url, ttl)
        ttl = ttl or 0
        if ttl > 0 then
            local c = cache[url]
            if c and c.raw ~= nil and (tick() - c.t) < ttl then return c.raw end
        end
        local ok, body = Net.getRaw(url)
        if not ok then return nil end
        if ttl > 0 then cache[url] = { t = tick(), raw = body } end
        return body
    end

    -- POST: hàng đợi VÒNG O(1) qHead/qTail + worker + retry + coalesce (File A 191-252)
    -- FIX 4b (user 2026-07-02): mainstatus có hàng đợi RIÊNG + 1 worker DUY NHẤT → gửi FIFO tuần tự,
    -- không còn 4 worker chạy đua ghi đè lệch thứ tự. Các POST khác vẫn dùng postQ + 4 worker chung.
    local postQ  = {}  -- hàng đợi chung (mọi key trừ "mainstatus")
    local statusQ = {} -- hàng đợi riêng CHỈ cho mainstatus (1 worker tuần tự)
    local qHead = 1;  local qTail = 0
    local sqHead = 1; local sqTail = 0
    local keyed = {}  -- key -> job mới nhất
    local MAX_Q = 800
    local POST_RETRIES = 6
    local function qPush(job)
        qTail = qTail + 1
        postQ[qTail] = job
    end
    local function qPop()
        if qHead > qTail then return nil end
        local job = postQ[qHead]
        postQ[qHead] = nil
        qHead = qHead + 1
        if qHead > qTail then qHead, qTail = 1, 0 end
        return job
    end
    local function sqPush(job)
        sqTail = sqTail + 1
        statusQ[sqTail] = job
    end
    local function sqPop()
        if sqHead > sqTail then return nil end
        local job = statusQ[sqHead]
        statusQ[sqHead] = nil
        sqHead = sqHead + 1
        if sqHead > sqTail then sqHead, sqTail = 1, 0 end
        return job
    end
    function Net.postJSON(url, tbl, key)
        local bodyStr
        local ok = pcall(function() bodyStr = HttpService:JSONEncode(tbl or {}) end)
        if not ok then Net.log("ERR", "JSON encode fail: " .. url); return end
        local job = { url = url, body = bodyStr, key = key, attempts = 0 }
        if key then
            local old = keyed[key]
            if old then old.replaced = true end
            keyed[key] = job
        end
        if key == "mainstatus" then
            -- hàng đợi riêng: 1 worker tuần tự → không out-of-order
            if (sqTail - sqHead + 1) >= MAX_Q then sqPop() end
            sqPush(job)
        else
            if (qTail - qHead + 1) >= MAX_Q then
                qPop()
                Net.log("WARN", "postQ tràn, bỏ job cũ nhất")
            end
            qPush(job)
        end
    end

    local function runJob(job, popKeyed)
        acquirePost()
        local sok, _, _, err = rawRequest("POST", job.url, job.body)
        releasePost()
        if sok then
            if job.key and keyed[job.key] == job then keyed[job.key] = nil end
        else
            job.attempts = job.attempts + 1
            if (not job.replaced) and job.attempts < POST_RETRIES then
                Net.log("WARN", ("POST retry %d/%d %s : %s"):format(job.attempts, POST_RETRIES, job.url, tostring(err)))
                task.wait(0.3 * job.attempts)
                popKeyed(job)
            elseif not job.replaced then
                Net.log("ERR", ("POST bỏ sau %d lần: %s"):format(job.attempts, job.url))
                if job.key and keyed[job.key] == job then keyed[job.key] = nil end
            end
        end
    end

    -- [FINAL §8.1] Net.postJSONSync — POST JSON ĐỒNG BỘ, đọc body + decode, trả ACK thật.
    --   return: ok(bool), decoded(table|nil), statusCode(number), errorMessage(string|nil)
    --   KHÁC postJSON (fire-and-forget): dùng cho CRITICAL event cần ACK. KHÔNG coi 200-body-sai là ok.
    --   Có semaphore để không mở quá nhiều request đồng thời, nhưng KHÔNG block MainTick (gọi trong worker riêng).
    function Net.postJSONSync(url, payload, timeoutSeconds)
        local bodyStr
        local encOk = pcall(function() bodyStr = HttpService:JSONEncode(payload or {}) end)
        if not encOk then return false, nil, 0, "json_encode_fail" end
        acquirePost()
        -- [§XXIII-13] TIMEOUT HỮU HẠN: chạy request trong thread con, thread chính chờ tối đa timeoutSeconds.
        --   httprequest yield trong thread con; nếu quá hạn → trả timeout cho caller (KHÔNG treo worker vô hạn).
        local tmo = tonumber(timeoutSeconds) or 8
        if not (tmo > 0) then tmo = 8 end
        local done, ok, status_, respBody, err = false, nil, nil, nil, nil
        task.spawn(function()
            local a, b, c, d = rawRequest("POST", url, bodyStr)
            ok, status_, respBody, err = a, b, c, d
            done = true
        end)
        local t0 = tick()
        while not done and (tick() - t0) < tmo do task.wait() end
        releasePost()
        if not done then return false, nil, 0, "post_timeout" end
        if not ok then return false, nil, status_ or 0, tostring(err or "request_fail") end
        -- HTTP status ngoài 2xx → coi là lỗi (server disabled trả 4xx…)
        if status_ and (status_ < 200 or status_ >= 300) then
            -- vẫn thử decode để lấy reason (vd disabled/404 body JSON)
            local d2 = nil
            pcall(function() d2 = HttpService:JSONDecode(respBody or "") end)
            return false, d2, status_, "http_" .. tostring(status_)
        end
        if type(respBody) ~= "string" or #respBody == 0 then
            return false, nil, status_ or 0, "empty_body"
        end
        local decoded
        local decOk = pcall(function() decoded = HttpService:JSONDecode(respBody) end)
        if not decOk or type(decoded) ~= "table" then
            return false, nil, status_ or 0, "json_decode_fail"
        end
        return true, decoded, status_ or 200, nil
    end
    -- [FINAL §10] Net.getJSONSync — GET JSON đồng bộ đọc body (dùng cho /sync long-poll + /curmain fallback).
    function Net.getJSONSync(url)
        acquireGet()
        local ok, status_, respBody, err = rawRequest("GET", url, nil)
        releaseGet()
        if not ok then return false, nil, status_ or 0, tostring(err or "request_fail") end
        if status_ and (status_ < 200 or status_ >= 300) then
            return false, nil, status_, "http_" .. tostring(status_)
        end
        if type(respBody) ~= "string" or #respBody == 0 then return false, nil, status_ or 0, "empty_body" end
        local decoded
        local decOk = pcall(function() decoded = HttpService:JSONDecode(respBody) end)
        if not decOk or type(decoded) ~= "table" then return false, nil, status_ or 0, "json_decode_fail" end
        return true, decoded, status_ or 200, nil
    end

    local function worker()
        while Runtime.alive do
            local job = qPop()
            if not job or job.replaced then task.wait(0.05)
            else runJob(job, qPush) end
        end
    end
    -- 1 worker tuần tự DUY NHẤT cho mainstatus → đảm bảo FIFO, không race
    local function statusWorker()
        while Runtime.alive do
            local job = sqPop()
            if not job or job.replaced then task.wait(0.05)
            else runJob(job, sqPush) end
        end
    end
    for _ = 1, 4 do task.spawn(worker) end
    task.spawn(statusWorker)

    Net.log("INFO", "Net init — hasReq=" .. tostring(Net.hasReq))
end

--[[ ============================================================================
 [08] STATESTORE — status/job cache (hot-path cache-only), role info. (File A 259-359)
============================================================================ ]]
local State = {}
do
    State.myName          = Config.myName
    State.myRole          = "unknown"
    State.myMainIndex     = nil
    State.isAlly          = {}
    State.isMain          = {}     -- = isaccmain File A
    State.mainIndexOf     = {}
    State.statusCache     = {}     -- name -> { t, status }  (File A 318)
    State.mainJobCache    = {}     -- name -> { jobid, time, t } (File A 460)
    State.serverMainOrder = nil    -- _G.srvMainOrder
    State.serverCurMain   = nil    -- _G.srvCurMain
    State.serverCurJobid  = nil    -- _G.srvCurMainJobid
    State._lastCurMainOK  = 0
    -- CLEAN JOIN: field điều hướng do server /curmain trả
    State.fullmoonLocked    = false
    State.gateOpenedOnce    = false
    State.gateOpen          = false
    State.trialPhase        = "idle"
    State.fullmoonJobid     = nil
    State.allyTargetJobid   = nil
    State.main1Name         = nil
    State.requiredAllies    = 2
    State.fullmoonAllyCount = 0
    State.candidateAllyCount= 0
    State.joinSpamInterval  = 5
    State.mainJoinTimeout   = 45
    State.partyOrder        = {}
    State.allyLeader        = nil
    State.lastScoutSignalAt = 0
    -- CLEAN JOIN: chống "chưa trial đã done" — chỉ set done/training khi thật sự đã vào trial lượt này
    State.didEnterTrialThisTurn = false
    State.trialStartedAt        = 0
    State.trialStartedCycleId   = nil  -- cycle mà timer Trial 60s đang đo
    State.trialTimeoutCycleId   = nil  -- latch chặn cùng cycle tự bật lại in_trail sau timeout
    State._lastCurrentMain      = nil  -- BS-5: theo dõi current đổi cycle
    -- [FINAL §7.2] session do server cấp
    State.sessionToken      = nil
    State.sessionGeneration = 0
    State.eventSequence     = 0
    State._sessionStale     = false
    -- [FIX #1] Character token: KHÔNG dùng tostring(Character) (hai Character cũ/mới thường trùng tên account
    --   → old==new → server reject character_unchanged, helpreset không ghi, Main không bao giờ đủ điều kiện thắng).
    --   clientBootId ổn định theo phiên script; characterGeneration tăng ĐÚNG 1 lần mỗi Character mới (một
    --   lifecycle manager duy nhất — xem CharacterTracker). Token = sessionGeneration:clientBootId:characterGeneration.
    --   KHÔNG nhét trialCycleId vào token (token đại diện Character, không đại diện cycle).
    State.clientBootId       = State.clientBootId or nil  -- sinh 1 lần ở CharacterTracker.init
    State.characterGeneration = 0
    State.characterToken     = nil
    -- [FINAL §12] post-trial per-cycle state (thay State.postTrialDeathDetected bị reset mỗi tick)
    State.activeCycleId          = nil
    State.postTrialPhase         = "idle"
    State.postTrialStartedAt     = nil
    State.postTrialCycleId       = nil  -- cycle canon của grace/kill phase
    State.postTrialHoldCFrame    = nil  -- vị trí giữ Main đứng im đủ 4 giây
    State.postTrialEliminated    = {}   -- userId đã chết trong cycle; respawn không đánh lại
    State.postTrialSeen          = {}   -- userId từng được thấy trong FFA
    State.postTrialCharacters    = {}   -- userId -> Character đầu tiên của participant trong cycle
    State.postTrialDeathDetected = false
    State.intentionalPostTrialReset = false
    State.intentionalResetCycleId    = nil   -- [§XIV] cycle của intentional reset (chỉ set khi win_confirmed)
    State.intentionalResetCharacter  = nil   -- [§XIV] Character tại thời điểm intentional reset
    State.winCandidateEventId    = nil
    State.winConfirmed           = false
    State.lastCycleResult        = nil
    -- [FINAL §10] state từ /sync long-poll
    State.stateRevision     = 0
    State.trialCycleId      = nil
    State.trialCycleState   = "idle"
    State.trialResult       = nil       -- final result của cycle (win_confirmed/loss/cancelled)
    State.trialResultCycle  = nil
    State.fullmoonUnlockPending = false
    State._syncActive       = false     -- có 1 long-poll đang chạy?
    State._syncHealthy      = false     -- /sync ổn định → tắt fast /curmain

    for _, v in ipairs(Config.allies) do State.isAlly[v] = true end

    -- hot-path: KHÔNG gọi HTTP. cache trống → "waiting" (đúng File A 355-359).
    function State.getMainStatus(name)
        local c = State.statusCache[name]
        if c then return c.status end
        return "waiting"
    end

    -- POST mainstatus qua queue (retry). Cập nhật cache NGAY để logic dùng giá trị mới (File A 322-326).
    -- DEDUP (user 2026-07-02): chỉ POST khi status ĐỔI so với lần POST gần nhất; cùng giá trị → chỉ
    -- cập nhật cache local, KHÔNG spam job (cắt loạn khi tick 0.35s gọi lại cùng status). Vẫn re-POST
    -- mỗi STATUS_REPOST_MS để chống mất gói (server prune 50s → 5s re-sync vẫn thừa an toàn).
    State._lastPostedStatus = nil
    State._lastPostedAt     = 0
    local STATUS_REPOST_MS  = 5
    local function pushStatus(statusStr)
        State.statusCache[State.myName] = { t = tick(), status = statusStr }
        local changed = statusStr ~= State._lastPostedStatus
        local stale   = (tick() - State._lastPostedAt) >= STATUS_REPOST_MS
        if changed or stale then
            State._lastPostedStatus = statusStr
            State._lastPostedAt = tick()
            Net.postJSON(endpoint("/mainstatus", { name = State.myName }), { status = statusStr }, "mainstatus")
        end
    end
    function State.setMyMainStatus(statusStr)
        if not State.myMainIndex then return end
        pushStatus(statusStr)
    end
    -- Báo status cho BẤT KỲ account (kể cả ALLY — không cần myMainIndex). (File A 330-333)
    function State.reportStatus(statusStr)
        pushStatus(statusStr)
    end
end

--[[ ============================================================================
 [09] SAFEREMOTE — InvokeServer trong thread con + timeout (chống yield treo). (File A 571-592)
============================================================================ ]]
local SafeRemote = {}
do
    local _commF
    local function resolve()
        local rem = ReplicatedStorage:FindFirstChild("Remotes") or ReplicatedStorage:WaitForChild("Remotes", 10)
        if not rem then return nil end
        return rem:FindFirstChild("CommF_") or rem:WaitForChild("CommF_", 10)
    end
    _commF = resolve()

    function SafeRemote.invoke(timeout, ...)
        if not _commF then _commF = resolve() end
        if not _commF then return false end
        local args = table.pack(...)
        local done, packed = false, nil
        task.spawn(function()
            packed = table.pack(pcall(function()
                return _commF:InvokeServer(table.unpack(args, 1, args.n))
            end))
            done = true
        end)
        local t0 = tick()
        while not done and (tick() - t0) < timeout do task.wait() end
        if not done or not packed then return false end
        return table.unpack(packed, 1, packed.n)
    end
end

--[[ ============================================================================
 [10] SERVERSYNC — /init, heartbeat(+fullmoon), offline, warmer /curmain (trọng tài),
      net probe, clock sync. (File A 281-313, 368-429, 477-519, 2397-2427)
============================================================================ ]]
local ServerSync = {}
do
    local B = Config.baseUrl

    -- clock sync (File A 2397-2422)
    ServerSync.clockOffset = nil
    function ServerSync.syncClock()
        local t0 = tick()
        local srv = tonumber(Net.text(B .. "/timeserver", 0))
        local t1 = tick()
        if srv then
            ServerSync.clockOffset = (srv + (t1 - t0) / 2) - t1
            return true
        end
        return false
    end
    function ServerSync.now()
        if ServerSync.clockOffset ~= nil then return tick() + ServerSync.clockOffset end
        local srv = tonumber(Net.text(B .. "/timeserver", 1))
        if srv then return srv end
        return (os and os.time and os.time()) or 0
    end
    Logger.timeFn = ServerSync.now

    -- /init: gộp identify + allmains 1 request, retry 8 lần (File A 283-313)
    -- [FINAL §7.1] server cấp session_token + session_generation → lưu vào State cho CriticalEvents dùng.
    function ServerSync.init()
        local allies_str = table.concat(Config.allies, ",")
        local mains_str  = table.concat(Config.mains, ",")
        local url = endpoint("/init", { name = Config.myName, allies = allies_str, mains = mains_str })
        local data
        for attempt = 1, 8 do
            data = Net.getJSON(url, 0)
            if data and data.role then break end
            Net.log("WARN", "/init thử lại " .. attempt .. "/8")
            task.wait(0.3 + 0.2 * attempt)
        end
        if data then
            State.myRole = data.role or "unknown"
            if State.myRole == "main" then
                State.myMainIndex = data.index
                State.isMain[Config.myName] = true
                State.mainIndexOf[Config.myName] = data.index
            end
            if data.mains then
                for _, v in ipairs(data.mains) do
                    if v.name and v.name ~= "" then
                        State.isMain[v.name] = true
                        State.mainIndexOf[v.name] = v.index
                    end
                end
            end
            -- [FINAL §7.2] lưu session do server cấp. Chỉ khi có token mới bật gửi event V2.
            if type(data.session_token) == "string" and #data.session_token > 0 then
                State.sessionToken = data.session_token
                State.sessionGeneration = tonumber(data.session_generation) or 1
                State._sessionStale = false
                State.eventSequence = 0
                -- [FIX #1] session đổi → rebuild characterToken để nhét sessionGeneration mới (token cũ tự vô hiệu).
                if _G.KaitunRebuildToken then pcall(_G.KaitunRebuildToken) end
                Net.log("INFO", "/init session gen=" .. tostring(State.sessionGeneration))
            end
            Net.log("INFO", "/init OK role=" .. tostring(State.myRole) .. " index=" .. tostring(State.myMainIndex))
        else
            Net.log("ERR", "/init thất bại hoàn toàn — sẽ retry qua warmer")
        end
        return data ~= nil
    end

    -- [FINAL §8.3] re-init khi session client bị server báo stale (token/generation cũ).
    ServerSync._lastReinitAt = 0
    function ServerSync.reinitIfStale()
        if not State._sessionStale then return end
        if (tick() - (ServerSync._lastReinitAt or 0)) < 3 then return end -- cooldown chống spam re-init
        ServerSync._lastReinitAt = tick()
        Net.log("WARN", "session stale → re-init lấy token mới")
        State._sessionStale = false
        ServerSync.init()
    end

    -- Heartbeat kèm cờ fullmoon (File A 368-373). isfullmoon là global khai báo dưới → pcall.
    -- NIL-SAFE: isfullmoon() có thể trả nil khi Sky/Moon texture chưa load → KHÔNG gửi fullmoon field
    -- để tránh overwrite STORE.fullmoon[leader]=true thành false trên server khi Sky đang lag load.
    function ServerSync.sendHeartbeat()
        if not Runtime.alive then return end
        -- Lấy fmRaw mà không ép nil → false
        local fmRaw = nil
        pcall(function()
            if _G.isfullmoon then fmRaw = _G.isfullmoon() end
        end)
        local players, allies = 0, 0
        pcall(function() if _G.countServerInfo then players, allies = _G.countServerInfo() end end)
        local body = { role = State.myRole, players = players, allies = allies, scout = Config.scout == true }
        -- Chỉ gửi fullmoon khi là boolean thật. nil = Sky chưa load → bỏ qua field, server giữ giá trị cũ.
        if fmRaw == true then body.fullmoon = true
        elseif fmRaw == false then body.fullmoon = false
        end
        Net.postJSON(endpoint("/heartbeat", { name = Config.myName }), body, "heartbeat")
    end

    -- Offline đúng 1 lần, gửi cả POST queue lẫn GET đồng bộ (File A 378-385)
    function ServerSync.sendOffline()
        if Runtime._offlineSent then return end
        Runtime._offlineSent = true
        -- [FINAL §9/A4] báo offline qua event (main offline giữa FFA = loss ở server) — best-effort, không chờ.
        pcall(function()
            if Config.enableEventProtocol and CriticalEvents.enabled() and State.trialCycleId then
                CriticalEvents.emit("offline", { cycle_id = State.trialCycleId })
            end
        end)
        -- BS-8: GỬI offline TRƯỚC, tắt runtime SAU (tránh worker loop thoát trước khi gửi kịp)
        local url = endpoint("/offline", { name = Config.myName })
        pcall(function()
            if Net.raw then
                Net.raw("POST", url, HttpService:JSONEncode({ role = State.myRole }))
            else
                Net.postJSON(url, { role = State.myRole }, "offline")
            end
        end)
        pcall(function() Net.getRaw(url) end)
        Runtime.alive = false -- tắt SAU CÙNG
    end

    -- /curmain = TRỌNG TÀI (File A 477-488): order, current, current_jobid, current_time, mains[]
    function ServerSync.fetchCurMain()
        if not Net.raw then return nil end
        local ok, _, body = Net.raw("GET", B .. "/curmain", nil)
        if not (ok and body) then return nil end
        local good, res = pcall(function() return HttpService:JSONDecode(body) end)
        if good and res and type(res.order) == "table" then return res end
        return nil
    end

    function ServerSync.startWarmers()
        -- clock (File A 2424-2427)
        task.spawn(function()
            ServerSync.syncClock()
            while Runtime.alive do task.wait(20); pcall(ServerSync.syncClock) end
        end)
        -- heartbeat 5s (File A 388-396)
        task.spawn(function()
            while Runtime.alive do
                ServerSync.sendHeartbeat()
                pcall(ServerSync.reinitIfStale) -- [FINAL §8.3] re-init nếu session bị server báo stale
                for _ = 1, Config.HEARTBEAT_INTERVAL do
                    if not Runtime.alive then break end
                    task.wait(1)
                end
            end
        end)
        -- warmer /curmain ~0.7s: 1 request lấy order + status MỌI main + jobid main stt1 (File A 493-519)
        -- [FINAL §10/A8] khi /sync long-poll ổn định (State._syncHealthy) → GIÃN poll này ra (0.7s→2.5s)
        --   để KHÔNG chạy fast-poll + long-poll song song lâu dài. /sync lỗi → tự về nhịp cũ.
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    local data = ServerSync.fetchCurMain()
                    if data and type(data.order) == "table" then
                        ServerSync.applyCurMain(data)
                    end
                end)
                if State._syncHealthy then task.wait(2.5) else task.wait(Config.CURMAIN_INTERVAL) end
            end
        end)
        -- [FINAL §10/A8] /sync LONG-POLL: 1 request duy nhất, chờ tối đa 20s, áp state từ /sync.
        if Config.enableLongPoll then ServerSync.startSyncLoop() end
    end

    -- [FINAL] tách áp dụng dữ liệu /curmain ra hàm riêng để cả fast-poll và /sync tái dùng.
    function ServerSync.applyCurMain(data)
        if not (data and type(data.order) == "table") then return end
        State.serverMainOrder = data.order
        State.serverCurMain   = data.current
        State.serverCurJobid  = data.current_jobid
        State._lastCurMainOK  = tick()

        -- /curmain và /sync có thể trả snapshot trễ/nil/đổi cycle đúng lúc đang kill.
        -- Trong live kill phase, server snapshot KHÔNG được xóa didEnterTrialThisTurn
        -- hoặc reset grace local Character+Job.
        local preserveLiveKill =
            State.postTrialPhase == "kill_phase"
            and State.postTrialStartedAt ~= nil
            and LocalPlayer.Character ~= nil

        if State.isMain[State.myName] and not preserveLiveKill then
            local prevLocked = State.fullmoonLocked
            if prevLocked and (data.fullmoon_locked ~= true) then State.didEnterTrialThisTurn = false end
            if State._lastCurrentMain ~= nil and data.current ~= State._lastCurrentMain then
                State.didEnterTrialThisTurn = false
            end
        end
        State._lastCurrentMain = data.current
        State.fullmoonLocked    = data.fullmoon_locked == true
        State.gateOpenedOnce    = data.gate_opened_once == true
        State.gateOpen          = data.gate_open == true
        State.trialPhase        = tostring(data.trial_phase or "idle")
        State.fullmoonJobid     = nonEmpty(data.fullmoon_jobid)
        State.allyTargetJobid   = nonEmpty(data.ally_target_jobid)
        State.main1Name         = nonEmpty(data.main1_name)
        State.requiredAllies    = tonumber(data.required_allies or 2) or 2
        State.allyLeader        = nonEmpty(data.ally_leader)
        State.fullmoonAllyCount = tonumber(data.fullmoon_ally_count or 0) or 0
        State.candidateAllyCount= tonumber(data.candidate_ally_count or 0) or 0
        State.joinSpamInterval  = tonumber(data.join_spam_interval or 5) or 5
        State.mainJoinTimeout   = tonumber(data.main_join_timeout or 45) or 45
        State.partyOrder        = (type(data.party_order) == "table") and data.party_order or {}
        -- [FINAL §10] trial cycle + revision (additive fields; nil-safe)
        if data.state_revision ~= nil then State.stateRevision = tonumber(data.state_revision) or State.stateRevision end
        if data.trial_cycle_id ~= nil then
            -- cycle đổi → cho phép TrialEvents emit lại lượt mới (dedup theo cycle)
            if data.trial_cycle_id ~= State.trialCycleId and TrialEvents then
                pcall(function() TrialEvents.resetForNewCycle() end)
                State.winConfirmed = false
                State.trialStartedAt = 0
                State.trialStartedCycleId = nil
                State.trialTimeoutCycleId = nil
                if not preserveLiveKill then
                    State.postTrialStartedAt = nil
                    State.postTrialCycleId = nil
                    State.postTrialHoldCFrame = nil
                else
                    DBG(
                        "[POSTTRIAL] applyCurMain cycle changed during kill → preserve local grace",
                        "info",
                        "posttrial_apply_preserve_cycle"
                    )
                end
                -- [FIX #5] KHÔNG clear intentional-reset flags ở đây (đường /sync–/curmain). Nếu /curmain tới
                --   đúng lúc Main vừa Health=0 mà Humanoid.Died chưa chạy, clear ở đây → death thật bị hiểu là
                --   death (không phải intentional) → gửi main_died oan. Chỉ processAfterRespawn() được clear.
            end
            State.trialCycleId = data.trial_cycle_id
        end
        if data.trial_state ~= nil then State.trialCycleState = tostring(data.trial_state) end
        -- [§XXIII-8] Server cycle về IDLE (cycle_id null hoặc state idle) → clear cycle cũ ở client để không
        --   giữ trialCycleId chết (event cycle-bound gửi sau sẽ bị server reject; guard/flag phải dọn sạch).
        if (data.trial_cycle_id == nil and data.trial_state == nil) then
            -- không có field trial trong response này → bỏ qua (giữ nguyên)
        elseif data.trial_cycle_id == nil or (data.trial_state ~= nil and tostring(data.trial_state) == "idle") then
            if State.trialCycleId ~= nil and TrialEvents then pcall(function() TrialEvents.resetForNewCycle() end) end
            State.trialCycleId = nil
            State.winConfirmed = false
            State.trialStartedAt = 0
            State.trialStartedCycleId = nil
            State.trialTimeoutCycleId = nil
            if not preserveLiveKill then
                State.postTrialStartedAt = nil
                State.postTrialCycleId = nil
                State.postTrialHoldCFrame = nil
            else
                DBG(
                    "[POSTTRIAL] idle snapshot during kill → preserve local grace/runtime",
                    "info",
                    "posttrial_apply_preserve_idle"
                )
            end
            -- [FIX #5] KHÔNG clear intentional-reset flags ở idle-sync (lý do như trên). processAfterRespawn()
            --   sẽ clear sau khi Character mới sống. Giữ flag ở đây để Humanoid.Died đang chờ vẫn nhận diện
            --   đúng intentional reset thay vì loss.
        end
        if data.fullmoon_unlock_pending ~= nil then State.fullmoonUnlockPending = data.fullmoon_unlock_pending == true end
        if State.fullmoonJobid or State.allyTargetJobid then State.lastScoutSignalAt = tick() end
        _G.srvMainOrder    = data.order
        _G.srvCurMain      = data.current
        _G.srvCurMainJobid = data.current_jobid
        if type(data.mains) == "table" then
            for _, m in ipairs(data.mains) do
                if m.name and m.name ~= State.myName then
                    State.statusCache[m.name] = { t = tick(), status = m.status or "waiting" }
                end
            end
        end
        local curr = data.current
        if curr and curr ~= State.myName and data.current_jobid and data.current_jobid ~= "" then
            State.mainJobCache[curr] = { jobid = data.current_jobid, time = gettimeserver(), t = tick() }
        end
    end

    -- [FINAL §10/A8] /sync long-poll loop — 1 loop DUY NHẤT. Áp revision/trial state/result.
    --   Ổn định → set _syncHealthy (fast-poll giãn nhịp). Lỗi liên tục → tắt healthy, fallback /curmain.
    function ServerSync.startSyncLoop()
        if State._syncActive then return end
        State._syncActive = true
        task.spawn(function()
            local failStreak = 0
            local COOLDOWN_AFTER_FAILS = 5
            while Runtime.alive do
                if not Config.enableLongPoll then State._syncHealthy = false; task.wait(2); else
                    local url = endpoint("/sync", { name = Config.myName, since_revision = State.stateRevision or 0, wait = 20 })
                    local ok, res = Net.getJSONSync(url)
                    if ok and res and res.ok ~= false then
                        failStreak = 0
                        State._syncHealthy = true
                        -- áp revision + trial state/result từ /sync (không phá field cũ)
                        if res.state_revision ~= nil then
                            local rev = tonumber(res.state_revision) or 0
                            -- bỏ response revision CŨ hơn local §10
                            if rev >= (State.stateRevision or 0) then State.stateRevision = rev end
                        end
                        if res.trial_cycle_id ~= nil then State.trialCycleId = res.trial_cycle_id end
                        if res.trial_state ~= nil then State.trialCycleState = tostring(res.trial_state) end
                        if res.fullmoon_unlock_pending ~= nil then State.fullmoonUnlockPending = res.fullmoon_unlock_pending == true end
                        if res.trial_result ~= nil and res.trial_result ~= false then
                            State.trialResult = res.trial_result
                            State.trialResultCycle = res.final_cycle_id or res.trial_cycle_id
                        end
                        -- khi có delta (keepalive=false) → refresh /curmain 1 lần để đồng bộ order/current chi tiết
                        if res.keepalive == false then
                            pcall(function()
                                local data = ServerSync.fetchCurMain()
                                if data then ServerSync.applyCurMain(data) end
                            end)
                        end
                    else
                        failStreak = failStreak + 1
                        State._syncHealthy = false
                        if failStreak >= COOLDOWN_AFTER_FAILS then
                            -- lỗi liên tục → cooldown trước khi thử /sync lại (fast-poll /curmain gánh trong lúc này)
                            task.wait(3)
                            failStreak = 0
                        else
                            task.wait(0.7)
                        end
                    end
                end
            end
            State._syncActive = false
        end)
    end

    -- Net probe (File A 405-429)
    function ServerSync.startNetProbe()
        Diagnostics.netDiag = "NET: đang kiểm tra…"
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    if not Net.raw then Diagnostics.netDiag = "NET: thiếu Net.raw"; return end
                    local g0 = tick()
                    local gok = Net.raw("GET", B .. "/timeserver", nil)
                    local gms = math.floor((tick() - g0) * 1000)
                    local pok, pms = nil, 0
                    if Net.hasReq then
                        local p0 = tick()
                        pok = Net.raw("POST", endpoint("/heartbeat", { name = Config.myName }), HttpService:JSONEncode({ role = State.myRole }))
                        pms = math.floor((tick() - p0) * 1000)
                    end
                    Diagnostics.netGetOk  = gok and true or false
                    Diagnostics.netPostOk = Net.hasReq and (pok and true or false) or nil
                    Diagnostics.netDiag = ("req=%s | GET %s %dms | POST %s"):format(
                        tostring(Net.hasReq), gok and "OK" or "FAIL", gms,
                        Net.hasReq and ((pok and "OK " or "FAIL ") .. pms .. "ms") or "N/A (thiếu request)")
                end)
                task.wait(5)
            end
        end)
    end
end

-- serverNow/gettimeserver: tên File A dùng nhiều nơi → alias sang ServerSync.now
local function serverNow() return ServerSync.now() end
local function gettimeserver() return ServerSync.now() end

--[[ ============================================================================
 [10c] CRITICAL EVENT QUEUE — [PROD REFACTOR §PHẦN II.A] FIFO 1 worker, idempotent, retry.
   OPT-IN: chỉ hoạt động khi Config.enableEventProtocol=true (getgenv().ENABLE_EVENT_PROTOCOL=true)
   VÀ server bật ENABLE_EVENT_PROTOCOL. MẶC ĐỊNH TẮT → CriticalEvents.emit() là no-op, client giữ
   NGUYÊN hành vi cũ (/lockmoon, /fmlost, /helpreset, /mainstatus như trước). Đây là hạ tầng sẵn sàng
   để bật dần, KHÔNG đổi luồng nghiệp vụ hiện tại.

   Đặc điểm (khi bật):
     - 1 session_id ngẫu nhiên/lần load; sequence đơn điệu tăng.
     - event_id = session_id .. ":" .. sequence (server dedupe).
     - 1 worker FIFO duy nhất — KHÔNG gửi song song cùng event, KHÔNG spawn worker mỗi retry.
     - Retry theo lịch §RETRY: 0 / 0.20 / 0.35 / 0.70 / 1.50s rồi backoff nền có giới hạn.
     - ACK có accepted/duplicate/accepted_sequence/state_revision.
============================================================================ ]]
--[[ ============================================================================
 [10c] CRITICAL EVENT QUEUE — [FINAL §8] FIFO 1 worker, session do SERVER cấp, ACK thật.
   MẶC ĐỊNH BẬT (§37). Client tự fallback route cũ nếu server trả disabled/404/lỗi liên tục.

   Đặc điểm:
     - Session do SERVER cấp (§7.1): /init trả session_token + session_generation. Client KHÔNG tự tạo.
     - Chưa có token → KHÔNG gửi event V2 (giữ trong queue, re-init lấy token, hoặc fallback legacy).
     - sequence đơn điệu tăng; event_id = session_token .. ":" .. sequence (server dedupe).
     - 1 worker FIFO DUY NHẤT — KHÔNG gửi song song, KHÔNG spawn worker mỗi retry, KHÔNG coalesce critical.
     - postJSONSync đọc ACK thật; chỉ xoá event khi accepted=true HOẶC duplicate=true có result.
     - Retry cùng event_id §8.3: 0 / 0.20 / 0.35 / 0.70 / 1.50s rồi backoff nền có giới hạn.
     - stale_session → dừng worker, báo ServerSync re-init; huỷ event thuộc session/cycle cũ.
     - disabled/404 liên tục → tắt protocol V2 tạm thời (cooldown), fallback route cũ.
============================================================================ ]]
local CriticalEvents = {}
do
    local B = Config.baseUrl
    local seq = 0
    -- FIFO queue O(1) head/tail
    local q = {}          -- array of jobs {event_id, payload, attempts, cycleId, generation}
    local head, tail = 1, 0
    local workerAlive = false
    local RETRY_SCHEDULE = { 0.20, 0.35, 0.70, 1.50 } -- sau lần gửi đầu (attempt 0)
    local BACKOFF_MAX = 8
    -- trạng thái protocol V2 (fallback khi server disabled/404 liên tục)
    local v2Disabled = false          -- true → emit no-op, dùng route legacy
    local v2DisabledUntil = 0         -- cooldown (tick) trước khi thử lại V2
    local disabledStreak = 0
    local DISABLED_STREAK_MAX = 5
    local V2_COOLDOWN = 30            -- giây tắt V2 trước khi thử lại

    local function nextSeq() seq = seq + 1; return seq end

    -- lấy session hiện tại từ State (do ServerSync.init cấp)
    local function haveSession()
        return type(State.sessionToken) == "string" and #State.sessionToken > 0 and (State.sessionGeneration or 0) > 0
    end

    -- [STANDARD PATCH] Event tạo trước /init có token Character dạng 0:<bootId>:<charGen>.
    -- Khi bind event vào session đầu tiên, chỉ rebind token DO CharacterTracker của chính boot này sinh;
    -- chuỗi tùy ý/legacy không khớp format+bootId được giữ nguyên. Không đổi token của event session thật cũ.
    local TRACKED_TOKEN_FIELDS = {
        "character_id", "character_token",
        "old_character_id", "new_character_id",
        "old_character_token", "new_character_token",
    }
    local function rebindTrackedCharacterToken(value, targetGeneration)
        if type(value) ~= "string" then return value end
        local oldGen, bootId, charGen = value:match("^([^:]+):([^:]+):([^:]+)$")
        if not oldGen or not bootId or not charGen then return value end
        if tonumber(oldGen) == nil or tonumber(charGen) == nil then return value end
        if bootId ~= tostring(State.clientBootId or "") then return value end
        return table.concat({ tostring(targetGeneration), bootId, charGen }, ":")
    end
    local function bindPreInitJobToSession(job, targetGeneration)
        for _, field in ipairs(TRACKED_TOKEN_FIELDS) do
            local value = job.payload[field]
            if value ~= nil then
                job.payload[field] = rebindTrackedCharacterToken(value, targetGeneration)
            end
        end
        -- event_id cũng phải thuộc session thật thay vì prefix "nosession".
        local reboundEventId = tostring(State.sessionToken) .. ":" .. tostring(job.payload.sequence)
        job.payload.event_id = reboundEventId
        job.event_id = reboundEventId
    end

    -- gửi 1 job qua /event (đồng bộ, đọc ACK). trả (removed, ack, hardFail)
    --   removed=true  → xoá khỏi queue (accepted / duplicate-with-result / bỏ qua vĩnh viễn)
    --   removed=false → giữ lại retry
    local function sendOnce(job)
        local curGen = State.sessionGeneration or 0
        -- [FIX #4] Guard generation-0. Trong Lua số 0 là TRUTHY → guard cũ `if job.generation and ...`
        --   coi event pre-init (generation=0) là "thuộc generation" rồi so 0 ~= 1 → HUỶ oan
        --   (mất trial_entered/ffa_entered/main_died/helpreset nếu init chậm).
        --   Đúng: (a) session CHƯA sẵn (curGen<=0) → GIỮ chờ /init, KHÔNG gửi, KHÔNG huỷ.
        --         (b) event chưa đóng dấu generation thật (job.generation<=0) → đóng dấu generation hiện tại
        --             rồi gửi (event pre-init được bind vào session đầu tiên).
        --         (c) chỉ HUỶ khi event mang generation THẬT (>0) KHÁC session hiện tại (session cũ sau re-init).
        if curGen <= 0 then
            return false, { pending_session = true }, false  -- chờ /init; worker retry
        end
        if job.generation and job.generation > 0 and job.generation ~= curGen then
            -- event thuộc generation THẬT cũ → huỷ (không gửi event session cũ sang session mới) §8.3
            return true, { stale_local = true }, false
        end
        if not job.generation or job.generation <= 0 then
            bindPreInitJobToSession(job, curGen)
            job.generation = curGen  -- đóng dấu generation thật cho event pre-init
        end
        job.payload.session_token = State.sessionToken
        job.payload.session_generation = State.sessionGeneration
        local ok, ack, status_, err = Net.postJSONSync(B .. "/event", job.payload, 8)
        if not ok then
            -- server disabled/404 → đếm streak để fallback
            if status_ == 404 or (ack and ack.error == "event_protocol_disabled") then
                disabledStreak = disabledStreak + 1
                if disabledStreak >= DISABLED_STREAK_MAX then
                    v2Disabled = true
                    v2DisabledUntil = tick() + V2_COOLDOWN
                    if Net.log then Net.log("WARN", "V2 event protocol disabled/404 → fallback legacy (cooldown " .. V2_COOLDOWN .. "s)") end
                end
                return true, ack, true -- bỏ event này (server không nhận V2)
            end
            return false, ack, false -- lỗi mạng → retry
        end
        disabledStreak = 0
        -- ACK hợp lệ. accepted / duplicate → xoá. stale_session → xử lý riêng.
        if ack and ack.reason == "stale_session" then
            -- session client đã cũ → cần re-init. Đánh dấu để ServerSync re-init, giữ event? → huỷ event cũ.
            State._sessionStale = true
            return true, ack, false
        end
        if ack and (ack.accepted == true or ack.duplicate == true) then
            -- lưu result cuối (win_confirmed/loss...) nếu có, cho caller đọc
            if ack.result then job._ackResult = ack.result end
            job._ack = ack
            return true, ack, false
        end
        -- accepted=false nhưng KHÔNG stale (vd win_waiting, not_cycle_member) → coi như đã xử lý (không retry vô hạn)
        if ack and ack.accepted == false then
            job._ack = ack
            return true, ack, false
        end
        return false, ack, false
    end

    local function runWorker()
        if workerAlive then return end
        workerAlive = true
        task.spawn(function()
            while Runtime and Runtime.alive and head <= tail do
                -- chưa có session → chờ ServerSync cấp (KHÔNG gửi event V2 khi thiếu token §7.2/A3)
                if not haveSession() then
                    task.wait(0.3)
                else
                    local job = q[head]
                    if job then
                        local removed, ack, _hard = sendOnce(job)
                        -- callback ACK cho caller (win result...) nếu đăng ký
                        if removed and job.onAck then pcall(job.onAck, ack) end
                        if removed then
                            q[head] = nil
                            head = head + 1
                        else
                            job.attempts = (job.attempts or 0) + 1
                            local idx = job.attempts
                            local waitS = RETRY_SCHEDULE[idx]
                            if not waitS then
                                waitS = math.min(BACKOFF_MAX, 1.50 * (idx - #RETRY_SCHEDULE + 1))
                            end
                            task.wait(waitS)
                        end
                    else
                        head = head + 1
                    end
                end
            end
            workerAlive = false
        end)
    end

    -- Public: đẩy 1 critical event vào FIFO. opts.onAck(ack) gọi khi có ACK cuối.
    function CriticalEvents.emit(eventName, extra, opts)
        if not Config.enableEventProtocol then return nil end
        -- V2 tạm tắt (fallback) → thử bật lại sau cooldown
        if v2Disabled then
            if tick() >= v2DisabledUntil then v2Disabled = false; disabledStreak = 0
            else return nil end
        end
        local s = nextSeq()
        local payload = {
            event_id   = (State.sessionToken or "nosession") .. ":" .. tostring(s),
            session_token = State.sessionToken,
            session_generation = State.sessionGeneration,
            sequence   = s,
            name       = Config.myName,
            event      = eventName,
            role       = State.myRole,
            jobid      = game.JobId,
            placeid    = game.PlaceId,
            client_time = math.floor((ServerSync.now and ServerSync.now()) or 0),
        }
        if extra then
            for k, v in pairs(extra) do payload[k] = v end
        end
        tail = tail + 1
        q[tail] = {
            event_id = payload.event_id, payload = payload, attempts = 0,
            cycleId = extra and extra.cycle_id or nil,
            generation = State.sessionGeneration,
            onAck = opts and opts.onAck or nil,
        }
        runWorker()
        return payload.event_id
    end

    -- huỷ mọi event thuộc cycle cũ (khi cycle cancel/end + reconnect) §8.3
    function CriticalEvents.dropCycle(cycleId)
        for i = head, tail do
            local job = q[i]
            if job and job.cycleId == cycleId then q[i] = false end -- đánh dấu bỏ (worker skip false)
        end
    end
    function CriticalEvents.pending() return (tail - head + 1) end
    function CriticalEvents.sessionToken() return State.sessionToken end
    function CriticalEvents.enabled() return Config.enableEventProtocol == true and not v2Disabled end
    function CriticalEvents.isV2Disabled() return v2Disabled end
end

-- [FINAL §9] TrialEvents được ĐỊNH NGHĨA SAU templeState/WorldProbe (xem [10d] bên dưới) để tránh
--   tham chiếu local chưa khai báo. Forward-declare ở đây cho các module trung gian nếu cần.
local TrialEvents


--[[ ============================================================================
 [11] LIFECYCLE HOOKS — teleport guard, offline-once, [FIX-BUG2] death guard.
============================================================================ ]]
do
    -- [FIX #1] CharacterTracker — nguồn DUY NHẤT sinh characterToken. Tăng characterGeneration ĐÚNG 1 lần
    --   mỗi Character mới. Token = sessionGeneration:clientBootId:characterGeneration (KHÔNG có trialCycleId).
    --   Nếu script khởi động khi Character đã tồn tại → bind Character hiện tại thành generation đầu tiên.
    --   Khi sessionGeneration đổi (re-init) token tự khác ở lần rebuild kế → không giữ token session cũ.
    do
        if not State.clientBootId then
            local ok, guid = pcall(function() return HttpService:GenerateGUID(false) end)
            State.clientBootId = ok and guid or ("boot-" .. tostring(tick()))
        end
        local function rebuildToken()
            State.characterToken = table.concat({
                tostring(State.sessionGeneration or 0),
                tostring(State.clientBootId),
                tostring(State.characterGeneration or 0),
            }, ":")
            return State.characterToken
        end
        -- một hàm bump duy nhất; mọi CharacterAdded (kể cả bind ban đầu) đi qua đây
        local function onNewCharacter()
            State.characterGeneration = (State.characterGeneration or 0) + 1
            rebuildToken()
            -- Character mới = đã rời lifecycle Trial cũ; cho phép retry cùng lượt sạch timer/latch.
            State.trialStartedAt = 0
            State.trialStartedCycleId = nil
            State.trialTimeoutCycleId = nil
            State.postTrialHoldCFrame = nil
        end
        _G.KaitunCharacterToken = function() return State.characterToken or rebuildToken() end
        _G.KaitunRebuildToken   = rebuildToken   -- gọi lại sau /init để nhét sessionGeneration mới vào token
        -- bind Character hiện có (nếu đã tồn tại) = generation đầu
        if LocalPlayer and LocalPlayer.Character then onNewCharacter() end
        pcall(function()
            LocalPlayer.CharacterAdded:Connect(function() onNewCharacter() end)
        end)
    end

    -- [FIX-BUG2] Global death guard: reset trial flag when MAIN dies anywhere
    pcall(function()
        local function setupDeathGuard()
            local char = LocalPlayer.Character
            if not char then return end
            local hum = char:FindFirstChild("Humanoid")
            if not hum then return end

            -- Disconnect old connection if any
            if RuntimeState._deathGuardConnection then
                pcall(function() RuntimeState._deathGuardConnection:Disconnect() end)
            end

            RuntimeState._deathGuardConnection = hum.Died:Connect(function()
                DBG("[DEATH-GUARD] Character died → reset didEnterTrialThisTurn", "warn", "death_guard")
                State.didEnterTrialThisTurn = false
                RuntimeState.inTrial = false
            end)
        end

        -- Setup on initial character
        setupDeathGuard()

        -- Re-setup on each respawn
        LocalPlayer.CharacterAdded:Connect(function()
            task.wait(1)  -- Wait for character to fully load
            setupDeathGuard()
        end)
    end)

    pcall(function()
        LocalPlayer.OnTeleport:Connect(function(stateEnum)
            if stateEnum == Enum.TeleportState.Started or stateEnum == Enum.TeleportState.InProgress then
                Runtime.teleporting = true
            elseif stateEnum == Enum.TeleportState.Failed or stateEnum == Enum.TeleportState.Cancelled then
                Runtime.teleporting = false -- hop hỏng → cho phép offline nếu sau đó rời thật
            end
        end)
    end)
    pcall(function()
        Players.PlayerRemoving:Connect(function(plr)
            if plr == LocalPlayer and not Runtime.teleporting then ServerSync.sendOffline() end
        end)
    end)
    pcall(function() game:BindToClose(function()
        if not Runtime.teleporting then ServerSync.sendOffline() end
    end) end)
end

--[[ ============================================================================
 [12] MOVEMENT — module nhúng File A: topos(proxy tween 150/nil-safe), noclip thật,
      eq, haki, join, getdis, anti-AFK. (File A 717-838, 861-872)
============================================================================ ]]
local Movement = {}
do
    local LP = LocalPlayer

    local function getHRP()
        local c = LP.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end
    Movement.getHRP = getHRP

    -- getdis (File A 819-827, 861-863)
    function Movement.getdis(x, y)
        if typeof(x) ~= "CFrame" then return math.huge end
        if not y then
            local hrp = getHRP()
            if not hrp then return math.huge end
            y = hrp.CFrame
        end
        if typeof(y) == "CFrame" then y = y.Position end
        return (x.Position - y).Magnitude
    end
    Movement.distance = function(cf) return Movement.getdis(cf) end

    -- eq (File A 729-741)
    function Movement.equip()
        local char = LP.Character
        local bp = LP:FindFirstChild("Backpack")
        if not (char and bp) then return end
        for _, L in pairs(bp:GetChildren()) do
            if L:IsA("Tool") then
                local tip = L.ToolTip
                if (tip == "Melee" and not _G.USESWORD) or (tip == "Sword" and _G.USESWORD) then
                    if pcall(function() char.Humanoid:EquipTool(L) end) then break end
                end
            end
        end
    end

    -- haki (File A 743-750)
    function Movement.haki()
        local char = LP.Character
        if char and not char:FindFirstChild("HasBuso") then
            pcall(function()
                ReplicatedStorage.Remotes.CommF_:InvokeServer("Buso")
            end)
        end
    end

    -- ========================================================================
    -- NEW TWEEN CORE — ALL PLAYER MOVEMENT = 150 STUDS/S
    --
    -- CHỈ thay implementation tween. Public API vẫn giữ nguyên:
    --   Movement.cancel()
    --   Movement.topos(targetCFrame, v36)
    --   Movement.to(cf, options)
    --
    -- TweenService chạy trên proxy Part; HumanoidRootPart bám proxy bằng
    -- PreSimulation. Caller cũ không cần sửa và toàn bộ business logic giữ nguyên.
    -- ========================================================================

    local TWEEN_SPEED = 150
    Movement.TWEEN_SPEED = TWEEN_SPEED

    local TWEEN_CFG = {
        AlreadyThere     = 3,
        ArriveDistance   = 1.5,
        SameTarget       = 2.5,

        SettleMin        = 0.65,
        QuietNeed        = 0.35,
        SettlePull       = 4,

        ReleaseConfirm   = 0.35,
        ReleasePull      = 7,
        MaxReleaseRetry  = 3,

        PushSnap         = 28,
        StuckSec         = 10,
        StreamTimeout    = 5,
    }

    local _moveSerial = 0
    local _activeMove = nil

    local function setRootVelocity(root, velocity)
        if not root or not root.Parent then return end

        pcall(function()
            root.AssemblyLinearVelocity = velocity
            root.AssemblyAngularVelocity = Vector3.zero
        end)

        pcall(function()
            root.Velocity = velocity
            root.RotVelocity = Vector3.zero
        end)
    end

    local function movementLocked(character)
        if Runtime.teleporting then
            return true
        end

        if not character then
            return true
        end

        if character:FindFirstChild("AntiMover") then
            return true
        end

        local ok, tagged = pcall(function()
            return CollectionService:HasTag(character, "Teleporting")
        end)

        return ok and tagged == true
    end

    local function requestMoveStreaming(position)
        task.spawn(function()
            pcall(function()
                LP:RequestStreamAroundAsync(
                    position,
                    TWEEN_CFG.StreamTimeout
                )
            end)
        end)
    end

    local function cleanupMove(data)
        if not data or data.cleaned then return end
        data.cleaned = true

        if data.tween then
            pcall(function()
                data.tween:Cancel()
            end)
        end

        if data.stepConnection then
            pcall(function()
                data.stepConnection:Disconnect()
            end)
        end

        if data.characterConnection then
            pcall(function()
                data.characterConnection:Disconnect()
            end)
        end

        if data.humanoid and data.humanoid.Parent then
            pcall(function()
                data.humanoid.AutoRotate = data.autoRotate
            end)
        end

        for _, inst in ipairs(data.instances or {}) do
            if inst and inst.Parent then
                pcall(function()
                    inst:Destroy()
                end)
            end
        end

        if data.root and data.root.Parent then
            setRootVelocity(data.root, Vector3.zero)
        end
    end

    local function stopMove()
        _moveSerial += 1

        local data = _activeMove
        _activeMove = nil

        cleanupMove(data)
    end

    function Movement.cancel()
        stopMove()
    end

    function Movement.isMoving()
        return _activeMove ~= nil
            and not _activeMove.cleaned
    end

    local function finishMove(id, data)
        if id ~= _moveSerial
            or _activeMove ~= data
            or data.finishing
        then
            return
        end

        data.finishing = true
        _activeMove = nil
        cleanupMove(data)
    end

    local function launchProxyTween(data)
        if not data
            or data.cleaned
            or not data.proxy
            or not data.proxy.Parent
        then
            return
        end

        local remaining =
            (data.proxy.Position - data.target.Position).Magnitude

        if remaining <= TWEEN_CFG.ArriveDistance then
            data.proxy.CFrame = data.target
            return
        end

        if data.tween then
            pcall(function()
                data.tween:Cancel()
            end)
        end

        local duration =
            math.clamp(
                remaining / TWEEN_SPEED,
                0.05,
                600
            )

        local tw =
            TweenService:Create(
                data.proxy,
                TweenInfo.new(
                    duration,
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.Out
                ),
                {
                    CFrame = data.target
                }
            )

        data.tween = tw
        tw:Play()
    end

    local function retargetMove(data, targetCFrame, raw)
        if not data
            or data.cleaned
            or typeof(targetCFrame) ~= "CFrame"
        then
            return false
        end

        local targetChanged =
            (data.target.Position - targetCFrame.Position).Magnitude
                > TWEEN_CFG.SameTarget

        local rotationChanged =
            (data.target.LookVector - targetCFrame.LookVector).Magnitude
                > 0.05

        data.raw = raw == true

        if not targetChanged and not rotationChanged then
            return true
        end

        data.target = targetCFrame
        data.rotation =
            targetCFrame - targetCFrame.Position

        data.phase = "travel"
        data.phaseStartedAt = os.clock()
        data.lastCorrectionAt = os.clock()
        data.bestRemaining =
            (data.proxy.Position - targetCFrame.Position).Magnitude
        data.lastNetAt = os.clock()
        data.releaseRetries = 0

        requestMoveStreaming(targetCFrame.Position)
        launchProxyTween(data)

        return true
    end

    local function startMove(targetCFrame, raw)
        if typeof(targetCFrame) ~= "CFrame" then
            return nil
        end

        local character = LP.Character
        local root =
            character
            and character:FindFirstChild("HumanoidRootPart")

        local humanoid =
            character
            and character:FindFirstChildOfClass("Humanoid")

        if not root
            or not humanoid
            or humanoid.Health <= 0
        then
            stopMove()
            return nil
        end

        if not raw then
            pcall(function()
                humanoid.Sit = false
            end)
        end

        -- Caller PVP/Fish/Mink gọi lại rất dày.
        -- Giữ cùng proxy session, chỉ retarget thay vì phá/tạo tween mới.
        if _activeMove
            and not _activeMove.cleaned
            and _activeMove.character == character
            and _activeMove.root == root
        then
            retargetMove(
                _activeMove,
                targetCFrame,
                raw
            )
            return _activeMove
        end

        stopMove()

        local distance =
            (root.Position - targetCFrame.Position).Magnitude

        if distance <= TWEEN_CFG.AlreadyThere then
            return true
        end

        _moveSerial += 1
        local id = _moveSerial
        local now = os.clock()

        requestMoveStreaming(targetCFrame.Position)

        local proxy = Instance.new("Part")
        proxy.Name = "KaitunMoveProxy"
        proxy.Anchored = true
        proxy.CanCollide = false
        proxy.CanQuery = false
        proxy.CanTouch = false
        proxy.Transparency = 1
        proxy.Size = Vector3.new(1, 1, 1)
        proxy.CFrame = root.CFrame
        proxy.Parent = workspace

        local stabilizer = Instance.new("BodyVelocity")
        stabilizer.Name = "KaitunMoveStabilizer"
        stabilizer.MaxForce =
            Vector3.new(1e9, 1e9, 1e9)
        stabilizer.P = 1000000
        stabilizer.Velocity = Vector3.zero
        stabilizer.Parent = root

        local data = {
            id = id,

            character = character,
            root = root,
            humanoid = humanoid,

            proxy = proxy,
            stabilizer = stabilizer,

            target = targetCFrame,
            rotation =
                targetCFrame - targetCFrame.Position,
            raw = raw == true,

            phase = "travel",
            phaseStartedAt = now,
            lastCorrectionAt = now,

            lastApplied = root.Position,
            bestRemaining = distance,
            lastNetAt = now,

            releaseRetries = 0,
            lockedSeen = false,

            autoRotate = humanoid.AutoRotate,

            instances = {
                proxy,
                stabilizer,
            },
        }

        _activeMove = data
        humanoid.AutoRotate = false

        launchProxyTween(data)

        data.characterConnection =
            LP.CharacterAdded:Connect(function()
                if id == _moveSerial
                    and _activeMove == data
                then
                    stopMove()
                end
            end)

        data.stepConnection =
            RunService.PreSimulation:Connect(function(dt)
                if id ~= _moveSerial
                    or _activeMove ~= data
                    or data.cleaned
                then
                    return
                end

                if not root
                    or not root.Parent
                    or not humanoid
                    or humanoid.Health <= 0
                    or not proxy
                    or not proxy.Parent
                then
                    stopMove()
                    return
                end

                dt =
                    math.clamp(
                        dt or 0.016,
                        0.001,
                        0.1
                    )

                local frameNow = os.clock()

                if not data.raw then
                    pcall(function()
                        humanoid.Sit = false
                    end)
                end

                -- Nhường quyền hoàn toàn cho teleport thật của game.
                if movementLocked(character) then
                    if not data.lockedSeen then
                        data.lockedSeen = true

                        if data.tween then
                            pcall(function()
                                data.tween:Cancel()
                            end)
                        end
                    end

                    return
                end

                -- Sau teleport thật, resume proxy từ vị trí server mới.
                if data.lockedSeen then
                    data.lockedSeen = false

                    local newPos = root.Position

                    proxy.CFrame =
                        CFrame.new(newPos)
                        * data.rotation

                    data.lastApplied = newPos
                    data.bestRemaining =
                        (newPos - data.target.Position).Magnitude
                    data.lastNetAt = frameNow

                    launchProxyTween(data)
                end

                local serverPos = root.Position
                local proxyPos = proxy.Position

                local remaining =
                    (proxyPos - data.target.Position).Magnitude

                local push =
                    (serverPos - data.lastApplied).Magnitude

                local velocity = Vector3.zero

                if dt > 0 then
                    velocity =
                        (proxyPos - data.lastApplied) / dt

                    local maxVelocity =
                        TWEEN_SPEED * 1.03

                    if velocity.Magnitude > maxVelocity then
                        velocity =
                            velocity.Unit * maxVelocity
                    end
                end

                if stabilizer and stabilizer.Parent then
                    stabilizer.Velocity =
                        data.phase == "travel"
                        and velocity
                        or Vector3.zero
                end

                root.CFrame =
                    CFrame.new(proxyPos)
                    * data.rotation

                setRootVelocity(root, velocity)
                data.lastApplied = proxyPos

                if data.phase == "travel" then
                    if remaining <= TWEEN_CFG.ArriveDistance then
                        data.phase = "settle"
                        data.phaseStartedAt = frameNow
                        data.lastCorrectionAt = frameNow

                        if data.tween then
                            pcall(function()
                                data.tween:Cancel()
                            end)
                        end

                        proxy.CFrame = data.target
                        root.CFrame = data.target
                        setRootVelocity(root, Vector3.zero)

                    else
                        if push > TWEEN_CFG.PushSnap then
                            data.lastCorrectionAt = frameNow
                        end

                        if remaining < data.bestRemaining - 2 then
                            data.bestRemaining = remaining
                            data.lastNetAt = frameNow

                        elseif frameNow - data.lastNetAt
                            > TWEEN_CFG.StuckSec
                        then
                            finishMove(id, data)
                            return
                        end
                    end

                elseif data.phase == "settle" then
                    proxy.CFrame = data.target
                    root.CFrame = data.target
                    setRootVelocity(root, Vector3.zero)

                    local serverOff =
                        (serverPos - data.target.Position).Magnitude

                    if serverOff > TWEEN_CFG.SettlePull then
                        data.lastCorrectionAt = frameNow
                    end

                    if frameNow - data.phaseStartedAt
                            >= TWEEN_CFG.SettleMin
                        and frameNow - data.lastCorrectionAt
                            >= TWEEN_CFG.QuietNeed
                    then
                        data.phase = "release"
                        data.phaseStartedAt = frameNow
                    end

                elseif data.phase == "release" then
                    local serverOff =
                        (serverPos - data.target.Position).Magnitude

                    if serverOff > TWEEN_CFG.ReleasePull then
                        data.releaseRetries += 1

                        if data.releaseRetries
                            > TWEEN_CFG.MaxReleaseRetry
                        then
                            finishMove(id, data)
                            return
                        end

                        data.phase = "settle"
                        data.phaseStartedAt = frameNow
                        data.lastCorrectionAt = frameNow

                        proxy.CFrame = data.target
                        root.CFrame = data.target

                    elseif frameNow - data.phaseStartedAt
                        >= TWEEN_CFG.ReleaseConfirm
                    then
                        finishMove(id, data)
                        return
                    end
                end
            end)

        return data
    end

    function Movement.topos(targetCFrame, v36)
        return startMove(
            targetCFrame,
            v36 == true
        )
    end

    -- Dùng cho các helper cũ cần chờ tween hoàn tất.
    function Movement.waitFor(targetCFrame, timeout, tolerance)
        if typeof(targetCFrame) ~= "CFrame" then
            return false
        end

        tolerance = tonumber(tolerance) or 5

        local startDistance =
            Movement.getdis(targetCFrame)

        timeout =
            tonumber(timeout)
            or math.max(
                5,
                startDistance / TWEEN_SPEED + 8
            )

        local deadline = tick() + timeout

        while Runtime.alive
            and tick() < deadline
        do
            if Movement.getdis(targetCFrame)
                <= tolerance
            then
                return true
            end

            if not Movement.isMoving() then
                return Movement.getdis(targetCFrame)
                    <= tolerance
            end

            task.wait(0.05)
        end

        return Movement.getdis(targetCFrame)
            <= tolerance
    end

    -- Object movement (BringMob) cũng gom về core này và khóa 150 studs/s.
    -- Không dùng character proxy cho mob vì sẽ thay đổi network-ownership logic;
    -- nhưng caller không còn tự tạo TweenService/tốc độ riêng.
    local _objectTweens =
        setmetatable({}, { __mode = "k" })

    function Movement.tweenObject(object, targetCFrame)
        if not object
            or not object.Parent
            or typeof(targetCFrame) ~= "CFrame"
        then
            return nil
        end

        local old = _objectTweens[object]

        if old then
            pcall(function()
                old:Cancel()
                old:Destroy()
            end)
        end

        local distance =
            (targetCFrame.Position - object.Position).Magnitude

        local duration =
            math.clamp(
                distance / TWEEN_SPEED,
                0.03,
                600
            )

        local tw =
            TweenService:Create(
                object,
                TweenInfo.new(
                    duration,
                    Enum.EasingStyle.Linear,
                    Enum.EasingDirection.Out
                ),
                {
                    CFrame = targetCFrame
                }
            )

        _objectTweens[object] = tw

        tw.Completed:Once(function()
            if _objectTweens[object] == tw then
                _objectTweens[object] = nil
            end

            pcall(function()
                tw:Destroy()
            end)
        end)

        tw:Play()
        return tw
    end

    -- alias Movement.to(cf, opts) cho code module-style.
    -- options giữ nguyên API cũ; mọi movement vẫn cố định 150.
    function Movement.to(cf, options)
        return Movement.topos(
            cf,
            options and options.raw
        )
    end

    -- join team qua ChooseTeam UI firesignal (File A 771-780)
    function Movement.joinTeam(v2)
        v2 = (v2 == "Marines" or v2 == "Pirates") and v2 or "Marines"
        for _, v in pairs(LP.PlayerGui:GetChildren()) do
            if v:FindFirstChild("ChooseTeam") then
                local b = v.ChooseTeam.Container:FindFirstChild(v2)
                b = b and b:FindFirstChild("Frame"); b = b and b:FindFirstChild("TextButton")
                if b then pcall(function() firesignal(b.Activated) end) end
            end
        end
    end

    -- tele bằng __ServerBrowser (File A 782-786)
    function Movement.tele(v)
        pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", v or game.JobId)
        end)
    end

    -- noclip: compile loadstring 1 LẦN + single-instance + nil-safe (File A 788-817)
    local _noclipOn = false
    function Movement.enableNoclip(condStr)
        if _noclipOn then return end
        _noclipOn = true
        local okC, fn = pcall(loadstring, condStr or "return true")
        local cond = (okC and type(fn) == "function") and fn or function() return true end
        task.spawn(function()
            while Runtime.alive do
                task.wait()
                local char = LP.Character
                local hum = char and char:FindFirstChild("Humanoid")
                local hrp = char and char:FindFirstChild("HumanoidRootPart")
                local okR, want = pcall(cond)
                if okR and want and hum and hrp and not hum.Sit then
                    local bc = hrp:FindFirstChild("BodyClip")

                    -- BodyClip cũ giữ Velocity=0 nên sẽ đánh nhau với proxy tween.
                    -- Chỉ tạm bỏ BodyClip trong lúc tween; noclip CanCollide vẫn giữ nguyên.
                    if Movement.isMoving() then
                        if bc then bc:Destroy() end
                    elseif not bc then
                        local bv = Instance.new("BodyVelocity")
                        bv.Name = "BodyClip"
                        bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
                        bv.Velocity = Vector3.zero
                        bv.Parent = hrp
                    end

                    for _, p in pairs(char:GetDescendants()) do
                        if p:IsA("BasePart") and p.CanCollide then
                            p.CanCollide = false
                        end
                    end
                elseif hrp then
                    local bc = hrp:FindFirstChild("BodyClip")
                    if bc then bc:Destroy() end
                end
            end
        end)
    end

    -- anti-AFK (File A 830-837)
    pcall(function()
        LP.Idled:Connect(function()
            VirtualUser:Button2Down(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
            task.wait(1)
            VirtualUser:Button2Up(Vector2.new(0, 0), workspace.CurrentCamera.CFrame)
        end)
    end)
end

-- alias File A: getdis(...) / module:topos / module:eq / module:haki
local function getdis(...) return Movement.getdis(...) end
local module = {
    topos = function(_, cf, v) return Movement.topos(cf, v) end,
    eq    = function() return Movement.equip() end,
    haki  = function() return Movement.haki() end,
    getdis = function(_, ...) return Movement.getdis(...) end,
}

-- wrapper topos() của File A 865-872: tự kill khi target xa & đang gần temple entry (chống kẹt)
local TEMPLE_ENTRY_POS = Vector3.new(28310.0234, 14895.1123, 109.456741)
local TEMPLE_ENTRY_FAR_CF = CFrame.new(28310.0234, 14895.1123, 109.456741, -0.469690144, -2.85620132e-08, -0.882831335, -3.23509219e-08, 1, -1.51411736e-08, 0.882831335, 2.14487486e-08, -0.469690144)
local function topos(v)
    pcall(function()
        if getdis(v) > 2500 and getdis(TEMPLE_ENTRY_FAR_CF) < 1500 then
            LocalPlayer.Character.Humanoid.Health = 0
        end
    end)
    return Movement.topos(v)
end

--[[ ============================================================================
 [13] WORLDPROBE — lazy getter + cache (KHÔNG WaitForChild vô hạn). (File A 842-980)
============================================================================ ]]
local WorldProbe = {}
do
    local doorCache, trialCache = {}, {}

    local RACE_TRIAL_NAME = {
        ["Human"]   = "Trial of Strength", ["Mink"] = "Trial of Speed", ["Fishman"] = "Trial of Water",
        ["Skypiea"] = "Trial of the King", ["Ghoul"] = "Trial of Carnage",
        ["Cyborg"]  = "Trial of the Machine", ["Draco"] = "Trial of Flames",
    }
    WorldProbe.RACE_TRIAL_NAME = RACE_TRIAL_NAME

    function WorldProbe.getRace()
        local ok, race = pcall(function() return LocalPlayer.Data.Race.Value end)
        return ok and race or nil
    end
    function WorldProbe.getTemple()
        local map = workspace:FindFirstChild("Map")
        return map and map:FindFirstChild("Temple of Time")
    end

    -- getdoor: cache theo race + check Parent (File A 842-859)
    -- Path chuẩn (toạ độ chuẩn) = Corridor.Door.Door; Skypiea = Corridor.Door (part luôn).
    -- Ưu tiên .Door.Door → .Door (nếu tự nó là part, cho Skypiea) → .Entrance (fallback cũ).
    function WorldProbe.getDoorForRace(race)
        race = race or WorldProbe.getRace()
        if not race then return nil end
        local cached = doorCache[race]
        if cached and cached.Parent then return cached end
        local temple = WorldProbe.getTemple()
        if not temple then return nil end
        local corridor = temple:FindFirstChild(race .. "Corridor")
        if not corridor then return nil end
        local door = corridor:FindFirstChild("Door")
        if not door then return nil end
        -- 1) .Door.Door (part cửa thật, toạ độ chuẩn)
        local innerDoor = door:FindFirstChild("Door")
        if innerDoor and innerDoor:IsA("BasePart") then
            doorCache[race] = innerDoor
            return innerDoor
        end
        -- 2) .Door tự nó là part (trường hợp Skypiea)
        if door:IsA("BasePart") then
            doorCache[race] = door
            return door
        end
        -- 3) fallback .Entrance (bản cũ)
        local entrance = door:FindFirstChild("Entrance")
        if entrance then doorCache[race] = entrance end
        return entrance
    end

    -- getRaceTrialPlace: cache theo race (File A 970-980)
    function WorldProbe.getRaceTrialPlace(race)
        race = race or WorldProbe.getRace()
        if not race then return nil end
        local c = trialCache[race]
        if c and c.Parent then return c end
        local wo = workspace:FindFirstChild("_WorldOrigin")
        local loc = wo and wo:FindFirstChild("Locations")
        local nm = RACE_TRIAL_NAME[race]
        local p = (loc and nm) and loc:FindFirstChild(nm) or nil
        if p then trialCache[race] = p end
        return p
    end

    function WorldProbe.getForcefieldState()
        local temple = WorldProbe.getTemple()
        if not temple then return nil end
        local ff
        pcall(function()
            local border = temple:FindFirstChild("FFABorder")
            local field = border and border:FindFirstChild("Forcefield")
            if field then ff = field.Transparency end
        end)
        return ff
    end
    function WorldProbe.distanceToCFrame(cf, fromCf)
        return Movement.getdis(cf, fromCf)
    end
end
-- alias File A
local function getdoor(vv) return WorldProbe.getDoorForRace(vv) end
local function getRaceTrialPlace(race) return WorldProbe.getRaceTrialPlace(race) end

--[[ ============================================================================
 [14] TEMPLEMANAGER — templeState (cache TTL 0.5s, reparent throttle 5s) +
      goToMyDoor. (File A 880-942)
============================================================================ ]]
local TempleManager = {}
do
    local TEMPLE_ENTRY = TEMPLE_ENTRY_POS
    local TEMPLE_ENTRY_CF = CFrame.new(TEMPLE_ENTRY)
    TempleManager.TEMPLE_ENTRY = TEMPLE_ENTRY

    -- templeState: cache 0.5s, reparent MapStash throttle 5s, trả loading/ffup/ffdown (File A 911-942)
    function TempleManager.templeState()
        local t = tick()
        if RuntimeState._tsCacheTime and (t - RuntimeState._tsCacheTime) < 0.5 then return RuntimeState._tsCacheValue end
        RuntimeState._tsCacheTime = t
        local temple = WorldProbe.getTemple()
        if not temple then
            if not RuntimeState.lastTempleReparent or (tick() - RuntimeState.lastTempleReparent) > 5 then
                RuntimeState.lastTempleReparent = tick()
                pcall(function()
                    local stash = ReplicatedStorage:FindFirstChild("MapStash")
                    local m = stash and stash:FindFirstChild("Temple of Time")
                    local map = workspace:FindFirstChild("Map")
                    if m and map then m.Parent = map end
                end)
            end
            RuntimeState._tsCacheValue = "loading"
            return "loading"
        end
        local ff = WorldProbe.getForcefieldState()
        if ff == 0 then RuntimeState._tsCacheValue = "ffup"; return "ffup" end
        RuntimeState._tsCacheValue = "ffdown"
        return "ffdown"
    end

    -- toposSlow giữ API cũ nhưng dùng chung NEW TWEEN CORE 150 studs/s.
    -- Tất cả player movement hiện dùng chung proxy tween 150 studs/s.
    -- Riêng trial door, tween quá nhanh (200 studs/s + Linear.Out decelerate) khiến HRP đến
    -- vị trí cửa với vận tốc ~0 trong 1 frame → trigger có thể không tính là "touched" → ghost.
    -- 150 studs/s cho vận tốc cuối vẫn dương (chậm vừa), trigger overlap lâu hơn → door nhận.
    local function toposSlow(v, speed)
        -- speed arg giữ lại để không đổi signature/caller,
        -- nhưng tất cả movement tween hiện khóa 150 trong Movement.topos().
        pcall(function()
            if getdis(v) > 2500
                and getdis(TEMPLE_ENTRY_FAR_CF) < 1500
            then
                LocalPlayer.Character.Humanoid.Health = 0
            end
        end)

        local targetCf =
            typeof(v) == "CFrame"
            and v
            or CFrame.new(v)

        return Movement.topos(targetCf)
    end

    -- goToMyDoor: xa temple >3000 → requestEntrance throttle 4s; gần → toposSlow cửa (150 studs/s);
    -- snap sát cửa khi d<=35. Trả d<=25 (File A 880-901 + FIX 2026-07-04 tốc độ trial riêng).
    -- FIX (user 2026-07-04): ưu tiên WorldProbe.getTrialDoorCFrame() (toạ độ chuẩn có hướng),
    -- CHỈ fallback getDoorForRace() nếu không có manualCf. Snap sát cửa khi d<=35.
    function TempleManager.goToMyDoor()
        if Movement.getdis(CFrame.new(TEMPLE_ENTRY)) >= 3000 then
            if not RuntimeState.lastReqEntrance or (tick() - RuntimeState.lastReqEntrance) > 4 then
                RuntimeState.lastReqEntrance = tick()
                pcall(function()
                    ReplicatedStorage.Remotes.CommF_:InvokeServer("requestEntrance", TEMPLE_ENTRY)
                end)
            end
            Diagnostics.lastDoorSrc = "far"
            return false
        end
        local manualCf = WorldProbe.getTrialDoorCFrame()
        local targetCf, src, doorName
        if manualCf then
            targetCf, src, doorName = manualCf, "C", WorldProbe.normalizeRace(WorldProbe.getRace()) or "manual"
        else
            local door = WorldProbe.getDoorForRace()
            if not door then Diagnostics.lastDoorSrc = "noload"; return false end
            targetCf, src, doorName = door.CFrame, "R", door.Name
        end
        local char = LocalPlayer.Character
        if not (char and char:FindFirstChild("HumanoidRootPart")) then return false end
        pcall(function() toposSlow(targetCf, 150) end)
        local d = Movement.getdis(targetCf)
        -- snap sát cửa khi d<=35: teleport HRP = targetCf để đứng đúng vị trí + đúng hướng
        if d <= 35 then
            pcall(function()
                local hrp = char:FindFirstChild("HumanoidRootPart")
                if hrp then
                    Movement.cancel()
                    hrp.CFrame = targetCf
                end
            end)
            d = Movement.getdis(targetCf)
        end
        Diagnostics.lastDoorSrc, Diagnostics.lastDoorName, Diagnostics.lastDoorDist = src, doorName, d
        -- FIX (user 2026-07-04) — sau snap d<=35, quẹt trigger cửa 1 lần (áp dụng cả main + ally)
        -- để phòng ghost door (door load xong nhưng Touched event chưa register đúng frame).
        if d <= 25 then
            TempleManager.doorTouch(targetCf, "goToMyDoor_snap")
        end
        return d <= 25
    end

    -- FIX (user 2026-07-04) — doorTouch: quẹt HRP qua cửa 2-3 lần để "đánh thức" trigger
    -- khi door ghost. Mô phỏng thao tác người dùng bấm R + teleport lên/xuống rồi bay lại.
    -- ÁP DỤNG CẢ MAIN + ALLY (không phân biệt current main). Cooldown 1.5s để không spam.
    -- offsets = {0, 5, -3, 0}: từ giữa đi tới +5, lùi -3, về 0. Mỗi bước task.wait(0.08) → ~0.32s tổng.
    local _doorTouchCD = 0
    local DOOR_TOUCH_CD = 1.5
    function TempleManager.doorTouch(targetCf, reason)
        if not targetCf then return end
        local now = tick()
        if (now - _doorTouchCD) < DOOR_TOUCH_CD then return end
        _doorTouchCD = now
        pcall(function()
            if Movement.cancel then Movement.cancel() end
            local char = LocalPlayer and LocalPlayer.Character
            if not (char and char:FindFirstChild("HumanoidRootPart")) then return end
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local look = targetCf.LookVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            if flatLook.Magnitude <= 0 then flatLook = Vector3.new(0, 0, -1) end
            flatLook = flatLook.Unit
            local pos = targetCf.Position
            local offsets = {0, 5, -3, 0}
            for _, off in ipairs(offsets) do
                local p = pos + flatLook * off
                hrp.CFrame = CFrame.lookAt(p, p + flatLook)
                task.wait(0.08)
            end
            hrp.CFrame = targetCf
        end)
        Diagnostics.lastDoorSrc = "touch"
        if reason then Diagnostics.lastDoorTouchReason = reason end
    end
end
local function goToMyDoor() return TempleManager.goToMyDoor() end
local function templeState() return TempleManager.templeState() end
-- [FIX #7] phơi templeState cho CombatActions.observeCharacterInFFA (khai báo sau, dùng qua _G).
_G.KaitunTempleState = templeState

--[[ ============================================================================
 [10d] TRIALEVENTS — [FINAL §9/A4-A7] caller THẬT của CriticalEvents.emit tại lifecycle.
   Định nghĩa SAU templeState/WorldProbe để tham chiếu local hợp lệ. Đã forward-declare `TrialEvents`.
   - trial_entered / ffa_entered / ffa_left: gửi 1 lần / cycle (dedup theo cycleId + character).
   - ffa_presence: MỘT loop DUY NHẤT (~1s), tự dừng khi rời FFA/chết/teleport/đổi cycle/runtime stop.
   Tất cả no-op khi Config.enableEventProtocol=false hoặc V2 disabled (fallback route cũ).
============================================================================ ]]
do
    TrialEvents = {}
    local emittedTrialEntered = {}   -- key: cycleId..":"..charId
    local emittedFfaEntered   = {}
    local presenceRunning = false

    local function canV2()
        return Config.enableEventProtocol and CriticalEvents.enabled()
    end
    -- [FIX #1] charId() trả characterToken THẬT (không dùng tostring(Character) — trùng tên account →
    --   old==new → server reject). Fallback token nếu tracker chưa sẵn (không bao giờ trả tên account).
    local function charId()
        if _G.KaitunCharacterToken then
            local ok, tok = pcall(_G.KaitunCharacterToken)
            if ok and tok then return tok end
        end
        return State.characterToken or "nochar"
    end
    local function cid() return State.trialCycleId end

    -- §9.1 trial_entered — account xác nhận ĐÃ vào Trial Race (không chỉ đứng cửa).
    function TrialEvents.trialEntered(extra)
        if not canV2() then return end
        local c = cid()
        local key = tostring(c) .. ":" .. charId()
        if emittedTrialEntered[key] then return end
        emittedTrialEntered[key] = true
        local payload = {
            cycle_id = c, character_id = charId(),
            race = (WorldProbe and WorldProbe.getRace and WorldProbe.getRace()) or nil,
            gate_open = State.gateOpen == true,
            current_main = State.serverCurMain,
        }
        if extra then for k, v in pairs(extra) do payload[k] = v end end
        CriticalEvents.emit("trial_entered", payload)
    end

    -- §9.2 ffa_entered — CHỈ khi thật sự vào vùng FFA (templeState ffup). Account ngoài trio server reject.
    function TrialEvents.ffaEntered()
        if not canV2() then return end
        local c = cid()
        local key = tostring(c) .. ":" .. charId()
        if emittedFfaEntered[key] then return end
        emittedFfaEntered[key] = true
        State.postTrialPhase = "ffa"
        CriticalEvents.emit("ffa_entered", { cycle_id = c, character_id = charId() })
        TrialEvents.startPresence()
    end

    function TrialEvents.ffaLeft()
        if not canV2() then return end
        CriticalEvents.emit("ffa_left", { cycle_id = cid(), character_id = charId() })
    end

    -- §9.3/A7 FFA PRESENCE — MỘT loop duy nhất ~1s. Tự dừng đúng điều kiện.
    function TrialEvents.startPresence()
        if not canV2() then return end
        if presenceRunning then return end
        presenceRunning = true
        local myCycle = cid()
        local myChar = LocalPlayer.Character
        task.spawn(function()
            while Runtime.alive and presenceRunning do
                local c = LocalPlayer.Character
                local hum = c and c:FindFirstChild("Humanoid")
                local inFfa = (templeState() == "ffup")
                local alive = hum ~= nil and hum.Health > 0
                -- điều kiện dừng: rời FFA / chết / teleport / đổi cycle / đổi character / runtime stop
                if (not inFfa) or (not alive) or Runtime.teleporting
                   or cid() ~= myCycle or c ~= myChar then
                    if canV2() and cid() == myCycle then
                        CriticalEvents.emit("ffa_presence", {
                            cycle_id = myCycle, in_ffa = false, alive = alive,
                            character_id = charId(),   -- [FIX #1] token thật, không tostring(Character)
                        })
                    end
                    break
                end
                -- [FIX #2/#7] visible_allies TRI-STATE: chỉ gửi key khi observe ra true/false; thiếu = unknown.
                --   Ý nghĩa: true = Main xác nhận Ally trong FFA geometry, false = Ally ngoài FFA/mất server.
                --   KHÔNG dùng Players:FindFirstChild ~= nil (Player object sống dai qua respawn → luôn true).
                local visible = nil
                pcall(function()
                    visible = {}
                    for _, allyName in ipairs(Config.allies) do
                        local ap = Players:FindFirstChild(allyName)
                        local observed = _G.KaitunObserveAllyFFA and _G.KaitunObserveAllyFFA(ap) or nil
                        if observed ~= nil then visible[allyName] = observed end
                    end
                end)
                CriticalEvents.emit("ffa_presence", {
                    cycle_id = myCycle, in_ffa = true, alive = alive,
                    character_id = charId(), visible_allies = visible,  -- [FIX #1] token thật
                })
                task.wait(1)
            end
            presenceRunning = false
        end)
    end
    function TrialEvents.stopPresence() presenceRunning = false end
    function TrialEvents.presenceRunning() return presenceRunning end

    function TrialEvents.resetForNewCycle()
        emittedTrialEntered = {}
        emittedFfaEntered = {}
    end
end

--[[ ============================================================================
 [15] WORLD HELPERS — isnight / isfullmoon / isSamePlace. (File A 1130-1144)
============================================================================ ]]
local function isnight()
    local c = Lighting.ClockTime
    return (c >= 16 or c < 5)
end
-- FIX detect full moon (user 2026-07-02): MoonPhase attribute KHÔNG tụt ngay khi moon hết
-- (game báo "The full moon ends" nhưng attribute vẫn =5) → Ally tưởng còn moon, báo sai, /fmlost
-- không bao giờ bắn. Dùng Sky.MoonTextureId (asset THẬT, đổi ngay khi hết) như file tham khảo
-- kickendmoon.txt, + loại "fake moon" ban ngày (texture full nhưng ClockTime 5..12).
local FULLMOON_TEXTURE = "http://www.roblox.com/asset/?id=9709149431"
local function moonTextureId()
    local sky = Lighting:FindFirstChildOfClass("Sky")
    if sky and sky.MoonTextureId then return sky.MoonTextureId end
    return ""
end
-- true = đang full moon THẬT, false = không phải FM, nil = Sky chưa load (unknown, chưa kết luận).
-- Tách "chưa load" khỏi "không phải FM" để allyLeaderTick không bị kẹt pending khi Sky lag load.
local function isfullmoon()
    -- CHỈ 1 CÁCH: texture moon5 THẬT + gate ĐÊM, đúng theo kickendmoon.txt.
    local tex = moonTextureId()
    if tex == "" then return nil end            -- Sky chưa load → chưa kết luận, KHÔNG phải false
    if tex ~= FULLMOON_TEXTURE then return false end
    local c = Lighting.ClockTime
    return c <= 5 or c >= 18
end
_G.isfullmoon = isfullmoon   -- để heartbeat (khai báo trước) gọi được
-- Đếm tổng player + số ally đang ở server hiện tại (cho heartbeat → server xếp main theo
-- player và demote Main1 kẹt server full). Đếm distinct ally theo tên (State.isAlly).
local function countServerInfo()
    local players = #Players:GetPlayers()
    local seen, allies = {}, 0
    for _, p in ipairs(Players:GetPlayers()) do
        if State.isAlly[p.Name] and not seen[p.Name] then
            seen[p.Name] = true
            allies = allies + 1
        end
    end
    return players, allies
end
_G.countServerInfo = countServerInfo   -- heartbeat (khai báo trước) gọi qua _G như isfullmoon
local function isSamePlace(serverEntry)
    return serverEntry ~= nil and tonumber(serverEntry.placeid) == game.PlaceId
end

--[[ ============================================================================
 [16] TELEPORTMANAGER — hop fullmoon (cache 1h/placeid/player/blacklist 771) +
      hop server ít người (GetServers/HopServer) + cờ teleport riêng.
      (File A 604-708, 1146-1210)
============================================================================ ]]
local TeleportManager = {}
do
    local CACHE_FILE = "cache_v4.json"
    TeleportManager.deadJobs = {}

    local HOP_CONFIG = {
        MaxPlayers    = 6,
        CacheDuration = 60,
        MaxPages      = 100,
        RetryDelay    = 2,
    }

    function TeleportManager.markVisited(jobId)
        local data = FileStore.readJson(CACHE_FILE, {})
        data[jobId] = math.floor(tick())
        FileStore.writeJson(CACHE_FILE, data)
    end
    function TeleportManager.isSamePlace(entry) return isSamePlace(entry) end

    -- ===== HOP SERVER ÍT NGƯỜI (File A 611-708) =====
    local function _ifTableHaveIndex(j)
        for _ in pairs(j) do return true end
        return false
    end

    local _hopLastPull, _hopCachedServers
    function TeleportManager.getServers()
        if _hopLastPull and _hopCachedServers and (tick() - _hopLastPull) < HOP_CONFIG.CacheDuration then
            return _hopCachedServers
        end
        for i = 1, HOP_CONFIG.MaxPages do
            local ok, data = pcall(function()
                return ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer(i)
            end)
            if ok and data and _ifTableHaveIndex(data) then
                _hopLastPull = tick()
                _hopCachedServers = data
                return data
            end
        end
        DBG("[HOP] Không lấy được danh sách server!", "err")
        return nil
    end

    function TeleportManager.hopLowPlayer(Reason, MaxPlayers)
        MaxPlayers = MaxPlayers or HOP_CONFIG.MaxPlayers
        local Servers = TeleportManager.getServers()
        if not Servers then
            DBG("[HOP] Không có dữ liệu server → bỏ qua, vòng sau thử lại", "err")
            return false
        end
        local ArrayServers = {}
        for id, v in pairs(Servers) do
            if id ~= game.JobId and type(v) == "table" then
                table.insert(ArrayServers, { JobId = id, Players = v.Count or 0 })
            end
        end
        DBG(("[HOP] Nhận được %d server"):format(#ArrayServers), "ok")
        if #ArrayServers == 0 then
            DBG("[HOP] Danh sách server rỗng → bỏ qua", "err")
            return false
        end
        local Filtered = {}
        for _, s in ipairs(ArrayServers) do
            if (not MaxPlayers) or s.Players <= MaxPlayers then table.insert(Filtered, s) end
        end
        DBG(("[HOP] Sau lọc (<=%s người): %d server"):format(tostring(MaxPlayers), #Filtered), "ok")
        if #Filtered == 0 then
            DBG("[HOP] Không có server ít người → dùng toàn bộ danh sách", "err")
            Filtered = ArrayServers
        end
        local ServerData = Filtered[math.random(1, #Filtered)]
        RuntimeState.trainHopArmedT = tick()
        DBG(("[HOP] %s → teleport %s (Players=%d)"):format(tostring(Reason), tostring(ServerData.JobId), ServerData.Players), "ok")
        local ok = pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", ServerData.JobId)
        end)
        return ok
    end

    -- ===== CLEAN JOIN: hop tới 1 jobid do server chỉ định (throttle 5s/jobid) =====
    local _lastJobHop = {}
    function TeleportManager.hopToJob(jobid, reason)
        jobid = tostring(jobid or "")
        if jobid == "" or jobid == game.JobId then return false end
        -- HARD LOCK: Ally1 đang giữ locked fullmoon → KHÔNG hop sang server khác
        if State.myRole == "ally"
            and State.fullmoonLocked == true
            and State.fullmoonJobid and State.fullmoonJobid ~= ""
            and game.JobId == State.fullmoonJobid
            and jobid ~= State.fullmoonJobid
        then
            DBG("[ALLY1] BLOCK hop: holding locked fullmoon @ " .. tostring(State.fullmoonJobid), "warn", "ally1_block_hop")
            return false
        end
        if _lastJobHop[jobid] and (tick() - _lastJobHop[jobid]) < Config.RALLY_HOP_THROTTLE then return false end
        _lastJobHop[jobid] = tick()
        RuntimeState.rallyHopArmedT = tick()
        RuntimeState.lastRallyJob   = jobid
        DBG(("[RALLY] %s -> teleport %s"):format(tostring(reason), tostring(jobid)), "ok", "rally_hop")
        local ok = pcall(function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", jobid)
        end)
        return ok
    end

    -- Hop server ít người để TRAINING (dùng lại getServers + retry sẵn có)
    function TeleportManager.hopTrainingServer(reason)
        return TeleportManager.hopLowPlayer(reason or "[TRAINING]", 4)
    end

    -- ===== TeleportInitFailed: blacklist 771 + retry đúng cờ (File A 683-708) =====
    pcall(function()
        TeleportService.TeleportInitFailed:Connect(function(player, teleportResult, message)
            if player ~= LocalPlayer then return end
            Runtime.teleporting = false   -- chống kẹt teleporting=true khi fail
            -- (RALLY) Teleport tới jobid server chỉ định fail → báo Node reject (server tự tìm server khác)
            if RuntimeState.rallyHopArmedT and (tick() - RuntimeState.rallyHopArmedT) < 15 then
                local failedJob = RuntimeState.lastRallyJob
                RuntimeState.rallyHopArmedT = nil
                RuntimeState.lastRallyJob = nil
                -- FIX (user 2026-07-02) — GameFull = CHỜ SLOT, KHÔNG phá FullMoon:
                -- Main2-6 (hoặc Main1) hop vào full moon ĐÃ LOCK mà Roblox báo server ĐẦY (GameFull) →
                -- server chỉ đầy chứ KHÔNG chết. Nếu POST /rally/reject thì server sẽ XÓA fullmoonJobid +
                -- blacklist server FM tốt (index.js /rally/reject) → nuke cả lock Ally1 đang giữ. PHẢI:
                --   1) KHÔNG reject (giữ nguyên lock).
                --   2) Hạ status "waiting" ngay (setMyMainStatus: main-only, ally no-op) → gỡ kẹt "moon"
                --      (trước đây con này vòng nào cũng bị nhánh spam-join set lại "moon" → kẹt current mãi).
                --   3) Bật backoff FM_JOIN_BACKOFF giây → nhánh spam-join ngừng hop, chờ có người rời rồi thử lại.
                if teleportResult == Enum.TeleportResult.GameFull
                    and failedJob and failedJob ~= ""
                    and State.fullmoonJobid and failedJob == State.fullmoonJobid
                then
                    RuntimeState.fmJoinBackoffUntil = tick() + Config.FM_JOIN_BACKOFF
                    State.setMyMainStatus("waiting")
                    DBG("[FM-JOIN] Server FULL @ " .. tostring(failedJob)
                        .. " → chờ slot (waiting + backoff " .. tostring(Config.FM_JOIN_BACKOFF)
                        .. "s), KHÔNG reject/nuke FM", "warn", "fm_full_wait")
                    return
                end
                if failedJob and failedJob ~= "" then
                    TeleportManager.deadJobs[failedJob] = tick()
                    DBG("[RALLY] Teleport fail jobid=" .. tostring(failedJob) .. " -> reject", "err", "rally_fail")
                    pcall(function()
                        Net.postJSON(
                            endpoint("/rally/reject", { name = State.myName }),
                            { jobid = failedJob, reason = tostring(teleportResult), source = "teleport_fail" },
                            "rally_reject_" .. tostring(failedJob)
                        )
                    end)
                end
                return
            end
            -- (2) HOP ÍT NGƯỜI fail
            if RuntimeState.trainHopArmedT and (tick() - RuntimeState.trainHopArmedT) < 15 then
                RuntimeState.trainHopArmedT = nil
                if teleportResult == Enum.TeleportResult.GameFull then
                    DBG("[HOP] Server đầy → thử hop lại", "err")
                    task.delay(HOP_CONFIG.RetryDelay, function() TeleportManager.hopLowPlayer("Retry - Server đầy") end)
                else
                    DBG("[HOP] Teleport thất bại (" .. tostring(teleportResult) .. ") → thử server khác", "err")
                    task.delay(3, function() TeleportManager.hopLowPlayer("Retry - Teleport fail") end)
                end
                return
            end
            -- (3) ALLY hop fail → chỉ nhả cờ, vòng sau ally tự hop lại (không cướp retry khác)
            if RuntimeState.allyHopArmedT and (tick() - RuntimeState.allyHopArmedT) < 15 then
                RuntimeState.allyHopArmedT = nil
                DBG("[ALLY] Teleport fail (" .. tostring(teleportResult) .. ") → vòng sau hop lại", "err", "ally_tpfail")
            end
        end)
    end)
end
-- alias File A
local function HopServer(reason, maxp) return TeleportManager.hopLowPlayer(reason, maxp) end

--[[ ============================================================================
 [17] MAINQUEUE — thứ tự main (ưu tiên server /curmain, grace 8s). (File A 1378-1433)
============================================================================ ]]
local MainQueue = {}
do
    MainQueue._lastCurrent = nil

    function MainQueue.getOrder()
        if State.serverMainOrder and #State.serverMainOrder > 0 then return State.serverMainOrder end
        local active, waiting, finished = {}, {}, {}
        for _, name in ipairs(Config.mains) do
            local st = State.getMainStatus(name)
            if st == "offline" then
                -- bỏ qua: con đã rời → không tính hàng đợi
            elseif st == "moon" or st == "in_trail" then
                active[#active + 1] = name
            elseif st == "done" or st == "training" then
                finished[#finished + 1] = name
            else
                waiting[#waiting + 1] = name
            end
        end
        local order = {}
        for _, n in ipairs(active)   do order[#order + 1] = n end
        for _, n in ipairs(waiting)  do order[#order + 1] = n end
        for _, n in ipairs(finished) do order[#order + 1] = n end
        return order
    end

    function MainQueue.current()
        if State.serverCurMain then
            MainQueue._lastCurrent = State.serverCurMain
            return State.serverCurMain, 1
        end
        -- /curmain mất → giữ current cũ trong grace 8s (tránh nhảy main)
        if MainQueue._lastCurrent and (tick() - State._lastCurMainOK) < 8 then
            return MainQueue._lastCurrent, 1
        end
        local order = MainQueue.getOrder()
        if #order == 0 then return nil, nil end
        MainQueue._lastCurrent = order[1]
        return order[1], 1
    end

    function MainQueue.sttOf(name)
        for i, v in ipairs(MainQueue.getOrder()) do
            if v == name then return i end
        end
        return nil
    end

    -- cache-only mainJobCache; KHÔNG gọi mạng (File A 1424-1433)
    function MainQueue.isSameServerAsMain(mainName)
        if not mainName then return false, nil end
        local c = State.mainJobCache[mainName]
        if not c or not c.jobid then return false, nil end
        local fresh = (gettimeserver() - (c.time or 0)) < 60
        local same  = fresh and (c.jobid == game.JobId)
        return same, c.jobid
    end
end
-- alias File A
local function getCurrentMainBeingUpgraded() return MainQueue.current() end
local function mainSttOf(name) return MainQueue.sttOf(name) end
local function isSameServerAsMain(name) return MainQueue.isSameServerAsMain(name) end

--[[ ============================================================================
 [18] COMBATACTIONS — getmob1/checkmob_/getplayers/countplayers/attackTick/
      getallweapon/EquipTool/spam-skills/BringMob/GetMobPosition/TweenObject +
      FastAttack/AttackNoCoolDown. (File A 1214-1517, 2039-2395)
============================================================================ ]]
local CombatActions = {}
do
    local LP = LocalPlayer

    -- vị trí 6 ô player trong trial (File A 944-951)
    CombatActions.pos_plr_trial = {
        CFrame.new(28692.3477, 14887.5605, -53.7669983, 0.707131445, -0, -0.707082093, 0, 1, -0, 0.707082093, 0, 0.707131445),
        CFrame.new(28782.7246, 14898.9902, -59.6069946, 0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, 0.707134247),
        CFrame.new(28700.875, 14888.2598, -154.110992, -1, 0, 0, 0, 1, 0, 0, 0, -1),
        CFrame.new(28795.7715, 14888.2598, -112.917999, -0.707134247, 0, 0.707079291, 0, 1, 0, -0.707079291, 0, -0.707134247),
        CFrame.new(28658.4551, 14888.2598, -121.372009, -0.515037298, 0, -0.857167721, 0, 1, 0, 0.857167721, 0, -0.515037298),
        CFrame.new(28742.4688, 14887.5596, -18.2120056, 0.92051065, 0, 0.390717506, 0, 1, 0, -0.390717506, 0, 0.92051065),
    }

    -- [FIX #2/#7] observeCharacterInFFA — TRI-STATE quan sát 1 Ally có ĐANG trong vùng FFA hay không.
    --   Trả:  true  = chắc chắn trong FFA (Character sống + trong INNER box)
    --         false = chắc chắn NGOÀI FFA / không còn server (Player object mất, HOẶC Character sống ngoài OUTER box)
    --         nil   = KHÔNG đủ dữ liệu (Character nil/đang respawn, HRP/Humanoid thiếu, FF toàn cục chưa ffup,
    --                 hoặc đứng ở VÙNG ĐỆM giữa inner/outer) → server coi là "unknown", KHÔNG phải false.
    --   Geometry-derived heuristic từ 6 CombatActions.pos_plr_trial (KHÔNG dùng FFABorder — chưa rõ Part/Model).
    --   Margins để trong Config.ffaZone để chỉnh trong Roblox mà không sửa flow. ROBLOX-RUNTIME UNVERIFIED.
    do
        -- bounding box của 6 ô player + margin (studs). Y gần phẳng nên margin Y rộng riêng.
        local zoneCfg = (Config and Config.ffaZone) or {}
        local INNER = zoneCfg.innerMargin or 70    -- trong box+70 → chắc chắn trong FFA
        local OUTER = zoneCfg.outerMargin or 160   -- ngoài box+160 → chắc chắn ngoài FFA
        local YIN   = zoneCfg.innerMarginY or 40
        local YOUT  = zoneCfg.outerMarginY or 90
        local minX, minY, minZ = math.huge, math.huge, math.huge
        local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
        for _, cf in ipairs(CombatActions.pos_plr_trial) do
            local p = cf.Position
            if p.X < minX then minX = p.X end; if p.X > maxX then maxX = p.X end
            if p.Y < minY then minY = p.Y end; if p.Y > maxY then maxY = p.Y end
            if p.Z < minZ then minZ = p.Z end; if p.Z > maxZ then maxZ = p.Z end
        end
        local function inBox(pos, mX, mY, mZ)
            return pos.X >= (minX - mX) and pos.X <= (maxX + mX)
               and pos.Y >= (minY - mY) and pos.Y <= (maxY + mY)
               and pos.Z >= (minZ - mZ) and pos.Z <= (maxZ + mZ)
        end
        function CombatActions.observeCharacterInFFA(player)
            if not player then return false end          -- không còn trong server → chắc chắn ngoài FFA
            local character = player.Character
            if not character then return nil end          -- đang respawn / chưa replicate
            local humanoid = character:FindFirstChildOfClass("Humanoid")
            local root = character:FindFirstChild("HumanoidRootPart")
            if not humanoid or not root then return nil end
            if humanoid.Health <= 0 then return nil end    -- đang chết → chưa kết luận
            -- FF toàn cục chưa bật → không kết luận (trận FFA chưa/không diễn ra)
            local ts = _G.KaitunTempleState and _G.KaitunTempleState() or nil
            if ts ~= "ffup" then return nil end
            local pos = root.Position
            if inBox(pos, INNER, YIN, INNER) then return true end       -- trong inner → true
            if not inBox(pos, OUTER, YOUT, OUTER) then return false end  -- ngoài outer → false
            return nil                                                   -- vùng đệm → unknown
        end
        _G.KaitunObserveAllyFFA = CombatActions.observeCharacterInFFA
    end

    function CombatActions.getmob1(pos)
        local allmobs = {}
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            if v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid")
                and v.Humanoid.Health > 0 and Movement.getdis(v.HumanoidRootPart.CFrame, pos) < 1000 then
                table.insert(allmobs, v)
            end
        end
        return allmobs
    end
    function CombatActions.checkmob_(v)
        return v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0
    end

    local function noideaforname(v)
        if State.isAlly[v.Name] then return false end
        return true
    end
    -- Quét động người còn sống trong toàn vùng FFA.
    -- Trả record { player, character }, nhờ vậy Character đầu cycle được giữ ổn định khi target chết/respawn.
    -- eliminated[userId]=true: người đã chết trong lượt này, respawn cũng KHÔNG đánh lại.
    -- seen[userId]=true: từng quan sát thấy trong FFA; Character nil tạm thời được tính unknown để chặn thắng giả.
    function CombatActions.getplayers(eliminated, seen, participantCharacters, opts)
        eliminated = eliminated or {}
        seen = seen or {}
        participantCharacters = participantCharacters or {}
        opts = opts or {}
        -- Post-trial fallback: Ally bình thường tự reset, nhưng nếu sau grace vẫn còn sống trong FFA
        -- thì Main phải được phép đánh họ để không đứng im/kẹt lượt. Các Main khác vẫn luôn bị loại.
        local includeAllies = opts.includeAllies == true
        local targets = {}
        local unknown = 0
        local myRoot = Movement.getHRP()

        for _, player in ipairs(Players:GetPlayers()) do
            local userId = player.UserId
            local includeAllPlayers = opts.includeAllPlayers == true
            if player ~= LP
                and (includeAllPlayers or not State.isMain[player.Name])
                and (includeAllies or noideaforname(player))
                and not eliminated[userId] then
                local character = player.Character
                local knownCharacter = participantCharacters[userId]

                -- Cùng Player nhưng Character đã đổi: Character cũ đã chết và người này đã bị loại.
                if knownCharacter and character ~= knownCharacter then
                    eliminated[userId] = true
                else
                    local hum = character and character:FindFirstChildOfClass("Humanoid")
                    local root = character and character:FindFirstChild("HumanoidRootPart")

                    if hum and root then
                        if hum.Health > 0 then
                            local observed = CombatActions.observeCharacterInFFA(player)
                            -- Fallback kiểu kkv4: nếu geometry báo false nhưng Player vẫn ở gần khu Trial,
                            -- vẫn nhận target. Điều này xử lý Character bị lệch Y/ở dưới nền sau FFA.
                            local nearLegacyTrial = false
                            for _, trialPos in ipairs(CombatActions.pos_plr_trial) do
                                if Movement.getdis(root.CFrame, trialPos) < 350 then
                                    nearLegacyTrial = true
                                    break
                                end
                            end
                            if observed ~= false or nearLegacyTrial then
                                seen[userId] = true
                                participantCharacters[userId] = participantCharacters[userId] or character
                                targets[#targets + 1] = { player = player, character = participantCharacters[userId] }
                            end
                        elseif seen[userId] then
                            eliminated[userId] = true
                        end
                    elseif seen[userId] then
                        unknown = unknown + 1
                    end
                end
            end
        end

        -- Chọn người gần Main trước để giảm tween chéo và tránh đổi target lung tung.
        table.sort(targets, function(a, b)
            local ar = a.character and a.character:FindFirstChild("HumanoidRootPart")
            local br = b.character and b.character:FindFirstChild("HumanoidRootPart")
            if not myRoot then return a.player.UserId < b.player.UserId end
            local ad = ar and (ar.Position - myRoot.Position).Magnitude or math.huge
            local bd = br and (br.Position - myRoot.Position).Magnitude or math.huge
            if ad == bd then return a.player.UserId < b.player.UserId end
            return ad < bd
        end)

        return targets, unknown
    end
    function CombatActions.countplayers(eliminated, seen, participantCharacters, opts)
        local targets, unknown = CombatActions.getplayers(eliminated, seen, participantCharacters, opts)
        return #targets, unknown
    end

    -- [FINAL §J1] attackTick: KHÔNG spam M1 toàn cục nữa. Mặc định chỉ di chuyển + equip/haki + FastAttack nền.
    --   M1 (Tool:Activate + LeftClickRemote) CHỈ chạy khi caller truyền opts.m1=true (post-trial PVP / boss fallback)
    --   VÀ khoảng cách thật <= M1_RANGE studs. Throttle chung 0.14s (§J4).
    local _atkOff, _atkT, _atkEqT = CFrame.new(0, 3, 0), 0, 0
    local _atkMoveT = 0
    local _lastM1Tick = 0
    local M1_RANGE = 11        -- §J4: chỉ M1 khi <= 9–12 studs
    local M1_THROTTLE = 0.14   -- §J4: 0.10–0.18s throttle chung
    -- Helper M1 dùng chung (throttle + equip đúng Tool). Trả true nếu đã bấm.
    function CombatActions.doM1(target)
        if (tick() - _lastM1Tick) <= M1_THROTTLE then return false end
        local char = LP.Character
        local hrp = target and target:FindFirstChild("HumanoidRootPart")
        local myHrp = char and char:FindFirstChild("HumanoidRootPart")
        if not (char and hrp and myHrp) then return false end
        -- §J4: chỉ M1 khi khoảng cách thật <= M1_RANGE
        if (hrp.Position - myHrp.Position).Magnitude > M1_RANGE then return false end
        _lastM1Tick = tick()
        pcall(function()
            local tool = char:FindFirstChildOfClass("Tool")
            if tool then
                tool:Activate()
                local remote = tool:FindFirstChild("LeftClickRemote")
                if remote then
                    local direction = (hrp.Position - char:GetPivot().Position).Unit
                    remote:FireServer(direction, 1)
                end
            end
        end)
        return true
    end

    function CombatActions.attackTick(target, opts)
        if tick() - _atkT > 0.3 then
            _atkT = tick()
            local x, z = math.random(1, 4), math.random(1, 4)
            if math.random(1, 2) == 1 then x = -x end
            if math.random(1, 2) == 1 then z = -z end
            _atkOff = CFrame.new(x, 3, z)
        end
        _G.SHOULDSPAMSKILLS = true
        if tick() - _atkEqT > 0.4 then
            _atkEqT = tick()
            pcall(function() Movement.equip() end)
            pcall(function() Movement.haki() end)
        end
        local hrp = target and target:FindFirstChild("HumanoidRootPart")
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if hrp and myHrp then
            -- Không gọi topos mỗi frame: Movement.topos() luôn cancel tween cũ, gọi quá dày sẽ
            -- khiến tween bị restart liên tục và nhìn như Main đứng im. Ở gần thì đặt sát target;
            -- ở xa chỉ cập nhật tween theo nhịp 0.18s.
            local targetCFrame = hrp.CFrame * _atkOff
            local dist = (targetCFrame.Position - myHrp.Position).Magnitude
            if dist <= 10 then
                Movement.cancel()
                myHrp.CFrame = CFrame.lookAt(targetCFrame.Position, hrp.Position)
                myHrp.AssemblyLinearVelocity = Vector3.zero
                myHrp.AssemblyAngularVelocity = Vector3.zero
            elseif (tick() - _atkMoveT) >= 0.18 then
                _atkMoveT = tick()
                pcall(function() topos(CFrame.lookAt(targetCFrame.Position, hrp.Position)) end)
            end

            if opts and opts.skillAim then
                CombatActions.setSkillAimTarget(hrp.Position + Vector3.new(0, 2, 0))
            end
        end
        -- [FINAL §J1] M1 CHỈ khi được yêu cầu rõ (opts.m1) — KHÔNG mặc định spam cho mọi target mỗi 0.1s.
        if opts and opts.m1 then CombatActions.doM1(target) end
    end

    -- Kill Player After Trial: cách đánh lấy từ kkv4.lua.txt, nhưng thêm throttle để
    -- Movement.topos() không cancel/restart tween ở mọi frame. Mỗi tick: equip + haki,
    -- bay sát Player với offset ngẫu nhiên, bật spam skill, aim vào target và M1 khi đủ gần.
    local _kkv4PvpOffset = CFrame.new(0, 3, 0)
    local _kkv4PvpOffsetAt = 0
    local _kkv4PvpMoveAt = 0
    local _kkv4PvpEquipAt = 0
    function CombatActions.attackPlayerKKV4Tick(target)
        local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
        local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
        local myChar = LP.Character
        local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not (targetRoot and targetHumanoid and targetHumanoid.Health > 0 and myRoot) then
            return false
        end

        _G.SHOULDSPAMSKILLS = true
        CombatActions.setSkillAimTarget(targetRoot.Position + Vector3.new(0, 2, 0))

        if (tick() - _kkv4PvpEquipAt) >= 0.35 then
            _kkv4PvpEquipAt = tick()
            pcall(function() Movement.equip() end)
            pcall(function() Movement.haki() end)
        end

        if (tick() - _kkv4PvpOffsetAt) >= 0.30 then
            _kkv4PvpOffsetAt = tick()
            local x = math.random(1, 4)
            local z = math.random(1, 4)
            if math.random(1, 2) == 1 then x = -x end
            if math.random(1, 2) == 1 then z = -z end
            _kkv4PvpOffset = CFrame.new(x, 3, z)
        end

        local targetCFrame = targetRoot.CFrame * _kkv4PvpOffset
        local dist = (targetCFrame.Position - myRoot.Position).Magnitude
        if dist <= 9 then
            Movement.cancel()
            myRoot.CFrame = CFrame.lookAt(targetCFrame.Position, targetRoot.Position)
            myRoot.AssemblyLinearVelocity = Vector3.zero
            myRoot.AssemblyAngularVelocity = Vector3.zero
        elseif (tick() - _kkv4PvpMoveAt) >= 0.18 then
            _kkv4PvpMoveAt = tick()
            pcall(function()
                topos(CFrame.lookAt(targetCFrame.Position, targetRoot.Position))
            end)
        end

        CombatActions.doM1(target)
        return true
    end

    -- weapon / spam-skills (File A 2039-2123)
    local fruits = {
        ['Buddha-Buddha'] = true, ['T-Rex-T-Rex'] = true, ['Dragon-Dragon'] = true, ['Yeti-Yeti'] = true,
        ['Leopard-Leopard'] = true, ['Venom-Venom'] = true, ['Phoenix-Phoenix'] = true, ['Kitsune-Kitsune'] = true,
        ['Mammoth-Mammoth'] = true, ['Gas-Gas'] = true, ["Portal-Portal"] = true,
    }
    local isvalidtooltip = { ["Melee"] = true, ["Blox Fruit"] = true, ["Sword"] = true, ["Gun"] = true }
    local isvalidnameui  = { ["Z"] = true, ["X"] = true, ["C"] = true, ["V"] = true, ["F"] = true }

    local function getallweapon()
        local weapon = {}
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            for _, v in pairs(bp:GetChildren()) do
                if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
            end
        end
        if LP.Character then
            for _, v in pairs(LP.Character:GetChildren()) do
                if v:IsA("Tool") and isvalidtooltip[v.ToolTip] then table.insert(weapon, v) end
            end
        end
        return weapon
    end
    local function EquipTool(v)
        local bp = LP:FindFirstChild("Backpack")
        local thua = bp and bp:FindFirstChild(v)
        if thua and LP.Character and LP.Character:FindFirstChild("Humanoid") then
            LP.Character.Humanoid:EquipTool(thua)
        end
    end

    -- Fish Trial only: ưu tiên kiếm đang CẦM, sau đó Backpack, cuối cùng mới LoadItem.
    -- Nhận diện tên không phân biệt hoa/thường; LoadItem giữ các fallback theo yêu cầu.
    local FISH_TRIAL_LOAD_NAMES = { "Tushita", "tushita", "Yama", "yama" }
    local fishTrialSwordState = {
        cycleKey = nil,
        character = nil,
        selectedName = nil, -- tên Tool thật trong game
        active = false,     -- khi true, spam-skills chỉ dùng đúng kiếm Fish Trial
        lastMissingTryAt = 0,
    }

    local function isFishTrialSwordName(name)
        local lower = tostring(name or ""):lower()
        return lower == "tushita" or lower == "yama"
    end

    local function findFishTrialSword(container, preferredName)
        if not container then return nil end
        local children = container:GetChildren()
        local preferred = preferredName and tostring(preferredName):lower() or nil

        if preferred then
            for _, child in ipairs(children) do
                if child:IsA("Tool") and child.Name:lower() == preferred and isFishTrialSwordName(child.Name) then
                    return child
                end
            end
            return nil
        end

        -- Khi có cả hai trong Backpack, luôn ưu tiên Tushita trước Yama.
        for _, wanted in ipairs({ "tushita", "yama" }) do
            for _, child in ipairs(children) do
                if child:IsA("Tool") and child.Name:lower() == wanted then
                    return child
                end
            end
        end
        return nil
    end

    local function resetFishSwordStateForCycle(char)
        local cycleKey = tostring(
            State.trialStartedCycleId
            or State.trialCycleId
            or State.trialStartedAt
            or game.JobId
        )
        if fishTrialSwordState.character ~= char or fishTrialSwordState.cycleKey ~= cycleKey then
            fishTrialSwordState.character = char
            fishTrialSwordState.cycleKey = cycleKey
            fishTrialSwordState.selectedName = nil
            fishTrialSwordState.active = false
            fishTrialSwordState.lastMissingTryAt = 0
        end
    end

    function CombatActions.equipFishTrialSword()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and hum.Health > 0) then return nil end
        resetFishSwordStateForCycle(char)

        -- 1) Đang cầm Tushita/Yama: dùng luôn, tuyệt đối không gọi LoadItem.
        local held = findFishTrialSword(char, fishTrialSwordState.selectedName)
            or findFishTrialSword(char)
        if held then
            fishTrialSwordState.selectedName = held.Name
            fishTrialSwordState.active = true
            return held.Name
        end

        -- 2) Có trong Backpack: EquipTool trực tiếp, không gọi LoadItem.
        local bp = LP:FindFirstChild("Backpack")
        local stored = findFishTrialSword(bp, fishTrialSwordState.selectedName)
            or findFishTrialSword(bp)
        if stored then
            pcall(function() hum:EquipTool(stored) end)
            task.wait()
            local equipped = findFishTrialSword(char, stored.Name) or findFishTrialSword(char)
            if equipped then
                fishTrialSwordState.selectedName = equipped.Name
                fishTrialSwordState.active = true
                Logger.info("Fish Trial sword: equipped from Backpack " .. equipped.Name, "fish_trial_sword_ok")
                return equipped.Name
            end
        end

        -- 3) Chỉ khi Character + Backpack đều không có mới thử LoadItem.
        -- Cooldown tránh doTrialForMyRace() gọi lặp và spam remote khi account không sở hữu kiếm.
        if fishTrialSwordState.lastMissingTryAt > 0
            and (tick() - fishTrialSwordState.lastMissingTryAt) < 8 then
            fishTrialSwordState.active = false
            return nil
        end
        fishTrialSwordState.lastMissingTryAt = tick()

        for _, loadName in ipairs(FISH_TRIAL_LOAD_NAMES) do
            SafeRemote.invoke(0.8, "LoadItem", loadName)
            task.wait(0.12)

            char = LP.Character
            hum = char and char:FindFirstChildOfClass("Humanoid")
            bp = LP:FindFirstChild("Backpack")
            if not (char and hum and hum.Health > 0) then break end

            held = findFishTrialSword(char)
            stored = findFishTrialSword(bp)
            if not held and stored then
                pcall(function() hum:EquipTool(stored) end)
                task.wait()
                held = findFishTrialSword(char, stored.Name) or findFishTrialSword(char)
            end

            if held then
                fishTrialSwordState.selectedName = held.Name
                fishTrialSwordState.active = true
                Logger.info("Fish Trial sword: loaded and equipped " .. held.Name, "fish_trial_sword_ok")
                return held.Name
            end
        end

        fishTrialSwordState.selectedName = nil
        fishTrialSwordState.active = false
        Logger.warn("Fish Trial sword: không có Tushita/Yama, tiếp tục bằng vũ khí hiện có", "fish_trial_sword_missing")
        return nil
    end

    function CombatActions.endFishTrialSwordMode()
        fishTrialSwordState.active = false
    end

    local function getFishTrialSwordForSpam(char)
        if not (fishTrialSwordState.active and fishTrialSwordState.selectedName) then return nil end
        local held = findFishTrialSword(char, fishTrialSwordState.selectedName)
        if held then return held end

        local bp = LP:FindFirstChild("Backpack")
        local stored = findFishTrialSword(bp, fishTrialSwordState.selectedName)
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if stored and hum and hum.Health > 0 then
            pcall(function() hum:EquipTool(stored) end)
            return findFishTrialSword(char, stored.Name) or stored
        end
        return nil
    end

    -- GetMobPosition / TweenObject / BringMob (File A 1457-1517)
    local function TweenObject(Object, Pos, Speed)
        -- Speed arg giữ để không đổi API cũ.
        -- Core mới khóa mọi movement tween ở 150 studs/s.
        return Movement.tweenObject(Object, Pos)
    end
    local function GetMobPosition(EnemiesName)
        local pos = Vector3.new(0, 0, 0)
        local count = 0
        for _, v in pairs(workspace.Enemies:GetChildren()) do
            if v.Name == EnemiesName and v:FindFirstChild("HumanoidRootPart") then
                pos = pos + v.HumanoidRootPart.Position
                count = count + 1
            end
        end
        if count > 0 then return pos / count end
        return nil
    end
    function CombatActions.BringMob()
        local myHrp = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
        if not myHrp then return end
        local ememe = workspace.Enemies:GetChildren()
        if #ememe > 0 then
            local totalpos = {}
            for _, v in pairs(ememe) do
                if not totalpos[v.Name] then totalpos[v.Name] = GetMobPosition(v.Name) end
            end
            for _, v in pairs(workspace.Enemies:GetChildren()) do
                local hum = v:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                    if (v.HumanoidRootPart.Position - myHrp.Position).Magnitude <= 350 then
                        for k, f in pairs(totalpos) do
                            if k and v.Name == k and f then
                                local dest = CFrame.new(f.X, f.Y, f.Z)
                                local d = (v.HumanoidRootPart.Position - dest.Position).Magnitude
                                if d > 3 and d <= 280 then
                                    TweenObject(v.HumanoidRootPart, dest)
                                    v.HumanoidRootPart.CanCollide = false
                                    v.Humanoid.WalkSpeed = 0
                                    v.Humanoid.JumpPower = 0
                                    v.Humanoid:ChangeState(14)
                                    pcall(function() sethiddenproperty(LP, "SimulationRadius", math.huge) end)
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- ===== V3 COMBAT (port từ V3.txt) — CHỈ DÙNG KHI TRAINING =====
    -- Lý do: FastAttack V4 (LeftClickRemote:FireServer) đôi lúc lơ lửng trên đầu quái mà KHÔNG gây damage
    -- (đứng bãi quái không đánh được sau vài bãi). V3 dùng RE/RegisterAttack + RE/RegisterHit + remote mã hoá
    -- (remoteAttack có attribute "Id", XOR theo GetServerTimeNow + seed) → đánh ăn chắc. Gom quái kiểu V3
    -- (BringMonster): kéo quái về 1 điểm để đánh gọn. Chỉ gọi trong doTrainGrind (training/raiding).
    local _v3 = { seed = nil, remoteAttack = nil, idremote = nil, ready = false, lastTry = 0, lastFA = 0, seedFetching = false }
    local _cloneref = (cloneref or clonereference or function(x) return x end)
    local _v3Names = { "Util", "Common", "Remotes", "Assets", "FX" }
    local function _v3ScanRemote()
        for _, nm in ipairs(_v3Names) do
            local container = ReplicatedStorage:FindFirstChild(nm)
            if container then
                for _, n in ipairs(container:GetChildren()) do
                    if n:IsA("RemoteEvent") and n:GetAttribute("Id") then
                        _v3.remoteAttack, _v3.idremote = n, n:GetAttribute("Id")
                    end
                end
            end
        end
    end
    local function _v3Init()
        if _v3.ready then return true end
        if (tick() - _v3.lastTry) < 1 then return false end
        _v3.lastTry = tick()
        pcall(_v3ScanRemote)
        -- FIX (user 2026-07-02): seed:InvokeServer() là RemoteFunction ĐỒNG BỘ, không timeout — gọi thẳng
        -- trên hot-path (đầu doTrainGrind + trong v3FastAttack, cả 2 chạy trong StateMachine.tick) → server
        -- chậm/không trả sẽ YIELD treo cả main loop. Fetch seed 1 lần ở THREAD NỀN, cache lại; _v3Init được
        -- gọi lại mỗi ~1s nên khi seed về thì ready bật, không block nhịp tick nào.
        if _v3.seed == nil and not _v3.seedFetching then
            _v3.seedFetching = true
            task.spawn(function()
                local ok, s = pcall(function()
                    return ReplicatedStorage.Modules.Net.seed:InvokeServer()
                end)
                if ok then _v3.seed = s end
                _v3.seedFetching = false
            end)
        end
        _v3.ready = (_v3.seed ~= nil and _v3.remoteAttack ~= nil and _v3.idremote ~= nil)
        return _v3.ready
    end
    CombatActions.initV3Combat = _v3Init

    -- watcher: remoteAttack có thể xuất hiện/đổi sau khi load → bám ChildAdded để cập nhật id
    function CombatActions.startV3CombatWatch()
        _v3Init()
        for _, nm in ipairs(_v3Names) do
            local container = ReplicatedStorage:FindFirstChild(nm)
            if container then
                container.ChildAdded:Connect(function(n)
                    if n:IsA("RemoteEvent") and n:GetAttribute("Id") then
                        _v3.remoteAttack, _v3.idremote = n, n:GetAttribute("Id")
                        _v3.ready = (_v3.seed ~= nil and _v3.remoteAttack ~= nil and _v3.idremote ~= nil)
                    end
                end)
            end
        end
    end

    -- v3FastAttack: RE/RegisterAttack + RE/RegisterHit + remote mã hoá (đánh mọi quái trong 65 studs)
    function CombatActions.v3FastAttack(onlyName)
        if not _v3.ready and not _v3Init() then return end
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildWhichIsA("Humanoid")
        -- FIX (user 2026-07-02): KHÔNG bắt buộc phải cầm Tool. Acc train bằng FIGHTING STYLE (vd Dragon
        -- Talon) hoặc fist thì Character KHÔNG có Tool instance → guard cũ return sớm → đứng trên đầu bãi
        -- quái mà không đánh (nhất là sau khi V4 transform tắt, tool bị unequip). RegisterHit vẫn ăn với
        -- đòn M1 fighting style. Chỉ cần còn sống là đánh.
        if not (hrp and hum and hum.Health > 0) then return end
        if (tick() - _v3.lastFA) <= 0.01 then return end
        local t = {}
        for _, folderName in ipairs({ "Characters", "Enemies" }) do
            local u = workspace:FindFirstChild(folderName)
            if u then
                for _, e in ipairs(u:GetChildren()) do
                    local eh = e:FindFirstChildWhichIsA("Humanoid")
                    local ehrp = e:FindFirstChild("HumanoidRootPart")
                    if e ~= char and (not onlyName or e.Name == onlyName)
                        and eh and ehrp and eh.Health > 0
                        and (ehrp.Position - hrp.Position).Magnitude <= 65 then
                        t[#t + 1] = e
                    end
                end
            end
        end
        if #t == 0 then return end
        local hitTbl = { [2] = {} }
        for i = 1, #t do
            local v = t[i]
            local part = v:FindFirstChild("Head") or v:FindFirstChild("HumanoidRootPart")
            if not hitTbl[1] then hitTbl[1] = part end
            hitTbl[2][#hitTbl[2] + 1] = { v, part }
        end
        pcall(function()
            local n = ReplicatedStorage.Modules.Net
            n:FindFirstChild("RE/RegisterAttack"):FireServer()
            n:FindFirstChild("RE/RegisterHit"):FireServer(unpack(hitTbl))
            _cloneref(_v3.remoteAttack):FireServer(string.gsub("RE/RegisterHit", ".", function(c)
                return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
            end), bit32.bxor(_v3.idremote + 909090, _v3.seed * 2), unpack(hitTbl))
        end)
        _v3.lastFA = tick()
    end

    -- v3BringMob: gom quái về 1 điểm (anchorCF nếu có, mặc định vị trí quái đầu tiên) trong tầm count*250
    function CombatActions.v3BringMob(onlyName, count, anchorCF)
        count = count or 3
        if count < 2 then return end
        local char = LP.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end
        pcall(function() setscriptable(LP, "SimulationRadius", true) end)
        pcall(function() sethiddenproperty(LP, "SimulationRadius", math.huge) end)
        pcall(function()
            local mob, anchor = {}, anchorCF
            for _, v in ipairs(workspace.Enemies:GetChildren()) do
                local h = v:FindFirstChildWhichIsA("Humanoid")
                local vhrp = v:FindFirstChild("HumanoidRootPart")
                if h and vhrp and h.Health > 0 and (not onlyName or v.Name == onlyName)
                    and (hrp.Position - vhrp.Position).Magnitude <= (count * 250) then
                    local dup = false
                    for _, chosen in ipairs(mob) do
                        local chrp = chosen:FindFirstChild("HumanoidRootPart")
                        if chrp and (vhrp.Position - chrp.Position).Magnitude <= 5 then dup = true; break end
                    end
                    if not dup then
                        mob[#mob + 1] = v
                        anchor = anchor or vhrp.CFrame
                    end
                    if #mob >= count then break end
                end
            end
            if not anchor then return end
            for i = 1, #mob do
                local vhrp = mob[i]:FindFirstChild("HumanoidRootPart")
                -- FIX (user 2026-07-02): select(1,pcall) = success bool, KHÔNG phải kết quả isnetworkowner
                -- → guard cũ thành no-op, teleport CẢ mob không sở hữu → server revert (rubber-band) +
                -- mất network-owner → RegisterHit không ăn = GHOST QUÁI. select(2) đọc đúng giá trị trả về;
                -- chỉ teleport khi ta THẬT sở hữu network của mob (khớp V3: if isnetworkowner(hrp)).
                local owned = true
                if isnetworkowner then owned = (select(2, pcall(isnetworkowner, vhrp)) == true) end
                if vhrp and owned then
                    vhrp.AssemblyLinearVelocity = Vector3.zero
                    vhrp.AssemblyAngularVelocity = Vector3.zero
                    vhrp.CFrame = anchor * CFrame.new((i - 1) * 2, 0, 0)
                end
            end
        end)
    end

    -- [FISH TRIAL AIM] Aim target tạm thời cho skill do LocalScript của game gửi Remote.
    -- Hook chỉ sửa Vector3/CFrame khi: target đang bật + SHOULDSPAMSKILLS=true + call đến từ game
    -- (checkcaller=false). Vì vậy BuySharkman/HTTP/remote do chính script gọi không bị đụng.
    do
        local aimState = { target = nil, installed = false, installFailed = false }

        local function resolveAimPosition(target)
            local kind = typeof(target)
            if kind == "Vector3" then return target end
            if kind == "CFrame" then return target.Position end
            if kind == "Instance" then
                if target:IsA("BasePart") then return target.Position end
                if target:IsA("Model") then
                    local part = target:FindFirstChild("HumanoidRootPart")
                        or target.PrimaryPart
                        or target:FindFirstChildWhichIsA("BasePart", true)
                    return part and part.Position or nil
                end
            end
            return nil
        end

        local function rewriteAimArgs(oldNamecall, self, ...)
            local method = getnamecallmethod()
            local target = aimState.target
            if target
                and (_G.SHOULDSPAMSKILLS or RuntimeState.fragmentTyrantSkillCasting == true)
                and not checkcaller()
                and (method == "FireServer" or method == "InvokeServer") then
                local args = { ... }
                for i = 1, #args do
                    local kind = typeof(args[i])
                    if kind == "Vector3" then
                        args[i] = target
                        return oldNamecall(self, unpack(args))
                    elseif kind == "CFrame" then
                        args[i] = CFrame.new(target)
                        return oldNamecall(self, unpack(args))
                    end
                end
            end
            return oldNamecall(self, ...)
        end

        function CombatActions.installSkillAim()
            if aimState.installed then return true end
            if aimState.installFailed then return false end
            if type(newcclosure) ~= "function" or type(getnamecallmethod) ~= "function"
                or type(checkcaller) ~= "function" then
                aimState.installFailed = true
                Logger.warn("Fish Trial aim: executor thiếu metamethod API; vẫn hạ độ cao nhưng không khóa remote aim", "fish_aim_api")
                return false
            end

            local ok, err = pcall(function()
                if type(hookmetamethod) == "function" then
                    local oldNamecall
                    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
                        return rewriteAimArgs(oldNamecall, self, ...)
                    end))
                else
                    if type(getrawmetatable) ~= "function" or type(setreadonly) ~= "function" then
                        error("missing hookmetamethod/getrawmetatable")
                    end
                    local mt = getrawmetatable(game)
                    local oldNamecall = mt.__namecall
                    setreadonly(mt, false)
                    mt.__namecall = newcclosure(function(self, ...)
                        return rewriteAimArgs(oldNamecall, self, ...)
                    end)
                    setreadonly(mt, true)
                end
            end)

            if not ok then
                aimState.installFailed = true
                Logger.warn("Fish Trial aim hook fail: " .. tostring(err), "fish_aim_hook")
                return false
            end
            aimState.installed = true
            return true
        end

        function CombatActions.setSkillAimTarget(target)
            aimState.target = resolveAimPosition(target)
            if aimState.target then CombatActions.installSkillAim() end
            return aimState.target ~= nil
        end

        function CombatActions.clearSkillAimTarget()
            aimState.target = nil
        end
    end

    -- spam-skills loop: BẬT theo _G.SHOULDSPAMSKILLS, 1 instance, check Runtime.alive (File A 2071-2123)
    -- [FISH TRIAL ONLY] Chu kỳ cố định theo yêu cầu:
    --   Melee Z/X/C x2 trong ~3 giây -> Sword Z/X x2 trong ~1 giây -> quay lại Melee.
    -- Dành nhiều thời gian hơn cho Melee để skill kịp nhận phím/cast trước khi đổi sang Sword.
    -- Nhánh ngoài Fish Trial giữ nguyên cơ chế cooldown cũ.
    local FISH_MELEE_KEYS = { "Z", "X", "C" }
    local FISH_SWORD_KEYS = { "Z", "X" }
    local FISH_MELEE_KEY_INTERVAL = 3 / (#FISH_MELEE_KEYS * 2) -- 6 lần bấm / khoảng 3 giây
    local FISH_SWORD_KEY_INTERVAL = 1 / (#FISH_SWORD_KEYS * 2) -- 4 lần bấm / khoảng 1 giây
    local FISH_KEY_HOLD = 0.05

    local function fishSpamStillActive()
        return Runtime.alive
            and _G.SHOULDSPAMSKILLS == true
            and fishTrialSwordState.active == true
    end

    local function tapFishSkillKey(keyName, interval)
        if not fishSpamStillActive() then return false end
        VirtualInputManager:SendKeyEvent(true, keyName, false, game)
        task.wait(FISH_KEY_HOLD)
        VirtualInputManager:SendKeyEvent(false, keyName, false, game)

        local remain = math.max(0, interval - FISH_KEY_HOLD)
        if remain > 0 then task.wait(remain) end
        return fishSpamStillActive()
    end

    local function findFishMeleeTool(char)
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and tool.ToolTip == "Melee" then
                    return tool
                end
            end
        end
        local bp = LP:FindFirstChild("Backpack")
        if bp then
            for _, tool in ipairs(bp:GetChildren()) do
                if tool:IsA("Tool") and tool.ToolTip == "Melee" then
                    return tool
                end
            end
        end
        return nil
    end

    local function equipFishPhaseTool(char, tool)
        if not (char and tool and tool.Parent) then return false end
        if tool.Parent == char then return true end
        local hum = char:FindFirstChildOfClass("Humanoid")
        if not (hum and hum.Health > 0) then return false end
        pcall(function() hum:EquipTool(tool) end)
        task.wait(0.05)
        return tool.Parent == char
    end

    local function spamFishPhase(keys, interval)
        for _ = 1, 2 do
            for _, keyName in ipairs(keys) do
                if not tapFishSkillKey(keyName, interval) then
                    return false
                end
            end
        end
        return fishSpamStillActive()
    end

    local function runFishTrialSkillSequence()
        local char = LP.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and hum.Health > 0) then return end

        -- Pha 1: Melee Z/X/C hai lượt trong khoảng 3 giây.
        local melee = findFishMeleeTool(char)
        if melee and equipFishPhaseTool(char, melee) then
            if not spamFishPhase(FISH_MELEE_KEYS, FISH_MELEE_KEY_INTERVAL) then return end
        end

        if not fishSpamStillActive() then return end

        -- Pha 2: đúng Tushita/Yama đã chọn, Z/X hai lượt trong khoảng 1 giây.
        char = LP.Character
        local sword = char and getFishTrialSwordForSpam(char) or nil
        if sword and equipFishPhaseTool(char, sword) then
            spamFishPhase(FISH_SWORD_KEYS, FISH_SWORD_KEY_INTERVAL)
        end
    end

    function CombatActions.startSpamSkills()
        task.spawn(function()
            while Runtime.alive do
                task.wait()
                if _G.SHOULDSPAMSKILLS then
                    pcall(function()
                        -- Fish Trial dùng chu kỳ riêng, không đi qua vòng cooldown/vũ khí chung.
                        if fishTrialSwordState.active then
                            runFishTrialSkillSequence()
                            return
                        end

                        local char = LP.Character
                        local skillsUI = LP.PlayerGui:FindFirstChild("Main")
                        skillsUI = skillsUI and skillsUI:FindFirstChild("Skills")
                        if not (char and skillsUI) then return end

                        local weapon = getallweapon()
                        for _, v in pairs(weapon) do
                            if not skillsUI:FindFirstChild(v.Name) then EquipTool(v.Name) end
                        end

                        for _, v in pairs(weapon) do
                            if v.Parent ~= char then EquipTool(v.Name) end
                            local ui_ = skillsUI:FindFirstChild(v.Name)
                            if ui_ then
                                for _, vl in pairs(ui_:GetChildren()) do
                                    if isvalidnameui[vl.Name] then
                                        local cooldown_frame = vl:FindFirstChild("Cooldown")
                                        local title_frame = vl:FindFirstChild("Title")
                                        if cooldown_frame and title_frame
                                            and (title_frame.TextColor3 == Color3.new(1, 1, 1) or title_frame.TextColor3 == Color3.fromRGB(255, 255, 255)) then
                                            if cooldown_frame.Size == UDim2.new(0, 0, 1, -1) then
                                                if vl.Name == "V" then
                                                    if not fruits[ui_.Name] then
                                                        VirtualInputManager:SendKeyEvent(true, "V", false, game)
                                                        task.wait(0.1)
                                                        VirtualInputManager:SendKeyEvent(false, "V", false, game)
                                                        task.wait(1.5)
                                                    end
                                                else
                                                    VirtualInputManager:SendKeyEvent(true, vl.Name, false, game)
                                                    task.wait(0.1)
                                                    VirtualInputManager:SendKeyEvent(false, vl.Name, false, game)
                                                    task.wait(1.5)
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end)
    end

    -- ===== FastAttack (File A 2228-2323) + AttackNoCoolDown/haki loop (File A 2125-2395) =====
    function CombatActions.startFastAttack()
        local okShake = pcall(function()
            local CameraShakerR = require(ReplicatedStorage.Util.CameraShaker)
            CameraShakerR:Stop()
        end)
        if not okShake then Logger.warn("CameraShaker miss (bỏ qua)", "cam_shake") end

        local _ENV = (getgenv or getrenv or getfenv)()
        local function SafeWaitForChild(parent, childName)
            local ok, result = pcall(function() return parent:WaitForChild(childName, 10) end)
            if not ok then return nil end
            return result
        end
        local Player = LP
        local Remotes = SafeWaitForChild(ReplicatedStorage, "Remotes")
        if not Remotes then return end
        local Modules = SafeWaitForChild(ReplicatedStorage, "Modules")
        local NetMod  = Modules and SafeWaitForChild(Modules, "Net")
        if not NetMod then return end
        local Settings = { AutoClick = true, ClickDelay = 0 }

        if _ENV.rz_FastAttack then return end
        local FastAttack = { Distance = 100 }
        local RegisterAttack = SafeWaitForChild(NetMod, "RE/RegisterAttack")
        local RegisterHit    = SafeWaitForChild(NetMod, "RE/RegisterHit")
        if not (RegisterAttack and RegisterHit) then return end
        local function IsAlive(character)
            return character and character:FindFirstChild("Humanoid") and character.Humanoid.Health > 0
        end
        local function ProcessEnemies(OthersEnemies, Folder)
            local BasePart = nil
            if not Folder then return nil end
            for _, Enemy in pairs(Folder:GetChildren()) do
                local Head = Enemy:FindFirstChild("Head")
                if Head and IsAlive(Enemy) and Player:DistanceFromCharacter(Head.Position) < FastAttack.Distance then
                    if Enemy ~= Player.Character then
                        table.insert(OthersEnemies, { Enemy, Head })
                        BasePart = Head
                    end
                end
            end
            return BasePart
        end
        function FastAttack:Attack(BasePart, OthersEnemies)
            if not BasePart or #OthersEnemies == 0 then return end
            RegisterAttack:FireServer(Settings.ClickDelay or 0)
            RegisterHit:FireServer(BasePart, OthersEnemies)
        end
        function FastAttack:AttackNearest()
            local OthersEnemies = {}
            local Part1 = ProcessEnemies(OthersEnemies, workspace:FindFirstChild("Enemies"))
            local Part2 = ProcessEnemies(OthersEnemies, workspace:FindFirstChild("Characters"))
            local character = Player.Character
            if not character then return end
            local equippedWeapon = character:FindFirstChildOfClass("Tool")
            if equippedWeapon and equippedWeapon:FindFirstChild("LeftClickRemote") then
                for _, enemyData in ipairs(OthersEnemies) do
                    local enemy = enemyData[1]
                    local ehrp = enemy:FindFirstChild("HumanoidRootPart")
                    if ehrp then
                        local direction = (ehrp.Position - character:GetPivot().Position).Unit
                        pcall(function() equippedWeapon.LeftClickRemote:FireServer(direction, 1) end)
                    end
                end
            elseif #OthersEnemies > 0 then
                self:Attack(Part1 or Part2, OthersEnemies)
            else
                return false -- [§XXIII-14] không có enemy → idle (loop tự backoff, KHÔNG spin task.wait(0))
            end
            return true -- có enemy trong tầm → đã đánh
        end
        function FastAttack:BladeHits()
            local Equipped = IsAlive(Player.Character) and Player.Character:FindFirstChildOfClass("Tool")
            if Equipped and Equipped.ToolTip ~= "Gun" then return self:AttackNearest() end
            return false -- không có vũ khí phù hợp → idle
        end
        _ENV.rz_FastAttack = FastAttack
        task.spawn(function()
            -- [§XXIII-14] KHÔNG global task.wait(0) khi idle. Có đánh → nhịp ClickDelay (nhanh); idle → backoff 0.15s.
            while Runtime.alive do
                local attacked = false
                if Settings.AutoClick then pcall(function() attacked = FastAttack:BladeHits() end) end
                if attacked then task.wait(Settings.ClickDelay) else task.wait(0.15) end
            end
        end)
    end

    -- haki loop nền (File A 2390-2395)
    function CombatActions.startHakiLoop()
        task.spawn(function()
            -- [§XXIII-15] Haki KHÔNG chạy mỗi frame (task.wait() ~ mỗi frame → tốn CPU). Throttle 1s/lần.
            while Runtime.alive do
                task.wait(1)
                pcall(function() Movement.haki() end)
            end
        end)
    end

    -- [FINAL §J2-J6] attackBossAttempt — helper CHUNG cho MỌI boss (Human/Ghoul/Cake Prince/Dough King).
    --   Mỗi call chạy MỘT attempt hữu hạn (options.maxSeconds, mặc định 12s), KHÔNG retry vô hạn, KHÔNG block 60s.
    --   FastAttack là chính; HP watchdog: HP không giảm trong 2–3s → bật M1 fallback (§J3), tắt sau khi FastAttack
    --   gây damage ổn định >=3 lần. M1 chỉ khi <=M1_RANGE (doM1). Movement chỉ khi lệch >5 studs & qua 0.25s (§J5).
    --   Boss chết CHỈ khi HP replicate <= 0 (§J6). Model missing → target_missing (KHÔNG coi là chết).
    -- Return: ok(bool), reason(string):
    --   true,"boss_dead" | false,"boss_still_alive" | false,"target_missing"
    --   false,"local_player_dead" | false,"phase_changed" | false,"cancelled"
    function CombatActions.attackBossAttempt(target, options)
        options = options or {}
        local maxSeconds = options.maxSeconds or 12
        local phaseCheck = options.phaseCheck        -- fn() -> true nếu phase còn hợp lệ
        local M1_RANGE_LOCAL = 11
        if not target or not target.Parent then return false, "target_missing" end
        local bossHum = target:FindFirstChildOfClass("Humanoid") or target:FindFirstChild("Humanoid")
        local bhrp = target:FindFirstChild("HumanoidRootPart") or (target.PrimaryPart)
        if not (bossHum and bhrp) then return false, "target_missing" end

        CombatActions.initV3Combat()
        local t0 = tick()
        local lastHp = bossHum.Health
        local lastHpCheck = tick()
        local lastDamageT = tick()
        local m1FallbackActive = false
        local fastAttackDamageStreak = 0
        local lastMoveT, lastMovePos = 0, nil
        local lastEquip = 0

        while Runtime.alive do
            -- huỷ theo điều kiện ngoài
            if phaseCheck and not phaseCheck() then return false, "phase_changed" end
            -- local player chết?
            local myChar = LP.Character
            local myHum = myChar and myChar:FindFirstChildOfClass("Humanoid")
            local myHrp = myChar and myChar:FindFirstChild("HumanoidRootPart")
            if not (myChar and myHum and myHrp) or myHum.Health <= 0 then
                return false, "local_player_dead"
            end
            -- boss model biến mất / reparent → target_missing (KHÔNG phải chết) §J6
            if not target.Parent or not bossHum.Parent or not bhrp.Parent then
                return false, "target_missing"
            end
            -- §J6: boss chết CHỈ khi HP replicate <= 0
            if bossHum.Health <= 0 then return true, "boss_dead" end
            -- timeout attempt (hữu hạn) → boss_still_alive, tick sau tìm lại
            if (tick() - t0) > maxSeconds then return false, "boss_still_alive" end

            -- equip/haki throttle 1s
            if (tick() - lastEquip) >= 1 then
                lastEquip = tick()
                pcall(function() Movement.equip() end)
                pcall(function() Movement.haki() end)
            end

            -- §J3 HP watchdog: kiểm mỗi ~0.5s; HP không giảm trong 2–3s → bật M1 fallback
            if (tick() - lastHpCheck) > 0.5 then
                local cur = bossHum.Health
                if (lastHp - cur) > 1 then
                    -- FastAttack đang gây damage
                    lastDamageT = tick()
                    fastAttackDamageStreak = fastAttackDamageStreak + 1
                    -- §J3: chỉ tắt M1 sau khi FastAttack damage ổn định >= 3 lần
                    if m1FallbackActive and fastAttackDamageStreak >= 3 then
                        m1FallbackActive = false
                    end
                else
                    fastAttackDamageStreak = 0
                    if (tick() - lastDamageT) >= 2.5 then m1FallbackActive = true end
                end
                lastHp = cur
                lastHpCheck = tick()
            end

            -- §J5 MOVEMENT: chỉ di chuyển khi lệch > 5 studs & qua 0.25s
            local dist = (bhrp.Position - myHrp.Position).Magnitude
            if (tick() - lastMoveT) > 0.25 then
                local moved = (not lastMovePos) or (bhrp.Position - lastMovePos).Magnitude > 4
                if dist > 5 or moved then
                    lastMoveT = tick()
                    lastMovePos = bhrp.Position
                    -- Mặc định giữ nguyên vị trí Human/Cake/Dough cũ.
                    -- Ghoul Trial có thể truyền options.ghoulSafeHeight để đứng cao hơn một chút
                    -- trên đầu quái, giảm bị mob chạm/đánh nhưng vẫn giữ trong tầm M1 fallback.
                    local safeHeight = tonumber(options.ghoulSafeHeight)
                    local offset
                    if safeHeight and safeHeight > 0 then
                        if m1FallbackActive then
                            -- Khi watchdog cần M1 fallback, tạm hạ xuống trong tầm <=11 studs.
                            -- Không giữ +20 ở nhánh này vì như vậy M1 sẽ nằm ngoài range và làm gãy fallback.
                            offset = CFrame.new(0, math.min(9, math.max(2, safeHeight - 1)), 4)
                        else
                            -- Ghoul hover chính: offset cũ Y=4, tăng đúng +20 -> Y=24.
                            offset = CFrame.new(0, safeHeight, 5)
                        end
                    else
                        -- Hành vi cũ cho Human và các boss khác.
                        offset = m1FallbackActive and CFrame.new(0, 2, 4) or CFrame.new(0, 4, 5)
                    end
                    pcall(function() topos(bhrp.CFrame * offset) end)
                end
            end

            -- FastAttack (chính)
            pcall(function() CombatActions.v3BringMob(target.Name, 3) end)
            pcall(function() CombatActions.v3FastAttack(target.Name) end)

            -- §J3/J4 M1 fallback: chỉ khi active + trong tầm
            if m1FallbackActive and dist <= M1_RANGE_LOCAL then
                CombatActions.doM1(target)
            end

            task.wait(0.06)
        end
        return false, "cancelled"
    end
end
-- alias File A
local function getplayers(...) return CombatActions.getplayers(...) end
local function countplayers(...) return CombatActions.countplayers(...) end
local function attackTick(t, opts) return CombatActions.attackTick(t, opts) end
local function getmob1(pos) return CombatActions.getmob1(pos) end
local function checkmob_(v) return CombatActions.checkmob_(v) end
local function BringMob() return CombatActions.BringMob() end
-- V3 combat alias (chỉ dùng khi training)
local function v3FastAttack(n) return CombatActions.v3FastAttack(n) end
local function v3BringMob(n, c, cf) return CombatActions.v3BringMob(n, c, cf) end

--[[ ============================================================================
 [19] GEARMANAGER — checkGear qua SafeRemote (File A 1435-1455)
============================================================================ ]]
local GearManager = {}
do
    -- state cho việc tiêu điểm Gear5 (chống spam SpendPoint → tránh kick)
    local _g5Lock    = false
    local _g5LastTry = 0

    function GearManager.checkGear()
        -- Main dùng checkGear bình thường (không clearAllyUnspentPoint)
        if State.myRole == "ally" then
            -- Ally: dùng clearAllyUnspentPoint thay thế (AllyGearLoop gọi)
            return GearManager.clearAllyUnspentPoint()
        end
        local _okcg, dt = SafeRemote.invoke(3, "TempleClock", "Check")
        if not (dt and type(dt) == "table") then return end
        if not dt.HadPoint then return end
        local rd = dt.RaceDetails
        if not (rd and rd.Completed ~= nil) then return end

        local g1, g2, g3 = Config.gear:match("^(.-)%-(.-)%-(.-)$")
        local a23 = { [2] = g1, [3] = g2, [4] = g3 }
        local a24 = { ["A"] = "Alpha", ["B"] = "Omega" }
        local lvl = rd.Completed
        local choosegear = (lvl == 1 or lvl == 5) and "Blank" or a24[a23[lvl]]
        local a = rd.A or 0
        local b = rd.B or 0
        if a >= 2 then
            SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.Completed), "Omega")
        elseif b >= 2 then
            SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(dt.Completed), "Alpha")
        else
            SafeRemote.invoke(3, "TempleClock", "SpendPoint", "Gear" .. tostring(rd.Completed), choosegear)
        end
    end

    -- ===== ALLY ONLY: clear unspent point thông minh — tính đúng slot theo installedCount =====
    -- Tách hoàn toàn khỏi checkGear của Main. Main KHÔNG bao giờ gọi function này.
    -- Lý do: khi Ally i=8 (Completed==5) vẫn còn HadPoint, cần swap Gear2/3/4 Alpha/Omega
    -- thay vì cố định Gear2. Dùng bestGearForRace để chọn đúng theo race.
    GearManager._allyUnspentLock   = false
    GearManager._lastAllyUnspentAt = 0
    GearManager._allyClearCursor   = 1
    GearManager._allyDtLogAt       = 0

    local _bestGearForRace = {
        Ghoul = "B-B-A", Cyborg = "A-B-B", Mink = "B-B-A",
        Skypiea = "B-B-A", Human = "B-A-A", Fishman = "B-A-A"
    }

    local function _countInstalledAB(gears)
        local a, b = 0, 0
        for _, slot in ipairs({ "Gear2", "Gear3", "Gear4" }) do
            local g = gears and gears[slot]
            if type(g) == "table" then
                if g.A == true or g.Alpha == true then a = a + 1 end
                if g.B == true or g.Omega == true then b = b + 1 end
            end
        end
        return a, b
    end

    function GearManager.clearAllyUnspentPoint()
        if State.myRole ~= "ally" then
            DBG("[ALLY-GEAR] skip because not ally", "info", "ally_gear_skip")
            return
        end
        if GearManager._allyUnspentLock then return end
        if (tick() - GearManager._lastAllyUnspentAt) < 5 then return end

        GearManager._allyUnspentLock   = true
        GearManager._lastAllyUnspentAt = tick()

        task.spawn(function()
            local function finish() GearManager._allyUnspentLock = false end

            local _ok, dt = SafeRemote.invoke(3, "TempleClock", "Check")
            if not (dt and type(dt) == "table") then return finish() end

            local hadPoint  = dt.HadPoint == true
            local completed = dt.Completed or 0
            local race      = ""
            pcall(function() race = tostring(LocalPlayer.Data.Race.Value) end)

            -- RaceDetails bên trong dt (key tên race)
            local rd = nil
            if dt.RaceDetails then
                rd = dt.RaceDetails[race]
            end

            DBG(("[ALLY-GEAR] Check HadPoint=%s Completed=%s Race=%s"):format(
                tostring(hadPoint), tostring(completed), tostring(race)), "info", "ally_gear_check")

            if not hadPoint then return finish() end

            -- Log dt đầy đủ 1 lần / 30s để debug cấu trúc lạ
            if (tick() - GearManager._allyDtLogAt) >= 30 then
                GearManager._allyDtLogAt = tick()
                local ok2, js = pcall(function() return game:GetService("HttpService"):JSONEncode(dt) end)
                if ok2 then DBG("[ALLY-GEAR] dt=" .. tostring(js):sub(1, 300), "info", "ally_gear_dt") end
            end

            if not rd then
                DBG("[ALLY-GEAR] RaceDetails[" .. race .. "] not found → fallback", "warn", "ally_gear_no_rd")
                rd = {}
            end

            -- Tính slot theo số gear đã cài
            local rdA, rdB = _countInstalledAB(rd.Gears)
            local installedCount = rdA + rdB
            local slotIndex = installedCount + 2
            if slotIndex < 2 then slotIndex = 2 end

            -- Chọn pattern gear
            local pattern = nil
            local cfgGear = tostring(Config.gear or "")
            if cfgGear and #cfgGear == 5 and cfgGear:match("^[AB]%-[AB]%-[AB]$") then
                pattern = cfgGear
            end
            if not pattern then pattern = _bestGearForRace[race] end
            if not pattern then pattern = "A-B-B" end

            local parts = {}
            for p in pattern:gmatch("[AB]") do table.insert(parts, p) end
            if #parts ~= 3 then parts = { "A", "B", "B" } end
            local convert = { A = "Alpha", B = "Omega" }

            local letter = parts[installedCount + 1] or parts[#parts] or "A"
            local choose = convert[letter] or "Alpha"

            DBG(("[ALLY-GEAR] calculated slot=Gear%d choose=%s installedCount=%d"):format(
                slotIndex, choose, installedCount), "info", "ally_gear_calc")

            local cleared = false

            -- ===== Bước 1: thử slot tính được =====
            if slotIndex <= 4 then
                local slotName = "Gear" .. tostring(slotIndex)
                DBG("[ALLY-GEAR] try SpendPoint " .. slotName .. " " .. choose, "ok", "ally_gear_try")
                SafeRemote.invoke(3, "TempleClock", "SpendPoint", slotName, choose)
                task.wait(1)
                local _ok2, dt2 = SafeRemote.invoke(3, "TempleClock", "Check")
                if dt2 and dt2.HadPoint ~= true then
                    DBG("[ALLY-GEAR] cleared unspent point via " .. slotName .. " " .. choose, "ok", "ally_gear_ok")
                    cleared = true
                end
            end

            -- ===== Bước 2: fallback quét Gear2/3/4 cả Alpha/Omega =====
            if not cleared then
                local slots = { "Gear2", "Gear3", "Gear4" }
                local picks = { choose, choose == "Alpha" and "Omega" or "Alpha" }
                for _, sl in ipairs(slots) do
                    if cleared then break end
                    for _, pk in ipairs(picks) do
                        DBG("[ALLY-GEAR] fallback try slot=" .. sl .. " pick=" .. pk, "info", "ally_gear_fb")
                        SafeRemote.invoke(3, "TempleClock", "SpendPoint", sl, pk)
                        task.wait(1)
                        local _ok3, dt3 = SafeRemote.invoke(3, "TempleClock", "Check")
                        if dt3 and dt3.HadPoint ~= true then
                            DBG("[ALLY-GEAR] cleared unspent point via fallback " .. sl .. " " .. pk, "ok", "ally_gear_fb_ok")
                            cleared = true
                            break
                        end
                    end
                end
            end

            -- ===== Bước 3: thử các action thay thế (cursor, không spam toàn bộ mỗi vòng) =====
            if not cleared then
                local actions = { "ReplacePoint", "Replace", "SwapPoint", "SwitchPoint" }
                local slots   = { "Gear2", "Gear3", "Gear4" }
                local picks   = { choose, choose == "Alpha" and "Omega" or "Alpha" }
                -- chỉ thử 4 attempt mỗi vòng, dùng cursor tiếp tục vòng sau
                local attempts = 0
                local totalActions = #actions * #slots * #picks
                for i = 1, 4 do
                    local cursor = ((GearManager._allyClearCursor - 1 + i - 1) % totalActions) + 1
                    local ai = math.ceil(cursor / (#slots * #picks))
                    local rest = cursor - (ai - 1) * #slots * #picks
                    local si = math.ceil(rest / #picks)
                    local pi = rest - (si - 1) * #picks
                    ai = math.clamp(ai, 1, #actions)
                    si = math.clamp(si, 1, #slots)
                    pi = math.clamp(pi, 1, #picks)
                    local action = actions[ai]
                    local sl = slots[si]
                    local pk = picks[pi]
                    DBG("[ALLY-GEAR] fallback try action=" .. action .. " slot=" .. sl .. " pick=" .. pk, "info", "ally_gear_act")
                    SafeRemote.invoke(3, "TempleClock", action, sl, pk)
                    task.wait(1)
                    local _ok4, dt4 = SafeRemote.invoke(3, "TempleClock", "Check")
                    if dt4 and dt4.HadPoint ~= true then
                        DBG("[ALLY-GEAR] cleared via action=" .. action, "ok", "ally_gear_act_ok")
                        cleared = true
                        GearManager._allyClearCursor = cursor + 1
                        break
                    end
                    attempts = attempts + 1
                end
                GearManager._allyClearCursor = ((GearManager._allyClearCursor - 1 + attempts) % totalActions) + 1
            end

            if not cleared then
                DBG("[ALLY-GEAR] still HadPoint=true after attempts", "warn", "ally_gear_stuck")
            end

            finish()
        end)
    end
end
local function checkgear() return GearManager.checkGear() end

--[[ ============================================================================
 [19b] ALLYGEARLOOP — loop nền riêng cho Ally: clear unspent point mỗi 5s.
   Chạy xuyên suốt (kể cả khi đang trial). Main KHÔNG được gọi loop này.
   Đổi từ checkGear/8s → clearAllyUnspentPoint/5s theo yêu cầu.
============================================================================ ]]
local AllyGearLoop = {}
do
    AllyGearLoop.started = false
    function AllyGearLoop.start()
        if AllyGearLoop.started then return end
        if State.myRole ~= "ally" then return end
        AllyGearLoop.started = true
        task.spawn(function()
            while Runtime.alive and State.myRole == "ally" do
                GearManager.clearAllyUnspentPoint()
                task.wait(5)
            end
        end)
    end
end

--[[ ============================================================================
 [20] TRIALACTIONS — doTrialForMyRace + runTrialPhase. (File A 982-1128)
============================================================================ ]]
local TrialTimeoutWatch -- forward declaration; khởi tạo ở [27.5]
local TrialActions = {}
do
    local LP = LocalPlayer

    -- bay từ từ (tween) tới cf, destroy chống leak (File A 996-1006)
    local function flyTo(cf)
        pcall(function()
            local hrp =
                LP.Character
                and LP.Character:FindFirstChild("HumanoidRootPart")

            if not hrp
                or typeof(cf) ~= "CFrame"
            then
                return
            end

            local dist =
                (cf.Position - hrp.Position).Magnitude

            Movement.topos(cf)

            -- Giữ behavior cũ: flyTo là blocking helper,
            -- chỉ thay cách tween và đổi tốc độ về 150.
            Movement.waitFor(
                cf,
                math.max(
                    5,
                    dist / Movement.TWEEN_SPEED + 8
                ),
                5
            )
        end)
    end

    -- cầm Melee (fallback Sword/Blox Fruit/Gun) (File A 1007-1022)
    local function equipMelee()
        pcall(function()
            local char = LP.Character
            if not (char and char:FindFirstChild("Humanoid")) then return end
            local melee, anyw
            local bp = LP:FindFirstChild("Backpack")
            if not bp then return end
            for _, t in pairs(bp:GetChildren()) do
                if t:IsA("Tool") then
                    local tip = t.ToolTip
                    if tip == "Melee" then melee = t break
                    elseif tip == "Sword" or tip == "Blox Fruit" or tip == "Gun" then anyw = anyw or t end
                end
            end
            local pick = melee or anyw
            if pick then char.Humanoid:EquipTool(pick) end
        end)
    end

    -- teleport thô (không tự kill như wrapper topos) (File A 993)
    local function tp(cf) pcall(function() Movement.topos(cf) end) end

    -- doTrialForMyRace (File A 989-1111) — y chang per-race
    function TrialActions.doTrialForMyRace()
        local myrace = LP.Data.Race.Value
        local race_trial_place = getRaceTrialPlace(myrace)

        if myrace == "Mink" then
            if tick() - (RuntimeState.minkLastTrial or 0) > 3 then task.wait(2) end
            RuntimeState.minkLastTrial = tick()
            local sp = RuntimeState.minkStartPoint
            if not (sp and sp.Parent) then
                sp = nil
                pcall(function()
                    for _, obj in pairs(workspace:GetDescendants()) do
                        if obj.Name == "StartPoint" then sp = obj break end
                    end
                end)
                RuntimeState.minkStartPoint = sp
            end
            if sp then
                local t0 = tick()
                repeat task.wait(); pcall(function() Movement.topos(sp.CFrame * CFrame.new(0, 2, 0)) end)
                until (tick() - t0) > 4
            end

        elseif myrace == "Skypiea" then
            local finish, model
            pcall(function()
                model = workspace.Map:FindFirstChild("SkyTrial")
                model = model and model:FindFirstChild("Model")
                if model then
                    for _, obj in pairs(model:GetDescendants()) do
                        if obj.Name == "snowisland_Cylinder.081" then finish = obj break end
                    end
                    finish = finish or model:FindFirstChild("FinishPart")
                end
            end)
            if not finish then
                local c = RuntimeState.skyFinish
                if c and c.Parent then finish = c
                else
                    pcall(function()
                        for _, obj in pairs(workspace:GetDescendants()) do
                            if obj.Name == "snowisland_Cylinder.081" then finish = obj break end
                        end
                    end)
                    RuntimeState.skyFinish = finish
                end
            end
            if finish then flyTo(finish.CFrame)
            elseif model then pcall(function() flyTo(model:GetPivot()) end)
            elseif race_trial_place then flyTo(race_trial_place.CFrame) end

        elseif myrace == "Cyborg" then
            pcall(function() tp(workspace.Map.CyborgTrial.Floor.CFrame * CFrame.new(0, 500, 0)) end)

        elseif myrace == "Human" or myrace == "Ghoul" then
            -- [FINAL §J2/J3] trial Human/Ghoul dùng CHUNG helper attackBossAttempt (FastAttack chính,
            --   HP watchdog 2–3s → M1 fallback <=12 studs, đứng ngang boss, KHÔNG set Health=0 client, mỗi
            --   attempt hữu hạn ~14s). Tick sau tự tìm target lại nếu chưa chết.
            pcall(function() CombatActions.initV3Combat() end)
            pcall(function() setscriptable(LP, "SimulationRadius", true) end)
            for _, v in pairs(workspace.Enemies:GetChildren()) do
                local hum = v:FindFirstChild("Humanoid")
                local hrp = v:FindFirstChild("HumanoidRootPart")
                if hum and hrp and hum.Health > 0
                    and (not race_trial_place or getdis(hrp.CFrame, race_trial_place.CFrame) < 1500) then
                    local ok, reason = CombatActions.attackBossAttempt(v, {
                        maxSeconds = 14,
                        -- Chỉ Ghoul đứng cao hơn quái đúng +20 studs so với offset cũ.
                        -- Hover chính cũ Y=4 -> mới Y=24. Khi M1 fallback kích hoạt sẽ hạ tạm về Y<=9 để M1 vẫn chạm.
                        -- Human và các race/boss khác giữ nguyên hoàn toàn.
                        ghoulSafeHeight = (myrace == "Ghoul") and 24 or nil,
                        phaseCheck = function() return templeState() ~= "ffup" end, -- vào FFA = phase đổi → dừng
                    })
                    DBG("[TRIAL-BOSS] " .. tostring(v.Name) .. " → " .. tostring(reason), ok and "ok" or "warn", "trial_boss")
                    if reason == "local_player_dead" or reason == "phase_changed" then break end
                end
            end

        elseif myrace == "Fishman" then
            -- [FISH TRIAL AIM] Logic target/timeout giữ nguyên; chỉ sửa cách đứng + khóa aim vào Sea Beast.
            -- Cũ: đứng thẳng trên HRP +500 studs → nhiều skill rơi ngoài tầm/góc bắn.
            -- Mới: đứng thấp, lùi ngang, CFrame.lookAt vào Sea Beast và cập nhật aim theo HRP đang di chuyển.
            -- CẤU HÌNH CỨNG: không đọc getgenv()/loader.
            -- 55 studs cao + lùi 20 studs: tránh Character/Sea Beast bị chìm hoặc nằm dưới nền Trial.
            local FISH_HEIGHT = 55
            local FISH_DISTANCE = 20
            local FISH_AIM_Y_OFFSET = 5
            local FISH_MOVE_INTERVAL = 0.25

            -- CHỈ Fish Trial mới tự lấy kiếm. Ưu tiên Tushita, không có mới thử Yama.
            -- Không tìm thấy kiếm vẫn tiếp tục Trial, không block/return.
            local fishSwordName
            pcall(function() fishSwordName = CombatActions.equipFishTrialSword() end)
            if fishSwordName then
                status("[FISH TRIAL] Đã cầm " .. tostring(fishSwordName) .. " → bay tới Sea Beast + spam Melee/Sword")
            else
                status("[FISH TRIAL] Không có Tushita/Yama → dùng vũ khí hiện có")
            end

            local seaBeastsFolder = workspace:FindFirstChild("SeaBeasts")
            if not seaBeastsFolder then
                CombatActions.endFishTrialSwordMode()
                return
            end

            for _, v in pairs(seaBeastsFolder:GetChildren()) do
                local ok, err = pcall(function()
                    local health = v:FindFirstChild("Health")
                    local targetRoot = v:FindFirstChild("HumanoidRootPart")
                    if health and health.Value > 0 and targetRoot
                        and (not race_trial_place or getdis(targetRoot.CFrame, race_trial_place.CFrame) < 1500) then
                        local t0 = tick()
                        local lastMoveAt = 0
                        _G.SHOULDSPAMSKILLS = true
                        CombatActions.installSkillAim()
                        status("[FISH TRIAL] Đang bay tới + spam Melee/Sword Sea Beast")

                        repeat
                            task.wait()
                            -- Không ép equip Sword mỗi 0.5s: việc đó cướp tay khỏi Melee giữa pha Z/X/C.
                            -- Sword đã được kiểm/load một lần trước target; spam sequence tự equip đúng vũ khí
                            -- ở đầu từng pha (Melee rồi Sword), nên không spam LoadItem/equip tại đây.
                            -- Không tự mua Sharkman Karate/Fishman Karate trong Fish Trial.

                            targetRoot = v:FindFirstChild("HumanoidRootPart")
                            if targetRoot then
                                local aimPosition = targetRoot.Position + Vector3.new(0, FISH_AIM_Y_OFFSET, 0)
                                CombatActions.setSkillAimTarget(aimPosition)

                                local myChar = LP.Character
                                local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
                                if myRoot and (tick() - lastMoveAt) >= FISH_MOVE_INTERVAL then
                                    lastMoveAt = tick()
                                    -- Giữ phía đang đứng để tránh nhảy xuyên qua Sea Beast khi target quay.
                                    local away = Vector3.new(
                                        myRoot.Position.X - aimPosition.X,
                                        0,
                                        myRoot.Position.Z - aimPosition.Z
                                    )
                                    if away.Magnitude < 1 then
                                        local look = targetRoot.CFrame.LookVector
                                        away = Vector3.new(-look.X, 0, -look.Z)
                                    end
                                    if away.Magnitude < 0.1 then away = Vector3.new(0, 0, -1) end

                                    local standPosition = aimPosition
                                        + away.Unit * FISH_DISTANCE
                                        + Vector3.new(0, FISH_HEIGHT, 0)
                                    local standCFrame = CFrame.lookAt(standPosition, aimPosition)
                                    local distanceToStand = (myRoot.Position - standPosition).Magnitude
                                    if distanceToStand <= 6 then
                                        -- Ở gần: đặt đúng vị trí ngay để không bị tween cũ/địa hình kéo xuống đất.
                                        Movement.cancel()
                                        myRoot.CFrame = standCFrame
                                        myRoot.AssemblyLinearVelocity = Vector3.zero
                                        myRoot.AssemblyAngularVelocity = Vector3.zero
                                    else
                                        -- Ở xa: tween thật sự tới Sea Beast; interval 0.25s tránh cancel tween quá dày.
                                        Movement.topos(standCFrame)
                                    end
                                end
                            end
                        until (not v.Parent) or (not v:FindFirstChild("Health")) or v.Health.Value <= 0
                            or (not v:FindFirstChild("HumanoidRootPart")) or (tick() - t0) > 25
                    end
                end)

                -- Cleanup bắt buộc kể cả khi target biến mất/error để không aim nhầm ngoài Fish Trial.
                _G.SHOULDSPAMSKILLS = false
                CombatActions.clearSkillAimTarget()
                if not ok then
                    Logger.warn("Fish Trial target error: " .. tostring(err), "fish_trial_target")
                end
            end
            _G.SHOULDSPAMSKILLS = false
            CombatActions.clearSkillAimTarget()
            CombatActions.endFishTrialSwordMode()
            -- Draco / khác: File A không có handler riêng → fallback bay vào trial place (status rõ)
        elseif race_trial_place then
            flyTo(race_trial_place.CFrame)
        end
    end

    -- handleRaceTrial(ctx) → trả phase rõ (StateMachine dùng) (File A doTrialForMyRace)
    function TrialActions.handleRaceTrial()
        local race = WorldProbe.getRace()
        if not race then return { ok = false, phase = "missing_object", detail = "no race" } end
        TrialActions.doTrialForMyRace()
        return { ok = true, phase = "running_trial", detail = race }
    end

    -- runTrialPhase: ở khu trial → làm trial (set in_trail nếu main); chưa → ra cửa (File A 1115-1128)
    function TrialActions.runTrialPhase(roleName, isMain)
        local race_trial_place = getRaceTrialPlace(WorldProbe.getRace())
        if race_trial_place and getdis(race_trial_place.CFrame) < 1500 then
            -- Đây là điểm xác nhận Character đã thật sự vào khu Trial.
            -- Ghi in_trail trước, rồi mới start timer 60s để cả lần gọi Trial đầu tiên cũng được canh timeout.
            if isMain then
                local st = State.getMainStatus(State.myName)
                if st ~= "in_trail" and st ~= "training" then State.setMyMainStatus("in_trail") end
            elseif RuntimeState.inTrial ~= true then
                State.reportStatus("in_trail")
            end
            RuntimeState.inTrial = true
            State.didEnterTrialThisTurn = true

            if TrialTimeoutWatch and not TrialTimeoutWatch.start(isMain, State.myMainIndex) then
                return "trial_timeout_reset"
            end

            status(roleName .. " Doing trial")
            TrialActions.doTrialForMyRace()
            return "running_trial"
        else
            status(roleName .. " Ready for trialing (đợi đồng bộ ability)")
            goToMyDoor()
            return "moving_to_trial"
        end
    end
end
local function doTrialForMyRace() return TrialActions.doTrialForMyRace() end
local function runTrialPhase(roleName, isMain) return TrialActions.runTrialPhase(roleName, isMain) end

--[[ ============================================================================
 [21] TRAINING — trialable/cachedTrialable + doTrainGrind + pressV4 + trainTimeoutHop.
      (File A 953-961, 1283-1329, 1583-1672)
============================================================================ ]]
local Training = {}
do
    local LP = LocalPlayer

    local race_abilities = {
        ["Human"] = "Last Resort", ["Mink"] = "Agility", ["Fishman"] = "Water Body",
        ["Skypiea"] = "Heavenly Blood", ["Ghoul"] = "Heightened Senses",
        ["Cyborg"] = "Energy Core", ["Draco"] = "Primordial Reign",
    }
    Training.race_abilities = race_abilities

    local function checkbackpack(v)
        return (LP.Backpack and LP.Backpack:FindFirstChild(v)) or (LP.Character and LP.Character:FindFirstChild(v))
    end
    Training.checkbackpack = checkbackpack

    -- ===== CACHE LÕI CHO UpgradeRace("Check") =====
    -- FIX MAINRACE DONE-RACE (2026-08-11): cache PHẢI thuộc về đúng race hiện tại.
    -- Khi reroll Angel -> Mink, kết quả i=5/8 của Angel tuyệt đối không được tái dùng cho Mink.
    -- TTL vẫn giữ 1.5s như cũ, chỉ thêm race-key + huỷ response nếu race đổi ngay trong lúc InvokeServer.
    local function _upgradeRaceKey()
        local rawRace = WorldProbe.getRace()
        return WorldProbe.normalizeRace(rawRace) or tostring(rawRace or "")
    end

    local _upgradeRaw = { t = -1e9, ok = false, i = nil, d = nil, f = nil, race = nil }

    local function _invalidateUpgradeRaw(reason)
        _upgradeRaw = { t = -1e9, ok = false, i = nil, d = nil, f = nil, race = _upgradeRaceKey(), invalidated = reason }
    end
    Training.invalidateUpgradeRaw = _invalidateUpgradeRaw

    local function _getUpgradeRaw()
        local now = tick()
        local raceBefore = _upgradeRaceKey()

        -- Chỉ reuse cache nếu VẪN cùng race.
        if (now - _upgradeRaw.t) < 1.5 and _upgradeRaw.race == raceBefore then
            return _upgradeRaw
        end

        local ok, i, d, f = SafeRemote.invoke(3, "UpgradeRace", "Check")
        local raceAfter = _upgradeRaceKey()

        -- Race đổi trong lúc remote đang chạy => response có thể thuộc race cũ. VỨT BỎ hoàn toàn.
        if raceAfter ~= raceBefore then
            _upgradeRaw = {
                t = -1e9, ok = false, i = nil, d = nil, f = nil,
                race = raceAfter, raceChanged = true,
            }
            Diagnostics.lastRaceI = "race_changed"
            RuntimeState.mainDoneValidatedRace = nil
            return _upgradeRaw
        end

        _upgradeRaw = {
            t = now, ok = ok,
            i = ok and i or nil, d = ok and d or nil, f = ok and f or nil,
            race = raceAfter,
        }
        Diagnostics.lastRaceI = _upgradeRaw.i
        return _upgradeRaw
    end

    -- DONE là marker nguy hiểm vì nó sẽ ghi <PlayerName>.txt.
    -- Với MainRace active, chỉ cho commit DONE sau N lần đọc FRESH liên tiếp
    -- trong khi race vẫn giữ nguyên đúng expectedRace. Không dùng cache cũ giữa các lần.
    function Training.confirmDoneForRace(expectedRace, requiredCount, interval)
        local expected = WorldProbe.normalizeRace(expectedRace) or tostring(expectedRace or "")
        requiredCount = tonumber(requiredCount) or 3
        interval = tonumber(interval) or 0.35
        if expected == "" then return false, "invalid_expected_race" end

        for n = 1, requiredCount do
            local before = _upgradeRaceKey()
            if before ~= expected then
                return false, "race_mismatch_before:" .. tostring(before)
            end

            _invalidateUpgradeRaw("confirm_done_" .. tostring(n))
            local raw = _getUpgradeRaw()
            local after = _upgradeRaceKey()

            if after ~= expected then
                return false, "race_changed_during_confirm:" .. tostring(after)
            end
            if not raw.ok then
                return false, raw.raceChanged and "race_changed_response" or "check_failed"
            end
            if raw.i ~= 5 and raw.i ~= 8 then
                return false, "not_done_i_" .. tostring(raw.i)
            end

            if n < requiredCount then task.wait(interval) end
        end

        return true, "done_confirmed"
    end

    -- ===== V4 PURCHASE HELPER — 1 authority cho Buy, có cooldown + invalidate cache =====
    -- FragmentTyrant chỉ kiếm đủ Fragment; quyền BUY vẫn thuộc Training/Kaitun.
    local function _attemptUpgradeBuy(source)
        local now = tick()
        if RuntimeState.fragmentPurchaseLastAt
            and (now - RuntimeState.fragmentPurchaseLastAt) < 0.8
        then
            return false, "buy_cooldown"
        end

        RuntimeState.fragmentPurchaseLastAt = now
        local ok, ret = SafeRemote.invoke(3, "UpgradeRace", "Buy")
        RuntimeState.fragmentPurchaseJustAttempted = tick()
        RuntimeState.fragmentPurchaseSource = tostring(source or "unknown")
        _invalidateUpgradeRaw("upgrade_buy_" .. tostring(source or "unknown"))
        return ok, ret
    end
    Training.attemptUpgradeBuy = _attemptUpgradeBuy

    function Training.getCurrentFragments()
        local frags = 0
        pcall(function() frags = tonumber(LP.Data.Fragments.Value) or 0 end)
        return frags
    end

    -- trialable (File A 1283-1319) — dùng cache lõi, classify riêng
    function Training.checkTrialable()
        local char = LP.Character
        local raw = _getUpgradeRaw()
        if not (char and char:FindFirstChild("RaceTransformed")) then
            Diagnostics.lastRaceI = raw.ok and raw.i or "?"
            if raw.ok and (raw.i == 5 or raw.i == 8) then return false, "done" end
            local race = WorldProbe.getRace()
            local abcxyz = race and checkbackpack(race_abilities[race])
            if abcxyz then return true end
            return false
        end
        if not raw.ok then Diagnostics.lastRaceI = "?"; return false end
        Diagnostics.lastRaceI = raw.i
        local i, d, f = raw.i, raw.d, raw.f
        if i == 5 or i == 8 then
            return false, "done"
        elseif i == 6 then
            return false, (d or 0) - 2
        elseif i == 1 or i == 3 then
            return false
        elseif i == 2 or i == 4 or i == 7 then
            if f then
                local totalfragments = tonumber(f)
                local frags = 0
                pcall(function() frags = LP.Data.Fragments.Value end)
                if totalfragments and frags >= totalfragments then
                    _attemptUpgradeBuy("trialable")
                else
                    return false, "raiding"
                end
            end
            return false, f
        elseif i == 0 then
            return true, d
        else
            return false
        end
    end

    -- classifyUpgradeForRole: classifier UpgradeRace("Check") theo role.
    -- MAIN: i==8/5 → main_done (done, không train)
    -- ALLY: i==8/0 → ready_trial; i==5 → done
    -- Trả table { trialable, done, needTrain, canBuyGear, needFragments, fragmentCost, fragments, uncertain, i, d, f, reason }
    function Training.checkUpgradeForRole(role)
        local raw = _getUpgradeRaw()
        local i, d, f = raw.i, raw.d, raw.f
        local result = {
            i = i, d = d, f = f,
            trialable = false, done = false,
            needTrain = false, canBuyGear = false,
            needFragments = false, fragmentCost = 0, fragments = 0,
            purchaseReady = false, purchaseAttempted = false,
            uncertain = true, reason = "unknown",
        }
        if not raw.ok then
            -- CHỈ remote thật sự fail/timeout (SafeRemote trả false) mới là uncertain.
            result.uncertain = true
            result.reason = "check_failed"
        elseif i == nil then
            -- FIX (user 2026-07-02): remote SUCCEEDED nhưng server trả nil = acc CHƯA trial lần nào (fresh,
            -- hiện [i=?]). ĐÂY KHÔNG PHẢI uncertain/train — theo user i=? = CÓ THỂ TRIAL. Trước đây gộp
            -- `not raw.ok or i == nil` thành uncertain → main fresh kẹt limbo, không bao giờ join full moon.
            result.uncertain = false
            result.trialable = true
            result.reason = "fresh_never_trialed"
        elseif i == 0 then
            result.uncertain = false
            result.trialable = true
            result.reason = "ready_trial"
        elseif i == 8 then
            result.uncertain = false
            if role == "main" then
                result.done = true
                result.reason = "main_done"
            else
                result.trialable = true
                result.reason = "ready_trial"
            end
        elseif i == 5 then
            result.uncertain = false
            result.done = true
            result.reason = role == "main" and "main_done" or "ally_done"
        elseif i == 1 or i == 3 then
            result.uncertain = false
            result.needTrain = true
            result.reason = "need_train"
        elseif i == 6 then
            result.uncertain = false
            result.needTrain = true
            result.reason = "need_train"
        elseif i == 2 or i == 4 or i == 7 then
            result.uncertain = false
            result.canBuyGear = true
            result.reason = "can_buy_gear"

            local totalfrags = tonumber(f) or 0
            local frags = Training.getCurrentFragments()
            result.fragmentCost = totalfrags
            result.fragments = frags

            if totalfrags > 0 and frags < totalfrags then
                -- ĐÃ qua training của stage này nhưng CHƯA đủ tiền mua gear.
                -- Giữ canBuyGear=true để không phá consumer cũ, đồng thời thêm gate rõ ràng.
                result.needFragments = true
                result.reason = "need_fragments"
            elseif totalfrags > 0 then
                result.purchaseReady = true
                local attempted = _attemptUpgradeBuy("role_" .. tostring(role or "unknown"))
                result.purchaseAttempted = attempted and true or false
            end
        else
            result.uncertain = true
            result.reason = "unknown_i_" .. tostring(i)
        end
        return result
    end

    -- cachedTrialable — đọc từ cache lõi qua checkTrialable (đã dùng _getUpgradeRaw)
    function Training.cachedTrialable()
        return Training.checkTrialable()
    end

    -- [FINAL §B7/§21] confirmClassify — check V4 progress N lần LIÊN TIẾP cùng CLASSIFICATION (mặc định 3 lần,
    --   cách 0.5s). Dùng SAU respawn (intentional reset / death / cycle cancel) để KHÔNG set thẳng training
    --   ngay sau reset khi giá trị còn dao động. So theo CLASSIFICATION (trialable/needTrain/done/canBuyGear/
    --   uncertain) chứ không so raw i (nhiều raw i cùng 1 classification). Trả result cuối + confirmed(bool).
    function Training.confirmClassify(role, requiredCount, interval)
        requiredCount = requiredCount or 3
        interval = interval or 0.5
        local function classOf(r)
            if r.trialable then return "trialable"
            elseif r.needTrain then return "training"
            elseif r.done then return "done"
            elseif r.canBuyGear then return "can_buy_gear"
            else return "uncertain" end
        end
        local firstClass, streak, last = nil, 0, nil
        for _ = 1, requiredCount * 3 do -- tối đa 3x số lần cần (chống kẹt vô hạn nếu cứ dao động)
            _upgradeRaw.t = -1e9 -- ép refresh (bỏ cache TTL) để đọc mới thật
            local r = Training.checkUpgradeForRole(role)
            last = r
            local c = classOf(r)
            if c == firstClass then
                streak = streak + 1
            else
                firstClass = c
                streak = 1
            end
            if streak >= requiredCount and firstClass ~= "uncertain" then
                r.confirmed = true
                r.confirmedClass = firstClass
                return r
            end
            task.wait(interval)
        end
        if last then last.confirmed = false; last.confirmedClass = firstClass end
        return last or { uncertain = true, confirmed = false, reason = "confirm_failed" }
    end

    -- pressV4 (File A 1598-1606)
    function Training.pressV4()
        pcall(function()
            local c = LP.Character
            if c and c:FindFirstChild("RaceEnergy") and c.RaceEnergy.Value == 1 then
                VirtualInputManager:SendKeyEvent(true, "Y", false, game)
                VirtualInputManager:SendKeyEvent(false, "Y", false, game)
            end
        end)
    end

    -- trainTimeoutHop (File A 1612-1625) — CHỈ main, dùng hop ít người
    local function trainTimeoutHop(tag)
        if not State.isMain[State.myName] then return false end
        if not RuntimeState.trainWinStart then return false end
        if (tick() - RuntimeState.trainWinStart) < Config.TRAIN_WINDOW then return false end
        if (RuntimeState.trainKills or 0) > 10 then
            RuntimeState.trainWinStart = tick(); RuntimeState.trainKills = 0
            return false
        end
        status(tag .. " ⏱ Timeout train (kill " .. tostring(RuntimeState.trainKills or 0) .. "/5' <=10) → hop server")
        HopServer(("Timeout train kill %d/5phut <=10"):format(RuntimeState.trainKills or 0))
        RuntimeState.trainWinStart = tick(); RuntimeState.trainKills = 0
        return true
    end
    Training.trainTimeoutHop = trainTimeoutHop

    local pos__ = CFrame.new(214.688675, 126.626984, -12600.2236, -0.180400655, -1.09679892e-08, 0.983593225, 1.94620693e-08, 1, 1.47204746e-08, -0.983593225, 2.17983427e-08, -0.180400655)

    -- doTrainGrind (File A 1583-1672)
    -- FIX (user 2026-07-02): khi TRAINING dùng attack + gom quái kiểu V3 (v3FastAttack/v3BringMob) — đánh
    -- ăn chắc bằng RE/RegisterHit + remote mã hoá, thay FastAttack nền (LeftClickRemote) hay lơ lửng không
    -- gây damage. THÊM timeout per-mob (chống lỗi đứng trên đầu bãi quái không đánh được sau vài bãi:
    -- quái không chết → repeat until checkmob_ kẹt vĩnh viễn). Status "Training" gửi TRƯỚC vòng grind.
    function Training.doTrainGrind(tag, AB, reassertFn)
        if reassertFn then reassertFn() end
        CombatActions.initV3Combat()   -- đảm bảo seed/remoteAttack sẵn sàng trước khi grind
        if AB == "raiding" then
            local boss = workspace.Enemies:FindFirstChild("Cake Prince") or workspace.Enemies:FindFirstChild("Dough King")
            if boss then
                status(tag .. " Raiding for fragment (boss helper)")
                -- [FINAL §J7] Cake Prince / Dough King dùng CHUNG helper attackBossAttempt — KHÔNG còn
                --   đứng cao 25 studs, KHÔNG FastAttack-only, KHÔNG timeout block 60s. Mỗi attempt hữu hạn;
                --   nếu boss chưa chết, thoát để tick sau tìm target lại (không block MainLoop).
                local ok, reason = CombatActions.attackBossAttempt(boss, {
                    maxSeconds = 14,
                    phaseCheck = function()
                        return (workspace.Enemies:FindFirstChild("Cake Prince") ~= nil)
                            or (workspace.Enemies:FindFirstChild("Dough King") ~= nil)
                    end,
                })
                DBG("[RAID] boss attempt → " .. tostring(reason), ok and "ok" or "warn", "raid_boss")
            end
            return
        end

        Training.pressV4()
        -- cửa sổ đếm kill (chỉ main) (File A 1626-1633)
        if State.isMain[State.myName] then
            if not RuntimeState.trainGrindLastT or (tick() - RuntimeState.trainGrindLastT) > 5 then
                RuntimeState.trainWinStart = tick(); RuntimeState.trainKills = 0
            end
            RuntimeState.trainGrindLastT = tick()
            if not RuntimeState.trainWinStart then RuntimeState.trainWinStart = tick() end
        end

        if getdis(pos__) < 1500 then
            status(tag .. " Training (Kill Mobs)")   -- status TRƯỚC vòng grind (tránh kẹt status trước loop stall)
            for _, v in ipairs(getmob1(pos__)) do
                if trainTimeoutHop(tag) then return end
                local lastY, lastTf, lastTrainPost = 0, nil, 0
                local mobT0 = tick()   -- timeout per-mob (backstop): chống kẹt đứng trên đầu quái không đánh được
                local mobTimedOut = false
                -- GHOST DETECT: mob còn trong workspace.Enemies + Health>0 ở CLIENT nhưng server đã xoá/đã
                -- chết (hoặc v3BringMob teleport HRP làm mất network-owner → RegisterHit không ăn). checkmob_
                -- chỉ đọc Health client → true mãi → repeat kẹt trên xác. Bám HP: đánh mà HP KHÔNG tụt trong
                -- GHOST_TTL giây (chỉ tính lúc đang đánh, không tính lúc chờ V4) → coi là ghost → bỏ ngay.
                local GHOST_TTL = 6
                local lastHp, lastHpDropT = nil, tick()
                repeat
                    if trainTimeoutHop(tag) then return end
                    -- ANTI-STUCK backstop: quá 20s mà quái chưa chết → bỏ con này, sang con kế
                    if (tick() - mobT0) > 20 then
                        status(tag .. " Training (mob stuck >20s → next)")
                        mobTimedOut = true
                        break
                    end
                    local c  = LP.Character
                    local tf = (c and c:FindFirstChild("RaceTransformed") and c.RaceTransformed.Value) or false
                    if tf then
                        if lastTf ~= true then
                            local hrp = v:FindFirstChild("HumanoidRootPart")
                            if hrp then pcall(function() topos(hrp.CFrame * CFrame.new(0, 150, 0)) end) end
                            status(tag .. " Training (Wait for end V4)")
                            lastTf = true
                        end
                        lastHpDropT = tick()   -- đang chờ V4 (không đánh) → không tính vào ghost timer
                        if (tick() - lastTrainPost) > 4 then if reassertFn then reassertFn() end; lastTrainPost = tick() end
                        task.wait(0.5)
                    else
                        Movement.equip(); Movement.haki()
                        -- TRAINING: KHÔNG spam chiêu. Tắt cờ để background loop (Z/X/C/V/F) im lặng.
                        _G.SHOULDSPAMSKILLS = false
                        local hrp = v:FindFirstChild("HumanoidRootPart")
                        -- V3: gom quái quanh con này rồi đánh trực tiếp. Đứng CẠNH mob (offset ngang 20,
                        -- Y ±20 tùy độ cao) và QUAY MẶT vào mob — KHÔNG lơ lửng thẳng trên đầu — để M1 +
                        -- RegisterHit ăn chắc, giữ trong 65 studs, giảm ghost do lệch vị trí / mất tầm.
                        if hrp then
                            v3BringMob(nil, 3, hrp.CFrame)
                            pcall(function()
                                local yoff = (hrp.Position.Y > 60) and -20 or 20
                                topos(CFrame.new(hrp.Position + Vector3.new(0, yoff, -20), hrp.Position))
                            end)
                        end
                        -- Chỉ dùng V3 attack (RegisterAttack + RegisterHit + encoded remote), không keypress chiêu.
                        if CombatActions.initV3Combat() then
                            v3FastAttack()
                        end
                        -- theo dõi HP: có tụt thì reset mốc; đứng yên quá GHOST_TTL → ghost → bỏ
                        local hp = (v:FindFirstChild("Humanoid") and v.Humanoid.Health) or nil
                        if hp then
                            if lastHp == nil or hp < lastHp - 0.5 then lastHpDropT = tick() end
                            lastHp = hp
                        end
                        if (tick() - lastHpDropT) > GHOST_TTL then
                            status(tag .. " Training (ghost mob HP đứng " .. GHOST_TTL .. "s → next)")
                            mobTimedOut = true
                            break
                        end
                        if lastTf ~= false then
                            status(tag .. " Training (Kill Mobs)")
                            lastTf = false
                        end
                        -- reassert định kỳ trong nhánh kill (giữ status training không bị đá khi grind lâu)
                        if (tick() - lastTrainPost) > 4 then if reassertFn then reassertFn() end; lastTrainPost = tick() end
                        if (tick() - lastY > 0.4) then lastY = tick(); Training.pressV4() end
                        task.wait()
                    end
                until not checkmob_(v)
                -- CHỈ đếm kill khi quái THẬT chết. Timeout/ghost (mobTimedOut) = đánh không ăn → KHÔNG đếm,
                -- nếu không trainKills phồng >10 → trainTimeoutHop tưởng "năng suất" → không hop → kẹt bãi.
                if not mobTimedOut and State.isMain[State.myName] then RuntimeState.trainKills = (RuntimeState.trainKills or 0) + 1 end
            end
        else
            topos(pos__)
        end
    end

    -- handleTraining(ctx): 1 nhịp grind, trả phase rõ
    function Training.handleTraining(tag, AB, reassertFn)
        Training.doTrainGrind(tag, AB, reassertFn)
        if AB == "raiding" then return "need_fragments" end
        return "training"
    end
end
local function trialable() return Training.checkTrialable() end
local function cachedTrialable() return Training.cachedTrialable() end
local function doTrainGrind(tag, AB, fn) return Training.doTrainGrind(tag, AB, fn) end


--[[ ============================================================================
 [21b] FRAGMENT TYRANT — worker kiếm Fragment CHỈ KHI V4 NEED PURCHASE.

  AUTHORITY / SAFETY:
    * KHÔNG reroll race, KHÔNG ghi Completed-fragment, KHÔNG ChangeFolder.
    * KHÔNG tự SetTeam / TravelZou / tạo UI / chạy standalone vô điều kiện.
    * StateMachine là nơi DUY NHẤT bật/tắt worker bằng V4 state.
    * Worker chỉ sở hữu movement/combat khi FragmentTyrant.active=true; StateMachine return ngay
      ở fragment gate nên Scout/FullMoon/Trial/Training không tranh movement.
    * Khi đủ đúng fragmentCost: STOP worker sạch TRƯỚC; Training mới UpgradeRace("Buy"),
      invalidate cache rồi tick sau đọc phase mới.

  Ruột farm port từ Auto Tyrant user gửi 2026-08-11:
    Tiki mobs -> 4 mắt đỏ -> 12 vase CFrame Z/X/C -> Tyrant -> lặp.
============================================================================ ]]
local FragmentTyrant = {}
do
    local rawCfg = getgenv().FragmentTyrantConfig
    if type(rawCfg) ~= "table" then rawCfg = {}; getgenv().FragmentTyrantConfig = rawCfg end

    local FTConfig = {
        Weapon = tostring(rawCfg.Weapon or "Dragon Talon"),
        AutoBuyDragonTalon = rawCfg.AutoBuyDragonTalon ~= false,
        TweenSpeed = tonumber(rawCfg.TweenSpeed) or 330,
        FarmHeight = tonumber(rawCfg.FarmHeight) or 18,
        BossHeight = tonumber(rawCfg.BossHeight) or 25,
        AttackDistance = tonumber(rawCfg.AttackDistance) or 85,
        VaseSkillKeys = { "Z", "X", "C" },
        VaseSkillRetryDelay = tonumber(rawCfg.VaseSkillRetryDelay) or 0.18,
        EyeReadyStableTime = tonumber(rawCfg.EyeReadyStableTime) or 0.75,
        WorkerInterval = tonumber(rawCfg.WorkerInterval) or 0.10,
    }

    local TIKI_CENTER = CFrame.new(
        -16490.9727, 98.1144867, 1245.58984,
        -0.034969449, 0, 0.999388516,
        0, 1, 0,
        -0.999388516, 0, -0.034969449
    )
    local ARENA_CENTER = Vector3.new(-16335, 174, 1397)
    local DRAGON_TALON_BUY_POS = CFrame.new(5661.616211, 1211.299438, 865.999451)

    local STATIC_VASE_CENTER = Vector3.new(-16275.984642, 157.838229, 1390.372659)
    local STATIC_VASE_TARGETS = {
        {Name="Vase01", CFrame=CFrame.new(-16332.5264,158.071655,1440.32507,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase02", CFrame=CFrame.new(-16335.1641,158.166733,1465.64404,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase03", CFrame=CFrame.new(-16288.6094,158.166733,1470.36816,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase04", CFrame=CFrame.new(-16258.001,156.760635,1461.40356,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase05", CFrame=CFrame.new(-16245.4121,158.437012,1463.36597,-0.993159413,0,0.116766132,0,1,0,-0.116766132,0,-0.993159413)},
        {Name="Vase06", CFrame=CFrame.new(-16212.4688,158.166733,1466.34387,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase07", CFrame=CFrame.new(-16211.9463,158.071655,1322.39807,-0.466439605,0,-0.884553134,0,1,0,0.884553134,0,-0.466439605)},
        {Name="Vase08", CFrame=CFrame.new(-16250.2354,158.166733,1313.01941,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase09", CFrame=CFrame.new(-16260.2803,158.166733,1320.45532,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase10", CFrame=CFrame.new(-16296.1162,157.767914,1315.79407,-0.463313937,0,0.886194229,0,1,0,-0.886194229,0,-0.463313937)},
        {Name="Vase11", CFrame=CFrame.new(-16286.0586,155.949478,1323.83765,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
        {Name="Vase12", CFrame=CFrame.new(-16334.9971,158.166733,1321.51672,0.999388874,0,0.0349550731,0,1,0,-0.0349550731,0,0.999388874)},
    }

    local VASE_SKILL_HOLD_TIME = { Z = 0.035, X = 0.12, C = 0.05 }
    local VASE_SKILL_RELEASE_WAIT = { Z = 0.65, X = 0.50, C = 1.45 }
    local DEFAULT_SKILL_COOLDOWNS = { Z = 6, X = 8, C = 12 }
    local internalSkillReadyAt = {}

    local TikiMobs = {
        ["Isle Outlaw"] = true,
        ["Island Boy"] = true,
        ["Sun-kissed Warrior"] = true,
        ["Isle Champion"] = true,
        ["Serpent Hunter"] = true,
        ["Skull Slayer"] = true,
    }

    local active = false
    local targetFragments = 0
    local generation = 0
    local worker = nil
    local currentMode = "IDLE"
    local currentTarget = nil
    local skillBusy = false
    local eyeReadySince = nil

    local function ftStatus(msg)
        RuntimeState.fragmentTyrantMode = currentMode
        RuntimeState.fragmentTyrantStatus = tostring(msg or "")
        status("[FRAGMENT-TYRANT] " .. tostring(msg or ""))
    end

    local function currentFragments()
        return Training.getCurrentFragments()
    end

    local function charParts()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        return char, hum, hrp
    end

    local function normalizeName(name)
        return tostring(name or ""):gsub("%s+", ""):lower()
    end

    local function findTool(name)
        local want = normalizeName(name)
        local char = LocalPlayer.Character
        local backpack = LocalPlayer:FindFirstChild("Backpack")
        if char then
            for _, tool in ipairs(char:GetChildren()) do
                if tool:IsA("Tool") and normalizeName(tool.Name) == want then return tool end
            end
        end
        if backpack then
            for _, tool in ipairs(backpack:GetChildren()) do
                if tool:IsA("Tool") and normalizeName(tool.Name) == want then return tool end
            end
        end
        return nil
    end

    local function hasMeleeStyle(styleName)
        local ok, value = pcall(function()
            local data = LocalPlayer:FindFirstChild("Data")
            local melee = data and data:FindFirstChild("Melee")
            return melee and melee.Value or nil
        end)
        return ok and value ~= nil and normalizeName(value) == normalizeName(styleName)
    end

    local function hasDragonTalon()
        return findTool("Dragon Talon") ~= nil
            or findTool("DragonTalon") ~= nil
            or hasMeleeStyle("Dragon Talon")
    end

    local function equipDragonTalon()
        local char, hum = charParts()
        if not char or not hum then return nil end
        local tool = findTool("Dragon Talon") or findTool("DragonTalon")
        if tool and tool.Parent ~= char then
            pcall(function() hum:EquipTool(tool) end)
            task.wait(0.08)
        end
        if tool and tool.Parent == char then return tool end
        pcall(function() Movement.equip() end)
        return char:FindFirstChildOfClass("Tool")
    end

    local function moveToAndWait(cf, timeout)
        local _, hum, hrp = charParts()
        if not (hum and hum.Health > 0 and hrp and cf) then return false end
        pcall(function() Movement.topos(cf) end)
        local started = tick()
        timeout = tonumber(timeout) or 12
        while active and Runtime.alive and tick() - started < timeout do
            _, hum, hrp = charParts()
            if not (hum and hum.Health > 0 and hrp) then return false end
            if (hrp.Position - cf.Position).Magnitude <= 12 then
                pcall(function() Movement.cancel() end)
                hrp.CFrame = cf
                return true
            end
            task.wait(0.08)
        end
        return false
    end

    local function getEnemyFolders()
        local out = {}
        local enemies = workspace:FindFirstChild("Enemies")
        if enemies then out[#out + 1] = enemies end
        local origin = workspace:FindFirstChild("_WorldOrigin")
        local oe = origin and origin:FindFirstChild("Enemies")
        if oe then out[#out + 1] = oe end
        return out
    end

    local function baseEnemyName(name)
        local clean = tostring(name or "")
        clean = clean:gsub("%s*%[Lv%.%s*%d+%]", "")
        clean = clean:gsub("%s*%[Lv%s*%d+%]", "")
        clean = clean:gsub("%s*%[Boss%]", "")
        clean = clean:gsub("%s*%[Raid Boss%]", "")
        return clean:gsub("%s+$", "")
    end

    local function isTikiMob(enemy)
        return enemy and TikiMobs[baseEnemyName(enemy.Name)] == true
    end

    local function findTyrant()
        for _, folder in ipairs(getEnemyFolders()) do
            for _, enemy in ipairs(folder:GetChildren()) do
                if string.find(string.lower(enemy.Name), "tyrant", 1, true) then
                    local hum = enemy:FindFirstChildOfClass("Humanoid")
                    local hrp = enemy:FindFirstChild("HumanoidRootPart")
                    if hum and hrp and hum.Health > 0 then return enemy end
                end
            end
        end
        return nil
    end

    local function nearestTikiMob()
        local _, _, root = charParts()
        if not root then return nil end
        local best, bestD = nil, math.huge
        for _, folder in ipairs(getEnemyFolders()) do
            for _, enemy in ipairs(folder:GetChildren()) do
                local hum = enemy:FindFirstChildOfClass("Humanoid")
                local erp = enemy:FindFirstChild("HumanoidRootPart")
                if hum and erp and hum.Health > 0 and isTikiMob(enemy) then
                    local d = (root.Position - erp.Position).Magnitude
                    if d < bestD then best, bestD = enemy, d end
                end
            end
        end
        return best
    end

    local FINAL_EYE_COLOR = Color3.fromRGB(255, 57, 57)
    local EYE_COLOR_TOLERANCE = 10 / 255

    local function eyeParts()
        local map = workspace:FindFirstChild("Map")
        local tiki = map and map:FindFirstChild("TikiOutpost")
        local island = tiki and tiki:FindFirstChild("IslandModel")
        local chunks = island and island:FindFirstChild("IslandChunks")
        local e = chunks and chunks:FindFirstChild("E")
        if not island then return nil, nil, nil, nil end
        return island:FindFirstChild("Eye1"), island:FindFirstChild("Eye2"),
            e and e:FindFirstChild("Eye3"), e and e:FindFirstChild("Eye4")
    end

    local function eyeRed(eye)
        if not eye or not eye:IsA("BasePart") or not eye:IsDescendantOf(workspace) then return false end
        local c = eye.Color
        return math.abs(c.R - FINAL_EYE_COLOR.R) <= EYE_COLOR_TOLERANCE
            and math.abs(c.G - FINAL_EYE_COLOR.G) <= EYE_COLOR_TOLERANCE
            and math.abs(c.B - FINAL_EYE_COLOR.B) <= EYE_COLOR_TOLERANCE
            and eye.Transparency <= 0.10
    end

    local function eyeProgress()
        local e1, e2, e3, e4 = eyeParts()
        local n = (eyeRed(e1) and 1 or 0) + (eyeRed(e2) and 1 or 0)
            + (eyeRed(e3) and 1 or 0) + (eyeRed(e4) and 1 or 0)
        if n == 4 then eyeReadySince = eyeReadySince or tick() else eyeReadySince = nil end
        return n
    end

    local function eyesReady()
        return eyeProgress() == 4 and eyeReadySince ~= nil
            and (tick() - eyeReadySince) >= FTConfig.EyeReadyStableTime
    end

    local function buyDragonTalon()
        if hasDragonTalon() then return true end
        if findTyrant() or not FTConfig.AutoBuyDragonTalon then return false end
        currentMode = "BUY_DRAGON_TALON"
        ftStatus("Chưa có Dragon Talon → đi mua trước khi phá bình")
        moveToAndWait(DRAGON_TALON_BUY_POS, 25)
        for _ = 1, 15 do
            if not active or currentFragments() >= targetFragments then return false end
            SafeRemote.invoke(3, "BuyDragonTalon")
            task.wait(0.5)
            if hasDragonTalon() then return true end
        end
        return false
    end

    local function ensureDragonTalon()
        if not hasDragonTalon() then buyDragonTalon() end
        return equipDragonTalon()
    end

    local function getSkillFrame(tool, keyName)
        local gui = LocalPlayer:FindFirstChild("PlayerGui")
        local main = gui and gui:FindFirstChild("Main")
        local skills = main and main:FindFirstChild("Skills")
        if not skills or not tool then return nil end
        local toolSkills = skills:FindFirstChild(tool.Name)
            or skills:FindFirstChild(FTConfig.Weapon)
            or skills:FindFirstChild("Dragon Talon")
        return toolSkills and toolSkills:FindFirstChild(keyName) or nil
    end

    local function skillReady(tool, keyName)
        if tick() < (internalSkillReadyAt[keyName] or 0) then return false end
        local frame = getSkillFrame(tool, keyName)
        if not frame then return true end
        local cooldown = frame:FindFirstChild("Cooldown")
        if cooldown and cooldown:IsA("GuiObject") then
            return cooldown.Size.X.Scale <= 0.015 and cooldown.Size.X.Offset <= 2
        end
        return true
    end

    local function sendSkillKey(keyName, down)
        local ok = pcall(function()
            VirtualInputManager:SendKeyEvent(down, keyName, false, game)
        end)
        if not ok and Enum.KeyCode[keyName] then
            ok = pcall(function()
                VirtualInputManager:SendKeyEvent(down, Enum.KeyCode[keyName], false, game)
            end)
        end
        return ok
    end

    local function castVaseSkill(targetPosition, keyName)
        if skillBusy or not active then return false end
        keyName = string.upper(tostring(keyName or ""))
        if keyName ~= "Z" and keyName ~= "X" and keyName ~= "C" then return false end

        local tool = ensureDragonTalon()
        local char, hum, root = charParts()
        if not tool or not char or tool.Parent ~= char or not hum or hum.Health <= 0 or not root then return false end
        if not skillReady(tool, keyName) then return false end

        skillBusy = true
        RuntimeState.fragmentTyrantSkillCasting = true
        _G.SHOULDSPAMSKILLS = false
        pcall(function() CombatActions.setSkillAimTarget(targetPosition) end)

        local keyDown = false
        local ok, err = pcall(function()
            hum.Sit = false
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            local flatLook = Vector3.new(targetPosition.X, root.Position.Y, targetPosition.Z)
            if (flatLook - root.Position).Magnitude > 0.1 then
                root.CFrame = CFrame.lookAt(root.Position, flatLook)
            end
            task.wait(0.08)
            keyDown = sendSkillKey(keyName, true)
            if not keyDown then return end
            task.wait(VASE_SKILL_HOLD_TIME[keyName] or 0.10)
            sendSkillKey(keyName, false)
            keyDown = false
            internalSkillReadyAt[keyName] = tick() + (DEFAULT_SKILL_COOLDOWNS[keyName] or 7)
            task.wait(VASE_SKILL_RELEASE_WAIT[keyName] or 0.50)
        end)

        if keyDown then sendSkillKey(keyName, false) end
        pcall(function() CombatActions.clearSkillAimTarget() end)
        RuntimeState.fragmentTyrantSkillCasting = false
        skillBusy = false
        if not ok then Logger.warn("[FRAGMENT-TYRANT] vase skill lỗi: " .. tostring(err), "ft_vase_skill") end
        if ok then task.wait(FTConfig.VaseSkillRetryDelay) end
        return ok
    end

    local function vaseAim(target)
        return target.CFrame.Position + Vector3.new(0, 0.75, 0)
    end

    local function vaseStand(target, keyName)
        local vasePosition = target.CFrame.Position
        local aimPosition = vaseAim(target)
        local inward = Vector3.new(
            STATIC_VASE_CENTER.X - vasePosition.X,
            0,
            STATIC_VASE_CENTER.Z - vasePosition.Z
        )
        if inward.Magnitude < 0.1 then inward = Vector3.new(0, 0, -1) else inward = inward.Unit end

        local standPosition
        if keyName == "Z" then
            standPosition = vasePosition + inward * 92 + Vector3.new(0, 3.0, 0)
        elseif keyName == "C" then
            standPosition = vasePosition + Vector3.new(0, 3.2, 0)
        else
            standPosition = vasePosition + inward * 14 + Vector3.new(0, 3.0, 0)
        end
        if keyName == "C" then return CFrame.lookAt(standPosition, standPosition + inward * 8) end
        return CFrame.lookAt(standPosition, aimPosition)
    end

    local function waitVaseSkill(preferred, timeout)
        local started = tick()
        while active and not findTyrant() and eyesReady() do
            local tool = ensureDragonTalon()
            if tool then
                preferred = string.upper(tostring(preferred or ""))
                if preferred ~= "" and skillReady(tool, preferred) then return preferred end
                for _, k in ipairs(FTConfig.VaseSkillKeys) do
                    if skillReady(tool, k) then return k end
                end
            end
            if timeout and tick() - started >= timeout then return nil end
            task.wait(0.10)
        end
        return nil
    end

    local function attackVase(target, preferred)
        if not active or not target or findTyrant() or not eyesReady() then return false end
        local key = waitVaseSkill(preferred, 15)
        if not key then return false end
        local aim = vaseAim(target)
        local stand = vaseStand(target, key)
        currentMode = "VASES"
        ftStatus(target.Name .. " | skill " .. tostring(key))
        moveToAndWait(stand, 15)
        local _, hum, root = charParts()
        if not (hum and hum.Health > 0 and root) then return false end
        pcall(function() Movement.cancel() end)
        root.CFrame = stand
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        task.wait(0.10)
        return castVaseSkill(aim, key)
    end

    local function breakVases(gen)
        currentMode = "VASES"
        local entryCF = CFrame.lookAt(STATIC_VASE_CENTER + Vector3.new(0, 8, 0), STATIC_VASE_CENTER)
        moveToAndWait(entryCF, 20)
        local pass = 0
        while active and generation == gen and Runtime.alive and eyesReady() and not findTyrant() do
            if currentFragments() >= targetFragments then return end
            pass = pass + 1
            for index, target in ipairs(STATIC_VASE_TARGETS) do
                if not active or generation ~= gen or findTyrant() or not eyesReady() then return end
                local preferred = FTConfig.VaseSkillKeys[((index + pass - 2) % #FTConfig.VaseSkillKeys) + 1]
                attackVase(target, preferred)
                task.wait(0.08)
            end
            ftStatus("Đã quét 12 bình lượt " .. tostring(pass) .. " → chờ boss/bình")
            task.wait(0.35)
        end
    end

    local function farmTiki(enemy, gen)
        local hum = enemy and enemy:FindFirstChildOfClass("Humanoid")
        local erp = enemy and enemy:FindFirstChild("HumanoidRootPart")
        if not (hum and erp and hum.Health > 0) then return end
        currentTarget = enemy
        currentMode = "MOBS"
        local stuckAt = tick()
        local lastHp = hum.Health
        while active and generation == gen and Runtime.alive
            and enemy.Parent and hum.Parent and erp.Parent and hum.Health > 0
        do
            if currentFragments() >= targetFragments then break end
            local _, ph, root = charParts()
            if not (ph and ph.Health > 0 and root) then break end
            pcall(function() Movement.haki() end)
            pcall(function() Movement.equip() end)
            pcall(function() CombatActions.v3BringMob(enemy.Name, 3, erp.CFrame) end)

            local target = CFrame.new(erp.Position + Vector3.new(0, FTConfig.FarmHeight, -20), erp.Position)
            if (root.Position - erp.Position).Magnitude > 55 then
                pcall(function() Movement.topos(target) end)
            else
                pcall(function()
                    Movement.cancel()
                    root.CFrame = target
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)
            end
            if CombatActions.initV3Combat() then pcall(function() CombatActions.v3FastAttack(enemy.Name) end) end

            if hum.Health < lastHp - 0.5 then
                lastHp = hum.Health
                stuckAt = tick()
            elseif tick() - stuckAt > 15 then
                pcall(function() root.CFrame = target end)
                stuckAt = tick()
            end
            task.wait(0.08)
        end
        currentTarget = nil
    end

    local function farmTyrant(enemy, gen)
        if not enemy then return end
        currentTarget = enemy
        currentMode = "BOSS"
        ftStatus("Tyrant xuất hiện → đánh boss")
        while active and generation == gen and Runtime.alive do
            local hum = enemy:FindFirstChildOfClass("Humanoid")
            if not (enemy.Parent and hum and hum.Health > 0) then break end
            if currentFragments() >= targetFragments then break end
            local ok, reason = CombatActions.attackBossAttempt(enemy, {
                maxSeconds = 14,
                phaseCheck = function()
                    return active and generation == gen and currentFragments() < targetFragments
                end,
            })
            DBG("[FRAGMENT-TYRANT] boss attempt → " .. tostring(reason), ok and "ok" or "warn", "ft_boss")
            task.wait(0.05)
        end
        currentTarget = nil
    end

    local function cleanupMotion()
        pcall(function() Movement.cancel() end)
        pcall(function() CombatActions.clearSkillAimTarget() end)
        RuntimeState.fragmentTyrantSkillCasting = false
        _G.SHOULDSPAMSKILLS = false
        currentTarget = nil
    end

    function FragmentTyrant.isActive() return active end
    function FragmentTyrant.getTarget() return targetFragments end
    function FragmentTyrant.getMode() return currentMode end
    function FragmentTyrant.currentFragments() return currentFragments() end
    function FragmentTyrant.targetReached()
        return active and targetFragments > 0 and currentFragments() >= targetFragments
    end

    function FragmentTyrant.stop(reason)
        if not active and not worker then return end
        active = false
        generation = generation + 1
        RuntimeState.fragmentTyrantActive = false
        RuntimeState.fragmentTyrantTarget = 0
        cleanupMotion()
        currentMode = "IDLE"
        RuntimeState.fragmentTyrantMode = currentMode
        worker = nil
        Logger.info("[FRAGMENT-TYRANT] STOP: " .. tostring(reason or "unknown"), "ft_stop")
    end

    function FragmentTyrant.start(requiredFragments)
        local target = math.max(0, tonumber(requiredFragments) or 0)
        local frags = currentFragments()
        if target <= 0 or frags >= target then
            if active then FragmentTyrant.stop("target already reached") end
            return false
        end

        targetFragments = target
        RuntimeState.fragmentTyrantTarget = target
        if active then return true end

        active = true
        generation = generation + 1
        local myGen = generation
        RuntimeState.fragmentTyrantActive = true
        _G.SHOULDSPAMSKILLS = false
        Logger.info("[FRAGMENT-TYRANT] START " .. tostring(frags) .. "/" .. tostring(target), "ft_start")

        worker = task.spawn(function()
            pcall(function() CombatActions.initV3Combat() end)
            while Runtime.alive and active and generation == myGen do
                local fr = currentFragments()
                if fr >= targetFragments then
                    FragmentTyrant.stop("fragment target reached")
                    return
                end

                local _, hum = charParts()
                if not (hum and hum.Health > 0) then
                    currentMode = "RESPAWN"
                    ftStatus("Chờ Character hồi sinh | F=" .. tostring(fr) .. "/" .. tostring(targetFragments))
                    task.wait(0.6)
                else
                    local tyrant = findTyrant()
                    if tyrant then
                        farmTyrant(tyrant, myGen)
                    elseif eyesReady() then
                        ftStatus("Đủ 4/4 mắt đỏ → phá 12 bình")
                        breakVases(myGen)
                    else
                        currentMode = "MOBS"
                        local eyes = eyeProgress()
                        ftStatus("Farm NPC Tiki | mắt " .. tostring(eyes) .. "/4 | F=" .. tostring(fr) .. "/" .. tostring(targetFragments))
                        ensureDragonTalon()
                        local mob = nearestTikiMob()
                        if mob then
                            farmTiki(mob, myGen)
                        else
                            moveToAndWait(TIKI_CENTER, 18)
                            task.wait(0.5)
                        end
                    end
                end
                task.wait(FTConfig.WorkerInterval)
            end
        end)
        return true
    end
end

--[[ ============================================================================
 [22] ABILITYSYNC — FILE-BASED y chang File A (folder racev4_vunguyen, giờ Hà Nội,
      CommE:FireServer("ActivateAbility")). (File A 2429-2698)
============================================================================ ]]
local AbilitySync = {}
do
    local ABILITY_FIRE_WINDOW = 6
    local AT_DOOR_DIST        = 25
    local START_LEAD          = 5
    local ABILITY_COOLDOWN    = 30
    local TZ_OFFSET           = 7 * 3600
    local SYNC_DIR            = "racev4_vunguyen"
    local START_FILE          = SYNC_DIR .. "/starttime.txt"
    AbilitySync.AT_DOOR_DIST  = AT_DOOR_DIST

    RuntimeState.myFireEpoch = RuntimeState.myFireEpoch or 0

    function AbilitySync.ensureSyncDir()
        if isfolder and not isfolder(SYNC_DIR) then pcall(function() makefolder(SYNC_DIR) end) end
    end
    AbilitySync.ensureSyncDir()
    -- dọn file cũ ở thư mục gốc (File A 2452-2458)
    pcall(function()
        if isfile and delfile then
            if isfile("checkalready.txt") then delfile("checkalready.txt") end
            if isfile("starttime.txt") then delfile("starttime.txt") end
        end
    end)

    -- giờ Hà Nội (File A 2502-2516)
    local function hanoiSecOfDay(epoch) return math.floor(epoch + TZ_OFFSET) % 86400 end
    local function fmtHanoi(epoch)
        local s = hanoiSecOfDay(epoch)
        return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor((s % 3600) / 60), s % 60)
    end
    local function parseHanoi(str)
        local h, m, s = string.match(str or "", "(%d+):(%d+):(%d+)")
        if not h then return nil end
        return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s)
    end

    local function checkFileForLabel(label) return SYNC_DIR .. "/checkalready_" .. string.lower(label) end

    -- FIX (user 2026-07-04) — bảng mới: cả Position + LookVector → tạo CFrame.lookAt để giữ hướng nhân vật.
    -- User yêu cầu: không dùng CFrame.new(x,y,z) 3-số nữa. LookVector ép Y=0 (CheckCoor báo 0.000/-0.000).
    local TRIAL_DOOR_DATA = {
        ["Mink"] = {
            pos = Vector3.new(29020.736328, 14896.214844, -375.964600),
            look = Vector3.new(0.927, 0, -0.374),
        }, -- Rabbit
        ["Human"] = {
            pos = Vector3.new(29237.261719, 14896.117188, -202.743515),
            look = Vector3.new(0.868, 0, -0.496),
        },
        ["Skypiea"] = {
            pos = Vector3.new(28968.304688, 14924.379883, 237.973160),
            look = Vector3.new(1.000, 0, 0.020),
        }, -- Angel
        ["Fishman"] = {
            pos = Vector3.new(28224.082031, 14896.032227, -215.569672),
            look = Vector3.new(-0.954, 0, -0.299),
        }, -- Shark
        ["Ghoul"] = {
            pos = Vector3.new(28669.337891, 14895.611328, 454.683319),
            look = Vector3.new(0.004, 0, 1.000),
        },
        ["Cyborg"] = {
            pos = Vector3.new(28492.220703, 14900.972656, -426.378815),
            look = Vector3.new(-0.985, 0, 0.170),
        },
    }
    WorldProbe.TRIAL_DOOR_DATA = TRIAL_DOOR_DATA

    -- normalizeRace: ánh xạ alias → race chuẩn Blox Fruits.
    -- Rabbit=Mink, Mink=Mink, Angel=Skypiea, Skypiea=Skypiea,
    -- Shark=Fishman, Fishman=Fishman, Human, Ghoul, Cyborg.
    function WorldProbe.normalizeRace(race)
        if not race then return nil end
        local r = tostring(race):lower()
        local map = {
            ["rabbit"]   = "Mink",
            ["mink"]     = "Mink",
            ["angel"]    = "Skypiea",
            ["skypiea"]  = "Skypiea",
            ["shark"]    = "Fishman",
            ["fishman"]  = "Fishman",
            ["human"]    = "Human",
            ["ghoul"]    = "Ghoul",
            ["cyborg"]   = "Cyborg",
        }
        return map[r]
    end

    -- getTrialDoorCFrame: ưu tiên tuyệt đối, tạo CFrame.lookAt(position, position+look) để đứng đúng hướng.
    function WorldProbe.getTrialDoorCFrame(race)
        race = race or WorldProbe.getRace()
        race = WorldProbe.normalizeRace(race)
        if not race then return nil end

        local data = TRIAL_DOOR_DATA[race]
        if not data then return nil end

        local pos = data.pos
        local look = data.look
        if typeof(pos) ~= "Vector3" or typeof(look) ~= "Vector3" then return nil end

        -- ép Y=0 (CheckCoor báo 0.000 / -0.000, coi như 0, không cần nhìn lên/xuống)
        look = Vector3.new(look.X, 0, look.Z)
        if look.Magnitude <= 0 then
            return CFrame.new(pos)
        end

        look = look.Unit
        return CFrame.lookAt(pos, pos + look)
    end

    -- khoảng cách tới cửa — ƯU TIÊN WorldProbe.getTrialDoorCFrame() (toạ độ chuẩn do user cung cấp).
    -- Chỉ fallback getdoor() nếu không có manualCf. User 2026-07-04 yêu cầu: KHÔNG ưu tiên part thật trong map.
    function AbilitySync.distToMyDoor()
        local manualCf = WorldProbe.getTrialDoorCFrame()
        if manualCf then
            local d = getdis(manualCf)
            Diagnostics.lastDoorSrc, Diagnostics.lastDoorName, Diagnostics.lastDoorDist = "C",
                WorldProbe.normalizeRace(WorldProbe.getRace()) or "manual", d
            return d
        end
        local door = getdoor()
        if door then
            local d = getdis(door.CFrame)
            Diagnostics.lastDoorSrc, Diagnostics.lastDoorName, Diagnostics.lastDoorDist = "R", door.Name, d
            return d
        end
        Diagnostics.lastDoorSrc, Diagnostics.lastDoorName, Diagnostics.lastDoorDist = "X", "none", 1e9
        return 1e9
    end

    -- SAME = mình đang ở ĐÚNG server full moon Ally1 đã chốt (fullmoonJobid) — điểm hẹn chung
    -- của Main + 2 Ally (user 2026-07-02). Trước đây trả true vô điều kiện khi myName==curName,
    -- hoặc auto-true khi đứng fullmoonJobid mà main1 chưa chắc ở đó → SAME giả. Giờ CHỈ dựa vào
    -- game.JobId == fullmoonJobid: main1 và ally cùng so với 1 mốc → "same" chỉ khi thật sự tụ đúng chỗ.
    local _ssCache = { t = -1e9, v = false }
    function AbilitySync.sameServerAsCurrentMain()
        local fm = State.fullmoonJobid
        if fm and fm ~= "" then
            return game.JobId == fm
        end
        -- chưa chốt full moon → chưa có điểm hẹn → không thể "same"
        return false
    end

    function AbilitySync.allyIndexOf(nm)
        for i, v in ipairs(Config.allies) do if v == nm then return i end end
        return nil
    end

    -- label của mình (File A 2545-2553)
    function AbilitySync.myAbilityLabel()
        local curName, curIdx = getCurrentMainBeingUpgraded()
        if curName and State.myName == curName then return "Main" .. tostring(curIdx) end
        local ai = AbilitySync.allyIndexOf(State.myName)
        if ai then return "Ally" .. ai end
        return nil
    end

    -- nhãn bắt buộc true để chốt giờ: main turn + toàn bộ ally (File A 2556-2564)
    function AbilitySync.requiredLabels()
        local _curName, curIdx = getCurrentMainBeingUpgraded()
        local labels = {}
        if curIdx then table.insert(labels, "Main" .. tostring(curIdx)) end
        for i, _ in ipairs(Config.allies) do table.insert(labels, "Ally" .. i) end
        return labels
    end

    -- canactive: đã qua cooldown 30s (File A 2568-2572)
    function AbilitySync.myCanActive()
        local fe = RuntimeState.myFireEpoch or 0
        if fe <= 0 then return true end
        return serverNow() >= (fe + ABILITY_COOLDOWN)
    end

    -- đọc ready 1 label (File A 2576-2584)
    function AbilitySync.readLabelReady(label)
        local fp = checkFileForLabel(label)
        if not (isfile and isfile(fp)) then return false end
        local ok, data = pcall(readfile, fp)
        if not ok or not data then return false end
        local door = string.match(data, "doorandability=(%w+)") == "true"
        local cana = string.match(data, "canactiveability=(%w+)") == "true"
        return door and cana
    end

    -- ghi file riêng của mình (File A 2588-2599)
    function AbilitySync.writeMyCheck(label, cond)
        if not label then return end
        AbilitySync.ensureSyncDir()
        local fe = RuntimeState.myFireEpoch or 0
        local fireStr = (fe > 0) and fmtHanoi(fe) or "00:00:00"
        pcall(function()
            writefile(checkFileForLabel(label),
                label .. ":doorandability=" .. (cond and "true" or "false")
                .. ";canactiveability=" .. (AbilitySync.myCanActive() and "true" or "false")
                .. ";" .. fireStr)
        end)
    end

    -- đủ tất cả nhãn (File A 2602-2609)
    function AbilitySync.allReady()
        local req = AbilitySync.requiredLabels()
        if #req == 0 then return false end
        for _, lb in ipairs(req) do
            if not AbilitySync.readLabelReady(lb) then return false end
        end
        return true
    end

    -- đọc starttime (File A 2612-2617)
    function AbilitySync.readStart()
        if not (isfile and isfile(START_FILE)) then return nil end
        local ok, data = pcall(readfile, START_FILE)
        if not ok or not data then return nil end
        return parseHanoi((string.gsub(data, "%s", "")))
    end
    -- ghi starttime (main turn chốt) (File A 2649)
    function AbilitySync.writeStart(epoch)
        AbilitySync.ensureSyncDir()
        pcall(function() writefile(START_FILE, fmtHanoi(epoch)) end)
    end

    -- reportAtDoor: ghi check của mình (giữ tên module-style; nội dung = writeMyCheck)
    function AbilitySync.reportAtDoor()
        local label = AbilitySync.myAbilityLabel()
        if not label then return end
        local dd = AbilitySync.distToMyDoor()
        local ss = AbilitySync.sameServerAsCurrentMain()
        Diagnostics.lastDoorDist = dd; Diagnostics.lastSameSrv = ss
        local cond = (dd < AT_DOOR_DIST) and ss
        RuntimeState.myDoorReady = cond and true or false
        AbilitySync.writeMyCheck(label, cond)
    end
    -- maybeFire: main turn chốt starttime khi đủ ready (File A 2641-2651)
    function AbilitySync.maybeFire()
        local curName = getCurrentMainBeingUpgraded()
        if not (curName and State.myName == curName) then return end
        local now = serverNow()
        local last = RuntimeState.myStartEpoch or 0
        if (now - last) > (START_LEAD + ABILITY_FIRE_WINDOW) and AbilitySync.allReady() then
            AbilitySync.writeStart(now + START_LEAD)
            RuntimeState.myStartEpoch = now
        end
    end
    -- pressAbility: CommE ActivateAbility (File A 2688)
    function AbilitySync.pressAbility()
        RuntimeState.myFireEpoch = serverNow()
        pcall(function()
            ReplicatedStorage.Remotes.CommE:FireServer("ActivateAbility")
        end)
    end
    -- pollFire: đọc starttime, bấm trong cửa sổ hợp lệ, latch chống lặp (File A 2673-2698)
    function AbilitySync.pollFire()
        local st = AbilitySync.readStart() or RuntimeState.syncStart
        if st then RuntimeState.syncStart = st end
        if st and st ~= RuntimeState.allyLastFire then
            local age = hanoiSecOfDay(serverNow()) - st
            if age < -43200 then age = age + 86400 end
            if age >= ABILITY_FIRE_WINDOW then
                RuntimeState.allyLastFire = st
            elseif age >= 0 and AbilitySync.distToMyDoor() < AT_DOOR_DIST then
                RuntimeState.allyLastFire = st
                AbilitySync.pressAbility()
            end
        end
    end

    -- ===== 3 LOOP NỀN (y chang File A 2623-2698), check Runtime.alive =====
    function AbilitySync.startLoops()
        -- write loop 1s (File A 2623-2657)
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    RuntimeState.myDoorReady = false
                    local label = AbilitySync.myAbilityLabel()
                    if label then
                        local dd = AbilitySync.distToMyDoor()
                        local ss = AbilitySync.sameServerAsCurrentMain()
                        Diagnostics.lastDoorDist = dd; Diagnostics.lastSameSrv = ss
                        local cond = (dd < AT_DOOR_DIST) and ss
                        RuntimeState.myDoorReady = cond and true or false
                        AbilitySync.writeMyCheck(label, cond)
                        local curName = getCurrentMainBeingUpgraded()
                        if curName and State.myName == curName then
                            local now = serverNow()
                            local last = RuntimeState.myStartEpoch or 0
                            if (now - last) > (START_LEAD + ABILITY_FIRE_WINDOW) and AbilitySync.allReady() then
                                AbilitySync.writeStart(now + START_LEAD)
                                RuntimeState.myStartEpoch = now
                            end
                        end
                    end
                end)
                task.wait(1)
            end
        end)
        -- read starttime loop 1s (File A 2660-2668)
        task.spawn(function()
            while Runtime.alive do
                pcall(function()
                    local v = AbilitySync.readStart()
                    if v then RuntimeState.syncStart = v end
                end)
                task.wait(1)
            end
        end)
        -- press loop: ở cửa+ready → 0.1s, chưa → 0.5s (File A 2673-2698)
        task.spawn(function()
            while Runtime.alive do
                if RuntimeState.myDoorReady == true then
                    pcall(function()
                        local st = AbilitySync.readStart() or RuntimeState.syncStart
                        if st then RuntimeState.syncStart = st end
                        if st and st ~= RuntimeState.allyLastFire then
                            local age = hanoiSecOfDay(serverNow()) - st
                            if age < -43200 then age = age + 86400 end
                            if age >= ABILITY_FIRE_WINDOW then
                                RuntimeState.allyLastFire = st
                            elseif age >= 0 and AbilitySync.distToMyDoor() < AT_DOOR_DIST then
                                RuntimeState.allyLastFire = st
                                AbilitySync.pressAbility()
                            end
                        end
                    end)
                    task.wait(0.1)
                else
                    task.wait(0.5)
                end
            end
        end)
    end
end

--[[ ============================================================================
 [23] POSTTRIAL — ffup = kill phase/reset. helpreset main/ally. (File A 1855-2025)
============================================================================ ]]
local PostTrial = {}
do
    local B = Config.baseUrl

    -- ===== [PROD REFACTOR §22] DEATH GUARD cycle-scoped (1 connection / Character) =====
    -- VẤN ĐỀ CŨ: mainKillThenReset() được gọi MỖI MainTick (~0.35s) trong ffup. Mỗi lần gọi:
    --   (1) reset State.postTrialDeathDetected=false → XÓA tín hiệu chết trước khi FSM kịp xử lý;
    --   (2) tạo hum.Died:Connect MỚI → LEAK connection, nhiều callback cùng bắn.
    -- SỬA: 1 guard theo cycle/Character. armDeathGuard() idempotent — chỉ connect khi Character đổi,
    --   disconnect connection cũ, KHÔNG reset flag mỗi tick. Callback từ Character CŨ bị bỏ qua.
    local _guard = {
        conn = nil,          -- RBXScriptConnection hiện tại
        char = nil,          -- Character đang canh
        cycleId = nil,       -- id cycle đang canh (đơn điệu tăng)
        died = false,        -- ĐÃ phát hiện main chết trong cycle này
        reason = nil,
    }

    -- Bắt đầu (hoặc tiếp tục) canh chết cho cycle hiện tại. Gọi được nhiều lần — idempotent.
    function PostTrial.armDeathGuard(expectedCycleId)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if not hum then return false end
        -- cùng cycle + cùng Character + còn connection → không làm gì (KHÔNG tạo connection mới)
        if _guard.conn and _guard.char == char and _guard.cycleId == expectedCycleId then
            return true
        end
        -- Character/cycle đổi → disconnect cái cũ TRƯỚC (chống leak), rồi connect cái mới.
        -- Nếu chỉ server cycle id tới trễ/đổi nhưng Character vẫn là một instance,
        -- giữ nguyên tín hiệu chết đã quan sát; tuyệt đối không biến loss thành alive.
        local sameCharacter = (_guard.char == char)
        local preservedDied = sameCharacter and _guard.died == true
        local preservedReason = preservedDied and _guard.reason or nil
        local preservedDiedEmitted = sameCharacter and _guard._diedEmitted == true
        if _guard.conn then Safe.disconnect(_guard.conn, "posttrial_guard"); _guard.conn = nil end
        _guard.char = char
        _guard.cycleId = expectedCycleId
        _guard.died = preservedDied
        _guard.reason = preservedReason
        _guard._diedEmitted = preservedDiedEmitted
        local capturedChar = char
        local capturedCycle = expectedCycleId
        _guard.conn = hum.Died:Connect(function()
            -- Bỏ qua callback từ Character CŨ / cycle CŨ (chống event trễ ghi đè cycle mới).
            if _guard.char ~= capturedChar or _guard.cycleId ~= capturedCycle then return end
            -- [§XIV] intentional reset CHỈ được bỏ qua khi ĐỦ CẢ 4 điều kiện:
            --   (1) intentional flag = true, (2) cycle khớp (activeCycleId + intentionalResetCycleId),
            --   (3) Character khớp (intentionalResetCharacter), (4) server result = win_confirmed.
            --   Thiếu bất kỳ điều kiện nào (đặc biệt death TRƯỚC win_confirmed) → vẫn tính loss.
            local intentionalOK =
                State.intentionalPostTrialReset == true
                and State.activeCycleId == capturedCycle
                and State.intentionalResetCycleId == capturedCycle
                and State.intentionalResetCharacter == capturedChar
                and State.winConfirmed == true
            if intentionalOK then
                DBG("[POSTTRIAL] intentional reset death (cycle " .. tostring(capturedCycle) .. ") → bỏ qua", "ok", "posttrial_intentional")
                return
            end
            _guard.died = true
            _guard.reason = "humanoid_died"
            State.didEnterTrialThisTurn = false
            State.postTrialDeathDetected = true
            -- [FINAL §9.4/B2] gửi main_died idempotent (chỉ 1 lần / cycle) qua CriticalEvents.
            if Config.enableEventProtocol and not _guard._diedEmitted then
                _guard._diedEmitted = true
                CriticalEvents.emit("main_died", {
                    cycle_id = State.trialCycleId or capturedCycle,
                    character_id = tostring(capturedChar),
                    phase = State.postTrialPhase or "ffa",
                    reason = "humanoid_died",
                    intentional = false,
                })
            end
            DBG("[POSTTRIAL] MAIN died (cycle " .. tostring(capturedCycle) .. ") → mark loss", "err", "posttrial_death")
        end)
        return true
    end

    -- §22 helper: đánh dấu loss idempotent cho đúng cycle.
    function PostTrial.markMainLoss(reason, expectedCycleId)
        if expectedCycleId ~= nil and _guard.cycleId ~= nil and expectedCycleId ~= _guard.cycleId then
            return false -- loss của cycle khác → bỏ qua
        end
        _guard.died = true
        _guard.reason = reason or "loss"
        State.postTrialDeathDetected = true
        State.didEnterTrialThisTurn = false
        return true
    end

    -- §22 helper: main còn sống trong cycle này? (chưa có tín hiệu chết + Humanoid.Health>0)
    function PostTrial.isMainAlive(expectedCycleId)
        if expectedCycleId ~= nil and _guard.cycleId ~= nil and expectedCycleId ~= _guard.cycleId then
            return false
        end
        if _guard.died then return false end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        return hum ~= nil and hum.Health > 0
    end

    -- §22 helper: dọn cycle (disconnect guard). preserveResult=true → giữ cờ died để FSM đọc.
    function PostTrial.clearCycle(reason, preserveResult)
        if _guard.conn then Safe.disconnect(_guard.conn, "posttrial_guard"); _guard.conn = nil end
        _guard.char = nil
        _guard.cycleId = nil
        if not preserveResult then
            _guard.died = false
            _guard.reason = nil
            State.postTrialDeathDetected = false
        end
    end

    function PostTrial.deathReason() return _guard.reason end

    -- Grace 4 giây thuộc về Character+JobId local, KHÔNG thuộc server trial_cycle_id.
    -- Server cycle có thể tới trễ/nil/đổi trong kill phase nhưng không được làm grace chạy lại.
    local _killGrace = {
        token = nil,
        character = nil,
        jobId = nil,
        startedAt = nil,
        deadline = nil,
        serverCycleId = nil,
    }

    local function clearKillGraceRuntime()
        _killGrace.token = nil
        _killGrace.character = nil
        _killGrace.jobId = nil
        _killGrace.startedAt = nil
        _killGrace.deadline = nil
        _killGrace.serverCycleId = nil
    end

    local function clearKillRuntime(keepGrace)
        State.postTrialStartedAt = nil
        State.postTrialCycleId = nil
        State.postTrialHoldCFrame = nil
        State.postTrialEliminated = {}
        State.postTrialSeen = {}
        State.postTrialCharacters = {}
        if keepGrace ~= true then
            clearKillGraceRuntime()
        end
    end
    PostTrial.clearKillRuntime = clearKillRuntime

    local function stopPostTrialMotion()
        Movement.cancel()
        _G.SHOULDSPAMSKILLS = false
        pcall(function() CombatActions.clearSkillAimTarget() end)
        local root = Movement.getHRP()
        if root then
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end
        return root
    end

    -- Ally auto-reset CHẮC CHẮN + CHỜ Character mới rồi mới gửi helpreset (§14/B3).
    -- [FINAL §14] KHÔNG gửi helpreset sau task.wait(0.5) đơn giản. Phải: char cũ chết → CharacterAdded →
    --   Humanoid mới Health>0 → không còn FFA → cycle vẫn đúng → gửi ally_respawn_confirmed + helpreset (V2).
    function PostTrial.resetAllyOnce(roleName)
        if RuntimeState.allyKillReset then return "ally_reset" end
        RuntimeState.allyKillReset = true
        status(roleName .. " Kill-player → AUTO RESET NGAY (ally) + chờ respawn confirm")
        local cycleId = State.trialCycleId
        local oldChar = LocalPlayer.Character
        -- [FIX #1] token CŨ = characterToken TRƯỚC khi tự sát (không tostring(Character)).
        local oldToken = (_G.KaitunCharacterToken and _G.KaitunCharacterToken()) or State.characterToken
        task.spawn(function()
            -- 1) tự sát chắc chắn (loop 5)
            for _ = 1, 5 do
                pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
                pcall(function() LocalPlayer.Character:BreakJoints() end)
                local c = LocalPlayer.Character
                local h = c and c:FindFirstChild("Humanoid")
                if (not h) or h.Health <= 0 then break end
                task.wait(0.15)
            end
            -- 2) chờ Character MỚI (khác char cũ) + Humanoid Health>0 — tối đa ~12s
            local newChar, newHum = nil, nil
            local t0 = tick()
            while (tick() - t0) < 12 and Runtime.alive do
                local c = LocalPlayer.Character
                if c and c ~= oldChar then
                    local h = c:FindFirstChild("Humanoid")
                    if h and h.Health > 0 then newChar = c; newHum = h; break end
                end
                task.wait(0.1)
            end
            -- [FIX #1] token MỚI = characterToken SAU respawn. CharacterTracker đã tăng generation ở CharacterAdded
            --   → token này KHÁC oldToken. Đọc sau khi Character mới đã sống.
            local newToken = (_G.KaitunCharacterToken and _G.KaitunCharacterToken()) or State.characterToken
            -- 3) V2: gửi leave-evidence (ffa_left token cũ) TRƯỚC, rồi helpreset kèm token cũ/mới (§2 token-chain).
            local sentV2 = false
            if Config.enableEventProtocol and CriticalEvents.enabled() and newChar and cycleId then
                -- ffa_left mang token cũ = leave-evidence server cần trước khi ghi helpreset (§2A/2B).
                CriticalEvents.emit("ffa_left", { cycle_id = cycleId, character_id = oldToken, character_token = oldToken })
                local extra = {
                    cycle_id = cycleId, source = "respawn_confirmed",
                    old_character_id = oldToken, new_character_id = newToken,
                    old_character_token = oldToken, new_character_token = newToken,
                    in_ffa = false, alive = true,
                }
                CriticalEvents.emit("ally_respawn_confirmed", extra)
                CriticalEvents.emit("helpreset", extra)
                sentV2 = true
            end
            -- 4) fallback legacy /helpreset (khi V2 tắt / disabled / chưa có cycle) — giữ tương thích cũ
            if not sentV2 then
                Net.postJSON(B .. "/helpreset", { name = State.myName, cycle_id = cycleId }, "helpreset")
            end
        end)
        return "ally_reset"
    end

    -- [FINAL §B5/B6/§18/§19/§20] V2 WIN FLOW: Main gửi trial_win_candidate, GIỮ SỐNG chờ win_confirmed,
    --   chỉ khi nhận win_confirmed (qua ACK duplicate hoặc /sync) mới intentional reset.
    --   Trả: "win_confirmed_reset" | "win_timeout" | "posttrial_died"
    function PostTrial.currentMainWinV2(myStt, cycleId)
        cycleId = cycleId or State.trialCycleId
        if not cycleId then return "no_cycle" end
        State.activeCycleId = cycleId
        State.winConfirmed = false
        State.postTrialPhase = "win_candidate"
        -- gửi win candidate (server verify → win_pending → grace → win_confirmed)
        local evId = CriticalEvents.emit("trial_win_candidate", { cycle_id = cycleId }, {
            onAck = function(ack)
                if ack and ack.result == "win_confirmed" then State.winConfirmed = true end
            end,
        })
        State.winCandidateEventId = evId
        -- CHỜ win_confirmed: giữ Main sống, death guard KHÔNG disconnect. Tối đa ~12s.
        local t0 = tick()
        while (tick() - t0) < 12 and Runtime.alive do
            -- death ưu tiên: nếu Main chết trong lúc chờ → loss, thoát
            if not PostTrial.isMainAlive(cycleId) then
                PostTrial.markMainLoss("win_wait_death", cycleId)
                return "posttrial_died"
            end
            -- (a) ACK trực tiếp báo confirmed
            if State.winConfirmed then break end
            -- (b) /sync báo final result đúng cycle
            if State.trialResult == "win_confirmed" and tostring(State.trialResultCycle) == tostring(cycleId) then
                State.winConfirmed = true; break
            end
            if State.trialResult == "loss" and tostring(State.trialResultCycle) == tostring(cycleId) then
                PostTrial.markMainLoss("server_loss", cycleId)
                return "posttrial_died"
            end
            -- (c) hỏi nhanh /sync?result_cycle= (không chờ long-poll)
            pcall(function()
                local ok, res = Net.getJSONSync(endpoint("/sync", { name = State.myName, result_cycle = cycleId }))
                if ok and res then
                    if res.result == "win_confirmed" then State.winConfirmed = true
                    elseif res.result == "loss" then State.trialResult = "loss"; State.trialResultCycle = cycleId end
                end
            end)
            task.wait(0.4)
        end
        if not State.winConfirmed then
            status("[MAIN " .. tostring(myStt) .. "] ⏱ chờ win_confirmed timeout → giữ current, retry")
            return "win_timeout"
        end
        -- ĐÃ win_confirmed → intentional reset (§XIV): set ĐỦ flag + cycle + character TRƯỚC self-reset.
        State.winConfirmed = true
        State.intentionalPostTrialReset = true
        State.intentionalResetCycleId = State.activeCycleId
        State.intentionalResetCharacter = LocalPlayer.Character
        status("[MAIN " .. tostring(myStt) .. "] ✅ win_confirmed → intentional reset")
        pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
        return "win_confirmed_reset"
    end

    -- [§XVII/§XVIII] POST-RESPAWN PROCESSOR — sau intentional reset (win) / death loss / cycle abort/cancel,
    --   PHẢI check V4 progress 3 lần liên tiếp cùng classification (Training.confirmClassify), rồi ROUTE
    --   theo result — KHÔNG set thẳng "training". Chờ Character mới sống trước khi check (tránh đọc lúc
    --   respawn dở). Clear intentional flag CHỈ sau khi Character mới sống + processor bắt đầu (§XIV).
    --   Trả classification cuối: "trialable" | "training" | "done" | "can_buy_gear" | "uncertain".
    function PostTrial.processAfterRespawn(myStt, tag)
        tag = tag or ("[MAIN " .. tostring(myStt) .. "]")
        -- 1) chờ Character MỚI sống (tối đa ~12s) trước khi đọc progress.
        -- Khi đây là intentional reset, Character phải khác đúng reference đã lưu trước self-reset.
        local oldIntentionalCharacter = State.intentionalResetCharacter
        local readyCharacter = nil
        local t0 = tick()
        while (tick() - t0) < 12 and Runtime.alive do
            local c = LocalPlayer.Character
            local h = c and c:FindFirstChild("Humanoid")
            local isDifferent = (oldIntentionalCharacter == nil) or (c ~= oldIntentionalCharacter)
            if c and isDifferent and h and h.Health > 0 then
                readyCharacter = c
                break
            end
            task.wait(0.1)
        end
        -- Timeout/chưa có Character mới thật → fail closed: giữ guard, không check i/release/hop.
        if not readyCharacter then
            DBG(tag .. " post-respawn → uncertain (new live Character not confirmed)",
                "warn", "post_respawn_character_wait")
            return "uncertain"
        end
        -- 2) Đã xác nhận Character mới khác Character intentional cũ và đang sống → mới clear guard.
        --   Đây vẫn là NƠI DUY NHẤT clear các cờ intentional-reset.
        State.intentionalPostTrialReset = false
        State.intentionalResetCycleId = nil
        State.intentionalResetCharacter = nil
        -- 3) check V4 progress 3 lần liên tiếp cùng classification
        local r = Training.confirmClassify("main", 3, 0.5)
        -- [FIX #3] CHỈ route theo classification khi confirmed==true. Dao động (training/trialable/training…)
        --   → confirmClassify trả confirmed=false → PHẢI trả "uncertain", KHÔNG dùng confirmedClass để set
        --   thẳng "training"/release current (bug cũ: dùng r.confirmedClass bất kể confirmed).
        if not r or r.confirmed ~= true then
            DBG(tag .. " post-respawn i-check → uncertain (confirmed=" .. tostring(r and r.confirmed) .. ")",
                "warn", "post_respawn_iclass")
            return "uncertain"
        end
        local cls = r.confirmedClass or "uncertain"
        DBG(tag .. " post-respawn i-check → " .. tostring(cls) .. " (confirmed=true)",
            "ok", "post_respawn_iclass")
        return cls
    end

    -- Current main: CHỜ server báo "/helpreset all_done" (tức allies đã POST xong)
    -- rồi mới tự sát. Trước đây reset ngay → main chết trước ally → ally còn trong server → tween đi lung tung.
    -- [FINAL] LEGACY fallback — chỉ dùng khi V2 tắt/disabled. V2 dùng currentMainWinV2().
    function PostTrial.currentMainReset(myStt)
        if not State.didEnterTrialThisTurn then
            status("[MAIN " .. tostring(myStt) .. "] Chưa thắng trial → KHÔNG reset")
            return "posttrial_skip"
        end
        local allies_str = table.concat(Config.allies, ",")
        if allies_str ~= "" then
            status("[MAIN " .. tostring(myStt) .. "] Waiting for help accs to reset first...")
            local timeout = 0
            repeat
                task.wait(1)
                timeout = timeout + 1
                local res = Net.getJSON(B .. "/helpreset?allies=" .. allies_str, 0)
                if res and res.all_done then
                    status("[MAIN " .. tostring(myStt) .. "] All allies reset done → reset main")
                    break
                end
            until timeout >= Config.HELPRESET_TIMEOUT
            if timeout >= Config.HELPRESET_TIMEOUT then
                status("[MAIN " .. tostring(myStt) .. "] ⏱ Help reset timeout " .. tostring(Config.HELPRESET_TIMEOUT) .. "s → reset main anyway")
            end
        end
        pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
        task.wait(3)
        State.setMyMainStatus("training")
        Net.postJSON(B .. "/helpreset/clear", {}, "helpreset_clear")
        return "main_reset_done"
    end

    -- [FINAL §B8] otherMainReset — GIỮ để tương thích nhưng KHÔNG gọi trong flow V2.
    --   Một lượt chỉ có Current Main + Ally1 + Ally2; Main2–5 KHÔNG vào FFA lượt hiện tại.
    function PostTrial.otherMainReset()
        task.spawn(function()
            local delay = (#Config.allies * 2) + 4 + math.random(0, 3)
            task.wait(delay)
            pcall(function() LocalPlayer.Character.Humanoid.Health = 0 end)
            task.wait(1)
            Net.postJSON(B .. "/helpreset", { name = State.myName }, "helpreset")
        end)
        return "other_main_reset"
    end

    -- [FIX-BUG2] Main đang turn (current) kill player trong tầm rồi reset.
    -- 4s đầu đứng im thật để ally kịp reset trước, tránh tween cũ kéo Main đi.
    -- BỎ ĐUỔI khi player chạy xa > 1500 studs (chống tween đi lung tung ra khỏi vùng FFA).
    -- Chỉ reset khi đã thắng trial (didEnterTrialThisTurn).
    -- [FIX-BUG2] + DEATH GUARD: phát hiện MAIN chết trong kill phase → mark loss, KHÔNG reset
    function PostTrial.mainKillThenReset(myStt, currentmain)
        -- FIX KILL PLAYER AFTER TRIAL:
        -- Grace sở hữu bởi Character token + JobId local. trial_cycle_id chỉ là metadata server.
        -- Vì vậy /curmain hoặc /sync trả nil/trễ/đổi cycle KHÔNG được restart 4 giây.
        local char = LocalPlayer.Character
        local characterToken = nil
        pcall(function()
            if _G.KaitunCharacterToken then
                characterToken = _G.KaitunCharacterToken()
            end
        end)
        characterToken = tostring(characterToken or char or "nochar")
        local localKillToken = characterToken .. "|" .. tostring(game.JobId)
        local serverCycleId = State.trialCycleId

        local newLocalKillRuntime =
            _killGrace.token ~= localKillToken
            or _killGrace.character ~= char
            or _killGrace.jobId ~= game.JobId
            or _killGrace.deadline == nil

        if newLocalKillRuntime then
            PostTrial.clearCycle("new_character_job_kill_phase", false)
            clearKillRuntime(false)

            _killGrace.token = localKillToken
            _killGrace.character = char
            _killGrace.jobId = game.JobId
            _killGrace.startedAt = tick()
            _killGrace.deadline = _killGrace.startedAt + 4
            _killGrace.serverCycleId = serverCycleId

            State.postTrialCycleId =
                serverCycleId
                or ("legacy:" .. localKillToken)
            State.postTrialStartedAt = _killGrace.startedAt
            State.postTrialEliminated = {}
            State.postTrialSeen = {}
            State.postTrialCharacters = {}

            local root = stopPostTrialMotion()
            State.postTrialHoldCFrame = root and root.CFrame or nil

            DBG(
                "[POSTTRIAL] grace start token="
                    .. tostring(localKillToken)
                    .. " deadline=+4s cycle="
                    .. tostring(State.postTrialCycleId),
                "ok",
                "posttrial_grace_start"
            )
        else
            -- Server cycle tới trễ/đổi: adopt metadata mới nhưng giữ nguyên deadline, targets và Character.
            if serverCycleId ~= nil
                and serverCycleId ~= _killGrace.serverCycleId
            then
                _killGrace.serverCycleId = serverCycleId
                State.postTrialCycleId = serverCycleId
                DBG(
                    "[POSTTRIAL] adopt late cycle="
                        .. tostring(serverCycleId)
                        .. " without restarting grace",
                    "info",
                    "posttrial_cycle_adopt"
                )
            end
            State.postTrialStartedAt = _killGrace.startedAt
        end

        local cycleId =
            _killGrace.serverCycleId
            or State.postTrialCycleId
            or ("legacy:" .. localKillToken)

        PostTrial.armDeathGuard(cycleId)
        State.activeCycleId = cycleId
        State.postTrialPhase = "kill_phase"

        -- Đứng im THẬT đủ 4 giây theo deadline cố định Character+Job.
        if tick() < _killGrace.deadline then
            local root = stopPostTrialMotion()
            if root then
                State.postTrialHoldCFrame = State.postTrialHoldCFrame or root.CFrame
                root.CFrame = State.postTrialHoldCFrame
            end
            -- Seed participant Character ngay trong grace; ai chết/respawn trước lúc Main bắt đầu đánh vẫn bị loại đúng.
            getplayers(State.postTrialEliminated, State.postTrialSeen, State.postTrialCharacters, { includeAllies = true, includeAllPlayers = true })
            status(
                "[MAIN "
                    .. tostring(myStt)
                    .. "] Kill phase → grace "
                    .. string.format("%.1f", math.max(0, _killGrace.deadline - tick()))
                    .. "s (Character+Job token)"
            )
            if not PostTrial.isMainAlive(cycleId) then
                PostTrial.markMainLoss("grace_death", cycleId)
                PostTrial.clearCycle("grace_death", true)
                clearKillRuntime()
                DBG("[POSTTRIAL] Died in grace period → abort", "err", "posttrial_grace_death")
                State.setMyMainStatus("waiting")
                return "posttrial_died"
            end
            return "posttrial_wait_ally"
        end
        State.postTrialHoldCFrame = nil

        -- Kill động: giết một người → đánh dấu bị loại → QUÉT LẠI toàn vùng FFA → tìm người tiếp theo.
        -- Không chờ Character của người đã chết respawn và không đánh lại UserId đã bị loại.
        status("[MAIN " .. tostring(myStt) .. "] Kill Players After Trial")
        local eliminated = State.postTrialEliminated
        local seen = State.postTrialSeen
        local participantCharacters = State.postTrialCharacters
        local emptyConfirm = 0
        local confirmedEmpty = false
        local lastTargetStatusUserId = nil
        local lastNoTargetStatusAt = 0
        -- PvP skill phải có target aim riêng; hook đã scoped bởi SHOULDSPAMSKILLS.
        pcall(function() CombatActions.installSkillAim() end)

        while Runtime.alive and templeState() == "ffup" do
            if not PostTrial.isMainAlive(cycleId) then
                PostTrial.markMainLoss("kill_loop_death", cycleId)
                DBG("[POSTTRIAL] MAIN died during kill loop → abort", "err", "posttrial_kill_death")
                break
            end
            if State.trialCycleId ~= nil
                and State.trialCycleId ~= cycleId
            then
                -- Snapshot server tới trễ/đổi trong lúc đang đánh:
                -- nhận cycle mới nhưng KHÔNG hủy combat, KHÔNG clear targets, KHÔNG chạy lại grace.
                cycleId = State.trialCycleId
                _killGrace.serverCycleId = cycleId
                State.postTrialCycleId = cycleId
                State.activeCycleId = cycleId
                PostTrial.armDeathGuard(cycleId)
                DBG(
                    "[POSTTRIAL] adopted server cycle during kill="
                        .. tostring(cycleId)
                        .. " | grace deadline unchanged",
                    "info",
                    "posttrial_cycle_adopt_live"
                )
            end

            local targets, unknown = getplayers(eliminated, seen, participantCharacters, { includeAllies = true, includeAllPlayers = true })
            local target = targets[1]

            if target then
                emptyConfirm = 0
                local targetPlayer = target.player
                local targetCharacter = target.character
                local targetHumanoid = targetCharacter and targetCharacter:FindFirstChildOfClass("Humanoid")
                local targetRoot = targetCharacter and targetCharacter:FindFirstChild("HumanoidRootPart")

                if targetHumanoid and targetRoot and targetHumanoid.Health > 0 then
                    local userId = targetPlayer.UserId
                    if lastTargetStatusUserId ~= userId then
                        lastTargetStatusUserId = userId
                        status("[MAIN " .. tostring(myStt) .. "] Đang đánh " .. tostring(targetPlayer.Name))
                    end
                    repeat
                        task.wait()

                        if not PostTrial.isMainAlive(cycleId) then
                            PostTrial.markMainLoss("kill_loop_death", cycleId)
                            break
                        end
                        if templeState() ~= "ffup" or State.postTrialDeathDetected then break end

                        -- Character đổi = người cũ đã chết/respawn; trong Trial họ đã bị loại, không đuổi Character mới.
                        if targetPlayer.Character ~= targetCharacter then
                            eliminated[userId] = true
                            break
                        end

                        targetHumanoid = targetCharacter:FindFirstChildOfClass("Humanoid")
                        targetRoot = targetCharacter:FindFirstChild("HumanoidRootPart")
                        if not targetHumanoid or not targetRoot or targetHumanoid.Health <= 0 then
                            eliminated[userId] = true
                            break
                        end

                        local observed = CombatActions.observeCharacterInFFA(targetPlayer)
                        if observed == false then break end -- chắc chắn đã ra ngoài FFA

                        local tooFar = getdis(targetRoot.CFrame) > 1500
                        if tooFar then break end
                        -- Dùng cách attack Player từ kkv4: bay sát offset ngẫu nhiên + equip/haki
                        -- + spam skill + M1. Bản này thêm throttle tween để không đứng im vì cancel liên tục.
                        CombatActions.attackPlayerKKV4Tick(targetCharacter)
                    until false
                else
                    -- Đã được scan sống nhưng Character biến mất trước lúc đánh = đã chết/đổi Character → bị loại.
                    eliminated[targetPlayer.UserId] = true
                    task.wait(0.1)
                end
            else
                lastTargetStatusUserId = nil
                pcall(function() CombatActions.clearSkillAimTarget() end)
                if unknown > 0 then
                    -- Có participant đã thấy nhưng Character đang replicate: chưa được phép báo thắng.
                    emptyConfirm = 0
                    if (tick() - lastNoTargetStatusAt) >= 1 then
                        lastNoTargetStatusAt = tick()
                        status("[MAIN " .. tostring(myStt) .. "] Chờ target FFA replicate...")
                    end
                else
                    emptyConfirm = emptyConfirm + 1
                    if emptyConfirm >= 3 then
                        confirmedEmpty = true
                        status("[MAIN " .. tostring(myStt) .. "] Không còn target hợp lệ trong FFA")
                        break
                    end
                end
                task.wait(0.2)
            end
        end
        stopPostTrialMotion()

        -- Main chết luôn ưu tiên hơn mọi kết quả thắng.
        if State.postTrialDeathDetected or not PostTrial.isMainAlive(cycleId) then
            PostTrial.markMainLoss("posttrial_death", cycleId)
            PostTrial.clearCycle("loss", true)
            clearKillRuntime()
            DBG("[POSTTRIAL] Loss marked → KHÔNG reset, KHÔNG training", "err", "posttrial_loss")
            State.setMyMainStatus("waiting")
            return "posttrial_died"
        end

        -- FFA/cycle đổi giữa lúc quét: không tự suy ra thắng.
        if templeState() ~= "ffup" or not confirmedEmpty then
            return "posttrial_running"
        end

        -- §21: kiểm lần cuối ngay trước win candidate.
        if not PostTrial.isMainAlive(cycleId) then
            PostTrial.markMainLoss("win_check_death", cycleId)
            PostTrial.clearCycle("win_check_death", true)
            clearKillRuntime()
            DBG("[POSTTRIAL] MAIN dead at win check → mark loss", "err", "posttrial_win_check_death")
            State.setMyMainStatus("waiting")
            return "posttrial_died"
        end

        local isCurrentMain = State.isMain[State.myName] and State.myName == currentmain
        local isOtherMain   = State.isMain[State.myName] and State.myName ~= currentmain
        if isCurrentMain then
            -- V2: server xác nhận đủ điều kiện rồi mới intentional reset.
            if Config.enableEventProtocol and CriticalEvents.enabled() and State.trialCycleId then
                local r = PostTrial.currentMainWinV2(myStt, State.trialCycleId)
                if r == "win_confirmed_reset" then
                    PostTrial.clearCycle("win", false)
                    clearKillRuntime()
                    local cls = PostTrial.processAfterRespawn(myStt)
                    if cls == "training" then
                        State.setMyMainStatus("training")
                    elseif cls == "done" then
                        State.setMyMainStatus("done")
                    else
                        State.setMyMainStatus("waiting")
                    end
                    return "main_reset_done"
                elseif r == "posttrial_died" then
                    PostTrial.clearCycle("loss", true)
                    clearKillRuntime()
                    State.setMyMainStatus("waiting")
                    return "posttrial_died"
                else
                    return "posttrial_running"
                end
            end
            PostTrial.clearCycle("win", false)
            clearKillRuntime()
            DBG("[POSTTRIAL] Win confirmed (legacy) → reset", "ok", "posttrial_win")
            return PostTrial.currentMainReset(myStt)
        elseif isOtherMain then
            PostTrial.clearCycle("win_other", false)
            clearKillRuntime()
            if not (Config.enableEventProtocol and CriticalEvents.enabled()) then
                return PostTrial.otherMainReset()
            end
            return "posttrial_running"
        end
        return "posttrial_running"
    end
end

--[[ ============================================================================
 [24] TEAMMANAGER — join team bền + recovery loop sau hop.
 ensureTeamSelected() có retry mềm, pcall đúng cách. (File A 528-559)
============================================================================ ]]
local startGameReadyGate
local TeamManager = {}
TeamManager.started = false
TeamManager._started = false
TeamManager._selecting = false

function TeamManager.ensureTeamSelected()
    if not Runtime.alive then return end
    if LocalPlayer.Team then return true end
    local team = Config.team
    local timeout = 60
    local t0 = tick()
    local attempt = 0
    while Runtime.alive and not LocalPlayer.Team and (tick() - t0) < timeout do
        attempt = attempt + 1
        if attempt == 1 or (attempt % 10) == 0 then
            Logger.info("[TEAM] choosing team (attempt " .. tostring(attempt) .. ")", "team_choose")
        end
        SafeRemote.invoke(3, "SetTeam", team)
        task.wait(0.5)
        if LocalPlayer.Team then
            Logger.ok("[TEAM] selected (" .. tostring(team) .. ") attempt=" .. tostring(attempt), "team_ok")
            return true
        end
        -- pcall đúng: nhận cả ok + result
        local ok, chooseGui = pcall(function()
            return LocalPlayer.PlayerGui:FindFirstChild("ChooseTeam", true)
        end)
        if ok and chooseGui and chooseGui.Visible then
            local ok2, uiCtrl = pcall(function()
                return LocalPlayer.PlayerGui:FindFirstChild("UIController", true)
            end)
            if ok2 and uiCtrl and getgc then
                for _, fn in pairs(getgc(true)) do
                    if type(fn) == "function" and getfenv(fn).script == uiCtrl then
                        local consts = getconstants(fn)
                        if consts and #consts == 1 and (consts[1] == "Pirates" or consts[1] == "Marines") then
                            if consts[1] == team then pcall(fn, team) end
                        end
                    end
                end
            end
            -- FIX hop→team: fallback firesignal nút ChooseTeam (File A 179-184) — dùng khi SetTeam/getgc
            -- không chọn được team trên server mới vừa hop. Movement.joinTeam trước đó là dead code.
            pcall(function() Movement.joinTeam(team) end)
        end
        task.wait(1)
    end
    if not LocalPlayer.Team then
        Logger.warn("[TEAM] timeout sau " .. tostring(timeout) .. "s, tiếp tục retry nền", "team_timeout")
    end
    return LocalPlayer.Team ~= nil
end

local function startTeamRecoveryLoop()
    task.spawn(function()
        -- FIX hop→team: KHÔNG wait 10s nữa. Ngay sau boot/hop, ChooseTeam có thể xuất hiện trong
        -- vài giây đầu rồi tự đóng nếu không click kịp. Poll 0.5s trong 60s đầu, sau đó 2s.
        local startT = tick()
        while Runtime.alive do
            local elapsed = tick() - startT
            task.wait(elapsed < 60 and 0.5 or 2)
            if not TeamManager._started then break end
            if LocalPlayer.Team then
                -- đã có team, thỉnh thoảng check lại phòng mất team (server reset, hop mới)
                task.wait(3)
            else
                -- chưa có team → thử ngay
                Logger.info("[TEAM] missing team, retrying", "team_missing")
                status("Recovering team...")
                TeamManager.ensureTeamSelected()
            end
        end
    end)
    -- FIX hop→team: lắng nghe ChooseTeam xuất hiện trong PlayerGui (signal-based, không phụ thuộc poll interval)
    task.spawn(function()
        while Runtime.alive do
            local pgui = LocalPlayer:FindFirstChild("PlayerGui")
            if pgui then
                pgui.ChildAdded:Connect(function(child)
                    if not Runtime.alive then return end
                    if not child:FindFirstChild("ChooseTeam") then return end
                    -- ChooseTeam screen vừa xuất hiện → chọn team ngay
                    task.wait(0.1) -- 1 frame để UI init
                    if not LocalPlayer.Team then
                        Logger.info("[TEAM] ChooseTeam detected (signal) → ensureTeamSelected", "team_signal")
                        status("ChooseTeam detected → selecting team...")
                        TeamManager.ensureTeamSelected()
                    end
                end)
                -- cũng check DescendantAdded phòng ChooseTeam nằm trong ScreenGui con
                pgui.DescendantAdded:Connect(function(desc)
                    if not Runtime.alive then return end
                    if desc.Name ~= "ChooseTeam" then return end
                    task.wait(0.1)
                    if not LocalPlayer.Team then
                        Logger.info("[TEAM] ChooseTeam descendant detected (signal) → ensureTeamSelected", "team_signal_desc")
                        TeamManager.ensureTeamSelected()
                    end
                end)
                break
            end
            task.wait(0.5)
        end
    end)
end

function TeamManager.start()
    if TeamManager.started then return end
    TeamManager.started = true
    Logger.info("[BOOT] waiting game ready", "boot_team")
    startGameReadyGate()
    -- FIX hop→team: bật _started TRƯỚC khi gọi ensureTeamSelected (blocking tới 60s).
    -- Nếu không, recovery loop (break khi not _started) sẽ chết vĩnh viễn lúc server mới
    -- load chậm sau hop → không còn ai chọn lại team.
    TeamManager._started = true
    startTeamRecoveryLoop()
    task.spawn(function()
        Logger.info("[TEAM] choosing team", "team_start")
        TeamManager.ensureTeamSelected()
    end)
end

--[[ ============================================================================
[25] SEAMANAGER — đảm bảo Sea3 (check PlaceId), travel nếu chưa. (File A 14-33)
============================================================================ ]]
local SeaManager = {}
function SeaManager.start()
    if Config.SEA3_PLACEIDS[game.PlaceId] then return end
    task.spawn(function()
        while Runtime.alive and not Config.SEA3_PLACEIDS[game.PlaceId] do
            pcall(function()
                local R = ReplicatedStorage.Remotes.CommF_
                if Config.SEA2_PLACEIDS[game.PlaceId] then
                    R:InvokeServer("TravelZou")        -- Sea2 → Sea3
                else
                    R:InvokeServer("TravelDressrosa")  -- Sea1/khác → Sea2
                end
            end)
            task.wait(5)
        end
    end)
end

--[[ ============================================================================
 [26] TEMPLE DOOR GATE — check 1 lần rồi ghi file riêng account. (File A 1519-1539)
============================================================================ ]]
local TempleDoorGate = {}
do
    local FILE = Config.myName .. "_kaitunv4.json"
    function TempleDoorGate.ready()
        if RuntimeState.templeDoorOK then return true end
        local fdata = FileStore.readJson(FILE, {})
        if fdata.templedoor == true then RuntimeState.templeDoorOK = true; return true end
        local ok, res = SafeRemote.invoke(3, "CheckTempleDoor")
        if ok and res then
            RuntimeState.templeDoorOK = true
            FileStore.writeJson(FILE, { templedoor = true })
            return true
        end
        return res
    end
end


--[[ ============================================================================
 [26b] TEMPLE DONT-PULL CHECK — luồng ĐỘC LẬP, đúng 5 lần / cách nhau 2 giây.
      - Nếu BẤT KỲ lần 1-4 nào CheckTempleDoor == true: dừng quét ngay, KHÔNG tạo file.
      - 4 lần đầu KHÔNG cần đều false; false/nil vẫn tiếp tục tới lần 5.
      - CHỈ kết quả LẦN THỨ 5 quyết định:
          + lần 5 == false -> tạo <PlayerName>.txt = Completed-dontpull
          + lần 5 == true hoặc nil/lỗi -> không tạo file.
============================================================================ ]]
local TempleDontPullCheck = {}
do
    local started = false
    local finished = false
    local CHECK_TIMES = 5
    local CHECK_GAP = 2

    local function writeDontPullMarker()
        local outName = tostring(LocalPlayer.Name) .. ".txt"
        if type(writefile) ~= "function" then
            DBG("[TEMPLE-DONTPULL] writefile không khả dụng → không thể tạo " .. outName,
                "err", "temple_dontpull_no_writefile")
            status("⚠ Không thể tạo " .. outName .. " (writefile không khả dụng)")
            return false
        end

        local ok, err = pcall(function()
            writefile(outName, "Completed-dontpull")
        end)
        if not ok then
            DBG("[TEMPLE-DONTPULL] ghi " .. outName .. " thất bại: " .. tostring(err),
                "err", "temple_dontpull_write_fail")
            status("⚠ Ghi " .. outName .. " thất bại: " .. tostring(err))
            return false
        end

        -- Verify lại nếu executor có isfile/readfile để tránh trường hợp writefile im lặng thất bại.
        local verified = true
        if type(isfile) == "function" then
            local okFile, exists = pcall(isfile, outName)
            if okFile and exists == false then verified = false end
        end
        if verified and type(readfile) == "function" then
            local okRead, content = pcall(readfile, outName)
            if okRead and tostring(content or "") ~= "Completed-dontpull" then verified = false end
        end

        if verified then
            DBG("[TEMPLE-DONTPULL] lần 5 CheckTempleDoor=false → CREATED " .. outName
                .. " = Completed-dontpull", "ok", "temple_dontpull_created")
            status("✅ Lần 5 CheckTempleDoor=false → " .. outName .. " = Completed-dontpull")
            return true
        end

        DBG("[TEMPLE-DONTPULL] writefile chạy nhưng verify " .. outName .. " thất bại",
            "err", "temple_dontpull_verify_fail")
        status("⚠ Đã gọi writefile nhưng verify " .. outName .. " thất bại")
        return false
    end

    function TempleDontPullCheck.start()
        if started then return end
        started = true

        task.spawn(function()
            for attempt = 1, CHECK_TIMES do
                if not Runtime.alive then return end

                local result = TempleDoorGate.ready()
                DBG("[TEMPLE-DONTPULL] CheckTempleDoor lần " .. tostring(attempt)
                    .. "/" .. tostring(CHECK_TIMES) .. " = " .. tostring(result),
                    "info", "temple_dontpull_check_" .. tostring(attempt))
                status("Chờ mở cửa đền (CheckTempleDoor=" .. tostring(result) .. ") ["
                    .. tostring(attempt) .. "/" .. tostring(CHECK_TIMES) .. "]")

                -- Nếu true ở BẤT KỲ lần nào (kể cả lần 5) → dừng ngay, không tạo marker.
                if result == true then
                    finished = true
                    DBG("[TEMPLE-DONTPULL] CheckTempleDoor=true ở lần " .. tostring(attempt)
                        .. "/" .. tostring(CHECK_TIMES) .. " → STOP, không tạo file",
                        "ok", "temple_dontpull_true_stop")
                    return
                end

                if attempt == CHECK_TIMES then
                    finished = true
                    -- CHỈ lần thứ 5 quyết định. Không quan tâm 4 lần đầu là false hay nil.
                    if result == false then
                        writeDontPullMarker()
                    else
                        DBG("[TEMPLE-DONTPULL] lần 5 không phải false (" .. tostring(result)
                            .. ") → không ghi Completed-dontpull",
                            "warn", "temple_dontpull_last_not_false")
                    end
                    return
                end

                task.wait(CHECK_GAP)
            end
        end)
    end

    function TempleDontPullCheck.isFinished()
        return finished
    end
end

--[[ ============================================================================
[27] ALLY TRAINING GATE — ally chỉ train khi xác nhận ổn định.
Mặc định giữ ready_trialing. Dùng Training.checkUpgradeForRole("ally").
Map UpgradeRace ally: i==8/0 → ready_trial, i==5 → done.
(File A: fix ally training quá sớm)
============================================================================ ]]
local AllyTrainingGate = {}
do
    AllyTrainingGate.started = false
    AllyTrainingGate.state = "ready_trialing"
    AllyTrainingGate.lastReadyAt = tick()
    AllyTrainingGate.notReadySince = 0
    AllyTrainingGate.confirmCount = 0
    AllyTrainingGate.lastI = nil

    function AllyTrainingGate.start()
        if AllyTrainingGate.started then return end
        AllyTrainingGate.started = true
        AllyTrainingGate.lastReadyAt = tick()
    end

    function AllyTrainingGate.tick(roleName)
        if not AllyTrainingGate.started then AllyTrainingGate.start() end
        if State.isMain[State.myName] then
            return "ready_trialing", "is_main", nil
        end
        local result = Training.checkUpgradeForRole("ally")
        local i = result.i
        local eval = result.reason
        local now = tick()

        if eval == "ready_trial" then
            AllyTrainingGate.confirmCount = 0
            AllyTrainingGate.notReadySince = 0
            AllyTrainingGate.lastReadyAt = now
            AllyTrainingGate.lastI = i
            Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. eval .. " confirm=0", "ally_gate_ready")
            AllyTrainingGate.state = "ready_trialing"
            return "ready_trialing", eval, i
        end

        if eval == "done" or eval == "ally_done" then
            AllyTrainingGate.confirmCount = 0
            AllyTrainingGate.notReadySince = 0
            AllyTrainingGate.lastReadyAt = now
            AllyTrainingGate.lastI = nil
            Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. eval .. " confirm=0", "ally_gate_done")
            AllyTrainingGate.state = "ready_trialing"
            return "ready_trialing", eval, i
        end

        if eval == "need_train" then
            if i ~= AllyTrainingGate.lastI then
                AllyTrainingGate.lastI = i
                AllyTrainingGate.confirmCount = 1
                AllyTrainingGate.notReadySince = now
                Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=need_train_first confirm=1", "ally_gate_first")
                AllyTrainingGate.state = "ready_trialing"
                return "ready_trialing", "need_train_first", i
            end
            local stable = (now - AllyTrainingGate.notReadySince) >= 3
            AllyTrainingGate.confirmCount = AllyTrainingGate.confirmCount + 1
            if stable and AllyTrainingGate.confirmCount >= 3 and (now - AllyTrainingGate.lastReadyAt) >= 5 then
                Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=training reason=confirmed confirm=" .. tostring(AllyTrainingGate.confirmCount), "ally_gate_train")
                AllyTrainingGate.state = "training"
                return "training", "confirmed", i
            else
                local reasonStr = "need_train_stable_" .. tostring(math.floor(now - AllyTrainingGate.notReadySince)) .. "s"
                Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. reasonStr .. " confirm=" .. tostring(AllyTrainingGate.confirmCount), "ally_gate_checking")
                AllyTrainingGate.state = "ready_trialing"
                return "ready_trialing", reasonStr, i
            end
        end

        if eval == "can_buy_gear" then
            AllyTrainingGate.confirmCount = 0
            AllyTrainingGate.notReadySince = 0
            AllyTrainingGate.lastI = nil
            Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=can_buy confirm=0", "ally_gate_buy")
            AllyTrainingGate.state = "ready_trialing"
            return "ready_trialing", eval, i
        end

        -- unknown / check_failed
        AllyTrainingGate.confirmCount = 0
        AllyTrainingGate.notReadySince = 0
        AllyTrainingGate.lastI = nil
        Logger.info("[ALLY-GATE] i=" .. tostring(i) .. " state=ready_trialing reason=" .. eval .. " confirm=0", "ally_gate_unknown")
        AllyTrainingGate.state = "ready_trialing"
        return "ready_trialing", eval, i
    end

    function AllyTrainingGate.reset()
        AllyTrainingGate.confirmCount = 0
        AllyTrainingGate.notReadySince = 0
        AllyTrainingGate.state = "ready_trialing"
    end
end

--[[ ============================================================================
[27b] GAME READY GATE — chờ team/char/data (timeout 45s), KHÔNG block.
(File A 1549-1568)
============================================================================ ]]
startGameReadyGate = function()
    Logger.info("[BOOT] waiting game ready", "boot_gate")
    task.spawn(function()
        local t0 = tick()
        repeat
            task.wait(0.2)
            local c   = LocalPlayer.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local ready = LocalPlayer.Team
                and c and c:FindFirstChild("HumanoidRootPart")
                and hum and hum.Health > 0
                and LocalPlayer:FindFirstChild("Data") and LocalPlayer.Data:FindFirstChild("Race")
            if ready then
                Logger.info("[BOOT] playergui ready", "boot_ok_pgui")
                break
            end
        until (tick() - t0) > 45
        RuntimeState.gameReady = true
        Logger.ok(("[BOOT] game ready (%.1fs elapsed)"):format(tick() - t0), "boot_ok")
    end)
end

--[[ ============================================================================
 [27b2] MAINRACE REROLL — Main / Ally1 / Ally2 tự check race của CHÍNH MÌNH.
   Mapping cố định:
     Angel  → Ally1 Human,  Ally2 Rabbit
     Rabbit → Ally1 Human,  Ally2 Angel
     Ghoul  → Ally1 Angel,  Ally2 Rabbit
     Human  → Ally1 Angel,  Ally2 Rabbit
     Cyborg → Ally1 Angel,  Ally2 Rabbit
     Shark  → Ally1 Angel,  Ally2 Rabbit

   QUY TẮC:
     1. Mọi account trong MainAccount = role "main", target = getgenv().MainRace.
     2. Allies[1] = Ally1, Allies[2] = Ally2, target lấy từ mapping trên.
     3. Mỗi account đọc LocalPlayer.Data.Race.Value của chính nó.
     4. Nếu race hiện tại trùng target sau normalize alias → KHÔNG reroll.
     5. Chỉ khi không trùng mới gọi reroll.
     6. Alias được coi là cùng race:
          Angel = Skypiea
          Rabbit = Mink
          Shark = Fishman
     7. Main chạy trong phase checking 8 giây đầu.
     8. Nếu hết 8 giây mà race vẫn chưa đúng thì tiếp tục blocking/reroll.
     9. Chỉ khi race của chính account trùng target mới dừng.
============================================================================ ]]
local MainRaceReroll = {}
do
    -- Chuẩn hóa về đúng tên race nội bộ trong Data.Race.Value.
    -- Điều này ngăn lỗi Data.Race.Value="Skypiea" nhưng target="Angel"
    -- bị hiểu sai là khác race và reroll oan.
    local RACE_ALIAS_TO_CANONICAL = {
        human   = "Human",

        mink    = "Mink",
        rabbit  = "Mink",

        fishman = "Fishman",
        shark   = "Fishman",

        skypiea = "Skypiea",
        angel   = "Skypiea",

        ghoul   = "Ghoul",
        cyborg  = "Cyborg",
    }

    local CANONICAL_TO_DISPLAY = {
        Human   = "Human",
        Mink    = "Rabbit",
        Fishman = "Shark",
        Skypiea = "Angel",
        Ghoul   = "Ghoul",
        Cyborg  = "Cyborg",
    }

    local function normalizeRace(value)
        local key = tostring(value or "")
            :lower()
            :gsub("^%s+", "")
            :gsub("%s+$", "")
            :gsub("[^%a]", "")

        return RACE_ALIAS_TO_CANONICAL[key]
    end

    local function displayRace(value)
        local canonical = normalizeRace(value) or tostring(value or "?")
        return CANONICAL_TO_DISPLAY[canonical] or canonical
    end

    -- Race thường (Human/Rabbit/Shark/Angel) reroll bằng 3000 Fragments.
    -- MainRaceReroll chỉ mượn FragmentTyrant làm worker kiếm F; tuyệt đối không nhả blocking
    -- và không chạy gameplay khác trong lúc thiếu F.
    local REROLL_FRAGMENT_COST = 3000

    local function getCurrentFragments()
        local value = 0
        pcall(function()
            local data = LocalPlayer:FindFirstChild("Data")
            local fragments = data and data:FindFirstChild("Fragments")
            value = tonumber(fragments and fragments.Value) or 0
        end)
        return value
    end

    local function needsFragmentReroll(targetCanonical)
        return targetCanonical ~= "Ghoul" and targetCanonical ~= "Cyborg"
    end

    -- Mapping dùng canonical names để so sánh chính xác với Data.Race.Value.
    local ALLY_MAP = {
        Skypiea = { "Human",   "Mink"     }, -- MainRace Angel
        Mink    = { "Human",   "Skypiea"  }, -- MainRace Rabbit
        Ghoul   = { "Skypiea", "Mink"     },
        Human   = { "Skypiea", "Mink"     },
        Cyborg  = { "Skypiea", "Mink"     },
        Fishman = { "Skypiea", "Mink"     }, -- MainRace Shark
    }

    local function listContains(list, wanted)
        for _, name in ipairs(list or {}) do
            if tostring(name) == tostring(wanted) then
                return true
            end
        end
        return false
    end

    -- Main = mọi account có tên trong Config.mains.
    -- Ally1/Ally2 vẫn xác định đúng theo thứ tự Config.allies.
    local function resolveMyRole()
        local me = Config.myName

        if listContains(Config.mains, me) then
            return "main"
        end

        if Config.allies[1] == me then
            return "ally1"
        end

        if Config.allies[2] == me then
            return "ally2"
        end

        return nil
    end

    -- Đọc race hiện tại của CHÍNH LocalPlayer.
    local function getCurrentRace()
        local ok, value = pcall(function()
            local data = LocalPlayer:FindFirstChild("Data")
            local race = data and data:FindFirstChild("Race")
            return race and race.Value
        end)

        if not ok or value == nil then
            return nil, nil
        end

        return normalizeRace(value), tostring(value)
    end

    local function isCurrentRaceTarget(targetRace)
        local currentCanonical, currentRaw = getCurrentRace()
        local targetCanonical = normalizeRace(targetRace)

        if not currentCanonical or not targetCanonical then
            return false, currentCanonical, currentRaw, targetCanonical
        end

        return currentCanonical == targetCanonical,
            currentCanonical,
            currentRaw,
            targetCanonical
    end

    -- Reroll race về target.
    -- Trước khi gọi remote sẽ check LẠI một lần để tránh race vừa đổi xong
    -- nhưng coroutine cũ vẫn gọi reroll.
    local function doReroll(targetRace)
        local targetCanonical = normalizeRace(targetRace)
        if not targetCanonical then
            return false, "invalid_target"
        end

        local alreadyMatch = isCurrentRaceTarget(targetCanonical)
        if alreadyMatch then
            Logger.ok(
                "[MAINRACE] Race đã trùng "
                    .. displayRace(targetCanonical)
                    .. " → SKIP reroll",
                "mainrace_skip_remote"
            )
            return true, "already_match"
        end

        -- Guard cuối ngay trước remote: race thường bắt buộc phải có đủ 3000F.
        -- Nếu Fragment vừa bị tiêu/đổi giữa hai nhịp thì KHÔNG spam BlackbeardReward;
        -- vòng MainRace phía ngoài sẽ chuyển sang Auto Tyrant để bù lại.
        if needsFragmentReroll(targetCanonical) then
            local frags = getCurrentFragments()
            if frags < REROLL_FRAGMENT_COST then
                return false, "need_reroll_fragments"
            end
        end

        Logger.info(
            "[MAINRACE] gọi reroll → "
                .. displayRace(targetCanonical)
                .. " (canonical="
                .. tostring(targetCanonical)
                .. ")",
            "mainrace_reroll"
        )

        local R =
            ReplicatedStorage:FindFirstChild("Remotes")
            and ReplicatedStorage.Remotes:FindFirstChild("CommF_")

        if not R then
            return false, "CommF_missing"
        end

        if targetCanonical == "Ghoul" then
            -- Ghoul là race đặc biệt: KHÔNG đi qua UpgradeRace và KHÔNG dùng Fragment reroll.
            -- Chuỗi đúng theo logic Ghoul đã dùng ổn định trong các bản trước:
            --   Ectoplasm -> BuyCheck -> 4
            --   Ectoplasm -> Change   -> 4
            -- BuyCheck chỉ xác nhận quyền sở hữu; Change mới là lệnh đổi race.
            local ghoulCheckOk, ghoulCheckResult =
                SafeRemote.invoke(3, "Ectoplasm", "BuyCheck", 4)

            task.wait(0.5)

            -- Guard lại Data.Race trước Change để coroutine cũ không đổi thừa
            -- nếu race vừa được một flow khác đổi sang Ghoul.
            if isCurrentRaceTarget(targetCanonical) then
                return true, "matched_before_ghoul_change"
            end

            local ghoulChangeOk, ghoulChangeResult =
                SafeRemote.invoke(3, "Ectoplasm", "Change", 4)

            task.wait(0.8)

            if isCurrentRaceTarget(targetCanonical) then
                return true, "matched_after_ghoul_change"
            end

            -- Không gọi Ectoplasm Buy ở MainRace: MainRace chỉ có nhiệm vụ đổi
            -- về Ghoul đã sở hữu. Nếu chưa đổi được, vòng MainRace hiện tại sẽ
            -- retry theo cooldown/attempt sẵn có, không chạm các flow khác.
            if not ghoulCheckOk or not ghoulChangeOk then
                Logger.warn(
                    "[MAINRACE][Ghoul] Ectoplasm remote lỗi | BuyCheck="
                        .. tostring(ghoulCheckResult)
                        .. " | Change="
                        .. tostring(ghoulChangeResult),
                    "mainrace_ghoul_remote_error"
                )
            end

        elseif targetCanonical == "Cyborg" then
            -- Giữ nguyên chuỗi remote Cyborg của bản gốc.
            pcall(function()
                SafeRemote.invoke(3, "CyborgTrainer")
            end)
            task.wait(0.3)

            if isCurrentRaceTarget(targetCanonical) then
                return true, "matched_after_check"
            end

            pcall(function()
                SafeRemote.invoke(3, "CyborgTrainer", "Buy")
            end)

        else
            -- Race thường là reroll ngẫu nhiên bằng fragments.
            -- Check trước từng remote để không reroll thêm nếu race đã đúng.
            if isCurrentRaceTarget(targetCanonical) then
                return true, "matched_before_reroll_1"
            end

            pcall(function()
                R:InvokeServer(
                    "BlackbeardReward",
                    "Reroll",
                    "1"
                )
            end)
            task.wait(0.3)

            if isCurrentRaceTarget(targetCanonical) then
                return true, "matched_after_reroll_1"
            end

            pcall(function()
                R:InvokeServer(
                    "BlackbeardReward",
                    "Reroll",
                    "2"
                )
            end)
        end

        return true, "remote_sent"
    end

    local function waitForRaceResult(
        targetRace,
        oldCanonical,
        timeoutSeconds
    )
        local deadline = tick() + (tonumber(timeoutSeconds) or 4)

        repeat
            local matched, currentCanonical =
                isCurrentRaceTarget(targetRace)

            if matched then
                if Training.invalidateUpgradeRaw then pcall(Training.invalidateUpgradeRaw, "reroll_matched") end
                return true, currentCanonical
            end

            -- Race thường reroll ngẫu nhiên: nếu đã đổi sang race khác,
            -- trả kết quả để vòng check sau quyết định reroll tiếp.
            if currentCanonical
                and oldCanonical
                and currentCanonical ~= oldCanonical
            then
                if Training.invalidateUpgradeRaw then pcall(Training.invalidateUpgradeRaw, "reroll_race_changed") end
                RuntimeState.mainDoneValidatedRace = nil
                return false, currentCanonical
            end

            task.wait(0.2)
        until not Runtime.alive or tick() >= deadline

        local matched, currentCanonical =
            isCurrentRaceTarget(targetRace)

        return matched, currentCanonical
    end

    -- MỖI ACCOUNT tự check race hiện tại của chính mình.
    -- Trùng target = return true ngay và tuyệt đối không gọi doReroll().
    local function checkAndReroll(targetRace, role)
        local targetCanonical = normalizeRace(targetRace)
        if not targetCanonical then
            Logger.warn(
                "[MAINRACE] target không hợp lệ: "
                    .. tostring(targetRace),
                "mainrace_invalid_target"
            )
            return false
        end

        local matched, currentCanonical, currentRaw =
            isCurrentRaceTarget(targetCanonical)

        if not currentCanonical then
            Logger.warn(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] chưa đọc được Data.Race.Value",
                "mainrace_data_not_ready"
            )
            return false
        end

        -- ĐÚNG RACE: không gọi bất kỳ remote reroll nào.
        if matched then
            Logger.ok(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] current="
                    .. tostring(currentRaw)
                    .. " | target="
                    .. displayRace(targetCanonical)
                    .. " → TRÙNG, KHÔNG REROLL",
                "mainrace_already_correct_" .. tostring(role)
            )

            status(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] Race đúng: "
                    .. displayRace(targetCanonical)
                    .. " → không reroll"
            )

            return true
        end

        Logger.warn(
            "[MAINRACE]["
                .. tostring(role)
                .. "] current="
                .. tostring(currentRaw)
                .. " ("
                .. tostring(currentCanonical)
                .. ") | target="
                .. displayRace(targetCanonical)
                .. " ("
                .. tostring(targetCanonical)
                .. ") → KHÔNG TRÙNG, reroll",
            "mainrace_wrong_" .. tostring(role)
        )

        status(
            "[MAINRACE]["
                .. tostring(role)
                .. "] Đang reroll "
                .. displayRace(currentCanonical)
                .. " → "
                .. displayRace(targetCanonical)
                .. "..."
        )

        -- Race có thể đổi giữa lúc check và lúc gọi remote.
        -- doReroll() có check lại lần cuối trước remote.
        local sent = doReroll(targetCanonical)
        if not sent then
            return false
        end

        local ok, afterCanonical =
            waitForRaceResult(
                targetCanonical,
                currentCanonical,
                5
            )

        if ok then
            Logger.ok(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] reroll thành công: "
                    .. displayRace(afterCanonical),
                "mainrace_ok_" .. tostring(role)
            )
            status(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] Race đúng: "
                    .. displayRace(afterCanonical)
            )
        else
            Logger.warn(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] sau reroll race="
                    .. displayRace(afterCanonical)
                    .. " | vẫn cần="
                    .. displayRace(targetCanonical),
                "mainrace_fail_" .. tostring(role)
            )
        end

        return ok
    end

    -- Xác định target riêng cho Main / Ally1 / Ally2.
    local function resolveTargetRace()
        local rawTarget = getgenv().MainRace
        local rawText = tostring(rawTarget or ""):lower()

        if rawTarget == nil
            or rawText == ""
            or rawText == "off"
            or rawText == "nil"
        then
            return nil, nil
        end

        local mainRace = normalizeRace(rawTarget)
        local entry = mainRace and ALLY_MAP[mainRace] or nil

        if not mainRace or not entry then
            Logger.warn(
                "[MAINRACE] MainRace="
                    .. tostring(rawTarget)
                    .. " không hợp lệ "
                    .. "(Angel/Shark/Human/Ghoul/Cyborg/Rabbit)",
                "mainrace_invalid"
            )
            return nil, nil
        end

        local role = resolveMyRole()

        if role == "main" then
            return mainRace, role
        end

        if role == "ally1" then
            return entry[1], role
        end

        if role == "ally2" then
            return entry[2], role
        end

        Logger.warn(
            "[MAINRACE] "
                .. tostring(Config.myName)
                .. " không thuộc MainAccount/Allies[1]/Allies[2] → bỏ qua",
            "mainrace_role_unknown"
        )

        return nil, nil
    end

    MainRaceReroll._blocking = false
    MainRaceReroll._resolved = false
    MainRaceReroll._target = nil
    MainRaceReroll._role = nil
    MainRaceReroll._currentRace = nil
    MainRaceReroll._startedAt = 0
    MainRaceReroll._attempt = 0
    MainRaceReroll._matchedAt = 0 -- mốc race target vừa ổn định; dùng chặn DONE stale ngay sau reroll
    MainRaceReroll._fragmentFunding = false
    MainRaceReroll._fragmentRequired = 0

    local function stopMainRaceFragmentFarm(reason)
        if MainRaceReroll._fragmentFunding then
            if FragmentTyrant.isActive() then
                FragmentTyrant.stop(reason or "MainRace fragment farm stop")
            end
            MainRaceReroll._fragmentFunding = false
            MainRaceReroll._fragmentRequired = 0
        end
    end

    -- Trả true khi đã đủ tiền cho MỘT lần reroll race thường.
    -- Trả false khi đang thiếu F: giữ MainRace blocking và giao movement/combat cho FragmentTyrant.
    local function ensureMainRaceRerollFragments(targetCanonical, role)
        if not needsFragmentReroll(targetCanonical) then
            stopMainRaceFragmentFarm("special race does not use 3000F reroll")
            return true
        end

        local frags = getCurrentFragments()
        if frags >= REROLL_FRAGMENT_COST then
            stopMainRaceFragmentFarm("enough 3000F for race reroll")
            return true
        end

        MainRaceReroll._fragmentFunding = true
        MainRaceReroll._fragmentRequired = REROLL_FRAGMENT_COST
        if role == "main" then
            State.reportStatus("checking")
        end

        status(
            "[MAINRACE]["
                .. tostring(role)
                .. "] Thiếu Fragment reroll | F="
                .. tostring(frags)
                .. "/"
                .. tostring(REROLL_FRAGMENT_COST)
                .. " → AUTO TYRANT"
        )

        FragmentTyrant.start(REROLL_FRAGMENT_COST)
        return false
    end

    -- Khoảng nghỉ giữa hai lần reroll.
    -- checkAndReroll đã chờ kết quả đổi race; khoảng này chỉ chống gọi remote dồn.
    local MAINRACE_RETRY_INTERVAL = 0.75

    function MainRaceReroll.isBlocking()
        return MainRaceReroll._blocking == true
    end

    function MainRaceReroll.isResolved()
        return MainRaceReroll._resolved == true
    end

    function MainRaceReroll.getRole()
        return MainRaceReroll._role
    end

    function MainRaceReroll.getTarget()
        return MainRaceReroll._target
    end

    function MainRaceReroll.getMatchedAt()
        return tonumber(MainRaceReroll._matchedAt) or 0
    end

    function MainRaceReroll.isTargetMatchedNow()
        if not MainRaceReroll._target then return true end
        local matched = isCurrentRaceTarget(MainRaceReroll._target)
        return matched == true
    end

    function MainRaceReroll.getCurrentRace()
        local currentCanonical, currentRaw = getCurrentRace()
        MainRaceReroll._currentRace =
            currentCanonical or currentRaw
        return currentCanonical, currentRaw
    end

    function MainRaceReroll.getStatusText()
        local currentCanonical, currentRaw =
            MainRaceReroll.getCurrentRace()

        local text = "[MAINRACE]["
            .. tostring(MainRaceReroll._role or "?")
            .. "] Checking race | current="
            .. displayRace(currentRaw or currentCanonical)
            .. " | target="
            .. displayRace(MainRaceReroll._target)
            .. " | attempt="
            .. tostring(MainRaceReroll._attempt or 0)

        if MainRaceReroll._fragmentFunding then
            text = text
                .. " | FARM F="
                .. tostring(getCurrentFragments())
                .. "/"
                .. tostring(MainRaceReroll._fragmentRequired or REROLL_FRAGMENT_COST)
        end

        return text
    end

    -- Worker chạy cho tới khi race của CHÍNH account trùng target.
    --
    -- Main:
    --   mọi account nằm trong Config.mains đều target getgenv().MainRace.
    --
    -- Ally:
    --   Allies[1] target mapping Ally1;
    --   Allies[2] target mapping Ally2.
    --
    -- Không còn fail-safe 15 giây:
    -- race chưa đúng thì tiếp tục reroll; chỉ khi đúng mới nhả blocking.
    function MainRaceReroll.start()
        local target, role = resolveTargetRace()
        if not target or not role then
            MainRaceReroll._blocking = false
            MainRaceReroll._resolved = true
            return
        end

        MainRaceReroll._target = target
        MainRaceReroll._role = role

        -- FIX DONE-RACE: chặn gameplay NGAY TỪ LÚC start(), không đợi coroutine gameReady.
        -- MainLoop được start gần như song song; nếu để _blocking=false vài nhịp thì AB="done"
        -- của race cũ có thể lọt qua trước khi worker reroll kịp khóa.
        MainRaceReroll._blocking = true
        MainRaceReroll._resolved = false
        MainRaceReroll._matchedAt = 0
        MainRaceReroll._fragmentFunding = false
        MainRaceReroll._fragmentRequired = 0
        RuntimeState.mainDoneValidatedRace = nil
        if Training.invalidateUpgradeRaw then pcall(Training.invalidateUpgradeRaw, "mainrace_start") end

        task.spawn(function()
            -- Chờ game/data/team sẵn sàng.
            local t0 = tick()
            repeat
                task.wait(0.2)
                local data = LocalPlayer:FindFirstChild("Data")
                local race = data and data:FindFirstChild("Race")
                if RuntimeState.gameReady and LocalPlayer.Team and race then
                    break
                end
            until not Runtime.alive or (tick() - t0) > 90

            if not Runtime.alive then
                return
            end

            MainRaceReroll._blocking = true
            MainRaceReroll._resolved = false
            MainRaceReroll._startedAt = tick()
            MainRaceReroll._attempt = 0

            Logger.info(
                "[MAINRACE]["
                    .. tostring(role)
                    .. "] continuous self-check start | player="
                    .. tostring(Config.myName)
                    .. " | target="
                    .. displayRace(target)
                    .. " | canonical="
                    .. tostring(target),
                "mainrace_continuous_start_" .. tostring(role)
            )

            while Runtime.alive do
                local matched, currentCanonical, currentRaw =
                    isCurrentRaceTarget(target)

                MainRaceReroll._currentRace =
                    currentCanonical or currentRaw

                -- Race của chính account đã đúng:
                -- dừng ngay và tuyệt đối không gọi thêm reroll.
                if matched then
                    -- Nếu race vừa đạt trong lúc đang kiếm F (vd manual reroll), dừng Tyrant sạch trước.
                    stopMainRaceFragmentFarm("MainRace target matched")
                    -- Target vừa đạt: huỷ MỌI UpgradeRace cache của race trước và ghi mốc settle.
                    if Training.invalidateUpgradeRaw then pcall(Training.invalidateUpgradeRaw, "mainrace_target_match") end
                    MainRaceReroll._matchedAt = tick()
                    RuntimeState.mainDoneValidatedRace = nil
                    MainRaceReroll._resolved = true
                    MainRaceReroll._blocking = false

                    Logger.ok(
                        "[MAINRACE]["
                            .. tostring(role)
                            .. "] current="
                            .. tostring(currentRaw or currentCanonical)
                            .. " | target="
                            .. displayRace(target)
                            .. " → MATCH, STOP REROLL",
                        "mainrace_until_match_done_" .. tostring(role)
                    )

                    status(
                        "[MAINRACE]["
                            .. tostring(role)
                            .. "] Race đúng: "
                            .. displayRace(target)
                            .. " → dừng reroll"
                    )
                    return
                end

                -- Race thường cần 3000F cho MỖI lần reroll. Nếu thiếu thì KHÔNG tăng attempt,
                -- KHÔNG gọi remote; giữ blocking và farm Tyrant tới đúng 3000F rồi mới quay lại reroll.
                if not ensureMainRaceRerollFragments(target, role) then
                    task.wait(0.5)
                    continue
                end

                MainRaceReroll._attempt =
                    (MainRaceReroll._attempt or 0) + 1

                -- Mọi Main đều giữ status checking trong lúc chưa đúng race.
                -- State.reportStatus dùng được cả khi /init chưa kịp set myMainIndex.
                if role == "main" then
                    State.reportStatus("checking")
                end

                status(
                    "[MAINRACE]["
                        .. tostring(role)
                        .. "] current="
                        .. displayRace(currentRaw or currentCanonical)
                        .. " ≠ target="
                        .. displayRace(target)
                        .. " → reroll attempt "
                        .. tostring(MainRaceReroll._attempt)
                )

                -- checkAndReroll luôn check lại race ngay trước remote.
                -- Nếu race vừa đổi đúng giữa hai nhịp thì remote sẽ được skip.
                checkAndReroll(target, role)

                -- Kiểm tra ngay sau lần gọi, không chờ sang chu kỳ kế nếu đã đúng.
                local nowMatched = isCurrentRaceTarget(target)
                if nowMatched then
                    stopMainRaceFragmentFarm("MainRace target reached after reroll")
                    if Training.invalidateUpgradeRaw then pcall(Training.invalidateUpgradeRaw, "mainrace_target_reached") end
                    MainRaceReroll._matchedAt = tick()
                    RuntimeState.mainDoneValidatedRace = nil
                    MainRaceReroll._resolved = true
                    MainRaceReroll._blocking = false

                    Logger.ok(
                        "[MAINRACE]["
                            .. tostring(role)
                            .. "] target reached after attempt "
                            .. tostring(MainRaceReroll._attempt)
                            .. " → stop",
                        "mainrace_reached_after_attempt_" .. tostring(role)
                    )

                    status(
                        "[MAINRACE]["
                            .. tostring(role)
                            .. "] Race đúng: "
                            .. displayRace(target)
                            .. " → dừng reroll"
                    )
                    return
                end

                task.wait(MAINRACE_RETRY_INTERVAL)
            end

            -- Runtime tắt thì dừng worker Fragment của MainRace rồi mới nhả lock nội bộ;
            -- không đánh dấu resolved giả.
            stopMainRaceFragmentFarm("Runtime stopped during MainRace")
            MainRaceReroll._blocking = false
        end)
    end
end

--[[ ============================================================================
 [27c] SCOUTNAVIGATOR — LỚP ĐIỀU HƯỚNG MỎNG (chỉ teleport, KHÔNG chặn trial gốc).
   tick(ctx) → true = đã điều hướng, dừng tick lượt này; false = đã ở đúng nơi → THẢ
   xuống logic trial/training gốc. Fullmoon-join 100% do server + 2 Ally.
============================================================================ ]]
local ScoutNavigator = {}
do
    local _lastAllyHoldHop = 0
    local _lastMainJoinSpam = 0
    local _allyFmConfirmedAt = 0   -- tick lần cuối isfullmoon()==true khi đang đứng ĐÚNG target (chống flicker rời sớm)
    local ALLY_FM_GRACE = 8        -- giây: moon "tắt" dưới ngưỡng này coi là flicker (world chưa load) → VẪN giữ server

    -- Ally1/Ally2 = 2 ally đầu theo thứ tự config
    local function isScoutAlly()
        if State.myRole ~= "ally" then return false end
        for i, nm in ipairs(Config.allies or {}) do
            if nm == Config.myName and i <= (State.requiredAllies or 2) then return true end
        end
        return false
    end
    RuntimeState.isScoutAlly = isScoutAlly

    -- Ally1 (LEADER) = ally đầu tiên online do server chốt (ally_leader từ /curmain).
    -- Fallback: nếu server chưa cấp → dùng ally đầu trong Config online. Ally1 là AUTHORITY:
    -- tự /getseverapi (đúng placeid) → hop → xác nhận còn FM → /lockmoon. Ally2 chờ jobid đã chốt rồi join.
    local function isAllyLeader()
        if not isScoutAlly() then return false end
        if State.allyLeader and State.allyLeader ~= "" then
            return State.allyLeader == Config.myName
        end
        -- fallback: ally đầu tiên trong Config == mình
        for _, nm in ipairs(Config.allies or {}) do
            if State.myRole == "ally" then return nm == Config.myName end
        end
        return false
    end
    RuntimeState.isAllyLeader = isAllyLeader

    local _lastGetSeverApi = 0     -- chống spam /getseverapi
    local _getSeverApiCooldown = 5  -- giây: Ally1 detect hết FM + xin server mới mỗi 5s (yêu cầu user)
    local _joinMoonReported = false -- tránh POST liên tục khi đang hop
    local _leaderTarget = nil       -- jobid Ally1 tự xin từ /getseverapi (trước khi server chốt)
    local _lastLockMoon = 0         -- chống spam /lockmoon
    -- FORWARD-DECLARE: __allyTrainExit (định nghĩa bên dưới) gọi leaderRequestServer, mà hàm đó
    -- lại khai báo SAU nó. Không forward-declare thì closure bắt GLOBAL nil → crash "attempt to
    -- call a nil value" đúng lúc ally train xong.
    local leaderRequestServer
    -- HOOK: AllyFullMoonWatch (1 authority phá lock) gọi khi đã /fmlost → clear target chết để nhịp
    -- allyLeaderTick sau thấy target=nil → tự /getseverapi xin server mới. Đây là cầu nối để leaderTick
    -- KHÔNG tự quyết rời (chống hop sớm) mà vẫn xin được server mới sau khi Watch xác nhận hết FM.
    RuntimeState.__leaderOnFmLost = function()
        _leaderTarget = nil
        _allyFmConfirmedAt = 0
    end
    -- HOOK: AllyFullMoonWatch gọi sau khi getseverapi trả jobid mới → set _leaderTarget ngay,
    -- không phải chờ nhịp leaderTick gọi leaderRequestServer (tránh kẹt "waiting current main").
    RuntimeState.__leaderSetTarget = function(jobid)
        _leaderTarget = jobid and jobid ~= "" and jobid or nil
    end

    --[[ ===== ALLY TRAIN MODE (user 2026-08-10) =====
      YÊU CẦU USER: Ally1/Ally2 khi CẦN TRAIN thì phải train TRƯỚC, không quan tâm gì khác.
      Ally1 (đang giữ lock) → PHÁ LOCK NGAY: POST /fmlost + clear state local rồi đi train.
      Ally2 (không giữ lock) → tự đi train, KHÔNG /fmlost (không phá lock của Ally1).
      Khi train xong (gate về ready_trial) → allyTrainExit() → Ally1 tự /getseverapi xin server mới.

      Cờ này là AUTHORITY duy nhất: khi bật, allyTick() nhả quyền điều hướng (return false) để
      StateMachine chạy nhánh ally-train. Nhờ vậy ally KHÔNG cần đang-ở-FM mới train được
      (trước đây allyTick return true ở mọi nhánh join → không bao giờ chạm nhánh train). ]]
    local _allyTrainMode = false
    local _allyTrainSince = 0
    local _lastFmLostForTrain = 0

    RuntimeState.__allyTrainModeActive = function() return _allyTrainMode end

    -- Vào train mode. Ally1 giữ lock → phá lock (/fmlost) trước khi train.
    RuntimeState.__allyTrainEnter = function()
        if _allyTrainMode then return end
        _allyTrainMode = true
        _allyTrainSince = tick()
        local fmJob = State.fullmoonJobid
        local holdingLock = State.fullmoonLocked == true
            and fmJob and fmJob ~= "" and game.JobId == fmJob
        -- clear target local NGAY (đồng bộ) → nhịp sau không hop lại FM khi đang train
        _leaderTarget = nil
        _allyFmConfirmedAt = 0
        _joinMoonReported = false
        if holdingLock and isAllyLeader() then
            -- Ally1 ĐANG GIỮ LOCK → phải nhả để cả đàn không chờ vô ích.
            if (tick() - _lastFmLostForTrain) >= 5 then
                _lastFmLostForTrain = tick()
                Logger.info("[ALLY-TRAIN] cần train khi đang GIỮ locked FM @ " .. tostring(fmJob)
                    .. " → POST /fmlost phá lock rồi đi train", "ally_train_fmlost")
                task.spawn(function()
                    pcall(function()
                        Net.postJSON(endpoint("/fmlost", { name = Config.myName }),
                            { jobid = fmJob, reason = "ally_need_train" }, "fmlost")
                    end)
                end)
            end
            -- clear local ngay, không đợi /curmain poll
            State.fullmoonJobid = nil
            State.serverCurJobid = nil
        else
            Logger.info("[ALLY-TRAIN] cần train (không giữ lock) → đi train, KHÔNG /fmlost",
                "ally_train_nolock")
        end
    end

    -- Ra khỏi train mode (gate đã về ready_trial/done) → quay lại nhiệm vụ FM.
    RuntimeState.__allyTrainExit = function()
        if not _allyTrainMode then return end
        _allyTrainMode = false
        Logger.info("[ALLY-TRAIN] train xong sau " .. tostring(math.floor(tick() - _allyTrainSince))
            .. "s → quay lại nhiệm vụ FullMoon", "ally_train_exit")
        _allyTrainSince = 0
        -- Ally1: xin server FM mới ngay (Ally2 sẽ tự follow khi Ally1 chốt).
        if isAllyLeader() then leaderRequestServer("[after-train]") end
    end

    -- Ally1 xin server full moon mới (server lọc đúng placeid của Ally1) → set _leaderTarget để hop.
    -- LƯU Ý: gán vào biến đã forward-declare ở trên (KHÔNG dùng `local function` — sẽ tạo local
    -- MỚI che biến cũ, khiến __allyTrainExit vẫn thấy nil).
    function leaderRequestServer(reasonTag)
        -- HARD LOCK: đang giữ locked fullmoon job → KHÔNG xin server mới
        if State.myRole == "ally"
            and State.fullmoonLocked == true
            and State.fullmoonJobid and State.fullmoonJobid ~= ""
            and game.JobId == State.fullmoonJobid
        then
            DBG("[ALLY1] skip getseverapi: locked fullmoon still held @ " .. tostring(State.fullmoonJobid), "info", "ally1_skip_getsev")
            return
        end
        if (tick() - _lastGetSeverApi) < _getSeverApiCooldown then return end
        _lastGetSeverApi = tick()
        local placeId = tostring(game.PlaceId)
        task.spawn(function()
            local url = endpoint("/getseverapi", { name = Config.myName, placeid = placeId })
            local ok, body = Net.getRaw(url)
            if ok and body then
                local good, res = pcall(function() return HttpService:JSONDecode(body) end)
                if good and res and res.ok and res.jobid and res.jobid ~= "" then
                    _leaderTarget = tostring(res.jobid)
                    Logger.info("[ALLY1-GETSEV] " .. tostring(reasonTag) .. " server cấp jobid=" .. _leaderTarget
                        .. " (placeid=" .. placeId .. ")", "ally1_getsev")
                else
                    Logger.info("[ALLY1-GETSEV] không có server phù hợp placeid=" .. placeId, "ally1_getsev_nil")
                end
            end
        end)
    end

    -- ===== Ally1 (LEADER): tự pick server (đúng placeid) → hop → xác nhận còn FM → /lockmoon → giữ =====
    local function allyLeaderTick()
        -- HARD LOCK GUARD: đang ở đúng server đã chốt → KHÔNG hop, KHÔNG getseverapi, KHÔNG clear target
        local lockedFmJob = State.fullmoonJobid
        local locked = State.fullmoonLocked == true and lockedFmJob and lockedFmJob ~= ""
        if locked and game.JobId == lockedFmJob then
            local fmNow = isfullmoon()
            _leaderTarget = lockedFmJob
            State.reportStatus("ally")
            if fmNow == true then
                -- CÒN full moon: gửi /lockmoon theo cooldown để giữ chốt
                if (tick() - _lastLockMoon) >= 3 then
                    _lastLockMoon = tick()
                    task.spawn(function()
                        pcall(function()
                            Net.postJSON(endpoint("/lockmoon", { name = Config.myName }),
                                { jobid = lockedFmJob }, "lockmoon_" .. tostring(lockedFmJob))
                        end)
                    end)
                end
                status("[ALLY1] HOLD locked FM @ " .. tostring(lockedFmJob) .. " (fmNow=true)")
                return false
            elseif fmNow == nil then
                -- Sky chưa load → chưa kết luận, giữ nguyên, Watch sẽ phán quyết
                status("[ALLY1] HOLD locked FM @ " .. tostring(lockedFmJob) .. " (Sky loading, fmNow=nil)")
                return false
            else
                -- fmNow == false: có vẻ hết FM → KHÔNG tự hop, giao AllyFullMoonWatch xử lý qua grace
                status("[ALLY1] locked FM maybe lost @ " .. tostring(lockedFmJob) .. " → hold, chờ Watch xác nhận")
                return false
            end
        end

        -- đã có server chốt (fullmoonJobid) → coi đó là đích; chưa có → dùng _leaderTarget tự xin
        local target = State.fullmoonJobid or _leaderTarget
        if not target then
            leaderRequestServer("[no-target]")
            State.reportStatus("moon")
            status("[ALLY1] Xin server full moon (placeid=" .. tostring(game.PlaceId) .. ")...")
            return true
        end
        if game.JobId ~= target then
            -- ĐANG HOP tới server candidate
            _allyFmConfirmedAt = 0
            if not _joinMoonReported then _joinMoonReported = true; State.reportStatus("join_moon") end
            if (tick() - _lastAllyHoldHop) >= (State.joinSpamInterval or 5) then
                _lastAllyHoldHop = tick()
                status("[ALLY1] Hop vào server full moon: " .. tostring(target))
                RuntimeState.allyHopArmedT = tick()
                TeleportManager.hopToJob(target, "[ALLY1-JOIN-FULLMOON]")
            end
            return true
        end
        -- ĐÃ Ở target
        _joinMoonReported = false
        local fmState = isfullmoon()  -- true=FM, false=không phải FM, nil=Sky chưa load
        if fmState == true then
            local justConfirmed = _allyFmConfirmedAt == 0  -- lần đầu confirm FM lượt này
            _allyFmConfirmedAt = tick()
            -- CÒN full moon → CHỐT lên server (/lockmoon) ngay lần đầu confirm, sau đó throttle 3s
            local shouldLock = State.fullmoonJobid ~= target
                and (justConfirmed or (tick() - _lastLockMoon) >= 3)
            if shouldLock then
                _lastLockMoon = tick()
                task.spawn(function()
                    pcall(function()
                        Net.postJSON(endpoint("/lockmoon", { name = Config.myName }),
                            { jobid = target }, "lockmoon_" .. tostring(target))
                    end)
                end)
            end
            State.reportStatus("ally")
            status("[ALLY1] Holding FullMoon " .. tostring(target) .. " → CHỐT + ally")
            return false
        elseif fmState == nil then
            -- Sky chưa load xong (texture rỗng) → chưa kết luận, KHÔNG phải "hết FM".
            -- Nếu đã từng confirm FM lượt này (_allyFmConfirmedAt>0) → gửi /lockmoon ngay
            -- để không bị muộn 3 phút do Sky lag. Watch sẽ phán quyết sau khi Sky load.
            if _allyFmConfirmedAt > 0 and State.fullmoonJobid ~= target and (tick() - _lastLockMoon) >= 3 then
                _lastLockMoon = tick()
                task.spawn(function()
                    pcall(function()
                        Net.postJSON(endpoint("/lockmoon", { name = Config.myName }),
                            { jobid = target }, "lockmoon_" .. tostring(target))
                    end)
                end)
            end
            State.reportStatus("ally")
            status("[ALLY1] Sky đang load @ " .. tostring(target) .. " → giữ chỗ")
            return false
        else
            -- fmState == false: FM CÓ VẺ tắt.
            -- Tới được đây nghĩa là target KHÔNG phải locked-fullmoon đang-giữ (case đó đã bị chặn ở
            -- block "HARD LOCK GUARD" đầu hàm). Target ở đây chỉ là _leaderTarget/candidate CHƯA lock
            -- (hoặc server vừa UNLOCK khiến State.fullmoonJobid=nil). AllyFullMoonWatch KHÔNG can thiệp
            -- case này (nó early-return khi State.fullmoonJobid==nil hoặc game.JobId~=fullmoonJobid),
            -- nên nếu ngồi "chờ Watch" thì _leaderTarget dính server chết VĨNH VIỄN → Ally1 kẹt
            -- "Waiting for current main" (bug user 2026-07-02: server /fmlost + unlock đúng, Ally2 sang
            -- moon, nhưng Ally1 không xin server mới). PHẢI tự bỏ target chết + /getseverapi.
            if _allyFmConfirmedAt == 0 then _allyFmConfirmedAt = tick() end
            if (tick() - _allyFmConfirmedAt) >= ALLY_FM_GRACE then
                -- quá grace mà vẫn KHÔNG phải full moon → server này chết → bỏ target + xin server mới ngay
                if _leaderTarget == target then _leaderTarget = nil end
                _allyFmConfirmedAt = 0
                State.reportStatus("moon")
                leaderRequestServer("[candidate-not-fm]")
                status("[ALLY1] Candidate " .. tostring(target) .. " KHÔNG full moon (quá grace) → bỏ, xin server mới")
                return true
            end
            -- còn trong grace → coi là flicker/world chưa load, giữ tạm
            State.reportStatus("ally")
            status("[ALLY1] moon pending @ " .. tostring(target) .. " → giữ (grace, tự bỏ nếu quá " .. tostring(ALLY_FM_GRACE) .. "s)")
            return false
        end
    end

    -- ===== Ally2 (FOLLOWER): CHỜ Ally1 chốt (fullmoonJobid) rồi join theo. KHÔNG tự pick server. =====
    local function allyFollowerTick()
        local target = State.fullmoonJobid   -- chỉ join khi ĐÃ chốt (không dùng candidate/allyTarget mơ hồ)
        if not target then
            _allyFmConfirmedAt = 0
            State.reportStatus("moon")
            status("[ALLY2] Chờ Ally1 chốt server full moon...")
            return true
        end
        if game.JobId ~= target then
            _allyFmConfirmedAt = 0
            if not _joinMoonReported then _joinMoonReported = true; State.reportStatus("join_moon") end
            if (tick() - _lastAllyHoldHop) >= (State.joinSpamInterval or 5) then
                _lastAllyHoldHop = tick()
                status("[ALLY2] Join server full moon Ally1 đã chốt: " .. tostring(target))
                RuntimeState.allyHopArmedT = tick()
                TeleportManager.hopToJob(target, "[ALLY2-JOIN-FULLMOON]")
            end
            return true
        end
        _joinMoonReported = false
        if isfullmoon() then
            _allyFmConfirmedAt = tick()
            State.reportStatus("ally")
            status("[ALLY2] Holding FullMoon " .. tostring(target) .. " → ally")
            return false
        elseif _allyFmConfirmedAt > 0 and (tick() - _allyFmConfirmedAt) < ALLY_FM_GRACE then
            State.reportStatus("ally")
            status("[ALLY2] moon flicker → giữ")
            return false
        else
            -- LỚP 1 (user 2026-07-02): đứng đúng server ĐÃ LOCK mà isfullmoon() đọc hụt 1 nhịp (Sky/texture
            -- load lệch giữa các client) → KHÔNG flip "moon". Tin server + Ally1/AllyFullMoonWatch làm trọng
            -- tài quyết FM mất (grace 8s + /fmlost). Nếu FM thật sự hết → Ally1 /fmlost → server UNLOCK →
            -- State.fullmoonJobid=nil → nhịp sau rơi vào nhánh "not target" ở trên → tự về "moon". KHÔNG kẹt.
            if State.fullmoonLocked == true and target and game.JobId == target then
                State.reportStatus("ally")
                status("[ALLY2] isfullmoon() hụt nhưng server ĐÃ LOCK @ " .. tostring(target) .. " → giữ ally (chờ Ally1/Watch quyết)")
                return false
            end
            -- Server CHƯA lock (hoặc đã unlock) → thật sự hết FM → KHÔNG tự xin server (để Ally1 quyết).
            _allyFmConfirmedAt = 0
            State.reportStatus("moon")
            status("[ALLY2] FullMoon hết, chờ Ally1 chốt server mới...")
            return true
        end
    end

    local function allyTick()
        --[[ ALLY TRAIN MODE (user 2026-08-10): CẦN TRAIN thì train TRƯỚC, không quan tâm gì khác.
             Trả false = NHẢ quyền điều hướng → StateMachine chạy nhánh ally-train ở dưới.
             ĐẶT TRƯỚC isScoutAlly() để ally 3+ (standby) cũng train được khi cần.
             Không hop, không join FM, không reportStatus("moon") — nhánh train tự set "training". ]]
        if _allyTrainMode then
            status("[ALLY] TRAIN MODE — train trước, tạm bỏ nhiệm vụ FullMoon")
            return false
        end
        if not isScoutAlly() then
            State.reportStatus("moon")
            status("[ALLY] Scout standby (không phải Ally1/Ally2)")
            return true
        end
        if isAllyLeader() then return allyLeaderTick() end
        return allyFollowerTick()
    end

    local function mainTick(ctx)
        local myStatus = ctx.myStatus
        -- FIX stt1: ưu tiên current do server /curmain cấp (Promt.md §XI dòng 630) → detect main stt1 đúng
        local currentmain = State.serverCurMain or ctx.currentmain
        local fmJob = State.fullmoonJobid

        -- training → hop server ít người (1 lần) rồi THẢ xuống training gốc; done → thả gốc (changefolder)
        -- FIX #4 (user 2026-07-02): CHỈ hop training server sau khi ĐÃ thực sự in_trail lượt này
        -- (RuntimeState.didTrialInFM). Nếu chuyển "training" mà CHƯA in_trail (vd cần train i=1/3) → KHÔNG hop,
        -- train TẠI CHỖ. Tránh "Trial done → hop" khống lúc vừa vào server + cắt loop i=3 hop-ra-join-lại.
        if myStatus == "training" then
            if fmJob and game.JobId == fmJob and RuntimeState.didTrialInFM and not RuntimeState.trainingHopped then
                RuntimeState.trainingHopped = true
                RuntimeState.didTrialInFM = false
                State.didEnterTrialThisTurn = false -- BS-5: rời fullmoon để training → reset
                status("[TRAINING] In_trial xong → hop low-player training server")
                TeleportManager.hopTrainingServer("[AFTER-TRIAL-TRAINING]")
                return true
            end
            return false
        end
        if myStatus == "done" then return false end
        RuntimeState.trainingHopped = false

        -- FIX #3 (user 2026-07-02): TRƯỚC khi join full moon phải check còn cần training không.
        -- Đã xác nhận cần train 3 lần (ctx.trainConfirmed) → KHÔNG join/ready FM, thả xuống StateMachine
        -- để train trước (chặn lỗi i=3: join FM → phát hiện cần train → hop ra → gate còn mở → join lại → loop).
        if ctx.trainConfirmed then return false end

        -- CHƯA lock full moon (hoặc chưa có fmJob) → current báo moon + "Waiting for Ally"; con khác chờ
        -- FIX stt1: thêm "or not fmJob" (Promt.md §XI dòng 639) → tránh hopToJob(nil) khi lock mà jobid chưa propagate
        if not State.fullmoonLocked or not fmJob then
            if currentmain == Config.myName then
                State.setMyMainStatus("moon")
                status("[MAIN] Waiting for Ally (chờ 2 Ally giữ full moon)...")
            else
                -- SPEC MỚI (user 2026-07-02): Main2-6 chờ = "waiting" (KHÔNG để kẹt "checking" từ check window)
                if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                status("[MAIN] Waiting for Ally...")
            end
            return true
        end

        -- ĐÃ lock. Main1/current vào TRƯỚC
        if currentmain == Config.myName then
            if game.JobId ~= fmJob then
                -- FIX (user 2026-07-02): CHỈ join full moon khi ĐÃ xác nhận trial được 3 lần (trialConfirmed).
                -- Chưa xác nhận (mới vào server, _G streak reset) → return false, train/grind tại chỗ, KHÔNG join.
                if not ctx.trialConfirmed then return false end
                -- FIX GameFull (user 2026-07-02): vừa hop gặp server ĐẦY → backoff, ngừng spam + tụt "waiting"
                -- (không kẹt "moon"/current). Hết backoff mới thử join lại (chờ có người rời server FM).
                if RuntimeState.fmJoinBackoffUntil and tick() < RuntimeState.fmJoinBackoffUntil then
                    if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                    status("[MAIN1] Server FM đầy → chờ slot (" .. tostring(math.ceil(RuntimeState.fmJoinBackoffUntil - tick())) .. "s)")
                    return true
                end
                if (tick() - _lastMainJoinSpam) >= (State.joinSpamInterval or 5) then
                    _lastMainJoinSpam = tick()
                    State.setMyMainStatus("moon")
                    status("[MAIN1] Join server Ally: " .. tostring(fmJob))
                    TeleportManager.hopToJob(fmJob, "[MAIN1-JOIN-FULLMOON]")
                end
                return true
            end
            -- ĐÃ ở FM cùng Ally. FIX ready-sớm (user 2026-07-02): CHỈ báo "ready" khi ĐỦ requiredAllies
            -- (2) ally ĐANG giữ FM cùng jobid này (State.fullmoonAllyCount do server tính = allyFullmoonNamesAt).
            -- LÝ DO: ready → server mở gate → Main2-6 flood spam-join → server ĐẦY 12 người → ally thứ 2
            -- (join_moon) DÍNH Error 772 KHÔNG vào nổi → FM chỉ có 1 ally, cả đàn kẹt. Chưa đủ ally → giữ
            -- "moon" (đang chờ ally vào), gate CHƯA mở, Main2-6 còn "waiting" → CHỪA slot cho ally thứ 2.
            local needAllies = State.requiredAllies or 2
            local haveAllies = State.fullmoonAllyCount or 0
            if haveAllies < needAllies then
                if myStatus ~= "moon" then State.setMyMainStatus("moon") end
                status("[MAIN1] In FullMoon, chờ đủ ally (" .. tostring(haveAllies) .. "/" .. tostring(needAllies) .. ") mới ready → chừa slot cho ally")
                return true
            end
            -- Đủ ally → ready → THẢ xuống my-turn gốc (door/trial/kill)
            State.setMyMainStatus("ready")
            status("[MAIN1] In FullMoon với đủ " .. tostring(haveAllies) .. " ally → Ready for trialing")
            return false
        end

        -- Main2-6: CHỈ spam join khi đủ 4 cờ (Promt.md §6): locked + gate_open + gate_opened_once + fmJob
        -- (gate_open ≈ Main1 đã báo ready + đủ Ally). Trước đó → thả xuống StateMachine = waiting/train song song.
        -- FIX E (user 2026-07-02): ĐÃ vật lý ở trong FM (game.JobId==fmJob) → LUÔN "ready", KHÔNG phụ thuộc gate.
        -- Trước đây "ready" bị bọc trong điều kiện gate → khi gate chưa mở (current đang training), main ở
        -- FM bị skip → rơi xuống StateMachine, status "moon" cũ (set lúc join) kẹt mãi không chuyển ready.
        if fmJob and game.JobId == fmJob then
            if myStatus ~= "ready" then State.setMyMainStatus("ready") end
            status("[MAIN " .. tostring(ctx.myStt) .. "] In FullMoon (ready) → chờ tới lượt trial theo thứ tự vào")
            return true
        end
        if State.fullmoonLocked and State.gateOpen and State.gateOpenedOnce and fmJob then
            -- FIX (user 2026-07-02): CHỈ join full moon khi ĐÃ xác nhận trial được 3 lần (trialConfirmed).
            -- Chưa xác nhận (mới vào server, _G streak reset) → return false, train/grind tại chỗ, KHÔNG join.
            if not ctx.trialConfirmed then return false end
            -- FIX moon-đồng-loạt (user 2026-07-02): GIỚI HẠN số main "moon"/spam-join cùng lúc = MOON_CONCURRENT_MAX.
            -- Trước đây Main1 ready → gate mở → TẤT CẢ main2-9 đồng loạt moon spam-join → flood server đầy 12.
            -- Giờ chỉ stt <= MOON_CONCURRENT_MAX (stt1=Main1 ready; stt2-5 moon) được vào; stt còn lại giữ
            -- "waiting" chờ slot. Window TỰ TRƯỢT theo order server: con trước xong (done/training rời order)
            -- thì con sau lọt vào top → được moon. → không bao giờ có quá 4 con đập cùng lúc.
            local myStt = ctx.myStt
            if myStt and myStt > (Config.MOON_CONCURRENT_MAX or 5) then
                if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                status("[MAIN " .. tostring(myStt) .. "] Chờ slot moon (stt>" .. tostring(Config.MOON_CONCURRENT_MAX or 5) .. ") → waiting")
                return true
            end
            -- FIX GameFull (user 2026-07-02): vừa hop gặp server ĐẦY → backoff, ngừng spam + tụt "waiting"
            -- (không kẹt "moon"). Con này rơi về rank waiting → KHÔNG lọt lên current. Hết backoff mới thử lại.
            if RuntimeState.fmJoinBackoffUntil and tick() < RuntimeState.fmJoinBackoffUntil then
                if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                status("[MAIN " .. tostring(ctx.myStt) .. "] Server FM đầy → chờ slot (" .. tostring(math.ceil(RuntimeState.fmJoinBackoffUntil - tick())) .. "s)")
                return true
            end
            -- SPEC MỚI (user 2026-07-02): gate mở → Main2-6 spam join = status "moon"
            -- (moon = "đang làm open gate + spam full moon"). "waiting" chỉ dành cho lúc CHỜ Main1 ready.
            if (tick() - _lastMainJoinSpam) >= (State.joinSpamInterval or 5) then
                _lastMainJoinSpam = tick()
                State.setMyMainStatus("moon")
                status("[MAIN] Gate open → spam join full moon: " .. tostring(fmJob))
                TeleportManager.hopToJob(fmJob, "[MAIN2-6-SPAM-JOIN]")
            end
            return true
        end
        -- gate chưa mở (Main1 chưa ready) → CHỜ → status "waiting" (SPEC MỚI: waiting = đợi Main1 ready)
        if myStatus ~= "waiting" then
            State.setMyMainStatus("waiting")
            status("[MAIN " .. tostring(ctx.myStt) .. "] Waiting Main1 ready (gate chưa mở)...")
        end
        return false
    end

    function ScoutNavigator.tick(ctx)
        if ctx.isMain then return mainTick(ctx) end
        return allyTick()
    end
end

--[[ ============================================================================
 [27b] ALLYFULLMOONWATCH — LOOP NỀN RIÊNG cho Ally1/Ally2 (user 2026-07-02).
   Vì allyTick chạy trong StateMachine.tick, khi Ally đang trial (runTrialPhase yield lâu)
   thì nhịp bị nghẽn → check "hết full moon" bị trễ. Tách loop nền độc lập: mỗi 5s check
   isfullmoon() khi đang ĐỨNG đúng fullmoonJobid. Hết FM (quá grace) → POST /fmlost để PHÁ
   lock + đóng open gate trên server NGAY (không chờ grace 45s), rồi /getseverapi xin server mới.
============================================================================ ]]
local AllyFullMoonWatch = {}
do
    AllyFullMoonWatch.CHECK_INTERVAL = 5
    AllyFullMoonWatch.GRACE = 8          -- moon "tắt" dưới ngưỡng này = flicker (world chưa load) → bỏ qua
    AllyFullMoonWatch.ARRIVE_GRACE = 15  -- grace KHỞI ĐỘNG khi vừa tới server (world chưa load xong Sky/moon)
    AllyFullMoonWatch.POST_COOLDOWN = 5  -- chống spam /fmlost + /getseverapi
    AllyFullMoonWatch.started = false
    AllyFullMoonWatch._fmConfirmedAt = 0
    AllyFullMoonWatch._lastPostAt = 0
    AllyFullMoonWatch._confirmedReal = false -- đã có ÍT NHẤT 1 lần isfullmoon()==true THẬT tại server này chưa
    AllyFullMoonWatch._watchJob = nil        -- jobid đang canh (đổi server → seed lại grace khởi động)

    function AllyFullMoonWatch.start()
        if AllyFullMoonWatch.started then return end
        AllyFullMoonWatch.started = true
        task.spawn(function()
            while Runtime.alive do
                task.wait(AllyFullMoonWatch.CHECK_INTERVAL)
                pcall(AllyFullMoonWatch.check)
            end
        end)
    end

    function AllyFullMoonWatch.check()
        if not Runtime.alive or Runtime.teleporting then return end
        -- chỉ Ally1 (LEADER) mới phá lock: nó là authority giữ FM. Ally2 canh nhưng KHÔNG /fmlost
        -- (tránh phá lock sai khi Ally1 vẫn đang giữ). Ally2 chờ server đổi fullmoonJobid.
        if not (RuntimeState.isAllyLeader and RuntimeState.isAllyLeader()) then return end
        local fmJob = State.fullmoonJobid
        -- chưa chốt FM hoặc mình chưa đứng đúng server FM → không phải việc của watch này (allyTick lo join)
        if not fmJob or game.JobId ~= fmJob then
            AllyFullMoonWatch._fmConfirmedAt = 0
            AllyFullMoonWatch._confirmedReal = false
            AllyFullMoonWatch._watchJob = nil
            return
        end
        -- VỪA TỚI server này (đổi jobid đang canh) → SEED grace khởi động: coi như vừa xác nhận FM để guard
        -- chống-flicker luôn hoạt động (không còn kẽ hở "_fmConfirmedAt=0 → hop ngay nhịp đầu khi Sky chưa
        -- load"). _confirmedReal=false cho tới khi isfullmoon() thật → dùng ARRIVE_GRACE dài ở giai đoạn này.
        -- VỪA TỚI server này (đổi jobid đang canh) → seed grace khởi động
        if AllyFullMoonWatch._watchJob ~= fmJob then
            AllyFullMoonWatch._watchJob = fmJob
            AllyFullMoonWatch._fmConfirmedAt = tick()
            AllyFullMoonWatch._confirmedReal = false
        end
        local fmNow = isfullmoon()
        if fmNow == true then
            -- CÒN full moon: cập nhật xác nhận thật + cập nhật _fmConfirmedAt liên tục
            AllyFullMoonWatch._fmConfirmedAt = tick()
            if not AllyFullMoonWatch._confirmedReal then
                AllyFullMoonWatch._confirmedReal = true
                Logger.info("[ALLY-WATCH] FM xác nhận THẬT lần đầu @ " .. tostring(fmJob), "ally_watch_confirm")
            end
            -- không cần làm gì thêm — allyLeaderTick lo /lockmoon + reportStatus("ally")
            return
        elseif fmNow == nil then
            -- Sky chưa load xong → chưa kết luận, giữ nguyên grace
            return
        else
            -- fmNow == false: moon có vẻ tắt → kiểm tra grace trước khi /fmlost
            -- Chưa confirm thật lần nào → dùng ARRIVE_GRACE (world còn load); đã confirm → GRACE thường
            local grace = AllyFullMoonWatch._confirmedReal and AllyFullMoonWatch.GRACE or AllyFullMoonWatch.ARRIVE_GRACE
            if AllyFullMoonWatch._fmConfirmedAt > 0
                and (tick() - AllyFullMoonWatch._fmConfirmedAt) < grace then
                return  -- chưa quá grace → flicker, bỏ qua
            end
            -- HẾT full moon THẬT (quá grace) → phá lock + xin server mới
            if (tick() - AllyFullMoonWatch._lastPostAt) < AllyFullMoonWatch.POST_COOLDOWN then return end
            -- FINAL DOUBLE-CHECK: check lại 1 lần nữa trước khi /fmlost để tránh false-positive
            local final = isfullmoon()
            if final == true or final == nil then
                -- FM vẫn còn hoặc Sky chưa load → KHÔNG /fmlost, seed lại confirmed
                AllyFullMoonWatch._fmConfirmedAt = tick()
                Logger.info("[ALLY-WATCH] /fmlost aborted: final check=" .. tostring(final) .. " @ " .. tostring(fmJob), "ally_watch_abort")
                return
            end
            AllyFullMoonWatch._lastPostAt = tick()
            AllyFullMoonWatch._fmConfirmedAt = 0
            AllyFullMoonWatch._confirmedReal = false
            AllyFullMoonWatch._watchJob = nil
            Logger.info("[ALLY-WATCH] HẾT full moon @ " .. tostring(fmJob) .. " → POST /fmlost + xin server mới", "ally_watch_lost")
            status("[ALLY-WATCH] FullMoon ended → phá lock + xin server mới...")
            -- 1) Clear state local NGAY để allyLeaderTick không còn thấy target cũ → không kẹt "waiting current main"
            if RuntimeState.__leaderOnFmLost then pcall(RuntimeState.__leaderOnFmLost) end
            -- Xóa fullmoonJobid local ngay (không đợi /curmain poll) → nhịp tiếp allyLeaderTick thấy nil → tự getseverapi
            State.fullmoonJobid = nil
            State.serverCurJobid = nil
            -- 2) POST /fmlost lên server phá lock
            task.spawn(function()
                pcall(function()
                    Net.postJSON(endpoint("/fmlost", { name = Config.myName }), { jobid = fmJob }, "fmlost")
                end)
            end)
            -- 3) Xin server full moon mới ngay (không đợi allyLeaderTick nhịp sau)
            local placeId = tostring(game.PlaceId)
            task.spawn(function()
                local url = endpoint("/getseverapi", { name = Config.myName, placeid = placeId })
                local ok, bodyRes = Net.getRaw(url)
                if ok and bodyRes then
                    local good, res = pcall(function() return HttpService:JSONDecode(bodyRes) end)
                    if good and res and res.ok and res.jobid and res.jobid ~= "" then
                        -- Set _leaderTarget qua hook nếu ScoutNavigator expose nó
                        if RuntimeState.__leaderSetTarget then pcall(RuntimeState.__leaderSetTarget, res.jobid) end
                        Logger.info("[ALLY-WATCH] server cấp jobid mới=" .. tostring(res.jobid), "ally_watch_newsev")
                    else
                        Logger.info("[ALLY-WATCH] không có server mới (getseverapi nil)", "ally_watch_newsev_nil")
                    end
                end
            end)
        end
    end
end
_G.AllyFullMoonWatch = AllyFullMoonWatch

--[[ ============================================================================
 [27.5] TRIAL TIMEOUT WATCHDOG — CLIENT ONLY, đúng 60 giây kể từ lúc VÀO TRIAL.
  - Chỉ start khi _inTrialNow == true và status đã chuyển sang in_trail.
  - Không phụ thuộc server/cycle/event protocol.
  - Nếu Trial chưa hoàn thành sau 60s: hủy movement/skill và reset Character.
  - Chạy task riêng nên vẫn hoạt động nếu doTrialForMyRace() đang block.
============================================================================ ]]
TrialTimeoutWatch = {
    generation = 0,
    active = false,
    characterToken = nil,
    timedOutCharacterToken = nil,
    startedAt = 0,
}

do
    local function currentToken()
        return tostring(State.characterToken or LocalPlayer.Character or "no-character")
    end

    local function cleanupTrialMotion()
        Movement.cancel()
        _G.SHOULDSPAMSKILLS = false
        pcall(function() CombatActions.clearSkillAimTarget() end)
        pcall(function() CombatActions.endFishTrialSwordMode() end)
    end

    local function clearActiveWatch(myGeneration)
        if myGeneration and TrialTimeoutWatch.generation ~= myGeneration then return end
        TrialTimeoutWatch.active = false
        TrialTimeoutWatch.characterToken = nil
        TrialTimeoutWatch.startedAt = 0
        State.trialStartedAt = 0
        State.trialStartedCycleId = nil
    end

    function TrialTimeoutWatch.stopNormal()
        TrialTimeoutWatch.generation = TrialTimeoutWatch.generation + 1
        clearActiveWatch()
        -- timedOutCharacterToken chỉ được vô hiệu tự nhiên khi Character mới sinh token mới.
    end

    function TrialTimeoutWatch.start(isMain, myStt)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not (char and hum and hum.Health > 0) then return false end

        local token = currentToken()

        -- Cùng Character đã timeout thì không được tự bật lại in_trail trước khi reset xong.
        if TrialTimeoutWatch.timedOutCharacterToken == token then
            cleanupTrialMotion()
            RuntimeState.inTrial = false
            State.didEnterTrialThisTurn = false
            if isMain then State.setMyMainStatus("waiting") else State.reportStatus("ally") end
            pcall(function() if hum.Health > 0 then hum.Health = 0 end end)
            return false
        end

        -- Đang đếm đúng Character này rồi: không restart timer ở mỗi tick.
        if TrialTimeoutWatch.active
            and TrialTimeoutWatch.characterToken == token
            and TrialTimeoutWatch.startedAt > 0 then
            return true
        end

        -- Hủy watch cũ (nếu có) rồi bắt đầu đúng một lần tại thời điểm đã vào Trial.
        TrialTimeoutWatch.generation = TrialTimeoutWatch.generation + 1
        local myGeneration = TrialTimeoutWatch.generation
        TrialTimeoutWatch.active = true
        TrialTimeoutWatch.characterToken = token
        TrialTimeoutWatch.startedAt = tick()
        State.trialStartedAt = TrialTimeoutWatch.startedAt
        State.trialStartedCycleId = token

        task.spawn(function()
            while Runtime.alive and TrialTimeoutWatch.generation == myGeneration do
                task.wait(0.1)

                -- Character đổi hoặc chết: Trial cũ đã kết thúc, dừng timer.
                if LocalPlayer.Character ~= char or currentToken() ~= token then
                    clearActiveWatch(myGeneration)
                    return
                end

                hum = char:FindFirstChildOfClass("Humanoid")
                if not (hum and hum.Health > 0) then
                    clearActiveWatch(myGeneration)
                    return
                end

                -- Forcefield mở = Trial đã hoàn thành, không reset.
                if templeState() == "ffup" then
                    clearActiveWatch(myGeneration)
                    return
                end

                -- Main loop đã xác nhận rời Trial bình thường.
                if RuntimeState.inTrial ~= true then
                    clearActiveWatch(myGeneration)
                    return
                end

                if (tick() - TrialTimeoutWatch.startedAt) >= 60 then
                    TrialTimeoutWatch.timedOutCharacterToken = token
                    State.trialTimeoutCycleId = token
                    TrialTimeoutWatch.active = false
                    RuntimeState.inTrial = false
                    State.didEnterTrialThisTurn = false
                    cleanupTrialMotion()

                    status((isMain and "[MAIN " .. tostring(myStt) .. "]" or "[ALLY]")
                        .. " ⏱ Trial quá 60s chưa xong → tự reset")

                    if isMain then
                        State.setMyMainStatus("waiting")
                        RuntimeState.myTurnStart = nil
                    else
                        State.reportStatus("ally")
                    end

                    -- Reset thật; CharacterAdded sẽ tạo token mới và cho phép retry sạch.
                    pcall(function()
                        local liveHum = char:FindFirstChildOfClass("Humanoid")
                        if liveHum and liveHum.Health > 0 then liveHum.Health = 0 end
                    end)
                    return
                end
            end
        end)

        return true
    end
end

--[[ ============================================================================
 [28] STATEMACHINE — flow chính y chang File A main loop (1689-2030).
============================================================================ ]]
local StateMachine = {}
do
    StateMachine.state = "BOOTING"
    StateMachine._lastStatus = nil

    local S = {
        BOOTING = "BOOTING", WAITING_ROLE = "WAITING_ROLE", WAITING_MAIN = "WAITING_MAIN",
        WAITING_MOON = "WAITING_MOON", GOING_DOOR = "GOING_DOOR",
        IN_TRIAL = "IN_TRIAL", POST_TRIAL = "POST_TRIAL",
        POST_TRIAL_WAIT    = "POST_TRIAL_WAIT",    -- 3s đứng im sau ffup
        POST_TRIAL_KILL    = "POST_TRIAL_KILL",    -- đang tìm/kill player
        POST_TRIAL_CONFIRM = "POST_TRIAL_CONFIRM", -- xác nhận thắng trial
        POST_TRIAL_RESET   = "POST_TRIAL_RESET",   -- reset + hop server
        TRAINING = "TRAINING",
        DONE = "DONE", ERROR_RECOVER = "ERROR_RECOVER",
    }
    StateMachine.S = S
    function StateMachine.transition(newState, reason)
        if StateMachine.state == newState then return end
        Logger.info(("FSM %s → %s (%s)"):format(StateMachine.state, newState, tostring(reason)), "fsm_" .. newState)
        StateMachine.state = newState
    end

    -- 1 nhịp = bản dịch sạch của main loop File A (giữ nguyên thứ tự nhánh/điều kiện)
    function StateMachine.tick()
        local me = State.myName
        local isMain = State.isMain[me] == true
        _G.ShouldSendData = false

        -- MAINRACE SELF-CHECK:
        -- Ally1/Ally2 không có checking-window riêng như Main, nên chặn ngay
        -- mọi trial/hop/training cho tới khi race của chính account đúng target.
        if MainRaceReroll.isBlocking()
            and MainRaceReroll.getRole() ~= "main"
        then
            status(MainRaceReroll.getStatusText())
            return
        end

        -- ===== CHECKING GATE (user 2026-07-02): giai đoạn ĐẦU sau khi load team xong chỉ CHECK phase =====
        -- Mốc RuntimeState.teamReadyAt = lần đầu thấy LocalPlayer.Team (sau ChooseTeam). Trong CHECK_WINDOW: KHÔNG
        -- join/trial/train, chỉ để 3-strike đọc remote xác định phase; xong window tự chạy tiếp status thật.
        --
        -- FIX checking-vĩnh-viễn (user 2026-07-02):
        --  (1) LATCH per-JobId: xong window 1 lần cho server này thì THÔI, đổi server (JobId) mới check lại.
        --      Tránh Team nhấp nháy (mất/nối lại) làm teamReadyAt reset → window restart mỗi tick → kẹt
        --      "checking" vĩnh viễn + current-main kẹt window không bao giờ chạm self-demote → chặn cả queue.
        --  (2) GRACE khi Team==nil: KHÔNG xoá teamReadyAt ngay 1 nhịp nil (respawn/anti-cheat) — chỉ coi là
        --      mất team nếu nil liên tục > TEAM_GRACE. Team về lại KHÔNG restart window (đã latch theo JobId).
        --  (3) Đổi JobId (hop server) → reset latch + streak + trainCheckLastT để check lại từ đầu, sạch state.
        local TEAM_GRACE = 3
        if RuntimeState.checkJobId ~= game.JobId then
            RuntimeState.checkJobId = game.JobId
            RuntimeState.teamReadyAt = nil
            RuntimeState.checkDoneForJob = nil
            RuntimeState.teamLostAt = nil
            RuntimeState.trainNeedStreak = 0; RuntimeState.trialableStreak = 0; RuntimeState.trainCheckLastT = nil
            RuntimeState.uncertainStreak = 0
        end
        if LocalPlayer.Team then
            RuntimeState.teamLostAt = nil
            if not RuntimeState.teamReadyAt then RuntimeState.teamReadyAt = tick() end
        else
            if not RuntimeState.teamLostAt then RuntimeState.teamLostAt = tick() end
            if (tick() - RuntimeState.teamLostAt) > TEAM_GRACE then RuntimeState.teamReadyAt = nil end
        end
        -- FIX checking (user 2026-07-02): 3-strike cần 3×1.5s = 4.5s remote reads; CHECK_WINDOW=5s quá sát
        -- → con nào remote trả chậm/uncertain 1 lần là KHÔNG đủ 3 strike trong 5s → ra window với streak sai
        -- (con lỗi con không). Nâng 8s cho đủ biên 3 lần đọc ổn định.
        local CHECK_WINDOW = 8
        local inCheckWindow = (not RuntimeState.checkDoneForJob) and RuntimeState.teamReadyAt ~= nil
            and (tick() - RuntimeState.teamReadyAt) < CHECK_WINDOW
        -- window đã trôi hết cho server này → latch lại, không bao giờ vào lại cho tới khi đổi JobId
        if (not RuntimeState.checkDoneForJob) and RuntimeState.teamReadyAt ~= nil and (tick() - RuntimeState.teamReadyAt) >= CHECK_WINDOW then
            RuntimeState.checkDoneForJob = game.JobId
        end

        local ab, AB = cachedTrialable()
        local currentmain = getCurrentMainBeingUpgraded()
        local myStt = mainSttOf(me) or State.myMainIndex
        local myStatus = ""
        if isMain then myStatus = State.getMainStatus(me) end
        -- CLEAN JOIN: lượt mới (waiting) → reset cờ đã-vào-trial.
        -- Không reset trong live kill phase vì snapshot status có thể tới trễ.
        if isMain
            and (myStatus == "waiting" or myStatus == "")
            and State.postTrialPhase ~= "kill_phase"
        then
            State.didEnterTrialThisTurn = false
        end

        -- ===== 3-STRIKE TRAINING CHECK (yêu cầu user 2026-07-02) =====
        -- DÙ ĐANG Ở STATUS NÀO (kể cả "ready"), main vừa vào phải CHECK training. Chỉ khi
        -- xác nhận "cần train" 3 LẦN LIÊN TIẾP (mỗi lần cách ≥1.5s = 3 lần đọc remote thật)
        -- mới thật sự chuyển "training" + DỪNG mọi hành động. Tránh vừa vào full moon đã nhảy
        -- training khi chưa kịp check. ready vẫn chạy check này song song (priority ready vẫn cao
        -- nhất — chỉ 3-strike train mới được ghi đè ready). Reset streak ngay khi trialable/done/gear.
        if isMain then
            if not RuntimeState.trainCheckLastT or (tick() - RuntimeState.trainCheckLastT) >= 1.5 then
                RuntimeState.trainCheckLastT = tick()
                local upg = Training.checkUpgradeForRole("main")
                if upg and not upg.uncertain then
                    RuntimeState.uncertainStreak = 0
                    if upg.needTrain then
                        RuntimeState.trainNeedStreak = (RuntimeState.trainNeedStreak or 0) + 1
                        RuntimeState.trialableStreak = 0
                    elseif upg.trialable or upg.done or upg.canBuyGear then
                        RuntimeState.trainNeedStreak = 0
                        RuntimeState.trialableStreak = (RuntimeState.trialableStreak or 0) + 1
                    end
                else
                    -- uncertain GIỜ CHỈ còn là remote THẬT SỰ fail/timeout (raw.ok==false). Case [i=?]
                    -- "acc chưa trial lần nào" đã được checkUpgradeForRole phân loại thành trialable ở nguồn
                    -- (không rơi vào đây nữa). Nếu remote fail liên tục N lần → nghiêng TRIALABLE để thoát
                    -- limbo (nhất quán: khi không chắc thì cho trial, không đẩy train).
                    RuntimeState.uncertainStreak = (RuntimeState.uncertainStreak or 0) + 1
                    if RuntimeState.uncertainStreak >= 5 then
                        RuntimeState.trainNeedStreak = 0
                        RuntimeState.trialableStreak = (RuntimeState.trialableStreak or 0) + 1
                    end
                end
            end
        else
            RuntimeState.trainNeedStreak = 0
            RuntimeState.trialableStreak = 0
            RuntimeState.uncertainStreak = 0
        end
        local trainConfirmed = isMain and (RuntimeState.trainNeedStreak or 0) >= 3
        -- FIX (user 2026-07-02): CHỈ open gate + join full moon SAU khi xác nhận TRIALABLE 3 lần liên tiếp
        -- (đọc remote thật, không cần training). Trước khi xác nhận → KHÔNG join, train tại chỗ.
        -- Chặn bug: main1 trial xong hop training server → vào lại _G reset → tưởng waiting → spam join full
        -- moon NGAY khi chưa kịp check training. Giờ phải "trial được 3 lần" mới join.
        local trialConfirmed = isMain and (RuntimeState.trialableStreak or 0) >= 3

        -- CHECKING GATE (main): trong 5s đầu sau load team → 3-strike ở trên ĐÃ chạy (đọc remote xác định
        -- phase), nhưng CHƯA hành động (join/trial/train). Báo status "checking" để dashboard thấy đang dò.
        -- Hết 5s tick sau tự chạy tiếp theo status thật. CHỈ áp main (ally có loop hold/getsever riêng).
        if isMain and inCheckWindow then
            -- Trong 8 giây đầu, phase-check và MainRace worker chạy song song.
            -- Main chưa được join/trial/train cho tới hết window.
            if AB ~= "done" and State.getMainStatus(me) ~= "checking" then
                State.reportStatus("checking")
            end

            if MainRaceReroll.isBlocking()
                and MainRaceReroll.getRole() == "main"
            then
                status(
                    "[MAIN "
                        .. tostring(myStt)
                        .. "] Checking phase "
                        .. string.format("%.1f", tick() - RuntimeState.teamReadyAt)
                        .. "/"
                        .. tostring(CHECK_WINDOW)
                        .. "s | "
                        .. MainRaceReroll.getStatusText()
                )
            else
                status(
                    "[MAIN "
                        .. tostring(myStt)
                        .. "] Checking phase ("
                        .. string.format("%.1f", tick() - RuntimeState.teamReadyAt)
                        .. "/"
                        .. tostring(CHECK_WINDOW)
                        .. "s)..."
                )
            end
            return
        end

        -- Hết checking-window 8 giây nhưng MainRace vẫn chưa đúng:
        -- tiếp tục giữ checking và chặn gameplay. Chỉ đúng target mới nhả.
        if MainRaceReroll.isBlocking()
            and MainRaceReroll.getRole() == "main"
        then
            if State.getMainStatus(me) ~= "checking" then
                State.reportStatus("checking")
            end
            status(
                "[MAIN "
                    .. tostring(myStt)
                    .. "] Checking race after 8s | "
                    .. MainRaceReroll.getStatusText()
            )
            return
        end

        -- FIX checking-kẹt UNIVERSAL (user 2026-07-02): ra khỏi check window mà status server vẫn "checking"
        -- → CHUẨN HOÁ "waiting" NGAY, TRƯỚC mọi phân nhánh. Trước đây chỉ nhánh "chưa tới lượt" (dòng ~4211)
        -- mới dọn "checking" → con nào ra window rồi đi path khác (ScoutNavigator return handled / done / training /
        -- currentmain==me) thì status server KẸT "checking" vĩnh viễn (bug: 1 con kẹt checking, các con khác qua).
        -- Đặt ở đây → status thật (moon/waiting/ready/training/done) do các nhánh phía dưới set đè lại ngay.
        if isMain and State.getMainStatus(me) == "checking" then
            State.setMyMainStatus("waiting"); myStatus = "waiting"
        end

        -- ===== chuẩn hoá status main (File A 1702-1742) =====
        if isMain then
            if AB == "done" then
                -- FIX MAINRACE DONE-RACE (2026-08-11):
                -- AB="done" KHÔNG còn đủ để ghi file. Khi MainRace active, phải đảm bảo:
                --   (1) Data.Race hiện tại đúng target;
                --   (2) target đã đứng yên >= 2s sau reroll;
                --   (3) UpgradeRace("Check") FRESH trả i=5/8 3 lần liên tiếp trên CHÍNH race target.
                -- Nhờ vậy Angel đã done -> reroll ra Mink sẽ KHÔNG mang "done" của Angel sang Mink.
                local mainRaceTarget = MainRaceReroll.getTarget()
                local mainRaceGuardActive = MainRaceReroll.getRole() == "main" and mainRaceTarget ~= nil
                local currentRaceRaw = WorldProbe.getRace()
                local currentRaceCanonical = WorldProbe.normalizeRace(currentRaceRaw) or tostring(currentRaceRaw or "")
                local targetCanonical = WorldProbe.normalizeRace(mainRaceTarget) or tostring(mainRaceTarget or "")
                local targetMatches = (not mainRaceGuardActive) or (currentRaceCanonical ~= "" and currentRaceCanonical == targetCanonical)
                local settleAge = tick() - (MainRaceReroll.getMatchedAt() or 0)
                local targetSettled = (not mainRaceGuardActive)
                    or (MainRaceReroll.isResolved() and MainRaceReroll.isTargetMatchedNow() and settleAge >= 2.0)

                if mainRaceGuardActive and (not targetMatches or not targetSettled) then
                    -- Đây chính là cửa sổ race vừa đổi: tuyệt đối không phát DONE / không ghi file / không đi gameplay.
                    if myStatus == "done" then State.setMyMainStatus("checking"); myStatus = "checking" end
                    RuntimeState.changeFileWritten = false
                    RuntimeState.mainDoneValidatedRace = nil
                    status("[MAIN " .. tostring(myStt) .. "] MainRace vừa đổi → bỏ DONE cũ, đang verify "
                        .. tostring(currentRaceRaw or "?") .. " (target=" .. tostring(mainRaceTarget or "?") .. ")")
                    return
                end

                local doneVerified = true
                if mainRaceGuardActive then
                    doneVerified = RuntimeState.mainDoneValidatedRace == currentRaceCanonical
                    if not doneVerified then
                        local okDone, whyDone = Training.confirmDoneForRace(targetCanonical, 3, 0.35)
                        doneVerified = okDone == true
                        if doneVerified then
                            RuntimeState.mainDoneValidatedRace = currentRaceCanonical
                        else
                            RuntimeState.mainDoneValidatedRace = nil
                            RuntimeState.changeFileWritten = false
                            if myStatus == "done" then State.setMyMainStatus("waiting"); myStatus = "waiting" end
                            if Training.invalidateUpgradeRaw then pcall(Training.invalidateUpgradeRaw, "done_rejected") end
                            status("[MAIN " .. tostring(myStt) .. "] Bỏ DONE stale sau reroll (" .. tostring(whyDone) .. ")")
                            return
                        end
                    end
                end

                if doneVerified then
                    if myStatus ~= "done" then State.setMyMainStatus("done"); myStatus = "done"; State.didEnterTrialThisTurn = false end
                    -- [§XIX] DONE: ghi "<PlayerName>.txt" = "Completed-<Race>" (UTF-8, ghi đè an toàn).
                    --   KHÔNG ChangeToFolder / Disconnect / Shutdown.
                    if not RuntimeState.changeFileWritten then
                        local _okw, _race = pcall(function()
                            return LocalPlayer.Data.Race.Value
                        end)
                        local raceName = _okw and tostring(_race) or "Unknown"
                        pcall(function()
                            local n = WorldProbe.normalizeRace(raceName)
                            if n and n ~= "" then raceName = n end
                        end)
                        local _okw2 = pcall(function()
                            writefile(LocalPlayer.Name .. ".txt", "Completed-" .. raceName)
                        end)
                        if _okw2 then
                            RuntimeState.changeFileWritten = true
                            status("[MAIN " .. tostring(myStt) .. "] DONE VERIFIED → ghi " .. LocalPlayer.Name .. ".txt = Completed-" .. raceName)
                        end
                    end
                end
            else
                if myStatus == "done" then State.setMyMainStatus("waiting"); myStatus = "waiting" end
                RuntimeState.changeFileWritten = false
                -- Nếu race hiện tại đã đổi khỏi race đã validate thì marker validate cũ hết hiệu lực.
                local _curDoneRace = WorldProbe.normalizeRace(WorldProbe.getRace()) or tostring(WorldProbe.getRace() or "")
                if RuntimeState.mainDoneValidatedRace and RuntimeState.mainDoneValidatedRace ~= _curDoneRace then
                    RuntimeState.mainDoneValidatedRace = nil
                end
                -- [§XVIII/§XXIII-7] Nhánh set-thẳng-training theo didEnterTrialThisTurn CHỈ còn là LEGACY
                --   (V2 tắt/disabled). Khi V2 active, việc chuyển training/done sau trial do PostTrial.
                --   processAfterRespawn() (check V4 3 lần) quyết định — KHÔNG set thẳng "training" ở đây nữa.
                local _v2Active = Config.enableEventProtocol and CriticalEvents.enabled()
                if (not _v2Active) and (myStatus == "in_trail" or myStatus == "moon") and not ab and State.didEnterTrialThisTurn then
                    -- [FIX-BUG2] Death guard: nếu MAIN chết trong post-trial → KHÔNG chuyển training
                    if State.postTrialDeathDetected then
                        DBG("[MAIN] Died in post-trial → KHÔNG training, stay waiting", "err", "main_died_no_training")
                        State.setMyMainStatus("waiting"); myStatus = "waiting"
                        State.didEnterTrialThisTurn = false
                        State.postTrialDeathDetected = false  -- Reset cho lượt sau
                    else
                        local inOwnFFA = (myStatus == "in_trail") and (templeState() == "ffup")
                            and (getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 2000)
                        if not inOwnFFA then
                            status("[MAIN " .. myStt .. "] (legacy) Trial completed, switching to training!")
                            State.setMyMainStatus("training"); myStatus = "training"; State.didEnterTrialThisTurn = false
                        else
                            status("[MAIN " .. myStt .. "] Trial done → ở lại kill player (FFA)")
                        end
                    end
                end
            end
            if myStatus == "in_trail" and ab then
                local in_temple = getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 3000
                if not in_temple then
                    status("[MAIN " .. myStt .. "] Died in trial, retrying...")
                    State.trialStartedAt = 0
                    State.trialStartedCycleId = nil
                    State.trialTimeoutCycleId = nil
                    State.setMyMainStatus("waiting"); myStatus = "waiting"
                end
            end
        end

        -- ===== VIỆC 1: MAIN STT1 quá 5' chưa xong lượt → tụt cuối (File A 1746-1768) =====
        if isMain then
            if currentmain == me and myStatus ~= "training" and myStatus ~= "done" then
                if not RuntimeState.myTurnStart then RuntimeState.myTurnStart = tick() end
                if (tick() - RuntimeState.myTurnStart) > Config.MAIN_TURN_TIMEOUT then
                    status("[MAIN " .. myStt .. "] ⏱ Quá 5 phút chưa xong lượt → tụt cuối (waiting)")
                    State.setMyMainStatus("waiting"); myStatus = "waiting"
                    RuntimeState.inTrial = false
                    RuntimeState.myTurnStart = nil
                    return
                end
            else
                RuntimeState.myTurnStart = nil
            end
        end

        -- ===== IN-TRIAL LATCH (File A 1770-1809) =====
        local _tplace = getRaceTrialPlace(WorldProbe.getRace())
        local _inTrialNow = (_tplace and ab and getdis(_tplace.CFrame) < 1500 and templeState() ~= "ffup") and true or false
        if _inTrialNow then
            local trialCycleKey = State.trialCycleId
                or ("legacy:" .. tostring(game.JobId) .. ":" .. tostring(RuntimeState.myTurnStart or State.characterToken or "trial"))

            -- Chỉ sau khi đã xác nhận VÀO TRIAL và ghi status in_trail mới bắt đầu đếm 60 giây.
            if isMain then
                if myStatus ~= "in_trail" then State.setMyMainStatus("in_trail"); myStatus = "in_trail" end
            elseif not RuntimeState.inTrial then
                State.reportStatus("in_trail")
            end
            RuntimeState.inTrial = true
            State.didEnterTrialThisTurn = true

            -- Client-only watchdog: không restart mỗi tick, không cần server hỗ trợ.
            if not TrialTimeoutWatch.start(isMain, myStt) then
                return
            end
            pcall(function() if TrialEvents then TrialEvents.trialEntered() end end)
            if isMain and State.fullmoonJobid and game.JobId == State.fullmoonJobid then RuntimeState.didTrialInFM = true end
            StateMachine.transition(S.IN_TRIAL, "in trial zone")
            status((isMain and "[MAIN " .. tostring(myStt) .. "]" or "[ALLY]") .. " 🔥 IN-TRIAL → đang làm trial")
            doTrialForMyRace()
            return
        else
            if RuntimeState.inTrial then
                -- Rời Trial bình thường (vào FFA hoặc ra ngoài): dừng watchdog/timer 60s của lần Trial này.
                TrialTimeoutWatch.stopNormal()
                State.trialStartedAt = 0
                State.trialStartedCycleId = nil
                if not isMain then
                    State.reportStatus("ally")
                else
                    -- inOwnFFA: trial VỪA xong + đang ở FFA của mình (ffup, gần temple) → KHÔNG flip training/done
                    -- vội. Giữ in_trail + didEnterTrialThisTurn để nhánh ffup dưới (3745) chạy KILL PLAYER.
                    -- Trước đây flip ngay → status clobber "ready"/"training" → check in_trail trượt → bay ra cửa.
                    local inOwnFFA = (templeState() == "ffup")
                        and (getdis(CFrame.new(TEMPLE_ENTRY_POS)) < 2000)
                    if not inOwnFFA then
                        -- [§XVII/§XVIII] KHÔNG set training/done từ MỘT lần check trialable(). Khi V2 active,
                        --   PostTrial.processAfterRespawn() (check 3 lần) mới được quyết định. Nhánh 1-lần-check
                        --   này CHỈ còn cho LEGACY (V2 tắt/disabled).
                        local _v2Active = Config.enableEventProtocol and CriticalEvents.enabled()
                        if not _v2Active then
                            local fresh_ab, fresh_AB = trialable()
                            if not fresh_ab then
                                if fresh_AB == "done" then State.setMyMainStatus("done")
                                else State.setMyMainStatus("training") end
                                State.didEnterTrialThisTurn = false -- BS-5: rời trial + chuyển done/training → reset
                            end
                        end
                    end
                end
            end
            RuntimeState.inTrial = false
        end


        --[[ ===== FRAGMENT PURCHASE GATE (2026-08-11) =====
             PRIORITY: IN-TRIAL > NEED FRAGMENTS/PURCHASE > ALLY TRAIN > SCOUT/FULLMOON.

             FragmentTyrant chỉ FARM. Training/Kaitun giữ quyền BUY.
             Khi thiếu F: khóa toàn bộ flow khác bằng return ở đây.
             Khi đủ F: worker phải STOP sạch trước; UpgradeRace Buy + invalidate cache; tick sau mới
             trả quyền cho Training/Scout/FullMoon theo phase MỚI. ]]
        do
            -- Worker có thể chạm target giữa 2 tick StateMachine. Dừng NGAY trước mọi check có quyền Buy.
            if FragmentTyrant.targetReached() then
                FragmentTyrant.stop("target reached before V4 buy")
            end

            local fragmentRole = isMain and "main" or "ally"
            local fragUpg = Training.checkUpgradeForRole(fragmentRole)
            local purchaseJustSent = RuntimeState.fragmentPurchaseJustAttempted
                and (tick() - RuntimeState.fragmentPurchaseJustAttempted) < 1.0

            if fragUpg and fragUpg.needFragments then
                local cost = tonumber(fragUpg.fragmentCost) or tonumber(fragUpg.f) or 0
                local have = tonumber(fragUpg.fragments) or Training.getCurrentFragments()

                RuntimeState.trainNeedStreak = 0
                RuntimeState.trialableStreak = 0
                State.didEnterTrialThisTurn = false
                _G.SHOULDSPAMSKILLS = false

                if isMain then
                    if myStatus ~= "training" then
                        State.setMyMainStatus("training")
                        myStatus = "training"
                    end
                else
                    -- Mượn ally-train mode CHỈ để nhả FullMoon lock/khóa Scout. Không dùng nó để farm.
                    if RuntimeState.__allyTrainModeActive
                        and not RuntimeState.__allyTrainModeActive()
                    then
                        RuntimeState.fragmentTyrantAllyBorrowedTrainMode = true
                    end
                    if RuntimeState.__allyTrainEnter then pcall(RuntimeState.__allyTrainEnter) end
                    State.reportStatus("training")
                end

                StateMachine.transition(S.TRAINING, "need fragments for V4 purchase")
                FragmentTyrant.start(cost)
                status((isMain and "[MAIN " .. tostring(myStt) .. "]" or "[ALLY]")
                    .. " NEED PURCHASE → thiếu Fragment " .. tostring(have) .. "/" .. tostring(cost)
                    .. " → AUTO TYRANT (khóa flow khác)")
                return
            end

            -- Nếu vừa đủ F và một consumer cũ đã gửi Buy ở đầu tick, vẫn khóa tick hiện tại để
            -- response/cache cũ không kéo account sang Scout/Trial trước khi UpgradeRace refresh.
            if purchaseJustSent then
                if FragmentTyrant.isActive() then FragmentTyrant.stop("V4 buy sent") end
                _G.SHOULDSPAMSKILLS = false
                StateMachine.transition(S.TRAINING, "V4 purchase sent; refreshing")
                status((isMain and "[MAIN " .. tostring(myStt) .. "]" or "[ALLY]")
                    .. " đủ Fragment → STOP TYRANT → BUY V4 → refresh UpgradeRace...")
                return
            end

            -- Purchase stage đã biến mất (buy xong / phase đổi / external change) → dọn worker sạch.
            if FragmentTyrant.isActive() then
                FragmentTyrant.stop("V4 purchase stage cleared")
            end

            -- Nếu trước đó fragment gate mượn allyTrainMode:
            --   phase mới vẫn needTrain -> GIỮ train mode để AllyTrainingGate tiếp quản;
            --   phase mới trialable/done -> nhả mode để Ally1 quay lại FM.
            if not isMain and RuntimeState.fragmentTyrantAllyBorrowedTrainMode then
                if fragUpg and fragUpg.needTrain then
                    RuntimeState.fragmentTyrantAllyBorrowedTrainMode = nil
                elseif fragUpg and not fragUpg.uncertain then
                    RuntimeState.fragmentTyrantAllyBorrowedTrainMode = nil
                    if RuntimeState.__allyTrainExit then pcall(RuntimeState.__allyTrainExit) end
                end
            end
        end

        --[[ ===== ALLY TRAIN PRE-GATE (user 2026-08-10) — PHẢI ĐỨNG TRƯỚC ScoutNavigator =====
             LÝ DO: ScoutNavigator.tick() return true ở MỌI nhánh join/hop/chờ FM và bị
             `if handled then return end` cắt tick. Nếu gate train nằm SAU đó thì ally đang ở
             NGOÀI FM không bao giờ chạm gate → không bao giờ biết mình cần train (chỉ ally
             đã đứng trong FM mới train được — sai với rule "cần train thì train trước").
             Train có quyền ưu tiên CAO HƠN ScoutNavigator/FullMoon.

             CHỈ EVALUATE 1 LẦN / TICK: AllyTrainingGate.tick() tăng confirmCount mỗi lần gọi
             (độc lập cache _upgradeRaw TTL 1.5s — cache chỉ chặn remote, không chặn đếm), nên
             gọi 2 lần/tick sẽ confirm training nhanh gấp đôi thiết kế 3 nhịp. Kết quả lưu vào
             3 biến dưới, nhánh ally ở cuối DÙNG LẠI, KHÔNG gọi gate lần hai. ]]
        local allyGateState, allyGateReason, allyGateI
        if not isMain then
            allyGateState, allyGateReason, allyGateI = AllyTrainingGate.tick("[ALLY]")
            if allyGateState == "training" then
                -- Ally1 đang giữ locked FM → helper tự POST /fmlost + clear lock local (idempotent).
                -- Ally2 không giữ lock → chỉ đi train, KHÔNG /fmlost.
                if RuntimeState.__allyTrainEnter then pcall(RuntimeState.__allyTrainEnter) end
                RuntimeState.allyKillReset = false
                State.reportStatus("training")
                StateMachine.transition(S.TRAINING, "ally train")
                status("[ALLY] Training confirmed (i=" .. tostring(allyGateI) .. ")")
                Training.handleTraining("[ALLY]", nil, function() State.reportStatus("training") end)
                return
            end
            -- gate đã về ready_trialing/done → nếu trước đó đang train thì thoát train mode
            -- (Ally1 tự /getseverapi xin FM mới; Ally2 follow khi Ally1 chốt).
            --
            -- FIX EDGE CASE (user 2026-08-10): CHỈ exit khi có PROOF THẬT.
            -- AllyTrainingGate trả "ready_trialing" cho CẢ nhánh unknown/check_failed (dòng 5592-5598)
            -- khi remote UpgradeRace("Check") timeout. Nếu exit theo đó thì chỉ 1 nhịp remote lag
            -- giữa lúc đang train là Ally1 tưởng train xong → /getseverapi → hop lại FM → vòng sau
            -- gate lại báo training → /fmlost → lặp vô hạn (flap phá lock).
            -- Proof hợp lệ: ready_trial (i=0/8), done/ally_done (i=5), fresh_never_trialed,
            -- can_buy_gear (i=2/4/7 — đã qua giai đoạn cần train).
            if RuntimeState.__allyTrainModeActive and RuntimeState.__allyTrainModeActive() then
                local r = tostring(allyGateReason or "")
                local proofDone = (r == "ready_trial") or (r == "done") or (r == "ally_done")
                    or (r == "fresh_never_trialed") or (r == "can_buy_gear") or (r == "need_fragments")
                if proofDone then
                    if RuntimeState.__allyTrainExit then pcall(RuntimeState.__allyTrainExit) end
                else
                    -- check_failed / unknown_i_* → KHÔNG kết luận, GIỮ train mode, train tiếp.
                    Logger.info("[ALLY-TRAIN] giữ train mode: gate reason=" .. r
                        .. " (không phải proof hết train)", "ally_train_hold_noproof")
                    RuntimeState.allyKillReset = false
                    State.reportStatus("training")
                    StateMachine.transition(S.TRAINING, "ally train hold (no proof)")
                    status("[ALLY] Train tiếp — chưa có kết quả check chắc chắn (" .. r .. ")")
                    Training.handleTraining("[ALLY]", nil, function() State.reportStatus("training") end)
                    return
                end
            end
        end

        -- ===== CLEAN JOIN: LỚP ĐIỀU HƯỚNG (chỉ teleport). true=dừng; false=thả xuống trial/training gốc =====
        if Config.scout then
            local handled = ScoutNavigator.tick({ isMain = isMain, myStatus = myStatus, currentmain = currentmain, myStt = myStt, trainConfirmed = trainConfirmed, trialConfirmed = trialConfirmed })
            if handled then return end
            -- re-read sau ScoutNavigator: có thể đã set ready/moon trong cùng tick này
            if isMain then myStatus = State.getMainStatus(me) end
        end

        -- ===== NHÁNH MAIN (File A 1811-1909) =====
        -- 3-STRIKE: đã xác nhận cần train 3 lần → CHUYỂN training + DỪNG mọi hành động khác
        -- (ghi đè cả "ready"). Đặt TRƯỚC mọi nhánh main để chặn vào trial/door khi thật sự cần train.
        if isMain and trainConfirmed and AB ~= "done" then
            if myStatus ~= "training" then State.setMyMainStatus("training"); myStatus = "training" end
            State.didEnterTrialThisTurn = false
            StateMachine.transition(S.TRAINING, "3-strike need train")
            status("[MAIN " .. myStt .. "] Cần train (xác nhận 3 lần) → training, dừng hành động khác")
            Training.handleTraining("[MAIN " .. myStt .. "]", AB, function() State.setMyMainStatus("training") end)
            return
        end

        if isMain and myStatus == "done" then
            StateMachine.transition(S.DONE, "full gear")
            status("[MAIN " .. myStt .. "] ✅ DONE YOUR RACE - FULL GEAR (Gear2/3/4)!")
            -- [§XIX] Done: KHÔNG ChangeToFolder / Disconnect / Shutdown. File Completed đã ghi ở nhánh AB=="done".
            --   ĐÃ XÓA HẲN caller ChangeFolder (§XIX/§XXIII-9).

        elseif isMain and myStatus == "training" then
            StateMachine.transition(S.TRAINING, "training")
            status("[MAIN " .. myStt .. "] Training (parallel)")
            if not ab then
                State.setMyMainStatus("training")
                Training.handleTraining("[MAIN " .. myStt .. "]", AB, function() State.setMyMainStatus("training") end)
            else
                if myStatus ~= "waiting" then State.setMyMainStatus("waiting") end
                status("[MAIN " .. myStt .. "] Training done → waiting (chờ tới lượt)")
            end

        elseif isMain and currentmain == me then
            StateMachine.transition(S.GOING_DOOR, "my turn")
            status("[MAIN " .. myStt .. "] My turn to upgrade gear!")
            -- LỚP 1 (user 2026-07-02): CHẶN tụt "moon" khi đang vật lý ở server FM ĐÃ LOCK. Đứng đúng
            -- fullmoonJobid = đã "ready" (ScoutNavigator set) → KHÔNG bao giờ báo "moon" nữa (moon chỉ dành
            -- cho lúc ĐI TÌM/CHỜ full moon, ngoài FM). Server unlock → game.JobId ~= fmJob → về logic cũ.
            local inLockedFM = State.fullmoonLocked == true and State.fullmoonJobid and game.JobId == State.fullmoonJobid
            if (myStatus == "waiting" or myStatus == "") and State.getMainStatus(me) ~= "ready" and not inLockedFM then State.setMyMainStatus("moon") end
            -- BS-3: ĐÃ XÓA self-hop fullmoon (ScoutNavigator đưa vào FM). Chạy thẳng gear/door/trial.
            do
                task.spawn(checkgear)
                _G.ShouldSendData = true
                local ts = templeState()
                if ts == "loading" then
                    status("[MAIN " .. myStt .. "] Đang vào Temple of Time...")
                elseif ts == "ffup" then
                    -- [FINAL §9.2/A6] Main vào FFA thật → emit ffa_entered (1 lần/cycle) + bật presence loop.
                    pcall(function() if TrialEvents then TrialEvents.ffaEntered() end end)
                    -- Dùng state chi tiết hơn trong post-trial FSM
                    if State.didEnterTrialThisTurn then
                        local killResult = PostTrial.mainKillThenReset(myStt, currentmain)
                        if killResult == "posttrial_wait_ally" then
                            StateMachine.transition(S.POST_TRIAL_WAIT, "ffup_wait")
                        elseif killResult == "posttrial_running" then
                            StateMachine.transition(S.POST_TRIAL_KILL, "ffup_kill")
                        elseif killResult == "posttrial_skip" then
                            StateMachine.transition(S.POST_TRIAL_CONFIRM, "ffup_confirm")
                        else
                            StateMachine.transition(S.POST_TRIAL_RESET, "ffup_reset")
                        end
                    else
                        -- Chưa vào trial lượt này → chờ ở cửa, KHÔNG kill, KHÔNG reset
                        StateMachine.transition(S.POST_TRIAL, "ffup_no_trial")
                        status("[MAIN " .. myStt .. "] ffup nhưng chưa vào trial lượt này → đứng cửa")
                        goToMyDoor()
                    end
                else
                    -- ffdown: gear + ra cửa + ability sync
                    runTrialPhase("[MAIN " .. myStt .. "]", true)
                    AbilitySync.reportAtDoor()
                    AbilitySync.maybeFire()
                end
            end

        elseif isMain then
            -- MAIN CHƯA TỚI LƯỢT: còn train được → train song song; sẵn sàng → waiting (+ stt2-4 bám fullmoon)
            RuntimeState.allyKillReset = false
            -- FIX checking-kẹt (user 2026-07-02): sau khi ra khỏi CHECK_WINDOW với streak<3 (con lỗi remote),
            -- status BÁO SERVER vẫn là "checking" cũ (reportStatus("checking") set trong window) mà nhánh này
            -- KHÔNG có path nào xoá khi myStatus=="checking" → dashboard kẹt "checking" vĩnh viễn dù acc đang
            -- grind/chờ lượt. Chuẩn hoá "checking"→"waiting" NGAY để status server phản ánh đúng.
            if myStatus == "checking" then State.setMyMainStatus("waiting"); myStatus = "waiting" end
            if (not ab) and AB ~= "done" then
                -- FIX flap i=: theo Promt.md §XIII — CHỈ set status "training" khi ĐÃ vào trial lượt này.
                -- Chưa vào trial (main2-6 đang chờ lượt) → giữ "waiting", vẫn grind tại chỗ, KHÔNG để
                -- status="training" khiến ScoutNavigator kéo khỏi fullmoon rồi bật lại (đá training↔waiting).
                if State.didEnterTrialThisTurn then
                    if myStatus ~= "training" then State.setMyMainStatus("training") end
                else
                    if myStatus == "training" then State.setMyMainStatus("waiting") end
                end
                StateMachine.transition(S.TRAINING, "train parallel")
                status("[MAIN " .. myStt .. "] Training song song (chưa tới lượt)")
                Training.handleTraining("[MAIN " .. myStt .. "]", AB, function()
                    if State.didEnterTrialThisTurn then State.setMyMainStatus("training") end
                end)
            else
                if myStatus == "training" then State.setMyMainStatus("waiting") end
                StateMachine.transition(S.WAITING_MAIN, "waiting turn")
                -- BS-3: ĐÃ XÓA self-hop fullmoon khi waiting (ScoutNavigator lo spam-join)
                status("[MAIN " .. myStt .. "] Waiting for current main: " .. tostring(currentmain))
            end

        else
            -- ===== NHÁNH ALLY (File A 1910-2029) =====
            local roleName = "[ALLY]"
            -- ALLY TRAIN PRE-GATE (user 2026-08-10): gate ĐÃ được evaluate MỘT LẦN ở đầu
            -- StateMachine.tick, TRƯỚC ScoutNavigator (xem block "ALLY TRAIN PRE-GATE").
            -- TUYỆT ĐỐI KHÔNG gọi AllyTrainingGate.tick() lần thứ hai ở đây: gate tăng
            -- confirmCount MỖI lần gọi (dòng ~5570) và cache _upgradeRaw (TTL 1.5s) chỉ chặn
            -- remote call chứ KHÔNG chặn việc đếm → gọi 2 lần/tick sẽ confirm training nhanh
            -- gấp đôi thiết kế 3 nhịp. Ở đây chỉ DÙNG LẠI kết quả đã có.
            status(roleName .. " Ready for trialing — " .. tostring(allyGateReason))
            -- BS-3: scout ally giữ status "ally" do ScoutNavigator set (KHÔNG ghi đè)

            status(roleName .. " Đang dò main đang tới lượt…")
            local mainActive = false
            if currentmain then
                local st = State.getMainStatus(currentmain)
                mainActive = (st == "moon" or st == "in_trail")
                status(roleName .. " main " .. tostring(currentmain) .. " = " .. tostring(st))
            end
            local sameServer = isSameServerAsMain(currentmain)
            -- BS-3: scout ally KHÔNG follow main (server điều phối full moon). Nhánh FOLLOWING_MAIN cũ
            -- ("Hop sang server main" + hop __ServerBrowser) đã XÓA HẲN vì Config.scout luôn = true.
            -- FIX #4: Main1 báo ready → server set trial_phase="trialing" → Ally biết vào trial ngay
            -- khi đang đứng đúng server full moon (không cần đợi main1 đến cửa/moon-active detect).
            local trialingSignal = (State.trialPhase == "trialing")
                and State.fullmoonJobid and State.fullmoonJobid ~= ""
                and game.JobId == State.fullmoonJobid
            if (currentmain and mainActive and sameServer) or trialingSignal or Config.vipServer or (isnight() and isfullmoon()) then
                task.spawn(checkgear)
                _G.ShouldSendData = true
                local ts = templeState()
                if ts == "loading" then
                    status(roleName .. " Đang vào Temple of Time...")
                elseif ts == "ffup" then
                    -- [FINAL §9.2/A6] Ally vào FFA thật → emit ffa_entered (1 lần/cycle) trước khi reset.
                    pcall(function() if TrialEvents then TrialEvents.ffaEntered() end end)
                    StateMachine.transition(S.POST_TRIAL, "ally ffup")
                    PostTrial.resetAllyOnce(roleName)
                else
                    RuntimeState.allyKillReset = false
                    StateMachine.transition(S.GOING_DOOR, "ally to door")
                    runTrialPhase(roleName, false)
                    AbilitySync.reportAtDoor()
                end
            else
                RuntimeState.allyKillReset = false
                StateMachine.transition(S.WAITING_MAIN, "ally wait main")
                status(roleName .. " Waiting for current main: " .. tostring(currentmain))
            end
        end
    end
end

--[[ ============================================================================
 [29] MAINLOOP — tick FSM, xpcall, ERROR_RECOVER. (File A 1674-2037)
============================================================================ ]]
local MainLoop = {}
do
    MainLoop._errStreak = 0
    function MainLoop.start()
        task.spawn(function()
            -- CheckTempleDoor + marker Completed-dontpull đã tách sang TempleDontPullCheck riêng.
            -- MainLoop chỉ giữ behavior gốc: chờ cửa mở rồi mới chạy StateMachine.
            local checktempledoor = nil

            while Runtime.alive do
                RuntimeState.loopTick = (RuntimeState.loopTick or 0) + 1
                RuntimeState.loopLastT = tick()
                if not RuntimeState.firstLoopHit then
                    RuntimeState.firstLoopHit = true
                    status("Vòng chính đã chạy — đang đồng bộ…")
                end
                -- Behavior gốc: nếu cửa chưa mở thì MainLoop tiếp tục chờ/check độc lập với TempleDontPullCheck.
                if not checktempledoor then checktempledoor = TempleDoorGate.ready() end
                if not checktempledoor then
                    status("Chờ mở cửa đền (CheckTempleDoor=" .. tostring(checktempledoor) .. ")")
                else
                    local ok, err = xpcall(StateMachine.tick, debug.traceback)
                    if ok then
                        MainLoop._errStreak = 0
                    else
                        MainLoop._errStreak = MainLoop._errStreak + 1
                        status("⚠ Lỗi vòng chính: " .. tostring(err))
                        Net.log("ERR", "main loop crash: " .. tostring(err))
                        if MainLoop._errStreak >= 5 then
                            StateMachine.transition(StateMachine.S.ERROR_RECOVER, "too many errors")
                            task.wait(2)
                        end
                    end
                end
                task.wait(Config.MAIN_TICK)
            end
        end)
    end
end

--[[ ============================================================================
 [30] NOGUCHI LOOP — mọi account POST jobid mỗi 1s. (File A 2701-2706)
============================================================================ ]]
local function startNoguchiLoop()
    task.spawn(function()
        while Runtime.alive do
            Net.postJSON(endpoint("/noguchi", { name = State.myName }), { jobid = game.JobId }, "noguchi")
            task.wait(1)
        end
    end)
end

--[[ ============================================================================
[31] UIMANAGER — GUI Premium (port File A 2709-3373) + fallback text-only.
UI lỗi KHÔNG được làm chết main loop (mọi thứ bọc pcall).
Recovery loop: nếu GUI mất → tự tạo lại.
============================================================================ ]]
local UIManager = {}
UIManager.started = false
UIManager._creating = false

local function startUIRecoveryLoop()
    task.spawn(function()
        task.wait(10)
        while Runtime.alive do
            task.wait(5)
            if not UIManager.started then break end
            local ok_gui, gui = pcall(function()
                return LocalPlayer.PlayerGui:FindFirstChild("VuNguyenKaitunV4")
            end)
            if ok_gui and not gui then
                Logger.info("[UI] missing, recreating", "ui_recreate")
                status("Recreating UI...")
                UIManager.started = false
                UIManager.start()
                Logger.ok("[UI] created", "ui_ok")
            end
        end
    end)
end

function UIManager.start()
    if UIManager.started then return end
    UIManager.started = true
    Logger.info("[UI] building...", "ui_start")
    -- text-only state luôn có (đề phòng UI build fail)
    task.spawn(function()
        while Runtime.alive do
            pcall(function()
                Diagnostics.fullStatus = (Diagnostics.statusnow or "…")
                    .. " | role=" .. tostring(State.myRole)
                    .. " | fsm=" .. tostring(StateMachine.state)
                    .. " | cur=" .. tostring(getCurrentMainBeingUpgraded())
            end)
            task.wait(Config.UI_THROTTLE)
        end
    end)

    local okUI = pcall(function()
        local TS = TweenService
        pcall(function()
            local old = LocalPlayer.PlayerGui:FindFirstChild("VuNguyenKaitunV4")
            if old then old:Destroy() end
        end)
        local rgbActive = true
        local function RegisterRGB(obj, offset, s, v, prop)
            local hue = (0.65 + (offset or 0)) % 1
            pcall(function() obj[prop or "Color"] = Color3.fromHSV(hue, s or 0.85, v or 1) end)
        end

        local Gui = Instance.new("ScreenGui")
        Gui.Name = "VuNguyenKaitunV4"; Gui.ResetOnSpawn = false; Gui.IgnoreGuiInset = false
        Gui.DisplayOrder = 1000; Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        local playerGui = LocalPlayer:WaitForChild("PlayerGui", 10)
        if not playerGui then
            Logger.warn("[UI] PlayerGui timeout, skip UI build", "playergui_timeout")
            return
        end
        Gui.Parent = playerGui

        local Toggle = Instance.new("TextButton")
        Toggle.Size = UDim2.new(0, 54, 0, 54); Toggle.Position = UDim2.new(1, -70, 0.30, 0)
        Toggle.BackgroundColor3 = Color3.fromRGB(18, 20, 28); Toggle.BorderSizePixel = 0
        Toggle.Text = "👑"; Toggle.TextSize = 26; Toggle.Font = Enum.Font.GothamBold
        Toggle.TextColor3 = Color3.fromRGB(255, 255, 255); Toggle.AutoButtonColor = false; Toggle.Parent = Gui
        Instance.new("UICorner", Toggle).CornerRadius = UDim.new(0, 14)
        local togStroke = Instance.new("UIStroke", Toggle)
        togStroke.Thickness = 2.5; togStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        RegisterRGB(togStroke, 0)

        local Panel = Instance.new("Frame")
        Panel.Size = UDim2.new(0, 320, 0, 460); Panel.Position = UDim2.new(0.5, -160, 0.5, -230)
        Panel.BackgroundColor3 = Color3.fromRGB(12, 14, 22); Panel.BorderSizePixel = 0
        Panel.Active = true; Panel.Draggable = true; Panel.Visible = true; Panel.Parent = Gui
        Instance.new("UICorner", Panel).CornerRadius = UDim.new(0, 16)
        local pStroke = Instance.new("UIStroke", Panel)
        pStroke.Thickness = 2.5; pStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
        RegisterRGB(pStroke, 0)

        local Header = Instance.new("Frame")
        Header.Size = UDim2.new(1, -20, 0, 52); Header.Position = UDim2.new(0, 10, 0, 10)
        Header.BackgroundColor3 = Color3.fromRGB(20, 23, 35); Header.BorderSizePixel = 0; Header.Parent = Panel
        Instance.new("UICorner", Header).CornerRadius = UDim.new(0, 10)
        local Title = Instance.new("TextLabel")
        Title.Size = UDim2.new(1, -50, 0, 24); Title.Position = UDim2.new(0, 14, 0, 6)
        Title.BackgroundTransparency = 1; Title.Text = "👑 VU NGUYEN KAITUN V4"
        Title.TextColor3 = Color3.fromRGB(255, 255, 255); Title.TextXAlignment = Enum.TextXAlignment.Left
        Title.Font = Enum.Font.GothamBold; Title.TextSize = 15; Title.Parent = Header
        local SubTitle = Instance.new("TextLabel")
        SubTitle.Size = UDim2.new(1, -50, 0, 14); SubTitle.Position = UDim2.new(0, 14, 0, 30)
        SubTitle.BackgroundTransparency = 1; SubTitle.Text = "✦ PREMIUM"
        SubTitle.TextXAlignment = Enum.TextXAlignment.Left; SubTitle.Font = Enum.Font.GothamBold
        SubTitle.TextSize = 11; SubTitle.Parent = Header
        RegisterRGB(SubTitle, 0.1, 0.7, 1, "TextColor3")
        local CloseBtn = Instance.new("TextButton")
        CloseBtn.Size = UDim2.new(0, 30, 0, 30); CloseBtn.Position = UDim2.new(1, -38, 0.5, -15)
        CloseBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 50); CloseBtn.BorderSizePixel = 0
        CloseBtn.Text = "✕"; CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        CloseBtn.Font = Enum.Font.GothamBold; CloseBtn.TextSize = 15; CloseBtn.AutoButtonColor = false; CloseBtn.Parent = Header
        Instance.new("UICorner", CloseBtn).CornerRadius = UDim.new(0, 8)
        CloseBtn.MouseButton1Click:Connect(function() Panel.Visible = false end)
        Toggle.MouseButton1Click:Connect(function() Panel.Visible = not Panel.Visible end)

        local TabBar = Instance.new("Frame")
        TabBar.Size = UDim2.new(1, -20, 0, 34); TabBar.Position = UDim2.new(0, 10, 0, 70)
        TabBar.BackgroundColor3 = Color3.fromRGB(16, 18, 28); TabBar.BorderSizePixel = 0; TabBar.Parent = Panel
        Instance.new("UICorner", TabBar).CornerRadius = UDim.new(0, 9)
        local tabLayout = Instance.new("UIListLayout", TabBar)
        tabLayout.FillDirection = Enum.FillDirection.Horizontal
        tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        tabLayout.VerticalAlignment = Enum.VerticalAlignment.Center; tabLayout.Padding = UDim.new(0, 4)

        local PageHolder = Instance.new("Frame")
        PageHolder.Size = UDim2.new(1, -20, 1, -120); PageHolder.Position = UDim2.new(0, 10, 0, 112)
        PageHolder.BackgroundTransparency = 1; PageHolder.BorderSizePixel = 0; PageHolder.Parent = Panel

        local pages, tabBtns = {}, {}
        local function selectTab(name)
            for n, pg in pairs(pages) do pg.Visible = (n == name) end
            for n, b in pairs(tabBtns) do
                local on = (n == name)
                b.BackgroundColor3 = on and Color3.fromRGB(40, 45, 68) or Color3.fromRGB(20, 23, 35)
                b.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 160, 185)
            end
        end
        local function CreatePage(name)
            local page = Instance.new("ScrollingFrame")
            page.Size = UDim2.new(1, 0, 1, 0); page.BackgroundTransparency = 1; page.BorderSizePixel = 0
            page.ScrollBarThickness = 4; page.ScrollBarImageColor3 = Color3.fromRGB(120, 160, 240)
            page.CanvasSize = UDim2.new(0, 0, 0, 0); page.AutomaticCanvasSize = Enum.AutomaticSize.Y
            page.Visible = false; page.Parent = PageHolder
            local l = Instance.new("UIListLayout", page); l.SortOrder = Enum.SortOrder.LayoutOrder; l.Padding = UDim.new(0, 8)
            pages[name] = page
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(0, 96, 1, -6); btn.BackgroundColor3 = Color3.fromRGB(20, 23, 35); btn.BorderSizePixel = 0
            btn.Text = name; btn.Font = Enum.Font.GothamBold; btn.TextSize = 12
            btn.TextColor3 = Color3.fromRGB(150, 160, 185); btn.AutoButtonColor = false; btn.Parent = TabBar
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 7)
            btn.MouseButton1Click:Connect(function() selectTab(name) end)
            tabBtns[name] = btn
            return page
        end
        local function addCard(page, order, height)
            local f = Instance.new("Frame")
            f.LayoutOrder = order; f.Size = UDim2.new(1, 0, 0, height)
            f.BackgroundColor3 = Color3.fromRGB(18, 20, 30); f.BorderSizePixel = 0; f.Parent = page
            Instance.new("UICorner", f).CornerRadius = UDim.new(0, 10)
            return f
        end
        local function StatusCard(page, order)
            local f = addCard(page, order, 72)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -16, 0, 16); t.Position = UDim2.new(0, 12, 0, 8)
            t.BackgroundTransparency = 1; t.Text = "● STATUS"; t.TextColor3 = Color3.fromRGB(140, 200, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 11; t.Parent = f
            local v = Instance.new("TextLabel")
            v.Size = UDim2.new(1, -20, 0, 40); v.Position = UDim2.new(0, 12, 0, 26)
            v.BackgroundTransparency = 1; v.Text = "Đang khởi động..."; v.TextColor3 = Color3.fromRGB(255, 255, 255)
            v.TextXAlignment = Enum.TextXAlignment.Left; v.TextYAlignment = Enum.TextYAlignment.Top
            v.Font = Enum.Font.GothamBold; v.TextSize = 13; v.TextWrapped = true; v.Parent = f
            return v
        end
        local function LabelCard(page, order, titleText, descText)
            local f = addCard(page, order, 50)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -16, 0, 18); t.Position = UDim2.new(0, 12, 0, 7)
            t.BackgroundTransparency = 1; t.Text = titleText; t.TextColor3 = Color3.fromRGB(230, 235, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
            local d = Instance.new("TextLabel")
            d.Size = UDim2.new(1, -16, 0, 16); d.Position = UDim2.new(0, 12, 0, 27)
            d.BackgroundTransparency = 1; d.Text = descText or ""; d.TextColor3 = Color3.fromRGB(140, 150, 175)
            d.TextXAlignment = Enum.TextXAlignment.Left; d.Font = Enum.Font.Gotham; d.TextSize = 11
            d.TextTruncate = Enum.TextTruncate.AtEnd; d.Parent = f
            return { SetDesc = function(_, x) d.Text = x end }
        end
        local function ButtonCard(page, order, text, callback)
            local btn = Instance.new("TextButton")
            btn.LayoutOrder = order; btn.Size = UDim2.new(1, 0, 0, 42)
            btn.BackgroundColor3 = Color3.fromRGB(22, 25, 38); btn.BorderSizePixel = 0
            btn.Text = text; btn.Font = Enum.Font.GothamBold; btn.TextSize = 13
            btn.TextColor3 = Color3.fromRGB(245, 250, 255); btn.AutoButtonColor = false; btn.Parent = page
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 10)
            btn.MouseButton1Click:Connect(function()
                local ok, err = pcall(callback)
                if not ok then warn("[Kaitun GUI] " .. tostring(err)) end
            end)
            return btn
        end
        local function ToggleCard(page, order, text, default, callback)
            local f = addCard(page, order, 46)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -70, 1, 0); t.Position = UDim2.new(0, 12, 0, 0)
            t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = Color3.fromRGB(230, 235, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
            local sw = Instance.new("TextButton")
            sw.Size = UDim2.new(0, 44, 0, 22); sw.Position = UDim2.new(1, -54, 0.5, -11)
            sw.BackgroundColor3 = default and Color3.fromRGB(60, 200, 110) or Color3.fromRGB(60, 64, 82)
            sw.Text = ""; sw.AutoButtonColor = false; sw.Parent = f
            Instance.new("UICorner", sw).CornerRadius = UDim.new(1, 0)
            local state = default
            sw.MouseButton1Click:Connect(function()
                state = not state
                sw.BackgroundColor3 = state and Color3.fromRGB(60, 200, 110) or Color3.fromRGB(60, 64, 82)
                pcall(callback, state)
            end)
            return f
        end
        local function DropdownCard(page, order, text, options, default, callback)
            local f = addCard(page, order, 46)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -110, 1, 0); t.Position = UDim2.new(0, 12, 0, 0)
            t.BackgroundTransparency = 1; t.Text = text; t.TextColor3 = Color3.fromRGB(230, 235, 255)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = f
            local cur = Instance.new("TextButton")
            cur.Size = UDim2.new(0, 90, 0, 30); cur.Position = UDim2.new(1, -100, 0.5, -15)
            cur.BackgroundColor3 = Color3.fromRGB(30, 34, 50); cur.Text = default
            cur.TextColor3 = Color3.fromRGB(255, 255, 255); cur.Font = Enum.Font.GothamBold; cur.TextSize = 12
            cur.AutoButtonColor = false; cur.Parent = f
            Instance.new("UICorner", cur).CornerRadius = UDim.new(0, 7)
            local idx = 1
            for i, o in ipairs(options) do if o == default then idx = i end end
            cur.MouseButton1Click:Connect(function()
                idx = (idx % #options) + 1
                cur.Text = options[idx]
                pcall(callback, options[idx])
            end)
            return f
        end
        local function TextboxCard(page, order, placeholder, callback)
            local f = addCard(page, order, 46)
            local box = Instance.new("TextBox")
            box.Size = UDim2.new(1, -24, 1, -14); box.Position = UDim2.new(0, 12, 0, 7)
            box.BackgroundColor3 = Color3.fromRGB(14, 16, 24); box.PlaceholderText = placeholder
            box.Text = ""; box.TextColor3 = Color3.fromRGB(255, 255, 255); box.PlaceholderColor3 = Color3.fromRGB(120, 128, 150)
            box.Font = Enum.Font.Gotham; box.TextSize = 13; box.ClearTextOnFocus = false
            box.TextXAlignment = Enum.TextXAlignment.Left; box.Parent = f
            Instance.new("UICorner", box).CornerRadius = UDim.new(0, 7)
            box:GetPropertyChangedSignal("Text"):Connect(function() pcall(callback, box.Text) end)
            return box
        end

        -- PAGE: MAIN
        local mainPage = CreatePage("Main")
        local StatusValue = StatusCard(mainPage, 1)
        do
            local savedGear = Config.gear
            pcall(function()
                local y = HttpService:JSONDecode(readfile("nawy/kaitunv4.json"))
                if y and y["Choose Gear"] then savedGear = y["Choose Gear"] end
            end)
            getgenv().Config["Gear"] = savedGear; Config.gear = savedGear
            DropdownCard(mainPage, 2, "Choose Gear", { "A-B-B", "A-A-B" }, savedGear, function(v)
                getgenv().Config["Gear"] = v; Config.gear = v
                pcall(function()
                    local m = {}; pcall(function() m = HttpService:JSONDecode(readfile("nawy/kaitunv4.json")) end)
                    if type(m) ~= "table" then m = {} end
                    if not isfolder("nawy") then makefolder("nawy") end
                    m["Choose Gear"] = v; writefile("nawy/kaitunv4.json", HttpService:JSONEncode(m))
                end)
            end)
        end
        ToggleCard(mainPage, 3, "Reset After Trial", Config.resetAfterTrial, function(v)
            getgenv().Config["ResetAfterTrial"] = v; Config.resetAfterTrial = v
        end)
        TextboxCard(mainPage, 4, "Nhập Job ID...", function(text) RuntimeState.jobidinput = text end)
        ButtonCard(mainPage, 5, "Join Job Id", function()
            ReplicatedStorage:WaitForChild("__ServerBrowser", 10):InvokeServer("teleport", RuntimeState.jobidinput)
        end)
        ButtonCard(mainPage, 6, "Change Race (3000F)", function()
            local R = ReplicatedStorage.Remotes.CommF_
            R:InvokeServer("BlackbeardReward", "Reroll", "1")
            R:InvokeServer("BlackbeardReward", "Reroll", "2")
        end)
        local NetDiag = LabelCard(mainPage, 7, "🌐 Net (backend)", "đang kiểm tra…")
        local PlaceCard = LabelCard(mainPage, 8, "🆔 Place / Server", "…")
        local SyncDbg = LabelCard(mainPage, 9, "🔎 Sync Debug", "…")

        -- PAGE: STATUS
        local statusPage = CreatePage("Status")
        local mainStatusLabels = {}
        for i, name in ipairs(Config.mains) do
            mainStatusLabels[name] = LabelCard(statusPage, i, "Main " .. i .. ": " .. name, "loading...")
        end

        -- PAGE: DEBUG
        local debugPage = CreatePage("Debug")
        local function IndicatorRow(order, labelText)
            local f = addCard(debugPage, order, 30)
            local dot = Instance.new("Frame")
            dot.Size = UDim2.new(0, 12, 0, 12); dot.Position = UDim2.new(0, 12, 0.5, -6)
            dot.BackgroundColor3 = Color3.fromRGB(110, 116, 140); dot.BorderSizePixel = 0; dot.Parent = f
            Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, -36, 1, 0); t.Position = UDim2.new(0, 32, 0, 0)
            t.BackgroundTransparency = 1; t.Text = labelText; t.TextColor3 = Color3.fromRGB(220, 225, 240)
            t.TextXAlignment = Enum.TextXAlignment.Left; t.Font = Enum.Font.Gotham; t.TextSize = 12
            t.TextTruncate = Enum.TextTruncate.AtEnd; t.Parent = f
            return function(ok, txt)
                dot.BackgroundColor3 = ok and Color3.fromRGB(60, 205, 115) or Color3.fromRGB(235, 75, 85)
                if txt then t.Text = txt end
            end
        end
        local setLoop = IndicatorRow(1, "Loop")
        local setNet  = IndicatorRow(2, "Net")
        local setSrv  = IndicatorRow(3, "Server")
        local setDoor = IndicatorRow(4, "Door")
        local setMain = IndicatorRow(5, "Main stt1")

        local logSF
        do
            local box = addCard(debugPage, 6, 286)
            local hl = Instance.new("TextLabel")
            hl.Size = UDim2.new(1, -16, 0, 18); hl.Position = UDim2.new(0, 10, 0, 4)
            hl.BackgroundTransparency = 1; hl.Text = "📜 LOG (200 dòng · cuộn ↕)"
            hl.TextColor3 = Color3.fromRGB(150, 200, 255); hl.TextXAlignment = Enum.TextXAlignment.Left
            hl.Font = Enum.Font.GothamBold; hl.TextSize = 11; hl.Parent = box
            logSF = Instance.new("ScrollingFrame")
            logSF.Size = UDim2.new(1, -12, 1, -28); logSF.Position = UDim2.new(0, 6, 0, 24)
            logSF.BackgroundColor3 = Color3.fromRGB(10, 12, 18); logSF.BackgroundTransparency = 0.3
            logSF.BorderSizePixel = 0; logSF.ScrollBarThickness = 5
            logSF.ScrollBarImageColor3 = Color3.fromRGB(120, 160, 240)
            logSF.CanvasSize = UDim2.new(0, 0, 0, 0); logSF.AutomaticCanvasSize = Enum.AutomaticSize.Y; logSF.Parent = box
            Instance.new("UICorner", logSF).CornerRadius = UDim.new(0, 8)
            local lay = Instance.new("UIListLayout", logSF); lay.SortOrder = Enum.SortOrder.LayoutOrder; lay.Padding = UDim.new(0, 1)
        end
        local logLabels = {}

        selectTab("Main")
        Panel.Size = UDim2.new(0, 0, 0, 0)
        TS:Create(Panel, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
            { Size = UDim2.new(0, 320, 0, 460) }):Play()

        -- update loops (mỗi loop pcall riêng, check Runtime.alive)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.2)
                pcall(function()
                    if Diagnostics.statusnow then StatusValue.Text = Diagnostics.statusnow .. "\nPlaceId: " .. tostring(game.PlaceId) end
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(1)
                pcall(function() if Diagnostics.netDiag then NetDiag:SetDesc(Diagnostics.netDiag) end end)
                pcall(function()
                    PlaceCard:SetDesc(("PlaceId: %s | Job: %s"):format(tostring(game.PlaceId), tostring(game.JobId):sub(1, 18)))
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.5)
                pcall(function()
                    local cur = getCurrentMainBeingUpgraded()
                    local c = cur and State.statusCache[cur]
                    local me = State.isMain[State.myName] and ("MAIN" .. tostring(State.myMainIndex)) or "ALLY"
                    SyncDbg:SetDesc(("me=%s cur=%s st=%s ss=%s i=%s d=%s%s"):format(
                        me, tostring(cur):sub(1, 12), tostring(c and c.status or "?"),
                        Diagnostics.lastSameSrv and "same" or "diff", tostring(Diagnostics.lastRaceI),
                        tostring(Diagnostics.lastDoorDist and math.floor(Diagnostics.lastDoorDist) or "?"), tostring(Diagnostics.lastDoorSrc or "?")))
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(3)
                for i, name in ipairs(Config.mains) do
                    pcall(function()
                        if mainStatusLabels[name] then mainStatusLabels[name]:SetDesc("Status: " .. State.getMainStatus(name)) end
                    end)
                end
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.4)
                pcall(function()
                    local alive = RuntimeState.loopLastT and (tick() - RuntimeState.loopLastT) < 2
                    setLoop(alive == true, "Loop: " .. (alive and ("alive #" .. tostring(RuntimeState.loopTick or 0)) or "STALL!"))
                    local g, p = Diagnostics.netGetOk, Diagnostics.netPostOk
                    setNet(g and p == true, "Net: GET " .. (g and "OK" or "FAIL")
                        .. " | POST " .. (p == nil and "N/A" or (p and "OK" or "FAIL")))
                    setSrv(Diagnostics.lastSameSrv == true, "Server: " .. (Diagnostics.lastSameSrv and "SAME" or "DIFF"))
                    local atDoor = Diagnostics.lastDoorDist and Diagnostics.lastDoorDist < 150
                    setDoor(atDoor == true, "Door: d=" .. tostring(Diagnostics.lastDoorDist and math.floor(Diagnostics.lastDoorDist) or "?")
                        .. tostring(Diagnostics.lastDoorSrc or "?"))
                    local cur = getCurrentMainBeingUpgraded()
                    local c = cur and State.statusCache[cur]
                    setMain(c ~= nil, "Main1: " .. tostring(cur):sub(1, 12) .. " = " .. tostring(c and c.status or "?"))
                end)
            end
        end)
        task.spawn(function()
            while Runtime.alive do
                task.wait(0.4)
                pcall(function()
                    local present = {}
                    for _, e in ipairs(Diagnostics.dbgLog) do
                        present[e.seq] = true
                        if not logLabels[e.seq] then
                            local lb = Instance.new("TextLabel")
                            lb.Size = UDim2.new(1, -4, 0, 0); lb.AutomaticSize = Enum.AutomaticSize.Y
                            lb.BackgroundTransparency = 1; lb.LayoutOrder = e.seq
                            lb.Font = Enum.Font.Code; lb.TextSize = 11; lb.TextWrapped = true
                            lb.TextXAlignment = Enum.TextXAlignment.Left; lb.Text = e.text
                            lb.TextColor3 = (e.level == "ok" and Color3.fromRGB(80, 210, 120))
                                or (e.level == "err" and Color3.fromRGB(235, 80, 90))
                                or Color3.fromRGB(190, 198, 215)
                            lb.Parent = logSF
                            logLabels[e.seq] = lb
                        end
                    end
                    for seq, lb in pairs(logLabels) do
                        if not present[seq] then lb:Destroy(); logLabels[seq] = nil end
                    end
                    local nb = logSF.CanvasPosition.Y >= (logSF.AbsoluteCanvasSize.Y - logSF.AbsoluteWindowSize.Y - 24)
                    if nb then logSF.CanvasPosition = Vector2.new(0, logSF.AbsoluteCanvasSize.Y) end
                end)
            end
        end)
    end)
    if not okUI then
        Logger.warn("UIManager: build GUI fail → chạy text-only (Diagnostics.fullStatus / Diagnostics.dbgLog).", "ui_fail")
    end
end

--[[ ============================================================================
 [32] STARTUP — init + start mọi module (chống start trùng). (File A: rải toàn file)
============================================================================ ]]
if not Runtime._started then
    Runtime._started = true
    _G[State.myName] = true

    -- Helper: start module an toàn — 1 module lỗi KHÔNG được kéo sập cả startup (root cause "không load").
    local function safeStart(label, fn)
        if Runtime.startedModules[label] then return true end
        local ok, err = Safe.call("boot_" .. label, fn)
        if ok then
            Runtime.startedModules[label] = true
            return true
        end
        if Net and Net.log then
            pcall(function() Net.log("ERR", "startup '" .. label .. "' lỗi: " .. tostring(err)) end)
        end
        return false
    end

    -- ========== ƯU TIÊN 1: THỨ NGƯỜI DÙNG THẤY — chạy TRƯỚC, KHÔNG phụ thuộc network ==========
    -- Trước đây ServerSync.init() (HTTP retry 8 lần, block ~8-10s / throw) chạy ĐẦU → nếu chậm/lỗi thì
    -- UI + choose team + main loop phía dưới KHÔNG BAO GIỜ chạy → "không load UI, không chọn team, không load script".
    -- Giờ: UI + TeamManager lên trước, vô điều kiện; init đẩy xuống thread nền.
    safeStart("ui", UIManager.start)                 -- UI hiện ngay (kể cả khi mọi thứ khác fail)
    safeStart("ui_recovery", startUIRecoveryLoop)
    safeStart("team", TeamManager.start)             -- chọn team ngay (có recovery loop riêng)
    safeStart("sea", SeaManager.start)

    -- ========== ƯU TIÊN 2: NETWORK / ROLE — chạy NỀN, không block UI/team ==========
    task.spawn(function()
        safeStart("markVisited", function() TeleportManager.markVisited(game.JobId) end)
        safeStart("serversync_init", ServerSync.init)       -- /init retry 8 lần → nền, không treo startup
        safeStart("warmers", ServerSync.startWarmers)
        safeStart("netprobe", ServerSync.startNetProbe)
        safeStart("noguchi", startNoguchiLoop)
        safeStart("ability_sync", AbilitySync.startLoops)
    end)

    -- ========== ƯU TIÊN 3: WORLD / COMBAT / VÒNG CHÍNH ==========
    safeStart("noclip", function() Movement.enableNoclip("return true") end)
    safeStart("spam_skills", CombatActions.startSpamSkills)
    safeStart("fast_attack", CombatActions.startFastAttack)
    safeStart("v3_combat_watch", CombatActions.startV3CombatWatch)  -- V3 attack/gom quái (chỉ dùng khi training)
    safeStart("haki", CombatActions.startHakiLoop)
    safeStart("mainrace", MainRaceReroll.start)            -- self-check/reroll đến đúng target mới dừng
    safeStart("ally_train_gate", AllyTrainingGate.start)
    safeStart("ally_fm_watch", AllyFullMoonWatch.start)  -- loop nền Ally1/Ally2 canh hết full moon
    safeStart("ally_gear_loop", AllyGearLoop.start)      -- loop nền gear5 unspend cho ally (8s/lần)
    safeStart("temple_dontpull_check", TempleDontPullCheck.start) -- worker riêng: 5 lần, cách 2s; chỉ lần 5=false mới ghi marker
    safeStart("main_loop", MainLoop.start)               -- vòng chính — LUÔN chạy dù init nền chưa xong

    Logger.ok("KaitunV4 bản 2 (modular, port từ File A) khởi động xong. role=" .. tostring(State.myRole))
end
