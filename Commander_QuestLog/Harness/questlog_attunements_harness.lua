-- Commander Quest Log: the Attunements tab in the window (luajit). DECISIONS D48-D57.
--
--     /opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_attunements_harness.lua
--     CQL_ATTUNE= / CQL_ATTUNE_ENGINE= / CQL_ATTUNE_DATA=/path/copy.lua luajit ...   (a mutated copy)
--
-- The REAL data, engine and tab, loaded with every other window file in the
-- TOC's order (minus the map drawer and the quest dialog) under the shared
-- client mock (questlog_mock.lua), the fake Questie (fake_questie.lua), the
-- suite's Go button (Commander_Events/CommanderGoButton.lua) and a recording
-- Commander Orders 3.1 stand-in with a door table. The engine's own checks
-- (phase, detectors, side and class, scoring, marks, events) live in
-- questlog_attune_engine_harness.lua and need no window; this file drives
-- the tab the player sees, section by section of the specification's 9.2:
--
--   E  registration and the switch: the fourth tab, order 40, width 76,
--      the underline, the Zones toolbar put away, NavTopInset 50 and the
--      navigator at -58, HideAll before the tab was ever built, the setting
--   F  rows and toolbar: six headers with counts, folds, words, strips,
--      bar widths, row heights, selection, the four filters, the count,
--      the phase button and its menu, the empty messages
--   G  the briefing: the overview's order, the course page's title, facts,
--      every notice, the STEPS list, the band, the open lesson's body, the
--      focus, Escape, the two folds, SPEND, ALSO NEEDED, the auto-select
--   H  Go: spec and query by the door rule with and without Orders, the
--      action-bar Go, a turn-in, an inside step, Magisters' Terrace by
--      instance id, Ctrl+Right-click, Nothing to go to, the turn-in cleanup
--   J  the hero card in its four states, its bar, its tooltip, its clicks
--   K  settings, saved variables, slash: the seven defaults, Reset, the
--      load-time repairs, the settings page's controls, /cql attune, /cql
--      rep, /cql status, PrepareOpen refusing, OpenToTab on a lesson
--   Q  the module reloaded with no Questie at all
--   Z  hygiene: no new global, no error, plain words, coloured strings
--
-- Every check tests the real files. A failing check is either a harness
-- misreading (fixed here) or a finding against the product or the
-- specification, recorded where this file was written.

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local MODULE = ADDONS .. "/Commander_QuestLog/"

local mock = dofile(MODULE .. "Harness/questlog_mock.lua")
local Fake = dofile(MODULE .. "Harness/fake_questie.lua")
local CHECK, _, counts = mock.Checker()
-- One line per section, then "N checks passed" (exit 0) or the count of
-- failures (exit 1)
local section = { name = nil, checks = 0, fails = 0 }
local function Section(name)
    if section.name then
        io.write(string.format("%-6s %3d checks, %d failures\n", section.name, counts.checks - section.checks, counts.fails - section.fails))
    end
    section.name, section.checks, section.fails = name, counts.checks, counts.fails
end
local function Done()
    Section(nil)
    if counts.fails == 0 then
        io.write(string.format("%d checks passed\n", counts.checks))
        os.exit(0)
    end
    io.write(string.format("%d checks, %d failures\n", counts.checks, counts.fails))
    os.exit(1)
end
local function EQ(got, want, label) CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function HAS(s, needle, label) CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, s) end

-- The client's Enable / Disable as the real buttons have them (the mock's
-- are silent no-ops; the Go button greys itself out with them)
do
    local probe = mock.NewWidget("Button")
    local mt = getmetatable(probe)
    local index = mt.__index
    mt.__index = function(self, key)
        if key == "Enable" then return function(s) s.__enabled = true end end
        if key == "Disable" then return function(s) s.__enabled = false end end
        if key == "LockHighlight" then return function(s) s.__locked = true end end
        if key == "UnlockHighlight" then return function(s) s.__locked = false end end
        return index(self, key)
    end
end

-- Modifier keys, held by hand
local mods = { SHIFT = false, CTRL = false }
function IsShiftKeyDown() return mods.SHIFT end
function IsControlKeyDown() return mods.CTRL end

-- ===========================================================================
-- The client the engine reads, defined BEFORE Fake.InstallClient (the fake
-- fills only nil slots) and before the module files load. Every detector's
-- read has a knob in T: quest flags, bags and keyring, spells, skill lines,
-- faction, race, level, class, the instance stood in, the dungeon
-- difficulty, the NPC spoken to, encounter locks and the combat log.
-- GetSavedInstanceInfo is REDEFINED over the mock's ten returns to the
-- client's fourteen (the map id at 14, the encounter counts at 11 and 12).
-- ===========================================================================
local world = Fake.DefaultWorld()
local T = {
    done = {}, items = {}, keyring = {}, spells = {}, skills = {}, encounters = {},
    faction = "Alliance", race = "Human", className = "Warrior", class = "WARRIOR", level = 70,
    realm = "Testrealm", name = "Harness",
    instance = { kind = "none", id = nil, difficulty = 0 }, dungeonDifficulty = 1,
    npcGUID = nil, cleu = nil, expandCalls = 0,
}
function GetSavedInstanceInfo(index)
    local i = mock.state.savedInstances[index]
    if not i then return nil end
    return i.name, 100 + index, i.reset or 3600, i.difficulty or 1, i.locked ~= false, i.extended or false,
        0, i.isRaid ~= false, i.maxPlayers or 10, i.difficultyName or "Normal",
        i.encountersTotal or 0, i.encountersCompleted or 0, false, i.mapID
end
function GetSavedInstanceEncounterInfo(index, j)
    local i = mock.state.savedInstances[index]
    local boss = i and i.bosses and i.bosses[j]
    if not boss then return nil end
    return boss[1], 0, boss[2] == true
end
function GetInstanceInfo() return "Name", T.instance.kind, T.instance.difficulty or 0, "", 5, 0, false, T.instance.id end
C_Container = {
    GetContainerNumSlots = function(bag) if bag == -2 then return #T.keyring end return 0 end,
    GetContainerItemID = function(bag, slot) if bag == -2 then return T.keyring[slot] end return nil end,
}
C_Item = { GetItemCount = function(id) return T.items[id] or 0 end }
C_SpellBook = { IsSpellKnown = function(id) return T.spells[id] == true end }
function GetNumSkillLines() return #T.skills end
function GetSkillLineInfo(i)
    local s = T.skills[i]
    if not s then return nil end
    return s.name, s.header == true, s.expanded ~= false, s.rank or 0, 0, 0, s.max or 375
end
function ExpandSkillHeader() T.expandCalls = T.expandCalls + 1 end   -- a spy: the engine never expands
function UnitGUID(unit) if unit == "npc" then return T.npcGUID end return nil end
function GetDungeonDifficultyID() return T.dungeonDifficulty end
C_RaidLocks = { IsEncounterComplete = function(map, enc) return T.encounters[tostring(map) .. ":" .. tostring(enc)] == true end }
function CombatLogGetCurrentEventInfo() if T.cleu then return unpack(T.cleu) end return nil end
function UnitFactionGroup() return T.faction, T.faction end
function UnitRace() return T.race, T.race, 1 end
function GetRealmName() return T.realm end
function UnitLevel() return T.level end            -- over the mock's 62
function UnitClass() return T.className, T.class, 1 end
function UnitName() return T.name end
C_QuestLog = C_QuestLog or {}
C_QuestLog.IsQuestFlaggedCompleted = function(id) return T.done[id] == true end
-- Zone names for the Go tooltips ("Alterac Mountains 15.5, 54.5"): the
-- fake world's own maps first, then the data's thirteen zones (3.1 MAPS)
local MAP_NAMES = {
    [1944] = "Hellfire Peninsula", [1946] = "Zangarmarsh", [1952] = "Terokkar Forest", [1951] = "Nagrand",
    [1949] = "Blade's Edge Mountains", [1953] = "Netherstorm", [1948] = "Shadowmoon Valley", [1955] = "Shattrath City",
    [1430] = "Deadwind Pass", [1446] = "Tanaris", [1942] = "Ghostlands", [1957] = "Isle of Quel'Danas", [1416] = "Alterac Mountains",
}
C_Map = C_Map or {}
C_Map.GetMapInfo = function(uiMapId)
    local map = world.uiMaps[uiMapId]
    if map then return { mapID = uiMapId, name = map.name, mapType = map.mapType, parentMapID = map.parent or 0 } end
    local name = MAP_NAMES[uiMapId]
    if name then return { mapID = uiMapId, name = name, mapType = 3, parentMapID = 1945 } end
    return nil
end

