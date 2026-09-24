-- Commander Kicks UI smoke (luajit)
--
--     luajit Commander_Kicks/Harness/kicks_ui_smoke.lua
--
-- The engine smoke next door covers the reasoning with no client attached.
-- This one covers the half that reasoning cannot reach: what the bar does
-- with what a real client says. It loads all four files of the module over a
-- small WoW mock, drives real events, and asserts on what got painted.
--
-- Sections:
--   A  an arena: three seats read from the unit tokens, the whole book drawn
--      from the gates, in seat order, with seat badges
--   B  a Counterspell in the log: the right icon goes down, the clock goes
--      red for the lockout and white after, and comes back with a flash
--   C  the felhunter: a Spell Lock from arenapet2 lands on seat 2
--   D  a battleground: no seats, a target's book, a stranger's spent kick
--      appearing and leaving, and a Frost Shock spending the Earth Shock
--   E  hostile only: a partner's Kick is nobody's business
--   F  the zone gate, only-in-combat, the classic (ready-hidden) bar
--   G  the test bar, and the read-only API

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

-- ===========================================================================
-- The mock
-- ===========================================================================
local now = 1000
function GetTime() return now end

local eventRegistry = {}
local caughtErrors = {}

local function IsMethodName(key)
    return type(key) == "string" and key:match("^[A-Z]")
end

