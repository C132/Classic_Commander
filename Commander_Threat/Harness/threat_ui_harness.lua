-- Commander Threat UI smoke harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all three Commander_Threat files under a permissive WoW mock (the
-- Meters harness preamble + a fixture-driven unit/threat/nameplate API),
-- then drives login, the settings panel, role switching, live sampling in
-- all three roles, warnings, the pinned-self row, the test fight, and
-- visibility. Catches nil-global calls, bad signatures, and font traps
-- without a client.
--
--   /opt/homebrew/bin/luajit threat_ui_harness.lua

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
-- WoW mock (the Meters harness widget machinery)
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
local frames = {}
local eventRegistry = {}

local NUMERIC_GETTERS = {
    GetWidth = 240, GetHeight = 0, GetScale = 1, GetEffectiveScale = 1,
    GetFrameLevel = 2, GetLeft = 0, GetBottom = 0, GetTop = 0, GetRight = 0,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0, GetStringWidth = 10,
    GetID = 1, GetNumPoints = 1, GetAlpha = 1,
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
WorldFrame = NewWidget("Frame", "WorldFrame")
UISpecialFrames = {}
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack

GameFontNormal = NewWidget("Font")
GameFontNormalLarge = NewWidget("Font")
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

-- ---------------------------------------------------------------------------
-- Fixture-driven unit / threat / nameplate API
-- ---------------------------------------------------------------------------

-- units[token] = { guid, name, class, hostile }
local units = {}
-- threatPairs[unit .. "@" .. mob] = { tanking, status, scaled, raw, value }
local threatPairs = {}
local combat = false
local grouped, inRaid, groupSize = false, false, 0
local plateTokens = {}

function GetRealmName() return "TestRealm" end
function UnitExists(u) return units[u] ~= nil end
function UnitName(u) local d = units[u]; return d and d.name end
function UnitClass(u)
    local d = units[u]
    if d and d.class then return d.class, d.class end
end
function UnitGUID(u) local d = units[u]; return d and d.guid end
function UnitIsUnit(a, b)
    if a == b then return true end
    local da, db2 = units[a], units[b]
    return (da and db2 and da.guid == db2.guid) or false
end
function UnitCanAttack(_, u)
    local d = units[u]
    return (d and d.hostile) or false
end
function UnitIsDeadOrGhost() return false end
function UnitPlayerOrPetInParty(u)
    local d = units[u]
    return (d and d.inGroup) or false
end
function UnitPlayerOrPetInRaid(u)
    local d = units[u]
    return (d and d.inGroup and inRaid) or false
end
function UnitDetailedThreatSituation(u, mob)
    local t = threatPairs[u .. "@" .. mob]
    if not t then return nil end
    return t[1], t[2], t[3], t[4], t[5]
end
function UnitThreatSituation(u, mob)
    local t = threatPairs[u .. "@" .. mob]
    return t and t[2] or nil
end
function InCombatLockdown() return combat end
function IsInRaid() return inRaid end
function IsInGroup() return grouped end
function GetNumGroupMembers() return groupSize end
C_NamePlate = {
    GetNamePlates = function()
        local out = {}
        for _, token in ipairs(plateTokens) do
            out[#out + 1] = { namePlateUnitToken = token }
        end
        return out
    end,
}
function GetCursorPosition() return 0, 0 end
function IsInInstance() return false, "none" end
function GetInstanceInfo() return "Azeroth", "none", 0, "", 5, 0, false, 0, 5 end

RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 },
    PRIEST = { r = 1, g = 1, b = 1 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
SlashCmdList = {}

-- Meters external-mode contract mock (records the cross-addon calls)
local metersEmbed = { spec = nil, shown = {}, retired = {} }
function CommanderMeters_RegisterExternalMode(spec)
    metersEmbed.spec = spec
    return true
end
function CommanderMeters_RetireExternalMode(key)
    metersEmbed.retired[#metersEmbed.retired + 1] = key
    if metersEmbed.spec and metersEmbed.spec.key == key then metersEmbed.spec = nil end
end
function CommanderMeters_ShowExternalPane(key)
    metersEmbed.shown[#metersEmbed.shown + 1] = key
    return true
end

-- Threat fixture helpers: (unit, mob, tanking, status, scaled, raw, value)
local function SetThreat(u, mob, tanking, status, scaled, raw, value)
    threatPairs[u .. "@" .. mob] = { tanking, status, scaled, raw, value }
end
local function ClearThreat()
    for k in pairs(threatPairs) do threatPairs[k] = nil end
end

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

-- Suite palette fixture (the Console global shape) so the accent dropdown
-- and AccentByKey resolution both execute
CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}
-- Saved variables from a "previous session": a suite accent key + a role
-- for another character, so login resolves the accent through Console and
-- this character still defaults to DAMAGE
CommanderThreatDB = {
    AccentColor = "FEL",
    RoleByChar = { ["Oldalt-TestRealm"] = "HEALER" },
}

units.player = { guid = "P-me", name = "Devinp", class = "WARRIOR" }

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Threat/CommanderThreatDB.lua")
Load(ADDONS .. "/Commander_Threat/CommanderThreatEngine.lua")
Load(ADDONS .. "/Commander_Threat/CommanderThreat.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

local function TextShownSomewhere(text)
    for _, fs in ipairs(allFontStrings) do
        -- SetText coerces numbers on the real client; compare likewise
        if fs.__text ~= nil and tostring(fs.__text) == text then return true end
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

-- ===========================================================================
-- Login (solo, out of combat)
-- ===========================================================================

Fire("ADDON_LOADED", "Commander_Threat")
Fire("PLAYER_LOGIN")

CHECK(#harnessFailedErrors == 0, "C: login clean", harnessFailedErrors[1])
CHECK(CommanderThreatDB.EnableThreat == true and CommanderThreatDB.WarnAt == 80,
    "C: defaults applied")
CHECK(CommanderThreatDB.DBVersion == 1, "C: schema version stamped")
CHECK(CommanderThreatDB.AccentColor == "FEL", "C: saved suite accent survives")
CHECK(CommanderThreatDB.RoleByChar["Oldalt-TestRealm"] == "HEALER",
    "C: other characters' roles untouched")
CHECK(CommanderThreat_GetRole() == "DAMAGE", "C: this character defaults to Damage")
CHECK(SlashCmdList.COMMANDERUI_THREAT ~= nil, "C: slash registered")
CHECK(_G.SLASH_COMMANDERUI_THREAT1 == "/cthreat" and _G.SLASH_COMMANDERUI_THREAT2 == "/ct",
    "C: slash aliases /cthreat + /ct")
CHECK(_G.CommanderThreatFrame ~= nil, "C: board created")

do
    local found
    for _, info in ipairs(Commander.GetModules()) do
        if info.key == "Threat" then found = info end
    end
    CHECK(found ~= nil, "C: module in Commander registry")
    CHECK(found and found.slash == "/cthreat", "C: registry slash")
end

CHECK(#allFontStrings > 0, "C: fontstrings created (SetFont flags all valid)")

local root = _G.CommanderThreatFrame
RunTickers()
CHECK(root.__shown == false, "C: idle board hidden (Only In Combat)")

-- Role set/get is per character
CommanderThreat_SetRole("TANK")
CHECK(CommanderThreatDB.RoleByChar["Devinp-TestRealm"] == "TANK", "C: role stored per character")
CHECK(#harnessFailedErrors == 0, "C: role-change apply clean", harnessFailedErrors[1])
CommanderThreat_SetRole("DAMAGE")

-- The board's role tag opens the three-role menu (found by its marker —
-- blind-clicking every button would set off the panel's Test Board)
do
    local roleBtn
    for _, f in ipairs(frames) do
        if f.headerRole == "role" then roleBtn = f end
    end
    CHECK(roleBtn ~= nil, "C: board role tag found")
    if roleBtn then
        menuCaptured = {}
        roleBtn.__scripts.OnClick(roleBtn)
    end
    CHECK(#menuCaptured == 3 and menuCaptured[1].text == "Tank",
        "C: board role menu offers the three roles", #menuCaptured)
    if roleBtn then
        for _, info in ipairs(menuCaptured) do
            if info.text == "Healer" then info.func() end
        end
        CHECK(CommanderThreat_GetRole() == "HEALER", "C: menu switches the role")
        CommanderThreat_SetRole("DAMAGE")
    end
end

-- ===========================================================================
-- Live party fight, Damage role
-- ===========================================================================

units.party1 = { guid = "P-tank", name = "Brakk", class = "WARRIOR", inGroup = true }
units.target = { guid = "C-mob1", name = "Deviate Guardian", hostile = true }
units.pet = nil
grouped, groupSize = true, 2
combat = true
Fire("GROUP_ROSTER_UPDATE")

SetThreat("party1", "target", true, 3, 100, 100, 100000)
SetThreat("player", "target", false, 0, 55, 60, 60000)
RunTickers()

CHECK(#harnessFailedErrors == 0, "C: live repaint clean", harnessFailedErrors[1])
CHECK(root.__shown == true, "C: board shown in combat")
CHECK(TextShownSomewhere("Brakk"), "C: tank bar painted")
CHECK(TextShownSomewhere("DEVIATE GUARDIAN"), "C: mob named in the header")
CHECK(TextShownSomewhere("TO PULL"), "C: damage headline label")
CHECK(TextShownSomewhere("55%"), "C: player pull percentage painted")
CHECK(TextMatching("HOLDER · ") ~= nil, "C: damage footer names the holder", TextMatching("HOLDER"))

-- Crossing the threshold fires the klaxon exactly once
local before = KlaxonCount()
SetThreat("player", "target", false, 1, 85, 93, 93000)
Advance(1)
CHECK(KlaxonCount() == before + 1, "C: pull warning klaxon fired once", KlaxonCount() - before)
Advance(2)
CHECK(KlaxonCount() == before + 1, "C: warning is an edge, not a level")

-- Taking aggro fires the loud alert (after the per-type gap)
before = KlaxonCount()
Advance(3)
SetThreat("player", "target", true, 3, 100, 115, 115000)
SetThreat("party1", "target", false, 0, 80, 87, 100000)
Advance(1)
CHECK(KlaxonCount() == before + 1, "C: aggro-gained klaxon fired")
CHECK(TextShownSomewhere("AGGRO"), "C: damage headline flips to AGGRO")

-- Vignette + header flash decay paths execute
do
    local hadUpdate = false
    for _, f in ipairs(frames) do
        if f.__scripts.OnUpdate then
            f.__scripts.OnUpdate(f, 0.3)
            hadUpdate = true
        end
    end
    CHECK(hadUpdate, "C: flash decay drivers ran")
    CHECK(#harnessFailedErrors == 0, "C: decay clean", harnessFailedErrors[1])
end

-- ===========================================================================
-- Tank role: chase, loose mobs, loss
-- ===========================================================================

SlashCmdList.COMMANDERUI_THREAT("tank")
CHECK(CommanderThreat_GetRole() == "TANK", "C: /cthreat tank switches the role")

SetThreat("player", "target", true, 3, 100, 100, 120000)
SetThreat("party1", "target", false, 0, 60, 66, 79000)
-- Nameplates: two on the player, one loose on Brakk
units.nameplate1 = { guid = "C-mob1", name = "Deviate Guardian", hostile = true }
units.nameplate1target = { guid = "P-me", name = "Devinp" }
units.nameplate2 = { guid = "C-mob2", name = "Deviate Slayer", hostile = true }
units.nameplate2target = { guid = "P-me", name = "Devinp" }
units.nameplate3 = { guid = "C-mob3", name = "Deviate Stinger", hostile = true }
units.nameplate3target = { guid = "P-tank", name = "Brakk", inGroup = true }
plateTokens = { "nameplate1", "nameplate2", "nameplate3" }
SetThreat("player", "nameplate1", true, 3, 100, 100, 120000)
SetThreat("player", "nameplate2", true, 3, 100, 100, 50000)
SetThreat("player", "nameplate3", false, 0, 30, 33, 9000)

Advance(1)
CHECK(#harnessFailedErrors == 0, "C: tank repaint clean", harnessFailedErrors[1])
CHECK(TextShownSomewhere("SECURE"), "C: tank headline reads SECURE")
CHECK(TextMatching("CHASE · ") ~= nil, "C: tank headline names the chaser")
CHECK(TextMatching("HELD 2/3") ~= nil, "C: tank footer counts held mobs", TextMatching("HELD"))
CHECK(TextMatching("LOOSE 1") ~= nil, "C: tank footer flags the loose mob")

-- The chaser crossing the line fires the chase warning
before = KlaxonCount()
Advance(3)
SetThreat("party1", "target", false, 1, 85, 93, 111000)
Advance(1)
CHECK(KlaxonCount() == before + 1, "C: chase warning klaxon fired")

-- Losing the mob (still contested) fires the loss alert
before = KlaxonCount()
Advance(3)
SetThreat("player", "target", false, 1, 90, 91, 111000)
SetThreat("party1", "target", true, 3, 100, 100, 122000)
Advance(1)
CHECK(KlaxonCount() == before + 1, "C: aggro-lost klaxon fired")
CHECK(TextShownSomewhere("NOT TANKING"), "C: tank headline flips to NOT TANKING")

-- ===========================================================================
-- Healer role: worst-mob sweep + inbound
-- ===========================================================================

SlashCmdList.COMMANDERUI_THREAT("healer")
CHECK(CommanderThreat_GetRole() == "HEALER", "C: /cthreat healer switches the role")

ClearThreat()
SetThreat("party1", "target", true, 3, 100, 100, 122000)
SetThreat("player", "target", false, 0, 40, 44, 49000)
SetThreat("player", "nameplate1", false, 0, 40, 44, 49000)
SetThreat("player", "nameplate2", false, 1, 88, 97, 44000)
SetThreat("player", "nameplate3", false, 0, 10, 11, 4000)
units.nameplate1target = { guid = "P-tank", name = "Brakk", inGroup = true }
units.nameplate2target = { guid = "P-tank", name = "Brakk", inGroup = true }

before = KlaxonCount()
Advance(4)
CHECK(#harnessFailedErrors == 0, "C: healer repaint clean", harnessFailedErrors[1])
CHECK(TextShownSomewhere("88%"), "C: healer headline shows the WORST mob, not the target")
CHECK(TextMatching("PEAK · DEVIATE SLAYER") ~= nil, "C: healer peak names the hot mob",
    TextMatching("PEAK"))
CHECK(KlaxonCount() == before + 1, "C: healer warned off the worst mob")

-- A mob turning to the healer: INBOUND
before = KlaxonCount()
Advance(3)
units.nameplate2target = { guid = "P-me", name = "Devinp" }
Advance(1)
CHECK(KlaxonCount() == before + 1, "C: inbound klaxon fired")
CHECK(TextShownSomewhere("INBOUND"), "C: healer status reads INBOUND")
CHECK(TextMatching("INBOUND · DEVIATE SLAYER") ~= nil, "C: healer footer names the inbound mob")

-- ===========================================================================
-- Pinned self in a deep raid list
-- ===========================================================================

SlashCmdList.COMMANDERUI_THREAT("damage")
ClearThreat()
plateTokens = {}
inRaid, grouped, groupSize = true, true, 12
for i = 1, 12 do
    local guid = (i == 3) and "P-me" or ("P-raid" .. i)
    local name = (i == 3) and "Devinp" or ("Raider" .. i)
    units["raid" .. i] = { guid = guid, name = name, class = "ROGUE", inGroup = true }
    -- Descending threat: raid1 tops the list, the player (raid3) sits last
    local value = (i == 3) and 5000 or ((14 - i) * 10000)
    SetThreat("raid" .. i, "target", i == 1, i == 1 and 3 or 0,
        i == 1 and 100 or (value / 130000 * 100 / 1.1), value / 130000 * 100, value * 100)
end
Fire("GROUP_ROSTER_UPDATE")
Advance(1)
CHECK(#harnessFailedErrors == 0, "C: raid repaint clean", harnessFailedErrors[1])
CHECK(TextShownSomewhere("12"), "C: player pinned into the last slot with the real rank")
CHECK(TextShownSomewhere("Devinp"), "C: pinned row is the player")

-- Wheel scroll clamps and repaints
do
    local rowsFrameWidget
    for _, f in ipairs(frames) do
        if f.__scripts.OnMouseWheel then rowsFrameWidget = f end
    end
    CHECK(rowsFrameWidget ~= nil, "C: rows frame wheels")
    if rowsFrameWidget then
        rowsFrameWidget.__scripts.OnMouseWheel(rowsFrameWidget, -1)
        rowsFrameWidget.__scripts.OnMouseWheel(rowsFrameWidget, 1)
        rowsFrameWidget.__scripts.OnMouseWheel(rowsFrameWidget, 1)
        CHECK(#harnessFailedErrors == 0, "C: wheel scroll clean", harnessFailedErrors[1])
    end
end

-- ===========================================================================
-- Combat ends: rows clear, board hides
-- ===========================================================================

ClearThreat()
combat = false
Fire("PLAYER_REGEN_ENABLED")
Advance(1)
CHECK(root.__shown == false, "C: board hides after the lists clear")

-- Always-on mode keeps it up
CommanderThreatDB.CombatOnly = false
Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
CHECK(root.__shown == true, "C: Only In Combat off keeps the board shown")
CHECK(TextShownSomewhere("No threat data"), "C: empty board says so")
CommanderThreatDB.CombatOnly = true
Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
CHECK(root.__shown == false, "C: visibility restored")

-- ===========================================================================
-- Test fight: the full alert chain per role, then a clean exit
-- ===========================================================================

inRaid, grouped, groupSize = false, false, 0
units.target = nil
before = KlaxonCount()
SlashCmdList.COMMANDERUI_THREAT("test")
CHECK(root.__shown == true, "C: test shows the board")
CHECK(PrintedMatching("test fight running"), "C: test announces itself")
Advance(13)
CHECK(#harnessFailedErrors == 0, "C: test fight clean", harnessFailedErrors[1])
CHECK(KlaxonCount() >= before + 2, "C: damage test walked warn + aggro",
    KlaxonCount() - before)
CHECK(PrintedMatching("test complete"), "C: test announced completion")
CHECK(root.__shown == false, "C: board hides after the test")

SlashCmdList.COMMANDERUI_THREAT("tank")
before = KlaxonCount()
SlashCmdList.COMMANDERUI_THREAT("test")
Advance(13)
CHECK(KlaxonCount() >= before + 2, "C: tank test walked chase + loss",
    KlaxonCount() - before)

SlashCmdList.COMMANDERUI_THREAT("healer")
before = KlaxonCount()
SlashCmdList.COMMANDERUI_THREAT("test")
Advance(13)
CHECK(KlaxonCount() >= before + 2, "C: healer test walked warn + inbound",
    KlaxonCount() - before)
CHECK(#harnessFailedErrors == 0, "C: role tests clean", harnessFailedErrors[1])

-- ===========================================================================
-- Restore Defaults keeps roles
-- ===========================================================================

CommanderThreatDB.WarnAt = 65
SlashCmdList.COMMANDERUI_THREAT("reset")
CHECK(CommanderThreatDB.WarnAt == 80, "C: reset restores settings")
CHECK(CommanderThreatDB.RoleByChar["Devinp-TestRealm"] == "HEALER",
    "C: reset keeps character roles")
CHECK(#harnessFailedErrors == 0, "C: reset clean", harnessFailedErrors[1])

-- Unlocking forces the board visible for placement
CommanderThreatDB.HudLocked = false
Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
CHECK(root.__shown == true, "C: unlocked board forced visible")
CommanderThreatDB.HudLocked = true
Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)

-- ===========================================================================
-- Meters embed: registration, board retirement, provider rows, degradation
-- ===========================================================================

-- Back to a live damage-role party fight so the provider has rows to serve
SlashCmdList.COMMANDERUI_THREAT("damage")
units.target = { guid = "C-mob1", name = "Deviate Guardian", hostile = true }
combat = true
ClearThreat()
SetThreat("party1", "target", true, 3, 100, 100, 100000)
SetThreat("player", "target", false, 0, 55, 60, 60000)
inRaid, grouped, groupSize = false, true, 2
Fire("GROUP_ROSTER_UPDATE")
Advance(1)
CHECK(root.__shown == true, "C: standalone board up before the embed")

-- Enable through the panel path (DB write + toggle hook + notify)
CommanderThreatDB.MetersEmbed = true
CommanderThreat_EmbedToggled(true)
Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
CHECK(metersEmbed.spec ~= nil and metersEmbed.spec.key == "THREAT",
    "C: embed registers the THREAT mode with Meters")
CHECK(metersEmbed.shown[#metersEmbed.shown] == "THREAT",
    "C: enabling opens Meters' threat pane")
Advance(1)
CHECK(root.__shown == false, "C: standalone board retires while embedded (mid-combat)")

-- The provider serves Meters-shaped display rows from live engine data
do
    local rows, n = metersEmbed.spec.collect(0)
    CHECK(n == 2, "C: provider row count", n)
    CHECK(rows[1].name == "Brakk" and rows[1].valueText == "100%",
        "C: provider top row is the holder at 100%")
    CHECK(rows[2].valueText == "55%", "C: provider carries scaled % in the value column")
    CHECK(rows[2].barFrac and math.abs(rows[2].barFrac - 0.55) < 0.001,
        "C: provider bar fraction keeps the pull-point encoding")
    CHECK(metersEmbed.spec.caption() == "DEVIATE GUARDIAN",
        "C: provider caption names the mob", metersEmbed.spec.caption())
    CHECK(metersEmbed.spec.empty == "No threat data", "C: provider empty line set")
end

-- Warnings keep firing while embedded — only the surface moved
before = KlaxonCount()
Advance(3)
SetThreat("player", "target", false, 1, 85, 93, 93000)
Advance(1)
CHECK(KlaxonCount() == before + 1, "C: pull warning still fires while embedded")
CHECK(root.__shown == false, "C: a warning does not resurrect the board")

-- Disabling retires the mode and brings the board back
CommanderThreatDB.MetersEmbed = false
CommanderThreat_EmbedToggled(false)
Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
CHECK(metersEmbed.retired[#metersEmbed.retired] == "THREAT",
    "C: disabling retires the Meters mode")
Advance(1)
CHECK(root.__shown == true, "C: standalone board returns")

-- Meters absent: the saved setting degrades to the standalone board
do
    local savedReg = CommanderMeters_RegisterExternalMode
    local savedShow = CommanderMeters_ShowExternalPane
    local savedRet = CommanderMeters_RetireExternalMode
    CommanderMeters_RegisterExternalMode = nil
    CommanderMeters_ShowExternalPane = nil
    CommanderMeters_RetireExternalMode = nil
    CommanderThreatDB.MetersEmbed = true
    CommanderThreat_EmbedToggled(true)
    Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
    Advance(1)
    CHECK(root.__shown == true, "C: Meters absent — standalone board stays")
    CommanderThreatDB.MetersEmbed = false
    CommanderMeters_RegisterExternalMode = savedReg
    CommanderMeters_ShowExternalPane = savedShow
    CommanderMeters_RetireExternalMode = savedRet
    Commander.Notify(COMMANDER_THREAT_EVENTS.UPDATE)
end
CHECK(#harnessFailedErrors == 0, "C: embed cycle clean", harnessFailedErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
