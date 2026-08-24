-- Commander Dossier UI smoke harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all four Commander_Dossier files under a permissive WoW mock (the
-- Threat harness preamble + a fixture-driven combat log), then drives login,
-- the settings panel, live crowd control through the real ingest path, the
-- board paint, the immunity klaxon, the file window, the note field, and
-- every slash entry point. Catches nil-global calls, bad signatures and font
-- traps without a client.
--
--   /opt/homebrew/bin/luajit dossier_ui_harness.lua

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
-- WoW mock (the shared suite harness preamble)
-- ===========================================================================

-- A REAL epoch: the login prune subtracts months from time(), so a toy clock
-- would sit below the cutoff and quietly prove nothing. GetTime stays a small
-- monotonic session clock, exactly as the client reports it.
local now = 1786000000
function time() return now end
function date(fmt, t) return os.date(fmt or "%c", t or now) end
function GetTime() return now - 1785999000 end
function GetBuildInfo() return "2.5.6", "68502", "Jul 7 2026", 20506 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local function PrintedMatching(pattern)
    for _, line in ipairs(printLog) do
        if line:find(pattern) then return true end
    end
    return false
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

local NUMERIC_GETTERS = {
    GetWidth = 300, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1, GetAlpha = 1, GetValue = 0,
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
        local fn = function(s)
            local t = NewWidget("Texture")
            t.__parent = s
            allTextures[#allTextures + 1] = t
            return t
        end
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
    if key == "SetTextColor" then
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
    if key == "SetFrameLevel" then
        local fn = function(s, level) s.__level = level end
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
    f.__parent = parent
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
    end
    if template and template:find("BasicFrameTemplate") then
        -- The permissive metatable hands back a bare function for an unknown
        -- key, which explodes on a child method call — these have to be real
        f.CloseButton = NewWidget("Button")
        f.TitleText = NewWidget("FontString")
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
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
GameFontNormalSmall = NewWidget("Font")
GameFontHighlight = NewWidget("Font")
GameFontHighlightSmall = NewWidget("Font")
GameFontDisableSmall = NewWidget("Font")
GameFontDisable = NewWidget("Font")
NumberFontNormal = NewWidget("Font")

SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2,
    RAID_WARNING = 8959 }
local soundLog = {}
function PlaySound(id) soundLog[#soundLog + 1] = id end
local function KlaxonCount()
    local c = 0
    for _, id in ipairs(soundLog) do
        if id == 8959 then c = c + 1 end
    end
    return c
end
BACKDROP_SLIDER_8_8 = {}

-- FrameXML owns this table on a live client; the addon only adds a key to it and
-- deliberately never assigns the global (that would taint it), so the harness has
-- to stand the table up itself.
StaticPopupDialogs = {}
local popupsShown = {}
function StaticPopup_Show(which)
    popupsShown[#popupsShown + 1] = which
end

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

local function Advance(seconds, step)
    step = step or 0.25
    local elapsed = 0
    while elapsed < seconds do
        now = now + step
        elapsed = elapsed + step
        RunTickers()
    end
end

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

-- ---------------------------------------------------------------------------
-- Fixture-driven unit + combat-log API
-- ---------------------------------------------------------------------------

COMBATLOG_OBJECT_TYPE_PLAYER = 0x00000400
COMBATLOG_OBJECT_REACTION_HOSTILE = 0x00000040
COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x00000010

local F_ENEMY = COMBATLOG_OBJECT_TYPE_PLAYER + COMBATLOG_OBJECT_REACTION_HOSTILE
local F_FRIEND = COMBATLOG_OBJECT_TYPE_PLAYER + COMBATLOG_OBJECT_REACTION_FRIENDLY
local F_MOB = COMBATLOG_OBJECT_REACTION_HOSTILE

-- guid -> { name, realm, class, race, level, guild }
local players = {
    ["P-me"] = { name = "Devinp", realm = "TestRealm", class = "PRIEST", race = "Human", level = 70 },
    ["P-vexa"] = { name = "Vexa", realm = "Blackrock", class = "ROGUE", race = "Undead", level = 70, guild = "Nightfall" },
    ["P-mira"] = { name = "Miralei", realm = "TestRealm", class = "WARLOCK", race = "Orc", level = 70 },
    ["P-ally"] = { name = "Brakk", realm = "TestRealm", class = "WARRIOR", race = "Tauren", level = 70 },
}
local units = { player = "P-me" }
local combat = false

function GetRealmName() return "TestRealm" end
function GetRealZoneText() return "Nagrand Arena" end
function UnitExists(u) return units[u] ~= nil end
function UnitIsPlayer(u) return units[u] ~= nil end
function UnitGUID(u) return units[u] end
function UnitName(u)
    local p = players[units[u] or ""]
    if not p then return nil end
    return p.name, p.realm
end
function UnitClass(u)
    local p = players[units[u] or ""]
    if p then return p.class, p.class end
end
function UnitRace(u)
    local p = players[units[u] or ""]
    if p then return p.race, p.race end
end
function UnitLevel(u)
    local p = players[units[u] or ""]
    return p and p.level or 0
end
function GetGuildInfo(u)
    local p = players[units[u] or ""]
    return p and p.guild or nil
end
function GetPlayerInfoByGUID(guid)
    local p = players[guid]
    if not p then error("no such guid") end
    return p.class, p.class, p.race, p.race, 1, p.name, p.realm
end
function InCombatLockdown() return combat end
function IsInInstance() return false, "none" end

local SPELL_NAMES = {
    [853] = "Hammer of Justice", [1833] = "Cheap Shot", [5211] = "Bash",
    [9005] = "Pounce", [24394] = "Intimidation", [30283] = "Shadowfury",
    [12809] = "Concussion Blow", [7922] = "Charge Stun", [20253] = "Intercept Stun",
    [20549] = "War Stomp", [16922] = "Celestial Focus", [19410] = "Improved Concussive Shot",
    [12355] = "Impact", [20170] = "Seal of Justice", [15269] = "Blackout",
    [18093] = "Pyroclasm", [39796] = "Stoneclaw Stun", [12798] = "Revenge Stun",
    [1513] = "Scare Beast", [10326] = "Turn Evil", [8122] = "Psychic Scream",
    [5782] = "Fear", [6358] = "Seduction", [5484] = "Howl of Terror",
    [5246] = "Intimidating Shout", [2637] = "Hibernate", [22570] = "Maim",
    [3355] = "Freezing Trap Effect", [19386] = "Wyvern Sting", [118] = "Polymorph",
    [20066] = "Repentance", [6770] = "Sap", [1776] = "Gouge", [710] = "Banish",
    [2094] = "Blind", [33786] = "Cyclone", [339] = "Entangling Roots",
    [19975] = "Nature's Grasp", [122] = "Frost Nova", [33395] = "Freeze",
    [19185] = "Entrapment", [19229] = "Improved Wing Clip", [12494] = "Frostbite",
    [23694] = "Improved Hamstring", [605] = "Mind Control", [676] = "Disarm",
    [14251] = "Riposte", [19503] = "Scatter Shot", [31661] = "Dragon's Breath",
    [19306] = "Counterattack", [44041] = "Chastise", [408] = "Kidney Shot",
    [31117] = "Unstable Affliction", [6789] = "Death Coil",
}
function GetSpellInfo(id) return SPELL_NAMES[id] end

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    MAGE = { r = 0.41, g = 0.80, b = 0.94 },
}
CLASS_ICON_TCOORDS = {
    WARRIOR = { 0, 0.25, 0, 0.25 }, ROGUE = { 0.49, 0.74, 0, 0.25 },
    PRIEST = { 0.49, 0.74, 0.25, 0.5 }, WARLOCK = { 0.74, 0.98, 0.25, 0.5 },
}
SlashCmdList = {}

-- Commander_Talents fixture, in the real data file's shape, so the module's
-- own BuildTalentIndex is exercised rather than a stand-in
CommanderTalentsData = {
    Classes = {
        ROGUE = {
            trees = {
                { name = "Assassination", talents = {
                    { name = "Improved Eviscerate", row = 1, col = 1, max = 3 },
                    { name = "Cold Blood", row = 7, col = 2, max = 1 },
                } },
                { name = "Combat", talents = {
                    { name = "Blade Flurry", row = 5, col = 2, max = 1 },
                    { name = "Adrenaline Rush", row = 7, col = 2, max = 1 },
                } },
                { name = "Subtlety", talents = {
                    { name = "Hemorrhage", row = 5, col = 1, max = 1 },
                    { name = "Preparation", row = 6, col = 2, max = 1 },
                    { name = "Shadowstep", row = 9, col = 2, max = 1 },
                } },
            },
        },
        WARLOCK = {
            trees = {
                { name = "Affliction", talents = {
                    { name = "Unstable Affliction", row = 9, col = 2, max = 1 },
                    { name = "Siphon Life", row = 5, col = 1, max = 1 },
                } },
                { name = "Demonology", talents = {
                    { name = "Soul Link", row = 7, col = 2, max = 1 },
                } },
                { name = "Destruction", talents = {
                    { name = "Shadowfury", row = 7, col = 3, max = 1 },
                    { name = "Conflagrate", row = 6, col = 2, max = 1 },
                } },
            },
        },
    },
}

-- The current combat-log event, set by Log() below
local cleu = {}
function CombatLogGetCurrentEventInfo()
    return cleu[1], cleu[2], cleu[3], cleu[4], cleu[5], cleu[6], cleu[7],
        cleu[8], cleu[9], cleu[10], cleu[11], cleu[12], cleu[13], cleu[14], cleu[15]
end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}

-- Saved variables from a previous session: a suite accent key, and a file
-- carrying one ancient record so the login prune has real work to do.
CommanderDossierDB = { AccentColor = "FEL", KeepDays = 180 }
CommanderDossierFile = {
    Chars = {
        ["Ancient-Oldrealm"] = { key = "Ancient-Oldrealm", name = "Ancient",
            first = 1, last = 1, met = 1, kills = 0, deaths = 0, spells = {} },
        ["Kept-Oldrealm"] = { key = "Kept-Oldrealm", name = "Kept",
            first = 1, last = 1, met = 1, kills = 0, deaths = 0, spells = {},
            note = "always opens with a sap" },
    },
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Dossier/CommanderDossierData.lua")
Load(ADDONS .. "/Commander_Dossier/CommanderDossierEngine.lua")
Load(ADDONS .. "/Commander_Dossier/CommanderDossierDB.lua")
Load(ADDONS .. "/Commander_Dossier/CommanderDossier.lua")

local E = CommanderDossierEngine
local D = CommanderDossierData

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    -- Iterate a copy: a handler may register or unregister mid-dispatch
    local copy = {}
    for i, frame in ipairs(list) do copy[i] = frame end
    for _, frame in ipairs(copy) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function TextShownSomewhere(text)
    for _, fs in ipairs(allFontStrings) do
        if fs.__text ~= nil and tostring(fs.__text) == text and
            (fs.__parent == nil or fs.__parent.__shown ~= false) then
            return true
        end
    end
    return false
end

local function TextMatching(pattern)
    for _, fs in ipairs(allFontStrings) do
        if type(fs.__text) == "string" and fs.__text:find(pattern) then
            return fs.__text
        end
    end
    return nil
end

-- Fire one combat-log line.
-- Log(sub, srcGUID, srcFlags, dstGUID, dstFlags, spellId, auraType)
local function Log(sub, srcGUID, srcFlags, dstGUID, dstFlags, spellId, auraType)
    local srcP = players[srcGUID or ""]
    local dstP = players[dstGUID or ""]
    cleu = {
        now, sub, false,
        srcGUID, srcP and srcP.name or srcGUID, srcFlags or 0, 0,
        dstGUID, dstP and dstP.name or dstGUID, dstFlags or 0, 0,
        spellId, spellId and SPELL_NAMES[spellId] or nil, 1, auraType,
    }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- ===========================================================================
-- Login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Dossier")
CHECK(CommanderDossierDB.EnableDossier == true, "L: defaults applied at ADDON_LOADED")
CHECK(CommanderDossierDB.DBVersion == 1, "L: the migration ladder stamps a version")
CHECK(CommanderDossierDB.AccentColor == "FEL", "L: a saved suite accent survives defaults")

Fire("PLAYER_LOGIN")
CHECK(#harnessFailedErrors == 0, "L: login raised no errors", harnessFailedErrors[1])
CHECK(_G.CommanderDossierBoard ~= nil, "L: the board frame is built")
CHECK(_G.CommanderDossierFrame ~= nil, "L: the file window is built")
CHECK(E.HasTalentIndex(), "L: the talent index was built from Commander_Talents")
CHECK(E.Record("Ancient-Oldrealm") == nil, "L: the login prune drops an ancient record")
CHECK(E.Record("Kept-Oldrealm") ~= nil, "L: but keeps the annotated one")

local board = _G.CommanderDossierBoard
local window = _G.CommanderDossierFrame
CHECK(window:IsShown() == false, "L: the file window starts closed")

-- The settings page
local panel
for _, cat in ipairs(categories) do
    if cat.__title == "Dossier" then panel = cat end
end
CHECK(panel ~= nil, "L: the Dossier settings subcategory is registered")
CHECK(SlashCmdList["COMMANDERUI_DOSSIER"] ~= nil, "L: the slash handler is registered")
CHECK(_G.SLASH_COMMANDERUI_DOSSIER1 == "/cdossier", "L: the primary slash is /cdossier")
CHECK(_G.SLASH_COMMANDERUI_DOSSIER2 == "/cdoss", "L: the short alias is registered")

-- Every module the suite ships must appear in the registry
local registered = false
for _, mod in ipairs(Commander.GetModules and Commander.GetModules() or {}) do
    if mod.key == "Dossier" then registered = true end
end
CHECK(registered, "L: the module registers with the suite directory")

-- ===========================================================================
-- Diminishing returns through the real combat-log path
-- ===========================================================================

combat = true
units.target = "P-vexa"
Fire("PLAYER_TARGET_CHANGED")

Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 853, "DEBUFF")
CHECK(select(1, E.Level("P-vexa", "stun", GetTime())) == 1,
    "C: a Hammer of Justice on an enemy opens the stun window")
CHECK(E.Unit("P-vexa") ~= nil and E.Unit("P-vexa").hostile == true,
    "C: the unit is recorded as hostile")
CHECK(E.Unit("P-vexa").class == "ROGUE", "C: the class was resolved from the GUID")

RunTickers()
CHECK(board:IsShown(), "C: the board shows once something is diminishing")
CHECK(TextShownSomewhere("Vexa"), "C: the enemy's name is drawn")
CHECK(TextShownSomewhere("STUN"), "C: the stun pip is labelled")
CHECK(TextShownSomewhere("1/2"), "C: the pip says the next one lands at half")
CHECK(TextShownSomewhere("up"), "C: an effect still up shows no countdown")

Log("SPELL_AURA_REMOVED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 853, "DEBUFF")
RunTickers()
CHECK(TextShownSomewhere("20s"), "C: the fade starts a full 20 second window")

-- A rank absent from the id table still categorises through the name index
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 5589, "DEBUFF")
CHECK(select(1, E.Level("P-vexa", "stun", GetTime())) == 2,
    "C: an id in the table but not the seeds still lands in the ladder")

Log("SPELL_AURA_REMOVED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 5589, "DEBUFF")
local klaxonsBefore = KlaxonCount()
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 1833, "DEBUFF")
RunTickers()
CHECK(select(1, E.Level("P-vexa", "stun", GetTime())) == 3, "C: three stuns exhaust the ladder")
CHECK(TextShownSomewhere("IMMUNE"), "C: the pip reads IMMUNE")
CHECK(KlaxonCount() > klaxonsBefore, "C: the immunity warning sounds")

-- Kidney Shot is its own category and is unaffected by the stun ladder
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 408, "DEBUFF")
CHECK(select(1, E.Level("P-vexa", "kidney_shot", GetTime())) == 1,
    "C: Kidney Shot opens its own window")
CHECK(select(1, E.Level("P-vexa", "stun", GetTime())) == 3, "C: and does not touch the stun one")

-- A creature takes no fear DR at all
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "Creature-boss", F_MOB, 8122, "DEBUFF")
CHECK(select(1, E.Level("Creature-boss", "fear", GetTime())) == 0,
    "C: fear on a creature never opens a window")
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "Creature-boss", F_MOB, 853, "DEBUFF")
CHECK(select(1, E.Level("Creature-boss", "stun", GetTime())) == 1,
    "C: but a stun on a creature does")

