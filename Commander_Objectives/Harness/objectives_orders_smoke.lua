-- Commander Objectives + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Objectives/Harness/objectives_orders_smoke.lua
--     OBJECTIVES_RUNTIME=/tmp/mutant.lua luajit ...   (a mutated CommanderObjectives.lua)
--
-- Objectives 2.2.0 (Commander Orders 3.1, SPEC 5 and S9): the Turn-in Offer.
-- When a quest in the log turns complete, a quiet waypoint marks its
-- finisher. This boots the real Orders over the client mock its own
-- harnesses share (Commander_Orders/Harness/orders_mock.lua) and Objectives'
-- two files after it; the quest log is the mock's, and Commander Quest Log's
-- Questie adapter is a stand-in answering Finisher(questID) in its real shape
-- ({ name, uiMapId, x, y (0..100), spawns = { { uiMapId, x, y }, ... } }).
--   A  loads clean; the offer ships off
--   B  on: a quest turning complete is ONE quiet waypoint (Objectives,
--      turnin:<id>) at its finisher, every spawn as its choices, temporary,
--      silent, never PINNED, never taking the arrow from a pin of yours;
--      quests already complete at login are not offered
--   C  turned in, abandoned, or no longer complete: the offer goes; a quest
--      under a collapsed header is left as it was
--   D  in combat: parked until combat ends
--   E  off, no Quest Log adapter, a finisher with no place: nothing

local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then HERE = (os.getenv("PWD") or ".") .. "/" .. HERE end
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local M = dofile(ADDONS .. "/Commander_Orders/Harness/orders_mock.lua")

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail ~= nil and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, "got " .. tostring(got) .. ", want " .. tostring(want))
end
local function Section(name, fn)
    local ok, err = pcall(fn)
    CHECK(ok, name .. ": ran to the end", err)
end

local SKIP = { CommanderOrdersPins = true, CommanderOrdersUI = true }
local GOLDSHIRE = { 1429, 0.42, 0.655 }

-- The quest log: { title, questID, complete = 1 | nil, header = true }
local log = {}
-- Commander Quest Log's adapter, as far as Objectives reads it
local FINISHERS = {
    [60] = { name = "Marshal Dughan", uiMapId = 1429, x = 42.1, y = 65.9, kind = "npc", id = 240,
             spawns = { { uiMapId = 1429, x = 42.1, y = 65.9 }, { uiMapId = 1429, x = 30.0, y = 50.0 } } },
    [61] = { name = "Remy", uiMapId = 1429, x = 42.0, y = 67.1, kind = "npc", id = 241 },
    [62] = { name = "Nowhere Man", kind = "npc", id = 9 },            -- Questie knows him, not where
}

local function Boot(opts)
    opts = opts or {}
    local mutant = os.getenv("OBJECTIVES_RUNTIME")
    local files = { "CommanderObjectivesDB.lua" }
    if not mutant then files[2] = "CommanderObjectives.lua" end
    M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        saved = opts.saved or { CommanderObjectivesDB = { TurnInOffer = true } },
        before = function()
            rawset(_G, "UnitXP", function() return 100 end)
            rawset(_G, "UnitXPMax", function() return 1000 end)
            rawset(_G, "UnitLevel", function() return 20 end)
            rawset(_G, "GetNumQuestLogEntries", function() return #log end)
            rawset(_G, "GetQuestLogTitle", function(i)
                local q = log[i]
                if not q then return nil end
                return q.title, 20, 0, q.header and true or false, false, q.complete, 0, q.questID
            end)
            if opts.adapter ~= false then
                rawset(_G, "CommanderQuestLog", { Questie = { Finisher = function(id) return FINISHERS[id] end } })
            end
        end,
        addons = { { name = "Commander_Objectives", files = files } },
        afterFiles = function()
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
        end,
    })
    M.Fire("QUEST_LOG_UPDATE")
    M.Advance(0.5)
end

local function O() return rawget(_G, "CommanderOrders") end
local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Offer(id) return O().R.Store():ByKey("Objectives", "turnin:" .. id) end
local function Update()
    M.Fire("QUEST_LOG_UPDATE")
    M.Fire("QUEST_LOG_UPDATE")
    M.Advance(0.5)
end

-- ===========================================================================
Section("A", function()
    log = {}
    Boot({ saved = {} })
    NoErrors("A")
    EQ(CommanderObjectivesDB.TurnInOffer, false, "A: the Turn-in Offer ships off")
    log = { { title = "Elwynn", header = true }, { title = "The Fargodeep Mine", questID = 60 } }
    Update()
    log[2].complete = 1
    Update()
    EQ(Offer(60), nil, "A: off: no waypoint")
end)

