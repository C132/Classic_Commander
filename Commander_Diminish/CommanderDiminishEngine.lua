-- Commander Diminish: the reasoning, with no client attached.
--
-- Everything here is a pure function of (what we have been told, what time it
-- is). It never reads a unit, never draws, and never calls a WoW API -- which
-- is what lets it run under plain luajit (Harness/diminish_engine_smoke.lua)
-- and, more usefully, what makes its answers arguable: a diminishing-returns
-- bracket is either right or wrong, and finding out should not involve
-- queueing for a game.
--
-- Three things live here:
--
--   DR       the ladder, per person per category. Shared semantics with
--            Commander Arena Frames, because the rules are the server's and
--            there is only one correct reading of them.
--   Roster   who is worth keeping. An arena has three enemies and a fixed set
--            of unit tokens; a battleground has forty and none, so this
--            module's state is keyed by GUID alone and has to forget people
--            on its own or it grows all game.
--   Profile  which categories THIS character can actually open. Derived from
--            the spellbook rather than from a table of classes, which is the
--            only way it stays right across a respec, a new rank, a pet swap,
--            and the eleven alts the account already has.

CommanderDiminish_Engine = CommanderDiminish_Engine or {}
local E = CommanderDiminish_Engine

local DATA = CommanderDiminish_Data
local floor, max, min = math.floor, math.max, math.min

-- ---------------------------------------------------------------------------
-- Categories
-- ---------------------------------------------------------------------------

function E.Category(spellId)
    return (DATA.DR_BY_SPELL or {})[spellId]
end

-- The generated group list is the display order too. Fixed on purpose: a
-- category that changes position when it opens is one you have to read rather
-- than glance at, and glancing is the entire point of a DR strip.
local orderIndex
local function Order()
    if orderIndex then return orderIndex end
    orderIndex = {}
    for i, group in ipairs(DATA.DR_GROUPS or {}) do
        orderIndex[group.key] = i
    end
    return orderIndex
end
E.Order = Order

function E.GroupInfo(key)
    for _, group in ipairs(DATA.DR_GROUPS or {}) do
        if group.key == key then return group end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- The character's own reach.
--
-- The question this answers is "which of these sixteen ladders can I open",
-- and the honest source is the spellbook -- not the class. A frost mage and an
-- arcane mage are the same class and do not have the same answer: only one of
-- them has Dragon's Breath. A warlock's answer depends on which demon is out.
-- A hunter who has not trained Freezing Trap does not have that ladder yet.
--
-- So: hand it every spell id the character can cast (player book AND pet book)
-- and it returns the set of categories those spells fall into. Nothing is
-- assumed, and the answer follows a respec without being told about it.
--
-- `extra` is the manual escape hatch -- a set of category keys the player has
-- asked for regardless. It exists because one thing genuinely IS worth
-- tracking outside your own reach: a partner's CC. The profile is a default,
-- not a cage.
-- ---------------------------------------------------------------------------
function E.Profile(spellIds, extra)
    local cats = {}
    for _, id in ipairs(spellIds or {}) do
        local cat = E.Category(id)
        if cat then cats[cat] = true end
    end
    for key in pairs(extra or {}) do
        cats[key] = true
    end
    return cats
end

