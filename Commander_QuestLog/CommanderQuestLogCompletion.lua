-- Commander Quest Log: the completion engine.
--
-- Everything the Zones tab and the world-map drawer say about a zone -- what
-- counts toward its 100%, what is locked and why, what is gone for good, which
-- quests form a chain and what to do next -- is decided here, in plain Lua over
-- plain tables. No client API, no Questie global, no print, no timer: the
-- adapter (CommanderQuestLogQuestie.lua) turns Questie's database into one
-- "fact" per quest and the character into one "char" table, and this file
-- turns those into a view. That split is the point. The engine is the part
-- with the rules in it, and rules are only trustworthy when a harness can run
-- every one of them under bare luajit without a fake world wrapped round them;
-- it also means the window and the map drawer cannot disagree about a number,
-- because neither of them computes one.
--
-- The traps this file exists to contain:
--
--   * Questie answers ONE reason per quest. IsDoableVerbose returns the first
--     check that fails in its own order, and it checks the level before the
--     prerequisites and the reputation, so a quest that is both too high and
--     behind an unfinished chain reads "level too low" and nothing else. A
--     completionist view that only repeated Questie's word would promise the
--     quest at the next ding and then move it into a chain list. Every locked
--     quest is therefore re-examined here, from its own fields, for every
--     reason that holds; Questie's verdict only picks which one leads.
--   * The same early return hides PERMANENT reasons behind temporary ones: a
--     quest still under its level whose breadcrumb target is already done is
--     reported as level-locked, and becomes "missed" at the ding. Missing
--     beats locking here, so the denominator does not shrink on a level-up.
--   * Exclusive choices. Questie's own Journey counts a quest whose rival was
--     taken as COMPLETED, so picking one of three moves its percentage by two.
--     Here an exclusive group is one SLOT: before the choice one member
--     counts, after it the chosen member counts and the others are missed, and
--     the denominator never moves. Exclusive groups cross zone borders (Area
--     52's seven, the Netherwing drakes), so a choice made in another zone is
--     looked up through peers outside the zone -- they are consulted to learn
--     whether a choice was made, never joined into this zone's slots.
--   * exclusiveTo is ONE-WAY. Questie blocks a quest only when something in
--     its OWN list is done or in the log (IsDoableVerbose, and the preGroup
--     substitution in IsPreQuestGroupFulfilled); a quest that merely appears in
--     somebody else's list is untouched. The data leans on that: 192 one-way
--     pairs in TBC alone, most of them a breadcrumb listing the quest it leads
--     to ("Journey to the Crossroads" lists "Plainstrider Menace", which stays
--     doable). So a member's own list decides whether IT is missed or locked
--     by a choice, a slot is built only from MUTUAL edges, and the adapter's
--     reverse index is used for nothing but a name. Reading the relation both
--     ways called quests missed that Questie offers.
--   * Tiered lines. The Caverns of Time rings come in four lines of four
--     tiers, and each later tier lists the OTHER lines' first quest. Only the
--     first quests form a slot; a later tier FOLLOWS the one first quest its
--     list leaves out, and counts only while that line is the slot's. The
--     denominator is then a line's length both before and after the pledge.
--   * A quest whose only way in is gone is gone too. Questie reports such a
--     quest as waiting on its prerequisite (a temporary verdict), so the
--     engine walks the prerequisites itself: a locked quest whose every
--     preSingle, or any preGroup member, is missed for good is missed, and
--     the walk repeats until nothing changes, so a whole chain behind one
--     lost quest goes with it.
--   * The Aldor and the Scryers. Their rival quests are not missed: in TBC the
--     other side can be ground back up. They get their own bucket, decided by
--     a pure standing comparison (no quest ids written down here), and stay out
--     of the 100% unless the player asks for both sides. The mirror case --
--     the pre-pledge quests gated on staying BELOW Neutral with the side you
--     joined -- is the same rule read through requiredMaxRep.
--   * HIDE_ON_MAP is not "always completable": most of those entries are sets
--     removed in later patches, several mutually exclusive. They are optional.
--   * The percentage FLOORS. 199 of 200 is 99%, never a rounded 100%: the one
--     thing a completionist number must not do is claim the zone is finished.
--   * Zone entries are also Q.BuildList entries, so the window can search,
--     filter and fold them with the machinery the Log already has. BuildList's
--     search walks ipairs(entry.objectives), so every entry carries an empty
--     one; Q.Progress reads numObjectives, so it is 0; and a flat (level or
--     name) list must carry NO header, because BuildList hides any row whose
--     header is folded, and a fold made in the Guide would otherwise swallow
--     rows in a list that has no header row to unfold it from.
--   * Group titles are fold keys (ZoneCollapsed). They are fixed strings, and a
--     chain whose root happens to share a title with another chain or with a
--     fixed group is given a distinct one, or folding one would fold both.
--
-- Ids here are quest ids. The view's areaId is passed through from meta and
-- never interpreted: the areaId / uiMapID split is the adapter's business.

CommanderQuestLog = CommanderQuestLog or {}
local Q = CommanderQuestLog

local C = {}
Q.Completion = C

-- ---------------------------------------------------------------------------
-- Vocabulary
--
-- A quest has a BASE status -- what is true of it for this character -- and a
-- BUCKET, the list it is shown in. They differ for the quests that never
-- count: a daily you can pick up today is AVAILABLE underneath and REPEATABLE
-- on screen. Filters read the base (an ignored quest you could pick up is
-- still "open"); grouping and the count read the bucket.
-- ---------------------------------------------------------------------------

C.STATUS = {
    DONE = "DONE", LOG = "LOG", AVAILABLE = "AVAILABLE", LOCKED = "LOCKED",
    MISSED = "MISSED", RIVAL = "RIVAL",
    REPEATABLE = "REPEATABLE", SEASONAL = "SEASONAL", OPTIONAL = "OPTIONAL",
    IGNORED = "IGNORED", EXTRA = "EXTRA",
}

C.LOCK = {
    LEVEL = "LEVEL", PREREQ = "PREREQ", REP = "REP", PROFESSION = "PROFESSION",
    CHOICE = "CHOICE", OTHER = "OTHER",
}

-- Group (sort) modes for the navigator, in dropdown order, with their labels
C.GROUPS = { "GUIDE", "STATUS", "CHAIN", "LEVEL", "NAME" }
C.GROUP_LABELS = {
    GUIDE = "Guide", STATUS = "By status", CHAIN = "By chain", LEVEL = "By level", NAME = "By name",
}

-- Filters, shaped like Q.FILTERS (keyed, {label, tooltip}); FILTER_ORDER is
-- the button order, because a keyed table has none.
C.FILTERS = {
    ALL = { label = "All", tooltip = "Every quest this zone lists for you, counted toward 100% or not." },
    OPEN = { label = "Open", tooltip = "Quests you can work on now: in your log, or ready to pick up." },
    LOCKED = { label = "Locked", tooltip = "Quests waiting on your level, an earlier quest, reputation, a skill or a choice." },
    DONE = { label = "Done", tooltip = "Quests you have turned in." },
    MISSED = { label = "Missed", tooltip = "Quests this character can no longer get, each with the reason." },
}
C.FILTER_ORDER = { "ALL", "OPEN", "LOCKED", "DONE", "MISSED" }

-- Group titles. These exact strings are what ZoneCollapsed is keyed by, so
-- they are constants rather than prose that someone might reword.
C.GROUP_TITLES = {
    TURN_IN = "Turn in",
    IN_PROGRESS = "In progress",
    PICK_UP = "Pick up now",
    UNLOCKS_LEVEL = "Unlocks with level",
    AFTER_QUEST = "After another quest",
    NEEDS_REP_SKILL = "Needs reputation or skill",
    DONE = "Done",
    IN_LOG = "In your log",
    AVAILABLE = "Available",
    LOCKED = "Locked",
    STANDALONE = "Standalone quests",
    MISSED = "Missed",
    RIVAL = "Other faction",
    REPEATABLE = "Dailies and repeatables",
    SEASONAL = "Seasonal",
    OPTIONAL = "Optional",
    EXTRA = "Also starting here",
    IGNORED = "Ignored",
}

local S, K, T = C.STATUS, C.LOCK, C.GROUP_TITLES
local DONE, LOG, AVAILABLE, LOCKED = S.DONE, S.LOG, S.AVAILABLE, S.LOCKED
local MISSED, RIVAL, REPEATABLE, SEASONAL = S.MISSED, S.RIVAL, S.REPEATABLE, S.SEASONAL
local OPTIONAL, IGNORED, EXTRA = S.OPTIONAL, S.IGNORED, S.EXTRA

-- The four buckets that make up the denominator
local COUNTED = { DONE = true, LOG = true, AVAILABLE = true, LOCKED = true }

function C.IsCountedBucket(bucket) return COUNTED[bucket] and true or false end

-- The uncounted groups, always last and always in this order
local UNCOUNTED_GROUPS = {
    { key = MISSED, title = T.MISSED },
    { key = RIVAL, title = T.RIVAL },
    { key = REPEATABLE, title = T.REPEATABLE },
    { key = SEASONAL, title = T.SEASONAL },
    { key = OPTIONAL, title = T.OPTIONAL },
    { key = EXTRA, title = T.EXTRA },
    { key = IGNORED, title = T.IGNORED },
}

-- ---------------------------------------------------------------------------
-- Questie's verdicts
--
-- One row per DoableStates NAME (QuestieDB.lua:87-121, all 33). The adapter
-- translates Questie's number to the name with a reverse map built from the
-- live enum, so a renumbering in a Questie update cannot shift every row by
-- one. base / lock / reason are the defaults; three rows are refined in
-- Classify (PARENT_INACTIVE, MISSING_REPUTATION, EXCEED_REPUTATION). `bucket`
-- forces the display list for the two states that are about the calendar,
-- not the character. `hide` drops the quest outright: another race or class
-- will never see it, and Questie's own Journey does the same.
-- ---------------------------------------------------------------------------

local STATE_MAP = {
    COMPLETED = { base = DONE, reason = "DONE" },
    QUEST_LOG = { base = LOG, reason = "IN_LOG" },
    AVAILABLE = { base = AVAILABLE, reason = "AVAILABLE" },
    PARENT_ACTIVE = { base = AVAILABLE, reason = "PARENT_ACTIVE" },
    LEVEL_TOO_LOW = { base = LOCKED, lock = K.LEVEL, reason = "LEVEL" },
    NO_PREQUESTSINGLE = { base = LOCKED, lock = K.PREREQ, reason = "PREREQ" },
    NO_PREQUESTGROUP = { base = LOCKED, lock = K.PREREQ, reason = "PREREQ" },
    BREADCRUMB_ACTIVE = { base = LOCKED, lock = K.PREREQ, reason = "BREADCRUMB_ACTIVE" },
    ENABLING_QUEST_MISSING = { base = LOCKED, lock = K.PREREQ, reason = "ENABLING_QUEST" },
    PARENT_INACTIVE = { base = LOCKED, lock = K.PREREQ, reason = "PARENT_INACTIVE" },
    MISSING_REPUTATION = { base = LOCKED, lock = K.REP, reason = "REP" },
    EXCEED_REPUTATION = { base = LOCKED, lock = K.REP, reason = "REP_HIGH" },
    PROFESSION_SKILL = { base = LOCKED, lock = K.PROFESSION, reason = "SKILL" },
    PROFESSION_RANK = { base = LOCKED, lock = K.PROFESSION, reason = "RANK" },
    EXCLUSIVE_COMPLETED = { base = MISSED, reason = "CHOSE_OTHER" },
    EXCLUSIVE_IN_QUEST_LOG = { base = LOCKED, lock = K.CHOICE, reason = "ON_OTHER" },
    NEXTQUESTINCHAIN_ACTIVE_OR_COMPLETED = { base = MISSED, reason = "PAST_IN_CHAIN" },
    BREADCRUMB_FOLLOWUP = { base = MISSED, reason = "SKIPPED_BREADCRUMB" },
    LEVEL_TOO_HIGH = { base = MISSED, reason = "OUTLEVELED" },
    PROFESSION_SPECIALIZATION = { base = MISSED, reason = "PROFESSION" },
    PROFESSION_MISSING = { base = MISSED, reason = "PROFESSION" },
    SPELL_KNOWN = { base = MISSED, reason = "NO_LONGER_OFFERED" },
    DISABLING_QUEST_COMPLETED = { base = MISSED, reason = "NO_LONGER_OFFERED" },
    BLACKLISTED = { base = MISSED, reason = "REMOVED" },
    SPELL_MISSING = { base = LOCKED, lock = K.OTHER, reason = "SPELL" },
    MISSING_ACHIEVEMENT = { base = LOCKED, lock = K.OTHER, reason = "ACHIEVEMENT" },
    DISABLED_BY = { base = LOCKED, lock = K.OTHER, reason = "DISABLED_BY" },
    ARENA_RATING = { base = LOCKED, lock = K.OTHER, reason = "ARENA_RATING" },
    MISSING_DAILY = { base = AVAILABLE, bucket = REPEATABLE, reason = "NOT_TODAY" },
    INACTIVE_DAILY = { base = AVAILABLE, bucket = REPEATABLE, reason = "NOT_TODAY" },
    EVENT_INACTIVE = { base = LOCKED, lock = K.OTHER, bucket = SEASONAL, reason = "EVENT_CLOSED" },
    WRONG_RACE = { hide = true },
    WRONG_CLASS = { hide = true },
}

-- Read-only, for the harness and for /cql status
C.STATE_MAP = STATE_MAP

-- ---------------------------------------------------------------------------
-- Reading the character
--
-- Every char member is optional; a missing function answers "no" (or
-- "unknown" for reputation, which is NOT the same as zero -- an unknown
-- standing never locks anything). Id lists from Questie are arrays, but a
-- set-shaped answer ({[id] = true}) is accepted too, because the reverse
-- exclusive index is naturally a set and nothing here should care.
-- ---------------------------------------------------------------------------

local function Num(value)
    return tonumber(value) or 0
end

local function CharLevel(char)
    local level = tonumber(char and char.level)
    if not level or level < 1 then return 1 end
    return level
end

local function Complete(char, id)
    if not (id and char.isComplete) then return false end
    return char.isComplete(id) and true or false
end

local function InLog(char, id)
    if not (id and char.isInLog) then return false end
    return char.isInLog(id) and true or false
end

local function RepValue(char, factionId)
    if not (factionId and char.repValue) then return nil end
    return tonumber(char.repValue(factionId))
end

-- {id, value} with both numbers, or nil: a reputation ({factionId, value})
-- or a skill ({skillId, value}), copied so the lock never aliases the fact
local function NumberPair(pair)
    if type(pair) ~= "table" then return nil end
    local key, value = tonumber(pair[1]), tonumber(pair[2])
    if not (key and value) then return nil end
    return { key, value }
end

-- Appends the ids of an array OR a set to out, skipping anything in seen
local function AddIds(out, seen, list)
    if type(list) ~= "table" then return end
    for key, value in pairs(list) do
        local id
        if type(value) == "number" then
            id = value
        elseif value == true and type(key) == "number" then
            id = key
        end
        if id and not seen[id] then
            seen[id] = true
            out[#out + 1] = id
        end
    end
end

-- A quest's OWN exclusiveTo list: the fact's when the fact carries one, else
-- the adapter's forward answer (char.exclusiveTo). This is the only list
-- Questie consults, so it is the only one that decides anything here. Sorted,
-- so a set-shaped answer cannot make the output order depend on hashing.
local function ForwardList(char, id, fact)
    local out, seen = {}, { [id] = true }
    if fact and type(fact.exclusiveTo) == "table" then
        AddIds(out, seen, fact.exclusiveTo)
    elseif char.exclusiveTo then
        AddIds(out, seen, char.exclusiveTo(id))
    end
    table.sort(out)
    return out
end

-- Every quest exclusive with id in either direction: the adapter's
-- forward-plus-reverse answer joined with the forward list. For NAMING a
-- choice only, never for deciding one (see the header: the relation is
-- one-way).
local function PeerList(char, id, fact)
    local out, seen = {}, { [id] = true }
    AddIds(out, seen, ForwardList(char, id, fact))
    if char.exclusivePeers then AddIds(out, seen, char.exclusivePeers(id)) end
    table.sort(out)
    return out
end

-- ---------------------------------------------------------------------------
-- Prerequisites
--
-- A mirror of QuestieDB:IsPreQuestSingleFulfilled / IsPreQuestGroupFulfilled
-- (QuestieDB.lua:821-867), returning WHICH ids are unmet instead of a bool:
--
--   preSingle -- satisfied when ANY listed quest is done; nil or empty is
--                satisfied. When unmet, every listed id is unmet ("any of").
--   preGroup  -- EVERY entry must be satisfied. A positive id p is also
--                satisfied by any quest in p's OWN exclusiveTo list being done
--                (you did its alternative); a negative id -p means exactly p,
--                with no substitution.
--
-- The substitution goes through p's forward list only, exactly as Questie's
-- does (QuestieDB.lua:833-847). The data's exclusive groups are NOT listed
-- both ways (see the header), so a quest that merely names p does not stand
-- in for it.
-- ---------------------------------------------------------------------------

-- Returns unmetAll, unmetAny (both arrays, possibly empty)
local function UnmetPrereqs(fact, char)
    local all, any = {}, {}
    local single = fact.preSingle
    if type(single) == "table" and #single > 0 then
        local met = false
        for _, id in ipairs(single) do
            if Complete(char, id) then met = true break end
        end
        if not met then
            for _, id in ipairs(single) do any[#any + 1] = id end
        end
    end
    local group = fact.preGroup
    if type(group) == "table" then
        for _, entryId in ipairs(group) do
            local id = tonumber(entryId)
            if id and id < 0 then
                if not Complete(char, -id) then all[#all + 1] = -id end
            elseif id and id > 0 and not Complete(char, id) then
                local substituted = false
                for _, peer in ipairs(ForwardList(char, id, nil)) do
                    if Complete(char, peer) then substituted = true break end
                end
                if not substituted then all[#all + 1] = id end
            end
        end
    end
    return all, any
end

-- Every prerequisite id a fact names, absolute and de-duplicated, in order
local function PrereqIds(fact)
    local out, seen = {}, {}
    if type(fact) ~= "table" then return out end
    for _, list in ipairs({ fact.preSingle or false, fact.preGroup or false }) do
        if type(list) == "table" then
            for _, value in ipairs(list) do
                local id = tonumber(value)
                if id and id ~= 0 then
                    id = math.abs(id)
                    if not seen[id] then
                        seen[id] = true
                        out[#out + 1] = id
                    end
                end
            end
        end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Reputation
--
-- Questie's comparison (QuestieReputation.lua:156-202): a minimum is met at
-- value >= min, a maximum holds while value < max. A standing the adapter
-- could not read is unknown and never locks; Questie itself treats an
-- undiscovered faction as 0, which is why its verdict and ours can differ for
-- a faction the character has never met, and why its verdict leads.
-- ---------------------------------------------------------------------------

local function RepBelowMin(fact, char)
    local rep = NumberPair(fact.minRep)
    if not rep then return nil end
    local value = RepValue(char, rep[1])
    if value and value < rep[2] then return rep end
    return nil
end

local function RepAboveMax(fact, char)
    local rep = NumberPair(fact.maxRep)
    if not rep then return nil end
    local value = RepValue(char, rep[1])
    if value and value >= rep[2] then return rep end
    return nil
end

-- The rival rule. For a minimum on faction F whose rival is R: the player
-- sided with R when both standings are known and R's is higher. For a maximum
-- on F (the pre-pledge quests offered only while you stay below Neutral with
-- F): the player sided with F itself. Returns the faction the player sided
-- with (or nil), and whether that was only the tie-break.
--
-- The tie-break: a character of any race but the two with a side already
-- starts both at Neutral, and before the pledge both sides' gated quests
-- would count -- so the pledge would then pull a side's worth of quests out
-- of three zones at once. With the standings level, the lower faction id (the
-- Aldor) is the side that counts and the other side's quests are its rivals
-- (TieSide below takes the ones whose gate is already met), so an Aldor
-- pledge moves nothing and a Scryer pledge swaps the two sets.
local function RivalSide(fact, char, useMin, useMax)
    local rivals = char.rivals
    if type(rivals) ~= "table" then return nil end
    if useMin then
        local rep = NumberPair(fact.minRep)
        local other = rep and rivals[rep[1]]
        if other then
            local mine, theirs = RepValue(char, rep[1]), RepValue(char, other)
            if mine and theirs then
                if theirs > mine then return other, false end
                if theirs == mine and other < rep[1] then return other, true end
            end
        end
    end
    if useMax then
        local rep = NumberPair(fact.maxRep)
        local other = rep and rivals[rep[1]]
        if other then
            local mine, theirs = RepValue(char, rep[1]), RepValue(char, other)
            if mine and theirs and mine > theirs then return rep[1], false end
        end
    end
    return nil
end

-- The tie-break for a gate that is already MET at the tie: a {Scryers,
-- Neutral} minimum (Firewing Signets, Synthesis of Power) is met at 0/0 and
-- RivalSide is never asked about it, so both sides' Neutral quests used to
-- count and the pledge pulled half of them out again; and a maximum on the
-- Aldor (Strained Supplies) is the Scryer side's pre-pledge quest, held to
-- the same rule. Only at an exact tie of two known standings, so nothing
-- after the pledge reads any differently. Returns the side that counts.
local function TieSide(fact, char)
    local rivals = char.rivals
    if type(rivals) ~= "table" then return nil end
    local rep = NumberPair(fact.minRep)
    local other = rep and rivals[rep[1]]
    if other then
        local mine, theirs = RepValue(char, rep[1]), RepValue(char, other)
        if mine and theirs and mine == theirs and other < rep[1] then return other end
    end
    rep = NumberPair(fact.maxRep)
    other = rep and rivals[rep[1]]
    if other then
        local mine, theirs = RepValue(char, rep[1]), RepValue(char, other)
        if mine and theirs and mine == theirs and rep[1] < other then return rep[1] end
    end
    return nil
end

-- Standard standing thresholds (barValue, as GetFactionInfoByID answers it)
local STANDINGS = {
    { -42000, "Hated" }, { -6000, "Hostile" }, { -3000, "Unfriendly" }, { 0, "Neutral" },
    { 3000, "Friendly" }, { 9000, "Honored" }, { 21000, "Revered" }, { 42000, "Exalted" },
}

-- The standing a raw reputation value falls in. The game's own words, so
-- "Honored" keeps the client's spelling. An unknown value is NOT Neutral: a
-- faction the character has not met sits at its Faction.db2 base for this
-- race and class (Sporeggar -2500, Kurenai -1200, Netherwing -42000), which
-- the caller hands in as `base`; with neither there is no word to give.
function C.StandingWord(value, base)
    value = tonumber(value) or tonumber(base)
    if not value then return nil end
    local word = STANDINGS[1][2]
    for _, row in ipairs(STANDINGS) do
        if value >= row[1] then word = row[2] end
    end
    return word
end

local function FactionName(char, factionId)
    local name = char.factionName and char.factionName(factionId)
    if type(name) == "string" and name ~= "" then return name end
    return "faction " .. tostring(factionId)
end

-- ---------------------------------------------------------------------------
-- Classification
-- ---------------------------------------------------------------------------

-- questLevel / requiredLevel -1 means "scales to the player". A quest with no
-- level of its own (0) borrows its required level so it sorts and colours
-- somewhere sensible instead of as a grey level-0 row.
function C.EffectiveLevel(fact, char)
    local playerLevel = CharLevel(char)
    local level = Num(fact and fact.questLevel)
    local required = Num(fact and fact.requiredLevel)
    if level == -1 then level = playerLevel end
    if required == -1 then required = playerLevel end
    if level <= 0 and required > 0 then level = required end
    if required < 0 then required = 0 end
    return level, required
end

-- Reasons a quest is gone for good, read from its own fields: the ones
-- Questie's early returns can hide behind a temporary lock. Order mirrors
-- IsDoableVerbose (max level, breadcrumb, then parent and chain).
local function GoneReason(fact, char, playerLevel)
    local maxLevel = Num(fact.requiredMaxLevel)
    if maxLevel > 0 and playerLevel > maxLevel then return "OUTLEVELED" end
    local crumb = Num(fact.breadcrumbFor)
    if crumb > 0 and (Complete(char, crumb) or InLog(char, crumb)) then return "SKIPPED_BREADCRUMB" end
    if fact.oneWayRep and RepAboveMax(fact, char) then return "REP_PAST" end
    local parent = Num(fact.parent)
    if parent > 0 and not InLog(char, parent) and Complete(char, parent) then return "PARENT_DONE" end
    local nextId = Num(fact.nextInChain)
    if nextId > 0 and (Complete(char, nextId) or InLog(char, nextId)) then return "PAST_IN_CHAIN" end
    return nil
end

-- The raw classifier, for a fact Questie gave no verdict on (or a verdict
-- this file does not know). Returns base, lockKind, reasonKey.
local function RawBase(fact, char, playerLevel, required)
    local id = tonumber(fact.id)
    if Complete(char, id) then return DONE, nil, "DONE" end
    if InLog(char, id) then return LOG, nil, "IN_LOG" end
    local gone = GoneReason(fact, char, playerLevel)
    if gone then return MISSED, nil, gone end
    if required > playerLevel then return LOCKED, K.LEVEL, "LEVEL" end
    local all, any = UnmetPrereqs(fact, char)
    if #all > 0 or #any > 0 then return LOCKED, K.PREREQ, "PREREQ" end
    local parent = Num(fact.parent)
    if parent > 0 and not InLog(char, parent) then return LOCKED, K.PREREQ, "PARENT_INACTIVE" end
    if RepBelowMin(fact, char) then return LOCKED, K.REP, "REP" end
    if RepAboveMax(fact, char) then return LOCKED, K.REP, "REP_HIGH" end
    return AVAILABLE, nil, "AVAILABLE"
end

-- Every reason a LOCKED quest is locked (2.4.1). Questie's lockKind adds the
-- details only it could see (it trusted UnitLevel, it knows the skill check).
local function BuildLock(fact, char, kind, reasonKey, playerLevel, required)
    local lock = {}
    if required > playerLevel then lock.level = required end
    local all, any = UnmetPrereqs(fact, char)
    if #all > 0 or #any > 0 then
        lock.prereqAll, lock.prereqAny = all, any
        local prereq = {}
        for _, id in ipairs(all) do prereq[#prereq + 1] = id end
        for _, id in ipairs(any) do prereq[#prereq + 1] = id end
        lock.prereq = prereq
    end
    lock.rep = RepBelowMin(fact, char)
    lock.repMax = RepAboveMax(fact, char)
    if kind == K.LEVEL and not lock.level then
        -- Questie read a lagging UnitLevel, or the adapter's level is ahead
        local raw = Num(fact.requiredLevel)
        lock.level = (required > 0 and required) or (raw > 0 and raw) or nil
    elseif kind == K.REP then
        if reasonKey == "REP_HIGH" then
            lock.repMax = lock.repMax or NumberPair(fact.maxRep)
        else
            lock.rep = lock.rep or NumberPair(fact.minRep)
        end
    elseif kind == K.PROFESSION then
        lock.skill = NumberPair(fact.skill)
        lock.rank = (reasonKey == "RANK") or nil
    elseif kind == K.OTHER then
        lock.other = reasonKey
    end
    return lock
end

-- The first done (or in-log) peer of a quest, for naming the choice. Its own
-- list first: that is the list Questie's verdict came from, and a quest that
-- merely names this one must not be credited with a choice it did not cause.
local function FirstPeer(char, id, fact, test)
    for _, peer in ipairs(ForwardList(char, id, fact)) do
        if test(char, peer) then return peer end
    end
    for _, peer in ipairs(PeerList(char, id, fact)) do
        if test(char, peer) then return peer end
    end
    return nil
end

-- Riding is the one skill Questie keeps a quest in its zone for (zoneDB.lua
-- re-files every other profession quest under the profession), and every
-- character can train it, so "no Riding skill line yet" is a lock, not a
-- quest gone for good
local RIDING_SKILL = 762

local function NeedsRiding(fact)
    local skill = NumberPair(fact.skill)
    return skill ~= nil and skill[1] == RIDING_SKILL
end

-- Classify one fact. Returns nil for a quest that is not shown at all.
function C.Classify(fact, char)
    if type(fact) ~= "table" or not tonumber(fact.id) then return nil end
    char = char or {}
    local opts = char.opts or {}
    local id = tonumber(fact.id)
    local playerLevel = CharLevel(char)
    local level, required = C.EffectiveLevel(fact, char)

    local state = type(fact.state) == "string" and fact.state or nil
    local row = state and STATE_MAP[state] or nil
    if row and row.hide then return nil end

    local base, kind, reasonKey, forced
    if row then
        base, kind, reasonKey, forced = row.base, row.lock, row.reason, row.bucket
        if state == "PARENT_INACTIVE" and Num(fact.parent) > 0 and Complete(char, fact.parent) then
            base, kind, reasonKey = MISSED, nil, "PARENT_DONE"
        elseif state == "EXCEED_REPUTATION" and fact.oneWayRep then
            base, kind, reasonKey = MISSED, nil, "REP_PAST"
        elseif state == "PROFESSION_MISSING" and NeedsRiding(fact) then
            base, kind, reasonKey = LOCKED, K.PROFESSION, "SKILL"
        end
        -- Missing beats locking: a permanent reason Questie's early return
        -- hid behind a temporary one. Not for the calendar rows, whose bucket
        -- already says what they are.
        if base == LOCKED and not forced then
            local gone = GoneReason(fact, char, playerLevel)
            if gone then base, kind, reasonKey = MISSED, nil, gone end
        end
    else
        base, kind, reasonKey = RawBase(fact, char, playerLevel, required)
    end

    local info = {
        id = id, level = level, requiredLevel = required, state = state,
        ready = false, failed = false,
    }

    if base == LOG and char.logInfo then
        local live = char.logInfo(id)
        if type(live) == "table" then
            info.ready = live.complete and true or false
            info.failed = live.failed and true or false
        end
    end

    -- An open quest of the side the tie does not count is that side's too.
    -- Not with both sides counted: there it is simply open.
    if base == AVAILABLE and not opts.countRival and TieSide(fact, char) then
        base, kind, reasonKey = LOCKED, K.REP, "RIVAL"
    end
    if base == LOCKED then
        local lock = BuildLock(fact, char, kind, reasonKey, playerLevel, required)
        -- The rival rule: Questie's verdict for it is MISSING_REPUTATION, but
        -- a rival quest above the player's level reads LEVEL_TOO_LOW first, so
        -- any locked quest whose unmet reputation is the other side's is RIVAL.
        local side, tie = RivalSide(fact, char,
            state == "MISSING_REPUTATION" or lock.rep ~= nil,
            state == "EXCEED_REPUTATION" or lock.repMax ~= nil)
        if not side then
            side = TieSide(fact, char)
            tie = side ~= nil
        end
        if side then
            base, kind = RIVAL, K.REP
            reasonKey = "RIVAL"
            info.rivalSide = side
            info.rivalTie = tie or nil
            lock.rep = lock.rep or NumberPair(fact.minRep)
        end
        info.lock = lock
        if kind == K.CHOICE then
            info.chosen = FirstPeer(char, id, fact, InLog)
            lock.choice = info.chosen
        end
    elseif base == MISSED and reasonKey == "CHOSE_OTHER" then
        info.chosen = FirstPeer(char, id, fact, Complete)
    end

    -- Bucket precedence (first match wins)
    local bucket
    if type(char.ignored) == "table" and char.ignored[id] then
        bucket = IGNORED
    elseif fact.event or forced == SEASONAL then
        bucket = SEASONAL
    elseif fact.repeatable or fact.daily or forced == REPEATABLE then
        bucket = REPEATABLE
    elseif fact.hiddenOnMap and not opts.countOptional then
        bucket = OPTIONAL
    elseif fact.layer == "EXTRA" and not opts.countExtras then
        bucket = EXTRA
    elseif base == RIVAL and opts.countRival then
        bucket = LOCKED
    else
        bucket = base
    end
    if base == RIVAL then info.rival = true end

    info.status, info.base, info.lockKind, info.reasonKey = bucket, base, kind, reasonKey
    info.counted = COUNTED[bucket] and true or false
    return info
end

-- ---------------------------------------------------------------------------
-- Exclusive-choice slots
--
-- exclusiveTo is one-way (see the header), so two things are kept apart:
--
--   who is blocked -- each counted entry is decided by its OWN list, exactly
--       as Questie decides it: a quest in that list done makes the entry
--       MISSED / CHOSE_OTHER, one in the log makes it LOCKED / CHOICE (not
--       counted). A member in the log keeps LOG and a done one keeps DONE
--       whatever its list says: the server let the player take it, and a
--       quest in the log is never called missed. Questie's own verdict says
--       the same thing for the quests it answered; this repeats it for the
--       ones the raw classifier handled and names the choice.
--   what is one slot -- components (union-find) over MUTUAL edges among the
--       zone's counted entries: A lists B and B lists A. While nothing in a
--       component is done, in the log or blocked by a choice, one member
--       counts -- AVAILABLE before LOCKED, then the lowest required level,
--       then the lowest id -- and the rest keep their bucket with counted =
--       false and choiceOf = component size. Once a choice is made, each
--       member stands on its own list: the ones it blocks are out, and any
--       member it does not block is still doable and counts.
--
-- Peers outside the zone (or here but uncounted) are only ever asked "done?"
-- and "in the log?" through a member's own list; they never count for a
-- slot. One here but uncounted (ignored, optional) that is mutual with a
-- member is still one of its choices for the follower test below, so
-- ignoring one ring pledge does not turn its line's tiers, and every other
-- line's, into ordinary quests.
--
-- Followers. A counted entry outside every slot whose own list names nothing
-- but the choices of one undecided slot, and leaves exactly one of them out,
-- FOLLOWS that one: it is the later tier of the line the left-out member
-- starts (the Caverns of Time rings), or a breadcrumb into it (Muren
-- Stormpike, into Vejrek, names the other level-10 warrior quests). It
-- counts only while its line holds the slot; otherwise it reads as one of
-- the slot's choices. A follower in the log or done is never uncounted:
-- its line is the one the player started, so its head takes the slot. After
-- the choice Questie's verdicts take over (the other lines' tiers list the
-- chosen quest), so the denominator is one line's length before and after.
-- ---------------------------------------------------------------------------

local SLOT_RANK = { AVAILABLE = 0, LOCKED = 1, RIVAL = 1 }

local function NameOf(id, char, byId)
    local entry = byId and byId[id]
    if entry and entry.title then return entry.title end
    local name = char.questName and char.questName(id)
    if type(name) == "string" and name ~= "" then return name end
    return nil
end

local function SlotBetter(a, b)
    local ra, rb = SLOT_RANK[a.base] or 2, SLOT_RANK[b.base] or 2
    if ra ~= rb then return ra < rb end
    local la, lb = Num(a.requiredLevel), Num(b.requiredLevel)
    if la ~= lb then return la < lb end
    return a.id < b.id
end

-- One entry against its own list. Returns true when a choice touches it
-- (made, pending, or it is the done / in-log member itself).
local function DecideByOwnList(entry, list, char, byId)
    if entry.base == DONE or entry.base == LOG then return false end
    local doneId, logId
    for _, peer in ipairs(list) do
        if not doneId and Complete(char, peer) then doneId = peer end
        if not logId and InLog(char, peer) then logId = peer end
    end
    if doneId then
        entry.status, entry.base = MISSED, MISSED
        entry.lockKind, entry.lock = nil, nil
        entry.reasonKey = "CHOSE_OTHER"
        entry.chosen, entry.chosenName = doneId, NameOf(doneId, char, byId)
        entry.counted = false
        return true
    end
    if logId then
        entry.status, entry.base = LOCKED, LOCKED
        entry.lockKind = K.CHOICE
        entry.lock = entry.lock or {}
        entry.lock.choice = logId
        entry.reasonKey = "ON_OTHER"
        entry.chosen, entry.chosenName = logId, NameOf(logId, char, byId)
        entry.counted = false
        return true
    end
    return false
end

-- Returns decided, best (the member that holds an undecided slot)
local function ResolveComponent(members, char, byId, forward)
    local decided = false
    for _, entry in ipairs(members) do
        if entry.base == DONE or entry.base == LOG then decided = true end
        if DecideByOwnList(entry, forward[entry.id], char, byId) then decided = true end
    end
    if decided or #members < 2 then return decided, nil end
    local best = members[1]
    for index = 2, #members do
        if SlotBetter(members[index], best) then best = members[index] end
    end
    for _, entry in ipairs(members) do
        entry.slotSize = #members
        if entry ~= best then
            entry.counted = false
            entry.choiceOf = #members
        end
    end
    return false, best
end

-- The one choice of an undecided slot that a follower's list leaves out: nil
-- unless the list names nothing but that slot's choices, all but one. The
-- choices are its members plus any uncounted entry mutual with one (slot.all)
local function LeftOut(list, slot)
    if #list == 0 then return nil end
    local named = {}
    for _, id in ipairs(list) do
        if not slot.has[id] then return nil end
        named[id] = true
    end
    local left
    for _, entry in ipairs(slot.all or slot.members) do
        if not named[entry.id] then
            if left then return nil end
            left = entry
        end
    end
    return left
end

function C.ApplySlots(entries, char)
    char = char or {}
    local byId, member, parent = {}, {}, {}
    for _, entry in ipairs(entries or {}) do
        if not entry.isHeader and entry.id then
            byId[entry.id] = entry
            if entry.counted then
                member[entry.id] = entry
                parent[entry.id] = entry.id
            end
        end
    end

    local function Find(id)
        while parent[id] ~= id do
            parent[id] = parent[parent[id]]
            id = parent[id]
        end
        return id
    end

    local ids, forward, lists = {}, {}, {}
    for id in pairs(member) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        local list = ForwardList(char, id, member[id].fact)
        lists[id] = list
        local set = {}
        for _, peer in ipairs(list) do set[peer] = true end
        forward[id] = set
    end
    -- Mutual edges only: a quest that merely names another is not its rival
    for _, id in ipairs(ids) do
        for _, peer in ipairs(lists[id]) do
            if member[peer] and forward[peer][id] then
                local a, b = Find(id), Find(peer)
                if a ~= b then
                    if a < b then parent[b] = a else parent[a] = b end
                end
            end
        end
    end

    local components, roots = {}, {}
    for _, id in ipairs(ids) do
        local root = Find(id)
        if not components[root] then
            components[root] = {}
            roots[#roots + 1] = root
        end
        local list = components[root]
        list[#list + 1] = member[id]
    end
    local slots = {}
    for _, root in ipairs(roots) do
        local members = components[root]
        local decided, best = ResolveComponent(members, char, byId, lists)
        local has = {}
        for _, entry in ipairs(members) do has[entry.id] = true end
        slots[root] = { members = members, has = has, decided = decided, best = best }
    end

    -- An uncounted entry (ignored, optional) mutual with a member is still
    -- one of that slot's choices for LeftOut -- never its holder. Not a
    -- missed one: a line whose head is gone is no choice at all.
    for _, entry in ipairs(entries or {}) do
        local id = entry.id
        if id and not entry.isHeader and not member[id] and entry.fact and entry.base ~= MISSED then
            for _, peer in ipairs(ForwardList(char, id, entry.fact)) do
                if member[peer] and forward[peer][id] then
                    local slot = slots[Find(peer)]
                    if slot and not slot.has[id] then
                        slot.has[id] = true
                        if not slot.all then
                            slot.all = {}
                            for index, each in ipairs(slot.members) do slot.all[index] = each end
                        end
                        slot.all[#slot.all + 1] = entry
                    end
                    break
                end
            end
        end
    end

    -- Followers: a lone, still-counted entry whose list points into one
    -- undecided slot. The anchor is the first member its list names, which
    -- need not be the first id (that one may be ignored).
    local follow = {}
    for _, root in ipairs(roots) do
        local members = components[root]
        local entry = members[1]
        local list = lists[entry.id]
        local anchor
        for _, peer in ipairs(list) do
            if member[peer] then anchor = peer; break end
        end
        if #members == 1 and entry.counted and anchor then
            local slot = slots[Find(anchor)]
            if slot and #slot.members > 1 and not slot.decided and slot.best then
                local head = LeftOut(list, slot)
                if head then
                    follow[#follow + 1] = { entry = entry, head = head, slot = slot }
                    -- A follower in the log or done: its line is the one
                    -- the player is on, so its head holds the slot
                    if member[head.id] and (entry.base == DONE or entry.base == LOG) then
                        slot.started = slot.started or head
                    end
                end
            end
        end
    end
    for _, root in ipairs(roots) do
        local slot = slots[root]
        local started = slot.started
        if started and slot.best and started ~= slot.best then
            slot.best.counted, slot.best.choiceOf = false, #slot.members
            started.counted, started.choiceOf = true, nil
            slot.best = started
        end
    end
    for _, each in ipairs(follow) do
        local entry, head, slot = each.entry, each.head, each.slot
        entry.follows = head.id
        entry.followsName = NameOf(head.id, char, byId)
        if head ~= slot.best and entry.base ~= DONE and entry.base ~= LOG then
            entry.counted = false
            entry.choiceOf = #slot.members
        end
    end
    return entries
end

-- ---------------------------------------------------------------------------
-- Chains
--
-- Questie has no chain builder (critic 3.6): the graph is ours, from
-- preQuestSingle, |preQuestGroup|, nextQuestInChain and breadcrumbForQuestId.
-- Dailies and seasonal quests are left out -- they hang off a chain without
-- being part of its story, and a "chain" of twelve Netherwing dailies is a
-- list, not a guide. Order inside a component is a topological one that, of
-- the quests ready to go next, always takes the lowest level then the lowest
-- id; whatever a cycle in the data leaves over is appended in the same order,
-- so bad data costs ordering, never a hang or a missing row.
-- ---------------------------------------------------------------------------

local function LevelBefore(a, b)
    local la, lb = Num(a.level), Num(b.level)
    if la ~= lb then return la < lb end
    return a.id < b.id
end

local function OrderComponent(ids, nodes, out)
    local inComp, indegree = {}, {}
    for _, id in ipairs(ids) do
        inComp[id] = true
        indegree[id] = 0
    end
    for _, id in ipairs(ids) do
        for target in pairs(out[id] or {}) do
            if inComp[target] then indegree[target] = indegree[target] + 1 end
        end
    end
    local order, placed = {}, {}
    while true do
        local best
        for _, id in ipairs(ids) do
            if not placed[id] and indegree[id] == 0 and (not best or LevelBefore(nodes[id], nodes[best])) then
                best = id
            end
        end
        if not best then break end
        placed[best] = true
        order[#order + 1] = best
        for target in pairs(out[best] or {}) do
            if inComp[target] then indegree[target] = indegree[target] - 1 end
        end
    end
    local rest = {}
    for _, id in ipairs(ids) do
        if not placed[id] then rest[#rest + 1] = nodes[id] end
    end
    table.sort(rest, LevelBefore)
    for _, entry in ipairs(rest) do order[#order + 1] = entry.id end
    return order
end

function C.BuildChains(entries)
    local nodes, nodeIds = {}, {}
    for _, entry in ipairs(entries or {}) do
        if not entry.isHeader and entry.id then
            entry.chain, entry.chainPos, entry.externalPrereqs = nil, nil, nil
            if entry.status ~= REPEATABLE and entry.status ~= SEASONAL then
                nodes[entry.id] = entry
                nodeIds[#nodeIds + 1] = entry.id
            end
        end
    end
    table.sort(nodeIds)

    local parent, out = {}, {}
    for _, id in ipairs(nodeIds) do parent[id] = id end
    local function Find(id)
        while parent[id] ~= id do
            parent[id] = parent[parent[id]]
            id = parent[id]
        end
        return id
    end
    local function Edge(from, to)
        if from == to or not (nodes[from] and nodes[to]) then return end
        out[from] = out[from] or {}
        out[from][to] = true
        local a, b = Find(from), Find(to)
        if a ~= b then
            if a < b then parent[b] = a else parent[a] = b end
        end
    end

    for _, id in ipairs(nodeIds) do
        local fact = nodes[id].fact or {}
        for _, pre in ipairs(PrereqIds(fact)) do Edge(pre, id) end
        Edge(id, Num(fact.nextInChain))
        Edge(id, Num(fact.breadcrumbFor))
    end

    -- Prerequisites that are not nodes of this zone, for every entry
    for _, entry in ipairs(entries or {}) do
        if not entry.isHeader and entry.id then
            local external = {}
            for _, pre in ipairs(PrereqIds(entry.fact)) do
                if not nodes[pre] then external[#external + 1] = pre end
            end
            if #external > 0 then entry.externalPrereqs = external end
        end
    end

    local components, roots = {}, {}
    for _, id in ipairs(nodeIds) do
        local root = Find(id)
        if not components[root] then
            components[root] = {}
            roots[#roots + 1] = root
        end
        local list = components[root]
        list[#list + 1] = id
    end

    local chains = {}
    for _, root in ipairs(roots) do
        local ids = components[root]
        if #ids > 1 then
            local order = OrderComponent(ids, nodes, out)
            local first = nodes[order[1]]
            local chain = { id = first.id, title = first.title, members = order, done = 0, total = 0 }
            for position, id in ipairs(order) do
                local entry = nodes[id]
                entry.chain, entry.chainPos = chain.id, position
                if entry.counted then
                    chain.total = chain.total + 1
                    if entry.base == DONE then chain.done = chain.done + 1 end
                end
            end
            chains[#chains + 1] = chain
        end
    end
    table.sort(chains, function(a, b)
        local ea, eb = nodes[a.id], nodes[b.id]
        if Num(ea.level) ~= Num(eb.level) then return Num(ea.level) < Num(eb.level) end
        local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
        if ta ~= tb then return ta < tb end
        return a.id < b.id
    end)
    return chains
end

-- ---------------------------------------------------------------------------
-- The zone view
-- ---------------------------------------------------------------------------

local function TitleOf(fact, id)
    if type(fact.name) == "string" and fact.name ~= "" then return fact.name end
    return "Quest " .. tostring(id)
end

local function MakeEntry(fact, info)
    local id = info.id
    return {
        isHeader = false, id = id, key = "id:" .. id, questID = id,
        title = TitleOf(fact, id), level = info.level, requiredLevel = info.requiredLevel,
        status = info.status, base = info.base, lockKind = info.lockKind, lock = info.lock,
        reasonKey = info.reasonKey, state = info.state,
        counted = info.counted, ready = info.ready, failed = info.failed,
        rival = info.rival, rivalSide = info.rivalSide, rivalTie = info.rivalTie, chosen = info.chosen,
        layer = (fact.layer == "EXTRA") and "EXTRA" or "ZONE",
        startsHere = fact.startsHere ~= false, startZoneName = fact.startZoneName,
        starters = fact.starters or {}, finishers = fact.finishers or {}, tag = fact.tag,
        -- Q.BuildList's search walks these and Q.Progress reads the count;
        -- the live objectives of a quest in the log come from Q.ReadDetail
        objectives = {}, numObjectives = 0, numFinished = 0,
        fact = fact,
    }
end

local function NameBefore(a, b)
    local ta, tb = (a.title or ""):lower(), (b.title or ""):lower()
    if ta ~= tb then return ta < tb end
    return a.id < b.id
end

local function LevelNameBefore(a, b)
    local la, lb = Num(a.level), Num(b.level)
    if la ~= lb then return la < lb end
    return NameBefore(a, b)
end

-- Totals over a list of entries (after slots). byStatus counts buckets, so
-- it includes the slot members that share a bucket without counting;
-- countedByStatus counts only what is in the denominator, and its four
-- numbers always add up to `counted` (the breakdown line wants that).
function C.Totals(entries)
    local byStatus = {}
    for _, bucket in pairs(S) do byStatus[bucket] = 0 end
    local countedByStatus = { DONE = 0, LOG = 0, AVAILABLE = 0, LOCKED = 0 }
    local counted, done = 0, 0
    for _, entry in ipairs(entries or {}) do
        if not entry.isHeader then
            byStatus[entry.status] = (byStatus[entry.status] or 0) + 1
            if entry.counted then
                counted = counted + 1
                if entry.base == DONE then done = done + 1 end
                countedByStatus[entry.status] = (countedByStatus[entry.status] or 0) + 1
            end
        end
    end
    return {
        counted = counted, done = done, pct = counted > 0 and done / counted or nil,
        byStatus = byStatus, countedByStatus = countedByStatus,
    }
end

-- ---------------------------------------------------------------------------
-- Prerequisites gone for good
--
-- Questie answers a quest behind a lost prerequisite with NO_PREQUESTSINGLE,
-- a temporary verdict, so without this pass it stays counted and locked for
-- ever: an Aldor who took another Area 52 breadcrumb can never do "Assist
-- Exarch Orelis", the only way into sixteen Netherstorm quests, and the
-- briefing would tell them to complete a quest the Shattrath list calls
-- missed. A prerequisite is gone when it is MISSED in this view, or -- for
-- one outside it -- when the adapter's char.isGone says Questie's own
-- verdict on it is permanent. A preGroup member that a quest in its own
-- exclusive list could still stand in for is never called gone. The walk
-- repeats until nothing moves, so a chain falls with its first link. It
-- runs before the slots, so a gone quest cannot be the one a slot counts.
-- The other Aldor / Scryer side is walked too: its standing can be ground
-- back, a lost pledge or breadcrumb cannot, so "Gated on the faction you did
-- not side with" would promise a way in that is not there -- and with both
-- sides counted, a zone could never finish.
-- ---------------------------------------------------------------------------

local function PrereqGone(id, byId, char)
    local entry = byId[id]
    if entry then return entry.base == MISSED end
    return char.isGone and char.isGone(id) and true or false
end

-- The prerequisite that makes a lock permanent, or nil
local function GoneVia(lock, byId, char)
    for _, id in ipairs(lock.prereqAll or {}) do
        if PrereqGone(id, byId, char) and #ForwardList(char, id, nil) == 0 then return id end
    end
    local any = lock.prereqAny or {}
    if #any == 0 then return nil end
    for _, id in ipairs(any) do
        if not PrereqGone(id, byId, char) then return nil end
    end
    return any[1]
end

local function MarkUnreachable(entries, byId, char)
    local changed = true
    while changed do
        changed = false
        for _, entry in ipairs(entries) do
            if (entry.base == LOCKED or entry.base == RIVAL) and entry.lockKind ~= K.CHOICE and entry.lock
                and entry.status ~= REPEATABLE and entry.status ~= SEASONAL then
                local via = GoneVia(entry.lock, byId, char)
                if via then
                    entry.base, entry.lockKind, entry.lock = MISSED, nil, nil
                    entry.reasonKey, entry.goneVia = "PREREQ_GONE", via
                    entry.rival, entry.rivalSide, entry.rivalTie = nil, nil, nil
                    if entry.status == LOCKED or entry.status == RIVAL then entry.status = MISSED end
                    entry.counted = COUNTED[entry.status] and true or false
                    changed = true
                end
            end
        end
    end
end

function C.BuildZone(facts, char, meta)
    char = char or {}
    meta = meta or {}

    -- One fact per id; a quest in both layers keeps its ZONE copy
    local chosen, ids = {}, {}
    for _, fact in pairs(facts or {}) do
        local id = type(fact) == "table" and tonumber(fact.id) or nil
        if id then
            local held = chosen[id]
            if not held then
                chosen[id] = fact
                ids[#ids + 1] = id
            elseif held.layer == "EXTRA" and fact.layer ~= "EXTRA" then
                chosen[id] = fact
            end
        end
    end
    table.sort(ids)

    local entries, byId = {}, {}
    for _, id in ipairs(ids) do
        local fact = chosen[id]
        local info = C.Classify(fact, char)
        if info then
            local entry = MakeEntry(fact, info)
            entries[#entries + 1] = entry
            byId[id] = entry
        end
    end
    -- Name the peer behind a Questie EXCLUSIVE verdict the way slots do
    for _, entry in ipairs(entries) do
        if entry.chosen and not entry.chosenName then
            entry.chosenName = NameOf(entry.chosen, char, byId)
        end
    end

    MarkUnreachable(entries, byId, char)
    C.ApplySlots(entries, char)
    local chains = C.BuildChains(entries)
    table.sort(entries, LevelNameBefore)

    return {
        areaId = meta.areaId, name = meta.name,
        entries = entries, byId = byId, chains = chains,
        totals = C.Totals(entries),
    }
end

function C.Summary(view)
    local totals = view and view.totals
    if not totals then return { counted = 0, done = 0, pct = nil } end
    return { counted = totals.counted, done = totals.done, pct = totals.pct }
end

-- "69%", floored: 100% only when it is. "--" when nothing counts.
function C.PercentText(pct)
    if type(pct) ~= "number" then return "--" end
    return math.floor(pct * 100 + 1e-9) .. "%"
end

-- "62 / 90  \194\183  69%" (the window) or "62/90 \194\183 69%" (compact, the map drawer)
function C.TotalsText(totals, compact)
    totals = totals or {}
    local counted, done = totals.counted or 0, totals.done or 0
    if compact then
        return string.format("%d/%d \194\183 %s", done, counted, C.PercentText(totals.pct))
    end
    return string.format("%d / %d  \194\183  %s", done, counted, C.PercentText(totals.pct))
end

-- ---------------------------------------------------------------------------
-- Grouping for the navigator
--
-- Output is the Q.Scan shape: header entries, each followed by its quests
-- (whose `header` is set to the group title), ready for Q.BuildList with sort
-- "LOG" -- which keeps this order and applies search, filter and folds.
--
-- LEVEL and NAME return a FLAT list (no headers, every entry.header nil) in
-- ascending level / name order; pass it through BuildList with sort "LOG" to
-- keep that order (BuildList's own LEVEL sort runs highest first). The header
-- is cleared rather than left over from a grouped mode, because BuildList
-- hides a row whose header title is folded even when no header row exists.
--
-- `header` is written onto the view's own entries (BuildList matches quests
-- to header rows through it), so the LAST Group call on a view decides it:
-- group, then BuildList, with nothing regrouping in between. NextUp exists so
-- the overview can read the Guide's order without doing exactly that.
-- ---------------------------------------------------------------------------

local function Distance(entry, pos, areaId)
    if not (entry.startsHere and type(entry.starters) == "table") then return nil end
    local best
    for _, starter in ipairs(entry.starters) do
        local x, y = tonumber(starter.x), tonumber(starter.y)
        local sameMap = not (starter.areaId and areaId) or starter.areaId == areaId
        if x and y and sameMap then
            local dx, dy = x - pos.x, y - pos.y
            local d = math.sqrt(dx * dx + dy * dy)
            if not best or d < best then best = d end
        end
    end
    return best
end

local function SortPickUp(list, opts, areaId)
    local pos = opts.playerPos
    if not (type(pos) == "table" and tonumber(pos.x) and tonumber(pos.y)) then
        table.sort(list, LevelNameBefore)
        return
    end
    pos = { x = tonumber(pos.x), y = tonumber(pos.y) }
    local dist = {}
    for _, entry in ipairs(list) do dist[entry] = Distance(entry, pos, areaId) end
    table.sort(list, function(a, b)
        local da, db = dist[a], dist[b]
        if da and db and da ~= db then return da < db end
        if (da ~= nil) ~= (db ~= nil) then return da ~= nil end
        return LevelNameBefore(a, b)
    end)
end

local function LockLevel(entry)
    return Num(entry.lock and entry.lock.level or entry.requiredLevel)
end

local function Emit(list, key, title, members, chain)
    if #members == 0 then return end
    local header = {
        isHeader = true, title = title, group = key, countMode = "COUNT",
        quests = #members, complete = 0,
    }
    for _, entry in ipairs(members) do
        if entry.base == DONE then header.complete = header.complete + 1 end
    end
    if chain then
        header.countMode = "RATIO"
        header.quests, header.complete = chain.total, chain.done
        header.chainId = chain.id
    end
    list[#list + 1] = header
    for _, entry in ipairs(members) do
        entry.header = title
        list[#list + 1] = entry
    end
end

local function EmitUncounted(list, buckets)
    for _, group in ipairs(UNCOUNTED_GROUPS) do
        local members = buckets[group.key] or {}
        table.sort(members, LevelNameBefore)
        Emit(list, group.key, group.title, members)
    end
end

local function GuideKey(entry)
    local status = entry.status
    if status == LOG then return entry.ready and "TURN_IN" or "IN_PROGRESS" end
    if status == AVAILABLE then return "PICK_UP" end
    if status == LOCKED then
        local kind = entry.lockKind
        if kind == K.LEVEL then return "UNLOCKS_LEVEL" end
        if kind == K.PREREQ or kind == K.CHOICE then return "AFTER_QUEST" end
        return "NEEDS_REP_SKILL"
    end
    return status
end

local GUIDE_COUNTED = { "TURN_IN", "IN_PROGRESS", "PICK_UP", "UNLOCKS_LEVEL", "AFTER_QUEST", "NEEDS_REP_SKILL" }

-- The Guide's buckets, each sorted; shared by Group and NextUp
local function GuideBuckets(view, opts)
    local buckets = {}
    for _, entry in ipairs(view.entries) do
        local key = GuideKey(entry)
        buckets[key] = buckets[key] or {}
        table.insert(buckets[key], entry)
    end
    local chainIndex = {}
    for index, chain in ipairs(view.chains or {}) do chainIndex[chain.id] = index end

    table.sort(buckets.TURN_IN or {}, LevelNameBefore)
    table.sort(buckets.IN_PROGRESS or {}, LevelNameBefore)
    SortPickUp(buckets.PICK_UP or {}, opts, view.areaId)
    table.sort(buckets.UNLOCKS_LEVEL or {}, function(a, b)
        local la, lb = LockLevel(a), LockLevel(b)
        if la ~= lb then return la < lb end
        return NameBefore(a, b)
    end)
    table.sort(buckets.AFTER_QUEST or {}, function(a, b)
        local ca, cb = chainIndex[a.chain] or math.huge, chainIndex[b.chain] or math.huge
        if ca ~= cb then return ca < cb end
        local pa, pb = a.chainPos or 0, b.chainPos or 0
        if pa ~= pb then return pa < pb end
        return LevelNameBefore(a, b)
    end)
    table.sort(buckets.NEEDS_REP_SKILL or {}, LevelNameBefore)
    table.sort(buckets.DONE or {}, LevelNameBefore)
    return buckets
end

local function GroupGuide(view, opts, list)
    local buckets = GuideBuckets(view, opts)
    for _, key in ipairs(GUIDE_COUNTED) do
        Emit(list, key, T[key], buckets[key] or {})
    end
    Emit(list, DONE, T.DONE, buckets[DONE] or {})
    EmitUncounted(list, buckets)
end

local function GroupStatus(view, list)
    local buckets = {}
    for _, entry in ipairs(view.entries) do
        buckets[entry.status] = buckets[entry.status] or {}
        table.insert(buckets[entry.status], entry)
    end
    local logList = buckets[LOG] or {}
    table.sort(logList, function(a, b)
        if a.ready ~= b.ready then return a.ready and true or false end
        return LevelNameBefore(a, b)
    end)
    for _, key in ipairs({ AVAILABLE, LOCKED, DONE }) do table.sort(buckets[key] or {}, LevelNameBefore) end
    Emit(list, LOG, T.IN_LOG, logList)
    Emit(list, AVAILABLE, T.AVAILABLE, buckets[AVAILABLE] or {})
    Emit(list, LOCKED, T.LOCKED, buckets[LOCKED] or {})
    Emit(list, DONE, T.DONE, buckets[DONE] or {})
    EmitUncounted(list, buckets)
end

local function GroupChain(view, list)
    local used = {}
    for _, title in pairs(T) do used[title] = true end
    local placed = {}
    for _, chain in ipairs(view.chains or {}) do
        -- A chain with nothing counted in it (all optional, all extra) is not
        -- worth a header; its quests fall to their own groups below
        if chain.total > 0 then
            local title = chain.title or ("Quest " .. chain.id)
            if used[title] then
                title = title .. " (" .. chain.id .. ")"
                local n = 2
                while used[title] do
                    title = (chain.title or "Quest") .. " (" .. chain.id .. "-" .. n .. ")"
                    n = n + 1
                end
            end
            used[title] = true
            local members = {}
            for _, id in ipairs(chain.members) do
                local entry = view.byId[id]
                if entry then
                    members[#members + 1] = entry
                    placed[entry] = true
                end
            end
            Emit(list, "CHAIN:" .. chain.id, title, members, chain)
        end
    end
    local standalone, buckets = {}, {}
    for _, entry in ipairs(view.entries) do
        if not placed[entry] then
            if COUNTED[entry.status] then
                standalone[#standalone + 1] = entry
            else
                buckets[entry.status] = buckets[entry.status] or {}
                table.insert(buckets[entry.status], entry)
            end
        end
    end
    table.sort(standalone, LevelNameBefore)
    Emit(list, "STANDALONE", T.STANDALONE, standalone)
    EmitUncounted(list, buckets)
end

function C.Group(view, mode, opts)
    opts = opts or {}
    local list = {}
    if not (view and view.entries) then return list end
    if mode == "LEVEL" or mode == "NAME" then
        for _, entry in ipairs(view.entries) do
            entry.header = nil
            list[#list + 1] = entry
        end
        table.sort(list, mode == "LEVEL" and LevelNameBefore or NameBefore)
        return list
    end
    if mode == "STATUS" then
        GroupStatus(view, list)
    elseif mode == "CHAIN" then
        GroupChain(view, list)
    else
        GroupGuide(view, opts, list)
    end
    return list
end

-- The first `count` quests of the Guide's to-do groups (Turn in through
-- Needs reputation or skill: never Done, never an uncounted group), for the
-- overview's NEXT UP list and the map drawer. Unlike Group it does NOT touch
-- entry.header, so it can run between the navigator's Group and BuildList
-- without re-labelling the rows.
function C.NextUp(view, count, opts)
    local out = {}
    if not (view and view.entries) then return out end
    count = count or 6
    local buckets = GuideBuckets(view, opts or {})
    for _, key in ipairs(GUIDE_COUNTED) do
        for _, entry in ipairs(buckets[key] or {}) do
            if #out >= count then return out end
            out[#out + 1] = entry
        end
    end
    return out
end

-- The predicate behind the zone filter buttons. Reads the BASE status, so an
-- ignored quest you could pick up still shows under "Open". Unknown keys pass,
-- like Q.BuildList's own filter.
function C.PassesFilter(entry, key)
    if not entry or entry.isHeader then return true end
    local base = entry.base
    if key == "OPEN" then return base == LOG or base == AVAILABLE end
    if key == "LOCKED" then return base == LOCKED or base == RIVAL end
    if key == "DONE" then return base == DONE end
    if key == "MISSED" then return base == MISSED end
    return true
end

-- ---------------------------------------------------------------------------
-- Words and sentences
--
-- The engine owns the vocabulary; the window and the drawer only colour it.
-- Plain words, never shape glyphs (D11). colourKey is one of good / open /
-- warn / bad / faint, which each surface maps onto its own ink.
-- ---------------------------------------------------------------------------

local LOCK_WORDS = {
    PREREQ = "chain", REP = "rep", PROFESSION = "skill", CHOICE = "choice", OTHER = "locked",
}

local function BaseWord(entry)
    local base = entry.base
    if base == DONE then return "done", "good" end
    if base == LOG then
        if entry.ready then return "ready", "good" end
        if entry.failed then return "failed", "bad" end
        return "log", "open"
    end
    if base == AVAILABLE then return "open", "open" end
    if base == LOCKED then
        if entry.rival then return "rival", "faint" end
        local kind = entry.lockKind
        if kind == K.LEVEL then
            local level = LockLevel(entry)
            return "lv " .. level, "warn"
        end
        if kind == K.CHOICE then return "choice", "faint" end
        return LOCK_WORDS[kind] or "locked", "warn"
    end
    if base == MISSED then return "missed", "bad" end
    if base == RIVAL then return "rival", "faint" end
    return "", "faint"
end

function C.StateWord(entry)
    if not entry then return "", "faint" end
    local status = entry.status
    if status == REPEATABLE then
        if entry.base == LOG or entry.base == DONE then return BaseWord(entry) end
        if entry.base == AVAILABLE and entry.reasonKey ~= "NOT_TODAY" then return "today", "open" end
        return "daily", "faint"
    end
    if status == SEASONAL then
        if entry.base == LOG or entry.base == DONE then return BaseWord(entry) end
        if entry.base == AVAILABLE then return "event", "open" end
        return "event", "faint"
    end
    if status == IGNORED then
        local word = BaseWord(entry)
        return word, "faint"
    end
    return BaseWord(entry)
end

local function Quoted(name) return "\"" .. name .. "\"" end

-- "a", "a and b", "a, b and c"
local function JoinWords(parts, word)
    if #parts == 0 then return "" end
    if #parts == 1 then return parts[1] end
    return table.concat(parts, ", ", 1, #parts - 1) .. " " .. word .. " " .. parts[#parts]
end

local NAME_CAP = 3

local function QuestLabel(id, char, view)
    return Quoted(NameOf(id, char, view and view.byId) or ("quest " .. id))
end

-- Names for a list of ids, each external one with its zone in brackets
-- unless suppressZoneOf names the id whose zone the caller places itself
local function PrereqNames(ids, entry, char, view, word, suppressZoneOf)
    local external = {}
    for _, id in ipairs(entry.externalPrereqs or {}) do external[id] = true end
    local parts = {}
    for index, id in ipairs(ids) do
        if index > NAME_CAP then
            parts[#parts + 1] = (#ids - NAME_CAP) .. " more"
            break
        end
        local label = QuestLabel(id, char, view)
        if external[id] and id ~= suppressZoneOf and char.questZoneName then
            local zone = char.questZoneName(id)
            if type(zone) == "string" and zone ~= "" then label = label .. " (" .. zone .. ")" end
        end
        parts[#parts + 1] = label
    end
    return JoinWords(parts, word)
end

local function PrereqPhrase(entry, char, view, suppressZoneOf)
    local lock = entry.lock or {}
    local all = lock.prereqAll or (not lock.prereqAny and lock.prereq) or {}
    local any = lock.prereqAny or {}
    local phrases = {}
    if #all > 0 then phrases[#phrases + 1] = PrereqNames(all, entry, char, view, "and", suppressZoneOf) end
    if #any > 0 then
        local names = PrereqNames(any, entry, char, view, "or", suppressZoneOf)
        if #all > 0 and #any > 1 then names = "one of " .. names end
        phrases[#phrases + 1] = names
    end
    return table.concat(phrases, " and ")
end

local function RepPhrase(rep, char)
    return C.StandingWord(rep[2]) .. " with " .. FactionName(char, rep[1])
end

local function SkillPhrase(lock, char)
    if lock.rank then return "a higher profession rank" end
    local skill = lock.skill
    if not skill then return "more profession skill" end
    local name = char.skillName and char.skillName(skill[1])
    if type(name) == "string" and name ~= "" then return skill[2] .. " " .. name end
    return "profession skill " .. skill[2]
end

local PREREQ_SENTENCES = {
    BREADCRUMB_ACTIVE = "A breadcrumb to it is in your log; turn that in first.",
    ENABLING_QUEST = "Opens once an earlier quest is picked up or done.",
    PARENT_INACTIVE = "Offered only while its parent quest is in your log.",
}

local OTHER_SENTENCES = {
    SPELL = "Needs a spell you have not learned.",
    ACHIEVEMENT = "Needs an achievement.",
    DISABLED_BY = "Closed while another quest is in your log.",
    ARENA_RATING = "Needs a higher arena rating.",
    EVENT_CLOSED = "Seasonal; the event is closed.",
}

-- The rival sentence. Before the Aldor / Scryers pledge both standings are
-- level and the tie-break (RivalSide) counts one side; saying "the faction
-- you did not side with" to someone who has not sided would be wrong.
local function RivalSentence(entry)
    if entry.rivalTie then
        return "Until you side with the Aldor or the Scryers only one side's quests count, and this is the other side's."
    end
    return "Gated on the faction you did not side with."
end

-- " (Zone)" for a choice's other version when it lives in another zone. Race
-- and faction twins share a title, and "You chose 'X'" on a quest called X
-- tells the player nothing.
local function TwinZone(entry, char, view)
    local zone = entry.chosen and char.questZoneName and char.questZoneName(entry.chosen)
    if type(zone) == "string" and zone ~= "" and zone ~= (view and view.name) then
        return " (" .. zone .. ")"
    end
    return ""
end

local function LockedSentence(entry, char, view)
    local lock = entry.lock or {}
    local kind = entry.lockKind
    if entry.rival then return RivalSentence(entry) end
    if kind == K.CHOICE then
        local name = entry.chosenName or (entry.chosen and NameOf(entry.chosen, char, view and view.byId))
        if name and name == entry.title then
            return "Another version of this quest is in your log" .. TwinZone(entry, char, view)
                .. "; only one can be taken."
        end
        if name then return "You are on " .. Quoted(name) .. "; only one of these can be taken." end
        return "Another quest of this choice is in your log; only one can be taken."
    end
    if kind == K.OTHER then
        return OTHER_SENTENCES[entry.reasonKey] or "Locked for now."
    end
    if kind == K.PREREQ and not lock.prereq then
        return PREREQ_SENTENCES[entry.reasonKey] or "Opens after an earlier quest."
    end
    if kind == K.REP and not lock.rep and lock.repMax then
        return "Only offered below " .. RepPhrase(lock.repMax, char) .. "."
    end

    -- Composable reasons, the primary first
    local order, seen, phrases = { kind, K.LEVEL, K.PREREQ, K.REP, K.PROFESSION }, {}, {}
    local prereqIndex
    local prereqCount = #(lock.prereq or {})
    local single = prereqCount == 1 and lock.prereq[1] or nil
    for _, each in ipairs(order) do
        if each and not seen[each] then
            seen[each] = true
            if each == K.LEVEL and lock.level then
                phrases[#phrases + 1] = "level " .. lock.level
            elseif each == K.PREREQ and prereqCount > 0 then
                phrases[#phrases + 1] = PrereqPhrase(entry, char, view, nil)
                prereqIndex = #phrases
            elseif each == K.REP and lock.rep then
                phrases[#phrases + 1] = RepPhrase(lock.rep, char)
            elseif each == K.PROFESSION and (kind == K.PROFESSION or lock.skill) then
                phrases[#phrases + 1] = SkillPhrase(lock, char)
            end
        end
    end
    if #phrases == 0 then return "Locked for now." end
    if #phrases == 1 and prereqIndex == 1 then
        -- "Complete "X" first (Zone)." -- one quest, its zone after "first"
        local zone
        local external = {}
        for _, id in ipairs(entry.externalPrereqs or {}) do external[id] = true end
        if single and external[single] and char.questZoneName then
            zone = char.questZoneName(single)
            if not (type(zone) == "string" and zone ~= "") then zone = nil end
        end
        local names = single and QuestLabel(single, char, view) or phrases[1]
        return "Complete " .. names .. " first" .. (zone and (" (" .. zone .. ")") or "") .. "."
    end
    return "Needs " .. JoinWords(phrases, "and") .. "."
end

local MISSED_SENTENCES = {
    PAST_IN_CHAIN = "You are past this point in the chain.",
    OUTLEVELED = "You have outlevelled it.",
    PROFESSION = "Needs a profession or specialisation you do not have.",
    NO_LONGER_OFFERED = "No longer offered to you.",
    REMOVED = "Removed from the game.",
    PARENT_DONE = "Its parent quest is already done, so it is no longer offered.",
    REP_PAST = "Your reputation is past the point where it is offered.",
    PREREQ_GONE = "Needs a quest you can no longer get.",
}

local function MissedSentence(entry, char, view)
    local key = entry.reasonKey
    if key == "CHOSE_OTHER" then
        local name = entry.chosenName or (entry.chosen and NameOf(entry.chosen, char, view and view.byId))
        if name and name == entry.title then
            return "You did another version of this quest" .. TwinZone(entry, char, view) .. "."
        end
        if name then return "You chose " .. Quoted(name) .. "." end
        return "You chose another quest in its place."
    end
    if key == "PREREQ_GONE" and entry.goneVia then
        local external = {}
        for _, id in ipairs(entry.externalPrereqs or {}) do external[id] = true end
        local label = QuestLabel(entry.goneVia, char, view)
        if external[entry.goneVia] and char.questZoneName then
            local zone = char.questZoneName(entry.goneVia)
            if type(zone) == "string" and zone ~= "" then label = label .. " (" .. zone .. ")" end
        end
        return "Needs " .. label .. ", which you can no longer get."
    end
    if key == "SKIPPED_BREADCRUMB" then
        local target = Num(entry.fact and entry.fact.breadcrumbFor)
        local name = target > 0 and NameOf(target, char, view and view.byId) or nil
        if name then return "You went straight to " .. Quoted(name) .. "; the breadcrumb is gone." end
        return "You went straight to the quest it leads to; the breadcrumb is gone."
    end
    return MISSED_SENTENCES[key] or "No longer available to you."
end

local function BaseSentence(entry, char, view)
    local base = entry.base
    if base == DONE then return "Done." end
    if base == LOG then
        if entry.ready then return "Ready to turn in." end
        if entry.failed then return "Failed; abandon it and pick it up again." end
        return "In your quest log."
    end
    if base == AVAILABLE then
        if entry.startsHere == false and entry.startZoneName then
            return "Available now; it starts in " .. entry.startZoneName .. "."
        end
        return "Available now."
    end
    if base == LOCKED then return LockedSentence(entry, char, view) end
    if base == MISSED then return MissedSentence(entry, char, view) end
    if base == RIVAL then return RivalSentence(entry) end
    return ""
end

-- One plain sentence (two at most, for the uncounted extras) for the briefing
-- and tooltips. view is optional; it lets in-zone quests be named without
-- asking the adapter.
function C.Reason(entry, char, view)
    if not entry then return "" end
    char = char or {}
    local status = entry.status
    if status == IGNORED then return "Ignored; not part of your 100%." end
    if entry.choiceOf and not entry.counted then
        if entry.follows then
            local name = entry.followsName or NameOf(entry.follows, char, view and view.byId)
            if name then
                return "Follows " .. Quoted(name) .. ", one of " .. entry.choiceOf .. " choices; only one line counts."
            end
        end
        return "One of " .. entry.choiceOf .. " choices; only one counts."
    end
    if status == REPEATABLE then
        if entry.reasonKey == "NOT_TODAY" then return "Not offered today." end
        if entry.base == LOG then return BaseSentence(entry, char, view) end
        local fact = entry.fact or {}
        if fact.daily then return "Daily; not part of your 100%." end
        return "Repeatable; not part of your 100%."
    end
    if status == SEASONAL then
        if entry.reasonKey == "EVENT_CLOSED" then return "Seasonal; the event is closed." end
        if entry.base == LOG or entry.base == DONE then return BaseSentence(entry, char, view) end
        return "Seasonal; the event is on now."
    end
    if status == OPTIONAL then
        return BaseSentence(entry, char, view) .. " Optional; not part of your 100%."
    end
    if status == EXTRA then
        return BaseSentence(entry, char, view) .. " Filed under another heading; not part of your 100%."
    end
    return BaseSentence(entry, char, view)
end
