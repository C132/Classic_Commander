-- Commander Quest Log: Questie adapter smoke (luajit).
--
-- Drives CommanderQuestLogQuestie.lua against fake_questie.lua -- a Questie
-- that reproduces the real one's traps -- under a WoW mock just big enough for
-- the adapter: a C_Timer with a manual clock that runs one "frame" at a time,
-- an event frame, print capture and the client stubs the fake installs.
--
--   luajit questie_adapter_smoke.lua
--   CQL_ADAPTER=/some/copy.lua luajit questie_adapter_smoke.lua   -- against a mutated copy
--   CQL_ENGINE=/nonexistent luajit questie_adapter_smoke.lua      -- the engine-absent path
--
-- (Mutation-tested on 2026-10-04: thirty-odd single-line breakages of the
-- adapter -- returnText false, ImportModule, no pcall round the throwing
-- bridge, no QuestPointers guard, no folds, no debounce, a cached `complete`,
-- no LRU, no pin merge or cap, wrong flag bits, work inside the ready
-- callback, one-shot sweep, wrong waypoint order, dot for colon, a truncated
-- faction read, dropped event bumps -- each fails at least one check.)
--
-- What it proves, section by section: A no Questie at all; B LOADING, and the
-- ready callback deferred a frame with no work done inside it; C uiMap ->
-- areaId through the throwing bridge, the parent / 3535 / instance folds and
-- the continents; D the zone menu and continent zone lists; E facts (the
-- returnText gotcha, flag arithmetic, givers, sentinels, layers); F the
-- reverse exclusive index, chunked, and its generation step; G the character
-- table read fresh; H one generation step and one listener call per burst;
-- I the view cache by generation and its LRU; J background summaries;
-- K waypoints to Commander Orders (owned per quest, every spawn as
-- alternatives, the /way line when refused), Route Zone and the entrance
-- resolver; L giver pins; M one-quest reads; N broken and
-- absent Questies; O end to end through the REAL engine (skipped, not
-- failed, while that file is absent); P nothing forbidden was ever called,
-- no global leaked, no shape glyph was printed.
--
-- Mock notes worth keeping:
--   * Timers run by FRAME: a C_Timer.After(0, fn) scheduled during a frame
--     runs on the next one, as in the client. The reverse index's chunking
--     and the ready deferral are only observable that way.
--   * The adapter pcalls every Questie call, so a forbidden call that raised
--     would be swallowed. The fake RECORDS forbidden and wrong-style calls and
--     section P reads the record.
--   * Reloading the adapter for a new scenario clears the timer queue, the
--     event registry and the hub's listeners first, or the previous
--     instance's handlers would keep firing against the new fake.

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
local function NEAR(a, b) return type(a) == "number" and type(b) == "number" and math.abs(a - b) < 1e-6 end

