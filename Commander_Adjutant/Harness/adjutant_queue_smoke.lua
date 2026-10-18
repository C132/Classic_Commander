-- Commander Adjutant smoke (luajit) — the 2.2.0 deployment countdown: the bar
-- under the battleground invite, the free-standing timer that survives Hide,
-- the closing warning, and the port-expiration fallback. Mock modeled on
-- Commander_Production/Harness.
--
--   luajit Commander_Adjutant/Harness/adjutant_queue_smoke.lua

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

-- Combat lockdown, the way the client applies it: a frame built from a
-- secure template is protected, and so is its PARENT (hiding the parent
-- would hide the secure child -- the field report was exactly that parent's
-- Hide). In combat, showing, hiding, moving or sizing one is refused and
-- reported as ADDON_ACTION_BLOCKED; here it is recorded and dropped.
inCombatNow = false
function InCombatLockdown() return inCombatNow end
blockedCalls = {}
function Blocked(s, what)
    if not (inCombatNow and rawget(s, "__protected")) then return false end
    blockedCalls[#blockedCalls + 1] = (rawget(s, "__name") or "?") .. ":" .. what
    return true
end

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
        local fn = function(s, w) if Blocked(s, "SetWidth") then return end s.__w = w end
        rawset(self, key, fn); return fn
    end
    if key == "GetWidth" then
        local fn = function(s) return s.__w or 0 end
        rawset(self, key, fn); return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) if Blocked(s, "SetSize") then return end s.__w, s.__h = w, h end
        rawset(self, key, fn); return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            if Blocked(s, "SetPoint") then return end
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
        rawset(self, key, fn); return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) if Blocked(s, "ClearAllPoints") then return end s.__points = {} end
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
        local fn = function(s) if Blocked(s, "Show") then return end s.__shown = true end
        rawset(self, key, fn); return fn
    end
    if key == "Hide" then
        local fn = function(s) if Blocked(s, "Hide") then return end s.__shown = false end
        rawset(self, key, fn); return fn
    end
    if key == "SetShown" then
        local fn = function(s, shown) if Blocked(s, "SetShown") then return end s.__shown = not not shown end
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
    if key == "SetAttribute" then
        local fn = function(s, name, value)
            s.__attributes = s.__attributes or {}
            s.__attributes[name] = value
        end
        rawset(self, key, fn); return fn
    end
    if key == "GetAttribute" then
        local fn = function(s, name) return s.__attributes and s.__attributes[name] end
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
    if template and template:find("Secure") then
        f.__protected = true
        if parent then parent.__protected = true end
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
-- Battlefield queue mock
-- ---------------------------------------------------------------------------
local queues = {}        -- index -> { status, mapName, expiration (nil = client reports nothing) }
local ports = {}         -- AcceptBattlefieldPort call log
MAX_BATTLEFIELD_QUEUES = 3
function GetMaxBattlefieldID() return 3 end
function GetBattlefieldStatus(index)
    local q = queues[index]
    if not q then return "none" end
    return q.status, q.mapName, nil, nil
end
function GetBattlefieldPortExpiration(index)
    local q = queues[index]
    return (q and q.expiration) or 0
