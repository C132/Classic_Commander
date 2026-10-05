-- Commander Quest Log: the reputation rules engine.
--
-- Every surface that shows a quest -- the Log's briefing, the Zones and
-- Reputations tabs, the map drawer, a waypoint's note, the NPC's own quest
-- dialog -- says what reputation it is worth, and they must all say the SAME
-- number. That number is decided here, in plain Lua over plain tables, and
-- nowhere else. No client API, no Questie global, no print, no timer: the
-- generated data file (CommanderQuestLogReputationData) and the character's
-- standings are handed in by the adapter, and this file turns a quest's
-- listed rewards into what the server will actually do to the bar.
--
-- Why not Questie's own QuestieReputation.GetReputationReward? Because it is
-- wrong in ways a completionist notices: it never rounds (+137.5 Sha'tar), it
-- takes the Aldor/Scryers penalty from the RAW value (-275 for a Human where
-- the server takes -302), it has no per-quest reward clamp, it boosts the
-- stored Sha'tar row as if it were a reward, and it shows a Human +46200 for
-- Ally of the Netherwing. The rules below are the server's (CMaNGOS mangos-tbc
-- Player::CalculateReputationGain and ReputationMgr::SetReputation), with the
-- client's own Faction DB2 for spillover and starting standings.
--
-- The traps this file exists to contain:
--
--   * Rounding is per turn-in and toward zero. A Human's 25-point mark is 27,
--     not 27.5, and ten of them are 270, not 275. A projection therefore
--     truncates every turn-in on its own; it never multiplies a sum.
--   * Modifiers ADD for a gain and SUBTRACT for a loss (Diplomacy shrinks a
--     Human's direct losses by 10%), and they are read at the moment of
--     computing -- the Hallow's End buff comes and goes, so nothing here ever
--     bakes one into a stored value.
--   * Three Classic factions (Argent Dawn, Cenarion Circle, Timbermaw Hold)
--     carry a server-side quest rate of 2: the listed value is doubled.
--   * Clamp, THEN spill. The per-quest reward clamp (RewMaxRepValue: the mark
--     turn-ins stop at 8999, Ally of the Netherwing at exactly 0) and the
--     42999 ceiling cut the gain first; spillover is taken from that clamped,
--     boosted gain. So an Orc at 8900 Aldor turning in ten marks moves the
--     Aldor +99, the Scryers -108 and the Sha'tar +49 -- not +250/-275/+125.
--   * The rival loss IS spillover: the Aldor and the Scryers spill -110% into
--     each other. No quest stores it; it is derived from the faction data.
--   * Spillover has a window. The Sha'tar takes half of every Aldor/Scryers
--     gain only while it is Friendly or below, and (rules.spillClamp
--     "capTop", the default, backed by the reward caps in the data itself)
--     never past the top of that window: 8999. Under "mangos" the last spill
--     may overshoot, as the emulator's rank-before-gain check allows.
--   * Stored rows that are really spillover. The quest data writes the
--     Sha'tar's half into 85 Aldor/Scryers quests (and goblin-town or city
--     halves into a few more). Counted as rewards they are paid twice. The
--     generator lists them as `derived`; they are dropped and regenerated
--     from the spill rules, which also gets the window and Diplomacy right.
--   * A header passes a reward to its children at each CHILD's rate, not at
--     100% -- the data carries the flattened edge rate, and that is used.
--   * Gates close. Several quests are offered only BELOW a standing (the
--     Consortium's crystal and ivory quests under 3000). "Can quests alone
--     get me there" is a simulation in the best order -- the spill window
--     and the closing gates first -- never a plain sum, and an exclusive
--     choice counts once.
--   * An unmet faction's standing is its DB2 base for this race and class
--     (Sporeggar -2500, Kurenai -1200, Netherwing -42000), never "Neutral".
--
-- Units are raw reputation points, signed, as Questie's reputationReward and
-- CMaNGOS's RewRepValue carry them. Ranks are 0 (Hated) .. 7 (Exalted); the
-- client's standingID is rank + 1.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local R = {}
Q.Standing = R

local floor, ceil, abs = math.floor, math.ceil, math.abs
local format = string.format

-- ---------------------------------------------------------------------------
-- Constants
--
-- The thresholds are ReputationMgr's PointsInRank laid end to end from the
-- bottom; the data file carries the same eight numbers, and the harness holds
-- the two together. Exalted's bar runs to 43000 but the value stops at 42999.
-- ---------------------------------------------------------------------------

local THRESHOLDS = { -42000, -6000, -3000, 0, 3000, 9000, 21000, 42000 }
local BOTTOM, CEILING, EXALTED = -42000, 42999, 42000
local MAX_RANK = 7

R.THRESHOLDS = THRESHOLDS
R.BOTTOM, R.CAP, R.EXALTED = BOTTOM, CEILING, EXALTED

-- English fallbacks, indexed by standingID (rank + 1) like the client's
-- FACTION_STANDING_LABEL1..8; the adapter passes the localised ones.
R.LABELS = { "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }

R.KIND = { DIRECT = "DIRECT", SPILL = "SPILL", RIVAL = "RIVAL" }
R.NO_REPUTATION = "No reputation"

-- Diplomacy (Human racial, 20599) and Invocation of the Wickerman (24705)
-- are both aura 156 at BasePoints 9 + DieSides 1 in this build's DB2: +10%.
R.DIPLOMACY_PCT, R.WICKERMAN_PCT = 10, 10

local DIRECT, SPILL, RIVAL = "DIRECT", "SPILL", "RIVAL"

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

-- A finite number, or nil. NaN and the infinities are not standings.
local function Num(value)
    value = tonumber(value)
    if value and value == value and value ~= math.huge and value ~= -math.huge then return value end
    return nil
end

-- Toward zero: int32(x) in the server, for gains and losses alike
local function Trunc(x)
    if x >= 0 then return floor(x) end
    return ceil(x)
end
R.Trunc = Trunc

local function Clamp(value, D)
    local lo = Num(D and D.bottom) or BOTTOM
    local hi = Num(D and D.cap) or CEILING
    if value > hi then return hi end
    if value < lo then return lo end
    return value
end

local function CeilingOf(D) return Num(D and D.cap) or CEILING end
local function BottomOf(D) return Num(D and D.bottom) or BOTTOM end

local function Faction(D, factionId)
    local list = type(D) == "table" and D.factions
    local f = type(list) == "table" and factionId and list[factionId]
    if type(f) == "table" then return f end
    return nil
end

local function QuestTable(D, key, questId)
    local list = type(D) == "table" and D[key]
    if type(list) ~= "table" or not questId then return nil end
    local row = list[questId]
    if row == nil or row == false then return nil end
    return row
end

-- 2^(id - 1): the race and class masks in Faction.db2 are bit sets, and the
-- client answers race and class ids (UnitRace / UnitClass third return).
function R.Bit(id)
    id = Num(id)
    if not id or id < 1 or id ~= floor(id) or id > 52 then return nil end
    return 2 ^ (id - 1)
end

local function IsBit(bit)
    if type(bit) ~= "number" or bit < 1 or bit ~= floor(bit) then return false end
    while bit > 1 do
        if bit % 2 ~= 0 then return false end
        bit = bit / 2
    end
    return true
end

-- mask & bit for a single-bit `bit`, with no bit library (pure Lua 5.1)
local function HasBit(mask, bit)
    return floor(mask / bit) % 2 == 1
end

-- ---------------------------------------------------------------------------
-- Ranks
-- ---------------------------------------------------------------------------

-- rank 0..7 and the rank's bar, as the client's GetFactionInfo answers it:
-- rankMin is the first value of the rank, rankMax the first value of the
-- next (Exalted's is 43000), so the bar reads value - rankMin of rankMax -
-- rankMin. Values outside [-42000, 42999] are clamped, as the server does.
function R.Rank(value)
    value = Num(value)
    if not value then return nil end
    if value > CEILING then value = CEILING elseif value < BOTTOM then value = BOTTOM end
    local rank = 0
    for i = 2, #THRESHOLDS do
        if value >= THRESHOLDS[i] then rank = i - 1 end
    end
    return rank, THRESHOLDS[rank + 1], THRESHOLDS[rank + 2] or (CEILING + 1)
end

-- The last value inside a rank: 8999 for Friendly, 42999 for Exalted
function R.RankTop(rank)
    rank = Num(rank)
    if not rank then return nil end
    rank = floor(rank)
    if rank < 0 then rank = 0 elseif rank > MAX_RANK then rank = MAX_RANK end
    return (THRESHOLDS[rank + 2] or (CEILING + 1)) - 1
end

-- Points to the next rank (nil at Exalted), and to Exalted (0 once there).
-- Exalted starts at 42000; the 42999 ceiling only matters for clamping.
function R.ToNext(value)
    local rank, _, rankMax = R.Rank(value)
    if not rank or rank >= MAX_RANK then return nil end
    return rankMax - Clamp(Num(value), nil)
end

function R.ToExalted(value)
    value = Num(value)
    if not value then return nil end
    value = Clamp(value, nil)
    if value >= EXALTED then return 0 end
    return EXALTED - value
end

-- ---------------------------------------------------------------------------
-- Starting standing (Faction.db2 ReputationBase, FactionEntry::GetIndexFitTo)
--
-- The FIRST base row whose race mask and class mask both fit (a mask of 0
-- fits everyone) gives the value and the default flags; no row fitting means
-- 0. The server stores standing as a delta from this base, so a faction the
-- character has never met sits at exactly its base -- and that is what the
-- adapter shows when GetFactionInfoByID answers nothing for it.
-- ---------------------------------------------------------------------------

-- raceBit / classBit are R.Bit(raceId) / R.Bit(classId); nil means "do not
-- filter on that axis". A non-bit (a raw race id of 3, say) answers nil, so a
-- caller's slip shows as nothing rather than as a plausible wrong standing.
function R.Base(D, factionId, raceBit, classBit)
    local f = Faction(D, Num(factionId))
    if not f then return nil end
    if raceBit ~= nil and not IsBit(raceBit) then return nil end
    if classBit ~= nil and not IsBit(classBit) then return nil end
    if type(f.base) ~= "table" then return 0, 0 end
    for _, row in ipairs(f.base) do
        if type(row) == "table" then
            local raceMask, classMask = Num(row[1]) or 0, Num(row[2]) or 0
            local raceFits = raceMask == 0 or not raceBit or HasBit(raceMask, raceBit)
            local classFits = classMask == 0 or not classBit or HasBit(classMask, classBit)
            if raceFits and classFits then return Num(row[3]) or 0, Num(row[4]) or 0 end
        end
    end
    return 0, 0
end

-- The player's side from the data alone: every faction the generator marked
-- with a side votes, and a faction whose base for this race is -42000 votes
-- for the other side (critic W9: the flags do not say it, the base does).
function R.Side(D, raceBit)
    if not IsBit(raceBit) or type(D) ~= "table" or type(D.factions) ~= "table" then return nil end
    local votes = { Alliance = 0, Horde = 0 }
    for factionId, f in pairs(D.factions) do
        local side = type(f) == "table" and f.side
        if votes[side] then
            local base = R.Base(D, factionId, raceBit, nil)
            if base == BOTTOM then
                side = side == "Alliance" and "Horde" or "Alliance"
            end
            votes[side] = votes[side] + 1
        end
    end
    if votes.Alliance > votes.Horde then return "Alliance" end
    if votes.Horde > votes.Alliance then return "Horde" end
    return nil
end

-- A faction belongs to the other side when the data says so; a faction with
-- no side is everyone's.
local function SideOk(D, factionId, side)
    if not side then return true end
    local f = Faction(D, factionId)
    local own = f and f.side
    return not own or own == side
end

-- The spill edges out of a faction, as { target, rate, maxRankIn } rows
local function Edges(D, factionId)
    local f = Faction(D, factionId)
    if f and type(f.spill) == "table" then return f.spill end
    return nil
end

local function EdgeTo(D, source, target)
    local edges = Edges(D, source)
    if not edges then return nil end
    for _, edge in ipairs(edges) do
        if type(edge) == "table" and Num(edge[1]) == target then
            return Num(edge[2]), Num(edge[3])
        end
    end
    return nil
end

-- The factions a gain with this one costs: its negative spill edges
function R.Rivals(D, factionId)
    local out = {}
    local edges = Edges(D, Num(factionId))
    if edges then
        for _, edge in ipairs(edges) do
            local target, rate = type(edge) == "table" and Num(edge[1]), type(edge) == "table" and Num(edge[2])
            if target and rate and rate < 0 then out[#out + 1] = target end
        end
    end
    table.sort(out)
    return out
end

local function IsRival(D, a, b)
    local rate = EdgeTo(D, a, b)
    return rate ~= nil and rate < 0
end

-- ---------------------------------------------------------------------------
-- One turn-in (Player::CalculateReputationGain)
-- ---------------------------------------------------------------------------

-- mods = { human = bool, wickerman = bool [, extra = n] } -> 100 + the sum
function R.Multiplier(mods)
    local pct = 100
    if type(mods) == "table" then
        if mods.human then pct = pct + R.DIPLOMACY_PCT end
        if mods.wickerman then pct = pct + R.WICKERMAN_PCT end
        local extra = Num(mods.extra)
        if extra then pct = pct + extra end
    end
    return pct
end

-- The percentage one listed value is paid at: the modifiers added for a gain
-- and taken away for a loss, the low-level rule behind its flag (off: the
-- 2.0.1 change, CMaNGOS cca2dcc), then the faction's quest rate.
local function Percent(D, factionId, raw, pct, levels)
    local mods = (Num(pct) or 100) - 100
    local percent = 100 + (raw > 0 and mods or -mods)
    local rules = type(D) == "table" and type(D.rules) == "table" and D.rules or nil
    if rules and rules.lowLevelQuestPenalty and type(levels) == "table" then
        local questLevel, playerLevel = Num(levels.quest), Num(levels.player)
        if questLevel and playerLevel and questLevel > 0 and playerLevel > questLevel + 5 then
            local minRate = Num(rules.lowLevelMinRate) or 0.2
            local factor = 1 - 0.2 * (playerLevel - (questLevel + 5))
            percent = percent * (factor > minRate and factor or minRate)
        end
    end
    if percent <= 0 then return 0 end
    local f = Faction(D, factionId)
    local rate = f and type(f.rate) == "table" and Num(f.rate.quest)
    if rate then
        if rate <= 0 then return 0 end
        percent = percent * rate
    end
    return percent
end

-- The truncated gain before any clamp
local function RawGain(D, factionId, raw, pct, levels)
    raw = Num(raw)
    if not raw or raw == 0 then return 0 end
    return Trunc(raw * Percent(D, factionId, raw, pct, levels) / 100)
end
R.RawGain = RawGain

local function RewardCap(D, questId, factionId)
    local caps = QuestTable(D, "rewardCap", questId)
    return type(caps) == "table" and Num(caps[factionId]) or nil
end
R.RewardCap = RewardCap

-- The gain one turn-in makes at `current`: truncated, quest-rated, and held to
-- the quest's RewMaxRepValue for this faction (42999 when it has none). The
-- server zeroes ANY result once current >= that value, a loss included.
-- Returns gain, capped (the clamp cut it), limit (the value it stops at).
function R.QuestGain(D, questId, factionId, raw, current, pct, levels)
    questId, factionId = Num(questId), Num(factionId)
    local full = RawGain(D, factionId, raw, pct, levels)
    if full == 0 then return 0, false, nil end
    local ceiling = CeilingOf(D)
    local limit = RewardCap(D, questId, factionId) or ceiling
    if limit > ceiling then limit = ceiling end
    current = Num(current) or 0
    local gain = full
    if current < limit then
        local room = limit - current
        if gain > room then gain = room end
    else
        gain = 0
    end
    return gain, gain ~= full, limit
end

-- ---------------------------------------------------------------------------
-- Calibration (runtime truth)
--
-- The adapter watches a turn-in move the bars and hands each faction's delta
-- here. It is stored NORMALISED -- as the listed value that would produce it
-- at a multiplier of 100 -- so a sample taken with the Hallow's End buff up
-- still reads right without it. A sample that hit the ceiling, the bottom, a
-- quest's reward clamp or a spill window says nothing about the quest and is
-- thrown away, and so does a move several of the quest's rows made between
-- them (R.MixedSources: the adapter sets it aside, Effects never reads one).
-- store[questId][factionId] = { raw, n, delta, pct, kind }.
-- ---------------------------------------------------------------------------

-- The integer listed value r with trunc(r * percent / 100) == delta, nearest
-- the exact quotient; the rounded quotient when no integer reproduces it.
local function Normalise(delta, percent)
    if percent == 100 or percent <= 0 then return delta end
    local exact = delta * 100 / percent
    local base = Trunc(exact)
    local best
    for step = -1, 1 do
        local r = base + step
        if Trunc(r * percent / 100) == delta then
            if not best or abs(r - exact) < abs(best - exact) then best = r end
        end
    end
    if best then return best end
    if exact >= 0 then return floor(exact + 0.5) end
    return -floor(-exact + 0.5)
end
R.Normalise = Normalise

-- flags = { kind = "DIRECT"|"SPILL"|"RIVAL", rate = quest rate, after = the
-- standing after the turn-in, cap = the quest's reward clamp for this faction,
-- ceiling / bottom / rewardClamp / spillCap / capped = true to drop }.
-- Returns true, raw when stored; false, reason when dropped.
function R.Observe(store, questId, factionId, delta, pct, flags)
    if type(store) ~= "table" then return false, "no store" end
    questId, factionId, delta = Num(questId), Num(factionId), Num(delta)
    if not (questId and factionId and delta) then return false, "incomplete" end
    flags = type(flags) == "table" and flags or {}
    pct = Num(pct) or 100
    local after, cap = Num(flags.after), Num(flags.cap)
    if flags.ceiling or (after and after >= CEILING) then return false, "ceiling" end
    if flags.bottom or (after and after <= BOTTOM) then return false, "bottom" end
    if flags.rewardClamp or (cap and after and after >= cap) then return false, "reward clamp" end
    if flags.spillCap then return false, "spill cap" end
    if flags.capped then return false, "capped" end
    local kind = flags.kind
    local percent
    if kind == SPILL or kind == RIVAL then
        -- a spill is a share of the boosted gain: undo the boost only
        percent = pct
    else
        local mods = pct - 100
        percent = 100 + (delta >= 0 and mods or -mods)
        local rate = Num(flags.rate)
        if rate and rate > 0 then percent = percent * rate end
    end
    local raw = Normalise(delta, percent)
    local byQuest = store[questId]
    if type(byQuest) ~= "table" then
        byQuest = {}
        store[questId] = byQuest
    end
    local sample = byQuest[factionId]
    if type(sample) ~= "table" then
        sample = {}
        byQuest[factionId] = sample
    end
    if sample.raw ~= nil and sample.raw ~= raw then sample.changed = (sample.changed or 0) + 1 end
    sample.raw, sample.delta, sample.pct, sample.kind = raw, delta, pct, kind
    sample.n = (Num(sample.n) or 0) + 1
    return true, raw
end

-- raw, kind: a sample's normalised listed value and the kind it was stored
-- as ("DIRECT" | "SPILL" | "RIVAL"; nil for a bare number)
local function ObservedRaw(store, questId, factionId)
    local byQuest = type(store) == "table" and questId and store[questId]
    local sample = type(byQuest) == "table" and factionId and byQuest[factionId]
    if type(sample) == "table" then return Num(sample.raw), sample.kind end
    return Num(sample), nil
end

-- The normalised listed value seen in game for this pair, or nil
function R.Observed(store, questId, factionId)
    return (ObservedRaw(store, Num(questId), Num(factionId)))
end

-- How many quests carry at least one sample (for the status line)
function R.ObservedCount(store)
    local quests, samples = 0, 0
    if type(store) ~= "table" then return 0, 0 end
    for _, byQuest in pairs(store) do
        if type(byQuest) == "table" then
            local any = false
            for _, sample in pairs(byQuest) do
                if type(sample) == "table" and Num(sample.raw) then
                    samples = samples + 1
                    any = true
                end
            end
            if any then quests = quests + 1 end
        end
    end
    return quests, samples
end

-- ---------------------------------------------------------------------------
-- A quest's effects on every faction it moves
-- ---------------------------------------------------------------------------

local function StandingOf(standings, factionId)
    local value
    if type(standings) == "function" then
        value = standings(factionId)
    elseif type(standings) == "table" then
        value = standings[factionId]
    end
    return Num(value)
end

local function AsSet(list)
    local set = {}
    if type(list) == "table" then
        for key, value in pairs(list) do
            if type(key) == "number" and Num(value) then
                set[Num(value)] = true -- array form { 935, ... }
            elseif Num(key) and value == true then
                set[Num(key)] = true -- set form { [935] = true }
            end
        end
    end
    return set
end

-- Questie's rows, minus the generator's `derived` (stored spillover), with
-- the audited `overrides` applied on top (an override of 0 removes a row, a
-- faction the rows lack is added after them, lowest id first). Rows for a
-- faction with no standing slot are dropped, as the server drops them.
local function PrepareRows(D, questId, rows)
    local out, at, dropped = {}, {}, {}
    local derived = AsSet(QuestTable(D, "derived", questId))
    local known = type(D) == "table" and type(D.factions) == "table" and next(D.factions) ~= nil
    if type(rows) == "table" then
        for _, row in ipairs(rows) do
            local factionId = type(row) == "table" and Num(row[1])
            local raw = type(row) == "table" and Num(row[2])
            if factionId and raw and raw ~= 0 then
                if derived[factionId] then
                    dropped[#dropped + 1] = factionId
                elseif known and not Faction(D, factionId) then
                    dropped[#dropped + 1] = factionId
                elseif not at[factionId] then
                    out[#out + 1] = { factionId, raw }
                    at[factionId] = #out
                end
            end
        end
    end
    local overrides = QuestTable(D, "overrides", questId)
    if type(overrides) == "table" then
        local keys = {}
        for key, value in pairs(overrides) do
            if Num(key) and Num(value) then keys[#keys + 1] = Num(key) end
        end
        table.sort(keys)
        for _, factionId in ipairs(keys) do
            local value = Num(overrides[factionId]) or Num(overrides[tostring(factionId)])
            if at[factionId] then
                local row = out[at[factionId]]
                row[2], row.overridden = value, true
            else
                out[#out + 1] = { factionId, value, overridden = true }
                at[factionId] = #out
            end
        end
    end
    local kept = {}
    for _, row in ipairs(out) do
        if row[2] ~= 0 then kept[#kept + 1] = row end
    end
    return kept, dropped
end

-- The factions whose move on one turn-in no single source explains: a
-- DIRECT faction another of the quest's direct rows spills into (Orgrimmar
-- on Cutting Teeth, which pays the Darkspear Trolls too, moves by its own
-- 250 plus their 62), and a spill target two or more direct rows feed (the
-- Undercity from both). A sample of such a move is a SUM; read back as one
-- faction's listed value it is paid again on every share -- the 2026-10-04
-- review saw Durotar's quests double after one turn-in. So the adapter sets
-- these moves aside, and the engine never reads a sample for them (one an
-- older build stored included). Conservative by design: any edge counts,
-- whatever window or side would cut it on the day, and a lost sample costs
-- nothing (D40). `list` is PrepareRows' answer; -> { [factionId] = true }.
local function MixedSet(D, list, side)
    local direct, feeds, mixed = {}, {}, {}
    for _, row in ipairs(list) do
        if SideOk(D, row[1], side) then direct[row[1]] = true end
    end
    for source in pairs(direct) do
        for _, edge in ipairs(Edges(D, source) or {}) do
            local target = type(edge) == "table" and Num(edge[1])
            local rate = type(edge) == "table" and Num(edge[2])
            if target and target ~= source and rate and rate ~= 0 and SideOk(D, target, side) then
                feeds[target] = (feeds[target] or 0) + 1
            end
        end
    end
    for target, sources in pairs(feeds) do
        if direct[target] or sources > 1 then mixed[target] = true end
    end
    return mixed
end

-- The same for Questie's rows of one quest (derived dropped, overrides on):
-- { [factionId] = true } for every faction a sample cannot stand for
function R.MixedSources(D, questId, rows, side)
    questId = Num(questId)
    return MixedSet(D, (PrepareRows(D, questId, rows)), side)
end

-- R.Observed for a reader that takes the sample as the faction's OWN listed
-- value (a done quest's estimate, a projection's raw): nil when the sample
-- is a spill share or the faction's move on this quest is mixed.
function R.ObservedFor(D, store, questId, factionId, rows, side)
    questId, factionId = Num(questId), Num(factionId)
    local raw, kind = ObservedRaw(store, questId, factionId)
    if raw == nil or kind == SPILL or kind == RIVAL then return nil end
    if R.MixedSources(D, questId, rows, side)[factionId] then return nil end
    return raw
end

local function RankWord(rank, labels)
    return R.StandingWord(rank, labels) or R.LABELS[(rank or 3) + 1]
end

-- One faction's entry in a quest's effects, created on first touch
local function Entry(acc, order, D, factionId)
    local entry = acc[factionId]
    if not entry then
        local f = Faction(D, factionId)
        entry = { factionId, 0, factionId = factionId, delta = 0, kind = SPILL, capped = false,
            name = f and type(f.name) == "string" and f.name or nil, uncapped = 0 }
        acc[factionId] = entry
        order[#order + 1] = entry
    end
    return entry
end

local function Note(entry, note)
    entry.capped = true
    if note and not entry.capNote then entry.capNote = note end
end

-- Moves one faction's running value by `amount`, clamped to the bar, and
-- books the change on its entry. Returns the change actually made.
local function Move(state, entry, D, factionId, amount, labels)
    local before = state[factionId]
    local after = Clamp(before + amount, D)
    if after ~= before + amount then
        Note(entry, after >= CeilingOf(D) and "at the Exalted cap" or ("at the bottom of " .. RankWord(0, labels)))
    end
    state[factionId] = after
    entry.delta = entry.delta + (after - before)
    entry[2] = entry.delta
    return after - before
end

local function SortEffects(list)
    table.sort(list, function(a, b)
        local ad, bd = a.kind == DIRECT, b.kind == DIRECT
        if ad ~= bd then return ad end
        local am, bm = abs(a.delta), abs(b.delta)
        if am ~= bm then return am > bm end
        return a.factionId < b.factionId
    end)
end

-- effects = { {factionId, delta, kind=, capped=, capNote=, ...}, ... }:
-- DIRECT first, then SPILL/RIVAL, each by size. `rows` are Questie's raw
-- reputationReward pairs; `standings` answers a faction's current value (a
-- function or a table; nil reads as 0 and marks the entry `unknown`); `pct`
-- is R.Multiplier's answer. opts (optional): side ("Alliance"/"Horde") or
-- raceBit to drop the other side's factions; store (the calibration store,
-- whose samples override the data for display, entry.observed = true --
-- never a mixed move's, and a spill reads only a share stored as one);
-- levels {quest, player} for the low-level rule; labels for the notes.
function R.Effects(D, questId, rows, standings, pct, opts)
    opts = type(opts) == "table" and opts or {}
    questId = Num(questId)
    pct = Num(pct) or 100
    local labels = opts.labels
    local side = opts.side or (opts.raceBit and R.Side(D, opts.raceBit)) or nil
    local mode = type(D) == "table" and type(D.rules) == "table" and D.rules.spillClamp or "capTop"
    local store = opts.store
    local list, dropped = PrepareRows(D, questId, rows)
    local state, unknown, acc, order = {}, {}, {}, {}
    -- a sample of a move several sources made is never read (MixedSet)
    local mixed = type(store) == "table" and MixedSet(D, list, side) or {}

    local function Current(factionId)
        if state[factionId] == nil then
            local value = StandingOf(standings, factionId)
            if value == nil then unknown[factionId] = true end
            state[factionId] = Clamp(value or 0, D)
        end
        return state[factionId]
    end

    local function Spill(source, gain, full)
        local edges = Edges(D, source)
        if not edges or gain == 0 then return end
        for _, edge in ipairs(edges) do
            local target = type(edge) == "table" and Num(edge[1])
            local rate, maxRankIn = type(edge) == "table" and Num(edge[2]), type(edge) == "table" and Num(edge[3])
            if target and rate and rate ~= 0 and SideOk(D, target, side) then
                maxRankIn = maxRankIn or MAX_RANK
                local current = Current(target)
                local entry = Entry(acc, order, D, target)
                if rate < 0 then entry.rival = true end
                local amount = Trunc(gain * rate)
                -- only a share stored as one: never a DIRECT sample, never a
                -- mixed move (each would be this source's share AND more)
                local observed, kind = ObservedRaw(store, questId, target)
                if observed and gain == full and kind ~= DIRECT and not mixed[target] then
                    amount = Trunc(observed * pct / 100)
                    entry.observed = true
                end
                entry.uncapped = entry.uncapped + amount
                if R.Rank(current) > maxRankIn then
                    Note(entry, "no spillover above " .. RankWord(maxRankIn, labels))
                else
                    local top = R.RankTop(maxRankIn)
                    -- a window that runs to Exalted is the ceiling's business (Move)
                    if mode ~= "mangos" and amount > 0 and top < CeilingOf(D) then
                        if current + amount > top then
                            amount = current < top and top - current or 0
                            Note(entry, "spillover stops at " .. R.FormatNumber(top))
                        end
                    end
                    Move(state, entry, D, target, amount, labels)
                end
            end
        end
    end

    local function Direct(factionId, raw, overridden)
        local entry = Entry(acc, order, D, factionId)
        local observed = ObservedRaw(store, questId, factionId)
        if observed and not mixed[factionId] then
            raw = observed
            entry.observed = true
        end
        local current = Current(factionId)
        local full = RawGain(D, factionId, raw, pct, opts.levels)
        local gain, capped, limit = R.QuestGain(D, questId, factionId, raw, current, pct, opts.levels)
        -- spillover first, from the clamped and boosted gain (SetReputation)
        Spill(factionId, gain, full)
        entry.direct = true
        entry.raw = (entry.raw or 0) + raw
        entry.overridden = entry.overridden or overridden or nil
        entry.uncapped = entry.uncapped + full
        if capped then
            if limit and limit < CeilingOf(D) then
                Note(entry, "this quest stops at " .. R.FormatNumber(limit))
            else
                Note(entry, "at the Exalted cap")
            end
        end
        Move(state, entry, D, factionId, gain, labels)
    end

    for _, row in ipairs(list) do
        if SideOk(D, row[1], side) then Direct(row[1], row[2], row.overridden) end
    end

    -- A faction seen moving in game that neither the data nor the spill rules
    -- name (the Sha'tar on a pledge, say): runtime truth, shown as seen.
    local seen = type(store) == "table" and questId and store[questId]
    if type(seen) == "table" then
        local extra = {}
        for factionId in pairs(seen) do
            factionId = Num(factionId)
            if factionId and not acc[factionId] and not mixed[factionId] and ObservedRaw(store, questId, factionId)
                and SideOk(D, factionId, side) then
                extra[#extra + 1] = factionId
            end
        end
        table.sort(extra)
        for _, factionId in ipairs(extra) do
            local entry = Entry(acc, order, D, factionId)
            entry.extra = true
            Direct(factionId, 0, nil)
        end
    end

    for _, entry in ipairs(order) do
        if entry.direct then
            entry.kind = DIRECT
        elseif entry.rival then
            entry.kind = RIVAL
        else
            entry.kind = SPILL
        end
        entry.rival = nil
        if unknown[entry.factionId] then entry.unknown = true end
        entry[1], entry[2] = entry.factionId, entry.delta
    end
    SortEffects(order)
    order.questId, order.dropped, order.pct = questId, dropped, pct
    return order
end

-- The entry for one faction, or nil
function R.For(effects, factionId)
    factionId = Num(factionId)
    if type(effects) ~= "table" or not factionId then return nil end
    for _, entry in ipairs(effects) do
        if entry.factionId == factionId then return entry end
    end
    return nil
end

-- The biggest DIRECT gain: the faction a row's badge and a rep sort use.
-- Ties go to the entry the effects list puts first.
function R.Primary(effects)
    if type(effects) ~= "table" then return nil end
    local best
    for _, entry in ipairs(effects) do
        if entry.kind == DIRECT and (not best or entry.delta > best.delta) then best = entry end
    end
    if not best then return nil end
    return best.factionId, best.delta
end

-- ---------------------------------------------------------------------------
-- Words and numbers
-- ---------------------------------------------------------------------------

-- labels: an array by standingID (rank + 1), or a function(standingID) -- the
-- adapter's GetText("FACTION_STANDING_LABEL"..n, UnitSex("player")). English
-- when a label is missing. nil for no rank: an unknown standing has no word.
function R.StandingWord(rank, labels)
    rank = Num(rank)
    if not rank then return nil end
    rank = floor(rank)
    if rank < 0 or rank > MAX_RANK then return nil end
    local word
    if type(labels) == "function" then
        word = labels(rank + 1)
    elseif type(labels) == "table" then
        word = labels[rank + 1]
    end
    if type(word) ~= "string" or word == "" then word = R.LABELS[rank + 1] end
    return word
end

function R.WordFor(value, labels)
    return R.StandingWord((R.Rank(value)), labels)
end

-- "1,250"; truncated toward zero; "-302" keeps its sign
function R.FormatNumber(n)
    n = Num(n)
    if not n then return nil end
    n = Trunc(n)
    local negative = n < 0
    local digits = format("%d", negative and -n or n)
    local grouped = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return negative and ("-" .. grouped) or grouped
end

-- "+1,250", "-302", "0"
function R.FormatRep(n)
    n = Num(n)
    if not n then return nil end
    n = Trunc(n)
    if n > 0 then return "+" .. R.FormatNumber(n) end
    return R.FormatNumber(n)
end

-- "Friendly 1,250 / 6,000"; Exalted at the cap reads 999 / 1,000
function R.FormatProgress(value, labels)
    local rank, rankMin, rankMax = R.Rank(value)
    if not rank then return nil end
    local clamped = Clamp(Num(value), nil)
    return format("%s %s / %s", R.StandingWord(rank, labels), R.FormatNumber(clamped - rankMin),
        R.FormatNumber(rankMax - rankMin))
end

-- ---------------------------------------------------------------------------
-- Abbreviations for narrow rows ("+250 HH")
--
-- Built from the names, so a localised client abbreviates its own names; a
-- handful of enUS names have a shorter form players already use. A table
-- built over a set of factions is unique within it: the first claimant in
-- `order` (the picker's, TBC first) keeps a short form, a later one takes a
-- longer form, and the full name is the last resort.
-- ---------------------------------------------------------------------------

local KNOWN_SHORT = {
    ["The Consortium"] = "Cons", ["Netherwing"] = "Neth", ["Sporeggar"] = "Spore", ["Thrallmar"] = "Thrall",
    ["Tranquillien"] = "Tranq", ["Stormwind"] = "SW", ["Ironforge"] = "IF", ["Darnassus"] = "Darn",
    ["Orgrimmar"] = "Org", ["Undercity"] = "UC",
}
local SMALL_WORDS = { ["of"] = true, ["the"] = true, ["and"] = true, ["des"] = true, ["de"] = true, ["la"] = true }

-- the first n characters of a UTF-8 string (never half a character)
local function Prefix(text, n)
    local out, count = {}, 0
    for char in text:gmatch("[%z\1-\127\192-\255][\128-\191]*") do
        count = count + 1
        if count > n then break end
        out[#out + 1] = char
    end
    return table.concat(out)
end

local function Length(text)
    local _, count = text:gsub("[^\128-\191]", "")
    return count
end

local function Words(name)
    local stripped = name:gsub("^[Tt]he%s+", "")
    local words = {}
    for word in stripped:gmatch("[^%s%-,]+") do words[#words + 1] = word end
    return words, stripped
end

function R.Abbrev(name)
    if type(name) ~= "string" or name == "" then return nil end
    if KNOWN_SHORT[name] then return KNOWN_SHORT[name] end
    local words, stripped = Words(name)
    if #words >= 2 then
        local out = {}
        for _, word in ipairs(words) do
            local first = Prefix(word, 1)
            out[#out + 1] = SMALL_WORDS[word:lower()] and first:lower() or first:upper()
        end
        return table.concat(out)
    end
    local word = words[1] or stripped
    if Length(word) <= 9 then return word end
    return Prefix(word, 5)
end

-- the second try after a clash: the first word, whole when it is short
local function LongerAbbrev(name)
    local words, stripped = Words(name)
    local word = words[1] or stripped
    if Length(word) <= 9 then return word end
    return Prefix(word, 6)
end

-- names = { [factionId] = name }; order = the ids that claim first
function R.AbbrevTable(names, order)
    local out, taken, ids, queued = {}, {}, {}, {}
    if type(names) ~= "table" then return out end
    if type(order) == "table" then
        for _, id in ipairs(order) do
            if names[id] and not queued[id] then
                ids[#ids + 1] = id
                queued[id] = true
            end
        end
    end
    local rest = {}
    for id in pairs(names) do
        if not queued[id] then rest[#rest + 1] = id end
    end
    table.sort(rest, function(a, b) return tostring(a) < tostring(b) end)
    for _, id in ipairs(rest) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local name = names[id]
        if type(name) == "string" and name ~= "" then
            local short = R.Abbrev(name)
            if not short or taken[short] then short = LongerAbbrev(name) end
            if not short or short == "" or taken[short] then short = (name:gsub("^[Tt]he%s+", "")) end
            if taken[short] then short = name end
            if taken[short] then short = name .. " " .. tostring(id) end
            taken[short] = true
            out[id] = short
        end
    end
    return out
end

local function NameOf(names, entry)
    local name
    if type(names) == "function" then
        name = names(entry.factionId)
    elseif type(names) == "table" then
        name = names[entry.factionId]
    end
    if type(name) ~= "string" or name == "" then name = entry.name end
    if type(name) ~= "string" or name == "" then name = "faction " .. tostring(entry.factionId) end
    return name
end

-- "+250 Honor Hold" | "+275 The Aldor  -302 The Scryers  +137 The Sha'tar" |
-- "No reputation". A capped DIRECT entry is always shown, even at 0 (the
-- quest is worth nothing to you NOW, and that is the news); a spill that
-- moves nothing is not. opts: compact (abbreviated names, one space between
-- effects), abbrev (a table or function from R.AbbrevTable), max (shown
-- effects, then "and N more"), marks (append "(capped)"; default on unless
-- compact), none (the "No reputation" text).
function R.Line(effects, names, opts)
    opts = type(opts) == "table" and opts or {}
    local compact = opts.compact and true or false
    local marks = opts.marks
    if marks == nil then marks = not compact end
    local shown = {}
    if type(effects) == "table" then
        for _, entry in ipairs(effects) do
            if type(entry) == "table" and Num(entry.delta) and (entry.delta ~= 0 or entry.kind == DIRECT) then
                shown[#shown + 1] = entry
            end
        end
    end
    -- with no table handed in, the line's own names are made unique among
    -- themselves (Booty Bay and Bloodsail Buccaneers are not both "BB")
    local own
    if compact and opts.abbrev == nil then
        local byId, ids = {}, {}
        for _, entry in ipairs(shown) do
            byId[entry.factionId] = NameOf(names, entry)
            ids[#ids + 1] = entry.factionId
        end
        own = R.AbbrevTable(byId, ids)
    end
    local parts = {}
    for _, entry in ipairs(shown) do
        local name = NameOf(names, entry)
        if compact then
            local short
            if type(opts.abbrev) == "function" then
                short = opts.abbrev(entry.factionId, name)
            elseif type(opts.abbrev) == "table" then
                short = opts.abbrev[entry.factionId]
            elseif own then
                short = own[entry.factionId]
            end
            name = (type(short) == "string" and short ~= "") and short or R.Abbrev(name) or name
        end
        local text = R.FormatRep(entry.delta) .. " " .. name
        if marks and entry.capped then text = text .. " (capped)" end
        parts[#parts + 1] = text
    end
    if #parts == 0 then return opts.none or R.NO_REPUTATION end
    local max = Num(opts.max)
    if max and max >= 1 and #parts > max then
        local more = #parts - floor(max)
        local kept = {}
        for i = 1, floor(max) do kept[i] = parts[i] end
        kept[#kept + 1] = "and " .. more .. " more"
        parts = kept
    end
    return table.concat(parts, compact and " " or "  ")
end

-- ---------------------------------------------------------------------------
-- Repeatables and dailies
-- ---------------------------------------------------------------------------

-- gate: a number (offered while value < gate) or { max = n, min = n }.
-- factionId (optional, trailing): the faction the raw value is for, so its
-- quest rate and this quest's reward clamp for it apply.
-- -> { perTurnIn (one turn-in, before any clamp), nextGain (the next one at
--      `current`, clamped), cap (the value turn-ins stop at: the gate's last
--      turn-in, the reward clamp, or 42999), toCap, toNext (turn-ins to the
--      next rank, nil when it is out of this quest's reach), next, nextRank,
--      toExalted, costItem, costCount (the first item), costs ({itemId, count}
--      for every item), costToCap, costToNext, costToExalted (in the first
--      item), open, capped, rotating, conditional }
function R.Repeatable(D, questId, raw, current, pct, gate, factionId)
    questId, factionId = Num(questId), Num(factionId)
    raw = Num(raw) or 0
    current = Clamp(Num(current) or 0, D)
    local gateMax, gateMin
    if type(gate) == "table" then
        gateMax = Num(gate.max or gate.gateMax or gate[1])
        gateMin = Num(gate.min or gate.gateMin or gate[2])
    else
        gateMax = Num(gate)
    end
    local per = RawGain(D, factionId, raw, pct)
    local ceiling = CeilingOf(D)
    local rewardCap = RewardCap(D, questId, factionId)
    local limit = rewardCap and (rewardCap < ceiling and rewardCap or ceiling) or ceiling
    local res = {
        questId = questId, perTurnIn = per, gateMax = gateMax, gateMin = gateMin, rewardCap = rewardCap,
        nextGain = (R.QuestGain(D, questId, factionId, raw, current, pct)),
        rotating = QuestTable(D, "rotating", questId), conditional = QuestTable(D, "conditional", questId),
    }
    -- { itemId, count[, itemId, count ...] }: the first pair is the headline,
    -- `costs` carries every one (Brewfest-style multi-item turn-ins)
    local cost = QuestTable(D, "repeatCost", questId)
    if type(cost) == "table" then
        res.costs = {}
        for i = 1, #cost - 1, 2 do
            local itemId, count = Num(cost[i]), Num(cost[i + 1])
            if itemId and count then res.costs[#res.costs + 1] = { itemId, count } end
        end
        if not res.costs[1] and Num(cost.itemId) and Num(cost.count) then
            res.costs[1] = { Num(cost.itemId), Num(cost.count) }
        end
        if res.costs[1] then res.costItem, res.costCount = res.costs[1][1], res.costs[1][2] end
    end
    res.capped = current >= limit
    res.open = (not gateMin or current >= gateMin) and (not gateMax or current < gateMax) and not res.capped
    res.cap = current
    if per <= 0 or not res.open then
        if per > 0 then res.toCap = 0 end
        return res
    end
    -- offered while value < gateMax, so the last turn-in may carry past it
    local turnIns = ceil((limit - current) / per)
    local stop = limit
    if gateMax and gateMax < limit then
        local byGate = ceil((gateMax - current) / per)
        if byGate < turnIns then
            turnIns = byGate
            stop = current + byGate * per
            if stop > limit then stop = limit end
        end
    end
    res.cap, res.toCap = stop, turnIns
    local rank, _, rankMax = R.Rank(current)
    if rank < MAX_RANK and rankMax <= stop then
        res.toNext, res.next, res.nextRank = ceil((rankMax - current) / per), rankMax, rank + 1
    end
    if stop >= EXALTED then
        res.toExalted = current >= EXALTED and 0 or ceil((EXALTED - current) / per)
    end
    local count = res.costCount
    if count then
        res.costToCap = turnIns * count
        if res.toNext then res.costToNext = res.toNext * count end
        if res.toExalted then res.costToExalted = res.toExalted * count end
    end
    return res
end

-- Today's pick among the rotating "Wanted" dailies: one NORMAL (Nether-Stalker
-- Mah'duun) and one HEROIC (Wind Trader Zhareem) a day. Questie remembers the
-- ones an NPC did NOT offer today (unavailableQuestsDeterminedByTalking); when
-- they leave exactly one candidate of a kind, that is today's. opts.exclude
-- (a set or function) takes quests that could never be offered -- hidden by
-- phase, say -- out of the pool; opts.offered (a set) names one seen offered,
-- in the log or done today, which settles its kind outright.
function R.TodaysRotating(D, unavailable, opts)
    opts = type(opts) == "table" and opts or {}
    local pools = {}
    local rotating = type(D) == "table" and type(D.rotating) == "table" and D.rotating or {}
    local exclude = opts.exclude
    for questId, kind in pairs(rotating) do
        questId = Num(questId)
        local out = false
        if type(exclude) == "function" then
            out = exclude(questId) and true or false
        elseif type(exclude) == "table" then
            out = exclude[questId] and true or false
        end
        if questId and type(kind) == "string" and not out then
            local pool = pools[kind] or { candidates = {}, marked = 0 }
            pools[kind] = pool
            if type(opts.offered) == "table" and opts.offered[questId] then pool.offered = questId end
            if type(unavailable) == "table" and unavailable[questId] then
                pool.marked = pool.marked + 1
            else
                pool.candidates[#pool.candidates + 1] = questId
            end
        end
    end
    local today = {}
    for kind, pool in pairs(pools) do
        if pool.offered then
            today[kind] = pool.offered
        elseif pool.marked > 0 and #pool.candidates == 1 then
            today[kind] = pool.candidates[1]
        end
    end
    return today
end

-- A faction's daily income. dailies = { {questId, raw}, ... } (raw for this
-- faction). Rotating dailies are never summed: at most one of each kind a
-- day, and only today's counts when it is known. Conditional ones (Halaa)
-- are listed, not counted, unless opts.includeConditional. The total is held
-- to the client's daily cap (opts.max, GetMaxDailyQuests, default 25).
-- opts.value (the faction's standing now) holds every gain to what a
-- turn-in pays from there -- the quest's reward clamp and the 42999
-- ceiling, as each row says it -- and the day's total to the room left
-- under the ceiling: at Exalted 999 a daily is worth 0, the same 0 its row
-- shows (2026-10-04 review). Without it, the listed rates.
function R.DailyIncome(D, dailies, pct, opts)
    opts = type(opts) == "table" and opts or {}
    local factionId = Num(opts.factionId)
    local value = Num(opts.value)
    local today = opts.today or R.TodaysRotating(D, opts.unavailable, opts)
    local res = { perDay = 0, count = 0, max = Num(opts.max) or 25, steady = {}, rotating = {}, conditional = {} }
    local counted = {}
    if type(dailies) == "table" then
        for _, daily in ipairs(dailies) do
            local questId = type(daily) == "table" and Num(daily.questId or daily[1])
            local raw = type(daily) == "table" and Num(daily.raw or daily[2])
            if questId and raw then
                local gain
                if value then
                    gain = R.QuestGain(D, questId, factionId, raw, value, pct)
                else
                    gain = RawGain(D, factionId, raw, pct)
                end
                local kind = QuestTable(D, "rotating", questId)
                local condition = QuestTable(D, "conditional", questId)
                if type(kind) == "string" then
                    local pool = res.rotating[kind] or { candidates = 0, best = 0 }
                    res.rotating[kind] = pool
                    pool.candidates = pool.candidates + 1
                    if gain > pool.best then pool.best = gain end
                    if today[kind] == questId then pool.today, pool.gain = questId, gain end
                elseif condition then
                    res.conditional[#res.conditional + 1] = { questId = questId, gain = gain, condition = condition }
                    if opts.includeConditional then counted[#counted + 1] = gain end
                else
                    res.steady[#res.steady + 1] = { questId = questId, gain = gain }
                    counted[#counted + 1] = gain
                end
            end
        end
    end
    for kind, pool in pairs(res.rotating) do
        pool.known = today[kind] ~= nil
        pool.elsewhere = pool.known and not pool.today or nil
        if pool.today then counted[#counted + 1] = pool.gain end
    end
    table.sort(counted, function(a, b) return a > b end)
    for i, gain in ipairs(counted) do
        if i > res.max then break end
        res.perDay = res.perDay + gain
        res.count = i
    end
    if value then
        local room = CeilingOf(D) - Clamp(value, D)
        if res.perDay > room then res.perDay = room > 0 and room or 0 end
    end
    table.sort(res.steady, function(a, b)
        if a.gain ~= b.gain then return a.gain > b.gain end
        return a.questId < b.questId
    end)
    return res
end

-- ---------------------------------------------------------------------------
-- Projection: how far can quests take one faction, in the best order
--
-- plan = { factionId = F,
--   once = { {questId, raw, gateMax?, gateMin?, slot?, name = ?}, ... }
--          -- quests that pay F directly, done once; gateMax: offered only
--          -- while F < gateMax; gateMin: only once F >= gateMin; quests
--          -- sharing a slot are one exclusive choice and count once
--   spillFrom = { {questId, raw, source, name = ?, slot = ?}, ... }
--          -- quests that reach F only as spillover from `source` (the
--          -- Sha'tar from Aldor or Scryers quests); raw is the source's
--          -- listed value; rival sources (Aldor vs Scryers) are one choice,
--          -- and the better one is projected. No gate on the source is
--          -- read here: the caller hands in only the quests the source's
--          -- own projection reaches (the adapter's GateSpill)
--   repeatables = { {questId, raw, gateMax?, gateMin?}, ... },
--   labels = standing labels for the hints }
--
-- The order: spillover first while its window is open (it is capped at the
-- window's top, so everything done before it eats it), each closing quest
-- slotted in just before the spill step that would shut it; then the closing
-- quests still open, soonest-closing first; then the rest, smallest first,
-- each newly opened closing quest as soon as it opens. A quest whose reward
-- clamp sits below the ceiling is ordered with the closing ones (it shrinks
-- as F rises) but never locks. Every turn-in is truncated and clamped on its
-- own. A greedy order, not an exhaustive search: it is exact for the gates
-- TBC actually has (a few 250s under 3000, one spill window).
-- ---------------------------------------------------------------------------

local function ProjectItem(item, kind)
    if type(item) ~= "table" then return nil end
    local raw = Num(item.raw or item[2])
    if not raw then return nil end
    local out = { questId = Num(item.questId or item[1]), raw = raw, name = item.name }
    if kind == "spill" then
        out.source = Num(item.source or item[3])
        out.rate, out.maxRankIn = Num(item.rate), Num(item.maxRankIn)
        out.sourceValue = Num(item.sourceValue)
        out.slot = item.slot
    else
        out.gateMax = Num(item.gateMax or item[3])
        out.gateMin = Num(item.gateMin or item[4])
        out.slot = item.slot
        if out.slot == nil then out.slot = item[5] end
    end
    return out
end

local function ById(a, b) return (a.questId or 0) < (b.questId or 0) end

-- One member per exclusive slot: an open one before a closed one, then the
-- biggest, then the lowest id. Returns the kept items and the other members.
local function PickSlots(items, start)
    local best = {}
    for _, item in ipairs(items) do
        if item.slot ~= nil then
            local current = best[item.slot]
            local open = not item.gateMax or start < item.gateMax
            local currentOpen = current and (not current.gateMax or start < current.gateMax)
            if not current or (open and not currentOpen)
                or (open == currentOpen and (item.raw > current.raw
                    or (item.raw == current.raw and (item.questId or 0) < (current.questId or 0)))) then
                best[item.slot] = item
            end
        end
    end
    local kept, peers = {}, {}
    for _, item in ipairs(items) do
        if item.slot == nil or best[item.slot] == item then
            kept[#kept + 1] = item
        elseif item.questId then
            peers[#peers + 1] = item.questId
        end
    end
    return kept, peers
end

local function HintText(item, labels)
    local gate = item.gateMax
    local rank, rankMin = R.Rank(gate + 1)
    local word = R.StandingWord(rank, labels)
    local where = word
    -- a gate one short of a rank is "before" that rank; anything else names the point
    if gate + 1 ~= rankMin and gate ~= rankMin then
        local _, ownMin = R.Rank(gate)
        where = R.StandingWord((R.Rank(gate)), labels) .. " " .. R.FormatNumber(gate - ownMin)
    end
    local name = (type(item.name) == "string" and item.name ~= "") and ('"' .. item.name .. '"')
        or ("quest " .. tostring(item.questId))
    return "Do " .. name .. " before " .. where, where
end

local function Simulate(D, F, start, pct, once, spill, labels)
    local value = start
    local res = { order = {}, lockedOut = {}, orderHints = {}, hints = {}, unreached = {}, spillOrder = {}, gains = {} }
    local closing, other = {}, {}
    local ceiling = CeilingOf(D)
    local mangos = type(D) == "table" and type(D.rules) == "table" and D.rules.spillClamp == "mangos"
    for _, item in ipairs(once) do
        local copy = {}
        for k, v in pairs(item) do copy[k] = v end
        -- a reward clamp below the ceiling shrinks the quest as F rises (Ally
        -- of the Netherwing pays up to exactly 0): it is ordered like a gate,
        -- soonest first, but is never locked out -- late, it is only worth less
        local cap = RewardCap(D, copy.questId, F)
        copy.closeAt = copy.gateMax
        if cap and cap < ceiling and (not copy.closeAt or cap < copy.closeAt) then copy.closeAt = cap end
        if copy.closeAt then closing[#closing + 1] = copy else other[#other + 1] = copy end
    end
    table.sort(closing, function(a, b)
        if a.closeAt ~= b.closeAt then return a.closeAt < b.closeAt end
        if a.raw ~= b.raw then return a.raw > b.raw end
        return ById(a, b)
    end)
    table.sort(other, function(a, b)
        if a.raw ~= b.raw then return a.raw < b.raw end
        return ById(a, b)
    end)
    local function Open(item)
        return (not item.gateMin or value >= item.gateMin) and (not item.gateMax or value < item.gateMax)
    end
    local function Do(item)
        local gain = R.QuestGain(D, item.questId, F, item.raw, value, pct)
        value = Clamp(value + gain, D)
        item.done, item.gain = true, gain
        res.order[#res.order + 1] = item.questId
        if item.questId then res.gains[item.questId] = gain end
    end
    for _, item in ipairs(closing) do
        if item.gateMax and value >= item.gateMax then
            item.out = true
            res.lockedOut[#res.lockedOut + 1] = item.questId
        end
    end

    -- 1. the spill window, closing quests slotted in just before they shut
    if #spill > 0 then
        local window = { from = value, total = 0, landed = 0 }
        for _, item in ipairs(spill) do
            local top = R.RankTop(item.maxRankIn)
            window["until"] = window["until"] or top
            window.total = window.total + item.amount
            local function Next()
                if not mangos and item.amount > 0 and value + item.amount > top then return value < top and top or value end
                return Clamp(value + item.amount, D)
            end
            while R.Rank(value) <= item.maxRankIn do
                local nextValue = Next()
                local shut
                for _, c in ipairs(closing) do
                    if not c.done and not c.out and Open(c) and nextValue >= c.closeAt then
                        shut = c
                        break
                    end
                end
                if not shut then break end
                Do(shut)
            end
            if R.Rank(value) <= item.maxRankIn then
                local nextValue = Next()
                window.landed = window.landed + (nextValue - value)
                value = nextValue
                res.spillOrder[#res.spillOrder + 1] = item.questId
            end
        end
        window.lost = window.total - window.landed
        window.to = window["until"]
        res.spillWindow = window
    end

    -- 2. everything else; a closing quest as soon as it is open
    local progress = true
    while progress do
        progress = false
        for _, c in ipairs(closing) do
            if not c.done and not c.out then
                if c.gateMax and value >= c.gateMax then
                    c.out = true
                    res.lockedOut[#res.lockedOut + 1] = c.questId
                elseif Open(c) then
                    Do(c)
                    progress = true
                    break
                end
            end
        end
        if not progress then
            for _, item in ipairs(other) do
                if not item.done and Open(item) then
                    Do(item)
                    progress = true
                    break
                end
            end
        end
    end
    for _, c in ipairs(closing) do
        if not c.done and not c.out then
            if c.gateMax and value >= c.gateMax then
                res.lockedOut[#res.lockedOut + 1] = c.questId
            else
                res.unreached[#res.unreached + 1] = c.questId
            end
        end
    end
    for _, item in ipairs(other) do
        if not item.done then res.unreached[#res.unreached + 1] = item.questId end
    end

    -- the closing quests the climb itself would shut: do them first
    for _, c in ipairs(closing) do
        if c.done and c.gateMax and c.gateMax <= value then
            local text, where = HintText(c, labels)
            res.orderHints[#res.orderHints + 1] = text
            res.hints[#res.hints + 1] = { questId = c.questId, name = c.name, gateMax = c.gateMax, before = where, text = text }
        end
    end
    res.reach = value
    return res
end

-- The spill items of one plan, with each one's amount worked out
local function SpillItems(D, F, plan, pct)
    local items = {}
    if type(plan.spillFrom) ~= "table" then return items end
    for _, raw in ipairs(plan.spillFrom) do
        local item = ProjectItem(raw, "spill")
        if item and item.source then
            local rate, maxRankIn = EdgeTo(D, item.source, F)
            rate = item.rate or rate
            maxRankIn = item.maxRankIn or maxRankIn or MAX_RANK
            if rate and rate ~= 0 then
                local gain
                if item.sourceValue then
                    gain = R.QuestGain(D, item.questId, item.source, item.raw, item.sourceValue, pct)
                else
                    gain = RawGain(D, item.source, item.raw, pct)
                end
                item.amount = Trunc(gain * rate)
                item.maxRankIn = maxRankIn
                items[#items + 1] = item
            end
        end
    end
    return items
end

-- The value repeatables can carry F to after the once-only quests
local function RepeatReach(D, F, plan, value, pct)
    if type(plan.repeatables) ~= "table" then return value end
    local items = {}
    for _, raw in ipairs(plan.repeatables) do
        local item = ProjectItem(raw, "repeat")
        if item then items[#items + 1] = item end
    end
    for _ = 1, #items + 1 do
        local moved = false
        for _, item in ipairs(items) do
            local info = R.Repeatable(D, item.questId, item.raw, value, pct, { max = item.gateMax, min = item.gateMin }, F)
            if info.open and info.cap > value then
                value = info.cap
                moved = true
            end
        end
        if not moved then break end
    end
    return value
end

-- -> { reach, rank, toExalted, left, lockedOut = {questId...}, orderHints =
--      {"Do X before Friendly", ...}, hints = {{questId, gateMax, before,
--      text}}, spillWindow = { from, ["until"] (also `to`), total, landed,
--      lost, source } or nil, order, gains = { [questId] = what each
--      once-only quest paid in that order }, unreached, slotPeers,
--      repeatReach, repeatRank }
function R.Project(D, plan, startValue, pct)
    plan = type(plan) == "table" and plan or {}
    local F = Num(plan.factionId)
    local start = Clamp(Num(startValue) or 0, D)
    pct = Num(pct) or 100
    local once = {}
    if type(plan.once) == "table" then
        for _, raw in ipairs(plan.once) do
            local item = ProjectItem(raw, "once")
            if item then once[#once + 1] = item end
        end
    end
    local kept, peers = PickSlots(once, start)

    -- spillover: rival sources are one choice, and an exclusive slot is
    -- settled INSIDE each choice -- the two pledges share a slot, and
    -- choosing the Scryers means taking theirs, so settling the slot first
    -- (the lower id, the Aldor's) would weigh the Scryers without it
    local spill = SpillItems(D, F, plan, pct)
    local function ByAmount(a, b)
        if a.amount ~= b.amount then return a.amount < b.amount end
        return ById(a, b)
    end
    local sources, seen = {}, {}
    for _, item in ipairs(spill) do
        if not seen[item.source] then
            seen[item.source] = true
            sources[#sources + 1] = item.source
        end
    end
    table.sort(sources)
    local choices = { {} } -- each: a set of excluded sources
    for i = 1, #sources do
        for j = i + 1, #sources do
            local a, b = sources[i], sources[j]
            if IsRival(D, a, b) or IsRival(D, b, a) then
                local nextChoices = {}
                for _, choice in ipairs(choices) do
                    if not choice[a] and not choice[b] then
                        local keepA, keepB = {}, {}
                        for k, v in pairs(choice) do keepA[k], keepB[k] = v, v end
                        keepA[b], keepB[a] = true, true
                        nextChoices[#nextChoices + 1] = keepA
                        nextChoices[#nextChoices + 1] = keepB
                    else
                        nextChoices[#nextChoices + 1] = choice
                    end
                end
                choices = nextChoices
            end
        end
    end

    local best, bestSource, bestPeers
    for _, excluded in ipairs(choices) do
        local open = {}
        for _, item in ipairs(spill) do
            if not excluded[item.source] then open[#open + 1] = item end
        end
        local items, spillPeers = PickSlots(open, start)
        table.sort(items, ByAmount)
        local used
        for _, item in ipairs(items) do used = used or item.source end
        local res = Simulate(D, F, start, pct, kept, items, plan.labels)
        if not best or res.reach > best.reach then
            best, bestSource, bestPeers = res, used, spillPeers
        end
    end
    for _, id in ipairs(bestPeers or {}) do peers[#peers + 1] = id end
    if best.spillWindow then best.spillWindow.source = bestSource end
    best.factionId, best.start = F, start
    best.rank = (R.Rank(best.reach))
    best.toExalted = R.ToExalted(best.reach)
    best.left = best.reach - start
    best.slotPeers = peers
    best.spillSource = bestSource
    best.repeatReach = RepeatReach(D, F, plan, best.reach, pct)
    best.repeatRank = (R.Rank(best.repeatReach))
    return best
end
