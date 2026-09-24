-- Commander Recovery smoke (luajit) -- the 2.2.0 battleground auto-release:
-- where it fires, everything that holds it back, the retry loop, and the
-- existing casualty/corpse-order flow it had to leave intact. Mock lifted
-- from Commander_Adjutant/Harness.
--
--   luajit Commander_Recovery/Harness/recovery_release_smoke.lua

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

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err) harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err) end
end

local NUMERIC_GETTERS = {
    GetHeight = 0, GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2,
    GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetStringWidth = 10, GetID = 1, GetNumPoints = 1,
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
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn); return fn
    end
    -- Width is tracked for real: the drain bar's fill is sized off its
    -- parent's width, so a mock that always answered 0 would assert nothing
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
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
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
end

local allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
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
GameFontNormalLarge = NewWidget("Font")
GameFontNormalHuge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
BACKDROP_SLIDER_8_8 = {}

SOUNDKIT = {
    IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    IG_CHARACTER_INFO_TAB = 841, READY_CHECK = 8960,
    IG_QUEST_LIST_COMPLETE = 875, RAID_WARNING = 8959,
    RAID_BOSS_EMOTE_WARNING = 37666,
}
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
C_AddOns = { GetAddOnMetadata = function() return "2.2.0" end }

local timers, tickers = {}, {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn, cancelled = false }
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

function UnitClass() return "Warrior", "WARRIOR" end
function UnitHealth() return 100 end
function UnitHealthMax() return 100 end
function GetNumGroupMembers() return 0 end
function GetInventoryItemDurability() return nil end
C_Container = {
    GetContainerNumSlots = function() return 16 end,
    GetContainerNumFreeSlots = function() return 4 end,
}

-- ---------------------------------------------------------------------------
-- Death / battleground mock. The player's state is driven by hand so the
-- retry loop is tested against a server that has not answered yet -- which is
-- the whole reason the loop exists.
-- ---------------------------------------------------------------------------
local playerDead, playerGhost = false, false
local instanceType = "none"
local battlefieldWinner = nil
local resurrectOfferer = nil
local selfResurrects = {}
local repops = {}
local hiddenPopups = {}

