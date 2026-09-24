-- Commander Oracle engine smoke (luajit). The projection math, checked against
-- hand-computed Arathi Basin numbers — no WoW mock needed, because the engine
-- and the canon it reads never touch the client API.
--
--   luajit Commander_Oracle/Harness/oracle_engine_smoke.lua

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

assert(loadfile(ADDONS .. "/Commander_Oracle/CommanderOracleData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Oracle/CommanderOracleEngine.lua"))()

local AB = CommanderOracle_AB
local E = CommanderOracle_Engine
local INF = math.huge

-- ---------------------------------------------------------------------------
-- A: the canon itself
-- ---------------------------------------------------------------------------
CHECK(AB.maxScore == 2000, "A: TBC caps at 2000, not the later 1600", AB.maxScore)
CHECK(AB.captureSeconds == 60, "A: a flag takes a full minute", AB.captureSeconds)
CHECK(AB.uiMapID == 1461, "A: Arathi Basin is 1461 on this client", AB.uiMapID)
CHECK(#AB.nodes == 5, "A: five nodes", #AB.nodes)

-- Every node has five distinct POIs and every POI resolves back to it
local seen = {}
for _, node in ipairs(AB.nodes) do
    for _, id in pairs(node.poi) do
        CHECK(not seen[id], "A: POI " .. id .. " is claimed once")
        seen[id] = true
        CHECK(CommanderOracle_POI[id] and CommanderOracle_POI[id].node == node,
            "A: POI " .. id .. " maps back to " .. node.name)
    end
end
CHECK(CommanderOracle_POI[1612].assaulter == "ALLIANCE", "A: 1612 is the Alliance assaulting the Stables")
CHECK(CommanderOracle_POI[1613].assaulter == "HORDE", "A: 1613 is the Horde assaulting the Stables")
CHECK(CommanderOracle_POI[1610].owner == "ALLIANCE" and CommanderOracle_POI[1610].state == "OWNED",
    "A: 1610 is the Stables held by the Alliance")

-- ---------------------------------------------------------------------------
-- B: rates — the step function
-- ---------------------------------------------------------------------------
CHECK(E.Rate(0) == 0, "B: no bases, no income", E.Rate(0))
CHECK(NEAR(E.Rate(1), 10 / 12), "B: 1 base = 10 per 12s", E.Rate(1))
CHECK(NEAR(E.Rate(2), 10 / 9), "B: 2 bases = 10 per 9s", E.Rate(2))
CHECK(NEAR(E.Rate(3), 10 / 6), "B: 3 bases = 10 per 6s", E.Rate(3))
CHECK(NEAR(E.Rate(4), 10 / 3), "B: 4 bases = 10 per 3s", E.Rate(4))
CHECK(NEAR(E.Rate(5), 30), "B: 5 bases = 30 per 1s", E.Rate(5))
CHECK(E.Rate(9) == E.Rate(5) and E.Rate(-3) == 0, "B: base counts clamp")
-- The cliff that decides games: a five-cap is not "four plus one"
CHECK(E.Rate(5) / E.Rate(4) == 9, "B: the fifth base is a 9x multiplier", E.Rate(5) / E.Rate(4))

-- A five-cap from nothing ends it in about a minute; three bases takes twenty
CHECK(NEAR(E.TimeToCap(0, 5), 2000 / 30, 0.01), "B: 0->2000 on five bases", E.TimeToCap(0, 5))
CHECK(NEAR(E.TimeToCap(0, 3), 1200), "B: 0->2000 on three bases is 20 minutes", E.TimeToCap(0, 3))
CHECK(E.TimeToCap(0, 0) == INF, "B: nobody caps on nothing")
CHECK(E.TimeToCap(2000, 1) == 0, "B: already there")

-- ---------------------------------------------------------------------------
-- C: the race
-- ---------------------------------------------------------------------------
-- Even score, we hold 3 to their 2. Ours: 1000 left at 1/0.6s -> 600s.
-- Theirs in that time: 1000 + 600*(10/9) = 1666.67, so we win by 333.33.
local race = E.Race({ allianceScore = 1000, hordeScore = 1000, allianceBases = 3, hordeBases = 2 })
CHECK(race.winner == "ALLIANCE", "C: three bases beats two from level", race.winner)
CHECK(NEAR(race.seconds, 600), "C: and it lands at 600s", race.seconds)
CHECK(NEAR(race.margin, 2000 - (1000 + 600 * (10 / 9)), 0.01), "C: by 333", race.margin)

-- Being 400 down on four bases is not being down at all
local behind = E.Race({ allianceScore = 600, hordeScore = 1000, allianceBases = 4, hordeBases = 1 })
CHECK(behind.winner == "ALLIANCE", "C: 400 behind on 4 bases still wins", behind.winner)

-- Nobody holding anything is a stall, not a draw
local stalled = E.Race({ allianceScore = 5, hordeScore = 5, allianceBases = 0, hordeBases = 0 })
CHECK(stalled.stalled and stalled.winner == nil, "C: an empty board is stalled, not drawn")

-- A dead heat names no winner rather than picking one
local heat = E.Race({ allianceScore = 900, hordeScore = 900, allianceBases = 2, hordeBases = 2 })
CHECK(heat.winner == nil and heat.margin == 0, "C: a mirrored board is a dead heat", heat.winner)

-- Outcome is the race from one chair, and the two chairs must agree
local mine = E.Outcome({ allianceScore = 1000, hordeScore = 1000, allianceBases = 3, hordeBases = 2 }, "HORDE")
CHECK(mine.loss and not mine.win, "C: the same board is a loss from the other side")
CHECK(NEAR(mine.margin, race.margin), "C: and the margin is the same number")

-- ---------------------------------------------------------------------------
-- D: the ladder
-- ---------------------------------------------------------------------------
local snapshot = { allianceScore = 1000, hordeScore = 1000, allianceBases = 3, hordeBases = 2 }
local ladder = E.Ladder(snapshot, "ALLIANCE")
CHECK(#ladder == 6, "D: a row for every hold 0..5", #ladder)
CHECK(ladder[1].bases == 5 and ladder[6].bases == 0, "D: read top down, five first")

local byBases = {}
for _, row in ipairs(ladder) do byBases[row.bases] = row end
CHECK(byBases[5].win and byBases[4].win and byBases[3].win, "D: from level, three holds it")
CHECK(byBases[2].loss, "D: dropping to two loses it")
CHECK(byBases[0].loss, "D: and zero certainly does")
-- Holding more is never worth less
for bases = 1, 5 do
    if byBases[bases].win and byBases[bases - 1].win then
        CHECK(byBases[bases].margin >= byBases[bases - 1].margin - 0.001,
            "D: " .. bases .. " bases is worth at least as much as " .. (bases - 1))
    end
end
CHECK(E.MinimumHold(snapshot, "ALLIANCE") == 3, "D: the call is 'hold three'", E.MinimumHold(snapshot, "ALLIANCE"))

-- Four bases is not enough when they are one tick from the cap...
local desperate = { allianceScore = 100, hordeScore = 1900, allianceBases = 1, hordeBases = 4 }
CHECK(E.MinimumHold(desperate, "ALLIANCE") == 5, "D: when only a five-cap saves it, it says five",
    E.MinimumHold(desperate, "ALLIANCE"))

-- ...and the reason it says five is the sharpest rule in the map: a five-cap
-- takes the enemy's income to zero, so their score FREEZES. However far ahead
-- they are, they never arrive. Hold all five and the win is arithmetic.
for enemyScore = 0, AB.maxScore - 1, 199 do
    local cornered = { allianceScore = 0, hordeScore = enemyScore, allianceBases = 1, hordeBases = 4 }
    local top = E.Ladder(cornered, "ALLIANCE")[1]
    CHECK(top.bases == 5 and top.win, "D: a five-cap wins even from " .. enemyScore .. " down")
end

-- The only board no hold can save is one already at the cap, and there the
-- addon must say so rather than promise a five-cap it cannot cash
local over = { allianceScore = 100, hordeScore = AB.maxScore, allianceBases = 1, hordeBases = 4 }
CHECK(E.MinimumHold(over, "ALLIANCE") == nil, "D: nothing saves a game already at 2000",
    E.MinimumHold(over, "ALLIANCE"))

-- ---------------------------------------------------------------------------
-- E: deadlines
-- ---------------------------------------------------------------------------
-- Level scores, we sit on 2 to their 3, and we want a third.
-- K = R3*r3 - R2*r2, C = R3*(2000-1000) - R2*(2000-1000); d* = 360s exactly.
local behindSnapshot = { allianceScore = 1000, hordeScore = 1000, allianceBases = 2, hordeBases = 3 }
local deadline = E.Deadline(behindSnapshot, "ALLIANCE", 3)
CHECK(deadline.winsNow, "E: taking a third right now would win it")
CHECK(NEAR(deadline.seconds, 360, 0.01), "E: and we have exactly six minutes to do it", deadline.seconds)
CHECK(not deadline.boundedByCap, "E: the algebra binds here, not the enemy's clock")

-- The boundary is a real boundary: one second either side flips the outcome
local function OutcomeAfterDelay(delay, target)
    local rA, rH = E.Rate(2), E.Rate(3)
    return E.Outcome({
        allianceScore = 1000 + rA * delay,
        hordeScore = 1000 + rH * delay,
        allianceBases = target,
        hordeBases = 5 - target,
    }, "ALLIANCE")
end
CHECK(OutcomeAfterDelay(359, 3).win, "E: acting a second early wins")
CHECK(not OutcomeAfterDelay(361, 3).win, "E: acting a second late does not")

-- A hold that does not win has no deadline to report
CHECK(E.Deadline(behindSnapshot, "ALLIANCE", 2).winsNow == false, "E: two bases never wins, so no clock")
-- Out-earning them already means there is nothing to race
local ahead = { allianceScore = 1000, hordeScore = 1000, allianceBases = 4, hordeBases = 1 }
CHECK(E.Deadline(ahead, "ALLIANCE", 4).seconds == INF, "E: while ahead on income there is no deadline")
-- Denying the enemy every base means we win whenever we like
CHECK(E.Deadline(ahead, "ALLIANCE", 5).seconds == INF, "E: a five-cap has no deadline either")
-- A deadline the game outlives is flagged rather than shouted
local slow = E.Deadline({ allianceScore = 1900, hordeScore = 200, allianceBases = 4, hordeBases = 1 }, "ALLIANCE", 3)
CHECK(slow.winsNow and slow.seconds == INF, "E: while comfortably ahead there is nothing to outrun",
    slow.seconds)

-- The five-cap clamp. They sit on 1850 with four bases and will finish in 45s.
-- A five-cap freezes their income, so the ALGEBRA says there is no deadline —
-- and that is wrong, because they get there first. The enemy's own clock has
-- to bind.
local desperateFive = { allianceScore = 300, hordeScore = 1850, allianceBases = 1, hordeBases = 4 }
local fiveCap = E.Deadline(desperateFive, "ALLIANCE", 5)
CHECK(fiveCap.winsNow, "E: a five-cap does still win it")
CHECK(fiveCap.boundedByCap, "E: and the clock on it is theirs, not the algebra")
CHECK(NEAR(fiveCap.seconds, (2000 - 1850) / E.Rate(4), 0.01),
    "E: exactly as long as they need to finish", fiveCap.seconds)
-- One second inside the clamp still wins; one second past it does not
local function FiveCapAfter(delay)
    return E.Outcome({
        allianceScore = 300 + E.Rate(1) * delay,
        hordeScore = math.min(AB.maxScore, 1850 + E.Rate(4) * delay),
        allianceBases = 5, hordeBases = 0,
    }, "ALLIANCE")
end
CHECK(FiveCapAfter(fiveCap.seconds - 1).win, "E: capping a second early takes it")
CHECK(not FiveCapAfter(fiveCap.seconds + 1).win, "E: a second late and they are already home")

-- ---------------------------------------------------------------------------
-- F: reading the board
-- ---------------------------------------------------------------------------
local board = {
    { state = "OWNED", owner = "ALLIANCE" },
    { state = "OWNED", owner = "ALLIANCE" },
    { state = "CONTESTED", assaulter = "HORDE" },
    { state = "OWNED", owner = "HORDE" },
    { state = "NEUTRAL" },
}
local counts = E.CountBases(board)
CHECK(counts.ALLIANCE == 2 and counts.HORDE == 1, "F: a contested node pays nobody",
    counts.ALLIANCE .. "/" .. counts.HORDE)
CHECK(counts.CONTESTED == 1 and counts.NEUTRAL == 1, "F: and is counted apart from a neutral one")

local resolved = E.CountBases(E.ResolveContested(board))
CHECK(resolved.HORDE == 2 and resolved.ALLIANCE == 2, "F: resolving the flags hands it to the assaulter",
    resolved.ALLIANCE .. "/" .. resolved.HORDE)
CHECK(resolved.CONTESTED == 0, "F: and leaves nothing ticking")

-- ---------------------------------------------------------------------------
-- G: formatting
-- ---------------------------------------------------------------------------
CHECK(E.FormatClock(0) == "0:00", "G: zero clock", E.FormatClock(0))
CHECK(E.FormatClock(65) == "1:05", "G: a minute and five", E.FormatClock(65))
CHECK(E.FormatClock(600) == "10:00", "G: ten minutes", E.FormatClock(600))
CHECK(E.FormatClock(INF) == "never", "G: infinity has a word, not a number", E.FormatClock(INF))
CHECK(E.FormatClock(nil) == "--:--", "G: and nothing has a placeholder")
CHECK(E.FormatMargin(333.33) == "333", "G: margins are whole resources", E.FormatMargin(333.33))

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