local NewWidget
local WidgetMT = {}
WidgetMT.__index = function(self, key)
    local recorders = {
        SetText = function(s, text) s.__text = text end,
        GetText = function(s) return s.__text end,
        SetTextColor = function(s, r, g, b) s.__color = { r, g, b } end,
        SetVertexColor = function(s, r, g, b, a) s.__color = { r, g, b, a } end,
        SetAlpha = function(s, a) s.__alpha = a end,
        GetAlpha = function(s) return s.__alpha or 1 end,
        SetDesaturated = function(s, d) s.__desat = not not d end,
        SetTexture = function(s, t) s.__texture = t end,
        SetCooldown = function(s, start, dur) s.__cd = { start = start, dur = dur } end,
        Show = function(s) s.__shown = true end,
        Hide = function(s) s.__shown = false end,
        SetShown = function(s, v) s.__shown = not not v end,
        IsShown = function(s) return s.__shown end,
        IsVisible = function(s) return s.__shown end,
        SetSize = function(s, w, h) s.__w, s.__h = w, h end,
        GetWidth = function(s) return s.__w or 0 end,
        GetHeight = function(s) return s.__h or 0 end,
        SetPoint = function(s, point, rel, relPoint, x, y)
            s.__point = { point = point, rel = rel, relPoint = relPoint, x = x, y = y }
        end,
        ClearAllPoints = function(s) s.__point = nil end,
        GetFont = function() return "Fonts\\FRIZQT__.TTF", 10, "" end,
        SetFont = function(s, font, size, flags) s.__font = { font, size, flags } end,
        GetFrameLevel = function() return 1 end,
        CreateTexture = function(s)
            local t = NewWidget("Texture"); t.__parent = s; return t
        end,
        CreateFontString = function(s)
            local t = NewWidget("FontString"); t.__parent = s; return t
        end,
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
    if not fn and IsMethodName(key) then fn = function() end end
    if fn then rawset(self, key, fn) end
    return fn
end

NewWidget = function(kind, name)
    return setmetatable({ __kind = kind, __name = name, __scripts = {}, __shown = true }, WidgetMT)
end

local allFrames = {}
function CreateFrame(frameType, name, parent, template)
    local f = NewWidget(frameType, name)
    f.__template, f.__parent = template, parent
    if name then _G[name] = f end
    allFrames[#allFrames + 1] = f
    return f
end

UIParent = NewWidget("Frame", "UIParent")
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
strsub, strlen, strbyte = string.sub, string.len, string.byte
bit = bit or require("bit")
COMBATLOG_OBJECT_REACTION_HOSTILE = 0x40
COMBATLOG_OBJECT_REACTION_FRIENDLY = 0x10
COMBATLOG_OBJECT_TYPE_PLAYER = 0x400
COMBATLOG_OBJECT_TYPE_PET = 0x1000
RAID_CLASS_COLORS = {
    MAGE = { r = 0.41, g = 0.8, b = 0.94 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 },
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
}
SOUNDKIT = { RAID_WARNING = 8959 }
local sounds = {}
function PlaySound(id) sounds[#sounds + 1] = id end
function GetSpellTexture(id) return "tex:" .. tostring(id) end
function InCombatLockdown() return _G.__inCombat or false end
local prints = {}
function print(...) prints[#prints + 1] = table.concat({ ... }, " ") end

-- Units: tokens the tests set up
local units = {}
function UnitExists(unit) return units[unit] ~= nil end
function UnitIsPlayer(unit) local u = units[unit]; return u and not u.pet or false end
function UnitCanAttack(_, unit) local u = units[unit]; return u and u.hostile ~= false or false end
function UnitGUID(unit) local u = units[unit]; return u and u.guid end
function UnitName(unit) local u = units[unit]; return u and u.name end
function UnitClass(unit) local u = units[unit]; return u and u.class, u and u.class end
function UnitRace(unit) local u = units[unit]; return u and u.race, u and u.race end
local playerInfo = {}
function GetPlayerInfoByGUID(guid)
    local p = playerInfo[guid]
    if not p then return nil end
    return p.class, p.class, p.race, p.race, 0, p.name, ""
end
local instanceType = "arena"
function IsInInstance() return instanceType ~= "none", instanceType end

local cleuArgs
function CombatLogGetCurrentEventInfo() return unpack(cleuArgs, 1, cleuArgs.n) end

local function Fire(event, ...)
    for _, f in ipairs(eventRegistry[event] or {}) do
        local handler = f.__scripts.OnEvent
        if handler then
            local ok, err = pcall(handler, f, event, ...)
            if not ok then caughtErrors[#caughtErrors + 1] = event .. ": " .. tostring(err) end
        end
    end
end

local function CLEU(subevent, o)
    cleuArgs = {
        now, subevent, false,
        o.sourceGUID, o.sourceName, o.sourceFlags or (COMBATLOG_OBJECT_REACTION_HOSTILE + COMBATLOG_OBJECT_TYPE_PLAYER), 0,
        o.destGUID or "Player-ME", o.destName or "Me", COMBATLOG_OBJECT_REACTION_FRIENDLY, 0,
        o.spellID, o.spellName, 0,
    }
    cleuArgs.n = 14
    Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Tick the OnUpdate frames by `seconds`, in tenths, the way the client would
local function Advance(seconds)
    local steps = math.floor(seconds / 0.1 + 0.5)
    for _ = 1, steps do
        now = now + 0.1
        for _, f in ipairs(allFrames) do
            local handler = f.__scripts.OnUpdate
            if handler then
                local ok, err = pcall(handler, f, 0.1)
                if not ok then caughtErrors[#caughtErrors + 1] = "OnUpdate: " .. tostring(err) end
            end
        end
    end
end

local listeners = {}
Commander = {
    AddListener = function(event, fn)
        listeners[event] = listeners[event] or {}
        table.insert(listeners[event], fn)
    end,
    Notify = function(event)
        for _, fn in ipairs(listeners[event] or {}) do
            local ok, err = pcall(fn)
            if not ok then caughtErrors[#caughtErrors + 1] = "Notify: " .. tostring(err) end
        end
    end,
    UI = {
        HudChromeDefaults = function() return { HudStyle = "NONE", HudScale = 1, HudLocked = true, HudPos = false } end,
        HudUnlocked = function(db, prefix) return not db[prefix .. "Locked"] end,
        ApplyHudChrome = function() end,
        AddHudChromeOptions = function() end,
        AttachTooltip = function() end,
        ResetToDefaults = function() end,
        ApplyDefaults = function(db, defaults)
            for key, value in pairs(defaults) do
                if db[key] == nil then db[key] = value end
            end
        end,
        NewPanel = function()
            local panel = {}
            local noop = function() return panel end
            return setmetatable(panel, { __index = function(_, key)
                if type(key) == "string" and key:match("^[A-Z]") then return noop end
                return nil
            end })
        end,
    },
}

-- ===========================================================================
-- Load, in TOC order
-- ===========================================================================
local function Load(file)
    local chunk, err = loadfile(ADDONS .. "/Commander_Kicks/" .. file)
    if not chunk then error("could not load " .. file .. ": " .. tostring(err)) end
    local ok, runErr = pcall(chunk)
    if not ok then error("error running " .. file .. ": " .. tostring(runErr)) end
end
Load("CommanderKicksData.lua")
Load("CommanderKicksEngine.lua")
Load("CommanderKicksDB.lua")
Load("CommanderKicks.lua")

Fire("ADDON_LOADED", "Commander_Kicks")
Fire("PLAYER_LOGIN")

local root = CommanderKicksFrame
local function Cells()
    -- Visible cells, in position order, with their spell (read off the icon
    -- texture the painter set)
    local out = {}
    for _, f in ipairs(allFrames) do
        if f.__parent == root and f.icon and f.__shown then out[#out + 1] = f end
    end
    table.sort(out, function(a, b) return (a._pos or 0) < (b._pos or 0) end)
    return out
end
local function Spells()
    local names = {}
    for _, cell in ipairs(Cells()) do names[#names + 1] = cell._tex end
    return table.concat(names, ",")
end
local function Redraw() Advance(0.1) end

-- ===========================================================================
-- A: an arena from the gates
-- ===========================================================================
units.player = { guid = "Player-ME", name = "Me", class = "PRIEST", hostile = false }
units.arena1 = { guid = "Player-1", name = "Frostpath", class = "MAGE", race = "Human" }
units.arena2 = { guid = "Player-2", name = "Zaldrek", class = "WARLOCK", race = "Undead" }
units.arenapet2 = { guid = "Pet-2", name = "Zharvia", pet = true }
units.arena3 = { guid = "Player-3", name = "Shivspine", class = "ROGUE", race = "BloodElf" }
instanceType = "arena"
Fire("PLAYER_ENTERING_WORLD")
Fire("ARENA_OPPONENT_UPDATE")
Redraw()

CHECK(root:IsShown(), "A: the bar is up in an arena")
EQ(Spells(), "tex:2139,tex:19647,tex:38768,tex:28730",
    "A: the whole book from the gates, in seat order: CS, Spell Lock, Kick, Torrent")
local cells = Cells()
EQ(cells[1].badge.__text, "1", "A: seat badge on seat 1")
EQ(cells[3].badge.__text, "3", "A: seat badge on seat 3")
EQ(cells[4].badge.__text, "3", "A: the racial carries the same seat")
CHECK(cells[1].badge.__color and cells[1].badge.__color[1] == 0.41, "A: badge in class colour")
for i, cell in ipairs(cells) do
    CHECK(not cell.icon.__desat and cell._text == nil and not cell.cd.__shown,
        "A: cell " .. i .. " is ready: coloured, no clock, no sweep")
end
CHECK(cells[1].rim.__color[2] > 0.8, "A: a ready rim is green")
CHECK(cells[2]._pos > cells[1]._pos + 30, "A: a new seat opens the wider gap")
EQ(#caughtErrors, 0, "A: no errors so far", caughtErrors[1])

-- ===========================================================================
-- B: a Counterspell
-- ===========================================================================
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-1", sourceName = "Frostpath",
    spellID = 2139, spellName = "Counterspell" })
Redraw()
cells = Cells()
EQ(Spells(), "tex:2139,tex:19647,tex:38768,tex:28730", "B: same shape after the press")
CHECK(cells[1].icon.__desat, "B: CS is greyed while down")
CHECK(cells[1].cd.__shown and cells[1].cd.__cd and cells[1].cd.__cd.dur == 24, "B: a 24s sweep")
EQ(cells[1].timer.__text, "24", "B: the clock reads 24")
CHECK(cells[1].timer.__color[1] > 0.9 and cells[1].timer.__color[2] < 0.3, "B: red inside the lockout")
CHECK(cells[1].rim.__color[2] < 0.5, "B: a down rim is grey")
CHECK(not cells[2].icon.__desat, "B: the neighbour is untouched")

Advance(9)
cells = Cells()
EQ(cells[1].timer.__text, "15", "B: fifteen to go")
CHECK(cells[1].timer.__color[1] == 1 and cells[1].timer.__color[2] == 1, "B: white after the 8s lockout")
local sweepStart = cells[1].cd.__cd.start
Advance(1)
cells = Cells()
EQ(cells[1].cd.__cd.start, sweepStart, "B: the sweep is not restarted every tick")

-- Ranks by name: a rank-1 Kick from the rogue lands on the Kick icon
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-3", sourceName = "Shivspine",
    spellID = 1766, spellName = "Kick" })
Redraw()
cells = Cells()
CHECK(cells[3].icon.__desat and cells[3].cd.__cd.dur == 10, "B: a rank-1 Kick spends the Kick")

-- Back up: the flash, the sound, and the sound only once
CommanderKicksDB.ReadySound = true
local before = #sounds
Advance(9.9)
cells = Cells()
CHECK(not cells[3].icon.__desat, "B: the Kick is back")
CHECK(cells[3].glow.__shown, "B: ...and flashing")
EQ(#sounds, before + 1, "B: one sound when it came back")
Advance(2)
cells = Cells()
CHECK(not cells[3].glow.__shown, "B: the flash is over")
EQ(#sounds, before + 1, "B: ...and the sound did not repeat")
CommanderKicksDB.ReadySound = false
EQ(#caughtErrors, 0, "B: no errors", caughtErrors[1])

-- ===========================================================================
-- C: the felhunter
-- ===========================================================================
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Pet-2", sourceName = "Zharvia",
    sourceFlags = COMBATLOG_OBJECT_REACTION_HOSTILE + COMBATLOG_OBJECT_TYPE_PET,
    spellID = 19647, spellName = "Spell Lock" })
Redraw()
cells = Cells()
EQ(Spells(), "tex:2139,tex:19647,tex:38768,tex:28730", "C: the pet's press did not add a stranger")
CHECK(cells[2].icon.__desat and cells[2].cd.__cd.dur == 24, "C: seat 2's Spell Lock is down")
EQ(cells[2].badge.__text, "2", "C: ...credited to the warlock's seat")

-- An unowned pet (no arena token): its own group, classed after the spell
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Pet-9", sourceName = "Jhuunam",
    sourceFlags = COMBATLOG_OBJECT_REACTION_HOSTILE + COMBATLOG_OBJECT_TYPE_PET,
    spellID = 19244, spellName = "Spell Lock" })
Redraw()
cells = Cells()
EQ(#cells, 5, "C: an unowned pet is its own stranger")
EQ(cells[5].badge.__text, "J", "C: ...badged with its initial")
CHECK(cells[5].badge.__color[1] == 0.58, "C: ...in warlock colour, from the spell")
EQ(#caughtErrors, 0, "C: no errors", caughtErrors[1])

-- ===========================================================================
-- D: a battleground
-- ===========================================================================
units.arena1, units.arena2, units.arena3, units.arenapet2 = nil, nil, nil, nil
instanceType = "pvp"
Fire("PLAYER_ENTERING_WORLD")
Redraw()
CHECK(not root:IsShown(), "D: nothing to draw yet: hidden")

units.target = { guid = "Player-7", name = "Stormcaller", class = "SHAMAN", race = "Troll" }
Fire("PLAYER_TARGET_CHANGED")
Redraw()
cells = Cells()
EQ(Spells(), "tex:25454", "D: the target's book: Earth Shock")
EQ(cells[1].badge.__text, "S", "D: no seat outside arena: the initial")

CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-7", sourceName = "Stormcaller",
    spellID = 8056, spellName = "Frost Shock" })
Redraw()
cells = Cells()
CHECK(cells[1].icon.__desat and cells[1].cd.__cd.dur == 6, "D: a Frost Shock spends the Earth Shock")

-- A stranger's Pummel: appears, badged from GetPlayerInfoByGUID, then leaves
playerInfo["Player-8"] = { name = "Bonecrush", class = "WARRIOR", race = "Orc" }
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-8", sourceName = "Bonecrush",
    spellID = 6554, spellName = "Pummel" })
Redraw()
cells = Cells()
EQ(Spells(), "tex:25454,tex:6554", "D: a stranger's spent Pummel joins after the target")
EQ(cells[2].badge.__text, "B", "D: the stranger is named")
CHECK(cells[2].badge.__color[1] == 0.78, "D: ...and classed from the client")
Advance(13)
cells = Cells()
EQ(Spells(), "tex:25454", "D: the stranger leaves once the Pummel is back and the flash is over")
CHECK(not cells[1].icon.__desat, "D: the target's shock is back and stays, ready")
EQ(#caughtErrors, 0, "D: no errors", caughtErrors[1])

-- ===========================================================================
-- E: hostile only
-- ===========================================================================
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-P", sourceName = "Partner",
    sourceFlags = COMBATLOG_OBJECT_REACTION_FRIENDLY + COMBATLOG_OBJECT_TYPE_PLAYER,
    spellID = 38768, spellName = "Kick" })
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Creature-1", sourceName = "Guard",
    sourceFlags = COMBATLOG_OBJECT_REACTION_HOSTILE + 0x800,
    spellID = 38768, spellName = "Kick" })
