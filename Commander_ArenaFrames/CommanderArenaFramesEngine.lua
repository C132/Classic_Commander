-- Commander Arena Frames: the reasoning, with no client attached.
--
-- Everything here is a pure function of (what we have been told, what time it
-- is). It never reads a unit, never draws, and never calls a WoW API -- which
-- is what makes it testable under plain luajit (Harness/arenaframes_engine_smoke.lua)
-- and, more usefully, what makes its answers arguable: a diminishing-returns
-- bracket is either right or wrong, and the way to find out should not involve
-- queueing for a game.
--
-- Three things live here, and they are the three the board cannot fake:
--
--   DR      the diminishing-returns ladder per enemy per category. This is the
--           single most-wanted number on an arena frame and the easiest one to
--           get subtly wrong -- see the note on the reset clock below.
--   Book    what each enemy's cooldowns are doing. Learned from the combat log,
--           because the client will not tell you an enemy's cooldowns.
--   Spec    which specialization an enemy has REVEALED. Never inferred from
--           their class; see DATA.SPEC_MARKERS.

CommanderArenaFrames_Engine = CommanderArenaFrames_Engine or {}
local E = CommanderArenaFrames_Engine

local DATA = CommanderArenaFrames_Data
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- ---------------------------------------------------------------------------
-- Lookup indexes, built once from the generated tables.
--
-- Both are keyed by NAME as well as by id, and the reason is the combat log:
-- it reports the exact rank that was cast, and the book only carries the rank
-- a level-70 enemy uses. A rogue who is still levelling, a spell that gained a
-- rank in a patch, a proc that fires an unlisted rank -- all of them arrive as
-- an id the book has never seen and a name it knows perfectly well.
-- ---------------------------------------------------------------------------

local bookById, bookByName = {}, {}

local function IndexBook()
    if next(bookById) then return end
    for classToken, entries in pairs(DATA.ENEMY_BOOK or {}) do
        for _, entry in ipairs(entries) do
            entry.class = classToken
            bookById[entry.id] = entry
            bookByName[classToken .. "\0" .. entry.name] = entry
        end
    end
    for race, entries in pairs(DATA.RACIAL_BOOK or {}) do
        for _, entry in ipairs(entries) do
            entry.race = race
            bookById[entry.id] = entry
            bookByName["\1" .. race .. "\0" .. entry.name] = entry
        end
    end
end

-- The book entry for a spell an enemy just used, or nil. `classToken` and
-- `race` scope the name lookup: "Nature's Swiftness" is a shaman spell and a
-- druid spell with different ids and the same name, and a board that shows the
-- druid's cooldown on the shaman is worse than one that shows neither.
function E.BookEntry(classToken, race, spellId, spellName)
    IndexBook()
    local byId = bookById[spellId]
    if byId then
        -- An id match still has to belong to this enemy: a racial id is
        -- unambiguous, a class id is not once pets enter the log.
        if byId.race then
            if not race or byId.race == race then return byId end
        elseif not classToken or byId.class == classToken then
            return byId
        end
    end
    if not spellName then return nil end
    if classToken then
        local hit = bookByName[classToken .. "\0" .. spellName]
        if hit then return hit end
    end
    if race then
        return bookByName["\1" .. race .. "\0" .. spellName]
    end
    return nil
end

