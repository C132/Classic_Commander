-- Commander Meters: the ARENA match engine — both teams, every seat, the
-- whole match, replayable.
--
-- The core engine (CommanderMetersEngine) records the GROUP's story: your
-- side of a fight, attributed and segmented. An arena is a different
-- question. There are two teams of two to five players in a box small
-- enough that the combat log sees nearly everything, the match has a
-- beginning (the gates), an end (a winner), and a result that costs
-- rating — and the enemy's numbers matter exactly as much as yours. So
-- this file keeps a MATCH record: two teams, every player on both, and
-- everything that happened between them, with the clock kept so any
-- moment can be revisited.
--
-- Like the core engine it is pure: no frames, no unit reads, no WoW API.
-- The window layer feeds it (rosters from the arena/party tokens, HP
-- snapshots, combat-log events, the scoreboard at the end) and asks it
-- questions; timing flows through combat-log timestamps plus an explicit
-- now, so the luajit harness replays fixtures byte-identically.
--
-- What a seat records, in one place:
--   * Damage done = landed + absorbed (the core engine's rule), healing =
--     effective + absorbs credited via SPELL_ABSORBED, damage taken.
--   * CC applied and taken, with the DR bracket the cast landed at (full /
--     half / quarter), its real duration from apply to fade, who broke it
--     early, and casts that hit an immune target (wasted CC). Bracket
--     rules are the server's: the 15 s reset clock starts when the aura
--     FADES and is frozen while anything in the category is still on them.
--   * Interrupts (kicks) and what they stopped; dispels split into
--     friendly dispels and offensive purges/steals.
--   * Kills (the last hit before a death), deaths, casts (APM), mana
--     drained and drunk, trinkets, and every book cooldown seen — the
--     book is Commander Arena Frames' when it is installed.
--   * Per-second series (damage, healing, taken, casts) and HP snapshots,
--     so the replay can show the state of the board at any second.
--   * A bounded ledger of MOMENTS — the discrete events worth reading in
--     a timeline — in the order they happened.
--
-- Pets fold into their owners exactly once, from SPELL_SUMMON plus the
-- token-fed owner map (arenapetN → arenaN, partypetN → partyN); a minion
-- with no known owner is skipped and counted as an anomaly, never guessed.

CommanderMetersArena = {}
local A = CommanderMetersArena

local band = bit.band
local floor = math.floor
local max = math.max
local min = math.min

-- ---------------------------------------------------------------------------
-- Tuning constants (deliberately not settings)
-- ---------------------------------------------------------------------------

local MAX_MATCHES = 20         -- matches kept in the session ring
local LEDGER_CAP = 4000        -- moments per match; past it, only deaths and END land
local SERIES_CAP = 1800        -- 30 min of 1 s buckets per seat
local NAME_CAP = 40            -- distinct ability/target names per map
local OTHER_NAMES = "(other)"
local KILL_WINDOW = 6          -- s: the last hit within this window is the killing blow
local KILL_CC_WINDOW = 10      -- s: controls on the victim's teammates this long before a kill
local CC_OPEN_CAP = 12         -- s: a CC never seen fading is closed at this length
                               -- (TBC's PvP cap is 10 s; nothing controlling lasts longer)
local DRINK_OPEN_CAP = 30      -- s: same for a drink
local DR_RESET = 15            -- s after FADE before a category resets
local CAST_CAP = 1500          -- cast records per seat (starts + instants)
local AURA_CAP = 600           -- buff/debuff intervals per seat (the store's weight is here)
local CAST_OPEN_CAP = 10       -- s: a cast never seen ending is closed at this length
local GCD = 1.5                -- s: the global cooldown the replay draws after a cast
local TARGET_MEMORY = 8        -- s: a cast's target counts as "who they are on" this long
local RATED_TEAMS = { "us", "them" }

-- Auto-attacks the client reports as casts; never a decision
local AUTO_CASTS = { [75] = true, [5019] = true }

-- Arena Preparation: the buff every player wears until the gates open.
-- Its removal on a seat is the gate clock. Two ids because the client has
-- shipped both across builds.
local PREP_AURAS = { [32727] = true, [32728] = true }

-- "PvP Trinket" — every TBC insignia/medallion casts this one spell since
-- 2.4.3. The racial CC breaks that matter in arena ride along as trinket
-- moments too (the question they answer is the same: "is their break up?").
local TRINKET_IDS = {
    [42292] = "TRINKET",       -- PvP Trinket (medallion / insignia)
    [7744]  = "WILL",          -- Will of the Forsaken
    [20589] = "ESCAPE",        -- Escape Artist
}
-- Their cooldowns (s), carried on the moment like a book entry's, so the
-- replay can say how long the break is down for
local TRINKET_CD = { [42292] = 120, [7744] = 120, [20589] = 60 }
-- Feign Death puts a real UNIT_DIED in the log for the hunter. A death
-- inside FEIGN_WINDOW of the feign's cast or aura is the feign, not a
-- death; and a seat recorded dead that then ACTS was never dead.
local FEIGN_IDS = { [5384] = true }
local feignNames = { ["Feign Death"] = true }
local FEIGN_WINDOW = 2         -- s between the feign and its UNIT_DIED, either order
local REVIVE_HP_DELAY = 1.5    -- s after a death before an hp reading can contradict it
local TRINKET_DEFAULT_CD = 120
local TRINKET_DEDUP = 3        -- s: two reports this close are one press

-- The medallions and insignias each cast their OWN item spell, so one id
-- is not the trinket: a press is recognised by NAME as well (the aliases
-- Party Frames matches on), plus the localized name of 42292 fed at login.
local trinketNames = {
    ["PvP Trinket"] = true,
    ["Medallion of the Alliance"] = true, ["Medallion of the Horde"] = true,
    ["Insignia of the Alliance"] = true, ["Insignia of the Horde"] = true,
}

function A.SetFeignNames(names)
    for _, name in ipairs(names or {}) do
        if type(name) == "string" and name ~= "" then feignNames[name] = true end
    end
end

local function IsFeign(id, name)
    return (id and FEIGN_IDS[id]) or (name and feignNames[name]) or false
end

function A.SetTrinketNames(names)
    for _, name in ipairs(names or {}) do
        if type(name) == "string" and name ~= "" then trinketNames[name] = true end
    end
end

-- Is this spell a PvP trinket (the medallion kind)? Returns the kind tag.
function A.IsTrinketSpell(id, name)
    local kind = id and TRINKET_IDS[id]
    if kind then return kind end
    if name and trinketNames[name] then return "TRINKET" end
    return nil
end

-- Combat-log flag masks (native constants when the client provides them)
local AFFIL_GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1)
    + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2)
    + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)
local REACT_HOSTILE = COMBATLOG_OBJECT_REACTION_HOSTILE or 0x40
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local TYPE_MINION = (COMBATLOG_OBJECT_TYPE_PET or 0x1000)
    + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)
    + (COMBATLOG_OBJECT_TYPE_OBJECT or 0x4000)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local live = nil               -- the match in progress, or nil
local matches = {}             -- closed matches, newest first
local matchCounter = 0
local ownerOf = {}             -- minion GUID -> owner GUID (session-wide)
local petNames = {}            -- minion GUID -> name
local anomalies = {}
local drTable = nil            -- spellId -> DR category (soft import)
local controlExtra = nil       -- spellId -> control kind (silences etc.)
local ccNames = {}             -- fallback: CC aura names (no bracket)
local bookById, bookByName = nil, nil -- cooldown book (soft import)
local specById = nil           -- signature spell id -> spec name (soft import)
local drinkIds = {}            -- aura ids that mean "drinking"
local petKeyCache = {}

A.onMatchStart = nil           -- UI hooks
A.onMatchEnd = nil             -- receives the closed match (or nil if discarded)

local function Anomaly(key)
    local n = (anomalies[key] or 0) + 1
    anomalies[key] = n
    if n == 1 then
        print("Commander Meters (arena): " .. key .. " — skipped, not guessed. /cmeters health shows counts.")
    end
end

function A.GetAnomalies() return anomalies end

-- ---------------------------------------------------------------------------
-- Rule data (fed by the window layer at login; every feed is optional)
-- ---------------------------------------------------------------------------

-- The diminishing-returns table (spellId -> category key) and the control
-- kinds for auras with no ladder (silences). Both come from Commander Arena
-- Frames or Commander Diminish when installed; without them CC still
-- counts by name (SetCCNames) but shows no bracket.
function A.SetDRTable(bySpell, extra)
    drTable = bySpell
    controlExtra = extra
end

function A.SetCCNames(names)
    ccNames = names or {}
end

-- The cooldown book: { CLASS = { {id, name, role, cd, dur}, ... } } plus a
-- racial book keyed by race. Indexed by id and by class+name (the log
-- reports the rank cast; the book carries one id per spell).
function A.SetBook(enemyBook, racialBook)
    bookById, bookByName = {}, {}
    for classToken, entries in pairs(enemyBook or {}) do
        for _, e in ipairs(entries) do
            bookById[e.id] = e
            bookByName[classToken .. "\0" .. e.name] = e
        end
    end
    for _, entries in pairs(racialBook or {}) do
        for _, e in ipairs(entries) do
            bookById[e.id] = e
            bookByName["\1" .. e.name] = e
        end
    end
end