Redraw()
EQ(Spells(), "tex:25454", "E: a partner's Kick and an NPC's are nobody's business")

-- ===========================================================================
-- F: the zone gate, combat only, the classic bar
-- ===========================================================================
instanceType = "none"
Fire("PLAYER_ENTERING_WORLD")
units.target = { guid = "Player-7", name = "Stormcaller", class = "SHAMAN", race = "Troll" }
Redraw()
CHECK(not root:IsShown(), "F: the world is off by default")
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-7", sourceName = "Stormcaller",
    spellID = 25454, spellName = "Earth Shock" })
Redraw()
CHECK(not root:IsShown(), "F: ...and a cast there is not tracked")

CommanderKicksDB.ShowInWorld = true
Commander.Notify(COMMANDER_KICKS_EVENTS.UPDATE)
Redraw()
CHECK(root:IsShown(), "F: turned on, the world draws")
CommanderKicksDB.CombatOnly = true
Redraw()
CHECK(not root:IsShown(), "F: only-in-combat hides it out of combat")
_G.__inCombat = true
Fire("PLAYER_REGEN_DISABLED")
Redraw()
CHECK(root:IsShown(), "F: ...and shows it in combat")
_G.__inCombat = false
CommanderKicksDB.CombatOnly = false

CommanderKicksDB.ShowReady = false
Redraw()
CHECK(not root:IsShown(), "F: classic bar: nothing on cooldown, nothing drawn")
CLEU("SPELL_CAST_SUCCESS", { sourceGUID = "Player-7", sourceName = "Stormcaller",
    spellID = 25454, spellName = "Earth Shock" })
