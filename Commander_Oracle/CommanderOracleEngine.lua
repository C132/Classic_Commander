-- Commander Oracle: the projection engine.
--
-- Pure arithmetic over a board snapshot — no WoW API, no frames, no globals
-- beyond the canon it reads. Everything the HUD says is decided here, so the
-- headless harness can hold the whole prediction to account without mocking a
-- client.
--
-- The one idea underneath all of it: Arathi Basin is a race to 2000 where
-- your speed is a step function of how many bases you hold. So "are we
-- winning" is never about the scoreboard alone — a side that is 400 behind on
-- four bases is not behind at all. Every function here answers a question the
-- scoreboard cannot.

CommanderOracle_Engine = {}

local E = CommanderOracle_Engine
local AB = CommanderOracle_AB
local Opposite = CommanderOracle_Opposite

local INF = math.huge
local MAX_BASES = 5

-- ---------------------------------------------------------------------------
-- Rates
-- ---------------------------------------------------------------------------

local function ClampBases(bases)
    bases = math.floor(tonumber(bases) or 0)
    if bases < 0 then return 0 end
    if bases > MAX_BASES then return MAX_BASES end
    return bases
end

-- Resources per second at a given base count. The table is lumpy on purpose:
-- 1->2 bases buys a third more income, 4->5 buys nine times.
function E.Rate(bases)
    bases = ClampBases(bases)
    local interval = AB.tickInterval[bases]
    if not interval or interval <= 0 then return 0 end
    return AB.tickPoints[bases] / interval
end

-- Seconds for a side sitting on `bases` to reach the cap from `score`.
function E.TimeToCap(score, bases)
    local rate = E.Rate(bases)
    local remaining = AB.maxScore - (tonumber(score) or 0)
    if remaining <= 0 then return 0 end
    if rate <= 0 then return INF end
    return remaining / rate
end

-- Where a side sitting on `bases` stands after `seconds`, capped.
function E.ScoreAfter(score, bases, seconds)
    local projected = (tonumber(score) or 0) + E.Rate(bases) * (seconds or 0)
    if projected > AB.maxScore then return AB.maxScore end
    return projected
end

-- ---------------------------------------------------------------------------
-- The race
-- ---------------------------------------------------------------------------

-- snapshot: { allianceScore, hordeScore, allianceBases, hordeBases }
-- Run both sides forward at their CURRENT base counts and see who arrives.
-- Returns:
--   winner    "ALLIANCE" | "HORDE" | nil (dead heat, or nobody scoring)
--   seconds   until the winner caps (INF if nobody ever does)
--   margin    resources the loser is still short when it ends
--   allianceFinal / hordeFinal, allianceRate / hordeRate
function E.Race(snapshot)
    local aScore = tonumber(snapshot.allianceScore) or 0
    local hScore = tonumber(snapshot.hordeScore) or 0
    local aBases = ClampBases(snapshot.allianceBases)
    local hBases = ClampBases(snapshot.hordeBases)

    local aTime = E.TimeToCap(aScore, aBases)
    local hTime = E.TimeToCap(hScore, hBases)

    local result = {
        allianceRate = E.Rate(aBases),
        hordeRate = E.Rate(hBases),
        allianceTime = aTime,
        hordeTime = hTime,
    }

    if aTime == INF and hTime == INF then
        -- Nobody holds anything. Not a draw so much as a game that has not
        -- started; say so rather than inventing a winner.
        result.winner = nil
        result.seconds = INF
        result.allianceFinal = aScore
        result.hordeFinal = hScore
        result.margin = 0
        result.stalled = true
        return result
    end

    local seconds = math.min(aTime, hTime)
    result.seconds = seconds
    result.allianceFinal = E.ScoreAfter(aScore, aBases, seconds)
    result.hordeFinal = E.ScoreAfter(hScore, hBases, seconds)

    if aTime < hTime then
        result.winner = "ALLIANCE"
        result.margin = AB.maxScore - result.hordeFinal
    elseif hTime < aTime then
        result.winner = "HORDE"
        result.margin = AB.maxScore - result.allianceFinal
    else
        result.winner = nil          -- exact dead heat
        result.margin = 0
    end

    return result