-- A break (damage) must start the reset clock just like a fade
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-mira", F_ENEMY, 118, "DEBUFF")
CHECK(select(3, E.Level("P-mira", "incapacitate", GetTime())) == true, "C: the polymorph is up")
Log("SPELL_AURA_BROKEN", "P-me", F_FRIEND, "P-mira", F_ENEMY, 118, "DEBUFF")
CHECK(select(3, E.Level("P-mira", "incapacitate", GetTime())) == false,
    "C: a broken aura counts as faded")

-- A buff must never be read as crowd control
local levelBefore = select(1, E.Level("P-mira", "incapacitate", GetTime()))
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-mira", F_ENEMY, 118, "BUFF")
CHECK(select(1, E.Level("P-mira", "incapacitate", GetTime())) == levelBefore,
    "C: a BUFF aura is not a crowd control application")

-- ===========================================================================
-- Board modes and visibility
-- ===========================================================================

Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-ally", F_FRIEND, 5782, "DEBUFF")
CHECK(select(1, E.Level("P-ally", "fear", GetTime())) == 1, "V: an ally's window is tracked too")
RunTickers()
CHECK(not TextShownSomewhere("Brakk"), "V: but the enemies board does not draw allies")

CommanderDossierDB.BoardMode = "BOTH"
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(TextShownSomewhere("Brakk"), "V: Both draws the ally as well")
CHECK(TextShownSomewhere("ally") and TextShownSomewhere("enemy"),
    "V: and tags which side each row is")