Redraw()
EQ(Spells(), "tex:25454", "F: classic bar: the spent shock appears")
Advance(6.2)
cells = Cells()
CHECK(#cells == 1 and cells[1].glow.__shown, "F: classic bar: lingers to flash 'back up'")
Advance(2)
CHECK(not root:IsShown(), "F: classic bar: then leaves")
CommanderKicksDB.ShowReady = true

-- Vertical layout stacks along y
CommanderKicksDB.Orientation = "VERTICAL"
CommanderKicksDB.ShowName = true
units.focus = { guid = "Player-9", name = "Backstabber", class = "ROGUE", race = "Orc" }
Fire("PLAYER_FOCUS_CHANGED")
Redraw()
cells = Cells()
EQ(#cells, 2, "F: target and focus: two groups")
CHECK(cells[1].__point.y < 0 and cells[2].__point.y < cells[1].__point.y and cells[2].__point.x == 0,
    "F: vertical: the second icon is below the first")
CHECK(root.__h > root.__w, "F: vertical: the root is taller than wide")
CommanderKicksDB.Orientation = "HORIZONTAL"
CommanderKicksDB.ShowName = false
units.focus = nil
EQ(#caughtErrors, 0, "F: no errors", caughtErrors[1])

-- ===========================================================================
-- G: the test bar and the API
-- ===========================================================================
CommanderKicksDB.ShowInWorld = false
units.target = nil
Commander.Notify(COMMANDER_KICKS_EVENTS.UPDATE)
Redraw()
CHECK(not root:IsShown(), "G: quiet before the test")
CommanderKicksDB.HudLocked = false
Redraw()
CHECK(root:IsShown() and #Cells() == 0, "G: unlocked with nothing to draw: an empty placeholder to drag")
CommanderKicksDB.HudLocked = true
Redraw()
CHECK(not root:IsShown(), "G: locked again: gone")
CommanderKicks_Test()
Redraw()
cells = Cells()
EQ(Spells(), "tex:2139,tex:38768,tex:28730,tex:19647", "G: the test bar: mage, rogue+racial, warlock")
CHECK(cells[1].icon.__desat and cells[1].timer.__color[1] > 0.9, "G: the CS is inside its lockout")
CHECK(cells[3].timer.__text == "1:19", "G: the Torrent reads minutes: 1:19 a tick in", cells[3].timer.__text)
CHECK(not cells[4].icon.__desat, "G: the Spell Lock is ready")
local left = CommanderKicks_Remaining("Player-TEST-1", "Counterspell")
CHECK(left and left > 20 and left < 21.1, "G: the API answers for a tracked interrupt", left)
CHECK(CommanderKicks_Remaining("Player-TEST-3", "Spell Lock") == nil, "G: ...nil when ready")
Advance(21)
Redraw()
CHECK(not root:IsShown(), "G: the test bar clears itself")
CommanderKicks_Report()
CHECK(prints[#prints]:find("tracking 0 people", 1, true) ~= nil, "G: the report prints", prints[#prints])
EQ(#caughtErrors, 0, "G: no errors anywhere", caughtErrors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
