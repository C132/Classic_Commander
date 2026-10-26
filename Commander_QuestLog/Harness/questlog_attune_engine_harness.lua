-- Commander Quest Log: the Attunements ENGINE (luajit). DECISIONS D48-D57.
--
--     /opt/homebrew/bin/luajit Commander_QuestLog/Harness/questlog_attune_engine_harness.lua
--     CQL_ATTUNE_ENGINE= / CQL_ATTUNE_DATA= / CQL_ATTUNE=/path/copy.lua luajit ...   (a mutated copy)
--
-- The engine (CommanderQuestLogAttune.lua, Q.Attune) decides what every guide
-- and step of the Attunements tab says: the content phase and why, a status,
-- a reason and a progress pair per step, a word and a ratio per guide, the
-- step to continue with, the marks and the account ledger. This file boots
-- the REAL data, engine and tab under the shared client mock
-- (questlog_mock.lua) with the fake Questie (fake_questie.lua), the suite Go
-- button and a recording Commander Orders 3.1, then drives the engine
-- directly: hand-built contexts through A.Detect for the detectors, the live
-- client stubs through A.Steps / A.Guide / A.Guides for everything the engine
-- layers over them. The tab is drawn only where a check needs the window's
-- refresh queue (section L). Its sister, questlog_attunements_harness.lua,
-- drives the tab (sections E F G H J K Q Z); the sections here are the
-- engine's half of the specification's 9.2 plan:
--
--   A  the phase: the calendar epochs, Questie's vote, the setting, the
--      in-game evidence that never lowers, the names and sentences, the
--      minute tick and Restore Defaults
--   B  the detectors, every branch of 4.5: LEVEL, QUEST (flag, implication,
--      grace, log, daily, ANY, CHAIN, ALL, accept, splits, a quest's own
--      level), ITEM (keyring, bags, anyOf, partial, consumed, with a quest),
--      KILL (lockout by name, encounter and end boss, full clears, the combat
--      log, weekly resets, a quest with shards), REP, SPELL, SKILL, TALK,
--      MANUAL, and the precedence over marks, locks and waivers
--   C  side and class: pledges, standings, the chosen side, class-hidden
--      steps, the rogue's Lockpicking route, the druid's flight routes
--   D  scoring and lists: what counts, other-phase steps, the current pointer
--      and the Next word, the five guide words, buckets and order, header
--      counts and totals, the ledger, Continue's six reasons, Find, filters
--   I  marks: dated marks, undo, the guide mark, weekly expiry, Clear Marks,
--      the account ledger written by detection only
--   L  events: one domain per event, the collectors, CLEU arming, the
--      refresh queue, the calendar tick, the suite's UPDATE notification

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local MODULE = ADDONS .. "/Commander_QuestLog/"

local mock = dofile(MODULE .. "Harness/questlog_mock.lua")
local Fake = dofile(MODULE .. "Harness/fake_questie.lua")
local CHECK, Done, counts = mock.Checker()
local function EQ(got, want, label) CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want)) end
local function HAS(s, needle, label) CHECK(type(s) == "string" and s:find(needle, 1, true) ~= nil, label, s) end
local function Section(name) io.write(name, "\n") end

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
-- The client the mock lacks: defined BEFORE Fake.InstallClient (the fake fills
-- only nil slots) and before the module loads. T is the character: flip its
-- fields, invalidate the engine, read again.
-- ===========================================================================
local T = {
    done = {}, items = {}, keyring = {}, spells = {}, skills = {}, encounters = {},
    faction = "Alliance", race = "Human", class = { "Warrior", "WARRIOR" }, level = 70,
    instance = { inside = false, kind = "none", id = nil, difficulty = 0 }, dungeonDifficulty = 1,
    npcGuid = nil, cleu = nil, expandCalls = 0,
}
C_QuestLog = C_QuestLog or {}
C_QuestLog.IsQuestFlaggedCompleted = function(id) return T.done[id] == true end
C_Item = { GetItemCount = function(id) return T.items[id] or 0 end }
function GetItemCount(id) return T.items[id] or 0 end
C_Container = {
    GetContainerNumSlots = function(bag) if bag == -2 then return #T.keyring end return 0 end,
    GetContainerItemID = function(bag, slot) if bag == -2 then return T.keyring[slot] end return nil end,
}
C_SpellBook = { IsSpellKnown = function(id) return T.spells[id] == true end }
function IsSpellKnown(id) return T.spells[id] == true end
IsPlayerSpell = IsSpellKnown
function GetNumSkillLines() return #T.skills end
function GetSkillLineInfo(i)
    local s = T.skills[i]
    if not s then return nil end
    return s.name, s.header or false, s.expanded or false, s.rank or 0, 0, 0, s.max or 375
end
function ExpandSkillHeader() T.expandCalls = T.expandCalls + 1 end
function UnitFactionGroup() return T.faction, T.faction end
function UnitRace() return T.race, T.race:upper(), 1 end
function UnitClass() return T.class[1], T.class[2] end
function UnitLevel() return T.level end
function UnitName() return "Tester" end
function UnitGUID(unit) if unit == "npc" then return T.npcGuid end return nil end
function GetRealmName() return "Testrealm" end
function IsInInstance() return T.instance.inside, T.instance.kind end
function GetInstanceInfo() return "Name", T.instance.kind, T.instance.difficulty or 0, "", 5, 0, false, T.instance.id end
function GetDungeonDifficultyID() return T.dungeonDifficulty end
C_RaidLocks = { IsEncounterComplete = function(map, enc) return T.encounters[tostring(map) .. ":" .. tostring(enc)] == true end }
function CombatLogGetCurrentEventInfo()
    local c = T.cleu
    if not c then return nil end
    return c.timestamp or 0, c.sub, false, c.sourceGUID, c.sourceName, 0, 0, c.destGUID, c.destName, 0, 0
end
RAID_CLASS_COLORS.DRUID = { r = 1, g = 0.49, b = 0.04 }
RAID_CLASS_COLORS.ROGUE = { r = 1, g = 0.96, b = 0.41 }
-- The 2.5.6 saved-instance reads: 14 returns (mapID at 14, difficultyID at 4,
-- encountersTotal 11, encountersCompleted 12) over mock.state.savedInstances
-- rows { name, reset, difficulty, locked, extended, isRaid, maxPlayers,
-- difficultyName, total, completed, mapID, bosses = { { name, killed } } }
function GetSavedInstanceInfo(index)
    local i = mock.state.savedInstances[index]
    if not i then return nil end
    return i.name, 100 + index, i.reset or 0, i.difficulty or 1, i.locked ~= false, i.extended or false,
        0, i.isRaid ~= false, i.maxPlayers or 10, i.difficultyName or "Normal", i.total or 0, i.completed or 0, false, i.mapID
end
function GetSavedInstanceEncounterInfo(index, j)
    local i = mock.state.savedInstances[index]
    local b = i and i.bosses and i.bosses[j]
    if not b then return nil end
    return b.name, 0, b.killed and true or false
end