-- The profile as an ordered list, for a strip that has to lay out left to
-- right the same way every game.
function E.ProfileList(cats, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    for _, group in ipairs(DATA.DR_GROUPS or {}) do
        if cats[group.key] then out[#out + 1] = group.key end
    end
    return out
end

-- ---------------------------------------------------------------------------
-- The ladder.
--
-- Bracket() answers the question actually being asked, which is about the NEXT
-- cast rather than the one that just happened: 1 = full, 2 = half, 3 = quarter,
-- 4 = immune.
--
-- The reset clock starts when the aura FADES and is FROZEN while anything in
-- the category is still on them. Both halves matter and both are easy to lose:
-- stamp the apply instead and the tracker is optimistic by exactly the length
-- of the CC that opened the category; forget the freeze and two overlapping
-- stuns from two different people start the clock when the first one drops.
-- ---------------------------------------------------------------------------

local DR = {}
DR.__index = DR

function E.NewDR()
    return setmetatable({ state = {}, touched = {} }, DR)
end

local function Entry(self, guid, cat, create)
    local perUnit = self.state[guid]
    if not perUnit then
        if not create then return nil end
        perUnit = {}
        self.state[guid] = perUnit
    end
    local entry = perUnit[cat]
    if not entry and create then
        entry = { used = 0, stacks = 0, faded = nil }
        perUnit[cat] = entry
    end
    return entry
end

-- Has this category's fifteen seconds run out? Only ever true with nothing
-- from the category still on them -- an active aura freezes the clock.
local function Expired(entry, now)
    return entry.stacks == 0 and entry.faded and (now - entry.faded) > DATA.DR_RESET
end

-- An aura in a diminishing category landed on `guid`. Returns the category, or
-- nil when the spell does not diminish -- so a caller can use the return as
-- the "was this worth recording" test rather than asking twice.
--
-- `refresh` is for SPELL_AURA_REFRESH, and the difference is the STACK rather
-- than the count. Re-casting a CC on a target who is still under it is a new
-- cast, so the server increments the ladder -- but there is still only ONE
-- aura on them, and only ONE removal will ever arrive. Counting a refresh as
-- a second stack leaves the category permanently one-deep: `stacks` never
-- returns to zero, the fifteen seconds never start, and the category reads as
-- held for the rest of the game.
function DR:Applied(guid, spellId, now, refresh)
    local cat = E.Category(spellId)
    if not cat then return nil end
    local entry = Entry(self, guid, cat, true)
    if Expired(entry, now) then entry.used = 0 end
    entry.used = min(entry.used + 1, DATA.DR_MAX + 1)
    if not refresh then entry.stacks = entry.stacks + 1 end
    entry.faded = now
    entry.last = spellId
    self.touched[guid] = now
    return cat
end

-- It fell off -- expired, broken by damage, dispelled or trinketed. All four
-- start the same clock, which is why nothing here asks which.
function DR:Faded(guid, spellId, now)
    local cat = E.Category(spellId)
    if not cat then return nil end
    local entry = Entry(self, guid, cat, false)
    if not entry then return nil end
    entry.stacks = max(0, entry.stacks - 1)
    entry.faded = now
    self.touched[guid] = now
    return cat
end

-- ---------------------------------------------------------------------------
-- Checking the model against the server.
--
-- Everything above is inference: the combat log says a CC landed, and the
-- ladder is a MODEL of what the server did with it. The model can be wrong --
-- an event that never arrived, an aura from someone we could not see -- and
-- when it is, it is wrong silently and in the worst possible way: it says
-- "full" and you spend a sheep finding out otherwise.
--
-- But the client knows the answer. An aura on a unit we can address carries
-- the duration the SERVER assigned it, which is the base duration with the
-- cap and the ladder already applied. A 10-second polymorph landed at full; a
-- 5-second one landed at half. That is not a model, it is the server's own
-- arithmetic read back.
--
-- So: learn each spell's full duration by watching (the largest ever seen),
-- and classify a landed CC by its ratio to that. Where this disagrees with
-- the ladder, the observation wins -- and the caller is told, because a
-- disagreement is the single most useful thing this module can report.
-- ---------------------------------------------------------------------------

local learnedFull = {}

function E.ResetLearnedDurations()
    for k in pairs(learnedFull) do learnedFull[k] = nil end
end

function E.LearnedDuration(spellId)
    return learnedFull[spellId]
end

-- Record a duration and return the best "full duration" known for the spell.
-- The first sighting is taken as full, which is wrong exactly when the first
-- CC you ever watch is already diminished -- and self-corrects the moment a
-- longer one lands, because a duration longer than the assumed full IS the
-- new full.
function E.NoteDuration(spellId, duration)
    if not duration or duration <= 0 then return learnedFull[spellId] end
    local known = learnedFull[spellId]
    if not known or duration > known + 0.05 then
        learnedFull[spellId] = duration
        return duration
    end
    return known
end

-- Which rung a landed CC actually came in on: 1 full, 2 half, 3 quarter.
-- nil when there is nothing to compare against yet.
function E.LevelFromDuration(spellId, duration)
    local full = E.NoteDuration(spellId, duration)
    if not full or not duration or duration <= 0 then return nil end
    local ratio = duration / full
    -- Generous bands. The rungs are a factor of two apart, so anything that
    -- lands between them is a measurement problem rather than an ambiguity.
    if ratio > 0.72 then return 1 end
    if ratio > 0.36 then return 2 end
    return 3
end

-- Reconcile the ladder with an aura the client can actually see.
--
-- Returns the level observed, the level the model had predicted for this cast,
-- and whether the ladder was corrected. A caller that logs the disagreement is
-- the whole reason this returns three things.
-- `expiresAt` is when the observed aura is DUE TO END, and it is not optional
-- decoration -- it is the clock.
--
-- Everything else that writes to a ladder entry (Applied, Faded) stamps
-- `faded`, and every reader assumes one is there. Observe did not, and it
-- creates entries: a CC seen on someone whose APPLIED never reached us --
-- sapped out of combat-log range, targeted mid-polymorph, zoned in already
-- under one -- minted a row with `used` counted and no clock at all. That row
-- could never expire (Expired needs a stamp), so the bracket sat wherever the
-- observation put it for the rest of the game, and ResetAt walked straight
-- into an arithmetic-on-nil and took the draw down with it.
--
-- The stamp has to be the aura's EXPIRY rather than the moment it was read,
-- and that is the server's own rule: the fifteen seconds start when the last
-- aura in the category fades. Observation is driven by UNIT_AURA, so nothing
-- re-reads a polymorph that is quietly running its course -- stamping `now`
-- would start the clock while the target is still sheeped and call the
-- category full while they are standing there. Projecting forward to the
-- expiry is right, and a real SPELL_AURA_REMOVED overwrites it unconditionally
-- if the CC is broken early, which is exactly what should happen.
function DR:Observe(guid, spellId, duration, now, expiresAt)
    local cat = E.Category(spellId)
    if not cat then return nil end
    local level = E.LevelFromDuration(spellId, duration)
    if not level then return nil end
    local entry = Entry(self, guid, cat, true)
    -- Never backwards. Applied stamps the moment of the cast, which is always
    -- earlier than the same aura's expiry, and a second observation of an
    -- aura already seen must not pull the clock in.
    local stamp = expiresAt or now
    if not entry.faded or stamp > entry.faded then entry.faded = stamp end
    entry.last = entry.last or spellId
    self.touched[guid] = now
    -- `used` counts casts; the level this cast came in at IS what used should
    -- be afterwards. A cast that landed at half means one landed before it.
    local predicted = entry.used
    local corrected = min(level, DATA.DR_MAX + 1)
    if predicted ~= corrected then
        entry.used = corrected
        return level, predicted, true, cat
    end
    return level, predicted, false, cat
end

function DR:Bracket(guid, cat, now)
    local entry = Entry(self, guid, cat, false)
    if not entry or entry.used == 0 then return 1 end
    if Expired(entry, now) then return 1 end
    return min(entry.used + 1, DATA.DR_MAX + 1)
end

-- What fraction of its full duration the next cast in `cat` would keep.
function DR:Multiplier(guid, cat, now)
    return DATA.DR_LADDER[self:Bracket(guid, cat, now)] or 1
end

-- When this category goes back to full, or nil if it is not counting down --
-- either nothing has been applied, or something in the category is still up,
-- which freezes the clock. A board must draw those two cases differently: one
-- is "clear", the other is "held".
function DR:ResetAt(guid, cat, now)
    local entry = Entry(self, guid, cat, false)
    if not entry or entry.used == 0 then return nil end
    if entry.stacks > 0 then return nil end
    -- An entry with no stamp has no clock to report, and saying so is the only
    -- honest answer. Prune already guards this; ResetAt did not, and every
    -- writer stamping one is an invariant rather than a guarantee -- one that
    -- Observe broke. A missing clock must draw as "no timer", never as an
    -- error thrown out of the middle of a strip that is redrawn every frame.
    if not entry.faded then return nil end
    if Expired(entry, now) then return nil end
    return entry.faded + DATA.DR_RESET
end

-- Is something from this category on them right now? The clock-frozen case.
function DR:Held(guid, cat)
    local entry = Entry(self, guid, cat, false)
    return (entry and entry.stacks or 0) > 0
end

-- The spell that last opened this category on them. A battleground's answer to
-- "who am I actually fighting": a KIDNEY bracket means a rogue is on you even
-- if you never saw them.
function DR:LastSpell(guid, cat)
    local entry = Entry(self, guid, cat, false)
    return entry and entry.last or nil
end

-- One row per category for a strip.
--
-- `cats` is the filter -- the character's profile, ordinarily. `includeFull`
-- decides whether a category at full is drawn at all: with a profile in hand
-- it usually should be (three or four grey icons that light up is a strip you
-- can read at a glance, and it shows you what you HAVE), and without one it
-- must not be, because sixteen empty brackets is not information.
function DR:Strip(guid, now, cats, includeFull, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    local perUnit = self.state[guid]
    local order = Order()

    local function Row(cat)
        local bracket = self:Bracket(guid, cat, now)
        local entry = perUnit and perUnit[cat]
        local held = (entry and entry.stacks or 0) > 0
        if not includeFull and bracket <= 1 and not held then return end
        out[#out + 1] = {
            cat = cat, bracket = bracket, held = held,
            resetAt = self:ResetAt(guid, cat, now),
            last = entry and entry.last or nil,
            open = bracket > 1 or held,
        }
    end

    if cats then
        for _, group in ipairs(DATA.DR_GROUPS or {}) do
            if cats[group.key] then Row(group.key) end
        end
        -- A category outside the profile that is OPEN still gets a row: it is
        -- something being done to this person by someone else, and on your own
        -- row it is the whole story. Filtering it away would be filtering away
        -- the only reason a healer looks at their own DR.
        if perUnit then
            for cat in pairs(perUnit) do
                if not cats[cat] then
                    local bracket = self:Bracket(guid, cat, now)
                    if bracket > 1 or self:Held(guid, cat) then Row(cat) end
                end
            end
        end
    elseif perUnit then
        for cat in pairs(perUnit) do Row(cat) end
    end

    table.sort(out, function(a, b)
        return (order[a.cat] or 99) < (order[b.cat] or 99)
    end)
    return out
end

-- Is there anything on this person worth drawing at all?
function DR:HasOpen(guid, now)
    local perUnit = self.state[guid]
    if not perUnit then return false end
    for cat in pairs(perUnit) do
        if self:Bracket(guid, cat, now) > 1 or self:Held(guid, cat) then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Forgetting people.
--
-- An arena tracker never needs this: five seats, and the game ends. A
-- battleground hands you a combat log carrying forty enemies, and a table
-- keyed by GUID that only ever grows is a memory leak with a scoreboard.
--
-- The rule is the same one the ladder uses, plus a grace period: once every
-- category on someone has been reset for `grace` seconds, there is nothing
-- left to remember about them, because the next CC starts a fresh ladder
-- whether or not we kept the row.
-- ---------------------------------------------------------------------------
function DR:Prune(now, grace)
    grace = grace or 10
    local cutoff = DATA.DR_RESET + grace
    local dropped = 0
    for guid, perUnit in pairs(self.state) do
        local alive = false
        for _, entry in pairs(perUnit) do
            if entry.stacks > 0 or not entry.faded or (now - entry.faded) <= cutoff then
                alive = true
                break
            end
        end
        if not alive then
            self.state[guid] = nil
            self.touched[guid] = nil
            dropped = dropped + 1
        end
    end
    return dropped
end

-- Everyone with something open, most recently touched first, capped at
-- `limit`. This is the battleground answer to a board with no unit tokens: you
-- feared someone and swapped target, and their fear ladder is still the thing
-- you need to see.
function DR:Recent(now, limit, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    for guid in pairs(self.state) do
        if self:HasOpen(guid, now) then
            out[#out + 1] = guid
        end
    end
    local touched = self.touched
    table.sort(out, function(a, b)
        return (touched[a] or 0) > (touched[b] or 0)
    end)
    for i = #out, (limit or 5) + 1, -1 do out[i] = nil end
    return out
end

-- Is anything at all remembered about this person? The pruner's companion:
-- a caller keeping its own per-GUID table (names, classes) needs to drop a row
-- exactly when the ladder state behind it goes, and should not have to reach
-- into this one to find out.
function DR:Knows(guid)
    return self.state[guid] ~= nil
end

function DR:Clear(guid)
    self.state[guid] = nil
    self.touched[guid] = nil
end

function DR:Wipe()
    for k in pairs(self.state) do self.state[k] = nil end
    for k in pairs(self.touched) do self.touched[k] = nil end
end

function DR:Count()
    local n = 0
    for _ in pairs(self.state) do n = n + 1 end
    return n
end

-- ---------------------------------------------------------------------------
-- How long the next one would actually last.
--
-- The cap comes first, exactly as the server orders it
-- (ApplyDiminishingToDuration caps, then multiplies), which is why a 20s
-- Polymorph and a 12s Fear both come out at 5s on the second cast rather than
-- 10s and 6s.
-- ---------------------------------------------------------------------------
function E.PredictDuration(dr, guid, spellId, baseDuration, now)
    local cat = E.Category(spellId)
    if not cat or not baseDuration or baseDuration <= 0 then return baseDuration, nil, 1 end
    local capped = baseDuration
    if DATA.CAPPED_IN_PVP[cat] and capped > DATA.DR_PVP_CAP then
        capped = DATA.DR_PVP_CAP
    end
    if cat == "LIMIT" then
        -- No ladder at all: the cap is the whole rule.
        return capped, cat, 1
    end
    local bracket = dr and dr:Bracket(guid, cat, now) or 1
    return capped * (DATA.DR_LADDER[bracket] or 1), cat, bracket
end

-- ---------------------------------------------------------------------------
-- Formatting
-- ---------------------------------------------------------------------------

-- Under ten seconds a decimal is worth having; over it is noise.
function E.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 10 then return string.format("%d", floor(seconds + 0.5)) end
    return string.format("%.1f", seconds)
end

return E
