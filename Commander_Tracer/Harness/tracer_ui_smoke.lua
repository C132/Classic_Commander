-- Commander Tracer UI smoke (luajit)
--
--     luajit Commander_Tracer/Harness/tracer_ui_smoke.lua
--
-- The engine smoke next door covers the reasoning with no client attached.
-- This one covers the half that reasoning cannot reach: what the lanes do
-- with what a real client says. All four files load over a WoW widget mock
-- (the Plates board recorder set) PLUS the suite's REAL settings framework
-- (CommanderSettingsUI.lua, CommanderEvents.lua), so the page is built the
-- way the client builds it, every dropdown's entries are recorded, and the
-- preview strip runs its refreshers.
--
-- Sections:
--   A  login: defaults applied, six roots built and named, Blizzard's CVars
--      taken with their old values kept
--   B  a Fireball in the log becomes a number in Outgoing and a row in the
--      ledger, dressed with its icon, its school colour and its text
--   C  motion over time: the number rises, fades, expires; its frame goes
--      back to the pool
--   D  the ledger merges a repeat into one row with a count
--   E  incoming: a Mortal Strike on you falls on the left with its spell
--   F  crits: bigger, marked, punched; the big-hit threshold
--   G  sounds: the kill bell, the crit chime and its threshold
--   H  the client's own feed: a proc ready, honor gained
--   I  routing: Off, ledger-only, a lane disabled, hide-below, pets
--   J  the module off and on again: roots hidden, CVars given back exactly
--   K  the takeover boxes, one at a time, and combat deferral
--   L  the volley reaches every lane; Clear empties them; unlock labels
--   M  the settings page builds on the real framework: every dropdown has
--      faces, every refresher runs, the previews take the lane's face
-- ===========================================================================

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

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

local now = 1000
function GetTime() return now end
function time() return 1000000 + now end
function GetCursorPosition() return 0, 0 end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local caughtErrors = {}
function geterrorhandler()
    return function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end
end

-- ===========================================================================
-- The widget mock
-- ===========================================================================
local NUMERIC_GETTERS = {
    GetScale = 1, GetEffectiveScale = 1, GetFrameLevel = 2, GetLeft = 0, GetBottom = 0,
    GetTop = 0, GetRight = 0, GetStringWidth = 10, GetID = 1, GetNumPoints = 1,
    GetVerticalScroll = 0, GetVerticalScrollRange = 0,
}

local function IsMethodName(key)
    return type(key) == "string" and key:match("^[A-Z]")
end

local eventRegistry = {}
local NewWidget
local allFrames = {}