-- ===========================================================================
-- A recording Commander Orders 3.1 with a door table (the engine's Go asks
-- Orders for every instance row; PlaceFor answers the entrance query)
-- ===========================================================================
local O = { gone = {}, records = {}, order = {}, active = nil, available = true, removed = {} }
COMMANDER_ORDERS_EVENTS = { CHANGED = "COMMANDER_ORDERS_CHANGED", UPDATE = "COMMANDER_ORDERS_UPDATE" }
local DOORS = {
    [545] = { map = 1946, x = 0.5036, y = 0.4081, title = "Coilfang Reservoir entrance" },
    [547] = { map = 1946, x = 0.5036, y = 0.4081, title = "Coilfang Reservoir entrance" },
    [546] = { map = 1946, x = 0.5036, y = 0.4081, title = "Coilfang Reservoir entrance" },
    [548] = { map = 1946, x = 0.5036, y = 0.4081, title = "Coilfang Reservoir entrance" },
    [269] = { map = 1446, x = 0.6570, y = 0.4980, title = "Caverns of Time entrance" },
    [560] = { map = 1446, x = 0.6570, y = 0.4980, title = "Caverns of Time entrance" },
    [534] = { map = 1446, x = 0.6570, y = 0.4980, title = "Caverns of Time entrance" },
    [585] = { map = 1957, x = 0.6152, y = 0.3110, title = "Magisters' Terrace entrance" },
    [532] = { map = 1430, x = 0.4659, y = 0.7411, title = "Karazhan entrance" },
    [565] = { map = 1949, x = 0.6935, y = 0.2354, title = "Gruul's Lair entrance" },
    [544] = { map = 1944, x = 0.4764, y = 0.5201, title = "Magtheridon's Lair entrance" },
    [540] = { map = 1944, x = 0.4740, y = 0.5202, title = "The Shattered Halls entrance" },
    [552] = { map = 1953, x = 0.7457, y = 0.5762, title = "The Arcatraz entrance" },
    [553] = { map = 1953, x = 0.7183, y = 0.5482, title = "The Botanica entrance" },
    [554] = { map = 1953, x = 0.7064, y = 0.6982, title = "The Mechanar entrance" },
    [555] = { map = 1952, x = 0.3963, y = 0.7378, title = "Shadow Labyrinth entrance" },
    [556] = { map = 1952, x = 0.4506, y = 0.6562, title = "Sethekk Halls entrance" },
    [568] = { map = 1942, x = 0.8259, y = 0.6431, title = "Zul'Aman entrance" },
}
local function Changed() if Commander and Commander.Notify then Commander.Notify(COMMANDER_ORDERS_EVENTS.CHANGED) end end
CommanderOrders = {
    IsAvailable = function()
        if O.available then return true end
        return false, "disabled"
    end,
    Reason = function(why)
        if why == "disabled" then return "Commander Orders is turned off (/corder)" end
        return "Reason: " .. tostring(why)
    end,
    GoTo = function(target, opts)
        O.gone[#O.gone + 1] = { target = target, opts = opts }
        if not O.available then return nil, "disabled" end
        local s = {}
        for k, v in pairs(target) do s[k] = v end
        for _, f in ipairs({ "source", "key", "title", "icon", "note" }) do
            if opts and opts[f] ~= nil then s[f] = opts[f] end
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
        if type(target) == "table" and target.map then
            return { map = target.map, x = target.x, y = target.y, title = target.title }
        end
        if type(target) == "table" and type(target.entrance) == "table" then
            local d = DOORS[target.entrance.instance]
            if d then return { map = d.map, x = d.x, y = d.y, title = d.title } end
            return nil, "nowhere"
        end
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
        if O.records[id] then O.records[id] = nil return 1 end
        return 0
    end,
    Add = function() error("Orders 3.1: the Go path never calls Add") end,
    AddRoute = function() return "r1" end,
    RegisterResolver = function() return true end,
    Describe = function() return "Commander Orders arrow" end,
}

-- ===========================================================================
-- Boot: the fake Questie (its phase vote says 3), the framework, the Go
-- button, every window file in TOC order minus the map drawer and the quest
-- dialog, plus the three Attunements files; then login on a Phase 4 day
-- ===========================================================================
local world = Fake.DefaultWorld()
world.contentPhases = { active = 3 }           -- Questie 12.1.0's TBC vote
local fake = Fake.Install(world)
Fake.InstallClient(world)

mock.LoadFramework()
mock.Load(ADDONS .. "/Commander_Events/CommanderGoButton.lua")
local MODULE_FILES = {
    "CommanderQuestLogDB.lua", "CommanderQuestLogModel.lua", "CommanderQuestLogReputationData.lua",
    "CommanderQuestLogCompletion.lua", "CommanderQuestLogStanding.lua", "CommanderQuestLogQuestie.lua",
    "CommanderQuestLogUI.lua", "CommanderQuestLogCatalogue.lua", "CommanderQuestLogZones.lua",
    "CommanderQuestLogReputations.lua",
    "CommanderQuestLogAttuneData.lua", "CommanderQuestLogAttune.lua", "CommanderQuestLogAttunements.lua",
}
local OVERRIDE = {
    ["CommanderQuestLogAttuneData.lua"] = os.getenv("CQL_ATTUNE_DATA"),
    ["CommanderQuestLogAttune.lua"] = os.getenv("CQL_ATTUNE_ENGINE"),
    ["CommanderQuestLogAttunements.lua"] = os.getenv("CQL_ATTUNE"),
}
for _, file in ipairs(MODULE_FILES) do mock.Load(OVERRIDE[file] or (MODULE .. file)) end

local D = CommanderQuestLogAttuneData
local PH = {}
for _, p in ipairs(D.PHASES) do PH[p.n] = p end
local NOW4 = PH[4].since + 2 * 86400           -- 24 Oct 2026: Phase 4 from the calendar
mock.clock.serverTime = NOW4
mock.Login()
local function Settle() for _ = 1, 8 do mock.RunTimers(1) end end
Settle()

local Q = CommanderQuestLog
local A = Q.Attune
local db = CommanderQuestLogDB
CHECK(type(A) == "table" and type(Q.Attunements) == "table" and type(D) == "table", "boot: data, engine and tab present")
CHECK(Q.Questie.State() == "READY", "boot: the fake Questie is ready", Q.Questie.State())

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local DOMAINS = { "quests", "items", "reps", "char", "spells", "skills", "locks", "world", "store", "phase" }
local function Bump() for _, d in ipairs(DOMAINS) do A.Invalidate(d) end end
local function Char() return Q.EnsureCharDB().Attune end
local function Now() return mock.clock.serverTime end
local function DW(t, withYear) return (os.date(withYear and "%d %b %Y" or "%d %b", t):gsub("^0", "")) end

-- The raw step record and its guide
local function Rec(guideKey, stepKey)
    local g = A.byKey[guideKey]
    for _, s in ipairs(g and g.steps or {}) do
        if s.key == stepKey then return s, g end
    end
    return nil, g
end
-- The step's view from A.Steps, and the summary
local function View(guideKey, stepKey, opts)
    local steps, summary = A.Steps(guideKey, opts)
    for _, v in ipairs(steps) do
        if v.key == stepKey then return v, summary end
    end
    return nil, summary
end
-- A.Detect over a hand-built context
local function Ctx(o)
    o = o or {}
    return {
        level = o.level or 70, class = o.class or "WARRIOR", faction = o.faction or "A", race = o.race or "Human",
        completed = o.completed or {}, onQuest = o.onQuest or {}, logState = o.logState or {}, seen = o.seen or {},
        count = o.count or {}, keyring = o.keyring or {}, badges = 0,
        rep = o.rep or {}, known = o.known or {}, skills = o.skills or {},
        locks = o.locks or {}, kills = o.kills or {}, talked = o.talked or {}, entered = o.entered or {},
        marks = {}, touched = {}, account = {}, side = o.side,
        dungeonDifficulty = o.dungeonDifficulty, instanceId = o.instanceId,
    }
end
local function Detect(guideKey, stepKey, c)
    local step, guide = Rec(guideKey, stepKey)
    return A.Detect(step, guide, c)
end
-- Everything back to a fresh level-70 Alliance warrior on the Phase 4 day
local function Clean()
    for _, k in ipairs({ "done", "items", "keyring", "spells", "skills", "encounters" }) do T[k] = {} end
    T.level, T.class, T.faction = 70, { "Warrior", "WARRIOR" }, "Alliance"
    T.instance = { inside = false, kind = "none", id = nil, difficulty = 0 }
    T.dungeonDifficulty, T.npcGuid, T.cleu = 1, nil, nil
    mock.state.savedInstances = {}
    mock.state.log = {}
    world.reps[932], world.reps[934], world.reps[946], world.reps[942] = 3500, -3500, 4000, 9500
    local at = Char()
    for _, k in ipairs({ "marks", "seen", "touched", "kills", "talked", "entered", "phaseEvidence" }) do at[k] = {} end
    at.guide, at.side = nil, nil
    db.AttuneAccount, db.AttunePhaseSeen, db.AttunePhase = {}, {}, "AUTO"
    mock.clock.serverTime = NOW4
    Bump()
end
-- Quests in the client's log: ready = 1, failed = -1
local function Log(...)
    local list = { mock.Header("Outland") }
    for _, q in ipairs({ ... }) do
        list[#list + 1] = mock.Quest({ title = "Quest " .. q.id, level = 70, questID = q.id, isComplete = q.state,
            objectives = q.objectives or {} })
    end
    mock.state.log = list
    A.Invalidate("quests")
end

