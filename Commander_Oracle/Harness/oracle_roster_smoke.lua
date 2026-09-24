-- Commander Oracle roster smoke (luajit). The Impact score and the one-line
-- read, checked against hand-built scoreboards — no WoW mock needed, because
-- the roster arithmetic never touches the client API.
--
--   luajit Commander_Oracle/Harness/oracle_roster_smoke.lua

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

local function NEAR(a, b, tol)
    if type(a) ~= "number" or type(b) ~= "number" then return false end
    return math.abs(a - b) <= (tol or 0.001)
end

assert(loadfile(ADDONS .. "/Commander_Oracle/CommanderOracleRoster.lua"))()
local R = CommanderOracle_Roster

-- A row builder so a scoreboard reads as a scoreboard in the tests
local function Row(name, faction, spec)
    spec = spec or {}
    return {
        name = name, faction = faction, classToken = spec.classToken,
        killingBlows = spec.kb or 0, honorableKills = spec.hk or 0,
        deaths = spec.deaths or 0, damage = spec.dmg or 0, healing = spec.heal or 0,
        honor = spec.honor or 0, objectives = spec.obj or {},
    }
end

local AB_COLUMNS = { "Bases Assaulted", "Bases Defended" }

local function Find(report, name)
    for _, entry in ipairs(report.players) do
        if entry.name == name then return entry end
    end
end

local function Group(faction, report, key)
    for _, group in ipairs(report.factions[faction].groups) do
        if group.key == key then return group end
    end
end

-- ---------------------------------------------------------------------------
-- A: formatting
-- ---------------------------------------------------------------------------
CHECK(R.Short(0) == "0", "A: zero", R.Short(0))
CHECK(R.Short(940) == "940", "A: raw under a thousand", R.Short(940))
CHECK(R.Short(1500) == "1.5k", "A: one decimal in the thousands", R.Short(1500))
CHECK(R.Short(41200) == "41k", "A: whole thousands once it is big", R.Short(41200))
CHECK(R.Short(1600000) == "1.6m", "A: millions", R.Short(1600000))

-- ---------------------------------------------------------------------------
-- A2: range -- four different answers, and each says which one it is
-- ---------------------------------------------------------------------------
CHECK(NEAR(R.Distance(0, 0, 3, 4), 5), "A2: plain euclidean yards", R.Distance(0, 0, 3, 4))
CHECK(R.RangeText({ yards = 23.4 }) == "23y", "A2: a measured distance is a number",
    R.RangeText({ yards = 23.4 }))
CHECK(R.RangeText({ yards = 0 }) == "0y", "A2: including standing on them",
    R.RangeText({ yards = 0 }))
-- The "<" is the honesty: an interaction band is an upper bound, and printing
-- it as a bare number would claim a measurement nobody made
CHECK(R.RangeText({ within = 28 }) == "<28y", "A2: a bound is written as a bound",
    R.RangeText({ within = 28 }))
CHECK(R.RangeText({ seen = true }) == "seen", "A2: a unit with no range at all still says so",
    R.RangeText({ seen = true }))
CHECK(R.RangeText(nil) == "", "A2: and nothing known prints nothing", R.RangeText(nil))
CHECK(R.RangeText({ yards = 40000 }) == "",
    "A2: a nonsense reading is dropped rather than drawn",
    R.RangeText({ yards = 40000 }))
local r1, g1 = R.RangeColor({ yards = 5 })
local r2, g2 = R.RangeColor({ yards = 20 })
local r3, g3 = R.RangeColor({ yards = 80 })
CHECK(r1 == 1 and g1 < 0.5, "A2: on top of you reads as danger", g1)
CHECK(r2 == 1 and g2 > 0.8, "A2: in play reads as live", g2)
CHECK(r3 < 0.7, "A2: out of the fight reads as neither", r3)

