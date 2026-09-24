-- Commander Oracle: the roster.
--
-- Pure arithmetic over the rows the client's scoreboard hands us -- no WoW
-- API, no frames, no globals beyond the one it exports -- so the headless
-- harness can hold the scoring to account without a battleground, exactly as
-- it does the projection engine.
--
-- The problem this file exists to solve: a battleground scoreboard is a table
-- of raw totals, and raw totals lie in four different ways at once. Damage is
-- padded by anyone willing to AoE a flag pile. A healer's damage column says
-- nothing about whether they are the reason you cannot kill anything. Killing
-- blows pay whoever landed the last hit rather than whoever won the fight.
-- And the one column that actually decides the match -- the objective column
-- -- is the smallest number on the row.
--
-- Impact reads all of them at once. Two rules keep it honest:
--
--   1. Every part is a SHARE of what the best players in THIS match are doing,
--      never an absolute. A number you would have to calibrate against a
--      different battleground, bracket or patch is a number nobody can read.
--   2. A metric nobody in the match has scored on DROPS OUT and its weight is
--      redistributed. Early in a match, on a client that does not report a
--      column, or in a battleground with no objective stats, the score stays
--      the same shape instead of quietly reading low for everyone.

CommanderOracle_Roster = {}

local R = CommanderOracle_Roster

-- The four numbers, and why they are weighted the way they are.
--
-- This is a StarCraft scoreboard, not a raid meter. What that game taught
-- everybody to read is not "who did the most damage" but "who TRADED best":
-- resources destroyed against resources lost. A player pumping out 250k while
-- feeding eight deaths is running a losing economy, and the old model scored
-- him beside somebody who did the same damage and died twice.
--
-- So Trade is a first-class component rather than a modifier, and deaths live
-- inside it: your own currency, per life spent. Nothing else in a battleground
-- separates a carry from a body as cleanly.
--
-- Objectives are DELIBERATELY the smallest weight, and this is the one number
-- here that is a judgement call rather than arithmetic. Base and flag counts
-- are 0-to-5 integers: with only five distinct values and a trimmed top of
-- about three, one lucky cap scores the same as an entire match of damage, and
-- at a heavy weight that noise ran the whole board -- three base defends were
-- out-scoring twelve killing blows. Objectives still decide the MATCH (that is
-- what the BATTLE tab is for, and it prices them properly); they are just a
-- terrible instrument for measuring a PLAYER.
R.WEIGHTS = { output = 0.35, trade = 0.30, kills = 0.20, objectives = 0.15 }

-- Denominators are the mean of the top three rather than the single best, so
-- one outlier (the geared warrior farming a graveyard) cannot flatten
-- everybody else's score to a rounding error.
R.TRIM = 3

R.FACTIONS = { "ALLIANCE", "HORDE" }

R.FACTION_NAMES = { ALLIANCE = "Alliance", HORDE = "Horde" }

-- The three metrics every battleground reports. Objective columns are not
-- here: the client names its own, and they differ per map (bases in Arathi,
-- flags in Warsong, five separate ones in Alterac), so they are appended from
-- whatever the scoreboard says it has.
R.GROUPS = {
    { key = "kills",   label = "Killing blows", field = "killingBlows", format = "count" },
    { key = "damage",  label = "Damage",        field = "damage",       format = "short" },
    { key = "healing", label = "Healing",       field = "healing",      format = "short" },
}

-- A rate, the way a post-game screen reads one. nil when the match will not
-- say how long it has been running -- a per-minute figure over an unknown
-- minute is not a statistic.
function R.Rate(value, seconds, suffix)
    if not seconds or seconds <= 0 then return nil end
    local perMinute = (tonumber(value) or 0) * 60 / seconds
    suffix = suffix or "/min"
    if perMinute > 0 and perMinute < 10 then
        return string.format("%.1f%s", perMinute, suffix)
    end
    return R.Short(perMinute) .. suffix
end

-- ---------------------------------------------------------------------------
-- Formatting (here rather than in the UI so the harness can hold it too)
-- ---------------------------------------------------------------------------

