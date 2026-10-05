-- Commander Production smoke (luajit) — Icon Strip direction (ICONS /
-- ICONS_RTL), the Ready Sound / Ready Callout alert options, and the 2.4.0
-- compact metrics: Icon Size, Icons per Row wrapping, Row Height, Spacing,
-- and the name/countdown split in the Bars layouts; then the 2.6.0 Radial
-- Discs: the disc's geometry, its ring, spark, wipe, countdown, glow and
-- flash, and that its art is Commander Plates' byte for byte. Mock modeled
-- on Commander_Meters/Harness.
--
--   luajit Harness/production_smoke.lua                the checks
--   luajit Harness/production_smoke.lua board.json     ...and dump the radial
--       board's resolved widgets for Harness/render_discs.py to draw

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
local noMasks = false

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
    if key == "SetAllPoints" then
        local fn = function(s, rel) s.__points = { { all = true, rel = rel } } end
        rawset(self, key, fn); return fn
    end
    if key == "SetTexture" then
        local fn = function(s, tex) s.__tex = tex end
        rawset(self, key, fn); return fn
    end
    if key == "SetVertexColor" or key == "SetSwipeColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a == nil and 1 or a } end
        rawset(self, key, fn); return fn
    end
    if key == "SetSwipeTexture" then
        local fn = function(s, tex) s.__swipe = tex end
        rawset(self, key, fn); return fn
    end
    if key == "SetCooldown" then
        local fn = function(s, start, duration) s.__cd = { start, duration } end
        rawset(self, key, fn); return fn
    end
    if key == "SetRotation" then
        local fn = function(s, radians) s.__rot = radians end
        rawset(self, key, fn); return fn
    end
    if key == "SetBlendMode" then
        local fn = function(s, mode) s.__blend = mode end
        rawset(self, key, fn); return fn
    end
    if key == "SetFont" then
        local fn = function(s, path, size, flags) s.__font = { path, size, flags } end
        rawset(self, key, fn); return fn
    end
    if key == "SetFrameLevel" then
        local fn = function(s, level) s.__level = level end
        rawset(self, key, fn); return fn
    end
    if key == "GetFrameLevel" then
        local fn = function(s) return s.__level or 2 end
        rawset(self, key, fn); return fn
    end
    -- Masks exist on this client; `noMasks` plays one where they do not
    if key == "CreateMaskTexture" then
        if noMasks then return nil end
        local fn = function(s) local t = NewWidget("MaskTexture"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "AddMaskTexture" then
        local fn = function(s, mask) s.__masks = s.__masks or {}; s.__masks[#s.__masks + 1] = mask end
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
        local fn = function(s, _, layer, _, sub)
            local t = NewWidget("Texture")
            t.__parent, t.__layer, t.__sub = s, layer or "ARTWORK", sub or 0
            s.__regions = s.__regions or {}
            s.__regions[#s.__regions + 1] = t
            return t
        end
        rawset(self, key, fn); return fn
    end
    if key == "CreateFontString" then
        local fn = function(s)
            local t = NewWidget("FontString")
            t.__parent = s
            s.__regions = s.__regions or {}
            s.__regions[#s.__regions + 1] = t
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

-- Combat log: only the interrupt stamp is read out of it
function UnitGUID(unit) return unit == "player" and "Player-1" or nil end
local cleuArgs = {}
function CombatLogGetCurrentEventInfo() return unpack(cleuArgs, 1, 18) end

-- Spellbook: two spells, cooldown state the harness controls
local cooldowns = {}  -- slot -> { start, duration }
local SPELLBOOK = {
    [1] = { name = "Lay on Hands", texture = "Interface\\Icons\\LoH", id = 633 },
    [2] = { name = "Divine Shield", texture = "Interface\\Icons\\DS", id = 642 },
}
function GetNumSpellTabs() return 1 end
function GetSpellTabInfo() return "General", "tex", 0, #SPELLBOOK end
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
CHECK(CommanderProductionDB.LingerTime == 10, "C: linger time defaults to 10s",
    tostring(CommanderProductionDB.LingerTime))

-- Only the LAST DB watcher may run PLAYER_LOGIN (earlier scenario frames
-- would build duplicate panels against their stale DB upvalues)
local loginList = eventRegistry["PLAYER_LOGIN"]
eventRegistry["PLAYER_LOGIN"] = { loginList[#loginList] }

Load(ADDONS .. "/Commander_Production/CommanderProductionRadial.lua")
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
-- Compact metrics: Icon Size, Icons per Row, Row Height, Spacing
-- ===========================================================================

-- One icon per line: the strip wraps into a column instead of a banner
CommanderProductionDB.Layout = "ICONS"
CommanderProductionDB.IconSize = 18
CommanderProductionDB.Spacing = 2
CommanderProductionDB.PerRow = 1
Redraw()
local STRIP_ROW = 18 + 4 + 2   -- icon + slim bar + its 2px offset
rows = ShownRows()
CHECK(#rows == 2, "wrap: two rows shown", #rows)
if #rows == 2 then
    local a1, a2 = rows[1].__points[1], rows[2].__points[1]
    CHECK(a1 and a1.x == 0 and a1.y == 0, "wrap: first icon sits on the anchor",
        a1 and (tostring(a1.x) .. "," .. tostring(a1.y)))
    CHECK(a2 and a2.x == 0 and a2.y == -(STRIP_ROW + 2),
        "wrap: second icon drops to line two", a2 and (tostring(a2.x) .. "," .. tostring(a2.y)))
    CHECK(rows[1].__w == 18 and rows[1].__h == STRIP_ROW, "wrap: icon size honoured",
        tostring(rows[1].__w) .. "x" .. tostring(rows[1].__h))
end
CHECK(root.__w == 18 and root.__h == 2 * (STRIP_ROW + 2) - 2,
    "wrap: root is one column, two lines",
    tostring(root.__w) .. "x" .. tostring(root.__h))

-- With the slim bar off, the strip row stops reserving its height
CommanderProductionDB.CooldownOverlay = "SWEEP"
Redraw()
rows = ShownRows()
CHECK(rows[1] and rows[1].__h == 18, "wrap: sweep-only rows are the icon alone",
    rows[1] and tostring(rows[1].__h))
CHECK(root.__h == 2 * (18 + 2) - 2, "wrap: no slim bar, no reserved height",
    tostring(root.__h))
CommanderProductionDB.CooldownOverlay = "BAR"

-- RTL wraps the same way, marching left from the right edge
CommanderProductionDB.Layout = "ICONS_RTL"
CommanderProductionDB.PerRow = 2
Redraw()
rows = ShownRows()
if #rows == 2 then
    local a2 = rows[2].__points[1]
    CHECK(a2 and a2.point == "TOPRIGHT" and a2.x == -20 and a2.y == 0,
        "wrap: RTL keeps a two-wide line on one row",
        a2 and (a2.point .. "@" .. tostring(a2.x) .. "," .. tostring(a2.y)))
end
CHECK(root.__w == 2 * 20 - 2 and root.__h == STRIP_ROW,
    "wrap: RTL root is two columns, one line",
    tostring(root.__w) .. "x" .. tostring(root.__h))

-- Bars: Row Height drives the row, its icon, and the frame
CommanderProductionDB.Layout = "BARS_DOWN"
CommanderProductionDB.RowHeight = 10
CommanderProductionDB.Spacing = 1
CommanderProductionDB.BarWidth = 80
Redraw()
rows = ShownRows()
CHECK(#rows == 2, "compact bars: two rows shown", #rows)
if #rows == 2 then
    CHECK(rows[1].__w == 80 + 10 + 4 + 4 and rows[1].__h == 10,
        "compact bars: row sized from width + row height",
        tostring(rows[1].__w) .. "x" .. tostring(rows[1].__h))
    local a2 = rows[2].__points[1]
    CHECK(a2 and a2.y == -11, "compact bars: rows stack at height + spacing",
        a2 and tostring(a2.y))
    -- Name left, countdown its own right-aligned string
    local label = rows[1].__fontStrings and rows[1].__fontStrings[1]
    local timeFS = rows[1].__fontStrings and rows[1].__fontStrings[2]
    CHECK(label and label.__text == "Lay on Hands", "compact bars: label is the name alone",
        label and tostring(label.__text))
    CHECK(timeFS and timeFS.__text and timeFS.__text:match("^%d+s$"),
        "compact bars: countdown is its own string", timeFS and tostring(timeFS.__text))
end
CHECK(root.__w == 98 and root.__h == 2 * 11, "compact bars: root fits the compact rows",
    tostring(root.__w) .. "x" .. tostring(root.__h))

-- Back to the defaults the rest of the run assumes
CommanderProductionDB.IconSize = 26
CommanderProductionDB.Spacing = 4
CommanderProductionDB.PerRow = 20
CommanderProductionDB.RowHeight = 12
CommanderProductionDB.BarWidth = 110
Redraw()
CHECK(root.__w == 130, "metrics: default bars geometry restored", tostring(root.__w))
CHECK(#harnessFailedErrors == 0, "metrics redraws clean", harnessFailedErrors[1])

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

-- Panel dropdown order: 1 Layout, 2 Overlay, 3 Ready Glow Style, 4 Glow
-- Motion, 5 Ready Sound, 6 Ready Callout, 7 Frame Style
local layoutDropdown = _G.CommanderUIDropDown1
CHECK(layoutDropdown ~= nil, "layout dropdown built")
if layoutDropdown then
    ToggleDropDownMenu(1, nil, layoutDropdown)
    CHECK(#menuCaptured == 6, "layout menu lists six options", #menuCaptured)
    local rtl
    for _, info in ipairs(menuCaptured) do
        if info.value == "ICONS_RTL" then rtl = info end
    end
    CHECK(rtl ~= nil, "ICONS_RTL entry present")
    local discs = 0
    for _, info in ipairs(menuCaptured) do
        if info.value == "RADIAL" or info.value == "RADIAL_RTL" then discs = discs + 1 end
    end
    CHECK(discs == 2, "both Radial Discs layouts offered", discs)
end

local soundDropdown = _G.CommanderUIDropDown5
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

local calloutDropdown = _G.CommanderUIDropDown6
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

-- ===========================================================================
-- Linger When Ready: the configured Linger Time drives hold, fade, and drop
-- ===========================================================================

CommanderProductionDB.Layout = "BARS_DOWN"
CommanderProductionDB.ReadyAlert = false
CommanderProductionDB.LingerReady = true
CommanderProductionDB.LingerTime = 10
cooldowns[1] = { start = now, duration = 30 }
Redraw()
now = now + 31
cooldowns[1] = nil
Redraw()
rows = ShownRows()
CHECK(#rows == 1, "linger: finished cooldown parks as a READY row", #rows)
if #rows == 1 then
    local label = rows[1].__fontStrings and rows[1].__fontStrings[1]
    local timeFS = rows[1].__fontStrings and rows[1].__fontStrings[2]
    CHECK(label and label.__text == "Lay on Hands" and timeFS and timeFS.__text == "READY",
        "linger: READY sits in the countdown slot, name untouched",
        (label and tostring(label.__text)) .. "/" .. (timeFS and tostring(timeFS.__text)))
end
CHECK(rows[1] and (rows[1].__alpha or 1) == 1, "linger: full opacity during the hold",
    rows[1] and tostring(rows[1].__alpha))

-- Still inside the 10s hold
now = now + 9
Redraw()
rows = ShownRows()
CHECK(#rows == 1 and (rows[1].__alpha or 1) == 1, "linger: holds the full 10 seconds",
    #rows .. "/" .. tostring(rows[1] and rows[1].__alpha))

-- 11.5s in: 1.5s into the 5s fade tail (half the linger time)
now = now + 2.5
Redraw()
rows = ShownRows()
local lingerAlpha = rows[1] and (rows[1].__alpha or 1)
CHECK(#rows == 1 and lingerAlpha and math.abs(lingerAlpha - 0.7) < 0.01,
    "linger: fades across the tail", tostring(lingerAlpha))

-- Past hold + fade: gone
now = now + 4
Redraw()
CHECK(#ShownRows() == 0, "linger: dropped after hold plus fade", #ShownRows())

-- A shorter Linger Time expires sooner: 4s hold + 2s fade
CommanderProductionDB.LingerTime = 4
cooldowns[1] = { start = now, duration = 30 }
Redraw()
now = now + 31
cooldowns[1] = nil
Redraw()
CHECK(#ShownRows() == 1, "linger: short setting still parks the row", #ShownRows())
now = now + 5
Redraw()
rows = ShownRows()
lingerAlpha = rows[1] and (rows[1].__alpha or 1)
CHECK(#rows == 1 and lingerAlpha and math.abs(lingerAlpha - 0.5) < 0.01,
    "linger: 4s setting is half faded at 5s", tostring(lingerAlpha))
now = now + 2
Redraw()
CHECK(#ShownRows() == 0, "linger: 4s setting is gone by 7s", #ShownRows())
CommanderProductionDB.LingerReady = false

local function FireInterruptOnPlayer(destGUID)
    cleuArgs = { now, "SPELL_INTERRUPT", false, "Player-2", "Levira", 0, 0,
        destGUID or "Player-1", "Me", 0, 0, 2139, "Counterspell", 0, 116, "Frostbolt", 0x10, nil }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- ===========================================================================
-- Interrupt lockouts: shown while the school is down, gone the moment it
-- lifts — a lock is not a cooldown, so it must not linger or alert
-- ===========================================================================

CommanderProductionDB.Layout = "BARS_DOWN"
CommanderProductionDB.LingerReady = true
CommanderProductionDB.LingerTime = 10
CommanderProductionDB.ReadyAlert = true
CommanderProductionDB.ReadyCallout = "CHAT"
cooldowns[1], cooldowns[2] = nil, nil
Redraw()

-- Kicked: the school reports a 10s "cooldown" on both spells
now = now + 1
FireInterruptOnPlayer()
cooldowns[1] = { start = now, duration = 10 }
cooldowns[2] = { start = now, duration = 10 }
Redraw()
CHECK(#ShownRows() == 2, "lockout: locked spells still show while the school is down",
    #ShownRows())

-- Lock lifts: gone at once, no READY hold and no alert
local printsBefore = #printLog
now = now + 11
cooldowns[1], cooldowns[2] = nil, nil
Redraw()
CHECK(#ShownRows() == 0, "lockout: no linger once the school is back", #ShownRows())
CHECK(#printLog == printsBefore, "lockout: no ready alert for a lock lifting",
    printLog[#printLog])

-- A real cooldown cast during the same lockout window still behaves
now = now + 1
FireInterruptOnPlayer()
cooldowns[1] = { start = now, duration = 10 }    -- the lock
cooldowns[2] = { start = now, duration = 30 }    -- a real 30s cooldown
Redraw()
CHECK(#ShownRows() == 2, "lockout: a real cooldown alongside it still queues", #ShownRows())
now = now + 11
cooldowns[1] = nil
Redraw()
CHECK(#ShownRows() == 1, "lockout: only the locked spell drops out", #ShownRows())
now = now + 20
cooldowns[2] = nil
Redraw()
rows = ShownRows()
CHECK(#rows == 1, "lockout: the real cooldown still parks as a READY row", #rows)
now = now + 16
Redraw()

-- An interrupt on someone else is not my lockout
now = now + 5
FireInterruptOnPlayer("Player-9")
cooldowns[1] = { start = now, duration = 10 }
Redraw()
now = now + 11
cooldowns[1] = nil
Redraw()
CHECK(#ShownRows() == 1, "lockout: a kick on someone else leaves cooldowns alone",
    #ShownRows())
now = now + 16
Redraw()
CommanderProductionDB.LingerReady = false
CommanderProductionDB.ReadyAlert = false

-- ===========================================================================
-- The embed accessor (2.5.0): what Commander_PartyFrames reads to carry this
-- queue on its banner — the same sorted list the frame draws, capped at
-- Queue Length, and nothing at all while the module is off
-- ===========================================================================

now = now + 1
cooldowns[1] = { start = now, duration = 60 }
cooldowns[2] = { start = now, duration = 20 }
CommanderProductionDB.MaxBars = 5
Redraw()
local q, n = CommanderProduction_Queue()
CHECK(q ~= nil and n == 2, "embed: the accessor hands over the queue with its count", tostring(n))
CHECK(q and q[1] and q[1].entry and q[1].entry.duration == 20,
    "embed: ...sorted soonest-ready first, exactly as the frame draws it",
    q and q[1] and q[1].entry and tostring(q[1].entry.duration))
CHECK(q and q[1].entry.texture ~= nil and q[1].entry.start == now,
    "embed: an entry carries the texture and clock the banner needs")
CommanderProductionDB.MaxBars = 1
Redraw()
q, n = CommanderProduction_Queue()
CHECK(n == 1 and #q == 2, "embed: the count is capped at Queue Length, the list is not",
    string.format("%s/%s", tostring(n), tostring(q and #q)))
CommanderProductionDB.MaxBars = 5
CommanderProductionDB.EnableProduction = false
Redraw()
CHECK(CommanderProduction_Queue() == nil, "embed: nothing while the module is off")
CommanderProductionDB.EnableProduction = true
cooldowns[1], cooldowns[2] = nil, nil
Redraw()

-- ===========================================================================
-- Radial Discs (2.6.0): the queue as discs -- the spell's icon cut round, its
-- cooldown a ring around it
-- ===========================================================================

local R = CommanderProduction_Radial
local function Near(a, b, eps) return a and b and math.abs(a - b) < (eps or 0.001) end

-- Geometry, no widgets involved. Angles run clockwise from twelve.
do
    local x, y, theta = R.ArcPoint(10, 0)
    CHECK(Near(x, 0) and Near(y, 10) and Near(theta, 0), "arc: fraction 0 is twelve o'clock")
    x, y = R.ArcPoint(10, 0.25)
    CHECK(Near(x, 10) and Near(y, 0), "arc: a quarter round is three o'clock", x .. "," .. y)
    x, y = R.ArcPoint(10, 0.5)
    CHECK(Near(x, 0) and Near(y, -10), "arc: half way round is six", x .. "," .. y)
    CHECK(R.RingWeight(20, 4) == 3 and R.RingWeight(20, 2) == 2 and R.RingWeight(20, 10) == 6,
        "ring: the nearest of the six weights")
    CHECK(#R.RING_FILES == #R.RING_RATIOS, "ring: a ratio for every weight")

    -- The wipe darkens what REMAINS: each left-half disc is turned
    -- counterclockwise into (or out of) its clip
    local a1, a2 = R.WipeAngles(0)
    CHECK(a1 == -180 and a2 == 0, "wipe: nothing left, both halves turned out of their clips")
    a1, a2 = R.WipeAngles(0.25)
    CHECK(a1 == -90 and a2 == 0, "wipe: a quarter left is the top-left quadrant")
    a1, a2 = R.WipeAngles(0.5)
    CHECK(a1 == 0 and a2 == 0, "wipe: half left fills the left half")
    a1, a2 = R.WipeAngles(0.75)
    CHECK(a1 == 0 and a2 == 90, "wipe: three quarters left reaches round to three o'clock")
    a1, a2 = R.WipeAngles(1)
    CHECK(a1 == 0 and a2 == 180, "wipe: a fresh cooldown darkens the whole face")
    a1, a2 = R.WipeAngles(7)
    CHECK(a1 == 0 and a2 == 180, "wipe: clamped")

    local cfg = R.Config({})
    CHECK(cfg.outer == 20 and cfg.core == 15 and cfg.backdropRadius == 22 and cfg.cell == 44,
        "config: defaults give a 40px ring on a 44px backdrop",
        string.format("%s/%s/%s/%s", cfg.outer, cfg.core, tostring(cfg.backdropRadius), cfg.cell))
    local sig = cfg.signature
    cfg = R.Config({ RadialBackdropSize = -30 })
    CHECK(cfg.backdropRadius == 16 and cfg.cell == 40,
        "config: a pulled-in backdrop stops at the face and the cell is the ring's",
        tostring(cfg.backdropRadius) .. "/" .. cfg.cell)
    cfg = R.Config({ RadialBackdropAlpha = 0 })
    CHECK(cfg.backdropRadius == nil and cfg.cell == 40, "config: no backdrop, no room kept for one")
    cfg = R.Config({ RadialSize = 24, RadialThickness = 10 })
    CHECK(cfg.core == 4, "config: the face never shrinks to nothing", cfg.core)
    CHECK(R.Config({ RadialSpark = false, RadialGlowMotion = "SPIN", RadialWipe = true }).signature == sig,
        "config: what is painted per draw is not geometry")
    CHECK(R.Config({ RadialSize = 42 }).signature ~= sig and R.Config({ RadialGlowStyle = "RUNIC" }).signature ~= sig,
        "config: what Layout applies is")
end

-- The art is Commander Plates', byte for byte (Harness/copy_radial_art.py)
do
    local function Bytes(path)
        local fh = io.open(path, "rb")
        if not fh then return nil end
        local data = fh:read("*a")
        fh:close()
        return data
    end
    local files = { R.EDGE_FILE, R.MASK_FILE, R.HALF_LEFT, R.HALF_RIGHT }
    for _, f in ipairs(R.RING_FILES) do files[#files + 1] = f end
    for _, key in ipairs(R.GLOW_ORDER) do
        CHECK(R.GLOW_STYLES[key] ~= nil and R.GLOW_LABEL[key] ~= nil, "art: glow " .. key .. " has a file and a label")
        files[#files + 1] = R.GLOW_STYLES[key]
    end
    local missing, differ = {}, {}
    for _, f in ipairs(files) do
        local name = f:match("([^\\]+)$")
        local mine = Bytes(ADDONS .. "/Commander_Production/Textures/" .. name)
        local theirs = Bytes(ADDONS .. "/Commander_Plates/Textures/" .. name)
        if not mine then missing[#missing + 1] = name
        elseif theirs and mine ~= theirs then differ[#differ + 1] = name end
    end
    CHECK(#files == 20 and #missing == 0, "art: every texture the brushes name is shipped", table.concat(missing, " "))
    CHECK(#differ == 0, "art: every copy matches Commander Plates'", table.concat(differ, " "))
end

-- Two cooldowns as discs
CommanderProductionDB.Layout = "RADIAL"
CommanderProductionDB.LingerReady = false
CommanderProductionDB.ReadyAlert = false
now = now + 1
cooldowns[1] = { start = now, duration = 30 }
cooldowns[2] = { start = now, duration = 60 }
Redraw()
rows = ShownRows()
CHECK(#rows == 2, "radial: two discs shown", #rows)
local CELL, STEP = 44, 48
local row1, row2 = rows[1], rows[2]
local disc = row1 and row1.disc
CHECK(disc ~= nil and row2 and row2.disc ~= nil, "radial: each row carries a disc")
if disc then
    local a1, a2 = row1.__points[1], row2.__points[1]
    CHECK(a1.point == "TOPLEFT" and a1.x == 0 and a2.point == "TOPLEFT" and a2.x == STEP and a2.y == 0,
        "radial: discs march right from the anchor", tostring(a2.point) .. "@" .. tostring(a2.x))
    CHECK(row1.__w == CELL and row1.__h == CELL, "radial: a cell is the backdrop's diameter",
        tostring(row1.__w) .. "x" .. tostring(row1.__h))
    CHECK(root.__w == 2 * STEP - 4 and root.__h == CELL, "radial: root fits two discs",
        tostring(root.__w) .. "x" .. tostring(root.__h))
    CHECK(row1.icon.__shown == false and row1.bar.__shown == false and row1.barBG.__shown == false
        and row1.label.__shown == false and row1.time.__shown == false and row1.sweep.__shown == false,
        "radial: the disc stands in for the row's icon, bar and text")
    CHECK(disc.__shown == true and disc.__w == CELL, "radial: the disc is up and fills its cell", tostring(disc.__w))

    -- The face
    CHECK(disc.core.__tex == "Interface\\Icons\\LoH", "radial: the face is the spell's icon", tostring(disc.core.__tex))
    CHECK(disc.coreMasked == true and disc.core.__masks and disc.core.__masks[1].__tex == R.MASK_FILE,
        "radial: the face is cut round")
    CHECK(disc.core.__w == 30, "radial: the face fills the ring's inside, less a pixel of air", tostring(disc.core.__w))

    -- The ring: a real cooldown the client animates
    local cd = disc.arc.cd
    CHECK(cd.__cd and cd.__cd[1] == now and cd.__cd[2] == 30, "radial: the ring is the spell's own cooldown",
        cd.__cd and (tostring(cd.__cd[1]) .. "/" .. tostring(cd.__cd[2])))
    CHECK(cd.__shown == true and disc.arc.full.__shown == false, "radial: a pending ring is the sweep, not the full circle")
    CHECK(cd.__swipe == R.RING_FILES[3] and Near(cd.__w, 20 / R.RING_OUTER),
        "radial: the sweep is the donut of the nearest weight, sized to the ring",
        tostring(cd.__swipe) .. " " .. tostring(cd.__w))
    CHECK(cd.__color and cd.__color[1] == 0.35 and cd.__color[3] == 1, "radial: pending is the queue's blue")
    CHECK(cd.noCooldownCount == true and cd.noOCC == true, "radial: countdown addons are kept off the ring")
    CHECK(disc.arc.track.__shown == true and Near(disc.arc.track.__color[4], 0.35), "radial: the empty ring is drawn dim")

    -- The countdown across the face, and the shade under it
    CHECK(disc.text.__shown == true and disc.text.__text == "30s", "radial: the countdown is written on the face",
        tostring(disc.text.__text))
    CHECK(disc.shade.__shown == true and Near(disc.shade.__color[4], 0.45), "radial: the face darkens under the number")
    CHECK(disc.text.__font and disc.text.__font[2] == 12, "radial: the number is sized off the face",
        disc.text.__font and tostring(disc.text.__font[2]))

    -- The spark rides the ring's head, on the widget's own clock
    local sp = disc.spark.__points and disc.spark.__points[1]
    CHECK(disc.spark.__shown == true and sp and Near(sp.x, 0) and Near(sp.y, 18),
        "radial: the spark starts at twelve, mid-band", sp and (tostring(sp.x) .. "," .. tostring(sp.y)))
    local tick = disc.__scripts.OnUpdate
    CHECK(type(tick) == "function", "radial: the animation clock runs while a spark is live")
    now = now + 7.5
    if tick then tick(disc, 0.016) end
    sp = disc.spark.__points and disc.spark.__points[1]
    CHECK(sp and Near(sp.x, 18) and Near(sp.y, 0) and Near(disc.spark.__rot, -math.pi / 2),
        "radial: a quarter in, the spark is at three and turned with the ring",
        sp and (tostring(sp.x) .. "," .. tostring(sp.y)))
    CHECK(disc.glow.__shown == false and disc.flash.__shown == false, "radial: nothing glows on a pending disc")
    CHECK(disc.glow.__parent == row1, "radial: the glow is drawn on the row, beneath every disc")
    CHECK(row1.tipText == "Lay on Hands — 30s" and row1.spellID == 633, "radial: the hover tooltip still has its spell",
        tostring(row1.tipText))

    -- Steady state: a redraw with nothing moved writes nothing to the ring
    cd.__cd = nil
    Redraw()
    CHECK(cd.__cd == nil, "radial: an unchanged cooldown is not re-set every draw")
    Redraw()
    CHECK(disc.text.__text == "23s", "radial: the countdown follows the clock", tostring(disc.text.__text))
end

-- Right to left, and wrapping
CommanderProductionDB.Layout = "RADIAL_RTL"
Redraw()
rows = ShownRows()
if #rows == 2 then
    local a1, a2 = rows[1].__points[1], rows[2].__points[1]
    CHECK(a1.point == "TOPRIGHT" and a1.x == 0 and a2.point == "TOPRIGHT" and a2.x == -STEP,
        "radial RTL: discs march left from the right edge", a2.point .. "@" .. tostring(a2.x))
end
CommanderProductionDB.Layout = "RADIAL"
CommanderProductionDB.PerRow = 1
Redraw()
rows = ShownRows()
if #rows == 2 then
    local a2 = rows[2].__points[1]
    CHECK(a2.x == 0 and a2.y == -STEP, "radial: Icons per Row wraps discs onto a second line",
        tostring(a2.x) .. "," .. tostring(a2.y))
end
CHECK(root.__w == CELL and root.__h == 2 * STEP - 4, "radial: root is one column, two lines",
    tostring(root.__w) .. "x" .. tostring(root.__h))
CommanderProductionDB.PerRow = 20

-- The disc's own metrics re-lay it
if disc then
    CommanderProductionDB.RadialSize = 60
    CommanderProductionDB.RadialThickness = 6
    CommanderProductionDB.RadialBackdropSize = 5
    Redraw()
    CHECK(row1.__w == 70 and disc.__w == 70, "radial: Disc Size and Backdrop Size resize the cell", tostring(row1.__w))
    CHECK(disc.core.__w == 46 and Near(disc.arc.cd.__w, 30 / R.RING_OUTER) and disc.backdrop.__w == 70,
        "radial: ...and the face, ring and backdrop inside it",
        tostring(disc.core.__w) .. "/" .. tostring(disc.backdrop.__w))
    CHECK(disc.backdrop.__shown == true and disc.backdropRim.__shown == true, "radial: backdrop and border drawn")
    CommanderProductionDB.RadialBackdropBorder = false
    Redraw()
    CHECK(disc.backdropRim.__shown == false, "radial: Backdrop Border off takes the rim away")
    CommanderProductionDB.RadialBackdropAlpha = 0
    Redraw()
    CHECK(disc.backdrop.__shown == false and row1.__w == 60, "radial: no backdrop, and the cell is the ring's",
        tostring(row1.__w))
    CommanderProductionDB.RadialTrackAlpha = 0
    Redraw()
    CHECK(disc.arc.track.__shown == false, "radial: Empty Ring Opacity off draws only what is left")
    CommanderProductionDB.RadialSize, CommanderProductionDB.RadialThickness = 40, 4
    CommanderProductionDB.RadialBackdropSize, CommanderProductionDB.RadialBackdropAlpha = 2, 0.6
    CommanderProductionDB.RadialBackdropBorder, CommanderProductionDB.RadialTrackAlpha = true, 0.35

    -- Countdown and its shade
    CommanderProductionDB.RadialTextShade = 0
    Redraw()
    CHECK(disc.text.__shown == true and disc.shade.__shown == false, "radial: shade off leaves the face untouched")
    CommanderProductionDB.RadialTextShade = 0.45
    CommanderProductionDB.RadialCountdown = false
    Redraw()
    CHECK(disc.text.__shown == false and disc.shade.__shown == false, "radial: Countdown off clears the face")
    CommanderProductionDB.RadialCountdown = true
    CommanderProductionDB.RadialSpark = false
    Redraw()
    CHECK(disc.spark.__shown == false and disc.__scripts.OnUpdate ~= nil,
        "radial: Ring Spark off hides it (the clock notices on its next tick)")
    disc.__scripts.OnUpdate(disc, 0.016)
    CHECK(disc.__scripts.OnUpdate == nil, "radial: with nothing live the animation clock stops")
    CommanderProductionDB.RadialSpark = true

    -- The face wipe: masked halves turned to what remains (22.5s of 30)
    CommanderProductionDB.RadialWipe = true
    Redraw()
    local a1, a2 = R.WipeAngles(22.5 / 30)
    CHECK(disc.wipeMasked == true and disc.wipe[1].__shown and disc.wipe[2].__shown,
        "radial: Face Wipe raises both masked halves while more than half is left")
    CHECK(disc.wipe[1].__tex == R.HALF_LEFT and disc.wipe[1].clip.__tex == R.HALF_LEFT
        and disc.wipe[2].clip.__tex == R.HALF_RIGHT, "radial: each half is clipped to its own side of the face")
    CHECK(Near(disc.wipe[1].__rot, math.rad(a1)) and Near(disc.wipe[2].__rot, math.rad(a2)),
        "radial: the wipe is turned to the cooldown left", tostring(disc.wipe[2].__rot))
    CHECK(disc.coreCd.__shown == false, "radial: the unmasked fallback stays down where masks work")
    now = now + 7.5
    disc.__scripts.OnUpdate(disc, 0.016)
    CHECK(Near(disc.wipe[1].__rot, 0) and Near(disc.wipe[2].__rot, 0), "radial: at half the wipe is exactly the left half",
        tostring(disc.wipe[1].__rot) .. "/" .. tostring(disc.wipe[2].__rot))
    CHECK(disc.wipe[1].__shown == true and disc.wipe[2].__shown == false,
        "radial: ...and the second half, wholly out of its clip, is hidden rather than left as a hairline")

    -- A client with no masks: the next disc built keeps a square face and
    -- wipes with a Cooldown held under the ring
    noMasks = true
    CommanderProduction_Test()
    noMasks = false
    rows = ShownRows()
    local plain = rows[3] and rows[3].disc
    CHECK(plain ~= nil and plain.coreMasked == false and plain.wipeMasked == false, "no masks: the disc still builds")
    if plain then
        CHECK(Near(plain.core.__w, 30 * 0.7071), "no masks: the icon stays the largest square the face holds",
            tostring(plain.core.__w))
        CHECK(plain.coreCd.__shown == true and plain.coreCd.__cd
            and plain.coreCd.__cd[1] == plain.arc.cd.__cd[1] and plain.coreCd.__cd[2] == plain.arc.cd.__cd[2]
            and plain.wipe[1].__shown == false, "no masks: the wipe falls back to a Cooldown on the ring's clock")
        CHECK((plain.coreCd.__level or 0) < (plain.arc.cd.__level or 0), "no masks: ...held below the ring")
    end
    CommanderProductionDB.RadialWipe = false
    Redraw()
    CHECK(disc.wipe[1].__shown == false and (not plain or plain.coreCd.__shown == false), "radial: Face Wipe off clears both kinds")
end

-- READY: the lingering entry closes its ring in green, glows and flashes
CommanderProductionDB.LingerReady = true
CommanderProductionDB.LingerTime = 10
now = now + 15.5                      -- Lay on Hands (30s) is back
cooldowns[1] = nil
Redraw()
local function DiscShowing(texture)
    for _, r in ipairs(ShownRows()) do
        if r.disc and r.disc.core.__tex == texture then return r.disc, r end
    end
end
local ready, readyRow = DiscShowing("Interface\\Icons\\LoH")
local pending = DiscShowing("Interface\\Icons\\DS")
CHECK(ready ~= nil and pending ~= nil and ready ~= disc, "ready: the queue re-sorted, READY after pending")
if ready and pending then
    CHECK(pending.arc.cd.__shown == true and pending.arc.cd.__cd[2] == 60 and pending.arc.full.__shown == false
        and pending.glow.__shown == false, "ready: the row that took over the pending entry is repainted as it")
    CHECK(ready.arc.full.__shown == true and ready.arc.cd.__shown == false, "ready: the ring is closed")
    CHECK(ready.arc.full.__color[1] == 0.3 and ready.arc.full.__color[2] == 1, "ready: ...in the queue's READY green")
    CHECK(ready.text.__shown == false and ready.shade.__shown == false and ready.spark.__shown == false,
        "ready: no countdown, shade or spark on a finished cooldown")
    CHECK(ready.glow.__shown == true and ready.glow.__tex == R.GLOW_STYLES.SOFT and ready.glow.__blend == "ADD",
        "ready: the glow is up, in the chosen style")
    local glowSize = (22 + 1) / 0.28
    CHECK(Near(ready.glow.__w, glowSize), "ready: the glow rises from the backdrop's edge", tostring(ready.glow.__w))
    CHECK(ready.flash.__shown == true and ready.flash.__alpha == 1, "ready: the flash bursts as it comes back")
    now = now + 0.3
    ready.__scripts.OnUpdate(ready, 0.016)
    CHECK(Near(ready.flash.__alpha, 0.5), "ready: the flash fades over its 0.6s", tostring(ready.flash.__alpha))
    now = now + 0.4
    ready.__scripts.OnUpdate(ready, 0.016)
    CHECK(ready.flash.__shown == false and ready.__scripts.OnUpdate == nil,
        "ready: the flash ends and a still glow needs no clock")
    Redraw()
    CHECK(ready.flash.__shown == false, "ready: a redraw does not flash an old READY again")

    -- Glow motion, size and style
    CommanderProductionDB.RadialGlowMotion = "BOTH"
    Redraw()
    CHECK(ready.__scripts.OnUpdate ~= nil, "glow: motion starts the clock")
    ready.__scripts.OnUpdate(ready, 0.016)
    CHECK(ready.glow.__rot ~= nil and ready.glow.__rot ~= 0 and ready.glow.__alpha >= 0.65 and ready.glow.__alpha <= 1,
        "glow: it turns and breathes", tostring(ready.glow.__rot) .. "/" .. tostring(ready.glow.__alpha))
    CommanderProductionDB.RadialGlowMotion = "NONE"
    Redraw()
    CHECK(ready.glow.__rot == 0 and ready.glow.__alpha == 1, "glow: Still puts it back upright and full")
    CommanderProductionDB.RadialGlowStyle = "RUNIC"
    CommanderProductionDB.RadialGlowSize = 1.5
    Redraw()
    CHECK(ready.glow.__tex == R.GLOW_STYLES.RUNIC and Near(ready.glow.__w, glowSize * 1.5),
        "glow: style and size follow their settings", tostring(ready.glow.__tex))
    CommanderProductionDB.RadialGlowStyle = "OFF"
    Redraw()
    CHECK(ready.glow.__shown == false and ready.arc.full.__shown == true, "glow: Off leaves only the closed ring")
    CommanderProductionDB.RadialGlowStyle, CommanderProductionDB.RadialGlowSize = "SOFT", 1
    Redraw()
    CHECK(ready.glow.__shown == true, "glow: back on")

    -- The linger fade takes the whole disc with it
    now = now + 11.8                  -- 12.5s into a 10s hold + 5s fade
    Redraw()
    CHECK(Near(readyRow.__alpha, 0.5, 0.01), "ready: the disc fades on the linger clock", tostring(readyRow.__alpha))

    -- Recast while lingering: straight back to a pending ring
    cooldowns[1] = { start = now, duration = 30 }
    Redraw()
    local again, againRow = DiscShowing("Interface\\Icons\\LoH")
    CHECK(again and again.arc.cd.__shown == true and again.arc.cd.__cd[1] == now and again.arc.full.__shown == false
        and again.glow.__shown == false and again.text.__text == "30s" and againRow.__alpha == 1,
        "ready: a recast puts the disc straight back on the clock")
end

-- The flash belongs to the moment, not to the row. A new cooldown pushes the
-- READY stragglers down a row each, and the disc that takes one over must not
-- burst for a cooldown that came back seconds ago.
local function TickAll()
    for _, r in ipairs(ShownRows()) do
        local tick = r.disc and r.disc.__scripts.OnUpdate
        if tick then tick(r.disc, 0.016) end
    end
end
CommanderProductionDB.LingerTime = 60
now = now + 3                         -- the three come back one at a time,
Redraw()                              -- so each has its own moment: the test
now = now + 15                        -- cooldown, then Divine Shield, then
cooldowns[2] = nil                    -- Lay on Hands
Redraw()
now = now + 13
cooldowns[1] = nil
Redraw()
CHECK(#ShownRows() == 3, "ready: three stragglers linger", #ShownRows())
now = now + 2
TickAll()                             -- every flash has run its course
local oldReady, oldRow = DiscShowing("Interface\\Icons\\LoH")
CommanderProduction_Test()            -- the test cooldown again: pending, so first
local moved, movedRow = DiscShowing("Interface\\Icons\\LoH")
CHECK(moved ~= nil and movedRow ~= oldRow and moved.arc.full.__shown == true,
    "ready: a new cooldown pushes the stragglers down a row")
CHECK(moved and moved.flash.__shown == false and oldReady.flash.__shown == false,
    "ready: ...and the disc that takes one over does not flash for it again")

-- Ready Flash off: the next one to finish closes its ring without a burst
CommanderProductionDB.RadialReadyFlash = false
now = now + 31
Redraw()
ready = DiscShowing("Interface\\Icons\\INV_Misc_PocketWatch_01")
CHECK(ready ~= nil and ready.arc.full.__shown == true and ready.flash.__shown == false,
    "ready: Ready Flash off closes the ring quietly")
CommanderProductionDB.RadialReadyFlash = true
CommanderProductionDB.LingerTime = 10

-- Back to bars: the discs are put away and the rows are rows again
CommanderProductionDB.LingerReady = false
cooldowns[1] = { start = now, duration = 30 }
cooldowns[2] = { start = now, duration = 60 }
Redraw()
CommanderProductionDB.Layout = "BARS_DOWN"
Redraw()
rows = ShownRows()
CHECK(#rows == 2 and root.__w == 130, "radial -> bars: bar geometry restored", tostring(root.__w))
if rows[1] and rows[1].disc then
    local d = rows[1].disc
    CHECK(d.__shown == false and d.__scripts.OnUpdate == nil and d.spark.__shown == false and d.arc.cd.__shown == false,
        "radial -> bars: the disc is cleared and its clock stopped")
    CHECK(rows[1].icon.__shown == true and rows[1].bar.__shown == true and rows[1].label.__shown == true,
        "radial -> bars: the row's own icon, bar and name are back")
end
CommanderProductionDB.Layout = "ICONS"
Redraw()
rows = ShownRows()
CHECK(rows[1] and rows[1].__w == 26 and rows[1].icon.__shown == true and rows[1].disc.__shown == false,
    "radial -> strip: plain icons again", rows[1] and tostring(rows[1].__w))
CommanderProductionDB.Layout = "RADIAL"
Redraw()
rows = ShownRows()
CHECK(rows[1] and rows[1].disc.__shown == true and rows[1].disc.arc.cd.__shown == true
    and rows[1].disc.arc.cd.__cd[2] == 30 and rows[1].icon.__shown == false,
    "bars -> radial: a cleared disc comes back painted")

-- The settings page: the disc's foldout follows the layout, and every
-- Radial setting has a control that writes it
do
    local page
    for _, cat in ipairs(categories) do
        if cat.__panel and cat.__panel._key == "Production" then page = cat.__panel end
    end
    local fold = page and page._folds and page._folds[1]
    CHECK(fold ~= nil and fold.title == "Radial: The Disc" and #page._folds == 1, "page: one foldout, the disc's")
    if fold then
        CHECK(fold.isShown() == true, "page: the disc's options are on the page under a Radial layout")
        CommanderProductionDB.Layout = "ICONS"
        CHECK(fold.isShown() == false, "page: ...and off it under any other")
        CommanderProductionDB.Layout = "RADIAL"
        local after = 0
        for _, e in ipairs(page._rows) do
            if e.fold == nil and not e.header then after = after + 1 end
        end
        CHECK(after >= 10, "page: the rows around the foldout stay on the page when it is shut", after)
    end
    local glowDropdown = _G.CommanderUIDropDown3
    ToggleDropDownMenu(1, nil, glowDropdown)
    local hasDefault, hasOff = false, false
    for _, info in ipairs(menuCaptured) do
        if info.value == "SOFT" then hasDefault = true end
        if info.value == "OFF" then hasOff = true end
    end
    CHECK(#menuCaptured == 11 and hasDefault and hasOff, "page: ten glow styles and Off", #menuCaptured)
    ToggleDropDownMenu(1, nil, _G.CommanderUIDropDown4)
    CHECK(#menuCaptured == 4, "page: four glow motions", #menuCaptured)

    local source = io.open(ADDONS .. "/Commander_Production/CommanderProductionDB.lua"):read("*a")
    local radialKeys, unreachable = 0, {}
    for key in pairs(CommanderProductionDB) do
        if key:match("^Radial") then
            radialKeys = radialKeys + 1
            if not source:find("CommanderProductionDB." .. key .. " = value", 1, true) then
                unreachable[#unreachable + 1] = key
            end
        end
    end
    CHECK(radialKeys == 14 and #unreachable == 0, "page: every Radial setting has a control",
        radialKeys .. " keys; unreachable: " .. table.concat(unreachable, " "))
end

CommanderProductionDB.Layout = "BARS_DOWN"
cooldowns[1], cooldowns[2] = nil, nil
Redraw()

CHECK(#harnessFailedErrors == 0, "no errors across the run", harnessFailedErrors[1])

-- ===========================================================================
-- The picture. A widget mock cannot see whether a ring sits round its face or
-- a glow swallows its neighbour; a drawing can. With a path argument, a few
-- radial boards are painted through the real runtime, every texture's
-- rectangle is resolved from the anchors the brushes set, and the lot is
-- written out for Harness/render_discs.py to composite from the real art.
-- ===========================================================================

local dumpPath = arg and arg[1]
if dumpPath then
    local OFFSET = {
        CENTER = { 0, 0 }, TOP = { 0, 1 }, BOTTOM = { 0, -1 }, LEFT = { -1, 0 }, RIGHT = { 1, 0 },
        TOPLEFT = { -1, 1 }, TOPRIGHT = { 1, 1 }, BOTTOMLEFT = { -1, -1 }, BOTTOMRIGHT = { 1, -1 },
    }
    -- Centre and size of a widget, root's top-left corner at the origin, y up
    local function Rect(wd)
        if wd == root then
            return root.__w / 2, -root.__h / 2, root.__w, root.__h
        end
        local p = wd.__points and wd.__points[1]
        local rel = (p and p.rel) or wd.__parent
        local rcx, rcy, rw, rh = Rect(rel)
        if not p or p.all then return rcx, rcy, wd.__w or rw, wd.__h or rh end
        local w, h = wd.__w or 0, wd.__h or 0
        local to, from = OFFSET[p.relPoint or p.point], OFFSET[p.point]
        local ax = rcx + to[1] * rw / 2 + (p.x or 0)
        local ay = rcy + to[2] * rh / 2 + (p.y or 0)
        return ax - from[1] * w / 2, ay - from[2] * h / 2, w, h
    end
    local function Visible(wd)
        if wd.__shown == false then return false end
        if wd == root or not wd.__parent then return true end
        return Visible(wd.__parent)
    end
    local function Alpha(wd)
        local a = wd.__alpha or 1
        if wd == root or not wd.__parent then return a end
        return a * Alpha(wd.__parent)
    end
    local function Level(fr)
        if fr.__level then return fr.__level end
        if fr == root or not fr.__parent then return 1 end
        return Level(fr.__parent) + 1
    end
    local function Under(fr, top)
        while fr do
            if fr == top then return true end
            fr = fr.__parent
        end
        return false
    end
    local LAYER = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }

    local function Collect()
        local items = {}
        local function Add(item, wd)
            item.cx, item.cy, item.w, item.h = Rect(wd)
            item.alpha = Alpha(wd)
            items[#items + 1] = item
        end
        for seq, fr in ipairs(allFrames) do
            if fr ~= root and Under(fr, root) and Visible(fr) then
                local level = Level(fr)
                if fr.__kind == "Cooldown" and fr.__cd and fr.__swipe then
                    local c = fr.__color or { 0, 0, 0, 0.8 }
                    Add({ kind = "swipe", tex = fr.__swipe, r = c[1], g = c[2], b = c[3], a = c[4],
                        elapsed = math.max(0, math.min(1, (now - fr.__cd[1]) / fr.__cd[2])),
                        order = { level, 2, 0, seq } }, fr)
                end
                for i, region in ipairs(fr.__regions or {}) do
                    if region.__shown ~= false then
                        if region.__kind == "FontString" then
                            if region.__text and region.__text ~= "" then
                                Add({ kind = "text", text = region.__text, size = (region.__font and region.__font[2]) or 10,
                                    order = { level, 3, 9, seq + i / 100 } }, region)
                            end
                        elseif region.__tex then
                            local c = region.__color or { 1, 1, 1, 1 }
                            local item = { kind = "tex", tex = region.__tex, r = c[1], g = c[2], b = c[3], a = c[4],
                                blend = region.__blend, rot = region.__rot,
                                order = { level, LAYER[region.__layer] or 2, region.__sub or 0, seq + i / 100 } }
                            if region.__masks then
                                local m = region.__masks[1]
                                local mx, my, mw, mh = Rect(m)
                                item.mask = { tex = m.__tex, cx = mx, cy = my, w = mw, h = mh }
                            end
                            Add(item, region)
                        end
                    end
                end
            end
        end
        return items
    end

    local function Json(v)
        local t = type(v)
        if t == "table" then
            local parts = {}
            if #v > 0 or next(v) == nil then
                for i = 1, #v do parts[i] = Json(v[i]) end
                return "[" .. table.concat(parts, ",") .. "]"
            end
            for k, x in pairs(v) do parts[#parts + 1] = string.format("%q:%s", k, Json(x)) end
            return "{" .. table.concat(parts, ",") .. "}"
        elseif t == "string" then
            return '"' .. v:gsub('[\\"]', "\\%0") .. '"'
        end
        return tostring(v)
    end

    SPELLBOOK[3] = { name = "Avenging Wrath", texture = "Interface\\Icons\\Wrath", id = 31884 }
    SPELLBOOK[4] = { name = "Hammer of Justice", texture = "Interface\\Icons\\Hammer", id = 853 }
    SPELLBOOK[5] = { name = "Blessing of Protection", texture = "Interface\\Icons\\BoP", id = 1022 }
    local DISC_DEFAULTS = {
        RadialSize = 40, RadialThickness = 4, RadialTrackAlpha = 0.35, RadialSpark = true,
        RadialCountdown = true, RadialTextShade = 0.45, RadialWipe = false, RadialBackdropAlpha = 0.6,
        RadialBackdropSize = 2, RadialBackdropBorder = true, RadialGlowStyle = "SOFT", RadialGlowSize = 1,
        RadialGlowMotion = "NONE", RadialReadyFlash = true,
        Layout = "RADIAL", PerRow = 20, Spacing = 4, MaxBars = 5, LingerReady = true, LingerTime = 10,
    }
    local scenes = {}
    -- One spell just back (READY, glowing, `sinceReady` into its flash) and
    -- four at different points round the ring
    local function Scene(caption, settings, sinceReady)
        for k, v in pairs(DISC_DEFAULTS) do CommanderProductionDB[k] = v end
        for k, v in pairs(settings) do CommanderProductionDB[k] = v end
        CommanderProductionDB.LingerReady = false
        for slot = 1, 5 do cooldowns[slot] = nil end
        Redraw()
        CommanderProductionDB.LingerReady = true
        now = now + 400
        cooldowns[1] = { start = now - 29.95, duration = 30 }
        Redraw()
        now = now + 0.05
        cooldowns[1] = nil
        cooldowns[2] = { start = now - 6, duration = 60 }
        cooldowns[3] = { start = now - 66, duration = 180 }
        cooldowns[4] = { start = now - 36, duration = 60 }
        cooldowns[5] = { start = now - 268, duration = 300 }
        Redraw()
        now = now + (sinceReady or 0.2)
        Redraw()
        for _, r in ipairs(ShownRows()) do
            local tick = r.disc and r.disc.__scripts.OnUpdate
            if tick then tick(r.disc, 0.016) end
        end
        scenes[#scenes + 1] = { caption = caption, w = root.__w, h = root.__h, items = Collect() }
    end
    -- (The third disc of every board is the one the checks above built with
    -- masks switched off: the square-faced fallback, kept in the picture.)
    Scene("Defaults: 40px disc, 4px ring, backdrop +2, Soft Halo; the READY disc 0.2s into its flash", {})
    Scene("Face Wipe on, countdown off, no backdrop, 56px disc, 6px ring, Runebound glow at 130%",
        { RadialWipe = true, RadialCountdown = false, RadialBackdropAlpha = 0, RadialSize = 56,
          RadialThickness = 6, RadialGlowStyle = "RUNIC", RadialGlowSize = 1.3 }, 1)
    Scene("Right to left, three per row, 28px disc, 2px ring, spacing 2, Holy Halo, backdrop +4 without its border",
        { Layout = "RADIAL_RTL", PerRow = 3, RadialSize = 28, RadialThickness = 2, Spacing = 2,
          RadialGlowStyle = "HALO", RadialBackdropSize = 4, RadialBackdropBorder = false }, 1)
    Scene("Empty ring off, text shade off, 48px disc, 8px ring, Emberflame, backdrop pulled in to -6",
        { RadialTrackAlpha = 0, RadialTextShade = 0, RadialSize = 48, RadialThickness = 8,
          RadialGlowStyle = "EMBER", RadialBackdropSize = -6 }, 1)
    local fh = assert(io.open(dumpPath, "w"))
    fh:write(Json({ scenes = scenes }))
    fh:close()
    CHECK(#harnessFailedErrors == 0, "render boards painted clean", harnessFailedErrors[1])
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
