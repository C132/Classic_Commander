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
--   E  Orders turned off: the press says so and prints the /way line

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
local function Boot()
    loadErrors = {}
    M.Boot({
        player = { 1944, 0.50, 0.60 },        -- Hellfire Peninsula, near Honor Hold
        faction = "Alliance",
        skipFiles = { CommanderOrdersPins = true, CommanderOrdersUI = true },
        loaded = { Questie = true },
        before = function()
            -- Questie loads before both (the Quest Log's OptionalDeps); the
            -- fake fills in only the client calls the Orders mock lacks
            local Fake = dofile(QL .. "/Harness/fake_questie.lua")
            local world = Fake.DefaultWorld()
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
    })
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
CHECK(view.hop and view.hop.entrance == true and view.hop.map == 1944 and NEAR(view.hop.x, 0.477),
    "B: Orders offers the entrance the Quest Log's resolver gave", view.hop and view.hop.name)
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
path = A().Waypoint({ title = "Know Your Enemy", areaId = 3483, x = 61.8, y = 60.6, questId = 9005 })
CHECK(path == "PRINT" and Last("/way #1944 61.80 60.60 Know Your Enemy") ~= nil,
    "E: the press prints the place and its /way line", path)
CHECK(#O().List({ source = "QuestLog", routeId = false }) == 0, "E: and Orders took nothing")
CommanderOrdersDB.EnableOrders = true

CHECK(#M.errors == 0, "no errors", M.errors[1])

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