-- ===========================================================================
Section("B", function()
    log = { { title = "Elwynn", header = true },
            { title = "Already Done", questID = 61, complete = 1 },
            { title = "The Fargodeep Mine", questID = 60 } }
    Boot()
    EQ(Offer(61), nil, "B: a quest already complete at login is not offered")
    local mine = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Mine" })
    M.Frame()
    M.ClearLog()
    log[3].complete = 1
    Update()
    local wp = Offer(60)
    CHECK(wp ~= nil, "B: a quest turning complete is a waypoint (Objectives, turnin:60)")
    EQ(wp and wp.title, "Turn in: The Fargodeep Mine (Marshal Dughan)", "B: ...titled with the quest and who takes it")
    CHECK(wp and wp.map == 1429 and math.abs(wp.x - 0.421) < 1e-9, "B: ...at the finisher")
    EQ(wp and wp.alternatives and #wp.alternatives, 2, "B: ...every spawn as its choices")
    CHECK(wp and wp.temporary == true and wp.persistent == false, "B: ...temporary and session-only")
    EQ(wp and wp.icon, "QUEST", "B: ...in the quest tint")
    EQ(#M.prints, 0, "B: ...quietly")
    EQ(O().Active() and O().Active().uid, mine, "B: it never takes the arrow from a pin of yours")
    Update()
    EQ(#O().List({ source = "Objectives" }), 1, "B: another log update adds nothing")
    -- With nothing of yours, still never pinned
    O().Remove(mine)
    M.Frame()
    local a = O().Active()
    CHECK(not (a and a.why == "PINNED"), "B: never PINNED: it never asks for the arrow", a and a.why)
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    log = { { title = "Elwynn", header = true }, { title = "The Fargodeep Mine", questID = 60 },
            { title = "Remy's Errand", questID = 61 } }
    Boot()
    log[2].complete, log[3].complete = 1, 1
    Update()
    CHECK(Offer(60) ~= nil and Offer(61) ~= nil, "C: (two offers)")
    -- Turned in
    table.remove(log, 2)
    M.Fire("QUEST_TURNED_IN", 60, 100, 0)
    Update()
    EQ(Offer(60), nil, "C: turned in: its offer goes")
    CHECK(Offer(61) ~= nil, "C: ...the other stays")
    -- No longer complete (an item dropped)
    log[2].complete = nil
    Update()
    EQ(Offer(61), nil, "C: no longer complete: its offer goes")
    -- Complete again, then abandoned
    log[2].complete = 1
    Update()
    CHECK(Offer(61) ~= nil, "C: complete again: offered again")
    table.remove(log, 2)
    M.Fire("QUEST_REMOVED", 61)
    Update()
    EQ(Offer(61), nil, "C: abandoned: its offer goes")
    -- Under a collapsed header: not seen, left as it was
    log = { { title = "Elwynn", header = true }, { title = "The Fargodeep Mine", questID = 60 } }
    Update()
    log[2].complete = 1
    Update()
    CHECK(Offer(60) ~= nil, "C: (offered)")
    log = { { title = "Elwynn", header = true } }       -- the header collapsed
    Update()
    CHECK(Offer(60) ~= nil, "C: a quest under a collapsed header keeps its offer")
    log = { { title = "Elwynn", header = true }, { title = "The Fargodeep Mine", questID = 60, complete = 1 } }
    Update()
    EQ(#O().List({ source = "Objectives" }), 1, "C: ...and expanding it again offers nothing twice")
    NoErrors("C")
end)

-- ===========================================================================
Section("D", function()
    log = { { title = "The Fargodeep Mine", questID = 60 } }
    Boot()
    M.SetCombat(true)
    log[1].complete = 1
    Update()
    EQ(Offer(60), nil, "D: in combat nothing is placed")
    M.SetCombat(false)
    M.Frame()
    CHECK(Offer(60) ~= nil, "D: it is placed when combat ends")
    local a = O().Active()
    CHECK(not (a and a.why == "PINNED"), "D: with nothing of yours it is still never PINNED", a and a.why)
    NoErrors("D")
end)

-- ===========================================================================
Section("E", function()
    log = { { title = "The Fargodeep Mine", questID = 60 } }
    Boot({ adapter = false })
    log[1].complete = 1
    Update()
    EQ(Offer(60), nil, "E: without Commander Quest Log's adapter: nothing")
    log = { { title = "Lost Cause", questID = 62 } }
    Boot()
    log[1].complete = 1
    Update()
    EQ(Offer(62), nil, "E: a finisher with no place: nothing")
    NoErrors("E")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
