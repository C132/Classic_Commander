-- Commander Armory UI harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all five Commander_Armory files under the suite's permissive WoW mock,
-- on top of a FIXTURED WORLD: nineteen paperdoll slots, three bags (one of them
-- a quiver, so the family-0 rule has something to exclude), a bank, a real
-- cursor with real item locks, and a character frame with five tabs waiting for
-- a sixth.
--
-- The cursor and the locks are the reason this file is long. The swap sequencer
-- is the part of this module most likely to carry a subtle bug, and it can only
-- be exercised by a mock where a pickup genuinely empties the square it came
-- from, locks it, and fires ITEM_LOCK_CHANGED -- so that is what the mock does.
-- A run below really moves items between the fixture containers, and the
-- assertions afterwards read the fixture, not the addon's opinion of it.
--
-- Every check asserts on CONTENT. "Nothing threw" cannot tell a working feature
-- from one that silently does nothing, which is why every frame and row in this
-- module was given a global name or a named field in the first place.
--
--   /opt/homebrew/bin/luajit armory_ui_harness.lua

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

-- ===========================================================================
-- WoW mock: the shared suite preamble
-- ===========================================================================

-- A REAL epoch. The bank cache stamps time() and reports its age in minutes; a
-- toy clock makes that arithmetic meaningless.
local now = 1786000000
local sessionBase = 1785999000
function time() return now end
function date(fmt, t) return os.date(fmt or "%c", t or now) end
function GetTime() return now - sessionBase end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local function PrintedMatching(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern) then return line end
    end
    return nil
end

local function ClearPrintLog()
    for i = #printLog, 1, -1 do printLog[i] = nil end
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err)
        harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err)
    end
end

local VALID_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE, MONOCHROME"] = true }

local allFontStrings = {}
local allTextures = {}
local frames = {}
local eventRegistry = {}

-- GetID is deliberately NOT here: the paperdoll slot buttons and the sixth
-- character tab are identified entirely by their id, so a constant 1 would make
-- every slot look like the head and the tab check meaningless.
local NUMERIC_GETTERS = {
    GetWidth = 300, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetNumPoints = 1, GetAlpha = 1, GetValue = 0,
}

local function IsMethodName(key)
    return type(key) == "string" and key:match("^[A-Z]") and not key:match("^[A-Z][a-z]*$")
        or (type(key) == "string" and (key:match("^Set") or key:match("^Get") or key:match("^Is")
        or key:match("^Can") or key:match("^Enable") or key:match("^Disable")
        or key:match("^Register") or key:match("^Unregister") or key:match("^Hook")
        or key:match("^Clear") or key:match("^Create") or key:match("^Show")
        or key:match("^Hide") or key:match("^Raise") or key:match("^Start")
        or key:match("^Stop") or key:match("^Add") or key:match("^Lock")))
end

