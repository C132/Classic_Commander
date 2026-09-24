-- Commander Forecast — the estimator.
--
-- The number on an icon has to answer one question: if I press this now, at
-- the thing I am currently pointed at, how much comes out? TBC gives an addon
-- no API for that, so this file answers it twice and prefers the better answer.
--
--   MODEL     — the spell's own tooltip text (base damage or healing), plus
--               your gear's spell power through the TBC coefficient, plus your
--               crit chance and the level-based miss chance. Costs nothing and
--               works on a spell you have never cast. It is also blind to
--               every talent and every buff percentage, because nothing in the
--               client reports those, so it reads LOW for a talented spec.
--
--   MEASURED  — what that exact spell ID has actually landed for, taken off
--               your own combat log and averaged. It knows your talents, your
--               buffs, the target's armour and resistance and your own hit
--               rating, because it never had to reason about any of them. It
--               only needs you to have cast the spell a few times.
--
-- So the model is the cold open and the log corrects it. Everything in this
-- file is pure apart from the clearly marked runtime section at the bottom,
-- which is the only part that touches the client — that split is what lets the
-- Harness drive the parser and the arithmetic headlessly.

CommanderForecast = _G.CommanderForecast or {}

local M = {}
CommanderForecast.Model = M

local CAST_CAP = 3.5            -- TBC's direct-cast coefficient window
local DOT_CAP = 15              -- ...and its damage-over-time window
local GCD = 1.5                 -- an instant still costs a global
local SPELL_CRIT_MULT = 1.5     -- TBC spell crits are +50%, melee are +100%
local MELEE_CRIT_MULT = 2.0

M.CAST_CAP, M.DOT_CAP, M.GCD = CAST_CAP, DOT_CAP, GCD
M.SPELL_CRIT_MULT, M.MELEE_CRIT_MULT = SPELL_CRIT_MULT, MELEE_CRIT_MULT

-- Spell school indices as GetSpellBonusDamage/GetSpellCritChance take them.
M.SCHOOLS = {
    physical = 1, holy = 2, fire = 3, nature = 4, frost = 5, shadow = 6, arcane = 7,
}
M.SCHOOL_NAMES = {
    "Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane",
}

-- ---------------------------------------------------------------------------
-- Tooltip text -> a spell profile
-- ---------------------------------------------------------------------------

-- Lines of a spell tooltip that are never the description. Cast time, range,
-- cost and rank all carry digits, and a description pattern let loose on them
-- reads "30 yd range" as thirty of something. Naming them is cheaper and far
-- more predictable than guessing which line is the prose.
local META_LINE = {
    "^Rank %d",
    "yd range",
    "sec cast",
    -- Exact: Ice Barrier's description begins "Instantly shields you", and a
    -- prefix match here dropped the whole spell.
    "^Instant$",
    "^Instant cast$",
    "^Channeled$",
    "cooldown",
    "^Requires",
    "^Next melee",
    "Mana$", "Rage$", "Energy$", "Focus$",
    "of base mana",
    "^Reagents?:",
    "^Tools:",
    "^Melee Range",
}

function M.IsMetaLine(text)
    if not text or text == "" then return true end
    for _, pattern in ipairs(META_LINE) do
        if text:find(pattern) then return true end
    end
    return false
end

-- Big numbers arrive unseparated on this client, but a locale that ever adds
-- a separator would otherwise turn 1,236 into 1.
local function Normalize(text)
    return (text:gsub("(%d),(%d)", "%1%2"))
end

