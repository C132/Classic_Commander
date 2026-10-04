-- Commander Oracle UI smoke (luajit) — the live half: reading the map's area
-- POIs and the client's resource widget, and everything the board draws from
-- them. Loads the REAL Commander_Events framework and the REAL Oracle files
-- under a client mock. Mock modeled on Commander_Adjutant/Harness.
--
--   luajit Commander_Oracle/Harness/oracle_ui_smoke.lua

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local now = 1000
function GetTime() return now end
function time() return 1000000 + now end
function GetBuildInfo() return "2.5.6", "69546", "Aug 28 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local harnessErrors = {}
function geterrorhandler()
    return function(err) harnessErrors[#harnessErrors + 1] = tostring(err) end
end

local NUMERIC_GETTERS = {
    GetHeight = 0, GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2,
    GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetStringWidth = 10, GetStringHeight = 12, GetID = 1, GetNumPoints = 1,
}

local function IsMethodName(key)
    return type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock"))
end

local eventRegistry = {}
local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if key == "GetHeight" then
        local fn = function(s) return s.__h or 0 end
        rawset(self, key, fn); return fn
    end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn); return fn
    end
    if key == "SetHeight" then
        local fn = function(s, h) s.__h = h end
        rawset(self, key, fn); return fn
    end
    if key == "GetWidth" then
        local fn = function(s) return s.__w or 0 end
        rawset(self, key, fn); return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
        rawset(self, key, fn); return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
        rawset(self, key, fn); return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = {} end
        rawset(self, key, fn); return fn
    end
    -- Attributes are stored for real: the whole click-to-target feature is a
    -- macrotext string, and a mock that swallowed it would test nothing
    if key == "SetAttribute" then
        local fn = function(s, name, value)
            s.__attrs = s.__attrs or {}
            s.__attrs[name] = value
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetAttribute" then
        local fn = function(s, name) return s.__attrs and s.__attrs[name] end
        rawset(self, key, fn); return fn
    end
    if key == "IsProtected" then
        -- True for anything built from a secure template, and for anything
        -- carrying one: the engine walks up from the secure button
        local fn = function(s)
            if s.__template and s.__template:find("Secure") then return true end
            for _, child in ipairs(s.__children or {}) do
                if child:IsProtected() then return true end
            end
            return false
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn); return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text end
        rawset(self, key, fn); return fn
    end
    if key == "SetTextColor" or key == "SetColorTexture" or key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn); return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn); return fn
    end
    if key == "GetAlpha" then
        local fn = function(s) return s.__alpha or 1 end
        rawset(self, key, fn); return fn
    end
    if key == "Show" then
        local fn = function(s) s.__shown = true end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s) s.__shown = false end
        rawset(self, key, fn); return fn
    end
    if key == "SetShown" then
        local fn = function(s, shown) s.__shown = not not shown end
        rawset(self, key, fn); return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn); return fn
    end
    if key == "SetEnabled" then
        local fn = function(s, enabled) s.__enabled = not not enabled end
        rawset(self, key, fn); return fn
    end
    if key == "IsEnabled" then
        local fn = function(s) return s.__enabled ~= false end
        rawset(self, key, fn); return fn
    end
    if key == "CreateTexture" then
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "CreateFontString" then
        local fn = function(s)
            local t = NewWidget("FontString")
            t.__parent = s
            s.__fontStrings = s.__fontStrings or {}
            s.__fontStrings[#s.__fontStrings + 1] = t
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "SetFontObject" then
        local fn = function(s, object) s.__fontObject = object; s.__fontFlags = nil end
        rawset(self, key, fn); return fn
    end
    if key == "GetFont" then
        local fn = function(s) return "Fonts\\ARIALN.TTF", 10, s.__fontFlags end
        rawset(self, key, fn); return fn
    end
    if key == "SetFont" then
        local fn = function(s, file, size, flags) s.__fontFlags = flags end
        rawset(self, key, fn); return fn
    end
    if key == "SetScript" or key == "HookScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn); return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn); return fn
    end
    if key == "RegisterEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn); return fn
    end
    if key == "UnregisterEvent" then
        local fn = function(s, event)
            local list = eventRegistry[event]
            if list then
                for i = #list, 1, -1 do
                    if list[i] == s then table.remove(list, i) end
                end
            end
        end
        rawset(self, key, fn); return fn
    end
    if IsMethodName(key) then
        local fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true,
        __children = {} }, WidgetMT)
end

local allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    -- Parents remember their children so IsProtected can walk the tree the
    -- way the engine does
    if parent and parent.__children then
        parent.__children[#parent.__children + 1] = f
    end
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalSmall = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
BACKDROP_SLIDER_8_8 = {}

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2, RAID_WARNING = 8959 }
local playedSounds = {}
function PlaySound(kit) playedSounds[#playedSounds + 1] = kit end

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

local timers, tickers = {}, {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn, nextAt = now + interval, cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        tickers[#tickers + 1] = t
        return t
    end,
}

function UIDropDownMenu_Initialize() end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton() end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu() end
SlashCmdList = {}

C_EventUtils = { IsEventValid = function() return true end }
Enum = { UIWidgetVisualizationType = { IconAndText = 0, CaptureBar = 1, DoubleStatusBar = 2 } }

-- ---------------------------------------------------------------------------
-- The battleground mock: the two things Oracle actually reads
-- ---------------------------------------------------------------------------

local zone = { inBasin = false, pvp = false, arena = false }
function GetInstanceInfo()
    if zone.arena then return "Nagrand Arena", "arena", 0, "", 5, 0, false, 559, 5 end
    if zone.inBasin then return "Arathi Basin", "pvp", 0, "", 30, 0, false, 529, 30 end
    -- A battleground that is NOT Arathi: the roster tabs work here, the
    -- projection must not
    if zone.pvp then return "Warsong Gulch", "pvp", 0, "", 10, 0, false, 489, 10 end
    return "Elwynn Forest", "none", 0, "", 0, 0, false, 0, 0
end
C_Map = { GetBestMapForUnit = function()
    if zone.inBasin then return 1461 end
    return zone.pvp and 1339 or 1429
end }

-- ---------------------------------------------------------------------------
-- The battlefield scoreboard mock
--
-- The shape the client hands back, in the order Blizzard's own TBC
-- WorldStateFrame.lua unpacks it: name, killingBlows, honorableKills, deaths,
-- honorGained, faction, rank, race, class, classToken, damageDone,
-- healingDone -- with faction 0 = Horde and 1 = Alliance. Getting either the
-- ORDER or the faction numbering wrong is silent and total, which is why the
-- mock speaks the client's shape rather than a convenient one.
-- ---------------------------------------------------------------------------
local scoreRows, scoreColumns = {}, {}
local scoreRequests = 0
function RequestBattlefieldScoreData() scoreRequests = scoreRequests + 1 end
function GetNumBattlefieldScores() return #scoreRows end
function GetBattlefieldScore(index)
    local row = scoreRows[index]
    if not row then return nil end
    return row.name, row.kb or 0, row.hk or 0, row.deaths or 0, row.honor or 0,
        row.faction, 0, "Human", "Warrior", row.classToken, row.dmg or 0, row.heal or 0
end
function GetNumBattlefieldStats() return #scoreColumns end
function GetBattlefieldStatInfo(index) return scoreColumns[index], "", "" end
function GetBattlefieldStatData(playerIndex, column)
    local row = scoreRows[playerIndex]
    return (row and row.obj and row.obj[column]) or 0
end
function GetBattlefieldInstanceRunTime() return 480000 end

local playerFaction = "Alliance"
function UnitFactionGroup() return playerFaction, playerFaction end

local groupped = true
local chatLog = {}
LE_PARTY_CATEGORY_INSTANCE = 2
function IsInGroup(category) return groupped and category == LE_PARTY_CATEGORY_INSTANCE end
function SendChatMessage(msg, channel) chatLog[#chatLog + 1] = { msg = msg, channel = channel } end

-- The map hands back exactly one POI per node — whichever of its five states
-- is live. This mock is the honest part of the file: it speaks the same shape.
local livePOIs = {}
C_AreaPoiInfo = {
    GetAreaPOIForMap = function(uiMapID)
        if uiMapID ~= 1461 or not zone.inBasin then return {} end
        return livePOIs
    end,
    GetAreaPOIInfo = function() return nil end,
}

-- The resource widgets, in the shape a live Arathi Basin actually reports
-- them (verified 2026-09-06): TWO IconAndText widgets, one per faction, each
-- reading "Bases: 1  Resources: 20/2000". `left`/`right` are the client's own
-- line order, which the addon is not allowed to assume is Alliance-then-Horde.
local widgetScores = { left = nil, right = nil }
local widgetBases = { left = nil, right = nil }
widgetCap = 2000
-- Set to true to serve the retail DoubleStatusBar shape instead, exercising
-- the fallback path.
local widgetUseBars = false

-- ---------------------------------------------------------------------------
-- The world the range reader looks at
--
-- Honest about the client's actual asymmetry: UnitPosition answers for the
-- raid you are in and returns nothing for anybody else, which is exactly why
-- an enemy can only ever be given a bound.
-- ---------------------------------------------------------------------------
local combat = false
function InCombatLockdown() return combat end

local world = {}          -- name -> { token, x, y, near, position }
local tokenOwner = {}     -- token -> name
local currentTarget = nil

local function PlaceUnit(name, token, spec)
    spec = spec or {}
    world[name] = spec
    spec.token = token
    tokenOwner[token] = name
end

function UnitExists(token) return tokenOwner[token] ~= nil end
function UnitName(token)
    local name = tokenOwner[token]
    if not name then return nil end
    local base, realm = name:match("^([^%-]+)%-?(.*)$")
    return base, (realm ~= "" and realm or nil)
end
function UnitIsUnit(a, b) return a == b or (tokenOwner[a] and tokenOwner[a] == tokenOwner[b]) end
function UnitPosition(token)
    local spec = world[tokenOwner[token] or ""]
    -- The client answers for group members only
    if not (spec and spec.position) then return nil end
    return spec.y, spec.x, 0, 1
end
-- The raid, and the eight icons it can carry. SetRaidTarget is logged as well
-- as applied: "did not re-issue a mark it had already placed" is a real
-- requirement and only the call log can tell.
local raidMarks, markCalls = {}, {}
local isLeader, isAssistant = false, false
function UnitIsGroupLeader(unit) return unit == "player" and isLeader end
function UnitIsGroupAssistant(unit) return unit == "player" and isAssistant end
function CanBeRaidTarget(token) return tokenOwner[token] ~= nil end
function UnitClass(token)
    local spec = world[tokenOwner[token or ""] or ""]
    local class = (spec and spec.class) or "WARRIOR"
    return class:sub(1, 1) .. class:sub(2):lower(), class
end
function GetRaidTargetIndex(token) return raidMarks[token] end
function SetRaidTarget(token, index)
    markCalls[#markCalls + 1] = { token = token, index = index }
    raidMarks[token] = (index ~= 0) and index or nil
end

-- CheckInteractDistance is deliberately NOT mocked. It is PROTECTED on this
-- client (2.5.6): calling it from addon code raises ADDON_ACTION_BLOCKED and
-- returns nothing. A mock that answered it would prove a range path the game
-- will never run -- which is exactly what this harness used to do, while the
-- live client logged ten blocked calls a refresh.

local function LineText(score, bases)
    if bases then
        return string.format("Bases: %d  Resources: %d/%d", bases, score, widgetCap)
    end
    return string.format("Resources: %d/%d", score, widgetCap)
end

C_UIWidgetManager = {
    GetTopCenterWidgetSetID = function() return 1 end,
    GetBelowMinimapWidgetSetID = function() return 2 end,
    GetObjectiveTrackerWidgetSetID = function() return 3 end,
    GetAllWidgetsBySetID = function(setID)
        if setID ~= 1 or not widgetScores.left then return {} end
        if widgetUseBars then return { { widgetID = 42, widgetType = 2 } } end
        return {
            { widgetID = 11, widgetType = 0, orderIndex = 1 },
            { widgetID = 12, widgetType = 0, orderIndex = 2 },
        }
    end,
    GetIconAndTextWidgetVisualizationInfo = function(widgetID)
        if not widgetScores.left or widgetUseBars then return nil end
        if widgetID == 11 then return { text = LineText(widgetScores.left, widgetBases.left) } end
        if widgetID == 12 then return { text = LineText(widgetScores.right, widgetBases.right) } end
        return nil
    end,
    GetDoubleStatusBarWidgetVisualizationInfo = function(widgetID)
        if widgetID ~= 42 or not widgetScores.left or not widgetUseBars then return nil end
        return {
            leftBarValue = widgetScores.left, leftBarMin = 0, leftBarMax = widgetCap,
            rightBarValue = widgetScores.right, rightBarMin = 0, rightBarMax = widgetCap,
        }
    end,
}

-- ===========================================================================
-- Load
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, frame in ipairs(snap) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function Advance(seconds, step)
    step = step or 0.25
    local left = seconds
    while left > 0 do
        local dt = math.min(step, left)
        now = now + dt
        left = left - dt
        for _, frame in ipairs(allFrames) do
            local handler = frame.__scripts.OnUpdate
            if handler then handler(frame, dt) end
        end
        for _, t in ipairs(timers) do
            if not t.done and t.at <= now then t.done = true; t.fn() end
        end
        for _, t in ipairs(tickers) do
            while not t.cancelled and t.nextAt <= now do
                t.nextAt = t.nextAt + t.interval
                t.fn()
            end
        end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Oracle/CommanderOracleData.lua")
Load(ADDONS .. "/Commander_Oracle/CommanderOracleEngine.lua")
Load(ADDONS .. "/Commander_Oracle/CommanderOracleRoster.lua")
Load(ADDONS .. "/Commander_Oracle/CommanderOracleDB.lua")
-- Mutation hook: ORACLE_RUNTIME=/path of a copy of CommanderOracle.lua
Load(os.getenv("ORACLE_RUNTIME") or (ADDONS .. "/Commander_Oracle/CommanderOracle.lua"))
Fire("ADDON_LOADED", "Commander_Oracle")
Fire("PLAYER_LOGIN")

local AB = CommanderOracle_AB
local UIx = CommanderOracle_Sections
local db = CommanderOracleDB

-- Sections A-L below exercise Full density (bars, one ladder row per rung).
-- Compact, Minimal and the no-backdrop text treatment get their own sections
-- at the end, against the shipped defaults.
db.Density = "FULL"

-- Set the board from a plain description, the way the map would report it.
local STATE_KEY = { A = "alliance", H = "horde", a = "conAlliance", h = "conHorde", o = "none" }
-- The board, and with it the base counts the client's own resource lines
-- report — the server derives both from the same place, and Oracle resolves
-- which line is which faction by matching them.
local function SetBoard(spec, swapLines)
    livePOIs = {}
    local alliance, horde = 0, 0
    for index, letter in ipairs(spec) do
        livePOIs[#livePOIs + 1] = AB.nodes[index].poi[STATE_KEY[letter]]
        if letter == "A" then alliance = alliance + 1 end
        if letter == "H" then horde = horde + 1 end
    end
    if swapLines then
        widgetBases.left, widgetBases.right = horde, alliance
    else
        widgetBases.left, widgetBases.right = alliance, horde
    end
end

-- Leaving is only committed after a grace period (see below), so a test that
-- means "we are out" has to wait it out.
local function LeaveBasin()
    zone.inBasin = false
    Fire("PLAYER_ENTERING_WORLD")
    Advance(12)
end

local function CommsButton(key)
    for _, button in ipairs(UIx.comms.buttons) do
        if button.spec.key == key then return button end
    end
end

local function ClickComms(key)
    local button = CommsButton(key)
    button.__scripts.OnClick(button, "LeftButton")
end

local function CommsTooltip(key)
    local button = CommsButton(key)
    GameTooltip.__lines = {}
    button.__scripts.OnEnter(button)
    return button
end

local function VerdictText() return UIx.verdict.headline:GetText() end
local function VerdictDetail() return UIx.verdict.detail:GetText() end
local function CallText() return UIx.call.text:GetText() end
local function LadderRow(n)
    for _, row in ipairs(UIx.ladder.rows) do
        if row.bases:GetText() == tostring(n) then return row end
    end
end

-- ---------------------------------------------------------------------------
-- A: it loads, and it stays out of the way outside a battleground
-- ---------------------------------------------------------------------------
CHECK(#harnessErrors == 0, "A: loads clean", harnessErrors[1])
CHECK(UIx.frame ~= nil, "A: the board exists")
CHECK(db.EnableOracle == true, "A: defaults applied")

Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(not UIx.frame:IsShown(), "A: standing in Elwynn, the board stays down")

-- ---------------------------------------------------------------------------
-- B: entering Arathi Basin
-- ---------------------------------------------------------------------------
zone.inBasin = true
SetBoard({ "A", "A", "H", "H", "o" })       -- 2 to us, 2 to them, farm open
widgetScores.left, widgetScores.right = 1000, 1000
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(UIx.frame:IsShown(), "B: the board comes up in Arathi Basin")
CHECK(VerdictText() == "DEAD HEAT", "B: two bases each on level resources is a dead heat", VerdictText())

-- The race reads us first, whichever side we are
CHECK(UIx.race.top.label:GetText() == "Alliance  2", "B: our row on top with our base count",
    UIx.race.top.label:GetText())
CHECK(UIx.race.bottom.label:GetText() == "Horde  2", "B: theirs under it", UIx.race.bottom.label:GetText())
CHECK(UIx.race.top.value:GetText() == "1000", "B: and the real resource number", UIx.race.top.value:GetText())

-- Releasing to the graveyard reports the player OUTSIDE the instance for a
-- moment. Taking that at face value would throw away the contested clocks and
-- the carried score on every death, so the exit has to hold before it counts.
Advance(10)
local heldScore = UIx.race.top.value:GetText()
zone.inBasin = false
Fire("PLAYER_ENTERING_WORLD")
Advance(2)
CHECK(UIx.frame:IsShown(), "B: a death-release blip does not tear the board down")
CHECK(UIx.race.top.value:GetText() == heldScore, "B: nor throw the match state away",
    UIx.race.top.value:GetText())
zone.inBasin = true
Fire("PLAYER_ENTERING_WORLD")
Advance(0.5)
CHECK(UIx.frame:IsShown(), "B: and coming back is seamless")

-- ---------------------------------------------------------------------------
-- C: a base changes hands and the answer changes with it
-- ---------------------------------------------------------------------------
SetBoard({ "A", "A", "A", "H", "o" })       -- we take the blacksmith: 3 to 1
Fire("AREA_POIS_UPDATED")
Advance(0.5)
CHECK(VerdictText():match("^WIN BY"), "C: three to one is a win", VerdictText())
-- 1000 left at 3 bases = 600s; they bank 1000 + 600*(10/12) = 1500, so 500 clear
CHECK(VerdictText() == "WIN BY 500", "C: by 500", VerdictText())
CHECK(VerdictDetail() == "ends in 10:00", "C: in ten minutes", VerdictDetail())

-- ...and the swing alert fires, because the ANSWER moved, not the score
CHECK(#playedSounds > 0, "C: the swing raised a sound")
local soundsBefore = #playedSounds
Advance(2)
CHECK(#playedSounds == soundsBefore, "C: and does not keep firing while the answer holds")

-- ---------------------------------------------------------------------------
-- D: the win-condition ladder
-- ---------------------------------------------------------------------------
CHECK(LadderRow(5) and LadderRow(0), "D: every hold has a row")
-- The ladder prices the WORST case: every row assumes the enemy takes every
-- base we do not hold. So it reads 333 (3 vs 2) where the headline reads 500
-- (3 vs 1, because the farm is still neutral and paying nobody). Both are
-- right, and the difference is the point of having both.
CHECK(LadderRow(3).outcome:GetText() == "win by 333", "D: three guarantees a win by 333",
    LadderRow(3).outcome:GetText())
CHECK(UIx.ladder.header:GetText():match("they take the rest"),
    "D: and the header says out loud what the rows assume", UIx.ladder.header:GetText())
CHECK(LadderRow(3).marker:IsShown(), "D: and three is the row we are standing on")
CHECK(not LadderRow(2).marker:IsShown(), "D: the others are not marked")
CHECK(LadderRow(2).outcome:GetText():match("^loss by"), "D: dropping to two would lose it",
    LadderRow(2).outcome:GetText())
CHECK(LadderRow(3).alpha ~= 0, "D: rows are drawn")
CHECK(LadderRow(3).outcome:GetAlpha() == 1 and LadderRow(2).outcome:GetAlpha() < 1,
    "D: the row we are on reads at full strength, the alternatives do not")

-- The call names the least we can hold, and how much slack that leaves
CHECK(CallText() == "HOLD 3. You can lose 0 and still win." or CallText():match("^HOLD"),
    "D: the call is a hold", CallText())

-- ---------------------------------------------------------------------------
-- E: a flag in flight pays nobody, and carries a real clock
-- ---------------------------------------------------------------------------
SetBoard({ "A", "A", "h", "H", "o" })       -- they click the blacksmith
Fire("AREA_POIS_UPDATED")
Advance(0.5)
CHECK(UIx.race.top.label:GetText() == "Alliance  2", "E: a contested node stops counting for us",
    UIx.race.top.label:GetText())
CHECK(UIx.nodes.pips[3].timer:GetText() == "60s" or UIx.nodes.pips[3].timer:GetText() == "59s",
    "E: and starts a sixty second clock", UIx.nodes.pips[3].timer:GetText())
CHECK(not UIx.nodes.pips[3].timer:GetText():match("~"),
    "E: exact, because we watched it start", UIx.nodes.pips[3].timer:GetText())
Advance(20)
local ticking = tonumber(UIx.nodes.pips[3].timer:GetText():match("(%d+)"))
CHECK(ticking and ticking >= 39 and ticking <= 41, "E: and it counts down", ticking)

-- The projection says where this is going if nobody turns it around
CHECK(VerdictDetail():match("flags in flight") or VerdictText():match("LOSS"),
    "E: the board says the flag in flight changes the answer", VerdictDetail())

-- Walking in on a flag already ticking gives an upper bound, and says so
SetBoard({ "A", "A", "H", "H", "o" })
Fire("AREA_POIS_UPDATED")
Advance(0.5)
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "h", "H", "o" })
Fire("PLAYER_ENTERING_WORLD")
Advance(0.5)
CHECK(UIx.nodes.pips[3].timer:GetText():match("^~"),
    "E: a flag we did not see start is marked as an upper bound",
    UIx.nodes.pips[3].timer:GetText())

-- ---------------------------------------------------------------------------
-- F: which of the client's two resource lines is ours
-- ---------------------------------------------------------------------------
-- The client lists its two lines in an order nothing documents as
-- Alliance-first, so Oracle settles it by arithmetic rather than by reading
-- text: each line states how many bases its side holds, and the map already
-- said exactly how many each faction holds. Feed the lines SWAPPED and it has
-- to resolve on the FIRST read — not after a minute of watching them climb.
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "A", "A", "H" }, true)         -- Horde line first
widgetScores.left, widgetScores.right = 300, 900     -- so 900 is ours
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(UIx.race.top.value:GetText() == "900",
    "F: swapped lines are matched by base count, immediately", UIx.race.top.value:GetText())
CHECK(UIx.race.bottom.value:GetText() == "300", "F: and theirs is the other one",
    UIx.race.bottom.value:GetText())

-- The straight order resolves just as directly
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "A", "A", "H" })                -- Alliance line first
widgetScores.left, widgetScores.right = 900, 300
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(UIx.race.top.value:GetText() == "900", "F: straight order needs no correction",
    UIx.race.top.value:GetText())

-- Equal base counts cannot name the sides — a resolution already made has to
-- hold rather than flapping back to a guess
SetBoard({ "A", "A", "H", "H", "o" })
widgetScores.left, widgetScores.right = 1000, 800
Fire("AREA_POIS_UPDATED")
Advance(1)
CHECK(UIx.race.top.value:GetText() == "1000", "F: an ambiguous board keeps the answer it had",
    UIx.race.top.value:GetText())

-- And the manual override beats the arithmetic
SetBoard({ "A", "A", "A", "A", "H" }, true)
widgetScores.left, widgetScores.right = 300, 900
Fire("AREA_POIS_UPDATED")
Advance(1)
CHECK(UIx.race.top.value:GetText() == "900", "F: auto still has it right")
db.ScoreBars = "LEFT_ALLIANCE"
Advance(1)
CHECK(UIx.race.top.value:GetText() == "300", "F: setting it by hand overrules auto",
    UIx.race.top.value:GetText())
db.ScoreBars = "AUTO"

-- A line with no base count in it still yields its resources; only the
-- side-matching goes quiet
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "A", "H", "H" })
widgetBases.left, widgetBases.right = nil, nil
widgetScores.left, widgetScores.right = 1200, 400
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(UIx.race.top.value:GetText() == "1200", "F: text without a base count still parses",
    UIx.race.top.value:GetText())