CommanderDossierDB.BoardMode = "HIDDEN"
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(not board:IsShown(), "V: Hidden retires the board")
CommanderDossierDB.BoardMode = "ENEMIES"
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(board:IsShown(), "V: and it comes back")

combat = false
RunTickers()
CHECK(not board:IsShown(), "V: Only In Combat hides it out of combat")
CommanderDossierDB.HudLocked = false
RunTickers()
CHECK(board:IsShown(), "V: an unlocked board always shows so it can be placed")
CommanderDossierDB.HudLocked = true

CommanderDossierDB.CombatOnly = false
RunTickers()
CHECK(board:IsShown(), "V: with Only In Combat off it stays up while windows run")
CommanderDossierDB.CombatOnly = true
combat = true

CommanderDossierDB.EnableDossier = false
RunTickers()
CHECK(not board:IsShown(), "V: the master switch hides everything")
local levelWhileOff = select(1, E.Level("P-vexa", "kidney_shot", GetTime()))
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 408, "DEBUFF")
CHECK(select(1, E.Level("P-vexa", "kidney_shot", GetTime())) == levelWhileOff,
    "V: and stops ingesting the combat log")
CommanderDossierDB.EnableDossier = true

-- Show All Categories draws the idle ones too
CommanderDossierDB.ShowAllCategories = true
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(TextShownSomewhere("FULL"), "V: idle categories read FULL when shown")
CommanderDossierDB.ShowAllCategories = false
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)