end
-- PROTECTED on this client: only secure code may call it. The mock keeps a
-- flag the way the client keeps a taint check, and the addon's own frames
-- are never secure -- so a call from anything but the dialog's own button
-- is logged as forbidden rather than as a port.
local secureCall = false
local forbidden = 0
function AcceptBattlefieldPort(index, accept)
    if not secureCall then
        forbidden = forbidden + 1
        return false
    end
    ports[#ports + 1] = { index = index, accept = accept }
    return true
end

-- The invite windows. PVPReadyDialog is what this client actually pops;
-- the static popup is still defined, so both paths are exercised.
PVPReadyDialog = NewWidget("Frame", "PVPReadyDialog")
PVPReadyDialog:Hide()
PVPReadyDialog:SetSize(320, 110)
-- Its Enter button, with Blizzard's own XML OnClick: the protected call from
-- secure code, off the dialog's activeIndex (which survives a Hide)
PVPReadyDialog.enterButton = NewWidget("Button", "PVPReadyDialogEnterBattleButton")
PVPReadyDialogEnterBattleButton = PVPReadyDialog.enterButton
PVPReadyDialog.enterButton.__scripts.OnClick = function(self)
    secureCall = true
    local ok = PVPReadyDialog.activeIndex and AcceptBattlefieldPort(PVPReadyDialog.activeIndex, true)
    secureCall = false
    return ok
end
-- A secure "click" action presses the button its clickbutton attribute
-- names; the addon's OnClick hook runs after it, the way HookScript does
local function SecureClick(button, mouseButton)
    if button.__attributes and button.__attributes.type1 == "click" and mouseButton == "LeftButton" then
        local target = button.__attributes.clickbutton1
        if target and target.__scripts.OnClick then target.__scripts.OnClick(target, mouseButton) end
    end
    if button.__scripts.OnClick then button.__scripts.OnClick(button, mouseButton) end
end
local staticPopup = NewWidget("Frame", "StaticPopup1")
staticPopup:Hide()
staticPopup:SetSize(320, 110)
staticPopup.which = "CONFIRM_BATTLEFIELD_ENTRY"
function StaticPopup_FindVisible(which, data)
    if which == "CONFIRM_BATTLEFIELD_ENTRY" and staticPopup:IsShown() and staticPopup.data == data then
        return staticPopup
    end
    return nil
end

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
Load(ADDONS .. "/Commander_Adjutant/CommanderAdjutantDB.lua")
Load(ADDONS .. "/Commander_Adjutant/CommanderAdjutant.lua")
Fire("ADDON_LOADED", "Commander_Adjutant")
Fire("PLAYER_LOGIN")

local db = CommanderAdjutantDB
local banner = _G.CommanderAdjutantBanner
local function BannerText()
    local fs = banner.__fontStrings and banner.__fontStrings[1]
    return fs and fs.__text
end
local function AttachBar() return _G.CommanderAdjutantPortBar end
local function FloatBar() return _G.CommanderAdjutantQueueTimer end
local function BarText(bar) return bar and bar.text and bar.text.__text end

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------
CHECK(db.ShowQueueTimer == true, "defaults: countdown on")
CHECK(db.KeepQueueTimer == true, "defaults: kept after Hide")
CHECK(db.QueueTimerWarning == 10, "defaults: 10s closing warning", tostring(db.QueueTimerWarning))
CHECK(db.AlertQueuePop == true, "defaults: pop banner on")
CHECK(db.QueueTimerLocked == true, "defaults: float locked", tostring(db.QueueTimerLocked))
CHECK(db.QueueTimerStyle == "DARK", "defaults: float chrome style", tostring(db.QueueTimerStyle))

-- Nothing queued: no bar, and no OnUpdate left running
Advance(20)
CHECK(not AttachBar() or not AttachBar():IsShown(), "idle: no bar before any invite")

-- ---------------------------------------------------------------------------
-- A: the invite pops with the dialog up
-- ---------------------------------------------------------------------------
queues[1] = { status = "confirm", mapName = "Arathi Basin", expiration = 79 }
PVPReadyDialog.activeIndex = 1
PVPReadyDialog:Show()
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
CHECK(BannerText() == "Transport ready: Arathi Basin", "A: pop announces the battleground", BannerText())
Advance(0.1)
CHECK(AttachBar():IsShown(), "A: bar rides the invite dialog")
CHECK(BarText(AttachBar()) == "Enter within  1:19", "A: reads the real port expiration", BarText(AttachBar()))
CHECK(not FloatBar():IsShown(), "A: no free-standing timer while the dialog is up")
local anchor = AttachBar().__points and AttachBar().__points[1]
CHECK(anchor and anchor.rel == PVPReadyDialog and anchor.point == "TOP" and anchor.relPoint == "BOTTOM",
    "A: anchored under the dialog")
CHECK(AttachBar():GetWidth() == 320, "A: matches the dialog's width", AttachBar():GetWidth())
-- 79 of an 80-second window: nearly full, and demonstrably not clipped
local usable = 320 - 12
local fill = AttachBar().fill.__w
CHECK(fill > usable * 0.9 and fill <= usable, "A: drain bar starts nearly full", fill)

-- B: the countdown follows the clock down
queues[1].expiration = 61
Advance(1)
CHECK(BarText(AttachBar()) == "Enter within  1:01", "B: minute boundary", BarText(AttachBar()))
queues[1].expiration = 45
Advance(1)
CHECK(BarText(AttachBar()) == "Enter within  0:45", "B: under a minute", BarText(AttachBar()))
CHECK(AttachBar().fill.__w < usable * 0.6, "B: bar drains with it", AttachBar().fill.__w)

-- ---------------------------------------------------------------------------
-- C: Hide the invite — the whole point of the feature
-- ---------------------------------------------------------------------------
PVPReadyDialog:Hide()
Advance(0.2)
CHECK(not AttachBar():IsShown(), "C: attached bar goes with the dialog")
CHECK(FloatBar():IsShown(), "C: free-standing timer takes over")
CHECK(BarText(FloatBar()) == "Arathi Basin  0:45", "C: names the battleground", BarText(FloatBar()))
CHECK(FloatBar().portIndex == 1, "C: knows which queue it would port into")

-- D: closing warning, once
queues[1].expiration = 12
Advance(1)
CHECK(BannerText() ~= "Transport leaving: Arathi Basin", "D: no warning above the threshold")
queues[1].expiration = 9
Advance(1)
CHECK(BannerText() == "Transport leaving: Arathi Basin", "D: warning at the threshold", BannerText())
CHECK(playedSounds[#playedSounds] == SOUNDKIT.RAID_WARNING, "D: with the alert sound")
local warnedSounds = #playedSounds
queues[1].expiration = 8
Advance(1)
CHECK(#playedSounds == warnedSounds, "D: warning fires once per invite", #playedSounds)

-- D2: a window that runs out while the slot still says "confirm" stops being
-- drawn, and does not re-announce itself as a fresh invite
banner.__fontStrings[1].__text = nil
queues[1].expiration = 0
Advance(0.3)
CHECK(not FloatBar():IsShown() and not AttachBar():IsShown(), "D2: expired window draws nothing")
CHECK(BannerText() == nil, "D2: and does not announce itself again", BannerText())
-- Back to a live window, the way the client would say so
queues[1].expiration = 8
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.1)
CHECK(FloatBar():IsShown(), "D2: a status update brings a live window back")
CHECK(BannerText() == nil, "D2: and the same invite never announces twice", BannerText())

-- E: clicking the free-standing timer ports you in -- through the dialog's
-- own Enter button, because the port call is protected
local enter = FloatBar().enter
CHECK(enter:GetAttribute("type1") == "click"
    and enter:GetAttribute("clickbutton1") == PVPReadyDialog.enterButton,
    "E: the timer's click is a secure press of the dialog's Enter button")
SecureClick(enter, "LeftButton")
CHECK(#ports == 1 and ports[1].index == 1 and ports[1].accept == true,
    "E: click accepts the port for that queue")
CHECK(forbidden == 0, "E: nothing insecure ever touched AcceptBattlefieldPort", forbidden)

-- F: the invite resolves — everything clears and the ticker stops
queues[1] = nil
staticPopup:Hide()
Advance(0.2)
CHECK(not AttachBar():IsShown() and not FloatBar():IsShown(), "F: both bars clear")
local countdownFrame
for _, frame in ipairs(allFrames) do
    if frame.__scripts.OnUpdate and frame.__name == nil and frame.__kind == "Frame" then
        countdownFrame = frame
    end
end
CHECK(countdownFrame == nil, "F: the countdown stops ticking with nothing queued")

-- ---------------------------------------------------------------------------
-- G: the static popup path (data carries the queue index)
-- ---------------------------------------------------------------------------
queues[2] = { status = "confirm", mapName = "Warsong Gulch", expiration = 30 }
staticPopup.data = 2
staticPopup:Show()
Fire("UPDATE_BATTLEFIELD_STATUS", 2)
Advance(0.1)
CHECK(AttachBar():IsShown(), "G: bar rides the static popup too")
local gAnchor = AttachBar().__points and AttachBar().__points[1]
CHECK(gAnchor and gAnchor.rel == staticPopup, "G: anchored to the popup that is up")
CHECK(BarText(AttachBar()) == "Enter within  0:30", "G: reads that queue's expiration", BarText(AttachBar()))
queues[2] = nil
staticPopup:Hide()
Advance(0.2)

-- ---------------------------------------------------------------------------
-- H: a client that will not report an expiration falls back to the window
-- ---------------------------------------------------------------------------
queues[1] = { status = "confirm", mapName = "Eye of the Storm" }   -- no expiration
PVPReadyDialog.activeIndex = 1
PVPReadyDialog:Show()
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.1)
CHECK(BarText(AttachBar()) == "Enter within  1:20", "H: falls back to the 80s window", BarText(AttachBar()))
-- 20.4s in on top of the 0.1 above: half a second clear of the 1:00/1:01
-- boundary, so the check is about the countdown running, not about float drift
Advance(20.4)
CHECK(BarText(AttachBar()) == "Enter within  1:00", "H: and counts itself down", BarText(AttachBar()))

-- I: an expiration reported in milliseconds is read as such, not as hours
queues[1].expiration = 45000
Advance(1)
CHECK(BarText(AttachBar()) == "Enter within  0:45", "I: milliseconds normalized", BarText(AttachBar()))
queues[1] = nil
PVPReadyDialog:Hide()
Advance(0.2)

-- ---------------------------------------------------------------------------
-- J: settings actually gate it
-- ---------------------------------------------------------------------------
db.KeepQueueTimer = false
queues[1] = { status = "confirm", mapName = "Arathi Basin", expiration = 60 }
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.1)
CHECK(not FloatBar():IsShown(), "J: Keep After Hiding off leaves nothing behind")
CHECK(not AttachBar():IsShown(), "J: and no dialog means no attached bar either")
db.KeepQueueTimer = true

db.ShowQueueTimer = false
Advance(0.2)
CHECK(not FloatBar():IsShown() and not AttachBar():IsShown(), "J: countdown off hides both bars")
-- ...but the pop banner is a separate switch
queues[1] = nil
Advance(0.2)
banner.__fontStrings[1].__text = nil
queues[2] = { status = "confirm", mapName = "Alterac Valley", expiration = 70 }
Fire("UPDATE_BATTLEFIELD_STATUS", 2)
CHECK(BannerText() == "Transport ready: Alterac Valley",
    "J: the pop banner still fires with the countdown off", BannerText())
db.ShowQueueTimer = true
queues[2] = nil
Advance(0.2)

db.AlertQueuePop = false
banner.__fontStrings[1].__text = nil
queues[1] = { status = "confirm", mapName = "Warsong Gulch", expiration = 70 }
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
CHECK(BannerText() == nil, "J: pop banner off stays quiet", BannerText())
db.AlertQueuePop = true
queues[1] = nil
Advance(0.2)

-- K: the master switch stands down the whole announcer
db.EnableAdjutant = false
banner.__fontStrings[1].__text = nil
queues[1] = { status = "confirm", mapName = "Arathi Basin", expiration = 70 }
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.2)
CHECK(BannerText() == nil, "K: master switch silences the pop", BannerText())
CHECK(not FloatBar():IsShown() and not AttachBar():IsShown(), "K: and shows no bar")
db.EnableAdjutant = true
queues[1] = nil
Advance(0.2)

