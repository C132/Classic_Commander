-- Commander Meters UI smoke harness (luajit).
-- Loads the REAL shared framework (CommanderSettingsUI.lua, CommanderEvents.lua)
-- plus all three Commander_Meters files under a permissive WoW mock, then
-- drives login, the settings panel, slash commands, menus, the repaint loop,
-- fight transitions, and resets. Catches nil-global calls, bad signatures,
-- and template/font traps without a client.

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
        local fn = function(s, _, layer, _, sublevel)
            local t = NewWidget("Texture")
            t.__parent, t.__layer, t.__sublevel = s, layer, sublevel or 0
            return t
        end
        rawset(self, key, fn)
        return fn
    end
    -- Layout recording (the renderer resolves these into rectangles)
    if key == "SetPoint" then
        local fn = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            -- Re-anchoring an existing point replaces it, as the client does
            for i = #s.__points, 1, -1 do
                if s.__points[i].point == point then table.remove(s.__points, i) end
            end
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end
        rawset(self, key, fn)
        return fn
    end
    if key == "ClearAllPoints" then
        local fn = function(s) s.__points = {}; s.__allPoints = nil end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAllPoints" then
        local fn = function(s, rel) s.__allPoints = rel or s.__parent or true end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetJustifyH" then
        local fn = function(s, j) s.__justify = j end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetTexture" then
        local fn = function(s, tex) s.__texture = tex end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetAlpha" then
        local fn = function(s, a) s.__alpha = a end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetHeight" then
        local fn = function(s, h) s.__h = h end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetRotation" then
        local fn = function(s, r) s.__rotation = r end
        rawset(self, key, fn)
        return fn
    end
    if key == "SetCooldown" then
        local fn = function(s, start, dur) s.__cdStart, s.__cdDur = start, dur end
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
    if _G.__widgets then _G.__widgets[#_G.__widgets + 1] = w end
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

-- Unit API
local playerGuid = "Player-0-ME"
function UnitGUID(unit)
    if unit == "player" then return playerGuid end
    return nil
end
function UnitName(unit) if unit == "player" then return "Devinp" end return nil end
function UnitClass(unit) if unit == "player" then return "Warrior", "WARRIOR" end return nil end
function UnitExists(unit) return unit == "player" end
function UnitHealth() return 5000 end
function UnitHealthMax() return 8000 end
function UnitIsFeignDeath() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
local instState = { inInstance = false, itype = "none", id = 0 }
function IsInInstance() return instState.inInstance, instState.itype end
function GetInstanceInfo()
    return "Azeroth", instState.itype, 0, "", 5, 0, false, instState.id, 5
end
function GetCursorPosition() return 0, 0 end
function InCombatLockdown() return false end
function IsInGroup(category) return false end
function IsInGuild() return true end
function GetSpellInfo(id) return "Spell" .. tostring(id), nil, "Interface\\Icons\\Icon" .. tostring(id) end
function GetSpellTexture(id) return "Interface\\Icons\\Icon" .. tostring(id) end
LE_PARTY_CATEGORY_INSTANCE = 2
local sentChat = {}
function SendChatMessage(msg, channel)
    sentChat[#sentChat + 1] = { msg = msg, channel = channel }
end
RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
    PRIEST = { r = 1, g = 1, b = 1 },
    SHAMAN = { r = 0, g = 0.44, b = 0.87 },
}
CLASS_ICON_TCOORDS = { WARRIOR = { 0, 0.25, 0, 0.25 } }
SlashCmdList = {}

-- ===========================================================================
-- Load the real framework + addon
-- ===========================================================================

local function Load(path)
    local chunk = assert(loadfile(path))
    chunk()
end

-- Suite palette fixture: shaped exactly like Commander_Console's global
-- (array entries {text, value, r, g, b}; CLASS carries no rgb) so the
-- suite-accent resolution and the dropdown parenthetical-strip both
-- execute under test
CommanderConsole_Colors = {
    { text = "Steel (Default)", value = "STEEL", r = 1, g = 1, b = 1 },
    { text = "Fel", value = "FEL", r = 0.5, g = 0.95, b = 0.15 },
    { text = "Class Color", value = "CLASS" },
}
-- Saved variables from a "previous session": a suite accent key, so login
-- must resolve it through the Console palette, not the local five
CommanderMetersDB = { AccentColor = "FEL", ArenaAutoOpen = true, DBVersion = 2 } -- a v2 save: the ladder must retire ArenaAutoOpen
-- Commander Arena Frames data fixture, shaped like the real generated
-- tables: the arena engine's DR brackets, control kinds, cooldown book and
-- drink list resolve through it (absent, CC still counts by name only)
CommanderArenaFrames_Data = {
    DR_BY_SPELL = { [11297] = "POLY", [12826] = "POLY", [1833] = "STUN", [11578] = "STUN",
        [20615] = "STUN", [408] = "KIDNEY", [8643] = "KIDNEY", [6215] = "FEAR", [27223] = "HORROR",
        [1715] = "LIMIT" },
    CONTROL_EXTRA = { [24259] = "SILENCE", [15487] = "SILENCE" },
    ENEMY_BOOK = {
        WARRIOR = { { id = 871, name = "Shield Wall", role = "DEF", cd = 1800, dur = 10 } },
        DRUID = { { id = 22812, name = "Barkskin", role = "DEF", cd = 60, dur = 12 } },
        WARLOCK = { { id = 19647, name = "Spell Lock", role = "KICK", cd = 24 } },
        MAGE = { { id = 2139, name = "Counterspell", role = "KICK", cd = 24, dur = 8 } },
    },
    RACIAL_BOOK = { BloodElf = { { id = 28730, name = "Arcane Torrent", role = "KICK", cd = 120 } } },
    DRINK_IDS = { 430, 27089 },
    SPEC_MARKERS = { WARRIOR = { { spec = "Arms", ids = { 30330 } } } },
}

Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersDB.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersDispel.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersEngine.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersArena.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMeters.lua")
Load(ADDONS .. "/Commander_Meters/CommanderMetersArenaUI.lua")

local function Fire(event, ...)
    local list = eventRegistry[event]
    if not list then return end
    for _, frame in ipairs(list) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

-- Login sequence
Fire("ADDON_LOADED", "Commander_Meters")
Fire("PLAYER_LOGIN")

CHECK(#harnessFailedErrors == 0, "C: login clean", harnessFailedErrors[1])
CHECK(CommanderMetersDB.EnableMeters == true, "C: defaults applied")
CHECK(CommanderMetersDB.ArenaAutoOpen == nil, "C: v3 migration retired ArenaAutoOpen")
    CHECK(CommanderMetersDB.DBVersion == 3, "C: schema version stamped", CommanderMetersDB.DBVersion)
CHECK(CommanderMetersDB.TextSize == 11 and CommanderMetersDB.BgOpacity == 0.92,
    "C: appearance defaults applied")
CHECK(CommanderMetersDB.AccentColor == "FEL",
    "C: saved suite accent survives ApplyDefaults", CommanderMetersDB.AccentColor)
CHECK(SlashCmdList.COMMANDERUI_METERS ~= nil, "C: slash registered")
CHECK(_G.SLASH_COMMANDERUI_METERS1 == "/cmeters" and _G.SLASH_COMMANDERUI_METERS2 == "/cm",
    "C: slash aliases /cmeters + /cm")
CHECK(_G.CommanderMetersFrame ~= nil, "C: main window created")
CHECK(_G.CommanderMetersDetailFrame ~= nil, "C: detail window created")

-- Module registered with the suite
do
    local found
    for _, info in ipairs(Commander.GetModules()) do
        if info.key == "Meters" then found = info end
    end
    CHECK(found ~= nil, "C: module in Commander registry")
    CHECK(found and found.slash == "/cmeters", "C: registry slash")
end

-- Every FontString that set a font used valid flags (SetFont asserts inside)
CHECK(#allFontStrings > 0, "C: fontstrings created", #allFontStrings)

-- Repaint pass with empty data
local root = _G.CommanderMetersFrame
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: empty repaint clean", harnessFailedErrors[1])

-- Inject the test fight through the slash path
SlashCmdList.COMMANDERUI_METERS("test")
CHECK(CommanderMetersEngine.InFight(), "C: test fight open")
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: live repaint clean", harnessFailedErrors[1])

-- Find the top bar's name: the warlock should lead damage
do
    local found = false
    for _, fs in ipairs(allFontStrings) do
        if fs.__text == "Diabolist" then found = true end
    end
    CHECK(found, "C: bars painted actor names")
end

-- Let the ticker close the fight (test events end ~1s before now)
now = now + 6
RunTickers()
CHECK(not CommanderMetersEngine.InFight(), "C: ticker closed the test fight")
CHECK(#CommanderMetersEngine.GetFights() == 1, "C: fight archived to Last")
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: post-fight repaint clean", harnessFailedErrors[1])

-- Death made it into the log with an hp snapshot
do
    local f1 = CommanderMetersEngine.GetFights()[1]
    CHECK(#f1.deaths == 1, "C: test fight recorded the death")
    local d = f1.deaths[1]
    CHECK(d and #d.log > 0, "C: death has an event trail")
end

-- Menus: mode menu lists all nine modes; pick HEALING
do
    local modeBtn
    -- find via scripts: buttons whose OnClick opens a menu; drive the real one
    -- through the header button reference exposed by click behavior instead:
    -- simulate by calling the OnClick of each button child until menu captured
    for _, f in ipairs(frames) do
        -- The header's mode button is tagged for the harness; clicking
        -- every button in creation order would fire the settings panel's
        -- Test/Forget buttons as a side effect
        if f.__kind == "Button" and f.headerRole == "mode" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 16 and menuCaptured[1].text == "DAMAGE" then
                modeBtn = f
                break
            end
        end
    end
    CHECK(modeBtn ~= nil, "C: mode menu opens with 9 modes + the arena section (16 entries: five arena modes)")
    if modeBtn then
        for _, info in ipairs(menuCaptured) do
            if info.text == "HEALING" then info.func() end
        end
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: healing mode repaint clean", harnessFailedErrors[1])
    end
end

-- Utility modes recorded from the test fixture
do
    local f1 = CommanderMetersEngine.GetFights()[1]
    local warrior = f1 and f1.actors["Player-0-CMTEST01"]
    local priest = f1 and f1.actors["Player-0-CMTEST03"]
    CHECK(warrior and warrior.ints == 1, "C: test fight recorded the interrupt")
    CHECK(priest and priest.dispels == 2, "C: test fight recorded both dispels")
    CHECK(priest and priest.purges == 1 and priest.cleanses == 1,
        "C: the split: a buff off the dummy is offensive, a curse off the warrior defensive")
    CHECK(priest and priest.purgeSpells["Dummy Ward"] and priest.cleanseSpells["Dummy Curse"],
        "C: each removal is listed on its own side")
    -- APM: keypresses only — the warrior's wand shot and the pet's Cleave
    -- are not counted, the warlock's ten bolts and the priest's two heals are
    local warlock = f1 and f1.actors["Player-0-CMTEST02"]
    CHECK(warrior and warrior.casts == 10, "C: test fight counted the warrior's casts (wand excluded)",
        warrior and warrior.casts)
    CHECK(warlock and warlock.casts == 10 and warlock.castSpells["Grimtongue: Cleave"] == nil,
        "C: test fight counted the warlock's casts, not the pet's")
    CHECK(priest and priest.casts == 2, "C: test fight counted the priest's heal casts")
end

-- The DISPELS mode: offensive / defensive in the row's small column, both
-- named in the tooltip, and one detail list per side
do
    local function FindBtn(pred)
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and pred(f) then return f end
        end
    end
    local function fsHas(text)
        for _, fs in ipairs(allFontStrings) do
            if fs.__text == text and fs.__shown ~= false then return true end
        end
        return false
    end
    local modeBtn = FindBtn(function(f) return f.headerRole == "mode" and f.__scripts.OnClick end)
    local picked = false
    if modeBtn then
        menuCaptured = {}
        modeBtn.__scripts.OnClick(modeBtn)
        for _, info in ipairs(menuCaptured) do
            if info.text == "DISPELS" then info.func(); picked = true end
        end
    end
    CHECK(picked, "C: mode menu offers DISPELS")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: dispels mode repaint clean", harnessFailedErrors[1])
    local row = FindBtn(function(f) return f.paneIndex == 1 and f.rank and f.guid == "Player-0-CMTEST03" and f.__shown end)
    CHECK(row ~= nil, "C: the priest has a DISPELS row")
    if row then
        CHECK(row.value.__text == "2", "C: two removals", row.value.__text)
        CHECK(row.rate.__text and row.rate.__text:find("1|r", 1, true) ~= nil, "C: the small column carries the split", row.rate.__text)
        row.__scripts.OnEnter(row)
        CHECK(#harnessFailedErrors == 0, "C: dispels tooltip clean", harnessFailedErrors[1])
        row.__scripts.OnLeave(row)
        row.__scripts.OnClick(row)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: dispels detail clean", harnessFailedErrors[1])
        CHECK(fsHas("OFFENSIVE · PURGED / STOLEN") and fsHas("DEFENSIVE · CLEANSED"), "C: the detail lists both sides")
        local ward, curse = false, false
        for _, fs in ipairs(allFontStrings) do
            if type(fs.__text) == "string" then
                if fs.__text:find("Dummy Ward$") then ward = true end
                if fs.__text:find("Dummy Curse$") then curse = true end
            end
        end
        CHECK(ward and curse, "C: each side lists its aura, whole and with its icon")
        row.__scripts.OnClick(row) -- close the detail again
    end
end

-- Kill/wipe tagging via ENCOUNTER_END (fires while the fight is open)
SlashCmdList.COMMANDERUI_METERS("test")
Fire("ENCOUNTER_END", 101, "Gruul the Dragonkiller", 4, 25, 1)
now = now + 6
RunTickers()
do
    local f1 = CommanderMetersEngine.GetFights()[1]
    CHECK(f1 and f1.success == true and f1.name == "Gruul the Dragonkiller",
        "C: encounter end tagged the last fight")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: tagged label repaint clean", harnessFailedErrors[1])
end

-- Report to chat: share menu offers channels, sending produces lines
do
    local shareBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "share" and f.__scripts.OnClick then
            shareBtn = f
            break
        end
    end
    CHECK(shareBtn ~= nil, "C: share button found")
    if shareBtn then
        menuCaptured = {}
        shareBtn.__scripts.OnClick(shareBtn)
        CHECK(#menuCaptured >= 2, "C: share menu offers channels", #menuCaptured)
        local before = #sentChat
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
        CHECK(#sentChat > before, "C: report sent lines", #sentChat - before)
        CHECK(sentChat[before + 1] and sentChat[before + 1].msg:find("Commander Meters"),
            "C: report header line", sentChat[before + 1] and sentChat[before + 1].msg)
        CHECK(sentChat[before + 1] and sentChat[before + 1].channel == "GUILD",
            "C: report channel honored")
        CHECK(sentChat[before + 1] and not sentChat[before + 1].msg:find("|c", 1, true),
            "C: report is plain text (no color escapes)")
    end
end

-- An empty segment must not broadcast a bare header line
do
    SlashCmdList.COMMANDERUI_METERS("wipe")
    local shareBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "share" and f.__scripts.OnClick then
            shareBtn = f
            break
        end
    end
    if shareBtn then
        menuCaptured = {}
        shareBtn.__scripts.OnClick(shareBtn)
        local before = #sentChat
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
        CHECK(#sentChat == before, "C: empty segment sends nothing", #sentChat - before)
    end
    SlashCmdList.COMMANDERUI_METERS("test") -- restore data for later blocks
    now = now + 6
    RunTickers()
end

-- Split view: toggle opens the second pane and repaints clean
do
    local splitBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "split" and f.__scripts.OnClick then
            splitBtn = f
            break
        end
    end
    CHECK(splitBtn ~= nil, "C: split button found")
    if splitBtn then
        -- Locate the specific widgets whose split behavior is pinned:
        -- the header mode button, pane 2's caption, and one row per pane
        local modeButton, cap2, pct1, pct2
        for _, f in ipairs(frames) do
            if f.__kind == "Button" then
                if f.headerRole == "mode" then modeButton = f end
                if f.paneIndex == 2 and f.text and not f.rank then cap2 = f end
                if f.rank and f.pct then
                    if f.paneIndex == 1 and not pct1 then pct1 = f.pct end
                    if f.paneIndex == 2 and not pct2 then pct2 = f.pct end
                end
            end
        end
        splitBtn.__scripts.OnClick(splitBtn)
        CHECK(CommanderMetersDB.SplitOpen == true, "C: split toggled on")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: split repaint clean", harnessFailedErrors[1])
        CHECK(root.__w == CommanderMetersDB.FrameWidth,
            "C: split keeps the window footprint", root.__w)
        CHECK(modeButton and modeButton.__shown == false,
            "C: header mode button steps aside while split")
        CHECK(cap2 and cap2.text.__shown == true,
            "C: second pane caption visible while split")
        CHECK(cap2 and type(cap2.text.__text) == "string"
            and cap2.text.__text:find("HEALING", 1, true) ~= nil
            and cap2.text.__text:find("·", 1, true) ~= nil,
            "C: second pane caption carries mode and segment",
            cap2 and cap2.text.__text)
        -- The active split glyph must wear the seeded suite accent —
        -- proving AccentColor="FEL" resolved through the Console palette
        CHECK(splitBtn.icon and splitBtn.icon[1] and splitBtn.icon[1].__color
            and splitBtn.icon[1].__color[1] == 0.5
            and splitBtn.icon[1].__color[2] == 0.95
            and splitBtn.icon[1].__color[3] == 0.15,
            "C: active glyph wears the suite accent (FEL via Console palette)")
        CHECK(pct1 and pct1.__shown == false and pct2 and pct2.__shown == false,
            "C: split condenses both panes' row columns")
        splitBtn.__scripts.OnClick(splitBtn)
        CHECK(CommanderMetersDB.SplitOpen == false, "C: split toggled off")
        CHECK(pct1 and pct1.__shown == true, "C: full columns return unsplit")
        CHECK(cap2 and cap2.text.__shown == false, "C: captions hide unsplit")
        CHECK(modeButton and modeButton.__shown == true, "C: mode button returns unsplit")
    end
end

-- Per-pane segments: each caption is the WHOLE pane — a mode section and
-- a segment section — so the right pane can be pinned to Overall while
-- the left one runs live, without any hidden gesture.
do
    local splitBtn, cap1, cap2, segButton
    for _, f in ipairs(frames) do
        if f.__kind == "Button" then
            if f.glyphName == "split" and f.__scripts.OnClick then splitBtn = f end
            if f.paneIndex == 1 and f.text and not f.rank then cap1 = f end
            if f.paneIndex == 2 and f.text and not f.rank then cap2 = f end
        end
    end
    -- A caption reads "<MODE>  ·  <SEGMENT>", stripped of color escapes
    local function CaptionHalves(cap)
        local text = cap and cap.text.__text or ""
        local head, tail = text:match("^(.-)%s+·%s+(.*)$")
        if not tail then return text, "" end
        return (head:gsub("|c%x%x%x%x%x%x%x%x", "")), (tail:gsub("|r$", ""))
    end
    local function Pick(cap, title, label)
        -- Click a caption and invoke the entry named `label` from the
        -- section headed by `title` — proving the sections exist and are
        -- addressed separately, since OVERALL/CURRENT appear only under OVER
        menuCaptured = {}
        cap.__scripts.OnClick(cap)
        local inSection, entry = false, nil
        for _, info in ipairs(menuCaptured) do
            if info.isTitle then
                inSection = (info.text == title)
            elseif inSection and info.text == label then
                entry = info
            end
        end
        if entry then entry.func() end
        return entry, menuCaptured
    end

    if splitBtn and cap1 and cap2 then
        splitBtn.__scripts.OnClick(splitBtn) -- open the split
        CHECK(CommanderMetersDB.SplitOpen == true, "C: per-pane block opened the split")

        -- The right caption's menu is two titled sections, one level deep
        menuCaptured = {}
        cap2.__scripts.OnClick(cap2)
        local titles, modeSeen, segSeen, followSeen = {}, false, false, false
        local section
        for _, info in ipairs(menuCaptured) do
            if info.isTitle then
                titles[#titles + 1] = info.text
                section = info.text
            elseif section == "RIGHT PANE SHOWS" and info.text == "HEALING" then
                modeSeen = true
            elseif section == "OVER" then
                if info.text == "OVERALL" then segSeen = true end
                if info.text == "FOLLOW LEFT PANE" then followSeen = true end
            end
        end
        CHECK(#titles == 3 and titles[1] == "RIGHT PANE SHOWS" and titles[2] == "ARENA — BOTH TEAMS"
            and titles[3] == "OVER",
            "C: pane caption menu has a mode section (with the arena block) and a segment section",
            table.concat(titles, "/"))
        CHECK(modeSeen and segSeen and followSeen,
            "C: right caption offers modes, segments, and FOLLOW LEFT PANE")

        -- Unpinned is the default, and it is the checked entry
        menuCaptured = {}
        cap2.__scripts.OnClick(cap2)
        local followEntry, overallEntry
        local sec
        for _, info in ipairs(menuCaptured) do
            if info.isTitle then sec = info.text
            elseif sec == "OVER" then
                if info.text == "FOLLOW LEFT PANE" then followEntry = info end
                if info.text == "OVERALL" then overallEntry = info end
            end
        end
        CHECK(followEntry and followEntry.checked == true,
            "C: the right pane follows the window by default")
        CHECK(overallEntry and not overallEntry.checked,
            "C: an unfollowed pane checks no segment of its own")

        root.__scripts.OnUpdate(root, 0.6)
        local _, s1 = CaptionHalves(cap1)
        local _, s2 = CaptionHalves(cap2)
        CHECK(s1 == s2 and s1 ~= "",
            "C: unpinned, both captions name the same segment", s1 .. " | " .. s2)

        -- Pin the right pane to OVERALL from its own caption — the thing
        -- that was unreachable before
        harnessFailedErrors = {}
        Pick(cap2, "OVER", "OVERALL")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: pinned repaint clean", harnessFailedErrors[1])
        local m1, seg1 = CaptionHalves(cap1)
        local m2, seg2 = CaptionHalves(cap2)
        CHECK(seg2 == "OVERALL" and seg1 ~= "OVERALL",
            "C: the right pane pins to its own segment", seg1 .. " | " .. seg2)
        CHECK(CommanderMetersDB.SplitSegment == "overall",
            "C: the pin persists", CommanderMetersDB.SplitSegment)
        -- A pinned caption wears the accent on its segment half so the
        -- divergence is never silent
        -- ACCENT_ESC is the seeded FEL accent (0.5, 0.95, 0.15) as this
        -- addon writes color openers — the same escape the LIVE dot uses
        local ACCENT_ESC = "|cff80f226"
        CHECK(cap2.text.__text:find(ACCENT_ESC, 1, true) ~= nil,
            "C: a pinned caption wears the accent", cap2.text.__text)
        CHECK(cap1.text.__text:find(ACCENT_ESC, 1, true) == nil,
            "C: the following caption does not", cap1.text.__text)

        -- Each pane still owns its own MODE at the same time — the two
        -- are independent, not an either/or axis
        Pick(cap2, "RIGHT PANE SHOWS", "HEALING")
        Pick(cap1, "LEFT PANE SHOWS", "DMG TAKEN")
        root.__scripts.OnUpdate(root, 0.6)
        m1, seg1 = CaptionHalves(cap1)
        m2, seg2 = CaptionHalves(cap2)
        CHECK(m1 == "DMG TAKEN" and m2 == "HEALING" and seg1 ~= seg2,
            "C: mode and segment differ per pane at once",
            m1 .. "/" .. seg1 .. " | " .. m2 .. "/" .. seg2)
        CHECK(CommanderMetersDB.ViewMode == "TAKEN" and CommanderMetersDB.SplitMode == "HEAL",
            "C: each pane's mode writes its own key",
            CommanderMetersDB.ViewMode .. "/" .. CommanderMetersDB.SplitMode)

        -- The header's segment button moves the window but not the pin
        local pinnedBefore = seg2
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.text and f.__scripts.OnClick and not f.paneIndex
                and not f.rank and f ~= splitBtn then
                menuCaptured = {}
                f.__scripts.OnClick(f)
                if #menuCaptured >= 4 and menuCaptured[1].text == "OVERALL"
                    and not menuCaptured[1].isTitle then
                    segButton = f
                end
            end
        end
        if segButton then
            -- Remember which segment the fixture was on: later blocks read
            -- the detail, and an idle CURRENT has nothing in it
            menuCaptured = {}
            segButton.__scripts.OnClick(segButton)
            local restore
            for _, info in ipairs(menuCaptured) do
                if info.checked then restore = info.text end
            end
            menuCaptured = {}
            segButton.__scripts.OnClick(segButton)
            for _, info in ipairs(menuCaptured) do
                if info.text == "CURRENT" then info.func() end
            end
            root.__scripts.OnUpdate(root, 0.6)
            local _, hs1 = CaptionHalves(cap1)
            local _, hs2 = CaptionHalves(cap2)
            CHECK(hs1:find("CURRENT", 1, true) ~= nil and hs2 == pinnedBefore,
                "C: the header segment moves the window, never the pin",
                hs1 .. " | " .. hs2)
            if restore then
                menuCaptured = {}
                segButton.__scripts.OnClick(segButton)
                for _, info in ipairs(menuCaptured) do
                    if info.text == restore then info.func() end
                end
            end
        end

        -- FOLLOW LEFT PANE is the way back
        Pick(cap2, "OVER", "FOLLOW LEFT PANE")
        root.__scripts.OnUpdate(root, 0.6)
        local _, f1 = CaptionHalves(cap1)
        local _, f2 = CaptionHalves(cap2)
        CHECK(f1 == f2, "C: FOLLOW LEFT PANE unpins the right pane", f1 .. " | " .. f2)
        CHECK(CommanderMetersDB.SplitSegment == "follow",
            "C: unfollowing persists too", CommanderMetersDB.SplitSegment)
        CHECK(cap2.text.__text:find(ACCENT_ESC, 1, true) == nil,
            "C: the accent leaves with the pin")

        -- Leave the window as the earlier blocks left it
        Pick(cap1, "LEFT PANE SHOWS", "DAMAGE")
        splitBtn.__scripts.OnClick(splitBtn)
        CHECK(CommanderMetersDB.SplitOpen == false,
            "C: per-pane block leaves the split closed")
    end
end

-- Pie breakdown: click an ability row in the open detail
do
    -- reopen a detail on the top bar row (bar rows carry a rank column)
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.rank and f.guid and f.__scripts.OnClick then
            f.__scripts.OnClick(f)
            break
        end
    end
    root.__scripts.OnUpdate(root, 0.6)
    local abilityRow
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.keyRef and f.listIndex == 1 and f.__shown then
            abilityRow = f
            break
        end
    end
    CHECK(abilityRow ~= nil, "C: detail ability row found")
    if abilityRow then
        abilityRow.__scripts.OnClick(abilityRow)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: pie repaint clean", harnessFailedErrors[1])
        local pctFound = false
        for _, fs in ipairs(allFontStrings) do
            if fs.__text and tostring(fs.__text):find("%%$") then pctFound = true end
        end
        CHECK(pctFound, "C: pie center readout painted")
        -- Hover inspects with NO click: enter a DIFFERENT ability row and
        -- the pie readout must re-target to it, tooltip up. On leave the
        -- tooltip drops but the selection sticks.
        local otherRow
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.keyRef and f.listIndex == 1
                and f.__shown and f.keyRef ~= abilityRow.keyRef then
                otherRow = f
                break
            end
        end
        CHECK(otherRow ~= nil, "C: second ability row found for hover")
        if otherRow then
            local hoveredKey = otherRow.keyRef
            GameTooltip:Hide()
            otherRow.__scripts.OnEnter(otherRow)
            root.__scripts.OnUpdate(root, 0.6)
            local hoverSel = false
            for _, fs in ipairs(allFontStrings) do
                if fs.__text == hoveredKey then hoverSel = true end
            end
            CHECK(hoverSel, "C: hover re-targets the pie readout", hoveredKey)
            CHECK(GameTooltip.__shown == true, "C: hover raises the stats tooltip")
            otherRow.__scripts.OnLeave(otherRow)
            CHECK(GameTooltip.__shown == false, "C: leave hides the tooltip")
            CHECK(#harnessFailedErrors == 0, "C: hover inspection clean", harnessFailedErrors[1])
        end
        abilityRow.__scripts.OnClick(abilityRow) -- click path still selects
        root.__scripts.OnUpdate(root, 0.6)
    end
end

-- Detail close glyph: hides the popup
do
    local closeBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "close" and f.__scripts.OnClick then
            closeBtn = f
            break
        end
    end
    CHECK(closeBtn ~= nil, "C: close glyph found")
    if closeBtn then
        _G.CommanderMetersDetailFrame:Show()
        closeBtn.__scripts.OnClick(closeBtn)
        CHECK(_G.CommanderMetersDetailFrame.__shown == false,
            "C: close glyph hides the detail")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: close repaint clean", harnessFailedErrors[1])
    end
end

-- Death log + health curve: switch to DEATHS mode and repaint
do
    local modeBtn
    for _, f in ipairs(frames) do
        -- The header's mode button is tagged for the harness; clicking
        -- every button in creation order would fire the settings panel's
        -- Test/Forget buttons as a side effect
        if f.__kind == "Button" and f.headerRole == "mode" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 16 and menuCaptured[1].text == "DAMAGE" then
                modeBtn = f
                break
            end
        end
    end
    if modeBtn then
        for _, info in ipairs(menuCaptured) do
            if info.text == "DEATHS" then info.func() end
        end
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: deaths + curve repaint clean", harnessFailedErrors[1])
        -- Death-log hover tooltips: the trail rows carry the log entry
        -- (real spell tooltip + the event's numbers), the deaths rows the
        -- killing blow. Both must raise the tooltip on enter.
        _G.CommanderMetersDetailFrame:Show()
        root.__scripts.OnUpdate(root, 0.6)
        local trailRow, deathRow
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.__shown then
                if f.logRef and not trailRow then trailRow = f end
                if f.deathRef and not deathRow then deathRow = f end
            end
        end
        CHECK(trailRow ~= nil, "C: death trail row carries its log entry")
        if trailRow then
            CHECK(type(trailRow.logRef.id) == "number" or trailRow.logRef.what == "Melee",
                "C: trail entry carries a spell id (or is Melee)")
            GameTooltip:Hide()
            trailRow.__scripts.OnEnter(trailRow)
            CHECK(GameTooltip.__shown == true, "C: trail hover raises the spell tooltip")
            trailRow.__scripts.OnLeave(trailRow)
            CHECK(GameTooltip.__shown == false, "C: trail leave hides the tooltip")
        end
        CHECK(deathRow ~= nil and deathRow.blowRef ~= nil,
            "C: deaths row carries its killing blow")
        if deathRow and deathRow.blowRef then
            GameTooltip:Hide()
            deathRow.__scripts.OnEnter(deathRow)
            CHECK(GameTooltip.__shown == true, "C: death-row hover tooltips the blow")
            deathRow.__scripts.OnLeave(deathRow)
        end
        CHECK(#harnessFailedErrors == 0, "C: death-log hover clean", harnessFailedErrors[1])
        -- Death report: the detail head's share glyph exists exactly when
        -- a death is selected, opens the channel menu, and sends the trail
        -- as plain text — header first, killing blow last, ranking-weight cap
        local dShare = _G.CommanderMetersDetailFrame.share
        CHECK(dShare ~= nil and dShare.__shown == true,
            "C: death share glyph shown with a death selected")
        if dShare then
            menuCaptured = {}
            dShare.__scripts.OnClick(dShare)
            CHECK(#menuCaptured >= 2, "C: death share menu offers channels", #menuCaptured)
            local before = #sentChat
            for _, info in ipairs(menuCaptured) do
                if info.text == "GUILD" then info.func() end
            end
            local sent = #sentChat - before
            CHECK(sent >= 2 and sent <= 6, "C: death report is header + capped trail", sent)
            local head = sentChat[before + 1]
            CHECK(head and head.msg:find("DEATH: Confessor", 1, true) ~= nil,
                "C: death report header names the fallen", head and head.msg)
            CHECK(head and head.channel == "GUILD", "C: death report channel honored")
            local last = sentChat[#sentChat]
            CHECK(last and last.msg:find("Skull Crack", 1, true) ~= nil,
                "C: death report ends at the killing blow", last and last.msg)
            CHECK(last and not last.msg:find("|", 1, true),
                "C: death report is plain text (no escapes)")
        end
    end
end

-- Bar wheel scrolling path (offset clamp + repaint)
do
    for _, f in ipairs(frames) do
        if f.__scripts.OnMouseWheel then
            f.__scripts.OnMouseWheel(f, -1)
            f.__scripts.OnMouseWheel(f, 1)
        end
    end
    CHECK(#harnessFailedErrors == 0, "C: wheel scrolling clean", harnessFailedErrors[1])
end

-- Segment menu: overall + current + last + F#1
do
    local segBtn, entries
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.headerRole == "segment" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured >= 4 and menuCaptured[1].text == "OVERALL" then
                segBtn, entries = f, menuCaptured
                break
            end
        end
    end
    CHECK(segBtn ~= nil, "C: segment menu opens")
    if entries then
        CHECK(entries[2].text == "CURRENT" and entries[3].text == "LAST",
            "C: segment menu order")
        CHECK(entries[4] and entries[4].text:find("F#%d"), "C: fight entry listed", entries[4] and entries[4].text)
        entries[1].func() -- OVERALL
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: overall view repaint clean", harnessFailedErrors[1])
    end
end

-- Bar click opens the detail view
do
    local clicked = false
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.guid and f.__scripts.OnClick then
            f.__scripts.OnClick(f)
            clicked = true
            break
        end
    end
    CHECK(clicked, "C: found a clickable bar row")
    CHECK(_G.CommanderMetersDetailFrame.__shown, "C: detail opened on click")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: detail repaint clean", harnessFailedErrors[1])
    -- Pie auto-opens on the top entry (its 16pt readout exists without any
    -- ability-row click), and the column header labels painted
    local pctFound, colFound = false, false
    for _, fs in ipairs(allFontStrings) do
        if fs.__font and fs.__font[2] == 16 and fs.__text
            and tostring(fs.__text):find("%%$") then
            pctFound = true
        end
        -- records modes label N/CRIT; deaths mode labels AMOUNT/TIME
        if fs.__text == "N/CRIT" or fs.__text == "AMOUNT" then colFound = true end
    end
    CHECK(pctFound or colFound, "C: pie auto-opened (records) or death labels shown")
    CHECK(colFound, "C: breakdown column labels painted")
end

-- Reset menu wipes
do
    local entries
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "reset" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 2 and menuCaptured[1].text:find("RESET FIGHT") then
                entries = menuCaptured
                break
            end
        end
    end
    CHECK(entries ~= nil, "C: reset menu opens with two labeled actions")
    if entries then
        entries[2].func() -- RESET EVERYTHING
        CHECK(#CommanderMetersEngine.GetFights() == 0, "C: reset everything cleared fights")
        CHECK(CommanderMetersEngine.GetOverall().totals.dmg == 0, "C: reset everything cleared overall")
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: post-reset repaint clean", harnessFailedErrors[1])
    end
end

-- Toggle + dump + health slash paths
SlashCmdList.COMMANDERUI_METERS("")
CHECK(CommanderMetersDB.WindowShown == false, "C: bare slash toggled window off")
SlashCmdList.COMMANDERUI_METERS("")
CHECK(CommanderMetersDB.WindowShown == true, "C: bare slash toggled window on")
SlashCmdList.COMMANDERUI_METERS("dump")
CHECK(CommanderMetersLog.events ~= nil, "C: dump capture armed")
SlashCmdList.COMMANDERUI_METERS("test")
CHECK(#CommanderMetersLog.events > 0, "C: raw events captured", #CommanderMetersLog.events)
SlashCmdList.COMMANDERUI_METERS("dump")
SlashCmdList.COMMANDERUI_METERS("health")
SlashCmdList.COMMANDERUI_METERS("wipefight")
SlashCmdList.COMMANDERUI_METERS("wipe")
SlashCmdList.COMMANDERUI_METERS("settings")
CHECK(#harnessFailedErrors == 0, "C: all slash paths clean", harnessFailedErrors[1])

-- Settings panel: flip every widget through its refreshers
do
    local panel
    for _, cat in ipairs(categories) do
        if cat.__title == "Meters" then panel = cat.__panel end
    end
    CHECK(panel ~= nil, "C: Meters subcategory registered")
    if panel then
        panel:Refresh()
        CHECK(#harnessFailedErrors == 0, "C: panel refresh clean", harnessFailedErrors[1])
    end
end

-- Graph toggle path
do
    local graphBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.glyphName == "graph" then
            graphBtn = f
            break
        end
    end
    CHECK(graphBtn ~= nil, "C: graph button found")
    if graphBtn then
        SlashCmdList.COMMANDERUI_METERS("test")
        graphBtn.__scripts.OnClick(graphBtn)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: graph repaint clean", harnessFailedErrors[1])
        graphBtn.__scripts.OnClick(graphBtn)
    end
end

-- APM mode: the headline is a per-minute rate, the graph's scale says so,
-- the bar tooltip names the count CASTS, and the detail sub-line quotes APM
do
    local modeBtn
    for _, f in ipairs(frames) do
        -- The header's mode button is tagged for the harness; clicking
        -- every button in creation order would fire the settings panel's
        -- Test/Forget buttons as a side effect
        if f.__kind == "Button" and f.headerRole == "mode" and f.__scripts.OnClick then
            menuCaptured = {}
            f.__scripts.OnClick(f)
            if #menuCaptured == 16 and menuCaptured[1].text == "DAMAGE" then
                modeBtn = f
                break
            end
        end
    end
    local picked = false
    if modeBtn then
        for _, info in ipairs(menuCaptured) do
            if info.text == "APM" then info.func(); picked = true end
        end
    end
    CHECK(picked, "C: mode menu offers APM")
    if picked then
        SlashCmdList.COMMANDERUI_METERS("test")
        now = now + 6
        RunTickers()
        local graphBtn
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.glyphName == "graph" then graphBtn = f break end
        end
        graphBtn.__scripts.OnClick(graphBtn)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(#harnessFailedErrors == 0, "C: APM repaint with graph clean", harnessFailedErrors[1])
        local scaleFound, apmRow = false, nil
        for _, fs in ipairs(allFontStrings) do
            if fs.__text and tostring(fs.__text):match("^%d[%d%.km]* APM$") then scaleFound = true end
        end
        CHECK(scaleFound, "C: APM graph scale is quoted in APM")
        -- The top bar: big column = rate, small column = cast count — checked
        -- against the engine's own LAST segment (Follow Combat lands the view
        -- there once the injected fight closes)
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.guid == "Player-0-CMTEST02" and f.rate then apmRow = f break end
        end
        CHECK(apmRow ~= nil, "C: APM bar row for the warlock painted")
        if apmRow then
            local last = CommanderMetersEngine.GetFights()[1]
            local casts = last.actors["Player-0-CMTEST02"].casts
            CHECK(apmRow.rate.__text == tostring(casts), "C: APM row small column is the cast count",
                apmRow.rate.__text .. " vs " .. casts)
            local big = tonumber(apmRow.value.__text)
            local want = casts * 60 / last.dur
            CHECK(big and math.abs(big - want) <= 1, "C: APM row headline is casts per minute",
                (apmRow.value.__text or "?") .. " vs " .. want)
            apmRow.__scripts.OnEnter(apmRow)
            apmRow.__scripts.OnLeave(apmRow)
            apmRow.__scripts.OnClick(apmRow)
            root.__scripts.OnUpdate(root, 0.6)
            CHECK(#harnessFailedErrors == 0, "C: APM detail repaint clean", harnessFailedErrors[1])
            local sub = _G.CommanderMetersDetailFrame.sub.__text or ""
            CHECK(sub:find("APM%)") ~= nil, "C: APM detail sub-line quotes the rate", sub)
            CHECK(sub:find("ACTIVE") ~= nil, "C: APM detail sub-line shows cast-active time", sub)
        end
        graphBtn.__scripts.OnClick(graphBtn)
        -- Back to DAMAGE so the rest of the run sees the mode it expects
        menuCaptured = {}
        modeBtn.__scripts.OnClick(modeBtn)
        for _, info in ipairs(menuCaptured) do
            if info.text == "DAMAGE" then info.func() end
        end
        root.__scripts.OnUpdate(root, 0.6)
    end
end

-- Fight-follow behavior: AutoSwitchCurrent flashes and switches (indirect:
-- fresh fight then close, repaint stays clean and segment label updates)
now = now + 10
RunTickers()
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: follow-combat transitions clean", harnessFailedErrors[1])

-- Master switch gates the tester
CommanderMetersDB.EnableMeters = false
SlashCmdList.COMMANDERUI_METERS("test")
CHECK(not CommanderMetersEngine.InFight(), "C: test refused while disabled")
CommanderMetersDB.EnableMeters = true

-- Tooltips: bar hover and detail-row hover run clean and carry spell ids
do
    local barRow
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.guid and f.__scripts.OnEnter then
            barRow = f
            break
        end
    end
    CHECK(barRow ~= nil, "C: hoverable bar row found")
    if barRow then
        barRow.__scripts.OnEnter(barRow)
        barRow.__scripts.OnLeave(barRow)
    end
    local abilityRow
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.recRef and f.__scripts.OnEnter then
            abilityRow = f
            break
        end
    end
    if abilityRow then
        abilityRow.__scripts.OnEnter(abilityRow)
        abilityRow.__scripts.OnLeave(abilityRow)
        CHECK(type(abilityRow.recRef.id) == "number" or abilityRow.recRef.name == "Melee",
            "C: ability record carries a spell id (or is Melee)")
        -- A records-mode detail painted this row, so the death share glyph
        -- must have been put away by that same repaint
        CHECK(_G.CommanderMetersDetailFrame.share.__shown == false,
            "C: death share glyph hidden outside deaths mode")
    end
    CHECK(#harnessFailedErrors == 0, "C: tooltip paths clean", harnessFailedErrors[1])
end

-- Detail popup: draggable by its title bar
do
    local detail = _G.CommanderMetersDetailFrame
    local head
    for _, f in ipairs(frames) do
        if f.__scripts.OnDragStart and f.__scripts.OnDragStop and f ~= root then
            head = f
            break
        end
    end
    CHECK(head ~= nil, "C: detail title bar registers drag handlers")
    if head then
        head.__scripts.OnDragStart(head)
        head.__scripts.OnDragStop(head)
        CHECK(#harnessFailedErrors == 0, "C: detail drag cycle clean", harnessFailedErrors[1])
    end
end

-- Lock slashes drive the HudChrome state
SlashCmdList.COMMANDERUI_METERS("unlock")
CHECK(CommanderMetersDB.HudLocked == false, "C: /cmeters unlock")
SlashCmdList.COMMANDERUI_METERS("lock")
CHECK(CommanderMetersDB.HudLocked == true, "C: /cmeters lock")

-- Appearance toggles repaint clean (opacities live, click-through re-Apply)
CommanderMetersDB.BgOpacity = 0.5
CommanderMetersDB.BarOpacity = 0.6
CommanderMetersDB.ClickThrough = true
Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
root.__scripts.OnUpdate(root, 0.6)
CHECK(#harnessFailedErrors == 0, "C: appearance + clickthrough clean", harnessFailedErrors[1])
CommanderMetersDB.ClickThrough = false
Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)

-- Session persistence: logout writes the snapshot only when opted in
CommanderMetersDB.PersistData = true
Fire("PLAYER_LOGOUT")
CHECK(type(CommanderMetersSession) == "table" and CommanderMetersSession.v == 3,
    "C: logout wrote the session snapshot")
CHECK(CommanderMetersSession.overall ~= nil, "C: snapshot carries Overall")
CommanderMetersDB.PersistData = false
Fire("PLAYER_LOGOUT")
CHECK(CommanderMetersSession == nil, "C: opt-out logout clears the snapshot")

-- Roster + regen + instance events
Fire("GROUP_ROSTER_UPDATE")
Fire("PLAYER_REGEN_DISABLED")
Fire("PLAYER_REGEN_ENABLED")
Fire("PLAYER_ENTERING_WORLD", false, false)
Fire("READY_CHECK", "Devinp", 30)
Fire("UNIT_PET", "player")
CHECK(#harnessFailedErrors == 0, "C: gameplay events clean", harnessFailedErrors[1])

-- Instance auto-reset baseline persists: a "reload" inside the same
-- instance must never wipe (the PersistData-cancellation regression)
do
    SlashCmdList.COMMANDERUI_METERS("test")
    now = now + 6
    RunTickers()
    local dmgBefore = CommanderMetersEngine.GetOverall().totals.dmg
    CHECK(dmgBefore > 0, "C: instance test has data")
    CommanderMetersDB.AutoResetOnInstance = true
    CommanderMetersDB.LastInstanceKey = "party42" -- persisted baseline
    instState.inInstance, instState.itype, instState.id = true, "party", 42
    Fire("PLAYER_ENTERING_WORLD", false, true) -- the post-/reload PEW
    CHECK(CommanderMetersEngine.GetOverall().totals.dmg == dmgBefore,
        "C: reload inside the same instance does not wipe")
    instState.id = 43
    Fire("PLAYER_ENTERING_WORLD", false, false) -- a REAL instance change
    CHECK(CommanderMetersEngine.GetOverall().totals.dmg == 0,
        "C: real instance transition wipes")
    CHECK(CommanderMetersDB.LastInstanceKey == "party43", "C: baseline persisted to DB")
    CommanderMetersDB.AutoResetOnInstance = false
    instState.inInstance, instState.itype, instState.id = false, "none", 0
    Fire("PLAYER_ENTERING_WORLD", false, false)
end

-- Restore Defaults on a changed bake-at-login option prints the reload hint
do
    CommanderMetersDB.AccentColor = "CYAN"
    SlashCmdList.COMMANDERUI_METERS("reset")
    local hinted = false
    for i = #printLog - 3, #printLog do
        if printLog[i] and printLog[i]:find("applies after /reload") then hinted = true end
    end
    CHECK(hinted, "C: restore defaults hints the reload for baked options")
    CHECK(CommanderMetersDB.AccentColor == "AMBER", "C: restore defaults reset the accent")
end

-- External live pane modes (the Commander_Threat embed contract): register,
-- show, paint from provider rows, menu entry, share, detail guard, retire
do
    local fakeRows = {
        { name = "Xena", class = "WARRIOR", valueText = "100%", pctText = "12.4k",
            rateText = "1.2k", barFrac = 1 },
        { name = "Gabrielle", class = "PRIEST", valueText = "85%", pctText = "9.1k",
            rateText = "800", barFrac = 0.85 },
    }
    CHECK(CommanderMeters_RegisterExternalMode({
        key = "XTEST", label = "XTEST",
        collect = function() return fakeRows, #fakeRows end,
        caption = function() return "FAKE MOB" end,
        empty = "Nothing live",
    }) == true, "C: external mode registers")
    CHECK(CommanderMeters_RegisterExternalMode({}) == false, "C: bad external spec refused")

    CHECK(CommanderMeters_ShowExternalPane("XTEST") == true, "C: show opens the pane")
    CHECK(CommanderMetersDB.SplitOpen == true and CommanderMetersDB.SplitMode == "XTEST",
        "C: split state adopted")
    local root = _G.CommanderMetersFrame
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: external pane repaint clean", harnessFailedErrors[1])
    local function fsShown(text)
        for _, fs in ipairs(allFontStrings) do
            if fs.__text ~= nil and tostring(fs.__text) == text then return true end
        end
        return false
    end
    local function fsMatching(pattern)
        for _, fs in ipairs(allFontStrings) do
            if type(fs.__text) == "string" and fs.__text:find(pattern) then return true end
        end
        return false
    end
    CHECK(fsShown("Xena") and fsShown("Gabrielle"), "C: provider rows painted")
    CHECK(fsShown("100%"), "C: provider value text painted")
    CHECK(fsMatching("FAKE MOB"), "C: external caption painted")

    -- The pane-2 caption's mode menu offers (and checks) the external mode
    local cap2
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.paneIndex == 2 and f.text and not f.bar
            and f.__scripts.OnClick then
            cap2 = f
        end
    end
    CHECK(cap2 ~= nil, "C: pane 2 caption found")
    if cap2 then
        menuCaptured = {}
        cap2.__scripts.OnClick(cap2)
        local hasX, checkedX = false, false
        for _, info in ipairs(menuCaptured) do
            if info.text == "XTEST" then
                hasX = true
                checkedX = info.checked and true or false
            end
        end
        CHECK(hasX, "C: mode menu offers the external mode", #menuCaptured)
        CHECK(checkedX, "C: external mode shows checked in its pane")
    end

    -- External pane 1: report lines come from the provider
    CommanderMetersDB.ViewMode = "XTEST"
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    local beforeChat = #sentChat
    local shareBtn
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.headerRole == "share" and f.__scripts.OnClick then
            shareBtn = f
        end
    end
    if shareBtn then
        menuCaptured = {}
        shareBtn.__scripts.OnClick(shareBtn)
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
    end
    CHECK(#sentChat > beforeChat and sentChat[beforeChat + 1].msg:find("XTEST") ~= nil,
        "C: external report header from the provider",
        sentChat[beforeChat + 1] and sentChat[beforeChat + 1].msg)
    CHECK(sentChat[beforeChat + 2] ~= nil and sentChat[beforeChat + 2].msg:find("Xena") ~= nil,
        "C: external report names the top row")

    -- External rows carry no guid: clicking one never opens the detail
    _G.CommanderMetersDetailFrame:Hide()
    local row2
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.paneIndex == 2 and f.bar and f.__scripts.OnClick then
            row2 = row2 or f
        end
    end
    CHECK(row2 ~= nil, "C: pane 2 row found")
    if row2 then
        row2.__scripts.OnClick(row2)
        CHECK(_G.CommanderMetersDetailFrame.__shown == false,
            "C: external rows never open the detail")
    end

    -- Retire: orphaned panes point back at real modes and repaint clean
    CommanderMeters_RetireExternalMode("XTEST")
    CHECK(CommanderMetersDB.ViewMode == "DMG" and CommanderMetersDB.SplitMode == "HEAL",
        "C: retire points orphaned panes at real modes")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(#harnessFailedErrors == 0, "C: post-retire repaint clean", harnessFailedErrors[1])
end

-- ===========================================================================
-- ARENA: the match engine wired into the window, and the Arena Replay
-- ===========================================================================

do
    local A = CommanderMetersArena
    local function FindButton(pred)
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and pred(f) then return f end
        end
    end
    local function FindFrame(pred)
        for _, f in ipairs(frames) do
            if pred(f) then return f end
        end
    end
    local function fsMatching(pattern)
        for _, fs in ipairs(allFontStrings) do
            if type(fs.__text) == "string" and fs.__text:find(pattern) then return true end
        end
        return false
    end
    local function Errors(label)
        CHECK(#harnessFailedErrors == 0, label, harnessFailedErrors[1])
        for i = #harnessFailedErrors, 1, -1 do harnessFailedErrors[i] = nil end
    end

    CHECK(_G.CommanderMetersArenaFrame == nil, "ARENA: replay window is built lazily")

    -- Canned match through the slash path: recorded, WIN, never auto-opened
    CHECK(#A.GetMatches() == 0, "ARENA: no matches before the test")
    SlashCmdList.COMMANDERUI_METERS("arenatest")
    CHECK(#A.GetMatches() == 1, "ARENA: test match archived", #A.GetMatches())
    local tm = A.GetMatches()[1]
    CHECK(tm and tm.result == "WIN" and tm.bracket == 3, "ARENA: test match is a 3v3 WIN")
    CHECK(tm and tm.teams.us.n == 3 and tm.teams.them.n == 3, "ARENA: three seats a side")
    CHECK(tm and #tm.deaths == 3, "ARENA: three deaths recorded", tm and #tm.deaths)
    CHECK(tm and tm.seats["Player-1-CMARENA13"].deaths == 1 and tm.seats["Player-0-CMARENA01"].kills >= 1,
        "ARENA: the warlock died, the mage has a kill")
    CHECK(tm and tm.seats["Player-0-CMARENA01"].ccBroke == 1, "ARENA: the mage broke his own team's sap (the mistake counter)")
    CHECK(tm and tm.seats["Player-1-CMARENA11"].ccBroke == 0, "ARENA: freeing a teammate is not a mistake")
    CHECK(tm and tm.seats["Player-1-CMARENA11"].cds == 1 and tm.seats["Player-1-CMARENA12"].cds == 1,
        "ARENA: book cooldowns logged through the Arena Frames fixture")
    CHECK(tm and tm.seats["Player-0-CMARENA02"].ccCasts >= 4, "ARENA: rogue CC casts counted", tm and tm.seats["Player-0-CMARENA02"].ccCasts)
    CHECK(tm and tm.seats["Player-1-CMARENA11"].trinkets == 1, "ARENA: trinket press recorded")
    CHECK(tm and tm.seats["Player-0-CMARENA03"].drained == 3300, "ARENA: mana burns summed")
    CHECK(tm and tm.seats["Player-1-CMARENA12"].drinks == 1, "ARENA: the druid drank once")
    CHECK(tm and tm.scored and tm.seats["Player-0-CMARENA01"].sb.ratingChange == 14, "ARENA: scoreboard merged")
    CHECK(tm and tm.teams.us.name == "Frostbite Warrant", "ARENA: team info merged")
    CHECK(tm and tm.seats["Player-1-CMARENA11"].spec == "Arms" and tm.seats["Player-1-CMARENA11"].specRevealed,
        "ARENA: the warrior's spec was revealed by Mortal Strike")
    -- The replay records the canned match carries
    CHECK(tm and tm.seats["Player-0-CMARENA01"].castLogN >= 8, "ARENA: the mage's casts were logged", tm and tm.seats["Player-0-CMARENA01"].castLogN)
    CHECK(tm and tm.seats["Player-0-CMARENA01"].aurasN >= 3, "ARENA: the mage's auras were logged", tm and tm.seats["Player-0-CMARENA01"].aurasN)
    CHECK(tm and tm.seats["Player-0-CMARENA01"].sPow ~= nil and tm.seats["Player-0-CMARENA01"].powType == 0, "ARENA: mage mana snapshots")
    CHECK(tm and tm.seats["Player-1-CMARENA11"].powType == 1, "ARENA: warrior rage type")

    CHECK(_G.CommanderMetersArenaFrame == nil, "ARENA: the replay never opens itself at match end")
    local arenaGlyph = FindButton(function(f) return f.headerRole == "arena" end)
    CHECK(arenaGlyph ~= nil, "ARENA: header has an arena glyph button")
    if arenaGlyph then arenaGlyph.__scripts.OnClick(arenaGlyph) end
    local report = _G.CommanderMetersArenaFrame
    CHECK(report ~= nil, "ARENA: the header glyph builds and opens the replay")
    CHECK(report and report.__shown == true, "ARENA: replay shown after the glyph click")
    root.__scripts.OnUpdate(root, 0.6)
    CHECK(arenaGlyph and arenaGlyph.icon[1].__color and arenaGlyph.icon[1].__color[1] == 0.5,
        "ARENA: the arena glyph wears the accent while the replay is open")
    report.__scripts.OnUpdate(report, 0.6)
    Errors("ARENA: replay first paint clean")
    if _G.__afterArenaReport then _G.__afterArenaReport(report) end
    CHECK(fsMatching("Frostweaver") and fsMatching("Gorehowl"), "ARENA: both teams' cards painted")
    CHECK(fsMatching("FIRST BLOOD"), "ARENA: summary names first blood")
    CHECK(fsMatching("3v3 · NAGRAND ARENA"), "ARENA: header names the match")
    CHECK(fsMatching("1850 → 1864"), "ARENA: header shows the rating move")
    CHECK(fsMatching("MOMENTS"), "ARENA: moments feed titled")
    CHECK(fsMatching("YOUR TEAM") and fsMatching("ENEMY"), "ARENA: teams split, never combined")
    CHECK(fsMatching("DEAD|r"), "ARENA: dead seats read DEAD at the end")
    -- Cards: one per seat, with a portrait button carrying the guid
    local view = CommanderMetersArena_View()
    local card = FindButton(function(f) return f.guid == "Player-1-CMARENA11" and f.__parent and f.__parent.cardIndex end)
    CHECK(card ~= nil, "ARENA: enemy warrior has a card")
    if card then
        card.__scripts.OnEnter(card)
        Errors("ARENA: portrait tooltip clean")
        card.__scripts.OnLeave(card)
    end
    -- Meters table: six columns per team, values as of the cursor
    CHECK(fsMatching("^K/D$") and fsMatching("^KICK$"), "ARENA: meters table columns painted")

    -- Scrubbing: the wheel nudges the cursor off the end, skip returns it
    local plotFrame
    for _, f in ipairs(frames) do
        if f.__kind == "Frame" and f.__scripts.OnMouseWheel and f.__scripts.OnMouseDown and f.__scripts.OnMouseUp then
            plotFrame = f
        end
    end
    CHECK(plotFrame ~= nil, "ARENA: timeline plot found")
    if plotFrame then
        CHECK(view.t == nil, "ARENA: cursor starts at the end")
        plotFrame.__scripts.OnMouseWheel(plotFrame, -1)
        CHECK(view.t ~= nil and math.abs(view.t - (tm.tEnd - 1)) < 1e-6, "ARENA: wheel nudged the cursor one second back", view.t)
        report.__scripts.OnUpdate(report, 0.6)
        Errors("ARENA: scrubbed repaint clean")
        -- Mid-match: a cast in progress, buffs on the mage, the warlock's control
        view.t = 74.5
        report.__scripts.OnUpdate(report, 0.6)
        Errors("ARENA: mid-match repaint clean")
        CHECK(fsMatching("^Frostbolt  0%.5s$"), "ARENA: the mage's Frostbolt is on the cast bar with its time left")
        CHECK(fsMatching("on |r|cff[0-9a-f]+Nethra|r"), "ARENA: the card says who the mage is on")
        -- A controlled seat: kidney shot on the warlock at +70.2..76
        CHECK(fsMatching("KIDNEY SHOT") , "ARENA: the control on the warlock is written on his cast bar")
        local kidneyIcon = FindButton(function(f) return f.rec and f.rec.name == "Kidney Shot" and f.__shown and f.border end)
        CHECK(kidneyIcon ~= nil and kidneyIcon.border.__color and math.abs(kidneyIcon.border.__color[1] - 0.86) < 1e-6,
            "ARENA: a control debuff icon wears the control color")
        -- Cooldown icons on a card at +75: the warrior's trinket (pressed +71)
        -- The trinket badge on the warrior's portrait reads the time left; the
        -- generic cooldown row no longer repeats it
        local badge = FindButton(function(f) return f.trinketBadge and f.__parent and f.__parent.guid == "Player-1-CMARENA11" end)
        CHECK(badge ~= nil, "ARENA: the warrior's card has a trinket badge")
        if badge then
            CHECK(badge.text.__text == "1:57", "ARENA: the badge reads the trinket's time left (pressed at +71, cursor +74.5)", badge.text.__text)
            CHECK(badge.border.__color and math.abs(badge.border.__color[1] - 0.85) < 1e-6, "ARENA: a down trinket wears the red border")
            CHECK(badge.icon.__texture == "Interface\\Icons\\INV_Jewelry_TrinketPVP_02", "ARENA: an orc's badge is the Horde medallion", badge.icon.__texture)
            CHECK(badge.sweep and badge.sweep.__cdDur == 120 and badge.sweep.__cdStart ~= nil, "ARENA: a down trinket runs the radial sweep over its 120 s")
            CHECK(badge.sweep and math.abs((GetTime() - badge.sweep.__cdStart) - 3.5) < 1e-6, "ARENA: the sweep is set to the cursor's elapsed 3.5 s", badge.sweep and (GetTime() - badge.sweep.__cdStart))
            badge.__scripts.OnEnter(badge)
            Errors("ARENA: trinket badge tooltip clean")
            badge.__scripts.OnLeave(badge)
        end
        local cdIcon = FindButton(function(f) return f.rec and f.rec.kind == "TRINKET" and f.__shown and not f.trinketBadge end)
        CHECK(cdIcon == nil, "ARENA: the medallion is not repeated in the cooldown row")
        local mageBadge = FindButton(function(f) return f.trinketBadge and f.__parent and f.__parent.guid == "Player-0-CMARENA01" end)
        CHECK(mageBadge and mageBadge.text.__text == "" and mageBadge.border.__color and math.abs(mageBadge.border.__color[1] - 0.95) < 1e-6,
            "ARENA: an unpressed trinket reads up with the gold border")
        CHECK(mageBadge and mageBadge.icon.__texture == "Interface\\Icons\\INV_Jewelry_TrinketPVP_01", "ARENA: a human's badge is the Alliance medallion")
        local buffIcon = FindButton(function(f) return f.rec and f.rec.name == "Ice Barrier" and f.__shown end)
        CHECK(buffIcon ~= nil, "ARENA: the mage's Ice Barrier shows as a buff icon")
        if buffIcon then
            buffIcon.__scripts.OnEnter(buffIcon)
            Errors("ARENA: aura tooltip clean")
            buffIcon.__scripts.OnLeave(buffIcon)
        end
        -- The GCD sweep names its spell: the rogue 0.7 s after a Sinister Strike
        view.t = 68.2
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(fsMatching("|T.-|t Sinister Strike|cff[0-9a-f]+  GCD|r"), "ARENA: the GCD bar shows the icon and name of the spell it was spent on")
        -- Pressure: with nothing else on the cast bar, who is on them
        view.t = 95
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(fsMatching("1 on them: |r|cff[0-9a-f]+Frostweaver"), "ARENA: an idle card says who is on that player")
        -- A dead seat later on: DEAD, and what killed them for five seconds
        view.t = tm.deaths[1].t + 0.5
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(fsMatching("DEAD|r"), "ARENA: a dead seat reads DEAD at the cursor")
        CHECK(fsMatching("^KILLED  ← Frostbolt %(Frostweaver%)$"), "ARENA: the killing blow is on the dead card's cast bar")
        view.t = tm.deaths[1].t + 6
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(not fsMatching("^KILLED  ← "), "ARENA: the killing blow readout lasts five seconds")
        -- Hover: a hairline and a clock follow the mouse across the plot
        plotFrame.__scripts.OnEnter(plotFrame)
        report.__scripts.OnUpdate(report, 0.01)
        -- The hover clock is the "-0:03" string parented to the PLOT (the
        -- axis row shows the same time, permanently)
        local hoverText
        for _, fs in ipairs(allFontStrings) do
            if fs.__text == "-0:03" and fs.__shown and fs.__parent == plotFrame then hoverText = fs end
        end
        CHECK(hoverText ~= nil, "ARENA: hovering the plot shows the time under the mouse (x=0 → -0:03)")
        plotFrame.__scripts.OnLeave(plotFrame)
        report.__scripts.OnUpdate(report, 0.01)
        CHECK(hoverText and hoverText.__shown == false, "ARENA: leaving the plot hides the hover clock")
        -- Before the gates nothing has happened
        view.t = 10
        report.__scripts.OnUpdate(report, 0.6)
        Errors("ARENA: pre-gate repaint clean")
        plotFrame.__scripts.OnMouseDown(plotFrame)
        CHECK(view.dragging == true and view.t ~= nil and math.abs(view.t - (tm.tGates - 3)) < 1e-6,
            "ARENA: mouse down starts a drag at the plot's origin (3 s before the gates)", view.t)
        plotFrame.__scripts.OnMouseUp(plotFrame)
        CHECK(view.dragging == false, "ARENA: mouse up ends the drag")
    end
    local skipBtn = FindButton(function(f) return f.role == "skip" end)
    CHECK(skipBtn ~= nil, "ARENA: skip-to-end button found")
    if skipBtn then
        skipBtn.__scripts.OnClick(skipBtn)
        CHECK(view.t == nil, "ARENA: skip returns the cursor to the end")
    end

    -- Playback: play from the end restarts just before the gates
    local playBtn = FindButton(function(f) return f.role == "play" end)
    CHECK(playBtn ~= nil, "ARENA: play button found")
    if playBtn then
        playBtn.__scripts.OnClick(playBtn)
        CHECK(view.playing == true and view.t ~= nil and math.abs(view.t - (tm.tGates - 3)) < 1e-6, "ARENA: play from the end restarts before the gates", view.t)
        local before = view.t
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(view.t and view.t > before + 0.5, "ARENA: the clock advances while playing", view.t)
        Errors("ARENA: playing repaint clean")
        local speedBtn = FindButton(function(f) return f.role == "speed" end)
        CHECK(speedBtn ~= nil, "ARENA: speed button found")
        if speedBtn then
            speedBtn.__scripts.OnClick(speedBtn)
            CHECK(view.speedIndex == 2, "ARENA: speed steps to 2x")
            before = view.t
            report.__scripts.OnUpdate(report, 0.5)
            CHECK(view.t - before > 0.9, "ARENA: 2x advances a second per half second", view.t - before)
        end
        playBtn.__scripts.OnClick(playBtn)
        CHECK(view.playing == false, "ARENA: play toggles to pause")
        view.playing = true
        view.t = tm.tEnd - 0.1
        report.__scripts.OnUpdate(report, 1)
        CHECK(view.playing == false and view.t == nil, "ARENA: playback stops at the end")
    end

    -- The moments feed: clicking a moment moves the cursor to it
    report.__scripts.OnUpdate(report, 0.6)
    local ledgerRow = FindButton(function(f) return f.ledgerRow == 3 and f.idx end)
    CHECK(ledgerRow ~= nil, "ARENA: feed row painted with a moment")
    if ledgerRow then
        local e = tm.ledger[ledgerRow.idx]
        ledgerRow.__scripts.OnClick(ledgerRow)
        CHECK(view.t ~= nil and math.abs(view.t - e.t) < 1e-6, "ARENA: clicking a moment jumps the cursor to it")
        ledgerRow.__scripts.OnEnter(ledgerRow)
        Errors("ARENA: moment tooltip clean")
        ledgerRow.__scripts.OnLeave(ledgerRow)
        CHECK(ledgerRow.team and ledgerRow.team.__shown == true, "ARENA: feed rows carry a team stripe")
        local ccIdx
        for i = 1, tm.ledgerN do
            if tm.ledger[i].kind == "CC" and tm.ledger[i].x == 2 then ccIdx = i; break end
        end
        CHECK(ccIdx ~= nil, "ARENA: the Intercept stun landed at half")
        if ccIdx then
            view.t = tm.ledger[ccIdx].t
            report.__scripts.OnUpdate(report, 0.6)
            CHECK(fsMatching("Intercept Stun|cff") and fsMatching("\194\189"), "ARENA: feed row shows the half bracket")
        end
        view.t = nil
    end

    -- Match menu lists the kept match
    local matchBtn = FindButton(function(f) return f.headerRole == "arenaMatch" end)
    CHECK(matchBtn ~= nil, "ARENA: match button found")
    if matchBtn then
        menuCaptured = {}
        matchBtn.__scripts.OnClick(matchBtn)
        CHECK(#menuCaptured == 1 and menuCaptured[1].text:find("3v3 NAGRAND ARENA") ~= nil,
            "ARENA: match menu lists the kept match", menuCaptured[1] and menuCaptured[1].text)
        CHECK(menuCaptured[1] and menuCaptured[1].checked == true, "ARENA: the shown match is checked")
    end

    -- Sidebar: the match history, one row per kept match, click selects
    local sideRow = FindButton(function(f) return f.sideRow == 1 and f.matchSel ~= nil and f.__shown end)
    CHECK(sideRow ~= nil, "ARENA: sidebar lists the kept match")
    CHECK(sideRow and sideRow.matchSel == tm.id, "ARENA: the first sidebar row is the newest match")
    CHECK(sideRow and sideRow.sel.__shown == true, "ARENA: the shown match's row is highlighted")
    CHECK(fsMatching("^MATCHES$") and fsMatching("WIN %+14|r  "), "ARENA: sidebar row reads the result and length")
    CHECK(fsMatching("1 W|r"), "ARENA: the sidebar foot carries the running record")
    if sideRow then
        view.sel = "last"
        sideRow.__scripts.OnClick(sideRow)
        CHECK(view.sel == tm.id and view.t == nil, "ARENA: clicking a sidebar row opens that match at its end")
    end

    -- Share: plain lines, both teams, first blood
    local arenaShare = FindButton(function(f) return f.headerRole == "arenaShare" end)
    CHECK(arenaShare ~= nil, "ARENA: replay share button found")
    if arenaShare then
        menuCaptured = {}
        arenaShare.__scripts.OnClick(arenaShare)
        local before = #sentChat
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
        CHECK(#sentChat == before + 4, "ARENA: report is four lines", #sentChat - before)
        CHECK(sentChat[before + 1] and sentChat[before + 1].msg:find("ARENA 3v3 Nagrand Arena: WIN") ~= nil,
            "ARENA: report header", sentChat[before + 1] and sentChat[before + 1].msg)
        CHECK(sentChat[before + 2] and sentChat[before + 2].msg:find("^US: ") ~= nil, "ARENA: report US line")
        CHECK(sentChat[before + 3] and sentChat[before + 3].msg:find("^THEM: ") ~= nil, "ARENA: report THEM line")
        CHECK(sentChat[before + 4] and sentChat[before + 4].msg:find("First blood") ~= nil, "ARENA: report first blood line")
        for i = before + 1, #sentChat do
            CHECK(not sentChat[i].msg:find("|c", 1, true), "ARENA: report line " .. (i - before) .. " is plain text")
        end
    end
    -- The DISPEL LOG drawer (open by default): every dispel cast by cast
    do
        view.t = nil
        view.playing = false
        report.__scripts.OnUpdate(report, 0.6)
        Errors("DLOG: repaint clean")
        local btn = FindButton(function(f) return f.headerRole == "arenaDispels" end)
        CHECK(btn ~= nil, "DLOG: the replay header has a DISPELS button")
        CHECK(view.dlog == true, "DLOG: the drawer is open by default")
        CHECK(report.__w == 812 + 300, "DLOG: the window widens by the drawer", report.__w)
        CHECK(fsMatching("^DISPEL LOG$"), "DLOG: titled")
        CHECK(fsMatching("^4 casts$"), "DLOG: counts the match's dispel casts")
        local function Line(pred)
            return FindButton(function(f) return f.dlogLine and f.__shown and f.desc and f.desc.c and pred(f.desc) end)
        end
        local mdLine = Line(function(d) return d.kind == "cast" and d.c.name == "Mass Dispel" end)
        CHECK(mdLine ~= nil, "DLOG: the Mass Dispel is a cast line")
        CHECK(mdLine and mdLine.tag.__text:find("3 removed"), "DLOG: ...that took three auras", mdLine and mdLine.tag.__text)
        local roots = Line(function(d) return d.kind == "hit" and d.h.name == "Entangling Roots" end)
        CHECK(roots and roots.tag.__text:find("DISPEL"), "DLOG: the roots off the mage read as a defensive dispel")
        local gotw = Line(function(d) return d.kind == "hit" and d.h.name == "Gift of the Wild" end)
        CHECK(gotw and gotw.tag.__text:find("PURGE"), "DLOG: Gift of the Wild off the warrior reads as a purge")
        CHECK(mdLine and roots and gotw and mdLine.dlogLine < roots.dlogLine and roots.dlogLine < gotw.dlogLine,
            "DLOG: the removals sit under their cast, in log order")
        CHECK(gotw and gotw.text.__text:find("Gorehowl"), "DLOG: a removal names whom it came off")
        local miss = Line(function(d) return d.kind == "hit" and d.h.r == "RESIST" end)
        CHECK(miss and miss.tag.__text:find("RESISTED"), "DLOG: the felhunter's resisted Devour Magic is a line")
        CHECK(fsMatching("^FREED$") and fsMatching("^OFF$") and fsMatching("^DEF$"), "DLOG: the tally block's columns")
        for _, l in ipairs({ mdLine, roots, miss }) do
            if l then l.__scripts.OnEnter(l); l.__scripts.OnLeave(l) end
        end
        Errors("DLOG: line tooltips clean")
        if mdLine then
            mdLine.__scripts.OnClick(mdLine)
            CHECK(view.t ~= nil and math.abs(view.t - mdLine.desc.c.t) < 1e-6, "DLOG: clicking a cast moves the cursor to it")
            report.__scripts.OnUpdate(report, 0.6)
            local lit = Line(function(d) return d.kind == "cast" and d.c.name == "Mass Dispel" end)
            CHECK(lit and lit.now.__shown == true, "DLOG: the cast at the cursor is lit")
            CHECK(fsMatching("^4 of 4$"), "DLOG: the count reads as of the cursor")
            view.t = 85
            report.__scripts.OnUpdate(report, 0.6)
            local later = Line(function(d) return d.kind == "cast" and d.c.name == "Mass Dispel" end)
            CHECK(later and later.__alpha and later.__alpha < 1, "DLOG: casts past the cursor dim")
            CHECK(fsMatching("^1 of 4$"), "DLOG: one cast before the cursor at 0:25")
        end
        local offChip = FindButton(function(f) return f.chip == "off" end)
        CHECK(offChip ~= nil, "DLOG: filter chips")
        if offChip then
            view.t = nil
            offChip.__scripts.OnClick(offChip)
            report.__scripts.OnUpdate(report, 0.6)
            CHECK(view.dlogOff == false, "DLOG: the OFFENSIVE chip toggles")
            CHECK(Line(function(d) return d.kind == "hit" and d.h.name == "Gift of the Wild" end) == nil, "DLOG: offensive off hides the purges")
            CHECK(Line(function(d) return d.kind == "hit" and d.h.name == "Entangling Roots" end) ~= nil, "DLOG: ...and keeps the dispels")
            offChip.__scripts.OnClick(offChip)
        end
        local themChip = FindButton(function(f) return f.chip == "them" end)
        if themChip then
            themChip.__scripts.OnClick(themChip)
            report.__scripts.OnUpdate(report, 0.6)
            CHECK(Line(function(d) return d.c.src == "Player-1-CMARENA13" end) == nil, "DLOG: THEIRS off hides the enemy's casts")
            CHECK(Line(function(d) return d.c.name == "Mass Dispel" end) ~= nil, "DLOG: ...and keeps ours")
            themChip.__scripts.OnClick(themChip)
        end
        local anyLine = FindButton(function(f) return f.dlogLine == 1 end)
        local list = anyLine and anyLine.__parent
        CHECK(list and list.__scripts.OnMouseWheel ~= nil, "DLOG: the list scrolls")
        if list and list.__scripts.OnMouseWheel then
            report.__scripts.OnUpdate(report, 0.6)
            list.__scripts.OnMouseWheel(list, -1)
            CHECK(view.dlogFollow == false, "DLOG: the wheel stops the list following the cursor")
            view.t = 70
            report.__scripts.OnUpdate(report, 0.6)
            CHECK(view.dlogFollow == true, "DLOG: moving the cursor follows again")
            view.t = nil
        end
        if btn then
            btn.__scripts.OnClick(btn)
            CHECK(view.dlog == false and report.__w == 812, "DLOG: the button closes the drawer, the window shrinks back", report.__w)
            CHECK(CommanderMetersDB.ArenaDispelLog == false, "DLOG: the choice is remembered")
            report.__scripts.OnUpdate(report, 0.6)
            Errors("DLOG: closed repaint clean")
            btn.__scripts.OnClick(btn)
            CHECK(view.dlog == true and report.__w == 1112, "DLOG: ...and opens it again")
        end
        -- The meter window's ARENA DISPELS mode: both teams, the split per row
        CommanderMetersDB.ViewMode = "ARENA_DISPEL"
        CommanderMetersDB.SplitOpen = false
        Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
        root.__scripts.OnUpdate(root, 0.6)
        Errors("DLOG: ARENA DISPELS pane clean")
        local pr = FindButton(function(f) return f.paneIndex == 1 and f.rank and f.guid == "Player-0-CMARENA03" and f.__shown end)
        CHECK(pr and pr.value.__text == "5", "DLOG: the priest's five removals", pr and pr.value.__text)
        CHECK(pr and pr.rate.__text:find("3|r", 1, true) and pr.rate.__text:find("2|r", 1, true),
            "DLOG: the row reads 3 offensive / 2 defensive", pr and pr.rate.__text)
        if pr then
            pr.__scripts.OnEnter(pr)
            Errors("DLOG: seat tooltip with the dispel lines clean")
            pr.__scripts.OnLeave(pr)
        end
    end
    io.write(string.format("ARENA: canned 3v3 serializes to %.0f KB (%d moments)\n", #A.Serialize(tm) / 1024, tm.ledgerN))

    local special = false
    for _, name in ipairs(UISpecialFrames) do if name == "CommanderMetersArenaFrame" then special = true end end
    CHECK(special, "ARENA: replay closes on Escape")

    -- ARENA pane mode in the meter window: our team first, then theirs
    _G.CommanderMetersArenaFrame:Hide()
    CommanderMetersDB.ViewMode = "ARENA_DMG"
    CommanderMetersDB.SplitOpen = false
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    root.__scripts.OnUpdate(root, 0.6)
    Errors("ARENA: arena pane repaint clean")
    local enemyRow = FindButton(function(f) return f.paneIndex == 1 and f.rank and f.guid == "Player-1-CMARENA11" end)
    CHECK(enemyRow ~= nil, "ARENA: enemy seat painted in the meter pane")
    if enemyRow then
        CHECK(enemyRow.team and enemyRow.team.__shown == true, "ARENA: team stripe shown on an arena row")
        CHECK(enemyRow.team.__color and enemyRow.team.__color[1] == 0.90, "ARENA: enemy stripe is red")
        CHECK(enemyRow.rank.__text == 1, "ARENA: enemy rank is within the enemy team (the warrior leads it)", enemyRow.rank.__text)
        enemyRow.__scripts.OnEnter(enemyRow)
        Errors("ARENA: arena row tooltip clean")
        enemyRow.__scripts.OnLeave(enemyRow)
        enemyRow.__scripts.OnClick(enemyRow)
        CHECK(_G.CommanderMetersArenaFrame.__shown == true, "ARENA: clicking an arena row opens the replay")
        CHECK(_G.CommanderMetersDetailFrame.__shown == false, "ARENA: arena rows never open the detail popup")
    end
    -- Our team's rows come before theirs, whatever the values
    do
        local firstEnemyAt, lastUsAt = 99, 0
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.paneIndex == 1 and f.rank and f.guid and f.__shown then
                local seat = tm.seats[f.guid]
                local slot = tonumber(f.rank.__text) or 0
                if seat and seat.team == "them" then firstEnemyAt = math.min(firstEnemyAt, slot) end
            end
        end
        local usRow = FindButton(function(f) return f.paneIndex == 1 and f.rank and f.guid == "Player-0-CMARENA01" end)
        CHECK(usRow and usRow.team.__color and usRow.team.__color[1] == 0.30, "ARENA: friendly stripe is blue")
        -- Pane rows are painted top to bottom in creation order: the first
        -- three carry our guids, the last three theirs
        local order = {}
        for _, f in ipairs(frames) do
            if f.__kind == "Button" and f.paneIndex == 1 and f.rank and f.guid and f.__shown then order[#order + 1] = tm.seats[f.guid].team end
        end
        CHECK(#order == 6 and order[1] == "us" and order[3] == "us" and order[4] == "them" and order[6] == "them",
            "ARENA: pane lists our three seats, then their three — never interleaved", table.concat(order, ","))
    end
    CHECK(fsMatching("ARENA DMG"), "ARENA: header mode label")
    local graphBtn = FindButton(function(f) return f.glyphName == "graph" end)
    if graphBtn then
        graphBtn.__scripts.OnClick(graphBtn)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(fsMatching("ARENA REPORT"), "ARENA: graph band points at the replay")
        graphBtn.__scripts.OnClick(graphBtn)
    end
    local headerShare = FindButton(function(f) return f.headerRole == "share" end)
    if headerShare then
        menuCaptured = {}
        headerShare.__scripts.OnClick(headerShare)
        local before = #sentChat
        for _, info in ipairs(menuCaptured) do
            if info.text == "GUILD" then info.func() end
        end
        CHECK(#sentChat > before and sentChat[before + 1].msg:find("ARENA DMG") ~= nil, "ARENA: pane report header names the arena mode")
    end
    CommanderMetersDB.ViewMode = "DMG"
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    root.__scripts.OnUpdate(root, 0.6)
    local anyStripe = false
    for _, f in ipairs(frames) do
        if f.__kind == "Button" and f.paneIndex == 1 and f.team and f.team.__shown then anyStripe = true end
    end
    CHECK(not anyStripe, "ARENA: team stripes hide outside arena modes")

    -- A LIVE match through the event path: zone in, opponents appear, HP
    -- arrives, blows land, a winner is declared, the scoreboard is read
    local units = {
        player = { guid = playerGuid, name = "Devinp", class = "WARRIOR", race = "Human", hp = 9000, max = 9000 },
        party1 = { guid = "Player-0-P1", name = "Hallow", class = "PRIEST", race = "Dwarf", hp = 7000, max = 7000 },
        arena1 = { guid = "Player-1-E1", name = "Rime", class = "MAGE", race = "Undead", hp = 6000, max = 6000 },
    }
    function UnitExists(unit) return units[unit] ~= nil end
    function UnitGUID(unit) return units[unit] and units[unit].guid end
    function UnitName(unit) return units[unit] and units[unit].name end
    function UnitClass(unit) local u = units[unit]; if u then return u.class, u.class end end
    function UnitRace(unit) local u = units[unit]; if u then return u.race, u.race end end
    function UnitHealth(unit) return units[unit] and units[unit].hp or 5000 end
    function UnitHealthMax(unit) return units[unit] and units[unit].max or 8000 end
    local winner, ourFaction = nil, 1
    function GetBattlefieldWinner() return winner end
    function GetBattlefieldArenaFaction() return ourFaction end
    function GetBattlefieldInstanceRunTime() return 95000 end
    local scoreRows = {
        { "Devinp-Realm", 1, 2, 0, 0, 1, 0, "Human", "Warrior", "WARRIOR", 12000, 300, 11, 1700 },
        { "Rime", 0, 0, 1, 0, 0, 0, "Undead", "Mage", "MAGE", 8000, 0, -9, 1650 },
        -- An enemy the log never saw: seated from the scoreboard alone
        { "Wraith", 0, 0, 0, 0, 0, 0, "Orc", "Warlock", "WARLOCK", 3000, 0, -9, 1640 },
    }
    function GetNumBattlefieldScores() return #scoreRows end
    function GetBattlefieldScore(i) return unpack(scoreRows[i]) end
    function GetBattlefieldTeamInfo(index)
        if index == 1 then return "Home Team", 1700, 1711, 1705 end
        return "Away Team", 1660, 1651, 1648
    end

    instState.inInstance, instState.itype, instState.id = true, "arena", 559
    Fire("PLAYER_ENTERING_WORLD", false, false)
    CHECK(A.Live() ~= nil, "ARENA: zoning into an arena begins a match")
    local live = A.Live()
    CHECK(live and live.seats[playerGuid] and live.seats[playerGuid].team == "us", "ARENA: player seated on US")
    CHECK(live and live.seats["Player-0-P1"] ~= nil, "ARENA: party member seated")
    CHECK(live and live.seats["Player-1-E1"] and live.seats["Player-1-E1"].team == "them", "ARENA: arena1 seated on THEM")
    CHECK(live and live.seats["Player-1-E1"].race == "Undead", "ARENA: race read from the unit")
    CHECK(live and live.bracket == 2, "ARENA: bracket 2 from the rosters", live and live.bracket)
    CHECK(live and live.map == "Azeroth", "ARENA: map from GetInstanceInfo")
    -- A second opponent shows up later
    units.arena2 = { guid = "Player-1-E2", name = "Sting", class = "HUNTER", race = "Orc", hp = 8000, max = 8000 }
    Fire("ARENA_OPPONENT_UPDATE", "arena2", "seen")
    CHECK(live.seats["Player-1-E2"] ~= nil, "ARENA: late opponent seated on ARENA_OPPONENT_UPDATE")
    -- The enemy trinket, from the CLIENT (C_PvP.GetArenaCrowdControlInfo:
    -- spellId, start and duration in ms on the GetTime clock, zero while up)
    local trinketInfo = {}
    local asked = {}
    C_PvP = {
        GetArenaCrowdControlInfo = function(unit)
            local t = trinketInfo[unit]
            if t then return t[1], t[2], t[3] end
            return 195710, 0, 0
        end,
        RequestCrowdControlSpell = function(unit) asked[unit] = (asked[unit] or 0) + 1 end,
    }
    Fire("ARENA_COOLDOWNS_UPDATE")
    CHECK(live.seats["Player-1-E1"].trinkets == 0, "TRINKET: a ready trinket records nothing")
    CHECK(asked.arena1 == 1, "TRINKET: the client is asked for each enemy's trinket once")
    -- arena1 pressed it two seconds ago: an item spell id the log table never had
    -- (ten seconds into the match, so "two seconds ago" is inside it)
    now = now + 10
    trinketInfo.arena1 = { 195710, (GetTime() - 2) * 1000, 120000 }
    Fire("ARENA_CROWD_CONTROL_SPELL_UPDATE", "arena1")
    CHECK(live.seats["Player-1-E1"].trinkets == 1, "TRINKET: the client's answer records the enemy's press")
    do
        local e
        for i = live.ledgerN, 1, -1 do if live.ledger[i].kind == "TRINKET" then e = live.ledger[i]; break end end
        CHECK(e and e.src == "Player-1-E1" and e.amount == 120, "TRINKET: the moment carries the client's cooldown length")
        CHECK(e and math.abs((e.t0 or e.t) - ((time() - 2) - live.tsStart)) < 1e-6, "TRINKET: the press is stamped when it started, not when it was read")
    end
    RunTickers()
    Fire("ARENA_COOLDOWNS_UPDATE")
    CHECK(live.seats["Player-1-E1"].trinkets == 1 and asked.arena1 == 1, "TRINKET: re-reading the same press each second stays one press, one request")
    -- Our own side: the cast event names the unit and the spell
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 42292)
    CHECK(live.seats[playerGuid].trinkets == 1, "TRINKET: our own press is recorded from the cast event")
    Fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 133)
    Fire("UNIT_SPELLCAST_SUCCEEDED", "target", "Cast-3", 42292)
    CHECK(live.seats[playerGuid].trinkets == 1, "TRINKET: other spells and other unit tokens are ignored")
    -- The replay's badge reads it down
    CommanderMetersArena_Open()
    report.__scripts.OnUpdate(report, 0.6)
    do
        local eb = FindButton(function(f) return f.trinketBadge and f.__parent and f.__parent.guid == "Player-1-E1" end)
        CHECK(eb and eb.text.__text ~= "" and eb.sweep.__cdDur == 120, "TRINKET: the enemy's badge is down with its clock and sweep", eb and eb.text.__text)
    end
    Errors("TRINKET: live badge repaint clean")

    -- Feign Death on the enemy hunter (arena2): not a death, and the card says FEIGN
    do
        local hg = "Player-1-E2"
        A.OnCleu(time(), "SPELL_AURA_APPLIED", nil, hg, "Sting", 0x548, 0, hg, "Sting", 0x548, 0, 5384, "Feign Death", 1, "BUFF")
        A.OnCleu(time() + 0.2, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, hg, "Sting", 0x548, 0)
        CHECK(live.seats[hg].deaths == 0 and #live.deaths == 0, "FEIGN: the hunter's feign is not a death in a live match")
        now = now + 1
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(fsMatching("FEIGN|r"), "FEIGN: the card reads FEIGN while the aura is on")
        Errors("FEIGN: repaint clean")
        A.OnCleu(time() + 1, "SPELL_AURA_REMOVED", nil, hg, "Sting", 0x548, 0, hg, "Sting", 0x548, 0, 5384, "Feign Death", 1, "BUFF")
        now = now + 3
        report.__scripts.OnUpdate(report, 0.6)
        CHECK(not fsMatching("^|c%x+FEIGN|r$"), "FEIGN: the card recovers when the feign is cancelled")
    end

    -- UNIT_HEALTH feeds the replay while the match is on
    units.arena1.hp = 3000
    Fire("UNIT_HEALTH", "arena1")
    CHECK(live.seats["Player-1-E1"].sHp ~= nil, "ARENA: UNIT_HEALTH fed an hp snapshot")
    -- The ticker samples everyone once a second
    RunTickers()
    CHECK(live.seats[playerGuid].sHp ~= nil, "ARENA: the ticker samples friendly hp")
    -- The CORE meter reads the match as one fight (D28): armed on entry
    CHECK(CommanderMetersEngine.InMatch(), "ARENA: entering the arena arms the core meter's match mode")
    local coreFightsBefore = #CommanderMetersEngine.GetFights()
    -- Blows through the engine (the harness has no combat-log getter mock)
    local ts = time()
    CommanderMetersEngine.OnCleu(ts + 5, "SWING_DAMAGE", nil, playerGuid, "Devinp", 0x511, 0, "Player-1-E1", "Rime", 0x548, 0, 700, 0, 1, 0, 0, 0, false, false, false, false)
    CommanderMetersEngine.SetPlayerCombat(false, ts + 6)
    now = now + 30
    RunTickers()
    CHECK(CommanderMetersEngine.InFight(), "ARENA: the core fight stays open through a lull inside the match")
    A.OnCleu(ts, "SPELL_AURA_REMOVED", nil, playerGuid, "Devinp", 0x511, 0, playerGuid, "Devinp", 0x511, 0, 32727, "Arena Preparation", 1, "BUFF")
    A.OnCleu(ts + 5, "SWING_DAMAGE", nil, playerGuid, "Devinp", 0x511, 0, "Player-1-E1", "Rime", 0x548, 0, 700, 0, 1, 0, 0, 0, false, false, false, false)
    A.OnCleu(ts + 6, "SPELL_DAMAGE", nil, "Player-1-E1", "Rime", 0x548, 0, playerGuid, "Devinp", 0x511, 0, 27072, "Frostbolt", 16, 1200, 0, 16, 0, 0, 0, true, false, false, false)
    A.OnCleu(ts + 7, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, "Player-1-E1", "Rime", 0x548, 0)
    -- Meter window in arena mode shows the live match with a live caption
    CommanderMetersDB.ViewMode = "ARENA_DMG"
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    root.__scripts.OnUpdate(root, 0.6)
    Errors("ARENA: live arena pane repaint clean")
    CHECK(fsMatching("LIVE"), "ARENA: live match labeled LIVE")
    do
        local segButton = FindButton(function(f) return f.headerRole == "segment" end)
        CHECK(segButton and type(segButton.text.__text) == "string" and segButton.text.__text:find("LIVE", 1, true) ~= nil,
            "ARENA: the header segment button names the match while the left pane is arena",
            segButton and segButton.text.__text)
    end
    -- The report follows the live match if it is open
    CommanderMetersArena_Open()
    CHECK(view.sel == "live", "ARENA: opening during a match reads the live match")
    report.__scripts.OnUpdate(report, 0.6)
    Errors("ARENA: live report repaint clean")
    -- The scoreboard update before a winner changes nothing
    Fire("UPDATE_BATTLEFIELD_SCORE")
    CHECK(A.Live() == live, "ARENA: no winner yet keeps the match live")
    -- Winner declared: our faction wins
    winner = 1
    Fire("UPDATE_BATTLEFIELD_SCORE")
    CHECK(A.Live() == nil, "ARENA: winner declared ends the match")
    CHECK(not CommanderMetersEngine.InMatch() and not CommanderMetersEngine.InFight(), "ARENA: the winner closes the core meter's match fight")
    do
        local cf = CommanderMetersEngine.GetFights()[1]
        CHECK(#CommanderMetersEngine.GetFights() == coreFightsBefore + 1, "ARENA: one core segment for the whole match")
        CHECK(cf and cf.match == true and cf.success == true and cf.name == "3v3 Azeroth",
            "ARENA: the core segment is named after the match and tagged WIN", cf and cf.name)
        -- The left pane is still in an ARENA mode here (its header names
        -- the replay's match); a plain mode shows the SEGMENT label
        CommanderMetersDB.ViewMode = "DMG"
        Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
        root.__scripts.OnUpdate(root, 0.6)
        CHECK(fsMatching("LAST — 3V3 AZEROTH.*WIN"), "ARENA: the meter window's segment label reads the match with its WIN tag")
        CommanderMetersDB.ViewMode = "ARENA_DMG"
        Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    end
    local done = A.GetMatches()[1]
    CHECK(done == live and done.result == "WIN", "ARENA: live match archived as WIN")
    CHECK(done.runTime == 95, "ARENA: server run time recorded (s)")
    CHECK(done.seats[playerGuid].sb and done.seats[playerGuid].sb.ratingChange == 11, "ARENA: scoreboard merged on finish")
    CHECK(done.seats[playerGuid].kills == 1 and done.seats["Player-1-E1"].deaths == 1, "ARENA: kill and death credited")
    CHECK(done.teams.us.name == "Home Team" and done.teams.us.ratingAfter == 1711, "ARENA: our team info from index 1 (our faction)")
    CHECK(done.teams.them.name == "Away Team", "ARENA: their team info from the other index")
    CHECK(done.rated == true, "ARENA: rated by rating change")
    local wraith = done.seats["Score-Wraith"]
    CHECK(wraith and wraith.team == "them" and wraith.fromScoreboard and wraith.class == "WARLOCK",
        "ARENA: an unseen enemy on the scoreboard took a seat on THEM")
    CHECK(done.bracket == 3, "ARENA: bracket grows to 3 once a third enemy is seated from the scoreboard", done.bracket)
    CHECK(view.sel == done.id, "ARENA: report switched to the finished match")
    report.__scripts.OnUpdate(report, 0.6)
    Errors("ARENA: finished report repaint clean")
    CHECK(fsMatching("scoreboard only"), "ARENA: a scoreboard-only seat is labeled as such")
    CHECK(#A.GetMatches() == 2, "ARENA: two matches kept")
    -- A LOSS reads as a loss
    winner = 0
    instState.itype = "none"; instState.inInstance = false
    Fire("PLAYER_ENTERING_WORLD", false, false)
    CHECK(A.Live() == nil, "ARENA: leaving with no live match is quiet")
    instState.itype = "arena"; instState.inInstance = true
    Fire("ZONE_CHANGED_NEW_AREA")
    CHECK(A.Live() ~= nil, "ARENA: zone change into an arena begins a match")
    A.OnCleu(ts + 100, "SWING_DAMAGE", nil, playerGuid, "Devinp", 0x511, 0, "Player-1-E1", "Rime", 0x548, 0, 100, 0, 1, 0, 0, 0, false, false, false, false)
    Fire("UPDATE_BATTLEFIELD_SCORE")
    CHECK(A.GetMatches()[1].result == "LOSS", "ARENA: the other faction winning is a LOSS")
    -- Leaving mid-match with no winner archives as LEFT only if played
    winner = nil
    Fire("ZONE_CHANGED_NEW_AREA") -- still in the arena: a new match begins
    local third = A.Live()
    CHECK(third ~= nil, "ARENA: a fresh match begins")
    instState.itype = "none"; instState.inInstance = false
    Fire("ZONE_CHANGED_NEW_AREA")
    CHECK(A.Live() == nil and #A.GetMatches() == 3, "ARENA: an unplayed match is discarded on leaving", #A.GetMatches())

    -- A battleground is one fight per match too (no replay): enter, fight, a lull, the winner
    function UnitFactionGroup() return "Alliance", "Alliance" end
    winner = nil
    instState.inInstance, instState.itype, instState.id = true, "pvp", 529
    Fire("PLAYER_ENTERING_WORLD", false, false)
    CHECK(CommanderMetersEngine.InMatch(), "BG: entering a battleground arms match mode")
    CHECK(A.Live() == nil, "BG: no arena replay is recorded for a battleground")
    local bgBefore = #CommanderMetersEngine.GetFights()
    CommanderMetersEngine.OnCleu(ts + 300, "SWING_DAMAGE", nil, playerGuid, "Devinp", 0x511, 0, "Player-1-H9", "Hordie", 0x548, 0, 500, 0, 1, 0, 0, 0, false, false, false, false)
    CommanderMetersEngine.SetPlayerCombat(false, ts + 301)
    now = now + 120
    RunTickers()
    CHECK(CommanderMetersEngine.InFight(), "BG: a two-minute lull at a node does not close the fight")
    winner = 1 -- Alliance
    Fire("UPDATE_BATTLEFIELD_SCORE")
    CHECK(not CommanderMetersEngine.InFight() and #CommanderMetersEngine.GetFights() == bgBefore + 1, "BG: the winner closes the match fight")
    do
        local bf = CommanderMetersEngine.GetFights()[1]
        CHECK(bf and bf.match == true and bf.success == true and bf.name == "Azeroth", "BG: named after the battleground, tagged WIN", bf and bf.name)
    end
    instState.inInstance, instState.itype, instState.id = false, "none", 0
    Fire("PLAYER_ENTERING_WORLD", false, false)
    CHECK(not CommanderMetersEngine.InMatch(), "BG: leaving disarms match mode")

    -- Logout writes the history; zero keeps nothing
    Fire("PLAYER_LOGOUT")
    CHECK(type(CommanderMetersArenaLog) == "table" and CommanderMetersArenaLog.v == 1
        and #CommanderMetersArenaLog.matches == 3, "ARENA: logout exported the matches")
    CommanderMetersDB.ArenaKeepMatches = 0
    Fire("PLAYER_LOGOUT")
    CHECK(CommanderMetersArenaLog == nil, "ARENA: Keep Matches 0 writes no history")
    CommanderMetersDB.ArenaKeepMatches = 10

    -- Forget drops everything and the open report paints an empty state clean
    CommanderMeters_ArenaForget()
    CHECK(#A.GetMatches() == 0, "ARENA: forget clears the matches")
    report.__scripts.OnUpdate(report, 0.6)
    Errors("ARENA: empty report repaint clean")
    CHECK(fsMatching("NO MATCH RECORDED"), "ARENA: empty report says so")
    CommanderMetersDB.ViewMode = "DMG"
    Commander.Notify(COMMANDER_METERS_EVENTS.UPDATE)
    root.__scripts.OnUpdate(root, 0.6)
    Errors("ARENA: final repaint clean")
end

if fails > 0 then
    io.write(string.format("RESULT: %d/%d FAILED\n", fails, checks))
    for _, e in ipairs(harnessFailedErrors) do io.write("ERR: ", e, "\n") end
    os.exit(1)
end
io.write(string.format("STAGE C: all %d checks passed (%d fontstrings, %d frames)\n",
    checks, #allFontStrings, #frames))