-- Join the prose lines of a scanned tooltip into the one string the patterns
-- below run against. Line 1 is the spell name and never describes anything.
function M.DescriptionFrom(lines)
    local kept = {}
    for i = 2, #lines do
        local text = lines[i]
        if text and text ~= "" and not M.IsMetaLine(text) then
            kept[#kept + 1] = text
        end
    end
    return Normalize(table.concat(kept, " "))
end

-- "84 Fire damage over 8 sec" / "1236 damage over 18 sec". The optional school
-- word is `%a*%s*`, which backtracks to empty for the schoolless form.
local DOT_PATTERNS = {
    "(%d+)%s+%a*%s*damage over (%d+)%s*sec",
}
-- Per-tick forms: "264 Arcane damage every 1 sec for 5 sec" (Arcane Missiles),
-- "Inflicts 80 Frost damage to an enemy every 3 sec., stunning it for 8 sec"
-- (Freeze). The total is amount x ticks; the interval is NOT the duration.
local TICK_PATTERNS = {
    "(%d+)%s+%a*%s*damage.-every (%d+)%s*sec%.?,? for (%d+)%s*sec",
    "(%d+)%s+%a*%s*damage.-every (%d+)%s*sec%.?,?.-for (%d+)%s*sec",
}
-- "Heals the target for 1010 over 15 sec", and the second-clause form Healing
-- Wave's talented version uses ("...and another 500 over 12 sec").
local HOT_PATTERNS = {
    "for (%d+) over (%d+)%s*sec",
    "(%d+)%s+health over (%d+)%s*sec",
    "(%d+) over (%d+)%s*sec",
}
local DIRECT_RANGE_PATTERNS = {
    "(%d+) to (%d+)%s+%a*%s*damage",
}
local DIRECT_FLAT_PATTERNS = {
    "(%d+)%s+%a*%s*damage",
}
local HEAL_RANGE_PATTERNS = {
    "for (%d+) to (%d+)",
    "(%d+) to (%d+)%s+health",
}
local HEAL_FLAT_PATTERNS = {
    "for (%d+)",
    "(%d+)%s+health",
}
local ABSORB_PATTERNS = {
    "absorb%a*%s+(%d+)",
    "absorb%a*%s+.-%s(%d+)%s+damage",
}
-- Weapon-based abilities have to be recognised BEFORE the plain damage
-- patterns: "98 damage in addition to your normal weapon damage" is a flat
-- bonus on top of a swing, not a 98-damage spell.
local WEAPON_PATTERNS = {
    { pattern = "(%d+)%%%s*of weapon damage plus (%d+)", mult = 1, flat = 2 },
    { pattern = "(%d+)%%%s*weapon damage plus (%d+)",    mult = 1, flat = 2 },
    { pattern = "weapon damage plus (%d+)",              flat = 1 },
    { pattern = "(%d+) damage in addition to your normal weapon", flat = 1 },
    { pattern = "(%d+)%%%s*of weapon damage",            mult = 1 },
    { pattern = "(%d+)%%%s*weapon damage",               mult = 1 },
    { pattern = "weapon damage" },
}

local function SchoolFrom(text)
    for name, index in pairs(M.SCHOOLS) do
        if index > 1 and text:lower():find(name .. " damage") then
            return index
        end
    end
    return nil
end

local function MatchFirst(text, patterns)
    for _, pattern in ipairs(patterns) do
        local a, b = text:match(pattern)
        if a then return tonumber(a), tonumber(b) end
    end
    return nil
end

-- Pull the over-time clause out and hand back the remaining text, so the
-- direct patterns cannot read the DoT's own number as a direct hit. Immolate
-- ("327 Fire damage and then an additional 485 Fire damage over 15 sec") is
-- the case that makes this necessary rather than tidy.
local function ExtractOverTime(text, patterns, tickPatterns)
    for _, pattern in ipairs(tickPatterns or {}) do
        local amount, interval, duration = text:match(pattern)
        if amount then
            amount, interval, duration = tonumber(amount), tonumber(interval), tonumber(duration)
            if interval and interval > 0 and duration then
                return { total = amount * math.floor(duration / interval + 0.5), duration = duration },
                    (text:gsub(pattern, " "))
            end
        end
    end
    for _, pattern in ipairs(patterns) do
        local total, duration = text:match(pattern)
        if total then
            return { total = tonumber(total), duration = tonumber(duration) },
                (text:gsub(pattern, " "))
        end
    end
    return nil, text
end

-- text -> profile, or nil when nothing quantifiable is in there. The order of
-- the three arms is the classification: an absorb is not a heal, and a spell
-- that names a damage number is a damage spell even when it also heals (Holy
-- Nova), because the icon's number is about what it does to your target.
function M.ParseDescription(text)
    if not text or text == "" then return nil end
    text = Normalize(text)

    -- Case matters to a Lua pattern and not to Blizzard: Frost Ward's text
    -- is "Absorbs 675 Frost damage", and matched case-sensitively it read as
    -- 675 Frost DAMAGE, collecting crit and a full coefficient it never had.
    local absorb = MatchFirst(text:lower(), ABSORB_PATTERNS)
    if absorb then
        return {
            kind = "absorb",
            school = SchoolFrom(text) or M.SCHOOLS.holy,
            direct = { min = absorb, max = absorb, avg = absorb },
            -- Absorbs keep a tenth of spell power in TBC (a third for Power
            -- Word: Shield — the runtime raises it by name). Never the cast
            -- window, which would triple a ward's size on a geared caster.
            coefOverride = 0.1,
        }
    end

    -- Weapon abilities first: their flat bonus is written in the same words a
    -- direct nuke uses.
    for _, spec in ipairs(WEAPON_PATTERNS) do
        local a, b = text:match(spec.pattern)
        if a then
            local captures = { tonumber(a), tonumber(b) }
            return {
                kind = "damage",
                school = M.SCHOOLS.physical,
                weapon = true,
                weaponMult = spec.mult and (captures[spec.mult] or 100) / 100 or 1,
                weaponFlat = spec.flat and captures[spec.flat] or 0,
            }
        end
    end

    local school = SchoolFrom(text)

    -- Conditional multipliers the target's state switches on: Ice Lance's
    -- "Causes triple damage against Frozen targets". Read here, applied at
    -- estimate time when the target actually is.
    local frozenMult
    local word = text:match("(%a+) damage against [Ff]rozen targets")
    if word then
        frozenMult = ({ double = 2, triple = 3, quadruple = 4 })[word:lower()]
    end

    local overTime, rest = ExtractOverTime(text, DOT_PATTERNS, TICK_PATTERNS)
    local min, max = MatchFirst(rest, DIRECT_RANGE_PATTERNS)
    if not min then
        min = MatchFirst(rest, DIRECT_FLAT_PATTERNS)
        max = min
    end
    if min or overTime then
        return {
            kind = "damage",
            school = school or M.SCHOOLS.physical,
            direct = min and { min = min, max = max or min, avg = (min + (max or min)) / 2 } or nil,
            overTime = overTime,
            frozenMult = frozenMult,
        }
    end

    -- Healing. Nothing above matched, so a "damage" the text mentions is
    -- something being reacted to (Prayer of Mending), not something dealt.
    --
    -- Two gates, both of which cost real false positives without them. The
    -- text has to actually claim to heal, or Sunder Armor's "for 30 sec" is
    -- read as a thirty point heal; and a spell that restores mana and not
    -- health is not output at all, or a mana potion advertises 4200 healing.
    local lower = text:lower()
    if not (lower:find("heal") or lower:find("restor") or lower:find("health")) then
        return nil
    end
    if lower:find("mana") and not (lower:find("heal") or lower:find("health")) then
        return nil
    end

    -- Durations are written in the same "for N" the flat heal pattern reads.
    text = text:gsub("[Ff]or %d+%s*sec", " "):gsub("[Ff]or %d+%s*min", " ")

    local hot
    hot, rest = ExtractOverTime(text, HOT_PATTERNS)
    local lo, hi = MatchFirst(rest, HEAL_RANGE_PATTERNS)
    if not lo then
        lo = MatchFirst(rest, HEAL_FLAT_PATTERNS)
        hi = lo
    end
    if lo or hot then
        return {
            kind = "heal",
            school = M.SCHOOLS.holy,
            direct = lo and { min = lo, max = hi or lo, avg = (lo + (hi or lo)) / 2 } or nil,
            overTime = hot,
        }
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Coefficients
-- ---------------------------------------------------------------------------

-- How much of your spell power the direct part and the over-time part each
-- keep, under TBC's rules:
--
--   direct   castTime / 3.5   (an instant is charged the global, 1.5 / 3.5)
--   overtime duration / 15
--
-- and for a spell that does both, the two windows are normalised against each
-- other (c^2 / sum) so Fireball does not collect a full direct coefficient AND
-- a full DoT coefficient on top of it.
--
-- A CHANNEL is the shape that fools this: its "damage over 3 sec" is its cast
-- time, not a DoT riding on top of a cast, so it normalises against the 3.5s
-- window like any other cast. It is recognised by its over-time duration being
-- its cast time, which is exactly what makes it a channel.
function M.Coefficients(profile, castSeconds)
    if not profile or profile.weapon then return 0, 0 end
    if profile.coefOverride then return profile.coefOverride, 0 end

    local cast = castSeconds or 0
    local channelSeconds = cast
    if cast <= 0 then cast = GCD end
    if cast > CAST_CAP then cast = CAST_CAP end

    local directBase = profile.direct and profile.direct.avg or 0
    local overTime = profile.overTime
    local dotBase = overTime and overTime.total or 0

    if dotBase <= 0 then
        return cast / CAST_CAP, 0
    end

    local duration = overTime.duration or DOT_CAP
    if directBase <= 0 and channelSeconds > 0
        and math.abs(duration - channelSeconds) < 0.6 then
        return 0, cast / CAST_CAP
    end

    local dotWindow = math.min(duration, DOT_CAP) / DOT_CAP
    if directBase <= 0 then
        return 0, dotWindow
    end

    local directWindow = cast / CAST_CAP
    local sum = directWindow + dotWindow
    if sum <= 0 then return 0, 0 end
    return directWindow * directWindow / sum, dotWindow * dotWindow / sum
end

-- ---------------------------------------------------------------------------
-- Hit chance
-- ---------------------------------------------------------------------------

-- TBC's miss tables against a mob N levels above you. The +3 row is the boss
-- row and the reason a caster stacks hit at all.
local SPELL_MISS = { [0] = 0.04, [1] = 0.05, [2] = 0.06, [3] = 0.17 }
local MELEE_MISS = { [0] = 0.05, [1] = 0.055, [2] = 0.06, [3] = 0.09 }

function M.MissChance(isPhysical, levelDelta, isPlayer, hitBonus)
    local delta = levelDelta or 0
    -- Players are levelled with you in every fight that matters, and TBC has
    -- no boss row against a player.
    if isPlayer then delta = 0 end
    if delta < 0 then delta = 0 elseif delta > 3 then delta = 3 end
    local miss = (isPhysical and MELEE_MISS or SPELL_MISS)[delta] - (hitBonus or 0)
    if miss < 0.01 then miss = 0.01 end
    return miss
end

-- ---------------------------------------------------------------------------
-- Samples: what the spell has actually landed for
-- ---------------------------------------------------------------------------

-- Targets are bucketed by level difference and by whether they are a player,
-- because armour, resistance and resilience make "1400 into a level 70 elite"
-- and "1400 into a rogue" different facts about the same spell. Anything four
-- or more levels under you is one bucket: the differences down there are noise
-- next to the fact that it dies.
function M.LevelBucket(playerLevel, targetLevel, isPlayer)
    local delta = (targetLevel or playerLevel or 0) - (playerLevel or 0)
    -- -1 is the client's "skull", i.e. at least +5. Treat it as the boss row.
    if targetLevel == -1 then delta = 3 end
    if delta < -3 then delta = -3 elseif delta > 3 then delta = 3 end
    return (isPlayer and "p" or "n") .. delta
end

function M.NewRecord()
    return {
        n = 0, avg = 0,             -- every landing, crits included
        nHit = 0, avgHit = 0,       -- non-crit landings
        nCrit = 0, avgCrit = 0,
        landed = 0, missed = 0,
        tickN = 0, tickAvg = 0,     -- one periodic tick
        ticksN = 0, ticksAvg = 0,   -- ticks per application
    }
end

-- A running mean that converges like a plain average until it has `window`
-- samples and then tracks the last `window` — so a fresh spell settles fast
-- and a re-geared character is not held back by what it hit for last month.
local function Feed(count, avg, value, window)
    count = count + 1
    local weight = count < window and count or window
    return count, avg + (value - avg) / weight
end

function M.Observe(record, amount, isCrit, window)
    window = window or 20
    if type(amount) ~= "number" or amount <= 0 then return record end
    record.n, record.avg = Feed(record.n, record.avg, amount, window)
    if isCrit then
        record.nCrit, record.avgCrit = Feed(record.nCrit, record.avgCrit, amount, window)
    else
        record.nHit, record.avgHit = Feed(record.nHit, record.avgHit, amount, window)
    end
    record.landed = (record.landed or 0) + 1
    M.DecayCounters(record)
    return record
end

function M.ObserveTick(record, amount, window)
    window = window or 20
    if type(amount) ~= "number" or amount <= 0 then return record end
    record.tickN, record.tickAvg = Feed(record.tickN or 0, record.tickAvg or 0, amount, window)
    return record
end

function M.ObserveTickCount(record, count, window)
    window = window or 20
    if type(count) ~= "number" or count <= 0 then return record end
    record.ticksN, record.ticksAvg = Feed(record.ticksN or 0, record.ticksAvg or 0, count, window)
    return record
end

function M.ObserveMiss(record)
    record.missed = (record.missed or 0) + 1
    M.DecayCounters(record)
    return record
end

-- Keep the hit/miss ratio but let it forget: without this a character who
-- gears out of a hit deficit carries the old miss rate forever.
function M.DecayCounters(record)
    local total = (record.landed or 0) + (record.missed or 0)
    if total > 200 then
        record.landed = math.floor((record.landed or 0) / 2)
        record.missed = math.floor((record.missed or 0) / 2)
    end
end

function M.MissRate(record)
    local total = (record.landed or 0) + (record.missed or 0)
    if total < 10 then return nil end        -- too few to be a rate
    return (record.missed or 0) / total
end

-- ---------------------------------------------------------------------------
-- The two estimates
-- ---------------------------------------------------------------------------

local function PickNumber(mode, average, hit, crit)
    if mode == "HIT" then return hit end
    if mode == "CRIT" then return crit end
    return average
end

-- stats: { level, spellPower[1..7], healPower, spellCrit[1..7], meleeCrit,
--          weaponAvg, spellHit, meleeHit }
-- target: { exists, level, isPlayer }
-- opts:   { number = "AVERAGE"|"HIT"|"CRIT", applyHit = bool }
function M.ModelEstimate(profile, stats, target, opts)
    if not profile or not stats then return nil end
    opts = opts or {}

    local isHealing = profile.kind == "heal" or profile.kind == "absorb"
    local isPhysical = profile.weapon or profile.school == M.SCHOOLS.physical
    local school = profile.school or M.SCHOOLS.physical

    local power, critChance, critMult
    if isHealing then
        power = stats.healPower or 0
        critChance = (stats.spellCrit and stats.spellCrit[school]) or 0
        critMult = SPELL_CRIT_MULT
    elseif profile.weapon then
        power = 0
        critChance = stats.meleeCrit or 0
        critMult = MELEE_CRIT_MULT
    else
        power = (stats.spellPower and stats.spellPower[school]) or 0
        critChance = (stats.spellCrit and stats.spellCrit[school]) or 0
        critMult = SPELL_CRIT_MULT
    end

    -- An absorb scales off the school it names (a ward off frost damage, a
    -- priest's shield off healing) and cannot crit.
    if profile.kind == "absorb" then
        if school ~= M.SCHOOLS.holy then
            power = (stats.spellPower and stats.spellPower[school]) or 0
        end
        critChance = 0
    end

    -- Items pay their printed number flat.
    if profile.noScaling then
        power, critChance = 0, 0
    end

    local directCoef, dotCoef = M.Coefficients(profile, opts.castSeconds)

    local direct, dot
    if profile.weapon then
        -- The client already folds attack power into the weapon's displayed
        -- damage, so the swing is read rather than rebuilt.
        direct = (stats.weaponAvg or 0) * (profile.weaponMult or 1) + (profile.weaponFlat or 0)
        dot = 0
    else
        direct = (profile.direct and profile.direct.avg or 0) + power * directCoef
        dot = (profile.overTime and profile.overTime.total or 0) + power * dotCoef
    end

    -- The target's state flexes the number: Ice Lance into a Frost Nova.
    local multiplier = 1
    if profile.frozenMult and target and target.frozen then
        multiplier = profile.frozenMult
        direct = direct * multiplier
    end

    -- Periodic damage does not crit in TBC, so only the direct part is rolled.
    local hit = direct + dot
    local crit = direct * critMult + dot
    local average = direct * (1 + critChance * (critMult - 1)) + dot

    local missChance = 0
    if not isHealing then
        local delta = (target and target.level or stats.level or 0) - (stats.level or 0)
        if target and target.level == -1 then delta = 3 end
        missChance = M.MissChance(isPhysical, delta, target and target.isPlayer,
            isPhysical and stats.meleeHit or stats.spellHit)
        if opts.applyHit ~= false then
            average = average * (1 - missChance)
        end
    end

    return {
        source = "model",
        value = PickNumber(opts.number, average, hit, crit),
        average = average, hit = hit, crit = crit,
        direct = direct, dot = dot,
        power = power, directCoef = directCoef, dotCoef = dotCoef,
        critChance = critChance, critMult = critMult,
        missChance = missChance,
        multiplier = multiplier,
        kind = profile.kind,
        school = school,
    }
end

-- The measured estimate needs the profile only to know whether the spell has a
-- periodic part at all; every number in it comes off the log.
-- opts.multiplier scales the DIRECT part: the fallback for a conditional
-- spell whose condition holds now but whose record was measured without it
-- (an Ice Lance that has only ever hit unfrozen targets). Samples taken WITH
-- the condition live in their own bucket and never need it.
function M.MeasuredEstimate(record, profile, opts)
    if not record then return nil end
    opts = opts or {}
    local multiplier = opts.multiplier or 1

    local directHits = record.n or 0
    local tickHits = record.tickN or 0
    if directHits <= 0 and tickHits <= 0 then return nil end

    local ticks = 0
    if tickHits > 0 then
        -- Ticks per application is itself measured: counted between the aura
        -- landing and the aura leaving. The tooltip's duration is only the
        -- fallback, and a 3s period is TBC's near-universal default.
        local perApplication = (record.ticksN or 0) > 0 and record.ticksAvg or nil
        if not perApplication and profile and profile.overTime and profile.overTime.duration then
            perApplication = profile.overTime.duration / 3
        end
        ticks = (record.tickAvg or 0) * (perApplication or 0)
    end

    local directAverage = (directHits > 0 and record.avg or 0) * multiplier

    -- The non-crit average is the honest "normal hit"; before a non-crit has
    -- been seen the overall average is the only figure there is.
    local directHit = directAverage
    if (record.nHit or 0) > 0 then directHit = record.avgHit * multiplier end

    -- Likewise for the crit: until one lands, the multiplier has to be assumed,
    -- and which one to assume is the one thing the profile is still needed for.
    local directCrit
    if (record.nCrit or 0) > 0 then
        directCrit = record.avgCrit * multiplier
    else
        directCrit = directHit * ((profile and profile.weapon) and MELEE_CRIT_MULT or SPELL_CRIT_MULT)
    end

    local hit = directHit + ticks
    local crit = directCrit + ticks
    local average = directAverage + ticks

    local missRate = M.MissRate(record)
    if missRate and opts.applyHit ~= false then
        average = average * (1 - missRate)
    end

    return {
        source = "measured",
        value = PickNumber(opts.number, average, hit, crit),
        average = average, hit = hit, crit = crit,
        direct = directAverage,
        dot = ticks,
        samples = directHits + tickHits,
        critRate = directHits > 0 and (record.nCrit or 0) / directHits or nil,
        missChance = missRate,
        multiplier = multiplier,
    }
end

-- Which of the two the icon shows. AUTO is the point of the module: the model
-- carries a spell until the log knows better, and then the log takes over.
function M.Compose(modeled, measured, sourceMode, minSamples)
    if sourceMode == "MODEL" then return modeled end
    local enough = measured and (measured.samples or 0) >= (minSamples or 3)
    if sourceMode == "MEASURED" then return enough and measured or nil end
    if enough then return measured end
    return modeled
end

-- ---------------------------------------------------------------------------
-- Presentation
-- ---------------------------------------------------------------------------

function M.Format(value, compact, decimals)
    if type(value) ~= "number" or value ~= value then return nil end
    if value < 0 then value = 0 end
    if decimals then
        if value >= 100 then return string.format("%d", value + 0.5) end
        return string.format("%.1f", value)
    end
    if compact then
        if value >= 10000 then return string.format("%.0fk", value / 1000) end
        if value >= 1000 then return string.format("%.1fk", value / 1000) end
    end
    return string.format("%d", value + 0.5)
end

-- ---------------------------------------------------------------------------
-- Runtime: everything below here reads the live client
-- ---------------------------------------------------------------------------

-- Guarded so the Harness can load this file with no client at all.
local HAS_CLIENT = type(_G.CreateFrame) == "function"

if HAS_CLIENT then
    -- Our own tooltip, never GameTooltip: other suite modules hook GameTooltip's
    -- methods, and a scan is not a hover.
    local scanner = CreateFrame("GameTooltip", "CommanderForecastScanTooltip", nil, "GameTooltipTemplate")
    scanner:SetOwner(UIParent, "ANCHOR_NONE")

    local function ScanLines()
        local lines = {}
        for i = 1, scanner:NumLines() do
            local region = _G["CommanderForecastScanTooltipTextLeft" .. i]
            lines[i] = region and region:GetText() or ""
        end
        return lines
    end

    -- A tooltip Set* on this client can produce NOTHING without raising, so the
    -- only proof of a fill is a line count taken after it.
    local function Fill(fn, ...)
        scanner:SetOwner(UIParent, "ANCHOR_NONE")
        scanner:ClearLines()
        local ok = pcall(fn, scanner, ...)
        if not ok then return false end
        return (scanner:NumLines() or 0) > 0
    end

    local spellProfiles = {}
    local itemProfiles = {}
    local scanAttempts = {}
    local MAX_SCAN_ATTEMPTS = 40

    -- Absorbs that keep more than the default tenth of spell power.
    local ABSORB_COEF_BY_NAME = {
        ["Power Word: Shield"] = 0.3,
    }

    -- A spell's text never changes, so a parse is done once per spell ID for
    -- the life of the session. `false` is cached too: a spell whose wording we
    -- cannot read must not be re-scanned on every repaint.
    --
    -- With one exception that cost Ice Lance its number in the field: spell
    -- text arrives ASYNCHRONOUSLY on this client. A scan at login can come
    -- back with the name and nothing under it, and caching that as "nothing
    -- to say" is permanent. So an empty description is never cached — the
    -- data is requested, the scan retried on later repaints, and
    -- SPELL_TEXT_UPDATE / SPELL_DATA_LOAD_RESULT drop whatever was learned.
    -- Only a description that was READ and still parsed to nothing is final.
    function M.SpellProfile(spellID)
        if not spellID then return nil end
        local cached = spellProfiles[spellID]
        if cached ~= nil then return cached or nil end

        if C_Spell and C_Spell.IsSpellDataCached and not C_Spell.IsSpellDataCached(spellID) then
            if C_Spell.RequestLoadSpellData then
                pcall(C_Spell.RequestLoadSpellData, spellID)
            end
            scanAttempts[spellID] = (scanAttempts[spellID] or 0) + 1
            if scanAttempts[spellID] < MAX_SCAN_ATTEMPTS then return nil end
        end

        local filled = Fill(scanner.SetSpellByID, spellID)
        if not filled then
            local link = GetSpellLink and GetSpellLink(spellID)
            filled = link and Fill(scanner.SetHyperlink, link)
        end

        local description = filled and M.DescriptionFrom(ScanLines()) or ""
        if description == "" then
            scanAttempts[spellID] = (scanAttempts[spellID] or 0) + 1
            if scanAttempts[spellID] >= MAX_SCAN_ATTEMPTS then
                spellProfiles[spellID] = false
            end
            return nil
        end

        local profile = M.ParseDescription(description)
        if profile and profile.kind == "absorb" then
            local name = GetSpellInfo(spellID)
            profile.coefOverride = ABSORB_COEF_BY_NAME[name] or profile.coefOverride
        end
        spellProfiles[spellID] = profile or false
        return profile
    end

    function M.ForgetProfile(spellID)
        if spellID then
            spellProfiles[spellID] = nil
            scanAttempts[spellID] = nil
        end
    end

    function M.ItemProfile(itemID)
        if not itemID then return nil end
        local cached = itemProfiles[itemID]
        if cached ~= nil then return cached or nil end
        if not Fill(scanner.SetItemByID, itemID) then
            itemProfiles[itemID] = false
            return nil
        end
        local profile = M.ParseDescription(M.DescriptionFrom(ScanLines()))
        if profile then
            -- A healthstone heals for what it says and nothing more: it takes
            -- no spell power and it cannot crit. Without this it would collect
            -- a caster's +healing through the instant-cast coefficient and
            -- advertise a third more than it delivers.
            profile.noScaling = true
        end
        itemProfiles[itemID] = profile or false
        return profile
    end

    function M.ForgetProfiles()
        spellProfiles, itemProfiles, scanAttempts = {}, {}, {}
    end

    -- Cast seconds as the coefficient wants them: the real cast, or the global
    -- for an instant, because that is the window an instant is normalised over.
    function M.CastSeconds(spellID)
        local castMS = spellID and select(4, GetSpellInfo(spellID))
        if not castMS or castMS <= 0 then return 0 end
        return castMS / 1000
    end

    function M.ManaCost(spellID)
        local costs = spellID and C_Spell and C_Spell.GetSpellPowerCost
            and C_Spell.GetSpellPowerCost(spellID)
        if type(costs) ~= "table" then return 0 end
        for _, cost in ipairs(costs) do
            -- Enum.PowerType.Mana is 0; anything else (rage, energy) is not a
            -- currency "per mana" means anything about.
            if cost.type == 0 then return cost.cost or 0 end
        end
        return 0
    end

    -- One read of every stat the model needs, taken once per repaint rather
    -- than once per icon.
    function M.PlayerStats()
        local stats = {
            level = UnitLevel("player") or 1,
            spellPower = {},
            spellCrit = {},
            healPower = (GetSpellBonusHealing and GetSpellBonusHealing()) or 0,
            meleeCrit = ((GetCritChance and GetCritChance()) or 0) / 100,
            spellHit = 0,
            meleeHit = 0,
        }
        for school = 1, 7 do
            stats.spellPower[school] = (GetSpellBonusDamage and GetSpellBonusDamage(school)) or 0
            stats.spellCrit[school] = (((GetSpellCritChance and GetSpellCritChance(school)) or 0)) / 100
        end
        local minDamage, maxDamage = UnitDamage("player")
        stats.weaponAvg = ((minDamage or 0) + (maxDamage or 0)) / 2

        -- Hit is a rating on this client; the bonus getter is the percentage
        -- it converts to. Talent-granted hit is invisible here, which is one
        -- more reason the measured path outranks this one.
        if GetCombatRatingBonus then
            if _G.CR_HIT_SPELL then
                stats.spellHit = (GetCombatRatingBonus(_G.CR_HIT_SPELL) or 0) / 100
            end
            if _G.CR_HIT_MELEE then
                stats.meleeHit = (GetCombatRatingBonus(_G.CR_HIT_MELEE) or 0) / 100
            end
        end
        return stats
    end

    function M.TargetContext()
        if not UnitExists("target") then
            return { exists = false, level = UnitLevel("player") or 1, isPlayer = false }
        end
        return {
            exists = true,
            guid = UnitGUID("target"),
            level = UnitLevel("target") or (UnitLevel("player") or 1),
            isPlayer = UnitIsPlayer("target") and true or false,
            hostile = UnitCanAttack("player", "target") and true or false,
            -- `frozen` is stamped by the caller, which watches the combat log
            -- for freeze auras: that ordering is what makes an Ice Lance's
            -- own damage event still count as "into a frozen target" even
            -- though the same hit is what breaks the freeze.
        }
    end
end
