-- Commander Production smoke (luajit) — verification for the 2.2.0 change:
-- Icon Strip direction (ICONS / ICONS_RTL) and the Ready Sound / Ready
-- Callout alert options. Mock modeled on Commander_Meters/Harness.

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
function date(fmt, t) return os.date(fmt or "%c", t or (1000000 + now)) end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

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
    GetWidth = 0, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
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
    -- Recording setters the assertions read back
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
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
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
    if key == "GetFont" then
        local fn = function() return "Fonts\\FRIZQT__.TTF", 10, "" end
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
    if template and template:find("BasicFrameTemplate") then
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalHuge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")

SOUNDKIT = {
    IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    IG_CHARACTER_INFO_TAB = 841, READY_CHECK = 8960,
    IG_QUEST_LIST_COMPLETE = 875, RAID_WARNING = 8959,
}
local playedSounds = {}
function PlaySound(kit) playedSounds[#playedSounds + 1] = kit end
BACKDROP_SLIDER_8_8 = {}

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

-- Timers: tickers support Cancel (the banner fade relies on it)
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
local function RunDueTimers()
    for _, t in ipairs(timers) do
        if not t.done and t.at <= now then
            t.done = true
            t.fn()
        end
    end
end
local function RunTickers(times)
    for _ = 1, times or 1 do
        for _, t in ipairs(tickers) do
            if not t.cancelled then t.fn() end
        end
    end
end

local menuCaptured = {}
local dropdownInits = {}
function UIDropDownMenu_Initialize(frame, fn) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuCaptured[#menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu(level, value, frame)
    menuCaptured = {}
    local init = dropdownInits[frame]
    if init then init(frame) end
end

SlashCmdList = {}

-- Spellbook: two spells, cooldown state the harness controls
local cooldowns = {}  -- slot -> { start, duration }
local SPELLBOOK = {
    [1] = { name = "Lay on Hands", texture = "Interface\\Icons\\LoH", id = 633 },
    [2] = { name = "Divine Shield", texture = "Interface\\Icons\\DS", id = 642 },
}
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", "tex", 0, 2 end
function GetSpellBookItemName(slot) return SPELLBOOK[slot] and SPELLBOOK[slot].name end
function GetSpellBookItemTexture(slot) return SPELLBOOK[slot] and SPELLBOOK[slot].texture end
function GetSpellBookItemInfo(slot) return "SPELL", SPELLBOOK[slot] and SPELLBOOK[slot].id end
function GetSpellCooldown(slot)
    local cd = cooldowns[slot]
    if cd and (cd.start + cd.duration) > now then
        return cd.start, cd.duration, 1
    end
    return 0, 0, 1
end

-- ===========================================================================
-- Load the real framework, then run the migration matrix on the DB file
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    -- Snapshot: handlers may unregister mid-iteration
    local snap = {}
    for i, f in ipairs(list) do snap[i] = f end
    for _, frame in ipairs(snap) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

-- Scenario A: upgrader who had unchecked Ready Chat -> callout NONE
_G.CommanderProductionDB = { EnableProduction = true, ReadyChat = false }
Load(ADDONS .. "/Commander_Production/CommanderProductionDB.lua")
Fire("ADDON_LOADED", "Commander_Production")
CHECK(CommanderProductionDB.ReadyCallout == "NONE", "A: chat opt-out migrates to callout NONE",
    tostring(CommanderProductionDB.ReadyCallout))
CHECK(CommanderProductionDB.ReadyChat == nil, "A: ReadyChat key retired")
CHECK(CommanderProductionDB.ReadySound == "CLICK", "A: sound default CLICK")

-- Scenario B: upgrader with chat on -> callout CHAT (behavior unchanged)
_G.CommanderProductionDB = { EnableProduction = true, ReadyChat = true }
Load(ADDONS .. "/Commander_Production/CommanderProductionDB.lua")
Fire("ADDON_LOADED", "Commander_Production")
CHECK(CommanderProductionDB.ReadyCallout == "CHAT", "B: chat-on upgrader lands on callout CHAT",
    tostring(CommanderProductionDB.ReadyCallout))
CHECK(CommanderProductionDB.ReadyChat == nil, "B: ReadyChat key retired")

-- Scenario C: fresh install -> defaults (kept live for the runtime tests)
_G.CommanderProductionDB = nil
Load(ADDONS .. "/Commander_Production/CommanderProductionDB.lua")
Fire("ADDON_LOADED", "Commander_Production")
CHECK(CommanderProductionDB.ReadyCallout == "CHAT" and CommanderProductionDB.ReadySound == "CLICK",
    "C: fresh defaults CHAT + CLICK")
CHECK(CommanderProductionDB.Layout == "BARS_DOWN", "C: layout default")

-- Only the LAST DB watcher may run PLAYER_LOGIN (earlier scenario frames
-- would build duplicate panels against their stale DB upvalues)
local loginList = eventRegistry["PLAYER_LOGIN"]
eventRegistry["PLAYER_LOGIN"] = { loginList[#loginList] }

Load(ADDONS .. "/Commander_Production/CommanderProduction.lua")

-- Both spells on cooldown, then log in: Apply -> Sweep -> Draw
cooldowns[1] = { start = now, duration = 30 }
cooldowns[2] = { start = now, duration = 60 }
Fire("PLAYER_LOGIN")
CHECK(#harnessFailedErrors == 0, "login clean", harnessFailedErrors[1])

local root = _G.CommanderProductionFrame
CHECK(root ~= nil, "root frame exists")

-- ===========================================================================
-- Strip geometry: LTR vs RTL row anchoring
-- ===========================================================================

-- Queue rows are the root-parented frames stamped with a geometry signature
local function ShownRows()
    local rows = {}
    for _, f in ipairs(allFrames) do
        if f.__parent == root and f.geometrySig and f.__shown then
            rows[#rows + 1] = f
        end
    end
    return rows
end

-- Drive a redraw through the real settings-change path
local function Redraw()
    Commander.Notify(COMMANDER_PRODUCTION_EVENTS.UPDATE)
end

local ICON_STEP = 26 + 4  -- ICON_SIZE + ICON_GAP in the addon

CommanderProductionDB.Layout = "ICONS"
Redraw()
local rows = ShownRows()
CHECK(#rows == 2, "ICONS: two rows shown", #rows)
if #rows == 2 then
    local a1, a2 = rows[1].__points[1], rows[2].__points[1]
    CHECK(a1 and a1.point == "TOPLEFT" and a1.relPoint == "TOPLEFT" and a1.x == 0,
        "ICONS: row 1 anchors TOPLEFT at 0", a1 and (a1.point .. "@" .. tostring(a1.x)))
    CHECK(a2 and a2.point == "TOPLEFT" and a2.x == ICON_STEP,
        "ICONS: row 2 marches right", a2 and (a2.point .. "@" .. tostring(a2.x)))
end
CHECK(root.__w == 2 * ICON_STEP - 4, "ICONS: root width fits two icons", tostring(root.__w))

CommanderProductionDB.Layout = "ICONS_RTL"
Redraw()
rows = ShownRows()
CHECK(#rows == 2, "ICONS_RTL: two rows shown", #rows)
if #rows == 2 then
    local a1, a2 = rows[1].__points[1], rows[2].__points[1]
    CHECK(a1 and a1.point == "TOPRIGHT" and a1.relPoint == "TOPRIGHT" and a1.x == 0,
        "ICONS_RTL: row 1 anchors TOPRIGHT at 0", a1 and (a1.point .. "@" .. tostring(a1.x)))
    CHECK(a2 and a2.point == "TOPRIGHT" and a2.x == -ICON_STEP,
        "ICONS_RTL: row 2 marches left", a2 and (a2.point .. "@" .. tostring(a2.x)))
end
CHECK(root.__w == 2 * ICON_STEP - 4, "ICONS_RTL: root width identical", tostring(root.__w))
CHECK(#harnessFailedErrors == 0, "RTL redraw clean", harnessFailedErrors[1])

CommanderProductionDB.Layout = "BARS_DOWN"
Redraw()
rows = ShownRows()
if #rows == 2 then
    local a1 = rows[1].__points[1]
    CHECK(a1 and a1.point == "TOPLEFT", "BARS_DOWN: bars geometry restored",
        a1 and a1.point)
end
CHECK(root.__w == (CommanderProductionDB.BarWidth or 110) + 20, "BARS_DOWN: root width restored",
    tostring(root.__w))

-- ===========================================================================
-- Alert matrix
-- ===========================================================================

local function CountPrints(pattern)
    local n = 0
    for _, line in ipairs(printLog) do
        if line:find(pattern, 1, true) then n = n + 1 end
    end
    return n
end

local banner = _G.CommanderProductionBanner
CHECK(banner ~= nil and banner.__shown == false, "banner exists and starts hidden")

-- Spell 1 finishes under RTL: default CHAT + CLICK
CommanderProductionDB.Layout = "ICONS_RTL"
now = now + 31
cooldowns[1] = nil
Redraw()
CHECK(CountPrints("Commander Production: Lay on Hands ready") == 1, "chat callout fired once")
CHECK(playedSounds[#playedSounds] == SOUNDKIT.IG_CHARACTER_INFO_TAB, "CLICK sound played",
    tostring(playedSounds[#playedSounds]))
CHECK(banner.__shown == false, "banner stays hidden on CHAT callout")

-- Spell 2 finishes: BOTH callout + QUEST sound
CommanderProductionDB.ReadyCallout = "BOTH"
CommanderProductionDB.ReadySound = "QUEST"
now = now + 30
cooldowns[2] = nil
Redraw()
CHECK(CountPrints("Commander Production: Divine Shield ready") == 1, "chat half of BOTH fired")
CHECK(banner.__shown == true, "banner half of BOTH shown")
local bannerFS = banner.__fontStrings and banner.__fontStrings[1]
CHECK(bannerFS and bannerFS.__text == "Divine Shield ready", "banner text set",
    bannerFS and tostring(bannerFS.__text))

-- Banner hold + fade: run the hold timer, then tick the fade to zero
now = now + 3.1
RunDueTimers()
RunTickers(20)
CHECK(banner.__shown == false, "banner faded out and hid")
CHECK((banner.__alpha or 1) == 1, "banner alpha reset for next showing", tostring(banner.__alpha))
CHECK(playedSounds[#playedSounds] == SOUNDKIT.IG_QUEST_LIST_COMPLETE, "QUEST sound played",
    tostring(playedSounds[#playedSounds]))

-- Silent config: sound NONE + callout NONE -> nothing at all
CommanderProductionDB.ReadySound = "NONE"
CommanderProductionDB.ReadyCallout = "NONE"
local soundsBefore, printsBefore = #playedSounds, #printLog
cooldowns[1] = { start = now, duration = 10 }
Redraw()
now = now + 11
cooldowns[1] = nil
Redraw()
CHECK(#playedSounds == soundsBefore, "NONE sound stays silent", #playedSounds - soundsBefore)
CHECK(#printLog == printsBefore, "NONE callout prints nothing", #printLog - printsBefore)
CHECK(banner.__shown == false, "NONE callout leaves banner hidden")

-- Master switch off: BANNER + WARNING configured but ReadyAlert false
CommanderProductionDB.ReadyAlert = false
CommanderProductionDB.ReadySound = "WARNING"
CommanderProductionDB.ReadyCallout = "BANNER"
soundsBefore = #playedSounds
cooldowns[2] = { start = now, duration = 10 }
Redraw()
now = now + 11
cooldowns[2] = nil
Redraw()
CHECK(#playedSounds == soundsBefore and banner.__shown == false, "master off silences everything")
CommanderProductionDB.ReadyAlert = true

-- ===========================================================================
-- Settings panel: the new dropdowns write the DB and preview on select
-- ===========================================================================

-- Panel dropdown order: 1 Layout, 2 Overlay, 3 Ready Sound, 4 Ready Callout,
-- 5 Frame Style
local layoutDropdown = _G.CommanderUIDropDown1
CHECK(layoutDropdown ~= nil, "layout dropdown built")
if layoutDropdown then
    ToggleDropDownMenu(1, nil, layoutDropdown)
    CHECK(#menuCaptured == 4, "layout menu lists four options", #menuCaptured)
    local rtl
    for _, info in ipairs(menuCaptured) do
        if info.value == "ICONS_RTL" then rtl = info end
    end
    CHECK(rtl ~= nil, "ICONS_RTL entry present")
end

local soundDropdown = _G.CommanderUIDropDown3
CHECK(soundDropdown ~= nil, "ready sound dropdown built")
if soundDropdown then
    ToggleDropDownMenu(1, nil, soundDropdown)
    CHECK(#menuCaptured == 5, "sound menu lists five options", #menuCaptured)
    local picked
    for _, info in ipairs(menuCaptured) do
        if info.value == "READY_CHECK" then picked = info end
    end
    CHECK(picked ~= nil, "READY_CHECK entry present")
    if picked then
        soundsBefore = #playedSounds
        picked.func(picked)
        CHECK(CommanderProductionDB.ReadySound == "READY_CHECK", "sound dropdown writes the DB")
        CHECK(playedSounds[#playedSounds] == SOUNDKIT.READY_CHECK, "picking a sound previews it",
            tostring(playedSounds[#playedSounds]))
    end
end

local calloutDropdown = _G.CommanderUIDropDown4
CHECK(calloutDropdown ~= nil, "ready callout dropdown built")
if calloutDropdown then
    ToggleDropDownMenu(1, nil, calloutDropdown)
    local picked
    for _, info in ipairs(menuCaptured) do
        if info.value == "BANNER" then picked = info end
    end
    CHECK(picked ~= nil, "BANNER entry present")
    if picked then
        picked.func(picked)
        CHECK(CommanderProductionDB.ReadyCallout == "BANNER", "callout dropdown writes the DB")
        CHECK(banner.__shown == true, "picking banner previews the banner")
        CHECK(bannerFS and bannerFS.__text == "Production ready", "preview banner text",
            bannerFS and tostring(bannerFS.__text))
    end
end

CHECK(#harnessFailedErrors == 0, "no errors across the run", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
