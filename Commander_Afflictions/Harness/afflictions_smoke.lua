-- Commander Afflictions smoke (luajit) — verification for the 2.2.0 change:
-- Icon Strip direction (ICONS / ICONS_RTL). Loads the REAL Commander_Events
-- framework plus both Afflictions files under a WoW mock, seeds the board
-- with the addon's own test injector, and asserts row anchors both ways.
-- Mock modeled on Commander_Meters/Harness.

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
    if key == "CreateMaskTexture" then
        local fn = function(s) local t = NewWidget("MaskTexture"); t.__parent = s; return t end
        rawset(self, key, fn); return fn
    end
    if key == "CreateFontString" then
        local fn = function(s) local t = NewWidget("FontString"); t.__parent = s; return t end
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

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
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

C_Timer = {
    After = function() end,
    NewTicker = function()
        local t = { cancelled = false }
        t.Cancel = function(self) self.cancelled = true end
        return t
    end,
}

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

-- Unit API: just enough for login and the test board
function UnitGUID(unit) if unit == "player" then return "Player-0-ME" end return nil end
function UnitName(unit) if unit == "player" then return "Devinp" end return nil end
function UnitExists(unit) return unit == "player" end
function UnitIsUnit(a, b) return a == b end
function IsInRaid() return false end
function IsInGroup() return false end

-- ===========================================================================
-- Load the real framework + addon
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

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Afflictions/CommanderAfflictionsDB.lua")
Load(ADDONS .. "/Commander_Afflictions/CommanderAfflictions.lua")

Fire("ADDON_LOADED", "Commander_Afflictions")
Fire("PLAYER_LOGIN")
CHECK(#harnessFailedErrors == 0, "login clean", harnessFailedErrors[1])
CHECK(CommanderAfflictionsDB.Layout == "BARS_DOWN", "layout default")

local root = _G.CommanderAfflictionsFrame
CHECK(root ~= nil, "root frame exists")

-- Seed the board through the addon's own injector: 3 timed + 1 unknown
CommanderAfflictions_Test()

-- ===========================================================================
-- Strip geometry: LTR vs RTL row anchoring
-- ===========================================================================

local function ShownRows()
    local rows = {}
    for _, f in ipairs(allFrames) do
        if f.__parent == root and f.geometrySig and f.__shown then
            rows[#rows + 1] = f
        end
    end
    return rows
end

local function Redraw()
    Commander.Notify(COMMANDER_AFFLICTIONS_EVENTS.UPDATE)
end

local ICON_STEP = 26 + 4  -- ICON_SIZE + ICON_GAP in the addon

CommanderAfflictionsDB.Layout = "ICONS"
Redraw()
local rows = ShownRows()
CHECK(#rows == 4, "ICONS: four test entries shown", #rows)
if #rows >= 2 then
    local a1, a2 = rows[1].__points[1], rows[2].__points[1]
    CHECK(a1 and a1.point == "TOPLEFT" and a1.relPoint == "TOPLEFT" and a1.x == 0,
        "ICONS: row 1 anchors TOPLEFT at 0", a1 and (a1.point .. "@" .. tostring(a1.x)))
    CHECK(a2 and a2.point == "TOPLEFT" and a2.x == ICON_STEP,
        "ICONS: row 2 marches right", a2 and (a2.point .. "@" .. tostring(a2.x)))
end
CHECK(root.__w == 4 * ICON_STEP - 4, "ICONS: root width fits four icons", tostring(root.__w))

CommanderAfflictionsDB.Layout = "ICONS_RTL"
Redraw()
rows = ShownRows()
CHECK(#rows == 4, "ICONS_RTL: four test entries shown", #rows)
if #rows >= 2 then
    local a1, a2 = rows[1].__points[1], rows[2].__points[1]
    CHECK(a1 and a1.point == "TOPRIGHT" and a1.relPoint == "TOPRIGHT" and a1.x == 0,
        "ICONS_RTL: row 1 anchors TOPRIGHT at 0", a1 and (a1.point .. "@" .. tostring(a1.x)))
    CHECK(a2 and a2.point == "TOPRIGHT" and a2.x == -ICON_STEP,
        "ICONS_RTL: row 2 marches left", a2 and (a2.point .. "@" .. tostring(a2.x)))
end
CHECK(root.__w == 4 * ICON_STEP - 4, "ICONS_RTL: root width identical", tostring(root.__w))
CHECK(#harnessFailedErrors == 0, "RTL redraw clean", harnessFailedErrors[1])

CommanderAfflictionsDB.Layout = "BARS_DOWN"
Redraw()
rows = ShownRows()
if #rows >= 1 then
    local a1 = rows[1].__points[1]
    CHECK(a1 and a1.point == "TOPLEFT", "BARS_DOWN: bars geometry restored", a1 and a1.point)
end
CHECK(root.__w == (CommanderAfflictionsDB.BarWidth or 130) + 20, "BARS_DOWN: root width restored",
    tostring(root.__w))

-- ===========================================================================
-- Settings panel: the Layout dropdown lists both strip directions
-- ===========================================================================

-- Panel dropdown order: 1 Layout, 2 Drain Overlay, 3 Frame Style
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
    if rtl then
        rtl.func(rtl)
        CHECK(CommanderAfflictionsDB.Layout == "ICONS_RTL", "dropdown writes the DB")
    end
end

CHECK(#harnessFailedErrors == 0, "no errors across the run", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