function R.Short(value)
    value = tonumber(value) or 0
    if value >= 1000000 then
        return string.format("%.1fm", value / 1000000)
    end
    if value >= 10000 then
        return string.format("%dk", math.floor(value / 1000 + 0.5))
    end
    if value >= 1000 then
        return string.format("%.1fk", value / 1000)
    end
    return string.format("%d", math.floor(value + 0.5))
end

function R.Count(value)
    return string.format("%d", math.floor(tonumber(value) or 0))
end

function R.Format(value, format)
    if format == "short" then return R.Short(value) end
    return R.Count(value)
end

-- ---------------------------------------------------------------------------
-- Marking a team by class colour
--
-- Eight raid icons, nine classes: this is a matching problem, not a lookup.
-- What it has to answer is "which icon most LOOKS like this player", for the
-- people actually on the team.
--
-- Hue leads and saturation only breaks ties, and that is the whole trick.
-- Matching on plain RGB distance puts the mage on the green triangle -- a pale
-- cyan and a pale green are numerically close and perceptually nothing alike
-- -- and it hands the skull to whoever happens to be palest. Two rules fix it:
-- hue decides among colours, and a colour is never matched to a NON-colour, so
-- the priest's white takes the skull and nobody else may go near it.
--
-- The icon colours are the art's own hues; the class colours are TBC's.
-- ---------------------------------------------------------------------------

R.MARK_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }

R.MARK_COLORS = {
    { 1.00, 0.92, 0.00 },   -- 1 Star      yellow
    { 0.98, 0.57, 0.00 },   -- 2 Circle    orange
    { 0.83, 0.22, 0.90 },   -- 3 Diamond   purple
    { 0.04, 0.95, 0.00 },   -- 4 Triangle  green
    { 0.70, 0.82, 0.88 },   -- 5 Moon      pale blue
    { 0.00, 0.71, 1.00 },   -- 6 Square    blue
    { 1.00, 0.24, 0.17 },   -- 7 Cross     red
    { 0.94, 0.93, 0.87 },   -- 8 Skull     bone
}

R.CLASS_COLORS = {
    WARRIOR = { 0.78, 0.61, 0.43 },
    PALADIN = { 0.96, 0.55, 0.73 },
    HUNTER  = { 0.67, 0.83, 0.45 },
    ROGUE   = { 1.00, 0.96, 0.41 },
    PRIEST  = { 1.00, 1.00, 1.00 },
    SHAMAN  = { 0.00, 0.44, 0.87 },
    MAGE    = { 0.41, 0.80, 0.94 },
    WARLOCK = { 0.58, 0.51, 0.79 },
    DRUID   = { 1.00, 0.49, 0.04 },
}

-- Below this, a colour has no hue worth speaking of
local GREY = 0.12

local function ToHSV(color)
    local red, green, blue = color[1] or 0, color[2] or 0, color[3] or 0
    local high = math.max(red, green, blue)
    local low = math.min(red, green, blue)
    local delta = high - low
    local hue = 0
    if delta > 0 then
        if high == red then
            hue = 60 * (((green - blue) / delta) % 6)
        elseif high == green then
            hue = 60 * (((blue - red) / delta) + 2)
        else
            hue = 60 * (((red - green) / delta) + 4)
        end
    end
    return hue % 360, (high > 0 and delta / high or 0), high
end

function R.MarkDistance(a, b)
    local hueA, satA, valueA = ToHSV(a)
    local hueB, satB, valueB = ToHSV(b)
    local greyA, greyB = satA < GREY, satB < GREY
    -- A colour is not a non-colour, at any distance
    if greyA ~= greyB then return 1 + math.abs(valueA - valueB) end
    if greyA then
        return math.abs(valueA - valueB) * 0.5 + math.abs(satA - satB) * 0.5
    end
    local hue = math.abs(hueA - hueB)
    if hue > 180 then hue = 360 - hue end
    -- Saturation is a tiebreak, not an argument. At 0.35 it was strong enough
    -- to out-vote a 39-degree hue gap and put the warlock's purple on the pale
    -- blue moon instead of the purple diamond, which is the exact mistake the
    -- hue rule exists to prevent.
    return hue / 180 + math.abs(satA - satB) * 0.25 + math.abs(valueA - valueB) * 0.15