-- The retail DoubleStatusBar shape is kept as a fallback and must still work
LeaveBasin()
widgetUseBars = true
zone.inBasin = true
SetBoard({ "A", "A", "A", "H", "H" })
widgetScores.left, widgetScores.right = 1100, 500
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(UIx.race.top.value:GetText() == "1100", "F: the DoubleStatusBar fallback still reads",
    UIx.race.top.value:GetText())
widgetUseBars = false

-- ---------------------------------------------------------------------------
-- G: the widget going quiet
-- ---------------------------------------------------------------------------
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "A", "H", "H" })
widgetScores.left, widgetScores.right = 900, 800
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(not VerdictDetail():match("estimated"), "G: a live widget is not estimated", VerdictDetail())
local carriedFrom = tonumber(UIx.race.top.value:GetText())
widgetScores.left, widgetScores.right = nil, nil
Advance(20)
CHECK(VerdictDetail():match("estimated"), "G: a silent widget is carried forward and SAID to be",
    VerdictDetail())
local carriedTo = tonumber(UIx.race.top.value:GetText())
CHECK(carriedTo > carriedFrom, "G: and the carry actually advances the score",
    carriedFrom .. " -> " .. carriedTo)
-- Three bases for ~20s is 20 * 10/6 = 33 resources
CHECK(math.abs((carriedTo - carriedFrom) - 20 * (10 / 6)) < 6,
    "G: at the income the map says we have", carriedTo - carriedFrom)

-- ---------------------------------------------------------------------------
-- H: the call, in each of its three shapes
-- ---------------------------------------------------------------------------
widgetScores.left, widgetScores.right = 1000, 1000

-- On a five-cap the call still says HOLD 3, and that is the useful answer:
-- holding five does not mean you can afford to drop to one, because the two
-- you drop go straight to them. What five buys you is slack, and the call
-- prices the slack.
SetBoard({ "A", "A", "A", "A", "A" })       -- five-cap
Fire("AREA_POIS_UPDATED"); Advance(0.5)
CHECK(CallText() == "HOLD 3. You can lose 2 and still win.",
    "H: a five-cap is priced as three plus two to spare", CallText())

SetBoard({ "A", "A", "A", "H", "H" })       -- exactly enough
Fire("AREA_POIS_UPDATED"); Advance(0.5)
CHECK(CallText() == "HOLD ALL 3. Losing one loses the game.", "H: three of five is the whole margin",
    CallText())

SetBoard({ "A", "A", "H", "H", "H" })       -- short
Fire("AREA_POIS_UPDATED"); Advance(0.5)
CHECK(CallText():match("^TAKE 1 MORE"), "H: two of five needs one more", CallText())
CHECK(CallText():match("within %d+:%d%d"), "H: and says how long there is left to get it", CallText())

-- The opening-minutes case, taken from a live game: we are AHEAD on the board
-- (two bases to their one, two more flags ticking) but the worst case still
-- wants three, and because we currently out-earn them the algebra honestly
-- answers "you have two hours". That is a real answer to a question nobody is
-- asking, and on screen a 122:23 clock just reads as broken — so the deadline
-- is only shown when it lands before the game is otherwise decided.
widgetScores.left, widgetScores.right = 50, 20
SetBoard({ "A", "A", "h", "h", "H" })
Fire("AREA_POIS_UPDATED"); Advance(0.5)
CHECK(CallText():match("^TAKE 1 MORE"), "H: an opening board still names the hold", CallText())
CHECK(not CallText():match("within"),
    "H: but reports no deadline while a whole game is left to play", CallText())
CHECK(CallText() == "TAKE 1 MORE. Nothing less wins.", "H: it just states the requirement",
    CallText())
-- ...and once the same requirement DOES become urgent, the clock is back
widgetScores.left, widgetScores.right = 900, 1300
SetBoard({ "A", "A", "H", "H", "H" })
Fire("AREA_POIS_UPDATED"); Advance(0.5)
CHECK(CallText():match("within %d+:%d%d"), "H: a deadline inside the game is reported",
    CallText())
widgetScores.left, widgetScores.right = 1000, 1000

-- ---------------------------------------------------------------------------
-- I2: the cap comes from the server, not from our table
-- ---------------------------------------------------------------------------
CHECK(AB.maxScore == 2000, "I2: TBC canon to start with", AB.maxScore)
widgetCap = 1600
Advance(1)
CHECK(AB.maxScore == 1600, "I2: a server running a different cap is believed", AB.maxScore)
CHECK(UIx.race.top.label ~= nil, "I2: and the board keeps drawing")
-- ...and every projection moves with it
SetBoard({ "A", "A", "A", "H", "H" })
widgetScores.left, widgetScores.right = 1000, 1000
Fire("AREA_POIS_UPDATED"); Advance(0.5)
local at1600 = VerdictText()
widgetCap = 2000
Advance(1)
Fire("AREA_POIS_UPDATED"); Advance(0.5)
CHECK(VerdictText() ~= at1600, "I2: the verdict is measured against that cap, not a constant",
    at1600 .. " / " .. VerdictText())
CHECK(AB.maxScore == 2000, "I2: and back again", AB.maxScore)

-- ---------------------------------------------------------------------------
-- I: sections switch off and the board shrinks to fit
-- ---------------------------------------------------------------------------
local fullHeight = UIx.frame:GetHeight()
db.ShowLadder = false
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
CHECK(not UIx.ladder:IsShown(), "I: the ladder goes away when switched off")
CHECK(UIx.frame:GetHeight() < fullHeight, "I: and the board shrinks rather than leaving a hole",
    UIx.frame:GetHeight() .. " vs " .. fullHeight)
db.ShowLadder = true
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
CHECK(UIx.frame:GetHeight() == fullHeight, "I: and comes back the same size", UIx.frame:GetHeight())