-- ---------------------------------------------------------------------------
-- A3: marking a team by class colour
-- ---------------------------------------------------------------------------
local function MarkNames(classes)
    local assigned = R.AssignMarks(classes)
    local out = {}
    for slot in ipairs(classes) do
        out[#out + 1] = assigned[slot] and R.MARK_NAMES[assigned[slot]] or "--"
    end
    return table.concat(out, ",")
end

CHECK(MarkNames({ "DRUID" }) == "Circle", "A3: the druid takes the orange circle",
    MarkNames({ "DRUID" }))
CHECK(MarkNames({ "ROGUE" }) == "Star", "A3: the rogue the yellow star", MarkNames({ "ROGUE" }))
CHECK(MarkNames({ "SHAMAN" }) == "Square", "A3: the shaman the blue square",
    MarkNames({ "SHAMAN" }))
CHECK(MarkNames({ "WARLOCK" }) == "Diamond", "A3: the warlock the purple diamond",
    MarkNames({ "WARLOCK" }))
CHECK(MarkNames({ "PRIEST" }) == "Skull", "A3: and the priest's white the skull",
    MarkNames({ "PRIEST" }))

-- The failure that motivates the whole hue rule: on plain RGB distance a pale
-- cyan and a pale green are close neighbours, and the mage lands on the green
-- triangle -- which is not a colour anybody would call a mage.
CHECK(MarkNames({ "MAGE" }) ~= "Triangle", "A3: the mage is never put on the green triangle",
    MarkNames({ "MAGE" }))
CHECK(MarkNames({ "MAGE" }) == "Moon", "A3: it gets the pale blue moon", MarkNames({ "MAGE" }))

-- A colour is never matched to a non-colour, in either direction
CHECK(MarkNames({ "WARRIOR" }) ~= "Skull" and MarkNames({ "PALADIN" }) ~= "Skull",
    "A3: the skull belongs to white, and nobody else may have it")
CHECK(R.MarkDistance(R.CLASS_COLORS.WARRIOR, R.MARK_COLORS[8]) > 1,
    "A3: which the distance says out loud rather than by luck",
    R.MarkDistance(R.CLASS_COLORS.WARRIOR, R.MARK_COLORS[8]))

-- Every icon is used at most once, so a team of one class still reads
CHECK(MarkNames({ "MAGE", "MAGE", "MAGE" }) == "Moon,Square,Triangle",
    "A3: three mages get three different icons", MarkNames({ "MAGE", "MAGE", "MAGE" }))

-- Matched over the team actually present: a warrior alone is not turned away
-- for having no brown marker
CHECK(MarkNames({ "WARRIOR" }) ~= "--", "A3: a warrior alone still gets one",
    MarkNames({ "WARRIOR" }))
CHECK(MarkNames({ "WARRIOR", "PALADIN", "HUNTER", "MAGE", "DRUID" })
    == "Cross,Diamond,Star,Moon,Circle",
    "A3: and a real arena team comes out whole",
    MarkNames({ "WARRIOR", "PALADIN", "HUNTER", "MAGE", "DRUID" }))

-- Eight icons, nine classes: somebody goes without rather than sharing
local everyone = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
    "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local placed = 0
for _, index in pairs(R.AssignMarks(everyone)) do
    if index then placed = placed + 1 end
end
CHECK(placed == 8, "A3: eight icons is eight players, and the ninth goes unmarked", placed)

-- A player the client has not seen yet has no class and is simply skipped
local partial = R.AssignMarks({ "DRUID", nil, "ROGUE" })
CHECK(partial[1] and not partial[2], "A3: an unknown class is skipped, not guessed")

-- The same team must resolve the same way every time: an assignment that
-- wobbled would re-mark the raid for nothing
CHECK(MarkNames({ "ROGUE", "MAGE", "PRIEST", "WARRIOR", "SHAMAN" })
    == MarkNames({ "ROGUE", "MAGE", "PRIEST", "WARRIOR", "SHAMAN" }),
    "A3: and it is deterministic")

-- ---------------------------------------------------------------------------
-- B: an empty and a barely-started scoreboard say so rather than ranking noise
-- ---------------------------------------------------------------------------
local empty = R.Rank({}, { myFaction = "ALLIANCE" })
CHECK(empty.ready == false, "B: no rows is not a ranking")
CHECK(empty.reason ~= nil, "B: and it says why", empty.reason)

local silent = R.Rank({
    Row("Aone", "ALLIANCE"), Row("Hone", "HORDE"),
}, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
CHECK(silent.ready == false, "B: all-zero rows are not a ranking either")
CHECK(silent.reason == "The scoreboard is still empty.", "B: named exactly", silent.reason)

-- ---------------------------------------------------------------------------
-- C: the denominator is the top THREE, not the top one
--
-- One farmed-out player must not flatten everyone else to a rounding error.
-- ---------------------------------------------------------------------------
local outlierBoard = {
    Row("Runaway", "ALLIANCE", { kb = 30, dmg = 300000 }),
    Row("Second",  "ALLIANCE", { kb = 10, dmg = 100000 }),
    Row("Third",   "ALLIANCE", { kb = 10, dmg = 100000 }),
    Row("Fourth",  "HORDE",    { kb = 10, dmg = 100000 }),
}
local outlier = R.Rank(outlierBoard, { myFaction = "ALLIANCE" })
CHECK(NEAR(outlier.denominators.kills, (30 + 10 + 10) / 3), "C: kills denominator is the top-three mean",
    outlier.denominators.kills)
-- Second is on 10 of a 16.67 denominator = 0.6, not 10/30 = 0.33
CHECK(NEAR(Find(outlier, "Second").shares.kills, 10 / ((30 + 10 + 10) / 3), 0.0001),
    "C: a mid player keeps a readable share", Find(outlier, "Second").shares.kills)
CHECK(Find(outlier, "Runaway").shares.kills == 1, "C: and the outlier clamps at 1",
    Find(outlier, "Runaway").shares.kills)

-- ---------------------------------------------------------------------------
-- D: a metric nobody scored drops out and its weight is redistributed
-- ---------------------------------------------------------------------------
local noObjectives = R.Rank({
    Row("Aone", "ALLIANCE", { kb = 5, dmg = 50000 }),
    Row("Hone", "HORDE", { kb = 4, dmg = 40000 }),
}, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
CHECK(noObjectives.ready == true, "D: still a ranking with no objectives scored")
CHECK(noObjectives.weights.objectives == 0, "D: the objective weight is zeroed",
    noObjectives.weights.objectives)
CHECK(NEAR(noObjectives.weights.kills + noObjectives.weights.output
    + noObjectives.weights.trade, 1),
    "D: and redistributed over what is left",
    noObjectives.weights.kills + noObjectives.weights.output + noObjectives.weights.trade)
-- The best player at everything that IS reported scores 100 before survival
local top = Find(noObjectives, "Aone")
CHECK(top.impact == 100, "D: topping every live metric is a full score", top.impact)

-- A client that never fills the healing column still scores damage
local noHealing = R.Rank({
    Row("Aone", "ALLIANCE", { kb = 5, dmg = 50000 }),
    Row("Hone", "HORDE", { kb = 4, dmg = 40000 }),
}, { myFaction = "ALLIANCE" })
CHECK(noHealing.weights.output > 0, "D: output survives on damage alone", noHealing.weights.output)

-- ---------------------------------------------------------------------------
-- E: a healer is scored on the currency they actually spend
-- ---------------------------------------------------------------------------
local mixed = {
    Row("Smasher", "ALLIANCE", { kb = 10, dmg = 300000, deaths = 4 }),
    Row("Mender",  "ALLIANCE", { kb = 0,  dmg = 5000, heal = 300000, deaths = 4 }),
    Row("Filler",  "ALLIANCE", { kb = 3,  dmg = 90000, deaths = 4 }),
    Row("Hone",    "HORDE",    { kb = 9,  dmg = 250000, deaths = 4 }),
    Row("Htwo",    "HORDE",    { kb = 2,  dmg = 60000, heal = 40000, deaths = 4 }),
}
local mix = R.Rank(mixed, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
local mender = Find(mix, "Mender")
CHECK(mender.role == "HEALER", "E: healing over damage reads as a healer", mender.role)
CHECK(mender.outputKey == "healing", "E: judged on healing", mender.outputKey)
CHECK(mender.shares.output == 1, "E: topping the healing is a full output share",
    mender.shares.output)
CHECK(mender.reason == "healing", "E: and that is what they are on the board for", mender.reason)
-- The client's own column label is a sentence; a board cell has room for the
-- noun. Objectives are the smallest weight now, so a player only reads as an
-- objective player when objectives are genuinely all they did.
local capper = R.Rank({
    Row("Acap", "ALLIANCE", { kb = 0, dmg = 2000, deaths = 2, obj = { 6, 2 } }),
    Row("Adps", "ALLIANCE", { kb = 8, dmg = 200000, deaths = 2, obj = { 0, 0 } }),
    Row("Hone", "HORDE", { kb = 7, dmg = 180000, deaths = 2, obj = { 0, 0 } }),
}, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
CHECK(Find(capper, "Acap").reason == "bases",
    "E: an objective player reads as the noun, not the column sentence",
    Find(capper, "Acap").reason)
CHECK(mender.impact > Find(mix, "Filler").impact,
    "E: a healer out-scores a middling damage dealer",
    mender.impact .. " vs " .. Find(mix, "Filler").impact)

-- ---------------------------------------------------------------------------
-- F: the trade -- what you produced against the lives you spent on it
--
-- The StarCraft reading: two players with the same output are not the same
-- player if one of them fed eight deaths doing it.
-- ---------------------------------------------------------------------------
local tradeBoard = {
    Row("Efficient", "ALLIANCE", { kb = 6, dmg = 200000, deaths = 1 }),
    Row("Feeder",    "ALLIANCE", { kb = 6, dmg = 200000, deaths = 9 }),
    Row("Hone",      "HORDE",    { kb = 5, dmg = 150000, deaths = 4 }),
}
local trade = R.Rank(tradeBoard, { myFaction = "ALLIANCE", runTime = 600 })
CHECK(NEAR(Find(trade, "Efficient").perLife, 100000),
    "F: value per life spent, and a life you still hold counts as one",
    Find(trade, "Efficient").perLife)
CHECK(NEAR(Find(trade, "Feeder").perLife, 20000), "F: ten lives buys a tenth as much",
    Find(trade, "Feeder").perLife)
CHECK(Find(trade, "Efficient").impact > Find(trade, "Feeder").impact,
    "F: identical output, and the one who kept dying scores lower",
    Find(trade, "Efficient").impact .. " vs " .. Find(trade, "Feeder").impact)
CHECK(Find(trade, "Efficient").impact - Find(trade, "Feeder").impact >= 15,
    "F: by a margin worth reading, not a rounding difference",
    Find(trade, "Efficient").impact - Find(trade, "Feeder").impact)
CHECK(Find(trade, "Efficient").reason == "damage" or Find(trade, "Efficient").reason == "trade",
    "F: and reads as what carried it", Find(trade, "Efficient").reason)

-- Deaths are priced inside the trade now, not bolted on as a multiplier, so a
-- player who did nothing still scores nothing however long they lived
local afkBoard = {
    Row("Worker", "ALLIANCE", { kb = 10, dmg = 200000, deaths = 6 }),
    Row("Hider",  "ALLIANCE", { kb = 0,  dmg = 0, deaths = 0 }),
    Row("Hone",   "HORDE",    { kb = 8, dmg = 150000, deaths = 6 }),
    Row("Htwo",   "HORDE",    { kb = 6, dmg = 120000, deaths = 6 }),
}
local afk = R.Rank(afkBoard, { myFaction = "ALLIANCE" })
CHECK(Find(afk, "Hider").impact == 0, "F: doing nothing and dying none is still nothing",
    Find(afk, "Hider").impact)
CHECK(Find(afk, "Worker").impact <= 100, "F: nobody ever reads over 100",
    Find(afk, "Worker").impact)
CHECK(Find(afk, "Worker").impact > 0, "F: while the player who actually played scores",
    Find(afk, "Worker").impact)

-- ---------------------------------------------------------------------------
-- F2: objectives are DEVALUED on purpose
--
-- The board that prompted the reweight: a healer with three base defends was
-- out-scoring a warlock on twelve killing blows and the best damage in the
-- match, because a 0-to-5 integer saturates its own share instantly and used
-- to carry the heaviest weight.
-- ---------------------------------------------------------------------------
local basesBoard = {
    Row("Grimjaw", "HORDE", { kb = 12, deaths = 2, dmg = 251000, obj = { 1, 0 } }),
    Row("Hexmark", "HORDE", { kb = 0, deaths = 1, dmg = 15000, heal = 240000, obj = { 0, 3 } }),
    Row("Kelthuz", "HORDE", { kb = 5, deaths = 4, dmg = 176000, obj = { 2, 0 } }),
    Row("Ashvale", "ALLIANCE", { kb = 9, deaths = 3, dmg = 214000, obj = { 2, 1 } }),
    Row("Coldiron", "ALLIANCE", { kb = 7, deaths = 5, dmg = 168000, obj = { 4, 0 } }),
    Row("Brackwater", "ALLIANCE", { kb = 1, deaths = 2, dmg = 12000, heal = 186000, obj = { 0, 2 } }),
}
local bases = R.Rank(basesBoard, { myFaction = "ALLIANCE", columns = AB_COLUMNS, runTime = 480 })
CHECK(Find(bases, "Grimjaw").impact > Find(bases, "Hexmark").impact,
    "F2: twelve killing blows and the best damage now beat three base defends",
    Find(bases, "Grimjaw").impact .. " vs " .. Find(bases, "Hexmark").impact)
CHECK(Find(bases, "Ashvale").impact > Find(bases, "Coldiron").impact,
    "F2: and the better player beats the one with more caps",
    Find(bases, "Ashvale").impact .. " vs " .. Find(bases, "Coldiron").impact)
CHECK(Find(bases, "Coldiron").reason ~= "bases",
    "F2: caps stop being what everybody reads as", Find(bases, "Coldiron").reason)
CHECK(R.WEIGHTS.objectives < R.WEIGHTS.kills and R.WEIGHTS.objectives < R.WEIGHTS.output
    and R.WEIGHTS.objectives < R.WEIGHTS.trade,
    "F2: objectives are the smallest weight, deliberately", R.WEIGHTS.objectives)

-- Topping ONLY the objective column cannot buy the board any more
local onlyCaps = R.Rank({
    Row("Capper", "ALLIANCE", { kb = 0, deaths = 3, dmg = 3000, obj = { 5, 3 } }),
    Row("Fighter", "ALLIANCE", { kb = 9, deaths = 1, dmg = 200000, obj = { 0, 0 } }),
    Row("Hone", "HORDE", { kb = 4, deaths = 4, dmg = 90000, obj = { 1, 0 } }),
}, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
CHECK(Find(onlyCaps, "Fighter").impact > Find(onlyCaps, "Capper").impact,
    "F2: a player who only capped cannot out-score one who did everything else",
    Find(onlyCaps, "Fighter").impact .. " vs " .. Find(onlyCaps, "Capper").impact)

-- ---------------------------------------------------------------------------
-- F3: rates, the way a post-game screen reads them
-- ---------------------------------------------------------------------------
CHECK(R.Rate(240000, 480) == "30k/min", "F3: output per minute", R.Rate(240000, 480))
CHECK(R.Rate(12, 480) == "1.5/min", "F3: a small rate keeps its decimal", R.Rate(12, 480))
CHECK(R.Rate(100, nil) == nil, "F3: no clock, no rate -- not a zero")
CHECK(Find(trade, "Efficient").rates.output == R.Rate(200000, 600),
    "F3: carried on the entry for the read-out", Find(trade, "Efficient").rates.output)

-- ---------------------------------------------------------------------------
-- G: the per-metric boards -- top N, zeros dropped, stable order
-- ---------------------------------------------------------------------------
local boardRows = {
    Row("Acap",  "ALLIANCE", { kb = 2, dmg = 40000, obj = { 4, 1 } }),
    Row("Adps",  "ALLIANCE", { kb = 9, dmg = 220000, obj = { 0, 0 } }),
    Row("Aheal", "ALLIANCE", { kb = 0, dmg = 2000, heal = 180000, obj = { 0, 2 } }),
    Row("Aidle", "ALLIANCE", { kb = 0, dmg = 0, obj = { 0, 0 } }),
    Row("Hdps",  "HORDE",    { kb = 7, dmg = 200000, obj = { 1, 0 } }),
}
local board = R.Rank(boardRows, { myFaction = "ALLIANCE", columns = AB_COLUMNS, topCount = 3 })
local kills = Group("ALLIANCE", board, "kills")
CHECK(#kills.rows == 2, "G: players on zero are left off a board they scored nothing on", #kills.rows)
CHECK(kills.rows[1].player.name == "Adps", "G: ordered by the metric", kills.rows[1].player.name)
local objective1 = Group("ALLIANCE", board, "objective1")
CHECK(objective1 and objective1.label == "Bases Assaulted",
    "G: objective boards are named by the client's own column",
    objective1 and objective1.label)
CHECK(objective1.rows[1].player.name == "Acap", "G: and ranked", objective1.rows[1].player.name)
CHECK(#board.factions.ALLIANCE.groups == 5,
    "G: three universal boards plus one per objective column",
    #board.factions.ALLIANCE.groups)
CHECK(board.factions.ALLIANCE.totals.kills == 11, "G: faction totals",
    board.factions.ALLIANCE.totals.kills)
CHECK(board.factions.ALLIANCE.totals.objectives == 7, "G: including every objective column",
    board.factions.ALLIANCE.totals.objectives)

-- A tie has to resolve the same way twice or the board flickers on refresh
local tied = R.Rank({
    Row("Bravo", "ALLIANCE", { kb = 5, dmg = 100000 }),
    Row("Alpha", "ALLIANCE", { kb = 5, dmg = 100000 }),
    Row("Hone",  "HORDE",    { kb = 5, dmg = 100000 }),
}, { myFaction = "ALLIANCE" })
CHECK(tied.factions.ALLIANCE.players[1].name == "Alpha",
    "G: equal scores break by name, not by arrival order",
    tied.factions.ALLIANCE.players[1].name)

-- ---------------------------------------------------------------------------
-- H: the one-line read, in priority order
-- ---------------------------------------------------------------------------
local healerBoard = R.Rank({
    Row("Amain", "ALLIANCE", { kb = 6, dmg = 150000 }),
    Row("Hheal", "HORDE",    { kb = 0, dmg = 4000, heal = 400000 }),
    Row("Hdps",  "HORDE",    { kb = 8, dmg = 200000, heal = 20000 }),
    Row("Hdps2", "HORDE",    { kb = 7, dmg = 190000, heal = 10000 }),
}, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
CHECK(healerBoard.summaryKind == "HEALER", "H: the enemy healer outranks everything else",
    healerBoard.summaryKind)
CHECK(healerBoard.summary:find("Hheal", 1, true) ~= nil, "H: and is named", healerBoard.summary)

local killerBoard = R.Rank({
    Row("Amain", "ALLIANCE", { kb = 6, dmg = 150000 }),
    Row("Hkill", "HORDE",    { kb = 12, dmg = 200000 }),
    Row("Hdps",  "HORDE",    { kb = 2, dmg = 180000 }),
    Row("Hdps2", "HORDE",    { kb = 2, dmg = 170000 }),
}, { myFaction = "ALLIANCE" })
CHECK(killerBoard.summaryKind == "KILLER", "H: then whoever is doing the killing",
    killerBoard.summaryKind)

local capBoard = R.Rank({
    Row("Amain", "ALLIANCE", { kb = 6, dmg = 150000, obj = { 1, 0 } }),
    Row("Hcap",  "HORDE",    { kb = 3, dmg = 100000, obj = { 5, 1 } }),
    Row("Hdps",  "HORDE",    { kb = 4, dmg = 120000, obj = { 1, 0 } }),
    Row("Hdps2", "HORDE",    { kb = 4, dmg = 110000, obj = { 0, 1 } }),
}, { myFaction = "ALLIANCE", columns = AB_COLUMNS })
CHECK(capBoard.summaryKind == "OBJECTIVE", "H: then whoever is running the objectives",
    capBoard.summaryKind)
CHECK(capBoard.summary:find("Hcap", 1, true) ~= nil, "H: named too", capBoard.summary)

-- Leading is not standing out. Two healers splitting the healing means there
-- is no one healer to focus, and the read must not name one anyway.
local twoHealers = R.Rank({
    Row("Amain",  "ALLIANCE", { kb = 6, dmg = 150000, deaths = 3 }),
    Row("Hheal",  "HORDE",    { kb = 0, dmg = 4000, heal = 220000, deaths = 3 }),
    Row("Hheal2", "HORDE",    { kb = 0, dmg = 4000, heal = 200000, deaths = 3 }),
    Row("Hdps",   "HORDE",    { kb = 8, dmg = 200000, deaths = 3 }),
}, { myFaction = "ALLIANCE" })
CHECK(twoHealers.summaryKind ~= "HEALER",
    "H: two healers splitting the load is not one healer to focus",
    twoHealers.summary)

-- Nobody stands out: say how the sides are shaped instead of inventing a call
local evenBoard = {}
for i = 1, 8 do
    evenBoard[#evenBoard + 1] = Row("Ally" .. i, "ALLIANCE", { kb = 4, dmg = 100000, deaths = 3 })
    evenBoard[#evenBoard + 1] = Row("Horde" .. i, "HORDE", { kb = 4, dmg = 100000, deaths = 3 })
end
local even = R.Rank(evenBoard, { myFaction = "ALLIANCE" })
CHECK(even.summaryKind == "BEST" or even.summaryKind == "EVEN",
    "H: an even board gets an even read", even.summaryKind)
CHECK(even.summary:find("healing") == nil, "H: and does not invent a healer to focus", even.summary)

-- The army-level read: destroyed against lost, and it only speaks when both
-- sides agree about who is winning the fights
local tradeRead = R.Rank({
    Row("Amain", "ALLIANCE", { kb = 2, dmg = 90000, deaths = 8 }),
    Row("Atwo",  "ALLIANCE", { kb = 2, dmg = 80000, deaths = 8 }),
    Row("Hone",  "HORDE",    { kb = 8, dmg = 150000, deaths = 2 }),
    Row("Htwo",  "HORDE",    { kb = 8, dmg = 140000, deaths = 2 }),
}, { myFaction = "ALLIANCE" })
CHECK(tradeRead.summaryKind == "TRADE", "H: losing the fights is worth saying",
    tradeRead.summaryKind)
CHECK(tradeRead.summary:find("stop taking the fights", 1, true) ~= nil,
    "H: with the call that follows from it", tradeRead.summary)
CHECK(NEAR(tradeRead.factions.HORDE.totals.trade, 4),
    "H: sixteen kills for four deaths is four to one",
    tradeRead.factions.HORDE.totals.trade)

-- Everybody killing everybody is not an advantage for whoever we asked first
local bothBusy = R.Rank({
    Row("Amain", "ALLIANCE", { kb = 8, dmg = 90000, deaths = 6 }),
    Row("Atwo",  "ALLIANCE", { kb = 8, dmg = 80000, deaths = 6 }),
    Row("Hone",  "HORDE",    { kb = 8, dmg = 90000, deaths = 6 }),
    Row("Htwo",  "HORDE",    { kb = 8, dmg = 80000, deaths = 6 }),
}, { myFaction = "ALLIANCE" })
CHECK(bothBusy.summaryKind ~= "TRADE",
    "H: a bloodbath both sides are winning is not a trade read", bothBusy.summary)

-- A side carried by three people is worth saying out loud
local topHeavy = {}
for i = 1, 3 do
    topHeavy[#topHeavy + 1] = Row("Carry" .. i, "HORDE", { kb = 9, dmg = 250000, deaths = 2 })
    topHeavy[#topHeavy + 1] = Row("Ally" .. i, "ALLIANCE", { kb = 5, dmg = 120000, deaths = 2 })
end
for i = 4, 9 do
    topHeavy[#topHeavy + 1] = Row("Filler" .. i, "HORDE", { kb = 0, dmg = 1000, deaths = 2 })
    topHeavy[#topHeavy + 1] = Row("Ally" .. i, "ALLIANCE", { kb = 5, dmg = 120000, deaths = 2 })
end
local heavy = R.Rank(topHeavy, { myFaction = "ALLIANCE" })
CHECK(heavy.summaryKind == "TOPHEAVY", "H: a top-heavy side is named as one", heavy.summaryKind)
CHECK(heavy.summary:find("Horde", 1, true) ~= nil, "H: the right side", heavy.summary)

-- The first ninety seconds are noise and the read says so
local early = R.Rank(healerBoard.players and {
    Row("Amain", "ALLIANCE", { kb = 6, dmg = 150000 }),
    Row("Hheal", "HORDE", { kb = 0, dmg = 4000, heal = 400000 }),
} or {}, { myFaction = "ALLIANCE", runTime = 40 })
CHECK(early.summaryKind == "EARLY", "H: too early to rank anybody", early.summaryKind)
CHECK(early.ready == true, "H: which is still a ranking, just an honest read")

-- ---------------------------------------------------------------------------
-- I: the best player on each side is the one the board points at
-- ---------------------------------------------------------------------------
CHECK(board.best.ALLIANCE ~= nil and board.best.HORDE ~= nil, "I: one per side")
CHECK(board.best.ALLIANCE == board.factions.ALLIANCE.players[1],
    "I: and it is the top of that side's own order")
CHECK(board.best.ALLIANCE.impact >= board.factions.ALLIANCE.players[2].impact,
    "I: which is sorted by impact")

-- Anything that keeps a player across refreshes keeps the NAME and looks it up
CHECK(board.byName.Acap == Find(board, "Acap"), "I: entries are reachable by name")
CHECK(board.byName.Acap.fullName == "Acap",
    "I: and carry the scoreboard's own spelling for /targetexact and unit lookups",
    board.byName.Acap.fullName)
local crossRealm = R.Rank({
    { name = "Ashvale", fullName = "Ashvale-Whitemane", faction = "ALLIANCE",
      killingBlows = 3, deaths = 1, damage = 40000, healing = 0, objectives = {} },
    { name = "Hone", faction = "HORDE",
      killingBlows = 1, deaths = 1, damage = 10000, healing = 0, objectives = {} },
}, { myFaction = "ALLIANCE" })
CHECK(crossRealm.byName.Ashvale.fullName == "Ashvale-Whitemane",
    "I: a cross-realm row keeps its realm where the lookup can use it",
    crossRealm.byName.Ashvale.fullName)

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