local NewWidget

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        local fn = function() return v end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateTexture" then
        -- The draw layer is the second argument and it matters here: window art
        -- belongs on BORDER, the layer Blizzard's own character tabs use. The
        -- mock recorded the parent and the texture path but discarded the layer,
        -- so a check could confirm art existed and not that it would be drawn in
        -- the right order.
        local fn = function(s, name, layer)
            local t = NewWidget("Texture", type(name) == "string" and name or nil)
            t.__parent = s
            t.__layer = layer
            allTextures[#allTextures + 1] = t
            if type(name) == "string" then _G[name] = t end
            return t
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateFontString" then
        local fn = function(s, name)
            local t = NewWidget("FontString", type(name) == "string" and name or nil)
            t.__parent = s
            allFontStrings[#allFontStrings + 1] = t
            if type(name) == "string" then _G[name] = t end
            return t
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetScript" or key == "HookScript" then
        local fn = function(s, name, handler)
            -- HookScript must CHAIN, never replace (a suite harness lesson)
            local existing = s.__scripts[name]
            if key == "HookScript" and existing then
                s.__scripts[name] = function(...) existing(...) handler(...) end
            else
                s.__scripts[name] = handler
            end
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn)
        return fn
    end
    if key == "RegisterEvent" or key == "RegisterUnitEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            for _, existing in ipairs(eventRegistry[event]) do
                if existing == s then return end
            end
            table.insert(eventRegistry[event], s)
        end
        rawset(self, key, fn)
        return fn
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
        rawset(self, key, fn)
        return fn
    end
    if key == "Show" then
        local fn = function(s)
            local was = s.__shown
            s.__shown = true
            if not was and s.__scripts.OnShow then s.__scripts.OnShow(s) end
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "Hide" then
        local fn = function(s)
            local was = s.__shown
            s.__shown = false
            if was and s.__scripts.OnHide then s.__scripts.OnHide(s) end
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetShown" then
        local fn = function(s, v) if v then s:Show() else s:Hide() end end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetSize" then
        local fn = function(s, w, h) s.__w, s.__h = w, h end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetVertexColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetTextColor" then
        local fn = function(s, r, g, b, a) s.__color = { r, g, b, a } end
        rawset(self, key, fn)
        return fn
    end
    -- Desaturation is a STATE the module uses to mean exactly one thing
    -- ("locked"), so it has to be readable rather than swallowed.
    if key == "SetDesaturated" then
        local fn = function(s, v) s.__desat = v and true or false end
        rawset(self, key, fn)
        return fn
    end
    if key == "IsDesaturated" then
        local fn = function(s) return s.__desat end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetTexture" then
        local fn = function(s, tex) s.__texture = tex end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetTexture" then
        local fn = function(s) return s.__texture end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetWidth" then
        local fn = function(s, w) s.__w = w end
        rawset(self, key, fn)
        return fn
    end
    if key == "IsShown" or key == "IsVisible" then
        local fn = function(s) return s.__shown end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetText" then
        local fn = function(s, text) s.__text = text end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetText" then
        local fn = function(s) return s.__text or "" end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetFont" then
        local fn = function(s, path, size, flags)
            assert(type(path) == "string" and type(size) == "number",
                "SetFont bad args")
            assert(flags == nil or VALID_FLAGS[flags],
                "SetFont invalid flags: " .. tostring(flags))
            s.__font = { path, size, flags }
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetFont" then
        local fn = function(s)
            local f = s.__font or { "Fonts\\FRIZQT__.TTF", 12, "" }
            return f[1], f[2], f[3]
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetID" then
        local fn = function(s, id) s.__id = id end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetID" then
        local fn = function(s) return s.__id or 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAttribute" then
        local fn = function(s, name, value)
            s.__attributes = s.__attributes or {}
            s.__attributes[name] = value
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetAttribute" then
        local fn = function(s, name) return s.__attributes and s.__attributes[name] end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetChecked" then
        local fn = function(s, v) s.__checked = v and true or false end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetChecked" then
        local fn = function(s) return s.__checked end
        rawset(self, key, fn)
        return fn
    end
    if key == "Enable" then
        local fn = function(s) s.__enabled = true end
        rawset(self, key, fn)
        return fn
    end
    if key == "Disable" then
        local fn = function(s) s.__enabled = false end
        rawset(self, key, fn)
        return fn
    end
    if key == "IsEnabled" then
        local fn = function(s) return s.__enabled ~= false end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] =
                { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = nil end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetParent" then
        local fn = function(s, parent) s.__parent = parent end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetParent" then
        local fn = function(s) return s.__parent end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetFrameLevel" then
        local fn = function(s, level) s.__level = level end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetThumbTexture" then
        local fn = function() return NewWidget("Texture") end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetName" then
        local fn = function(s) return s.__name end
        rawset(self, key, fn)
        return fn
    end
    if IsMethodName(key) then
        local fn = function() end
        rawset(self, key, fn)
        return fn
    end
    return nil
end

NewWidget = function(kind, name)
    local w = setmetatable({
        __kind = kind, __name = name, __scripts = {}, __shown = true,
    }, WidgetMT)
    return w
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
        allFontStrings[#allFontStrings + 1] = f.Text
    end
    if template and template:find("BasicFrameTemplate") then
        -- Auto-generated widget methods are PREFIX matched only: a template
        -- child that is not created explicitly reads nil and explodes on the
        -- first method call.
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
        allFontStrings[#allFontStrings + 1] = f.TitleText
        f.Bg = NewWidget("Texture")
        f.TitleBg = NewWidget("Texture")
        f.Inset = NewWidget("Frame")
        f.NineSlice = NewWidget("Frame")
    end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
tremove = table.remove
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
strsplit = function(sep, str)
    local out = {}
    for piece in tostring(str):gmatch("[^" .. sep .. "]+") do out[#out + 1] = piece end
    return unpack(out)
end

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalSmall = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
GameFontDisable = NewWidget("Font")
NumberFontNormal = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}
SlashCmdList = {}

-- FrameXML owns this table on a live client; the addon only ever adds a key to
-- it (assigning the whole table would taint it), so the harness stands it up.
StaticPopupDialogs = {}
local popupsShown = {}
function StaticPopup_Show(which, arg) popupsShown[#popupsShown + 1] = { which = which, arg = arg } end
function StaticPopup_Hide() end
function StaticPopup_Visible() return false end
local function LastPopup() return popupsShown[#popupsShown] end

local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel, title)
        local cat = { __panel = panel, __title = title, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterCanvasLayoutSubcategory = function(parent, panel, title)
        local cat = { __panel = panel, __title = title, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat
        return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }

-- C_Timer.After must feed an EXECUTABLE queue: the UI's repaint debounce
-- reschedules itself, so a queue that is only recorded proves nothing.
local timers, tickers = {}, {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn }
        tickers[#tickers + 1] = t
        return t
    end,
}

local dropdownInits = {}
local menuCaptured = {}
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

-- Fire events by iterating a COPY of the registry: a handler may register or
-- unregister mid-dispatch. Errors are captured rather than thrown so one broken
-- handler produces one FAIL line instead of ending the run.
local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local copy = {}
    for i, frame in ipairs(list) do copy[i] = frame end
    local args = { n = select("#", ...), ... }
    for _, frame in ipairs(copy) do
        local handler = frame.__scripts.OnEvent
        if handler then
            local ok, err = xpcall(function()
                return handler(frame, event, unpack(args, 1, args.n))
            end, function(e) return tostring(e) .. "\n" .. debug.traceback("", 2) end)
            if not ok then
                harnessFailedErrors[#harnessFailedErrors + 1] = event .. " -> " .. tostring(err)
            end
        end
    end
end

local function RunTimers()
    local due = {}
    for i = #timers, 1, -1 do
        if timers[i].at <= now then
            due[#due + 1] = timers[i].fn
            table.remove(timers, i)
        end
    end
    for i = #due, 1, -1 do due[i]() end
end

local function RunTickers()
    local copy = {}
    for i, t in ipairs(tickers) do copy[i] = t end
    for _, t in ipairs(copy) do t.fn() end
end

-- Drive OnUpdate on every created frame, or an anonymous-local ticker (the
-- flyout's alt-key watcher is one) gets zero coverage.
local function RunFrames()
    local count = #frames
    for i = 1, count do
        local f = frames[i]
        local fn = f.__scripts and f.__scripts.OnUpdate
        if fn and f.__shown then fn(f, 0.25) end
    end
end

local function Advance(seconds, step)
    step = step or 0.25
    local elapsed = 0
    while elapsed < seconds do
        now = now + step
        elapsed = elapsed + step
        RunTimers()
        RunTickers()
        RunFrames()
    end
end

function hooksecurefunc(a, b, c)
    local holder, name, fn
    if type(a) == "string" then holder, name, fn = _G, a, b else holder, name, fn = a, b, c end
    local original = holder[name]
    if type(original) ~= "function" then return end
    holder[name] = function(...)
        local results = { original(...) }
        fn(...)
        return unpack(results)
    end
end

-- ===========================================================================
-- The fixtured world
-- ===========================================================================

-- Item canon. Deliberately written out rather than derived from
-- CommanderArmoryData: a fixture that shares the code under test's tables can
-- only ever agree with it.
local ITEMS = {}
local function Item(id, name, equipLoc, classID, subClassID, quality, ilvl, stats)
    ITEMS[id] = {
        id = id, name = name, equipLoc = equipLoc, classID = classID,
        subClassID = subClassID, quality = quality, ilvl = ilvl,
        icon = "Interface\\Icons\\Fixture_" .. id, stats = stats,
    }
    return id
end

local STR, STA, INT = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT", "ITEM_MOD_INTELLECT_SHORT"

-- Worn at login: a level-70 protection paladin's kit.
Item(41001, "Lightbringer Faceguard", "INVTYPE_HEAD",     4, 4, 4, 120, { [STR] = 30, [STA] = 45 })
Item(41002, "Pendant of Titans",      "INVTYPE_NECK",     4, 0, 4, 115, { [STA] = 24 })
Item(41003, "Lightbringer Shoulders", "INVTYPE_SHOULDER", 4, 4, 4, 115, { [STR] = 22, [STA] = 33 })
Item(41004, "Cloak of Fire",          "INVTYPE_CLOAK",    4, 0, 3, 110, { [STA] = 18 })
Item(41005, "Lightbringer Chestguard", "INVTYPE_CHEST",   4, 4, 4, 120, { [STR] = 30, [STA] = 48 })
Item(41006, "Bracers of Dawn",        "INVTYPE_WRIST",    4, 4, 3, 105, { [STA] = 18 })
Item(41007, "Gauntlets of the Sun",   "INVTYPE_HAND",     4, 4, 4, 115, { [STR] = 24, [STA] = 30 })
Item(41008, "Girdle of Valor",        "INVTYPE_WAIST",    4, 4, 3, 110, { [STA] = 27 })
Item(41009, "Legplates of Light",     "INVTYPE_LEGS",     4, 4, 4, 120, { [STR] = 28, [STA] = 42 })
Item(41010, "Boots of the Righteous", "INVTYPE_FEET",     4, 4, 3, 110, { [STA] = 27 })
Item(41011, "Band of Dawn",           "INVTYPE_FINGER",   4, 0, 3, 105, { [STA] = 18 })
Item(41012, "Signet of Vigor",        "INVTYPE_FINGER",   4, 0, 4, 115, { [STA] = 24 })
Item(41013, "Card of Vengeance",      "INVTYPE_TRINKET",  4, 0, 4, 115, { [STR] = 40 })
Item(41014, "Adamantine Figurine",    "INVTYPE_TRINKET",  4, 0, 3, 100, { [STA] = 20 })
Item(41015, "Blade of the Dawn",      "INVTYPE_WEAPON",   2, 7, 4, 120, { [STR] = 20 })
Item(41016, "Aegis of the Sun",       "INVTYPE_SHIELD",   4, 6, 4, 115, { [STA] = 30 })
Item(41017, "Libram of Light",        "INVTYPE_RELIC",    4, 7, 3, 100, nil)

-- In the bags.
Item(41020, "Helm of the Vanguard",   "INVTYPE_HEAD",     4, 4, 4, 133, { [STR] = 36, [STA] = 51 })
Item(41021, "Battleworn Helm",        "INVTYPE_HEAD",     4, 4, 2, 80,  { [STA] = 12 })
Item(41022, "Second Blade",           "INVTYPE_WEAPON",   2, 7, 3, 110, { [STR] = 14 })
Item(41023, "Tome of Wisdom",         "INVTYPE_HOLDABLE", 4, 0, 3, 100, { [INT] = 20 })
Item(41024, "Sunfire Bow",            "INVTYPE_RANGED",   2, 2, 3, 100, nil)
Item(41025, "Idol of the Wild",       "INVTYPE_RELIC",    4, 8, 3, 100, nil)
Item(41026, "Libram of Fervour",      "INVTYPE_RELIC",    4, 7, 4, 125, nil)
Item(41027, "Silk Robes",             "INVTYPE_ROBE",     4, 1, 2, 60,  { [INT] = 10 })
Item(41028, "Bloodfist Gauntlets",    "INVTYPE_HAND",     4, 4, 3, 118, { [STR] = 28 })
Item(41029, "Ring of Woe",            "INVTYPE_FINGER",   4, 0, 3, 100, { [STA] = 15 })
Item(41030, "Sharp Arrow",            "INVTYPE_AMMO",     6, 2, 1, 1,   nil)
Item(41031, "Healing Potion",         "",                 0, 0, 1, 0,   nil)
Item(41032, "Netherweave Bag",        "INVTYPE_BAG",      1, 0, 1, 0,   nil)

-- The quiver itself, worn in a container slot. It exists so GetItemFamily has a
-- real answer to give: the free-slot scan prefers GetContainerNumFreeSlots's
-- second return, and this is the fallback that covers the case it cannot answer.
Item(41050, "Sturdy Quiver",          "INVTYPE_QUIVER",   1, 2, 2, 0,   nil)

-- In the bank.
Item(41040, "Onslaught Breastplate",  "INVTYPE_CHEST",    4, 4, 4, 141, { [STR] = 40, [STA] = 55 })
Item(41041, "Vindicator's Legplates", "INVTYPE_LEGS",     4, 4, 4, 128, { [STR] = 33, [STA] = 45 })

local function Link(itemID)
    local it = ITEMS[itemID]
    if not it then return nil end
    return "|cffffffff|Hitem:" .. itemID .. ":0:0:0:0:0:0:0:70|h[" .. it.name .. "]|h|r"
end

-- The equip-loc map is the mock's OWN copy, so that a candidate the addon
-- offers and the "client" then refuses shows up as a failed run rather than
-- passing because both sides share one wrong table.
local SLOTS_FOR = {
    INVTYPE_HEAD = { 1 }, INVTYPE_NECK = { 2 }, INVTYPE_SHOULDER = { 3 },
    INVTYPE_BODY = { 4 }, INVTYPE_CHEST = { 5 }, INVTYPE_ROBE = { 5 },
    INVTYPE_WAIST = { 6 }, INVTYPE_LEGS = { 7 }, INVTYPE_FEET = { 8 },
    INVTYPE_WRIST = { 9 }, INVTYPE_HAND = { 10 }, INVTYPE_FINGER = { 11, 12 },
    INVTYPE_TRINKET = { 13, 14 }, INVTYPE_CLOAK = { 15 },
    INVTYPE_WEAPON = { 16, 17 }, INVTYPE_2HWEAPON = { 16 },
    INVTYPE_WEAPONMAINHAND = { 16 }, INVTYPE_WEAPONOFFHAND = { 17 },
    INVTYPE_SHIELD = { 17 }, INVTYPE_HOLDABLE = { 17 },
    INVTYPE_RANGED = { 18 }, INVTYPE_RANGEDRIGHT = { 18 },
    INVTYPE_THROWN = { 18 }, INVTYPE_RELIC = { 18 },
    INVTYPE_TABARD = { 19 }, INVTYPE_AMMO = { 0 },
}

NUM_BAG_SLOTS = 4
NUM_BANKBAGSLOTS = 7
BANK_CONTAINER = -1

local containers = {
    [-1] = { size = 24, family = 0, items = {} },   -- the bank proper
    [0]  = { size = 16, family = 0, items = {} },   -- backpack
    [1]  = { size = 16, family = 0, items = {} },
    [2]  = { size = 12, family = 1, items = {} },   -- a QUIVER: never spill space
    [3]  = { size = 0,  family = 0, items = {} },
    [4]  = { size = 0,  family = 0, items = {} },
    [5]  = { size = 16, family = 0, items = {} },   -- bank bag 1
    [6]  = { size = 0,  family = 0, items = {} },
    [7]  = { size = 0,  family = 0, items = {} },
    [8]  = { size = 0,  family = 0, items = {} },
    [9]  = { size = 0,  family = 0, items = {} },
    [10] = { size = 0,  family = 0, items = {} },
    [11] = { size = 0,  family = 0, items = {} },
}

local equipped = {
    [1] = 41001, [2] = 41002, [3] = 41003, [5] = 41005, [6] = 41008,
    [7] = 41009, [8] = 41010, [9] = 41006, [10] = 41007, [11] = 41011,
    [12] = 41012, [13] = 41013, [14] = 41014, [15] = 41004, [16] = 41015,
    [17] = 41016, [18] = 41017,
    -- Container slots live past the paperdoll: 19 + bagID. Bag 2 is the quiver.
    [21] = 41050,
}

for slot, id in ipairs({ 41020, 41021, 41022, 41023, 41024, 41025, 41026,
    41027, 41028, 41029, 41030, 41031, 41032 }) do
    containers[0].items[slot] = id
end
containers[-1].items[1] = 41040
containers[5].items[1] = 41041

local BAG0_USED = 13
local EXPECTED_FREE = (containers[0].size - BAG0_USED) + containers[1].size

local lockedInv = {}
local lockedBag = {}
local brokenSlots = {}
local brokenBagItems = {}
local cursor = nil
local combat = false
local casting = false
local dead = false
local dualWield = false
local relicSlot = true
local altDown = false
local shiftDown = false
local merchantOpen = false
local ammoID = nil
local restrictedCalls = {}

local function BagKey(bag, slot) return bag .. ":" .. slot end

local function FireLock() Fire("ITEM_LOCK_CHANGED") end

local function Restricted(name)
    if combat then
        restrictedCalls[#restrictedCalls + 1] = name
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Container API
-- ---------------------------------------------------------------------------

local function ReleaseOrigin(origin)
    if origin.kind == "inv" then
        lockedInv[origin.slot] = nil
    else
        lockedBag[BagKey(origin.bag, origin.slot)] = nil
    end
end

C_Container = {}

function C_Container.GetContainerNumSlots(bag)
    local c = containers[bag]
    return c and c.size or 0
end

function C_Container.GetContainerItemInfo(bag, slot)
    local c = containers[bag]
    local id = c and c.items[slot]
    if not id then return nil end
    local it = ITEMS[id]
    return {
        itemID = id, stackCount = 1, isLocked = lockedBag[BagKey(bag, slot)] and true or false,
        quality = it.quality, hyperlink = Link(id), hasNoValue = false,
        iconFileID = it.icon,
    }
end

function C_Container.GetContainerNumFreeSlots(bag)
    local c = containers[bag]
    if not c then return 0, 0 end
    local used = 0
    for _ in pairs(c.items) do used = used + 1 end
    return c.size - used, c.family
end

function C_Container.GetContainerFreeSlots(bag)
    local c = containers[bag]
    local out = {}
    if not c then return out end
    for slot = 1, c.size do
        if not c.items[slot] then out[#out + 1] = slot end
    end
    return out
end

function C_Container.GetContainerItemDurability(bag, slot)
    local c = containers[bag]
    local id = c and c.items[slot]
    if not id then return nil end
    if brokenBagItems[id] then return 0, 100 end
    return 100, 100
end

function C_Container.ContainerIDToInventoryID(bag) return 19 + bag end

function C_Container.PickupContainerItem(bag, slot)
    if Restricted("PickupContainerItem") then return end
    local c = containers[bag]
    if not c then return end
    if lockedBag[BagKey(bag, slot)] then return end
    if cursor then
        local existing = c.items[slot]
        local origin = cursor.origin
        c.items[slot] = cursor.itemID
        cursor = nil
        if existing then
            -- The client puts the displaced item back where the incoming one
            -- came from; it never strands it on the pointer.
            if origin.kind == "bag" then
                containers[origin.bag].items[origin.slot] = existing
            else
                equipped[origin.slot] = existing
            end
        end
        ReleaseOrigin(origin)
        FireLock()
    else
        local id = c.items[slot]
        if not id then return end
        c.items[slot] = nil
        cursor = { itemID = id, origin = { kind = "bag", bag = bag, slot = slot } }
        lockedBag[BagKey(bag, slot)] = true
        FireLock()
    end
end

-- The bare globals are deprecation shims on this client; provided only so the
-- lint's "the module never touches them" claim has something to be true about.
function GetContainerNumFreeSlots(bag) return C_Container.GetContainerNumFreeSlots(bag) end
function GetContainerNumSlots(bag) return C_Container.GetContainerNumSlots(bag) end

-- ---------------------------------------------------------------------------
-- Item API
-- ---------------------------------------------------------------------------

local function IDFromLink(link)
    if type(link) == "number" then return link end
    if type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

C_Item = {}

function C_Item.GetItemInfoInstant(itemIDOrLink)
    local id = IDFromLink(itemIDOrLink)
    local it = id and ITEMS[id]
    if not it then return nil end
    return it.id, "Fixture", "Fixture", it.equipLoc, it.icon, it.classID, it.subClassID
end

function C_Item.GetItemInfo(itemIDOrLink)
    local id = IDFromLink(itemIDOrLink)
    local it = id and ITEMS[id]
    if not it then return nil end
    -- Fourteen returns, because bindType is the fourteenth and the host reads
    -- exactly that position.
    return it.name, Link(id), it.quality, it.ilvl, 70, "Fixture", "Fixture", 1,
        it.equipLoc, it.icon, 100, it.classID, it.subClassID, 1
end

function C_Item.GetItemUniquenessByID(itemIDOrLink)
    local id = IDFromLink(itemIDOrLink)
    local it = id and ITEMS[id]
    if not it then return false, nil, 1, nil end
    return (it.unique and true or false), nil, 1, nil
end

function C_Item.GetDetailedItemLevelInfo(link)
    local id = IDFromLink(link)
    local it = id and ITEMS[id]
    return it and it.ilvl or 0
end

function C_Item.RequestLoadItemDataByID() end

function GetItemStats(link)
    local id = IDFromLink(link)
    local it = id and ITEMS[id]
    local out = {}
    if it and it.stats then
        for k, v in pairs(it.stats) do out[k] = v end
    end
    return out
end

function GetItemFamily(link)
    local id = IDFromLink(link)
    local it = id and ITEMS[id]
    if not it then return 0 end
    -- Arrows are family 1, and so is the quiver that holds them. Family is the
    -- whole reason a quiver's twelve empty squares are not spill space.
    if it.equipLoc == "INVTYPE_AMMO" or it.equipLoc == "INVTYPE_QUIVER" then return 1 end
    return 0
end

ITEM_QUALITY_COLORS = {
    [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.12, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 },
    [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.50, b = 0 },
}

-- ---------------------------------------------------------------------------
-- Paperdoll / cursor API
-- ---------------------------------------------------------------------------

function GetInventoryItemLink(unit, slot)
    -- Slot 0 deliberately answers nil even when ammo is equipped: that is the
    -- trap the host's AmmoInfo comment is about.
    if slot == 0 then return nil end
    local id = equipped[slot]
    return id and Link(id) or nil
end

function GetInventoryItemID(unit, slot)
    if slot == 0 then return ammoID end
    return equipped[slot]
end

function GetInventoryItemTexture(unit, slot)
    local id = (slot == 0) and ammoID or equipped[slot]
    return id and ITEMS[id] and ITEMS[id].icon or nil
end

function GetInventoryItemCount(unit, slot)
    if slot == 0 then return ammoID and 800 or 0 end
    return equipped[slot] and 1 or 0
end

function GetInventoryItemBroken(unit, slot)
    return brokenSlots[slot] and true or false
end

function GetInventorySlotInfo(name)
    local ids = {
        HeadSlot = 1, NeckSlot = 2, ShoulderSlot = 3, ShirtSlot = 4, ChestSlot = 5,
        WaistSlot = 6, LegsSlot = 7, FeetSlot = 8, WristSlot = 9, HandsSlot = 10,
        Finger0Slot = 11, Finger1Slot = 12, Trinket0Slot = 13, Trinket1Slot = 14,
        BackSlot = 15, MainHandSlot = 16, SecondaryHandSlot = 17, RangedSlot = 18,
        TabardSlot = 19,
    }
    local id = ids[name]
    if not id then error("GetInventorySlotInfo: unknown slot " .. tostring(name)) end
    return id, "Interface\\PaperDoll\\UI-PaperDoll-Slot-" .. name, false
end

function IsInventoryItemLocked(slot) return lockedInv[slot] and true or false end

function CursorHasItem() return cursor ~= nil end

function ClearCursor()
    if not cursor then return end
    local c = cursor
    cursor = nil
    if c.origin.kind == "inv" then
        if not equipped[c.origin.slot] then equipped[c.origin.slot] = c.itemID end
    else
        local target = containers[c.origin.bag]
        if target and not target.items[c.origin.slot] then
            target.items[c.origin.slot] = c.itemID
        end
    end
    ReleaseOrigin(c.origin)
    FireLock()
end

function CursorCanGoInSlot(invSlot)
    if not cursor then return false end
    local it = ITEMS[cursor.itemID]
    if not it then return false end
    local slots = SLOTS_FOR[it.equipLoc]
    if not slots then return false end
    local ok = false
    for _, id in ipairs(slots) do if id == invSlot then ok = true end end
    if not ok then return false end
    -- The SERVER rule, not ours: a one-handed weapon cannot go off-hand without
    -- the dual wield skill, whatever the addon thinks.
    if invSlot == 17 and it.equipLoc == "INVTYPE_WEAPON" and not dualWield then return false end
    return true
end

function PickupInventoryItem(invSlot)
    if Restricted("PickupInventoryItem") then return end
    if cursor then
        if not CursorCanGoInSlot(invSlot) then return end
        if lockedInv[invSlot] then return end
        local displaced = equipped[invSlot]
        local origin = cursor.origin
        equipped[invSlot] = cursor.itemID
        cursor = nil
        if displaced then
            if origin.kind == "bag" then
                containers[origin.bag].items[origin.slot] = displaced
            else
                equipped[origin.slot] = displaced
            end
        end
        ReleaseOrigin(origin)
        FireLock()
    else
        local id = equipped[invSlot]
        if not id then return end
        if lockedInv[invSlot] then return end
        equipped[invSlot] = nil
        cursor = { itemID = id, origin = { kind = "inv", slot = invSlot } }
        lockedInv[invSlot] = true
        FireLock()
    end
end

function EquipPendingItem() end
function SpellIsTargeting() return false end
function InCombatLockdown() return combat end
function UnitCastingInfo(unit) if casting then return "Fixture Cast" end return nil end
function UnitIsDeadOrGhost() return dead end
function UnitClass() return "Paladin", "PALADIN" end
function UnitName() return "Sunward" end
function GetRealmName() return "TestRealm" end
function CanDualWield() return dualWield end
function UnitHasRelicSlot() return relicSlot end
function IsAltKeyDown() return altDown end
-- Shift is the "wear it now" modifier on an authoring row, so it has to be a
-- state the fixture can hold rather than a constant false.
function IsShiftKeyDown() return shiftDown end
C_PaperDollInfo = { OffhandHasWeapon = function() return dualWield end }
C_EventUtils = { IsEventValid = function() return true end }
C_EquipmentSet = {
    CanUseEquipmentSets = function() return false end,
    GetNumEquipmentSets = function() return 0 end,
}
RELICSLOT = "Relic"

MerchantFrame = NewWidget("Frame", "MerchantFrame")
MerchantFrame.__shown = false
MerchantFrame.IsShown = function() return merchantOpen end

-- ---------------------------------------------------------------------------
-- The character frame and its five tabs
-- ---------------------------------------------------------------------------

CharacterFrame = nil   -- introduced later, on purpose: see section A
local PAPERDOLL_TABS = { "PaperDollFrame", "PetPaperDollFrame", "SkillFrame",
    "ReputationFrame", "TokenFrame" }

local function BuildCharacterFrame()
    CharacterFrame = CreateFrame("Frame", "CharacterFrame", UIParent)
    CharacterFrame:Hide()
    CHARACTERFRAME_SUBFRAMES = {}
    for index, name in ipairs(PAPERDOLL_TABS) do
        local sub = CreateFrame("Frame", name, CharacterFrame)
        sub:SetID(index)
        sub:Hide()
        CHARACTERFRAME_SUBFRAMES[index] = name
        local tab = CreateFrame("Button", "CharacterFrameTab" .. index, CharacterFrame)
        tab:SetID(index)
        tab:SetText(name)
    end
end

function PanelTemplates_SetNumTabs(frame, n) frame.__numTabs = n end
function PanelTemplates_TabResize(tab) tab.__resized = true end
function PanelTemplates_SetTab(frame, id) frame.selectedTab = id end

function CharacterFrame_ShowSubFrame(name)
    for _, sub in pairs(CHARACTERFRAME_SUBFRAMES) do
        local f = _G[sub]
        if f then
            if sub == name then f:Show() else f:Hide() end
        end
    end
end

function ToggleCharacter(name)
    local frame = _G[name]
    if not frame then return end
    if CharacterFrame:IsShown() and frame:IsShown() then
        CharacterFrame:Hide()
        CharacterFrame_ShowSubFrame(nil)
        return
    end
    CharacterFrame:Show()
    CharacterFrame_ShowSubFrame(name)
    PanelTemplates_SetTab(CharacterFrame, frame:GetID())
end

-- The built-in handler is a string-name if/elseif chain that simply no-ops for
-- anything past tab 5. Reproduced faithfully, because the module's whole tab
-- integration rests on that no-op being hookable.
function CharacterFrameTab_OnClick(self)
    local id = self and self:GetID()
    local name = PAPERDOLL_TABS[id]
    if name then ToggleCharacter(name) end
end

local paperdollUpdates = 0
function PaperDollItemSlotButton_Update(button) paperdollUpdates = paperdollUpdates + 1 end
function PaperDollItemSlotButton_OnEnter() end

local SLOT_BUTTONS = {
    [1] = "CharacterHeadSlot", [2] = "CharacterNeckSlot", [3] = "CharacterShoulderSlot",
    [4] = "CharacterShirtSlot", [5] = "CharacterChestSlot", [6] = "CharacterWaistSlot",
    [7] = "CharacterLegsSlot", [8] = "CharacterFeetSlot", [9] = "CharacterWristSlot",
    [10] = "CharacterHandsSlot", [11] = "CharacterFinger0Slot", [12] = "CharacterFinger1Slot",
    [13] = "CharacterTrinket0Slot", [14] = "CharacterTrinket1Slot", [15] = "CharacterBackSlot",
    [16] = "CharacterMainHandSlot", [17] = "CharacterSecondaryHandSlot",
    [18] = "CharacterRangedSlot", [19] = "CharacterTabardSlot",
}
for id, name in pairs(SLOT_BUTTONS) do
    local button = CreateFrame("Button", name, UIParent)
    button:SetID(id)
end
-- The ammo button exists on a live client but does NOT inherit
-- PaperDollItemSlotButtonTemplate, so nothing the module hooks ever reaches it.
CreateFrame("Button", "CharacterAmmoSlot", UIParent):SetID(0)

GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.__lines = {}
local tooltipItemLink = nil
GameTooltip.GetItem = function(self)
    if not tooltipItemLink then return nil end
    local id = IDFromLink(tooltipItemLink)
    return ITEMS[id] and ITEMS[id].name, tooltipItemLink
end
GameTooltip.AddLine = function(self, text, r, g, b, wrap)
    self.__lines[#self.__lines + 1] = tostring(text)
end
GameTooltip.SetOwner = function(self) self.__lines = {} end
GameTooltip.SetInventoryItem = function() return true end
GameTooltip.SetBagItem = function() return true end
GameTooltip.SetHyperlink = function() return true end

local function TooltipHas(pattern)
    for _, line in ipairs(GameTooltip.__lines) do
        if line:find(pattern) then return line end
    end
    return nil
end

-- ===========================================================================
-- Load the real framework + the real addon
-- ===========================================================================

local function Load(path) assert(loadfile(path))() end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 0.72, g = 0.78, b = 0.84 },
    { text = "Fel (Warlock)", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}

-- A previous session's saved variables: a suite accent the defaults must not
-- stamp over, and an empty set store.
CommanderArmoryDB = { AccentColor = "FEL" }
CommanderArmorySets = {}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Armory/CommanderArmoryData.lua")
Load(ADDONS .. "/Commander_Armory/CommanderArmoryEngine.lua")
Load(ADDONS .. "/Commander_Armory/CommanderArmoryDB.lua")
Load(ADDONS .. "/Commander_Armory/CommanderArmory.lua")
Load(ADDONS .. "/Commander_Armory/CommanderArmoryUI.lua")

local D = CommanderArmoryData
local E = CommanderArmoryEngine

-- ---------------------------------------------------------------------------
-- Assertion helpers
-- ---------------------------------------------------------------------------

local function TextMatching(pattern)
    for _, fs in ipairs(allFontStrings) do
        if type(fs.__text) == "string" and fs.__text:find(pattern) then return fs.__text end
    end
    return nil
end

local function TextShownSomewhere(text)
    for _, fs in ipairs(allFontStrings) do
        if fs.__text ~= nil and tostring(fs.__text) == text then return true end
    end
    return false
end

local function Strip(text)
    if type(text) ~= "string" then return "" end
    return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Everything the flyout is currently drawing, in the order it is drawn. The
-- rows are named globals precisely so this is possible.
local function FlyoutList()
    local out = {}
    for i = 1, 80 do
        local row = _G["CommanderArmoryFlyoutRow" .. i]
        if not row then break end
        if row:IsShown() and row.data then
            out[#out + 1] = {
                name = row.name.__text,
                badge = row.badge.__text,
                ilvl = tonumber(row.ilvl.__text),
                alpha = row.__alpha or 1,
                row = row,
            }
        end
    end
    return out
end

local function FlyoutNames()
    local names = {}
    for _, entry in ipairs(FlyoutList()) do names[#names + 1] = entry.name end
    return names
end

local function Joined(list) return table.concat(list, " | ") end

local function Contains(list, name)
    for _, value in ipairs(list) do if value == name then return true end end
    return false
end

local function EntryOf(list, name)
    for _, entry in ipairs(list) do if entry.name == name then return entry end end
    return nil
end

local function OpenFlyout(slotID)
    CommanderArmoryUI.CloseFlyout()
    CommanderArmoryUI.OpenFlyout(slotID)
end

-- The heavy half of the host's snapshot is cached for half a second and
-- invalidated by events, so a fixture edit has to say so out loud.
local function WorldChanged()
    Fire("BAG_UPDATE")
    Fire("PLAYER_EQUIPMENT_CHANGED", 1)
    CommanderArmoryUI.Refresh()
end

local function BagSlotOf(itemID)
    for bag = 0, 4 do
        for slot, id in pairs(containers[bag].items) do
            if id == itemID then return bag, slot end
        end
    end
end

local function CountItems(bag)
    local n = 0
    for _ in pairs(containers[bag].items) do n = n + 1 end
    return n
end

-- Capture a set that touches only the named slots and leaves every other slot
-- hands-off. Uses the real capture path and the real scratchpad, so the saved
-- entries are whatever the module would really write -- this is the two-slot
-- hit-cap swap the whole ignore model exists for.
local function CaptureNarrow(name, keep)
    local set = CommanderArmory.NewSet(name)
    local scratch = CommanderArmory.IgnoreScratch()
    for key in pairs(scratch) do scratch[key] = nil end
    local wanted = {}
    for _, key in ipairs(keep) do wanted[key] = true end
    for _, slot in ipairs(D.Slots) do
        if not wanted[slot.key] then scratch[slot.key] = true end
    end
    CommanderArmory.SaveSet(set, scratch)
    return set
end

local function ItemStates(set)
    local n = 0
    for _, entry in pairs((set and set.entries) or {}) do
        if entry.state == "ITEM" then n = n + 1 end
    end
    return n
end

local function DriveRun(seconds)
    Advance(seconds or 4, 0.25)
end

-- ===========================================================================
-- A. Boot with NO CharacterFrame at all: degrade, never error
-- ===========================================================================
-- The RankCheck precedent. Everything the module hangs off Blizzard's character
-- sheet must return nil rather than throw when that sheet is not there, and
-- must build itself later when it appears.

Fire("ADDON_LOADED", "Commander_Armory")
CHECK(CommanderArmoryDB.EnableArmory == true, "A: defaults applied at ADDON_LOADED")
CHECK(CommanderArmoryDB.DBVersion == 1, "A: the migration ladder stamps a version")
CHECK(CommanderArmoryDB.AccentColor == "FEL", "A: a saved suite accent survives ApplyDefaults")
CHECK(CommanderArmoryDB.FlyoutSort == "ILVL", "A: the flyout default sort is item level")
CHECK(type(CommanderArmorySets.Chars) == "table", "A: the set store is seeded outside DefaultSettings")

Fire("PLAYER_LOGIN")
CHECK(#harnessFailedErrors == 0, "A: login with no CharacterFrame raised no errors",
    harnessFailedErrors[1])
CHECK(_G.CommanderArmoryFrame == nil, "A: no character-frame tab is built without a character frame")
CHECK(_G.CharacterFrameTab6 == nil, "A: and no sixth tab either")
CHECK(_G.CommanderArmoryPane ~= nil, "A: the set manager pane is still built")
CHECK(_G.CommanderArmoryEquipWeapons ~= nil, "A: the secure weapon button is still built")
CHECK(CommanderArmory.THEME.accent[2] == 0.95,
    "A: the accent came from the Console palette, not the local five",
    CommanderArmory.THEME.accent[2])

CommanderArmoryUI.Toggle()
CHECK(_G.CommanderArmoryWindow ~= nil and _G.CommanderArmoryWindow:IsShown(),
    "A: /cgear falls back to the detached window when there is no character sheet")
CommanderArmoryUI.Toggle()
CHECK(not _G.CommanderArmoryWindow:IsShown(), "A: and closes it again")

-- Now the character sheet appears. The module must pick it up on the next
-- settings pass rather than needing a reload.
BuildCharacterFrame()
Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
CHECK(#harnessFailedErrors == 0, "A: adopting a late CharacterFrame raised no errors",
    harnessFailedErrors[1])
CHECK(_G.CommanderArmoryFrame ~= nil, "A: the tab frame is built once the sheet exists")

-- ===========================================================================
-- B. The settings page
-- ===========================================================================

local panelCategory
for _, cat in ipairs(categories) do
    if cat.__title == "Armory" then panelCategory = cat end
end
CHECK(panelCategory ~= nil, "B: the Armory settings subcategory is registered")
CHECK(SlashCmdList["COMMANDERUI_ARMORY"] ~= nil, "B: the slash handler is registered")
CHECK(_G.SLASH_COMMANDERUI_ARMORY1 == "/cgear", "B: the canonical slash is /cgear")
CHECK(_G.SLASH_COMMANDERUI_ARMORY2 == "/carmory", "B: the alias is /carmory")

for _, section in ipairs({ "Armory", "Character Panel", "Flyout", "Equipping",
    "Appearance", "Frame" }) do
    CHECK(TextShownSomewhere(section), "B: the settings page has a " .. section .. " section")
end
CHECK(TextMatching("separate saved file") or TextMatching("separate from every option"),
    "B: the Armory section says the sets live in their own file")
CHECK(TextMatching("Restore Defaults") ~= nil, "B: the Restore Defaults footer is drawn")
CHECK(TextMatching("Slash command: /cgear") ~= nil, "B: the footer names the slash command")
CHECK(_G.CommanderArmoryPanelScroll ~= nil, "B: the page is scrollable (MakeScrollable ran)")

local registered = false
for _, mod in ipairs(Commander.GetModules and Commander.GetModules() or {}) do
    if mod.key == "Armory" then registered = true end
end
CHECK(registered, "B: the module registers with the suite directory")

-- ===========================================================================
-- C. The sixth character tab
-- ===========================================================================

local tab = _G.CharacterFrameTab6
CHECK(tab ~= nil, "C: a sixth character tab exists")
CHECK(tab and tab:GetID() == 6, "C: and its id is 6", tab and tab:GetID())
CHECK(tab and tab:GetText() == "Armory", "C: labelled Armory", tab and tab:GetText())
CHECK(CharacterFrame.__numTabs == 6, "C: PanelTemplates_SetNumTabs was told about it",
    CharacterFrame.__numTabs)
CHECK(tab and tab.__resized, "C: and it was sized by hand, since the bounds check loops 1..5")
CHECK(_G.CommanderArmoryFrame:GetID() == 6, "C: the content frame carries the same id")

-- Shipped in 1.0.0 and only caught by a screenshot: CharacterFrame draws the
-- portrait, title and close button and NOTHING else. Every tab supplies its own
-- 384x512 window as four quadrant textures, so a subframe that draws no
-- background is fully transparent and its widgets float over the game world.
-- Nothing else in either harness looks at art, which is exactly why this one
-- has to: the addon loaded clean, raised no error, and looked broken.
do
    local pieces, missing = 0, nil
    for index = 1, 4 do
        local tex = _G["CommanderArmoryBackdrop" .. index]
        if tex and tex.__texture and tex.__texture ~= "" then
            pieces = pieces + 1
        else
            missing = missing or index
        end
    end
    CHECK(pieces == 4, "C: the tab draws its own window backdrop, all four quadrants",
        missing and ("quadrant " .. missing .. " has no texture"))
    local first = _G.CommanderArmoryBackdrop1
    CHECK(first and first.__layer == "BORDER",
        "C: on the BORDER layer, where Blizzard's own tabs put theirs",
        first and tostring(first.__layer))
    CHECK(first and first.__parent == _G.CommanderArmoryFrame,
        "C: parented to the tab frame, so it hides with the tab")
end

local listed = false
for _, name in pairs(CHARACTERFRAME_SUBFRAMES) do
    if name == "CommanderArmoryFrame" then listed = true end
end
CHECK(listed, "C: our frame is listed in CHARACTERFRAME_SUBFRAMES")

CharacterFrameTab_OnClick(tab)
CHECK(_G.CommanderArmoryFrame:IsShown(), "C: clicking tab 6 shows the Armory frame")
CHECK(not _G.PaperDollFrame:IsShown(), "C: and hides the paperdoll")
CHECK(CharacterFrame.selectedTab == 6, "C: the tab strip follows", CharacterFrame.selectedTab)
CHECK(_G.CommanderArmoryPane:IsShown(), "C: the set manager pane docks into the tab")
CHECK(_G.CommanderArmoryPane:GetParent() == _G.CommanderArmoryFrame,
    "C: and is re-parented into it rather than copied")

CharacterFrameTab_OnClick(_G.CharacterFrameTab1)
CHECK(_G.PaperDollFrame:IsShown(), "C: clicking tab 1 brings the paperdoll back")
CHECK(not _G.CommanderArmoryFrame:IsShown(), "C: and hides ours")

-- Back to the Armory tab: everything below wants the pane painting.
CharacterFrameTab_OnClick(tab)
CHECK(_G.CommanderArmoryPane:IsShown(), "C: and back again")

-- ===========================================================================
-- D. The paperdoll: popout arrows and ignore markers
-- ===========================================================================

local popoutCount = 0
for slotID = 0, 19 do
    if _G["CommanderArmoryPopout" .. slotID] then popoutCount = popoutCount + 1 end
end
CHECK(popoutCount == 19, "D: every one of the nineteen slots grew a popout arrow", popoutCount)
CHECK(_G.CommanderArmoryPopout0 == nil, "D: the ammo slot did not")
CHECK(_G.CommanderArmoryPopout1.glyphName == "popoutRight",
    "D: the head arrow points right, away from the model",
    _G.CommanderArmoryPopout1.glyphName)
CHECK(_G.CommanderArmoryPopout10.glyphName == "popoutLeft",
    "D: the hands arrow points left, away from the model",
    _G.CommanderArmoryPopout10.glyphName)
CHECK(_G.CommanderArmoryPopout16.glyphName == "popoutUp",
    "D: the weapon-row arrows point up",
    _G.CommanderArmoryPopout16.glyphName)
CHECK(_G.CommanderArmoryPopout1.slotID == 1 and _G.CommanderArmoryPopout12.slotID == 12,
    "D: each arrow carries the slot id it was built from (GetID, not a .id field)")
CHECK(#_G.CommanderArmoryPopout1.icon == 2, "D: the arrow is drawn from two rotated quads",
    #_G.CommanderArmoryPopout1.icon)
CHECK(_G.CommanderArmoryIgnoreMark1 ~= nil, "D: each slot also grew an ignore overlay")
CHECK(not _G.CommanderArmoryIgnoreMark1:IsShown(),
    "D: which is hidden while no set is selected")

_G.CommanderArmoryPopout1.__scripts.OnClick(_G.CommanderArmoryPopout1)
CHECK(_G.CommanderArmoryFlyout ~= nil and _G.CommanderArmoryFlyout:IsShown(),
    "D: clicking an arrow opens the popout")
CHECK(_G.CommanderArmoryFlyout.title.__text == "HEAD",
    "D: for the slot the arrow belongs to", _G.CommanderArmoryFlyout.title.__text)
CommanderArmoryUI.CloseFlyout()

-- Turning the arrows off must NOT take the markers with them: they are two
-- independent settings sharing one attach point.
CommanderArmoryDB.ShowSlotFlyouts = false
Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
CHECK(not _G.CommanderArmoryPopout1:IsShown(), "D: Slot Popouts off hides the arrows")
CommanderArmoryDB.ShowSlotFlyouts = true
Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
CHECK(_G.CommanderArmoryPopout1:IsShown(), "D: and back on shows them")

local before = paperdollUpdates
PaperDollItemSlotButton_Update(_G.CharacterHeadSlot)
CHECK(paperdollUpdates == before + 1,
    "D: the paperdoll hook chains onto Blizzard's function rather than replacing it")

-- ===========================================================================
-- E. The flyout: what it lists, and in what order
-- ===========================================================================

local snap = CommanderArmory.Snapshot()
CHECK(snap.playerClass == "PALADIN", "E: the snapshot resolved the class", snap.playerClass)
CHECK(snap.canDualWield == false, "E: a paladin cannot dual wield")
CHECK(snap.hasRelicSlot == true, "E: and has a relic slot")
CHECK(snap.freeBagSlots == EXPECTED_FREE,
    "E: free bag slots count family-0 containers only -- the quiver's twelve do not count",
    tostring(snap.freeBagSlots) .. " expected " .. EXPECTED_FREE)
CHECK(GetItemFamily(Link(41050)) == 1,
    "E: and the fixture really does have a non-zero family container to exclude")

OpenFlyout(1)
local head = FlyoutList()
CHECK(#head == 2, "E: the head popout lists both spare helms", Joined(FlyoutNames()))
CHECK(head[1] and head[1].name == "Helm of the Vanguard",
    "E: sorted by item level DESCENDING, not by bag position", Joined(FlyoutNames()))
CHECK(head[1] and head[1].ilvl == 133, "E: and the item level is drawn", head[1] and head[1].ilvl)
CHECK(head[2] and head[2].name == "Battleworn Helm", "E: the worse helm is second")
CHECK(not Contains(FlyoutNames(), "Lightbringer Faceguard"),
    "E: the helm already worn there is NOT offered for its own slot")
CHECK(head[1] and head[1].badge == "bags", "E: a bag row is badged bags", head[1] and head[1].badge)

OpenFlyout(11)
local ring = FlyoutList()
CHECK(Contains(FlyoutNames(), "Signet of Vigor"),
    "E: the ring worn in the OTHER finger is offered, so a ring swap is one click",
    Joined(FlyoutNames()))
CHECK(not Contains(FlyoutNames(), "Band of Dawn"),
    "E: but the ring already in this finger is not")
local signet = EntryOf(ring, "Signet of Vigor")
CHECK(signet and signet.badge == "worn: Ring 2",
    "E: and it says which slot it is coming off", signet and signet.badge)
CHECK(ring[1] and ring[1].name == "Signet of Vigor",
    "E: item level still decides the order across bags and body", Joined(FlyoutNames()))

OpenFlyout(17)
local off = FlyoutNames()
CHECK(not Contains(off, "Second Blade"),
    "E: a one-hander is refused off-hand while the character cannot dual wield", Joined(off))
CHECK(not Contains(off, "Blade of the Dawn"),
    "E: including the one already in the main hand")
CHECK(Contains(off, "Tome of Wisdom"),
    "E: a holdable is offered off-hand regardless of dual wield", Joined(off))

dualWield = true
WorldChanged()
OpenFlyout(17)
local off2 = FlyoutNames()
CHECK(Contains(off2, "Second Blade"),
    "E: dual wield trained, and the one-hander appears", Joined(off2))
CHECK(Contains(off2, "Blade of the Dawn"),
    "E: as does the weapon worn in the main hand")
dualWield = false
WorldChanged()

-- Ammo is outside the model entirely: no canon entry, no popout, no candidates.
CommanderArmoryUI.CloseFlyout()
CommanderArmoryUI.OpenFlyout(0)
CHECK(not (_G.CommanderArmoryFlyout and _G.CommanderArmoryFlyout:IsShown()),
    "E: slot 0 (ammo) has no popout at all")
CHECK(#CommanderArmory.Candidates(0) == 0, "E: and no candidates either")
CHECK(not Contains(FlyoutNames(), "Sharp Arrow"), "E: arrows never appear in any list")

-- Search, and the empty state that says WHY it is empty.
OpenFlyout(1)
_G.CommanderArmoryFlyoutSearch:SetText("vanguard")
_G.CommanderArmoryFlyoutSearch.__scripts.OnTextChanged(_G.CommanderArmoryFlyoutSearch)
CHECK(#FlyoutList() == 1 and FlyoutNames()[1] == "Helm of the Vanguard",
    "E: search narrows the list", Joined(FlyoutNames()))
_G.CommanderArmoryFlyoutSearch:SetText("nothing at all")
_G.CommanderArmoryFlyoutSearch.__scripts.OnTextChanged(_G.CommanderArmoryFlyoutSearch)
CHECK(#FlyoutList() == 0, "E: and can narrow it to nothing")
CHECK(Strip(_G.CommanderArmoryFlyout.empty.__text):find("nothing at all"),
    "E: and the empty state quotes the search rather than going blank",
    _G.CommanderArmoryFlyout.empty.__text)
_G.CommanderArmoryFlyoutSearch:SetText("")
_G.CommanderArmoryFlyoutSearch.__scripts.OnTextChanged(_G.CommanderArmoryFlyoutSearch)

-- Alt-click hides an item. This is the fix for the real failure mode: twelve
-- junk greens burying the two pieces you actually alternate between.
OpenFlyout(1)
altDown = true
local junk = FlyoutList()[2]
CHECK(junk and junk.name == "Battleworn Helm", "E: the junk helm is there to be hidden",
    junk and junk.name)
junk.row.__scripts.OnClick(junk.row)
altDown = false
OpenFlyout(1)
CHECK(#FlyoutList() == 1 and FlyoutNames()[1] == "Helm of the Vanguard",
    "E: alt-click hides an item from the popout", Joined(FlyoutNames()))
CHECK(equipped[1] == 41001, "E: and does NOT equip it on the way past", equipped[1])
altDown = true
OpenFlyout(1)
local revealed = EntryOf(FlyoutList(), "Battleworn Helm")
CHECK(revealed ~= nil, "E: holding alt reveals what you have hidden")
CHECK(revealed and revealed.badge == "hidden",
    "E: marked hidden, so you know why it came back", revealed and revealed.badge)
revealed.row.__scripts.OnClick(revealed.row)
altDown = false
OpenFlyout(1)
CHECK(#FlyoutList() == 2, "E: and alt-clicking again un-hides it", Joined(FlyoutNames()))
CommanderArmoryUI.CloseFlyout()

-- ===========================================================================
-- F. The bank: an instruction, not a dead end
-- ===========================================================================

-- Nothing has been at the bank yet, so the cache is empty and the banked chest
-- piece is simply unknown.
OpenFlyout(5)
CHECK(not Contains(FlyoutNames(), "Onslaught Breastplate"),
    "F: an unvisited bank contributes nothing -- we never invent stock")

Fire("BANKFRAME_OPENED")
CHECK(CommanderArmory.AtBank(), "F: BANKFRAME_OPENED puts us at the bank")
CHECK(CommanderArmory.BankAge() > 0, "F: and stamps the cache")
OpenFlyout(5)
local atBankChest = FlyoutList()
CHECK(Contains(FlyoutNames(), "Onslaught Breastplate"),
    "F: at the bank the banked chest piece is listed", Joined(FlyoutNames()))
local onslaught = EntryOf(atBankChest, "Onslaught Breastplate")
CHECK(onslaught and onslaught.badge == "bank →",
    "F: badged as a withdrawal, because at the bank the click really works",
    onslaught and onslaught.badge)

Fire("BANKFRAME_CLOSED")
CHECK(not CommanderArmory.AtBank(), "F: BANKFRAME_CLOSED leaves the bank")
OpenFlyout(5)
local awayChest = FlyoutList()
onslaught = EntryOf(awayChest, "Onslaught Breastplate")
CHECK(onslaught ~= nil,
    "F: away from the bank the item is STILL LISTED rather than silently dropped",
    Joined(FlyoutNames()))
CHECK(onslaught and onslaught.badge == "bank",
    "F: badged bank", onslaught and onslaught.badge)
CHECK(onslaught and onslaught.alpha and onslaught.alpha < 1,
    "F: and dimmed, because it cannot be clicked from here",
    onslaught and onslaught.alpha)
CHECK(awayChest[1] and awayChest[1].name == "Onslaught Breastplate",
    "F: a banked item still sorts by item level like everything else")

ClearPrintLog()
onslaught.row.__scripts.OnClick(onslaught.row)
CHECK(PrintedMatching("open a banker") ~= nil,
    "F: clicking it says what to do rather than failing silently",
    printLog[#printLog])
CHECK(equipped[5] == 41005, "F: and nothing was equipped")

-- Show Banked Items off removes it from the list entirely.
CommanderArmoryDB.FlyoutShowBank = false
OpenFlyout(5)
CHECK(not Contains(FlyoutNames(), "Onslaught Breastplate"),
    "F: Show Banked Items off filters the bank rows out")
CommanderArmoryDB.FlyoutShowBank = true
CommanderArmoryUI.CloseFlyout()

-- ===========================================================================
-- G. Slot 18 wears three faces
-- ===========================================================================

OpenFlyout(18)
CHECK(_G.CommanderArmoryFlyout.title.__text == "RELIC",
    "G: with a relic slot the popout is titled RELIC",
    _G.CommanderArmoryFlyout.title.__text)
local relics = FlyoutNames()
CHECK(Contains(relics, "Libram of Fervour"), "G: and offers librams", Joined(relics))
CHECK(not Contains(relics, "Idol of the Wild"),
    "G: never a druid's idol -- the relic SUBCLASS is checked, not just the equip location")
CHECK(not Contains(relics, "Sunfire Bow"), "G: and never a bow")
CHECK(CommanderArmory.AmmoInfo() == nil,
    "G: a relic class has no ammo, so the ammo readout is empty")

relicSlot = false
ammoID = 41030
WorldChanged()
OpenFlyout(18)
CHECK(_G.CommanderArmoryFlyout.title.__text == "RANGED",
    "G: without a relic slot the same slot id is titled RANGED",
    _G.CommanderArmoryFlyout.title.__text)
local ranged = FlyoutNames()
CHECK(Contains(ranged, "Sunfire Bow"), "G: and offers ranged weapons", Joined(ranged))
CHECK(not Contains(ranged, "Libram of Fervour"), "G: and no longer offers librams")
local ammoItemID, ammoName, _, _, ammoCount = CommanderArmory.AmmoInfo()
CHECK(ammoItemID == 41030 and ammoName == "Sharp Arrow",
    "G: and the ammo slot now reads through GetInventoryItemID, not the link", ammoName)
CHECK(ammoCount == 800, "G: with its stack count", ammoCount)
relicSlot = true
ammoID = nil
WorldChanged()
CommanderArmoryUI.CloseFlyout()

-- ===========================================================================
-- H. The cursor and the item locks, directly
-- ===========================================================================
-- The runner below is only meaningful if these primitives behave, so they are
-- asserted on their own first.

CHECK(not CursorHasItem(), "H: the cursor starts empty")
PickupInventoryItem(13)
CHECK(CursorHasItem(), "H: picking up an equipped item puts it on the cursor")
CHECK(IsInventoryItemLocked(13), "H: and LOCKS the square it came from")
CHECK(equipped[13] == nil, "H: which is now empty")
ClearCursor()
CHECK(not CursorHasItem() and equipped[13] == 41013,
    "H: clearing the cursor returns the item where it came from")
CHECK(not IsInventoryItemLocked(13), "H: and releases the lock")

local bag, slot = BagSlotOf(41028)
C_Container.PickupContainerItem(bag, slot)
CHECK(CursorHasItem() and containers[bag].items[slot] == nil,
    "H: a bag pickup empties the square too")
CHECK(CursorCanGoInSlot(10), "H: gauntlets can go in the hands slot")
CHECK(not CursorCanGoInSlot(1), "H: and not in the head slot")
PickupInventoryItem(10)
CHECK(equipped[10] == 41028, "H: a completed pair really equips the item")
CHECK(containers[bag].items[slot] == 41007,
    "H: and the displaced item lands in the square the new one came from",
    containers[bag].items[slot])
CHECK(not CursorHasItem(), "H: leaving the cursor empty")

-- Put it back by hand so the fixture is where the rest of the file expects.
C_Container.PickupContainerItem(bag, slot)
PickupInventoryItem(10)
CHECK(equipped[10] == 41007 and containers[bag].items[slot] == 41028,
    "H: and the swap is symmetric")
WorldChanged()

-- ===========================================================================
-- I. One-slot swaps through the flyout, driven to completion
-- ===========================================================================

local arena = CaptureNarrow("Arena Kit", { "head", "finger1", "finger2" })
CHECK(arena ~= nil and ItemStates(arena) == 3,
    "I: a narrow capture records exactly the three slots it was told to",
    arena and ItemStates(arena))
CHECK(arena.entries.head.state == "ITEM" and arena.entries.head.itemID == 41001,
    "I: with the item that is actually worn")
CHECK(arena.entries.chest.state == "IGNORED", "I: and everything else hands-off")
CHECK(arena.entries.shirt.state == "IGNORED",
    "I: cosmetics stay hands-off even when asked for the whole body")

local diff = CommanderArmory.Diff(arena)
CHECK(diff and diff.isEquipped, "I: a set captured from the body reads as worn")
CHECK(diff and diff.ignored >= 16, "I: and counts what it leaves alone", diff and diff.ignored)

-- Change the head through the popout.
OpenFlyout(1)
local vanguardRow = FlyoutList()[1].row
ClearPrintLog()
vanguardRow.__scripts.OnClick(vanguardRow)
DriveRun(3)
CHECK(equipped[1] == 41020, "I: clicking a popout row equips that item", equipped[1])
CHECK(BagSlotOf(41001) ~= nil, "I: and the helm it displaced is in a bag")
CHECK(CommanderArmory.RunState().status == "DONE",
    "I: the one-action run reported DONE", CommanderArmory.RunState().status)

-- Swap the two rings through the popout: this must be one SWAP_EQUIPPED, not
-- two trips through a bag.
OpenFlyout(11)
local signetRow = EntryOf(FlyoutList(), "Signet of Vigor").row
signetRow.__scripts.OnClick(signetRow)
DriveRun(3)
CHECK(equipped[11] == 41012, "I: the ring from the other finger moved across", equipped[11])
CHECK(equipped[12] == 41011, "I: and the one it replaced went the other way, not into a bag",
    equipped[12])
CHECK(BagSlotOf(41011) == nil, "I: neither ring ever passed through the bags")

CommanderArmoryUI.Refresh()
CHECK(CommanderArmory.Diff(arena).isEquipped == false,
    "I: the set now differs from the body")

-- ===========================================================================
-- J. A whole set equip, end to end
-- ===========================================================================

ClearPrintLog()
local started = CommanderArmory.EquipSet(arena)
CHECK(started == true, "J: the set pre-flighted clean and started")
CHECK(PrintedMatching("equipping \"Arena Kit\"") ~= nil,
    "J: and announced how many moves it would make", printLog[1])
CHECK(CommanderArmory.RunState().total >= 2,
    "J: three changed slots collapse into at least two moves",
    CommanderArmory.RunState().total)
CommanderArmoryUI.Refresh()
CHECK(Strip(_G.CommanderArmoryPane.progressText.__text):find("Equipping"),
    "J: the pane shows live progress while it runs",
    _G.CommanderArmoryPane.progressText.__text)

DriveRun(5)
CHECK(CommanderArmory.RunState().status == "DONE",
    "J: the runner drove the whole plan to completion",
    CommanderArmory.RunState().status)
CHECK(CommanderArmory.RunState().failed == 0, "J: with nothing failed",
    CommanderArmory.RunState().failed)
CHECK(equipped[1] == 41001, "J: the head is back to what the set asked for", equipped[1])
CHECK(equipped[11] == 41011, "J: as is ring 1", equipped[11])
CHECK(equipped[12] == 41012, "J: as is ring 2", equipped[12])
CommanderArmoryUI.Refresh()
CHECK(CommanderArmory.Diff(arena).isEquipped == true,
    "J: and the engine agrees the set is now worn")
CHECK(not CursorHasItem(), "J: the cursor is empty afterwards -- nothing was stranded")
CHECK(#restrictedCalls == 0, "J: no restricted call was made in combat", restrictedCalls[1])
CHECK(PrintedMatching("Arena Kit\" equipped") ~= nil,
    "J: and it said so when it finished", printLog[#printLog])

-- Equipping a set you are already wearing must move nothing, say so, and NOT
-- be reported as a failure. The engine is explicit about this: it returns
-- ok = false with verdict = "OK" and a NOTHING_TO_DO reason, and its own
-- comment says the two answer different questions.
ClearPrintLog()
local again = CommanderArmory.EquipSet(arena)
CHECK(again == false, "J: equipping a worn set starts no run")
CHECK(PrintedMatching("already") ~= nil,
    "J: and says the set is already on", printLog[#printLog])
CHECK(PrintedMatching("cannot be equipped") == nil,
    "J: without calling it a refusal -- verdict is OK, only ok is false",
    PrintedMatching("cannot be equipped"))
CHECK(CommanderArmory.RunState().status ~= "BLOCKED",
    "J: and without leaving the run state BLOCKED",
    CommanderArmory.RunState().status)

-- ===========================================================================
-- K. Ignore: the case retail gets right
-- ===========================================================================
-- A fully-equipped set is not a saved set: its hands-off flags can differ while
-- every item matches, and Save has to come back to life for exactly that.

CommanderArmoryUI.Refresh()
local pane = _G.CommanderArmoryPane
CHECK(pane.saveBtn.disabledReason ~= nil,
    "K: Save is disabled while a worn set has nothing to record")
CHECK(Strip(pane.status.__text):find("Saved"),
    "K: and the pane says so in words rather than only greying a button",
    pane.status.__text)

CommanderArmory.ToggleIgnore("head")
CommanderArmoryUI.Refresh()
CHECK(pane.saveBtn.disabledReason == nil,
    "K: toggling a hands-off flag re-enables Save even though the set is fully equipped")
CHECK(Strip(pane.status.__text):find("hands%-off flags changed"),
    "K: and names the reason", pane.status.__text)
CHECK(CommanderArmory.SelectionDirty() == true,
    "K: the host reports the selection dirty too")
CHECK(_G.CommanderArmorySlot1.ignoreMark:IsShown(),
    "K: the head cell wears the ignore overlay")
CHECK(_G.CommanderArmoryIgnoreMark1:IsShown(),
    "K: and so does the paperdoll slot, without opening the editor")

CommanderArmory.ToggleIgnore("head")
CommanderArmoryUI.Refresh()
CHECK(pane.saveBtn.disabledReason ~= nil,
    "K: toggling it back disables Save again")
CHECK(not _G.CommanderArmorySlot1.ignoreMark:IsShown(),
    "K: and clears the overlay")

-- The toggle lives in the popout, where it has always lived.
OpenFlyout(1)
CHECK(_G.CommanderArmoryFlyoutIgnore:IsShown(),
    "K: the popout carries the hands-off toggle while a set is selected")
CHECK(_G.CommanderArmoryFlyoutIgnore.text.__text == "Ignore This Slot",
    "K: labelled for the direction it would move",
    _G.CommanderArmoryFlyoutIgnore.text.__text)
_G.CommanderArmoryFlyoutIgnore.__scripts.OnClick(_G.CommanderArmoryFlyoutIgnore)
CHECK(_G.CommanderArmoryFlyoutIgnore.text.__text == "Include This Slot",
    "K: clicking it flips the label", _G.CommanderArmoryFlyoutIgnore.text.__text)
CHECK(_G.CommanderArmoryFlyoutIgnore.markInclude:IsShown()
    and not _G.CommanderArmoryFlyoutIgnore.markIgnore:IsShown(),
    "K: and the drawn glyph with it")
_G.CommanderArmoryFlyoutIgnore.__scripts.OnClick(_G.CommanderArmoryFlyoutIgnore)
CHECK(_G.CommanderArmoryFlyoutIgnore.text.__text == "Ignore This Slot",
    "K: and back")
CHECK(_G.CommanderArmoryFlyoutPlaceInBags:IsShown(),
    "K: Place In Bags is offered because the slot has something in it")
CommanderArmoryUI.CloseFlyout()

-- Markers can be switched off without losing the arrows.
CommanderArmory.ToggleIgnore("head")
CommanderArmoryDB.ShowIgnoreMarkers = false
Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
CHECK(not _G.CommanderArmoryIgnoreMark1:IsShown(),
    "K: Ignore Markers off clears the paperdoll overlay")
CHECK(_G.CommanderArmoryPopout1:IsShown(), "K: and leaves the arrows alone")
CommanderArmoryDB.ShowIgnoreMarkers = true
Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
CommanderArmory.ToggleIgnore("head")
CommanderArmoryUI.Refresh()

-- ===========================================================================
-- L. Three slot states, three treatments, never conflated
-- ===========================================================================

-- The selected set is the narrow Arena Kit, so the neck is already hands-off
-- and the two fingers are not: three states on three cells, with no toggling
-- needed to arrange them.
lockedInv[11] = true
brokenSlots[12] = true
WorldChanged()

local ignoredCell = _G.CommanderArmorySlot2    -- neck: the set leaves it alone
local lockedCell = _G.CommanderArmorySlot11    -- ring 1: in flight
local brokenCell = _G.CommanderArmorySlot12    -- ring 2: at zero durability

CHECK(ignoredCell.ignoreMark:IsShown(), "L: ignored draws OUR overlay")
CHECK(ignoredCell.tex.__desat ~= true, "L: and is NOT desaturated -- that word means locked")
CHECK(lockedCell.tex.__desat == true, "L: locked desaturates", lockedCell.tex.__desat)
CHECK(not lockedCell.ignoreMark:IsShown(), "L: and wears no ignore overlay")
CHECK(brokenCell.tex.__color and brokenCell.tex.__color[1] == 0.90
    and brokenCell.tex.__color[2] == 0.00,
    "L: broken takes Blizzard's own 0.9/0/0 red",
    brokenCell.tex.__color and table.concat(brokenCell.tex.__color, ","))
CHECK(brokenCell.tex.__desat ~= true, "L: and is not desaturated either")
CHECK(lockedCell.tex.__color and lockedCell.tex.__color[1] == 1,
    "L: a locked item is not tinted red")

-- And the three say which they are, in words, on the tooltip.
lockedCell.__scripts.OnEnter(lockedCell)
CHECK(TooltipHas("In flight") ~= nil, "L: the locked tooltip says the item is in flight")
brokenCell.__scripts.OnEnter(brokenCell)
CHECK(TooltipHas("Broken") ~= nil, "L: the broken tooltip says it still equips")
ignoredCell.__scripts.OnEnter(ignoredCell)
CHECK(TooltipHas("Hands off") ~= nil, "L: the ignored tooltip says the slot is left alone")

lockedInv[11] = nil
brokenSlots[12] = nil
WorldChanged()

-- ===========================================================================
-- M. Pre-flight: missing and banked are DIFFERENT answers
-- ===========================================================================

local headKit = CaptureNarrow("Head Kit", { "head" })
local legsKit = CaptureNarrow("Legs Kit", { "legs" })
CHECK(headKit.entries.head.itemID == 41001, "M: the head kit wants the worn helm")
CHECK(legsKit.entries.legs.itemID == 41009, "M: the legs kit wants the worn legplates")

-- The helm leaves the world entirely.
equipped[1] = nil
WorldChanged()
local missingPlan = CommanderArmory.Preflight(headKit)
CHECK(missingPlan and missingPlan.ok == false, "M: a set with a vanished item refuses")
CHECK(missingPlan and #missingPlan.actions == 0,
    "M: with ZERO actions -- never half-apply a set",
    missingPlan and #missingPlan.actions)
local missingReason
for _, reason in ipairs(missingPlan.reasons or {}) do
    if reason.code == "MISSING" then missingReason = reason end
end
CHECK(missingReason ~= nil, "M: and the reason code is MISSING")
CHECK(missingReason and missingReason.itemName == "Lightbringer Faceguard",
    "M: naming the item the player has to go and find",
    missingReason and missingReason.itemName)

-- The legplates go into the bank while we are standing at it, then we walk away.
equipped[7] = nil
containers[-1].items[2] = 41009
Fire("BANKFRAME_OPENED")
Fire("BANKFRAME_CLOSED")
WorldChanged()

local bankPlan = CommanderArmory.Preflight(legsKit)
CHECK(bankPlan and bankPlan.ok == false, "M: a set whose item is in the bank also refuses")
CHECK(bankPlan and #bankPlan.actions == 0, "M: with zero actions")
local bankReason, wronglyMissing
for _, reason in ipairs(bankPlan.reasons or {}) do
    if reason.code == "IN_BANK" then bankReason = reason end
    if reason.code == "MISSING" then wronglyMissing = reason end
end
CHECK(bankReason ~= nil, "M: the reason code is IN_BANK")
CHECK(wronglyMissing == nil,
    "M: and NOT missing -- this is the distinction the whole module exists for")
CHECK(bankReason and bankReason.itemName == "Legplates of Light",
    "M: naming the banked item", bankReason and bankReason.itemName)

-- The two must read differently to a human, not merely carry different codes.
CommanderArmory.SelectSet(2)   -- Head Kit
CommanderArmoryUI.Refresh()
local missingText = Strip(_G.CommanderArmoryPane.preflight.__text)
CHECK(missingText:find("Lightbringer Faceguard is not in your bags or your bank"),
    "M: the pane says the missing item is nowhere", missingText)
CHECK(missingText:find("Nothing has been moved"),
    "M: and promises nothing has moved", missingText)
CHECK(_G.CommanderArmoryPane.equipBtn.disabledReason ~= nil,
    "M: Equip is disabled and carries the reason")
CHECK(Strip(_G.CommanderArmorySetRow2.summary.__text):find("1 missing"),
    "M: and the set list row counts the missing pieces",
    _G.CommanderArmorySetRow2.summary.__text)

CommanderArmory.SelectSet(3)   -- Legs Kit
CommanderArmoryUI.Refresh()
local bankText = Strip(_G.CommanderArmoryPane.preflight.__text)
CHECK(bankText:find("Legplates of Light is in your bank"),
    "M: the pane says the banked item is in the bank", bankText)
CHECK(not bankText:find("not in your bags"),
    "M: and never calls a banked item missing", bankText)

-- The same distinction has to survive into the chat listing.
ClearPrintLog()
CommanderArmory_ListSets()
CHECK(PrintedMatching("Head Kit.*missing") ~= nil,
    "M: /cgear list flags the missing set", PrintedMatching("Head Kit") or "")
CHECK(PrintedMatching("Legs Kit.*in your bank") ~= nil,
    "M: and says the other one is in your bank", PrintedMatching("Legs Kit") or "")

-- And the per-slot diff stripe distinguishes them on the grid.
CommanderArmoryUI.Refresh()
CHECK(_G.CommanderArmorySlot7.stripe:IsShown(), "M: the legs cell carries a diff stripe")
_G.CommanderArmorySlot7.__scripts.OnEnter(_G.CommanderArmorySlot7)
CHECK(TooltipHas("is in your bank") ~= nil,
    "M: and its tooltip says which bank the item is sitting in")

-- Restore the world.
equipped[1] = 41001
equipped[7] = 41009
containers[-1].items[2] = nil
Fire("BANKFRAME_OPENED")
Fire("BANKFRAME_CLOSED")
WorldChanged()

-- ===========================================================================
-- N. Combat: queue rather than fail, flush when it lifts
-- ===========================================================================

CommanderArmory.SelectSet(1)   -- Arena Kit
-- Make it dirty again with a real swap.
OpenFlyout(1)
local vanguard = FlyoutList()[1].row
vanguard.__scripts.OnClick(vanguard)
DriveRun(3)
CHECK(equipped[1] == 41020, "N: the head is off-set again", equipped[1])

combat = true
ClearPrintLog()
local queued, why = CommanderArmory.EquipSet(arena)
CHECK(queued == false and why == "QUEUED",
    "N: an armor swap in combat queues rather than erroring", tostring(why))
CHECK(CommanderArmory.IsQueued() == true, "N: and the queue says so")
CHECK(PrintedMatching("queued set \"Arena Kit\"") ~= nil,
    "N: announced, with the reason", printLog[1])
CHECK(PrintedMatching("in combat") ~= nil, "N: which is combat")
CHECK(equipped[1] == 41020, "N: nothing moved")
CHECK(#restrictedCalls == 0, "N: and no restricted client call was attempted",
    restrictedCalls[1])
CommanderArmoryUI.Refresh()
CHECK(Strip(_G.CommanderArmoryPane.progressText.__text):find("Queued"),
    "N: the pane shows the queued swap", _G.CommanderArmoryPane.progressText.__text)
CHECK(_G.CommanderArmoryPane.cancelBtn:IsShown(),
    "N: with the cancel affordance the queue is worthless without")

-- The ticker must not sneak the swap through while combat is still on.
DriveRun(2)
CHECK(equipped[1] == 41020, "N: the ticker does not drain the queue during combat")

combat = false
Fire("PLAYER_REGEN_ENABLED")
DriveRun(5)
CHECK(CommanderArmory.IsQueued() == false, "N: leaving combat drains the queue")
CHECK(equipped[1] == 41001, "N: and the queued set really goes on", equipped[1])
CHECK(#restrictedCalls == 0, "N: still with no restricted call in combat")

-- Cancelling a queued swap.
combat = true
OpenFlyout(1)
CommanderArmory.EquipSingle(1, nil)
CHECK(CommanderArmory.IsQueued() == true, "N: a single-slot request queues too")
ClearPrintLog()
CHECK(CommanderArmory.CancelQueue() == true, "N: and can be cancelled")
CHECK(PrintedMatching("cancelled the queued") ~= nil, "N: which says so")
CHECK(CommanderArmory.IsQueued() == false, "N: leaving the queue empty")
combat = false
CommanderArmoryUI.CloseFlyout()

-- With the queue switched off, a refusal has to be loud instead.
CommanderArmoryDB.CombatQueue = false
combat = true
OpenFlyout(1)
CommanderArmoryUI.CloseFlyout()
ClearPrintLog()
local refused, refusedWhy = CommanderArmory.EquipSet(headKit)
CHECK(refused == false and refusedWhy == "IN_COMBAT",
    "N: Combat Queue off refuses instead of queueing", tostring(refusedWhy))
CHECK(PrintedMatching("while in combat") ~= nil, "N: and says why", printLog[1])
combat = false
CommanderArmoryDB.CombatQueue = true

-- A merchant window is a hard refusal: a swap with one open can sell gear.
merchantOpen = true
Fire("MERCHANT_SHOW")
ClearPrintLog()
local vendor = CommanderArmory.EquipSet(arena)
CHECK(vendor == false, "N: a swap is refused while a vendor window is open")
CHECK(PrintedMatching("vendor window is open") ~= nil, "N: and says so", printLog[1])
merchantOpen = false
Fire("MERCHANT_CLOSED")

-- ===========================================================================
-- O. The secure channel
-- ===========================================================================

local weapons = CaptureNarrow("Weapon Kit", { "mainhand", "offhand" })
CommanderArmoryUI.Refresh()
local macro = _G.CommanderArmoryEquipWeapons:GetAttribute("macrotext")
CHECK(type(macro) == "string" and macro:find("/equipslot %[combat%] 16 Blade of the Dawn"),
    "O: the secure button carries an /equipslot line for the main hand", macro)
CHECK(macro:find("/equipslot %[combat%] 17 Aegis of the Sun"),
    "O: and one for the off-hand", macro)
CHECK(_G.CommanderArmoryEquipWeapons:GetAttribute("type") == "macro",
    "O: as a macro attribute, since nothing scripted works in combat")
CHECK(_G.CommanderArmorySecureHost ~= nil
    and _G.CommanderArmorySecureHost:GetParent() == UIParent,
    "O: the secure container is a SIBLING parented to UIParent, never a child of ours")

combat = true
ClearPrintLog()
CommanderArmory.EquipSet(weapons)
CHECK(PrintedMatching("weapons only") ~= nil,
    "O: a weapons-only set queued in combat points at the keybind that can do it now",
    printLog[#printLog])
combat = false
CommanderArmory.CancelQueue()

CommanderArmory.SelectSet(1)
CommanderArmoryUI.Refresh()
local armorMacro = _G.CommanderArmoryEquipWeapons:GetAttribute("macrotext")
CHECK(armorMacro == "",
    "O: a set that ignores the weapons compiles an EMPTY macro rather than a stale one",
    armorMacro)

-- ===========================================================================
-- P. Stats, tooltips and the set list
-- ===========================================================================

CommanderArmoryUI.Refresh()
CHECK(_G.CommanderArmorySetRow1 ~= nil, "P: the set list rows are named")
CHECK(_G.CommanderArmorySetRow1.name.__text == "Arena Kit",
    "P: and the first row is the first set", _G.CommanderArmorySetRow1.name.__text)
CHECK(Strip(_G.CommanderArmorySetRow1.summary.__text):find("ignores %d+"),
    "P: each row summarises what the set leaves alone",
    _G.CommanderArmorySetRow1.summary.__text)
CHECK(_G.CommanderArmorySetRow1.check:IsShown(),
    "P: a worn set gets the tick")
CHECK(Strip(_G.CommanderArmorySetRow2.summary.__text):find("worn"),
    "P: and a repaired one loses its missing count",
    _G.CommanderArmorySetRow2.summary.__text)
CHECK(_G.CommanderArmorySetRow1.sel:IsShown(), "P: the selected row is highlighted")

CHECK(Strip(_G.CommanderArmoryPane.statsBody.__text):find("Item level"),
    "P: the stats panel totals the set's item level",
    _G.CommanderArmoryPane.statsBody.__text)
CHECK(Strip(_G.CommanderArmoryPane.detail.__text):find("free bag slot"),
    "P: and the detail line reports the free bag slots",
    _G.CommanderArmoryPane.detail.__text)

-- The tooltip line: the cheapest place to stop somebody vendoring a set piece.
tooltipItemLink = Link(41001)
GameTooltip:SetOwner(UIParent)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(TooltipHas("Armory: ") ~= nil, "P: an item a set wants gets a tooltip line",
    GameTooltip.__lines[1])
CHECK(TooltipHas("Arena Kit") ~= nil, "P: naming the set")
local linesAfterFirst = #GameTooltip.__lines
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(#GameTooltip.__lines == linesAfterFirst,
    "P: and a second OnTooltipSetItem for the same item does not stack a duplicate",
    #GameTooltip.__lines)

tooltipItemLink = Link(41031)
GameTooltip:SetOwner(UIParent)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(TooltipHas("Armory: ") == nil, "P: an item no set wants gets no line")
tooltipItemLink = nil

-- ===========================================================================
-- Q. Slash commands
-- ===========================================================================

local slash = SlashCmdList["COMMANDERUI_ARMORY"]

CharacterFrameTab_OnClick(_G.CharacterFrameTab1)
slash("")
CHECK(_G.CommanderArmoryFrame:IsShown(), "Q: the bare command opens the Armory")
slash("")
CHECK(not _G.CommanderArmoryFrame:IsShown(), "Q: and closes it")
slash("")

ClearPrintLog()
slash("list")
CHECK(PrintedMatching("set[s]? on this character") ~= nil, "Q: list prints the sets", printLog[1])
CHECK(PrintedMatching("Arena Kit") ~= nil, "Q: naming each one")

ClearPrintLog()
slash("equip")
CHECK(PrintedMatching("usage: /cgear equip") ~= nil,
    "Q: a bare equip prints the usage line", printLog[1])

-- Set-name lookup must be case-insensitive: the framework lowercases the
-- argument before it ever reaches us.
OpenFlyout(1)
local vg = FlyoutList()[1].row
vg.__scripts.OnClick(vg)
DriveRun(3)
CHECK(equipped[1] == 41020, "Q: off-set again, ready for the command")
ClearPrintLog()
slash("equip arena kit")
DriveRun(5)
CHECK(equipped[1] == 41001,
    "Q: /cgear equip <name> matches a set name regardless of case", equipped[1])

ClearPrintLog()
slash("equip weapon")
CHECK(PrintedMatching("Weapon Kit") ~= nil or PrintedMatching("already on") ~= nil,
    "Q: a prefix finds the set too", printLog[1])

ClearPrintLog()
slash("equip nothing at all")
CHECK(PrintedMatching("no set called") ~= nil,
    "Q: an unknown set name says so and lists nothing", printLog[1])

ClearPrintLog()
slash("banana")
CHECK(PrintedMatching("Usage: /cgear") ~= nil,
    "Q: an unknown subcommand prints the usage line", printLog[1])
CHECK(PrintedMatching("wipe") ~= nil, "Q: which enumerates the real subcommands")

-- /cgear save has to record what you are wearing. This is the point of the
-- command; a set that ignores every slot is not a saved kit.
ClearPrintLog()
slash("save duty kit")
local duty = CommanderArmory.FindSet("duty kit")
CHECK(duty ~= nil, "Q: /cgear save creates a set")
CHECK(duty and ItemStates(duty) > 0,
    "Q: and records the gear you are wearing in it",
    duty and ItemStates(duty))

-- ===========================================================================
-- R. New / Rename / Delete through the pane
-- ===========================================================================

CommanderArmoryUI.Refresh()
local setsBefore = #CommanderArmory.Sets()
_G.CommanderArmoryPane.newBtn.__scripts.OnClick(_G.CommanderArmoryPane.newBtn)
CHECK(_G.CommanderArmoryNameDialog ~= nil and _G.CommanderArmoryNameDialog:IsShown(),
    "R: New opens the name dialog")
CHECK(_G.CommanderArmoryIconButton1 ~= nil and _G.CommanderArmoryIconButton1:IsShown(),
    "R: with an icon grid, from the fallback list when the client has no macro icon API")
_G.CommanderArmorySetNameBox:SetText("Freshly Made")
_G.CommanderArmoryNameAccept.__scripts.OnClick(_G.CommanderArmoryNameAccept)
CHECK(#CommanderArmory.Sets() == setsBefore + 1,
    "R: accepting the New dialog stores the set",
    #CommanderArmory.Sets() .. " sets, was " .. setsBefore)
CHECK(CommanderArmory.FindSet("freshly made") ~= nil,
    "R: and it can be found by name afterwards")

CommanderArmory.SelectSet(1)
CommanderArmoryUI.Refresh()
_G.CommanderArmoryPane.renameBtn.__scripts.OnClick(_G.CommanderArmoryPane.renameBtn)
CHECK(_G.CommanderArmorySetNameBox:GetText() == "Arena Kit",
    "R: Rename opens with the current name filled in",
    _G.CommanderArmorySetNameBox:GetText())
_G.CommanderArmorySetNameBox:SetText("Arena 2v2")
_G.CommanderArmoryNameAccept.__scripts.OnClick(_G.CommanderArmoryNameAccept)
CHECK(CommanderArmory.Sets()[1].name == "Arena 2v2",
    "R: and renames in place", CommanderArmory.Sets()[1].name)
CHECK(CommanderArmory.FindSet("arena 2v2") ~= nil, "R: findable under the new name")

ClearPrintLog()
_G.CommanderArmoryPane.deleteBtn.__scripts.OnClick(_G.CommanderArmoryPane.deleteBtn)
CHECK(LastPopup() and LastPopup().which == "COMMANDER_ARMORY_DELETE_SET",
    "R: Delete asks first")
CHECK(CommanderArmory.FindSet("arena 2v2") ~= nil, "R: and has deleted nothing yet")
StaticPopupDialogs["COMMANDER_ARMORY_DELETE_SET"].OnAccept()
CHECK(CommanderArmory.FindSet("arena 2v2") == nil, "R: confirming removes it")
CHECK(PrintedMatching("deleted \"Arena 2v2\"") ~= nil, "R: and says so", printLog[#printLog])

-- ===========================================================================
-- S. Restore Defaults, and the wipe
-- ===========================================================================

CommanderArmoryDB.FlyoutMinQuality = 3
CommanderArmoryDB.AccentColor = "NOPE"
Commander.Notify(COMMANDER_ARMORY_EVENTS.UPDATE)
CHECK(CommanderArmory.THEME.accent[1] == 1.0 and CommanderArmory.THEME.accent[2] == 0.72,
    "S: an accent key nobody publishes falls back to amber rather than going blank",
    table.concat(CommanderArmory.THEME.accent, ","))

local setCountBeforeReset = #CommanderArmory.Sets()
CHECK(setCountBeforeReset > 0, "S: there are sets to protect", setCountBeforeReset)
ClearPrintLog()
slash("reset")
CHECK(CommanderArmoryDB.FlyoutMinQuality == 0, "S: Restore Defaults restores a changed option",
    CommanderArmoryDB.FlyoutMinQuality)
CHECK(CommanderArmoryDB.AccentColor == "AMBER", "S: including the accent",
    CommanderArmoryDB.AccentColor)
CHECK(CommanderArmoryDB.DBVersion == 1,
    "S: and does NOT un-migrate the database", CommanderArmoryDB.DBVersion)
CHECK(#CommanderArmory.Sets() == setCountBeforeReset,
    "S: and leaves every saved set exactly where it was",
    #CommanderArmory.Sets())
CHECK(PrintedMatching("your sets are untouched") ~= nil,
    "S: and says so out loud", printLog[1])

local store = CommanderArmory_CharStore()
store.hidden["41020:0:0:0:0:0:0"] = true
CHECK(#store.bank.items > 0, "S: the bank cache has something in it to lose",
    #store.bank.items)

ClearPrintLog()
slash("wipe")
CHECK(LastPopup() and LastPopup().which == "COMMANDER_ARMORY_WIPE",
    "S: wipe asks before deleting anything")
CHECK(#CommanderArmory.Sets() > 0, "S: and has deleted nothing yet")
StaticPopupDialogs["COMMANDER_ARMORY_WIPE"].OnAccept()
CHECK(#CommanderArmory.Sets() == 0, "S: confirming deletes every set")
CHECK(PrintedMatching("deleted") ~= nil, "S: and says so")
CHECK(#store.bank.items == 0,
    "S: the bank cache goes with them, as the dialog promised", #store.bank.items)
CHECK(next(store.hidden) == nil,
    "S: as does the hidden-item list, as the dialog promised")

-- The module has to keep working on the other side of a wipe.
CommanderArmoryUI.Refresh()
CHECK(Strip(_G.CommanderArmoryPane.status.__text):find("No set selected"),
    "S: the pane recovers to the empty state",
    _G.CommanderArmoryPane.status.__text)
OpenFlyout(1)
CHECK(#FlyoutList() >= 1, "S: and the popout still lists candidates with no sets at all")
CHECK(not _G.CommanderArmoryFlyoutIgnore:IsShown(),
    "S: with no hands-off toggle, because ignoring a slot is a statement about a set")
CommanderArmoryUI.CloseFlyout()

-- ===========================================================================
-- U. A naked new set, and authoring one from the pane
-- ===========================================================================
-- The wipe above left this character with no sets at all, which is exactly the
-- state a new one is made from. Everything here reads the STORE and the FIXTURE
-- rather than the confirmation messages: the whole point of the change is that
-- New no longer quietly records what you have on, and only the entries can say
-- whether it did.

CommanderArmoryUI.Refresh()
ClearPrintLog()
_G.CommanderArmoryPane.newBtn.__scripts.OnClick(_G.CommanderArmoryPane.newBtn)
_G.CommanderArmorySetNameBox:SetText("Naked Kit")
_G.CommanderArmoryNameAccept.__scripts.OnClick(_G.CommanderArmoryNameAccept)

local naked = CommanderArmory.FindSet("naked kit")
CHECK(naked ~= nil, "U: New stores the set")
CHECK(CommanderArmory.SelectedSet() == naked, "U: and selects it")
CHECK(ItemStates(naked) == 0,
    "U: and does NOT capture the gear you are wearing into it", ItemStates(naked))

do
    local total, empty, ignored = 0, 0, 0
    for _, entry in pairs(naked.entries) do
        total = total + 1
        if entry.state == "EMPTY" then empty = empty + 1
        elseif entry.state == "IGNORED" then ignored = ignored + 1 end
    end
    CHECK(total == #D.Slots, "U: a new set has one entry per canon slot", total)
    CHECK(empty == #D.Slots - 2, "U: seventeen of them EMPTY — it strips, it does not idle", empty)
    CHECK(ignored == 2, "U: and exactly two IGNORED", ignored)
    CHECK(naked.entries.shirt.state == "IGNORED" and naked.entries.tabard.state == "IGNORED",
        "U: which are the shirt and the tabard, nobody's guild tabard being a stat piece")

    -- The scratchpad is loaded from those entries, and it is what Save reads
    -- back. A new set whose scratch said "everything ignored" is precisely the
    -- bug that made /cgear save <newname> produce a set that did nothing.
    local scratch, n = CommanderArmory.IgnoreScratch(), 0
    for _ in pairs(scratch) do n = n + 1 end
    CHECK(n == 2 and scratch.shirt and scratch.tabard,
        "U: the ignore scratchpad reflects shirt and tabard, and nothing else", n)
end

-- The header names it, and the grid says what the set will do to each slot.
CHECK(Strip(_G.CommanderArmoryPaneName.text.__text) == "Naked Kit",
    "U: the pane header names the selected set",
    _G.CommanderArmoryPaneName.text.__text)

-- --- Authoring from the pane -----------------------------------------------
-- A click on the grid opens the same popout the paperdoll opens, and it means
-- something different: it writes the set and equips nothing.

local wornHeadBefore = equipped[1]
local wornBeforeAuthoring = {}
for slot = 1, 19 do wornBeforeAuthoring[slot] = equipped[slot] end
_G.CommanderArmorySlot1.__scripts.OnClick(_G.CommanderArmorySlot1)
CHECK(CommanderArmoryUI.FlyoutMode() == "AUTHOR",
    "U: the grid opens the popout in authoring mode", CommanderArmoryUI.FlyoutMode())
CHECK(_G.CommanderArmoryFlyout.mode == "AUTHOR", "U: and says so on the frame")
CHECK(_G.CommanderArmoryFlyout.modeText:IsShown()
    and Strip(_G.CommanderArmoryFlyout.modeText.__text):find("Naked Kit"),
    "U: with a header naming the set being edited",
    _G.CommanderArmoryFlyout.modeText.__text)
CHECK(_G.CommanderArmoryFlyoutLeaveBare:IsShown(),
    "U: the leave-bare row is offered while authoring")
CHECK(_G.CommanderArmoryFlyoutIgnore:IsShown(),
    "U: alongside the hands-off toggle, which is the same decision")

-- Row ORDER, not merely row presence: the two verbs that write the set come
-- first while authoring, and Place In Bags -- which acts on the body this
-- instant -- goes last so it cannot be mistaken for one of them.
local function SpecialY(widget)
    local points = widget.__points
    local last = points and points[#points]
    return last and last.y
end
CHECK(SpecialY(_G.CommanderArmoryFlyoutLeaveBare) > SpecialY(_G.CommanderArmoryFlyoutIgnore)
    and SpecialY(_G.CommanderArmoryFlyoutIgnore) > SpecialY(_G.CommanderArmoryFlyoutPlaceInBags),
    "U: leave-bare, then hands-off, then Place In Bags last",
    SpecialY(_G.CommanderArmoryFlyoutLeaveBare) .. "/"
        .. SpecialY(_G.CommanderArmoryFlyoutIgnore) .. "/"
        .. SpecialY(_G.CommanderArmoryFlyoutPlaceInBags))

do
    local target = EntryOf(FlyoutList(), "Battleworn Helm")
    CHECK(target ~= nil, "U: the popout lists the helm to author", Joined(FlyoutNames()))
    target.row.__scripts.OnClick(target.row)
end

CHECK(naked.entries.head.state == "ITEM",
    "U: clicking a candidate writes it into the set", naked.entries.head.state)
CHECK(naked.entries.head.itemID == 41021,
    "U: naming the item that was clicked", naked.entries.head.itemID)
CHECK(naked.entries.head.baseKey ~= nil,
    "U: an authored entry carries baseKey — without it loose matching dies silently",
    tostring(naked.entries.head.baseKey))
CHECK(naked.entries.head.name == "Battleworn Helm" and naked.entries.head.icon ~= nil,
    "U: and the name and icon a set needs to draw itself")
CHECK(equipped[1] == wornHeadBefore,
    "U: and equips absolutely nothing", tostring(equipped[1]))
do
    -- Not one square of the body moved. The fixture's pickups really relocate
    -- items, so this is the difference between "no run was started" and "the
    -- run did nothing", and only the second is worth asserting.
    local moved = nil
    for slot = 1, 19 do
        if equipped[slot] ~= wornBeforeAuthoring[slot] then moved = slot end
    end
    CHECK(moved == nil, "U: nothing anywhere on the body changed", moved)
end
CHECK(CommanderArmory.SelectionDirty() == true,
    "U: and the set now differs from what is on the body")

-- Authoring a slot that was hands-off includes it again, otherwise the very
-- next Save would write IGNORED straight back over the entry.
CommanderArmory.ToggleIgnore("hands")
CHECK(CommanderArmory.IgnoreScratch().hands == true, "U: the hands are hands-off to begin with")
_G.CommanderArmorySlot10.__scripts.OnClick(_G.CommanderArmorySlot10)
do
    local rows = FlyoutList()
    CHECK(rows[1] ~= nil, "U: with something to author into them", Joined(FlyoutNames()))
    if rows[1] then rows[1].row.__scripts.OnClick(rows[1].row) end
end
CHECK(naked.entries.hands.state == "ITEM",
    "U: authoring an ignored slot writes the item", naked.entries.hands.state)
CHECK(CommanderArmory.IgnoreScratch().hands == nil,
    "U: and takes the hands-off flag off with it")

-- --- Leave this slot bare ---------------------------------------------------
_G.CommanderArmorySlot3.__scripts.OnClick(_G.CommanderArmorySlot3)
_G.CommanderArmoryFlyoutLeaveBare.__scripts.OnClick(_G.CommanderArmoryFlyoutLeaveBare)
CHECK(naked.entries.shoulder ~= nil and naked.entries.shoulder.state == "EMPTY",
    "U: leave-bare writes EMPTY as a real entry, never a deleted one",
    naked.entries.shoulder and naked.entries.shoulder.state)
CHECK(equipped[3] ~= nil, "U: and takes nothing off right now", tostring(equipped[3]))

-- --- The same popout, opened from the paperdoll, still WEARS -----------------
CommanderArmoryUI.CloseFlyout()
_G.CommanderArmoryPopout1.__scripts.OnClick(_G.CommanderArmoryPopout1)
CHECK(CommanderArmoryUI.FlyoutMode() == "WEAR",
    "U: the paperdoll arrow opens the same list in wear mode, set selected or not",
    CommanderArmoryUI.FlyoutMode())
CHECK(not _G.CommanderArmoryFlyoutLeaveBare:IsShown(),
    "U: with no leave-bare row, because wearing is not authoring")
CHECK(SpecialY(_G.CommanderArmoryFlyoutPlaceInBags) > SpecialY(_G.CommanderArmoryFlyoutIgnore),
    "U: and Blizzard's own row order back, Place In Bags before the hands-off toggle")

do
    local target = EntryOf(FlyoutList(), "Helm of the Vanguard")
    CHECK(target ~= nil, "U: the wear list still offers the upgrade", Joined(FlyoutNames()))
    target.row.__scripts.OnClick(target.row)
end
DriveRun(6)
CHECK(equipped[1] == 41020, "U: and a click there really equips it", tostring(equipped[1]))
CHECK(naked.entries.head.itemID == 41021,
    "U: while leaving the authored set entry alone", naked.entries.head.itemID)

-- --- The pane with nothing selected has nothing to author --------------------
CommanderArmoryUI.CloseFlyout()
CommanderArmory.SelectSet(0)
CommanderArmoryUI.Refresh()
CHECK(Strip(_G.CommanderArmoryPaneName.text.__text):find("No set selected"),
    "U: the header says so when nothing is selected",
    _G.CommanderArmoryPaneName.text.__text)
_G.CommanderArmorySlot1.__scripts.OnClick(_G.CommanderArmorySlot1)
CHECK(CommanderArmoryUI.FlyoutMode() == "WEAR",
    "U: and the grid falls back to wearing, since there is no set to write to",
    CommanderArmoryUI.FlyoutMode())
CommanderArmoryUI.CloseFlyout()
CommanderArmory.SelectSet(1)
CommanderArmoryUI.Refresh()

-- --- Shift-click authors nothing and wears instead ---------------------------
shiftDown = true
_G.CommanderArmorySlot1.__scripts.OnClick(_G.CommanderArmorySlot1)
CHECK(CommanderArmoryUI.FlyoutMode() == "AUTHOR", "U: the pane is still authoring")
do
    local target = EntryOf(FlyoutList(), "Lightbringer Faceguard")
    CHECK(target ~= nil, "U: the old helm is back in the list", Joined(FlyoutNames()))
    target.row.__scripts.OnClick(target.row)
end
shiftDown = false
DriveRun(6)
CHECK(equipped[1] == 41001,
    "U: shift-click in the pane wears it now instead of writing it", tostring(equipped[1]))
CHECK(naked.entries.head.itemID == 41021,
    "U: and does not touch the set", naked.entries.head.itemID)

-- --- Renaming in the header --------------------------------------------------
CommanderArmoryUI.CloseFlyout()
CommanderArmoryUI.Refresh()
_G.CommanderArmoryPaneName.__scripts.OnClick(_G.CommanderArmoryPaneName)
CHECK(_G.CommanderArmoryPaneNameEdit:IsShown(), "U: clicking the name opens an edit box in place")
CHECK(not _G.CommanderArmoryPaneName:IsShown(), "U: and the label steps out of the way")
CHECK(_G.CommanderArmoryPaneNameEdit:GetText() == "Naked Kit",
    "U: pre-filled with the current name", _G.CommanderArmoryPaneNameEdit:GetText())

_G.CommanderArmoryPaneNameEdit:SetText("Stripped Down")
_G.CommanderArmoryPaneNameEdit.__scripts.OnEnterPressed(_G.CommanderArmoryPaneNameEdit)
CHECK(naked.name == "Stripped Down", "U: Enter commits the rename", naked.name)
CHECK(not _G.CommanderArmoryPaneNameEdit:IsShown(), "U: and closes the box")
CHECK(Strip(_G.CommanderArmoryPaneName.text.__text) == "Stripped Down",
    "U: the header repaints with the new name", _G.CommanderArmoryPaneName.text.__text)
CHECK(CommanderArmory.FindSet("stripped down") ~= nil, "U: findable under it too")

ClearPrintLog()
_G.CommanderArmoryPaneName.__scripts.OnClick(_G.CommanderArmoryPaneName)
_G.CommanderArmoryPaneNameEdit:SetText("   ")
_G.CommanderArmoryPaneNameEdit.__scripts.OnEnterPressed(_G.CommanderArmoryPaneNameEdit)
CHECK(naked.name == "Stripped Down", "U: an empty name is refused, not silently accepted", naked.name)
CHECK(PrintedMatching("a set needs a name") ~= nil,
    "U: and says why rather than doing nothing", printLog[1])
CHECK(_G.CommanderArmoryPaneNameEdit:IsShown(),
    "U: leaving the box open with what was typed still in it")

slash("save Second Kit")
CommanderArmory.SelectSet(1)
CommanderArmoryUI.Refresh()
ClearPrintLog()
_G.CommanderArmoryPaneName.__scripts.OnClick(_G.CommanderArmoryPaneName)
_G.CommanderArmoryPaneNameEdit:SetText("second kit")
_G.CommanderArmoryPaneNameEdit.__scripts.OnEnterPressed(_G.CommanderArmoryPaneNameEdit)
CHECK(CommanderArmory.Sets()[1].name == "Stripped Down",
    "U: a duplicate name is refused, case and all", CommanderArmory.Sets()[1].name)
CHECK(PrintedMatching("already have a set called") ~= nil,
    "U: naming the set that already has it", printLog[1])

_G.CommanderArmoryPaneNameEdit:SetText("Escaped")
_G.CommanderArmoryPaneNameEdit.__scripts.OnEscapePressed(_G.CommanderArmoryPaneNameEdit)
CHECK(CommanderArmory.Sets()[1].name == "Stripped Down", "U: Escape abandons the edit")
CHECK(not _G.CommanderArmoryPaneNameEdit:IsShown(), "U: and closes the box")
CHECK(_G.CommanderArmoryPaneName:IsShown(), "U: putting the label back")

-- --- The tooltip answers BOTH ways ------------------------------------------
-- Silence is not an answer: "no set wants this" has to be distinguishable from
-- the feature being off, and the gates are what stop that becoming spam.
tooltipItemLink = Link(41021)
GameTooltip:SetOwner(UIParent)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(TooltipHas("Armory: ") ~= nil and TooltipHas("Stripped Down") ~= nil,
    "U: an item a set names gets the positive line, naming the set",
    GameTooltip.__lines[#GameTooltip.__lines])

tooltipItemLink = Link(41029)          -- Ring of Woe: equippable, in no set
GameTooltip:SetOwner(UIParent)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(TooltipHas("not in any set") ~= nil,
    "U: an equippable item no set names says so out loud",
    GameTooltip.__lines[#GameTooltip.__lines])

tooltipItemLink = Link(41031)          -- Healing Potion: not equippable at all
GameTooltip:SetOwner(UIParent)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(TooltipHas("Armory") == nil,
    "U: a potion gets no Armory line at all — the gate that stops this being spam",
    GameTooltip.__lines[1])

tooltipItemLink = Link(41030)          -- Sharp Arrow: slot 0 is outside the model
GameTooltip:SetOwner(UIParent)
GameTooltip.__scripts.OnTooltipSetItem(GameTooltip)
CHECK(TooltipHas("Armory") == nil,
    "U: and neither does ammo, which no set can ever speak for (D4)",
    GameTooltip.__lines[1])
tooltipItemLink = nil

-- --- Equipping a fresh naked set STRIPS, rather than doing nothing -----------
-- The old empty set read as nineteen ignored slots and was a no-op forever.
local stripper = CommanderArmory.NewSet("Strip Test")
CommanderArmoryUI.Refresh()
do
    local snap = CommanderArmory.Snapshot()
    local wornCount = 0
    for _, slot in ipairs(D.Slots) do
        if not slot.cosmetic and snap.equipped[slot.id] then wornCount = wornCount + 1 end
    end
    CHECK(wornCount > 0, "U: there is gear on to strip", wornCount)

    local plan = CommanderArmory.Preflight(stripper)
    CHECK(plan and plan.ok == true, "U: a fresh naked set is a plan that runs",
        plan and plan.verdict)
    CHECK(plan and #plan.actions == wornCount,
        "U: with one action per worn slot rather than none at all",
        plan and #plan.actions)
    local removals = 0
    for _, action in ipairs((plan and plan.actions) or {}) do
        if action.op == "MOVE_TO_BAG" then removals = removals + 1 end
    end
    CHECK(removals == wornCount, "U: and every one of them strips a slot to the bags", removals)

    CommanderArmory.EquipSet(stripper)
    DriveRun(30)
    CHECK(equipped[1] == nil and equipped[5] == nil and equipped[16] == nil,
        "U: running it really does take the gear off",
        tostring(equipped[1]) .. "/" .. tostring(equipped[5]) .. "/" .. tostring(equipped[16]))
end

-- ===========================================================================
-- T. Nothing accumulated
-- ===========================================================================

CHECK(#harnessFailedErrors == 0, "T: no errors accumulated across the whole run",
    harnessFailedErrors[1])
CHECK(#restrictedCalls == 0,
    "T: no restricted client function was ever called under InCombatLockdown",
    restrictedCalls[1])
CHECK(not CursorHasItem(), "T: and the cursor is empty at the end")

io.write(string.format("\n%s  %d checks, %d failures\n",
    fails == 0 and "PASS" or "FAIL", checks, fails))
os.exit(fails == 0 and 0 or 1)