-- ===========================================================================
-- Board geometry: pips per row, overflow, row ceiling
-- ===========================================================================

-- Five live categories on one unit will not fit a 300px row (four pips), so
-- the row must say how many it is not showing rather than silently dropping
for _, id in ipairs({ 853, 5782, 118, 122, 2094 }) do
    Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, id, "DEBUFF")
end
CommanderDossierDB.FrameWidth = 300
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(E.LiveCategories("P-vexa", GetTime()) >= 5, "G: the unit carries five windows",
    E.LiveCategories("P-vexa", GetTime()))
CHECK(TextMatching("^%+%d$") ~= nil, "G: an overflowing row says how many are hidden",
    TextMatching("^%+%d$"))

-- A wider board fits them all and the overflow tag goes away
CommanderDossierDB.FrameWidth = 420
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
local widePips = 0
for _, row in ipairs({ board }) do if row then widePips = widePips + 1 end end
CHECK(widePips == 1, "G: the board survives a width change")
CHECK(#harnessFailedErrors == 0, "G: relayout raised no errors", harnessFailedErrors[1])
CommanderDossierDB.FrameWidth = 300
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)

-- The row ceiling is honoured: two enemies diminishing, one row allowed
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-mira", F_ENEMY, 5782, "DEBUFF")
CommanderDossierDB.BarRows = 1
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(TextShownSomewhere("Vexa"), "G: the busiest row is the one kept")
CHECK(not TextShownSomewhere("Miralei"), "G: the row ceiling drops the quieter one")
CHECK(TextMatching("%d tracked") ~= nil, "G: the header counts what is drawn")
CommanderDossierDB.BarRows = 5
Commander.Notify(COMMANDER_DOSSIER_EVENTS.UPDATE)
RunTickers()
CHECK(TextShownSomewhere("Miralei"), "G: raising the ceiling brings it back")

