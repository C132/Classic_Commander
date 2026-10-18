-- Commander Notebook UI harness (luajit).
--
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all three Commander_Notebook files under the suite's permissive widget
-- mock, then drives the whole lifecycle without a client: login, the settings
-- panel, building the window, writing a note, the auto-save debounce, search,
-- the sidebar, the trash, quick capture, the shift-click link path, and
-- (1.1.0) a stamp as a way back: Go and "Waypoint To This Note" through
-- Commander Orders, for new stamps by map id and for old ones by zone name.
--
-- It exists to catch what the store harness cannot: nil-global calls, wrong
-- widget signatures, and the wiring between the three files. The one check it
-- matters most for is R1 -- that Restore Defaults cannot delete writing.
--
--   /opt/homebrew/bin/luajit notebook_ui_harness.lua

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
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
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
-- ===========================================================================
-- Notebook-specific mock
--
-- The shared preamble above has no notion of keyboard focus, and this module
-- is built entirely around which box has it: the auto-save contract, the
-- deferred re-sort and the shift-click link path all branch on HasFocus. So
-- edit boxes get real focus and real text here, and nothing else does.
-- ===========================================================================

local focused = nil

local RawNewWidget = NewWidget
NewWidget = function(kind, name)
    local widget = RawNewWidget(kind, name)
    rawset(widget, "SetShown", function(self, shown)
        self.__shown = shown and true or false
    end)
    if kind == "EditBox" then
        rawset(widget, "SetFocus", function(self) focused = self end)
        rawset(widget, "ClearFocus", function(self)
            if focused == self then
                focused = nil
                local handler = self.__scripts.OnEditFocusLost
                if handler then handler(self) end
            end
        end)
        rawset(widget, "HasFocus", function(self) return focused == self end)
        rawset(widget, "Insert", function(self, text)
            self.__text = (self.__text or "") .. tostring(text or "")
        end)
        rawset(widget, "Enable", function(self) self.__enabled = true end)
        rawset(widget, "Disable", function(self) self.__enabled = false end)
    end
    return widget
end

-- Type into a box the way a person does: set the text, then fire the script
-- with userInput true, which is the flag every OnTextChanged in the module
-- branches on.
local function Type(box, text)
    box:SetFocus()
    box.__text = text
    local handler = box.__scripts.OnTextChanged
    if handler then handler(box, true) end
end

local function Blur(box)
    box:ClearFocus()
end

local function Click(widget, button)
    local handler = widget.__scripts.OnClick
    if handler then handler(widget, button or "LeftButton") end
end

function GetSubZoneText() return "Halaa" end
function GetRealmName() return "TestRealm" end

C_Map = {
    GetBestMapForUnit = function() return 1 end,
    GetPlayerMapPosition = function()
        return { GetXY = function() return 0.435, 0.612 end }
    end,
}

local itemRefs = {}
function SetItemRef(payload, link, button)
    itemRefs[#itemRefs + 1] = { payload = payload, link = link, button = button }
end

-- The client's own function, which the module wraps. The harness records
-- whether the ORIGINAL was reached, which is how the fall-through case below
-- is proved rather than assumed.
local originalInsertReached = 0
function ChatEdit_InsertLink(text)
    originalInsertReached = originalInsertReached + 1
    return false
end

function IsMacClient() return true end

local popupData = {}
local realStaticPopupShow = StaticPopup_Show
function StaticPopup_Show(which, arg1, arg2, data)
    popupData[which] = { arg1 = arg1, data = data }
    realStaticPopupShow(which, arg1, arg2, data)
    return { data = data, editBox = nil }
end

-- Run a popup's accept path the way clicking its button would.
local function AcceptPopup(which, typed)
    local dialog = StaticPopupDialogs[which]
    if not dialog then return false end
    local record = popupData[which] or {}
    local host = { data = record.data }
    if dialog.hasEditBox then
        local box = NewWidget("EditBox")
        box.__text = typed or ""
        host.editBox = box
        if dialog.OnShow then dialog.OnShow(host, record.data) end
        box.__text = typed or ""
    end
    if dialog.OnAccept then dialog.OnAccept(host, record.data) end
    return true
end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    assert(loadfile(path))()
end

CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}
CommanderConsoleDB = { ConsoleColor = "FEL" }

