-- Commander Quest Log against the REAL Commander Orders (luajit).
--
--     luajit Commander_QuestLog/Harness/questlog_orders_contract.lua
--     CQL_ADAPTER=/path/copy.lua luajit ...      (a mutated adapter)
--
-- The adapter smoke and the window and map harnesses drive the Quest Log
-- against a recording stand-in for Commander Orders, which proves what the
-- Quest Log ASKS for and nothing about whether Orders takes it. This harness
-- closes that gap: it boots Orders through Commander_Orders/Harness/orders_mock.lua
-- (the client Orders' own harnesses share: this build's UiMap and
-- UiMapAssignment rows, the real settings framework, every Orders file) with
-- the fake Questie installed underneath, loads the completion engine and the
-- Questie adapter after Orders' ADDON_LOADED (the client's order for an
-- addon with OptionalDeps: Commander_Orders), and checks the round trip:
--
--   A  the entrance resolver is registered with Orders at login and answers
--      Orders' own lookup for Hellfire Ramparts (347) from Questie's table
--   B  a waypoint to a giver inside a dungeon: Orders takes the dungeon map
--      (instance 543), cannot draw a straight arrow from Hellfire, and
--      offers the entrance the resolver gave -- the case the old single slot
--      left on a grey "other continent" for good
--   C  every spawn as alternatives: Orders keeps them and points at the
--      spawn nearest the player, and a second press on the same quest moves
--      the quest's one waypoint
--   D  Route Zone: Orders takes the route, owned, nearest first, with a
--      stop's alternatives intact
--   E  Orders turned off: the press gets Orders' one refusal line, the place
--      and its [Go] link (whose Ctrl-click is the /way line)
--
-- And the 1.7.0 "Go to" work (DECISIONS D45), on Orders 3.1's GoTo:
--   F  a press goes through GoTo: Orders' own "Waypoint set" line, none of
--      the Quest Log's
--   G  objectives (Fake.GoWorld's quest 9005): Questie's list in the log's
--      order (the object first, as objectObjectiveFirst asks), each kind's
--      place, and the real Orders taking each Go with every spawn
--   H  one waypoint per quest across its keys ("quest:<id>" and
--      "quest:<id>:<n>"); another quest's untouched
--   I  turned in or abandoned (QUEST_TURNED_IN, QUEST_REMOVED): every key of
--      the quest goes
--   J  the pinned quest Go survives a /reload (Orders 3.1, D5) and is still
--      cleared at the turn-in after it
--   K  a prerequisite's Go: to where that quest starts

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local QL = ADDONS .. "/Commander_QuestLog"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function NEAR(a, b, eps) return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= (eps or 1e-6) end

local loadErrors = {}
local function BootOpts()
    return {
        player = { 1944, 0.50, 0.60 },        -- Hellfire Peninsula, near Honor Hold
        faction = "Alliance",
        skipFiles = { CommanderOrdersPins = true, CommanderOrdersUI = true },
        loaded = { Questie = true },
        before = function()
            -- Questie loads before both (the Quest Log's OptionalDeps); the
            -- fake fills in only the client calls the Orders mock lacks
            local Fake = dofile(QL .. "/Harness/fake_questie.lua")
            local world = Fake.GoWorld()          -- the default world plus 9005's objectives
            -- L: the Shadow Labyrinth as Questie has it (area 3789, its one
            -- spot Terokkar 39.6, 71.0: QuestieDB dungeons.lua) with Murmur
            -- inside (the {-1, -1} sentinel) and a quest to kill him
            world.zones[3789] = { name = "Shadow Labyrinth", uiMapId = 260, category = 9,
                                  entrances = { { 3519, 39.6, 71.0 } } }
            world.npcs[18708] = { name = "Murmur", spawns = { [3789] = { { -1, -1 } } } }
            world.quests[10095] = { name = "Into the Heart of the Labyrinth", questLevel = 70, requiredLevel = 68,
                                    zoneOrSort = 3789, startedBy = { { 20022 } }, finishedBy = { { 20022 } },
                                    objectives = { { { 18708 } } } }
            Fake.Install(world)
            Fake.InstallClient(world, { force = false })
        end,
        afterFiles = function()
            local hook = CreateFrame("Frame")
            hook:RegisterEvent("ADDON_LOADED")
            hook:SetScript("OnEvent", function(_, _, name)
                if name ~= "Commander_Orders" then return end
                rawset(_G, "COMMANDER_QUESTLOG_EVENTS", { UPDATE = "COMMANDER_QUESTLOG_UPDATE" })
                rawset(_G, "CommanderQuestLogDB", {})
                rawset(_G, "CommanderQuestLogChar", { Ignored = {} })
                -- CQL_ADAPTER points at a mutated copy of the adapter, as in the smoke
                local files = { QL .. "/CommanderQuestLogCompletion.lua",
                    os.getenv("CQL_ADAPTER") or (QL .. "/CommanderQuestLogQuestie.lua") }
                for _, path in ipairs(files) do
                    local chunk, err = loadfile(path)
                    if not chunk then
                        loadErrors[#loadErrors + 1] = tostring(err)
                    else
                        local ok, runErr = pcall(chunk)
                        if not ok then loadErrors[#loadErrors + 1] = tostring(runErr) end
                    end
                end
                M.Fire("ADDON_LOADED", "Commander_QuestLog")
            end)
        end,
    }
end
local function Boot()
    loadErrors = {}
    M.Boot(BootOpts())
    M.Advance(1)
end

local function O() return rawget(_G, "CommanderOrders") end
local function A() return CommanderQuestLog.Questie end
local function Last(needle)
    for i = #M.prints, 1, -1 do
        if tostring(M.prints[i]):find(needle, 1, true) then return M.prints[i] end
    end
    return nil
end

-- ===========================================================================
-- A. The entrance resolver, registered with the real Orders at login
-- ===========================================================================
Boot()
CHECK(#loadErrors == 0 and #M.loadErrors == 0, "A: everything loads", loadErrors[1] or M.loadErrors[1])
CHECK(A().State() == "READY", "A: the fake Questie is ready under the Orders mock", A().State())
local e = O().R.Resolve("entrance", 347)
CHECK(type(e) == "table" and e.map == 1944 and NEAR(e.x, 0.477) and NEAR(e.y, 0.536)
    and e.title == "Hellfire Ramparts entrance", "A: Orders' own entrance lookup for 347 reaches the Quest Log's resolver",
    e and (tostring(e.map) .. " " .. tostring(e.title)))
CHECK(O().R.Resolve("entrance", 1944) == nil, "A: a zone map has no entrance")

-- ===========================================================================
-- B. A giver inside a dungeon: the dungeon map, and Orders offers the way in
-- ===========================================================================
CHECK(A().WaypointPath() == "ORDERS", "B: the path is the Commander Orders arrow")
local path = A().Waypoint({ title = "Weaken the Ramparts (Gunny)", uiMapId = 347, x = 47.7, y = 53.6, questId = 9016 })
CHECK(path == "ORDERS", "B: Orders takes a waypoint on a dungeon map", path)
local list = O().List({ source = "QuestLog" })
CHECK(#list == 1 and list[1].key == "quest:9016" and list[1].map == 347, "B: one QuestLog waypoint, keyed by its quest",
    list[1] and list[1].key)
M.Advance(0.5)
local view = O().R.View()
CHECK(view.mode == "OTHER", "B: no straight arrow from Hellfire into instance 543", view.mode)
-- Orders asks its own cited door table first (Orders D37, 3.1 review), so the
-- way in is the table's Ramparts door (0.4748), a couple of yards from the
-- resolver's 0.477; the resolver itself is still asked directly in A.
CHECK(view.hop and view.hop.entrance == true and view.hop.map == 1944 and view.hop.x
    and math.abs(view.hop.x - 0.477) < 0.005 and math.abs((view.hop.y or 0) - 0.536) < 0.005,
    "B: Orders offers the way in to the Ramparts (door table first, else the Quest Log's resolver)",
    view.hop and (tostring(view.hop.name) .. " " .. tostring(view.hop.x)))
O().RemoveBy("QuestLog")

-- ===========================================================================
-- C. Every spawn as alternatives; the nearest one wins; a re-press moves
-- ===========================================================================
local hellfire = A().ZoneView(3483)
local sentryEntry = hellfire and hellfire.byId[9033]
local sentry = sentryEntry and A().BestStarter(sentryEntry, 3483)
CHECK(sentry and sentry.spawns and #sentry.spawns == 8, "C: the Patrol Sentry's eight spawns", sentry and sentry.spawns and #sentry.spawns)
-- Stand on the last spawn (55, 25): the arrow should take it, not the first (20, 20)
M.SetPlayer(1944, 0.55, 0.25)
M.Advance(1.2)
path = A().Waypoint({ title = "Sentry Duty (Patrol Sentry)", areaId = 3483, uiMapId = sentry and sentry.uiMapId,
    x = sentry and sentry.x, y = sentry and sentry.y, questId = 9033, spawns = sentry and sentry.spawns })
CHECK(path == "ORDERS", "C: Orders takes the waypoint with its alternatives", path)
list = O().List({ source = "QuestLog" })
local wp = list[1]
CHECK(#list == 1 and wp.alternatives and #wp.alternatives == 8, "C: Orders keeps all eight as alternatives",
    wp and wp.alternatives and #wp.alternatives)
M.Advance(1.2)
local store = O().R.Store()
local live = store:Get(wp.uid)
local pos = live and store:Position(live, O().R.Ctx(true))
CHECK(pos and NEAR(pos.x, 0.55) and NEAR(pos.y, 0.25), "C: the arrow points at the spawn the player stands nearest",
    pos and (pos.x .. "," .. pos.y))
local active = O().Active()
CHECK(active and active.uid == wp.uid, "C: the pressed waypoint has the arrow")
A().Waypoint({ title = "Sentry Duty (turn in)", areaId = 3483, uiMapId = 1944, x = 20, y = 20, questId = 9033 })
list = O().List({ source = "QuestLog" })
CHECK(#list == 1 and list[1].uid == wp.uid and list[1].title == "Sentry Duty (turn in)",
    "C: a second press on the same quest moves its one waypoint", #list)
O().RemoveBy("QuestLog")

-- ===========================================================================
-- D. Route Zone through the real Orders
-- ===========================================================================
local stops = A().RouteStops(3483)
CHECK(#stops >= 2, "D: Hellfire has open quests to route", #stops)
local status, count = A().RouteOpen(3483)
CHECK(status == "ORDERS" and count == #stops, "D: Orders takes the route", status)
local route = O().ActiveRoute()
CHECK(route and route.source == "QuestLog" and route.key == "open:3483" and route.mode == "NEAREST"
    and #route.stops == #stops, "D: one owned NEAREST route, active, a stop per giver", route and route.key)
local withAlts = false
for _, uid in ipairs(route and route.stops or {}) do
    local stop = O().Get(uid)
    if stop and stop.alternatives and #stop.alternatives == 8 then withAlts = true end
end
CHECK(withAlts, "D: the Patrol Sentry's stop keeps its eight spawns")
A().RouteOpen(3483)
CHECK(#O().Routes() == 1, "D: routing the zone again replaces the route", #O().Routes())
CHECK(Last("quest givers in Hellfire Peninsula, nearest first") ~= nil, "D: and says so")

-- ===========================================================================
-- E. Orders turned off
-- ===========================================================================
CommanderOrdersDB.EnableOrders = false
CHECK(A().WaypointPath() == "ORDERS_OFF", "E: turned off is told apart from absent")
M.ClearLog()
path = A().Waypoint({ title = "Know Your Enemy", areaId = 3483, x = 61.8, y = 60.6, questId = 9005 })
local refusal = Last("Commander Orders is turned off (/corder)")
CHECK(path == "PRINT" and refusal ~= nil and refusal:find("Know Your Enemy (Hellfire Peninsula 61.8, 60.6)", 1, true)
    and refusal:find("|Haddon:CommanderOrders:w:1944:", 1, true) ~= nil,
    "E: the press gets Orders' one refusal line: the place and its [Go] link", refusal or path)
CHECK(#O().List({ source = "QuestLog", routeId = false }) == 0, "E: and Orders took nothing")
CommanderOrdersDB.EnableOrders = true

-- ===========================================================================
-- F. A press goes through Orders 3.1's GoTo
-- ===========================================================================
local function QuestKeys(questId)
    local out = {}
    for _, wp in ipairs(O().List({ source = "QuestLog" })) do
        if type(wp.key) == "string" and (wp.key == "quest:" .. questId or wp.key:find("^quest:" .. questId .. ":")) then
            out[#out + 1] = wp.key
        end
    end
    table.sort(out)
    return table.concat(out, ",")
end
local function QuestLogLines()
    local n = 0
    for _, line in ipairs(M.prints) do
        if tostring(line):find("Commander Quest Log:", 1, true) then n = n + 1 end
    end
    return n
end
O().RemoveBy("QuestLog")
M.ClearLog()
path = A().Waypoint({ title = "Know Your Enemy (Sergeant Altumus)", areaId = 3483, x = 61.8, y = 60.6, questId = 9005 })
CHECK(path == "ORDERS", "F: Orders takes the press", path)
CHECK(Last("Waypoint set: Know Your Enemy (Sergeant Altumus)") ~= nil, "F: Orders says Waypoint set, in its words",
    M.prints[#M.prints])
CHECK(QuestLogLines() == 0, "F: and the Quest Log adds no line of its own")
local kye = O().R.Store():ByKey("QuestLog", "quest:9005")
CHECK(kye and kye.icon == "QUEST" and kye.map == 1944, "F: owned (QuestLog, quest:9005), the quest's icon")

-- ===========================================================================
-- G. Objectives: Questie's list in the log's order, each one a Go
-- ===========================================================================
local targets = A().ObjectiveTargets(9005)
local kinds, names = {}, {}
for i, t in ipairs(targets) do kinds[i] = t.kind; names[i] = tostring(t.name) end
CHECK(table.concat(kinds, ",") == "object,monster,item,reputation,killcredit,event",
    "G: Questie's order, the object first (objectObjectiveFirst)", table.concat(kinds, ","))
CHECK(names[1] == "Wanted Poster" and names[2] == "Patrol Sentry" and names[3] == "Legion Missive"
    and names[5] == "Caza'rez slain" and names[6] == "Scout the Legion front", "G: each named", table.concat(names, "|"))
CHECK(targets[1].places == 1 and targets[2].places == 8 and targets[3].places == 9 and targets[4].places == 0
    and targets[5].places == 1 and targets[6].places == 1, "G: spots: the poster, eight sentries, the missive's nine droppers' spawns, none for reputation",
    targets[1].places .. "," .. targets[2].places .. "," .. targets[3].places .. "," .. targets[4].places)
local spec, key, qid = A().ObjectiveSpec(9005, 2)
CHECK(spec and key == "quest:9005:2" and qid == 9005 and spec.title == "Know Your Enemy: Patrol Sentry"
    and spec.alternatives and #spec.alternatives == 8, "G: the sentry objective's Go: its own key, every spawn",
    spec and spec.title)
CHECK(A().ObjectiveSpec(9005, 4) == nil, "G: a reputation objective has nowhere to go")
-- Orders' door, not Questie's spot (46.0, 51.8): section L has the why
local furnace = A().ObjectiveSpec(9005, 5)
local furnaceDoor = O().Entrance({ instance = 542 })
CHECK(furnace and furnaceDoor and furnace.map == 1944 and furnace.map == furnaceDoor.map
    and NEAR(furnace.x, furnaceDoor.x, 1e-4) and NEAR(furnace.y, furnaceDoor.y, 1e-4),
    "G: a creature only inside the Blood Furnace is its door, Orders' own", furnace and (furnace.map .. " " .. furnace.x))
local trigger = A().ObjectiveSpec(9005, 6)
CHECK(trigger and trigger.map == 1944 and NEAR(trigger.x, 0.70) and NEAR(trigger.y, 0.40)
    and trigger.title == "Know Your Enemy: Scout the Legion front", "G: the explore trigger's spot")
CHECK(A().ObjectiveSpec(9005, 7) == nil and A().ObjectiveSpec(9003, 1) == nil, "G: no objective, no Go")
M.SetPlayer(1944, 0.55, 0.25)
M.Advance(1.2)
CHECK(A().GoSpec(spec, key, qid) == "ORDERS", "G: the real Orders takes the sentry Go")
local sentryWp = O().R.Store():ByKey("QuestLog", "quest:9005:2")
CHECK(sentryWp and sentryWp.alternatives and #sentryWp.alternatives == 8, "G: ...with all eight spawns")
M.Advance(1.2)
local spot = sentryWp and O().R.Store():Position(sentryWp, O().R.Ctx(true))
CHECK(spot and NEAR(spot.x, 0.55) and NEAR(spot.y, 0.25), "G: the arrow takes the spawn the player stands by",
    spot and (spot.x .. "," .. spot.y))
CHECK(O().Active() and O().Active().uid == sentryWp.uid, "G: and it has the arrow")
CHECK(A().GoSpec(A().ObjectiveSpec(9005, 3)) == "ORDERS", "G: the item objective's Go is taken too")

-- ===========================================================================
-- H. One waypoint per quest, across its keys
-- ===========================================================================
O().RemoveBy("QuestLog")
A().GoSpec(A().ObjectiveSpec(9005, 2))
CHECK(QuestKeys(9005) == "quest:9005:2", "H: (an objective's Go)", QuestKeys(9005))
A().Waypoint({ title = "Know Your Enemy (Sergeant Altumus)", areaId = 3483, x = 61.8, y = 60.6, questId = 9005 })
CHECK(QuestKeys(9005) == "quest:9005", "H: the turn-in's Go replaces it: still one waypoint for the quest", QuestKeys(9005))
A().Waypoint({ title = "Sentry Duty (Patrol Sentry)", areaId = 3483, x = 20, y = 20, questId = 9033 })
A().GoSpec(A().ObjectiveSpec(9005, 6))
CHECK(QuestKeys(9005) == "quest:9005:6", "H: and back to an objective", QuestKeys(9005))
CHECK(QuestKeys(9033) == "quest:9033", "H: another quest's waypoint is left alone", QuestKeys(9033))
CHECK(QuestKeys(900) == "", "H: (keys are matched whole: quest 900 owns none of 9005's)")

-- ===========================================================================
-- I. Turned in or abandoned: every key of the quest goes
-- ===========================================================================
M.Fire("QUEST_TURNED_IN", 900, 0, 0)
CHECK(QuestKeys(9005) == "quest:9005:6", "I: a turn-in of quest 900 leaves 9005's alone (keys match whole)", QuestKeys(9005))
M.Fire("QUEST_TURNED_IN", 9005, 0, 0)
CHECK(QuestKeys(9005) == "", "I: QUEST_TURNED_IN removes the quest's waypoint", QuestKeys(9005))
CHECK(QuestKeys(9033) == "quest:9033", "I: ...and nobody else's")
A().GoSpec(A().ObjectiveSpec(9005, 1))
A().Waypoint({ title = "Know Your Enemy", areaId = 3483, x = 61.8, y = 60.6, questId = 9005 })
A().GoSpec(A().ObjectiveSpec(9005, 2))
M.Fire("QUEST_REMOVED", 9005)
CHECK(QuestKeys(9005) == "", "I: QUEST_REMOVED (abandoned) removes it too", QuestKeys(9005))
M.Fire("QUEST_REMOVED", 9005)
CHECK(#M.errors == 0, "I: a second removal is harmless", M.errors[1])
CHECK(QuestKeys(9033) == "quest:9033", "I: (9033's is still there)")

-- ===========================================================================
-- J. The pinned quest Go survives a /reload; the turn-in still clears it
-- ===========================================================================
O().RemoveBy("QuestLog")
A().Waypoint({ title = "Sentry Duty (Patrol Sentry)", areaId = 3483, x = 20, y = 20, questId = 9033 })
CHECK(O().Active() and O().Active().key == "quest:9033", "J: (the quest's Go has the arrow)")
loadErrors = {}
M.Reload(BootOpts())
M.Advance(1)
CHECK(#loadErrors == 0, "J: the Quest Log loads again after the reload", loadErrors[1])
CHECK(QuestKeys(9033) == "quest:9033", "J: Orders 3.1 kept the pinned quest Go across the /reload", QuestKeys(9033))
M.Fire("QUEST_TURNED_IN", 9033, 0, 0)
CHECK(QuestKeys(9033) == "", "J: and the turn-in after the reload clears it", QuestKeys(9033))

-- ===========================================================================
-- K. A prerequisite's Go: to where that quest starts
-- ===========================================================================
local start, startKey, startQuest = A().StarterSpec(9004)
CHECK(start and start.title == "The Legion Reborn (Force Commander Danath)" and startKey == "quest:9004"
    and startQuest == 9004 and start.map == 1944 and NEAR(start.x, 0.566), "K: The Legion Reborn starts with Danath",
    start and start.title)
CHECK(A().GoSpec(start, startKey, startQuest) == "ORDERS" and QuestKeys(9004) == "quest:9004", "K: and Orders takes it")
CHECK(A().StarterSpec(9022) == nil, "K: an item-started quest has nowhere to go")

-- ===========================================================================
-- L. A creature inside an instance goes to Orders' door (2026-10-05 review)
-- ===========================================================================
-- Orders' shipped door table is the suite's one way in: the arrow's dungeon
-- hint, the corpse run and every other module's Go use it. Questie's own
-- Shadow Labyrinth spot is on the Auchindoun tunnel ~100 yd short of the
-- portal, so a Go to Murmur must land on Orders' door, within a few yards
local function Yards(a, b)
    local ia, pa = C_Map.GetWorldPosFromMapPos(a.map, CreateVector2D(a.x, a.y))
    local ib, pb = C_Map.GetWorldPosFromMapPos(b.map, CreateVector2D(b.x, b.y))
    if not (pa and pb) or ia ~= ib then return nil end
    local ax, ay = pa:GetXY()
    local bx, by = pb:GetXY()
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
local labyrinth = O().Entrance({ instance = 555 })
local murmur = A().ObjectiveSpec(10095, 1)
local apart = murmur and labyrinth and Yards(murmur, labyrinth)
CHECK(labyrinth and labyrinth.map == 1952, "L: (Orders' Shadow Labyrinth door is on Terokkar)", labyrinth and labyrinth.map)
CHECK(murmur and murmur.map == 1952 and apart and apart < 5, "L: Murmur's objective Go lands on Orders' door",
    murmur and string.format("%d %.4f,%.4f %s yd", murmur.map, murmur.x, murmur.y, tostring(apart)))
local questieSpot = { map = 1952, x = 0.396, y = 0.710 }
local short = labyrinth and Yards(questieSpot, labyrinth)
CHECK(short and short > 50, "L: (Questie's own spot is the tunnel short of it)", short)
local murmurGiver = A().ObjectiveTargets(10095)[1]
CHECK(murmurGiver and murmurGiver.name == "Murmur" and murmurGiver.places == 1, "L: one place for Murmur: the door",
    murmurGiver and murmurGiver.places)
CHECK(A().GoSpec(murmur, "quest:10095:1", 10095) == "ORDERS", "L: and the real Orders takes it")

CHECK(#M.errors == 0, "no errors", M.errors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