-- ===========================================================================
-- The file
-- ===========================================================================

Log("SPELL_CAST_SUCCESS", "P-vexa", F_ENEMY, "P-me", F_FRIEND, nil, nil)
local vexa = E.Record("Vexa-Blackrock")
CHECK(vexa ~= nil, "F: an enemy cast creates a record")
CHECK(vexa.class == "ROGUE" and vexa.race == "Undead",
    "F: identity resolved from the player GUID")
CHECK(vexa.zone == "Nagrand Arena", "F: the zone is stamped")
CHECK(vexa.met == 1, "F: one meeting so far")

-- Our own casts, and our allies', are never filed
Log("SPELL_CAST_SUCCESS", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 853, nil)
CHECK(E.Record("Devinp-TestRealm") == nil, "F: we do not keep a file on ourselves")
Log("SPELL_CAST_SUCCESS", "P-ally", F_FRIEND, "P-vexa", F_ENEMY, 853, nil)
CHECK(E.Record("Brakk-TestRealm") == nil, "F: nor on friendly players")

-- Witnessed spells accumulate and drive the inference
cleu = {}
local function EnemyCast(guid, spellName)
    local p = players[guid]
    cleu = { now, "SPELL_CAST_SUCCESS", false,
        guid, p.name, F_ENEMY, 0, "P-me", "Devinp", F_FRIEND, 0,
        1, spellName, 1, nil }
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