end

-- The race told from one side's chair.
--   win      true if `faction` takes it
--   margin   resources between the two at the end (0 on a dead heat)
--   seconds  until it is decided
function E.Outcome(snapshot, faction)
    local race = E.Race(snapshot)
    return {
        win = race.winner == faction,
        loss = race.winner ~= nil and race.winner ~= faction,
        winner = race.winner,
        margin = race.margin,
        seconds = race.seconds,
        stalled = race.stalled,
        race = race,
    }
end

-- ---------------------------------------------------------------------------
-- The win-condition ladder
-- ---------------------------------------------------------------------------

-- The question a scoreboard never answers: from where we stand RIGHT NOW,
-- what does each possible hold buy us? One row per base count 0..5 (the enemy
-- takes the rest), each carrying the outcome if that split held to the end.
-- Returned high to low, the way it wants to be read.
--
-- This is the whole point of the addon. "We are 300 down" means nothing;
-- "three bases wins by 260, two loses by 310" is a call.
function E.Ladder(snapshot, faction)
    local enemy = Opposite(faction)
    if not enemy then return {} end

    local rows = {}
    for bases = MAX_BASES, 0, -1 do
        local trial = {
            allianceScore = snapshot.allianceScore,
            hordeScore = snapshot.hordeScore,
        }
        trial[faction == "ALLIANCE" and "allianceBases" or "hordeBases"] = bases
        trial[enemy == "ALLIANCE" and "allianceBases" or "hordeBases"] = MAX_BASES - bases

        local outcome = E.Outcome(trial, faction)
        rows[#rows + 1] = {
            bases = bases,
            win = outcome.win,
            loss = outcome.loss,
            stalled = outcome.stalled,
            margin = outcome.margin,
            seconds = outcome.seconds,
        }
    end
    return rows
end