-- ---------------------------------------------------------------------------
-- L: /cadj timer demo
-- ---------------------------------------------------------------------------
CommanderAdjutant_TestQueueTimer()
Advance(0.1)
CHECK(FloatBar():IsShown(), "L: demo puts the timer on screen")
CHECK(BarText(FloatBar()) == "Alterac Valley  0:20", "L: demo counts from 20", BarText(FloatBar()))
CHECK(FloatBar().portIndex == nil, "L: demo timer ports nowhere")
Advance(21)
CHECK(not FloatBar():IsShown(), "L: demo clears itself")

-- ---------------------------------------------------------------------------
-- M: unlocked with nothing queued — the drag placeholder
-- ---------------------------------------------------------------------------
db.QueueTimerLocked = false
Commander.Notify(COMMANDER_ADJUTANT_EVENTS.UPDATE)
Advance(0.2)
CHECK(FloatBar():IsShown(), "M: unlocked frame stays on screen to be dragged")
CHECK(BarText(FloatBar()) == "Deployment  0:00", "M: parked placeholder", BarText(FloatBar()))
local color = FloatBar().text.__color
CHECK(color and color[2] == 0.85, "M: the placeholder is not painted as an expiring invite", color and color[2])
db.QueueTimerLocked = true
Commander.Notify(COMMANDER_ADJUTANT_EVENTS.UPDATE)
Advance(0.2)
CHECK(not FloatBar():IsShown(), "M: locking it again puts it away")