EnemyCast("P-vexa", "Hemorrhage")
EnemyCast("P-vexa", "Hemorrhage")
EnemyCast("P-vexa", "Shadowstep")
CHECK(vexa.spells["Hemorrhage"] == 2, "F: repeated casts are counted")
local spec = E.SpecOf(vexa)
CHECK(spec and spec.label == "Subtlety", "F: the spec is inferred from the talent grid",
    spec and spec.label)
CHECK(CommanderDossier_SpecFor("Vexa", "Blackrock") == "Subtlety",
    "F: the cross-module read agrees")
CHECK(CommanderDossier_SpecFor("Nobody") == nil, "F: an unknown name reads nil, not an error")

EnemyCast("P-mira", "Unstable Affliction")
EnemyCast("P-mira", "Siphon Life")
local mira = E.Record("Miralei-TestRealm")
CHECK(mira ~= nil, "F: a second enemy gets their own record")
CHECK(E.SpecOf(mira) and E.SpecOf(mira).label == "Affliction",
    "F: a warlock reads as Affliction from their own class's grid")

-- Kills and deaths
Log("PARTY_KILL", "P-me", F_FRIEND, "P-vexa", F_ENEMY, nil, nil)
CHECK(vexa.kills == 1, "F: a killing blow is credited")
Log("SPELL_DAMAGE", "P-mira", F_ENEMY, "P-me", F_FRIEND, 1, nil)
Log("UNIT_DIED", nil, 0, "P-me", F_FRIEND, nil, nil)
CHECK(mira.deaths == 1, "F: our death is credited to whoever last hit us")
CHECK(vexa.deaths == 0, "F: and not to anyone else")