-- ===========================================================================
-- A. Phase
-- ===========================================================================
do
    Section("A Phase")
    Clean()
    local function At(t) mock.clock.serverTime = t; A.Invalidate("phase"); return A.Phase() end
    -- the calendar alone first: Questie's vote (3) would win below Phase 3
    fake.modules.ContentPhases.activePhases.TBC = nil
    EQ((At(PH[1].since - 1)), 1, "A1 before P1 is 1")
    local n = 2
    for p = 1, 4 do
        EQ((At(PH[p].since - 1)), math.max(p - 1, 1), "A" .. n .. " one second before the P" .. p .. " epoch")
        n = n + 1
        EQ((At(PH[p].since + 1)), p, "A" .. n .. " one second after the P" .. p .. " epoch")
        n = n + 1
    end
    fake.modules.ContentPhases.activePhases.TBC = 3
    local ph, source, since, why, votes = At(NOW4)
    CHECK(ph == 4 and source == "calendar" and votes.questie == 3, "A10 Questie 3 under calendar 4 gives 4 calendar",
        tostring(ph) .. " " .. tostring(source) .. " questie " .. tostring(votes.questie))
    EQ(why, "Phase 4 since " .. DW(PH[4].since, true) .. ", from the calendar.", "A10 ...the calendar's sentence")
    EQ(since, PH[4].since, "A10 ...since is the epoch")
    fake.modules.ContentPhases.activePhases.TBC = 5
    A.Invalidate("phase")
    ph, source, since, why = A.Phase()
    CHECK(ph == 5 and source == "questie" and why == "Phase 5: Questie says so." and since == false,
        "A11 Questie 5 gives 5 questie, no date", tostring(ph) .. " " .. tostring(source) .. " " .. tostring(why))
    fake.modules.ContentPhases.activePhases.TBC = 3
    A.SetPhase(2)
    ph, source, since, why, votes = A.Phase()
    CHECK(ph == 2 and source == "setting" and votes.setting == 2, "A12 setting 2 gives 2 setting", tostring(ph) .. " " .. tostring(source))
    EQ(why, "Phase 2, set by you; the calendar says Phase 4.", "A12 ...why names the calendar's 4")
    A.SetPhase("AUTO")
    ph, source, since, why, votes = A.Phase()
    CHECK(ph == 4 and votes.setting == "AUTO" and votes.calendar == 4 and votes.evidence == nil,
        "A12 ...AUTO again: votes calendar 4, questie 3, evidence none, setting automatic")
    -- evidence: a Zul'Aman lockout under a Phase 3 calendar
    mock.clock.serverTime = PH[3].since + 86400
    A.Invalidate("phase")
    EQ((A.Phase()), 3, "A13 (calendar 3 before the lockout)")
    mock.state.savedInstances = { { name = "Zul'Aman", mapID = 568, reset = 200000, isRaid = true, total = 6, completed = 2 } }
    mock.Fire("UPDATE_INSTANCE_INFO")
    ph, source, since, why = A.Phase()
    CHECK(ph == 4 and source == "evidence" and why == "Phase 4: you hold a Zul'Aman lockout.",
        "A13 568 lockout gives 4 evidence", tostring(ph) .. " " .. tostring(source) .. " " .. tostring(why))
    mock.state.savedInstances = {}
    mock.Fire("UPDATE_INSTANCE_INFO")
    A.Invalidate("phase")
    CHECK((A.Phase()) == 4 and type(db.AttunePhaseSeen[4]) == "table" and db.AttunePhaseSeen[4].kind == "lockout",
        "A13 ...and persists in AttunePhaseSeen after the row is removed", tostring(db.AttunePhaseSeen[4] and db.AttunePhaseSeen[4].kind))
    T.done[11481] = true
    mock.Fire("QUEST_TURNED_IN", 11481)
    ph, source, since, why = A.Phase()
    CHECK(ph == 5 and source == "evidence" and why == "Phase 5: quest 11481 is flagged complete.",
        "A14 11481 flagged gives 5", tostring(ph) .. " " .. tostring(why))
    mock.state.savedInstances = { { name = "Zul'Aman", mapID = 568, reset = 200000, isRaid = true } }
    mock.Fire("UPDATE_INSTANCE_INFO")
    EQ((A.Phase()), 5, "A15 evidence never lowers (row 4 after 5 stays 5)")
    local ev = A.Evidence()
    CHECK(#ev == 2 and ev[1].n == 4 and ev[1].kind == "lockout" and ev[2].n == 5 and ev[2].kind == "quest",
        "A15 ...Evidence() lists the strongest row per phase, sorted by n", #ev)
    mock.state.savedInstances = {}
    T.done[11481] = nil
    db.AttunePhaseSeen = {}
    Char().phaseEvidence = {}
    A.Invalidate("quests"); A.Invalidate("phase")
    EQ((A.Phase()), 3, "A16 (evidence cleared: back to the calendar's 3)")
    mock.Fire("QUEST_ACCEPTED", 7, 11163)
    ph, source = A.Phase()
    CHECK(ph == 4 and source == "evidence" and db.AttunePhaseSeen[4] and db.AttunePhaseSeen[4].detail == "quest 11163 in your log",
        "A16 QUEST_ACCEPTED's second argument is read", tostring(db.AttunePhaseSeen[4] and db.AttunePhaseSeen[4].detail))
    db.AttunePhaseSeen = {}
    Char().phaseEvidence = {}
    mock.clock.serverTime = NOW4
    A.Invalidate("phase")
    local short, name, blizzard = A.PhaseName(4)
    CHECK(short == "Phase 4" and name == "The Gods of Zul'Aman" and blizzard == "Phase 3.5", "A17 PhaseName both numberings",
        tostring(short) .. " / " .. tostring(name) .. " / " .. tostring(blizzard))
    EQ(select(3, A.PhaseName(5)), "Phase 4", "A17 ...Blizzard's Phase 4 is our 5")
    HAS(A.PhaseSentences(4)[1], "Honored", "A18 PhaseSentences say Honored at 4")
    HAS(A.PhaseSentences(3)[1], "Revered", "A18 ...and Revered at 3")
    local s5 = A.PhaseSentences(5)
    local last = s5[#s5]
    CHECK(type(last) == "string" and last:find("^Some of this phase's rules rest on inference: ") ~= nil
        and last:find("the standing the heroic keys cost", 1, true) ~= nil,
        "A19 assumed keys surface in sentences at 5", last)
    EQ(#A.PhaseSentences(4), #D.RULES[4].sentences, "A19 ...and nothing is appended at 4 (nothing assumed)")
    CHECK(A.Rules(4).heroicKeyStanding == 6 and A.Rules() == A.Rules(4), "A19 ...Rules(n) is the data's row; Rules() the resolved phase's")
    -- the calendar tick: the boundary crossed between two reads, no reload
    mock.clock.serverTime = PH[4].since - 1
    A.Invalidate("phase")
    EQ((A.Phase()), 3, "A20 (one second before the P4 epoch: 3)")
    mock.clock.serverTime = PH[4].since + 1
    EQ((A.Phase()), 3, "A20 ...the memo still says 3 before the tick")
    mock.RunTimers(60)
    EQ((A.Phase()), 4, "A20 the calendar tick flips at a boundary without reload")
    local next = false
    for _, t in ipairs(mock.timers) do
        if not t.done and t.at == mock.state.now + 60 then next = true end
    end
    CHECK(next, "A20 ...and the timers table holds the next tick")
    mock.clock.serverTime = NOW4
    A.Invalidate("phase")
    -- Restore Defaults rewrites AttunePhase without A.SetPhase
    A.SetPhase(2)
    EQ((A.Phase()), 2, "A21 (set to 2)")
    SlashCmdList["COMMANDERUI_QUESTLOG"]("reset")
    Q.Refresh()
    CHECK(db.AttunePhase == "AUTO" and (A.Phase()) == 4, "A21 after Reset() the next read gives the calendar's phase",
        tostring(db.AttunePhase) .. " " .. tostring((A.Phase())))
    A.SetPhase(9)
    EQ(db.AttunePhase, "AUTO", "A22 SetPhase out of range is AUTO")
end

-- ===========================================================================
-- B. Detectors (hand-built contexts through A.Detect; the live client where
-- the engine's layering is the thing)
-- ===========================================================================
do
    Section("B Detectors")
    Clean()
    local st, why, prog
    -- LEVEL
    st, why, prog = Detect("KARAZHAN_ATTUNEMENT", "level_68", Ctx({ level = 64 }))
    CHECK(st == "LOCKED" and why == "Level 64 of 68", "B1 LEVEL under: Locked, Level 64 of 68", why)
    CHECK(prog and prog.have == 64 and prog.need == 68, "B2 ...with progress 64 of 68")
    st, why = Detect("KARAZHAN_ATTUNEMENT", "level_68", Ctx({ level = 68 }))
    CHECK(st == "DONE" and why == "You are level 68", "B3 LEVEL at: Done, You are level 68", why)
    st, why = Detect("FLYING", "level_70", Ctx({ level = 68, class = "DRUID" }))
    CHECK(st == "DONE" and why == "You are level 68", "B4 LEVEL druid 68 on the 70-or-68 step: Done", why)
    st, why = Detect("FLYING", "level_70", Ctx({ level = 68, class = "WARRIOR" }))
    CHECK(st == "LOCKED" and why == "Level 68 of 70", "B5 ...a warrior at 68 is Locked", why)
    -- QUEST
    st, why = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ completed = { [9824] = true } }))
    CHECK(st == "DONE" and why == "Flagged complete", "B6 QUEST flagged: Done, Flagged complete", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ completed = { [9826] = true } }))
    CHECK(st == "DONE" and why == "Implied: a later quest is complete", "B7 QUEST implied by a later flag", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ seen = { [9824] = Now() - 3 } }))
    CHECK(st == "DONE" and why == "Just handed in", "B8 QUEST seen 3 s ago: Done, Just handed in", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ seen = { [9824] = Now() - 20 } }))
    CHECK(st == "OPEN" and why == "Not started", "B9 QUEST seen 20 s ago: To do again", why)
    st, why, prog = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ onQuest = { [9824] = true },
        logState = { [9824] = { objectives = { { text = "Readings taken: 1/2", finished = false, have = 1, need = 2 } } } } }))
    CHECK(st == "LOG" and why == "In your log" and prog and prog.have == 1 and prog.need == 2, "B10 QUEST on quest: In log with have/need", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ onQuest = { [9824] = true }, logState = { [9824] = { ready = true } } }))
    CHECK(st == "READY" and why == "Complete in your log: hand it in", "B11 QUEST ready", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "arcane_disturbances", Ctx({ onQuest = { [9824] = true }, logState = { [9824] = { failed = true } } }))
    CHECK(st == "FAILED" and why == "Failed in your log", "B12 QUEST failed", why)
    st, why = Detect("HEROIC_HELLFIRE", "fortifications_daily", Ctx({ completed = { [10106] = true } }))
    CHECK(st == "DONE" and why == "Handed in today", "B13 daily flagged: Done, Handed in today", why)
    st, why = Detect("HEROIC_HELLFIRE", "fortifications_daily", Ctx({}))
    CHECK(st == "OPEN" and why == "Available today", "B14 daily open: To do, Available today", why)
    local v = View("OGRILA_UNLOCK", "relic_emanation_daily")
    CHECK(v and v.daily and v.counted == false and v.kindWord == "Daily", "B15 a daily never counts outside BADGES (Ogri'la)", v and tostring(v.counted))
    v = View("BADGES", "heroic_daily")
    CHECK(v and v.daily and v.counted == true, "B15 ...in BADGES the daily is an EARN line that counts", v and tostring(v.counted))
    st, why = Detect("ARCATRAZ_KEY", "assisting_consortium", Ctx({ completed = { [10264] = true } }))
    CHECK(st == "DONE" and why == "Flagged complete", "B16 ANY pool: either twin flagged is Done (side undecided)", why)
    st, why, prog = Detect("TK_ATTUNEMENT", "enraged_spirits", Ctx({ completed = { [10458] = true } }))
    CHECK(st == "PARTIAL" and why == "1 of 3 quests done" and prog and prog.have == 1 and prog.need == 3,
        "B17 CHAIN 10458 flagged only: PARTIAL 1 of 3", why)
    A.SetPhase(2)
    T.done[10458] = true
    Bump()
    v = View("TK_ATTUNEMENT", "enraged_spirits")
    CHECK(v and v.status == "PARTIAL" and v.word == "1/3", "B18 ...the word is the ratio 1/3", v and v.word)
    T.done[10458] = nil
    A.SetPhase("AUTO")
    st, why = Detect("TK_ATTUNEMENT", "enraged_spirits", Ctx({ completed = { [10481] = true } }))
    CHECK(st == "DONE" and why == "Flagged complete", "B19 CHAIN 10481 (the last) flagged: Done", why)
    st, why, prog = Detect("TK_ATTUNEMENT", "enraged_spirits", Ctx({ completed = { [10458] = true }, onQuest = { [10480] = true } }))
    CHECK(st == "LOG" and why == "In your log; 1 of 3 quests done" and prog and prog.have == 1 and prog.need == 3,
        "B20 CHAIN 10480 in log: In log with 1 of 3", why)
    st, why, prog = Detect("BADGES", "za_quests", Ctx({ completed = { [11171] = true } }))
    CHECK(st == "PARTIAL" and why == "1 of 2 quests done" and prog and prog.have == 1 and prog.need == 2, "B21 ALL 11171 only: PARTIAL 1 of 2", why)
    st, why = Detect("BADGES", "za_quests", Ctx({ completed = { [11171] = true, [11163] = true } }))
    CHECK(st == "DONE", "B22 ALL both flagged: Done", why)
    st, why = Detect("SSC_ATTUNEMENT", "accept_cudgel", Ctx({ onQuest = { [10901] = true } }))
    CHECK(st == "DONE" and why == "Accepted", "B23 accept step with 10901 in log: Done, Accepted", why)
    st, why = Detect("SSC_ATTUNEMENT", "turn_in_cudgel", Ctx({ onQuest = { [10901] = true } }))
    CHECK(st == "LOG" and why == "In your log", "B24 ...the turn-in step reads In log", why)
    A.SetPhase(2)
    T.items[30623], T.items[31750], T.items[31751] = 1, 1, 1
    Log({ id = 10901 })
    Bump()
    local sum
    v, sum = View("SSC_ATTUNEMENT", "turn_in_cudgel")
    CHECK(v and v.status == "LOG" and v.isCurrent and sum.current == "turn_in_cudgel", "B25 ...and is the current step (live, phase 2)",
        tostring(sum and sum.current) .. " " .. tostring(v and v.status))
    v = View("SSC_ATTUNEMENT", "accept_cudgel")
    CHECK(v and v.status == "DONE" and v.reason == "Accepted", "B25 ...while the accept step reads Done Accepted", v and v.reason)
    Clean()
    st = Detect("HEROIC_HELLFIRE", "fortifications_daily", Ctx({ faction = "A", completed = { [10106] = true } }))
    EQ(st, "DONE", "B26 A/H split: Alliance id flagged is Done for the Alliance")
    st = Detect("HEROIC_HELLFIRE", "fortifications_daily", Ctx({ faction = "H", completed = { [10106] = true } }))
    EQ(st, "OPEN", "B27 ...and not for the Horde")
    st = Detect("HEROIC_HELLFIRE", "fortifications_daily", Ctx({ faction = "H", completed = { [10110] = true } }))
    EQ(st, "DONE", "B28 ...whose own id counts")
    st = Detect("BLACK_TEMPLE_ATTUNEMENT", "tablets_of_baari", Ctx({ completed = { [10551] = true, [10568] = true } }))
    EQ(st, "DONE", "B29 side split, Aldor pledged: the Aldor quest counts")
    st = Detect("BLACK_TEMPLE_ATTUNEMENT", "tablets_of_baari", Ctx({ completed = { [10551] = true, [10683] = true } }))
    EQ(st, "OPEN", "B30 ...and the Scryers' twin does not")
    st = Detect("BLACK_TEMPLE_ATTUNEMENT", "tablets_of_baari", Ctx({ completed = { [10683] = true } }))
    EQ(st, "DONE", "B31 side undecided: both twins are candidates")
    T.level = 41
    Bump()
    v = View("ALDOR_SCRYER_CHOICE", "adal")
    CHECK(v and v.status == "LOCKED" and v.reason == "Level 41 of 60" and v.isCurrent, "B32 a level on a QUEST step locks at 41 (and stays current)",
        v and (tostring(v.status) .. " " .. tostring(v.reason)))
    T.level = 60
    Bump()
    v = View("ALDOR_SCRYER_CHOICE", "adal")
    CHECK(v and v.status == "NEXT" and v.word == "Next", "B33 ...and not at 60: Next", v and v.status)
    Clean()
    -- ITEM
    st, why = Detect("HEROIC_HELLFIRE", "buy_key", Ctx({ count = { [30622] = 1 }, keyring = { [30622] = true } }))
    CHECK(st == "DONE" and why == "In your keyring", "B34 ITEM in the keyring: Done, In your keyring", why)
    st, why = Detect("HEROIC_HELLFIRE", "buy_key", Ctx({ count = { [30622] = 1 } }))
    CHECK(st == "DONE" and why == "In your bags or bank", "B35 ITEM in the bags only: Done, In your bags or bank", why)
    T.keyring = { 30622 }
    Bump()
    v = View("HEROIC_HELLFIRE", "buy_key")
    CHECK(v and v.status == "DONE" and v.reason == "In your keyring", "B36 live: the keyring scan alone finds the key (count 0)", v and v.reason)
    T.keyring = {}
    Bump()
    st, why = Detect("HEROIC_HELLFIRE", "buy_key", Ctx({ count = { [265830] = 1 } }))
    CHECK(st == "DONE" and why == "In your bags or bank", "B37 ITEM anyOf: the Communal key satisfies the key step", why)
    local synthetic = { key = "essence", kind = "ITEM", title = "Ten essences", item = { id = 24480, name = "Ghostly Essence", count = 10 } }
    st, why, prog = A.Detect(synthetic, A.byKey.KARAZHAN_ATTUNEMENT, Ctx({ count = { [24480] = 6 } }))
    CHECK(st == "PARTIAL" and why == "6 of 10 Ghostly Essence" and prog and prog.have == 6 and prog.need == 10, "B38 ITEM partial: 6 of 10", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "second_fragment_steamvault", Ctx({ completed = { [9832] = true } }))
    CHECK(st == "DONE" and why == "Handed in with Return both fragments to Khadgar", "B39 ITEM consumed by a later quest", why)
    st, why = Detect("KARAZHAN_ATTUNEMENT", "second_fragment_steamvault", Ctx({}))
    CHECK(st == "OPEN" and why == "Not in your bags", "B40 ITEM absent: To do, Not in your bags", why)
    -- ITEM with questId (the Tempest Keep trials)
    st, why = Detect("TK_ATTUNEMENT", "trial_mercy", Ctx({ completed = { [10884] = true } }))
    CHECK(st == "DONE" and why == "Flagged complete", "B41 trial flagged with the axe gone: Done", why)
    st, why = Detect("TK_ATTUNEMENT", "trial_mercy", Ctx({ onQuest = { [10884] = true },
        logState = { [10884] = { objectives = { { text = "Unused Axe of the Executioner: 1/1", finished = true } } } } }))
    CHECK(st == "DONE" and why == "Objective complete", "B42 trial in the log with its objective finished: Done", why)
    st, why = Detect("TK_ATTUNEMENT", "trial_mercy", Ctx({ count = { [31716] = 1 } }))
    CHECK(st == "DONE" and why == "In your bags", "B43 the axe in the bags: Done", why)
    st, why = Detect("TK_ATTUNEMENT", "trial_mercy", Ctx({}))
    CHECK(st == "OPEN" and why == "Not in your bags", "B44 neither: To do", why)
    st, why = Detect("TK_ATTUNEMENT", "trial_mercy", Ctx({ onQuest = { [10884] = true },
        logState = { [10884] = { objectives = { { text = "Unused Axe of the Executioner: 0/1", finished = false } } } } }))
    CHECK(st == "OPEN" and why == "Not in your bags; the quest is in your log", "B45 in the log, objective open: the reason says so", why)
    -- KILL with questId and needs (the Arcatraz shards)
    st, why = Detect("ARCATRAZ_KEY", "kill_warp_splinter", Ctx({ count = { [31085] = 1 } }))
    CHECK(st == "DONE" and why == "In your bags", "B46 the Top Shard in the bags: Done, In your bags", why)
    st, why = Detect("ARCATRAZ_KEY", "kill_warp_splinter", Ctx({ completed = { [10704] = true } }))
    CHECK(st == "DONE" and why == "Flagged complete", "B47 10704 flagged: Done", why)
    local shards = { [10704] = { objectives = { { text = "Top Shard of the Arcatraz Key: 1/1", finished = true },
        { text = "Bottom Shard of the Arcatraz Key: 0/1", finished = false } } } }
    st, why = Detect("ARCATRAZ_KEY", "kill_warp_splinter", Ctx({ onQuest = { [10704] = true }, logState = shards }))
    CHECK(st == "DONE" and why == "Objective complete", "B48 10704 in the log with the Top Shard objective finished: Done", why)
    st, why = Detect("ARCATRAZ_KEY", "kill_pathaleon", Ctx({ onQuest = { [10704] = true }, logState = shards }))
    CHECK(st == "UNKNOWN" and why == "No lockout shows it: mark it done if you have; the quest is in your log",
        "B49 ...the Bottom Shard step, unfinished and with no lock on 554, is Unchecked with the log appended", why)
    -- REP
    st, why = Detect("HEROIC_HELLFIRE", "rep_honored", Ctx({}))
    CHECK(st == "OPEN" and why == "Not met yet: no Honor Hold standing on this character", "B50 REP never met: To do with the authored name", why)
    local honored = { [946] = { name = "Honor Hold", standingID = 6, barMin = 9000, barMax = 21000, barValue = 13250 } }
    st, why, prog = Detect("HEROIC_HELLFIRE", "rep_revered", Ctx({ rep = honored }))
    EQ(st, "STANDING", "B51 REP below: STANDING")
    EQ(why, "Honored 4,250 of 12,000; Revered needed", "B52 ...reason is the rep line and the standing needed")
    CHECK(prog and prog.have == 4250 and prog.need == 12000, "B53 ...progress is the bar", prog and (prog.have .. "/" .. prog.need))
    st, why = Detect("HEROIC_HELLFIRE", "rep_honored", Ctx({ rep = honored }))
    CHECK(st == "DONE" and why == "Honored 4,250 of 12,000", "B54 REP at the standing: Done with the rep line", why)
    honored[946].standingID = 7
    st = Detect("HEROIC_HELLFIRE", "rep_honored", Ctx({ rep = honored }))
    EQ(st, "DONE", "B55 REP above: Done")
    world.reps[946] = -1000
    A.Invalidate("reps")
    v = View("HEROIC_HELLFIRE", "rep_honored")
    CHECK(v and v.status == "STANDING" and v.word == "Unfriendly", "B56 live: the word is the standing word (Unfriendly)", v and v.word)
    world.reps[946] = 4000
    A.Invalidate("reps")
    CHECK(not why:find("/", 1, true), "B57 the rep line reads of, never a slash", why)
    -- KILL
    local gruulLock = { difficultyID = 1, encountersTotal = 2, encountersCompleted = 2,
        bosses = { ["High King Maulgar"] = true, ["Gruul the Dragonkiller"] = true }, bossList = { "High King Maulgar", "Gruul the Dragonkiller" } }
    st, why = Detect("GRUUL_MAGTHERIDON", "kill_gruul", Ctx({ locks = { [565] = gruulLock } }))
    CHECK(st == "DONE" and why == "Killed this lockout", "B58 KILL by the English boss name", why)
    T.encounters["565:650"] = true
    st, why = Detect("GRUUL_MAGTHERIDON", "kill_gruul", Ctx({ locks = { [565] = { difficultyID = 1, bosses = {}, bossList = {} } } }))
    CHECK(st == "DONE" and why == "Killed this lockout", "B59 KILL by the encounter id when the names do not match", why)
    T.encounters = {}
    st, why = Detect("GRUUL_MAGTHERIDON", "kill_gruul", Ctx({ locks = { [565] = { difficultyID = 1,
        bosses = { ["Gruul der Drachenschlaechter"] = true }, bossList = { "Hochkoenig Maulgar", "Gruul der Drachenschlaechter" } } } }))
    CHECK(st == "DONE" and why == "Killed this lockout", "B60 KILL by the end-boss index with localised names", why)
    st, why = Detect("BADGES", "heroic_mechanar", Ctx({ locks = { [554] = { difficultyID = 1, bosses = { ["Pathaleon the Calculator"] = true },
        bossList = { "Pathaleon the Calculator" } } } }))
    CHECK(st == "OPEN" and why == "Not this lockout", "B61 a heroic KILL ignores a normal lockout", why)
    st, why, prog = Detect("BADGES", "karazhan", Ctx({ locks = { [532] = { difficultyID = 1, encountersTotal = 11, encountersCompleted = 9 } } }))
    CHECK(st == "PARTIAL" and why == "9 of 11 bosses this lockout" and prog and prog.have == 9 and prog.need == 11,
        "B62 full clear 9 of 11: PARTIAL", why)
    mock.state.savedInstances = { { name = "Karazhan", mapID = 532, reset = 400000, isRaid = true, total = 11, completed = 9 } }
    mock.Fire("UPDATE_INSTANCE_INFO")
    v = View("BADGES", "karazhan")
    CHECK(v and v.status == "PARTIAL" and v.word == "9/11", "B63 ...the word 9/11", v and v.word)
    CHECK(v and v.status ~= "DONE", "B64 ...never Done at nine")
    mock.state.savedInstances[1].completed = 11
    mock.Fire("UPDATE_INSTANCE_INFO")
    v = View("BADGES", "karazhan")
    CHECK(v and v.status == "DONE" and v.reason == "11 of 11 bosses this lockout", "B65 11 of 11: Done", v and v.reason)
    mock.state.savedInstances = {}
    mock.Fire("UPDATE_INSTANCE_INFO")
    -- the combat log, inside Gruul's Lair
    T.instance = { inside = true, kind = "raid", id = 565, difficulty = 1 }
    mock.Fire("ZONE_CHANGED_NEW_AREA")
    T.cleu = { sub = "UNIT_DIED", destGUID = "Creature-0-4379-565-1234-19044-00001A2B3C", destName = "Gruul the Dragonkiller" }
    mock.Fire("COMBAT_LOG_EVENT_UNFILTERED")
    v = View("GRUUL_MAGTHERIDON", "kill_gruul")
    CHECK(v and v.status == "DONE" and v.reason == "Seen fall on " .. DW(Now()), "B66 KILL seen in the combat log: Done, Seen fall on", v and v.reason)
    T.instance = { inside = false, kind = "none", id = nil, difficulty = 0 }
    mock.Fire("ZONE_CHANGED_NEW_AREA")
    Char().entered = {}
    Char().kills = {}
    Bump()
    st, why = Detect("BADGES", "gruul_mag", Ctx({ kills = { [19044] = { when = Now() - 10 } } }))
    CHECK(st == "DONE" and why == "Seen fall on " .. DW(Now() - 10), "B67 a weekly KILL counts a kill after the last reset", why)
    st, why = Detect("BADGES", "gruul_mag", Ctx({ kills = { [19044] = { when = Now() - 30000 } } }))
    CHECK(st == "OPEN" and why == "Not this lockout", "B68 ...and not one before it", why)
    st, why = Detect("BADGES", "gruul_mag", Ctx({}))
    CHECK(st == "OPEN" and why == "Not this lockout", "B69 a weekly step with no lock: To do, Not this lockout", why)
    st, why = Detect("SHADOW_LABYRINTH_KEY", "kill_ikiss", Ctx({}))
    CHECK(st == "UNKNOWN" and why == "No lockout shows it: mark it done if you have", "B70 a one-off kill with no lock: Unchecked", why)
    -- SPELL, SKILL
    st, why = Detect("FLYING", "flight_form", Ctx({ known = { [33943] = true } }))
    CHECK(st == "DONE" and why == "Known", "B71 SPELL known", why)
    st, why = Detect("FLYING", "flight_form", Ctx({}))
    CHECK(st == "OPEN" and why == "Not known", "B72 SPELL not known", why)
    st, why = Detect("FLYING", "expert_riding", Ctx({ skills = { Riding = 225 } }))
    CHECK(st == "DONE" and why == "Riding 225", "B73 SKILL present at rank: Done, Riding 225", why)
    st, why, prog = Detect("FLYING", "expert_riding", Ctx({ skills = { Riding = 150 } }))
    CHECK(st == "PARTIAL" and why == "Riding 150; 225 needed" and prog and prog.have == 150 and prog.need == 225, "B74 SKILL lower: PARTIAL with progress", why)
    T.skills = { { name = "Secondary Skills", header = true, expanded = false }, { name = "Riding", rank = 150 } }
    Bump()
    v = View("FLYING", "expert_riding")
    CHECK(v and v.status == "PARTIAL" and v.word == "150/225", "B75 ...the word 150/225 (live, a header skipped)", v and v.word)
    st, why = Detect("FLYING", "expert_riding", Ctx({ known = { [34090] = true } }))
    CHECK(st == "DONE" and why == "Known", "B76 SKILL absent but the spell is known: Done", why)
    st, why = Detect("FLYING", "expert_riding", Ctx({}))
    CHECK(st == "UNKNOWN" and why:find("^The skill line was not found") ~= nil, "B77 SKILL absent without the spell: Unchecked", why)
    EQ(T.expandCalls, 0, "B78 the engine never expands a skill header")
    T.skills = {}
    -- TALK, MANUAL
    st, why = Detect("BADGES", "talk_geras", Ctx({ talked = { [18525] = Now() } }))
    CHECK(st == "DONE" and why == "Visited", "B79 TALK: Done with the reason Visited", why)
    st, why = Detect("BADGES", "talk_geras", Ctx({}))
    CHECK(st == "OPEN" and why == "Not visited yet", "B80 TALK not yet", why)
    st, why = Detect("GRUUL_MAGTHERIDON", "gruul_door", Ctx({ entered = { [565] = { when = Now(), difficulty = 1 } } }))
    CHECK(st == "DONE" and why == "You have been inside", "B81 MANUAL door entered (auto from its own instance)", why)
    st, why = Detect("SHADOW_LABYRINTH_KEY", "open_gate", Ctx({ locks = { [555] = { difficultyID = 1 } } }))
    CHECK(st == "DONE" and why == "You have been inside", "B82 MANUAL gate via a lock (auto from the guide's instance)", why)
    st, why = Detect("HEROIC_HELLFIRE", "set_heroic", Ctx({ dungeonDifficulty = 2 }))
    CHECK(st == "SET" and why == "Heroic is selected", "B83 MANUAL difficulty: Set", why)
    st, why = Detect("HEROIC_HELLFIRE", "set_heroic", Ctx({ dungeonDifficulty = 1 }))
    CHECK(st == "UNSET" and why == "Normal is selected", "B84 ...Not set", why)
    st = Detect("BADGES", "heroics_overview", Ctx({}))
    EQ(st, "NOTE", "B85 MANUAL note: NOTE")
    st, why = A.Detect({ key = "bare", kind = "MANUAL", title = "Bare" }, A.byKey.BADGES, Ctx({}))
    CHECK(st == "UNKNOWN" and why == "Nothing the client can check: mark it done", "B86 a bare MANUAL step: Unchecked", why)
    local bare = {}
    for _, g in ipairs(D.guides) do
        for _, s in ipairs(g.steps) do
            if s.kind == "MANUAL" and not s.note and type(s.auto) ~= "table" then bare[#bare + 1] = g.key .. ":" .. s.key end
        end
    end
    EQ(#bare, 0, "B87 no data MANUAL step is bare (ALLOW_UNKNOWN is empty)", table.concat(bare, ","))
    -- precedence: a detected Done beats the lock, the waiver and the mark
    Clean()
    T.level = 62
    T.items[31085] = 1
    Bump()
    v = View("ARCATRAZ_KEY", "kill_warp_splinter")
    CHECK(v and v.status == "DONE" and v.reason == "In your bags", "B88 a detected Done beats the step's own level lock", v and (v.status .. " " .. v.reason))
    Clean()
    T.level = 62
    T.items[265830] = 1
    Bump()
    v, sum = View("HEROIC_HELLFIRE", "buy_key")
    CHECK(v and v.status == "DONE" and v.reason == "In your bags or bank", "B89 a detected Done is never relabelled Not needed by the unlock proof", v and v.reason)
    A.Mark("HEROIC_HELLFIRE", "buy_key", true)
    v = View("HEROIC_HELLFIRE", "buy_key")
    CHECK(v and v.status == "DONE" and v.reason == "In your bags or bank", "B90 a mark never changes a detected Done's reason", v and v.reason)
    A.Mark("HEROIC_HELLFIRE", "buy_key", false)
    v, sum = View("HEROIC_HELLFIRE", "rep_honored")
    CHECK(v and v.status == "WAIVED" and v.word == "Not needed" and v.reason == "Not needed: you already hold a Communal Flamewrought Key" and v.counted,
        "B91 unlock proof waives the REP step, which still counts", v and (tostring(v.status) .. " " .. tostring(v.reason)))
    v = View("HEROIC_HELLFIRE", "level_70")
    CHECK(v and v.status == "LOCKED" and v.reason == "Level 62 of 70" and v.isCurrent, "B92 ...but not the LEVEL step, which stays Locked and current", v and v.status)
    local item = A.Guide("HEROIC_HELLFIRE")
    CHECK(item.status == "PROGRESS" and item.word == "2/3" and item.currentLocked == true and sum.unlockHeld == true,
        "B93 the level-62 alt with a Communal key reads 2/3, PROGRESS, currentLocked", item.word .. " " .. item.status)
    EQ(sum.notice, "You hold the Flamewrought Key; heroic Hellfire Citadel opens at level 70.", "B94 ...the notice names the citadel and the level")
    T.level = 70
    Bump()
    item = A.Guide("HEROIC_HELLFIRE")
    local _, sum70 = A.Steps("HEROIC_HELLFIRE")
    CHECK(item.status == "DONE" and item.word == "Done" and item.done == 3 and item.total == 3, "B95 at 70 the same alt reads Done 3/3", item.word .. " " .. item.done .. "/" .. item.total)
    EQ(sum70.notice, "You hold the Flamewrought Key: heroic Hellfire Citadel is open to you.", "B96 ...the notice says the citadel is open")
    Clean()
    A.MarkGuide("NIGHTBANE_SUMMON", true)
    v = View("NIGHTBANE_SUMMON", "kamsis")
    item = A.Guide("NIGHTBANE_SUMMON")
    CHECK(v and v.status == "DONE" and v.reason == "Marked for the whole guide" and item.status == "DONE", "B97 a guide mark: every counted step Done, the guide Done", v and v.reason)
    A.MarkGuide("NIGHTBANE_SUMMON", false)
    Clean()
    T.level = 62
    Bump()
    v, sum = View("HEROIC_HELLFIRE", "level_70")
    item = A.Guide("HEROIC_HELLFIRE")
    CHECK(v and v.status == "LOCKED" and v.word == "Locked" and v.isCurrent and sum.current == "level_70" and item.currentLocked,
        "B98 a level-locked first step stays Locked and is current", v and (v.status .. " " .. tostring(sum.current)))
    Clean()
end

-- ===========================================================================
-- C. Side and class
-- ===========================================================================
do
    Section("C Side and class")
    Clean()
    local function Reps(aldor, scryer) world.reps[932], world.reps[934] = aldor, scryer; A.Invalidate("reps") end
    local side, why
    Reps(3000, 0)
    T.done[10551] = true
    A.Invalidate("quests")
    side, why = A.Side()
    CHECK(side == "ALDOR" and why == "pledged", "C1 the Aldor pledge flag", tostring(side) .. " " .. tostring(why))
    T.done[10551] = nil
    T.done[10552] = true
    A.Invalidate("quests")
    side, why = A.Side()
    CHECK(side == "SCRYER" and why == "pledged", "C2 the Scryers pledge flag", tostring(side) .. " " .. tostring(why))
    T.done[10552] = nil
    A.Invalidate("quests")
    Reps(3000, -1000)
    side, why = A.Side()
    CHECK(side == "ALDOR" and why == "standings", "C3 bars: Aldor Friendly and Scryers Unfriendly is Aldor by standings", tostring(side) .. " " .. tostring(why))
    Reps(3000, 0)
    side = A.Side()
    EQ(side, nil, "C4 a Draenei at Aldor Friendly and Scryers Neutral is undecided")
    T.done[10551] = true
    A.Invalidate("quests")
    Reps(-42000, 9000)
    side, why = A.Side()
    CHECK(side == "SCRYER" and why == "standings", "C5 a swapped character (Aldor flag, Scryers Honored, Aldor Hated) is Scryer by standings",
        tostring(side) .. " " .. tostring(why))
    T.done[10551] = nil
    A.Invalidate("quests")
    Reps(3000, 0)
    Char().side = "SCRYERS"
    A.Invalidate("store")
    side, why = A.Side()
    CHECK(side == "SCRYER" and why == "chosen by you", "C6 the side chosen by click (SCRYERS accepted as SCRYER)", tostring(side) .. " " .. tostring(why))
    Clean()
    -- class
    T.class = { "Rogue", "ROGUE" }
    Bump()
    CHECK(View("SHADOW_LABYRINTH_KEY", "lockpick_alt") ~= nil, "C7 a rogue sees the Lockpicking step")
    T.class = { "Warrior", "WARRIOR" }
    Bump()
    CHECK(View("SHADOW_LABYRINTH_KEY", "lockpick_alt") == nil, "C8 a warrior does not")
    T.class = { "Rogue", "ROGUE" }
    T.skills = { { name = "Lockpicking", rank = 350 } }
    Bump()
    local item = A.Guide("SHADOW_LABYRINTH_KEY")
    CHECK(item.status == "DONE" and item.word == "Done", "C9 a rogue with Lockpicking 350 reads Shadow Labyrinth Key Done", item.word)
    local ikiss, lootKey = View("SHADOW_LABYRINTH_KEY", "kill_ikiss"), View("SHADOW_LABYRINTH_KEY", "loot_key")
    CHECK(ikiss and ikiss.status == "WAIVED" and ikiss.word == "Not needed" and lootKey and lootKey.status == "WAIVED" and not ikiss.counted,
        "C10 ...with the Talon King and the key Not needed", ikiss and ikiss.status)
    Clean()
    -- the druid's flight
    T.class = { "Druid", "DRUID" }
    Bump()
    item = A.Guide("FLYING")
    EQ(item.word, "1/4", "C11 a level-70 druid with neither form nor mount reads 1/4")
    local ff = View("FLYING", "flight_form")
    CHECK(ff and ff.status == "NEXT" and ff.word == "Next" and ff.isCurrent, "C12 ...Flight Form is Next", ff and ff.status)
    local riding, mount = View("FLYING", "expert_riding"), View("FLYING", "flying_mount")
    CHECK(riding and not riding.counted and riding.word == "Unchecked"
        and riding.reason:find("^Not counted: the Flight Form route is preferred for druids") ~= nil
        and mount and not mount.counted and mount.word == "To do"
        and mount.reason:find("^Not counted: the Flight Form route is preferred for druids") ~= nil,
        "C13 ...riding and mount keep their own words, uncounted, with the Not counted reason", riding and riding.reason)
    T.skills = { { name = "Riding", rank = 225 } }
    T.items[25470] = 1
    Bump()
    ff = View("FLYING", "flight_form")
    CHECK(ff and ff.status == "WAIVED" and ff.word == "Not needed", "C14 a druid who bought riding anyway: Flight Form Not needed", ff and ff.status)
    T.spells[40120] = true
    Bump()
    local artisan = View("FLYING", "artisan_riding")
    item = A.Guide("FLYING")
    CHECK(artisan and artisan.counted and artisan.status == "PARTIAL" and artisan.word == "225/300" and item.status ~= "DONE",
        "C15 Swift Flight Form's group needs Artisan Riding: the guide is not Done", artisan and artisan.word)
    Clean()
    T.class = { "Druid", "DRUID" }
    T.level = 68
    Bump()
    artisan = View("FLYING", "artisan_riding")
    local lvl = View("FLYING", "level_70")
    CHECK(artisan and artisan.status == "LOCKED" and artisan.reason == "Level 68 of 70" and lvl and lvl.status == "DONE",
        "C16 a 68 druid: level step Done, Artisan Locked", artisan and artisan.reason)
    Clean()
    T.skills = { { name = "Riding", rank = 300 } }
    T.items[32857] = 1
    Bump()
    item = A.Guide("FLYING")
    CHECK(item.status == "DONE" and item.done == 5 and item.total == 5 and View("FLYING", "flight_form") == nil,
        "C17 a warrior with Riding 300 and a Netherwing drake reads both flights done", item.done .. "/" .. item.total .. " " .. item.status)
    Clean()
end

-- ===========================================================================
-- D. Scoring and lists
-- ===========================================================================
do
    Section("D Scoring and lists")
    Clean()
    local v, sum, item
    v = View("KARAZHAN_ATTUNEMENT", "shadow_lab_key_access")
    CHECK(v and v.optional and not v.counted and v.status == "OPTIONAL" and v.word == "Optional", "D1 an optional step is not counted: Optional", v and v.status)
    v = View("BADGES", "heroics_overview")
    CHECK(v and v.note and not v.counted and v.status == "NOTE" and v.word == "", "D2 a note line is not counted and has no word", v and v.status)
    v = View("HEROIC_HELLFIRE", "set_heroic")
    CHECK(v and not v.counted and v.status == "UNSET" and v.word == "Not set", "D3 the difficulty setting is not counted: Not set", v and v.status)
    T.dungeonDifficulty = 2
    Bump()
    v = View("HEROIC_HELLFIRE", "set_heroic")
    CHECK(v and v.status == "SET" and v.word == "Set", "D3 ...Set once Heroic is selected", v and v.status)
    T.dungeonDifficulty = 1
    Bump()
    v, sum = View("HEROIC_HELLFIRE", "rep_revered")
    CHECK(v == nil and sum.hiddenOtherPhases == 1, "D4 a PAST step is hidden at Phase 4 and counted in hiddenOtherPhases", tostring(sum.hiddenOtherPhases))
    v = View("HEROIC_HELLFIRE", "rep_revered", { otherPhases = true })
    CHECK(v and v.status == "PAST" and v.word == "Until Phase 3" and not v.counted and v.phaseWord == "Until Phase 3",
        "D5 ...shown under otherPhases as Until Phase 3, uncounted", v and v.word)
    A.SetPhase(3)
    v = View("HEROIC_HELLFIRE", "rep_honored", { otherPhases = true })
    CHECK(v and v.status == "LATER" and v.word == "Phase 4" and not v.counted, "D6 a LATER step reads the phase short name", v and v.word)
    v = View("HEROIC_HELLFIRE", "rep_honored")
    CHECK(v == nil, "D6 ...and is hidden without otherPhases")
    A.SetPhase("AUTO")
    -- the current pointer and the Next word
    v, sum = View("KARAZHAN_ATTUNEMENT", "arcane_disturbances")
    CHECK(v and v.isCurrent and v.status == "NEXT" and v.word == "Next" and sum.current == "arcane_disturbances", "D7 an OPEN current step reads Next", v and v.status)
    v = View("KARAZHAN_ATTUNEMENT", "restless_activity")
    CHECK(v and not v.isCurrent and v.status == "OPEN" and v.word == "To do", "D7 ...the one after it reads To do", v and v.word)
    Log({ id = 9824 })
    v = View("KARAZHAN_ATTUNEMENT", "arcane_disturbances")
    CHECK(v and v.isCurrent and v.status == "LOG" and v.word == "In log", "D8 a LOG current step keeps In log", v and v.status)
    T.done[9824] = true
    Log({ id = 9826, state = 1 })
    v, sum = View("KARAZHAN_ATTUNEMENT", "contact_from_dalaran")
    CHECK(v and v.status == "READY" and v.isCurrent and sum.current == "contact_from_dalaran", "D9 a READY step anywhere is the current step", tostring(sum.current))
    v = View("KARAZHAN_ATTUNEMENT", "restless_activity")
    CHECK(v and v.status == "OPEN" and not v.isCurrent, "D9 ...the open step before it is not", v and v.status)
    Clean()
    T.level = 62
    Bump()
    item = A.Guide("HEROIC_HELLFIRE")
    v = View("HEROIC_HELLFIRE", "level_70")
    CHECK(v and v.status == "LOCKED" and v.word == "Locked" and v.isCurrent and item.currentLocked == true and item.current == "level_70",
        "D10 a LOCKED current step keeps Locked and the guide says currentLocked", v and v.status)
    Clean()
    -- the five guide words and strips
    T.done[9824] = true
    Bump()
    item = A.Guide("KARAZHAN_ATTUNEMENT")
    CHECK(item.status == "PROGRESS" and item.word == "2/11" and item.tone == "secondary" and item.strip == "open", "D11 PROGRESS: the ratio, strip open with progress",
        item.word .. " " .. item.strip)
    item = A.Guide("NIGHTBANE_SUMMON")
    CHECK(item.status == "PROGRESS" and item.word == "0/9" and item.strip == "faint", "D12 PROGRESS at 0: strip faint", item.word .. " " .. item.strip)
    A.MarkGuide("GRUUL_MAGTHERIDON", true)
    item = A.Guide("GRUUL_MAGTHERIDON")
    CHECK(item.status == "DONE" and item.word == "Done" and item.tone == "good" and item.strip == "good" and item.bucket == "DONE", "D13 DONE: Done, good", item.word)
    item = A.Guide("SSC_ATTUNEMENT")
    CHECK(item.status == "NOTNEEDED" and item.word == "Not needed" and item.tone == "faint" and item.strip == "faint" and item.bucket == "OTHER",
        "D14 NOTNEEDED: Not needed, faint, bucket OTHER", item.word)
    item = A.Guide("SUNWELL_PLATEAU")
    CHECK(item.status == "LATER" and item.word == "Phase 5" and item.tone == "warn" and item.strip == "warn" and item.bucket == "OTHER",
        "D15 LATER: the phase short name, warn", item.word)
    T.items[29434] = 37
    Bump()
    item = A.Guide("BADGES")
    CHECK(item.status == "RECURRING" and item.word == "37 badges" and item.tone == "open" and item.bucket == "NEEDED", "D16 RECURRING: 37 badges", item.word)
    -- buckets, order, header counts, totals
    local items, totals = A.Guides({ filter = "ALL", search = "", collapsed = {} })
    local raid = {}
    local raidHeader, badgesHeader
    for _, it in ipairs(items) do
        if it.kind == "header" and it.category == "RAID" then raidHeader = it end
        if it.kind == "header" and it.category == "BADGES" then badgesHeader = it end
        if it.kind == "guide" and it.category == "RAID" then raid[#raid + 1] = it.key end
    end
    EQ(table.concat(raid, ","),
        "KARAZHAN_ATTUNEMENT,NIGHTBANE_SUMMON,ZUL_AMAN,GRUUL_MAGTHERIDON,SSC_ATTUNEMENT,TK_ATTUNEMENT,HYJAL_ATTUNEMENT,BLACK_TEMPLE_ATTUNEMENT,SUNWELL_PLATEAU",
        "D17 order within a module: NEEDED, then DONE, then Not needed, then Later, each in data order")
    CHECK(raidHeader and raidHeader.done == 1 and raidHeader.total == 4, "D18 header counts: done over NEEDED and DONE guides, Other excluded",
        raidHeader and (raidHeader.done .. "/" .. raidHeader.total))
    CHECK(badgesHeader and badgesHeader.done == 0 and badgesHeader.total == 0, "D19 the BADGES header carries no count")
    CHECK(totals.guides == 25 and totals.done == 1 and totals.notNeeded == 4 and totals.later == 3 and totals.todo == 17 and totals.needed == 18,
        "D20 totals: 25 guides (the recurring one excluded), 1 done, 17 to do, 4 not needed, 3 later",
        totals.guides .. " " .. totals.done .. " " .. totals.todo .. " " .. totals.notNeeded .. " " .. totals.later)
    CHECK(totals.needed == totals.done + totals.todo and math.abs(totals.pct - totals.done / totals.needed) < 1e-9, "D21 needed = done + todo; pct = done / needed")
    A.MarkGuide("GRUUL_MAGTHERIDON", false)
    item = A.Guide("SSC_ATTUNEMENT")
    local _, ssum = A.Steps("SSC_ATTUNEMENT")
    CHECK(type(item.pct) == "number" and item.pct == item.done / math.max(item.total, 1) and item.notice and item.notice:find("^Not needed since Phase 3") ~= nil
        and ssum.total == 0, "D22 NOTNEEDED keeps its ratio and says since when (all of its steps are PAST at Phase 4: 0 of 0)", item.notice)
    item = A.Guide("SUNWELL_PLATEAU")
    EQ(item.notice, "Opens in Phase 5, no date announced.", "D23 LATER guide notice")
    Clean()
    db.AttuneAccount.KARAZHAN_ATTUNEMENT = { char = "Main-Realm", at = 1697000000 }
    A.Invalidate("store")
    item = A.Guide("KARAZHAN_ATTUNEMENT")
    CHECK(item.status == "DONE" and item.bucket == "DONE" and item.account and item.account.char == "Main-Realm", "D24 the ledger makes an alt's guide Done", item.status)
    Clean()
    A.MarkGuide("SSC_ATTUNEMENT", true)
    A.SetPhase(2)
    item = A.Guide("SSC_ATTUNEMENT")
    A.Guides({})
    CHECK(item.status == "DONE" and db.AttuneAccount.SSC_ATTUNEMENT == nil, "D25 the ledger is NOT written when a guide is Done by a guide mark", tostring(db.AttuneAccount.SSC_ATTUNEMENT))
    A.MarkGuide("SSC_ATTUNEMENT", false)
    for _, sv in ipairs((A.Steps("SSC_ATTUNEMENT"))) do
        if sv.counted then A.Mark("SSC_ATTUNEMENT", sv.key, true) end
    end
    item = A.Guide("SSC_ATTUNEMENT")
    A.Guides({})
    CHECK(item.status == "DONE" and db.AttuneAccount.SSC_ATTUNEMENT == nil, "D26 ...nor by step marks", tostring(db.AttuneAccount.SSC_ATTUNEMENT))
    A.SetPhase("AUTO")
    Clean()
    -- Continue: a character with no progress anywhere (the default world's
    -- Cenarion Expedition at Honored would already satisfy Heroic Coilfang's
    -- rep step, and rule (3) would call that guide started)
    local gk, sk, reason
    world.reps[942] = 0
    T.level = 41
    Bump()
    gk, sk, reason = A.Continue()
    CHECK(gk == nil and reason == "none", "D27 Continue at 41: none (nothing passes rule 4)", tostring(gk) .. " " .. tostring(reason))
    T.level = 60
    Bump()
    gk, sk, reason = A.Continue()
    CHECK(gk == "ALDOR_SCRYER_CHOICE" and sk == "adal" and reason == "first", "D28 Continue at 60: first, the Aldor or Scryers guide (minLevel 60)",
        tostring(gk) .. " " .. tostring(sk) .. " " .. tostring(reason))
    T.level = 70
    T.done[9824] = true
    Bump()
    gk, sk, reason = A.Continue()
    CHECK(gk == "KARAZHAN_ATTUNEMENT" and sk == "restless_activity" and reason == "started", "D29 Continue: started, the first needed guide with a quest done",
        tostring(gk) .. " " .. tostring(sk) .. " " .. tostring(reason))
    A.Touch("HEROIC_COILFANG")
    Char().guide = nil
    A.Invalidate("store")
    gk, sk, reason = A.Continue()
    CHECK(gk == "HEROIC_COILFANG" and reason == "progressed", "D30 Continue: progressed, the latest touch", tostring(gk) .. " " .. tostring(reason))
    A.Touch("HEROIC_HELLFIRE")
    gk, sk, reason = A.Continue()
    CHECK(gk == "HEROIC_HELLFIRE" and sk == "rep_honored" and reason == "opened", "D31 Continue: opened, the guide opened last",
        tostring(gk) .. " " .. tostring(sk) .. " " .. tostring(reason))
    Clean()
    local list = A.Guides({})
    for _, it in ipairs(list) do
        if it.kind == "guide" and it.bucket == "NEEDED" and it.status ~= "RECURRING" then A.MarkGuide(it.key, true) end
    end
    gk, sk, reason = A.Continue()
    CHECK(gk == nil and reason == "done", "D32 Continue: done when every needed guide is Done", tostring(gk) .. " " .. tostring(reason))
    Clean()
    world.reps[942] = 0
    A.Invalidate("reps")
    -- 4.10 rule (3) is "the first NEEDED guide in catalogue order with
    -- 0 < done", and done counts every counted step that is Done; a LEVEL
    -- step is counted (8.7: "counted = level_70 Done, ..."), so a fresh 70
    -- reads Karazhan 1/11 on level_68 alone and Continue calls it started
    -- before any quest is done. Rule (4), which would skip Karazhan for its
    -- Caverns of Time prerequisite and Nightbane for Karazhan, is never
    -- reached at 68 or more with this data (9.2 D's clause asked for it;
    -- the spec finding against 4.10 rule (3) records the tension).
    item = A.Guide("KARAZHAN_ATTUNEMENT")
    local l68 = View("KARAZHAN_ATTUNEMENT", "level_68")
    gk, sk, reason = A.Continue()
    CHECK(gk == "KARAZHAN_ATTUNEMENT" and sk == "arcane_disturbances" and reason == "started"
        and item.done == 1 and item.total == 11 and l68 ~= nil and l68.status == "DONE",
        "D33 Continue at 70 with Karazhan undone: rule (3) calls it started on its Done level step alone (1/11; rule (4) not reached)",
        tostring(gk) .. " " .. tostring(sk) .. " " .. tostring(reason) .. " " .. tostring(item.done) .. "/" .. tostring(item.total)
            .. " level_68=" .. tostring(l68 and l68.status))
    -- Find
    EQ((A.Find("karazhan")), "KARAZHAN_ATTUNEMENT", "D34 Find exact name")
    EQ((A.Find("heroic co")), "HEROIC_COILFANG", "D35 Find a prefix of the name")
    EQ((A.Find("flamewrought")), "HEROIC_HELLFIRE", "D36 Find a substring of the title")
    EQ((A.Find("shadow_labyrinth")), "SHADOW_LABYRINTH_KEY", "D37 Find with underscores as spaces")
    EQ((A.Find("zzz")), nil, "D38 Find nothing is nil")
    local _, name = A.Find("nightbane")
    EQ(name, "Nightbane", "D38 ...the second return is the name")
    -- filters and search
    A.MarkGuide("GRUUL_MAGTHERIDON", true)
    local function Guides(view)
        local out, tot = {}, nil
        local its
        its, tot = A.Guides(view)
        for _, it in ipairs(its) do if it.kind == "guide" then out[#out + 1] = it end end
        return out, tot
    end
    local todo, tot = Guides({ filter = "TODO" })
    -- the recurring Badges guide is bucket NEEDED (its module's only row) but
    -- never one of the totals
    local ok = #todo == tot.todo + 1
    for _, it in ipairs(todo) do if it.bucket ~= "NEEDED" then ok = false end end
    CHECK(ok, "D39 the To do filter lists every NEEDED guide (Badges included) and nothing else", #todo .. " vs " .. tot.todo)
    local done = Guides({ filter = "DONE" })
    CHECK(#done == 1 and done[1].key == "GRUUL_MAGTHERIDON", "D40 the Done filter lists the finished guide", #done)
    local other = Guides({ filter = "OTHER" })
    ok = #other == tot.notNeeded + tot.later
    for _, it in ipairs(other) do if it.bucket ~= "OTHER" then ok = false end end
    CHECK(ok, "D41 the Other filter lists Not needed and Later", #other)
    A.MarkGuide("GRUUL_MAGTHERIDON", false)
    local ikiss = Rec("SHADOW_LABYRINTH_KEY", "kill_ikiss")
    local hits = Guides({ filter = "ALL", search = ikiss.title })
    CHECK(#hits == 1 and hits[1].key == "SHADOW_LABYRINTH_KEY", "D42 a search hit on a step title lists its guide", #hits .. " " .. tostring(hits[1] and hits[1].key))
    Clean()
end

-- ===========================================================================
-- I. Marks
-- ===========================================================================
do
    Section("I Marks")
    Clean()
    local v
    A.Mark("KARAZHAN_ATTUNEMENT", "arcane_disturbances", true)
    v = View("KARAZHAN_ATTUNEMENT", "arcane_disturbances")
    CHECK(v and v.status == "DONE" and v.word == "Done", "I1 Mark Done flips the word to Done", v and v.word)
    EQ(A.IsMarked("KARAZHAN_ATTUNEMENT", "arcane_disturbances"), Now(), "I2 ...and stores the date")
    CHECK(v and v.reason == "Marked by you on " .. DW(Now()) and v.markedAt == Now() and v.how:find(" Marked by you on " .. DW(Now()) .. ".", 1, true),
        "I3 ...the reason and the how sentence name the date", v and v.reason)
    A.Mark("KARAZHAN_ATTUNEMENT", "arcane_disturbances", false)
    v = View("KARAZHAN_ATTUNEMENT", "arcane_disturbances")
    CHECK(A.IsMarked("KARAZHAN_ATTUNEMENT", "arcane_disturbances") == nil and v and v.status == "NEXT", "I4 Undo clears the mark and the word", v and v.status)
    A.MarkGuide("KARAZHAN_ATTUNEMENT", true)
    v = View("KARAZHAN_ATTUNEMENT", "the_masters_touch")
    local item = A.Guide("KARAZHAN_ATTUNEMENT")
    CHECK(A.IsMarked("KARAZHAN_ATTUNEMENT", nil) == Now() and v and v.status == "DONE" and v.reason == "Marked for the whole guide" and item.status == "DONE",
        "I5 the guide mark: dated, every counted step Marked for the whole guide, the guide Done", v and v.reason)
    A.MarkGuide("KARAZHAN_ATTUNEMENT", false)
    A.Mark("BADGES", "karazhan", true)
    local m = Char().marks["BADGES:karazhan"]
    local until_ = type(m) == "table" and m["until"]
    CHECK(until_ == Now() + mock.clock.apiWeekly and A.IsMarked("BADGES", "karazhan") == Now(), "I6 a weekly mark carries until = now + the weekly reset",
        tostring(until_))
    mock.clock.serverTime = until_ + 1
    A.Invalidate("store")
    v = View("BADGES", "karazhan")
    CHECK(A.IsMarked("BADGES", "karazhan") == nil and v and v.status == "OPEN", "I6 ...and expires at its until", v and v.status)
    mock.clock.serverTime = NOW4
    A.Mark("BADGES", "karazhan", false)
    T.done[9824] = true
    Bump()
    A.Mark("KARAZHAN_ATTUNEMENT", "arcane_disturbances", true)
    v = View("KARAZHAN_ATTUNEMENT", "arcane_disturbances")
    CHECK(v and v.reason == "Flagged complete", "I7 a mark never overrides a detected Done's reason", v and v.reason)
    Char().seen[9825] = Now()
    A.Touch("KARAZHAN_ATTUNEMENT")
    db.AttuneAccount.TK_ATTUNEMENT = { char = "Main-Realm", at = Now() }
    A.ClearMarks()
    local at = Char()
    CHECK(next(at.marks) == nil and at.seen[9825] == Now() and at.touched.KARAZHAN_ATTUNEMENT == Now() and db.AttuneAccount.TK_ATTUNEMENT ~= nil,
        "I8 Clear Marks wipes marks only: seen, touched and the ledger stay")
    Clean()
    T.done[9837] = true
    Bump()
    item = A.Guide("KARAZHAN_ATTUNEMENT")
    local row = db.AttuneAccount.KARAZHAN_ATTUNEMENT
    CHECK(item.status == "DONE" and type(row) == "table", "I9 AttuneAccount is written when an account-wide guide reaches Done by detection", item.status)
    CHECK(row and row.char == "Tester-Testrealm" and row.at == Now(), "I10 ...the row names Name-Realm and the time", row and tostring(row.char))
    Clean()
    db.AttuneAccount.KARAZHAN_ATTUNEMENT = { char = "Main-Realm", at = 1697000000 }
    A.Invalidate("store")
    item = A.Guide("KARAZHAN_ATTUNEMENT")
    local _, sum = A.Steps("KARAZHAN_ATTUNEMENT")
    CHECK(item.status == "DONE" and item.notice == "Done by Main-Realm, " .. DW(1697000000)
        and sum.notice == "Done by Main-Realm on " .. DW(1697000000) .. " (account ledger).",
        "I11 another character reads the row as Done by Name-Realm", tostring(item.notice))
    A.ClearMarks()
    CHECK(type(db.AttuneAccount.KARAZHAN_ATTUNEMENT) == "table" and A.AccountDone("KARAZHAN_ATTUNEMENT").char == "Main-Realm",
        "I12 the ledger survives Clear Marks and AccountDone reads it")
    Clean()
end

-- ===========================================================================
-- L. Events
-- ===========================================================================
do
    Section("L Events")
    Clean()
    local seen = {}
    local function Spy(domain) seen[#seen + 1] = domain end
    A.AddListener(Spy)
    local function Reset() for i = #seen, 1, -1 do seen[i] = nil end end
    local function Domains()
        local set, out = {}, {}
        for _, d in ipairs(seen) do if not set[d] then set[d] = true; out[#out + 1] = d end end
        table.sort(out)
        return table.concat(out, ",")
    end
    local DOMAIN = { QUEST_TURNED_IN = "quests", QUEST_ACCEPTED = "quests", QUEST_REMOVED = "quests", QUEST_LOG_UPDATE = "quests",
        BAG_UPDATE_DELAYED = "items", UPDATE_FACTION = "reps", PLAYER_LEVEL_UP = "char", SPELLS_CHANGED = "spells",
        LEARNED_SPELL_IN_SKILL_LINE = "spells", SKILL_LINES_CHANGED = "skills", UPDATE_INSTANCE_INFO = "locks",
        PLAYER_ENTERING_WORLD = "world", ZONE_CHANGED_NEW_AREA = "world", PLAYER_DIFFICULTY_CHANGED = "world",
        GOSSIP_SHOW = "store", MERCHANT_SHOW = "store", ENCOUNTER_END = "store", BOSS_KILL = "store", PLAYER_LOGIN = "phase" }
    local ARGS = { QUEST_TURNED_IN = { 9824 }, QUEST_ACCEPTED = { 3, 9825 }, QUEST_REMOVED = { 9824 }, PLAYER_LEVEL_UP = { 70 },
        ENCOUNTER_END = { 650, "Gruul the Dragonkiller", 1, 25, 1 }, BOSS_KILL = { 651, "Magtheridon" } }
    local bad, unregistered = {}, {}
    local names = {}
    for event in pairs(DOMAIN) do names[#names + 1] = event end
    table.sort(names)
    for _, event in ipairs(names) do
        Reset()
        local gen = A.generation
        mock.Fire(event, unpack(ARGS[event] or {}))
        if not (mock.eventRegistry[event] and #mock.eventRegistry[event] > 0) then unregistered[#unregistered + 1] = event end
        if Domains() ~= DOMAIN[event] or A.generation ~= gen + 1 then bad[#bad + 1] = event .. "=" .. Domains() end
    end
    EQ(#unregistered, 0, "L1 (every event of 4.7 is registered)", table.concat(unregistered, " "))
    EQ(#bad, 0, "L1 each registered event flips exactly its own domain, once", table.concat(bad, " "))
    Char().kills = {}
    local orig = Q.IsExpanding
    Q.IsExpanding = function() return true end
    Reset()
    local gen = A.generation
    mock.Fire("QUEST_LOG_UPDATE")
    Q.IsExpanding = orig
    CHECK(#seen == 0 and A.generation == gen, "L2 QUEST_LOG_UPDATE while Q.IsExpanding() flips nothing", Domains())
    local before = #mock.timers
    mock.Fire("QUEST_TURNED_IN", 9825)
    EQ(Char().seen[9825], Now(), "L3 QUEST_TURNED_IN writes seen")
    local at1, at11 = false, false
    for i = before + 1, #mock.timers do
        if mock.timers[i].at == mock.state.now + 1 then at1 = true end
        if mock.timers[i].at == mock.state.now + 11 then at11 = true end
    end
    CHECK(at1 and at11, "L4 ...and arms the two grace rechecks at 1 s and 11 s", (#mock.timers - before) .. " timers")
    mock.state.savedInstances = { { name = "Zul'Aman", mapID = 568, reset = 200000, isRaid = true } }
    mock.Fire("UPDATE_INSTANCE_INFO")
    local row = db.AttunePhaseSeen[4]
    CHECK(type(row) == "table" and row.kind == "lockout" and row.detail == "Zul'Aman lockout" and Char().phaseEvidence[4] ~= nil,
        "L5 a 568 saved instance writes evidence 4 (account-wide and the character's mirror)", row and tostring(row.detail))
    mock.state.savedInstances = {}
    CHECK(mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED == nil or #mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED == 0,
        "L9 (no combat log listener outside a KILL map)")
    T.instance = { inside = true, kind = "raid", id = 565, difficulty = 1 }
    mock.Fire("ZONE_CHANGED_NEW_AREA")
    local e = Char().entered[565]
    CHECK(type(e) == "table" and e.difficulty == 1 and e.when == Now(), "L6 entering 565 writes entered", tostring(e and e.difficulty))
    T.npcGuid = "Creature-0-4379-530-1234-18525-0000ABCDEF"
    mock.Fire("MERCHANT_SHOW")
    EQ(Char().talked[18525], Now(), "L7 MERCHANT_SHOW with a creature GUID writes talked")
    mock.Fire("ENCOUNTER_END", 650, "Gruul the Dragonkiller", 1, 25, 0)
    CHECK(Char().kills[19044] == nil, "L8 (a wipe writes no kill)")
    mock.Fire("ENCOUNTER_END", 650, "Gruul the Dragonkiller", 1, 25, 1)
    local k = Char().kills[19044]
    CHECK(type(k) == "table" and k.when == Now(), "L8 ENCOUNTER_END with success 1 writes kills for the encounter's creatures", tostring(k and k.when))
    CHECK(mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED and #mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED == 1,
        "L9 the combat log is listened to only after entering a KILL map", tostring(mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED and #mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED))
    T.instance = { inside = false, kind = "none", id = nil, difficulty = 0 }
    mock.Fire("ZONE_CHANGED_NEW_AREA")
    CHECK(#mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED == 0, "L10 ...and unregistered on leaving", #mock.eventRegistry.COMBAT_LOG_EVENT_UNFILTERED)
    -- a client that rejects ENCOUNTER_END: the engine loads in a sandbox whose
    -- frames raise on it and register nothing anywhere else
    do
        local env = setmetatable({
            CommanderQuestLog = { EnsureCharDB = Q.EnsureCharDB },
            CreateFrame = function()
                local f = mock.NewWidget("Frame")
                f.RegisterEvent = function(_, event)
                    if event == "ENCOUNTER_END" or event == "BOSS_KILL" then error("Unknown event: " .. event) end
                end
                return f
            end,
        }, { __index = _G })
        local chunk = assert(loadfile(OVERRIDE["CommanderQuestLog" .. "Attune.lua"] or (MODULE .. "CommanderQuestLogAttune.lua")))
        setfenv(chunk, env)
        local ok, err = pcall(chunk)
        CHECK(ok and type(env.CommanderQuestLog.Attune) == "table" and env.CommanderQuestLog ~= Q,
            "L11 a client rejecting ENCOUNTER_END does not break loading", err)
    end
    -- the refresh queue: never Q.Refresh from the handler, one flush per RunTimers
    Clean()
    db.ViewMode = "LOG"
    CommanderQuestLog_Show()
    Q.SetViewMode("ATTUNE")
    mock.RunTimers(15); mock.RunTimers(15)
    EQ(Q.ViewMode(), "ATTUNE", "L12 (the window is up on the Attunements tab)")
    local refreshes = 0
    local realRefresh = Q.Refresh
    Q.Refresh = function(...) refreshes = refreshes + 1; return realRefresh(...) end
    mock.Fire("QUEST_LOG_UPDATE")
    mock.Fire("BAG_UPDATE_DELAYED")
    mock.Fire("UPDATE_FACTION")
    EQ(refreshes, 0, "L12 Q.Refresh is never called from the event handler")
    mock.RunTimers(1)
    EQ(refreshes, 1, "L13 RunTimers flushes exactly one coalesced refresh")
    Q.Refresh = realRefresh
    Reset()
    mock.RunTimers(60)
    HAS(Domains(), "phase", "L14 mock.RunTimers(60) fires the calendar tick and the phase generation moves")
    Reset()
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    HAS(Domains(), "phase", "L15 the suite's UPDATE notification invalidates the phase")
    HAS(Domains(), "store", "L16 ...and the store")
    db.ViewMode = "LOG"
    CommanderQuestLog_Hide()
    Clean()
    EQ(#mock.caughtErrors, 0, "L17 no error caught anywhere in the run", mock.caughtErrors[1])
end

if counts.fails == 0 then io.write(counts.checks, " checks passed\n") end
Done()