-- ---------------------------------------------------------------------------
-- N: combat. The floating timer parents the secure Enter button, so it is a
-- protected frame: nothing may show, hide, move or size it in combat (the
-- field report: CommanderAdjutantQueueTimer:Hide() blocked 14 times in one
-- battleground). The countdown must keep running anyway.
-- ---------------------------------------------------------------------------
CHECK(FloatBar().__protected == true, "N: the timer is protected, as on the client (it parents a secure button)")
banner.__fontStrings[1].__text = nil
queues[1] = { status = "confirm", mapName = "Warsong Gulch", expiration = 60 }
PVPReadyDialog.activeIndex = 1
PVPReadyDialog:Show()
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.1)
CHECK(AttachBar():IsShown() and not FloatBar():IsShown(), "N: out of combat, the bar rides the dialog")
inCombatNow = true
blockedCalls = {}
-- The dialog is dismissed mid-fight: the timer must come up, but the
-- protected frame cannot be shown -- the plain bar stands in on its spot
PVPReadyDialog:Hide()
Advance(0.3)
CHECK(#blockedCalls == 0, "N: nothing blocked while the dialog goes away in combat", blockedCalls[1])
CHECK(AttachBar():IsShown() and (BarText(AttachBar()) or ""):find("^Warsong Gulch") ~= nil,
    "N: the plain bar stands in for the timer", BarText(AttachBar()))
local sp = AttachBar().__points and AttachBar().__points[1]
CHECK(sp and sp.rel == FloatBar() and sp.point == "CENTER", "N: ...on the timer's own spot")
-- The invite resolves mid-fight: everything must go, still without a block
queues[1] = nil
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.3)
CHECK(#blockedCalls == 0, "N: nothing blocked when the invite clears in combat", blockedCalls[1])
CHECK(not AttachBar():IsShown(), "N: the stand-in goes")
-- A timer that WAS up when combat began is hidden by alpha, not Hide()
inCombatNow = false
queues[1] = { status = "confirm", mapName = "Eye of the Storm", expiration = 50 }
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.2)
CHECK(FloatBar():IsShown(), "N: out of combat the real timer is up")
inCombatNow = true
queues[1] = nil
Fire("UPDATE_BATTLEFIELD_STATUS", 1)
Advance(0.3)
CHECK(#blockedCalls == 0, "N: no blocked Hide on the protected timer", blockedCalls[1])
CHECK(FloatBar():GetAlpha() == 0, "N: it is hidden by alpha instead")
-- Combat ends: the real state is put right
inCombatNow = false
Fire("PLAYER_REGEN_ENABLED")
Advance(0.2)
CHECK(not FloatBar():IsShown() and FloatBar():GetAlpha() == 1, "N: after combat the timer is really hidden, alpha restored")

-- ---------------------------------------------------------------------------
-- O: the repair alert names and marks the nearest repair (2.3.0). Commander
-- Logistics is a stub here (its own learning and the real Orders waypoint are
-- Commander_Logistics/Harness/logistics_orders_smoke.lua); what is checked is
-- Adjutant's half: the words on the banner, one offer per alert, never in
-- combat, withdrawn when mended, every switch, and nothing escaping.
-- ---------------------------------------------------------------------------
do
    db.EnableAdjutant, db.AlertRepair = true, true
    CHECK(db.RepairWaypoint == true, "O: Mark the Nearest Repair defaults on")
    local dura = 1
    GetInventoryItemDurability = function(slot)
        if slot == 5 then return math.floor(dura * 100), 100 end
        return nil
    end
    local function Wear(ratio) dura = ratio; Fire("UPDATE_INVENTORY_DURABILITY") end
    local offers, clears, lastClearOpts = {}, 0, nil
    local vendor = { name = "Smith Argus", map = 1429, x = 0.416, y = 0.655, yards = 340 }
    local function StubLogistics()
        CommanderLogistics_NearestRepair = function() return vendor end
        CommanderLogistics_RepairWaypoint = function(opts) offers[#offers + 1] = opts; return true, "w4", vendor end
        CommanderLogistics_ClearRepairWaypoint = function(opts) clears = clears + 1; lastClearOpts = opts; return 1 end
        CommanderLogistics_FormatYards = function(y) return string.format("%d yd", y) end
    end
    local errs0 = #harnessFailedErrors

    -- Without Logistics: the alert as it always was
    Wear(1)
    Wear(0.1)
    CHECK(BannerText() == "Units require repair", "O: no Logistics, the plain alert", BannerText())
    Wear(1)

    -- With a known vendor: named on the banner, marked once, as an offer
    StubLogistics()
    Wear(0.1)
    CHECK(BannerText() == "Units require repair: Smith Argus, 340 yd", "O: the banner names the nearest repair", BannerText())
    CHECK(#offers == 1, "O: ...and marks it once", #offers)
    CHECK(offers[1] and offers[1].temporary == true and offers[1].quiet == true,
        "O: ...as a temporary, quiet offer that never takes a chosen arrow")
    Wear(0.05)
    CHECK(#offers == 1, "O: more wear does not offer again", #offers)
    -- Mended: the offer is withdrawn, once
    Wear(1)
    CHECK(clears == 1, "O: mended gear takes the mark down", clears)
    CHECK(type(lastClearOpts) == "table" and lastClearOpts.offerOnly == true,
        "O: ...the offer only: a repair waypoint you asked for on the same line is yours (review 2026-10-05)")
    Wear(1)
    CHECK(clears == 1, "O: ...once", clears)

    -- In combat: the banner, but no mark until the fight is over
    inCombatNow = true
    Wear(0.1)
    CHECK(BannerText() == "Units require repair: Smith Argus, 340 yd", "O: in combat the banner still names it", BannerText())
    CHECK(#offers == 1, "O: ...but nothing is marked mid-fight", #offers)
    inCombatNow = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(#offers == 2, "O: the mark lands when combat ends", #offers)
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(#offers == 2, "O: ...once", #offers)
    Wear(1)
    -- Mended before the fight ended: nothing left to offer afterwards
    inCombatNow = true
    Wear(0.1)
    Wear(1)
    inCombatNow = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(#offers == 2, "O: gear mended mid-fight is not marked afterwards", #offers)

    -- The switches
    db.RepairWaypoint = false
    Wear(0.1)
    CHECK(BannerText() == "Units require repair: Smith Argus, 340 yd" and #offers == 2,
        "O: Mark the Nearest Repair off: named, not marked", #offers)
    Wear(1)
    db.RepairWaypoint = true
    db.AlertRepair = false
    Wear(0.1)
    CHECK(#offers == 2, "O: the repair alert off: no mark either", #offers)
    Wear(1)
    db.AlertRepair = true

    -- Nothing learned: the plain alert, no mark
    CommanderLogistics_NearestRepair = function() return nil, "none" end
    Wear(0.1)
    CHECK(BannerText() == "Units require repair" and #offers == 2, "O: no vendor known: plain alert, no mark", BannerText())
    Wear(1)

    -- A Logistics that throws never takes the alert down with it
    CommanderLogistics_NearestRepair = function() error("logistics blew up") end
    Wear(0.1)
    CHECK(BannerText() == "Units require repair", "O: a throwing Logistics still gets the plain alert", BannerText())
    Wear(1)
    StubLogistics()
    CommanderLogistics_RepairWaypoint = function() error("waypoint blew up") end
    Wear(0.1)
    CHECK(BannerText() == "Units require repair: Smith Argus, 340 yd", "O: a throwing mark still names the vendor")
    Wear(1)
    CHECK(#harnessFailedErrors == errs0, "O: nothing escaped", harnessFailedErrors[#harnessFailedErrors])
    CommanderLogistics_NearestRepair, CommanderLogistics_RepairWaypoint = nil, nil
    CommanderLogistics_ClearRepairWaypoint, CommanderLogistics_FormatYards = nil, nil
end

-- ---------------------------------------------------------------------------
-- P: full bags name and mark the nearest vendor (2.4.0, Commander Orders
-- 3.1). Logistics is a stub again; its "Vendor" supply line through the REAL
-- Orders and its locator is logistics_orders_smoke.lua section I.
-- ---------------------------------------------------------------------------
do
    db.EnableAdjutant, db.AlertBagsFull = true, true
    CHECK(db.VendorWaypoint == true, "P: Mark the Nearest Vendor defaults on")
    local free = 4
    C_Container = {
        GetContainerNumSlots = function() return 16 end,
        GetContainerNumFreeSlots = function(bag) return bag == 0 and free or 0 end,
    }
    local function Fill(n) free = n; Fire("BAG_UPDATE_DELAYED") end
    local offers, clears, clearOpts = {}, {}, {}
    local vendor = { name = "Innkeeper Grosk", map = 1411, x = 0.5, y = 0.5, yards = 120 }
    local function StubLogistics()
        CommanderLogistics_Nearest = function(kind) if kind == "Vendor" then return vendor end end
        CommanderLogistics_SupplyWaypoint = function(kind, opts)
            offers[#offers + 1] = { kind = kind, opts = opts }
            return true, "w9", vendor
        end
        CommanderLogistics_ClearSupplyWaypoint = function(kind, opts) clears[#clears + 1] = kind; clearOpts[#clearOpts + 1] = opts; return 1 end
        CommanderLogistics_FormatYards = function(y) return string.format("%d yd", y) end
    end
    local errs0 = #harnessFailedErrors

    Fill(4)
    Fill(0)
    CHECK(BannerText() == "Storage at full capacity", "P: no Logistics, the plain alert", BannerText())
    Fill(4)

    StubLogistics()
    Fill(0)
    CHECK(BannerText() == "Storage at full capacity: Innkeeper Grosk, 120 yd", "P: the banner names the nearest vendor", BannerText())
    CHECK(#offers == 1 and offers[1].kind == "Vendor", "P: ...and marks it once, on the vendor line", #offers)
    CHECK(offers[1] and offers[1].opts.temporary == true and offers[1].opts.quiet == true,
        "P: ...as a temporary, quiet offer")
    Fill(0)
    CHECK(#offers == 1, "P: still full: no second offer", #offers)
    Fill(1)
    CHECK(#clears == 1 and clears[1] == "Vendor", "P: a free slot takes the mark down", #clears)
    CHECK(type(clearOpts[1]) == "table" and clearOpts[1].offerOnly == true,
        "P: ...the offer only: a vendor waypoint you asked for on the same line is yours (review 2026-10-05)")
    Fill(2)
    CHECK(#clears == 1, "P: ...once", #clears)

    inCombatNow = true
    Fill(0)
    CHECK(#offers == 1, "P: nothing is marked mid-fight", #offers)
    inCombatNow = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(#offers == 2, "P: the mark lands when combat ends", #offers)
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(#offers == 2, "P: ...once", #offers)
    Fill(3)
    inCombatNow = true
    Fill(0)
    Fill(3)
    inCombatNow = false
    Fire("PLAYER_REGEN_ENABLED")
    CHECK(#offers == 2, "P: bags emptied mid-fight are not marked afterwards", #offers)

    db.VendorWaypoint = false
    Fill(0)
    CHECK(BannerText() == "Storage at full capacity: Innkeeper Grosk, 120 yd" and #offers == 2,
        "P: Mark the Nearest Vendor off: named, not marked", #offers)
    Fill(3)
    db.VendorWaypoint = true
    db.AlertBagsFull = false
    Fill(0)
    CHECK(#offers == 2, "P: the full-bags alert off: no mark either", #offers)
    Fill(3)
    db.AlertBagsFull = true

    CommanderLogistics_Nearest = function() return nil, "none" end
    Fill(0)
    CHECK(BannerText() == "Storage at full capacity" and #offers == 2, "P: no vendor known: plain alert, no mark", BannerText())
    Fill(3)
    CommanderLogistics_Nearest = function() error("logistics blew up") end
    Fill(0)
    CHECK(BannerText() == "Storage at full capacity", "P: a throwing Logistics still gets the plain alert", BannerText())
    Fill(3)
    StubLogistics()
    CommanderLogistics_SupplyWaypoint = function() error("waypoint blew up") end
    Fill(0)
    CHECK(BannerText() == "Storage at full capacity: Innkeeper Grosk, 120 yd", "P: a throwing mark still names the vendor")
    Fill(3)
    CHECK(#harnessFailedErrors == errs0, "P: nothing escaped", harnessFailedErrors[#harnessFailedErrors])
    CommanderLogistics_Nearest, CommanderLogistics_SupplyWaypoint = nil, nil
    CommanderLogistics_ClearSupplyWaypoint, CommanderLogistics_FormatYards = nil, nil
end

CHECK(#harnessFailedErrors == 0, "no errors across the run", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