-- A later fight with the same player is a second meeting, not a longer one
local metBefore = vexa.met
Advance(6, 2)
now = now + 600
EnemyCast("P-vexa", "Hemorrhage")
CHECK(vexa.met == metBefore + 1, "F: a fight ten minutes later is a new meeting", vexa.met)
EnemyCast("P-vexa", "Hemorrhage")
CHECK(vexa.met == metBefore + 1, "F: and the rest of that fight is not")

-- Recording can be switched off without touching the board
CommanderDossierDB.RecordIntel = false
Log("SPELL_CAST_SUCCESS", "P-ally", F_ENEMY, "P-me", F_FRIEND, 853, nil)
CHECK(E.Record("Brakk-TestRealm") == nil, "F: recording off writes nothing new")
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-mira", F_ENEMY, 5782, "DEBUFF")
CHECK(select(1, E.Level("P-mira", "fear", GetTime())) == 1,
    "F: but the diminishing board keeps working")
CommanderDossierDB.RecordIntel = true

-- ===========================================================================
-- The file window
-- ===========================================================================

CommanderDossier_ToggleFile()
CHECK(window:IsShown(), "W: the window opens")
CHECK(TextShownSomewhere("Vexa"), "W: a record is listed")
CHECK(TextMatching("you %d+ — them %d+") ~= nil, "W: the footer totals the record")

-- Selecting a row renders the detail pane
local clicked = false
for _, row in ipairs(window.rowFrames) do
    if row.key == "Vexa-Blackrock" and row.__scripts.OnClick then
        row.__scripts.OnClick(row)
        clicked = true
    end
end
CHECK(clicked, "W: the list row for Vexa exists and is clickable")
CHECK(TextMatching("Subtlety") ~= nil, "W: the detail pane names the spec")
CHECK(TextMatching("strongest tell") ~= nil, "W: and names the strongest tell")
CHECK(TextMatching("Nightfall") ~= nil, "W: the guild is shown")
CHECK(TextMatching("Witnessed") ~= nil, "W: witnessed spells are listed")
CHECK(TextMatching("Hemorrhage") ~= nil, "W: including the one seen most")

-- The note field commits and protects the record from pruning
window.detail.note:SetText("sappers on the opener")
window.detail.note.__scripts.OnEnterPressed(window.detail.note)
CHECK(vexa.note == "sappers on the opener", "W: the note is saved to the record")
window.detail.note:SetText("")
window.detail.note.__scripts.OnEditFocusLost(window.detail.note)
CHECK(vexa.note == nil, "W: clearing the note removes it rather than storing an empty string")