-- Specialization markers: { CLASS = { { spec = "Arms", ids = {...} }, ... } }
-- (Arena Frames' shape). Casting a signature spell REVEALS the spec; a seat
-- whose spec the prep API never named learns it here. Never guessed from
-- class alone.
function A.SetSpecMarkers(markers)
    specById = {}
    for _, entries in pairs(markers or {}) do
        for _, entry in ipairs(entries) do
            for _, id in ipairs(entry.ids or {}) do
                specById[id] = entry.spec
            end
        end
    end
end

function A.SetDrinkIds(ids)
    drinkIds = {}
    for _, id in ipairs(ids or {}) do drinkIds[id] = true end
end

local function BookEntry(classToken, spellId, spellName)
    if not bookById then return nil end
    local e = bookById[spellId]
    if e then return e end
    if spellName then
        if classToken then
            e = bookByName[classToken .. "\0" .. spellName]
            if e then return e end
        end
        return bookByName["\1" .. spellName]
    end
    return nil
end

-- Categories that diminish but are not CONTROL in the sense a timeline
-- cares about: Hamstring has no ladder at all.
local NOT_CC = { LIMIT = true }

-- What a CC aura is: its DR category (bracketed) or a control kind from
-- the extra table (silences, unbracketed), or "CC" from the name fallback.
local function CCCategory(spellId, spellName)
    if drTable then
        local cat = drTable[spellId]
        if cat and not NOT_CC[cat] then return cat, true end
        if controlExtra then
            local kind = controlExtra[spellId]
            if kind then return kind, false end
        end
        return nil
    end
    if spellName and ccNames[spellName] then return "CC", false end
    return nil
end

-- ---------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------

local function NewTeam(key)
    return {
        key = key,
        name = nil,             -- rated team name, when the client says
        ratingBefore = nil, ratingAfter = nil, mmr = nil,
        order = {},             -- seat guids in seating order
        n = 0,
    }
end

local function NewMatch(id, ts)
    return {
        id = id,
        tsStart = ts,           -- epoch: when the recorder began (entering the arena)
        tGates = nil,           -- relative: gates opened
        tEnd = nil,             -- relative: result declared / left
        dur = 0,
        map = nil,
        bracket = 0,            -- 2 / 3 / 5, 0 until both rosters are seen
        rated = nil,            -- true / false / nil unknown
        result = nil,           -- "WIN" | "LOSS" | "DRAW" | "LEFT"
        teams = { us = NewTeam("us"), them = NewTeam("them") },
        seats = {},             -- guid -> seat (players only, both teams)
        ledger = {},            -- moments, time-ordered
        ledgerN = 0,
        ledgerDropped = 0,
        deaths = {},            -- {t, guid, killer, name, id}
        firstBlood = nil,       -- {t, guid}
        runTime = nil,          -- server's match age at the end (s)
        scored = false,         -- scoreboard merged
        tLast = 0,              -- newest combat-log time seen (keeps END last)
    }
end

local function NewSeat(guid, team)
    return {
        guid = guid, name = nil, class = nil, race = nil, spec = nil,
        team = team, token = nil,
        namePending = true,
        dmg = 0, absorbedOut = 0, heal = 0, overheal = 0, absorb = 0, taken = 0,
        crits = 0, hits = 0, misses = 0,
        ints = 0, intsTaken = 0,
        dispels = 0, purges = 0, dispelsTaken = 0, purgesTaken = 0,
        ccCasts = 0, ccSeconds = 0, ccTaken = 0, ccTakenSeconds = 0,
        ccBroke = 0,            -- broke a TEAMMATE's CC early (the mistake)
        ccWasted = 0,           -- CC that hit an immune/evaded/resisting target
        kills = 0, deaths = 0, casts = 0,
        drained = 0, drainedTaken = 0,
        drinks = 0, drinkSeconds = 0, trinkets = 0, cds = 0,
        spells = {}, spellsN = 0,        -- damage records
        heals = {}, healsN = 0,
        takenSpells = {}, takenSpellsN = 0, -- damage-taken records
        targets = {}, targetsN = 0,      -- name -> damage
        sources = {}, sourcesN = 0,      -- name -> damage taken
        ccSpells = {}, ccSpellsN = 0,    -- CC applied by aura name
        castSpells = {}, castSpellsN = 0,
        sDmg = nil, sHeal = nil, sTaken = nil, sCasts = nil,
        sHp = nil,              -- bucket -> hp per mille (last snapshot that second)
        hpMax = nil,
        sPow = nil,             -- bucket -> power per mille
        powType = nil,          -- 0 mana, 1 rage, 3 energy (Blizzard's power ids)
        castLog = {}, castLogN = 0, -- {t, t2, id, name, r} — r: "OK" | "FAIL" | "KICKED" | nil (open); instant = true for GCD-only
        openCast = nil,         -- index of the cast in progress
        auras = {}, aurasN = 0, -- {t, t2, id, name, buff, src} intervals
        auraDropped = 0,
        openAuras = {},         -- aura name -> index
        dr = {},                -- category -> {used, stacks, faded}
        openCC = {},            -- aura key -> ledger index (CC on this seat)
        openDrink = nil,        -- ledger index
        lastHit = nil,          -- {guid, t, name, id}
        alive = true,
        diedAt = nil,           -- t of the recorded death (nil while alive)
        feignAt = nil,          -- t of the last Feign Death cast / aura
    }
end

local function NewRecord(name, pet, id)
    return { name = name, pet = pet, id = id, total = 0, count = 0, crit = 0,
        miss = 0, min = nil, max = nil, absorbed = 0, overheal = 0 }
end

-- Bounded record maps: past the cap, new keys fold into "(other)" so every
-- sum invariant holds byte-exact.
local function Rec(seat, mapField, nField, key, name, pet, id)
    local map = seat[mapField]
    local rec = map[key]
    if rec then return rec end
    if seat[nField] < NAME_CAP then
        seat[nField] = seat[nField] + 1
        rec = NewRecord(name, pet, id)
        map[key] = rec
        return rec
    end
    rec = map[OTHER_NAMES]
    if not rec then
        rec = NewRecord(OTHER_NAMES, nil, nil)
        map[OTHER_NAMES] = rec
    end
    return rec
end

local function Tally(seat, mapField, nField, key, amount)
    local map = seat[mapField]
    if map[key] ~= nil then
        map[key] = map[key] + amount
        return
    end
    if seat[nField] < NAME_CAP then
        seat[nField] = seat[nField] + 1
        map[key] = amount
    else
        map[OTHER_NAMES] = (map[OTHER_NAMES] or 0) + amount
    end
end

local function PetKey(petName, spellName)
    local perPet = petKeyCache[petName]
    if not perPet then perPet = {}; petKeyCache[petName] = perPet end
    local key = perPet[spellName]
    if not key then
        key = petName .. ": " .. spellName
        perPet[spellName] = key
    end
    return key
end

-- ---------------------------------------------------------------------------
-- Match lifecycle
-- ---------------------------------------------------------------------------

function A.Begin(ts, map)
    if live then return live end
    matchCounter = matchCounter + 1
    live = NewMatch(matchCounter, ts)
    live.map = map
    if A.onMatchStart then A.onMatchStart(live) end
    return live
end

function A.Live() return live end
function A.GetMatches() return matches end
function A.InMatch() return live ~= nil end

-- Selector: "live", "last", or a match id
function A.GetMatch(sel)
    if sel == "live" then return live end
    if sel == "last" then return matches[1] end
    for i = 1, #matches do
        if matches[i].id == sel then return matches[i] end
    end
end

local function Rel(m, ts)
    local t = ts - m.tsStart
    if t < 0 then t = 0 end
    return t
end

local function Bucket(m, ts)
    local b = floor(Rel(m, ts)) + 1
    if b > SERIES_CAP then return nil end
    return b
end

-- Moments. The ledger is append-only and time-ordered because the combat
-- log is; past the cap only deaths and the end marker still land (the
-- story's skeleton), and the drop count is shown, never hidden.
local function Moment(m, t, kind, src, dst, id, name, amount, x)
    if m.ledgerN >= LEDGER_CAP and kind ~= "DEATH" and kind ~= "END" then
        m.ledgerDropped = m.ledgerDropped + 1
        return nil
    end
    -- The ledger is searched by bisection, so it must stay sorted: a
    -- moment arriving behind the newest one is clamped up to it (the log
    -- is chronological; only a replayed fixture can misorder)
    if m.ledgerN > 0 and t < m.ledger[m.ledgerN].t then
        t = m.ledger[m.ledgerN].t
    end
    m.ledgerN = m.ledgerN + 1
    local e = { t = t, kind = kind, src = src, dst = dst, id = id, name = name,
        amount = amount, x = x }
    m.ledger[m.ledgerN] = e
    return m.ledgerN, e
end

function A.SetMap(map)
    if live and map then live.map = map end
end

-- The gate clock: Arena Preparation fading, or the first blow if that was
-- never seen (a /reload after the gates, say)
function A.SetGates(ts)
    if live and not live.tGates then
        live.tGates = Rel(live, ts)
        Moment(live, live.tGates, "GATES")
    end
end

-- Seats. team = "us" | "them". Nil fields mean "not right now", never
-- "not any more": a stealthed enemy answers nil to every unit query and
-- must not have its identity erased.
function A.SetSeat(team, guid, name, class, race, token, spec)
    if not live or not guid then return end
    local seat = live.seats[guid]
    if not seat then
        seat = NewSeat(guid, team)
        live.seats[guid] = seat
        local tm = live.teams[team]
        tm.n = tm.n + 1
        tm.order[tm.n] = guid
    elseif seat.team ~= team then
        -- A GUID cannot change sides mid-match; the first sighting wins
        Anomaly("seat reported on both teams (" .. tostring(name or seat.name) .. ")")
    end
    if name then seat.name = name; seat.namePending = nil end
    if class then seat.class = class end
    if race then seat.race = race end
    if token then seat.token = token end
    if spec then seat.spec = spec end
    -- Bracket: the larger roster, snapped to a real arena size
    local n = max(live.teams.us.n, live.teams.them.n)
    live.bracket = n <= 2 and 2 or (n <= 3 and 3 or 5)
    return seat
end

function A.SetOwner(minionGuid, ownerGuid, minionName)
    if not minionGuid or not ownerGuid or minionGuid == ownerGuid then return end
    ownerOf[minionGuid] = ownerGuid
    if minionName then petNames[minionGuid] = minionName end
end

-- HP snapshots feed the replay: one value per second per seat, the last
-- reading in that second wins. Stored as PER-MILLE INTEGERS (0..1000): a
-- fraction serializes as a 17-digit float in SavedVariables and the HP
-- series was most of a saved match's weight; three digits carry the same
-- picture. Readers divide by HP_SCALE.
local HP_SCALE = 1000

local Revive -- forward: undoes a death that was not one

function A.SetHealth(guid, hp, hpMax, ts)
    if not live or not guid or not hp or not hpMax or hpMax <= 0 then return end
    local seat = live.seats[guid]
    if not seat then return end
    -- A living reading well after a recorded death: they were never dead
    -- (a feign the log did not announce, or one seen out of order)
    if seat.diedAt and hp > 0 and (ts - live.tsStart) - seat.diedAt > REVIVE_HP_DELAY then
        Revive(live, seat)
    end
    local b = Bucket(live, ts)
    if not b then return end
    local s = seat.sHp
    if not s then s = {}; seat.sHp = s end
    local v = floor(hp / hpMax * HP_SCALE + 0.5)
    if v < 0 then v = 0 elseif v > HP_SCALE then v = HP_SCALE end
    s[b] = v
    seat.hpMax = hpMax
end

function A.SetPower(guid, power, powerMax, powerType, ts)
    if not live or not guid or not power or not powerMax or powerMax <= 0 then return end
    local seat = live.seats[guid]
    if not seat then return end
    local b = Bucket(live, ts)
    if not b then return end
    local s = seat.sPow
    if not s then s = {}; seat.sPow = s end
    local v = floor(power / powerMax * HP_SCALE + 0.5)
    if v < 0 then v = 0 elseif v > HP_SCALE then v = HP_SCALE end
    s[b] = v
    if type(powerType) == "number" then seat.powType = powerType end
end

-- Resolve a combat-log unit to its seat (players directly, minions via
-- their owner). Unknown hostile PLAYERS become enemy seats on the spot —
-- the log sees a rogue before any unit token does. Returns seat, petName.
local function SeatOf(m, guid, name, flags)
    if not guid then return nil end
    local seat = m.seats[guid]
    if seat then
        if name and seat.namePending then seat.name = name; seat.namePending = nil end
        return seat, nil
    end
    if band(flags, TYPE_PLAYER) ~= 0 then
        if band(flags, REACT_HOSTILE) ~= 0 then
            seat = A.SetSeat("them", guid, name)
            return seat, nil
        end
        if band(flags, AFFIL_GROUP) ~= 0 then
            seat = A.SetSeat("us", guid, name)
            return seat, nil
        end
        return nil
    end
    if band(flags, TYPE_MINION) ~= 0 then
        local owner = ownerOf[guid]
        if owner then
            seat = m.seats[owner]
            if seat then return seat, petNames[guid] or name or "Pet" end
        end
        Anomaly("minion with unknown owner (" .. (name or "?") .. ")")
        return nil
    end
    return nil
end

-- The destination side: players only (a CC on a pet is not a seat event),
-- auto-seating an unknown player exactly like the source side does.
local function PlayerSeat(m, guid, name, flags)
    if not guid or band(flags, TYPE_PLAYER) == 0 then return nil end
    local seat = SeatOf(m, guid, name, flags)
    return seat
end

-- ---------------------------------------------------------------------------
-- Diminishing returns (per seat per category)
-- ---------------------------------------------------------------------------

local function DREntry(seat, cat)
    local e = seat.dr[cat]
    if not e then
        e = { used = 0, stacks = 0, faded = nil }
        seat.dr[cat] = e
    end
    return e
end

-- The bracket THIS application landed at: 1 full, 2 half, 3 quarter. A
-- fourth application should never land (the target is immune); it is
-- reported as 4 so a wrong table shows up as a visible number.
local function DRApply(seat, cat, t)
    local e = DREntry(seat, cat)
    if e.stacks == 0 and e.faded and (t - e.faded) > DR_RESET then
        e.used = 0
    end
    e.used = e.used + 1
    e.stacks = e.stacks + 1
    return min(e.used, 4)
end

local function DRFade(seat, cat, t)
    local e = seat.dr[cat]
    if not e then return end
    if e.stacks > 0 then e.stacks = e.stacks - 1 end
    e.faded = t
end

-- ---------------------------------------------------------------------------
-- Crediting
-- ---------------------------------------------------------------------------

local function Series(seat, field, b, amount)
    local s = seat[field]
    if not s then s = {}; seat[field] = s end
    s[b] = (s[b] or 0) + amount
end

local function CreditDamage(m, seat, petName, ts, spellName, spellId, target, amount, absorbed, crit)
    seat.dmg = seat.dmg + amount
    seat.hits = seat.hits + 1
    if crit then seat.crits = seat.crits + 1 end
    if absorbed > 0 then seat.absorbedOut = seat.absorbedOut + absorbed end
    local key = petName and PetKey(petName, spellName) or spellName
    local rec = Rec(seat, "spells", "spellsN", key, spellName, petName, spellId)
    rec.total = rec.total + amount
    rec.count = rec.count + 1
    if crit then rec.crit = rec.crit + 1 end
    if absorbed > 0 then rec.absorbed = rec.absorbed + absorbed end
    if not rec.min or amount < rec.min then rec.min = amount end
    if not rec.max or amount > rec.max then rec.max = amount end
    if target then Tally(seat, "targets", "targetsN", target, amount) end
    local b = Bucket(m, ts)
    if b then Series(seat, "sDmg", b, amount) end
end

local function CreditTaken(m, seat, ts, spellName, spellId, source, srcGuid, amount, absorbed, crit)
    seat.taken = seat.taken + amount
    local rec = Rec(seat, "takenSpells", "takenSpellsN", spellName, spellName, nil, spellId)
    rec.total = rec.total + amount
    rec.count = rec.count + 1
    if crit then rec.crit = rec.crit + 1 end
    if absorbed > 0 then rec.absorbed = rec.absorbed + absorbed end
    if not rec.min or amount < rec.min then rec.min = amount end
    if not rec.max or amount > rec.max then rec.max = amount end
    if source then Tally(seat, "sources", "sourcesN", source, amount) end
    local b = Bucket(m, ts)
    if b then Series(seat, "sTaken", b, amount) end
    -- Killing-blow candidate: the last hit within KILL_WINDOW of a death
    local lh = seat.lastHit
    if not lh then lh = {}; seat.lastHit = lh end
    lh.guid, lh.t, lh.name, lh.id = srcGuid, Rel(m, ts), spellName, spellId
end

local function CreditHealing(m, seat, petName, ts, spellName, spellId, effective, over, crit, isAbsorb)
    if isAbsorb then
        seat.absorb = seat.absorb + effective
    else
        seat.heal = seat.heal + effective
        seat.overheal = seat.overheal + over
    end
    local key = petName and PetKey(petName, spellName) or spellName
    local rec = Rec(seat, "heals", "healsN", key, spellName, petName, spellId)
    rec.total = rec.total + effective
    rec.count = rec.count + 1
    rec.overheal = rec.overheal + over
    if crit then rec.crit = rec.crit + 1 end
    local b = Bucket(m, ts)
    if b then Series(seat, "sHeal", b, effective) end
end

-- ---------------------------------------------------------------------------
-- Combat-log dispatch
-- ---------------------------------------------------------------------------

local DISPATCH = {
    SWING_DAMAGE            = { prefix = 0, kind = 1 },
    RANGE_DAMAGE            = { prefix = 3, kind = 1 },
    SPELL_DAMAGE            = { prefix = 3, kind = 1 },
    SPELL_PERIODIC_DAMAGE   = { prefix = 3, kind = 1 },
    DAMAGE_SHIELD           = { prefix = 3, kind = 1 },
    DAMAGE_SPLIT            = { prefix = 3, kind = 1 },
    ENVIRONMENTAL_DAMAGE    = { prefix = 1, kind = 1 },
    SWING_MISSED            = { prefix = 0, kind = 2 },
    RANGE_MISSED            = { prefix = 3, kind = 2 },
    SPELL_MISSED            = { prefix = 3, kind = 2 },
    SPELL_PERIODIC_MISSED   = { prefix = 3, kind = 2 },
    SPELL_HEAL              = { prefix = 3, kind = 3 },
    SPELL_PERIODIC_HEAL     = { prefix = 3, kind = 3 },
    SPELL_ABSORBED          = { kind = 4 },
    SPELL_SUMMON            = { kind = 5 },
    UNIT_DIED               = { kind = 6 },
    SPELL_INTERRUPT         = { kind = 7 },
    SPELL_DISPEL            = { kind = 8 },
    SPELL_STOLEN            = { kind = 8 },
    SPELL_AURA_BROKEN       = { kind = 9 },
    SPELL_AURA_BROKEN_SPELL = { kind = 9 },
    SPELL_CAST_SUCCESS      = { kind = 10 },
    SPELL_AURA_APPLIED      = { kind = 11 },
    SPELL_AURA_REFRESH      = { kind = 11 },
    SPELL_AURA_APPLIED_DOSE = { kind = 11 },  -- a stack: the same aura, still on
    SPELL_AURA_REMOVED      = { kind = 12 },
    SPELL_CAST_START        = { kind = 14 },
    SPELL_CAST_FAILED       = { kind = 15 },
    SPELL_DRAIN             = { kind = 13 },
    SPELL_PERIODIC_DRAIN    = { kind = 13 },
    SPELL_LEECH             = { kind = 13 },
    SPELL_PERIODIC_LEECH    = { kind = 13 },
}

-- Close a CC moment: stamp its end, credit control time to both sides,
-- update the caster's DR view of the target.
local function CloseCC(m, seat, key, t, breaker)
    local idx = seat.openCC[key]
    if not idx then return end
    seat.openCC[key] = nil
    local e = m.ledger[idx]
    if not e then return end
    local dur = max(t - e.t, 0)
    if dur > CC_OPEN_CAP then dur = CC_OPEN_CAP end
    e.t2 = e.t + dur
    if breaker then e.brk = breaker end
    seat.ccTakenSeconds = seat.ccTakenSeconds + dur
    local caster = e.src and m.seats[e.src]
    if caster then caster.ccSeconds = caster.ccSeconds + dur end
    if e.cat then DRFade(seat, e.cat, t) end
end

local function CloseDrink(m, seat, t)
    local idx = seat.openDrink
    if not idx then return end
    seat.openDrink = nil
    local e = m.ledger[idx]
    if not e then return end
    local dur = max(t - e.t, 0)
    if dur > DRINK_OPEN_CAP then dur = DRINK_OPEN_CAP end
    e.t2 = e.t + dur
    seat.drinkSeconds = seat.drinkSeconds + dur
end

-- One trinket press, from whichever source saw it first. Three sources
-- report the same press — the combat log, the client's arena crowd-control
-- answer, the cast event for our own side — so a report within
-- TRINKET_DEDUP seconds of a recorded one only refines its cooldown.
-- `tReal` may be a little in the past (the client reports a start time);
-- the ledger clamps a late moment up to its newest time, and the cooldown
-- is shortened by the same amount so it still ENDS when it really does.
local function RecordTrinket(m, seat, tReal, id, name, cd, kind)
    cd = cd or (id and TRINKET_CD[id]) or TRINKET_DEFAULT_CD
    for i = m.ledgerN, 1, -1 do
        local e = m.ledger[i]
        if e.t < tReal - 130 then break end
        if e.kind == "TRINKET" and e.src == seat.guid then
            local pressed = e.t0 or e.t
            if math.abs(pressed - tReal) <= TRINKET_DEDUP then
                -- The same press seen again: the client's cooldown wins
                if cd and cd > 0 then e.amount = cd - (e.t - pressed) end
                return e
            end
        end
    end
    seat.trinkets = seat.trinkets + 1
    local idx, e = Moment(m, tReal, "TRINKET", seat.guid, nil, id, name or "PvP Trinket", cd, kind or "TRINKET")
    if e then
        e.t0 = tReal
        if e.t > tReal then e.amount = max(cd - (e.t - tReal), 0) end
    end
    return e
end

-- A press reported from outside the combat log (the client's arena
-- crowd-control info for enemies, UNIT_SPELLCAST_SUCCEEDED for our side).
-- ts is the epoch time of the PRESS; cd its length in seconds.
function A.OnTrinket(guid, ts, cd, id, name)
    local m = live
    if not m or not guid then return end
    local seat = m.seats[guid]
    if not seat then return end
    return RecordTrinket(m, seat, Rel(m, ts), id, name, cd, "TRINKET")
end

-- Casts: a start opens one, a success/failure/kick closes it; a success
-- with nothing open is an instant (it still spends a global cooldown).
local function CloseCast(seat, t, r)
    local idx = seat.openCast
    if not idx then return end
    seat.openCast = nil
    local c = seat.castLog[idx]
    if not c then return end
    if t - c.t > CAST_OPEN_CAP then t = c.t + CAST_OPEN_CAP end
    c.t2 = t
    c.r = r
end

local function PushCast(seat, t, id, name, instant, tgt)
    if seat.castLogN >= CAST_CAP then return nil end
    seat.castLogN = seat.castLogN + 1
    local c = { t = t, t2 = instant and t or nil, id = id, name = name, r = instant and "OK" or nil,
        instant = instant or nil, tgt = tgt }
    seat.castLog[seat.castLogN] = c
    return seat.castLogN
end

-- Aura intervals: one per application; refreshes and stacks extend the
-- open one, REMOVED closes it. Bounded per seat; overflow is counted.
local function OpenAura(seat, t, id, name, buff, src)
    if seat.openAuras[name] then return end
    if seat.aurasN >= AURA_CAP then
        seat.auraDropped = seat.auraDropped + 1
        return
    end
    seat.aurasN = seat.aurasN + 1
    seat.auras[seat.aurasN] = { t = t, id = id, name = name, buff = buff, src = src }
    seat.openAuras[name] = seat.aurasN
end

local function CloseAura(seat, name, t)
    local idx = seat.openAuras[name]
    if not idx then return end
    seat.openAuras[name] = nil
    local a = seat.auras[idx]
    if a then a.t2 = t end
end

-- Undo a recorded death: the seat acted, read alive, or the death turned
-- out to be its own Feign Death. The death record goes, the kill credit
-- and first blood with it, and the DEATH moment becomes a FEIGN moment so
-- the timeline still says what happened at that second.
Revive = function(m, seat)
    if not seat.diedAt then return end
    for i = #m.deaths, 1, -1 do
        local d = m.deaths[i]
        if d.guid == seat.guid then
            if d.killer then
                local ks = m.seats[d.killer]
                if ks and ks.kills > 0 then ks.kills = ks.kills - 1 end
            end
            table.remove(m.deaths, i)
            break
        end
    end
    if seat.deaths > 0 then seat.deaths = seat.deaths - 1 end
    for i = m.ledgerN, 1, -1 do
        local e = m.ledger[i]
        if e.kind == "DEATH" and e.dst == seat.guid then
            e.kind, e.src, e.dst, e.name, e.id = "FEIGN", seat.guid, nil, "Feign Death", 5384
            break
        end
    end
    local first = m.deaths[1]
    m.firstBlood = first and { t = first.t, guid = first.guid } or nil
    -- The auras the false death closed were never lost: reopen the ones
    -- nothing has re-applied since (a real fade still logs its REMOVED)
    local closed = seat.deathClosed
    if closed then
        for name, idx in pairs(closed) do
            local a = seat.auras[idx]
            if a and a.name == name and a.t2 == seat.diedAt and not seat.openAuras[name] then
                a.t2 = nil
                seat.openAuras[name] = idx
            end
        end
        seat.deathClosed = nil
    end
    seat.alive = true
    seat.diedAt = nil
end

function A.OnCleu(ts, sub, hideCaster, sg, sn, sf, srf, dg, dn, df, drf,
        a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24)
    local m = live
    if not m then return end
    local d = DISPATCH[sub]
    if not d then return end
    local kind = d.kind
    do
        local tl = ts - m.tsStart
        if tl > m.tLast then m.tLast = tl end
    end

    if kind == 5 then
        -- SPELL_SUMMON: source summons dest; chained summons resolve to the
        -- root owner through the seat lookup
        local owner = SeatOf(m, sg, sn, sf)
        if owner then A.SetOwner(dg, owner.guid, dn) end
        return
    end

    if kind == 6 then
        local seat = PlayerSeat(m, dg, dn, df)
        if not seat then return end
        local t = Rel(m, ts)
        -- The feign's own UNIT_DIED: a moment, not a death
        if seat.feignAt and t - seat.feignAt <= FEIGN_WINDOW then
            Moment(m, t, "FEIGN", seat.guid, nil, 5384, "Feign Death")
            return
        end
        if seat.diedAt then return end -- already dead: one death per seat
        seat.deaths = seat.deaths + 1
        seat.alive = false
        seat.diedAt = t
        local killer, kname, kid
        local lh = seat.lastHit
        if lh and (t - lh.t) <= KILL_WINDOW then
            kname, kid = lh.name, lh.id
            -- A killing blow belongs to a SEAT that is not the victim: a
            -- Life Tap or Hellfire death names the blow but credits nobody
            local ks = lh.guid and m.seats[lh.guid]
            if ks and lh.guid ~= dg then
                killer = lh.guid
                ks.kills = ks.kills + 1
            end
        end
        m.deaths[#m.deaths + 1] = { t = t, guid = dg, killer = killer, name = kname, id = kid }
        if not m.firstBlood then m.firstBlood = { t = t, guid = dg } end
        -- Death ends every CC, drink, aura and cast on the seat (their auras
        -- vanish without a REMOVED event on this client when the unit dies)
        for key in pairs(seat.openCC) do CloseCC(m, seat, key, t) end
        CloseDrink(m, seat, t)
        -- (remembered, so a death that proves false can hand them back)
        local closed = {}
        for name, idx in pairs(seat.openAuras) do closed[name] = idx end
        seat.deathClosed = closed
        for name in pairs(closed) do CloseAura(seat, name, t) end
        CloseCast(seat, t, "FAIL")
        Moment(m, t, "DEATH", killer, dg, kid, kname)
        return
    end

    if kind == 7 then
        -- SPELL_INTERRUPT: extra = the interrupted spell (a15, a16)
        local src, pet = SeatOf(m, sg, sn, sf)
        local dst = PlayerSeat(m, dg, dn, df)
        if not (src or dst) then return end
        if type(a16) ~= "string" then
            Anomaly("interrupt with unexpected layout")
            return
        end
        local t = Rel(m, ts)
        if src then src.ints = src.ints + 1 end
        if dst then
            dst.intsTaken = dst.intsTaken + 1
            CloseCast(dst, t, "KICKED")
        end
        Moment(m, t, "KICK", src and src.guid, dg, type(a15) == "number" and a15 or nil,
            a16, nil, a13) -- x = the kick used
        return
    end

    if kind == 8 then
        -- SPELL_DISPEL / SPELL_STOLEN: extra = the removed aura (a15, a16)
        local src, pet = SeatOf(m, sg, sn, sf)
        local dst = PlayerSeat(m, dg, dn, df)
        if not (src or dst) then return end
        if type(a16) ~= "string" then
            Anomaly("dispel with unexpected layout")
            return
        end
        local t = Rel(m, ts)
        local offensive = src and dst and src.team ~= dst.team
        if not src and dst then offensive = false end
        if src then
            if offensive then src.purges = src.purges + 1 else src.dispels = src.dispels + 1 end
        end
        if dst then
            if offensive then dst.purgesTaken = dst.purgesTaken + 1 else dst.dispelsTaken = dst.dispelsTaken + 1 end
            -- A dispelled CC is a CC that ended now
            if dst.openCC[a16] then CloseCC(m, dst, a16, t, src and src.guid) end
        end
        Moment(m, t, "DISPEL", src and src.guid, dg, type(a15) == "number" and a15 or nil,
            a16, nil, offensive and "PURGE" or "DISPEL")
        return
    end

    if kind == 9 then
        -- SPELL_AURA_BROKEN(_SPELL): prefix = the broken aura, source = breaker
        local dst = PlayerSeat(m, dg, dn, df)
        if not dst then return end
        if type(a13) ~= "string" then
            Anomaly("aura break with unexpected layout")
            return
        end
        if not dst.openCC[a13] then return end
        local t = Rel(m, ts)
        local breaker = SeatOf(m, sg, sn, sf)
        local e = m.ledger[dst.openCC[a13]]
        CloseCC(m, dst, a13, t, breaker and breaker.guid)
        -- Breaking your OWN team's CC is the mistake worth a number
        if breaker and e and e.src and m.seats[e.src] and m.seats[e.src].team == breaker.team
            and breaker.guid ~= e.src then
            breaker.ccBroke = breaker.ccBroke + 1
            if e then e.own = true end
        end
        return
    end

    if kind == 10 then
        -- SPELL_CAST_SUCCESS: APM for players; trinkets and book cooldowns
        -- for the ledger (pets fold for cooldowns — Spell Lock is the
        -- warlock's decision — but never for APM)
        local seat, pet = SeatOf(m, sg, sn, sf)
        if not seat then return end
        if type(a13) ~= "string" then return end
        local t = Rel(m, ts)
        local id = type(a12) == "number" and a12 or nil
        if not pet then
            -- The feign stamps the seat, so its own UNIT_DIED is not a death
            if IsFeign(id, a13) then seat.feignAt = t end
            -- The dead do not cast: a seat recorded dead was feigning
            if seat.diedAt then Revive(m, seat) end
        end
        if not pet and not AUTO_CASTS[a12] then
            -- The cast record: a success ends the cast in progress, or is
            -- an instant of its own (which still spends a GCD)
            local open = seat.openCast and seat.castLog[seat.openCast]
            -- The success carries the spell's target: who they are on
            local tgt = (dg and dg ~= "" and m.seats[dg]) and dg or nil
            if open and (open.name == a13 or open.id == id) then
                open.tgt = tgt or open.tgt
                CloseCast(seat, t, "OK")
            else
                if open then CloseCast(seat, t, "FAIL") end
                PushCast(seat, t, id, a13, true, tgt)
            end
            seat.casts = seat.casts + 1
            local rec = Rec(seat, "castSpells", "castSpellsN", a13, a13, nil, id)
            rec.total = rec.total + 1
            rec.count = rec.count + 1
            local b = Bucket(m, ts)
            if b then Series(seat, "sCasts", b, 1) end
        end
        -- A signature spell reveals the spec (players only; a pet's cast
        -- says nothing about its owner's talents)
        if not pet and not seat.spec and specById and id and specById[id] then
            seat.spec = specById[id]
            seat.specRevealed = true
            Moment(m, t, "SPEC", seat.guid, nil, id, seat.spec)
        end
        local trinket = (not pet) and A.IsTrinketSpell(id, a13)
        if trinket then
            RecordTrinket(m, seat, t, id, a13, id and TRINKET_CD[id] or nil, trinket)
            return
        end
        local book = BookEntry(seat.class, id, a13)
        if book then
            seat.cds = seat.cds + 1
            Moment(m, t, "CD", seat.guid, dg ~= "" and dg or nil, id, a13, book.cd, book.role)
        end
        return
    end

    if kind == 11 then
        -- Aura applied/refreshed: CC landing (with its DR bracket), drinks
        local dst = PlayerSeat(m, dg, dn, df)
        if not dst then return end
        if type(a13) ~= "string" then return end
        local id = type(a12) == "number" and a12 or nil
        local t = Rel(m, ts)
        if id and PREP_AURAS[id] then return end
        -- The general aura record (buffs and debuffs alike), for the
        -- replay's icon rows. A refresh or a stack extends the open one.
        if sub == "SPELL_AURA_APPLIED" or not dst.openAuras[a13] then
            local srcSeat = SeatOf(m, sg, sn, sf)
            if sub == "SPELL_AURA_APPLIED" and dst.openAuras[a13] then
                CloseAura(dst, a13, t)
            end
            OpenAura(dst, t, id, a13, a15 == "BUFF", srcSeat and srcSeat.guid or nil)
        end
        if IsFeign(id, a13) then
            dst.feignAt = t
            local idx = dst.openAuras[a13]
            if idx and dst.auras[idx] then dst.auras[idx].feign = true end
            -- Only the living gain it: a UNIT_DIED logged first was the feign's own
            if dst.diedAt then Revive(m, dst) end
        end
        if id and drinkIds[id] then
            if dst.openDrink then
                -- A refresh is the same drink; a fresh APPLIED while one is
                -- open means its end was never logged — close it at its cap
                if sub == "SPELL_AURA_REFRESH" then return end
                local prev = m.ledger[dst.openDrink]
                CloseDrink(m, dst, prev and min(t, prev.t + DRINK_OPEN_CAP) or t)
            end
            dst.drinks = dst.drinks + 1
            dst.openDrink = Moment(m, t, "DRINK", dst.guid, nil, id, a13)
            return
        end
        local cat, laddered = CCCategory(id, a13)
        if not cat then return end
        local src = SeatOf(m, sg, sn, sf)
        -- A refresh of an open CC re-stamps nothing: one application, one
        -- moment (Fear's refresh-on-damage is the same fear). A fresh
        -- APPLIED while the same aura is still open means its fade was
        -- never logged — the target was out of range — so the stale one
        -- is closed at its cap and this one counts.
        if dst.openCC[a13] then
            if sub == "SPELL_AURA_REFRESH" then return end
            local prev = m.ledger[dst.openCC[a13]]
            CloseCC(m, dst, a13, prev and min(t, prev.t + CC_OPEN_CAP) or t)
        end
        local bracket = laddered and DRApply(dst, cat, t) or nil
        if src then
            src.ccCasts = src.ccCasts + 1
            local rec = Rec(src, "ccSpells", "ccSpellsN", a13, a13, nil, id)
            rec.total = rec.total + 1
            rec.count = rec.count + 1
        end
        dst.ccTaken = dst.ccTaken + 1
        local idx, e = Moment(m, t, "CC", src and src.guid, dg, id, a13, nil, bracket)
        if e then
            e.cat = cat
            dst.openCC[a13] = idx
        else
            -- Ledger full: still track the DR fade without a moment
            dst.openCC[a13] = nil
            if laddered then DRFade(dst, cat, t) end
        end
        return
    end

    if kind == 12 then
        local dst = PlayerSeat(m, dg, dn, df)
        if not dst then return end
        if type(a13) ~= "string" then return end
        local id = type(a12) == "number" and a12 or nil
        local t = Rel(m, ts)
        if id and PREP_AURAS[id] then
            A.SetGates(ts)
            return
        end
        CloseAura(dst, a13, t)
        if id and drinkIds[id] then
            CloseDrink(m, dst, t)
            return
        end
        if dst.openCC[a13] then CloseCC(m, dst, a13, t) end
        return
    end

    if kind == 14 or kind == 15 then
        -- SPELL_CAST_START opens a cast; SPELL_CAST_FAILED closes it (a
        -- moved cast, a lost target). Players only: a pet's cast is not on
        -- its owner's bar.
        local seat, pet = SeatOf(m, sg, sn, sf)
        if not seat or pet then return end
        if type(a13) ~= "string" then return end
        local t = Rel(m, ts)
        if kind == 14 and seat.diedAt then Revive(m, seat) end
        if kind == 14 then
            if seat.openCast then CloseCast(seat, t, "FAIL") end
            seat.openCast = PushCast(seat, t, type(a12) == "number" and a12 or nil, a13, false)
        else
            CloseCast(seat, t, "FAIL")
        end
        return
    end

    if kind == 13 then
        -- Drains/leeches: suffix = amount, powerType, extraAmount. Mana only
        -- (powerType 0): a mana burn or viper sting is the arena-relevant one.
        local src, pet = SeatOf(m, sg, sn, sf)
        local dst = PlayerSeat(m, dg, dn, df)
        if not (src or dst) then return end
        local amount, power = a15, a16
        if type(amount) ~= "number" or power ~= 0 then return end
        local t = Rel(m, ts)
        if src then src.drained = src.drained + amount end
        if dst then dst.drainedTaken = dst.drainedTaken + amount end
        Moment(m, t, "DRAIN", src and src.guid, dg, type(a12) == "number" and a12 or nil,
            type(a13) == "string" and a13 or "Drain", amount)
        return
    end

    if kind == 4 then
        -- SPELL_ABSORBED: credit the shield's caster like a heal
        local cg, cn, cf, spellName, amount, crit, shieldId
        if type(a12) == "number" then
            cg, cn, cf = a15, a16, a17
            spellName, amount, crit = a20, a22, a23
            shieldId = a19
        elseif type(a12) == "string" then
            cg, cn, cf = a12, a13, a14
            spellName, amount, crit = a17, a19, a20
            shieldId = a16
        end
        if type(cg) ~= "string" or type(spellName) ~= "string"
            or type(amount) ~= "number" or amount <= 0 or type(cf) ~= "number" then
            Anomaly("unrecognized SPELL_ABSORBED layout")
            return
        end
        local seat, pet = SeatOf(m, cg, cn, cf)
        if not seat then return end
        CreditHealing(m, seat, pet, ts, spellName, type(shieldId) == "number" and shieldId or nil,
            amount, 0, crit and true or false, true)
        return
    end

    -- Damage / miss / heal share the prefix decode
    local spellName, s1, s2, s3, s4
    if d.prefix == 0 then
        spellName = "Melee"
        s1, s2, s3, s4 = a12, a13, a14, a15
    elseif d.prefix == 1 then
        spellName = tostring(a12 or "Environment")
        s1, s2, s3, s4 = a13, a14, a15, a16
    else
        spellName = a13
        s1, s2, s3, s4 = a15, a16, a17, a18
    end
    if type(spellName) ~= "string" then
        Anomaly("event with non-string ability name (" .. sub .. ")")
        return
    end
    local spellId = d.prefix == 3 and type(a12) == "number" and a12 or nil

    if kind == 1 then
        local amount = s1
        local absorbed, critical
        if d.prefix == 0 then absorbed, critical = a17, a18
        elseif d.prefix == 1 then absorbed, critical = a18, a19
        else absorbed, critical = a20, a21 end
        if type(amount) ~= "number" then
            Anomaly("damage event with non-numeric amount (" .. sub .. ")")
            return
        end
        if type(absorbed) ~= "number" then absorbed = 0 end
        local quantum = amount + absorbed
        if quantum <= 0 then return end
        local crit = critical and true or false
        local src, pet = SeatOf(m, sg, sn, sf)
        local dst = PlayerSeat(m, dg, dn, df)
        if not (src or dst) then return end
        -- A melee swing from a seat recorded dead: they were feigning.
        -- (Spell damage proves nothing — bolts in flight and dots outlive
        -- their caster.)
        if src and not pet and src.diedAt and sub == "SWING_DAMAGE" then Revive(m, src) end
        -- The first blow between the teams opens the gates if the prep
        -- aura's fade was never seen
        if src and dst and src.team ~= dst.team and not m.tGates then A.SetGates(ts) end
        if src then
            CreditDamage(m, src, pet, ts, spellName, spellId, dn or "Unknown", quantum, absorbed, crit)
        end
        if dst then
            CreditTaken(m, dst, ts, spellName, spellId, (sn and sn ~= "" and sn) or spellName,
                src and src.guid or sg, quantum, absorbed, crit)
        end
        return
    end

    if kind == 2 then
        local missType, amountMissed = s1, s3
        local src, pet = SeatOf(m, sg, sn, sf)
        local dst = PlayerSeat(m, dg, dn, df)
        if not (src or dst) then return end
        if missType == "ABSORB" then
            local amount = type(amountMissed) == "number" and amountMissed or 0
            if amount <= 0 then return end
            if src then
                CreditDamage(m, src, pet, ts, spellName, spellId, dn or "Unknown", amount, amount, false)
            end
            if dst then
                CreditTaken(m, dst, ts, spellName, spellId, (sn and sn ~= "" and sn) or spellName,
                    src and src.guid or sg, amount, amount, false)
            end
            return
        end
        if src then
            src.misses = src.misses + 1
            local key = pet and PetKey(pet, spellName) or spellName
            local rec = Rec(src, "spells", "spellsN", key, spellName, pet, spellId)
            rec.miss = rec.miss + 1
            -- CC into immunity / resisted / dodged is the CC that never
            -- happened: the wasted-cast counter and a moment of its own
            if dst and spellId and CCCategory(spellId, spellName) then
                src.ccWasted = src.ccWasted + 1
                Moment(m, Rel(m, ts), "CCFAIL", src.guid, dg, spellId, spellName, nil, missType)
            end
        end
        if dst then
            local rec = Rec(dst, "takenSpells", "takenSpellsN", spellName, spellName, nil, spellId)
            rec.miss = rec.miss + 1
        end
        return
    end

    if kind == 3 then
        local amount, over, crit = s1, s2, s4
        if type(amount) ~= "number" then
            Anomaly("heal event with non-numeric amount (" .. sub .. ")")
            return
        end
        if type(over) ~= "number" then over = 0 end
        local src, pet = SeatOf(m, sg, sn, sf)
        if not src then return end
        local effective = amount - over
        if effective < 0 then effective = 0 end
        CreditHealing(m, src, pet, ts, spellName, spellId, effective, over, crit and true or false, false)
        return
    end
end

-- ---------------------------------------------------------------------------
-- Ending a match
-- ---------------------------------------------------------------------------

-- Scoreboard rows from GetBattlefieldScore, merged onto seats by name:
-- { name, kb, hk, deaths, honor, faction, race, classToken, dmg, heal,
--   ratingChange, mmr }. The server saw the whole box; where our log
-- disagrees, both numbers are kept and the board says which is which.
local function ShortName(name)
    if not name then return nil end
    local dash = name:find("-", 1, true)
    if dash then return name:sub(1, dash - 1) end
    return name
end

-- `ourFaction` (GetBattlefieldArenaFaction, 0/1) lets a row for a player the
-- log never saw — a 5v5 healer who stayed out of range all game — take a
-- seat of its own, with the server's numbers as its only numbers. Such a
-- seat has a synthetic guid and `fromScoreboard = true`; the board says
-- "server" beside its values because there is nothing else to say.
function A.MergeScoreboard(m, rows, ourFaction)
    if not m or type(rows) ~= "table" then return 0 end
    local byName = {}
    for guid, seat in pairs(m.seats) do
        if seat.name then byName[ShortName(seat.name)] = seat end
    end
    local merged = 0
    for _, row in ipairs(rows) do
        local seat = row.name and byName[ShortName(row.name)]
        if not seat and row.name and type(ourFaction) == "number" and type(row.faction) == "number" then
            live = m -- SetSeat writes to the live match; the merge runs just before Finish
            seat = A.SetSeat(row.faction == ourFaction and "us" or "them",
                "Score-" .. ShortName(row.name), row.name, row.classToken, row.race)
            if seat then
                seat.fromScoreboard = true
                byName[ShortName(row.name)] = seat
            end
        end
        if seat then
            seat.sb = {
                kb = tonumber(row.kb) or 0, hk = tonumber(row.hk) or 0,
                deaths = tonumber(row.deaths) or 0,
                dmg = tonumber(row.dmg) or 0, heal = tonumber(row.heal) or 0,
                ratingChange = tonumber(row.ratingChange),
                mmr = tonumber(row.mmr),
            }
            if row.classToken and not seat.class then seat.class = row.classToken end
            if row.race and not seat.race then seat.race = row.race end
            merged = merged + 1
        end
    end
    m.scored = merged > 0
    -- A rating change on anyone marks the match rated
    if m.rated == nil then
        for _, seat in pairs(m.seats) do
            if seat.sb and seat.sb.ratingChange and seat.sb.ratingChange ~= 0 then
                m.rated = true
                break
            end
        end
    end
    return merged
end

-- Team info from GetBattlefieldTeamInfo: { name, before, after, mmr }
function A.SetTeamInfo(m, teamKey, info)
    if not m or type(info) ~= "table" then return end
    local tm = m.teams[teamKey]
    if not tm then return end
    if type(info.name) == "string" and info.name ~= "" then tm.name = info.name end
    if type(info.before) == "number" then tm.ratingBefore = info.before end
    if type(info.after) == "number" then tm.ratingAfter = info.after end
    if type(info.mmr) == "number" then tm.mmr = info.mmr end
    if tm.name or tm.ratingBefore then m.rated = true end
end

local function CloseOpen(m, t)
    for _, seat in pairs(m.seats) do
        for key in pairs(seat.openCC) do CloseCC(m, seat, key, t) end
        CloseDrink(m, seat, t)
        for name in pairs(seat.openAuras) do CloseAura(seat, name, t) end
        CloseCast(seat, t, "FAIL")
    end
end

-- result: "WIN" | "LOSS" | "DRAW" | "LEFT"; runTime = the server's match
-- age in seconds when known (the honest duration — our clock started when
-- we zoned in, before the gates).
function A.Finish(ts, result, runTime)
    local m = live
    if not m then return nil end
    live = nil
    -- The end can never precede the last event: the caller's clock is
    -- whole seconds, the log's carries milliseconds
    local t = max(Rel(m, ts), m.tLast)
    m.tEnd = t
    m.result = result or "LEFT"
    m.runTime = type(runTime) == "number" and runTime > 0 and runTime or nil
    -- A match with no gates and no blows was a queue we never really
    -- played (zoned in and out, a crash-and-relog): discard it outright
    local any = false
    for _, seat in pairs(m.seats) do
        if seat.dmg > 0 or seat.heal > 0 or seat.taken > 0 then any = true; break end
    end
    if not any and not m.tGates then
        matchCounter = matchCounter - 1
        if A.onMatchEnd then A.onMatchEnd(nil) end
        return nil
    end
    CloseOpen(m, t)
    m.dur = max(t - (m.tGates or 0), 1)
    Moment(m, t, "END", nil, nil, nil, m.result)
    table.insert(matches, 1, m)
    matches[MAX_MATCHES + 1] = nil
    if A.onMatchEnd then A.onMatchEnd(m) end
    return m
end

-- Leaving the arena with no winner declared
function A.Abort(ts)
    return A.Finish(ts, "LEFT", nil)
end

function A.ResetAll()
    live = nil
    for i = #matches, 1, -1 do matches[i] = nil end
    matchCounter = 0
end

-- ---------------------------------------------------------------------------
-- Reading a match: stats, cumulative values at a time, replay state
-- ---------------------------------------------------------------------------

-- The stat table. Each stat says how to read a seat's WHOLE-match value,
-- how to read it up to a bucket (the replay), what its rate is called,
-- and which breakdown lists the seat detail shows. Series-backed stats
-- sum their buckets; ledger-backed stats count moments up to the cursor.
local function SumTo(s, b)
    if not s then return 0 end
    local total = 0
    for i = 1, b do
        local v = s[i]
        if v then total = total + v end
    end
    return total
end

A.STATS = {
    { key = "DMG", label = "DAMAGE", rateLabel = "DPS", color = "statDmg",
        value = function(s) return s.dmg end,
        series = "sDmg",
        lists = { { title = "ABILITIES", field = "spells", records = true },
                  { title = "TARGETS", field = "targets" } } },
    { key = "HEAL", label = "HEALING", rateLabel = "HPS", color = "statHeal",
        value = function(s) return s.heal + s.absorb end,
        series = "sHeal",
        lists = { { title = "SPELLS", field = "heals", records = true } } },
    { key = "TAKEN", label = "DMG TAKEN", rateLabel = "DTPS", color = "statTaken",
        value = function(s) return s.taken end,
        series = "sTaken",
        lists = { { title = "HIT BY", field = "takenSpells", records = true },
                  { title = "SOURCES", field = "sources" } } },
    { key = "CC", label = "CONTROL", rateLabel = nil, color = "statCC", seconds = true,
        value = function(s) return s.ccSeconds end,
        count = function(s) return s.ccCasts end,
        ledger = "CC", ledgerSide = "src", ledgerSeconds = true,
        lists = { { title = "CC APPLIED", field = "ccSpells", records = true } } },
    { key = "KICKS", label = "KICKS", rateLabel = nil, color = "statUtil",
        value = function(s) return s.ints end,
        ledger = "KICK", ledgerSide = "src",
        lists = {} },
    { key = "DISPEL", label = "DISPELS", rateLabel = nil, color = "statUtil",
        value = function(s) return s.dispels + s.purges end,
        ledger = "DISPEL", ledgerSide = "src",
        lists = {} },
    { key = "KILLS", label = "KILLS", rateLabel = nil, color = "statDeath",
        value = function(s) return s.kills end,
        ledger = "DEATH", ledgerSide = "src",
        lists = {} },
    { key = "APM", label = "APM", rateLabel = "APM", rateScale = 60, color = "statApm",
        value = function(s) return s.casts end,
        series = "sCasts", primary = "rate",
        lists = { { title = "CASTS", field = "castSpells", records = true } } },
    { key = "MANA", label = "MANA DRAINED", rateLabel = nil, color = "statMana",
        value = function(s) return s.drained end,
        ledger = "DRAIN", ledgerSide = "src", ledgerAmount = true,
        lists = {} },
    { key = "CDS", label = "COOLDOWNS", rateLabel = nil, color = "statCd",
        value = function(s) return s.cds + s.trinkets end,
        ledger = { CD = true, TRINKET = true }, ledgerSide = "src",
        lists = {} },
}

function A.StatByKey(key)
    for _, s in ipairs(A.STATS) do
        if s.key == key then return s end
    end
    return A.STATS[1]
end

-- A seat's value for a stat up to time t (nil = whole match). Series
-- stats sum buckets; ledger stats count (or sum) moments. Returns value,
-- count (for stats that carry both, like CC: seconds and casts).
local function LedgerMatch(stat, e)
    local want = stat.ledger
    if type(want) == "table" then return want[e.kind] == true end
    return e.kind == want
end

-- Cumulative series for a CLOSED match, built once per seat and series
-- on first use (a closed match never changes): the replay asks for
-- "damage up to t" ten times a repaint at 10 Hz, and summing 1800
-- buckets each time was the one cost that scaled with the match. Live
-- matches sum directly — they are short and still growing. `_cum` is
-- session-only (stripped from the store).
local function CumulativeAt(m, seat, field, b)
    local s = seat[field]
    if not s then return 0 end
    if not m.tEnd then return SumTo(s, b) end
    local cache = seat._cum
    if not cache then cache = {}; seat._cum = cache end
    local cum = cache[field]
    if not cum then
        cum = {}
        local n = min(floor(m.tEnd) + 1, SERIES_CAP)
        local run = 0
        for i = 1, n do
            run = run + (s[i] or 0)
            cum[i] = run
        end
        cum.n = n
        cache[field] = cum
    end
    if b > cum.n then b = cum.n end
    if b < 1 then return 0 end
    return cum[b]
end

function A.SeatValueAt(m, seat, stat, t)
    if t == nil then
        return stat.value(seat), stat.count and stat.count(seat) or nil
    end
    if stat.series then
        local b = floor(t) + 1
        if b > SERIES_CAP then b = SERIES_CAP end
        return CumulativeAt(m, seat, stat.series, b), nil
    end
    local total, count = 0, 0
    for i = 1, m.ledgerN do
        local e = m.ledger[i]
        if e.t > t then break end
        if LedgerMatch(stat, e) and e[stat.ledgerSide] == seat.guid then
            count = count + 1
            if stat.ledgerSeconds then
                local t2 = e.t2 or (e.t + CC_OPEN_CAP)
                total = total + (min(t2, t) - e.t)
            elseif stat.ledgerAmount then
                total = total + (e.amount or 0)
            else
                total = total + 1
            end
        end
    end
    return total, stat.count and count or nil
end

-- The duration a rate divides by: from the gates to the cursor (or to
-- the end). Before the gates nothing has happened, so 1.
function A.DurationAt(m, t)
    local g = m.tGates or 0
    local e = t or m.tEnd or g
    return max(e - g, 1)
end

-- Rows for a bar pane or the team board: every seat, sorted by value,
-- friendly and enemy alike. `rowsOut` is reused between calls (2 Hz).
local rowsOut = {}

local function RowOrder(x, y)
    if x.seat == nil then return false end
    if y.seat == nil then return true end
    if x.value ~= y.value then return x.value > y.value end
    return (x.seat.name or "") < (y.seat.name or "")
end

-- Returns rows, n, totals = { us = v, them = v }, dur
local teamTotals = { us = 0, them = 0 }

-- Ledger stats for EVERY seat in one pass (a per-seat scan would walk
-- the ledger ten times per repaint). Fills valueBy/countBy keyed by guid.
local valueBy, countBy = {}, {}

local function LedgerValuesAt(m, stat, t)
    for k in pairs(valueBy) do valueBy[k] = nil end
    for k in pairs(countBy) do countBy[k] = nil end
    for i = 1, m.ledgerN do
        local e = m.ledger[i]
        if t and e.t > t then break end
        if LedgerMatch(stat, e) then
            local guid = e[stat.ledgerSide]
            if guid then
                countBy[guid] = (countBy[guid] or 0) + 1
                local add
                if stat.ledgerSeconds then
                    local t2 = e.t2 or (e.t + CC_OPEN_CAP)
                    add = (t and min(t2, t) or t2) - e.t
                elseif stat.ledgerAmount then
                    add = e.amount or 0
                else
                    add = 1
                end
                valueBy[guid] = (valueBy[guid] or 0) + add
            end
        end
    end
end

function A.CollectRows(m, stat, t)
    local n = 0
    teamTotals.us, teamTotals.them = 0, 0
    local dur = A.DurationAt(m, t)
    local scale = stat.rateScale or 1
    local ledgerStat = stat.ledger ~= nil and (t ~= nil or stat.ledgerSeconds)
    if ledgerStat then LedgerValuesAt(m, stat, t) end
    for _, seat in pairs(m.seats) do
        local v, count
        if ledgerStat then
            v = valueBy[seat.guid] or 0
            count = stat.count and (countBy[seat.guid] or 0) or nil
            if t == nil then
                -- Whole match: the counters are the truth (they include
                -- moments the ledger cap dropped); the pass only supplied
                -- the seconds, which the counter also carries
                v = stat.value(seat)
                count = stat.count and stat.count(seat) or nil
            end
        else
            v, count = A.SeatValueAt(m, seat, stat, t)
        end
        n = n + 1
        local row = rowsOut[n]
        if not row then row = {}; rowsOut[n] = row end
        row.seat = seat
        row.value = v
        row.count = count
        row.rate = v * scale / dur
        teamTotals[seat.team] = teamTotals[seat.team] + v
    end
    for i = n + 1, #rowsOut do rowsOut[i].seat = nil end
    table.sort(rowsOut, RowOrder)
    return rowsOut, n, teamTotals, dur
end

-- Replay state at time t: for every seat, hp fraction (last snapshot at or
-- before t; nil when none yet), alive, and the CC on them right then.
-- `out` is reused: out.seats[guid] = { hp, alive, cc = { name, cat, x } }.
local function SeatStateAt(m, seat, t, st)
    -- HP: walk back from the cursor's bucket to the last reading
    local hp
    local s = seat.sHp
    if s then
        local b = floor(t) + 1
        if b > SERIES_CAP then b = SERIES_CAP end
        for i = b, 1, -1 do
            local v = s[i]
            if v then hp = v / HP_SCALE; break end
        end
    end
    st.hp = hp
    -- Power, the same way
    local pow
    local sp = seat.sPow
    if sp then
        local b = floor(t) + 1
        if b > SERIES_CAP then b = SERIES_CAP end
        for i = b, 1, -1 do
            local v = sp[i]
            if v then pow = v / HP_SCALE; break end
        end
    end
    st.pow = pow
    st.powType = seat.powType
    -- The cast in progress at t, and the global cooldown: the last cast
    -- success within GCD seconds (a spectator's "they are locked out of
    -- their next button" sweep)
    st.cast = nil
    st.gcd = nil
    st.gcdCast = nil   -- the cast the running GCD was spent on
    st.target = nil
    for i = seat.castLogN, 1, -1 do
        local c = seat.castLog[i]
        if c.t <= t then
            local endT = c.t2 or (c.t + CAST_OPEN_CAP)
            if not c.instant and t < endT then
                st.cast = c
            end
            local fired = c.r == "OK" and (c.instant and c.t or c.t2)
            if fired and st.gcd == nil and t - fired < GCD then
                st.gcd = (t - fired) / GCD
                st.gcdCast = c
            end
            -- Who they are on: the target of the newest cast that had one
            -- within TARGET_MEMORY seconds
            if st.target == nil and c.tgt and t - c.t <= TARGET_MEMORY then
                st.target = c.tgt
            end
            if c.t < t - CAST_OPEN_CAP then break end
        end
    end
    -- Auras on the seat at t: newest first, buffs and debuffs apart
    st.buffs = st.buffs or {}
    st.debuffs = st.debuffs or {}
    st.feign = false
    local nb, nd = 0, 0
    for i = seat.aurasN, 1, -1 do
        local a = seat.auras[i]
        if a.t <= t and (a.t2 == nil or t < a.t2) then
            if a.feign then st.feign = true end
            if a.buff then
                nb = nb + 1
                st.buffs[nb] = a
            else
                nd = nd + 1
                st.debuffs[nd] = a
            end
        end
    end
    for i = nb + 1, #st.buffs do st.buffs[i] = nil end
    for i = nd + 1, #st.debuffs do st.debuffs[i] = nil end
    st.buffN, st.debuffN = nb, nd
    -- Alive: dead from the death moment until the end (arena deaths are
    -- final — no releases mid-match)
    local alive = true
    for i = 1, #m.deaths do
        local d = m.deaths[i]
        if d.guid == seat.guid and d.t <= t then alive = false; break end
    end
    st.alive = alive
    if not alive then st.hp = 0 end
    -- Control: open CC moments covering t
    local ccN = 0
    st.cc = st.cc or {}
    for i = 1, m.ledgerN do
        local e = m.ledger[i]
        if e.t > t then break end
        if e.kind == "CC" and e.dst == seat.guid then
            local t2 = e.t2 or (e.t + CC_OPEN_CAP)
            if t < t2 then
                ccN = ccN + 1
                st.cc[ccN] = e
            end
        end
    end
    for i = ccN + 1, #st.cc do st.cc[i] = nil end
    st.ccN = ccN
    -- Cooldowns still running at t: book presses and trinkets whose
    -- cooldown covers the cursor, newest first is not needed — the order
    -- of pressing is the order shown
    local cdN = 0
    st.cd = st.cd or {}
    st.cdLeft = st.cdLeft or {}
    for i = 1, m.ledgerN do
        local e = m.ledger[i]
        if e.t > t then break end
        if (e.kind == "CD" or e.kind == "TRINKET") and e.src == seat.guid and e.amount then
            local left = e.t + e.amount - t
            if left > 0 then
                cdN = cdN + 1
                st.cd[cdN] = e
                st.cdLeft[cdN] = left
            end
        end
    end
    for i = cdN + 1, #st.cd do st.cd[i] = nil; st.cdLeft[i] = nil end
    st.cdN = cdN
end

function A.StateAt(m, t, out)
    out.seats = out.seats or {}
    for guid, seat in pairs(m.seats) do
        local st = out.seats[guid]
        if not st then st = {}; out.seats[guid] = st end
        SeatStateAt(m, seat, t, st)
    end
    return out
end

-- Team pressure per bucket: damage dealt by each side per second, for
-- the mirrored timeline. `out.us[b]`, `out.them[b]` arrays sized to n.
-- `nBuckets` (optional) fixes the span: the window passes the bucket that
-- holds its end time so columns, markers and the cursor share one x scale
-- even while a live match sits in a lull nobody is hitting through.
function A.Pressure(m, out, nBuckets)
    local n = nBuckets or floor((m.tEnd or 0) + 0.999)
    if not nBuckets and live == m then
        -- Live: the newest bucket any seat has written
        for _, seat in pairs(m.seats) do
            local s = seat.sDmg
            if s then
                for b in pairs(s) do if b > n then n = b end end
            end
        end
    end
    if n > SERIES_CAP then n = SERIES_CAP end
    if n < 1 then n = 1 end
    out.us = out.us or {}
    out.them = out.them or {}
    for b = 1, n do out.us[b] = 0; out.them[b] = 0 end
    for i = n + 1, #out.us do out.us[i] = nil end
    for i = n + 1, #out.them do out.them[i] = nil end
    local peak = 0
    for _, seat in pairs(m.seats) do
        local s = seat.sDmg
        if s then
            local arr = out[seat.team]
            for b, v in pairs(s) do
                if b <= n then
                    local nv = arr[b] + v
                    arr[b] = nv
                    if nv > peak then peak = nv end
                end
            end
        end
    end
    out.n = n
    out.peak = peak
    return out
end

-- The moments around a time: indexes of the ledger entries in [t0, t1],
-- with the first index at or after `t`. Used by the timeline's ledger
-- list, which centers on the cursor.
function A.LedgerIndexAt(m, t)
    local lo, hi = 1, m.ledgerN
    local ans = m.ledgerN + 1
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        if m.ledger[mid].t >= t then
            ans = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    return ans
end

-- Seat lookups the window layer needs by name (tooltips, scoreboard)
function A.SeatName(m, guid)
    local seat = guid and m.seats[guid]
    return seat and seat.name or nil
end

-- ---------------------------------------------------------------------------
-- Insights: the match read back as findings. Pure derivation from what the
-- ledger and the seats already hold — nothing here is a new measurement,
-- which is why every line can point at the moment it came from.
--
-- Records (out[1..n], out.n): timed ones first in clock order, summaries
-- after. Fields by kind:
--   FIRSTBLOOD  t, guid
--   KILL        t, guid (victim), killer, blow, controlled = { {guid, name, dur} }
--               — the victim's TEAMMATES under control inside the last
--               KILL_CC_WINDOW seconds: "the healer was sheeped for 4.2 s"
--   OWNBREAK    t, guid (breaker), victim, aura, caster
--   TRINKET     t, guid, aura (the control it ended, when one closed then)
--   WASTED      guid, count
--   DRINK       guid, count, seconds
--   SHARE       team, guid, pct, stat ("DMG" | "HEAL") — the team's top seat
--   CCTIME      us, them (seconds)
--   KICKS       us, them (interrupts landed)
--   PURGES      us, them
-- ---------------------------------------------------------------------------

local function InsightOrder(x, y)
    local tx, ty = x.t or math.huge, y.t or math.huge
    if tx ~= ty then return tx < ty end
    return (x.seq or 0) < (y.seq or 0)
end

function A.Insights(m, out)
    local n = 0
    local function add(rec)
        n = n + 1
        rec.seq = n
        out[n] = rec
    end
    if m.firstBlood then
        add({ kind = "FIRSTBLOOD", t = m.firstBlood.t, guid = m.firstBlood.guid })
    end
    for _, d in ipairs(m.deaths) do
        local rec = { kind = "KILL", t = d.t, guid = d.guid, killer = d.killer, blow = d.name, controlled = {} }
        local victim = m.seats[d.guid]
        for i = 1, m.ledgerN do
            local e = m.ledger[i]
            if e.t > d.t then break end
            if e.kind == "CC" and e.dst ~= d.guid and victim then
                local ds = m.seats[e.dst]
                if ds and ds.team == victim.team then
                    local t2 = e.t2 or (e.t + CC_OPEN_CAP)
                    local from = max(e.t, d.t - KILL_CC_WINDOW)
                    local till = min(t2, d.t)
                    if till > from then
                        rec.controlled[#rec.controlled + 1] = { guid = e.dst, name = e.name, dur = till - from }
                    end
                end
            end
        end
        add(rec)
    end
    for i = 1, m.ledgerN do
        local e = m.ledger[i]
        if e.kind == "CC" and e.own then
            add({ kind = "OWNBREAK", t = e.t2 or e.t, guid = e.brk, victim = e.dst, aura = e.name, caster = e.src })
        elseif e.kind == "TRINKET" then
            local aura
            for j = i - 1, 1, -1 do
                local c = m.ledger[j]
                if c.kind == "CC" and c.dst == e.src and c.t2 and math.abs(c.t2 - e.t) <= 0.5 then
                    aura = c.name
                    break
                end
                if c.t < e.t - CC_OPEN_CAP then break end
            end
            add({ kind = "TRINKET", t = e.t, guid = e.src, aura = aura })
        end
    end
    -- Per-seat summaries, in a stable order (seating order per team)
    for _, teamKey in ipairs(RATED_TEAMS) do
        local tm = m.teams[teamKey]
        for i = 1, tm.n do
            local seat = m.seats[tm.order[i]]
            if seat then
                if seat.ccWasted > 0 then add({ kind = "WASTED", guid = seat.guid, count = seat.ccWasted }) end
                if seat.drinks > 0 then add({ kind = "DRINK", guid = seat.guid, count = seat.drinks, seconds = seat.drinkSeconds }) end
            end
        end
    end
    -- Shares: each team's top damage and top healing seat
    for _, statKey in ipairs({ "DMG", "HEAL" }) do
        for _, teamKey in ipairs(RATED_TEAMS) do
            local best, bestV, total = nil, 0, 0
            for _, seat in pairs(m.seats) do
                if seat.team == teamKey then
                    local v = statKey == "DMG" and seat.dmg or (seat.heal + seat.absorb)
                    total = total + v
                    if v > bestV or (v == bestV and best and (seat.name or "") < (best.name or "")) then
                        best, bestV = seat, v
                    end
                end
            end
            if best and total > 0 then
                add({ kind = "SHARE", team = teamKey, guid = best.guid, pct = bestV / total * 100, stat = statKey, value = bestV })
            end
        end
    end
    local cc, kicks, purges = { us = 0, them = 0 }, { us = 0, them = 0 }, { us = 0, them = 0 }
    for _, seat in pairs(m.seats) do
        cc[seat.team] = cc[seat.team] + seat.ccSeconds
        kicks[seat.team] = kicks[seat.team] + seat.ints
        purges[seat.team] = purges[seat.team] + seat.purges
    end
    if cc.us + cc.them > 0 then add({ kind = "CCTIME", us = cc.us, them = cc.them }) end
    if kicks.us + kicks.them > 0 then add({ kind = "KICKS", us = kicks.us, them = kicks.them }) end
    if purges.us + purges.them > 0 then add({ kind = "PURGES", us = purges.us, them = purges.them }) end
    for i = n + 1, #out do out[i] = nil end
    table.sort(out, InsightOrder)
    out.n = n
    return out
end

-- ---------------------------------------------------------------------------
-- History: the kept matches read together. Records (out[1..n], out.n):
--   RECORD     played, wins, losses, left
--   RATING     delta, from, to  (our team's rating across rated matches)
--   BRACKET    size, played, wins
--   COMP       comp ("DRUID/WARLOCK/WARRIOR"), played, wins, losses
--   MAP        map, played, wins
--   TIMING     avgDur, avgFirstBlood (matches with one), n
--   FIRSTBLOOD drew, wonWhenDrew, gave, wonWhenGave
-- ---------------------------------------------------------------------------

local function CompKey(m)
    local tm = m.teams.them
    if tm.n == 0 then return nil end
    local classes = {}
    for i = 1, tm.n do
        local seat = m.seats[tm.order[i]]
        classes[#classes + 1] = seat and seat.class or "?"
    end
    table.sort(classes)
    return table.concat(classes, "/")
end

local function OurRatingMove(m)
    local tm = m.teams.us
    if tm.ratingBefore and tm.ratingAfter then return tm.ratingBefore, tm.ratingAfter end
    for _, seat in pairs(m.seats) do
        if seat.team == "us" and seat.token == "player" and seat.sb and seat.sb.ratingChange then
            return nil, nil, seat.sb.ratingChange
        end
    end
    return nil
end

function A.History(list, out)
    local n = 0
    local function add(rec) n = n + 1; out[n] = rec end
    local rec = { kind = "RECORD", played = 0, wins = 0, losses = 0, left = 0 }
    local byBracket, byComp, byMap = {}, {}, {}
    local durSum, durN, fbSum, fbN = 0, 0, 0, 0
    local fb = { kind = "FIRSTBLOOD", drew = 0, wonWhenDrew = 0, gave = 0, wonWhenGave = 0 }
    local ratingDelta, ratingFrom, ratingTo, rated = 0, nil, nil, 0
    for i = #list, 1, -1 do -- oldest first, so the rating trend runs forward
        local m = list[i]
        rec.played = rec.played + 1
        local won = m.result == "WIN"
        if won then rec.wins = rec.wins + 1
        elseif m.result == "LOSS" then rec.losses = rec.losses + 1
        else rec.left = rec.left + 1 end
        if m.bracket > 0 then
            local b = byBracket[m.bracket]
            if not b then b = { kind = "BRACKET", size = m.bracket, played = 0, wins = 0 }; byBracket[m.bracket] = b end
            b.played = b.played + 1
            if won then b.wins = b.wins + 1 end
        end
        local comp = CompKey(m)
        if comp then
            local c = byComp[comp]
            if not c then c = { kind = "COMP", comp = comp, played = 0, wins = 0, losses = 0 }; byComp[comp] = c end
            c.played = c.played + 1
            if won then c.wins = c.wins + 1 elseif m.result == "LOSS" then c.losses = c.losses + 1 end
        end
        if m.map then
            local mp = byMap[m.map]
            if not mp then mp = { kind = "MAP", map = m.map, played = 0, wins = 0 }; byMap[m.map] = mp end
            mp.played = mp.played + 1
            if won then mp.wins = mp.wins + 1 end
        end
        if m.dur and m.dur > 0 and m.result ~= "LEFT" then
            durSum = durSum + m.dur
            durN = durN + 1
        end
        if m.firstBlood then
            fbSum = fbSum + (m.firstBlood.t - (m.tGates or 0))
            fbN = fbN + 1
            local victim = m.seats[m.firstBlood.guid]
            if victim and victim.team == "them" then
                fb.drew = fb.drew + 1
                if won then fb.wonWhenDrew = fb.wonWhenDrew + 1 end
            elseif victim then
                fb.gave = fb.gave + 1
                if won then fb.wonWhenGave = fb.wonWhenGave + 1 end
            end
        end
        local before, after, change = OurRatingMove(m)
        if before and after then
            rated = rated + 1
            ratingFrom = ratingFrom or before
            ratingTo = after
            ratingDelta = ratingDelta + (after - before)
        elseif change then
            rated = rated + 1
            ratingDelta = ratingDelta + change
        end
    end
    add(rec)
    if rated > 0 then add({ kind = "RATING", delta = ratingDelta, from = ratingFrom, to = ratingTo, n = rated }) end
    if durN > 0 or fbN > 0 then
        add({ kind = "TIMING", avgDur = durN > 0 and durSum / durN or nil, avgFirstBlood = fbN > 0 and fbSum / fbN or nil, n = durN })
    end
    if fb.drew + fb.gave > 0 then add(fb) end
    local sizes = {}
    for size in pairs(byBracket) do sizes[#sizes + 1] = size end
    table.sort(sizes)
    for _, size in ipairs(sizes) do add(byBracket[size]) end
    local comps = {}
    for _, c in pairs(byComp) do comps[#comps + 1] = c end
    table.sort(comps, function(x, y)
        if x.played ~= y.played then return x.played > y.played end
        return x.comp < y.comp
    end)
    for _, c in ipairs(comps) do add(c) end
    local maps = {}
    for _, mp in pairs(byMap) do maps[#maps + 1] = mp end
    table.sort(maps, function(x, y)
        if x.played ~= y.played then return x.played > y.played end
        return x.map < y.map
    end)
    for _, mp in ipairs(maps) do add(mp) end
    for i = n + 1, #out do out[i] = nil end
    out.n = n
    return out
end

-- ---------------------------------------------------------------------------
-- Persistence: closed matches survive a /reload and a logout, so a night
-- of arenas can be reviewed the next day. Written ONCE at PLAYER_LOGOUT
-- (SavedVariables flush there and nowhere else). Import validates every
-- match's shape and refuses anything malformed — never guessed at.
-- ---------------------------------------------------------------------------

local STORE_V = 1

-- Live bookkeeping fields that must not persist (open indexes, DR clocks)
local function Strip(m)
    for _, seat in pairs(m.seats) do
        seat.openCC = {}
        seat.openDrink = nil
        seat.openCast = nil
        seat.openAuras = {}
        seat.lastHit = nil
        seat.deathClosed = nil
        seat.dr = {}
        seat._cum = nil
    end
end

function A.Export(keep)
    keep = tonumber(keep) or 0
    local out = { v = STORE_V, matches = {} }
    for i = 1, min(keep, #matches) do
        Strip(matches[i])
        out.matches[i] = matches[i]
    end
    return out
end

local function ValidMatch(m)
    if type(m) ~= "table" or type(m.seats) ~= "table" or type(m.teams) ~= "table"
        or type(m.ledger) ~= "table" or type(m.ledgerN) ~= "number"
        or type(m.dur) ~= "number" or type(m.tsStart) ~= "number"
        or type(m.deaths) ~= "table" or type(m.id) ~= "number" then
        return false
    end
    if type(m.teams.us) ~= "table" or type(m.teams.them) ~= "table" then return false end
    for guid, seat in pairs(m.seats) do
        if type(guid) ~= "string" or type(seat) ~= "table" or type(seat.dmg) ~= "number"
            or type(seat.spells) ~= "table" or (seat.team ~= "us" and seat.team ~= "them") then
            return false
        end
        -- Restore the live bookkeeping an old store stripped, and the
        -- replay records a pre-replay store never had
        seat.openCC = seat.openCC or {}
        seat.dr = seat.dr or {}
        seat.openAuras = seat.openAuras or {}
        seat.castLog = seat.castLog or {}
        seat.castLogN = seat.castLogN or 0
        seat.auras = seat.auras or {}
        seat.aurasN = seat.aurasN or 0
        seat.auraDropped = seat.auraDropped or 0
    end
    return true
end

-- Returns the number of matches adopted. Imported matches sit BEHIND any
-- the session already closed and keep their ids; the counter continues
-- past the highest id seen.
-- STORE_MIGRATIONS[v] upgrades a store from version v to v+1, the settings
-- DB's ladder pattern: a future reshape ships as a step, and an older store
-- keeps its matches. A store NEWER than this code is refused (never guessed).
local STORE_MIGRATIONS = {}

function A.Import(store)
    if type(store) ~= "table" or type(store.v) ~= "number" or type(store.matches) ~= "table" then
        return 0
    end
    if store.v > STORE_V then return 0 end
    local v = store.v
    while v < STORE_V do
        local step = STORE_MIGRATIONS[v]
        if not step then return 0 end
        step(store)
        v = v + 1
    end
    store.v = STORE_V
    local adopted = 0
    local top = matchCounter
    for _, m in ipairs(store.matches) do
        if ValidMatch(m) and #matches < MAX_MATCHES then
            matches[#matches + 1] = m
            adopted = adopted + 1
            if m.id > top then top = m.id end
        end
    end
    matchCounter = top
    return adopted
end

-- ---------------------------------------------------------------------------
-- Deterministic serialization (harness instrument, like the core engine's)
-- ---------------------------------------------------------------------------

local function SerializeInto(out, value, indent)
    local t = type(value)
    if t == "number" then
        out[#out + 1] = string.format("%.14g", value)
    elseif t == "string" then
        out[#out + 1] = string.format("%q", value)
    elseif t == "boolean" then
        out[#out + 1] = tostring(value)
    elseif t == "table" then
        local keys = {}
        for k in pairs(value) do keys[#keys + 1] = k end
        table.sort(keys, function(x, y)
            local tx, ty = type(x), type(y)
            if tx ~= ty then return tx < ty end
            return x < y
        end)
        out[#out + 1] = "{"
        for _, k in ipairs(keys) do
            out[#out + 1] = "\n" .. indent .. "  [" ..
                (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "]="
            SerializeInto(out, value[k], indent .. "  ")
        end
        out[#out + 1] = "}"
    else
        out[#out + 1] = "?"
    end
end

function A.Serialize(m)
    local out = {}
    SerializeInto(out, m, "")
    return table.concat(out)
end