-- The smallest hold that still wins, or nil when no hold does (the enemy is
-- close enough that even a five-cap arrives too late — the honest "this one
-- is gone" answer, and the only thing worth saying at that point).
function E.MinimumHold(snapshot, faction)
    local best
    for _, row in ipairs(E.Ladder(snapshot, faction)) do
        if row.win and (not best or row.bases < best) then best = row.bases end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Deadlines
-- ---------------------------------------------------------------------------

-- How long the CURRENT split can persist before reaching `target` bases stops
-- being enough to win. The clock everyone in a losing Arathi Basin wants and
-- nobody has: not "we need the Blacksmith" but "we need it within 47
-- seconds".
--
-- Both sides keep their present rate for `d` seconds, then the board becomes
-- target-vs-(5-target) forever. Win iff our remaining time beats theirs:
--
--   (M - A - rA·d)/RA  <  (M - H - rH·d)/RH
--
-- which is linear in d. Cross-multiplying (both rates positive) gives
--   d·(RA·rH - RH·rA)  <  RA·(M-H) - RH·(M-A)
-- so with K and C named for those two sides, K > 0 puts a ceiling on the
-- delay at exactly C/K, and K <= 0 means waiting never costs us the win.
--
-- One constraint sits on top of the algebra: while we are LOSING at the
-- present split, the enemy reaching 2000 ends the game whatever we were
-- planning, so the delay can never exceed that. It is the binding deadline for
-- a five-cap in particular — taking every base freezes their income, so the
-- algebra alone says "no deadline", when in fact you have exactly as long as
-- it takes them to finish.
--
-- Returns { winsNow, seconds, boundedByCap }:
--   winsNow       would `target` win if we reached it this instant
--   seconds       the deadline; INF when there is none, nil when winsNow is false
--   boundedByCap  the clock is the enemy reaching the cap, not the algebra
function E.Deadline(snapshot, faction, target)
    local enemy = Opposite(faction)
    if not enemy then return { winsNow = false } end

    target = ClampBases(target)
    local M = AB.maxScore
    local mine = faction == "ALLIANCE" and "alliance" or "horde"
    local theirs = enemy == "ALLIANCE" and "alliance" or "horde"

    local A = tonumber(snapshot[mine .. "Score"]) or 0
    local H = tonumber(snapshot[theirs .. "Score"]) or 0
    local rA = E.Rate(snapshot[mine .. "Bases"])
    local rH = E.Rate(snapshot[theirs .. "Bases"])
    local RA = E.Rate(target)
    local RH = E.Rate(MAX_BASES - target)

    -- Does it even win from a standing start?
    local immediate = {
        allianceScore = snapshot.allianceScore,
        hordeScore = snapshot.hordeScore,
    }
    immediate[mine .. "Bases"] = target
    immediate[theirs .. "Bases"] = MAX_BASES - target
    local winsNow = E.Outcome(immediate, faction).win
    if not winsNow then return { winsNow = false } end

    -- No income at the target: it cannot win, so winsNow already said no.
    if RA <= 0 then return { winsNow = false } end

    local algebraic
    if RH <= 0 then
        -- The target denies them every base, so nothing we do later loses it.
        algebraic = INF
    else
        local K = RA * rH - RH * rA
        local C = RA * (M - H) - RH * (M - A)
        if K > 0 then
            algebraic = math.max(0, C / K)
        else
            -- Waiting is neutral or actively in our favour (we already
            -- out-earn them at the target). Nothing to race.
            algebraic = INF
        end
    end

    -- While we are losing at the present split, their arrival at the cap is a
    -- hard ceiling on any delay. While we are winning it, there is nothing to
    -- outrun.
    local race = E.Race(snapshot)
    local losingNow = race.winner ~= nil and race.winner ~= faction
    local ceiling = losingNow and race.seconds or INF
    local seconds = math.min(algebraic, ceiling)

    return { winsNow = true, seconds = seconds, boundedByCap = ceiling < algebraic }
end

-- ---------------------------------------------------------------------------
-- The board
-- ---------------------------------------------------------------------------

-- board: array of per-node { state = "NEUTRAL"|"OWNED"|"CONTESTED",
--                            owner =, assaulter = }
-- Counts what each side actually banks income on. A contested node pays
-- NOBODY while its flag ticks — the commonest way a read of the map is wrong
-- is counting a node you just clicked as already yours.
function E.CountBases(board)
    local counts = { ALLIANCE = 0, HORDE = 0, NEUTRAL = 0, CONTESTED = 0 }
    for _, node in ipairs(board or {}) do
        if node.state == "OWNED" and node.owner then
            counts[node.owner] = counts[node.owner] + 1
        elseif node.state == "CONTESTED" then
            counts.CONTESTED = counts.CONTESTED + 1
        else
            counts.NEUTRAL = counts.NEUTRAL + 1
        end
    end
    return counts
end

-- The board as it will stand if every flag currently ticking lands with
-- whoever started it. This is the projection worth arguing with: it is where
-- the game is going if nobody intervenes, which is exactly the moment to
-- decide whether to intervene.
function E.ResolveContested(board)
    local resolved = {}
    for index, node in ipairs(board or {}) do
        if node.state == "CONTESTED" and node.assaulter then
            resolved[index] = { state = "OWNED", owner = node.assaulter, node = node.node, projected = true }
        else
            resolved[index] = node
        end
    end
    return resolved
end

-- ---------------------------------------------------------------------------
-- Formatting shared by the HUD and the harness
-- ---------------------------------------------------------------------------

function E.FormatClock(seconds)
    if not seconds or seconds ~= seconds then return "--:--" end
    if seconds == INF then return "never" end
    if seconds < 0 then seconds = 0 end
    local minutes = math.floor(seconds / 60)
    local rest = math.floor(seconds % 60)
    return string.format("%d:%02d", minutes, rest)
end

-- Resources are integers on the scoreboard; a projection that reads 260.4 is
-- claiming a precision it does not have.
function E.FormatMargin(margin)
    return string.format("%d", math.floor((margin or 0) + 0.5))
end