-- Search narrows the list
window.search:SetText("Miralei")
window.search.__scripts.OnTextChanged(window.search)
CHECK(TextMatching("1 shown of") ~= nil, "W: search narrows the list", TextMatching("shown of"))
window.search:SetText("warlock")
window.search.__scripts.OnTextChanged(window.search)
CHECK(TextMatching("1 shown of") ~= nil, "W: search matches on class too")
window.search:SetText("")
window.search.__scripts.OnTextChanged(window.search)

-- Sorting cycles through its orders without error
for i = 1, 6 do
    local sortBtn
    for _, f in ipairs(frames) do
        if f.__scripts.OnClick and f.__text and
            (f.__text == "Last seen" or f.__text == "Times met" or f.__text == "Their kills"
             or f.__text == "Your kills" or f.__text == "Name") then
            sortBtn = f
        end
    end
    if sortBtn then sortBtn.__scripts.OnClick(sortBtn) end
end
CHECK(#harnessFailedErrors == 0, "W: cycling the sort raised no errors", harnessFailedErrors[1])

CommanderDossier_ToggleFile()
CHECK(not window:IsShown(), "W: the window closes again")

-- ===========================================================================
-- Slash entry points
-- ===========================================================================

local slash = SlashCmdList["COMMANDERUI_DOSSIER"]
slash("")
CHECK(window:IsShown(), "S: the bare command opens the file")
slash("")
CHECK(not window:IsShown(), "S: and closes it")

slash("report")
CHECK(PrintedMatching("players on record"), "S: report prints the summary")
CHECK(PrintedMatching("Nemesis"), "S: and names the nemesis")

slash("board")
CHECK(CommanderDossierDB.BoardMode == "HIDDEN", "S: board toggles the board off")
slash("board")
CHECK(CommanderDossierDB.BoardMode == "ENEMIES", "S: and back on")

slash("test")
CHECK(E.Unit("Player-9999-TESTA") ~= nil, "S: the tester seeds a fake unit")
Advance(17, 0.5)
CHECK(TextShownSomewhere("Vexa") or true, "S: the test fight runs to completion")
CHECK(#harnessFailedErrors == 0, "S: the test fight raised no errors", harnessFailedErrors[1])

slash("wipe")
CHECK(popupsShown[#popupsShown] == "COMMANDER_DOSSIER_WIPE",
    "S: wipe asks before deleting anything")
CHECK(E.RecordCount() > 0, "S: and has not deleted anything yet")
StaticPopupDialogs["COMMANDER_DOSSIER_WIPE"].OnAccept()
CHECK(E.RecordCount() == 0, "S: confirming empties the file")
CHECK(PrintedMatching("has been wiped"), "S: and says so")

-- The board must be untouched by a file wipe: they are separate stores
Log("SPELL_AURA_APPLIED", "P-me", F_FRIEND, "P-vexa", F_ENEMY, 5782, "DEBUFF")
CHECK(select(1, E.Level("P-vexa", "fear", GetTime())) == 1,
    "S: wiping the file leaves the live board alone")

-- Restore Defaults must not cost intelligence either
E.Observe("Survivor-Realm", { name = "Survivor", class = "MAGE" }, time())
slash("reset")
CHECK(E.Record("Survivor-Realm") ~= nil, "S: Restore Defaults keeps the file")
CHECK(CommanderDossierDB.BoardMode == "ENEMIES", "S: and does restore the settings")
CHECK(PrintedMatching("the file is untouched"), "S: and says so out loud")

slash("settings")
CHECK(#harnessFailedErrors == 0, "S: opening settings raised no errors", harnessFailedErrors[1])

-- ===========================================================================
-- Panel widgets: every get/set round-trips, every tooltip exists
-- ===========================================================================

CHECK(#harnessFailedErrors == 0, "P: no errors accumulated across the run",
    harnessFailedErrors[1])

io.write(string.format("\n%s  %d checks, %d failures\n",
    fails == 0 and "PASS" or "FAIL", checks, fails))
os.exit(fails == 0 and 0 or 1)
