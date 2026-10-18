-- Commander Ladder harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus Commander_Ladder's files under a permissive WoW mock, and checks the
-- three calls Commander_Muster relies on (Lookup, Want, Generated), the
-- roster Commander_Recruit aims its sweep with (Roster, L9), the
-- missing-data-file case, the wanted list's caps, and the settings page.
--
-- Mock copied from Commander_Muster/Harness/muster_ui_harness.lua (its generic
-- half: path resolution, CHECK, widgets, timers).
--
-- Run:  /opt/homebrew/bin/luajit ladder_harness.lua

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
-- WoW mock
-- ===========================================================================

local now = 1000000
function time() return now end
function date(fmt, t) return os.date(fmt or "%c", t or now) end
function GetTime() return now - 999000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local harnessFailedErrors = {}
function geterrorhandler()
    return function(err)
        harnessFailedErrors[#harnessFailedErrors + 1] = tostring(err)
    end
end

-- Fonts: SetFont must reject garbage flags, per the client's hard-error trap
local VALID_FLAGS = { [""] = true, OUTLINE = true, THICKOUTLINE = true, MONOCHROME = true,
    ["OUTLINE, MONOCHROME"] = true }

local allFontStrings = {}
local frames = {}
local eventRegistry = {} -- event -> { frame, ... }

local NUMERIC_GETTERS = {
    GetWidth = 0, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1,
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
        local fn = function(s) local t = NewWidget("Texture"); t.__parent = s; return t end
        rawset(self, key, fn)
        return fn
    end
    if key == "CreateFontString" then
        local fn = function(s)
            local t = NewWidget("FontString")
            t.__parent = s
            allFontStrings[#allFontStrings + 1] = t
            return t
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetScript" or key == "HookScript" then
        local fn = function(s, name, handler) s.__scripts[name] = handler end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetScript" then
        local fn = function(s, name) return s.__scripts[name] end
        rawset(self, key, fn)
        return fn
    end
    if key == "RegisterEvent" then
        local fn = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
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
            s.__shown = true
            if s.__scripts.OnShow then s.__scripts.OnShow(s) end
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "Hide" then
        local fn = function(s) s.__shown = false end
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
    if key == "GetPoint" then
        local fn = function() return "CENTER", nil, "CENTER", 0, 0 end
        rawset(self, key, fn)
        return fn
    end
    if key == "GetThumbTexture" then
        local fn = function(s) return NewWidget("Texture") end
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
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
    end
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
GameTooltip.__lines = {}
GameTooltip.AddLine = function(s, text) s.__lines[#s.__lines + 1] = text end
GameTooltip.AddDoubleLine = function(s, left, right)
    s.__lines[#s.__lines + 1] = tostring(left) .. " = " .. tostring(right)
end
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
strsplit = function(sep, str) local out = {} for piece in string.gmatch(str, "([^" .. sep .. "]+)") do out[#out + 1] = piece end return unpack(out) end

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
NumberFontNormal = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2 }
function PlaySound() end
BACKDROP_SLIDER_8_8 = {}

-- Settings API
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
C_AddOns = { GetAddOnMetadata = function() return "2.1.0" end }

-- Timers
local timers, tickers = {}, {}
C_Timer = {
    After = function(delay, fn) timers[#timers + 1] = { at = now + delay, fn = fn } end,
    NewTicker = function(interval, fn)
        local t = { interval = interval, fn = fn }
        tickers[#tickers + 1] = t
        return t
    end,
}

local function RunTickers()
    for _, t in ipairs(tickers) do t.fn() end
end

-- Dropdown machinery
local menuCaptured = {}
local dropdownInits = {}
function UIDropDownMenu_Initialize(frame, fn, mode) dropdownInits[frame] = fn end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuCaptured[#menuCaptured + 1] = info end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue() end
function UIDropDownMenu_SetText() end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
function ToggleDropDownMenu(level, value, frame, anchor)
    menuCaptured = {}
    local init = dropdownInits[frame]
    if init then init(frame) end
end
SlashCmdList = {}
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    HUNTER = { r = 0.67, g = 0.83, b = 0.45 },
    MAGE = { r = 0.41, g = 0.80, b = 0.94 },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
function IsInRaid() return false end
local inCombat = false
function InCombatLockdown() return inCombat end

-- Advance the clock and fire every timer that came due, in order
local function Advance(seconds)
    now = now + seconds
    local again = true
    while again do
        again = false
        table.sort(timers, function(a, b) return a.at < b.at end)
        for i, t in ipairs(timers) do
            if t.at <= now then
                table.remove(timers, i)
                t.fn()
                again = true
                break
            end
        end
    end
end


-- ===========================================================================
-- Ladder-specific mock
-- ===========================================================================

function GetNormalizedRealmName() return "Dreamscythe" end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")

-- ===========================================================================
-- A. No data file: everything is nil and nothing breaks
-- ===========================================================================

CommanderLadderData = nil
Load(ADDONS .. "/Commander_Ladder/CommanderLadder.lua")
Load(ADDONS .. "/Commander_Ladder/CommanderLadderDB.lua")
Fire("ADDON_LOADED", "Commander_Ladder")
Fire("PLAYER_LOGIN")

CHECK(#harnessFailedErrors == 0, "login without a data file raised no errors", harnessFailedErrors[1])
CHECK(CommanderLadderDB.EnableLadder == true, "defaults applied")
CHECK(CommanderLadder.Lookup("Polypopin") == nil, "no data file: Lookup is nil")
CHECK(CommanderLadder.Generated() == nil, "no data file: Generated is nil")
CHECK(CommanderLadder.Count() == 0, "no data file: no players")
CHECK(CommanderLadder.Status():find("No feed yet"), "the status says how to get one", CommanderLadder.Status())

-- ===========================================================================
-- B. A data file, as ladder_feed.py writes it
-- ===========================================================================

-- Two realms with the same name is a coin toss: left unanswered (checked
-- first, on a file of its own, so the index is built from it)
CommanderLadderData = {
    generated = now, players = {
        ["Twin-Dreamscythe"] = { [2] = { 1500, 1, 1 }, t = now },
        ["Twin-Nightslayer"] = { [2] = { 1900, 1, 1 }, t = now },
        ["Solo-Nightslayer"] = { [3] = { 1700, 1, 1 }, t = now },
    },
}
CHECK(CommanderLadder.Lookup("Twin", nil, true) and CommanderLadder.Lookup("Twin", nil, true)[2][1] == 1500,
    "realm unknown, the name on ours and another: ours")
CHECK(CommanderLadder.Lookup("Solo", nil, true) and CommanderLadder.Lookup("Solo", nil, true)[3][1] == 1700,
    "realm unknown, the name on one other realm only: that one")
CommanderLadderData.players["Twin-Dreamscythe"] = nil
CommanderLadderData.players["Twin-LivingFlame"] = { [2] = { 1700, 1, 1 }, t = now }
CommanderLadderData.byBare = nil
CHECK(CommanderLadder.Lookup("Twin", nil, true) == nil
    and CommanderLadder.Lookup("Twin-Nightslayer") ~= nil,
    "...but two OTHER realms with it is not guessed")
CommanderLadderData.players["Twin-Dreamscythe"] = { [2] = { 1500, 1, 1 }, t = now }

CommanderLadderData = {
    generated = now - 3 * 3600, region = "us", namespace = "dynamic-classicann-us", season = 3,
    players = {
        ["Polypopin-Dreamscythe"] = { [2] = { 1534, 21, 18 }, [3] = { 1531, 21, 29 }, [5] = { 1605, 40, 46 }, t = now - 3 * 3600 },
        ["Zed-LivingFlame"] = { [5] = { 1888, 10, 2 }, t = now - 3600 },
    },
}

do
    local e = CommanderLadder.Lookup("Polypopin")
    CHECK(e and e[2][1] == 1534 and e[5][3] == 46, "a bare name is looked up on our realm")
    CHECK(CommanderLadder.Lookup("Polypopin", "Dreamscythe") == e, "name and realm")
    CHECK(CommanderLadder.Lookup("Polypopin-Dreamscythe") == e, "Name-Realm as one string")
    CHECK(CommanderLadder.Lookup("Zed", "Living Flame") and CommanderLadder.Lookup("Zed", "Living Flame")[5][1] == 1888,
        "a realm with a space finds its key")
    CHECK(CommanderLadder.Lookup("Zed") == nil, "the same name on our realm is someone else")
    CHECK(CommanderLadder.Lookup("") == nil and CommanderLadder.Lookup(nil) == nil, "no name, no entry")
    CHECK(CommanderLadder.Generated() == now - 3 * 3600, "Generated is the file's time")
    -- A name with no realm at all (L8): the group finder lists Nightslayer
    -- players that way, and "ours" was a wrong guess for every one of them
    CHECK(CommanderLadder.Lookup("Zed", nil, true) and CommanderLadder.Lookup("Zed", nil, true)[5][1] == 1888,
        "realm unknown: the one other realm with that name answers")
    CHECK(CommanderLadder.Lookup("zed", nil, true) ~= nil, "...whatever its case")
    CHECK(CommanderLadder.Lookup("Polypopin", nil, true) == e, "realm unknown: ours is still tried first")
    CHECK(CommanderLadder.Lookup("Zed-Dreamscythe", nil, true) == nil,
        "a written realm is never second-guessed")
    CHECK(CommanderLadder.Lookup("Nobody", nil, true) == nil, "a name nowhere in the file is nil")
    CHECK(CommanderLadder.Count() == 2, "two players counted")
    CHECK(CommanderLadder.Status():find("2 players") and CommanderLadder.Status():find("3h old")
        and CommanderLadder.Status():find("season 3"), "status line", CommanderLadder.Status())
end

-- ===========================================================================
-- B2. The roster (L9): who the home realm's rated players are, for Recruit
-- ===========================================================================

CHECK(#CommanderLadder.Roster() == 0, "a file written before L9 lists nobody")
local sectionBData = CommanderLadderData
CommanderLadderData = {
    generated = now - 3600, region = "us", namespace = "dynamic-classicann-us", season = 3,
    players = {
        ["Bootii-Dreamscythe"] = { [2] = { 1512, 11, 10 }, [5] = { 1840, 30, 20 },
            w = { "H", "ROGUE", "BloodElf", now - 86400, "Gank Squad", sex = "F", spec = "SUBTLETY" }, t = now },
        ["Loner-Dreamscythe"] = { [3] = { 1700, 4, 4 }, w = { "A", "PRIEST", "NightElf", 0 }, t = now },
        ["Bare-Dreamscythe"] = { [2] = { 1600, 1, 1 }, t = now },
        ["Zed-LivingFlame"] = { [5] = { 1888, 10, 2 }, w = { "H", "MAGE", "Troll", now, "Elsewhere" }, t = now },
    },
}
do
    local roster = CommanderLadder.Roster()
    CHECK(#roster == 2, "our realm's described players only", #roster)
    local boot, loner = roster[1], roster[2]
    CHECK(boot and boot.key == "Bootii-Dreamscythe" and boot.name == "Bootii" and boot.faction == "H"
        and boot.class == "ROGUE" and boot.race == "BloodElf" and boot.guild == "Gank Squad"
        and boot.last == now - 86400, "every field of w, by name")
    CHECK(boot and boot.best == 1840, "best is the highest bracket", boot and boot.best)
    CHECK(boot and boot.sex == "F" and boot.spec == "SUBTLETY", "sex and talent tree by name (L10)")
    CHECK(loner and loner.guild == nil and loner.last == nil and loner.sex == nil and loner.spec == nil,
        "no guild, login, sex or tree are nil")
    CHECK(CommanderLadder.Roster() == roster, "built once per data file")
    local other = CommanderLadder.Roster("Living Flame")
    CHECK(#other == 1 and other[1].name == "Zed", "another realm by name, spaces dropped")
    CommanderLadderDB.EnableLadder = false
    CHECK(#CommanderLadder.Roster() == 0, "off: nobody")
    CommanderLadderDB.EnableLadder = true
    CHECK(CommanderLadder.Lookup("Bootii")[5][1] == 1840 and CommanderLadder.Count() == 4,
        "a line with w still reads as ratings")
end
CommanderLadderData = sectionBData

-- ===========================================================================
-- C. Wanted names for the next feed run
-- ===========================================================================

CommanderLadderWanted = {}
do
    CommanderLadder.Want("Bob")
    CommanderLadder.Want("Ivy", "Nightslayer")
    CommanderLadder.Want("Kel-Living Flame")
    CHECK(CommanderLadderWanted["Bob-Dreamscythe"] == now, "a bare name is wanted on our realm")
    CHECK(CommanderLadderWanted["Ivy-Nightslayer"] ~= nil, "name and realm")
    CHECK(CommanderLadderWanted["Kel-LivingFlame"] ~= nil, "a written realm loses its space")
    CHECK(CommanderLadder.WantedCount() == 3, "three waiting", CommanderLadder.WantedCount())
    CommanderLadder.Want("Lfg", nil, true)
    CommanderLadder.Want("Kel-Living Flame", nil, true)
    CHECK(CommanderLadderWanted["Lfg-*Dreamscythe"] ~= nil and CommanderLadderWanted["Lfg-Dreamscythe"] == nil,
        "realm unknown: filed as Name-*OurRealm, for the feed to try every realm, ours first")
    CHECK(CommanderLadder.WantedCount() == 4, "...and a written realm is still filed under it",
        CommanderLadder.WantedCount())
    CommanderLadderWanted["Lfg-*Dreamscythe"] = nil
    CommanderLadder.ClearWanted()
    CommanderLadder.Want("Bob")
    CommanderLadder.Want("Ivy", "Nightslayer")
    CommanderLadder.Want("Kel-Living Flame")
    Advance(60)
    CommanderLadder.Want("Bob")
    CHECK(CommanderLadderWanted["Bob-Dreamscythe"] == now and CommanderLadder.WantedCount() == 3,
        "wanting again renews the time, not the count")

    -- Old wishes go after two weeks; the cap holds the newest
    CommanderLadderWanted["Old-Dreamscythe"] = now - 15 * 86400
    for i = 1, 1005 do CommanderLadderWanted["P" .. i .. "-Dreamscythe"] = now - 2000 + i end
    CommanderLadder.ClearWanted()
    CHECK(next(CommanderLadderWanted) == nil and CommanderLadder.WantedCount() == 0, "clear empties the list")
    for i = 1, 1005 do CommanderLadderWanted["P" .. i .. "-Dreamscythe"] = now - 2000 + i end
    CommanderLadderWanted["Old-Dreamscythe"] = now - 15 * 86400
    -- A fresh login: the count is taken again from the saved table
    Load(ADDONS .. "/Commander_Ladder/CommanderLadder.lua")
    CommanderLadder.Want("New")
    local n = 0
    for _ in pairs(CommanderLadderWanted) do n = n + 1 end
    CHECK(n == 1000, "the list is capped at 1000", n)
    CHECK(CommanderLadderWanted["Old-Dreamscythe"] == nil, "a two-week-old wish is dropped")
    CHECK(CommanderLadderWanted["New-Dreamscythe"] ~= nil, "the newest wish survives the cap")
    CHECK(CommanderLadderWanted["P1-Dreamscythe"] == nil and CommanderLadderWanted["P1005-Dreamscythe"] ~= nil,
        "the oldest go first")
end

-- ===========================================================================
-- D. The master switch
-- ===========================================================================

CommanderLadderDB.EnableLadder = false
CHECK(CommanderLadder.Lookup("Polypopin") == nil, "off: Lookup is nil")
CommanderLadder.ClearWanted()
CommanderLadder.Want("Bob")
CHECK(next(CommanderLadderWanted) == nil, "off: nothing is wanted")
CommanderLadderDB.EnableLadder = true

-- ===========================================================================
-- E. Settings page and slash command
-- ===========================================================================

CHECK(type(SlashCmdList.COMMANDERUI_LADDER) == "function", "slash command registered")
SlashCmdList.COMMANDERUI_LADDER("status")
do
    local found = false
    for _, line in ipairs(printLog) do if line:find("2 players") then found = true end end
    CHECK(found, "status prints the feed")
end
do
    local ok, err = pcall(function()
        for _, cat in ipairs(categories) do
            if cat.__title == "Ladder" then
                local panel = cat.__panel
                if panel.__scripts.OnShow then panel.__scripts.OnShow(panel) end
            end
        end
    end)
    CHECK(ok, "settings page refreshes without error", err)
end

CHECK(#harnessFailedErrors == 0, "no errors were swallowed by the error handler", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
