-- Commander Promotion + the REAL Commander Orders (luajit).
--
--     /opt/homebrew/bin/luajit Commander_Promotion/Harness/promotion_orders_smoke.lua
--     PROMOTION_RUNTIME=/tmp/mutant.lua luajit ...   (a mutated CommanderPromotion.lua)
--
-- Promotion 2.2.0 (Commander Orders 3.1, SPEC 5 and S9): on a level-up the
-- banner names the nearest class trainer, and Trainer Offer marks it with a
-- quiet waypoint, the way Commander Adjutant offers a repairer. This boots the
-- real Orders over the client mock its own harnesses share
-- (Commander_Orders/Harness/orders_mock.lua, the real Commander_Events
-- framework) and Promotion's two files after it. There is no Questie in the
-- mock, so the trainers come from a townsfolk resolver registered the way
-- Commander Logistics registers its learned repair book.
--   A  loads clean; Trainer Offer ships on
--   B  a level-up: the banner names the nearest trainer; ONE quiet waypoint
--      (Promotion, trainer): temporary, session-only, silent, never taking
--      the arrow from a pin of yours; the next level-up moves it
--   C  in combat: no waypoint until combat ends (Adjutant's parking rule)
--   D  opening a class trainer takes the offer down; a profession trainer
--      does not
--   E  at the cap, or with Trainer Offer off: no line, no waypoint
--   F  nobody to name: no line, no waypoint, nothing errors
--   G  /cpromo trainer: asked for, so the arrow goes there and Orders says so

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
local TRAINERS = {
    { map = 1429, x = 0.411, y = 0.658, title = "Brother Wilhelm", npc = 927 },
    { map = 1429, x = 0.250, y = 0.300, title = "Far Trainer", npc = 9003 },
}
local tradeskill = false

local function Boot(opts)
    opts = opts or {}
    local mutant = os.getenv("PROMOTION_RUNTIME")
    local files = { "CommanderPromotionDB.lua" }
    if not mutant then files[2] = "CommanderPromotion.lua" end
    M.Boot({
        player = GOLDSHIRE,
        skipFiles = SKIP,
        saved = opts.saved,
        before = function()
            rawset(_G, "IsTradeskillTrainer", function() return tradeskill end)
        end,
        addons = { { name = "Commander_Promotion", files = files } },
        afterFiles = function()
            if mutant then
                local chunk, err = loadfile(mutant)
                if not chunk then M.loadErrors[#M.loadErrors + 1] = tostring(err) else
                    local ok, runErr = pcall(chunk)
                    if not ok then M.loadErrors[#M.loadErrors + 1] = tostring(runErr) end
                end
            end
            if opts.book ~= false then
                CommanderOrders.RegisterResolver("townsfolk", function(kind)
                    if kind == "Class Trainer" then return TRAINERS end
                end)
            end
        end,
    })
end

local function O() return rawget(_G, "CommanderOrders") end
local function NoErrors(label)
    CHECK(#M.errors == 0, label .. ": no errors", M.errors[1])
    CHECK(#M.loadErrors == 0, label .. ": no load errors", M.loadErrors[1])
end
local function Count(needle)
    local n = 0
    for _, line in ipairs(M.prints) do
        if tostring(line):find(needle, 1, true) then n = n + 1 end
    end
    return n
end
local function LevelUp(level)
    M.Fire("PLAYER_LEVEL_UP", level, 40, 30, 1, 0, 1, 1, 2, 1)
    M.Frame()
end
-- The banner's trainer line: the shown FontString under the banner saying so
local function TrainerLine()
    for _, w in ipairs(M.W.widgets) do
        local t = rawget(w, "__text")
        if w.__kind == "FontString" and type(t) == "string" and t:find("New ranks at your class trainer", 1, true)
            and w.__shown ~= false then
            return t
        end
    end
    return nil
end
local function Offer() return O().R.Store():ByKey("Promotion", "trainer") end

-- ===========================================================================
Section("A", function()
    Boot()
    NoErrors("A")
    EQ(CommanderPromotionDB.TrainerOffer, true, "A: Trainer Offer ships on")
end)

-- ===========================================================================
Section("B", function()
    Boot()
    LevelUp(19)
    local alone = O().Active()
    CHECK(Offer() ~= nil and not (alone and alone.why == "PINNED"),
        "B: with nothing of yours the offer is never PINNED (it never asks for the arrow)", alone and alone.why)
    Boot()
    local mine = O().Add({ map = 1429, x = 0.48, y = 0.42, title = "Mine" })
    M.Frame()
    M.ClearLog()
    LevelUp(20)
    local line = TrainerLine()
    CHECK(line and line:find("Brother Wilhelm (Elwynn Forest 41.1, 65.8)", 1, true),
        "B: the banner names the nearest class trainer", line)
    local wp = Offer()
    CHECK(wp ~= nil, "B: a waypoint (Promotion, trainer)")
    CHECK(wp and wp.temporary == true and wp.persistent == false, "B: ...temporary and session-only")
    EQ(wp and wp.icon, "TRAINER", "B: ...in the trainer tint")
    EQ(wp and wp.alternatives and #wp.alternatives, 2, "B: ...every trainer on your landmass as its choices")
    EQ(Count("Waypoint set"), 0, "B: ...quietly: no chat line for an offer")
    EQ(O().Active() and O().Active().uid, mine, "B: and it never takes the arrow from a pin of yours")
    LevelUp(21)
    EQ(#O().List({ source = "Promotion" }), 1, "B: the next level-up moves it, never stacks")
    NoErrors("B")
end)

-- ===========================================================================
Section("C", function()
    Boot()
    M.SetCombat(true)
    LevelUp(22)
    EQ(Offer(), nil, "C: in combat no waypoint is placed")
    CHECK(TrainerLine() ~= nil, "C: (the banner still says where)")
    M.SetCombat(false)
    M.Frame()
    CHECK(Offer() ~= nil, "C: it is placed when combat ends")
    NoErrors("C")
end)

-- ===========================================================================
Section("D", function()
    Boot()
    LevelUp(24)
    CHECK(Offer() ~= nil, "D: (the offer)")
    tradeskill = true
    M.Fire("TRAINER_SHOW")
    CHECK(Offer() ~= nil, "D: a profession trainer leaves it")
    tradeskill = false
    M.Fire("TRAINER_SHOW")
    M.Frame()
    EQ(Offer(), nil, "D: opening a class trainer takes it down")
    NoErrors("D")
end)

-- ===========================================================================
Section("E", function()
    Boot()
    LevelUp(70)
    EQ(TrainerLine(), nil, "E: at the cap no trainer line")
    EQ(Offer(), nil, "E: ...and no waypoint")
    Boot({ saved = { CommanderPromotionDB = { TrainerOffer = false } } })
    LevelUp(30)
    EQ(TrainerLine(), nil, "E: Trainer Offer off: no line")
    EQ(Offer(), nil, "E: ...and no waypoint")
    NoErrors("E")
end)

-- ===========================================================================
Section("F", function()
    Boot({ book = false })
    LevelUp(32)
    EQ(TrainerLine(), nil, "F: nobody to name: no line")
    EQ(Offer(), nil, "F: ...no waypoint")
    NoErrors("F")
end)

-- ===========================================================================
Section("G", function()
    Boot()
    M.ClearLog()
    SlashCmdList["COMMANDERUI_PROMOTION"]("trainer")
    M.Frame()
    local wp = Offer()
    CHECK(wp ~= nil, "G: /cpromo trainer: the waypoint")
    EQ(O().Active() and O().Active().uid, wp and wp.uid, "G: ...with the arrow on it (asked for)")
    EQ(Count("Waypoint set"), 1, "G: ...and Orders says so, once")
    NoErrors("G")
end)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