-- ---------------------------------------------------------------------------
-- J: talking to the group — manual only
-- ---------------------------------------------------------------------------
local chatBefore = #chatLog
Advance(30)
CHECK(#chatLog == chatBefore, "J: Oracle says nothing to anyone on its own")
CommanderOracle_Call()
CHECK(#chatLog == chatBefore + 1, "J: and speaks when asked")
CHECK(chatLog[#chatLog].channel == "INSTANCE_CHAT",
    "J: through the instance channel, not RAID", chatLog[#chatLog].channel)
CHECK(chatLog[#chatLog].msg:match("^%[Oracle%]"), "J: labelled", chatLog[#chatLog].msg)
CHECK(chatLog[#chatLog].msg:match("TAKE") or chatLog[#chatLog].msg:match("HOLD"),
    "J: and carries the call, not just the score", chatLog[#chatLog].msg)

-- ---------------------------------------------------------------------------
-- K: the demo and the probe
-- ---------------------------------------------------------------------------
CommanderOracle_Probe()
CHECK(#harnessErrors == 0, "K: the probe does not throw", harnessErrors[1])
local probed = false
for _, line in ipairs(printLog) do
    if line:match("Oracle probe:.*widgets.*map POIs") then probed = true end
end
CHECK(probed, "K: and reports what the client is showing")

LeaveBasin()
CHECK(not UIx.frame:IsShown(), "K: leaving the battleground puts the board away")
CommanderOracle_Test()
Advance(0.5)
CHECK(UIx.frame:IsShown(), "K: the demo puts it back up outside a battleground")
CHECK(VerdictText():match("WIN BY"), "K: on a worked position", VerdictText())
Advance(31)
CHECK(not UIx.frame:IsShown(), "K: and the demo clears itself")

-- ---------------------------------------------------------------------------
-- L: the master switch, and the unlocked placeholder
-- ---------------------------------------------------------------------------
zone.inBasin = true
SetBoard({ "A", "A", "A", "H", "H" })
widgetScores.left, widgetScores.right = 1000, 1000
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(UIx.frame:IsShown(), "L: back up in a battleground")
db.EnableOracle = false
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
CHECK(not UIx.frame:IsShown(), "L: the master switch takes it down")
db.EnableOracle = true
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)

LeaveBasin()
db.BoardLocked = false
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
CHECK(UIx.frame:IsShown(), "L: unlocked, it stays on screen to be dragged")
db.BoardLocked = true
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
CHECK(not UIx.frame:IsShown(), "L: locking it again puts it away")

-- ---------------------------------------------------------------------------
-- M: the shipped defaults — compact, and readable with no backdrop
-- ---------------------------------------------------------------------------
Commander.UI.ResetToDefaults(db, {})   -- (no-op; defaults are already applied)
db.Density = "COMPACT"
db.BoardLocked = true
db.TextOutline = true
zone.inBasin = true
SetBoard({ "A", "A", "A", "H", "H" })
widgetScores.left, widgetScores.right = 1000, 1000
Fire("PLAYER_ENTERING_WORLD")
Advance(1)

CHECK(UIx.frame:IsShown(), "M: compact board comes up")
local compactHeight = UIx.frame:GetHeight()
db.Density = "FULL"
Advance(0.5)
local fullHeight = UIx.frame:GetHeight()
db.Density = "COMPACT"
Advance(0.5)
CHECK(UIx.frame:GetHeight() == compactHeight, "M: density switches back cleanly", UIx.frame:GetHeight())
-- Compact is meaningfully smaller, but not at the cost of legibility: text
-- sizes are the same at both, so the saving comes from dropping the bars and
-- folding the ladder, never from shrinking the font.
CHECK(compactHeight < fullHeight * 0.7,
    "M: compact carries the same read in well under two thirds the height",
    compactHeight .. " vs " .. fullHeight)

-- Compact drops the bars for the numbers they were carrying
CHECK(not UIx.race.top:IsShown() and UIx.race.mine:IsShown(), "M: no bars at compact")
CHECK(UIx.race.mine:GetText() == "3 bases  1000", "M: our bases and resources as text",
    UIx.race.mine:GetText())
CHECK(UIx.race.theirs:GetText() == "1000  2 bases", "M: theirs mirrored", UIx.race.theirs:GetText())

-- ...and folds the ladder into one strip, still saying what it assumes
CHECK(not UIx.ladder.rows[1]:IsShown(), "M: no ladder rows at compact")
CHECK(UIx.ladder.cells[1]:IsShown(), "M: a ladder strip instead")
CHECK(UIx.ladder.header:GetText() == "if they take the rest",
    "M: the strip still states its assumption", UIx.ladder.header:GetText())
CHECK(UIx.ladder.cells[1].bases:GetText() == "5" and UIx.ladder.cells[5].bases:GetText() == "1",
    "M: five rungs, five down to one")
CHECK(UIx.ladder.cells[3].bases:GetText() == "3" and UIx.ladder.cells[3].margin:GetText() == "+333",
    "M: signed margins", UIx.ladder.cells[3].margin:GetText())
CHECK(UIx.ladder.cells[4].margin:GetText() == "-333", "M: and losses read negative",
    UIx.ladder.cells[4].margin:GetText())
CHECK(UIx.ladder.cells[3].marker:IsShown() and not UIx.ladder.cells[4].marker:IsShown(),
    "M: the rung we are on is the lit one")

-- Two stacked rows of bare digits say nothing about which row is which. The
-- roomy version spells it out per row ("3  win by 333"); the strip cannot, so
-- it carries a label column instead.
CHECK(UIx.ladder.axisHold:IsShown() and UIx.ladder.axisHold:GetText() == "hold",
    "M: the strip names its top row", UIx.ladder.axisHold:GetText())
CHECK(UIx.ladder.axisEnds:IsShown() and UIx.ladder.axisEnds:GetText() == "ends",
    "M: and the number under it", UIx.ladder.axisEnds:GetText())

-- The labels are the strip's, not the roomy rows'
db.Density = "FULL"
Advance(0.5)
CHECK(not UIx.ladder.axisHold:IsShown(),
    "M: the roomy rows say it in words and need no label column")
db.Density = "COMPACT"
Advance(0.5)
CHECK(UIx.ladder.axisHold:IsShown(), "M: which comes back with the strip")

-- The label column has to come out of the strip's width, not off the edge of
-- the panel: five cells plus their gaps plus the labels have to still fit
local lastCell = UIx.ladder.cells[5]
local cellPoint = lastCell.__points and lastCell.__points[1]
CHECK(cellPoint and (cellPoint.x + lastCell:GetWidth()) <= 226,
    "M: and the last rung still lands inside the board",
    cellPoint and (cellPoint.x + lastCell:GetWidth()))

-- The call goes terse rather than being cut off
CHECK(CallText() == "Hold all 3", "M: the call is the instruction alone", CallText())
CHECK(VerdictText() == "WIN 333", "M: and the verdict loses its filler words", VerdictText())
CHECK(VerdictDetail() == "10:00", "M: the clock rides on the same line", VerdictDetail())

-- Minimal: one line for the whole read
db.Density = "MINIMAL"
Advance(0.5)
local minimalHeight = UIx.frame:GetHeight()
CHECK(minimalHeight < compactHeight, "M: minimal is smaller again",
    minimalHeight .. " vs " .. compactHeight)
CHECK(not UIx.race:IsShown() and not UIx.ladder:IsShown(),
    "M: minimal drops the race and the ladder — the context, not the instruction")
CHECK(VerdictText() == "WIN 333", "M: verdict", VerdictText())
CHECK(VerdictDetail() == "10:00", "M: with the clock beside it", VerdictDetail())
CHECK(UIx.call:IsShown() and CallText() == "Hold all 3",
    "M: the call keeps its own row rather than being clipped onto the verdict's",
    CallText())
CHECK(UIx.nodes:IsShown(), "M: and the flags stay")

-- Minimal ignores the section switches for the two things it always keeps
db.ShowCallout = false
Advance(0.5)
CHECK(UIx.call:IsShown(), "M: minimal keeps the call even when the switch is off")
db.ShowCallout = true

-- The section switches still bite at compact, and are ignored by minimal
db.Density = "COMPACT"
db.ShowRace = false
Advance(0.5)
CHECK(not UIx.race:IsShown(), "M: compact still honours the section switches")
db.ShowRace = true
Advance(0.5)

-- A board with nothing to project hides the ladder rather than drawing a void
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "H", "H", "o" })
widgetScores.left, widgetScores.right = nil, nil
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(VerdictText() == "READING", "M: it says it is still reading", VerdictText())
CHECK(not UIx.ladder:IsShown(), "M: and hides the ladder rather than six blank rungs")
CHECK(UIx.nodes:IsShown(), "M: the flags are known even when the scoreboard is not")
CHECK(UIx.race.mine:GetText() == "2 bases", "M: and so are the base counts",
    UIx.race.mine:GetText())

-- ---------------------------------------------------------------------------
-- N: the no-backdrop treatment
-- ---------------------------------------------------------------------------
-- Without this the clean style is unusable: white text on Arathi's snow.
db.TextOutline = true
db.Density = "COMPACT"
Advance(0.5)
CHECK(db.BoardStyle == "NONE", "N: no backdrop is the shipped default", db.BoardStyle)
CHECK(UIx.verdict.headline.__fontFlags == "OUTLINE", "N: the verdict is outlined",
    tostring(UIx.verdict.headline.__fontFlags))
CHECK(UIx.ladder.cells[1].margin.__fontFlags == "OUTLINE", "N: so is the ladder strip")
CHECK(UIx.nodes.pips[1].name.__fontFlags == "OUTLINE", "N: and the node board")
db.TextOutline = false
Advance(0.5)
CHECK(UIx.verdict.headline.__fontFlags == nil, "N: switching it off restores the plain font",
    tostring(UIx.verdict.headline.__fontFlags))
CHECK(UIx.verdict.headline.__fontObject ~= nil, "N: via the font object, not a hand-built font")
db.TextOutline = true
Advance(0.5)
CHECK(UIx.verdict.headline.__fontFlags == "OUTLINE", "N: and back on again")

-- ---------------------------------------------------------------------------
-- O: the comms header
-- ---------------------------------------------------------------------------
db.Density = "COMPACT"
db.ShowComms = true
groupped = true
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "A", "H", "H" })       -- 3 to 2, exactly the minimum
widgetScores.left, widgetScores.right = 1000, 1000
Fire("PLAYER_ENTERING_WORLD")
Advance(1)

CHECK(UIx.comms:IsShown(), "O: the header is up")
CHECK(#UIx.comms.buttons == 3, "O: three buttons", #UIx.comms.buttons)
CHECK(UIx.comms.buttons[1].label:GetText() == "CALL", "O: CALL first")

-- Nothing is EVER sent without a click
local before = #chatLog
Advance(60)
CHECK(#chatLog == before, "O: sixty seconds pass and the header has said nothing")

-- CALL posts the whole read
ClickComms("CALL")
CHECK(#chatLog == before + 1, "O: CALL posts once")
CHECK(chatLog[#chatLog].channel == "INSTANCE_CHAT", "O: to the instance channel, not RAID",
    chatLog[#chatLog].channel)
local call = chatLog[#chatLog].msg
CHECK(call:match("^%[Oracle%] 3b 1000 vs 1000 2b"), "O: with both sides' bases and resources", call)
CHECK(call:match("we WIN by 333 in 10:00"), "O: the verdict", call)
CHECK(call:match("HOLD ALL 3"), "O: and the call", call)

-- The throttle: a second press inside the window does not repeat it
ClickComms("CALL")
CHECK(#chatLog == before + 1, "O: a second press inside the throttle sends nothing")
Advance(9)
ClickComms("CALL")
CHECK(#chatLog == before + 2, "O: and is armed again once the throttle expires")

-- DEFEND on a board where every base is load-bearing
Advance(3)
ClickComms("DEFEND")
local defend = chatLog[#chatLog].msg
CHECK(defend:match("HOLD ALL 3"), "O: DEFEND warns we are on the line", defend)
CHECK(defend:match("losing any one base loses this"), "O: and says what that means", defend)

-- TAKE has nothing to say while we already hold enough
CHECK(not CommsButton("TAKE"):IsEnabled(), "O: TAKE is greyed out when we hold enough")
CHECK(CommsButton("CALL"):IsEnabled(), "O: while CALL always has the read to give")
local quiet = #chatLog
ClickComms("TAKE")
CHECK(#chatLog == quiet, "O: and a click on it posts nothing")

-- Now they start taking a base, and we are behind on resources with it:
-- DEFEND names the flag, its clock, and the cost of losing it
Advance(9)
SetBoard({ "A", "A", "h", "H", "H" })       -- they click the Blacksmith
widgetScores.left, widgetScores.right = 900, 1200
Fire("AREA_POIS_UPDATED")
Advance(0.5)
ClickComms("DEFEND")
local threat = chatLog[#chatLog].msg
CHECK(threat:match("DEFEND Blacksmith"), "O: DEFEND names the flag by name", threat)
CHECK(threat:match("%d+s"), "O: with its countdown", threat)
CHECK(threat:match("if they land"), "O: and what happens if it lands", threat)
CHECK(threat:match("we LOSE by"), "O: which here is a loss", threat)

-- ...and TAKE has woken up, because two of five is no longer enough
Advance(9)
CHECK(CommsButton("TAKE"):IsEnabled(), "O: TAKE arms when we are short")
ClickComms("TAKE")
local take = chatLog[#chatLog].msg
CHECK(take:match("^%[Oracle%] Need 1 more base within %d+:%d%d"), "O: TAKE names the count and the clock",
    take)
CHECK(take:match("out of reach"), "O: and the consequence", take)

-- The tooltip shows the exact line before it is committed to
local shown = CommsTooltip("CALL")
CHECK(shown ~= nil, "O: hovering a button builds its tooltip")
CHECK(#harnessErrors == 0, "O: and hovering does not throw", harnessErrors[1])

-- Outside a group it prints rather than posting into nothing
groupped = false
Advance(9)
local printed = #printLog
ClickComms("CALL")
CHECK(#printLog > printed, "O: with no battlegroup it prints to your own frame instead")
groupped = true

-- The slash commands go through exactly the same builder
Advance(9)
local viaSlash = #chatLog
CommanderOracle_Defend()
CHECK(#chatLog == viaSlash + 1, "O: /coracle defend posts")
CHECK(chatLog[#chatLog].msg:match("DEFEND"), "O: the DEFEND line", chatLog[#chatLog].msg)

-- The header can be switched off, and the board closes over it
db.ShowComms = false
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
local withoutHeader = UIx.frame:GetHeight()
CHECK(not UIx.comms:IsShown(), "O: the header goes away when switched off")
db.ShowComms = true
Commander.Notify(COMMANDER_ORACLE_EVENTS.UPDATE)
Advance(0.5)
CHECK(UIx.frame:GetHeight() > withoutHeader, "O: and the board grows to fit it again",
    UIx.frame:GetHeight() .. " vs " .. withoutHeader)

-- A board with no scoreboard yet has nothing to communicate
widgetScores.left, widgetScores.right = nil, nil
LeaveBasin()
zone.inBasin = true
SetBoard({ "A", "A", "H", "H", "o" })
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(not UIx.comms:IsShown(), "O: no header while there is nothing true to say")

-- ---------------------------------------------------------------------------
-- P: the tabs
-- ---------------------------------------------------------------------------
local function Tab(key)
    for _, button in ipairs(UIx.tabs.buttons) do
        if button.key == key then return button end
    end
end

local function VisibleTabs()
    local names = {}
    for _, button in ipairs(UIx.tabs.buttons) do
        if button:IsShown() then names[#names + 1] = button.key end
    end
    return table.concat(names, ",")
end

local function ClickTab(key)
    local button = Tab(key)
    button.__scripts.OnClick(button, "LeftButton")
    Advance(0.3)
end

db.Density = "COMPACT"
db.ShowComms = true
db.Tab = "BATTLE"
zone.inBasin, zone.pvp = true, false
SetBoard({ "A", "A", "H", "H", "o" })
widgetScores.left, widgetScores.right = 900, 700
Fire("PLAYER_ENTERING_WORLD")
Advance(1)

CHECK(UIx.tabs:IsShown(), "P: the tab strip is up")
CHECK(VisibleTabs() == "BATTLE,TOP,MINE,THEIRS", "P: four tabs in Arathi", VisibleTabs())
CHECK(Tab("MINE").label:GetText() == "ALLIANCE", "P: a faction tab is named for its faction",
    Tab("MINE").label:GetText())
CHECK(Tab("THEIRS").label:GetText() == "HORDE", "P: including the enemy's",
    Tab("THEIRS").label:GetText())
CHECK(UIx.verdict:IsShown(), "P: BATTLE is the tab we start on")
CHECK(not UIx.top:IsShown(), "P: and the roster is not drawn behind it")

ClickTab("TOP")
CHECK(db.Tab == "TOP", "P: the tab you picked is remembered", db.Tab)
CHECK(UIx.top:IsShown(), "P: TOP takes the board")
CHECK(not UIx.verdict:IsShown(), "P: the projection steps aside rather than stacking")
CHECK(not UIx.comms:IsShown(), "P: comms belong to the battle tab, not the roster")
CHECK(not UIx.nodes:IsShown(), "P: so does the node board")

-- A battleground that is not Arathi: the roster still works, the projection
-- has nothing true to say and takes ITSELF away
zone.inBasin, zone.pvp = false, true
Fire("PLAYER_ENTERING_WORLD")
Advance(1)
CHECK(VisibleTabs() == "TOP,MINE,THEIRS", "P: no Arathi answer offered in a Warsong Gulch",
    VisibleTabs())
CHECK(UIx.frame:IsShown(), "P: but the board is still up -- the roster reads every battleground")
db.Tab = "BATTLE"
Advance(0.5)
CHECK(UIx.top:IsShown(), "P: a tab that is not on offer falls back to one that is")
CHECK(not UIx.verdict:IsShown(), "P: and never draws the Arathi board over another map")

-- ---------------------------------------------------------------------------
-- Q: the roster reads the scoreboard
-- ---------------------------------------------------------------------------
local AB_COLUMNS = { "Bases Assaulted", "Bases Defended" }

local function SetScoreboard(rows, columns)
    scoreRows, scoreColumns = rows, columns or AB_COLUMNS
    Fire("UPDATE_BATTLEFIELD_SCORE")
    Advance(0.3)
end

local function TopRow(block, slot) return UIx.top.blocks[block].rows[slot] end

local function TopNames(block)
    local names = {}
    for _, row in ipairs(UIx.top.blocks[block].rows) do
        if row:IsShown() then names[#names + 1] = row.name:GetText() end
    end
    return table.concat(names, ",")
end

local function GroupHeaders()
    local labels = {}
    for _, group in ipairs(UIx.roster.groups) do
        if group.header:IsShown() then labels[#labels + 1] = group.header:GetText() end
    end
    return table.concat(labels, ",")
end

zone.inBasin, zone.pvp = true, false
Fire("PLAYER_ENTERING_WORLD")
db.Tab = "TOP"
db.TopCount = 3
Advance(1)

SetScoreboard({
    -- faction 1 is the Alliance; the realm suffix is what a cross-realm
    -- battleground actually sends
    { name = "Ashvale-Whitemane", faction = 1, classToken = "WARRIOR",
      kb = 9, deaths = 3, dmg = 214000, heal = 0, obj = { 2, 1 } },
    { name = "Brackwater", faction = 1, classToken = "PRIEST",
      kb = 1, deaths = 2, dmg = 12000, heal = 186000, obj = { 0, 2 } },
    { name = "Dunhollow", faction = 1, classToken = "MAGE",
      kb = 3, deaths = 6, dmg = 141000, heal = 0, obj = { 0, 0 } },
    { name = "Idler", faction = 1, classToken = "ROGUE",
      kb = 0, deaths = 0, dmg = 0, heal = 0, obj = { 0, 0 } },
    { name = "Grimjaw", faction = 0, classToken = "WARLOCK",
      kb = 12, deaths = 2, dmg = 251000, heal = 0, obj = { 1, 0 } },
    { name = "Hexmark", faction = 0, classToken = "SHAMAN",
      kb = 0, deaths = 1, dmg = 15000, heal = 240000, obj = { 0, 3 } },
    { name = "Nazgrint", faction = 0, classToken = "WARRIOR",
      kb = 4, deaths = 7, dmg = 133000, heal = 0, obj = { 1, 1 } },
})

CHECK(UIx.scores.report ~= nil and UIx.scores.report.ready,
    "Q: the scoreboard event builds a ranking")
CHECK(TopRow(1, 1).name:GetText() == "Ashvale",
    "Q: the realm is stripped off a cross-realm name", TopRow(1, 1).name:GetText())
CHECK(TopNames(1) == "Ashvale,Brackwater,Dunhollow",
    "Q: our side, ranked, with the player who did nothing left off", TopNames(1))
-- Grimjaw (top damage, top kills, two deaths) leads Hexmark (top healing,
-- three base defends, one death). Objectives are the smallest weight on
-- purpose: a 0-to-5 integer saturates its own share instantly, and when it
-- carried the heaviest weight three base defends out-scored twelve killing
-- blows and the best damage in the match.
CHECK(TopNames(2) == "Grimjaw,Hexmark,Nazgrint",
    "Q: and the enemy side, which only the server scoreboard could tell us", TopNames(2))
CHECK(TopRow(2, 1).reason:GetText() == "damage",
    "Q: named for what actually carried the score", TopRow(2, 1).reason:GetText())
CHECK(TopRow(2, 2).reason:GetText() == "healing",
    "Q: and the healer for hers", TopRow(2, 2).reason:GetText())
CHECK(UIx.top.blocks[1].header:GetText() == "ALLIANCE",
    "Q: our block is ours -- faction 1 is the Alliance",
    UIx.top.blocks[1].header:GetText())
CHECK(UIx.top.blocks[2].header:GetText() == "HORDE",
    "Q: and faction 0 is the Horde", UIx.top.blocks[2].header:GetText())
CHECK(tonumber(TopRow(1, 1).value:GetText()) ~= nil, "Q: every row carries its impact",
    TopRow(1, 1).value:GetText())
CHECK(TopRow(2, 1).reason:GetText() ~= nil and TopRow(2, 1).reason:GetText() ~= "",
    "Q: and what it is for", TopRow(2, 1).reason:GetText())
CHECK(UIx.top.summary:GetText():find("Hexmark", 1, true) ~= nil,
    "Q: the read names the enemy healer to focus", UIx.top.summary:GetText())

-- The faction tabs: one side, broken into what the battleground pays for
ClickTab("THEIRS")
CHECK(UIx.roster:IsShown(), "Q: the faction tab draws the faction view")
CHECK(not UIx.top:IsShown(), "Q: one view at a time")
CHECK(UIx.roster.header:GetText() == "HORDE", "Q: the side it is showing",
    UIx.roster.header:GetText())
CHECK(GroupHeaders() == "Killing blows,Damage,Healing,Bases Assaulted,Bases Defended",
    "Q: the three universal boards plus the map's OWN objective columns",
    GroupHeaders())
CHECK(UIx.roster.groups[1].rows[1].name:GetText() == "Grimjaw",
    "Q: ranked within the board", UIx.roster.groups[1].rows[1].name:GetText())
CHECK(UIx.roster.groups[2].rows[1].value:GetText() == "251k",
    "Q: with the number written the way you read it", UIx.roster.groups[2].rows[1].value:GetText())

ClickTab("MINE")
CHECK(UIx.roster.header:GetText() == "ALLIANCE", "Q: and the other side on the other tab",
    UIx.roster.header:GetText())

-- A board nobody has scored on is dropped, not drawn as a heading over three
-- blank rows: early in a match that is most of them
SetScoreboard({
    { name = "Ashvale", faction = 1, classToken = "WARRIOR",
      kb = 4, deaths = 1, dmg = 40000, heal = 0, obj = { 1, 0 } },
    { name = "Dunhollow", faction = 1, classToken = "MAGE",
      kb = 2, deaths = 1, dmg = 30000, heal = 0, obj = { 0, 0 } },
    { name = "Grimjaw", faction = 0, classToken = "WARLOCK",
      kb = 3, deaths = 2, dmg = 35000, heal = 0, obj = { 0, 0 } },
})
CHECK(GroupHeaders() == "Killing blows,Damage,Bases Assaulted",
    "Q: no healing and no defends means no headings for them", GroupHeaders())

-- The count setting bites on every board
db.TopCount = 1
Fire("UPDATE_BATTLEFIELD_SCORE")
Advance(0.5)
local shown = 0
for _, row in ipairs(UIx.roster.groups[1].rows) do
    if row:IsShown() then shown = shown + 1 end
end
CHECK(shown == 1, "Q: one player per board when that is what was asked for", shown)
db.TopCount = 3
Advance(0.5)

-- The scoreboard is a server round trip, and we only ask while somebody is
-- looking at the answer
db.Tab = "BATTLE"
Advance(2)
local quiet = scoreRequests
Advance(6)
CHECK(scoreRequests == quiet, "Q: the battle tab never polls the server for a scoreboard",
    scoreRequests - quiet)
db.Tab = "TOP"
Advance(6)
CHECK(scoreRequests > quiet, "Q: the roster tabs do", scoreRequests - quiet)
CHECK(scoreRequests - quiet <= 4, "Q: on a throttle, not once per frame", scoreRequests - quiet)

-- Out of the battleground entirely: the roster says what it has, which is
-- nothing, rather than drawing a stale ranking
db.RosterKeep = nil
zone.inBasin, zone.pvp = false, false
Fire("PLAYER_ENTERING_WORLD")
Advance(12)
CHECK(not UIx.frame:IsShown(), "Q: no battleground, no board")
CHECK(UIx.scores.report == nil, "Q: and the ranking is dropped rather than kept to go stale")

-- The demo brings its own scoreboard, so the tabs can be placed and read
-- outside a battleground
CommanderOracle_Test()
Advance(0.5)
CHECK(UIx.frame:IsShown(), "Q: the demo puts the board up")
CHECK(UIx.scores.report ~= nil and UIx.scores.report.ready,
    "Q: with a worked scoreboard behind the roster tabs")
db.Tab = "TOP"
Advance(0.5)
CHECK(TopNames(1) ~= "", "Q: which the TOP tab actually draws", TopNames(1))

-- R: range, and the rows you click
-- ---------------------------------------------------------------------------
local function Macro(row, button)
    return row:GetAttribute("macrotext" .. (button or 1))
end

combat = false
zone.inBasin, zone.pvp = true, false
Fire("PLAYER_ENTERING_WORLD")
db.Tab = "TOP"
db.TopCount = 3
db.ShowDistance = true
Advance(1)

-- The client answers with real coordinates for our own raid and refuses for
-- everybody else, which is the whole shape of the range column
PlaceUnit("Ashvale", "raid1", { position = true, x = 30, y = 40 })    -- 50 yards
PlaceUnit("Brackwater", "raid2", { position = true, x = 3, y = 4 })   -- 5 yards
PlaceUnit("Hexmark", "nameplate1", { near = 3 })                      -- close enough to duel
PlaceUnit("Grimjaw", "target", { near = 1 })                          -- inside inspect range only
PlaceUnit("Player", "player", { position = true, x = 0, y = 0 })
Fire("NAME_PLATE_UNIT_ADDED", "nameplate1")

SetScoreboard({
    { name = "Ashvale-Whitemane", faction = 1, classToken = "WARRIOR",
      kb = 9, deaths = 3, dmg = 214000, heal = 0, obj = { 2, 1 } },
    { name = "Brackwater", faction = 1, classToken = "PRIEST",
      kb = 1, deaths = 2, dmg = 12000, heal = 186000, obj = { 0, 2 } },
    { name = "Dunhollow", faction = 1, classToken = "MAGE",
      kb = 3, deaths = 6, dmg = 141000, heal = 0, obj = { 0, 0 } },
    { name = "Grimjaw", faction = 0, classToken = "WARLOCK",
      kb = 12, deaths = 2, dmg = 251000, heal = 0, obj = { 1, 0 } },
    { name = "Hexmark", faction = 0, classToken = "SHAMAN",
      kb = 0, deaths = 1, dmg = 15000, heal = 240000, obj = { 0, 3 } },
    { name = "Nazgrint", faction = 0, classToken = "WARRIOR",
      kb = 4, deaths = 7, dmg = 133000, heal = 0, obj = { 1, 1 } },
})
Advance(1)

-- Range on the ranked rows, which is where it was asked for
CHECK(TopRow(1, 1).range:GetText() == "50y",
    "R: a raid member gets a measured distance", TopRow(1, 1).range:GetText())
CHECK(TopRow(1, 2).range:GetText() == "5y",
    "R: measured from real coordinates, not guessed", TopRow(1, 2).range:GetText())
-- An enemy we hold a unit for reports "seen" and nothing more. There is no
-- unprotected way to range a hostile player on this client, so a bound is not
-- something the board can honestly print -- and printing one anyway is worse
-- than printing nothing. RangeText still understands { within = n } if a
-- future unprotected source can produce one.
CHECK(TopRow(2, 1).range:GetText() == "seen",
    "R: an enemy we hold a unit for is reported as seen, not measured",
    TopRow(2, 1).range:GetText())
CHECK(TopRow(2, 2).range:GetText() == "seen",
    "R: and a closer one is no more measurable than a far one",
    TopRow(2, 2).range:GetText())
CHECK(TopRow(2, 3).range:GetText() == "",
    "R: an enemy the client will not point at gets nothing, not a guess",
    TopRow(2, 3).range:GetText())

db.ShowDistance = false
Advance(0.5)
CHECK(not TopRow(1, 1).range:IsShown(), "R: the range column can be switched off")
db.ShowDistance = true
Advance(0.5)

-- ---------------------------------------------------------------------------
-- R: the ranked rows ARE the click targets -- there is no second list
-- ---------------------------------------------------------------------------
CHECK(TopRow(2, 1).__template == "SecureActionButtonTemplate",
    "R: a roster row is a secure button", TopRow(2, 1).__template)
CHECK(Macro(TopRow(2, 1), 1) == "/targetexact Grimjaw",
    "R: left-click targets the player on the row", Macro(TopRow(2, 1), 1))
CHECK(Macro(TopRow(2, 1), 2) == "/focus Grimjaw",
    "R: right-click focuses them", Macro(TopRow(2, 1), 2))
CHECK(TopRow(2, 1).name:GetText() == "Grimjaw",
    "R: and the name printed on it is the name the macro carries",
    TopRow(2, 1).name:GetText())
CHECK(TopRow(1, 1):GetAttribute("type1") == "macro"
    and TopRow(1, 1):GetAttribute("type2") == "macro",
    "R: both buttons are wired")
CHECK(UIx.frame:IsProtected(),
    "R: which makes the BOARD protected -- the price of clickable rows")

-- The faction boards are clickable too, on the same terms
db.Tab = "THEIRS"
Advance(0.5)
local groupRow = UIx.roster.groups[1].rows[1]
CHECK(groupRow.name:GetText() == "Grimjaw", "R: the metric boards carry rows too",
    groupRow.name:GetText())
CHECK(Macro(groupRow, 1) == "/targetexact Grimjaw", "R: and they click", Macro(groupRow, 1))
CHECK(Macro(groupRow, 2) == "/focus Grimjaw", "R: both ways", Macro(groupRow, 2))
db.Tab = "TOP"
Advance(0.5)

-- The row you are on is read back off the game, not remembered from the click
tokenOwner.target = "Grimjaw"
Advance(0.5)
CHECK(TopRow(2, 1).bg.__color and TopRow(2, 1).bg.__color[4] > 0.2,
    "R: the row you are targeting lights up",
    TopRow(2, 1).bg.__color and TopRow(2, 1).bg.__color[4])
tokenOwner.focus = "Hexmark"
Advance(0.5)
CHECK(TopRow(2, 2).bg.__color[4] > 0.1, "R: and the one you have focused",
    TopRow(2, 2).bg.__color[4])
CHECK(TopRow(2, 2).bg.__color[3] > TopRow(2, 2).bg.__color[1],
    "R: in its own colour, so the two never read as the same thing")
tokenOwner.target, tokenOwner.focus = nil, nil
Advance(0.5)
CHECK(TopRow(2, 1).bg.__color[4] < 0.2, "R: and both let go when you move off")

-- ---------------------------------------------------------------------------
-- R: what combat takes away, and what it does not
--
-- A secure button cannot be re-bound, moved, shown or hidden in combat, and
-- the protection walks up. So the board holds its SHAPE and every row holds
-- its player -- but nothing it SAYS is allowed to go stale, and what you click
-- can never disagree with what you read.
-- ---------------------------------------------------------------------------
combat = true
local heldNames = TopNames(2)
local heldMacro = Macro(TopRow(2, 1), 1)
local heldHeight = UIx.frame:GetHeight()

-- Nazgrint overtakes everybody while we are locked in
SetScoreboard({
    { name = "Grimjaw", faction = 0, classToken = "WARLOCK",
      kb = 1, deaths = 9, dmg = 20000, heal = 0, obj = { 0, 0 } },
    { name = "Hexmark", faction = 0, classToken = "SHAMAN",
      kb = 0, deaths = 9, dmg = 5000, heal = 20000, obj = { 0, 0 } },
    { name = "Nazgrint", faction = 0, classToken = "WARRIOR",
      kb = 30, deaths = 0, dmg = 400000, heal = 0, obj = { 5, 5 } },
    { name = "Ashvale-Whitemane", faction = 1, classToken = "WARRIOR",
      kb = 9, deaths = 3, dmg = 214000, heal = 0, obj = { 2, 1 } },
})
Advance(1)
CHECK(TopNames(2) == heldNames, "R: in combat the rows hold their players", TopNames(2))
CHECK(Macro(TopRow(2, 1), 1) == heldMacro, "R: and their bindings", Macro(TopRow(2, 1), 1))
CHECK(TopRow(2, 1).name:GetText() == "Grimjaw",
    "R: the name on the row still matches what the click will target",
    TopRow(2, 1).name:GetText())
CHECK(UIx.frame:GetHeight() == heldHeight, "R: the board holds its shape",
    UIx.frame:GetHeight())
-- ...and the reading is never held
CHECK(TopRow(2, 1).value:GetText() == tostring(UIx.scores.report.byName.Grimjaw.impact),
    "R: while the score on it keeps updating", TopRow(2, 1).value:GetText())
PlaceUnit("Grimjaw", "target", { near = 3 })
Advance(0.5)
CHECK(TopRow(2, 1).range:GetText() == "seen", "R: and so does the range cell",
    TopRow(2, 1).range:GetText())

-- A tab asked for mid-fight cannot take, so the strip lights the one you are
-- LOOKING at and marks the one you asked for
db.Tab = "THEIRS"
Advance(0.5)
CHECK(UIx.top:IsShown() and not UIx.roster:IsShown(),
    "R: the tab does not switch under a protected board")
local pendingTab
for _, button in ipairs(UIx.tabs.buttons) do
    if button:IsShown() and button.label:GetText():find("*", 1, true) then
        pendingTab = button.key
    end
end
CHECK(pendingTab == "THEIRS", "R: and the strip says which tab is waiting", pendingTab)

-- Combat ends: everything that was held goes in at once
combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(0.5)
CHECK(UIx.roster:IsShown(), "R: the tab lands the moment the fight ends")
db.Tab = "TOP"
Advance(0.5)
CHECK(TopNames(2):match("^Nazgrint") ~= nil, "R: and the rows re-rank", TopNames(2))
CHECK(Macro(TopRow(2, 1), 1) == "/targetexact Nazgrint", "R: and re-bind",
    Macro(TopRow(2, 1), 1))

-- Out of a battleground. Long enough to clear the exit grace AND any demo
-- window still standing from an earlier section -- the demo deliberately holds
-- the board up outside a match, so a shorter wait tests the demo, not the exit.
zone.inBasin, zone.pvp = false, false
Fire("PLAYER_ENTERING_WORLD")
Advance(45)
CHECK(not UIx.frame:IsShown(), "R: no battleground, no board")
CHECK(UIx.scores.report == nil, "R: and the ranking is dropped rather than kept to go stale")

-- The demo brings its own scoreboard, so the rows can be read outside a match
CommanderOracle_Test()
Advance(0.5)
CHECK(UIx.frame:IsShown(), "R: the demo puts the board up")
db.Tab = "TOP"
Advance(0.5)
CHECK(TopNames(1) ~= "", "R: which the TOP tab actually draws", TopNames(1))

-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- T: raid markers
--
-- The only thing Oracle does that other people can see, so the tests are as
-- much about what it must NOT do as what it must.
-- ---------------------------------------------------------------------------
local function MarkOf(name)
    for token, owner in pairs(tokenOwner) do
        if owner == name and raidMarks[token] then return raidMarks[token] end
    end
    return nil
end

local function Marked()
    local out = {}
    for token, index in pairs(raidMarks) do
        out[#out + 1] = (tokenOwner[token] or token) .. "=" .. index
    end
    table.sort(out)
    return table.concat(out, ",")
end

local function ClearMarkLog() for i = #markCalls, 1, -1 do markCalls[i] = nil end end

combat = false
zone.inBasin, zone.pvp = true, false
Fire("PLAYER_ENTERING_WORLD")
db.Tab = "TOP"
db.MarkCount = 3
db.MarkTop = false
isLeader, isAssistant = false, false
for token in pairs(raidMarks) do raidMarks[token] = nil end
ClearMarkLog()

-- Four on our side with a clear order, plus an enemy who must never be touched
PlaceUnit("Ashvale", "raid1", { position = true, x = 1, y = 1 })
PlaceUnit("Brackwater", "raid2", { position = true, x = 2, y = 2 })
PlaceUnit("Coldiron", "raid3", { position = true, x = 3, y = 3 })
PlaceUnit("Dunhollow", "raid4", { position = true, x = 4, y = 4 })
local function OurBoard(spec)
    local rows = {
        { name = "Grimjaw", faction = 0, classToken = "WARLOCK",
          kb = 12, deaths = 2, dmg = 251000, heal = 0, obj = { 1, 0 } },
    }
    for _, row in ipairs(spec) do rows[#rows + 1] = row end
    SetScoreboard(rows)
    Advance(1.5)
end
local function Ally(name, kb, dmg, deaths)
    return { name = name, faction = 1, classToken = "WARRIOR",
        kb = kb, deaths = deaths or 2, dmg = dmg, heal = 0, obj = { 0, 0 } }
end

OurBoard({
    Ally("Ashvale", 12, 260000), Ally("Brackwater", 9, 200000),
    Ally("Coldiron", 6, 140000), Ally("Dunhollow", 2, 60000),
})
CHECK(Marked() == "", "T: off by default -- nothing is written to the raid", Marked())

-- Switched on, but we are nobody
db.MarkTop = true
Advance(1.5)
CHECK(Marked() == "", "T: and nothing while we hold neither lead nor assist", Marked())

-- Leader: the top three carry icons, in rank order
isLeader = true
Advance(1.5)
CHECK(MarkOf("Ashvale") == 1 and MarkOf("Brackwater") == 2 and MarkOf("Coldiron") == 3,
    "T: the top three of OUR side get icons one to three", Marked())
CHECK(MarkOf("Dunhollow") == nil, "T: and the fourth does not")
CHECK(MarkOf("Grimjaw") == nil,
    "T: the enemy is never marked -- there is no unit token for one anyway")

-- The board shows the icon a player is carrying, in the rank slot: somebody
-- wearing a star does not also need to be told they are first
CHECK(TopRow(1, 1).mark:IsShown() and not TopRow(1, 1).rank:IsShown(),
    "T: a marked row shows the icon instead of its number")
CHECK(not TopRow(2, 1).mark:IsShown() and TopRow(2, 1).rank:IsShown(),
    "T: an unmarked row keeps the number")

-- An assistant may mark too; the server allows it
isLeader, isAssistant = false, true
Advance(1.5)
CHECK(MarkOf("Ashvale") == 1, "T: an assistant can mark as well as the leader")
isLeader, isAssistant = true, false

-- Sticky: a shuffle INSIDE the top three must not re-issue anything
ClearMarkLog()
OurBoard({
    Ally("Ashvale", 9, 200000), Ally("Brackwater", 12, 260000),
    Ally("Coldiron", 6, 140000), Ally("Dunhollow", 2, 60000),
})
CHECK(#markCalls == 0, "T: two players swapping places re-marks nobody", #markCalls)
CHECK(MarkOf("Ashvale") == 1 and MarkOf("Brackwater") == 2,
    "T: they keep the icon they were given", Marked())

-- Falling just past the cut is not enough to lose it either
ClearMarkLog()
OurBoard({
    Ally("Ashvale", 12, 260000), Ally("Brackwater", 9, 200000),
    Ally("Dunhollow", 7, 150000), Ally("Coldiron", 6, 140000),
})
CHECK(MarkOf("Coldiron") == 3, "T: fourth by a hair keeps the icon", Marked())
CHECK(MarkOf("Dunhollow") == nil, "T: and nobody is handed a free one over them")

-- Falling well past it does
OurBoard({
    Ally("Ashvale", 12, 260000), Ally("Brackwater", 9, 200000),
    Ally("Dunhollow", 8, 190000), Ally("Nazbo", 7, 180000),
    Ally("Torvald", 6, 170000), Ally("Coldiron", 0, 1000, 9),
})
CHECK(MarkOf("Coldiron") == nil, "T: dropping well out of the top gives the icon back",
    Marked())
CHECK(MarkOf("Dunhollow") == 3, "T: and the freed icon goes to whoever took the place",
    Marked())

-- Somebody else's mark is left exactly alone
PlaceUnit("Nazbo", "raid5", { position = true, x = 5, y = 5 })
raidMarks.raid5 = 8            -- another leader put a skull on them
ClearMarkLog()
OurBoard({
    Ally("Nazbo", 30, 400000), Ally("Ashvale", 12, 260000),
    Ally("Brackwater", 9, 200000), Ally("Dunhollow", 8, 190000),
})
CHECK(raidMarks.raid5 == 8, "T: a mark we did not place is not ours to take",
    tostring(raidMarks.raid5))
for _, call in ipairs(markCalls) do
    CHECK(call.token ~= "raid5", "T: and we never write over one", call.token)
end

-- If ours is taken over, we let go rather than fight for it
raidMarks.raid1 = 7            -- someone re-marked Ashvale
ClearMarkLog()
Advance(1.5)
CHECK(raidMarks.raid1 == 7, "T: an icon changed under us is left where it is",
    tostring(raidMarks.raid1))

-- Switching it off puts every icon we placed back
db.MarkTop = false
Advance(1.5)
CHECK(MarkOf("Brackwater") == nil and MarkOf("Dunhollow") == nil,
    "T: switching it off clears the icons we placed", Marked())
CHECK(raidMarks.raid5 == 8, "T: and leaves the ones we did not", tostring(raidMarks.raid5))

-- ...and so does leaving the battleground
db.MarkTop = true
Advance(1.5)
CHECK(MarkOf("Ashvale") ~= nil or MarkOf("Brackwater") ~= nil, "T: marks return", Marked())
zone.inBasin, zone.pvp = false, false
Fire("PLAYER_ENTERING_WORLD")
Advance(45)
CHECK(MarkOf("Brackwater") == nil and MarkOf("Dunhollow") == nil,
    "T: leaving the battleground takes our icons with it", Marked())
db.MarkTop = false
isLeader = false

-- ---------------------------------------------------------------------------
-- U: the arena team, marked by class colour
--
-- A different place with a different question. A battleground team is forty
-- strangers and the useful thing is who is playing best; an arena team is four
-- people you came with and the only useful thing is WHO IS WHO.
-- ---------------------------------------------------------------------------
zone.inBasin, zone.pvp, zone.arena = false, false, true
isLeader, isAssistant = false, false
db.MarkTop, db.MarkArenaTeam = false, false
for token in pairs(raidMarks) do raidMarks[token] = nil end
for token in pairs(tokenOwner) do tokenOwner[token] = nil end
ClearMarkLog()

PlaceUnit("Selfy", "player", { class = "MAGE" })
PlaceUnit("Grovewarden", "party1", { class = "DRUID" })
PlaceUnit("Backstabby", "party2", { class = "ROGUE" })
PlaceUnit("Mendicant", "party3", { class = "PRIEST" })
PlaceUnit("Totemic", "party4", { class = "SHAMAN" })
Fire("PLAYER_ENTERING_WORLD")
Advance(2)

CHECK(Marked() == "", "U: off by default, in an arena as anywhere else", Marked())

db.MarkArenaTeam = true
Advance(2)
CHECK(Marked() == "", "U: and nothing while we are not the party leader", Marked())

isLeader = true
Advance(2)
CHECK(MarkOf("Grovewarden") == 2, "U: the druid takes the orange circle",
    tostring(MarkOf("Grovewarden")))
CHECK(MarkOf("Backstabby") == 1, "U: the rogue the yellow star",
    tostring(MarkOf("Backstabby")))
CHECK(MarkOf("Mendicant") == 8, "U: the priest the skull", tostring(MarkOf("Mendicant")))
CHECK(MarkOf("Totemic") == 6, "U: the shaman the blue square", tostring(MarkOf("Totemic")))
CHECK(MarkOf("Selfy") == 5, "U: the mage the pale blue moon -- and yes, that is us",
    tostring(MarkOf("Selfy")))

-- Nothing to be sticky about: a class cannot change, so the same team resolves
-- the same way and a second pass writes nothing at all
ClearMarkLog()
Advance(3)
CHECK(#markCalls == 0, "U: and a settled team is not re-marked every pass", #markCalls)

-- The battleground switch is not this switch
db.MarkArenaTeam, db.MarkTop = false, true
Advance(2)
CHECK(Marked() == "", "U: the battleground mode does not mark an arena team", Marked())
db.MarkArenaTeam, db.MarkTop = true, false
Advance(2)
CHECK(MarkOf("Backstabby") == 1, "U: and back on when its own switch is")

-- Somebody else's icon is still left alone here
raidMarks.party2 = 7
ClearMarkLog()
Advance(2)
CHECK(raidMarks.party2 == 7, "U: a mark we did not place is not ours to take",
    tostring(raidMarks.party2))

-- The arena ends: our icons come off with it, and no grace period about it
zone.arena = false
Fire("PLAYER_ENTERING_WORLD")
Advance(2)
CHECK(MarkOf("Grovewarden") == nil and MarkOf("Mendicant") == nil,
    "U: leaving the arena takes our icons with it", Marked())
CHECK(raidMarks.party2 == 7, "U: and leaves the one we did not place", tostring(raidMarks.party2))
db.MarkArenaTeam = false
isLeader = false

-- ---------------------------------------------------------------------------
-- S: the settings page scrolls
--
-- It outgrew the Settings canvas somewhere around the roster tabs, and a page
-- whose last rows are simply unreachable is a page with missing features.
-- ---------------------------------------------------------------------------
local settingsPanel
for _, cat in ipairs(categories) do
    if cat.__panel and cat.__panel._key == "Oracle" then settingsPanel = cat.__panel end
end
CHECK(settingsPanel ~= nil, "S: the settings page was registered")

-- Scrolling comes from the shared settings framework now, so the page is
-- reached through the panel rather than through a name this module owns
local pageScroll = settingsPanel and settingsPanel._scroll
CHECK(pageScroll ~= nil, "S: its rows flow into a scroll frame")
CHECK(pageScroll and pageScroll.__template == "UIPanelScrollFrameTemplate",
    "S: on the client's own scroll template",
    pageScroll and pageScroll.__template)

-- The page really is taller than the canvas it is given -- which is the whole
-- reason this exists. Blizzard's settings canvas is a little over 500px and
-- this page flows about 1150.
-- Its sections fold now, so the whole of it is measured opened out
if settingsPanel and settingsPanel.SetAllFoldouts then settingsPanel:SetAllFoldouts(true) end
CHECK(settingsPanel and settingsPanel._contentHeight > 600,
    "S: and it has more page than canvas to put in it",
    settingsPanel and settingsPanel._contentHeight)

-- The wheel, including both ends of it
local wheel = pageScroll and pageScroll.__scripts.OnMouseWheel
CHECK(wheel ~= nil, "S: the wheel scrolls it")
if wheel then
    local at = 100
    pageScroll.GetVerticalScroll = function() return at end
    pageScroll.GetVerticalScrollRange = function() return 400 end
    pageScroll.SetVerticalScroll = function(_, value) at = value end
    wheel(pageScroll, -1)
    CHECK(at == 128, "S: down moves down the page", at)
    wheel(pageScroll, 1)
    CHECK(at == 100, "S: and up moves back", at)
    at = 10
    wheel(pageScroll, 1)
    CHECK(at == 0, "S: it stops at the top rather than scrolling past it", at)
    at = 390
    wheel(pageScroll, -1)
    CHECK(at == 400, "S: and at the bottom", at)
end

-- ---------------------------------------------------------------------------
-- W: a flag you can walk to (Commander Orders)
--
-- Clicking a pip asks Orders for ONE waypoint at that flag, placed where the
-- map's own area POI says the flag stands, pinned because it was asked for,
-- temporary and session-only, and gone with the match -- handing the arrow
-- back to a waypoint of yours if the click took it.
-- ---------------------------------------------------------------------------
do
    -- Where the map puts each flag (fractions of the Arathi Basin map)
    local FLAG_AT = { { 0.373, 0.291 }, { 0.404, 0.558 }, { 0.464, 0.452 }, { 0.575, 0.309 }, { 0.560, 0.599 } }
    local realPOIInfo = C_AreaPoiInfo.GetAreaPOIInfo
    local placed = true
    C_AreaPoiInfo.GetAreaPOIInfo = function(uiMapID, poiID)
        local entry = CommanderOracle_POI[poiID]
        if uiMapID ~= 1461 or not entry or not placed then return nil end
        local at = FLAG_AT[entry.node.index]
        return { areaPoiID = poiID, position = { x = at[1], y = at[2] } }
    end

    -- The tooltip, recorded
    local tipLines = {}
    rawset(GameTooltip, "SetOwner", function() tipLines = {} end)
    rawset(GameTooltip, "SetText", function(_, text) tipLines[#tipLines + 1] = tostring(text) end)
    rawset(GameTooltip, "AddLine", function(_, text) tipLines[#tipLines + 1] = tostring(text) end)

    -- Commander Orders, as far as Oracle reaches into it
    local calls, active, records
    local function Reset(pinned)
        calls = { add = {}, arrow = {}, removeBy = {} }
        active = pinned
        records = { w1 = true, w5 = true }
    end
    local orders
    orders = {
        Add = function(spec)
            calls.add[#calls.add + 1] = spec
            if orders.refuse then return nil, orders.refuse end
            records.w9 = true
            return "w9"
        end,
        SetArrow = function(uid)
            calls.arrow[#calls.arrow + 1] = uid
            active = { uid = uid, why = "PINNED", source = uid == "w9" and "Oracle" or "user" }
            return true
        end,
        RemoveBy = function(source)
            calls.removeBy[#calls.removeBy + 1] = source
            records.w9 = nil
            if active and active.source == source then active = nil end
            return 1
        end,
        Active = function() return active end,
        Get = function(uid) return records[uid] and { uid = uid } or nil end,
    }
    -- Reaching the flag, as the real Orders does it: the flag spec has no
    -- clearOnArrive, so BuildRecord's consumer default (true) applies, and
    -- FinishArrival -> Unlink removes the record and unpins it
    -- (CommanderOrdersStore.lua FinishArrival, Unlink). The arrow then falls
    -- to whatever Follow the Closest picks: `after`, or nothing.
    local function ArriveAtFlag(after)
        records.w9 = nil
        if active and active.uid == "w9" then active = after end
    end
    CommanderOrders = orders
    combat = false

    zone.inBasin = true
    SetBoard({ "A", "H", "a", "o", "h" })
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    local pips = UIx.nodes.pips
    local function ClickPip(index, button)
        pips[index].__scripts.OnMouseUp(pips[index], button or "LeftButton")
    end
    CHECK(pips[3].__scripts.OnMouseUp ~= nil, "W: the pips take a click")

    -- A pinned waypoint of yours, then a click on the Blacksmith
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    CHECK(#calls.add == 1, "W: one waypoint asked for", #calls.add)
    local spec = calls.add[1] or {}
    CHECK(spec.map == 1461, "W: on the Arathi Basin map", spec.map)
    CHECK(spec.x == 0.464 and spec.y == 0.452, "W: where the map's own POI puts the Blacksmith",
        tostring(spec.x) .. "," .. tostring(spec.y))
    CHECK(spec.title == "Blacksmith", "W: titled with the flag", spec.title)
    CHECK(spec.source == "Oracle" and spec.key == "node", "W: one Oracle waypoint (source Oracle, key node)")
    CHECK(spec.temporary == true and spec.persistent == false, "W: temporary and session-only")
    CHECK(spec.setArrow == false and calls.arrow[1] == "w9",
        "W: and pinned outright, so a pinned waypoint of yours cannot swallow the click", calls.arrow[1])

    -- Another flag moves the same waypoint; the arrow it took is remembered once
    ClickPip(1)
    CHECK(#calls.add == 2 and calls.add[2].title == "Stables" and calls.add[2].key == "node",
        "W: clicking another flag asks again under the same key (Orders moves it)")
    CHECK(calls.add[2].x == 0.373 and calls.add[2].y == 0.291, "W: to the Stables")

    -- Right-click is not a waypoint
    ClickPip(2, "RightButton")
    CHECK(#calls.add == 2, "W: a right-click asks for nothing")

    -- Combat: the click is not a frame change, so it works mid-fight
    combat = true
    ClickPip(5)
    CHECK(#calls.add == 3 and calls.add[3].title == "Farm", "W: in combat, a click still sets the waypoint")
    combat = false

    -- The tooltip says what the flag is doing and what a click does
    pips[3].__scripts.OnEnter(pips[3])
    local tip = table.concat(tipLines, "\n")
    CHECK(tip:find("Blacksmith", 1, true) ~= nil, "W: the tooltip names the flag", tip)
    CHECK(tip:find("Alliance assaulting", 1, true) ~= nil, "W: and that it is being assaulted", tip)
    CHECK(tip:find("Click: point the arrow at the Blacksmith (Commander Orders)", 1, true) ~= nil,
        "W: and what a click does", tip)
    pips[2].__scripts.OnEnter(pips[2])
    CHECK(table.concat(tipLines, "\n"):find("Held by the Horde", 1, true) ~= nil, "W: a held flag says who holds it")

    -- The match ends: the waypoint goes and the arrow goes back to yours
    LeaveBasin()
    CHECK(#calls.removeBy == 1 and calls.removeBy[1] == "Oracle", "W: leaving the basin removes the Oracle waypoint",
        calls.removeBy[1])
    CHECK(calls.arrow[#calls.arrow] == "w1", "W: and hands the arrow back to the waypoint it took",
        calls.arrow[#calls.arrow])

    -- ...unless you had moved the arrow yourself in the meantime
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(4)
    active = { uid = "w5", why = "PINNED", source = "user" }
    LeaveBasin()
    CHECK(#calls.removeBy == 1, "W: the Oracle waypoint still goes")
    CHECK(#calls.arrow == 1, "W: but your newer choice of arrow is left alone", calls.arrow[#calls.arrow])

    -- You pin something else mid-match and a later flag click takes it: the
    -- arrow goes back to that newer choice, not the one you came in with
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    active = { uid = "w5", why = "PINNED", source = "user" }
    ClickPip(1)
    LeaveBasin()
    CHECK(calls.arrow[#calls.arrow] == "w5", "W: the arrow goes back to the waypoint the LAST click took",
        calls.arrow[#calls.arrow])

    -- You REACHED the flag (the common case): Orders cleared and unpinned it,
    -- the arrow fell to another mark as the closest. The match ends: the
    -- arrow still goes back to the waypoint the click took
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    ArriveAtFlag({ uid = "w5", why = "CLOSEST", source = "user" })
    LeaveBasin()
    CHECK(#calls.removeBy == 1, "W: reached flag: the Oracle cleanup still runs")
    CHECK(#calls.arrow == 2 and calls.arrow[2] == "w1",
        "W: reached flag: the arrow goes back to the waypoint the click took", calls.arrow[#calls.arrow])
    -- ...and with nothing else to follow after reaching it
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    ArriveAtFlag(nil)
    LeaveBasin()
    CHECK(calls.arrow[#calls.arrow] == "w1", "W: reached flag, nothing else: the arrow goes back",
        calls.arrow[#calls.arrow])
    -- Reached, then you pinned something else: your newer choice stands
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    ArriveAtFlag(nil)
    active = { uid = "w5", why = "PINNED", source = "user" }
    LeaveBasin()
    CHECK(#calls.arrow == 1, "W: reached, then pinned elsewhere: left alone", calls.arrow[#calls.arrow])
    -- Reached, then you started a route: the route keeps the arrow
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    ArriveAtFlag(nil)
    active = { uid = "w5", why = "ROUTE", source = "QuestLog" }
    LeaveBasin()
    CHECK(#calls.arrow == 1, "W: reached, then a route: left alone", calls.arrow[#calls.arrow])
    -- NOT reached, but you cleared the arrow (the flag still stands, holding
    -- nothing): the Clear stands
    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)
    Reset({ uid = "w1", why = "PINNED", source = "user" })
    ClickPip(3)
    active = nil
    LeaveBasin()
    CHECK(#calls.arrow == 1, "W: a Clear mid-match is not undone at the match's end", calls.arrow[#calls.arrow])

    -- Outside Arathi Basin a flag means nothing to walk to
    Reset(nil)
    printLog = {}
    ClickPip(3)
    CHECK(#calls.add == 0, "W: outside the basin, no waypoint")
    CHECK(printLog[#printLog] and printLog[#printLog]:find("inside Arathi Basin", 1, true) ~= nil,
        "W: and it says so", printLog[#printLog])

    zone.inBasin = true
    Fire("PLAYER_ENTERING_WORLD")
    Advance(1)

    -- The map has not placed the flag: nothing guessed
    placed = false
    Reset(nil)
    ClickPip(3)
    CHECK(#calls.add == 0, "W: no POI position, no waypoint")
    CHECK(printLog[#printLog] and printLog[#printLog]:find("has not placed the Blacksmith", 1, true) ~= nil,
        "W: and it says so", printLog[#printLog])
    placed = true

    -- Orders switched off: says so, pins nothing
    orders.refuse = "disabled"
    Reset(nil)
    ClickPip(3)
    CHECK(#calls.arrow == 0, "W: Orders off: nothing pinned")
    CHECK(printLog[#printLog] and printLog[#printLog]:find("turned off", 1, true) ~= nil,
        "W: and it says Orders is off", printLog[#printLog])
    orders.refuse = nil

    -- Orders not loaded: the place as a /way line, so a click is never nothing
    CommanderOrders = nil
    ClickPip(3)
    CHECK(printLog[#printLog] and printLog[#printLog]:find("/way #1461 46.40 45.20", 1, true) ~= nil,
        "W: no Orders: the flag as a /way line", printLog[#printLog])
    pips[3].__scripts.OnEnter(pips[3])
    CHECK(table.concat(tipLines, "\n"):find("/way line", 1, true) ~= nil, "W: and the tooltip says so")
    LeaveBasin()

    C_AreaPoiInfo.GetAreaPOIInfo = realPOIInfo
    CommanderOrders = nil
    rawset(GameTooltip, "SetOwner", nil)
    rawset(GameTooltip, "SetText", nil)
    rawset(GameTooltip, "AddLine", nil)
end

CHECK(#harnessErrors == 0, "no errors across the whole run", harnessErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