end

-- classes: an array of class tokens (nil entries allowed -- an unseen player
-- has no class yet). Returns index -> raid marker for the players it could
-- place, best match first and every icon used at most once.
--
-- Matched over the team that is ACTUALLY here rather than through a fixed
-- nine-class table: with only five seats there is always an icon left, so a
-- warrior is never turned away for having no brown marker, and a team with two
-- mages still gets two different icons.
function R.AssignMarks(classes)
    local candidates = {}
    for slot, token in ipairs(classes or {}) do
        local color = token and R.CLASS_COLORS[token]
        if color then
            for index, mark in ipairs(R.MARK_COLORS) do
                candidates[#candidates + 1] = {
                    distance = R.MarkDistance(color, mark), slot = slot, index = index,
                }
            end
        end
    end
    -- Ties broken by slot then icon, so the same team always comes out the
    -- same way: an assignment that wobbled would re-mark the raid for nothing
    table.sort(candidates, function(a, b)
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.slot ~= b.slot then return a.slot < b.slot end
        return a.index < b.index
    end)

    local out, takenSlot, takenMark = {}, {}, {}
    for _, candidate in ipairs(candidates) do
        if not takenSlot[candidate.slot] and not takenMark[candidate.index] then
            takenSlot[candidate.slot] = true
            takenMark[candidate.index] = true
            out[candidate.slot] = candidate.index
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Range
--
-- What the client will and will not say about where somebody is, and the
-- shapes that answer comes in. This is the honest part: in a battleground the
-- game gives you real coordinates for the people in your raid and NOTHING for
-- the enemy team -- no position, no distance, not even a "far away". All you
-- get for an enemy is whatever unit token you happen to be holding (your
-- target, your focus, whatever the mouse is over, whatever has a nameplate up)
-- and the coarse interaction bands that work on it.
--
-- So a range is one of four things and says which it is:
--   { yards = 23.4 }  measured -- the client gave us both positions
--   { within = 28 }   a bound  -- an interaction check said no further
--   { seen = true }   we hold a unit for them and nothing more
--   nil               the client will not say
-- ---------------------------------------------------------------------------

function R.Distance(x1, y1, x2, y2)
    local dx, dy = (x1 or 0) - (x2 or 0), (y1 or 0) - (y2 or 0)
    return math.sqrt(dx * dx + dy * dy)
end

function R.RangeText(range)
    if not range then return "" end
    if range.yards then
        -- Past a few hundred yards the number stops being information: no
        -- battleground is that big and the reading is a bug, not a distance
        if range.yards >= 1000 then return "" end
        return string.format("%dy", math.floor(range.yards + 0.5))
    end
    -- The "<" is not decoration. An interaction band is an upper bound and
    -- writing it as a plain number would be claiming a measurement we do not
    -- have.
    if range.within then return string.format("<%dy", math.floor(range.within)) end
    if range.seen then return "seen" end
    return ""
end

-- Close enough to be hitting you, close enough to matter, or neither
function R.RangeColor(range)
    if not range then return 0.42, 0.42, 0.42 end
    local yards = range.yards or range.within
    if not yards then return 0.72, 0.72, 0.72 end
    if yards <= 10 then return 1.00, 0.45, 0.40 end
    if yards <= 30 then return 1.00, 0.85, 0.40 end
    return 0.62, 0.72, 0.85
end

-- Whole percent, and never a bare "0%" for something that is actually there
local function Percent(part, whole)
    if not whole or whole <= 0 then return 0 end
    return math.floor((part / whole) * 100 + 0.5)
end

-- ---------------------------------------------------------------------------
-- Denominators
-- ---------------------------------------------------------------------------