-- ===========================================================================
-- A recording Commander Orders 3.1: the API the Go buttons, the adapter and
-- the engine call, answering the way the real one does (GoTo merges opts
-- into the place; one record per (source, key); PlaceFor answers a place
-- from a spec or a door query out of a small door table, D37)
-- ===========================================================================
local O = { gone = {}, records = {}, order = {}, active = nil, available = true, copied = nil, shared = nil, removed = {}, notify = true }
local DOORS = {
    [545] = { 1946, 0.5036, 0.4081, "The Steamvault" }, [547] = { 1946, 0.5036, 0.4081, "The Slave Pens" },
    [546] = { 1946, 0.5036, 0.4081, "The Underbog" }, [269] = { 1446, 0.6487, 0.4996, "The Black Morass" },
    [560] = { 1446, 0.6487, 0.4996, "Old Hillsbrad Foothills" }, [585] = { 1957, 0.6118, 0.3058, "Magisters' Terrace" },
    [565] = { 1949, 0.6870, 0.2430, "Gruul's Lair" }, [544] = { 1944, 0.4764, 0.5201, "Magtheridon's Lair" },
    [532] = { 1430, 0.4700, 0.7500, "Karazhan" }, [568] = { 1942, 0.8230, 0.6430, "Zul'Aman" },
    [580] = { 1957, 0.4430, 0.4550, "Sunwell Plateau" }, [552] = { 1953, 0.7400, 0.6500, "The Arcatraz" },
    [555] = { 1952, 0.3950, 0.6550, "Shadow Labyrinth" }, [556] = { 1952, 0.3950, 0.6550, "Sethekk Halls" },
    [540] = { 1944, 0.4740, 0.5202, "The Shattered Halls" }, [553] = { 1953, 0.7200, 0.5500, "The Botanica" },
    [554] = { 1953, 0.7400, 0.6300, "The Mechanar" }, [557] = { 1952, 0.3950, 0.6550, "Mana-Tombs" },
}
local REASONS = {
    disabled = "Commander Orders is turned off (/corder)", needsorders = "Needs Commander Orders",
    nowhere = "No known location", instance = "Inside an instance; the arrow cannot see in",
    noquestie = "Needs Questie for this lookup",
}
COMMANDER_ORDERS_EVENTS = { CHANGED = "COMMANDER_ORDERS_CHANGED", UPDATE = "COMMANDER_ORDERS_UPDATE" }
local function Changed() if O.notify and Commander and Commander.Notify then Commander.Notify(COMMANDER_ORDERS_EVENTS.CHANGED) end end
local O_API = {
    IsAvailable = function()
        if O.available then return true end
        return false, "disabled"
    end,
    Reason = function(why)
        if REASONS[why] then return REASONS[why] end
        why = tostring(why)
        return why:sub(1, 1):upper() .. why:sub(2)
    end,
    GoTo = function(target, opts)
        O.gone[#O.gone + 1] = { target = target, opts = opts }
        if not O.available then return nil, "disabled" end
        local s = {}
        for k, v in pairs(target) do s[k] = v end
        for _, f in ipairs({ "source", "key", "title", "icon", "note" }) do
            if opts[f] ~= nil then s[f] = opts[f] end
        end
        local id = tostring(s.source) .. "|" .. tostring(s.key)
        if not O.records[id] then O.order[#O.order + 1] = id end
        s.uid = "w" .. #O.order
        O.records[id] = s
        O.active = s
        Changed()
        return s.uid
    end,
    IsGoing = function(source, key)
        local a = O.active
        return a ~= nil and O.records[tostring(a.source) .. "|" .. tostring(a.key)] == a and a.source == source
            and (key == nil or a.key == key)
    end,
    PlaceFor = function(target)
        if type(target) ~= "table" then return nil, "nowhere" end
        if target.map then return { map = target.map, x = target.x, y = target.y, title = target.title } end
        if type(target.entrance) == "table" then
            local row = DOORS[target.entrance.instance]
            if row then return { map = row[1], x = row[2], y = row[3], title = row[4] } end
            return nil, "instance"
        end
        if target.npc then return nil, "noquestie" end
        return nil, "nowhere"
    end,
    FormatCoords = function(x, y) return string.format("%.1f, %.1f", x * 100, y * 100) end,
    WayLineFor = function(m, x, y, t)
        return string.format("/way #%d %.2f %.2f%s", m, x * 100, y * 100, t and (" " .. t) or "")
    end,
    CopyText = function(text) O.copied = text end,
    SharePoint = function(spec, channel) O.shared = { spec = spec, channel = channel } return true end,
    List = function(filter)
        local out = {}
        for _, id in ipairs(O.order) do
            local r = O.records[id]
            if r and (not filter or not filter.source or r.source == filter.source) then out[#out + 1] = r end
        end
        return out
    end,
    RemoveBy = function(source, key)
        local id = tostring(source) .. "|" .. tostring(key)
        O.removed[#O.removed + 1] = key
        if O.records[id] then
            O.records[id] = nil
            return 1
        end
        return 0
    end,
    Add = function() error("Orders 3.1: the Go path never calls Add") end,
    AddRoute = function() return "r1" end,
    RegisterResolver = function() return true end,
    Describe = function() return "Commander Orders arrow" end,
}
CommanderOrders = O_API
local function LastGone() return O.gone[#O.gone] end

-- ===========================================================================
-- Boot: the fake Questie over the default world, the framework, the suite's
-- Go button, then every window file but the map drawer and the quest dialog
-- ===========================================================================
world.log[9826] = true                          -- Contact from Dalaran in the log (a turn-in Go)
local fake = Fake.Install(world)
Fake.InstallClient(world)

mock.LoadFramework()
mock.Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
local globalsBefore = {}
for key in pairs(_G) do globalsBefore[key] = true end

-- The TOC's order minus the map drawer and the quest dialog, the three 1.8.0
-- files included (E proves the list against the TOC itself)
local MODULE_FILES = {
    "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua", "CommanderQuestLogReputationData.lua",
    "CommanderQuestLogCompletion.lua", "CommanderQuestLogStanding.lua", "CommanderQuestLogQuestie.lua",
    "CommanderQuestLogUI.lua", "CommanderQuestLogCatalogue.lua", "CommanderQuestLogZones.lua",
    "CommanderQuestLogReputations.lua", "CommanderQuestLogAttuneData.lua", "CommanderQuestLogAttune.lua",
    "CommanderQuestLogAttunements.lua",
}
local OVERRIDE = {
    ["CommanderQuestLogAttunements.lua"] = os.getenv("CQL_ATTUNE"),
    ["CommanderQuestLogAttune.lua"] = os.getenv("CQL_ATTUNE_ENGINE"),
    ["CommanderQuestLogAttuneData.lua"] = os.getenv("CQL_ATTUNE_DATA"),
}
local function LoadModule()
    for _, file in ipairs(MODULE_FILES) do
        local path = OVERRIDE[file]
        if not (type(path) == "string" and path ~= "") then path = MODULE .. file end
        mock.Load(path)
    end
end
LoadModule()

-- Saved variables as a damaged file would hand them over, for K's
-- load-time repairs: the three Attune tables as other types, the character
-- table with a number where a sub-table and a string belong
CommanderQuestLogDB.AttuneCollapsed = 5
CommanderQuestLogDB.AttuneAccount = "x"
CommanderQuestLogDB.AttunePhaseSeen = true
CommanderQuestLogChar = { Attune = { marks = 5, guide = 7, seen = "no" } }

-- The server's clock two days into Phase 4 (22 Oct 2026, 1792706400), so
-- the calendar term answers 4 (the mock's own 2023 epoch would say 1)
mock.clock.serverTime = 1792706400 + 2 * 86400

mock.state.log = {
    mock.Header("Deadwind Pass"),
    mock.Quest({ title = "Contact from Dalaran", level = 70, questID = 9826,
        objectives = { { text = "Deliver Alturus's Report to Archmage Cedric", finished = false } } }),
}
mock.Login()
local function Settle() for _ = 1, 8 do mock.RunTimers(1) end end
Settle()

local Q = CommanderQuestLog
local db = CommanderQuestLogDB
local A, Tab, D = Q.Attune, Q.Attunements, CommanderQuestLogAttuneData
local kit, C = Q._kit, Q.Catalogue
local SEP = C.SEP
Section("boot")
CHECK(Q.Questie.State() == "READY", "boot: the fake Questie is ready", Q.Questie.State())
CHECK(type(A) == "table" and type(Tab) == "table" and type(D) == "table", "boot: engine, tab and data are loaded")

-- ---------------------------------------------------------------------------
-- Helpers over the tab's drawn state
-- ---------------------------------------------------------------------------
local function W() return Tab._Widgets() end
local function S() return Tab._State() end
local function PointY(widget) local p = widget.__points and widget.__points[1]; return p and p.y or nil end
local function TopLeftX(widget)
    local x
    for _, p in ipairs(widget.__points or {}) do if p.point == "TOPLEFT" then x = p.x end end
    return x
end
local function Strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
-- The briefing's shown blocks, top to bottom
local function Blocks()
    local out = {}
    for _, b in ipairs(W().blocks or {}) do
        if b:IsShown() and b:GetText() then out[#out + 1] = b end
    end
    table.sort(out, function(a, b) return (PointY(a) or 0) > (PointY(b) or 0) end)
    return out
end
local function Texts()
    local out = {}
    for i, b in ipairs(Blocks()) do out[i] = Strip(b:GetText()) end
    return out
end
local function IndexOf(texts, needle, from)
    for i = from or 1, #texts do
        if texts[i] == needle or texts[i]:find(needle, 1, true) == 1 then return i end
    end
    return nil
end
local function BlockWith(needle)
    for _, b in ipairs(Blocks()) do
        if Strip(b:GetText()):find(needle, 1, true) then return b end
    end
    return nil
end
local function Tip(widget)
    GameTooltip.__lines, GameTooltip.__colors = {}, {}
    local enter = widget and widget:GetScript("OnEnter")
    if enter then enter(widget) end
    return table.concat(GameTooltip.__lines, " | ")
end
local function Click(button, how, mouse)
    mods.SHIFT, mods.CTRL = how == "SHIFT", how == "CTRL"
    local handler = button:GetScript("OnClick")
    if handler then handler(button, mouse or "LeftButton") end
    mods.SHIFT, mods.CTRL = false, false
end
local function Refresh() Q.Refresh() end
local function Open(key, step) Q.OpenToTab("ATTUNE", key, step) end
local function GuideRow(key)
    for _, row in ipairs(W().rows or {}) do
        if row:IsShown() and row.guideKey == key then return row end
    end
    return nil
end
local function HeaderRow(category)
    for _, row in ipairs(W().rows or {}) do
        if row:IsShown() and row.category == category then return row end
    end
    return nil
end
local function ShownRows()
    local out = {}
    for _, row in ipairs(W().rows or {}) do if row:IsShown() then out[#out + 1] = row end end
    table.sort(out, function(a, b) return (PointY(a) or 0) > (PointY(b) or 0) end)
    return out
end
local function View(stepKey)
    for _, v in ipairs(S().steps or {}) do if v.key == stepKey then return v end end
    return nil
end
local function StepText(v)
    if v.status == "NOTE" then return v.title or "" end
    return (v.word or "") .. "  " .. (v.title or "")
end
local function StepBlock(stepKey)
    local v = View(stepKey)
    if not v then return nil end
    local want = StepText(v)
    for _, b in ipairs(Blocks()) do
        if Strip(b:GetText()) == want then return b end
    end
    return nil
end
-- The tab's Go at a line (TOPRIGHT at top - 3) and the hit over it (top - 1)
local function GoAt(block)
    local y = PointY(block)
    for _, b in ipairs(W().goLines or {}) do
        if b:IsShown() and PointY(b) == y + 3 then return b end
    end
    return nil
end
local function HitAt(block)
    local y = PointY(block)
    for _, h in ipairs(W().hits or {}) do
        if h:IsShown() and PointY(h) == y + 1 then return h end
    end
    return nil
end
local function ShownGos()
    local out = {}
    for _, b in ipairs(W().goLines or {}) do if b:IsShown() then out[#out + 1] = b end end
    return out
end
local function Same(a, b) return math.abs((a or 0) - (b or 0)) < 0.001 end
local function ColourIs(widget, r, g, b)
    local c = widget and widget.__color
    return c ~= nil and Same(c[1], r) and Same(c[2], g) and Same(c[3], b)
end
local function Paper(key)
    local r, g, b = C.ToneRGB(key)
    if key == "primary" or key == "secondary" or key == "faint" or key == "strong" then r, g, b = kit.Ink(key) end
    return kit.Paper(r, g, b)
end
local function DateWord(t, withYear)
    return (os.date(withYear and "%d %b %Y" or "%d %b", t):gsub("^0", ""))
end
local function NavY()
    local window = _G.CommanderQuestLogFrame
    local y
    for _, p in ipairs(window and window.navPane and window.navPane.__points or {}) do
        if p.point == "TOPLEFT" then y = p.y end
    end
    return y
end
local function Points(widget)
    local parts = {}
    for _, p in ipairs(widget.__points or {}) do
        parts[#parts + 1] = tostring(p.point) .. ":" .. tostring(p.rel and (p.rel.__name or "w") or "-") .. ":" .. tostring(p.relPoint)
            .. ":" .. tostring(p.x) .. ":" .. tostring(p.y)
    end
    return table.concat(parts, ";")
end
local function NothingShown()
    local w = W()
    for _, pool in ipairs({ w.rows, w.blocks, w.quads, w.bands, w.hits, w.goLines }) do
        for _, x in ipairs(pool or {}) do if x:IsShown() then return false end end
    end
    if w.emptyFS and w.emptyFS:IsShown() then return false end
    if w.toolbar and w.toolbar:IsShown() then return false end
    if w.card and w.card:IsShown() then return false end
    if w.actions and w.actions:IsShown() then return false end
    return true
end
-- Everything the tab put on screen, for the word sweeps (G, Z)
local drawn = {}
local function Sweep(tag)
    for _, text in ipairs(Texts()) do drawn[#drawn + 1] = { tag, text } end
    for _, row in ipairs(ShownRows()) do
        drawn[#drawn + 1] = { tag, row.title:GetText() or "" }
        drawn[#drawn + 1] = { tag, Strip(row.state:GetText() or "") }
    end
    local w = W()
    if w.card then
        for _, fs in ipairs({ w.card.name, w.card.totals, w.card.note }) do drawn[#drawn + 1] = { tag, fs:GetText() or "" } end
    end
    if w.countFS then drawn[#drawn + 1] = { tag, w.countFS:GetText() or "" } end
    if w.phaseBtn then drawn[#drawn + 1] = { tag, w.phaseBtn:GetText() or "" } end
    if w.emptyFS and w.emptyFS:IsShown() then drawn[#drawn + 1] = { tag, w.emptyFS:GetText() or "" } end
    for _, b in ipairs(ShownGos()) do drawn[#drawn + 1] = { tag, b:GetText() or "" } end
end
local function Note(tag, text) drawn[#drawn + 1] = { tag, text or "" } end
local function Char() return CommanderQuestLogChar.Attune end
local function WipeTouch()
    local at = Char()
    at.guide = nil
    for k in pairs(at.touched) do at.touched[k] = nil end
    A.Invalidate("store")
end

-- The window on the Log first: the tab's HideAll runs before it is built
db.ViewMode = "LOG"
CommanderQuestLog_Show()
local window = _G.CommanderQuestLogFrame
local searchPointsBefore = Points(window.searchBox)

-- ===========================================================================
-- E. Registration and the switch
-- ===========================================================================
Section("E")
do
    local toc = mock.TocFiles({ "CommanderQuestLogMap.lua", "CommanderQuestLogQuestFrame.lua" })
    EQ(table.concat(MODULE_FILES, ","), table.concat(toc, ","), "E: MODULE_FILES is the TOC's order minus Map and QuestFrame")
    local tabs = Q.Tabs()
    CHECK(#tabs == 4 and tabs[3].id == "REP" and tabs[4].id == "ATTUNE", "E: ATTUNE is the fourth tab, after Reputations", #tabs)
    CHECK(Tab.tab.order == 40 and Tab.tab.width == 76 and Tab.tab.label == "Attunements",
        "E: order 40, width 76, the word Attunements")
    CHECK(W().toolbar == nil and #mock.caughtErrors == 0,
        "E: a Log refresh before the tab was ever shown called HideAll without error, nothing built", mock.caughtErrors[1])
    local buttons = Q.TabButtons()
    CHECK(buttons.ATTUNE and buttons.ATTUNE:IsShown() and buttons.ATTUNE.__w == 76 and buttons.ATTUNE:GetText() == "Attunements",
        "E: the ATTUNE button is up, 76 wide")
    EQ(TopLeftX(buttons.ATTUNE), 212, "E: placed after Log, Zones and Reputations (12, 72, 132, 212)")
    -- the Zones tab first, so its toolbar exists to be put away
    Click(buttons.ZONE)
    local ZW = Q.Zones._Widgets()
    CHECK(Q.ViewMode() == "ZONE" and ZW.toolbar and ZW.toolbar:IsShown(), "E: (the Zones tab up, its toolbar shown)")
    Click(buttons.ATTUNE)
    CHECK(db.ViewMode == "ATTUNE" and Q.ViewMode() == "ATTUNE", "E: the button's OnClick switches ViewMode to ATTUNE")
    CHECK(buttons.ATTUNE.underline.__color[4] > 0.5 and buttons.LOG.underline.__color[4] == 0 and buttons.ZONE.underline.__color[4] == 0,
        "E: ...and lights its underline alone")
    CHECK(ZW.toolbar:IsShown() == false, "E: the Zones toolbar is hidden")
    CHECK(Tab.tab.NavTopInset() == 50 and NavY() == -58, "E: NavTopInset 50 while active: the navigator at -58",
        tostring(Tab.tab.NavTopInset()) .. " " .. tostring(NavY()))
    CHECK(W().toolbar:IsShown() and W().card:IsShown() and W().actions:IsShown(), "E: toolbar, card and action bar shown")
    local labels = {}
    for _, f in ipairs(mock.allFrames) do
        if f.__kind == "Button" and f.__parent == W().actions then labels[#labels + 1] = f.__text end
    end
    table.sort(labels)
    EQ(table.concat(labels, ","), "Go to Step,Mark Done,Open in Log,Overview", "E: the action bar is Go to Step, Mark Done, Open in Log, Overview: no Show on Map")
    Sweep("E overview")
    Q.SetViewMode("LOG")
    CHECK(Tab.tab.NavTopInset() == 0 and NavY() == -8, "E: on the Log the inset is 0 and the navigator at -8",
        tostring(Tab.tab.NavTopInset()) .. " " .. tostring(NavY()))
    CHECK(NothingShown(), "E: HideAll leaves nothing of the tab shown")
    db.ShowAttuneTab = false
    Q.SetViewMode("ATTUNE")
    CHECK(Q.ViewMode() == "LOG" and buttons.ATTUNE:IsShown() == false,
        "E: IsEnabled false removes the button and SetViewMode falls to LOG", Q.ViewMode())
    db.ShowAttuneTab = true
    Q.SetViewMode("ATTUNE")
    CHECK(Q.ViewMode() == "ATTUNE" and buttons.ATTUNE:IsShown(), "E: switched on again, the tab is back")
end

-- ===========================================================================
-- F. Rows and toolbar
-- ===========================================================================
Section("F")
do
    db.AttuneFilter = "ALL"
    S().selected = nil
    Refresh()
    local order = {}
    for _, row in ipairs(ShownRows()) do if row.category then order[#order + 1] = row.category end end
    EQ(table.concat(order, ","), "RAID,HEROIC,DUNGEON,UNLOCK,FLYING,BADGES", "F: six module headers in the catalogue's order")
    local headerItem = {}
    for _, item in ipairs(S().items) do if item.kind == "header" then headerItem[item.category] = item end end
    local set = kit.InkSet()
    local raid = HeaderRow("RAID")
    EQ(raid.state:GetText(), string.format("|cff%s%d|r/|cff%s%d|r", set.countDone, headerItem.RAID.done, set.countAll, headerItem.RAID.total),
        "F: a header counts done/needed in the InkSet's two hexes")
    CHECK(headerItem.RAID.total == 4 and headerItem.RAID.done == 0,
        "F: at Phase 4 the raid module needs four guides (SSC, TK, Hyjal, BT not needed; Sunwell later)",
        tostring(headerItem.RAID.done) .. "/" .. tostring(headerItem.RAID.total))
    EQ(HeaderRow("BADGES").state:GetText(), "", "F: the BADGES header shows no count")
    EQ(raid.title:GetText(), "Raid attunements", "F: the header's label is the category's")
    local lessons, guides = 0, 0
    for _, row in ipairs(ShownRows()) do
        if row.guideKey then guides = guides + 1 elseif not row.category then lessons = lessons + 1 end
    end
    CHECK(lessons == 0 and guides == #D.guides and #ShownRows() == guides + 6,
        "F: the navigator lists modules and guides only, never a lesson (D51)", #ShownRows())
    EQ(GuideRow("SSC_ATTUNEMENT").state.__w, 60, "F: the state column is 60 wide (Not needed, 200 badges)")
    -- the fold
    local before, raidGuides = #ShownRows(), 0
    for _, item in ipairs(S().items) do if item.kind == "guide" and item.category == "RAID" then raidGuides = raidGuides + 1 end end
    Click(raid)
    CHECK(raidGuides == 9 and db.AttuneCollapsed.RAID == true and GuideRow("KARAZHAN_ATTUNEMENT") == nil and #ShownRows() == before - raidGuides,
        "F: clicking a header folds it: AttuneCollapsed written, its nine guide rows gone", #ShownRows())
    local raidRow = HeaderRow("RAID")
    local chev = raidRow.chevron and raidRow.chevron[1]
    CHECK(chev and chev.__points[1].x == 9 and chev.__points[1].y == 2, "F: ...and the chevron turns shut",
        chev and (tostring(chev.__points[1].x) .. "," .. tostring(chev.__points[1].y)))
    Click(raidRow)
    chev = HeaderRow("RAID").chevron[1]
    CHECK(db.AttuneCollapsed.RAID == nil and GuideRow("KARAZHAN_ATTUNEMENT") ~= nil and chev.__points[1].x == 8 and chev.__points[1].y == 1.5,
        "F: a second click unfolds it (the key goes, the chevron opens)")
    -- words, strips, bars, heights
    local function Word(key) return GuideRow(key).state:GetText() end
    CHECK(Word("KARAZHAN_ATTUNEMENT"):match("^%d+/%d+$") and Word("KARAZHAN_ATTUNEMENT") == A.Guide("KARAZHAN_ATTUNEMENT").word,
        "F: a needed guide's word is its ratio", Word("KARAZHAN_ATTUNEMENT"))
    EQ(Word("SSC_ATTUNEMENT"), "Not needed", "F: a gate dropped this phase reads Not needed")
    EQ(Word("SUNWELL_PLATEAU"), "Phase 5", "F: a guide of a later phase reads the phase's short name")
    EQ(Word("BADGES"), "0 badges", "F: the recurring guide reads its badge count")
    CHECK(ColourIs(GuideRow("SSC_ATTUNEMENT").strip, Paper("faint")), "F: a Not needed strip is faint")
    CHECK(ColourIs(GuideRow("SUNWELL_PLATEAU").strip, Paper("warn")), "F: a later guide's strip is warn")
    local kz = GuideRow("KARAZHAN_ATTUNEMENT")
    local kzItem = A.Guide("KARAZHAN_ATTUNEMENT")
    CHECK(kzItem.done > 0 and ColourIs(kz.strip, Paper("open")), "F: a started guide's strip is open", tostring(kzItem.done))
    CHECK(ColourIs(GuideRow("ALDOR_SCRYER_CHOICE").strip, Paper("faint")) and A.Guide("ALDOR_SCRYER_CHOICE").done == 0,
        "F: an unstarted needed guide's strip is faint")
    local span = kit.NavChild():GetWidth() or 0
    if span <= 0 then span = 262 end
    CHECK(kz.bar:IsShown() and Same(kz.bar.__w, math.max(1, (span - 22) * kzItem.pct)),
        "F: the row bar is (span - 22) * pct wide", tostring(kz.bar.__w))
    CHECK(kz:GetHeight() == 30 and GuideRow("SSC_ATTUNEMENT"):GetHeight() == 24 and GuideRow("SUNWELL_PLATEAU"):GetHeight() == 24,
        "F: a guide with a ratio is 30 tall, an Other guide 24")
    db.ShowProgress = false
    Refresh()
    CHECK(GuideRow("KARAZHAN_ATTUNEMENT"):GetHeight() == 24 and not GuideRow("KARAZHAN_ATTUNEMENT").barBg:IsShown(),
        "F: with ShowProgress off every row is 24 and bar-less")
    db.ShowProgress = true
    Refresh()
    -- selection
    Click(GuideRow("KARAZHAN_ATTUNEMENT"))
    kz = GuideRow("KARAZHAN_ATTUNEMENT")
    CHECK(S().selected == "KARAZHAN_ATTUNEMENT" and kz.selection:IsShown() and Same(kz.selection.__color[4], 0.22)
        and ColourIs(kz.title, Paper("strong")), "F: a click selects the guide: the wash at 0.22, the title strong")
    CHECK(ColourIs(GuideRow("SSC_ATTUNEMENT").title, Paper("faint")) and ColourIs(GuideRow("GRUUL_MAGTHERIDON").title, Paper("primary")),
        "F: an Other guide's title is faint, a needed one primary")
    Sweep("F course")
    Click(GuideRow("KARAZHAN_ATTUNEMENT"))
    CHECK(S().selected == nil and not GuideRow("KARAZHAN_ATTUNEMENT").selection:IsShown(), "F: a second click returns to the overview")
    -- the toolbar
    local w = W()
    local xs = {}
    for i = 1, 4 do xs[i] = tostring(w.filters[i].__points[1].x) end
    EQ(table.concat(xs, ","), "0,44,88,132", "F: the four filters at 0, 44, 88, 132")
    EQ(Points(window.searchBox), searchPointsBefore, "F: the shared search box is where the window put it")
    local shownGuides = 0
    for _, item in ipairs(S().items) do if item.kind == "guide" then shownGuides = shownGuides + 1 end end
    EQ(w.countFS:GetText(), shownGuides .. " shown", "F: the count reads the guides on the list")
    local t = S().totals
    HAS(Tip(w.countHit), string.format("Done %d, To do %d, Not needed %d, Opens later %d", t.done, t.todo, t.notNeeded, t.later),
        "F: ...its tooltip the four totals")
    Note("F count tip", Tip(w.countHit))
    CHECK(t.notNeeded == 4 and t.later == 3 and t.done == 0 and t.todo == 18 and t.needed == 18 and t.guides == 25,
        "F: at Phase 4 and level 70: 4 not needed, 3 later (Sunwell, Magisters' Terrace, Shattered Sun), 18 to do, 25 counted (Badges never)",
        string.format("%d/%d/%d/%d/%d", t.done, t.todo, t.notNeeded, t.later, t.guides))
    local labels = { "All", "To do", "Done", "Other" }
    local wanted = { ALL = nil, TODO = "NEEDED", DONE = "DONE", OTHER = "OTHER" }
    local keys = { "ALL", "TODO", "DONE", "OTHER" }
    local allOk = true
    for i = 2, 4 do
        Click(w.filters[i])
        if db.AttuneFilter ~= keys[i] then allOk = false end
        for _, item in ipairs(S().items) do
            if item.kind == "guide" and item.bucket ~= wanted[keys[i]] then allOk = false end
        end
        if not (w.filters[i].underline.__color[4] > 0.9 and w.filters[1].underline.__color[4] == 0) then allOk = false end
        if w.filters[i]:GetText() ~= labels[i] then allOk = false end
    end
    CHECK(allOk, "F: To do, Done and Other each list only their bucket, the active one underlined")
    Click(w.filters[1])
    CHECK(db.AttuneFilter == "ALL" and w.filters[1].underline.__color[4] > 0.9 and ColourIs(w.filters[1]:GetFontString(), kit.Ink("strong")),
        "F: All again: its underline lit, its word strong")
    -- the phase button
    CHECK(w.phaseBtn:GetText() == "Phase 4" and ColourIs(w.phaseBtn:GetFontString(), kit.InkAccent()),
        "F: the phase button reads Phase 4 in the accent on automatic", w.phaseBtn:GetText())
    local rows = {}
    local addButton = UIDropDownMenu_AddButton
    UIDropDownMenu_AddButton = function(info) rows[#rows + 1] = info end
    w.phaseMenu.__init()
    UIDropDownMenu_AddButton = addButton
    local names = {}
    for i, info in ipairs(rows) do names[i] = info.text end
    EQ(table.concat(names, ","), "Automatic,Phase 1,Phase 2,Phase 3,Phase 4,Phase 5", "F: the menu's six rows")
    local tipsOk = #rows == 6 and rows[1].checked == true
    for i = 2, 6 do
        if rows[i].checked or rows[i].tooltipOnButton ~= true or type(rows[i].tooltipText) ~= "string" or rows[i].tooltipText == "" then tipsOk = false end
        Note("F menu tip", rows[i].tooltipText)
    end
    CHECK(tipsOk, "F: Automatic checked, every phase row carrying its rule sentences as a button tooltip")
    CHECK(rows[5].tooltipText:find("Honored", 1, true) and rows[4].tooltipText:find("Revered", 1, true)
        and rows[6].tooltipText:find("rest on inference", 1, true),
        "F: Phase 4 says Honored, Phase 3 Revered, Phase 5 names its inferred rules")
    rows[3].func()
    CHECK(db.AttunePhase == 2 and w.phaseBtn:GetText() == "Phase 2 (set)" and ColourIs(w.phaseBtn:GetFontString(), kit.Ink("secondary")),
        "F: choosing Phase 2 reads Phase 2 (set) in secondary ink, never warn", w.phaseBtn:GetText())
    local tip = Tip(w.phaseBtn)
    Note("F phase tip", tip)
    CHECK(tip:find("Your setting: Phase 2", 1, true) and tip:find("Calendar: Phase 4", 1, true) and tip:find("Click to choose.", 1, true),
        "F: ...its tooltip names the setting, the calendar's answer and the click", tip)
    rows[1].func()
    CHECK(db.AttunePhase == "AUTO" and w.phaseBtn:GetText() == "Phase 4", "F: Automatic again: Phase 4", w.phaseBtn:GetText())
    -- the empty messages the data can reach
    Tab.tab.SetSearch("zzzqq")
    Refresh()
    CHECK(#ShownRows() == 0 and w.emptyFS and w.emptyFS:IsShown() and w.emptyFS:GetText() == "No guide matches.",
        "F: a search nothing matches: No guide matches.", w.emptyFS and w.emptyFS:GetText())
    Tab.tab.SetSearch("")
    db.AttuneFilter = "DONE"
    Refresh()
    CHECK(#ShownRows() == 0 and w.emptyFS:IsShown() and w.emptyFS:GetText() == "Nothing finished yet.",
        "F: the Done filter with nothing finished: Nothing finished yet.", w.emptyFS:GetText())
    Sweep("F empty")
    db.AttuneFilter = "ALL"
    -- a finished guide: the Reservoir Key in the bags
    T.items[30623] = 1
    mock.Fire("BAG_UPDATE_DELAYED")
    Refresh()
    local cf = GuideRow("HEROIC_COILFANG")
    CHECK(cf and cf.state:GetText() == "Done" and ColourIs(cf.state, Paper("good")) and ColourIs(cf.strip, Paper("good")),
        "F: holding the Reservoir Key at 70 reads Done in good, strip good")
    local green = { kit.Paper(0.25, 0.82, 0.25) }
    CHECK(cf:GetHeight() == 30 and cf.bar:IsShown() and Same(cf.bar.__w, span - 22) and ColourIs(cf.bar, green[1], green[2], green[3]),
        "F: ...its bar full and green")
    CHECK(S().totals.done == 1 and w.emptyFS:IsShown() == false, "F: the totals count it done")
    T.items[30623] = nil
    mock.Fire("BAG_UPDATE_DELAYED")
    Refresh()
end

-- ===========================================================================
-- G. The briefing: the overview and the course page
-- ===========================================================================
Section("G")
do
    S().selected = nil
    WipeTouch()
    Refresh()
    local texts = Texts()
    EQ(texts[1], "Attunements", "G: the overview opens with its title")
    EQ(texts[2], "Phase 4, The Gods of Zul'Aman (Blizzard: Phase 3.5), since " .. DateWord(1792706400, true) .. ".",
        "G: the phase line names the phase, Blizzard's number and the date")
    EQ(texts[3], "Phase 4 since " .. DateWord(1792706400, true) .. ", from the calendar.", "G: then the engine's why")
    local t = S().totals
    EQ(texts[4], string.format("%d of %d guides done", t.done, t.needed) .. SEP .. string.format("%d%%", math.floor(t.pct * 100 + 0.5)),
        "G: the totals line")
    EQ(texts[5], "Done " .. t.done .. SEP .. "To do " .. t.todo .. SEP .. "Not needed " .. t.notNeeded .. SEP .. "Opens later " .. t.later,
        "G: the four counts")
    local iStand, iCont, iNext, iPhase = IndexOf(texts, "WHERE YOU STAND"), IndexOf(texts, "CONTINUE"), IndexOf(texts, "UP NEXT"), IndexOf(texts, "THIS PHASE")
    CHECK(iStand and iCont and iNext and iPhase and iStand < iCont and iCont < iNext and iNext < iPhase and iPhase < #texts,
        "G: WHERE YOU STAND, CONTINUE, UP NEXT, THIS PHASE in that order, the source line last",
        tostring(iStand) .. "," .. tostring(iCont) .. "," .. tostring(iNext) .. "," .. tostring(iPhase))
    EQ(texts[iStand + 1], "Raid attunements  0 of 4 done", "G: a module line under WHERE YOU STAND")
    CHECK(texts[iStand + 5] == "Flying  0 of 1 done" and texts[iStand + 6] == "Badges of Justice  0 in bags and bank",
        "G: ...Flying with a bar, Badges with its count and none", texts[iStand + 6])
    local thin = 0
    for _, q in ipairs(W().quads) do if q:IsShown() and q.__h == 3 then thin = thin + 1 end end
    CHECK(thin >= 5, "G: five 3 px module bars", thin)
    local contStep = Blocks()[iCont + 1]
    CHECK(S().continueKey == "KARAZHAN_ATTUNEMENT" and Strip(contStep:GetText()) == StepText(A.CurrentStep("KARAZHAN_ATTUNEMENT")) and GoAt(contStep) ~= nil,
        "G: CONTINUE draws the continue step as a line with a Go", Strip(contStep:GetText()))
    EQ(texts[iCont + 2], "The first guide you have started", "G: ...and the reason sentence")
    EQ(texts[iNext + 1], "Heroic Coilfang" .. SEP .. "2/3" .. SEP .. "Buy the Reservoir Key",
        "G: UP NEXT lists the started guides highest ratio first, each with its current step")
    local upNext, sorted, gos, lastPct = 0, true, true, 2
    for i = iNext + 1, iPhase - 1 do
        local d, t2 = texts[i]:match("^.-" .. SEP .. "(%d+)/(%d+)" .. SEP)
        if d then
            upNext = upNext + 1
            local pct = tonumber(d) / math.max(tonumber(t2), 1)
            if pct > lastPct + 0.001 then sorted = false end
            lastPct = pct
            if GoAt(Blocks()[i]) == nil then gos = false end
        end
    end
    CHECK(upNext == 6 and sorted and gos, "G: ...at most six of them, highest ratio first, each line with a Go",
        upNext .. " " .. tostring(sorted) .. " " .. tostring(gos))
    local rules = A.Rules(4).sentences
    EQ(texts[iPhase + 1], rules[1], "G: THIS PHASE prints the phase's sentences")
    HAS(texts[#texts], "The phase comes from the calendar", "G: the foot says where the phase comes from")
    Sweep("G overview")

    -- the course page: Karazhan at 70
    local calls, scroll = 0, nil
    local orig = kit.ScrollIntoView
    kit.ScrollIntoView = function(s, ...) calls = calls + 1; scroll = s; return orig(s, ...) end
    Click(GuideRow("KARAZHAN_ATTUNEMENT"))
    kit.ScrollIntoView = orig
    local summary, record = S().summary, D.guides[1]
    CHECK(S().focus == summary.current and summary.current == "arcane_disturbances" and calls > 0 and scroll == kit.DetailScroll(),
        "G: opening a guide selects its current step and scrolls the briefing to it", tostring(S().focus) .. " calls " .. calls)
    texts = Texts()
    EQ(texts[1], record.title, "G: the page title")
    local pct = string.format("%d%%", math.floor(summary.pct * 100 + 0.5))
    EQ(texts[2], "Raid attunements" .. SEP .. "From Phase 1" .. SEP .. summary.done .. " of " .. summary.total .. " steps" .. SEP .. pct,
        "G: the facts line")
    local aw = BlockWith("Account-wide on Anniversary")
    CHECK(aw and ColourIs(aw, kit.Paper(C.ToneRGB("log"))), "G: the account-wide notice in the log tone")
    EQ(texts[IndexOf(texts, "Account-wide") + 1], record.unlocks, "G: what the guide unlocks follows the notices")
    EQ(texts[IndexOf(texts, "STEPS")], "STEPS" .. SEP .. summary.done .. " of " .. summary.total .. " done", "G: the STEPS heading counts")
    local wantLines, haveLines = 0, 0
    for _, v in ipairs(S().steps) do
        if v.section ~= "SPEND" then
            wantLines = wantLines + 1
            if StepBlock(v.key) then haveLines = haveLines + 1 end
        end
    end
    CHECK(wantLines == #S().steps and haveLines == wantLines, "G: one line per drawn step, word then title", haveLines .. "/" .. wantLines)
    local cur = StepBlock("arcane_disturbances")
    local band = W().bands[1]
    CHECK(band and band:IsShown() and PointY(band) == PointY(cur) + 1 and band.__h == (cur:GetStringHeight() or 12) + 2,
        "G: the band sits under the current step's line, a pixel above it", tostring(PointY(band)) .. " vs " .. tostring(PointY(cur)))
    local iCur = IndexOf(texts, StepText(View("arcane_disturbances")))
    local iNextStep = IndexOf(texts, StepText(View("restless_activity")))
    local iHow = IndexOf(texts, "How the tab knows: ", iCur)
    CHECK(texts[iCur + 1] == "Checked: " .. View("arcane_disturbances").reason and iHow and iHow == iNextStep - 1,
        "G: the open body starts with Checked and ends with How the tab knows", texts[iCur + 1])
    EQ(texts[iHow], "How the tab knows: " .. View("arcane_disturbances").how, "G: ...the engine's sentence")
    HAS(texts[iCur + 3], "Starts  Archmage Alturus, Deadwind Pass 47.0, 75.5", "G: a place line reads role, name, zone and coordinates")
    Sweep("G Karazhan")
    -- focus by hit
    local other = StepBlock("contact_from_dalaran")
    Click(HitAt(other))
    texts = Texts()
    local iOther = IndexOf(texts, StepText(View("contact_from_dalaran")))
    CHECK(S().focus == "contact_from_dalaran" and texts[iOther + 1] == "Checked: In your log",
        "G: clicking a step's line opens its lesson", texts[iOther + 1])
    Click(HitAt(StepBlock("contact_from_dalaran")))
    CHECK(S().focus == summary.current and Texts()[IndexOf(Texts(), StepText(View("arcane_disturbances"))) + 1]:find("^Checked: "),
        "G: a second click returns to the current step")
    -- Escape walks back one level
    Tab.tab.SetSearch("x")
    Tab.tab.EscapeSearch()
    local a = S().search == ""
    S().focus = "khadgar"
    Refresh()
    Tab.tab.EscapeSearch()
    Refresh()
    local b = S().focus == summary.current and S().selected == "KARAZHAN_ATTUNEMENT"
    Tab.tab.EscapeSearch()
    Refresh()
    CHECK(a and b and S().selected == nil, "G: Escape clears the search, then the lesson, then the course")
    -- Done steps folded
    db.AttuneShowDone = false
    Open("KARAZHAN_ATTUNEMENT")
    local fold = BlockWith(" done. Show")
    local hiddenN = S().summary.doneHidden
    CHECK(fold and StepBlock("level_68") == nil and Strip(fold:GetText()) == hiddenN .. (hiddenN == 1 and " step done. Show" or " steps done. Show"),
        "G: with Show Done Steps off, done steps fold into one line", fold and Strip(fold:GetText()))
    Click(HitAt(fold))
    CHECK(S().showDone == true and StepBlock("level_68") ~= nil, "G: its Show hit reveals them for the session")
    S().showDone = nil
    db.AttuneShowDone = true
    -- other phases folded
    Open("HEROIC_HELLFIRE")
    fold = BlockWith(" from another phase. Show")
    CHECK(fold and Strip(fold:GetText()) == "1 step from another phase. Show" and View("rep_revered") == nil,
        "G: a step outside the phase window folds into one line", fold and Strip(fold:GetText()))
    Click(HitAt(fold))
    local past = View("rep_revered")
    local pastBlock = StepBlock("rep_revered")
    CHECK(S().showOtherPhases == true and past and past.status == "PAST" and past.word == "Until Phase 3" and past.counted == false
        and pastBlock and ColourIs(pastBlock, kit.Paper(kit.Ink("faint"))),
        "G: revealed, it reads Until Phase 3 in faint ink and does not count")
    Sweep("G Hellfire other")
    S().showOtherPhases = false
    -- notices
    Open("SUNWELL_PLATEAU")
    local later = BlockWith("Opens in Phase 5 (")
    CHECK(later and Strip(later:GetText()) == "Opens in Phase 5 (Fury of the Sunwell), no date announced. Read ahead; nothing here can be started yet."
        and ColourIs(later, kit.Paper(C.ToneRGB("warn"))), "G: a later guide's notice in warn", later and Strip(later:GetText()))
    Open("SSC_ATTUNEMENT")
    local nn = BlockWith("Not needed since")
    local ssc = A.byKey.SSC_ATTUNEMENT
    CHECK(nn ~= nil and ColourIs(nn, kit.Paper(kit.Ink("faint"))), "G: a Not needed guide carries a faint notice")
    EQ(nn and Strip(nn:GetText()), ssc.phase.note, "G: ...reading the guide's phase note (5.4 item 4: text = guide.phase.note)")
    local sscTip = Tip(GuideRow("SSC_ATTUNEMENT"))
    Note("G SSC row tip", sscTip)
    local _, prefixes = sscTip:gsub("Not needed since Phase 3", "")
    CHECK(prefixes == 1, "G: the row tooltip says Not needed since Phase 3 once (4.10's notice over the phase note)", sscTip)
    Sweep("G SSC")
    T.items[30622] = 1
    mock.Fire("BAG_UPDATE_DELAYED")
    Open("HEROIC_HELLFIRE")
    local held = BlockWith("You hold the Flamewrought Key")
    CHECK(held and ColourIs(held, kit.Paper(C.ToneRGB("good"))) and S().summary.unlockHeld == true and A.Guide("HEROIC_HELLFIRE").status == "DONE",
        "G: holding the key at 70: the guide is Done and the notice is good")
    EQ(held and Strip(held:GetText()), "You hold the Flamewrought Key: heroic Hellfire Citadel is open to you.",
        "G: ...worded as 3.6 words it (the citadel, not one wing)")
    T.level = 62
    A.Invalidate("char")
    Refresh()
    held = BlockWith("You hold the Flamewrought Key")
    CHECK(held and Strip(held:GetText()):find("; ", 1, true) and Strip(held:GetText()):find("opens at level 70.$")
        and ColourIs(held, kit.Paper(C.ToneRGB("warn"))) and A.Guide("HEROIC_HELLFIRE").word == "2/3" and View("level_70").word == "Locked",
        "G: at 62 the same key reads 2/3, the notice says it opens at 70 in warn, the level step Locked",
        held and Strip(held:GetText()))
    T.level = 70
    A.Invalidate("char")
    T.items[30622] = nil
    mock.Fire("BAG_UPDATE_DELAYED")
    db.AttuneAccount.KARAZHAN_ATTUNEMENT = { char = "Main-Realm", at = 1792300000 }
    A.Invalidate("store")
    Open("KARAZHAN_ATTUNEMENT")
    local ledger = BlockWith("Done by Main-Realm")
    CHECK(ledger and Strip(ledger:GetText()) == "Done by Main-Realm on " .. DateWord(1792300000) .. " (account ledger)."
        and ColourIs(ledger, kit.Paper(C.ToneRGB("good"))) and GuideRow("KARAZHAN_ATTUNEMENT").state:GetText() == "Done",
        "G: the account ledger makes the guide Done with its notice", ledger and Strip(ledger:GetText()))
    db.AttuneAccount.KARAZHAN_ATTUNEMENT = nil
    A.Invalidate("store")
    fake.SetRep(934, 0)
    A.Invalidate("reps")
    S().showOtherPhases = true          -- the Black Temple chain is Phase 3's; its steps are PAST at Phase 4
    Open("BLACK_TEMPLE_ATTUNEMENT")
    local side = BlockWith("Pick a side in the Aldor or Scryers guide")
    local tablets = View("tablets_of_baari")
    CHECK(side ~= nil and A.Side() == nil and tablets and #tablets.places == 4 and tablets.places[1].name == "Aldor: Anchorite Ceyla"
        and tablets.places[2].name == "Scryers: Arcanist Thelis",
        "G: with the side undecided the page says to pick one and a side-split step lists both places",
        tostring(side ~= nil) .. " " .. tostring(A.Side()) .. " " .. tostring(tablets and #tablets.places))
    Sweep("G BT")
    S().showOtherPhases = false
    Open("ALDOR_SCRYER_CHOICE")
    S().focus = "allegiance"
    Refresh()
    local pledge = BlockWith("I pledged the Aldor")
    CHECK(pledge and BlockWith("I pledged the Scryers") and HitAt(pledge) ~= nil, "G: the undecided choice page offers the two pledge lines")
    Click(HitAt(pledge))
    local chosen, why = A.Side()
    CHECK(chosen == "ALDOR" and why == "chosen by you" and Char().side == "ALDOR" and BlockWith("I pledged the Aldor") == nil,
        "G: clicking one records the side as chosen by you and the lines go", tostring(chosen) .. " " .. tostring(why))
    Char().side = nil
    S().focus = nil
    fake.SetRep(934, -3500)
    A.Invalidate("reps")
    A.Invalidate("store")
    T.level = 41
    A.Invalidate("char")
    Open("KARAZHAN_ATTUNEMENT")
    local low = BlockWith("Your level is 41")
    CHECK(low and Strip(low:GetText()) == "Your level is 41; this guide begins at 68." and View("level_68").word == "Locked"
        and S().summary.current == "level_68" and PointY(W().bands[1]) == PointY(StepBlock("level_68")) + 1,
        "G: under level the page says so, the level step Locked and banded as current", low and Strip(low:GetText()))
    Sweep("G Karazhan 41")
    T.level = 70
    A.Invalidate("char")
    -- the recurring guide
    Open("BADGES")
    texts = Texts()
    CHECK(IndexOf(texts, "EARN THIS PHASE") and IndexOf(texts, "SPEND THIS PHASE") and IndexOf(texts, "EARN THIS PHASE") < IndexOf(texts, "SPEND THIS PHASE"),
        "G: the Badges page is EARN THIS PHASE then SPEND THIS PHASE")
    EQ(texts[2], "Badges of Justice" .. SEP .. "0 in bags and bank" .. SEP .. "resets with each lockout", "G: ...its facts line")
    local geras = BlockWith("Vendor  G'eras, Shattrath City 50.8, 42.3")
    CHECK(geras and GoAt(geras) ~= nil and IndexOf(texts, "Vendor  G'eras") > IndexOf(texts, "SPEND THIS PHASE"),
        "G: a SPEND vendor line with a Go under the heading")
    Sweep("G Badges")
    -- prerequisites
    Open("BLACK_TEMPLE_ATTUNEMENT")
    texts = Texts()
    local iAlso = IndexOf(texts, "ALSO NEEDED")
    CHECK(iAlso and texts[iAlso + 1] == "Not needed  Mount Hyjal  (recommended)",
        "G: ALSO NEEDED lists a soft prerequisite as recommended with its word", texts[iAlso and iAlso + 1])
    Click(HitAt(Blocks()[iAlso + 1]))
    EQ(S().selected, "HYJAL_ATTUNEMENT", "G: ...and its hit opens that guide")
    Sweep("G Hyjal")
    local bad
    for _, pair in ipairs(drawn) do
        if pair[2]:find("_", 1, true) or pair[2]:find("C_", 1, true) then bad = pair[1] .. ": " .. pair[2] end
    end
    CHECK(bad == nil, "G: no drawn string carries an underscore or a client prefix", bad)
end

-- ===========================================================================
-- H. Go: the door rule with and without Orders
-- ===========================================================================
Section("H")
do
    S().showOtherPhases = false
    CommanderOrders = nil
    Open("KARAZHAN_ATTUNEMENT")
    local ad = View("arcane_disturbances")
    local t, why, idx = A.PlaceFor(ad, nil)
    CHECK(t and t.spec and t.spec.map == 1430 and t.query == nil and t.key == "quest:9824" and idx == 1,
        "H: an open quest step's default place is its start, a spec, under the shared quest key")
    local adGo = GoAt(StepBlock("arcane_disturbances"))
    CHECK(adGo and adGo.__enabled ~= false, "H: with no Orders a spec Go stays enabled")
    local sv = View("second_fragment_steamvault")
    local svGo = GoAt(StepBlock("second_fragment_steamvault"))
    local q = svGo and svGo._lineOpts.query()
    CHECK(svGo and svGo.__enabled == false and q and q.entrance and q.entrance.instance == 545 and svGo._lineOpts.spec() == nil,
        "H: an inside row with no coordinates is a query alone: greyed without Orders")
    HAS(Tip(svGo), "Needs Commander Orders", "H: ...saying Needs Commander Orders")
    Note("H inside tip", Tip(svGo))
    Open("GRUUL_MAGTHERIDON")
    local door = GoAt(StepBlock("gruul_door"))
    CHECK(door and door.__enabled ~= false and door._lineOpts.spec() and door._lineOpts.spec().map == 1949,
        "H: a door row without Orders fills its spec from the authored coordinates")
    mock.WipeLog()
    Click(door)
    CHECK(mock.Logged("/way #1949 68.70 24.30 Gruul's Lair") ~= nil, "H: ...and its click prints the /way line", mock.printLog[1])
    local w = W()
    CHECK(S().focus == "gruul_door" or S().summary.current == "gruul_door", "H: (the door step is the current one)", S().summary.current)
    mock.WipeLog()
    CHECK(w.goBtn.__enabled ~= false, "H: the action-bar Go on the door step is enabled without Orders")
    Click(w.goBtn)
    CHECK(mock.Logged("/way #1949 68.70 24.30 Gruul's Lair") ~= nil, "H: ...and prints the same line", mock.printLog[1])
    CommanderOrders = O_API
    Refresh()
    door = GoAt(StepBlock("gruul_door"))
    q = door._lineOpts.query()
    CHECK(q and q.entrance and q.entrance.instance == 565 and door._lineOpts.spec() == nil,
        "H: with Orders the same door line is a query and its spec answers nil (Orders' table decides)")
    local n = #O.gone
    Click(door)
    local gone = LastGone()
    CHECK(#O.gone == n + 1 and gone.target.entrance and gone.target.entrance.instance == 565 and gone.target.map == nil
        and gone.opts.key == "attune:GRUUL_MAGTHERIDON:gruul_door:1" and gone.opts.source == "QuestLog",
        "H: ...its click records the entrance query, never the authored coordinates", gone and gone.opts.key)
    HAS(Tip(door), "Go to: Gruul's Lair - Blade's Edge Mountains 68.7, 24.3", "H: ...and the tooltip names the door Orders found")
    Click(w.goBtn)
    gone = LastGone()
    CHECK(gone.target.entrance and gone.target.entrance.instance == 565 and gone.opts.key == "attune:GRUUL_MAGTHERIDON:gruul_door:1",
        "H: the action-bar Go on the door step records the same query")
    -- a turn-in in the log
    Open("KARAZHAN_ATTUNEMENT")
    local cd = View("contact_from_dalaran")
    local cdGo = GoAt(StepBlock("contact_from_dalaran"))
    HAS(Tip(cdGo), "Go to: Archmage Cedric - Alterac Mountains 15.5, 54.5", "H: a turn-in Go reads the finisher and the zone")
    Note("H turn-in tip", Tip(cdGo))
    Click(cdGo)
    gone = LastGone()
    CHECK(gone.opts.source == "QuestLog" and gone.opts.key == "quest:9826" and gone.target.map == 1416,
        "H: ...and records source QuestLog under the shared quest key")
    t, why, idx = A.PlaceFor(cd, nil)
    CHECK(t and t.key == "quest:9826" and idx == 2, "H: PlaceFor answers the turn-in as the default place with its index 2", idx)
    Click(GoAt(StepBlock("second_fragment_steamvault")))
    gone = LastGone()
    CHECK(gone.target.entrance and gone.target.entrance.instance == 545 and gone.opts.key == "attune:KARAZHAN_ATTUNEMENT:second_fragment_steamvault:1",
        "H: an inside step records its instance under its attune key", gone.opts.key)
    EQ(A.Go((A.PlaceFor(sv, nil))), "ORDERS", "H: A.Go on the same target answers ORDERS")
    -- Magisters' Terrace by instance id
    local steps = A.Steps("HEROIC_MAGISTERS_TERRACE", { otherPhases = true })
    local tyrith
    for _, v in ipairs(steps) do if v.key == "find_tyrith" then tyrith = v end end
    t, why, idx = A.PlaceFor(tyrith, 2)
    CHECK(t and t.query and t.query.entrance.instance == 585 and t.spec == nil and idx == 2 and t.key == "quest:11488" and A.Go(t) == "ORDERS"
        and LastGone().target.entrance.instance == 585 and LastGone().opts.key == "quest:11488",
        "H: a turn-in inside Magisters' Terrace is the entrance query for 585 under the quest key", t and t.key)
    t, why, idx = A.PlaceFor(tyrith, 3)
    CHECK(t and t.query and t.query.entrance.instance == 585 and idx == 3 and A.Go(t) == "ORDERS"
        and LastGone().target.entrance.instance == 585 and LastGone().opts.key == "attune:HEROIC_MAGISTERS_TERRACE:find_tyrith:3",
        "H: its inside row the same door under the attune key: 585 everywhere, never a uiMap", t and t.key)
    -- Ctrl+Right-click on a row and on a hit
    n = #O.gone
    Click(GuideRow("KARAZHAN_ATTUNEMENT"), "CTRL", "RightButton")
    gone = LastGone()
    CHECK(#O.gone == n + 1 and gone.opts.key == "quest:9824" and gone.target.map == 1430 and S().selected == "KARAZHAN_ATTUNEMENT",
        "H: Ctrl+Right-click on a row goes to its current step's default place", gone.opts.key)
    Click(GuideRow("KARAZHAN_ATTUNEMENT"), nil, "RightButton")
    EQ(#O.gone, n + 1, "H: a plain right-click is no Go")
    Click(HitAt(StepBlock("second_fragment_steamvault")), "CTRL", "RightButton")
    gone = LastGone()
    CHECK(#O.gone == n + 2 and gone.target.entrance.instance == 545, "H: Ctrl+Right-click on a step's line does the same")
    -- Nothing to go to
    Open("HEROIC_HELLFIRE")
    S().focus = "level_70"
    Refresh()
    CHECK(w.goBtn.__enabled == false, "H: a LEVEL step greys the action-bar Go")
    HAS(Tip(w.goBtn), "Nothing to go to", "H: ...with Nothing to go to")
    S().focus = "rep_honored"
    Refresh()
    CHECK(w.goBtn.__enabled == false and GoAt(StepBlock("rep_honored")) == nil and Tip(w.goBtn):find("Nothing to go to", 1, true) ~= nil,
        "H: a REP step too, and its line carries no Go")
    Note("H nothing tip", Tip(w.goBtn))
    S().focus = nil
    -- the action Go follows the focus
    Open("KARAZHAN_ATTUNEMENT")
    S().focus = "arcane_disturbances"
    Refresh()
    local k1 = w.goBtn._lineOpts.key
    S().focus = "second_fragment_steamvault"
    Refresh()
    local k2 = w.goBtn._lineOpts.key
    CHECK(k1 == "quest:9824" and k2 == "attune:KARAZHAN_ATTUNEMENT:second_fragment_steamvault:1", "H: the action Go follows the focus",
        tostring(k1) .. " then " .. tostring(k2))
    S().focus = nil
    -- the turn-in cleanup
    for i = #O.removed, 1, -1 do O.removed[i] = nil end
    mock.Fire("QUEST_TURNED_IN", 9826)
    local removed = table.concat(O.removed, ",")
    CHECK(removed:find("quest:9826", 1, true) and removed:find("attune:KARAZHAN_ATTUNEMENT:contact_from_dalaran:1", 1, true)
        and removed:find("attune:KARAZHAN_ATTUNEMENT:contact_from_dalaran:2", 1, true),
        "H: QUEST_TURNED_IN removes the quest key and every attune key of the step", removed)
    Char().seen[9826] = nil         -- the grace window would hold the step Done for the rest of the run
    A.Invalidate("quests")
    mock.RunTimers(12)
end

-- ===========================================================================
-- J. The hero card
-- ===========================================================================
Section("J")
do
    local w = W()
    S().selected = nil
    WipeTouch()
    A.Touch("HEROIC_COILFANG")
    Refresh()
    local item = A.Guide("HEROIC_COILFANG")
    CHECK(S().continueReason == "opened" and w.card.name:GetText() == "Heroic Coilfang"
        and w.card.totals:GetText() == string.format("%d/%d", item.done, item.total) and w.card.note:GetText() == "Next: Buy the Reservoir Key",
        "J: the card continues the guide opened last: name, ratio, Next", w.card.note:GetText())
    local span = (w.card:GetWidth() or 0) - 16
    if span <= 0 then span = kit.NAV_W - 16 end
    CHECK(w.card.bar:IsShown() and Same(w.card.bar.__w, math.max(1, span * item.pct)) and ColourIs(w.card.bar, kit.InkAccent()),
        "J: its bar is the card's width times the ratio, in the accent", tostring(w.card.bar.__w))
    local tip = Tip(w.card)
    Note("J card tip", tip)
    CHECK(tip:find("^Continue where you left off | Heroic Coilfang Reservoir: the Reservoir Key | Buy the Reservoir Key | Done when Reservoir Key", 1) ~= nil
        and tip:find("You opened this guide last", 1, true) and tip:find("Click to open. Right-click for the overview.", 1, true),
        "J: the tooltip: title, step, how, reason, the clicks", tip)
    Click(w.card)
    CHECK(S().selected == "HEROIC_COILFANG" and S().focus == "buy_key", "J: a left-click opens the guide on that step")
    Click(w.card, nil, "RightButton")
    EQ(S().selected, nil, "J: a right-click returns to the overview")
    WipeTouch()
    A.Touch("ALDOR_SCRYER_CHOICE")
    Refresh()
    EQ(w.card.note:GetText(), "Start here: Speak with A'dal in the Terrace of Light", "J: a guide with nothing done reads Start here")
    T.level = 41
    A.Invalidate("char")
    WipeTouch()
    A.Touch("KARAZHAN_ATTUNEMENT")
    Refresh()
    EQ(w.card.note:GetText(), "Locked: Reach level 68", "J: a level-locked current step reads Locked")
    WipeTouch()
    Refresh()
    -- Rule (3): Heroic Coilfang is started at 41 because the Cenarion
    -- Expedition is already Honored (a REP step done by standing)
    CHECK(S().continueReason == "started" and S().continueKey == "HEROIC_COILFANG" and w.card.note:GetText() == "Locked: Reach level 70",
        "J: a standing already met makes a guide started even at 41; its locked level step is the card's", w.card.note:GetText())
    fake.SetRep(942, 2000)
    A.Invalidate("reps")
    Refresh()
    CHECK(S().continueReason == "none" and w.card.name:GetText() == "Attunements" and w.card.totals:GetText() == "0/" .. S().totals.needed
        and w.card.note:GetText() == "Pick a guide to begin." and not w.card.bar:IsShown(),
        "J: at 41 with nothing started nothing can begin: Pick a guide to begin, no bar", w.card.note:GetText())
    fake.SetRep(942, 9500)
    A.Invalidate("reps")
    T.level = 70
    A.Invalidate("char")
    local marked = {}
    for _, g in ipairs(D.guides) do
        local it = A.Guide(g.key)
        if it and it.bucket == "NEEDED" and it.status ~= "RECURRING" then
            A.MarkGuide(g.key, true)
            marked[#marked + 1] = g.key
        end
    end
    WipeTouch()
    Refresh()
    local green = { kit.Paper(0.25, 0.82, 0.25) }
    CHECK(S().continueReason == "done" and w.card.name:GetText() == "Attunements"
        and w.card.totals:GetText() == S().totals.needed .. "/" .. S().totals.needed
        and w.card.note:GetText() == "Everything needed this phase is done.",
        "J: with every needed guide done the card says so", w.card.note:GetText())
    CHECK(w.card.bar:IsShown() and Same(w.card.bar.__w, span) and ColourIs(w.card.bar, green[1], green[2], green[3]),
        "J: ...its bar full and green")
    Sweep("J done")
    for _, key in ipairs(marked) do A.MarkGuide(key, false) end
    WipeTouch()
    Refresh()
    EQ(S().continueReason, "started", "J: marks undone, the card continues the first started guide again")
end

-- ===========================================================================
-- K. Settings, saved variables, slash
-- ===========================================================================
Section("K")
do
    local function Control(label)
        for _, f in ipairs(mock.allFrames) do
            if f.Text and f.Text.__text == label then return f end
            if f.__kind == "Button" and f.__text == label then return f end
        end
        return nil
    end
    local function LabelString(label)
        for _, f in ipairs(mock.allFrames) do
            for _, fs in ipairs(f.__fontStrings or {}) do
                if fs.__text == label then return fs end
            end
        end
        return nil
    end
    local defaults = { ShowAttuneTab = true, AttunePhase = "AUTO", AttuneFilter = "ALL", AttuneShowDone = true }
    local ok = true
    for key, value in pairs(defaults) do if db[key] ~= value then ok = false end end
    CHECK(ok and type(db.AttuneCollapsed) == "table" and type(db.AttuneAccount) == "table" and type(db.AttunePhaseSeen) == "table",
        "K: the seven Attune defaults are in place")
    CHECK(next(db.AttuneCollapsed) == nil and next(db.AttuneAccount) == nil and next(db.AttunePhaseSeen) == nil,
        "K: the three tables saved as other types were made tables at login")
    local at = Char()
    CHECK(type(at.marks) == "table" and next(at.marks) == nil and at.guide == nil and type(at.seen) == "table" and type(at.kills) == "table"
        and type(at.phaseEvidence) == "table", "K: EnsureCharDB repaired the character table's sub-tables and its guide")
    db.AttuneCollapsed.RAID = true
    db.AttuneAccount.KARAZHAN_ATTUNEMENT = { char = "Main-Realm", at = 1792300000 }
    db.AttunePhaseSeen[4] = { n = 4, kind = "lockout", detail = "Zul'Aman lockout", when = 1 }
    at.marks["HEROIC_HELLFIRE:buy_key"] = 1792300000
    db.AttuneFilter = "DONE"
    A.SetPhase(2)
    Refresh()
    EQ(W().phaseBtn:GetText(), "Phase 2 (set)", "K: (Phase 2 set before the reset)")
    SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
    CHECK(db.AttuneCollapsed.RAID == true and db.AttuneAccount.KARAZHAN_ATTUNEMENT ~= nil and db.AttunePhaseSeen[4] ~= nil
        and Char().marks["HEROIC_HELLFIRE:buy_key"] == 1792300000,
        "K: Restore Defaults keeps the folds, the ledger, the evidence and the character's marks")
    CHECK(db.AttuneFilter == "ALL" and db.AttunePhase == "AUTO" and db.ShowAttuneTab == true and db.AttuneShowDone == true,
        "K: ...and puts the four options back")
    -- ViewMode is a defaulted key too: the reset leaves the window on the
    -- Log, so the tab is switched back on before its button is read
    Settle()
    EQ(Q.ViewMode(), "LOG", "K: (Restore Defaults also puts ViewMode back to the Log)")
    Q.SetViewMode("ATTUNE")
    EQ(W().phaseBtn:GetText(), "Phase 4", "K: after the reset the phase button reads the calendar's phase, no (set)")
    db.AttuneCollapsed.RAID = nil
    db.AttuneAccount.KARAZHAN_ATTUNEMENT = nil
    db.AttunePhaseSeen[4] = nil
    Char().marks["HEROIC_HELLFIRE:buy_key"] = nil
    A.Invalidate("store")
    A.Invalidate("phase")
    for _, label in ipairs({ "Attunements Tab", "Show Done Steps", "Open Attunements", "Clear Marks" }) do
        CHECK(Control(label) ~= nil, "K: the settings page has " .. label)
    end
    CHECK(LabelString("Content Phase") ~= nil, "K: ...and the Content Phase dropdown")
    at.marks["HEROIC_HELLFIRE:buy_key"] = 1792300000
    Click(Control("Clear Marks"))
    CHECK(next(Char().marks) == nil, "K: Clear Marks wipes the marks")
    local slash = SlashCmdList["COMMANDERUI_QUESTLOG"]
    Q.SetViewMode("LOG")
    slash("attune")
    CHECK(Q.ViewMode() == "ATTUNE" and S().selected == nil, "K: /cql attune opens the tab on its overview", Q.ViewMode())
    slash("attune kara")
    EQ(S().selected, "KARAZHAN_ATTUNEMENT", "K: /cql attune kara lands on Karazhan")
    mock.WipeLog()
    Q.SetViewMode("LOG")
    slash("attune zzz")
    CHECK(mock.Logged("Commander Quest Log: no attunement guide matches 'zzz'. Try /cql attune and pick from the list.") ~= nil
        and Q.ViewMode() == "ATTUNE", "K: /cql attune zzz prints the no-match line and opens the tab", mock.printLog[1])
    slash("rep shatar")
    EQ(Q.ViewMode(), "REP", "K: /cql rep shatar still routes to the Reputations tab")
    mock.WipeLog()
    slash("status")
    local lines = 0
    for _, line in ipairs(mock.printLog) do if line:find("^%s*Attunements: ") then lines = lines + 1 end end
    EQ(lines, 5, "K: /cql status prints the five Attunements lines")
    db.ShowAttuneTab = false
    mock.WipeLog()
    Q.SetViewMode("LOG")
    Q.OpenToTab("ATTUNE", "KARAZHAN_ATTUNEMENT")
    CHECK(Tab.tab.PrepareOpen("KARAZHAN_ATTUNEMENT") == false and Q.ViewMode() == "LOG"
        and mock.Logged("Commander Quest Log: the Attunements tab is switched off (Settings, Attunements).") ~= nil,
        "K: switched off, PrepareOpen refuses and says so; OpenToTab leaves the Log", mock.printLog[1])
    db.ShowAttuneTab = true
    A.SetPhase(2)
    Q.OpenToTab("ATTUNE", "SSC_ATTUNEMENT", "mark_of_vashj")
    CHECK(Q.ViewMode() == "ATTUNE" and S().selected == "SSC_ATTUNEMENT" and S().focus == "mark_of_vashj",
        "K: OpenToTab with a step key lands on that lesson", tostring(S().selected) .. " " .. tostring(S().focus))
    Sweep("K SSC phase 2")
    A.SetPhase("AUTO")
    Refresh()
end

-- ===========================================================================
-- Q. The module with no Questie at all
-- ===========================================================================
Section("Q")
do
    db.AttuneFilter = "ALL"
    S().selected = nil
    WipeTouch()
    Refresh()
    local wordsBefore, barsBefore = {}, {}
    for _, row in ipairs(ShownRows()) do
        if row.guideKey then
            wordsBefore[row.guideKey] = Strip(row.state:GetText())
            barsBefore[row.guideKey] = row.bar:IsShown() and row.bar.__w or 0
        end
    end
    local totalsBefore = Texts()[4]
    fake.Uninstall()
    for event in pairs(mock.eventRegistry) do mock.eventRegistry[event] = nil end
    for i = #mock.timers, 1, -1 do mock.timers[i] = nil end
    CommanderQuestLog = nil
    CommanderQuestLogChar = nil
    CommanderQuestLog_OpenToZone = nil
    O.notify = false
    db.ViewMode = "ATTUNE"
    LoadModule()
    mock.Fire("ADDON_LOADED", "Commander_QuestLog")
    mock.Fire("PLAYER_LOGIN")
    Q = CommanderQuestLog
    A, Tab, D = Q.Attune, Q.Attunements, CommanderQuestLogAttuneData
    kit, C = Q._kit, Q.Catalogue
    Settle()
    EQ(Q.Questie.State(), "ABSENT", "Q: with no Questie the adapter says ABSENT")
    CommanderQuestLog_Show()
    window = _G.CommanderQuestLogFrame
    CHECK(window:IsShown() and Q.ViewMode() == "ATTUNE" and S().selected == nil, "Q: the window opens on the Attunements overview")
    local same, bars, count = true, true, 0
    for _, row in ipairs(ShownRows()) do
        if row.guideKey then
            count = count + 1
            if wordsBefore[row.guideKey] ~= Strip(row.state:GetText()) then same = false end
            if not Same(barsBefore[row.guideKey], row.bar:IsShown() and row.bar.__w or 0) then bars = false end
        end
    end
    CHECK(same and count == 26, "Q: every guide row carries the word it had with Questie", count)
    CHECK(bars, "Q: ...and the same bar")
    EQ(Texts()[4], totalsBefore, "Q: the overview's totals line is unchanged")
    local n, source, since, why, votes = A.Phase()
    CHECK(n == 4 and source == "calendar" and votes.questie == nil, "Q: the phase keeps its calendar term and loses only Questie's vote",
        tostring(n) .. " " .. tostring(source))
    HAS(Tip(W().phaseBtn), "Questie: none", "Q: the phase button's tooltip says Questie has no vote")
    Open("KARAZHAN_ATTUNEMENT")
    local adGo = GoAt(StepBlock("arcane_disturbances"))
    CHECK(adGo and adGo.__enabled ~= false, "Q: a spec Go is enabled without Questie")
    CommanderOrders = nil
    mock.WipeLog()
    local how = A.Go((A.PlaceFor(View("arcane_disturbances"), nil)))
    CHECK(how == "PRINT" and mock.Logged("/way #1430 47.00 75.50") ~= nil, "Q: ...and without Orders too its Go prints the /way line",
        tostring(how) .. " " .. tostring(mock.printLog[1]))
    CommanderOrders = O_API
    local lines = A.StatusLines()
    EQ(lines[5], "Attunements: Questie not loaded (phase vote missing); Commander Orders ready.", "Q: the status line says Questie is not loaded")
    HAS(lines[1], "Attunements: Phase 4, The Gods of Zul'Aman, since " .. DateWord(1792706400, true) .. "; from the calendar. Votes: calendar 4, Questie none, evidence none, setting automatic.",
        "Q: ...and the phase line reads the calendar")
    Sweep("Q Karazhan")
    S().selected = nil
    Refresh()
    EQ(#mock.caughtErrors, 0, "Q: no error anywhere in the Questie-less session", mock.caughtErrors[1])
end

-- ===========================================================================
-- Z. Hygiene
-- ===========================================================================
Section("Z")
do
    local fresh = {}
    for key in pairs(_G) do
        if not globalsBefore[key] and type(key) == "string" and not key:find("^CommanderQuestLog")
            and not key:find("^COMMANDER_QUESTLOG") and not key:find("^BINDING_") and not key:find("^SLASH_")
            and not key:find("^CommanderUI") then
            fresh[#fresh + 1] = key
        end
    end
    table.sort(fresh)
    EQ(table.concat(fresh, ","), "", "Z: no global written beyond the module's own")
    EQ(#mock.caughtErrors, 0, "Z: no errors across the run", mock.caughtErrors[1])
    local function Plain(s)
        s = s:gsub(C.SEP, ""):gsub(C.DASH, ""):gsub(C.ELLIPSIS, "")
        return not s:find("[\128-\255]")
    end
    local odd
    for _, pair in ipairs(drawn) do
        if not Plain(pair[2]) then odd = pair[1] .. ": " .. pair[2] end
    end
    CHECK(odd == nil, "Z: every drawn string is plain ASCII apart from the separator, the dash and the ellipsis", odd)
    local bad
    for _, pair in ipairs(drawn) do
        if pair[2]:find("_", 1, true) or pair[2]:find("C_", 1, true) then bad = pair[1] .. ": " .. pair[2] end
    end
    CHECK(bad == nil, "Z: no drawn string carries an underscore or a client prefix, the whole run over", bad)
    Open("HEROIC_COILFANG")
    local uncoloured = 0
    for _, b in ipairs(Blocks()) do if not b.__color then uncoloured = uncoloured + 1 end end
    for _, row in ipairs(ShownRows()) do
        if not row.title.__color or not row.state.__color then uncoloured = uncoloured + 1 end
    end
    local w = W()
    for _, fs in ipairs({ w.card.name, w.card.totals, w.card.note, w.countFS }) do if not fs.__color then uncoloured = uncoloured + 1 end end
    EQ(uncoloured, 0, "Z: every shown string was coloured this pass")
    EQ(T.expandCalls, 0, "Z: ExpandSkillHeader was never called")
end

Done()