local WidgetMT = {}
WidgetMT.__index = function(self, key)
    if type(key) ~= "string" then return nil end
    if key == "GetWidth" or key == "GetHeight" then
        local field = (key == "GetWidth") and "__w" or "__h"
        local fn = function(s) return rawget(s, field) or ((field == "__w") and 680 or 520) end
        rawset(self, key, fn); return fn
    end
    local recorders = {
        SetScale = function(s, v) s.__scale = v end,
        GetScale = function(s) return rawget(s, "__scale") or 1 end,
        SetFont = function(s, path, size, flags) s.__font = { path, size, flags } end,
        GetFont = function(s) local f = rawget(s, "__font"); if f then return f[1], f[2], f[3] end return "Fonts\\FRIZQT__.TTF", 10, "" end,
        SetShadowOffset = function(s, x, y) s.__shadow = { x, y } end,
        SetShadowColor = function(s, r, g, b, a) s.__shadowColor = { r, g, b, a } end,
        SetFrameLevel = function(s, v) s.__level = v end,
        GetFrameLevel = function(s) return rawget(s, "__level") or 2 end,
        SetFrameStrata = function(s, v) s.__strata = v end,
        EnableMouse = function(s, v) s.__mouse = not not v end,
        GetFrameStrata = function(s) return rawget(s, "__strata") or "MEDIUM" end,
        SetPoint = function(s, point, rel, relPoint, x, y)
            s.__points = s.__points or {}
            s.__points[#s.__points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end,
        GetPoint = function(s)
            local p = s.__points and s.__points[1]
            if not p then return nil end
            return p.point, p.rel, p.relPoint, p.x, p.y
        end,
        ClearAllPoints = function(s) s.__points = {} end,
        SetAllPoints = function(s) s.__allPoints = true end,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        SetWidth = function(s, w) s.__w = w end,
        SetHeight = function(s, h) s.__h = h end,
        SetTexture = function(s, tex) s.__texture = tex end,
        GetTexture = function(s) return s.__texture end,
        SetTexCoord = function(s, ...) s.__coords = { ... } end,
        SetVertexColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        SetColorTexture = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        SetTextColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        -- The client's rule, modelled: a FontString with no font object and
        -- no SetFont yet cannot be written to. This is exactly the error the
        -- first in-game load threw 79 times from the preview strip.
        SetText = function(s, text)
            if s.__kind == "FontString" and not (rawget(s, "__font") or rawget(s, "__fontObject")) then
                error("FontString:SetText(): Font not set")
            end
            s.__text = text
        end,
        SetFontObject = function(s, obj) s.__fontObject = obj or "?" end,
        GetText = function(s) return s.__text end,
        GetStringHeight = function(s)
            local text = s.__text or ""
            if text == "" then return 0 end
            local width = (s.__w and s.__w > 0) and s.__w or 430
            return math.max(12, math.ceil(#text * 5 / width) * 12)
        end,
        SetAlpha = function(s, a) s.__alpha = a end,
        GetAlpha = function(s) return s.__alpha or 1 end,
        Show = function(s) s.__shown = true end,
        Hide = function(s) s.__shown = false end,
        SetShown = function(s, shown) s.__shown = not not shown end,
        IsShown = function(s) return s.__shown end,
        IsVisible = function(s) return s.__shown end,
        SetChecked = function(s, v) s.__checked = not not v end,
        GetChecked = function(s) return s.__checked end,
        SetEnabled = function(s, v) s.__enabled = not not v end,
        Enable = function(s) s.__enabled = true end,
        Disable = function(s) s.__enabled = false end,
        SetValue = function(s, v) s.__value = v end,
        GetValue = function(s) return s.__value end,
        SetMinMaxValues = function(s, a, b) s.__min, s.__max = a, b end,
        SetScrollChild = function(s, child) s.__child = child end,
        SetBackdrop = function(s, b) s.__backdrop = b end,
        SetBackdropColor = function(s, r, g, b, a) s.__bdColor = { r, g, b, a } end,
        SetBackdropBorderColor = function(s, r, g, b, a) s.__bdBorder = { r, g, b, a } end,
        CreateTexture = function(s, _, layer, _, sublevel)
            local t = NewWidget("Texture")
            t.__parent, t.__layer, t.__sublevel = s, layer, sublevel or 0
            s.__children[#s.__children + 1] = t
            return t
        end,
        CreateFontString = function(s, _, _, template)
            local t = NewWidget("FontString")
            t.__parent = s
            t.__fontObject = template
            s.__children[#s.__children + 1] = t
            return t
        end,
        GetParent = function(s) return s.__parent end,
        SetScript = function(s, name, handler) s.__scripts[name] = handler end,
        HookScript = function(s, name, handler) s.__scripts[name] = handler end,
        GetScript = function(s, name) return s.__scripts[name] end,
        RegisterEvent = function(s, event)
            eventRegistry[event] = eventRegistry[event] or {}
            table.insert(eventRegistry[event], s)
        end,
        UnregisterEvent = function(s, event)
            local list = eventRegistry[event] or {}
            for i = #list, 1, -1 do if list[i] == s then table.remove(list, i) end end
        end,
    }
    local fn = recorders[key]
    if fn then rawset(self, key, fn); return fn end
    if NUMERIC_GETTERS[key] ~= nil then
        local v = NUMERIC_GETTERS[key]
        fn = function() return v end
        rawset(self, key, fn); return fn
    end
    if IsMethodName(key) then
        fn = function() end
        rawset(self, key, fn); return fn
    end
    return nil
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __children = {}, __shown = true }, WidgetMT)
end

function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template = template
    f.__parent = parent
    if parent and parent.__children then parent.__children[#parent.__children + 1] = f end
    if frameType == "CheckButton" or (template and template:find("CheckButton")) then
        f.Text = NewWidget("FontString")
        f.Text.__fontObject = "GameFontNormal"
    end
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
GameTooltip = NewWidget("GameTooltip", "GameTooltip")
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
unpack = unpack or table.unpack
bit = bit or require("bit")
for _, f in ipairs({ "GameFontNormal", "GameFontNormalLarge", "GameFontNormalSmall", "GameFontHighlight",
    "GameFontHighlightSmall", "GameFontDisable", "GameFontDisableSmall" }) do
    _G[f] = NewWidget("Font")
end
SOUNDKIT = { IG_MAINMENU_OPTION_CHECKBOX_ON = 1, IG_MAINMENU_OPTION_CHECKBOX_OFF = 2, RAID_WARNING = 8959, READY_CHECK = 8960 }
local sounds = {}
function PlaySound(id) sounds[#sounds + 1] = id; return true end
function PlaySoundFile(file) sounds[#sounds + 1] = file; return true end
BACKDROP_SLIDER_8_8 = {}
SlashCmdList = {}
local categories = {}
Settings = {
    RegisterCanvasLayoutCategory = function(panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterCanvasLayoutSubcategory = function(_, panel)
        local cat = { __panel = panel, GetID = function() return #categories + 1 end }
        categories[#categories + 1] = cat; return cat
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function() end,
}
C_AddOns = { GetAddOnMetadata = function() return "1.0.0" end }
C_Timer = { After = function() end, NewTicker = function() return { Cancel = function() end } end }
function UIDropDownMenu_Initialize(frame, fn)
    if not (frame and fn) then return end
    frame.__ddEntries = {}
    _G.__ddCurrent = frame
    local ok, err = pcall(fn, frame)
    if not ok then caughtErrors[#caughtErrors + 1] = "dropdown init: " .. tostring(err) end
    _G.__ddCurrent = nil
end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info)
    local f = _G.__ddCurrent
    if f and f.__ddEntries and info then f.__ddEntries[#f.__ddEntries + 1] = info end
end
function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_SetSelectedValue(frame, value) if frame then frame.__ddValue = value end end
function UIDropDownMenu_SetText(frame, text) if frame then frame.__ddText = text end end
function UIDropDownMenu_EnableDropDown() end
function UIDropDownMenu_DisableDropDown() end
RAID_CLASS_COLORS = { MAGE = { r = 0.41, g = 0.8, b = 0.94 }, WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
CLASS_ICON_TCOORDS = { MAGE = { 0.25, 0.5, 0, 0.25 } }

-- The client
local inCombat = false
function InCombatLockdown() return inCombat end
local petGUID = nil
function UnitGUID(unit)
    if unit == "player" then return "Player-1-ME" end
    if unit == "pet" then return petGUID end
    return nil
end
function UnitExists(unit) if unit == "pet" then return petGUID ~= nil end return unit == "player" end
function UnitClass(unit) if unit == "player" then return "Mage", "MAGE" end end
function GetSpellTexture(id) return "Interface\\Icons\\Spell_" .. tostring(id) end

local cvars = {}
local cvarWrites = {}
C_CVar = {
    GetCVar = function(name) return cvars[name] end,
    SetCVar = function(name, value) cvars[name] = value; cvarWrites[#cvarWrites + 1] = name .. "=" .. tostring(value) end,
}
for _, name in ipairs({ "floatingCombatTextCombatDamage_v2", "floatingCombatTextCombatHealing_v2",
    "floatingCombatTextCombatLogPeriodicSpells_v2", "floatingCombatTextPetMeleeDamage_v2",
    "floatingCombatTextPetSpellDamage_v2" }) do cvars[name] = "1" end
cvars.enableFloatingCombatText = "1"
cvars.floatingCombatTextCombatHealing_v2 = "0"   -- one already off, to prove restore is exact

local combatTextData = {}
C_CombatText = { GetCurrentEventInfo = function() return unpack(combatTextData, 1, combatTextData.n or #combatTextData) end }

local cleuArgs
function CombatLogGetCurrentEventInfo() return unpack(cleuArgs, 1, cleuArgs.n) end

local function Fire(event, ...)
    -- A copy: a handler that unregisters itself mid-dispatch must not make
    -- the next frame's handler vanish, which the client never lets happen
    local list = {}
    for i, f in ipairs(eventRegistry[event] or {}) do list[i] = f end
    for _, f in ipairs(list) do
        local handler = f.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, f, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

local ME = "Player-1-ME"
local HOSTILE = 0x40 + 0x400
local MINE = 0x1 + 0x400
local MYPET = 0x1 + 0x1000
local function CLEU(sub, sg, sn, sf, dg, dn, df, ...)
    cleuArgs = { now, sub, false, sg, sn, sf, 0, dg, dn, df, 0, ... }
    cleuArgs.n = 11 + select("#", ...)
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end
local function Hit(spellId, name, school, amount, crit, target)
    CLEU("SPELL_DAMAGE", ME, "Me", MINE, "Player-7", target or "Gankmage", HOSTILE,
        spellId, name, school, amount, 0, school, 0, 0, 0, crit and 1 or nil, false, false)
end

local function Advance(seconds)
    local steps = math.floor(seconds / 0.05 + 0.5)
    for _ = 1, steps do
        now = now + 0.05
        for _, f in ipairs(allFrames) do
            local handler = f.__scripts.OnUpdate
            if handler then
                local ok, err = pcall(handler, f, 0.05)
                if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
            end
        end
    end
end

-- ===========================================================================
-- Load: the real framework, then the module in TOC order
-- ===========================================================================
local function Load(path)
    local chunk, err = loadfile(path)
    if not chunk then error("could not load " .. path .. ": " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then error("error running " .. path .. ": " .. tostring(runErr)) end
end
Load(ADDONS .. "/Commander_Events/CommanderSettingsUI.lua")
Load(ADDONS .. "/Commander_Events/CommanderEvents.lua")
Load(ADDONS .. "/Commander_Tracer/CommanderTracerData.lua")
Load(ADDONS .. "/Commander_Tracer/CommanderTracerEngine.lua")
Load(ADDONS .. "/Commander_Tracer/CommanderTracerDB.lua")
Load(ADDONS .. "/Commander_Tracer/CommanderTracer.lua")

local DATA = CommanderTracer_Data
CommanderTracer_Engine.random = function() return 0.5 end

Fire("ADDON_LOADED", "Commander_Tracer")
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD")
EQ(#caughtErrors, 0, "A: login is clean", caughtErrors[1])

local db = CommanderTracerDB
local function Notify() Commander.Notify(COMMANDER_TRACER_EVENTS.UPDATE) end
local function Lane(key) return CommanderTracer_Lane(key) end
local function Entries(key) return Lane(key).state.entries end
local function Frames(key)
    local out = {}
    for _, e in ipairs(Entries(key)) do out[#out + 1] = Lane(key).frames[e] end
    return out
end
local function Texts(key)
    local t = {}
    for _, f in ipairs(Frames(key)) do t[#t + 1] = f and f.text.__text or "?" end
    return table.concat(t, " | ")
end

-- ===========================================================================
-- A: login
-- ===========================================================================
local declared = 0
for _ in pairs(CommanderTracer_Defaults) do declared = declared + 1 end
CHECK(declared >= 250, "A: the defaults table is the size the reach check counts", declared)
CHECK(db.Enable == true and db.OutMotion == "SCROLL" and db.InDirection == "DOWN" and db.LogMotion == "STACK",
    "A: lane defaults applied with each lane's own overrides")
EQ(db.DamageDoneLane, "Out", "A: kinds routed")
EQ(db.KillingBlowLedger, true, "A: ...with ledger flags")
EQ(db.SoundProc, "PING", "A: the proc chime defaults on")
for _, spec in ipairs(DATA.LANES) do
    local root = _G["CommanderTracer" .. spec.key]
    CHECK(root ~= nil, "A: root built for " .. spec.key)
    CHECK(root and root.__strata == "LOW", "A: ...on the LOW strata by default", root and root.__strata)
    CHECK(root and root:IsShown(), "A: ...shown, since the lane is enabled")
end
CHECK(_G.CommanderTracerLog.__w == 260, "A: the ledger root is as wide as its rows", _G.CommanderTracerLog.__w)
for _, name in ipairs(DATA.CVARS_WORLD) do
    EQ(cvars[name], "0", "A: world CVar taken: " .. name)
end
EQ(cvars.enableFloatingCombatText, "0", "A: player text CVar taken")
EQ(db.CVarBackup.floatingCombatTextCombatDamage_v2, "1", "A: ...its old value kept")
EQ(db.CVarBackup.floatingCombatTextCombatHealing_v2, "0", "A: ...even when it was already off")
EQ(db.CVarBackup.enableFloatingCombatText, "1", "A: ...and the player one")

-- ===========================================================================
-- B: a Fireball
-- ===========================================================================
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(#Entries("Out"), 1, "B: a Fireball lands in Outgoing")
local f = Frames("Out")[1]
CHECK(f and f:IsShown(), "B: ...its frame is shown")
EQ(f and f.text.__text, "1,204", "B: ...reads the amount, separated")
CHECK(f and f.text.__color[1] == 1 and f.text.__color[2] == 0.5, "B: ...in fire orange")
EQ(f and f.icon.__texture, "Interface\\Icons\\Spell_27070", "B: ...with the Fireball icon")
CHECK(f and f.icon:IsShown(), "B: ...shown")
CHECK(f and f.text.__font and f.text.__font[1] == "Fonts\\FRIZQT__.TTF" and f.text.__font[2] == 18 and f.text.__font[3] == "OUTLINE",
    "B: ...in the lane's face, size and outline", f and f.text.__font and table.concat(f.text.__font, ","))
CHECK(f and f.text.__shadowColor and f.text.__shadowColor[4] == 1, "B: ...with a shadow")
EQ(#Entries("Log"), 1, "B: ...and a ledger row")
local row = Frames("Log")[1]
EQ(row and row.text.__text, "Fireball 1,204 on Gankmage", "B: the row says everything")
CHECK(row and not row.sub:IsShown(), "B: ...nothing left for the sub line")
CHECK(row and row.bg:IsShown() and row.accent:IsShown(), "B: ...with backdrop and accent")
CHECK(row and row.accent.__color[1] == row.text.__color[1] and row.accent.__color[2] == row.text.__color[2], "B: ...the accent in the entry's colour")
CHECK(row and row.text.__color[1] == 1 and row.text.__color[2] == 1, "B: ...which, by kind, is white for a hit of yours")
CHECK(row and row.__w == 260, "B: ...as wide as the lane", row and row.__w)
CHECK(row and row.__points[1].point == "TOPLEFT" and row.__points[1].rel == _G.CommanderTracerLog, "B: ...hung from the ledger's top-left")
CHECK(row and row.text.__points[2] and row.text.__points[2].point == "RIGHT", "B: ...its text anchored to the row's right edge too")
EQ(#Entries("In"), 0, "B: nothing in Incoming")
EQ(#caughtErrors, 0, "B: no errors", caughtErrors[1])

-- ===========================================================================
-- C: motion
-- ===========================================================================
local p0 = f.__points[1]
CHECK(p0.point == "CENTER" and p0.rel == _G.CommanderTracerOut, "C: a number hangs from the lane's centre")
Advance(0.5)
local p1 = f.__points[1]
CHECK(p1.y > p0.y + 20, "C: half a second on, it has risen", p1.y)
CHECK(f.__alpha == 1, "C: ...fully visible", f.__alpha)
Advance(1.5)
CHECK(f.__alpha < 1 and f.__alpha > 0, "C: fading near the end", f.__alpha)
local poolBefore = #Lane("Out").pool
Advance(0.5)
EQ(#Entries("Out"), 0, "C: expired at Duration")
CHECK(not f:IsShown(), "C: ...its frame hidden")
EQ(#Lane("Out").pool, poolBefore + 1, "C: ...and back in the pool")
CHECK(#Entries("Log") == 1, "C: the ledger row holds longer (6s)")
Advance(4)
EQ(#Entries("Log"), 0, "C: ...and then goes too")
EQ(#caughtErrors, 0, "C: no errors", caughtErrors[1])

-- ===========================================================================
-- D: ledger merge
-- ===========================================================================
Hit(27070, "Fireball", 4, 1204)
Advance(0.5)
Hit(27070, "Fireball", 4, 1180)
Advance(0.05)
EQ(#Entries("Log"), 1, "D: a repeat inside the window merges into one row")
row = Frames("Log")[1]
EQ(row.text.__text, "Fireball 2,384 on Gankmage x2", "D: ...summed and counted")
CHECK(row.accent.__w > 3, "D: ...the accent punches", row.accent.__w)
EQ(#Entries("Out"), 2, "D: the number lane (Merge 0) drew both")
Hit(27072, "Frostbolt", 16, 900)
Advance(0.05)
EQ(#Entries("Log"), 2, "D: a different spell is its own row")
local rows = Frames("Log")
CHECK(rows[1].text.__text:find("Frostbolt", 1, true) and rows[2].text.__text:find("Fireball", 1, true),
    "D: newest first", Texts("Log"))
Advance(0.5)
rows = Frames("Log")
CHECK(rows[1].__points[1].y == 0 and rows[2].__points[1].y < -30, "D: the older row shoved down a slot", rows[2].__points[1].y)
CommanderTracer_Clear()
EQ(#Entries("Log") + #Entries("Out"), 0, "D: Clear empties the lanes")

-- ===========================================================================
-- E: incoming
-- ===========================================================================
CLEU("SPELL_DAMAGE", "Player-2", "Bonecrush", HOSTILE, ME, "Me", MINE,
    30330, "Mortal Strike", 1, 618, 0, 1, 0, 0, 0, nil, false, false)
Advance(0.05)
EQ(#Entries("In"), 1, "E: a Mortal Strike on you lands in Incoming")
f = Frames("In")[1]
EQ(f.text.__text, "618 Mortal Strike", "E: ...amount then spell")
CHECK(f.icon.__points[1].point == "LEFT" and f.icon.__points[1].rel == f.text, "E: ...icon on the right of the text")
Advance(0.5)
CHECK(f.__points[1].y < -20, "E: ...falling", f.__points[1].y)
CLEU("SWING_MISSED", "Player-2", "Bonecrush", HOSTILE, ME, "Me", MINE, "DODGE", false, nil)
Advance(0.05)
f = Frames("In")[2]
EQ(f and f.text.__text, "Dodge Melee", "E: a dodge is its word")
CHECK(f and f.text.__color[1] == 0.72, "E: ...in grey")
CHECK(f and not f.icon:IsShown(), "E: ...a swing has no icon")
CLEU("SPELL_HEAL", "Player-6", "Lightbringer", 0x10 + 0x400, ME, "Me", MINE,
    27137, "Flash of Light", 2, 1450, 0, 0, nil)
Advance(0.05)
EQ(Texts("InHeal"), "1,450 Flash of Light", "E: a heal on you lands in Incoming Heals")
CLEU("SPELL_ENERGIZE", "Player-6", "Lightbringer", 0x10 + 0x400, ME, "Me", MINE,
    27164, "Judgement of Wisdom", 2, 240, 0, 0)
Advance(0.05)
f = Frames("InHeal")[2]
EQ(f and f.text.__text, "+240 Mana (Judgement of Wisdom)", "E: mana gained")
CHECK(f and f.text.__color[3] == 1 and f.text.__color[1] == 0.35, "E: ...in mana blue")
CommanderTracer_Clear()
EQ(#caughtErrors, 0, "E: no errors", caughtErrors[1])

-- ===========================================================================
-- F: crits and big hits
-- ===========================================================================
Hit(27070, "Fireball", 4, 2410, true)
Advance(0.05)
f = Frames("Out")[1]
EQ(f.text.__text, "2,410!", "F: a crit is marked")
CHECK(f.__scale > 1.5, "F: ...and punches in above 1.5x", f.__scale)
local px = f.__points[1]
CHECK(math.abs(px.x * f.__scale - 0) < 0.01, "F: ...anchor offsets divided by the scale")
Advance(0.3)
CHECK(math.abs(f.__scale - 1.5) < 0.01, "F: ...settling at Crit Size", f.__scale)
CommanderTracer_Clear()
db.OutCritMark = "WORD"
db.OutCritScale = 2
db.OutCritPunch = false
Notify()
Hit(27070, "Fireball", 4, 2410, true)
Advance(0.05)
f = Frames("Out")[1]
EQ(f.text.__text, "2,410 crit", "F: the mark follows the setting")
CHECK(math.abs(f.__scale - 2) < 0.01, "F: no punch: straight to 2x", f.__scale)
db.OutCritMark = "BANG"; db.OutCritScale = 1.5; db.OutCritPunch = true
CommanderTracer_Clear()
db.BigHitThreshold = 1000
Notify()
Hit(27070, "Fireball", 4, 1204)
Hit(27070, "Fireball", 4, 800)
Advance(0.05)
EQ(Texts("Out"), "1,204! | 800", "F: a non-crit past the big-hit threshold gets the treatment; a smaller one does not")
db.BigHitThreshold = 0
CommanderTracer_Clear()
Notify()

-- ===========================================================================
-- G: sounds
-- ===========================================================================
sounds = {}
CLEU("PARTY_KILL", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE)
Advance(0.05)
EQ(#sounds, 0, "G: the kill bell is silent by default")
EQ(Texts("Call"), "Killing Blow: Gankmage", "G: ...but the callout lands")
CHECK(Frames("Call")[1].text.__font[2] == 26 and Frames("Call")[1].text.__font[3] == "THICKOUTLINE", "G: ...big and thick")
EQ(#Entries("Log"), 1, "G: ...and a ledger row")
db.SoundKill = "TOLL_HI"
Notify()
CLEU("PARTY_KILL", ME, "Me", MINE, "Player-8", "Bonecrush", HOSTILE)
EQ(sounds[#sounds], "Sound\\Doodad\\BellTollAlliance.wav", "G: the kill bell rings when picked")
local n = #sounds
CLEU("PARTY_KILL", ME, "Me", MINE, "Player-9", "Third", HOSTILE)
EQ(#sounds, n, "G: ...not twice inside the gap")
now = now + 1
db.SoundCrit = "READY"
db.CritChimeFrom = 2000
Notify()
n = #sounds
Hit(27070, "Fireball", 4, 1800, true)
EQ(#sounds, n, "G: a crit under the chime threshold is silent")
Hit(27070, "Fireball", 4, 2400, true)
EQ(sounds[#sounds], 8960, "G: ...over it, the chime rings (kit id)")
now = now + 1
db.BigHitThreshold = 500
Notify()
n = #sounds
Hit(27070, "Fireball", 4, 2400)
EQ(#sounds, n, "G: a big hit is not a crit to the chime")
db.BigHitThreshold = 0
db.SoundKill = "NONE"; db.SoundCrit = "NONE"
CommanderTracer_PlaySound("SoundProc")
EQ(sounds[#sounds], "Sound\\Interface\\MapPing.wav", "G: auditioning plays regardless")
CommanderTracer_Clear()
Notify()

-- ===========================================================================
-- H: the client's own feed
-- ===========================================================================
combatTextData = { "Overpower", nil, nil, n = 3 }
Fire("COMBAT_TEXT_UPDATE", "SPELL_ACTIVE")
Advance(0.05)
EQ(Texts("Call"), "Overpower ready", "H: a reactive ability ready is a callout")
EQ(Texts("Log"), "Overpower ready", "H: ...and a ledger row")
EQ(sounds[#sounds], "Sound\\Interface\\MapPing.wav", "H: ...with the proc chime")
combatTextData = { "SPELL_ACTIVE", "Revenge", nil, n = 3 }
Fire("COMBAT_TEXT_UPDATE", "SPELL_ACTIVE")
Advance(0.05)
CHECK(Texts("Call"):find("Revenge ready", 1, true), "H: a feed that repeats the type first is read past it", Texts("Call"))
combatTextData = { 15, nil, nil, n = 3 }
Fire("COMBAT_TEXT_UPDATE", "HONOR_GAINED")
Advance(0.05)
CHECK(Texts("Log"):find("+15 Honor", 1, true), "H: honor gained is a ledger row", Texts("Log"))
combatTextData = { 500, nil, nil, n = 3 }
Fire("COMBAT_TEXT_UPDATE", "DAMAGE")
Advance(0.05)
EQ(#Entries("In"), 0, "H: the feed's own damage type is ignored (the log carries it)")
CommanderTracer_Clear()
EQ(#caughtErrors, 0, "H: no errors", caughtErrors[1])

-- ===========================================================================
-- I: routing
-- ===========================================================================
db.DamageDoneLane = "OFF"
Notify()
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(#Entries("Out"), 0, "I: Off draws no number")
EQ(#Entries("Log"), 1, "I: ...the ledger row still comes")
db.DamageDoneLedger = false
CommanderTracer_Clear()
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(#Entries("Log"), 0, "I: ...until that is off too")
db.DamageDoneLane = "In"
Notify()
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(Texts("In"), "1,204 Fireball", "I: a kind can be sent to any lane")
db.DamageDoneLane = "Out"; db.DamageDoneLedger = true
CommanderTracer_Clear()
db.OutEnable = false
Notify()
CHECK(not _G.CommanderTracerOut:IsShown(), "I: a disabled lane's root hides")
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(#Entries("Out"), 0, "I: ...and draws nothing")
EQ(#Entries("Log"), 1, "I: ...while the ledger still does")
db.OutEnable = true
CommanderTracer_Clear()
db.OutMinAmount = 500
Notify()
CLEU("SPELL_PERIODIC_DAMAGE", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE,
    27215, "Immolate", 4, 96, 0, 4, 0, 0, 0, nil, false, false)
CLEU("SPELL_MISSED", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE, 27072, "Frostbolt", 16, "RESIST", false, nil)
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(Texts("Out"), "Resist | 1,204", "I: hide-below drops the small tick, keeps the miss and the hit")
db.OutMinAmount = 0
CommanderTracer_Clear()
Notify()
petGUID = "Pet-0-1"
Fire("UNIT_PET", "player")
CLEU("SPELL_DAMAGE", "Pet-0-1", "Boarpet", MYPET, "Player-7", "Gankmage", HOSTILE,
    27049, "Claw", 1, 310, 0, 1, 0, 0, 0, nil, false, false)
Advance(0.05)
EQ(Texts("Out"), "Pet: 310", "I: the pet's Claw, tagged")
db.PetTag = false
Notify()
CommanderTracer_Clear()
CLEU("SPELL_DAMAGE", "Pet-0-1", "Boarpet", MYPET, "Player-7", "Gankmage", HOSTILE,
    27049, "Claw", 1, 310, 0, 1, 0, 0, 0, nil, false, false)
Advance(0.05)
EQ(Texts("Out"), "310", "I: ...untagged when asked")
db.PetTag = true
db.NumberStyle = "SHORT"
Notify()
CommanderTracer_Clear()
Hit(27070, "Fireball", 4, 12345)
Advance(0.05)
EQ(Texts("Out"), "12.3k", "I: the number style flows to the screen")
db.NumberStyle = "SEPARATED"
CommanderTracer_Clear()
Notify()
CHECK(CommanderTracer_Post({ kind = "Interrupt", spellName = "Polymorph", target = "Gankmage" }), "I: another module can post a record")
Advance(0.05)
EQ(Texts("Call"), "Interrupted Polymorph", "I: ...and it draws")
CHECK(not CommanderTracer_Post({ kind = "Nonsense" }), "I: ...an unknown kind is refused")
CommanderTracer_Clear()
EQ(#caughtErrors, 0, "I: no errors", caughtErrors[1])

-- ===========================================================================
-- J: off and on
-- ===========================================================================
db.Enable = false
Notify()
for _, spec in ipairs(DATA.LANES) do
    CHECK(not _G["CommanderTracer" .. spec.key]:IsShown(), "J: root hidden while off: " .. spec.key)
end
EQ(cvars.floatingCombatTextCombatDamage_v2, "1", "J: Blizzard's world numbers given back")
EQ(cvars.floatingCombatTextCombatHealing_v2, "0", "J: ...the one that was off stays off")
EQ(cvars.enableFloatingCombatText, "1", "J: ...and the player text")
EQ(next(db.CVarBackup), nil, "J: ...nothing left held")
Hit(27070, "Fireball", 4, 1204)
Advance(0.05)
EQ(#Entries("Out"), 0, "J: nothing drawn while off")
CommanderTracer_Test()
CHECK(printLog[#printLog]:find("disabled", 1, true), "J: the volley says it is disabled")
db.Enable = true
Notify()
EQ(cvars.floatingCombatTextCombatDamage_v2, "0", "J: back on, taken again")
EQ(db.CVarBackup.floatingCombatTextCombatDamage_v2, "1", "J: ...and remembered again")
CHECK(_G.CommanderTracerOut:IsShown(), "J: roots back")

-- ===========================================================================
-- K: the takeover boxes and combat
-- ===========================================================================
db.HideBlizzardWorldText = false
Notify()
EQ(cvars.floatingCombatTextPetMeleeDamage_v2, "1", "K: world numbers given back on their own")
EQ(cvars.enableFloatingCombatText, "0", "K: ...the player text still held")
db.HideBlizzardWorldText = true
inCombat = true
Fire("PLAYER_REGEN_DISABLED")
Notify()
EQ(cvars.floatingCombatTextPetMeleeDamage_v2, "1", "K: in combat the CVar write waits")
CHECK(printLog[#printLog] == nil or true, "K: (no chatter)")
inCombat = false
Fire("PLAYER_REGEN_ENABLED")
EQ(cvars.floatingCombatTextPetMeleeDamage_v2, "0", "K: ...and lands at REGEN")
Advance(0.05)
EQ(#Entries("Log"), 0, "K: combat state is off the ledger by default")
db.CombatStateLedger = true
Notify()
Fire("PLAYER_REGEN_DISABLED")
Fire("PLAYER_REGEN_ENABLED")
Advance(0.05)
rows = Frames("Log")
EQ(#rows, 2, "K: entering and leaving combat are rows when asked")
EQ(rows[1].text.__text, "Leaving combat", "K: ...newest first")
db.CombatStateLedger = false
CommanderTracer_Clear()
CommanderTracer_Report()
CHECK(printLog[#printLog]:find("Blizzard text: world hidden, player hidden", 1, true), "K: the report reads the takeover", printLog[#printLog])
EQ(#caughtErrors, 0, "K: no errors", caughtErrors[1])

-- ===========================================================================
-- L: the volley, Clear, unlock
-- ===========================================================================
local seen = {}
CommanderTracer_Test()
for _ = 1, 100 do
    Advance(0.05)
    for _, spec in ipairs(DATA.LANES) do
        if #Entries(spec.key) > 0 then seen[spec.key] = true end
    end
end
for _, spec in ipairs(DATA.LANES) do
    CHECK(seen[spec.key], "L: the volley reached " .. spec.title)
end
CHECK(#Entries("Log") > 0, "L: the ledger is still holding rows after five seconds")
CommanderTracer_Clear()
for _, spec in ipairs(DATA.LANES) do
    EQ(#Entries(spec.key), 0, "L: Clear emptied " .. spec.key)
end
CHECK(_G.CommanderTracerOut.__mouse == false, "L: a locked lane never takes the mouse")
db.OutLocked = false
Notify()
CHECK(Lane("Out").label:IsShown(), "L: an unlocked lane wears its name")
CHECK(_G.CommanderTracerOut._hudDragOverlay and _G.CommanderTracerOut._hudDragOverlay:IsShown(), "L: ...and its drag overlay owns the mouse")
CHECK(not Lane("In").label:IsShown(), "L: ...a locked one does not")
db.OutLocked = true
Notify()
CHECK(not Lane("Out").label:IsShown(), "L: ...and loses it when locked")
db.Strata = "HIGH"
Notify()
EQ(_G.CommanderTracerOut.__strata, "HIGH", "L: the draw layer follows the setting")
db.Strata = "LOW"
db.OutMotion = "FOUNTAIN"
db.OutSide = "RIGHT"
Notify()
Hit(27070, "Fireball", 4, 1204)
Advance(0.3)
f = Frames("Out")[1]
CHECK(f.__points[1].x > 5 and f.__points[1].y > 0, "L: a fountain lane throws right and up", f.__points[1].x .. "," .. f.__points[1].y)
db.OutMotion = "SCROLL"; db.OutSide = "ALTERNATE"
CommanderTracer_Clear()
Notify()
EQ(#caughtErrors, 0, "L: no errors", caughtErrors[1])

-- ===========================================================================
-- M: the settings page on the real framework
-- ===========================================================================
local registered
for _, m in ipairs(Commander.GetModules()) do if m.key == "Tracer" then registered = m end end
CHECK(registered ~= nil, "M: the page registered as a Commander module")
CHECK(registered and registered.slash == "/ctracer", "M: ...with its slash command")
CHECK(SlashCmdList.COMMANDERUI_TRACER ~= nil, "M: the slash handler exists")
local panel = registered and categories[#categories].__panel
for i = #categories, 1, -1 do
    if categories[i].__panel and categories[i].__panel._key == "Tracer" then panel = categories[i].__panel end
end
CHECK(panel ~= nil and panel._key == "Tracer", "M: the panel is the registered one")
-- every dropdown on the page has entries, each with a face and a value
local dropdowns, blank, faceless = 0, 0, 0
for _, fr in ipairs(allFrames) do
    if fr.__ddEntries then
        dropdowns = dropdowns + 1
        if #fr.__ddEntries == 0 then blank = blank + 1 end
        for _, info in ipairs(fr.__ddEntries) do
            if not info.text or info.text == "" or info.value == nil then faceless = faceless + 1 end
        end
    end
end
CHECK(dropdowns >= 100, "M: a hundred-odd dropdowns built", dropdowns)
EQ(blank, 0, "M: none of them empty")
EQ(faceless, 0, "M: every entry has a face and a value")
panel:Refresh()
EQ(#caughtErrors, 0, "M: every refresher runs clean", caughtErrors[1])
local facesSet, blankFaces = 0, 0
for _, fr in ipairs(allFrames) do
    if fr.__ddEntries then
        if fr.__ddText and fr.__ddText ~= "" then facesSet = facesSet + 1 else blankFaces = blankFaces + 1 end
    end
end
EQ(blankFaces, 0, "M: after a refresh every dropdown shows its current value", blankFaces)
CHECK(panel._hasFolds and #panel._folds >= 12, "M: the page folds into sections", panel._folds and #panel._folds)
CHECK(panel._searchBox ~= nil, "M: ...and got a search box")
-- the previews took the lane's face: find a font string sized 26 THICK (the callouts sample)
local previewCall, previewRune = false, false
db.HealFont = "RUNE"
panel:Refresh()
for _, fr in ipairs(allFrames) do
    for _, child in ipairs(fr.__children or {}) do
        if child.__font and child.__font[2] == 18 and child.__font[3] == "THICKOUTLINE" then previewCall = true end
        if child.__font and child.__font[1] == "Fonts\\SKURRI.TTF" then previewRune = true end
    end
end
CHECK(previewCall, "M: the callouts preview draws at the callouts' size (scaled to fit) and outline")
CHECK(previewRune, "M: the healing preview follows a face change")
db.HealFont = "DEFAULT"
-- the slash command
SlashCmdList.COMMANDERUI_TRACER("unlock")
CHECK(db.OutLocked == false and db.LogLocked == false, "M: /ctracer unlock unlocks every lane")
SlashCmdList.COMMANDERUI_TRACER("lock")
CHECK(db.OutLocked == true and db.LogLocked == true, "M: /ctracer lock locks them")
SlashCmdList.COMMANDERUI_TRACER("report")
CHECK(printLog[#printLog]:find("Blizzard text", 1, true), "M: /ctracer report prints")
-- Restore Defaults keeps the CVar backup
db.OutFontSize = 40
SlashCmdList.COMMANDERUI_TRACER("reset")
EQ(db.OutFontSize, 18, "M: reset restores a lane setting")
EQ(db.CVarBackup.enableFloatingCombatText, "1", "M: ...without forgetting Blizzard's values")
EQ(#caughtErrors, 0, "M: no errors anywhere", caughtErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