local function TopMean(values, trim)
    table.sort(values, function(a, b) return a > b end)
    local count = math.min(trim or R.TRIM, #values)
    if count <= 0 then return 0 end
    local sum = 0
    for i = 1, count do sum = sum + values[i] end
    return sum / count
end

-- A share of the top-three mean, clamped: being better than the trimmed top is
-- worth the same as matching it, which is the point of trimming.
local function Share(value, denominator)
    if not denominator or denominator <= 0 then return nil end
    local share = (tonumber(value) or 0) / denominator
    if share < 0 then return 0 end
    if share > 1 then return 1 end
    return share
end

local function Number(value)
    local number = tonumber(value)
    if not number or number ~= number then return 0 end
    if number < 0 then return 0 end
    return number
end

-- ---------------------------------------------------------------------------
-- The ranking
-- ---------------------------------------------------------------------------

-- players: { { name, faction, classToken, class, killingBlows, honorableKills,
--             deaths, damage, healing, honor, objectives = { <value per column> } } }
-- opts:    { myFaction, topCount, columns = { <label per objective column> },
--            runTime = seconds }
function R.Rank(players, opts)
    players = players or {}
    opts = opts or {}
    local topCount = math.max(1, math.floor(tonumber(opts.topCount) or 3))
    local columns = opts.columns or {}

    local report = {
        ready = false,
        reason = "Waiting for the scoreboard.",
        players = {},
        -- Anything holding on to a player across refreshes holds the NAME and
        -- looks it up here: a ranking is rebuilt from scratch every time, so a
        -- kept reference to an entry is a number that quietly stops moving.
        byName = {},
        factions = {},
        best = {},
        columns = columns,
        weights = {},
        runTime = tonumber(opts.runTime) or 0,
    }

    for _, faction in ipairs(R.FACTIONS) do
        report.factions[faction] = {
            faction = faction,
            name = R.FACTION_NAMES[faction],
            players = {},
            groups = {},
            totals = { kills = 0, deaths = 0, damage = 0, healing = 0, objectives = 0,
                players = 0, trade = 0 },
        }
    end

    -- Pass one: normalise every row and collect the value lists the
    -- denominators come from. Rows without a name are the empty scoreboard
    -- slots the client pads with and are dropped here.
    local kills, damage, healing, objectives, deaths = {}, {}, {}, {}, {}
    for _, row in ipairs(players) do
        local faction = row.faction
        if row.name and report.factions[faction] then
            local objectiveTotal = 0
            local perColumn = {}
            for index in ipairs(columns) do
                local value = Number(row.objectives and row.objectives[index])
                perColumn[index] = value
                objectiveTotal = objectiveTotal + value
            end

            local entry = {
                name = row.name,
                -- The scoreboard's own spelling, realm and all. The display
                -- name is the short one; this is the one a /targetexact and a
                -- unit-token lookup have to match.
                fullName = row.fullName or row.name,
                faction = faction,
                class = row.class,
                classToken = row.classToken,
                killingBlows = Number(row.killingBlows),
                honorableKills = Number(row.honorableKills),
                deaths = Number(row.deaths),
                damage = Number(row.damage),
                healing = Number(row.healing),
                honor = Number(row.honor),
                objectives = perColumn,
                objectiveTotal = objectiveTotal,
            }
            entry.role = entry.healing > entry.damage and "HEALER" or "DAMAGE"

            report.players[#report.players + 1] = entry
            report.byName[entry.name] = entry
            local group = report.factions[faction]
            group.players[#group.players + 1] = entry
            group.totals.players = group.totals.players + 1
            group.totals.kills = group.totals.kills + entry.killingBlows
            group.totals.deaths = group.totals.deaths + entry.deaths
            group.totals.damage = group.totals.damage + entry.damage
            group.totals.healing = group.totals.healing + entry.healing
            group.totals.objectives = group.totals.objectives + entry.objectiveTotal

            kills[#kills + 1] = entry.killingBlows
            damage[#damage + 1] = entry.damage
            healing[#healing + 1] = entry.healing
            objectives[#objectives + 1] = entry.objectiveTotal
            deaths[#deaths + 1] = entry.deaths
        end
    end

    if #report.players == 0 then
        return report
    end

    -- The trade: your own currency against the lives you spent buying it.
    -- deaths + 1 rather than deaths, because a player who never died did not
    -- trade infinitely well -- they spent one life and still have it.
    local perLife = {}
    for _, entry in ipairs(report.players) do
        entry.currency = math.max(entry.damage, entry.healing)
        entry.lives = entry.deaths + 1
        entry.perLife = entry.currency / entry.lives
        perLife[#perLife + 1] = entry.perLife
    end

    local denominators = {
        kills = TopMean(kills),
        damage = TopMean(damage),
        healing = TopMean(healing),
        objectives = TopMean(objectives),
        deaths = TopMean(deaths),
        perLife = TopMean(perLife),
    }
    report.denominators = denominators

    -- Which components this match can actually speak to. Output survives if
    -- EITHER currency is being reported, so a client that never fills the
    -- healing column still scores damage properly, and the trade goes with it
    -- -- there is nothing to divide by lives when nothing is being reported.
    local live = {
        objectives = denominators.objectives > 0,
        kills = denominators.kills > 0,
        output = denominators.damage > 0 or denominators.healing > 0,
        trade = denominators.perLife > 0,
    }

    local weightTotal = 0
    for key, weight in pairs(R.WEIGHTS) do
        if live[key] then weightTotal = weightTotal + weight end
    end
    if weightTotal <= 0 then
        report.reason = "The scoreboard is still empty."
        return report
    end
    for key, weight in pairs(R.WEIGHTS) do
        report.weights[key] = live[key] and (weight / weightTotal) or 0
    end

    -- Pass two: score. Each part is kept on the entry, because a score whose
    -- parts are invisible is exactly the trap the ladder header warns about.
    for _, entry in ipairs(report.players) do
        local damageShare = Share(entry.damage, denominators.damage) or 0
        local healingShare = Share(entry.healing, denominators.healing) or 0
        -- A player is judged on their own currency: a healer with no damage is
        -- not a bad player, and taking the better of the two says so without
        -- having to guess anyone's spec.
        local outputShare, outputKey = damageShare, "damage"
        if healingShare > damageShare then
            outputShare, outputKey = healingShare, "healing"
        end

        entry.shares = {
            objectives = Share(entry.objectiveTotal, denominators.objectives) or 0,
            kills = Share(entry.killingBlows, denominators.kills) or 0,
            output = outputShare,
            trade = Share(entry.perLife, denominators.perLife) or 0,
            damage = damageShare,
            healing = healingShare,
        }
        entry.outputKey = outputKey

        -- Rates, for the read-out. Within one match every player shares the
        -- same clock, so a rate cannot change the RANKING -- it is here
        -- because a per-minute figure is what a post-game screen should say.
        entry.rates = {
            output = R.Rate(entry.currency, report.runTime),
            kills = R.Rate(entry.killingBlows, report.runTime),
        }

        local parts, base = {}, 0
        for key, weight in pairs(report.weights) do
            local contribution = entry.shares[key] * weight
            parts[key] = contribution
            base = base + contribution
        end
        entry.parts = parts
        -- Deaths are not a modifier any more: they are priced inside Trade,
        -- which is the only place they belong. A player who did nothing still
        -- scores nothing, however long they lived.
        entry.impact = math.floor(100 * base + 0.5)

        -- What they are on the board FOR: the part carrying the most of their
        -- own score, named the way it would be said out loud.
        local bestKey, bestValue = nil, 0
        for key, contribution in pairs(parts) do
            if contribution > bestValue then bestKey, bestValue = key, contribution end
        end
        if bestKey == "output" then bestKey = outputKey end
        if bestKey == "trade" then bestKey = "trade" end
        if bestKey == "objectives" then
            -- "Bases Assaulted" is the client's label; the noun is the only
            -- part that fits a board cell, and it is the part that means
            -- something ("bases", "flags", "graveyards")
            bestKey = (columns[1] and columns[1]:lower():match("^(%a+)")) or "objectives"
        end
        entry.reason = bestValue > 0 and bestKey or "present"
    end

    -- Pass three: the orders. Impact first, and a stable tiebreak so two equal
    -- scores do not swap places every refresh and make the board flicker.
    local function ByImpact(a, b)
        if a.impact ~= b.impact then return a.impact > b.impact end
        if a.objectiveTotal ~= b.objectiveTotal then return a.objectiveTotal > b.objectiveTotal end
        return a.name < b.name
    end

    table.sort(report.players, ByImpact)
    for _, faction in ipairs(R.FACTIONS) do
        local group = report.factions[faction]
        -- The army-level trade: what this side destroyed against what it lost.
        -- In a battleground one side's killing blows are very nearly the other
        -- side's deaths, so this is a real read on who is winning the fights
        -- rather than a derived guess.
        group.totals.trade = group.totals.kills / math.max(group.totals.deaths, 1)
        table.sort(group.players, ByImpact)
        report.best[faction] = group.players[1]

        -- The per-metric leaderboards: the three every battleground reports,
        -- then one per objective column the client says this map has.
        local specs = {}
        for _, spec in ipairs(R.GROUPS) do specs[#specs + 1] = spec end
        for index, label in ipairs(columns) do
            specs[#specs + 1] = { key = "objective" .. index, label = label,
                column = index, format = "count" }
        end

        for _, spec in ipairs(specs) do
            local rows = {}
            for _, entry in ipairs(group.players) do
                local value = spec.column and entry.objectives[spec.column]
                    or entry[spec.field]
                if value and value > 0 then
                    rows[#rows + 1] = { player = entry, value = value }
                end
            end
            table.sort(rows, function(a, b)
                if a.value ~= b.value then return a.value > b.value end
                return a.player.name < b.player.name
            end)
            while #rows > topCount do table.remove(rows) end
            group.groups[#group.groups + 1] = {
                key = spec.key, label = spec.label, format = spec.format, rows = rows,
                -- Carried through so a board can re-read a player's value for
                -- this metric later, without being handed the row again
                field = spec.field, column = spec.column,
            }
        end
    end

    report.ready = true
    report.reason = nil
    report.summary, report.summaryKind = R.Summarise(report, opts.myFaction)
    return report
end

-- ---------------------------------------------------------------------------
-- The read
--
-- One line, and it has to earn its place: "Alliance is ahead on damage" is not
-- worth a line of a HUD. These are ordered by what a player could actually act
-- on in the next thirty seconds -- a healer to focus, a killer to avoid, a
-- flag carrier to chase -- and the first one that is TRUE by a wide enough
-- margin wins. When none of them is, it says the honest structural thing
-- instead of inventing a call.
-- ---------------------------------------------------------------------------

-- The leader AND the runner-up, because "leads" and "stands out" are
-- different claims and only the second one is worth a line of a HUD.
local function Leader(group, field)
    local best, bestValue, runnerUp = nil, 0, 0
    for _, entry in ipairs(group.players) do
        local value = field == "objectiveTotal" and entry.objectiveTotal or entry[field]
        value = value or 0
        if value > bestValue then
            best, bestValue, runnerUp = entry, value, bestValue
        elseif value > runnerUp then
            runnerUp = value
        end
    end
    return best, bestValue, runnerUp
end

-- Half again as much as the next player. Without this, a scoreboard where
-- three people have 9, 9 and 9 killing blows out of 27 reports one of them as
-- the killer to focus, which is both true (33%!) and useless.
local DOMINANCE = 1.5

local function Dominant(value, runnerUp)
    if runnerUp <= 0 then return value > 0 end
    return value >= runnerUp * DOMINANCE
end

function R.Summarise(report, myFaction)
    local enemyFaction = myFaction == "ALLIANCE" and "HORDE"
        or (myFaction == "HORDE" and "ALLIANCE" or nil)
    local enemy = enemyFaction and report.factions[enemyFaction]

    -- Early on, everything below is noise dressed up as intelligence
    if (report.runTime or 0) > 0 and report.runTime < 90 then
        return "Too early to rank anybody -- the numbers are still noise.", "EARLY"
    end

    if enemy and enemy.totals.players > 0 then
        local name = enemy.name

        -- A healer doing most of a side's healing is the single most
        -- actionable fact on a battleground scoreboard
        local healer, healed, nextHealed = Leader(enemy, "healing")
        if healer and enemy.totals.healing > 0 then
            local share = Percent(healed, enemy.totals.healing)
            if share >= 35 and healed > 0 and Dominant(healed, nextHealed) then
                return string.format("Focus %s: %d%% of %s healing.", healer.name, share, name), "HEALER"
            end
        end

        local killer, kills, nextKills = Leader(enemy, "killingBlows")
        if killer and enemy.totals.kills > 0 then
            local share = Percent(kills, enemy.totals.kills)
            if share >= 30 and kills >= 3 and Dominant(kills, nextKills) then
                return string.format("%s has %d of %s %d killing blows.",
                    killer.name, math.floor(kills), name, math.floor(enemy.totals.kills)), "KILLER"
            end
        end

        local capper, caps, nextCaps = Leader(enemy, "objectiveTotal")
        if capper and enemy.totals.objectives > 0 then
            local share = Percent(caps, enemy.totals.objectives)
            if share >= 40 and caps >= 2 and Dominant(caps, nextCaps) then
                return string.format("%s is running %s objectives: %d of %d.",
                    capper.name, name, math.floor(caps), math.floor(enemy.totals.objectives)), "OBJECTIVE"
            end
        end
    end

    -- Nobody in particular stands out. The next most useful thing is the same
    -- one a post-game screen leads with: resources destroyed against resources
    -- lost, at the army level. It is the read that says stop taking the
    -- fights -- or start.
    local alliance, horde = report.factions.ALLIANCE, report.factions.HORDE
    local mine = myFaction and report.factions[myFaction]
    if mine and enemy and (mine.totals.deaths + enemy.totals.deaths) >= 12 then
        local ours, theirs = mine.totals.trade, enemy.totals.trade
        -- Both sides have to AGREE. One side's killing blows are the other
        -- side's deaths, so a real advantage shows up twice -- ours high and
        -- theirs low. Reading one side's ratio alone would call a match where
        -- everybody is killing everybody a win for whoever we happened to ask.
        local EDGE = 1.3
        if ours >= EDGE and theirs <= 1 / EDGE then
            return string.format("You are trading %.1f to 1 -- take the fights.", ours), "TRADE"
        end
        if theirs >= EDGE and ours > 0 and ours <= 1 / EDGE then
            return string.format("%s is trading %.1f to 1 -- stop taking the fights.",
                enemy.name, theirs), "TRADE"
        end
    end

    if alliance.totals.players > 0 and horde.totals.players > 0 then
        local function TopShare(group)
            local top, all = 0, 0
            for index, entry in ipairs(group.players) do
                if index <= 3 then top = top + entry.impact end
                all = all + entry.impact
            end
            return Percent(top, all)
        end
        local allianceTop, hordeTop = TopShare(alliance), TopShare(horde)
        local heavy = allianceTop >= hordeTop and alliance or horde
        local heavyShare = math.max(allianceTop, hordeTop)
        if heavyShare >= 45 then
            return string.format("%s rides on three players: %d%% of its impact.",
                heavy.name, heavyShare), "TOPHEAVY"
        end
        local best = report.best.ALLIANCE
        if report.best.HORDE and (not best or report.best.HORDE.impact > best.impact) then
            best = report.best.HORDE
        end
        if best then
            return string.format("%s is the best player here: %d impact on %s.",
                best.name, best.impact, best.reason), "BEST"
        end
    end

    return "No side has separated itself yet.", "EVEN"
end