-- Saved variables from a previous session: one notebook, two notes, a stale
-- selection pointing at a notebook that no longer exists, and a setting the
-- defaults must not overwrite.
CommanderNotebookDB = {
    FrameStyle = "DARK",
    LastScope = "notebook",
    LastKey = "nb-vanished",
    Notebooks = {
        ["nb-raids"] = { id = "nb-raids", name = "Raids", created = 1 },
    },
    Notes = {
        ["n2"] = { id = "n2", title = "Kara notes", body = "pull order",
            notebook = "nb-raids", tags = { "raid" }, created = 10, updated = 20 },
        ["n3"] = { id = "n3", title = "Old", body = "text",
            notebook = "nb-gone", created = 5, updated = 6 },
    },
    NextID = 1,
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
-- Commander_Events' TOC loads its Go button between the two (Orders 3.1)
Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
-- Mutation hooks: NOTEBOOK_STORE / NOTEBOOK_UI = /path of a copy to load instead
Load(os.getenv("NOTEBOOK_STORE") or (ADDONS .. "/Commander_Notebook/CommanderNotebookStore.lua"))
Load(ADDONS .. "/Commander_Notebook/CommanderNotebookDB.lua")
Load(os.getenv("NOTEBOOK_UI") or (ADDONS .. "/Commander_Notebook/CommanderNotebookUI.lua"))

local S = CommanderNotebookStore
local N = CommanderNotebook

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    local copy = {}
    for index, frame in ipairs(list) do copy[index] = frame end
    for _, frame in ipairs(copy) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function NoErrors(label)
    CHECK(#harnessFailedErrors == 0, label, harnessFailedErrors[1])
end

-- ===========================================================================
-- A. Login
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Notebook")
EQ(CommanderNotebookDB.EnableNotebook, true, "A1 defaults applied at ADDON_LOADED")
EQ(CommanderNotebookDB.FrameStyle, "DARK", "A1 a saved setting survives defaults")
EQ(CommanderNotebookDB.SortMode, "updated", "A1 a missing setting is filled in")
CHECK(S.Attached(), "A2 the store is attached at ADDON_LOADED")
EQ(S.Note("n3").notebook, S.DefaultNotebookID(), "A2 attach re-homed the dangling note")
CHECK(CommanderNotebookDB.Notes["n2"] ~= nil, "A2 existing notes survived load")

Fire("PLAYER_LOGIN")
CHECK(SlashCmdList["COMMANDERUI_NOTEBOOK"] ~= nil, "A3 the panel registered its slash command")
EQ(SLASH_COMMANDERUI_NOTEBOOK1, "/cnote", "A3 slash command name")
CHECK(SlashCmdList["COMMANDERNOTEBOOKCAPTURE"] ~= nil, "A3 capture registered its own command")
EQ(SLASH_COMMANDERNOTEBOOKCAPTURE1, "/cnb", "A3 capture command name")

EQ(CommanderNotebookDB.WelcomeWritten, true, "A4 the welcome note is considered once, at login")
CHECK(S.NotebookByName("Field Notes") ~= nil, "A4 the default notebook exists")
for _, note in pairs(CommanderNotebookDB.Notes) do
    CHECK(note.title ~= "Welcome to your notebook",
        "A4 an account that already has notes does not get a welcome note")
end

-- ...and one that has none does. Run against a second, empty store so the
-- fixture above is not disturbed.
do
    local saved = CommanderNotebookDB.Notes
    local savedFlag = CommanderNotebookDB.WelcomeWritten
    CommanderNotebookDB.Notes = {}
    CommanderNotebookDB.WelcomeWritten = nil
    S.Attach(CommanderNotebookDB)
    local welcome = N.EnsureWelcomeNote()
    CHECK(welcome ~= nil, "A5 an empty notebook gets a welcome note")
    EQ(welcome.title, "Welcome to your notebook", "A5 with the expected title")
    CHECK(welcome.pinned == true, "A5 pinned, so it is the first thing seen")
    CHECK(welcome.body:find("/cnb", 1, true) ~= nil, "A5 and it documents quick capture")
    CHECK(N.EnsureWelcomeNote() == nil, "A5 it is never written twice")
    CommanderNotebookDB.Notes = saved
    CommanderNotebookDB.WelcomeWritten = savedFlag
    S.Attach(CommanderNotebookDB)
end

-- WelcomeWritten is view state, not a setting: Restore Defaults must not be
-- able to resurrect the note in a notebook the user has since tidied.
CHECK(CommanderNotebook_Defaults.WelcomeWritten == nil,
    "A6 the welcome flag is not a defaulted setting")

-- Reaching into the window. Rows are pooled and reused, so a row is only the
-- row for a note while it is actually shown.
local function ListRowFor(id)
    for _, widget in ipairs(frames) do
        if rawget(widget, "noteID") == id and widget.__shown then return widget end
    end
end

local function SideRowLabelled(text)
    for _, widget in ipairs(frames) do
        local entry = rawget(widget, "entry")
        if entry and entry.label == text and widget.__shown then return widget end
    end
end

local function ShownListRows()
    local count = 0
    for _, widget in ipairs(frames) do
        if rawget(widget, "noteID") and widget.__shown then count = count + 1 end
    end
    return count
end

-- ===========================================================================
-- B. Building the window
-- ===========================================================================

N.Show()
NoErrors("B1 building the window raised nothing")
local window = _G.CommanderNotebookFrame
CHECK(window ~= nil, "B1 the window exists")
CHECK(window.__shown, "B1 the window is shown")
CHECK(_G.CommanderNotebookBody ~= nil, "B2 the editor exists")
CHECK(_G.CommanderNotebookTitleBox ~= nil, "B2 the title box exists")
CHECK(_G.CommanderNotebookTagBox ~= nil, "B2 the tag box exists")
CHECK(_G.CommanderNotebookSearchBox ~= nil, "B2 the search box exists")
CHECK(_G.CommanderNotebookListScroll ~= nil, "B2 the list scrolls")
CHECK(_G.CommanderNotebookSidebarScroll ~= nil, "B2 the sidebar scrolls")

local body = _G.CommanderNotebookBody
local titleBox = _G.CommanderNotebookTitleBox
local tagBox = _G.CommanderNotebookTagBox
local searchBox = _G.CommanderNotebookSearchBox

-- A5, deferred until the window exists to prove it: the stale source fell
-- back to All Notes rather than to an empty view of a deleted notebook.
CHECK(SideRowLabelled("All Notes") ~= nil, "B3 the sidebar built")
CHECK(SideRowLabelled("NOTEBOOKS") ~= nil, "B3 the notebooks header is there")
CHECK(SideRowLabelled("Raids") ~= nil, "B3 the saved notebook is listed")
CHECK(SideRowLabelled("Trash") ~= nil, "B3 the trash is always listed")
EQ(SideRowLabelled("All Notes").entry.count, 2, "B4 All Notes counts both saved notes")
EQ(ShownListRows(), 2, "B4 both notes have a row")
EQ(window.listCount.__text, "2 notes", "B4 the list says how many")

-- ===========================================================================
-- C. Writing
-- ===========================================================================

local made = N.NewNote()
NoErrors("C1 New Note raised nothing")
CHECK(made ~= nil, "C1 a note was created")
EQ(S.Note(made.id).notebook, S.DefaultNotebookID(), "C1 filed in the current source")
CHECK(titleBox:HasFocus(), "C1 the cursor lands in the title, ready to type")

Type(titleBox, "Arena comp")
Type(body, "RMP opener notes")
CHECK(S.Note(made.id).title == "", "C2 nothing is written until the timer fires")

-- The row's own text updates in place on every keystroke: that is what makes
-- the list feel live without the row jumping out from under the cursor.
local row = ListRowFor(made.id)
CHECK(row ~= nil, "C3 the new note has a row")
EQ(row.title.__text, "Arena comp", "C3 the row title tracks what is being typed")
EQ(row.snippet.__text, "RMP opener notes", "C3 the row snippet tracks it too")

Advance(2)
window.__scripts.OnUpdate(window)
EQ(S.Note(made.id).title, "Arena comp", "C4 the save timer wrote the title")
EQ(S.Note(made.id).body, "RMP opener notes", "C4 and the body")
NoErrors("C4 the save raised nothing")

-- The re-sort is deferred while the writer still has the cursor in the text.
Type(body, "RMP opener notes, second pass")
Advance(2)
window.__scripts.OnUpdate(window)
EQ(S.Note(made.id).body, "RMP opener notes, second pass", "C5 a second save lands")

Type(tagBox, "pvp, arena")
Advance(2)
window.__scripts.OnUpdate(window)
EQ(S.TagString(S.Note(made.id)), "pvp, arena", "C6 tags save through the same path")
Blur(tagBox)
CHECK(SideRowLabelled("pvp") ~= nil, "C6 a brand new tag appears in the sidebar at once")

-- Switching notes must not lose the keystrokes that had not been written yet.
Type(body, "unsaved when I clicked away")
N.OpenToNote("n2")
EQ(S.Note(made.id).body, "unsaved when I clicked away",
    "C7 switching notes flushes first, so nothing typed is lost")
EQ(body.__text, "pull order", "C7 the other note loaded")
NoErrors("C7 switching notes raised nothing")

-- Closing the window is the same promise.
N.OpenToNote(made.id)
Type(body, "typed then closed")
N.Hide()
EQ(S.Note(made.id).body, "typed then closed", "C8 hiding the window flushes")
N.Show()

-- Loading a note fires OnTextChanged with the note's own text. Without the
-- no-op guard in the store, merely READING a note would restamp it and
-- reorder every recently-updated list.
local stampBefore = S.Note("n2").updated
N.OpenToNote("n2")
Advance(2)
window.__scripts.OnUpdate(window)
EQ(S.Note("n2").updated, stampBefore, "C9 opening a note does not count as editing it")

-- A repaint from a menu action must not roll back what is still being typed.
-- Clicking a dropdown does not take focus off the editor, so this is a real
-- sequence, not a contrived one.
N.OpenToNote(made.id)
Type(body, "half a sentence still being")
S.TogglePin(made.id)
N.RefreshAll()
EQ(body.__text, "half a sentence still being",
    "C10 a repaint does not roll back unsaved keystrokes")
Advance(2)
window.__scripts.OnUpdate(window)
EQ(S.Note(made.id).body, "half a sentence still being", "C10 and they still save")
S.TogglePin(made.id)
Type(body, "typed then closed")
Advance(2)
window.__scripts.OnUpdate(window)

-- ===========================================================================
-- D. Searching
-- ===========================================================================

N.SelectSource("all")
Type(searchBox, "typed then closed")
EQ(ShownListRows(), 1, "D1 the search filters the list")
EQ(window.listCount.__text, "1 note", "D1 the count follows the filter, singular")
CHECK(S.Note(made.id) ~= nil, "D1 filtering does not touch notes")

Type(searchBox, "tag:pvp")
EQ(ShownListRows(), 1, "D2 the tag prefix works from the box")

Type(searchBox, "zzzznothing")
EQ(ShownListRows(), 0, "D3 no hits empties the list")
EQ(titleBox.__shown, false, "D3 and clears the page rather than stranding a note")
NoErrors("D3 an empty search result raised nothing")

Type(searchBox, "")
CHECK(ShownListRows() >= 3, "D4 clearing the box brings everything back")

-- Selecting a note that is scrolled out of view brings it into view; a plain
-- refresh (which typing causes constantly) must not move the list at all.
do
    local listScroll = _G.CommanderNotebookListScroll
    local moved = 0
    rawset(listScroll, "SetVerticalScroll", function(_, value)
        moved = moved + 1
        listScroll.__scroll = value
    end)
    rawset(listScroll, "GetVerticalScroll", function() return listScroll.__scroll or 0 end)
    rawset(listScroll, "GetHeight", function() return 40 end)
    rawset(listScroll, "GetVerticalScrollRange", function() return 400 end)

    N.SelectSource("all")
    local rows = S.List({ scope = "all", sort = "updated" })
    local last = rows[#rows]
    moved = 0
    N.OpenToNote(last.id)
    CHECK(moved > 0, "D5 selecting an off-screen note scrolls the list to it")

    moved = 0
    N.RefreshAll()
    EQ(moved, 0, "D5 a plain refresh does not move the list")
end

-- ===========================================================================
-- E. Sources
-- ===========================================================================

local raidsRow = SideRowLabelled("Raids")
Click(raidsRow)
EQ(ShownListRows(), 1, "E1 clicking a notebook narrows to it")
NoErrors("E1 selecting a notebook raised nothing")

-- A new note started from a notebook is filed in that notebook, not dumped in
-- the default where the reader cannot see it.
local inRaids = N.NewNote()
EQ(S.Note(inRaids.id).notebook, "nb-raids", "E2 a new note lands in the open notebook")

-- ...and one started from a tag carries that tag, for the same reason.
N.SelectSource("tag", "pvp")
local tagged = N.NewNote()
CHECK(S.HasTag(S.Note(tagged.id), "pvp"), "E3 a new note started from a tag carries it")
EQ(S.Note(tagged.id).notebook, S.DefaultNotebookID(), "E3 and is filed somewhere real")

local headerRow = SideRowLabelled("NOTEBOOKS")
Click(headerRow)
CHECK(SideRowLabelled("Raids") == nil, "E4 clicking a header collapses its section")
Click(SideRowLabelled("NOTEBOOKS"))
CHECK(SideRowLabelled("Raids") ~= nil, "E4 and expands it again")

-- ===========================================================================
-- F. The trash
-- ===========================================================================

N.SelectSource("all")
local doomed = N.NewNote()
S.SetTitle(doomed.id, "Delete me")
N.OpenToNote(doomed.id)
S.Trash(doomed.id)
N.SelectSource("all")
CHECK(ListRowFor(doomed.id) == nil, "F1 a trashed note leaves the list")
CHECK(S.Note(doomed.id) ~= nil, "F1 but the note is still there")

N.ShowTrash()
CHECK(ListRowFor(doomed.id) ~= nil, "F2 and appears in the trash")
CHECK(window.trashButton.__shown, "F2 Empty Trash appears with the trash")
NoErrors("F2 the trash view raised nothing")

N.OpenToNote(doomed.id)
EQ(body.__enabled, false, "F3 a note in the trash is read-only")
EQ(tagBox.__shown, false, "F3 and its tags cannot be edited")

S.Restore(doomed.id)
N.SelectSource("all")
CHECK(ListRowFor(doomed.id) ~= nil, "F4 restoring brings it back")
CHECK(window.trashButton.__shown == false, "F4 Empty Trash goes away outside the trash")

-- ===========================================================================
-- G. Quick capture
-- ===========================================================================

local before = S.Stats().notes
local captured = N.Capture("healer went right")
NoErrors("G1 capture raised nothing")
CHECK(captured ~= nil, "G1 capture made a note")
EQ(S.NotebookName(captured.notebook), "Quick Notes", "G1 filed in the capture notebook")
CHECK(captured.body:find("healer went right", 1, true) ~= nil, "G1 the line is in it")
EQ(S.Stats().notes, before + 1, "G1 exactly one note was created")

local again = N.Capture("then they rotated")
EQ(again.id, captured.id, "G2 a second capture the same day appends to the same note")
CHECK(again.body:find("healer went right", 1, true) ~= nil, "G2 the first line survived")
CHECK(again.body:find("then they rotated", 1, true) ~= nil, "G2 the second is there too")
EQ(S.Stats().notes, before + 1, "G2 and no second note was made")

N.Capture("   ")
EQ(S.Stats().notes, before + 1, "G3 capturing nothing writes nothing")

SlashCmdList["COMMANDERNOTEBOOKCAPTURE"]("through the slash command")
CHECK(S.Note(captured.id).body:find("through the slash command", 1, true) ~= nil,
    "G4 /cnb reaches the same path")

-- ===========================================================================
-- H. Shift-clicking a link into a note
-- ===========================================================================

local ITEM = "|cffa335ee|Hitem:19019::::::::70::::::::::|h[Thunderfury]|h|r"

N.OpenToNote(made.id)
Type(body, "the drop was ")
local handled = ChatEdit_InsertLink(ITEM)
EQ(handled, true, "H1 the wrapper claims the link when the editor has focus")
CHECK(body.__text:find("Thunderfury", 1, true) ~= nil, "H1 the link went into the note")
EQ(originalInsertReached, 0, "H1 and the chat path was not reached")

Advance(2)
window.__scripts.OnUpdate(window)
local links = S.Links(S.Note(made.id))
EQ(#links, 1, "H2 the note now carries one attachment")
EQ(links[1].label, "Thunderfury", "H2 with a readable label")

body:ClearFocus()
searchBox:SetFocus()
ChatEdit_InsertLink(ITEM)
EQ(originalInsertReached, 1, "H3 with no editor focused the link falls through to chat")
searchBox:ClearFocus()

-- ===========================================================================
-- I. Styling
-- ===========================================================================

CommanderNotebookDB.FrameStyle = "PARCHMENT"
Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
NoErrors("I1 switching to parchment raised nothing")

-- The parchment MUST paint something of its own. A backdrop whose bgFile does
-- not resolve draws its edge and no background, and with the template dressing
-- correctly hidden that is a transparent window with the game world showing
-- through it -- which is exactly what shipped once. The drawn base is the
-- guarantee, so its absence is a failure, not a cosmetic detail.
CHECK(window.parchment ~= nil, "I1 the parchment art frame exists")
CHECK(window.paperBase ~= nil,
    "I1 and it paints a drawn base, so the window is never see-through")
CommanderNotebookDB.FrameStyle = "DARK"
Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
NoErrors("I1 switching back raised nothing")

CommanderNotebookDB.ShowSidebar = false
Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
EQ(window.sidebarPane.__shown, false, "I2 the sidebar can be hidden")
CommanderNotebookDB.ShowSidebar = true
Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
EQ(window.sidebarPane.__shown, true, "I2 and brought back")

CommanderNotebookDB.ShowSnippets = false
CommanderNotebookDB.ShowListTags = false
Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
NoErrors("I3 a compact list raised nothing")
CommanderNotebookDB.ShowSnippets = true
CommanderNotebookDB.ShowListTags = true
Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)

for _, size in ipairs({ "SMALL", "NORMAL", "LARGE" }) do
    CommanderNotebookDB.EditorFontSize = size
    Commander.Notify(COMMANDER_NOTEBOOK_EVENTS.UPDATE)
    NoErrors("I4 font size " .. size .. " resolves to a real font object")
end

-- ===========================================================================
-- J. Stamping where you were
-- ===========================================================================

N.OpenToNote(made.id)
-- The Stamp button is rebuilt per note, so it is found by its label.
local stampButton
for _, widget in ipairs(frames) do
    if widget.__text == "Stamp" and widget.__shown then stampButton = widget end
end
CHECK(stampButton ~= nil, "J1 the Stamp button is on the page")
Click(stampButton)
NoErrors("J1 stamping raised nothing")
local stamped = S.Note(made.id).body
CHECK(stamped:find("Nagrand Arena", 1, true) ~= nil, "J2 the stamp names the zone")
CHECK(stamped:find("Halaa", 1, true) ~= nil, "J2 and the subzone")
CHECK(stamped:find("43.5", 1, true) ~= nil, "J2 and the coordinates")

-- ===========================================================================
-- L. A stamp is a way back (Commander Orders, 1.1.0)
-- ===========================================================================

do
    -- The stamp above kept where it was written
    local context = S.Note(made.id).context
    CHECK(context ~= nil, "L1 the stamp kept a context")
    EQ(context and context.map, 1, "L1 with the map the coordinates are on")
    EQ(context and context.x, 0.435, "L1 and the exact x, not the rounded one in the text")
    EQ(context and context.zone, "Nagrand Arena", "L1 and the zone name")

    -- Commander Orders, as far as Notebook reaches into it. Since Orders 3.1
    -- a map-stamped Go is GoTo(target, opts), recorded as the spec the real
    -- GoTo hands its Add (target and opts merged), plus what the Go button
    -- reads; an old stamp still goes through Import by name.
    local adds, imports = {}, {}
    local orders
    local REASONS = { disabled = "Commander Orders is turned off (/corder)" }
    orders = {
        GoTo = function(target, opts)
            local spec = {}
            for k, v in pairs(target or {}) do spec[k] = v end
            for k, v in pairs(opts or {}) do spec[k] = v end
            adds[#adds + 1] = spec
            if orders.refuse then return nil, orders.refuse end
            return "w1"
        end,
        IsAvailable = function()
            if orders.refuse then return false, orders.refuse end
            return true
        end,
        Reason = function(why) return REASONS[why] or tostring(why) end,
        Import = function(text, opts)
            imports[#imports + 1] = { text = text, opts = opts }
            if orders.ambiguous then
                return 0, { { line = 1, text = text, message = "\"" .. "Alterac" .. "\" is more than one zone",
                    candidates = { { line = "/way #1416 42.50 61.20 x" }, { line = "/way #1459 42.50 61.20 x" } } } }
            end
            return 1, {}
        end,
    }
    CommanderOrders = orders

    local function ActionButton(label)
        local found
        for _, widget in ipairs(frames) do
            if widget.__text == label and widget.__shown and widget.__template == "UIPanelButtonTemplate" then
                found = widget
            end
        end
        return found
    end

    N.OpenToNote(made.id)
    local go = ActionButton("Go")
    CHECK(go ~= nil, "L2 a stamped note offers Go")
    printLog = {}
    Click(go)
    NoErrors("L2 Go raised nothing")
    EQ(#adds, 1, "L2 one waypoint asked for")
    local spec = adds[1] or {}
    EQ(spec.map, 1, "L2 on the stamp's own map")
    EQ(spec.x, 0.435, "L2 at its exact x")
    EQ(spec.y, 0.612, "L2 and y")
    EQ(spec.title, "Arena comp", "L2 titled with the note")
    EQ(spec.source, "Notebook", "L2 source Notebook")
    EQ(spec.key, "note:" .. made.id, "L2 keyed by the note, so Go twice is one waypoint")
    EQ(spec.setArrow, true, "L2 and the arrow goes there")
    -- Orders 3.1 (SPEC 5): the one confirmation is Orders' own "Waypoint
    -- set" (GoTo, not silent); the Notebook no longer prints one of its own
    CHECK(not spec.silent and #printLog == 0, "L2 a one-line confirmation (Orders' own)", printLog[#printLog])
    EQ(spec.icon, "NOTE", "L2 in the Notebook's tint (Orders' NOTE icon)")
    CHECK(go and rawget(go, "_goOpts") ~= nil, "L2 the Go is Commander Orders' Go button")

    -- Go sits right after Stamp, and the row still fits the page
    local widths, used, shown = {}, 0, 0
    for _, label in ipairs({ "Pin", "Unpin", "Stamp", "Go", "Duplicate", "Move To...", "Delete" }) do
        local button = ActionButton(label)
        if button then rawset(button, "SetWidth", function(b, w) widths[b] = w end) end
    end
    N.OpenToNote(made.id)
    for button, w in pairs(widths) do
        if button.__shown then used, shown = used + w, shown + 1 end
    end
    used = used + 5 * (shown - 1)
    EQ(shown, 6, "L3 six verbs on a stamped note")
    CHECK(used <= 456, "L3 and they fit the 456 px action row", used)

    -- The note's menu has it too
    menuCaptured = {}
    Click(ActionButton("Move To..."))
    local entry
    for _, info in ipairs(menuCaptured) do
        if info.text == "Go To This Note" then entry = info end
    end
    CHECK(entry ~= nil, "L4 the note menu offers Go To This Note")
    if entry then entry.func() end
    EQ(#adds, 2, "L4 and it asks for the same waypoint")

    -- An old stamp: no map, the zone by name through Orders' /way resolver
    local oldNote = S.CreateNote({ title = "Rare spawn",
        body = "-- Devinp (70) | Halaa, Nagrand 42.5, 61.2 | 04 Oct 2026, 13:50" })
    N.OpenToNote(oldNote.id)
    go = ActionButton("Go")
    CHECK(go ~= nil, "L5 an old stamp still offers Go")
    adds, imports = {}, {}
    Click(go)
    EQ(#adds, 0, "L5 nothing added by map id: it has none")
    EQ(#imports, 1, "L5 the line goes through Orders' /way resolver")
    EQ(imports[1] and imports[1].text, "/way Nagrand 42.5 61.2 Rare spawn", "L5 as a /way line by zone name")
    EQ(imports[1] and imports[1].opts and imports[1].opts.source, "Notebook", "L5 under source Notebook")
    -- The Notebook's own "Waypoint set" for it follows Orders' Announce In
    -- Chat: said while it is on (or Orders keeps no settings), never off
    printLog = {}
    Click(go)
    CHECK(PrintedMatching("Waypoint set: Rare spawn"), "L5 found: \"Waypoint set\"", printLog[1])
    CommanderOrdersDB = { Announce = false }
    printLog = {}
    Click(go)
    EQ(#imports, 3, "L5 Announce In Chat off: the waypoint all the same")
    EQ(#printLog, 0, "L5 ...and no line of the Notebook's", printLog[1])
    CommanderOrdersDB = { Announce = true }
    printLog = {}
    Click(go)
    CHECK(PrintedMatching("Waypoint set: Rare spawn"), "L5 back on: said again", printLog[1])
    CommanderOrdersDB = nil
    orders.ambiguous = true
    printLog = {}
    Click(go)
    CHECK(PrintedMatching("more than one zone"), "L5 a name that is not one zone says so", printLog[1])
    CHECK(PrintedMatching("/way #1416"), "L5 and lists the candidates with their /way #id forms")
    orders.ambiguous = nil

    -- No stamp, no Go, no menu entry
    local plain = S.CreateNote({ title = "Plain", body = "just words" })
    N.OpenToNote(plain.id)
    CHECK(ActionButton("Go") == nil, "L6 a note with no place has no Go")
    menuCaptured = {}
    Click(ActionButton("Move To..."))
    local offered = false
    for _, info in ipairs(menuCaptured) do
        if info.text == "Go To This Note" then offered = true end
    end
    CHECK(not offered, "L6 and no menu entry")

    -- Orders switched off
    orders.refuse = "disabled"
    N.OpenToNote(made.id)
    printLog = {}
    Click(ActionButton("Go"))
    CHECK(PrintedMatching("turned off"), "L7 Orders off: it says so", printLog[1])
    orders.refuse = nil

    -- Orders not loaded: the spot as a /way line, so the button never does nothing
    CommanderOrders = nil
    printLog = {}
    Click(ActionButton("Go"))
    CHECK(PrintedMatching("/way #1 43%.50 61%.20 Arena comp"), "L8 no Orders: the /way line", printLog[1])
    N.OpenToNote(oldNote.id)
    printLog = {}
    Click(ActionButton("Go"))
    CHECK(PrintedMatching("/way Nagrand 42%.5 61%.2 Rare spawn"), "L8 for an old stamp too, by name", printLog[1])
    NoErrors("L8 no Orders raised nothing")

    -- L10 (1.2.0, Orders 3.1): one Go button follows the open note, and an
    -- old name-only stamp keeps the plain Go that asks Orders by name
    CommanderOrders = orders
    adds = {}
    local second = S.CreateNote({ title = "Second spot", body = "x" })
    S.SetContext(second.id, { map = 1, x = 0.25, y = 0.75, zone = "Nagrand Arena" })
    N.OpenToNote(made.id)
    local goA = ActionButton("Go")
    N.OpenToNote(second.id)
    local goB = ActionButton("Go")
    CHECK(goA ~= nil and goA == goB, "L10 one Go button, re-pointed at whichever note is open")
    Click(goB)
    EQ(adds[1] and adds[1].key, "note:" .. second.id, "L10 its key follows the open note")
    EQ(adds[1] and adds[1].x, 0.25, "L10 ...and so does its place")
    N.OpenToNote(oldNote and oldNote.id or made.id)
    local plainGo = ActionButton("Go")
    CHECK(plainGo ~= nil and rawget(plainGo, "_goOpts") == nil and plainGo ~= goA,
        "L10 an old stamp's Go is the plain button (Orders' /way by name)")
    N.OpenToNote(plain.id)
    CHECK(ActionButton("Go") == nil and not goA.__shown, "L10 a note with no place hides the Go button")
    orders.refuse = "disabled"
    N.OpenToNote(made.id)
    local reasonGo = ActionButton("Go")
    if reasonGo and reasonGo.Refresh then reasonGo:Refresh() end
    EQ(reasonGo and reasonGo._goReason, "disabled", "L10 greyed while Orders is off, the reason kept for its tooltip")
    orders.refuse = nil
    S.Trash(second.id)
    CommanderOrders = nil
    NoErrors("L10 raised nothing")

    -- A note stamped as it is made keeps its place as well
    CommanderNotebookDB.StampNewNotes = true
    local fresh = N.NewNote()
    EQ(S.Note(fresh.id).context and S.Note(fresh.id).context.map, 1, "L9 Stamp New Notes keeps the place too")
    CommanderNotebookDB.StampNewNotes = false
    S.Trash(fresh.id)
    S.Trash(plain.id)
    S.Trash(oldNote.id)
    NoErrors("L9 raised nothing")
end

-- ===========================================================================
-- K. Notebooks through their dialogs
-- ===========================================================================

StaticPopup_Show("COMMANDER_NOTEBOOK_NEWBOOK")
AcceptPopup("COMMANDER_NOTEBOOK_NEWBOOK", "Keys")
NoErrors("K1 creating a notebook raised nothing")
CHECK(S.NotebookByName("Keys") ~= nil, "K1 the notebook was created")
CHECK(SideRowLabelled("Keys") ~= nil, "K1 and is in the sidebar")

local keysID = S.NotebookByName("Keys")
local keyNote = N.NewNote(keysID)
StaticPopup_Show("COMMANDER_NOTEBOOK_DELETEBOOK", "Keys", nil, keysID)
AcceptPopup("COMMANDER_NOTEBOOK_DELETEBOOK")
CHECK(S.Notebook(keysID) == nil, "K2 the notebook was deleted")
CHECK(S.Note(keyNote.id) ~= nil, "K2 its note was NOT deleted")
EQ(S.Note(keyNote.id).notebook, S.DefaultNotebookID(), "K2 the note moved to the default")
NoErrors("K2 deleting a notebook raised nothing")

-- ===========================================================================
-- R. Restore Defaults cannot delete writing
--
-- The notes share a SavedVariables table with the settings, so this is the
-- one wiring mistake that would be unrecoverable for a user. It is checked
-- against the real defaults table and through the real slash path.
-- ===========================================================================

for _, key in ipairs({ "Notes", "Notebooks", "NextID", "LastNote", "LastScope", "LastKey" }) do
    CHECK(CommanderNotebook_Defaults[key] == nil,
        "R1 the defaults table does not mention " .. key)
end

local notesBefore = S.Stats().notes
local booksBefore = S.Stats().notebooks
CommanderNotebookDB.FrameStyle = "DARK"
SlashCmdList["COMMANDERUI_NOTEBOOK"]("reset")
EQ(S.Stats().notes, notesBefore, "R2 Restore Defaults kept every note")
EQ(S.Stats().notebooks, booksBefore, "R2 and every notebook")
EQ(S.Note(made.id).title, "Arena comp", "R2 and the writing inside them")
EQ(CommanderNotebookDB.FrameStyle, "PARCHMENT", "R2 while actually resetting the settings")
NoErrors("R2 Restore Defaults raised nothing")

-- ===========================================================================
-- S. Every slash entry point
-- ===========================================================================

for _, sub in ipairs({ "", "new", "search", "stats", "trash", "settings", "nonsense" }) do
    SlashCmdList["COMMANDERUI_NOTEBOOK"](sub)
    NoErrors("S1 /cnote " .. (sub == "" and "(bare)" or sub) .. " raised nothing")
end

CommanderNotebook_Toggle()
CommanderNotebook_Toggle()
CommanderNotebook_Show()
CommanderNotebook_FocusSearch()
CommanderNotebook_ShowTrash()
CommanderNotebook_PrintStats()
CommanderNotebook_Flush()
CHECK(CommanderNotebook_OpenToNote("n-does-not-exist") == false,
    "S2 opening a note that does not exist is refused, not an error")
NoErrors("S2 the public globals all run")

Fire("PLAYER_LOGOUT")
NoErrors("S3 logout flushes without raising")

-- ===========================================================================

if fails > 0 then
    io.write(string.format("\n%d/%d checks FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("notebook_ui_harness: %d checks passed\n", checks))