-- Every ability the board could show for this enemy, in book order. Used to
-- lay out a fixed cooldown strip -- fixed so a cooldown appears in the same
-- place every game, which is the only way a strip is readable at a glance.
function E.BookFor(classToken, race)
    IndexBook()
    local out = {}
    for _, entry in ipairs((DATA.ENEMY_BOOK or {})[classToken] or {}) do
        out[#out + 1] = entry
    end
    for _, entry in ipairs((DATA.RACIAL_BOOK or {})[race] or {}) do
        out[#out + 1] = entry
    end
    return out
end

-- ---------------------------------------------------------------------------
-- Diminishing returns.
--
-- The rule that gets implemented wrong: the reset clock starts when the aura
-- FADES, not when it lands. A 6-second Cheap Shot does not put the stun
-- category back to full 15 seconds after the opener -- it does so 15 seconds
-- after the stun ends, 21 seconds in. Boards that stamp the apply are
-- optimistic by exactly the duration of the CC, which is worst precisely where
-- it matters: on the long first cast that opened the ladder.
--
-- The server is explicit about it (Unit.cpp GetDiminishing): the counter only
-- resets when `stack == 0` AND the last stamp -- written on apply and on
-- remove alike -- is older than 15 seconds. `stacks` below is that stack, and
-- it is why two overlapping stuns from two enemies do not start the clock when
-- the first one drops.
--
-- Bracket() answers the question actually being asked, which is about the NEXT
-- cast, not the one that just happened: 1 = full, 2 = half, 3 = quarter,
-- 4 = immune.
-- ---------------------------------------------------------------------------

local DR = {}
DR.__index = DR

function E.NewDR()
    return setmetatable({ state = {} }, DR)
end

-- The DR category a spell belongs to, or nil. LIMIT is deliberately included:
-- Hamstring has no ladder, only the 10s cap, and the board wants to say so
-- rather than pretend the spell is uncategorised.
function E.Category(spellId)
    return (DATA.DR_BY_SPELL or {})[spellId]
end

-- Does this spell actually stop the target ACTING? DR categories answer a
-- different question -- "how long would the next one last" -- and the two come
-- apart on exactly the spells an arena cares about. A rooted mage is still
-- casting at you. A disarmed warrior is still moving, still intercepting,
-- still shield-bashing your heal. A hamstrung anyone is fully operational.
-- Those four diminish and none of them is control.
local NOT_CONTROL = {
    LIMIT = true,       -- Hamstring: a snare, and not even a laddered one
    DISARM = true,      -- no weapon, every ability
    ROOT = true,        -- rooted, not silenced
    ROOT_PROC = true,
}

function E.IsControlAura(spellId)
    if (DATA.CONTROL_EXTRA or {})[spellId] then return true end
    local cat = E.Category(spellId)
    if not cat then return false end
    return not NOT_CONTROL[cat]
end

-- What KIND of control this aura is, or nil for none:
--
--   FULL     they cannot act. Sap, Polymorph, a stun, a fear, a Blind.
--   SILENCE  they can move and swing but not cast. TBC has no diminishing
--            returns on silence at all, so none of these is in DR_BY_SPELL --
--            which means a board that derives control from the DR table alone
--            never draws a locked-out healer, the single most valuable thing
--            an arena board can tell a caster.
--   ROOT     rooted, and still casting at you.
--   DISARM   no weapon.
--
-- Kept separate from IsControlAura, which answers the narrower "can they act
-- at all" and deliberately says no to a root.
function E.ControlKind(spellId)
    local extra = (DATA.CONTROL_EXTRA or {})[spellId]
    if extra then
        return extra ~= true and extra or "FULL"
    end
    local cat = E.Category(spellId)
    if not cat or cat == "LIMIT" then return nil end
    if cat == "DISARM" then return "DISARM" end
    if cat == "ROOT" or cat == "ROOT_PROC" then return "ROOT" end
    return "FULL"
end

-- Worst first, for picking the ONE control a row shows. A sapped rogue who is
-- also snared is sapped; a healer who is feared and silenced is feared,
-- because the fear is the clock being played around.
function E.ControlRank(kind)
    return (DATA.CONTROL_RANK or {})[kind or ""] or 9
end

-- The word a player would use for it mid-fight. Preference order is the
-- specific over the general: the DR category names the effect ("SAPPED",
-- "FEARED"), the kind is the fallback for the ones with no category at all --
-- which in TBC is every silence.
function E.ControlWord(spellId, kind)
    local cat = E.Category(spellId)
    local word = cat and (DATA.CONTROL_LABEL or {})[cat]
    if word then return word end
    if kind == "SILENCE" then return "SILENCED" end
    if kind == "ROOT" then return "ROOTED" end
    if kind == "DISARM" then return "DISARMED" end
    return "CONTROLLED"
end

function E.ControlTint(kind)
    return (DATA.CONTROL_TINT or {})[kind or ""] or { 1, 1, 1 }
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

-- Has this category's 15 seconds run out? Only ever true with nothing from the
-- category still on the target -- an active aura freezes the clock.
local function Expired(entry, now)
    return entry.stacks == 0 and entry.faded and (now - entry.faded) > DATA.DR_RESET
end

-- An aura in a diminishing category landed on `guid`. Returns the category, or
-- nil when the spell does not diminish (so a caller can use the return as the
-- "was this worth recording" test rather than asking twice).
function DR:Applied(guid, spellId, now)
    local cat = E.Category(spellId)
    if not cat then return nil end
    local entry = Entry(self, guid, cat, true)
    if Expired(entry, now) then entry.used = 0 end
    entry.used = min(entry.used + 1, DATA.DR_MAX + 1)
    entry.stacks = entry.stacks + 1
    entry.faded = now          -- stamped on apply too, exactly as the server does
    entry.last = spellId
    return cat
end

-- It fell off -- expired, broken by damage, dispelled or trinketed. All four
-- start the same clock, which is why the board does not care which happened.
function DR:Faded(guid, spellId, now)
    local cat = E.Category(spellId)
    if not cat then return nil end
    local entry = Entry(self, guid, cat, false)
    if not entry then return nil end
    entry.stacks = max(0, entry.stacks - 1)
    entry.faded = now
    return cat
end

-- 1 = the next one lands at full duration, 2 = half, 3 = quarter, 4 = immune.
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
    -- Every writer here stamps `faded`, so this cannot currently be nil -- and
    -- that is exactly what was true of Commander Diminish's ladder until a
    -- second writer was added that did not. A missing clock is "no timer",
    -- never an error thrown out of a strip that redraws every frame.
    if not entry.faded then return nil end
    if Expired(entry, now) then return nil end
    return entry.faded + DATA.DR_RESET
end

-- Is something from this category on them right now? The clock-frozen case.
function DR:Held(guid, cat)
    local entry = Entry(self, guid, cat, false)
    return (entry and entry.stacks or 0) > 0
end

-- Which categories the 10-second PvP cap applies to. Not all of them, and the
-- two exceptions are the server's own (IsDiminishingReturnsGroupDurationLimited
-- lists neither DISARM nor DEATHCOIL): a Disarm runs its full length in an
-- arena, and Death Coil is three seconds anyway. Written as the set that IS
-- capped rather than the two that are not, so a category added later has to be
-- classified deliberately instead of inheriting a cap by silence.
E.CAPPED_IN_PVP = {
    STUN = true, STUN_PROC = true, KIDNEY = true, SLEEP = true,
    ROOT = true, ROOT_PROC = true, FEAR = true, CHARM = true,
    POLY = true, FREEZE = true, BLIND = true, BANISH = true,
    LIMIT = true, DRAGONS = true,
}

-- How long a CC would ACTUALLY last if cast right now: the ladder applied to
-- the spell's own duration, under the 10-second PvP cap. The cap comes first,
-- exactly as the server orders it (ApplyDiminishingToDuration caps, then
-- multiplies), which is why a 20s Polymorph and a 12s Fear both come out at
-- 5s on the second cast rather than 10s and 6s.
function E.PredictDuration(dr, guid, spellId, baseDuration, now)
    local cat = E.Category(spellId)
    if not cat or not baseDuration or baseDuration <= 0 then return baseDuration, nil, 1 end
    local capped = baseDuration
    if E.CAPPED_IN_PVP[cat] and capped > DATA.DR_PVP_CAP then
        capped = DATA.DR_PVP_CAP
    end
    if cat == "LIMIT" then
        -- No ladder at all: the cap is the whole rule.
        return capped, cat, 1
    end
    local bracket = dr and dr:Bracket(guid, cat, now) or 1
    return capped * (DATA.DR_LADDER[bracket] or 1), cat, bracket
end

-- Every category this enemy has open, worst first, for a strip or a tooltip.
-- Categories at full and not counting down are omitted: a board that lists
-- sixteen categories every game has told you nothing.
function DR:Open(guid, now, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    local perUnit = self.state[guid]
    if not perUnit then return out end
    for cat, entry in pairs(perUnit) do
        local bracket = self:Bracket(guid, cat, now)
        if bracket > 1 or entry.stacks > 0 then
            out[#out + 1] = {
                cat = cat, bracket = bracket, held = entry.stacks > 0,
                resetAt = self:ResetAt(guid, cat, now), last = entry.last,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.bracket ~= b.bracket then return a.bracket > b.bracket end
        return a.cat < b.cat
    end)
    return out
end

function DR:Clear(guid)
    self.state[guid] = nil
end

function DR:Wipe()
    for k in pairs(self.state) do self.state[k] = nil end
end

-- ---------------------------------------------------------------------------
-- The enemy cooldown ledger.
--
-- The client tells you nothing about an enemy's cooldowns, so every entry here
-- was witnessed: the combat log said they cast it, and the book says how long
-- that takes to come back. Two consequences the board has to be honest about
-- and usually is not:
--
--   * a cooldown we have never seen used is UNKNOWN, not READY. They may have
--     opened the game with it out of our sight. The board draws those
--     differently, because "their trinket is up" and "we have not seen their
--     trinket" are different bets.
--   * the number is the BASE cooldown. Talents shorten several of them and the
--     log does not say which the enemy took, so a timer that has run out means
--     "it is up, or it has been up for a while" -- never "it is exactly now".
--     Entries carrying a `talent` say so on the tooltip.
-- ---------------------------------------------------------------------------

local Book = {}
Book.__index = Book

function E.NewBook()
    return setmetatable({ state = {} }, Book)
end

-- How close two stamps of the same ability have to be to count as one event.
-- One press of Ice Block reaches the combat log at least twice -- as a
-- SPELL_CAST_SUCCESS and again as the SPELL_AURA_APPLIED that follows it --
-- and a caller that alerts or ANNOUNCES on every stamp says it twice in party
-- chat. The ledger itself does not care (the second write is identical), so
-- the de-duplication belongs here rather than in each caller.
local RESTAMP_WINDOW = 1.5

-- Record a cast. `classToken`/`race` scope the lookup; both may be nil, in
-- which case only an unambiguous id match counts.
--
-- Returns the book entry, plus whether this was a FRESH press rather than the
-- same one arriving down a second channel. Anything with a side effect --
-- a flash, a sound, a line in chat -- must gate on the second return.
function Book:Used(guid, classToken, race, spellId, spellName, now)
    local entry = E.BookEntry(classToken, race, spellId, spellName)
    if not entry then return nil, false end
    local perUnit = self.state[guid]
    if not perUnit then
        perUnit = {}
        self.state[guid] = perUnit
    end
    local previous = perUnit[entry.name]
    local fresh = not (previous and now and previous.at
        and (now - previous.at) < RESTAMP_WINDOW)
    perUnit[entry.name] = { at = now, cd = entry.cd, entry = entry }
    return entry, fresh
end

-- Seconds until `entry` is back, or nil when it is ready. A second return of
-- true means "never seen" rather than "ready" -- the distinction above.
function Book:Remaining(guid, entryName, now)
    local perUnit = self.state[guid]
    local used = perUnit and perUnit[entryName]
    if not used then return nil, true end
    local left = used.at + used.cd - now
    if left <= 0 then return nil, false end
    return left, false
end

-- The whole strip for one enemy, in book order, each row carrying what the
-- board needs to paint it. Order is the book's rather than by time remaining,
-- on purpose: a cooldown that moves position when it is used is a cooldown you
-- have to read rather than glance at.
function Book:Strip(guid, classToken, race, now, out)
    out = out or {}
    for i = #out, 1, -1 do out[i] = nil end
    for _, entry in ipairs(E.BookFor(classToken, race)) do
        local left, unseen = self:Remaining(guid, entry.name, now)
        out[#out + 1] = {
            entry = entry, id = entry.id, name = entry.name, role = entry.role,
            remaining = left, unseen = unseen, ready = (not left) and not unseen,
        }
    end
    return out
end

function Book:Clear(guid)
    self.state[guid] = nil
end

function Book:Wipe()
    for k in pairs(self.state) do self.state[k] = nil end
end

-- ---------------------------------------------------------------------------
-- Specialization, by revelation only.
--
-- Every marker is a spell nothing but that specialization can cast, so seeing
-- one is proof rather than evidence. Until one lands the answer is nil and the
-- board says the class -- which is the honest reading, and the reason this
-- never returns a "probably".
-- ---------------------------------------------------------------------------

local specById

local function IndexSpecs()
    if specById then return end
    specById = {}
    for classToken, specs in pairs(DATA.SPEC_MARKERS or {}) do
        for _, def in ipairs(specs) do
            for _, id in ipairs(def.ids) do
                specById[id] = { class = classToken, spec = def.spec }
            end
        end
    end
end

-- The specialization a spell proves, or nil. Scoped by class so a marker id
-- that also exists on someone else's bar cannot mislabel them.
function E.SpecFromSpell(classToken, spellId)
    IndexSpecs()
    local hit = specById[spellId]
    if not hit then return nil end
    if classToken and hit.class ~= classToken then return nil end
    return hit.spec
end

-- ---------------------------------------------------------------------------
-- Aura meaning. Pure lookups over DATA.AURA_NOTE, kept here so the drawing
-- code asks a question rather than carrying a table.
-- ---------------------------------------------------------------------------

function E.AuraNote(spellId)
    return (DATA.AURA_NOTE or {})[spellId]
end

-- Is the enemy untouchable right now? Returns the note, so a caller can say
-- WHICH immunity -- "Ice Block" and "Cloak of Shadows" mean different things
-- to a warrior and to a mage.
function E.ImmunityNote(spellId)
    local note = E.AuraNote(spellId)
    return (note and note.kind == "IMMUNE") and note or nil
end

local drinkSet, foodSet

function E.IsDrink(spellId)
    if not drinkSet then
        drinkSet = {}
        for _, id in ipairs(DATA.DRINK_IDS or {}) do drinkSet[id] = true end
    end
    return drinkSet[spellId] and true or false
end

function E.IsFood(spellId)
    if not foodSet then
        foodSet = {}
        for _, id in ipairs(DATA.FOOD_IDS or {}) do foodSet[id] = true end
    end
    return foodSet[spellId] and true or false
end

-- Human-readable seconds for a HUD: under ten it is worth a decimal, over a
-- minute it is worth none at all.
function E.FormatTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 60 then
        return string.format("%d:%02d", floor(seconds / 60), floor(seconds % 60))
    end
    if seconds >= 10 then
        return string.format("%d", floor(seconds + 0.5))
    end
    return string.format("%.1f", seconds)
end

-- The same clock squeezed onto an icon. "2:56" is four glyphs and an
-- eighteen-pixel slot holds three, so past a minute the strip rounds UP to
-- whole minutes ("3m" -- it is not back before then) and past an hour to
-- hours; under a minute it reads exactly as the wide form does.
function E.FormatSlotTime(seconds)
    if not seconds or seconds <= 0 then return "" end
    if seconds >= 3600 then return string.format("%dh", ceil(seconds / 3600)) end
    if seconds >= 60 then return string.format("%dm", ceil(seconds / 60)) end
    return E.FormatTime(seconds)
end