-- ===========================================================================
-- WoW mock
-- ===========================================================================

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end
local function LastPrint() return printLog[#printLog] end

local caughtErrors = {}
function geterrorhandler() return function(err) caughtErrors[#caughtErrors + 1] = tostring(err) end end

-- Time in whole milliseconds; a frame is 16 ms
local now = 0
local timers, timerSeq = {}, 0
C_Timer = {
    After = function(delay, fn)
        timerSeq = timerSeq + 1
        timers[#timers + 1] = { at = now + math.floor((delay or 0) * 1000 + 0.5), fn = fn, seq = timerSeq }
    end,
}
-- The client's clock on the same manual time (seconds, as GetTime answers)
function GetTime() return now / 1000 end
local function Frame(dt)
    now = now + (dt or 16)
    local due, keep = {}, {}
    for _, t in ipairs(timers) do
        if t.at <= now then due[#due + 1] = t else keep[#keep + 1] = t end
    end
    timers = keep
    table.sort(due, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.seq < b.seq end)
    for _, t in ipairs(due) do t.fn() end
    return #due
end
local function Advance(ms)
    local target = now + ms
    while now < target do Frame(math.min(16, target - now)) end
end
local function Settle()
    for _ = 1, 5000 do
        if #timers == 0 then return true end
        Frame()
    end
    return false
end

local registry = {}      -- event -> { frames }
local registeredEvents = {}
function CreateFrame()
    local frame = { __scripts = {} }
    function frame:RegisterEvent(event)
        registry[event] = registry[event] or {}
        table.insert(registry[event], self)
        registeredEvents[event] = true
    end
    function frame:SetScript(name, fn) self.__scripts[name] = fn end
    function frame:GetScript(name) return self.__scripts[name] end
    return frame
end
local function Fire(event, ...)
    for _, frame in ipairs(registry[event] or {}) do
        local handler = frame.__scripts.OnEvent
        if handler then handler(frame, event, ...) end
    end
end

Commander = { __listeners = {} }
function Commander.AddListener(event, fn)
    Commander.__listeners[event] = Commander.__listeners[event] or {}
    for _, existing in ipairs(Commander.__listeners[event]) do if existing == fn then return end end
    table.insert(Commander.__listeners[event], fn)
end
function Commander.Notify(event, ...)
    for _, fn in ipairs(Commander.__listeners[event] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then caughtErrors[#caughtErrors + 1] = tostring(err) end
    end
end
COMMANDER_QUESTLOG_EVENTS = { UPDATE = "COMMANDER_QUESTLOG_UPDATE" }
CommanderQuestLogDB = {}
CommanderQuestLogChar = { Ignored = {} }
C_AddOns = { GetAddOnMetadata = function(addon, field)
    if addon == "Questie" and field == "Version" then return "12.0.3" end
    return nil
end }
function UnitClass() return "Paladin", "PALADIN", 2 end

-- ===========================================================================
-- Load the engine (optional) and the fake
-- ===========================================================================

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local RealEngine
do
    -- CQL_ENGINE points at another copy (or at nothing, to try the skip path)
    local chunk = loadfile(os.getenv("CQL_ENGINE") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogCompletion.lua"))
    if chunk then
        local ok = pcall(chunk)
        local C = Q.Completion
        if ok and type(C) == "table" and type(C.BuildZone) == "function" then RealEngine = C end
    end
    Q.Completion = nil
end

local Fake = dofile(ADDONS .. "/Commander_QuestLog/Harness/fake_questie.lua")
local allFakes = {}

-- A stand-in engine for the sections that test the adapter's own machinery
-- (caching, jobs, pins), so a fault there is the adapter's and not the engine's
local stubBuilds = 0
local Stub = {
    BuildZone = function(facts, char, meta)
        stubBuilds = stubBuilds + 1
        local entries, byId, counted, done = {}, {}, 0, 0
        for _, fact in ipairs(facts) do
            local isDone = char.isComplete(fact.id)
            local entry = {
                isHeader = false, id = fact.id, questID = fact.id, key = "id:" .. fact.id, title = fact.name,
                status = isDone and "DONE" or "AVAILABLE", base = isDone and "DONE" or "AVAILABLE",
                counted = fact.layer ~= "EXTRA", layer = fact.layer, starters = fact.starters or {},
                finishers = fact.finishers or {}, startsHere = fact.startsHere, objectives = {}, fact = fact,
            }
            entries[#entries + 1] = entry
            byId[fact.id] = entry
            if entry.counted then
                counted = counted + 1
                if isDone then done = done + 1 end
            end
        end
        return {
            areaId = meta.areaId, name = meta.name, entries = entries, byId = byId, chains = {},
            totals = { counted = counted, done = done, pct = counted > 0 and done / counted or nil, byStatus = {} },
        }
    end,
    Summary = function(view)
        return { counted = view.totals.counted, done = view.totals.done, pct = view.totals.pct }
    end,
}

local A
-- CQL_ADAPTER points the harness at another copy (mutation testing)
local ADAPTER = os.getenv("CQL_ADAPTER") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogQuestie.lua")
local function LoadAdapter()
    timers = {}
    registry = {}
    Commander.__listeners = {}
    assert(loadfile(ADAPTER))()
    A = Q.Questie
end

local function Install(world, opts)
    local fake = Fake.Install(world, opts)
    Fake.InstallClient(world, { force = true })
    allFakes[#allFakes + 1] = fake
    return fake
end

-- A fresh, READY adapter over a fresh default world (optionally edited)
local function Fresh(edit)
    local world = Fake.DefaultWorld()
    if edit then edit(world) end
    local fake = Install(world)
    LoadAdapter()
    Fire("PLAYER_LOGIN")
    Settle()
    return fake, world
end

local function GlobalKeys()
    local keys = {}
    for k in pairs(_G) do keys[k] = true end
    return keys
end
local function NewGlobals(before)
    local added = {}
    for k in pairs(_G) do if not before[k] then added[#added + 1] = tostring(k) end end
    table.sort(added)
    return added
end

local function Contains(list, value)
    for _, v in ipairs(list or {}) do if v == value then return true end end
    return false
end

-- ===========================================================================
-- A. No Questie at all
-- ===========================================================================

do
    local before = GlobalKeys()
    LoadAdapter()
    Fire("PLAYER_LOGIN")
    CHECK(#NewGlobals(before) == 0, "A: loading the adapter defines no global", table.concat(NewGlobals(before), ","))
    CHECK(Q.Questie == A and type(A) == "table", "A: Q.Questie is published")
    local state, reason = A.State()
    CHECK(state == "ABSENT", "A: State ABSENT without Questie", state)
    CHECK(type(reason) == "string", "A: State gives a reason")
    local view, err = A.ZoneView(3483)
    CHECK(view == nil and err == "ABSENT", "A: ZoneView answers nil, ABSENT", err)
    CHECK(#A.ZoneMenu() == 0, "A: empty zone menu")
    CHECK(#A.ContinentZones(1945) == 0, "A: no continent zones")
    CHECK(A.ZoneForPlayer() == nil, "A: no player zone")
    local areaId, kind = A.ZoneForMap(1944)
    CHECK(areaId == nil and kind == nil, "A: zone maps resolve to nothing")
    areaId, kind = A.ZoneForMap(1945)
    CHECK(areaId == nil and kind == "CONTINENT", "A: a continent is still a continent")
    CHECK(A.Finisher(9003) == nil and A.QuestDetail(9003) == nil, "A: no quest reads")
    CHECK(A.IsQuestieDrawing(9005) == false, "A: Questie draws nothing")
    CHECK(#A.PinsFor(3483, 1944) == 0, "A: no pins")
    CHECK(A.ZoneSummary(3483) == nil, "A: no summary")
    A.Bump("test")
    CHECK(#timers == 0, "A: a bump without Questie schedules nothing")
    A.RequestSummaries({ 3483 }, function() end)
    Settle()
    CHECK(A.WaypointPath() == "PRINT", "A: waypoint path PRINT")
    CHECK(A.Waypoint({ title = "Somewhere", x = 10, y = 20, zoneName = "Nowhere" }) == "PRINT", "A: waypoint prints")
    CHECK((LastPrint() or ""):find("Somewhere", 1, true) and LastPrint():find("10.0, 20.0", 1, true),
        "A: the printed waypoint names the place", LastPrint())
    local lines = A.StatusLines()
    CHECK(type(lines) == "table" and (lines[1] or ""):find("ABSENT", 1, true), "A: status says ABSENT", lines[1])
    CHECK(#caughtErrors == 0, "A: no errors", caughtErrors[1])
end

-- ===========================================================================
-- B. LOADING, and the ready callback deferred a frame
-- ===========================================================================

local fake, world
do
    world = Fake.DefaultWorld()
    world.ready = false
    world.filler = 1000                           -- 1033 pointers: three sweep chunks
    world.uiMaps[7777] = { name = "Testland", mapType = 2, parent = 946 }
    world.quests[9005].specialFlags = 2           -- the event bit, not the repeatable one
    world.quests[9005].questFlags = 8192 + 8      -- weekly-ish bits, not the daily one
    fake = Install(world)
    LoadAdapter()
    Q.Completion = Stub
    Fire("PLAYER_LOGIN")
    CHECK(A.State() == "LOADING", "B: State LOADING before Questie is ready", A.State())
    CHECK(fake.PendingReadyCallbacks() == 1, "B: one ready callback queued with Questie")
    CHECK(fake.UpdateCallbackCount() == 1, "B: one quest-update callback registered")
    A.Init()
    CHECK(fake.PendingReadyCallbacks() == 1 and fake.UpdateCallbackCount() == 1, "B: Init is idempotent")
    local view, err = A.ZoneView(3483)
    CHECK(view == nil and err == "LOADING", "B: ZoneView answers nil, LOADING", err)
    local queries = (fake.calls.QueryQuest or 0) + (fake.calls.IsDoableVerbose or 0) + (fake.calls.QueryQuestSingle or 0)
    fake.SetReady()
    local after = (fake.calls.QueryQuest or 0) + (fake.calls.IsDoableVerbose or 0) + (fake.calls.QueryQuestSingle or 0)
    CHECK(after == queries, "B: the ready callback reads nothing (it runs inside Questie's coroutine)")
    CHECK(#fake.callbackErrors == 0, "B: the ready callback did not error", fake.callbackErrors[1])
    CHECK(A.State() == "LOADING", "B: still LOADING until the next frame", A.State())
    Frame()
    CHECK(A.State() == "READY", "B: READY one frame later", A.State())
end

-- ===========================================================================
-- F (part 1). The reverse exclusive index starts right after ready
-- ===========================================================================

local reverseGenerationBefore
do
    local done, total, ticks, finished = A._ReverseProgress()
    CHECK(done == 0 and total == 1033 and ticks == 0 and finished == false,
        "F: the sweep is queued, not run, at ready", string.format("%s/%s ticks %s", done, total, ticks))
    local char = A.Character()
    CHECK(#char.exclusivePeers(9014) == 0, "F: before the sweep, 9014 knows only its own (empty) list")
    CHECK(Contains(char.exclusivePeers(9013), 9014) and Contains(char.exclusivePeers(9013), 9012),
        "F: 9013's forward list is there from the start")
    Frame()
    done, total, ticks = A._ReverseProgress()
    CHECK(done == 400 and ticks == 1, "F: one chunk of 400 per frame", done)
    Frame()
    done, total, ticks = A._ReverseProgress()
    CHECK(done == 800 and ticks == 2, "F: second chunk", done)
    reverseGenerationBefore = A.generation
    Frame()
    done, total, ticks, finished = A._ReverseProgress()
    CHECK(finished and ticks == 3 and done == 1033, "F: finished in three chunks", tostring(ticks))
    CHECK(Contains(A.Character().exclusivePeers(9014), 9013), "F: after the sweep 9014 knows 9013 (reverse index)")
    CHECK(#A.Character().exclusivePeers(9014) == 1, "F: and nothing else")
end

-- ===========================================================================
-- C. Zones: uiMap -> areaId and back
-- ===========================================================================

do
    local function Resolves(uiMapId, wantArea, wantKind, label)
        local areaId, kind = A.ZoneForMap(uiMapId)
        CHECK(areaId == wantArea and kind == wantKind, "C: " .. label,
            tostring(areaId) .. " " .. tostring(kind))
    end
    Resolves(1944, 3483, "ZONE", "Hellfire's map is Hellfire")
    Resolves(1952, 3519, "ZONE", "Terokkar's map is Terokkar")
    local calls = fake.calls.GetAreaIdByUiMapId or 0
    Resolves(9999, nil, nil, "an unmatched map (ZoneDB throws) resolves to nothing")
    CHECK((fake.calls.GetAreaIdByUiMapId or 0) == calls + 1, "C: ...and ZoneDB really was asked")
    CHECK(A._LastError() == nil, "C: ...and its throw is an answer, not an error", A._LastError())
    Resolves(9536, 3483, "ZONE", "a subzone map folds to its parent zone")
    Resolves(9535, 3483, "ZONE", "the orphan subzone 3535 folds into Hellfire")
    Resolves(347, 3563, "DUNGEON", "Ramparts maps to the Hellfire Citadel group")
    Resolves(261, 3563, "DUNGEON", "Blood Furnace maps to the Hellfire Citadel group")
    Resolves(272, 3917, "DUNGEON", "Mana-Tombs maps to the Auchindoun group")
    Resolves(262, 3716, "DUNGEON", "the Underbog keeps its own key (Questie files its quests there)")
    Resolves(1945, nil, "CONTINENT", "Outland is a continent")
    Resolves(1414, nil, "CONTINENT", "Kalimdor is a continent")
    Resolves(1415, nil, "CONTINENT", "Eastern Kingdoms is a continent")
    Resolves(947, nil, "CONTINENT", "Azeroth is a continent-level map")
    Resolves(7777, nil, "CONTINENT", "a map the client calls a continent is one")
    Resolves(1941, 3430, "ZONE", "UI MAP 1941 is Eversong (area 3430), not area 1941")
    Resolves("x", nil, nil, "a non-number resolves to nothing")
    CHECK(A.ZoneName(1941) == "Caverns of Time", "C: AREA 1941 is the Caverns of Time", A.ZoneName(1941))

    CHECK(A.UiMapForArea(3483) == 1944, "C: Hellfire's uiMap")
    CHECK(A.UiMapForArea(3563) == 347, "C: a group key answers its first wing's map", tostring(A.UiMapForArea(3563)))
    CHECK(A.UiMapForArea(3917) == 272, "C: Auchindoun answers Mana-Tombs' map", tostring(A.UiMapForArea(3917)))
    CHECK(A.UiMapForArea(3535) == nil, "C: the orphan subzone has no map")
    CHECK(A.UiMapForArea(1941) == nil, "C: a group with no mapped wing has no map")

    local areaId, name = A.ZoneForPlayer()
    CHECK(areaId == 3483 and name == "Hellfire Peninsula", "C: the player stands in Hellfire", tostring(areaId))
    world.player.uiMapId = 1945
    world.player.zoneIdOverride = 3536
    areaId = A.ZoneForPlayer()
    CHECK(areaId == 3483, "C: on a continent map, Questie's own zone answer (a subzone, folded)", tostring(areaId))
    world.player.zoneIdOverride = nil
    world.player.uiMapId = 9999
    local before = #caughtErrors
    areaId = A.ZoneForPlayer()
    CHECK(areaId == nil and #caughtErrors == before, "C: Questie's GetCurrentZoneId throwing is contained")
    world.player.uiMapId = 1944

    CHECK(A.ZoneName(3483) == "Hellfire Peninsula", "C: names from the client")
    CHECK(A.ZoneName(3714) == "The Shattered Halls", "C: a dungeon the client cannot name", A.ZoneName(3714))
    CHECK(A.ZoneName(3999) == "Fallback Vale", "C: Questie's lookup as the last resort", A.ZoneName(3999))
    CHECK(A.ZoneName(4242) == "Zone 4242", "C: unknown areas get a plain label", A.ZoneName(4242))
    CHECK(A.ZoneName(-141) == "Paladin", "C: a class sort key is named", A.ZoneName(-141))
end

-- ===========================================================================
-- D. The zone menu and continent lists
-- ===========================================================================

do
    local menu = A.ZoneMenu()
    local keys = {}
    for i, cat in ipairs(menu) do keys[i] = cat.key end
    CHECK(table.concat(keys, ",") == "1,2,3,9,11", "D: categories EK, Kalimdor, Outland, Dungeons, Class",
        table.concat(keys, ","))
    local byKey = {}
    for _, cat in ipairs(menu) do byKey[cat.key] = cat end
    local function Names(cat)
        local out = {}
        for i, zone in ipairs(cat and cat.zones or {}) do out[i] = zone.name end
        return table.concat(out, "|")
    end
    CHECK(byKey[1] and byKey[1].text == "Eastern Kingdoms", "D: continent names from the Journey")
    CHECK(Names(byKey[1]) == "Elwynn Forest", "D: EK lists only zones with quests", Names(byKey[1]))
    CHECK(Names(byKey[2]) == "Azuremyst Isle", "D: Kalimdor", Names(byKey[2]))
    CHECK(Names(byKey[3]) == "Hellfire Peninsula|Terokkar Forest", "D: Outland sorted by name, Zangarmarsh (no quests) left out",
        Names(byKey[3]))
    CHECK(Names(byKey[9]) == "Auchindoun|Hellfire Citadel|The Underbog",
        "D: dungeons sorted, a folded wing (Mana-Tombs) listed as its group", Names(byKey[9]))
    CHECK(byKey[3] and byKey[3].zones[1].areaId == 3483, "D: zones carry their areaId")
    CHECK(byKey[11] and byKey[11].text == "Paladin" and byKey[11].zones[1].areaId == -141,
        "D: the class entry is the class sort key")

    local zones = A.ContinentZones(1945)
    local names = {}
    for i, zone in ipairs(zones) do names[i] = zone.name .. "@" .. tostring(zone.uiMapId) end
    CHECK(table.concat(names, "|") == "Hellfire Peninsula@1944|Terokkar Forest@1952",
        "D: Outland's children with quests, with their maps", table.concat(names, "|"))
    zones = A.ContinentZones(1415)
    CHECK(#zones == 1 and zones[1].areaId == 12, "D: Eastern Kingdoms' children with quests")
    zones = A.ContinentZones(947)
    names = {}
    for i, zone in ipairs(zones) do names[i] = zone.name end
    CHECK(table.concat(names, "|") == "Azuremyst Isle|Elwynn Forest",
        "D: a map whose children are continents falls back to the Journey categories", table.concat(names, "|"))
end

-- ===========================================================================
-- E. Facts
-- ===========================================================================

local factsById = {}
do
    local facts = A._Facts(3483)
    CHECK(type(facts) == "table", "E: facts build for Hellfire")
    for _, fact in ipairs(facts or {}) do factsById[fact.id] = fact end
    CHECK(#(facts or {}) == 25, "E: 21 zone quests + 4 that start here", #(facts or {}))
    local f = factsById
    CHECK(f[77777] == nil, "E: zoneMap's junk id (not a quest) is guarded out")
    CHECK(f[9024] == nil, "E: the Horde quest never reached this character's zoneMap")
    CHECK(f[9015] and f[9015].layer == "ZONE", "E: a quest filed under 3535 is a Hellfire quest")
    CHECK(fake.returnTextMissing == 0, "E: IsDoableVerbose always called with returnText")
    CHECK(f[9001] and f[9001].state == "COMPLETED", "E: state names come through (COMPLETED)", f[9001] and f[9001].state)
    CHECK(f[9003] and f[9003].state == "QUEST_LOG", "E: QUEST_LOG")
    CHECK(f[9004] and f[9004].state == "NO_PREQUESTSINGLE", "E: NO_PREQUESTSINGLE")
    CHECK(f[9005] and f[9005].state == "AVAILABLE", "E: AVAILABLE")
    CHECK(f[9007] and f[9007].state == "LEVEL_TOO_LOW", "E: LEVEL_TOO_LOW")
    CHECK(f[9011] and f[9011].state == "MISSING_REPUTATION", "E: MISSING_REPUTATION")
    CHECK(f[9019] and f[9019].state == "EVENT_INACTIVE", "E: EVENT_INACTIVE")
    CHECK(f[9009] and f[9009].state == "EXCEED_REPUTATION", "E: EXCEED_REPUTATION")
    CHECK(f[9008] and f[9008].repeatable == true and f[9008].daily == true, "E: specialFlags 1 / questFlags 4104 -> repeatable daily")
    CHECK(f[9005] and f[9005].repeatable == false and f[9005].daily == false, "E: specialFlags 2 / questFlags 8200 -> neither")
    CHECK(f[9018] and f[9018].hiddenOnMap == true and f[9005].hiddenOnMap == false, "E: HIDE_ON_MAP")
    CHECK(f[9019] and f[9019].event == true and f[9005].event == false, "E: event quest")
    CHECK(f[9009] and f[9009].oneWayRep == true and f[9010].oneWayRep == false, "E: one-way reputation")
    CHECK(f[9009] and f[9009].maxRep and f[9009].maxRep[1] == 942 and f[9009].maxRep[2] == 9000, "E: maxRep pair")
    CHECK(f[9010] and f[9010].minRep and f[9010].minRep[1] == 932, "E: minRep pair")
    CHECK(f[9005] and f[9005].minRep == nil and f[9005].skill == nil, "E: unset pairs read nil")
    CHECK(f[9004] and f[9004].nextInChain == 0 and f[9001].nextInChain == 9002, "E: unset numbers read 0")
    CHECK(f[9004] and f[9004].preSingle and f[9004].preSingle[1] == 9003, "E: preQuestSingle")
    CHECK(f[9005] and f[9005].preSingle == nil and f[9005].exclusiveTo == nil, "E: empty lists read nil")
    CHECK(f[9013] and #f[9013].exclusiveTo == 2, "E: exclusiveTo")
    CHECK(f[9020] and f[9020].breadcrumbFor == 9003, "E: breadcrumbForQuestId")
    CHECK(f[9021] and f[9021].requiredMaxLevel == 60, "E: requiredMaxLevel")
    local s = f[9001] and f[9001].starters[1]
    CHECK(s and s.kind == "npc" and s.name == "Watch Commander Relthorn" and s.x == 87.4 and s.y == 50.7
        and s.areaId == 3483 and s.uiMapId == 1944, "E: an NPC starter with name, coordinates and map")
    CHECK(f[9001] and f[9001].startsHere == true and f[9001].startZoneName == nil, "E: starts here")
    s = f[9015] and f[9015].starters[1]
    CHECK(s and s.areaId == 3483 and s.rawAreaId == 3536 and s.uiMapId == 1944 and s.x == 58.0,
        "E: a subzone spawn is drawn on its parent's map")
    CHECK(f[9015] and f[9015].startsHere == true, "E: ...and counts as starting here")
    CHECK(f[9023] and f[9023].startsHere == false and f[9023].startZoneName == "Terokkar Forest",
        "E: a Hellfire quest whose giver stands in Terokkar")
    s = f[9022] and f[9022].starters[1]
    CHECK(s and s.kind == "item" and s.name == "Glowing Fel Orb" and s.x == nil, "E: item starters carry no coordinates")
    s = f[9020] and f[9020].starters[1]
    CHECK(s and s.kind == "object" and s.name == "Wanted Poster", "E: object starters")
    s = f[9017] and f[9017].starters[1]
    CHECK(s and s.areaId == 3483 and s.x == 46.0 and s.y == 51.8 and s.dungeonAreaId == 3713,
        "E: the dungeon sentinel becomes the instance entrance")
    CHECK(f[9017] and f[9017].layer == "EXTRA" and f[9017].startsHere == true and f[9017].tag == "DUNGEON",
        "E: a dungeon quest whose giver is inside starts here, in the EXTRA layer")
    CHECK(f[9016] and f[9016].layer == "EXTRA" and f[9016].tag == "DUNGEON", "E: a dungeon quest whose giver stands here")
    CHECK(f[9025] and f[9025].layer == "EXTRA", "E: the class quest whose giver stands here")
    CHECK(f[9026] and f[9026].layer == "EXTRA" and f[9026].skill and f[9026].skill[1] == 186,
        "E: the profession quest (player has Mining)")
    CHECK(f[9033] and #f[9033].starters == 8, "E: a giver's spawns capped at eight", f[9033] and #f[9033].starters)
    CHECK(f[9001] and f[9001].finishers[1].name == "Force Commander Danath", "E: finishers")
    CHECK(f[9003] and f[9003].objectivesText and f[9003].objectivesText[1] == "Report to Force Commander Danath.",
        "E: objectivesText")
    CHECK(f[9005] and f[9005].tag == nil and f[9005].layer == "ZONE", "E: an ordinary quest has no tag")
    CHECK(f[9005] and f[9005].questLevel == 61 and f[9005].requiredLevel == 59, "E: levels")
    CHECK(f[9005] and f[9005].name == "Know Your Enemy", "E: names")

    local terokkar = A._Facts(3519)
    local ids = {}
    for _, fact in ipairs(terokkar or {}) do ids[#ids + 1] = fact.id .. ":" .. fact.layer end
    CHECK(table.concat(ids, ",") == "9014:ZONE,9032:ZONE,9029:EXTRA,9030:EXTRA",
        "E: Terokkar: its own two, and the Auchindoun quests whose giver stands there", table.concat(ids, ","))
    local auch = A._Facts(3917)
    ids = {}
    for _, fact in ipairs(auch or {}) do ids[#ids + 1] = fact.id .. ":" .. fact.layer .. ":" .. tostring(fact.startsHere) end
    CHECK(table.concat(ids, ",") == "9029:ZONE:false,9030:ZONE:false",
        "E: the Auchindoun group reads its wing (Mana-Tombs) too", table.concat(ids, ","))
    local zang = A._Facts(3521)
    CHECK(#(zang or {}) == 1 and zang[1].id == 9031 and zang[1].layer == "EXTRA",
        "E: the Underbog quest starts at its entrance in Zangarmarsh")
end

-- ===========================================================================
-- F (part 2). The index's generation step
-- ===========================================================================

do
    local listened = 0
    A.AddListener(function() listened = listened + 1 end)
    Advance(300)
    CHECK(A.generation == reverseGenerationBefore + 1, "F: ready and the finished sweep land as one generation step",
        A.generation .. " vs " .. reverseGenerationBefore)
    CHECK(listened == 1, "F: one listener call for the burst", listened)
    local lines = A.StatusLines()
    local joined = table.concat(lines, "\n")
    CHECK(joined:find("exclusive index", 1, true) and joined:find("complete", 1, true),
        "F: status reports the finished sweep", joined)
end

-- ===========================================================================
-- G. The character
-- ===========================================================================

do
    local char = A.Character()
    CHECK(char.level == 62, "G: level", char.level)
    CHECK(char.isComplete(9001) == true and char.isComplete(9005) == false, "G: isComplete")
    fake.ReassignComplete()
    Questie.db.char.complete[9005] = true
    CHECK(char.isComplete(9005) == true, "G: isComplete reads the REASSIGNED table")
    Questie.db.char.complete[9005] = nil
    Questie.db.char.complete[9008] = false
    CHECK(char.isComplete(9008) == false, "G: a repeatable stored as false is not complete")
    Questie.db.char.complete[9008] = nil
    CHECK(char.isInLog(9003) == true and char.isInLog(9005) == false, "G: isInLog through C_QuestLog")
    local onQuest = C_QuestLog.IsOnQuest
    C_QuestLog.IsOnQuest = nil
    fake.SetInLog(9006, true)
    CHECK(char.isInLog(9006) == true and char.isInLog(9003) == true, "G: isInLog falls back to Questie's (reassigned) log")
    fake.SetInLog(9006, false)
    C_QuestLog.IsOnQuest = onQuest
    A.SetLogEntries({
        { isHeader = true, title = "Hellfire Peninsula" },
        { isHeader = false, questID = 9003, isComplete = true, isFailed = false, objectives = {} },
        { isHeader = false, questID = 0, title = "No id" },
    })
    -- Ready comes off the CLIENT's log first: the window's scan exists only
    -- while the window is open, and the map drawer asks with it shut
    local info = char.logInfo(9003)
    CHECK(info and info.complete == false, "G: logInfo reads the client's log, not a stale window scan")
    world.logComplete = { [9003] = 1 }
    info = char.logInfo(9003)
    CHECK(info and info.complete == true and info.failed == false, "G: a quest the client calls complete is ready")
    world.logComplete = { [9003] = -1 }
    info = char.logInfo(9003)
    CHECK(info and info.failed == true and info.complete == false, "G: ...and -1 is failed, not done")
    world.logComplete = nil
    local byId = GetQuestLogIndexByID
    GetQuestLogIndexByID = nil
    info = char.logInfo(9003)
    CHECK(info and info.complete == true, "G: without the client call, the window's scan answers")
    GetQuestLogIndexByID = byId
    CHECK(char.logInfo(9005) == nil, "G: logInfo nil for a quest in neither")
    CHECK(Contains(char.exclusiveTo(9013), 9014) and Contains(char.exclusiveTo(9013), 9012),
        "G: exclusiveTo is the quest's own list")
    CHECK(#char.exclusiveTo(9014) == 0, "G: ...and the reverse index never adds to it (9014 lists nothing)")
    CHECK(char.isGone(9020) == true and char.isGone(9021) == true,
        "G: isGone: a skipped breadcrumb and an outlevelled quest are gone for good")
    CHECK(char.isGone(9004) == false and char.isGone(9007) == false and char.isGone(9005) == false,
        "G: ...a quest behind a prerequisite or a level is not")
    CHECK(char.isGone(77777) == false, "G: ...nor is a non-quest")
    CHECK(char.repValue(932) == 3500 and char.repValue(934) == -3500, "G: repValue is the bar value")
    CHECK(char.repValue(99999) == nil, "G: an unknown faction's rep is nil")
    CHECK(char.factionName(932) == "The Aldor", "G: factionName")
    CHECK(char.skillName(186) == "Mining" and char.skillName(99999) == nil,
        "G: skillName through QuestieProfessions (nil for a skill it does not name)", tostring(char.skillName(186)))
    CHECK(char.questName(9014) == "Choose: the Staff", "G: questName")
    CHECK(char.questZoneName(9014) == "Terokkar Forest", "G: questZoneName", char.questZoneName(9014))
    CHECK(char.questZoneName(9015) == "Hellfire Peninsula", "G: questZoneName folds 3535")
    CHECK(char.questZoneName(9025) == "Paladin", "G: questZoneName of a class quest")
    CHECK(char.rivals[932] == 934 and char.rivals[934] == 932, "G: Aldor and Scryers are rivals")
    CHECK(Contains(char.exclusivePeers(9013), 9012) and Contains(char.exclusivePeers(9013), 9014), "G: exclusivePeers")
    CommanderQuestLogChar.Ignored[9006] = true
    CHECK(A.Character().ignored[9006] == true, "G: ignored is the per-character list")
    CommanderQuestLogChar.Ignored[9006] = nil
    local saved = CommanderQuestLogChar
    CommanderQuestLogChar = nil
    CHECK(type(A.Character().ignored) == "table", "G: no per-character table yet is an empty list")
    CommanderQuestLogChar = saved
    CommanderQuestLogDB.CountRival = true
    char = A.Character()
    CHECK(char.opts.countRival == true and char.opts.countOptional == false and char.opts.countExtras == false,
        "G: opts from the settings")
    CommanderQuestLogDB.CountRival = nil
end

-- ===========================================================================
-- H. One generation step and one listener call per burst
-- ===========================================================================

do
    Settle()
    local calls = 0
    local function Listener() calls = calls + 1 end
    A.AddListener(Listener)
    A.AddListener(Listener)
    for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "UPDATE_FACTION",
                             "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP" }) do
        CHECK(registeredEvents[event], "H: registers " .. event)
    end
    local gen = A.generation
    Fire("QUEST_TURNED_IN", 9005)
    Fire("QUEST_ACCEPTED", 1, 9006)
    Fire("UPDATE_FACTION")
    fake.FireQuestUpdate(9003, 2, 1)
    A.Bump("ignore")
    CHECK(A.generation == gen and calls == 0, "H: nothing moves inside the burst")
    Advance(200)
    CHECK(A.generation == gen and calls == 0, "H: still nothing at 0.2 s")
    Advance(100)
    CHECK(A.generation == gen + 1, "H: one generation step after 0.25 s", A.generation - gen)
    CHECK(calls == 1, "H: exactly one listener call (and a listener added twice is called once)", calls)
    Advance(1000)
    CHECK(calls == 1, "H: and no more after it")
    for _, event in ipairs({ "QUEST_TURNED_IN", "QUEST_ACCEPTED", "QUEST_REMOVED", "UPDATE_FACTION",
                             "SKILL_LINES_CHANGED", "PLAYER_LEVEL_UP" }) do
        local step = A.generation
        Fire(event)
        Advance(300)
        CHECK(A.generation == step + 1, "H: " .. event .. " alone is a bump")
    end
    local step, heard = A.generation, calls
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    Advance(300)
    CHECK(A.generation == step + 1 and calls == heard + 1, "H: a settings change is a bump")
    local joined = table.concat(A.StatusLines(), "\n")
    CHECK(joined:find("settings", 1, true), "H: status names the last bump's reason", joined)
end

-- ===========================================================================
-- I. View cache: by generation, at most three, summaries kept for all
-- ===========================================================================

do
    Settle()
    local builds = stubBuilds
    local v1 = A.ZoneView(3483)
    CHECK(type(v1) == "table" and #v1.entries == 25, "I: Hellfire's view (stub engine)")
    CHECK(rawequal(A.ZoneView(3483), v1) and stubBuilds == builds + 1, "I: a second ask is a cache hit")
    local summary = A.ZoneSummary(3483)
    CHECK(summary and summary.counted == 21 and summary.done == 2 and summary.generation == A.generation,
        "I: the summary is recorded with its generation", summary and summary.counted)
    A.Bump("test")
    Advance(300)
    CHECK(A.ZoneSummary(3483) == nil, "I: a new generation leaves no current summary")
    CHECK(A.ZoneSummary(3483, true) ~= nil, "I: the stale one is still there when asked for")
    local v2 = A.ZoneView(3483)
    CHECK(v2 and not rawequal(v1, v2) and stubBuilds == builds + 2, "I: and the view is rebuilt")
    A.ZoneView(3519)
    A.ZoneView(3563)
    A.ZoneView(3917)
    local info = A._CacheInfo()
    CHECK(info.views == 3 and table.concat(info.order, ",") == "3519,3563,3917",
        "I: at most three views, least recent dropped", table.concat(info.order, ","))
    CHECK(A.ZoneSummary(3483) ~= nil, "I: an evicted zone keeps its summary")
    builds = stubBuilds
    A.ZoneView(3483)
    CHECK(stubBuilds == builds + 1, "I: an evicted zone is rebuilt on ask")
    A.ZoneView(3563)
    info = A._CacheInfo()
    CHECK(table.concat(info.order, ",") == "3917,3483,3563", "I: a hit moves to the front", table.concat(info.order, ","))
    local view, err = A.ZoneView(3430)
    CHECK(view == nil and err == "NO_QUESTS", "I: a zone with nothing filed and no giver: NO_QUESTS", err)
    CHECK(A.ZoneSummary(3430) and A.ZoneSummary(3430).counted == 0, "I: ...with an empty summary")
    view = A.ZoneView(3521)
    CHECK(view and #view.entries == 1, "I: a zone with only quests that start there still has a view")
    view, err = A.ZoneView("x")
    CHECK(view == nil and err == "NO_ZONE", "I: a non-number zone", err)

    -- The engine missing or failing degrades, never errors
    Q.Completion = nil
    A.Bump("test")
    Advance(300)
    view, err = A.ZoneView(3483)
    CHECK(view == nil and err == "ENGINE", "I: no engine: nil, ENGINE", err)
    Q.Completion = { BuildZone = function() error("boom") end }
    view, err = A.ZoneView(3483)
    CHECK(view == nil and err == "ENGINE_ERROR", "I: an engine error: nil, ENGINE_ERROR", err)
    CHECK((A._LastError() or ""):find("boom", 1, true), "I: ...remembered for /cql status", A._LastError())
    Q.Completion = Stub

    -- A change in which logged quests are ready is a bump, but only then
    A.ZoneView(3483)
    local gen = A.generation
    A.SetLogEntries({ { isHeader = false, questID = 9003, isComplete = false } })
    Advance(300)
    CHECK(A.generation == gen + 1, "I: a logged quest turning ready/unready bumps")
    A.ZoneView(3483)
    A.SetLogEntries({ { isHeader = false, questID = 9003, isComplete = false, objectives = { { text = "1/2" } } } })
    Advance(300)
    CHECK(A.generation == gen + 1, "I: the same log again does not")
end

-- ===========================================================================
-- J. Background summaries
-- ===========================================================================

do
    A.Bump("test")
    Advance(300)
    Settle()
    local seen = {}
    local calls = 0
    local function OnEach(areaId, summary)
        calls = calls + 1
        seen[areaId] = summary
    end
    local views = A._CacheInfo().views
    local builds = stubBuilds
    A.RequestSummaries({ 3483, 3519, 3563 }, OnEach)
    CHECK(calls == 0, "J: nothing computed synchronously")
    Advance(50)
    CHECK(calls == 1 and seen[3483], "J: one zone per tick", calls)
    Advance(50)
    CHECK(calls == 2, "J: second tick", calls)
    Advance(50)
    CHECK(calls == 3 and seen[3563], "J: third tick", calls)
    Advance(200)
    CHECK(calls == 3, "J: then the job is done")
    CHECK(stubBuilds == builds + 3, "J: three engine builds", stubBuilds - builds)
    CHECK(A._CacheInfo().views == views, "J: background summaries do not evict the window's views")
    CHECK(seen[3519] and seen[3519].counted == 2 and seen[3519].generation == A.generation, "J: summaries carry counts")
    builds = stubBuilds
    A.RequestSummaries({ 3483, 3519, 3563 }, OnEach)
    Advance(50)
    CHECK(calls == 6 and stubBuilds == builds, "J: zones already current are reported without rebuilding", calls)

    -- A bump mid-job does NOT rewind it. It used to, and a zone menu's job
    -- (whose menu had long closed) then rebuilt whole zones every tick for as
    -- long as reputation kills kept bumping. It carries on instead, working
    -- the zones it has left against the new generation.
    A.Bump("test")
    Advance(300)
    calls = 0
    local all = { 3483, 3519, 3563, 3917, 3716, 12, 3524, 3521, 3430 }
    builds = stubBuilds
    A.RequestSummaries(all, OnEach)
    Advance(60)
    local firstGeneration = seen[3483] and seen[3483].generation
    A.Bump("mid-job")
    Settle()
    CHECK(calls == #all, "J: a mid-job bump does not restart the job: each zone reported once", calls)
    CHECK(stubBuilds - builds <= #all, "J: ...and no zone is built twice", stubBuilds - builds)
    CHECK(seen[3430] and seen[3430].generation == A.generation and firstGeneration == A.generation - 1,
        "J: the zones after the bump carry the new generation, the one before it the old")
    CHECK(A.ZoneSummary(3483) == nil and A.ZoneSummary(3483, true) ~= nil,
        "J: ...so it reads as stale, and its last figure is still there for a label")
    CHECK(seen[3430] and seen[3430].counted == 0, "J: a zone with no quests reports an empty summary")

    -- A steady stream of bumps (every 0.4 s, a dungeon's reputation kills):
    -- the job still finishes once, at the cost of its own zones and no more
    A.Bump("test")
    Advance(300)
    calls = 0
    builds = stubBuilds
    A.RequestSummaries(all, OnEach)
    for _ = 1, 25 do
        Advance(400)
        A.Bump("kill")
    end
    Settle()
    CHECK(calls == #all, "J: under a stream of bumps the job finishes once", calls)
    CHECK(stubBuilds - builds <= #all, "J: ...without rebuilding what it already did", stubBuilds - builds)

    -- Replaced, not queued: the same callback twice is one job
    A.Bump("test")
    Advance(300)
    calls = 0
    A.RequestSummaries({ 3483 }, OnEach)
    A.RequestSummaries({ 3519 }, OnEach)
    Settle()
    CHECK(calls == 1 and seen[3519].generation == A.generation, "J: a repeat request replaces the job", calls)
end

-- ===========================================================================
-- K. Waypoints: Commander Orders, else a /way line in chat; routes; entrances
-- ===========================================================================

-- A recording Commander Orders shaped like its public table: every call
-- answers rather than raising, Add -> uid | nil, reason, AddRoute -> id
local ordersLog = { adds = {}, routes = {}, resolvers = {}, available = true, why = nil }
local function FakeOrders()
    local L = ordersLog
    return {
        IsAvailable = function()
            if L.available then return true end
            return false, L.why
        end,
        Add = function(spec)
            L.adds[#L.adds + 1] = spec
            if not L.available then return nil, L.why end
            return "w" .. #L.adds, nil, "added"
        end,
        AddRoute = function(spec)
            L.routes[#L.routes + 1] = spec
            if not L.available then return nil, L.why end
            return "r" .. #L.routes
        end,
        RegisterResolver = function(kind, fn)
            L.resolvers[#L.resolvers + 1] = { kind = kind, fn = fn }
            return true
        end,
        Describe = function() return "Commander Orders arrow" end,
    }
end

do
    Fresh()
    Q.Completion = Stub
    local L = ordersLog
    CommanderOrders, CommanderOrders_IssueOrder, TomTom = nil, nil, nil
    -- Neither TomTom nor the legacy single-slot order is ever called again
    TomTom = { AddWaypoint = function() error("TomTom must not be called") end }
    CommanderOrders_IssueOrder = function() error("the legacy order must not be called") end
    local target = { title = "Know Your Enemy", areaId = 3483, x = 61.8, y = 60.6, questId = 9005 }

    CHECK(A.WaypointPath() == "PRINT", "K: no Commander Orders: the chat frame (a TomTom is ignored)")
    CHECK(A.Waypoint(target) == "PRINT", "K: Waypoint prints without Orders")
    CHECK(LastPrint() == "Commander Quest Log: |cffffd100Know Your Enemy|r \226\128\148 Hellfire Peninsula 61.8, 60.6"
        .. "   /way #1944 61.80 60.60 Know Your Enemy", "K: the printed line ends in the /way line", LastPrint())
    CHECK(A.Waypoint({ title = "Fel Spirits", areaId = 3483 }) == "PRINT"
        and LastPrint() == "Commander Quest Log: |cffffd100Fel Spirits|r \226\128\148 Hellfire Peninsula",
        "K: no coordinates: the zone alone", LastPrint())
    CHECK(A.Waypoint(nil) == nil, "K: no target, no path")

    CommanderOrders = FakeOrders()
    CHECK(A.WaypointPath() == "ORDERS", "K: Orders loaded and on")
    CHECK(A.Waypoint(target) == "ORDERS", "K: Waypoint goes to Commander Orders")
    local spec = L.adds[#L.adds]
    CHECK(spec and spec.map == 1944 and NEAR(spec.x, 0.618) and NEAR(spec.y, 0.606),
        "K: Orders gets the uiMap and 0..1 coordinates", spec and spec.map)
    CHECK(spec and spec.source == "QuestLog" and spec.key == "quest:9005" and spec.title == "Know Your Enemy"
        and spec.setArrow == true and spec.icon == "QUEST",
        "K: the waypoint is owned by its quest (one per quest) and takes the arrow")
    CHECK(spec and spec.alternatives == nil, "K: a one-spawn giver carries no alternatives")
    CHECK(spec and spec.persistent == nil and spec.temporary == nil,
        "K: persistence is left to Orders' consumer default (session only)")

    -- Every spawn of the giver rides along as alternatives
    local view = A.ZoneView(3483)
    local sentry = A.BestStarter(view.byId[9033], 3483)
    CHECK(sentry and type(sentry.spawns) == "table" and #sentry.spawns == 8,
        "K: BestStarter carries every spawn of its giver", sentry and sentry.spawns and #sentry.spawns)
    CHECK(A.BestStarter(view.byId[9005], 3483).spawns == nil, "K: ...and none for a one-spawn giver")
    A.Waypoint({ title = "Sentry Duty", areaId = sentry.areaId, uiMapId = sentry.uiMapId, x = sentry.x, y = sentry.y,
        questId = 9033, spawns = sentry.spawns })
    spec = L.adds[#L.adds]
    local alts = spec and spec.alternatives
    CHECK(alts and #alts == 8 and alts[1].map == 1944 and NEAR(alts[1].x, 0.20) and NEAR(alts[1].y, 0.20)
        and NEAR(alts[8].x, 0.55) and NEAR(alts[8].y, 0.25), "K: the spawns become 0..1 alternatives on their uiMap",
        alts and #alts)
    CHECK(#A.SpawnsOf(view.byId[9033].starters, { kind = "npc", id = 20016 }) == 8
        and A.SpawnsOf(view.byId[9033].starters, { kind = "npc", id = 20003 }) == nil
        and A.SpawnsOf(nil, {}) == nil, "K: SpawnsOf matches one giver by kind and id")

    CHECK(A.Waypoint({ title = "Weaken the Ramparts", areaId = 3563, x = 47.7, y = 53.6 }) == "ORDERS"
        and L.adds[#L.adds].map == 347 and L.adds[#L.adds].key == nil,
        "K: a group key's waypoint uses its wing's map; no quest id, no key", L.adds[#L.adds].map)
    A.Waypoint({ title = "Direct", uiMapId = 1952, x = 10, y = 10 })
    CHECK(L.adds[#L.adds].map == 1952, "K: an explicit uiMapId is used as given")

    -- Refusals end in chat, never in silence
    L.available, L.why = false, "disabled"
    CHECK(A.WaypointPath() == "ORDERS_OFF", "K: Orders turned off is told apart from absent")
    CHECK(A.Waypoint(target) == "PRINT" and (LastPrint() or ""):find("/way #1944 61.80 60.60", 1, true),
        "K: ...and the press prints the /way line", LastPrint())
    L.available, L.why = true, nil
    local adds = #L.adds
    CommanderOrders.Add = function() return nil, "no world position" end
    CHECK(A.Waypoint(target) == "PRINT", "K: Orders refusing a map falls through to chat")
    CommanderOrders.Add = function() error("Orders broke") end
    CHECK(A.Waypoint(target) == "PRINT", "K: an Orders that raises still ends in chat")
    CHECK(#caughtErrors == 0, "K: ...without an error reaching the handler", caughtErrors[1])
    CommanderOrders = FakeOrders()
    CHECK(#L.adds == adds, "K: nothing recorded by the stand-ins")

    -- The turn-in carries its finisher's spawns too
    local fin = A.Finisher(9033)
    CHECK(fin and fin.spawns and #fin.spawns == 8, "K: Finisher carries every spawn of the finisher",
        fin and fin.spawns and #fin.spawns)

    -- Route open quests here (the stub engine calls every quest not done AVAILABLE)
    local stops = A.RouteStops(3483)
    local byGiver = {}
    for _, stop in ipairs(stops) do byGiver[stop.giver] = stop end
    local altumus = byGiver["Sergeant Altumus"]
    CHECK(altumus and #altumus.quests == 2 and altumus.title == "Sergeant Altumus: Know Your Enemy (+1)"
        and altumus.uiMapId == 1944 and altumus.x == 61.8, "K: a giver with two open quests is one stop",
        altumus and altumus.title)
    CHECK(byGiver["Patrol Sentry"] and #byGiver["Patrol Sentry"].spawns == 8, "K: a stop carries its giver's spawns")
    CHECK(byGiver["Wanted Poster"] ~= nil, "K: an object starter is a stop")
    CHECK(byGiver["Watch Commander Relthorn"] == nil, "K: a giver whose quest is done is not a stop")
    local itemStop = false
    for _, stop in ipairs(stops) do
        for _, title in ipairs(stop.quests) do if title == "Fel Spirits" then itemStop = true end end
    end
    CHECK(not itemStop, "K: an item-started quest has no giver to route to")
    CHECK(A.RouteOpen(3483) == "ORDERS", "K: Route Zone hands the route to Orders")
    local route = L.routes[#L.routes]
    CHECK(route and route.source == "QuestLog" and route.key == "open:3483" and route.mode == "NEAREST"
        and route.start == true and route.title == "Open quests: Hellfire Peninsula" and #route.stops == #stops,
        "K: one owned NEAREST route, started, a stop per giver", route and route.key)
    local first = route and route.stops[1]
    CHECK(first and type(first.map) == "number" and first.x >= 0 and first.x <= 1 and first.y >= 0 and first.y <= 1
        and type(first.title) == "string", "K: stops are uiMap and 0..1 specs with titles")
    local sentryStop
    for _, st in ipairs(route and route.stops or {}) do
        if st.title:find("Patrol Sentry", 1, true) then sentryStop = st end
    end
    CHECK(sentryStop and sentryStop.alternatives and #sentryStop.alternatives == 8,
        "K: a route stop keeps the nearest-of-N alternatives")
    CHECK((LastPrint() or ""):find("routed " .. #stops .. " quest givers in Hellfire Peninsula", 1, true),
        "K: and says so in chat", LastPrint())
    local status, why = A.RouteOpen(3430)
    CHECK(status == nil and why == "NOTHING" and (LastPrint() or ""):find("no open quest in Eversong Woods", 1, true),
        "K: a zone with nothing open routes nothing, and says so", why)
    L.available, L.why = false, "disabled"
    status, why = A.RouteOpen(3483)
    CHECK(status == nil and why == "ORDERS_OFF", "K: Orders off: no route", why)
    L.available, L.why = true, nil
    CommanderOrders = nil
    status, why = A.RouteOpen(3483)
    CHECK(status == nil and why == "NO_ORDERS" and (LastPrint() or ""):find("needs Commander Orders", 1, true),
        "K: no Orders: no route, and a line saying why", why)

    -- The entrance resolver: registered at Init, answering for dungeon maps
    CommanderOrders = FakeOrders()
    L.resolvers = {}
    A.Init()
    local entry = L.resolvers[1]
    CHECK(#L.resolvers == 1 and entry.kind == "entrance" and type(entry.fn) == "function",
        "K: Init registers one entrance resolver with Orders")
    A.Init()
    CHECK(#L.resolvers == 1, "K: ...once")
    local resolve = entry.fn
    local e = resolve(347)
    CHECK(e and e.map == 1944 and NEAR(e.x, 0.477) and NEAR(e.y, 0.536) and e.title == "Hellfire Ramparts entrance",
        "K: Hellfire Ramparts' entrance, on Hellfire's map in 0..1", e and (e.map .. " " .. tostring(e.title)))
    local u = resolve(262)
    CHECK(u and u.map == 1946 and NEAR(u.x, 0.504) and NEAR(u.y, 0.409), "K: the Underbog's, on Zangarmarsh's map")
    -- Questie's override answers uiMap 246 (The Shattered Halls) with 3713,
    -- the Blood Furnace (the fake does what the real one does): the resolver
    -- corrects it, so the Shattered Halls get THEIR door, not the Furnace's
    local sh = resolve(246)
    CHECK(sh and sh.map == 1944 and NEAR(sh.x, 0.477) and NEAR(sh.y, 0.520)
        and sh.title == "The Shattered Halls entrance",
        "K: The Shattered Halls' own door, despite Questie's override", sh and (sh.x .. " " .. tostring(sh.title)))
    local bf = resolve(261)
    CHECK(bf and NEAR(bf.x, 0.460) and NEAR(bf.y, 0.518) and bf.title == "The Blood Furnace entrance",
        "K: ...and the Blood Furnace keeps its own", bf and tostring(bf.title))
    -- Orphan-typed instance maps (this build types The Black Morass, Old
    -- Hillsbrad, Hyjal Summit and Zul'Aman 6, not 4): the map asked about is
    -- answered when Questie's row gives it a dungeon location
    local fake = allFakes[#allFakes]
    local W = fake.world
    W.zones[440] = { name = "Tanaris", uiMapId = 1446, category = 2 }
    W.zones[2366] = { name = "The Black Morass", category = 9, entrances = { { 440, 65.7, 49.8 } } }
    W.zones[3805] = { name = "Zul'Aman", category = 9, entrances = { { 3433, 82.25, 64.3 } } }
    W.zones[3433] = { name = "Ghostlands", uiMapId = 1942, category = 1 }
    W.uiMaps[1446] = { name = "Tanaris", mapType = 3, parent = 1414, areaId = 440 }
    W.uiMaps[1942] = { name = "Ghostlands", mapType = 3, parent = 1415, areaId = 3433 }
    W.uiMaps[273] = { name = "The Black Morass", mapType = 6, parent = 1446, areaId = 2366 }
    W.uiMaps[333] = { name = "Zul'Aman", mapType = 6, parent = 1942, areaId = 3805 }
    W.uiMaps[8273] = { name = "Somewhere Orphaned", mapType = 6, parent = 1446, areaId = 440 }
    W.uiMaps[8275] = { name = "Orphan With A Door", mapType = 6, parent = 1446, areaId = 2366 }
    W.uiMaps[8274] = { name = "A Floor", mapType = 4, parent = 8275, areaId = 440 }
    local bm = resolve(273)
    CHECK(bm and bm.map == 1446 and NEAR(bm.x, 0.657) and NEAR(bm.y, 0.498) and bm.title == "The Black Morass entrance",
        "K: an Orphan-typed instance (The Black Morass) gets its door in Tanaris", bm and tostring(bm.title))
    local za = resolve(333)
    CHECK(za and za.map == 1942 and NEAR(za.x, 0.8225) and NEAR(za.y, 0.643),
        "K: ...and Zul'Aman its door in the Ghostlands", za and tostring(za.map))
    CHECK(resolve(8273) == nil, "K: an Orphan map whose area has no dungeon location gets none")
    CHECK(resolve(8274) == nil, "K: the parent walk never climbs onto an Orphan map")
    local bridged = fake.calls.GetAreaIdByUiMapId or 0
    e.x = 0
    local again = resolve(347)
    CHECK(again and NEAR(again.x, 0.477), "K: each answer is a copy (Orders may write on it)")
    CHECK((fake.calls.GetAreaIdByUiMapId or 0) == bridged, "K: ...from a cache: no second bridge call")
    CHECK(resolve(1944) == nil and resolve(1945) == nil and resolve(9999) == nil,
        "K: a zone, a continent or an unknown map gets no entrance")
    CHECK((fake.calls.GetAreaIdByUiMapId or 0) == bridged, "K: ...and is never put through Questie's bridge")
    CHECK(resolve(nil) == nil and resolve("347") == nil, "K: junk in, nil out")
    local lines = table.concat(A.StatusLines(), "\n")
    CHECK(lines:find("Waypoints go to the Commander Orders arrow", 1, true)
        and lines:find("Dungeon entrances for Commander Orders: answered from Questie", 1, true),
        "K: /cql status names the path and the resolver", lines)

    -- A finisher with more spawns than a fact keeps: the turn-in waypoint
    -- reads its own, up to 32, while the zone's facts stay at eight
    Fresh(function(world)
        local spawns = world.npcs[20016].spawns[3483]
        for i = 1, 4 do spawns[#spawns + 1] = { 60 + i, 30 } end
    end)
    Q.Completion = Stub
    fin = A.Finisher(9033)
    CHECK(fin and fin.spawns and #fin.spawns == 12, "K: a turn-in carries all twelve of its finisher's spawns",
        fin and fin.spawns and #fin.spawns)
    local sentry12 = A.BestStarter(A.ZoneView(3483).byId[9033], 3483)
    CHECK(sentry12 and #sentry12.spawns == 8, "K: ...where the zone's facts keep eight", sentry12 and #sentry12.spawns)
    Fresh()

    CommanderOrders, CommanderOrders_IssueOrder, TomTom = nil, nil, nil
end

-- ===========================================================================
-- L. Giver pins
-- ===========================================================================

local function PinsHolding(pins, questId)
    local out = {}
    for _, pin in ipairs(pins) do
        for _, entry in ipairs(pin.quests) do
            if entry.id == questId then out[#out + 1] = pin end
        end
    end
    return out
end

local function PinChecks(tag)
    local pins = A.PinsFor(3483, 1944)
    CHECK(#pins > 0, tag .. ": Hellfire has pins")
    local p = PinsHolding(pins, 9005)
    CHECK(#p == 1 and #p[1].quests == 3, tag .. ": one NPC's two quests and a giver 0.22% away share one pin",
        p[1] and #p[1].quests)
    CHECK(p[1] and #PinsHolding({ p[1] }, 9006) == 1 and #PinsHolding({ p[1] }, 9010) == 1,
        tag .. ": ...the second quest and the merged giver's")
    local q = PinsHolding(pins, 9012)
    CHECK(#q == 1 and q[1] ~= p[1], tag .. ": a giver 0.6% away gets its own pin")
    CHECK(#PinsHolding(pins, 9033) == 5, tag .. ": at most five spawns per quest", #PinsHolding(pins, 9033))
    CHECK(#PinsHolding(pins, 9022) == 0, tag .. ": item starters are skipped")
    CHECK(#PinsHolding(pins, 9023) == 0, tag .. ": a giver standing in Terokkar is not on Hellfire's map")
    local sub = PinsHolding(pins, 9015)
    CHECK(#sub == 1 and NEAR(sub[1].x, 0.58) and NEAR(sub[1].y, 0.40), tag .. ": a subzone spawn on the parent's map")
    local sentinel = PinsHolding(pins, 9017)
    CHECK(#sentinel == 1 and NEAR(sentinel[1].x, 0.46) and NEAR(sentinel[1].y, 0.518),
        tag .. ": a giver inside a dungeon is pinned at its entrance")
    local inRange = true
    for _, pin in ipairs(pins) do
        if not (pin.x >= 0 and pin.x <= 1 and pin.y >= 0 and pin.y <= 1) then inRange = false end
    end
    CHECK(inRange, tag .. ": pin coordinates are 0..1")
    local other = A.PinsFor(3483, 1952)
    CHECK(#other == 1 and #PinsHolding(other, 9023) == 1, tag .. ": on Terokkar's map, Hellfire's view pins only the exile")
    local terokkar = A.PinsFor(3519, 1952)
    CHECK(#PinsHolding(terokkar, 9014) == 1 and #PinsHolding(terokkar, 9029) == 1,
        tag .. ": Terokkar pins its own and the Auchindoun giver")
end

do
    PinChecks("L")
    CHECK(#A.PinsFor(3430, 1941) == 0, "L: a zone with no view has no pins")
end

-- ===========================================================================
-- M. One quest: detail, finisher, best starter, Questie's own pins
-- ===========================================================================

do
    CHECK(A.IsQuestieDrawing(9005) == true and A.IsQuestieDrawing(9004) == false, "M: IsQuestieDrawing")
    local fin = A.Finisher(9003)
    CHECK(fin and fin.name == "Force Commander Danath" and fin.areaId == 3483 and fin.zoneName == "Hellfire Peninsula"
        and fin.x == 56.6 and fin.y == 66.4 and fin.uiMapId == 1944, "M: Finisher")
    fin = A.Finisher(9017)
    CHECK(fin and fin.areaId == 3483 and fin.x == 46.0, "M: a finisher inside a dungeon answers the entrance")
    CHECK(A.Finisher(77777) == nil, "M: no finisher for a non-quest")
    local view = A.ZoneView(3483)
    local best = A.BestStarter(view.byId[9015], 3483)
    CHECK(best and best.x == 58.0 and best.y == 40.0 and best.uiMapId == 1944 and best.zoneName == "Hellfire Peninsula",
        "M: BestStarter in the viewed zone")
    best = A.BestStarter(factsById[9023], 3483)
    CHECK(best and best.zoneName == "Terokkar Forest" and best.x == 40.0, "M: BestStarter anywhere when not here")
    CHECK(A.BestStarter(factsById[9022], 3483) == nil, "M: an item starter has no best spawn")
    CHECK(A.BestStarter(nil) == nil, "M: nothing in, nothing out")
    local detail = A.QuestDetail(9002, 3483)
    CHECK(detail and detail.name == "Journey to Honor Hold" and detail.level == 59 and detail.requiredLevel == 58,
        "M: QuestDetail basics")
    CHECK(detail and #detail.prereqs == 1 and detail.prereqs[1].id == 9001 and detail.prereqs[1].done == true
        and detail.prereqs[1].name == "Arrival in Outland" and detail.prereqs[1].zoneName == "Hellfire Peninsula",
        "M: prerequisites with names, state and zone")
    CHECK(detail and #detail.followups == 1 and detail.followups[1].id == 9003, "M: follow-ups (next in chain, deduped)")
    detail = A.QuestDetail(9005, 3483)
    CHECK(detail and #detail.repRewards == 1 and detail.repRewards[1].factionName == "Honor Hold"
        and detail.repRewards[1].value == 250, "M: reputation rewards")
    CHECK(detail and #detail.followups == 1 and detail.followups[1].id == 9007,
        "M: follow-ups found in the zone's prerequisites")
    CHECK(detail and detail.objectivesText[1] == "Scout the Legion front." and detail.starters[1].name == "Sergeant Altumus",
        "M: objectives and givers")
    detail = A.QuestDetail(9020, nil)
    CHECK(detail and detail.followups[1] and detail.followups[1].id == 9003, "M: a breadcrumb leads to its target")
    CHECK(A.QuestDetail(77777, 3483) == nil, "M: no detail for a non-quest")
end

-- ===========================================================================
-- N. Broken and absent Questies
-- ===========================================================================

do
    local world2 = Fake.DefaultWorld()
    local fake2 = Install(world2)
    fake2.modules.QuestieDB.IsDoableVerbose = nil
    LoadAdapter()
    Fire("PLAYER_LOGIN")
    Settle()
    local state, reason = A.State()
    CHECK(state == "BROKEN" and (reason or ""):find("IsDoableVerbose", 1, true), "N: a missing IsDoableVerbose is BROKEN",
        tostring(state) .. " " .. tostring(reason))
    local view, err = A.ZoneView(3483)
    CHECK(view == nil and err == "BROKEN", "N: ZoneView answers BROKEN", err)

    world2 = Fake.DefaultWorld()
    world2.ready = false
    fake2 = Install(world2)
    fake2.modules.QuestieJourney.zoneMap = nil
    LoadAdapter()
    Fire("PLAYER_LOGIN")
    fake2.SetReady()
    Settle()
    state, reason = A.State()
    CHECK(state == "BROKEN" and (reason or ""):find("zoneMap", 1, true), "N: no zoneMap at ready is BROKEN", reason)

    world2 = Fake.DefaultWorld()
    world2.ready = false
    fake2 = Install(world2)
    Questie.API.RegisterOnReady = nil
    LoadAdapter()
    Fire("PLAYER_LOGIN")
    Settle()
    CHECK(A.State() == "LOADING", "N: without RegisterOnReady, polling")
    Questie.API.isReady = true
    Advance(1100)
    Settle()
    CHECK(A.State() == "READY", "N: ...and the poll notices ready", A.State())

    world2 = Fake.DefaultWorld()
    world2.omitModules = { AvailableQuests = true, QuestieProfessions = true, l10n = true, QuestieEvent = true }
    world2.npcs[20003].spawns = { [3483] = { 7, { 61.8, 60.6 } } }     -- one malformed row
    fake2 = Install(world2)
    LoadAdapter()
    Q.Completion = Stub
    Fire("PLAYER_LOGIN")
    Settle()
    CHECK(A.State() == "READY", "N: optional modules missing is still READY")
    CHECK(A.IsQuestieDrawing(9005) == false, "N: no AvailableQuests: Questie draws nothing we know of")
    view = A.ZoneView(3483)
    CHECK(view and view.byId[9026] == nil and view.byId[9025] ~= nil,
        "N: no QuestieProfessions: no profession layer, the class layer still there")
    CHECK(view and #view.byId[9005].starters == 1 and view.byId[9005].starters[1].x == 61.8,
        "N: a malformed spawn row is skipped, the good one kept")
    CHECK(A.ZoneName(3999) == "Zone 3999", "N: no l10n: plain label")
    CHECK(fake2.modules.AvailableQuests == nil and #fake2.ModulesCreated() == 0,
        "N: nothing conjured a missing module into being")

    -- Questie answering in a shape nobody expected: the entry points degrade
    local raising = setmetatable({}, { __index = function() error("zoneMap exploded") end })
    fake2.modules.QuestieJourney.zoneMap = raising
    A.Bump("test")
    Advance(300)
    local before = #caughtErrors
    view, err = A.ZoneView(3483)
    CHECK(view == nil and err == "ADAPTER_ERROR", "N: a raising Questie table: ZoneView nil, ADAPTER_ERROR", err)
    CHECK(#A.ZoneMenu() == 0 and #A.ContinentZones(1945) == 0 and #A.PinsFor(3483, 1944) == 0,
        "N: ...the lists come back empty")
    CHECK((A._LastError() or ""):find("zoneMap exploded", 1, true), "N: ...and the error is kept for /cql status",
        A._LastError())
    CHECK(#caughtErrors == before, "N: ...and nothing reached the error handler")
    fake2.modules.QuestieJourney.zoneMap = {}

    Questie = {}      -- what a second Questie copy leaves behind
    CHECK(A.State() == "ABSENT", "N: Questie without an API is ABSENT")
    Questie = nil
    QuestieLoader = nil
    CHECK(A.State() == "ABSENT", "N: no Questie is ABSENT")
end

-- ===========================================================================
-- O. End to end through the real engine
-- ===========================================================================

local skippedEngine = false
if not RealEngine then
    skippedEngine = true
    io.write("SKIPPED: engine not present\n")
else
    CommanderQuestLogDB = {}
    CommanderQuestLogChar = { Ignored = {} }
    local fakeO = Fresh()
    Q.Completion = RealEngine
    local before = GlobalKeys()
    local view = A.ZoneView(3483)
    CHECK(type(view) == "table", "O: Hellfire's view from the real engine")
    local t = view and view.totals or {}
    CHECK(t.counted == 13, "O: 13 quests count toward Hellfire's 100%", t.counted)
    CHECK(t.done == 2, "O: 2 of them done", t.done)
    CHECK(NEAR(t.pct, 2 / 13), "O: 15%", t.pct)
    local by = t.byStatus or {}
    local expect = { DONE = 2, LOG = 1, AVAILABLE = 9, LOCKED = 2, MISSED = 3, RIVAL = 1, REPEATABLE = 1,
                     SEASONAL = 1, OPTIONAL = 1, EXTRA = 4, IGNORED = 0 }
    for bucket, n in pairs(expect) do
        CHECK(by[bucket] == n, "O: byStatus." .. bucket .. " == " .. n, by[bucket])
    end
    local e = view and view.byId or {}
    CHECK(e[9011] and e[9011].status == "RIVAL", "O: the Scryer quest is the rival's")
    CHECK(e[9009] and e[9009].status == "MISSED", "O: past a one-way rep cap is missed")
    CHECK(e[9020] and e[9020].status == "MISSED" and e[9021] and e[9021].status == "MISSED", "O: breadcrumb and outlevelled missed")
    CHECK(e[9007] and e[9007].status == "LOCKED" and e[9007].lock and e[9007].lock.level == 63,
        "O: level lock carries the level")
    local prereqs = e[9007] and e[9007].lock and e[9007].lock.prereq
    CHECK(prereqs and Contains(prereqs, 9005), "O: ...and the unmet prerequisite (multi-reason)")
    CHECK(e[9012] and e[9012].counted == true and e[9013] and e[9013].counted == false, "O: the exclusive pair is one slot")
    CHECK(e[9015] and e[9015].counted == true, "O: the 3535 quest counts for Hellfire")
    CHECK(e[9017] and e[9017].layer == "EXTRA" and e[9017].status == "EXTRA", "O: dungeon quests starting here are extras")
    CHECK(e[9023] and e[9023].startsHere == false and e[9023].startZoneName == "Terokkar Forest", "O: starts elsewhere")
    CHECK(e[9008] and e[9008].status == "REPEATABLE" and e[9019] and e[9019].status == "SEASONAL"
        and e[9018] and e[9018].status == "OPTIONAL", "O: daily, event, hidden-on-map buckets")
    CHECK(rawequal(A.ZoneView(3483), view), "O: cache hit with the real engine")
    local summary = A.ZoneSummary(3483)
    CHECK(summary and summary.counted == 13 and summary.done == 2, "O: summary")

    local terokkar = A.ZoneView(3519)
    CHECK(terokkar and terokkar.totals.counted == 2 and terokkar.totals.done == 0, "O: Terokkar 0 / 2",
        terokkar and terokkar.totals.counted)

    -- The choice made in Hellfire: the denominator holds
    fakeO.Complete(9013)
    fakeO.SetState(9012, "EXCLUSIVE_COMPLETED")
    A.Bump("test")
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.totals.counted == 13 and view.totals.done == 3, "O: choosing one of the pair keeps 13, done 3",
        view.totals.counted .. "/" .. view.totals.done)
    CHECK(view.byId[9012].status == "MISSED" and view.byId[9012].chosen == 9013, "O: the other is missed, naming the choice",
        tostring(view.byId[9012].chosen))
    -- 9013 names 9014, but 9014 names nothing: Questie still offers the
    -- Staff after the Shield (exclusiveTo is one-way), and so does the engine
    terokkar = A.ZoneView(3519)
    local staff = terokkar and terokkar.byId[9014]
    CHECK(staff and staff.status == "AVAILABLE" and staff.counted == true,
        "O: the Shield does not take the Staff away: 9014's own list is empty (one-way)", staff and staff.status)
    CHECK(terokkar and terokkar.totals.counted == 2, "O: ...and Terokkar keeps its 2", terokkar and terokkar.totals.counted)
    fakeO.Complete(9013, false)
    fakeO.SetState(9012, nil)

    -- The other way round: the Staff done rules the Shield out by the
    -- Shield's own list, and the Blade, which does not name the Staff, is
    -- still doable and now counts in the slot's place
    fakeO.Complete(9014)
    A.Bump("test")
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.byId[9013].status == "MISSED" and view.byId[9013].chosen == 9014
        and view.byId[9013].state == "EXCLUSIVE_COMPLETED", "O: the Staff done misses the Shield (its own list)")
    CHECK(view.byId[9012].counted == true and view.byId[9012].status == "AVAILABLE",
        "O: ...the Blade still counts")
    CHECK(view.totals.counted == 13, "O: ...and Hellfire's denominator holds", view.totals.counted)
    fakeO.Complete(9014, false)

    CommanderQuestLogChar.Ignored[9005] = true
    A.Bump("ignore")
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.totals.counted == 12 and view.byId[9005].status == "IGNORED", "O: an ignored quest leaves the 100%")
    CommanderQuestLogChar.Ignored[9005] = nil

    CommanderQuestLogDB.CountRival = true
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.totals.counted == 14 and view.byId[9011].status == "LOCKED", "O: Count Both Aldor and Scryers", view.totals.counted)
    CommanderQuestLogDB.CountRival = nil
    CommanderQuestLogDB.CountExtras = true
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.totals.counted == 17, "O: Count Dungeon and Class Quests That Start Here", view.totals.counted)
    CommanderQuestLogDB.CountExtras = nil
    CommanderQuestLogDB.CountOptional = true
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.totals.counted == 14 and view.byId[9018].counted == true, "O: Count Optional Quests", view.totals.counted)
    CommanderQuestLogDB.CountOptional = nil
    Commander.Notify(COMMANDER_QUESTLOG_EVENTS.UPDATE)
    Advance(300)

    A.ZoneView(3483)
    fakeO.world.logComplete = { [9003] = 1 }
    A.SetLogEntries({ { isHeader = false, questID = 9003, isComplete = true } })
    Advance(300)
    view = A.ZoneView(3483)
    CHECK(view.byId[9003].ready == true, "O: a logged quest the client calls complete reads ready")
    local list = RealEngine.Group(view, "GUIDE", { playerPos = A.PlayerPos(3483) })
    CHECK(type(list) == "table" and list[1] and list[1].isHeader and list[1].title == "Turn in",
        "O: the Guide opens with Turn in", list and list[1] and list[1].title)
    CHECK(A.PlayerPos(3483) and NEAR(A.PlayerPos(3483).x, 50) and NEAR(A.PlayerPos(3483).y, 60),
        "O: the player's position on the zone map, 0..100")
    CHECK(A.PlayerPos(3519) == nil, "O: no position on a map the player is not on")
    local reason = RealEngine.Reason(view.byId[9011], A.Character(), view)
    CHECK(type(reason) == "string" and reason ~= "", "O: the engine words a reason from the adapter's char", reason)
    local skillEntry = view.byId[9026]
    local skillReason = skillEntry and RealEngine.Reason(skillEntry, A.Character(), view)
    -- 9026 is filed under Mining, so it is an "Also starting here" row: the
    -- sentence leads with the lock and then says it does not count
    CHECK(type(skillReason) == "string" and skillReason:find("^Needs 300 Mining%.") ~= nil,
        "O: a skill lock names the profession through char.skillName", tostring(skillReason))

    PinChecks("O")

    local seen = {}
    A.RequestSummaries({ 3483, 3519 }, function(areaId, s) seen[areaId] = s end)
    Settle()
    CHECK(seen[3483] and seen[3483].counted == 13 and NEAR(seen[3483].pct, 2 / 13), "O: background summary for Hellfire")
    CHECK(seen[3519] and seen[3519].counted == 2, "O: background summary for Terokkar")
    local detail = A.QuestDetail(9004, 3483)
    CHECK(detail and detail.level == 62 and detail.requiredLevel == 61, "O: detail levels through EffectiveLevel")
    -- Route Zone over the real buckets: the open quests' givers and no other
    -- (not the locked, missed, daily, seasonal, optional or rival ones; a
    -- giver standing outside the zone still counts, its quest is filed here)
    local function RouteGivers()
        local out, n = {}, 0
        for _, stop in ipairs(A.RouteStops(3483)) do out[stop.giver] = stop; n = n + 1 end
        return out, n
    end
    local givers, nGivers = RouteGivers()
    CHECK(nGivers == 6 and givers["Sergeant Altumus"] and givers["Patrol Sentry"] and givers["Field Marshal Brock"]
        and givers["Terokkar Exile"] and givers["Gryphon Master Ivran"] and givers["Scout Ranger Ilsa"],
        "O: Route Zone visits the six givers of Hellfire's open quests", nGivers)
    CHECK(not givers["Wing Commander Dabir"] and not givers["Quartermaster Urgronn"] and not givers["Festival Keeper"]
        and not givers["Hidden Errand Giver"] and not givers["Scryer Envoy"] and not givers["Force Commander Danath"],
        "O: ...and none whose quests are locked, missed, daily, seasonal, optional, the rival's or in the log")
    CommanderQuestLogChar.Ignored[9010] = true
    A.Bump("test")
    Settle()
    givers, nGivers = RouteGivers()
    CHECK(nGivers == 5 and not givers["Gryphon Master Ivran"], "O: an ignored quest's giver drops off the route", nGivers)
    CommanderQuestLogChar.Ignored[9010] = nil
    A.Bump("test")
    Settle()
    CHECK(#NewGlobals(before) == 0, "O: a full pass defines no global", table.concat(NewGlobals(before), ","))
end

-- ===========================================================================
-- Q. Review fixes (2026-10-04), each against a fresh instance
-- ===========================================================================

do
    -- Zooming out of Outland lands on Cosmic (946), whose direct children are
    -- a world and a continent, never a zone
    Fresh()
    Q.Completion = Stub
    local cosmic = A.ContinentZones(946)
    local names = {}
    for i, zone in ipairs(cosmic) do names[i] = zone.name end
    CHECK(#cosmic >= 4 and table.concat(names, "|"):find("Hellfire Peninsula", 1, true)
        and table.concat(names, "|"):find("Elwynn Forest", 1, true),
        "Q: Cosmic lists every quest zone instead of none", table.concat(names, "|"))

    -- Raid keys Questie files quests under but leaves off its Journey list
    -- (Serpentshrine 3607 here) still get a zone in the Dungeons menu
    Fresh(function(w)
        w.zones[3607] = { name = "Serpentshrine Cavern" }        -- no category: not in Journey.zones[9]
        w.npcs[20030] = { name = "Coilfang Herald", spawns = { [3607] = { { -1, -1 } } } }
        w.quests[9034] = { name = "Coilfang Armaments", questLevel = 70, requiredLevel = 70, zoneOrSort = 3607,
                           startedBy = { { 20030 } }, finishedBy = { { 20030 } } }
    end)
    Q.Completion = Stub
    local dungeons
    for _, cat in ipairs(A.ZoneMenu()) do if cat.key == 9 then dungeons = cat end end
    local found = false
    for _, zone in ipairs(dungeons and dungeons.zones or {}) do
        if zone.areaId == 3607 and zone.name == "Serpentshrine Cavern" then found = true end
    end
    CHECK(found, "Q: the Dungeons menu reaches a raid key missing from Questie's Journey list")

    -- Glowcap Mushrooms (9808): capped below Friendly with Sporeggar, which
    -- never falls, but commented out of Questie's one-way list
    local fakeQ = Fresh(function(w)
        w.factions[970] = "Sporeggar"
        w.reps[970] = 3500
        w.quests[9808] = { name = "Glowcap Mushrooms", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                           startedBy = { { 20008 } }, finishedBy = { { 20008 } }, requiredMinRep = { 970, 0 },
                           requiredMaxRep = { 970, 3000 }, state = "EXCEED_REPUTATION" }
    end)
    CHECK(fakeQ.modules.QuestieDB.questsOnlyAvailableUntilReputationValue[9808] == nil,
        "Q: (Questie's own list leaves 9808 out, as the real one does)")
    local facts = {}
    for _, fact in ipairs(A._Facts(3483) or {}) do facts[fact.id] = fact end
    CHECK(facts[9808] and facts[9808].oneWayRep == true, "Q: the adapter's own list marks 9808 one-way")
    if RealEngine then
        Q.Completion = RealEngine
        local view = A.ZoneView(3483)
        CHECK(view and view.byId[9808] and view.byId[9808].status == "MISSED" and view.byId[9808].reasonKey == "REP_PAST",
            "Q: ...so past Friendly it is missed, not locked for ever", view and view.byId[9808] and view.byId[9808].status)
    end

    -- A reputation or skill change is asked about again once Questie's own
    -- 2 s bucket has refreshed the caches its verdicts read
    Fresh()
    Q.Completion = Stub
    Settle()
    local gen = A.generation
    Fire("UPDATE_FACTION")
    Advance(300)
    CHECK(A.generation == gen + 1, "Q: UPDATE_FACTION bumps at once")
    Advance(1700)
    CHECK(A.generation == gen + 1, "Q: ...nothing more inside Questie's 2 s bucket")
    Advance(500)
    CHECK(A.generation == gen + 2, "Q: ...and once more after Questie's cache bucket", A.generation - gen)
    CHECK(table.concat(A.StatusLines(), "\n"):find("Questie cache", 1, true), "Q: ...which status names")
    Fire("SKILL_LINES_CHANGED")
    Fire("SKILL_LINES_CHANGED")
    Advance(3000)
    CHECK(A.generation == gen + 4, "Q: a skill change too, once per bucket however many events", A.generation - gen)
    gen = A.generation
    Fire("QUEST_TURNED_IN")
    Advance(3000)
    CHECK(A.generation == gen + 1, "Q: a turn-in needs no second look")

    -- (review 2026-10-04, round 2) Trailing edge: a change that arrives while
    -- the late look is pending, a second after the one that armed it, gets a
    -- look of its own a whole bucket after IT -- the first look, 1.2 s after
    -- it, can land before Questie's bucket for the second has run
    Settle()
    gen = A.generation
    Fire("UPDATE_FACTION")
    Advance(1000)
    Fire("UPDATE_FACTION")
    Advance(1500)                                   -- t = 2.5: the first look (2.2) has stepped
    CHECK(A.generation == gen + 3, "Q: two changes a second apart: two bumps and the first look", A.generation - gen)
    Advance(2000)                                   -- t = 4.5
    CHECK(A.generation == gen + 3, "Q: ...nothing more inside the second change's bucket", A.generation - gen)
    Advance(200)                                    -- t = 4.7: the re-armed look (4.4) has stepped
    CHECK(A.generation == gen + 4, "Q: ...and a look after it, once Questie's bucket for it has run", A.generation - gen)
    CHECK(table.concat(A.StatusLines(), "\n"):find("Questie cache", 1, true), "Q: ...which status names")
    Advance(6000)
    CHECK(A.generation == gen + 4, "Q: ...and then no more", A.generation - gen)

    -- Background summaries skip the givers: same totals, no NPC reads
    if RealEngine then
        Fresh()
        Q.Completion = RealEngine
        A._Facts(3483)                       -- builds the EXTRA index first, as any full view does
        A.Bump("test")
        Advance(300)
        local fakeS = allFakes[#allFakes]
        local npcReads = fakeS.calls.QueryNPCSingle or 0
        local seen = {}
        A.RequestSummaries({ 3483, 3519 }, function(areaId, s) seen[areaId] = s end)
        Settle()
        CHECK(seen[3483] and seen[3483].counted == 13 and seen[3483].done == 2 and seen[3519] and seen[3519].counted == 2,
            "Q: a summary built without givers has the same totals", seen[3483] and seen[3483].counted)
        CHECK((fakeS.calls.QueryNPCSingle or 0) == npcReads, "Q: ...and read no NPC to get them",
            (fakeS.calls.QueryNPCSingle or 0) - npcReads)
        A.ZoneView(3483)
        CHECK((fakeS.calls.QueryNPCSingle or 0) > npcReads, "Q: (a full view does read them)")
    end

    -- The quest log window never opened this session: a quest the client
    -- calls complete is still ready, so the drawer's waypoint goes to the turn-in
    if RealEngine then
        Fresh(function(w) w.logComplete = { [9003] = 1 } end)
        Q.Completion = RealEngine
        local view = A.ZoneView(3483)
        CHECK(view and view.byId[9003].ready == true, "Q: ready without any window scan")

        -- (review 2026-10-04, round 2) ...and under a heading collapsed in the
        -- stock log, where GetQuestLogIndexByID answers 0 and the window's
        -- scan (which expands first) never ran or is stale: IsQuestComplete
        -- asks by questID
        local fakeC, worldC = Fresh(function(w) w.logComplete = { [9003] = 1 }; w.logCollapsed = true end)
        Q.Completion = RealEngine
        CHECK(GetQuestLogIndexByID(9003) == 0, "Q: (the collapsed heading takes 9003 out of the index space)")
        local collapsed = A.ZoneView(3483)
        CHECK(collapsed and collapsed.byId[9003].ready == true, "Q: ready under a collapsed heading, no window scan",
            collapsed and tostring(collapsed.byId[9003].ready))
        A.SetLogEntries({ { isHeader = false, questID = 9003, isComplete = false } })
        A.Bump("test")
        Advance(300)
        local stale = A.ZoneView(3483)
        CHECK(stale and stale.byId[9003].ready == true, "Q: ...and the client beats a scan from before it was finished")
        local saved = IsQuestComplete
        IsQuestComplete = nil
        worldC.logComplete = { [9003] = 1 }
        A.Bump("test")
        Advance(300)
        local without = A.ZoneView(3483)
        CHECK(without and without.byId[9003].ready == false, "Q: without IsQuestComplete it falls back to the scan")
        IsQuestComplete = function() return nil end
        A.Bump("test")
        Advance(300)
        local unknown = A.ZoneView(3483)
        CHECK(unknown and unknown.byId[9003].ready == false, "Q: ...and an answer that is not true is not believed")
        IsQuestComplete = saved
        CHECK(#fakeC.forbidden == 0, "Q: (nothing forbidden on the way)")
    end

    -- A quest whose only prerequisite is gone for good (outside the zone,
    -- Questie's verdict on it final) is missed, through the real engine
    if RealEngine then
        Fresh(function(w)
            w.quests[9040] = { name = "Assist Exarch Orelis", questLevel = 62, requiredLevel = 60, zoneOrSort = 3519,
                               startedBy = { { 20024 } }, finishedBy = { { 20024 } }, state = "EXCLUSIVE_COMPLETED" }
            w.quests[9041] = { name = "Distraction at the Manaforge", questLevel = 62, requiredLevel = 60, zoneOrSort = 3483,
                               startedBy = { { 20008 } }, finishedBy = { { 20008 } }, preQuestSingle = { 9040 },
                               state = "NO_PREQUESTSINGLE" }
            -- Riding: kept in its zone by Questie, and every character can train it
            w.quests[9042] = { name = "A Shabby Disguise", questLevel = 70, requiredLevel = 70, zoneOrSort = 3483,
                               startedBy = { { 20008 } }, finishedBy = { { 20008 } }, requiredSkill = { 762, 225 },
                               state = "PROFESSION_MISSING" }
        end)
        Q.Completion = RealEngine
        local view = A.ZoneView(3483)
        local lost = view and view.byId[9041]
        CHECK(lost and lost.status == "MISSED" and lost.reasonKey == "PREREQ_GONE" and lost.counted == false,
            "Q: a quest behind a prerequisite Questie calls gone is missed", lost and lost.status)
        CHECK(lost and RealEngine.Reason(lost, A.Character(), view)
            == "Needs \"Assist Exarch Orelis\" (Terokkar Forest), which you can no longer get.",
            "Q: ...naming it and its zone", lost and RealEngine.Reason(lost, A.Character(), view))
        local riding = view and view.byId[9042]
        CHECK(riding and riding.status == "LOCKED" and riding.counted == true,
            "Q: a Riding quest is locked and counted, not missed", riding and riding.status)
        CHECK(riding and RealEngine.Reason(riding, A.Character(), view) == "Needs 225 Riding and level 70.",
            "Q: ...and names Riding", riding and RealEngine.Reason(riding, A.Character(), view))
        CHECK(view and view.totals.counted == 14, "Q: Hellfire counts the Riding quest and not the lost one",
            view and view.totals.counted)
    end
    CHECK(A._LastError() == nil, "Q: no adapter error across the section", A._LastError())
end

-- ===========================================================================
-- P. Nothing forbidden, nothing leaked, no glyphs
-- ===========================================================================

do
    local forbidden, style, missingText, created, imports = {}, {}, 0, {}, 0
    for _, f in ipairs(allFakes) do
        for _, name in ipairs(f.forbidden) do forbidden[#forbidden + 1] = name end
        for _, name in ipairs(f.styleErrors) do style[#style + 1] = name end
        missingText = missingText + f.returnTextMissing
        for _, name in ipairs(f.ModulesCreated()) do created[#created + 1] = name end
        imports = imports + (f.calls.ImportModule or 0)
    end
    CHECK(#forbidden == 0, "P: no forbidden Questie call (IsDoable, IsComplete, HideQuest, GetZonesWithQuests, IsLevelRequirementsFulfilled)",
        table.concat(forbidden, ","))
    CHECK(#style == 0, "P: every Questie call used the right dot / colon style", table.concat(style, ","))
    CHECK(missingText == 0, "P: IsDoableVerbose never called without returnText")
    CHECK(#created == 0 and imports == 0, "P: ImportModule never called (no phantom modules)", table.concat(created, ","))

    local function GlyphFree(text)
        local stripped = text:gsub("\194\183", ""):gsub("\226\128\148", "")
        return not stripped:find("[\128-\255]")
    end
    local clean = true
    for _, line in ipairs(printLog) do
        if line ~= "SKIPPED: engine not present" and not GlyphFree(line) then clean = false end
    end
    CHECK(clean, "P: printed lines carry no shape glyph")
    local fakeP = Fresh()
    Q.Completion = RealEngine or Stub
    A.ZoneView(3483)
    A.ZoneMenu()
    A.ContinentZones(1945)
    A.PinsFor(3483, 1944)
    A.QuestDetail(9005, 3483)
    A.Finisher(9003)
    A.ZoneForPlayer()
    A.RequestSummaries({ 3483, 3519, 3563, 3917, 3716 }, function() end)
    Settle()
    CHECK(A._LastError() == nil, "P: a full pass over the default world records no error", A._LastError())
    local lines = A.StatusLines()
    local allClean = true
    for _, line in ipairs(lines) do if not GlyphFree(line) then allClean = false end end
    CHECK(#lines >= 6 and allClean, "P: status lines carry no shape glyph", #lines)
    CHECK(lines[1]:find("READY", 1, true) and lines[1]:find("12.0.3", 1, true), "P: status names the state and version", lines[1])
    CHECK(#fakeP.forbidden == 0, "P: still nothing forbidden")
    CHECK(#caughtErrors == 0, "P: no error reached the error handler", caughtErrors[1])
end

io.write(string.format("%d checks, %d failures%s\n", checks, fails, skippedEngine and " (end-to-end section skipped)" or ""))
os.exit(fails == 0 and 0 or 1)
