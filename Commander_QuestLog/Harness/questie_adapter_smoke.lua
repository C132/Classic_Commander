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
-- failed, while that file is absent); R reputation (1.6.0) over
-- Fake.RepWorld() with the REAL rules engine and generated data -- one number
-- per quest, the faction index, faction views on their own cache, the picker,
-- faction summaries, zone totals, the character, today's rotating dailies,
-- phase-held quests, calibration from the bars and the chat line, the guards,
-- the status lines, and the same number on every surface (skipped with O);
-- P nothing forbidden was ever called, no global leaked, no shape glyph was
-- printed.
--
--   CQL_STANDING=/path/copy.lua  luajit questie_adapter_smoke.lua  -- a mutated rules engine (R)
--   CQL_REPDATA=/path/copy.lua   luajit questie_adapter_smoke.lua  -- another data file (R)
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
-- R. Reputation (1.6.0) over Fake.RepWorld(), with the REAL rules engine and
--    the generated data. The two are loaded for this section only and taken
--    away after it, so every other section runs as it always did. Each
--    subsection is a fresh adapter over a fresh world.
-- ===========================================================================

local skippedRep = false
do
    local RepR, RepD
    local function LoadRules()
        Q.Standing, CommanderQuestLogReputationData = nil, nil
        for _, path in ipairs({
            os.getenv("CQL_REPDATA") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogReputationData.lua"),
            os.getenv("CQL_STANDING") or (ADDONS .. "/Commander_QuestLog/CommanderQuestLogStanding.lua"),
        }) do
            local chunk = loadfile(path)
            if chunk then pcall(chunk) end
        end
        RepR, RepD = Q.Standing, CommanderQuestLogReputationData
        return type(RepR) == "table" and type(RepR.Effects) == "function" and type(RepD) == "table"
    end

    -- A fresh READY adapter over a fresh reputation world (optionally
    -- edited), with the real engine and fresh saved variables
    local function RepFresh(edit)
        CommanderQuestLogDB = {}
        CommanderQuestLogChar = { Ignored = {} }
        local world = Fake.RepWorld()
        if edit then edit(world) end
        local fakeR = Install(world)
        LoadAdapter()
        Q.Completion = RealEngine
        Fire("PLAYER_LOGIN")
        Settle()
        return fakeR, world
    end

    -- A faction view needs the index read: asking the menu starts it
    local function Indexed()
        A.FactionMenu()
        Settle()
    end

    local function Ids(entries)
        local ids = {}
        for _, entry in ipairs(entries or {}) do ids[#ids + 1] = entry.id end
        table.sort(ids)
        return table.concat(ids, ",")
    end

    local function Find(list, key, value)
        for _, item in ipairs(list or {}) do if item[key] == value then return item end end
        return nil
    end

    local function Line(questId, opts) return (A.RepLine(questId, opts)) end

    local function DeepEqual(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not DeepEqual(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
    end

    local function GlyphFree(text)
        local stripped = text:gsub("\194\183", ""):gsub("\226\128\148", "")
        return not stripped:find("[\128-\255]")
    end

    if not (RealEngine and LoadRules()) then
        skippedRep = true
        io.write("SKIPPED: reputation section (the completion engine or the rules engine is not present)\n")
    else
        -- -------------------------------------------------------------------
        -- R1. One number per quest
        -- -------------------------------------------------------------------
        do
            local fakeR = RepFresh()
            local R = RepR
            CHECK(A.RepMultiplier() == 110, "R1: a Human is paid at 110% (Diplomacy)", A.RepMultiplier())
            CHECK(Line(9355) == "+275 Honor Hold", "R1: 250 Honor Hold is +275 to a Human", Line(9355))
            CHECK(Line(91001) == "No reputation", "R1: a quest that pays nothing says so", Line(91001))
            CHECK(Line(91002) == "+110 Honor Hold", "R1: a row for a faction with no standing slot is dropped",
                Line(91002))
            local e = A.RepEffects(10326) or {}
            local aldor, scryers, shatar = R.For(e, 932), R.For(e, 934), R.For(e, 935)
            CHECK(#e == 3 and e[1].factionId == 932 and aldor and aldor.delta == 275 and aldor.kind == "DIRECT",
                "R1: More Marks of Kil'jaeden pays the Aldor +275 directly", #e)
            CHECK(scryers and scryers.delta == -302 and scryers.kind == "RIVAL",
                "R1: the rival loss is spillover from the boosted gain (-302, not Questie's -275)",
                scryers and scryers.delta)
            CHECK(shatar and shatar.delta == 137 and shatar.kind == "SPILL",
                "R1: the stored Sha'tar half is spillover, paid once (+137: not 137.5, not 125 on top)",
                shatar and shatar.delta)
            CHECK(Line(10326) == "+275 The Aldor  -302 The Scryers  +137 The Sha'tar", "R1: the full line", Line(10326))
            CHECK(Line(10326, { compact = true }) == "+275 Aldor -302 Scryers +137 Sha'tar", "R1: the compact line",
                Line(10326, { compact = true }))
            CHECK(Line(11354) == "+385 The Consortium  +385 Honor Hold",
                "R1: an audited row is paid (Honor Hold), the other side's (Thrallmar) is not", Line(11354))
            local nether = A.RepEffects(10871) or {}
            CHECK(Line(10871) == "+42,000 Netherwing" and nether[1] and nether[1].unknown == nil,
                "R1: Ally of the Netherwing: the audited 38182, boosted, lifts a Human from the base (-42000) to 0",
                Line(10871))
            CHECK(Line(9266) == "+550 Everlook  -450 Bloodsail Buccaneers  +275 Booty Bay  +275 Gadgetzan  +275 Ratchet",
                "R1: the goblin-town rows are spillover; a Human loses 10% less", Line(9266))
            CHECK(Line(91003) == "+275 Stormwind  +68 Ironforge  +68 Gnomeregan Exiles  +68 Darnassus  +68 Exodar",
                "R1: the capitals' quarter", Line(91003))
            local miss, why = A.RepEffects(77777)
            CHECK(miss == nil and why == "UNKNOWN_QUEST" and Line(77777) == nil,
                "R1: a quest Questie does not know has no answer (and no line)", why)
            miss, why = A.RepEffects("x")
            CHECK(miss == nil and why == "NO_QUEST", "R1: nor has a non-id", why)
            local first = A.RepEffects(9355)
            CHECK(rawequal(first, A.RepEffects(9355)), "R1: one answer per generation, shared")
            A.Bump("test")
            Advance(300)
            CHECK(not rawequal(A.RepEffects(9355), first), "R1: a new generation works it out again")
            local plain = A.RepEffects(9355, { pct = 100 }) or {}
            CHECK(plain[1] and plain[1].delta == 250 and not rawequal(plain, A.RepEffects(9355)),
                "R1: opts are answered fresh, never cached")
            local high = A.RepEffects(9355, { standings = { [946] = 42900 } }) or {}
            CHECK(high[1] and high[1].delta == 99 and high[1].capped == true,
                "R1: at 42,900 a +275 stops at the 42,999 ceiling", high[1] and high[1].delta)
            CHECK(A.RepLine(9355, { effects = high }) == "+99 Honor Hold (capped)", "R1: RepLine puts handed effects into words",
                A.RepLine(9355, { effects = high }))
            local loose = A.RepEffects(55555, { rows = { { 946, 250 } } })
            CHECK(loose and loose[1] and loose[1].delta == 275, "R1: rows handed in need no quest Questie knows")
            -- membership mirrors the engine's own preparation, on every quest
            local mismatched = {}
            local queryRows = fakeR.modules.QuestieDB.QueryQuestSingle
            for questId in pairs(fakeR.world.quests) do
                local effects = R.Effects(RepD, questId, queryRows(questId, "reputationReward") or {}, {}, 100)
                local engine, mine = {}, A._DirectRows(questId) or {}
                for _, entry in ipairs(effects) do if entry.kind == "DIRECT" then engine[entry.factionId] = true end end
                for factionId in pairs(engine) do
                    if mine[factionId] == nil then mismatched[#mismatched + 1] = questId .. ":" .. factionId end
                end
                for factionId in pairs(mine) do
                    if not engine[factionId] then mismatched[#mismatched + 1] = questId .. ":" .. factionId end
                end
            end
            CHECK(#mismatched == 0, "R1: DirectRows names the engine's DIRECT factions on every quest of the world",
                table.concat(mismatched, ","))
            local detail = A.QuestDetail(10326)
            CHECK(detail and #detail.repRewards == 2 and detail.repRewards[2].value == 125,
                "R1: the detail keeps Questie's raw rows for what they are")
            CHECK(detail and detail.repLine == Line(10326) and rawequal(detail.repEffects, A.RepEffects(10326)),
                "R1: ...and carries the one number")
            local view = A.ZoneView(3483)
            local job = view and view.byId[9355]
            CHECK(job and rawequal(job.fact.repEffects, A.RepEffects(9355)),
                "R1: a full zone view's facts carry the same effects")
            CHECK(job and job.fact.repRows and job.fact.repRows[1][1] == 946 and job.fact.repRows[1][2] == 250,
                "R1: ...and Questie's raw rows")
            local none = view and view.byId[91001]
            CHECK(none and none.fact.repRows == nil and #none.fact.repEffects == 0, "R1: no rows, no effects")
            -- a quest's waypoint carries what it is worth
            local L = ordersLog
            L.available, L.why = true, nil
            CommanderOrders = FakeOrders()
            A.Waypoint({ title = "A Job for an Intelligent Man", areaId = 3483, x = 56.6, y = 66.4, questId = 9355 })
            CHECK(L.adds[#L.adds].note == "+275 Honor Hold", "R1: a quest's waypoint is noted with its reputation",
                L.adds[#L.adds].note)
            A.Waypoint({ title = "Scout the Perimeter", areaId = 3483, x = 56.6, y = 66.4, questId = 91001 })
            CHECK(L.adds[#L.adds].note == "No reputation", "R1: ...No reputation included", L.adds[#L.adds].note)
            A.Waypoint({ title = "Mine", areaId = 3483, x = 56.6, y = 66.4, questId = 9355, note = "my own" })
            CHECK(L.adds[#L.adds].note == "my own", "R1: a note of the caller's own wins")
            A.Waypoint({ title = "None", areaId = 3483, x = 56.6, y = 66.4, questId = 9355, note = false })
            CHECK(L.adds[#L.adds].note == nil, "R1: note = false leaves it off")
            A.Waypoint({ title = "Somewhere", areaId = 3483, x = 56.6, y = 66.4 })
            CHECK(L.adds[#L.adds].note == nil, "R1: no quest, no note")
            CommanderQuestLogDB.ShowRepEverywhere = false
            A.Waypoint({ title = "Off", areaId = 3483, x = 56.6, y = 66.4, questId = 9355 })
            CHECK(L.adds[#L.adds].note == nil, "R1: Show Reputation Everywhere off leaves it off")
            CommanderQuestLogDB.ShowRepEverywhere = nil
            CommanderOrders = nil
            CHECK(A._LastError() == nil, "R1: no adapter error across the section", A._LastError())
        end

        -- -------------------------------------------------------------------
        -- R2. The faction index: read on first need, 400 quests a frame
        -- -------------------------------------------------------------------
        do
            local _, world = RepFresh(function(w) w.filler = 1000 end)
            local quests, paying = 0, 0
            for _, q in pairs(world.quests) do
                quests = quests + 1
                if q.reputationReward then paying = paying + 1 end
            end
            CHECK(A.FactionIndexState() == "NONE", "R2: the faction index is not read at login", A.FactionIndexState())
            local view, err = A.FactionView(946)
            CHECK(view == nil and err == "INDEXING", "R2: a faction asked about first says the index is being read", err)
            local state, done, total = A.FactionIndexState()
            CHECK(state == "BUILDING" and done == 0 and total == quests, "R2: ...and starts it over every quest",
                state .. " " .. done .. "/" .. total)
            Frame()
            state, done = A.FactionIndexState()
            CHECK(state == "BUILDING" and done == 400, "R2: 400 quests a frame", done)
            local generation = A.generation
            Settle()
            state, done, total = A.FactionIndexState()
            CHECK(state == "READY" and done == quests and total == quests, "R2: then complete", state)
            CHECK(A.generation > generation, "R2: ...and the generation steps, so the tab redraws")
            local index = A._FactionIndex()
            CHECK(index.ticks == 3 and index.paying == paying, "R2: three frames; every quest that pays reputation",
                tostring(index.ticks) .. " " .. tostring(index.paying) .. "/" .. paying)
            local by = index.byFaction or {}
            CHECK(by[946] and by[946][9355] == 250 and by[946][11354] == 350 and by[947] and by[947][11354] == 350,
                "R2: audited rows are members (Honor Hold and Thrallmar on 11354)")
            CHECK(by[935] and by[935][10886] == 500 and by[935][10326] == nil,
                "R2: a stored Sha'tar half is not a membership")
            CHECK(by[21] == nil and by[87] and by[87][9266] == -500 and by[577] and by[577][9266] == 500,
                "R2: nor is a goblin-town half; a negative row is")
            CHECK(by[99999] == nil, "R2: a faction with no standing slot has no members")
            CHECK(by[1077] and by[1077][11524] == 150 and by[1077][91010] == 500, "R2: quests Questie holds back are indexed too")
            CHECK(rawequal(A.FactionView(946), A.FactionView(946)), "R2: views are built once it is read")
            -- never read before Questie is ready, whoever asks
            local fakeR = RepFresh(function(w) w.ready = false end)
            A.RequestSummaries({ 946 }, function() end, "FACTION")
            Settle()
            CHECK(A.FactionIndexState() == "NONE" and #A.FactionMenu() == 0, "R2: nothing is read before Questie is ready")
            fakeR.SetReady()
            Settle()
            A.FactionMenu()
            Settle()
            CHECK(A.FactionIndexState() == "READY", "R2: ...and once it is, the first faction asked about starts it",
                A.FactionIndexState())
        end

        -- -------------------------------------------------------------------
        -- R3. Faction views
        -- -------------------------------------------------------------------
        do
            RepFresh()
            Indexed()
            local R = RepR
            local view, err = A.FactionView(946)
            CHECK(view and view.factionId == 946 and view.name == "Honor Hold" and view.areaId == nil,
                "R3: Honor Hold's view", err)
            CHECK(Ids(view and view.entries) == "9355,10106,10937,11354,11362,11363,11364,91002",
                "R3: its quests: the Wanted dailies the audit gave it, not the Horde's 10110", Ids(view and view.entries))
            local rep = view and view.rep or {}
            CHECK(rep.value == 4000 and rep.met == true and rep.word == "Friendly" and rep.progress == "Friendly 1,000 / 6,000"
                and rep.base == 0 and rep.pct == 110, "R3: its standing", rep.progress)
            CHECK(rep.toNext == 5000 and rep.toExalted == 38000, "R3: 5,000 to Honored, 38,000 to Exalted")
            CHECK(view and view.totals.counted == 3 and view.totals.done == 1, "R3: three count (dailies do not), one done",
                view and view.totals.counted)
            local totals = rep.totals or {}
            CHECK(totals.doneOnce == 1100 and totals.doneCount == 1 and totals.leftCount == 2 and totals.leftOnce == 385,
                "R3: about 1,100 done (an estimate), 385 left in two quests", totals.doneOnce)
            CHECK(rep.projection and rep.projection.reach == 4385 and rep.projection.rank == 4,
                "R3: quests alone take it to 4,385", rep.projection and rep.projection.reach)
            local job = view and view.byId[9355]
            CHECK(job and job.repEffect and job.repEffect.delta == 275 and job.repEffect.kind == "DIRECT",
                "R3: a row's badge is the engine's effect on this faction")
            local dailies = rep.dailies or { rotating = {} }
            CHECK(dailies.perDay == 165 and dailies.count == 1,
                "R3: daily income: Hellfire Fortifications; a rotating daily only on its day", dailies.perDay)
            local normal, heroic = dailies.rotating.NORMAL, dailies.rotating.HEROIC
            CHECK(normal and normal.known and normal.elsewhere and normal.today == nil,
                "R3: today's normal Wanted daily is another faction's")
            CHECK(heroic and heroic.known == false and heroic.candidates == 3 and heroic.best == 385,
                "R3: today's heroic is not known: three candidates, at most +385")
            CHECK(rep.rotatingToday and rep.rotatingToday.NORMAL == 11371 and rep.rotatingToday.HEROIC == nil,
                "R3: today's normal one is 11371")
            CHECK(rep.phaseHidden == 0 and rep.phaseKnown == true and #rep.dailyQuests == 5,
                "R3: nothing held back; five dailies listed")
            CHECK(rawequal(A.FactionView(946), view), "R3: a cache hit")
            local firstHonorHold = view
            local cache = A._RepCacheInfo()
            CHECK(cache.views == 1 and cache.order[1] == 946 and A._CacheInfo().views == 0,
                "R3: in the faction cache, never the zones' LRU")
            local summary = A.FactionSummary(946)
            CHECK(summary and summary.counted == 3 and summary.done == 1 and summary.value == 4000 and summary.reach == 4385
                and summary.quests == 8, "R3: its summary")
            CHECK(A.ZoneSummary(946) == nil, "R3: ...kept apart from the zones'")

            -- the Aldor: repeatables with their item costs, what the rival's quests cost it
            view = A.FactionView(932)
            CHECK(Ids(view and view.entries) == "10020,10021,10325,10326,10327,10421,10551", "R3: the Aldor's quests",
                Ids(view and view.entries))
            rep = view and view.rep or {}
            local costs = {}
            for _, c in ipairs(rep.costs or {}) do costs[#costs + 1] = c.questId .. ":" .. c.source .. ":" .. c.delta end
            CHECK(table.concat(costs, ",") == "10412:934:-302,10414:934:-29,10552:934:-4235",
                "R3: what the Scryers' quests would cost it", table.concat(costs, ","))
            local marks = Find(rep.repeatables, "questId", 10326)
            CHECK(marks and marks.perTurnIn == 275 and marks.cap == 8999 and marks.toCap == 19 and marks.toNext == nil
                and marks.costItem == 29425 and marks.costCount == 10 and marks.costToCap == 190
                and marks.costName == "Mark of Kil'jaeden",
                "R3: More Marks: 19 turn-ins (190 marks) to its 8,999 clamp; the item named from the client's cache",
                marks and marks.toCap)
            local single = Find(rep.repeatables, "questId", 10327)
            CHECK(single and single.perTurnIn == 27 and single.toCap == 186,
                "R3: a single mark is 27 (truncated, not 27.5): 186 of them to the clamp", single and single.toCap)
            local arms = Find(rep.repeatables, "questId", 10421)
            CHECK(arms and arms.perTurnIn == 385 and arms.toNext == 13 and arms.toExalted == 99 and arms.toCap == 102
                and arms.costName == "Fel Armament",
                "R3: Fel Armaments run to Exalted: 13 to Honored, 99 to Exalted; the item named from Questie's table",
                arms and arms.toExalted)
            CHECK(rep.totals.doneOnce == 4125 and rep.totals.doneCount == 2 and rep.totals.leftCount == 2,
                "R3: the pledge and one quest done (about 4,125), two left", rep.totals.doneOnce)
            CHECK(rep.projection.reach == 4660 and rep.projection.repeatReach == 42999,
                "R3: once-only quests take the Aldor to 4,660, its repeatables all the way", rep.projection.reach)

            -- the Sha'tar: its own quests and the Aldor and Scryers quests of its window
            view = A.FactionView(935)
            CHECK(Ids(view and view.entries) == "10020,10021,10210,10325,10326,10327,10412,10414,10421,10551,10552,10886",
                "R3: the Sha'tar's quests and those of its window", Ids(view and view.entries))
            rep = view and view.rep or {}
            local via = view and view.byId[10326]
            CHECK(via and via.layer == "EXTRA" and via.fact.repVia == 932 and via.counted == false and via.repEffect
                and via.repEffect.delta == 137 and via.repEffect.kind == "SPILL",
                "R3: a window quest is listed, not counted, with its source and its spill as the badge")
            local rival = view and view.byId[10412]
            CHECK(rival and rival.fact.repVia == 934 and rival.base == "RIVAL", "R3: the Scryers' side is the rival's")
            CHECK(view and view.totals.counted == 2 and view.totals.done == 1, "R3: only its own two count")
            local windows = rep.spill and rep.spill.windows or {}
            CHECK(#windows == 3 and windows[1].source == 932 and windows[1].open == true and windows[1].top == 8999
                and windows[2].source == 934 and windows[3].source == 936,
                "R3: windows from the Aldor, the Scryers and Shattrath City, open until 8,999", #windows)
            CHECK(rep.spill and #rep.spill.members == 10, "R3: ten window quests", rep.spill and #rep.spill.members)
            local window = rep.projection and rep.projection.spillWindow
            CHECK(rep.projection and rep.projection.reach == 2879 and window and window.landed == 329 and window.source == 932,
                "R3: the window first (the Aldor's two open quests, +329), then its own (+550): 2,879",
                rep.projection and rep.projection.reach)
            CommanderQuestLogDB.CountExtras = true
            A.Bump("settings")
            Advance(300)
            view = A.FactionView(935)
            CHECK(view and view.totals.counted == 2, "R3: window quests never count, whatever Count Extras says",
                view and view.totals.counted)
            CommanderQuestLogDB.CountExtras = nil

            -- the Consortium: gates that close as it rises
            view = A.FactionView(933)
            rep = view and view.rep or {}
            CHECK(rep.phaseHidden == 2 and Contains(rep.phaseHiddenIds, 11499) and Contains(rep.phaseHiddenIds, 11500),
                "R3: the Magisters' Terrace dailies are not in this phase yet", rep.phaseHidden)
            local hints = rep.projection and rep.projection.orderHints or {}
            CHECK(#hints == 2 and hints[1] == 'Do "A Head Full of Ivory" before Friendly'
                and hints[2] == 'Do "Stealing from Thieves" before Friendly',
                "R3: the quests that lock as it rises, in the order they close", table.concat(hints, " | "))
            CHECK(rep.projection and rep.projection.reach == 3575
                and table.concat(rep.projection.order, ",") == "9914,9882,9900,10165",
                "R3: the closing quests first, soonest-closing first: 3,575",
                rep.projection and table.concat(rep.projection.order, ","))
            CHECK(rep.dailies and rep.dailies.perDay == 275 and rep.dailies.count == 1
                and rep.dailies.rotating.NORMAL.today == 11371, "R3: today's normal Wanted daily is the Consortium's",
                rep.dailies and rep.dailies.perDay)
            local crystals = Find(rep.repeatables, "questId", 9883)
            CHECK(crystals and crystals.toNext == 3 and crystals.cap == 3025 and crystals.costItem == 25416
                and crystals.costName == nil,
                "R3: More Crystal Fragments: three to Friendly, where it closes; an uncached item has no name yet")

            -- held back, not met
            view, err = A.FactionView(1077)
            CHECK(view and #view.entries == 0 and view.rep.phaseHidden == 4 and view.rep.value == 0 and view.rep.met == false,
                "R3: the Shattered Sun: nothing in this phase, four quests held back for a later one", err)
            view = A.FactionView(1015)
            rep = view and view.rep or {}
            CHECK(Ids(view and view.entries) == "10871,11015", "R3: Netherwing's quests for a Human (10870 is everyone else's)",
                Ids(view and view.entries))
            CHECK(rep.value == -42000 and rep.met == false and rep.base == -42000 and rep.word == "Hated"
                and rep.progress == "Hated 0 / 36,000", "R3: not met: at its base, never Neutral", rep.progress)
            CHECK(rep.projection and rep.projection.reach == 0 and rep.projection.left == 42000 and rep.projection.rank == 3,
                "R3: Ally of the Netherwing lands it on exactly 0")
            CHECK(rep.dailies and rep.dailies.perDay == 0, "R3: a daily locked behind Neutral earns nothing yet")
            view = A.FactionView(970)
            rep = view and view.rep or {}
            CHECK(rep.value == -2500 and rep.met == false and rep.word == "Unfriendly" and rep.projection.reach == -1675,
                "R3: Sporeggar from its base: The Sporelings' Plight takes it to -1,675", rep.projection and rep.projection.reach)
            local sacs = Find(rep.repeatables, "questId", 9742)
            CHECK(sacs and sacs.perTurnIn == 825 and sacs.toNext == 4 and sacs.toCap == 7,
                "R3: More Spore Sacs: four to Neutral, seven before its gate closes")

            -- area 47 is The Hinterlands, faction 47 is Ironforge
            local zone = A.ZoneView(47)
            local faction = A.FactionView(47)
            CHECK(zone and zone.areaId == 47 and zone.name == "The Hinterlands" and faction and faction.factionId == 47
                and faction.name == "Ironforge" and not rawequal(zone, faction),
                "R3: area 47 and faction 47 are two views")
            CHECK(rawequal(A.ZoneView(47), zone) and rawequal(A.FactionView(47), faction), "R3: each in its own cache")
            local shares = faction and faction.rep.spill.shares or {}
            CHECK(#shares == 1 and shares[1].source == 72 and shares[1].quests == 1 and shares[1].total == 68,
                "R3: Stormwind's quests reach Ironforge as a quarter: summed, not listed")
            CHECK(A.ZoneSummary(47) and A.ZoneSummary(47).counted == 1 and A.FactionSummary(47)
                and A.FactionSummary(47).quests == 1, "R3: ...and two summaries")
            CHECK(A._RepCacheInfo().views == 2, "R3: two faction views kept", A._RepCacheInfo().views)
            local hh = A.FactionView(946)
            CHECK(hh and not rawequal(hh, firstHonorHold) and A._RepCacheInfo().order[2] == 946,
                "R3: an evicted faction is built again")
            local detail = A.QuestDetail(10326, 935, "FACTION")
            CHECK(detail and detail.name == "More Marks of Kil'jaeden"
                and detail.repLine == "+275 The Aldor  -302 The Scryers  +137 The Sha'tar",
                "R3: a quest's detail read from a faction view", detail and detail.repLine)
            view, err = A.FactionView(947)
            CHECK(view == nil and err == "OTHER_SIDE", "R3: the other side's faction has no view", err)
            view, err = A.FactionView(99999)
            CHECK(view == nil and err == "NO_FACTION", "R3: nor has an id the data does not know", err)
            view, err = A.FactionView(54)
            CHECK(view == nil and err == "NO_QUESTS", "R3: a faction reached only as a quarter has no quests of its own", err)
            CHECK(A._LastError() == nil, "R3: no adapter error across the section", A._LastError())

            -- a change in the log's ready set is a bump with only a faction view cached
            RepFresh()
            Indexed()
            local shatar = A.FactionView(935)
            local generation = A.generation
            CHECK(A._CacheInfo().views == 0, "R3: no zone view cached")
            A.SetLogEntries({ { isHeader = false, questID = 10886, isComplete = true, isFailed = false } })
            Advance(300)
            CHECK(A.generation == generation + 1 and not rawequal(A.FactionView(935), shatar),
                "R3: the log's ready set changing is a bump while a faction view is up")
        end

        -- -------------------------------------------------------------------
        -- R4. The picker
        -- -------------------------------------------------------------------
        do
            RepFresh()
            local menu = A.FactionMenu()
            local alliance = Find(menu, "key", "ALLIANCE")
            CHECK(#menu == 6 and alliance and #alliance.items == 8 and alliance.items[1].quests == nil,
                "R4: while the index is read, every faction of your side is listed, uncounted", #menu)
            Settle()
            menu = A.FactionMenu()
            local keys = {}
            for i, group in ipairs(menu) do keys[i] = group.key end
            CHECK(table.concat(keys, ",") == "OUTLAND,SHATTRATH,TBC_OTHER,ALLIANCE,STEAMWHEEDLE,CLASSIC_OTHER",
                "R4: the data's groups in order, no Horde group for the Alliance", table.concat(keys, ","))
            local function GroupIds(key)
                local group = Find(menu, "key", key)
                local ids = {}
                for i, item in ipairs(group and group.items or {}) do ids[i] = item.factionId end
                return table.concat(ids, ","), group
            end
            local outland, og = GroupIds("OUTLAND")
            CHECK(outland == "1012,942,933,946,978,1015,1038,970", "R4: Outland without the Horde's Mag'har and Thrallmar",
                outland)
            CHECK(og and og.text == "Outland" and og.tbc == true, "R4: titled from the data while the client has no header name")
            local hh = Find(og and og.items, "factionId", 946)
            CHECK(hh and hh.name == "Honor Hold" and hh.word == "Friendly" and hh.quests == 8
                and hh.note == "Friendly  \194\183  8 quests", "R4: a faction: name, standing, quests", hh and hh.note)
            local nether = Find(og and og.items, "factionId", 1015)
            CHECK(nether and nether.met == false and nether.value == -42000 and nether.word == "Hated" and nether.quests == 2,
                "R4: a faction not met, at its base")
            local ogri = Find(og and og.items, "factionId", 1038)
            CHECK(ogri and ogri.quests == 0 and ogri.name == "Ogri'la", "R4: a TBC faction is listed with no quest for you")
            local shattrath, sg = GroupIds("SHATTRATH")
            CHECK(shattrath == "932,1011,934,935,1031,1077", "R4: Shattrath City", shattrath)
            local sso = Find(sg and sg.items, "factionId", 1077)
            CHECK(sso and sso.quests == 0 and sso.phaseHidden == 4
                and sso.note == "Neutral  \194\183  0 quests  \194\183  4 not in this phase yet",
                "R4: the Shattered Sun: none yet, four in a later phase", sso and sso.note)
            CHECK((GroupIds("TBC_OTHER")) == "930,989,990,967", "R4: the other TBC factions, the Horde's two left out",
                (GroupIds("TBC_OTHER")))
            CHECK((GroupIds("ALLIANCE")) == "47,72", "R4: classic factions only with a quest of their own",
                (GroupIds("ALLIANCE")))
            CHECK((GroupIds("STEAMWHEEDLE")) == "577", "R4: Everlook; the other towns only through stored spillover",
                (GroupIds("STEAMWHEEDLE")))
            CHECK((GroupIds("CLASSIC_OTHER")) == "87", "R4: the Bloodsail, whom Making Amends costs",
                (GroupIds("CLASSIC_OTHER")))
            CommanderQuestLogDB.RepIncludeClassic = false
            menu = A.FactionMenu()
            CHECK(#menu == 3 and menu[3].key == "TBC_OTHER", "R4: classic factions off: the TBC groups alone", #menu)
            CommanderQuestLogDB.RepIncludeClassic = nil
        end

        -- -------------------------------------------------------------------
        -- R5. Faction summaries in the background
        -- -------------------------------------------------------------------
        do
            RepFresh(function(w) w.filler = 1000 end)
            local got = {}
            A.RequestSummaries({ 946, 1077, 932 }, function(factionId, summary)
                got[#got + 1] = factionId .. ":" .. tostring(summary.counted)
            end, "FACTION")
            Frame()
            Frame()
            CHECK(#got == 0 and A.FactionIndexState() == "BUILDING", "R5: a faction job waits while the index is read")
            Settle()
            CHECK(table.concat(got, ",") == "946:3,1077:0,932:4", "R5: then one faction a tick", table.concat(got, ","))
            local stale = A.FactionSummary(946, true)
            CHECK(stale and stale.reach == 4385 and stale.quests == 8 and A.ZoneSummary(946, true) == nil,
                "R5: faction summaries, never the zones'")
            CHECK(A.FactionSummary(946) == nil and stale.generation < A.generation,
                "R5: ...by generation: the index's own step has passed them (a label reads them stale)")
            CHECK(A._RepCacheInfo().views == 0 and A._RepCacheInfo().summaries == 3, "R5: a summary keeps no view")
        end

        -- -------------------------------------------------------------------
        -- R6. What a zone's quests are worth, per faction
        -- -------------------------------------------------------------------
        do
            RepFresh()
            local totals = A.ZoneRepTotals(3483)
            local order = {}
            for i, t in ipairs(totals) do order[i] = t.factionId end
            CHECK(table.concat(order, ",") == "946,933",
                "R6: Hellfire pays Honor Hold and the Consortium; Thrallmar's rows are the other side's", table.concat(order, ","))
            local hh = totals[1] or {}
            CHECK(hh.remainingOnce == 385 and hh.doneOnce == 1100 and hh.doneCount == 1 and hh.leftCount == 2
                and hh.reach == 4385 and hh.reachesNext == false and hh.reachesExalted == false and hh.word == "Friendly",
                "R6: Honor Hold: 385 left once-only, about 1,100 done; not enough for Honored", hh.remainingOnce)
            CHECK(hh.repeatables and #hh.repeatables == 5 and hh.repeatablesPerTurnIn == 385,
                "R6: ...five dailies, the best +385 a turn-in", hh.repeatables and #hh.repeatables)
            local cons = totals[2] or {}
            CHECK(cons.remainingOnce == 0 and cons.repeatables and #cons.repeatables == 4 and cons.word == "Neutral",
                "R6: the Consortium only through its Wanted dailies")
            totals = A.ZoneRepTotals(3703)
            local shatar = Find(totals, "factionId", 935)
            local aldor = Find(totals, "factionId", 932)
            CHECK(totals[1] and totals[1].factionId == 935 and shatar.remainingOnce == 879 and shatar.viaSpill == 329,
                "R6: Shattrath: the Sha'tar first, its window from the Aldor's open quests counted (+329)",
                shatar and shatar.remainingOnce)
            CHECK(aldor and aldor.remainingOnce == 660 and aldor.doneOnce == 4125 and #aldor.repeatables == 3,
                "R6: the Aldor: 660 left, about 4,125 done, three repeatables", aldor and aldor.remainingOnce)
            CHECK(Find(totals, "factionId", 934) == nil, "R6: the rival's quests pay this character nothing to count")
            CHECK(#A.ZoneRepTotals(99999) == 0, "R6: no zone, no totals")
        end

        -- -------------------------------------------------------------------
        -- R7. The character: standings, the multiplier, the side
        -- -------------------------------------------------------------------
        do
            local fakeR = RepFresh()
            local char = A.Character()
            CHECK(char.repPct == 110 and char.repSide == "Alliance", "R7: the character carries its multiplier and side")
            CHECK(char.standing(1015) == -42000 and char.standing(970) == -2500 and char.standing(978) == -1200
                and char.standing(946) == 4000, "R7: standing(): the bar, or the base for a faction not met")
            CHECK(char.repValue(1015) == nil, "R7: repValue keeps its meaning (unknown never locks)")
            local spore = A.FactionStanding(970)
            CHECK(spore and spore.value == -2500 and spore.met == false and spore.word == "Unfriendly"
                and spore.progress == "Unfriendly 500 / 3,000" and spore.name == "Sporeggar" and spore.base == -2500,
                "R7: a faction's standing without a view", spore and spore.progress)
            CHECK(A.FactionStanding(99999) == nil, "R7: nothing for an id the data does not know")
            CHECK(A.FactionName(935) == "The Sha'tar" and A.FactionName(1015) == "Netherwing",
                "R7: names: the client's once met, the data's before")
            local generation = A.generation
            fakeR.SetAura(24705, true)
            Fire("UNIT_AURA", "target")
            Advance(1000)
            CHECK(A.generation == generation, "R7: another unit's auras are not looked at")
            Fire("UNIT_AURA", "player")
            Advance(1000)
            CHECK(A.generation == generation + 1, "R7: the Wickerman taken is a bump", A.generation - generation)
            CHECK(A.RepMultiplier() == 120 and A.Character().repPct == 120 and Line(9355) == "+300 Honor Hold",
                "R7: ...and 250 is +300 under it", Line(9355))
            local joined = table.concat(A.StatusLines(), "\n")
            CHECK(joined:find("Reputation multiplier: 120% (Diplomacy, Invocation of the Wickerman)", 1, true),
                "R7: status says why", joined)
            Fire("UNIT_AURA", "player")
            Advance(1000)
            CHECK(A.generation == generation + 1, "R7: an aura change that moves nothing is no bump")
            fakeR.SetAura(24705, false)
            local byId = C_UnitAuras.GetPlayerAuraBySpellID
            C_UnitAuras.GetPlayerAuraBySpellID = nil
            fakeR.SetAura(24705, true)
            CHECK(select(2, A.RepMultiplier()).wickerman == true, "R7: without the by-id call, a buff scan finds it")
            local auras = C_UnitAuras
            C_UnitAuras = nil
            CHECK(select(2, A.RepMultiplier()).wickerman == true, "R7: without C_UnitAuras, UnitBuff does")
            C_UnitAuras = auras
            C_UnitAuras.GetPlayerAuraBySpellID = byId
            fakeR.SetAura(24705, false)
            CHECK(A.RepMultiplier() == 110, "R7: gone again: 110")

            -- an Orc: no Diplomacy, the Horde's rows, a reward clamp
            RepFresh(function(w)
                w.player.race, w.player.raceFile, w.player.raceId, w.player.faction = "Orc", "Orc", 2, "Horde"
                w.reps[932] = 8900
                w.factions[947], w.reps[947] = "Thrallmar", 1000
                w.factions[946], w.reps[946] = nil, nil
            end)
            CHECK(A.RepMultiplier() == 100 and A.Character().repSide == "Horde", "R7: an Orc is paid at 100%")
            CHECK(Line(10326) == "+99 The Aldor (capped)  -108 The Scryers  +49 The Sha'tar",
                "R7: at 8,900 More Marks stops at 8,999; the spill comes from the clamped gain", Line(10326))
            CHECK(Line(11354) == "+350 The Consortium  +350 Thrallmar", "R7: the Horde is paid Thrallmar's row, not Honor Hold's",
                Line(11354))
            CHECK(A.FactionStanding(941).value == -500 and A.FactionStanding(946).value == -42000,
                "R7: the Mag'har's base for an Orc; the other side's -42,000")
            local view, err = A.FactionView(946)
            CHECK(view == nil and err == "OTHER_SIDE", "R7: Honor Hold is the other side's", err)
            Indexed()
            view = A.FactionView(947)
            CHECK(view and Ids(view.entries) == "10110,11354,11362,11363,11364", "R7: Thrallmar's quests for the Horde",
                view and Ids(view.entries))
            local outland = Find(A.FactionMenu(), "key", "OUTLAND")
            local ids = {}
            for i, item in ipairs(outland and outland.items or {}) do ids[i] = item.factionId end
            CHECK(table.concat(ids, ",") == "1012,942,933,941,1015,1038,970,947", "R7: the Horde's Outland",
                table.concat(ids, ","))
        end

        -- -------------------------------------------------------------------
        -- R8. Today's rotating dailies; quests held back by phase
        -- -------------------------------------------------------------------
        do
            local fakeR = RepFresh()
            local today = A.RotatingToday()
            CHECK(today.NORMAL == 11371 and today.HEROIC == nil,
                "R8: Questie's record leaves one normal Wanted daily (the held-back one is never a candidate)")
            fakeR.SetUnavailable(11362, true)
            CHECK(A.RotatingToday().HEROIC == 11363, "R8: one more NPC talked to settles the heroic")
            fakeR.ResetDailies()
            today = A.RotatingToday()
            CHECK(today.NORMAL == nil and today.HEROIC == nil,
                "R8: after the reset (Questie replaces its table) nothing is known: no stale copy kept")
            fakeR.SetInLog(11362, true)
            CHECK(A.RotatingToday().HEROIC == 11362, "R8: one in the log is today's")
            fakeR.SetInLog(11362, false)
            fakeR.SetUnavailable(11354, true)
            fakeR.SetUnavailable(11364, true)
            fakeR.SetUnavailable(11376, true)
            fakeR.modules.AvailableQuests.__unavailableQuestsDeterminedByTalking = nil
            CHECK(A.RotatingToday().NORMAL == 11371, "R8: read from Questie's saved record by realm, not only its alias")
            fakeR.ResetDailies()
            fakeR.SetUnavailable(11354, true)
            local record = Fake.DeepCopy(Questie.db.global.unavailableQuestsDeterminedByTalking)
            Indexed()
            A.FactionView(933)
            A.RotatingToday()
            A.StatusLines()
            CHECK(DeepEqual(record, Questie.db.global.unavailableQuestsDeterminedByTalking),
                "R8: Questie's record is read, never written")
            CHECK(fakeR.calls.BlacklistTbcQuestsByPhase == 1, "R8: Questie's phase list is read once",
                fakeR.calls.BlacklistTbcQuestsByPhase)
            RepFresh(function(w) w.contentPhases = nil end)
            Indexed()
            local sso = A.FactionView(1077)
            CHECK(sso and sso.rep.phaseHidden == 5 and sso.rep.phaseKnown == false,
                "R8: without Questie's phase list, every quest it holds back that would pay (not the Horde's)",
                sso and sso.rep.phaseHidden)
            RepFresh(function(w) w.locale = "deDE" end)
            CHECK(A.FactionName(1015) == "Netherschwingen" and A.FactionName(935) == "The Sha'tar",
                "R8: a faction not met has this locale's name from the data; a met one the client's")
            RepFresh(function(w) w.player.sex = 3; w.femaleLabels = { [5] = "Friendly (her)" } end)
            CHECK(A.FactionStanding(946).word == "Friendly (her)", "R8: standing words in the client's own form for her",
                A.FactionStanding(946).word)
        end

        -- -------------------------------------------------------------------
        -- R9. Calibration: what the bars did on a turn-in
        -- -------------------------------------------------------------------
        do
            local fakeR, world = RepFresh()
            local function Sample(questId, factionId)
                local store = type(CommanderQuestLogChar) == "table" and CommanderQuestLogChar.RepObserved
                return type(store) == "table" and store[questId] and store[questId][factionId] or nil
            end
            CHECK(CommanderQuestLogChar.RepObserved == nil, "R9: no store before the first sample")
            -- an emulator's order: the bar moves, then QUEST_TURNED_IN
            fakeR.SetRep(946, 4275)
            Fire("UPDATE_FACTION")
            Frame()
            Fire("QUEST_TURNED_IN", 9355, 0, 0)
            fakeR.Complete(9355)
            Advance(2500)
            local s = Sample(9355, 946)
            CHECK(s and s.raw == 250 and s.delta == 275 and s.n == 1 and s.kind == "DIRECT",
                "R9: +275 seen on a Human is stored as the listed 250", s and s.raw)
            local generationLine = A.StatusLines()[4] or ""
            CHECK(generationLine:find("calibration", 1, true), "R9: a sample is a bump", generationLine)
            local seen = A.RepEffects(9355) or {}
            CHECK(seen[1] and seen[1].observed == true and Line(9355) == "+275 Honor Hold", "R9: the quest reads as seen in game")
            -- the other order: QUEST_TURNED_IN, then the bar a frame later
            Fire("QUEST_TURNED_IN", 10030, 0, 0)
            Frame()
            fakeR.SetRep(1011, 275)
            Fire("UPDATE_FACTION")
            Advance(2500)
            s = Sample(10030, 1011)
            CHECK(s and s.raw == 250, "R9: the window runs both ways", s and s.raw)
            -- the data overruled, by a faction met for the first time
            fakeR.Meet(970, -2225)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 9739, 0, 0)
            Advance(2500)
            s = Sample(9739, 970)
            CHECK(s and s.raw == 250 and s.delta == 275,
                "R9: Sporeggar met by its first quest moves from its base: +275 seen is 250 listed, not Questie's 750",
                s and s.raw)
            local spore = A.RepEffects(9739) or {}
            CHECK(spore[1] and spore[1].delta == 275 and spore[1].observed == true and Line(9739) == "+275 Sporeggar",
                "R9: what was seen overrides the data", Line(9739))
            Indexed()
            local sporeggar = A.FactionView(970)
            local plight = sporeggar and Find(sporeggar.rep.direct, "questId", 9739)
            CHECK(plight and plight.observed == true and plight.raw == 250 and sporeggar.rep.observed == 1
                and sporeggar.rep.projection.reach == -1950,
                "R9: ...in the faction view too: the projection counts what was seen (-2,225 + 275)",
                sporeggar and sporeggar.rep.projection.reach)
            -- the chat line stands in when the snapshot saw nothing
            Fire("QUEST_TURNED_IN", 10918, 0, 0)
            Fire("CHAT_MSG_COMBAT_FACTION_CHANGE", "Reputation with Lower City increased by 275.")
            Advance(2500)
            s = Sample(10918, 1011)
            CHECK(s and s.raw == 250, "R9: the chat line is the second source", s and s.raw)
            -- a DIRECT row that did not move while the rest of the quest did
            fakeR.SetRep(933, 2475)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 11371, 0, 0)
            Advance(2500)
            CHECK(Sample(11371, 933) and Sample(11371, 933).raw == 250 and Sample(11371, 942)
                and Sample(11371, 942).raw == 0, "R9: a row that did not move while the quest's other did: a sample of 0")
            CHECK(Line(11371) == "+275 The Consortium  0 Cenarion Expedition", "R9: ...which the line shows", Line(11371))
            -- two turn-ins close enough to share a faction: both set aside
            local observer = A._RepObserver()
            local aside = observer.dropped
            fakeR.SetRep(932, 4275)
            fakeR.SetRep(934, -4702)
            fakeR.SetRep(935, 2137)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 10326, 0, 0)
            Advance(400)
            fakeR.SetRep(932, 4550)
            fakeR.SetRep(934, -5004)
            fakeR.SetRep(935, 2274)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 10326, 0, 0)
            Advance(3000)
            CHECK(CommanderQuestLogChar.RepObserved[10326] == nil and observer.dropped == aside + 6
                and (observer.why.ambiguous or 0) == 6,
                "R9: two turn-ins of one quest in quick succession teach nothing (each faction set aside)",
                observer.dropped - aside)
            -- two turn-ins whose moves one snapshot read caught together: one
            -- move of +440 on a faction both pay is nobody's
            fakeR.SetRep(946, world.reps[946] + 440)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 9355, 0, 0)
            Fire("QUEST_TURNED_IN", 10106, 0, 0)
            Advance(3000)
            CHECK(Sample(10106, 946) == nil and Sample(9355, 946).n == 1 and (observer.why.ambiguous or 0) == 8,
                "R9: a move two turn-ins could both own is set aside for both", observer.why.ambiguous)
            -- a faction that moved twice in the window: a kill, then the quest
            fakeR.SetRep(946, 4290)
            Fire("UPDATE_FACTION")
            Frame()
            fakeR.SetRep(946, 4455)
            Fire("UPDATE_FACTION")
            Frame()
            Fire("QUEST_TURNED_IN", 10106, 0, 0)
            Advance(2500)
            CHECK(Sample(10106, 946) == nil and observer.why.ambiguous == 9, "R9: a faction that moved twice is set aside",
                observer.why.ambiguous)
            -- a reward clamp cut the turn-in: nothing learned, not even the spill off it
            fakeR.SetRep(932, 8900)
            Fire("UPDATE_FACTION")
            Advance(3000)
            fakeR.SetRep(932, 8999)
            fakeR.SetRep(934, world.reps[934] - 108)
            fakeR.SetRep(935, world.reps[935] + 49)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 10326, 0, 0)
            Advance(2500)
            CHECK(CommanderQuestLogChar.RepObserved[10326] == nil and observer.why["source capped"] == 2
                and (observer.why["reward clamp"] or 0) >= 1,
                "R9: a clamped turn-in is no sample, nor are the spills off it")
            -- normalised by the multiplier of the moment
            fakeR.SetAura(24705, true)
            Fire("UNIT_AURA", "player")
            Advance(1000)
            fakeR.SetRep(933, world.reps[933] + 600)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 10165, 0, 0)
            Advance(2500)
            s = Sample(10165, 933)
            CHECK(s and s.raw == 500 and s.pct == 120 and s.delta == 600,
                "R9: +600 seen under the Wickerman is stored as the listed 500", s and s.raw)
            fakeR.SetAura(24705, false)
            Fire("UNIT_AURA", "player")
            Advance(1000)
            CHECK(Line(10165) == "+550 The Consortium", "R9: ...so without it the quest reads +550", Line(10165))
            -- what cannot be a sample
            Fire("QUEST_TURNED_IN", 77777, 0, 0)
            Advance(2500)
            CHECK(observer.why["unknown quest"] == 1, "R9: a quest Questie does not know")
            Fire("QUEST_TURNED_IN", 9900, 0, 0)
            Advance(2500)
            CHECK(observer.why["no move seen"] == 1 and Sample(9900, 933) == nil, "R9: a turn-in that moved nothing")
            local saved = CommanderQuestLogChar
            CommanderQuestLogChar = nil
            fakeR.SetRep(1011, world.reps[1011] + 275)
            Fire("UPDATE_FACTION")
            Fire("QUEST_TURNED_IN", 10030, 0, 0)
            Advance(2500)
            CHECK(observer.why["no saved variables"] == 1 and CommanderQuestLogChar == nil,
                "R9: no saved variables yet: nothing written, no global made")
            CommanderQuestLogChar = saved
            -- the chat line, read with the client's own strings
            local factionId, delta = A._ParseRepChat("Reputation with The Sha'tar increased by 137.")
            CHECK(factionId == 935 and delta == 137, "R9: chat: an increase")
            factionId, delta = A._ParseRepChat("Reputation with The Scryers decreased by 302.")
            CHECK(factionId == 934 and delta == -302, "R9: chat: a decrease")
            factionId, delta = A._ParseRepChat("Reputation with Honor Hold increased by 5. (+1.0 bonus)")
            CHECK(factionId == 946 and delta == 5, "R9: chat: the bonus form")
            CHECK(A._ParseRepChat("Reputation with Honor Hold increased.") == nil
                and A._ParseRepChat("You are now Friendly with Honor Hold.") == nil
                and A._ParseRepChat("Reputation with Nobody increased by 5.") == nil,
                "R9: chat: no amount, a rank-up line, a name that is no faction")
            local joined = table.concat(A.StatusLines(), "\n")
            CHECK(joined:find("Reputation seen in game: 6 quests, 7 samples (", 1, true),
                "R9: status counts what was seen and what was set aside", joined)
            -- a locale that puts the number first, and the data's name for it
            RepFresh(function(w) w.locale = "deDE" end)
            local english = FACTION_STANDING_INCREASED
            FACTION_STANDING_INCREASED = "%2$d Ruf mehr bei %1$s."
            factionId, delta = A._ParseRepChat("137 Ruf mehr bei Die Sha'tar.")
            CHECK(factionId == 935 and delta == 137, "R9: chat: the number first, the faction by this locale's name")
            FACTION_STANDING_INCREASED = english
        end

        -- -------------------------------------------------------------------
        -- R10. The guards: no rules, a raising engine
        -- -------------------------------------------------------------------
        do
            RepFresh()
            Indexed()
            local standing = Q.Standing
            Q.Standing = nil
            local effects, why = A.RepEffects(9355)
            CHECK(effects == nil and why == "NO_RULES" and A.RepLine(9355) == nil,
                "R10: without the rules engine there is no number, quietly", why)
            local view, err = A.FactionView(946)
            CHECK(view == nil and err == "NO_RULES" and #A.FactionMenu() == 0 and #A.ZoneRepTotals(3483) == 0,
                "R10: ...no faction view, no picker, no totals", err)
            local detail = A.QuestDetail(9355)
            CHECK(detail and detail.repEffects == nil and detail.repLine == nil and #detail.repRewards == 1,
                "R10: the detail carries Questie's raw rows alone")
            CHECK(A.ZoneView(3483) ~= nil and A.Character().repPct == nil, "R10: zone views and the character as before")
            local joined = table.concat(A.StatusLines(), "\n")
            CHECK(joined:find("Reputation rules: the rules engine did not load", 1, true), "R10: status says why", joined)
            Q.Standing = standing
            local data = CommanderQuestLogReputationData
            CommanderQuestLogReputationData = nil
            joined = table.concat(A.StatusLines(), "\n")
            CHECK(joined:find("Reputation rules: the reputation data did not load", 1, true) and A.RepLine(9355) == nil,
                "R10: ...or the data")
            CommanderQuestLogReputationData = data
            CHECK(A._LastError() == nil, "R10: missing rules are not an error", A._LastError())
            local project = standing.Project
            standing.Project = function() error("projection broke") end
            A.Bump("test")
            Advance(300)
            view, err = A.FactionView(946)
            CHECK(view == nil and err == "ADAPTER_ERROR" and (A._LastError() or ""):find("FactionView", 1, true),
                "R10: a raising engine costs the view, never a Lua error; the error is kept for /cql status", A._LastError())
            standing.Project = project
            local effectsFn = standing.Effects
            standing.Effects = function() error("effects broke") end
            A.Bump("test")
            Advance(300)
            CHECK(A.RepEffects(9355) == nil and A.RepLine(9355) == nil, "R10: ...nor the number")
            local zone = A.ZoneView(3483)
            CHECK(zone ~= nil and (A._LastError() or ""):find("reputation effects", 1, true),
                "R10: ...and the zone view is still built", A._LastError())
            standing.Effects = effectsFn
            CHECK(#caughtErrors == 0, "R10: nothing reached the error handler", caughtErrors[1])
        end

        -- -------------------------------------------------------------------
        -- R11. /cql status
        -- -------------------------------------------------------------------
        do
            RepFresh()
            local joined = table.concat(A.StatusLines(), "\n")
            CHECK(joined:find("Reputation rules: loaded (data for 2.5.6.69795)", 1, true), "R11: the rules", joined)
            CHECK(joined:find("Faction index: not read yet", 1, true), "R11: the index, not read yet")
            CHECK(joined:find("Reputation multiplier: 110% (Diplomacy)", 1, true), "R11: the multiplier and why")
            CHECK(joined:find("Reputation seen in game: 0 quests, 0 samples", 1, true), "R11: the calibration count")
            CHECK(joined:find("Cached: 0 faction views, 0 faction summaries", 1, true), "R11: the faction cache")
            CHECK(joined:find("Wanted dailies today: normal Wanted: Coilfang Myrmidons, heroic not known yet", 1, true),
                "R11: today's Wanted dailies")
            Indexed()
            A.FactionView(946)
            local index = A._FactionIndex()
            local lines = A.StatusLines()
            joined = table.concat(lines, "\n")
            CHECK(joined:find(string.format("Faction index: complete (%d quests read, %d pay reputation, %d factions)",
                index.quests or -1, index.paying or -1, index.factions or -1), 1, true), "R11: the index, complete", joined)
            CHECK(joined:find("Cached: 1 faction view, 1 faction summary", 1, true), "R11: one of each")
            local clean = true
            for _, line in ipairs(lines) do if not GlyphFree(line) then clean = false end end
            CHECK(clean, "R11: no shape glyph in a status line")
        end

        -- -------------------------------------------------------------------
        -- R12. The same number on every surface
        -- -------------------------------------------------------------------
        do
            RepFresh()
            Indexed()
            ordersLog.available, ordersLog.why = true, nil
            CommanderOrders = FakeOrders()
            local bad, quests = {}, 0
            for _, areaId in ipairs({ 3483, 3703, 3519, 3518, 3521, 3520, 12, 47, 33 }) do
                local view = A.ZoneView(areaId)
                for _, entry in ipairs(view and view.entries or {}) do
                    local questId = entry.id
                    local line = A.RepLine(questId)
                    quests = quests + 1
                    if not (line and rawequal(entry.fact.repEffects, A.RepEffects(questId))) then
                        bad[#bad + 1] = "zone:" .. questId
                    end
                    local detail = A.QuestDetail(questId, areaId)
                    if not (detail and detail.repLine == line) then bad[#bad + 1] = "detail:" .. questId end
                    A.Waypoint({ title = "x", areaId = areaId, x = 50, y = 50, questId = questId })
                    if ordersLog.adds[#ordersLog.adds].note ~= line then bad[#bad + 1] = "waypoint:" .. questId end
                end
            end
            for _, factionId in ipairs({ 946, 932, 935, 933, 1015, 970, 978, 942, 1011, 47, 72, 577, 87 }) do
                local view = A.FactionView(factionId)
                for _, entry in ipairs(view and view.entries or {}) do
                    local effect = RepR.For(A.RepEffects(entry.id), factionId)
                    quests = quests + 1
                    if not (entry.repEffect and effect and entry.repEffect.delta == effect.delta
                        and entry.repEffect.kind == effect.kind) then
                        bad[#bad + 1] = "faction:" .. factionId .. ":" .. entry.id
                    end
                    local detail = A.QuestDetail(entry.id, factionId, "FACTION")
                    if not (detail and detail.repLine == A.RepLine(entry.id)) then
                        bad[#bad + 1] = "faction detail:" .. factionId .. ":" .. entry.id
                    end
                end
            end
            CHECK(#bad == 0 and quests > 60,
                "R12: every surface shows the same number for the same quest (zone rows, the detail, waypoint notes, faction rows)",
                #bad > 0 and table.concat(bad, ",") or quests)
            CommanderOrders = nil
            CHECK(A._LastError() == nil, "R12: no adapter error across the section", A._LastError())
        end

        -- -------------------------------------------------------------------
        -- R13. The 2026-10-04 review: what a zone's totals say, mixed
        --      calibration moves, today's Wanted pick across a reset, the
        --      waypoint's note, and income at the cap
        -- -------------------------------------------------------------------
        do
            local R = RepR
            -- the Sha'tar's window shut (Honored): the zone's spill share is
            -- what the window LANDS -- nothing -- not every source's sum
            RepFresh(function(w) w.reps[935] = 9500 end)
            local shatar = Find(A.ZoneRepTotals(3703), "factionId", 935) or {}
            local window = shatar.projection and shatar.projection.spillWindow
            CHECK(window and window.landed == 0 and shatar.viaSpill == 0 and shatar.remainingOnce == 550,
                "R13: the window shut: no spill share in the zone's totals (was +329 that never lands)",
                tostring(shatar.viaSpill) .. "/" .. tostring(window and window.landed))

            -- unpledged: both pledges open, one exclusive choice that is
            -- each faction's own to make
            RepFresh(function(w)
                w.complete[10551] = nil
                w.reps[932], w.reps[934] = 0, 0
            end)
            local totals = A.ZoneRepTotals(3703)
            local scryers, aldor = Find(totals, "factionId", 934), Find(totals, "factionId", 932)
            CHECK(A.ZoneView(3703).byId[10552].counted == false and A.ZoneView(3703).byId[10552].choiceOf == 2,
                "R13: the zone counts one pledge of the two (the Aldor's, the lower id)")
            CHECK(scryers and scryers.remainingOnce == 3850 and scryers.leftCount == 1,
                "R13: ...yet the Scryers' own pledge counts for the Scryers (+3,850; it was missing)",
                scryers and scryers.remainingOnce)
            CHECK(aldor and aldor.leftCount == 3 and aldor.remainingOnce == 4510,
                "R13: ...and the Aldor's for the Aldor (3,850 + 275 + 385)", aldor and aldor.remainingOnce)

            -- a Scryers quest open beside the Aldor's: the Sha'tar's window
            -- takes ONE side, and the zone's spill share is that side's
            RepFresh(function(w)
                w.quests[91023] = { name = "A Scryer's Errand", questLevel = 65, requiredLevel = 60, zoneOrSort = 3703,
                    startedBy = { { 21002 } }, finishedBy = { { 21002 } }, reputationReward = { { 934, 500 } } }
            end)
            shatar = Find(A.ZoneRepTotals(3703), "factionId", 935) or {}
            window = shatar.projection and shatar.projection.spillWindow
            CHECK(window and window.source == 932 and window.landed == 329 and shatar.viaSpill == 329
                and shatar.remainingOnce == 879,
                "R13: the spill share is the Aldor's +329 that lands, not +604 with the Scryers' added",
                tostring(shatar.viaSpill))

            -- a dungeon quest starting here pays as much as any; a LOCKED
            -- Wanted daily is no headline; done and left read one set
            RepFresh(function(w)
                w.zones[3563] = { name = "Hellfire Citadel", category = 9 }
                w.quests[91020] = { name = "Weaken the Ramparts", questLevel = 62, requiredLevel = 59, zoneOrSort = 3563,
                    startedBy = { { 21006 } }, finishedBy = { { 21006 } }, reputationReward = { { 946, 350 } } }
                for _, id in ipairs({ 11354, 11362, 11363, 11364 }) do w.quests[id].state = "LEVEL_TOO_LOW" end
            end)
            local ramparts = A.ZoneView(3483) and A.ZoneView(3483).byId[91020]
            CHECK(ramparts and ramparts.layer == "EXTRA" and ramparts.counted == false,
                "R13: the dungeon quest is listed here, outside the zone's 100%")
            totals = A.ZoneRepTotals(3483)
            local hh, cons = Find(totals, "factionId", 946) or {}, Find(totals, "factionId", 933) or {}
            CHECK(hh.remainingOnce == 770 and hh.leftCount == 3 and hh.extraCount == 1 and hh.extraLeft == 385
                and hh.reach == 4770,
                "R13: ...and its reputation is in the zone's (+385 of +770), as the Reputations tab counts it",
                hh.remainingOnce)
            CHECK(#hh.repeatables == 5 and hh.repeatablesPerTurnIn == 165 and hh.steadyCount == 1
                and hh.steadyPerTurnIn == 165 and hh.rotatingCount == 4,
                "R13: four locked Wanted dailies: the best turn-in open now is +165, not their +385",
                hh.repeatablesPerTurnIn)
            local flagged = Find(hh.repeatables, "questId", 11354)
            CHECK(flagged and flagged.rotating == "HEROIC" and flagged.open == false and flagged.daily == true,
                "R13: each repeatable says whether it rotates and whether it is open")
            CHECK(cons.repeatablesPerTurnIn == 385 and cons.rotatingCount == 4 and cons.steadyCount == 0,
                "R13: nothing open at all: the best of them still answers")
            CommanderQuestLogChar.Ignored[10937] = true
            CommanderQuestLogChar.Ignored[9355] = true
            A.Bump("settings")
            Advance(300)
            hh = Find(A.ZoneRepTotals(3483), "factionId", 946) or {}
            CHECK(hh.doneCount == 0 and hh.doneOnce == 0 and hh.leftCount == 2 and hh.remainingOnce == 495,
                "R13: an ignored quest is out of both done and left", hh.doneCount)

            -- at the cap: every per-turn-in figure is what the row shows (0)
            RepFresh(function(w) w.reps[946] = 42999 end)
            Indexed()
            hh = Find(A.ZoneRepTotals(3483), "factionId", 946) or {}
            local fortifications = R.For(A.RepEffects(10106) or {}, 946)
            CHECK(fortifications and fortifications.delta == 0 and hh.repeatablesPerTurnIn == 0,
                "R13: Exalted 999: the zone's best turn-in is 0, the 0 its row shows", hh.repeatablesPerTurnIn)
            local view = A.FactionView(946)
            CHECK(view and view.rep.dailies and view.rep.dailies.perDay == 0,
                "R13: ...and a day's dailies are worth nothing more", view and view.rep.dailies and view.rep.dailies.perDay)

            -- quests behind a standing only repeatables reach: counted apart
            RepFresh(function(w)
                w.quests[91021] = { name = "Spore Errand", questLevel = 63, requiredLevel = 61, zoneOrSort = 3521,
                    startedBy = { { 21008 } }, finishedBy = { { 21008 } }, reputationReward = { { 970, 750 } },
                    requiredMinRep = { 970, 0 }, state = "MISSING_REPUTATION" }
            end)
            local spore = Find(A.ZoneRepTotals(3521), "factionId", 970) or {}
            CHECK(spore.unreachedCount == 1 and spore.reach == -1675 and spore.repeatReach and spore.repeatReach >= 0,
                "R13: Sporeggar: one quest waits on Neutral; More Spore Sacs carry it there",
                tostring(spore.unreachedCount) .. "/" .. tostring(spore.repeatReach))
        end

        -- a move several of one quest's rows made: never a sample
        do
            local fakeR = RepFresh(function(w)
                w.quests[91022] = { name = "A Capital Errand", questLevel = 20, requiredLevel = 15, zoneOrSort = 12,
                    startedBy = { { 21011 } }, finishedBy = { { 21011 } }, reputationReward = { { 72, 250 }, { 47, 250 } } }
            end)
            local before = Line(91022)
            CHECK(before == "+343 Ironforge  +343 Stormwind  +136 Gnomeregan Exiles  +136 Darnassus  +136 Exodar",
                "R13: Stormwind and Ironforge each pay 275 and spill a quarter into the other", before)
            -- what an older build stored after one exact turn-in
            CommanderQuestLogChar.RepObserved = { [91022] = {
                [72] = { raw = 312, kind = "DIRECT", n = 1 }, [47] = { raw = 312, kind = "DIRECT", n = 1 },
                [54] = { raw = 124, kind = "SPILL", n = 1 }, [69] = { raw = 124, kind = "SPILL", n = 1 },
                [930] = { raw = 124, kind = "SPILL", n = 1 } } }
            A.Bump("calibration")
            Advance(300)
            CHECK(Line(91022) == before, "R13: samples of mixed moves are never read (they doubled the line)", Line(91022))
            fakeR.SetRep(72, 9343)
            fakeR.SetRep(47, 3443)
            fakeR.SetRep(54, 3236)
            fakeR.SetRep(69, 3236)
            fakeR.SetRep(930, 3136)
            Fire("UPDATE_FACTION")
            Frame()
            Fire("QUEST_TURNED_IN", 91022, 0, 0)
            fakeR.Complete(91022)
            Advance(2500)
            local observer = A._RepObserver()
            CHECK(observer.why.mixed == 5 and CommanderQuestLogChar.RepObserved[91022] == nil,
                "R13: the turn-in's five moves are set aside, and the old samples dropped", observer.why.mixed)
            CHECK(Line(91022) == before, "R13: ...so the quest still reads its five numbers once", Line(91022))
        end

        -- today's Wanted pick across a daily reset in one session
        do
            local fakeR, world = RepFresh(function(w)
                w.serverTime, w.questResetIn = 1000000, 3600
                w.unavailableByTalking = { Testrealm = {} }
            end)
            fakeR.Complete(11354)
            CHECK(A.RotatingToday().HEROIC == 11354, "R13: a Wanted daily done this session is today's")
            -- the reset passes; Questie keeps its done list until a relog
            world.serverTime, world.questResetIn = 1003610, 86390
            fakeR.ResetDailies()
            CHECK(A.RotatingToday().HEROIC == nil, "R13: after the reset yesterday's turn-in is no longer today's")
            Fire("QUEST_TURNED_IN", 11362, 0, 0)
            fakeR.Complete(11362)
            CHECK(A.RotatingToday().HEROIC == 11362, "R13: one turned in since the reset is")
            Advance(2500)
        end

        -- a waypoint's note follows the numbers while the waypoint lives
        do
            local fakeR = RepFresh()
            ordersLog.available, ordersLog.why = true, nil
            local api = FakeOrders()
            local byUid, updates = {}, 0
            local add = api.Add
            api.Add = function(spec)
                local uid = add(spec)
                if uid then byUid[uid] = { uid = uid, source = spec.source, key = spec.key, note = spec.note } end
                return uid, nil, "added"
            end
            api.List = function(filter)
                local out = {}
                for _, wp in pairs(byUid) do
                    if not (filter and filter.source) or wp.source == filter.source then
                        out[#out + 1] = { uid = wp.uid, source = wp.source, key = wp.key, note = wp.note }
                    end
                end
                return out
            end
            api.Update = function(uid, fields)
                local wp = byUid[uid]
                if not wp then return nil, "unknown" end
                updates = updates + 1
                if fields.note ~= nil then wp.note = fields.note or nil end
                return { uid = uid, note = wp.note }
            end
            CommanderOrders = api
            A.Waypoint({ title = "A Job", areaId = 3483, x = 50, y = 50, questId = 9355 })
            A.Waypoint({ title = "Drill", areaId = 3483, x = 50, y = 50, questId = 91002 })
            A.Waypoint({ title = "Fortify", areaId = 3483, x = 50, y = 50, questId = 10106 })
            local job, drill, fort
            for _, wp in pairs(byUid) do
                if wp.key == "quest:9355" then job = wp elseif wp.key == "quest:91002" then drill = wp else fort = wp end
            end
            CHECK(job and job.note == "+275 Honor Hold", "R13: a quest's waypoint is noted with what it pays", job and job.note)
            drill.note = "my own words"
            byUid[fort.uid] = nil
            local adds = #ordersLog.adds
            fakeR.SetAura(24705, true)
            Fire("UNIT_AURA", "player")
            Advance(1000)
            CHECK(job.note == "+300 Honor Hold" and updates == 1,
                "R13: the Wickerman taken: the note is written again (+300), through Update", job.note)
            CHECK(drill.note == "my own words" and #ordersLog.adds == adds and byUid[fort.uid] == nil,
                "R13: a note someone changed is left alone, a waypoint removed stays removed")
            Fire("UNIT_AURA", "player")
            Advance(1000)
            A.Bump("test")
            Advance(300)
            CHECK(updates == 1, "R13: nothing moved, nothing written", updates)
            fakeR.SetAura(24705, false)
            CommanderOrders = nil
            CHECK(A._LastError() == nil, "R13: no adapter error across the section", A._LastError())
        end

        -- -------------------------------------------------------------------
        -- R14. The 2026-10-05 review: a spill window lands only what the
        --      source's own gate lets be done (an unpledged character's
        --      Shadowmoon read +1,574 for the Sha'tar from Scryers quests
        --      that need Friendly with the Scryers)
        -- -------------------------------------------------------------------
        do
            local function Shadowmoon(w)
                local function Quest(name, rows, minRep, maxRep)
                    return { name = name, questLevel = 70, requiredLevel = 67, zoneOrSort = 3520,
                             startedBy = { { 21009 } }, finishedBy = { { 21009 } }, reputationReward = rows,
                             requiredMinRep = minRep, requiredMaxRep = maxRep }
                end
                -- no stored Sha'tar half: the data drops those for the real ids only
                w.quests[91020] = Quest("An Aldor Errand at Friendly", { { 932, 350 } }, { 932, 3000 })
                w.quests[91021] = Quest("An Aldor Errand", { { 932, 250 } }, { 932, 0 })
                w.quests[91022] = Quest("An Aldor Errand at Revered", { { 932, 500 } }, { 932, 21000 })
                -- offered only below Neutral with the Aldor (Strained Supplies' shape)
                w.quests[91024] = Quest("An Aldor Errand for the Hostile", { { 932, 250 } }, nil, { 932, 0 })
                w.quests[91023] = Quest("A Sha'tar Errand", { { 935, 500 } }, nil)
            end
            RepFresh(function(w)
                Shadowmoon(w)
                w.reps[932], w.reps[934], w.reps[935] = 0, 0, 0
                w.complete[10551], w.complete[10021] = nil, nil
            end)
            local totals = A.ZoneRepTotals(3520)
            local shatar, aldor = Find(totals, "factionId", 935), Find(totals, "factionId", 932)
            local spillOrder = shatar and shatar.projection.spillOrder or {}
            CHECK(aldor and aldor.remainingOnce == 275 and aldor.unreachedCount == 2,
                "R14: unpledged in Shadowmoon, the Aldor's quests here reach +275; two need a standing they never reach",
                aldor and aldor.remainingOnce)
            CHECK(shatar and shatar.viaSpill == 137 and shatar.remainingOnce == 687
                and table.concat(spillOrder, ",") == "91021",
                "R14: ...so the Sha'tar's window lands only the ungated quest's +137 (550 of its own, 687 in all)",
                shatar and (shatar.viaSpill .. " " .. shatar.remainingOnce .. " " .. table.concat(spillOrder, ",")))
            Indexed()
            local view = A.FactionView(935)
            local fv = view and view.rep and view.rep.projection or { spillOrder = {} }
            CHECK(Contains(fv.spillOrder, 91020) and Contains(fv.spillOrder, 91021) and not Contains(fv.spillOrder, 91022),
                "R14: the Sha'tar's own view: the pledge reaches Friendly, never Revered, so 91022 spills nothing",
                table.concat(fv.spillOrder or {}, ","))
            RepFresh(Shadowmoon)
            totals = A.ZoneRepTotals(3520)
            shatar = Find(totals, "factionId", 935)
            spillOrder = shatar and shatar.projection.spillOrder or {}
            CHECK(shatar and shatar.viaSpill == 329 and table.concat(spillOrder, ",") == "91021,91020",
                "R14: pledged (the Aldor at 4,000), the Friendly quest spills too: +329; the Revered one and the one shut above Neutral do not",
                shatar and (shatar.viaSpill .. " " .. table.concat(spillOrder, ",")))
            CHECK(A._LastError() == nil, "R14: no adapter error", A._LastError())
        end

        -- Leave the rest of the run as it was
        Q.Standing, CommanderQuestLogReputationData = nil, nil
        Fake.UninstallRepClient()
        CommanderOrders = nil
        CommanderQuestLogDB = {}
        CommanderQuestLogChar = { Ignored = {} }
    end
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