function UnitIsDead(unit) return playerDead and not playerGhost end
function UnitIsGhost(unit) return playerGhost end
function UnitIsDeadOrGhost(unit) return playerDead or playerGhost end
function IsInInstance() return instanceType ~= "none", instanceType end
function GetBattlefieldWinner() return battlefieldWinner end
function ResurrectGetOfferer() return resurrectOfferer end
C_DeathInfo = {
    -- This client has no HasSoulstone; self-resurrects come through here
    GetSelfResurrectOptions = function() return selfResurrects end,
}
function RepopMe() repops[#repops + 1] = now end
function StaticPopup_Hide(which) hiddenPopups[#hiddenPopups + 1] = which end

function GetZoneText() return "Arathi Basin" end
C_Map = {
    GetBestMapForUnit = function() return 1461 end,
    GetPlayerMapPosition = function() return { x = 0.42, y = 0.58 } end,
}

-- Commander Orders, present and enabled, so the corpse-run path is exercised
local issuedOrders = {}
CommanderOrdersDB = { EnableOrders = true }
function CommanderOrders_IssueOrder(mapID, x, y)
    issuedOrders[#issuedOrders + 1] = { mapID = mapID, x = x, y = y }
    CommanderOrdersDB.Waypoint = { mapID = mapID, x = x, y = y }
    return true
end
function CommanderOrders_ClearOrder() CommanderOrdersDB.Waypoint = nil end
-- ===========================================================================
-- Load the framework and the module
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

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

-- Advance the clock and run every OnUpdate the way the client would
local function Advance(seconds, step)
    step = step or 0.1
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
            if not t.done and t.at <= now then
                t.done = true
                t.fn()
            end
        end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Recovery/CommanderRecoveryDB.lua")
Load(ADDONS .. "/Commander_Recovery/CommanderRecovery.lua")
Fire("ADDON_LOADED", "Commander_Recovery")
Fire("PLAYER_LOGIN")

local db = CommanderRecoveryDB

local function Wipe(t) for i = #t, 1, -1 do t[i] = nil end end

-- Reset every per-scenario piece of state: a fresh corpse, no presses logged
local function Scene(kind)
    playerDead, playerGhost = false, false
    instanceType = kind or "pvp"
    battlefieldWinner, resurrectOfferer = nil, nil
    Wipe(selfResurrects); Wipe(repops); Wipe(hiddenPopups); Wipe(printLog)
    Fire("PLAYER_UNGHOST")          -- clears any death still being tracked
    Wipe(printLog)
end

local function Kill()
    playerDead, playerGhost = true, false
    Fire("PLAYER_DEAD")
end

-- The server accepting the release: ghost, then PLAYER_ALIVE
local function ServerReleases()
    playerDead, playerGhost = false, true
    Fire("PLAYER_ALIVE")
end

local function Logged(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern, 1, true) then return line end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
CHECK(db.AutoRelease == true, "defaults: auto-release on")
CHECK(db.AutoReleaseArena == false, "defaults: arenas excluded")
CHECK(db.AutoReleaseDelay == 1, "defaults: one-second delay", tostring(db.AutoReleaseDelay))

-- ---------------------------------------------------------------------------
-- A: the open world is left alone -- this is a battleground feature
-- ---------------------------------------------------------------------------
Scene("none")
Kill()
Advance(20)
CHECK(#repops == 0, "A: no auto-release in the open world", #repops)
CHECK(#issuedOrders == 0, "A: and no corpse order until the spirit is released")

-- ---------------------------------------------------------------------------
-- B: a battleground death releases -- after the delay, not before
-- ---------------------------------------------------------------------------
Scene("pvp")
Kill()
Advance(0.5)
CHECK(#repops == 0, "B: nothing pressed inside the delay", #repops)
Advance(0.6)
CHECK(#repops == 1, "B: released once the delay is up", #repops)
CHECK(Logged("releasing spirit") ~= nil, "B: says so in chat")
CHECK(#hiddenPopups == 0,
    "B: the popup stays up while the release is unconfirmed -- it is the only manual way out")

-- C: the press is repeated until the server answers, then stops dead
Advance(1.1)
CHECK(#repops == 2, "C: pressed again while still lying there", #repops)
Advance(1.1)
CHECK(#repops == 3, "C: and again", #repops)
local announcements = 0
for _, line in ipairs(printLog) do
    if line:find("releasing spirit", 1, true) then announcements = announcements + 1 end
end
CHECK(announcements == 1, "C: announced once for the death, not once per press", announcements)
ServerReleases()
CHECK(hiddenPopups[1] == "DEATH", "C: popup taken down once the release lands", hiddenPopups[1])
local pressed = #repops
Advance(10)
CHECK(#repops == pressed, "C: the loop ends when the release lands", #repops - pressed)
CHECK(#issuedOrders == 1, "C: the corpse-run order still goes out on release", #issuedOrders)

-- ---------------------------------------------------------------------------
-- D: the retry window closes instead of pressing forever
-- ---------------------------------------------------------------------------
Scene("pvp")
Kill()
Advance(60)
CHECK(#repops > 1, "D: kept trying while dead", #repops)
CHECK(#hiddenPopups == 0, "D: a release that never took leaves the popup alone", #hiddenPopups)
CHECK(#repops <= 17, "D: gave up inside the window rather than pressing forever", #repops)

-- ---------------------------------------------------------------------------
-- E: everything that holds it back
-- ---------------------------------------------------------------------------
Scene("pvp")
selfResurrects[1] = { id = 1, name = "Soulstone Resurrection", canUse = true }
Kill()
Advance(20)
CHECK(#repops == 0, "E: a soulstone/reincarnation outranks the graveyard", #repops)
CHECK(#hiddenPopups == 0, "E: and the popup is left alone so it can be used")

Scene("pvp")
selfResurrects[1] = { id = 1, name = "Reincarnation", canUse = false }
Kill()
Advance(20)
CHECK(#repops > 0, "E: a self-res the client says is unusable holds nothing back", #repops)

Scene("pvp")
resurrectOfferer = "Healbot"
Kill()
Advance(20)
CHECK(#repops == 0, "E: an incoming resurrection holds it back", #repops)

Scene("pvp")
battlefieldWinner = 1
Kill()
Advance(20)
CHECK(#repops == 0, "E: nothing to release for once the match is decided", #repops)

-- Feign Death fires PLAYER_DEAD on a hunter who is very much alive
Scene("pvp")
Fire("PLAYER_DEAD")
Advance(20)
CHECK(#repops == 0, "E: Feign Death is not a death", #repops)

-- ---------------------------------------------------------------------------
-- F: the switches
-- ---------------------------------------------------------------------------
Scene("pvp")
db.AutoRelease = false
Kill()
Advance(20)
CHECK(#repops == 0, "F: off means off", #repops)
db.AutoRelease = true

Scene("pvp")
db.EnableRecovery = false
Kill()
Advance(20)
CHECK(#repops == 0, "F: the module's master switch covers it too", #repops)
db.EnableRecovery = true

Scene("arena")
Kill()
Advance(20)
CHECK(#repops == 0, "F: arenas are excluded by default", #repops)

Scene("arena")
db.AutoReleaseArena = true
Kill()
Advance(20)
CHECK(#repops > 0, "F: until arenas are opted in", #repops)
db.AutoReleaseArena = false

Scene("pvp")
db.AutoReleaseDelay = 0
Kill()
CHECK(#repops == 1, "F: an instant delay releases inside the death event itself", #repops)
db.AutoReleaseDelay = 1

Scene("pvp")
db.DeathReport = false
Kill()
Advance(2)
CHECK(#repops > 0, "F: a silent death still releases", #repops)
CHECK(Logged("releasing spirit") == nil, "F: with the report off it says nothing")
db.DeathReport = true

-- ---------------------------------------------------------------------------
-- G: ported in on a corpse -- PLAYER_DEAD is long gone and never fires again
-- ---------------------------------------------------------------------------
Scene("pvp")
playerDead, playerGhost = true, false
Fire("PLAYER_ENTERING_WORLD")
Advance(1.5)
CHECK(#repops == 0, "G: zone-in gets a settle beat before anything is pressed", #repops)
Advance(2)
CHECK(#repops > 0, "G: a corpse that arrived with us is still released", #repops)

-- A live player zoning in is not touched
Scene("pvp")
Fire("PLAYER_ENTERING_WORLD")
Advance(20)
CHECK(#repops == 0, "G: zoning in alive presses nothing", #repops)

-- ---------------------------------------------------------------------------
-- H: the tester answers "would this fire where I am standing?"
-- ---------------------------------------------------------------------------
Scene("none")
CommanderRecovery_Test()
CHECK(Logged("not a battleground") ~= nil, "H: test names the reason it would hold", printLog[#printLog])
CHECK(#repops == 0, "H: and the test never actually releases")

Scene("pvp")
CommanderRecovery_Test()
CHECK(Logged("auto-release armed") ~= nil, "H: test reports armed inside a battleground", printLog[#printLog])
CHECK(Logged("1.0s after you fall") ~= nil, "H: with the configured delay", printLog[#printLog])

Scene("pvp")
selfResurrects[1] = { id = 1, name = "Soulstone Resurrection", canUse = true }
CommanderRecovery_Test()
CHECK(Logged("self-resurrect is ready") ~= nil, "H: test sees the soulstone", printLog[#printLog])

CHECK(#harnessFailedErrors == 0, "no errors across the run", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
