-- Commander Meters: the data engine — combat-log ingestion, entity
-- resolution, the actor/ability/target model, per-second time series,
-- fight segmentation, and the mode table.
--
-- This file owns every number the meter ever shows and touches no frames,
-- so the whole layer runs headless under the luajit harness. All timing
-- flows through combat-log timestamps (epoch seconds) plus an explicit
-- Tick(now); GetTime() is never consulted, which is what makes fixture
-- replays byte-identical.
--
-- Attribution model, in one place:
--   * Damage done = landed amount + absorbed portion (a shield eating your
--     hit does not erase your hit). A fully absorbed swing arrives as a
--     _MISSED event with missType ABSORB and is credited the same way.
--   * Pets, guardians, and totems fold into their owner, exactly once,
--     with the contribution kept visible as "PetName: Ability". Ownership
--     comes from SPELL_SUMMON plus the UNIT_PET roster map — never from
--     display names.
--   * Healing = effective amount (overheal excluded, tracked separately)
--     plus absorbs credited to the shield's caster via SPELL_ABSORBED.
--   * Events with no fight open are dropped (damage OPENS a fight, heals
--     never do), so Overall is exactly the sum of its segments.

CommanderMetersEngine = {}
local E = CommanderMetersEngine

local band = bit.band
local floor = math.floor
local max = math.max

-- ---------------------------------------------------------------------------
-- Tuning constants (documented in DECISIONS.md; deliberately not settings)
-- ---------------------------------------------------------------------------

local MAX_FIGHTS = 10          -- closed fights retained (Fight #N ring)
local NAME_CAP = 60            -- distinct names per target/source/enemy map
local OTHER_NAMES = "(other)"  -- overflow bucket once a name map hits the cap
local MAX_SERIES_FIGHTS = 5    -- newest closed fights that keep their graphs
local MAX_SERIES_BUCKETS = 3600 -- 1h of 1s buckets; beyond that a fight stops graphing
local ACTIVE_GAP = 5           -- max gap (s) merged into an actor's active time
local RING_SIZE = 10           -- death log: events kept per player
local OWNER_MAP_LIMIT = 400    -- prune threshold for the pet->owner map
local OWNER_MAP_TTL = 600      -- owner entries idle this long are prunable
local CAPTURE_LIMIT = 2000     -- raw-event debug dump cap

-- Combat-log flag masks (native constants when the client provides them)
local AFFIL_GROUP = (COMBATLOG_OBJECT_AFFILIATION_MINE or 0x1)
    + (COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x2)
    + (COMBATLOG_OBJECT_AFFILIATION_RAID or 0x4)
local TYPE_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER or 0x400
local TYPE_MINION = (COMBATLOG_OBJECT_TYPE_PET or 0x1000)
    + (COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x2000)
    + (COMBATLOG_OBJECT_TYPE_OBJECT or 0x4000)

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local db                      -- CommanderMetersDB (settings; read-only here)
local overall                 -- the Overall segment (series-free)
local current                 -- open fight segment or nil
local fights = {}             -- closed fights, newest first (fights[1] = Last)
local fightCounter = 0
local overallDur = 0          -- sum of closed fight durations
local lastEventTs = 0         -- last group-relevant combat event (fight end stamp)
local lastActivityTs = 0      -- idle-timer clock (events + leaving combat)
local playerInCombat = false

local ownerOf = {}            -- minion GUID -> owner GUID
local ownerSeen = {}          -- minion GUID -> last use ts (for pruning)
local petNames = {}           -- minion GUID -> name (for "Pet: Ability" keys)
local ownerCount = 0

local tokenOf = {}            -- player GUID -> unit token ("raid7"), roster-fed
local classOf = {}            -- player GUID -> class token, roster-fed
local nameOf = {}             -- player GUID -> name, roster-fed

local petKeyCache = {}        -- petName -> spellName -> "petName: spellName"

local capture = nil           -- raw-event dump target (debug command)
local anomalies = {}          -- anomaly -> count; parse failures are loud, not silent
local ccNames = {}            -- CC aura names (UI resolves from spell IDs at login)

-- Both the live fight and Overall receive every credit; this pair is the
-- crediting loops' whole world. [1] is refreshed per event, [2] on reset.
local segPair = { nil, nil }

E.onFightStart = nil          -- UI hooks (auto-switch, chrome refresh)
E.onFightEnd = nil            -- receives the closed segment, or nil if it
                              -- was empty and discarded

-- ---------------------------------------------------------------------------
-- Records
-- ---------------------------------------------------------------------------

local function NewSegment(id, ts, wantSeries)
    return {
        id = id,                -- 0 = Overall
        name = nil,             -- resolved at close (or by ENCOUNTER_START)
        tsStart = ts,
        tsEnd = nil,
        dur = 0,
        series = wantSeries,
        actors = {},            -- guid -> actor
        enemies = {},           -- enemy name -> event tally (fight naming)
        enemiesN = 0,           -- distinct enemy names (NAME_CAP bound)
        deaths = {},            -- {ts, guid, name, log = {...}} in order
        totals = { dmg = 0, heal = 0, dtaken = 0, deaths = 0 },
    }
end

local function NewActor(guid, name, class, isPlayer)
    return {
        guid = guid, name = name, class = class, isPlayer = isPlayer,
        dmg = 0, absorbed = 0, dtaken = 0,
        heal = 0, overheal = 0, absorb = 0,
        deaths = 0,
        ints = 0, dispels = 0, ccb = 0, -- utility counters
        activeDmg = 0, lastDmgTs = nil,
        activeHeal = 0, lastHealTs = nil,
        spells = {},            -- key -> ability record (damage done)
        targets = {},           -- name -> damage done to it (NAME_CAP bound)
        targetsN = 0,
        taken = {},             -- key -> ability record (damage taken)
        sources = {},           -- name -> damage taken from it (NAME_CAP bound)
        sourcesN = 0,
        heals = {},             -- key -> ability record (healing done)
        intSpells = {},         -- interrupted spell name -> count record
        dispelSpells = {},      -- dispelled aura name -> count record
        ccSpells = {},          -- broken CC aura name -> count record
        sDmg = nil, sHeal = nil, sTaken = nil, -- 1s buckets, created on demand
        ring = nil, ringN = 0, ringI = 0, -- death-log ring (players only)
    }
end

-- id = the first-seen spellId (ranks share icons, so first-wins is fine);
-- nil for melee and environmental. The UI resolves icons from it.
local function NewAbility(name, pet, id)
    return { name = name, pet = pet, id = id, total = 0, count = 0, crit = 0,
        miss = 0, min = nil, max = nil, absorbed = 0, overheal = 0,
        glance = 0, crush = 0, resisted = 0, blocked = 0 }
end

local function Anomaly(key)
    local n = (anomalies[key] or 0) + 1
    anomalies[key] = n
    if n == 1 then
        print("Commander Meters: " .. key .. " — data for this case is being skipped, not guessed. /cmeters health shows counts.")
    end
end

E.GetAnomalies = function() return anomalies end

-- CC-break filtering: only breaks of these aura names count (the UI feeds
-- locale-safe names resolved from base spell IDs at login)
function E.SetCCNames(names)
    ccNames = names or {}
end

-- ---------------------------------------------------------------------------
-- Entity resolution
-- ---------------------------------------------------------------------------

-- Resolve a combat-log source/dest to the actor identity it should be
-- credited to. Returns nil when the unit is not part of the group's story,
-- else guid, name, class, isPlayer, petName (petName non-nil when this was
-- a minion folded into its owner).
local function ResolveOwner(guid, name, flags)
    if band(flags, AFFIL_GROUP) == 0 then return nil end
    if band(flags, TYPE_PLAYER) ~= 0 then
        return guid, name, classOf[guid], true, nil
    end
    if band(flags, TYPE_MINION) ~= 0 then
        local owner = ownerOf[guid]
        if owner then
            ownerSeen[guid] = lastEventTs
            return owner, nil, classOf[owner], true, petNames[guid] or name
        end
        -- Unknown owner: keep the minion visible as its own actor rather
        -- than guessing an owner or silently dropping its damage.
        Anomaly("minion with unknown owner (" .. (name or "?") .. ")")
        return guid, name, nil, false, nil
    end
    return nil
end

function E.SetOwner(minionGuid, ownerGuid, minionName, ts)
    if not minionGuid or not ownerGuid or minionGuid == ownerGuid then return end
    if not ownerOf[minionGuid] then
        ownerCount = ownerCount + 1
    end
    ownerOf[minionGuid] = ownerGuid
    -- Stamp with the caller's clock: a pet mapped during a lull must not
    -- inherit the last combat event's stale time, or the next prune pass
    -- strips a live pet's ownership
    ownerSeen[minionGuid] = ts or lastEventTs
    if minionName then petNames[minionGuid] = minionName end
end

function E.SetRosterEntry(guid, token, name, class)
    if not guid then return end
    tokenOf[guid] = token
    if class then classOf[guid] = class end
    if name then nameOf[guid] = name end
    -- Late roster knowledge: fix up actor records created before the scan
    -- saw this player (class tint, or an owner named only by a pet's event)
    local a = overall.actors[guid]
    if a then
        if not a.class and class then a.class = class end
        if a.namePending and name then a.name = name; a.namePending = nil end
    end
    if current then
        a = current.actors[guid]
        if a then
            if not a.class and class then a.class = class end
            if a.namePending and name then a.name = name; a.namePending = nil end
        end
    end
end

function E.ClearRoster()
    for k in pairs(tokenOf) do tokenOf[k] = nil end
end

local function PruneOwners(now)
    if ownerCount <= OWNER_MAP_LIMIT then return end
    for guid, seen in pairs(ownerSeen) do
        if now - seen > OWNER_MAP_TTL then
            ownerOf[guid] = nil
            ownerSeen[guid] = nil
            petNames[guid] = nil
            ownerCount = ownerCount - 1
        end
    end
end

local function PetKey(petName, spellName)
    local perPet = petKeyCache[petName]
    if not perPet then
        perPet = {}
        petKeyCache[petName] = perPet
    end
    local key = perPet[spellName]
    if not key then
        key = petName .. ": " .. spellName
        perPet[spellName] = key
    end
    return key
end

-- ---------------------------------------------------------------------------
-- Segment lifecycle
-- ---------------------------------------------------------------------------

local function OpenFight(ts)
    -- Optional trigger (off by default): a new fight wipes everything, so
    -- the meter only ever shows the pull you are on. Done here, inline,
    -- because resetting from the fight-start callback would re-enter.
    if db.AutoResetOnNewFight and (fights[1] or overall.totals.dmg > 0
        or overall.totals.heal > 0 or overall.totals.dtaken > 0) then
        overall = NewSegment(0, ts, false)
        segPair[2] = overall
        for i = #fights, 1, -1 do fights[i] = nil end
        fightCounter = 0
        overallDur = 0
    end
    fightCounter = fightCounter + 1
    current = NewSegment(fightCounter, ts, true)
    if E.onFightStart then E.onFightStart() end
end

local function BestEnemy(seg)
    -- Deterministic argmax: highest tally, ties broken by name. The
    -- overflow bucket never names a fight.
    local bestName, bestCount
    for name, count in pairs(seg.enemies) do
        if name ~= OTHER_NAMES and (not bestCount or count > bestCount
            or (count == bestCount and name < bestName)) then
            bestName, bestCount = name, count
        end
    end
    return bestName
end

local function CloseFight()
    local seg = current
    current = nil
    -- A segment that never recorded anything (a reset right before the idle
    -- close, say) is discarded outright — no phantom "Skirmish" entries
    local t = seg.totals
    if t.dmg == 0 and t.heal == 0 and t.dtaken == 0 and t.deaths == 0 then
        fightCounter = fightCounter - 1
        if E.onFightEnd then E.onFightEnd(nil) end
        return
    end
    seg.tsEnd = lastEventTs
    seg.dur = max(seg.tsEnd - seg.tsStart, 1)
    seg.name = seg.name or BestEnemy(seg) or "Skirmish"
    overallDur = overallDur + seg.dur
    table.insert(fights, 1, seg)
    -- Retention: graphs on the newest MAX_SERIES_FIGHTS, everything on the
    -- newest MAX_FIGHTS, nothing beyond that.
    local drop = fights[MAX_SERIES_FIGHTS + 1]
    if drop and drop.series then
        drop.series = false
        for _, actor in pairs(drop.actors) do
            actor.sDmg = nil
            actor.sHeal = nil
            actor.sTaken = nil
        end
    end
    fights[MAX_FIGHTS + 1] = nil
    PruneOwners(lastEventTs)
    if E.onFightEnd then E.onFightEnd(seg) end
end

-- Idle detection: a fight closes when the player is out of combat and no
-- group-relevant event has arrived for IdleTimeout seconds. The close is
-- stamped at the LAST event (not the idle deadline), so idle time never
-- pads the fight's duration.
function E.Tick(now)
    if current and not playerInCombat
        and now - lastActivityTs >= (db.IdleTimeout or 3) then
        CloseFight()
    end
end

function E.SetPlayerCombat(inCombat, now)
    playerInCombat = inCombat
    if not inCombat and current and now then
        -- Leaving combat arms the idle timer from now; the fight-end stamp
        -- stays on the last real event
        lastActivityTs = max(lastActivityTs, now)
    end
end

function E.OnEncounterStart(name)
    -- Encounter events are a naming refinement, never a segment boundary:
    -- segmentation must survive on clients where they do not exist.
    if current and name then
        current.name = name
    end
end

-- Kill/wipe tagging. ENCOUNTER_END can fire while the fight is still open
-- (boss dead, combat not yet dropped) or just after the idle close — accept
-- either, but never rewrite older history.
function E.OnEncounterEnd(name, success, now)
    local seg = current
    if not seg then
        local newest = fights[1]
        if newest and newest.tsEnd and now - newest.tsEnd <= 10 then
            seg = newest
        end
    end
    if seg and name then
        seg.name = name
        seg.success = success == 1
    end
end

-- ---------------------------------------------------------------------------
-- Crediting
-- ---------------------------------------------------------------------------

local function GetActor(seg, guid, name, class, isPlayer)
    local a = seg.actors[guid]
    if not a then
        a = NewActor(guid, name, class, isPlayer)
        seg.actors[guid] = a
    elseif name and a.name ~= name then
        a.name = name
    end
    return a
end

-- The owner keeps its own name; a folded pet must never rename the actor
local function GetOwnerActor(seg, guid, name, class, isPlayer, petName)
    local a = seg.actors[guid]
    if a then
        if not a.class and class then a.class = class end
        if a.namePending and name then a.name = name; a.namePending = nil end
        return a
    end
    a = NewActor(guid, name, class, isPlayer)
    if petName and not name then
        -- A pet acting before its owner did: the event names the pet, not
        -- the owner — take the owner's name from the roster or mark it
        -- pending until a direct event supplies it
        a.name = nameOf[guid] or "Unknown"
        a.namePending = nameOf[guid] == nil or nil
    end
    seg.actors[guid] = a
    return a
end

-- Name-keyed maps (targets/sources/enemies) are fed by enemy DISPLAY names,
-- which an evening of battlegrounds makes unbounded — past the cap, new
-- names fold into one "(other)" bucket so every sum invariant still holds.
local function Tally(map, key, amount, owner, counterField)
    if map[key] ~= nil then
        map[key] = map[key] + amount
        return
    end
    local n = owner[counterField]
    if n < NAME_CAP then
        owner[counterField] = n + 1
        map[key] = amount
    else
        map[OTHER_NAMES] = (map[OTHER_NAMES] or 0) + amount
    end
end

local function Bucket(seg, ts)
    local b = floor(ts - seg.tsStart) + 1
    if b < 1 then b = 1 end
    if b > MAX_SERIES_BUCKETS then return nil end
    return b
end

local function CreditDamage(seg, guid, name, class, isPlayer, petName,
        ts, key, spellName, targetName, amount, crit, id)
    local a = GetOwnerActor(seg, guid, name, class, isPlayer, petName)
    a.dmg = a.dmg + amount
    seg.totals.dmg = seg.totals.dmg + amount
    local rec = a.spells[key]
    if not rec then
        rec = NewAbility(spellName, petName, id)
        a.spells[key] = rec
    end
    rec.total = rec.total + amount
    rec.count = rec.count + 1
    if crit then rec.crit = rec.crit + 1 end
    if not rec.min or amount < rec.min then rec.min = amount end
    if not rec.max or amount > rec.max then rec.max = amount end
    Tally(a.targets, targetName, amount, a, "targetsN")
    -- Active time: merge gaps up to ACTIVE_GAP into the actor's activity
    local last = a.lastDmgTs
    if last then
        local gap = ts - last
        if gap > 0 and gap <= ACTIVE_GAP then
            a.activeDmg = a.activeDmg + gap
        end
    end
    a.lastDmgTs = ts
    if seg.series then
        local b = Bucket(seg, ts)
        if b then
            local s = a.sDmg
            if not s then s = {}; a.sDmg = s end
            s[b] = (s[b] or 0) + amount
        end
    end
    return rec
end

local function CreditHealing(seg, guid, name, class, isPlayer, petName,
        ts, key, spellName, effective, over, crit, isAbsorb, id)
    local a = GetOwnerActor(seg, guid, name, class, isPlayer, petName)
    if isAbsorb then
        a.absorb = a.absorb + effective
    else
        a.heal = a.heal + effective
        a.overheal = a.overheal + over
    end
    seg.totals.heal = seg.totals.heal + effective
    local rec = a.heals[key]
    if not rec then
        rec = NewAbility(spellName, petName, id)
        a.heals[key] = rec
    end
    rec.total = rec.total + effective
    rec.count = rec.count + 1
    rec.overheal = rec.overheal + over
    if crit then rec.crit = rec.crit + 1 end
    if not rec.min or effective < rec.min then rec.min = effective end
    if not rec.max or effective > rec.max then rec.max = effective end
    local last = a.lastHealTs
    if last then
        local gap = ts - last
        if gap > 0 and gap <= ACTIVE_GAP then
            a.activeHeal = a.activeHeal + gap
        end
    end
    a.lastHealTs = ts
    if seg.series then
        local b = Bucket(seg, ts)
        if b then
            local s = a.sHeal
            if not s then s = {}; a.sHeal = s end
            s[b] = (s[b] or 0) + effective
        end
    end
end

local function CreditTaken(seg, guid, name, class, ts, key, spellName,
        sourceName, amount, crit, absorbed, id)
    local a = GetActor(seg, guid, name, class, true)
    a.dtaken = a.dtaken + amount
    seg.totals.dtaken = seg.totals.dtaken + amount
    local rec = a.taken[key]
    if not rec then
        rec = NewAbility(spellName, nil, id)
        a.taken[key] = rec
    end
    rec.total = rec.total + amount
    rec.count = rec.count + 1
    if crit then rec.crit = rec.crit + 1 end
    if absorbed and absorbed > 0 then rec.absorbed = rec.absorbed + absorbed end
    if not rec.min or amount < rec.min then rec.min = amount end
    if not rec.max or amount > rec.max then rec.max = amount end
    Tally(a.sources, sourceName, amount, a, "sourcesN")
    if seg.series then
        local b = Bucket(seg, ts)
        if b then
            local s = a.sTaken
            if not s then s = {}; a.sTaken = s end
            s[b] = (s[b] or 0) + amount
        end
    end
    return rec
end

-- Death-log ring: last RING_SIZE hits/heals on each tracked player. Slots
-- are reused; a death snapshots them in order.
local function RingPush(seg, guid, name, class, ts, kind, what, amount, hp, hpMax, id)
    local a = GetActor(seg, guid, name, class, true)
    local ring = a.ring
    if not ring then
        ring = {}
        a.ring = ring
    end
    a.ringI = (a.ringI % RING_SIZE) + 1
    if a.ringN < RING_SIZE then a.ringN = a.ringN + 1 end
    local slot = ring[a.ringI]
    if not slot then
        slot = {}
        ring[a.ringI] = slot
    end
    slot.ts = ts
    slot.kind = kind
    slot.what = what
    slot.amount = amount
    slot.hp = hp
    slot.hpMax = hpMax
    slot.id = id
end

local function PlayerHp(guid)
    local token = tokenOf[guid]
    if token and UnitHealth then
        return UnitHealth(token), UnitHealthMax(token)
    end
end

-- ---------------------------------------------------------------------------
-- Combat-log dispatch
-- ---------------------------------------------------------------------------

-- Subevent -> how many prefix args sit before the suffix payload (spell
-- prefix = 3: spellId, spellName, spellSchool; swing = 0; environmental = 1)
-- and which handler family consumes it. An enumerated table keeps the hot
-- path to one lookup and makes the supported surface explicit.
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
    DAMAGE_SHIELD_MISSED    = { prefix = 3, kind = 2 },
    SPELL_HEAL              = { prefix = 3, kind = 3 },
    SPELL_PERIODIC_HEAL     = { prefix = 3, kind = 3 },
    SPELL_ABSORBED          = { kind = 4 },
    SPELL_SUMMON            = { kind = 5 },
    UNIT_DIED               = { kind = 6 },
    UNIT_DESTROYED          = { kind = 6 },
    SPELL_INTERRUPT         = { kind = 7 },
    SPELL_DISPEL            = { kind = 8 },
    SPELL_STOLEN            = { kind = 8 },
    SPELL_AURA_BROKEN       = { kind = 9 },
    SPELL_AURA_BROKEN_SPELL = { kind = 9 },
}

-- Utility family bookkeeping: which actor fields each kind feeds
local UTILITY_FIELDS = {
    [7] = { counter = "ints", map = "intSpells" },
    [8] = { counter = "dispels", map = "dispelSpells" },
    [9] = { counter = "ccb", map = "ccSpells" },
}

function E.OnCleu(ts, sub, hideCaster, sg, sn, sf, srf, dg, dn, df, drf,
        a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24)
    local d = DISPATCH[sub]
    if not d then return end

    if capture then
        local n = #capture
        if n < CAPTURE_LIMIT then
            capture[n + 1] = { ts, sub, sg, sn, sf, dg, dn, df,
                a12, a13, a14, a15, a16, a17, a18, a19, a20, a21, a22, a23, a24 }
        end
    end

    local kind = d.kind

    if kind == 5 then
        -- SPELL_SUMMON: source summons dest. Chained summons resolve to the
        -- root owner so a totem's elemental still lands on the shaman.
        local og, _, _, _, _ = ResolveOwner(sg, sn, sf)
        if og then
            E.SetOwner(dg, og, dn, ts)
        end
        return
    end

    if kind == 6 then
        -- UNIT_DIED / UNIT_DESTROYED
        if band(df, AFFIL_GROUP) ~= 0 and band(df, TYPE_PLAYER) ~= 0 then
            local token = tokenOf[dg]
            if token and UnitIsFeignDeath and UnitIsFeignDeath(token) then
                return
            end
            if not current then return end
            lastEventTs = ts
            lastActivityTs = ts
            segPair[1] = current
            for i = 1, 2 do
                local seg = segPair[i]
                local a = GetActor(seg, dg, dn, classOf[dg], true)
                a.deaths = a.deaths + 1
                seg.totals.deaths = seg.totals.deaths + 1
            end
            -- The death entry (with its event trail) lives on the fight
            local a = current.actors[dg]
            local log = {}
            if a.ring then
                for i = 1, a.ringN do
                    local idx = ((a.ringI - a.ringN + i - 1) % RING_SIZE) + 1
                    local s = a.ring[idx]
                    log[i] = { ts = s.ts, kind = s.kind, what = s.what,
                        amount = s.amount, hp = s.hp, hpMax = s.hpMax, id = s.id }
                end
            end
            a.ringN = 0
            current.deaths[#current.deaths + 1] =
                { ts = ts, guid = dg, name = dn, log = log }
        end
        return
    end

    if kind == 7 or kind == 8 or kind == 9 then
        -- Utility family: interrupts (7), dispels/steals (8), CC breaks (9).
        -- Never opens a fight; counts only inside one. The recorded key is
        -- what was interrupted / dispelled / broken, never the tool used.
        if not current then return end
        local og, on, oc, op, opet = ResolveOwner(sg, sn, sf)
        if not og then return end
        local what, whatId
        if kind == 9 then
            what, whatId = a13, a12   -- prefix spell IS the broken aura
        else
            what, whatId = a16, a15   -- extra: the interrupted/dispelled aura
        end
        if type(what) ~= "string" then
            Anomaly("utility event with unexpected layout (" .. sub .. ")")
            return
        end
        if kind == 9 then
            if not next(ccNames) then
                Anomaly("cc break seen before the CC name list loaded")
                return
            end
            if not ccNames[what] then return end
        end
        lastEventTs = ts
        lastActivityTs = ts
        segPair[1] = current
        local fields = UTILITY_FIELDS[kind]
        for i = 1, 2 do
            local a = GetOwnerActor(segPair[i], og, on, oc, op, opet)
            a[fields.counter] = a[fields.counter] + 1
            local map = a[fields.map]
            local rec = map[what]
            if not rec then
                rec = NewAbility(what, nil, type(whatId) == "number" and whatId or nil)
                map[what] = rec
            end
            rec.total = rec.total + 1
            rec.count = rec.count + 1
        end
        return
    end

    if kind == 4 then
        -- SPELL_ABSORBED: credit the shield's caster like a heal. Two
        -- payload shapes, told apart by arg12's type; anything that fails
        -- validation is skipped loudly (see Anomaly) rather than guessed.
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
        local og, on, oc, op, opet = ResolveOwner(cg, cn, cf)
        if not og then return end
        -- A shield eating a hit is evidence of enemy damage: the client
        -- emits SPELL_ABSORBED just BEFORE its paired damage/ABSORB-miss
        -- event, so on a shielded-puller opener this event must open the
        -- fight or the healer's credit for that hit is lost
        if not current then OpenFight(ts) end
        lastEventTs = ts
        lastActivityTs = ts
        segPair[1] = current
        local key = opet and PetKey(opet, spellName) or spellName
        for i = 1, 2 do
            CreditHealing(segPair[i], og, on, oc, op, opet,
                ts, key, spellName, amount, 0, crit and true or false, true,
                type(shieldId) == "number" and shieldId or nil)
        end
        return
    end

    -- Damage / miss / heal families share the prefix decode
    local spellName, suffix1, suffix2, suffix3, suffix4
    if d.prefix == 0 then
        spellName = "Melee"
        suffix1, suffix2, suffix3, suffix4 = a12, a13, a14, a15
    elseif d.prefix == 1 then
        spellName = tostring(a12 or "Environment")
        suffix1, suffix2, suffix3, suffix4 = a13, a14, a15, a16
    else
        spellName = a13
        suffix1, suffix2, suffix3, suffix4 = a15, a16, a17, a18
    end
    if type(spellName) ~= "string" then
        Anomaly("event with non-string ability name (" .. sub .. ")")
        return
    end

    if kind == 1 then
        -- _DAMAGE: suffix = amount, overkill, school, resisted, blocked,
        -- absorbed, critical, glancing, crushing, isOffHand
        local amount = suffix1
        local resisted, blocked, absorbed, critical, glancing, crushing
        if d.prefix == 0 then
            resisted, blocked, absorbed, critical, glancing, crushing = a15, a16, a17, a18, a19, a20
        elseif d.prefix == 1 then
            resisted, blocked, absorbed, critical, glancing, crushing = a16, a17, a18, a19, a20, a21
        else
            resisted, blocked, absorbed, critical, glancing, crushing = a18, a19, a20, a21, a22, a23
        end
        if type(amount) ~= "number" then
            Anomaly("damage event with non-numeric amount (" .. sub .. ")")
            return
        end
        if type(absorbed) ~= "number" then absorbed = 0 end
        local quantum = amount + absorbed
        local crit = critical and true or false

        local og, on, oc, op, opet = ResolveOwner(sg, sn, sf)
        local dstTracked = band(df, AFFIL_GROUP) ~= 0 and band(df, TYPE_PLAYER) ~= 0
        local spellId = d.prefix == 3 and type(a12) == "number" and a12 or nil
        -- Bystander violence (mob vs mob, enemy players elsewhere) must
        -- neither open fights nor hold them open
        if not (og or dstTracked) then return end

        if not current then OpenFight(ts) end
        lastEventTs = ts
        lastActivityTs = ts
        segPair[1] = current

        -- Partial avoidance detail (hit-table analysis: crushing blows on
        -- the tank, resist rates on the casters)
        local resNum = type(resisted) == "number" and resisted > 0 and resisted or nil
        local blkNum = type(blocked) == "number" and blocked > 0 and blocked or nil
        local glanced = glancing and true or false
        local crushed = crushing and true or false

        if og and quantum > 0 then
            local key = opet and PetKey(opet, spellName) or spellName
            local tname = dn or "Unknown"
            for i = 1, 2 do
                local rec = CreditDamage(segPair[i], og, on, oc, op, opet,
                    ts, key, spellName, tname, quantum, crit, spellId)
                if absorbed > 0 then
                    rec.absorbed = rec.absorbed + absorbed
                    segPair[i].actors[og].absorbed = segPair[i].actors[og].absorbed + absorbed
                end
                if glanced then rec.glance = rec.glance + 1 end
                if resNum then rec.resisted = rec.resisted + resNum end
                if blkNum then rec.blocked = rec.blocked + blkNum end
            end
            if not dstTracked and dn then
                Tally(current.enemies, dn, 1, current, "enemiesN")
            end
        end

        if dstTracked and quantum > 0 then
            local sname = (sn and sn ~= "" and sn) or spellName
            for i = 1, 2 do
                local rec = CreditTaken(segPair[i], dg, dn, classOf[dg], ts, spellName,
                    spellName, sname, quantum, crit, absorbed, spellId)
                if crushed then rec.crush = rec.crush + 1 end
                if glanced then rec.glance = rec.glance + 1 end
                if resNum then rec.resisted = rec.resisted + resNum end
                if blkNum then rec.blocked = rec.blocked + blkNum end
            end
            local hp, hpMax = PlayerHp(dg)
            RingPush(current, dg, dn, classOf[dg], ts, 1, spellName, quantum, hp, hpMax, spellId)
            if not og and sn then
                Tally(current.enemies, sn, 1, current, "enemiesN")
            end
        end
        return
    end

    if kind == 2 then
        -- _MISSED: suffix = missType, isOffHand, amountMissed, critical.
        -- ABSORB is landed damage that a shield ate — credited as damage
        -- done (attacker side) and damage taken (victim side), exactly like
        -- the partial-absorb field on _DAMAGE events.
        local missType, amountMissed = suffix1, suffix3
        local og, on, oc, op, opet = ResolveOwner(sg, sn, sf)
        local missSpellId = d.prefix == 3 and type(a12) == "number" and a12 or nil
        if missType == "ABSORB" then
            local amount = type(amountMissed) == "number" and amountMissed or 0
            if amount <= 0 then return end
            local dstTracked = band(df, AFFIL_GROUP) ~= 0 and band(df, TYPE_PLAYER) ~= 0
            if not (og or dstTracked) then return end
            if not current then OpenFight(ts) end
            lastEventTs = ts
            lastActivityTs = ts
            segPair[1] = current
            if og then
                local key = opet and PetKey(opet, spellName) or spellName
                local tname = dn or "Unknown"
                for i = 1, 2 do
                    local rec = CreditDamage(segPair[i], og, on, oc, op, opet,
                        ts, key, spellName, tname, amount, false, missSpellId)
                    rec.absorbed = rec.absorbed + amount
                    segPair[i].actors[og].absorbed = segPair[i].actors[og].absorbed + amount
                end
                if not dstTracked and dn then
                    Tally(current.enemies, dn, 1, current, "enemiesN")
                end
            end
            if dstTracked then
                local sname = (sn and sn ~= "" and sn) or spellName
                for i = 1, 2 do
                    CreditTaken(segPair[i], dg, dn, classOf[dg], ts, spellName,
                        spellName, sname, amount, false, amount, missSpellId)
                end
                local hp, hpMax = PlayerHp(dg)
                RingPush(current, dg, dn, classOf[dg], ts, 1, spellName, amount, hp, hpMax, missSpellId)
                if not og and sn then
                    Tally(current.enemies, sn, 1, current, "enemiesN")
                end
            end
            return
        end
        -- True whiffs only count inside an open fight (a stray out-of-combat
        -- miss must not open a segment). Both sides record: the attacker's
        -- ability miss, and — symmetrically — the miss on the victim's
        -- taken record (a tank's dodges are data too).
        local dstTracked = band(df, AFFIL_GROUP) ~= 0 and band(df, TYPE_PLAYER) ~= 0
        if not (og or dstTracked) then return end
        if not current then return end
        lastEventTs = ts
        lastActivityTs = ts
        segPair[1] = current
        if og then
            local key = opet and PetKey(opet, spellName) or spellName
            for i = 1, 2 do
                local a = GetOwnerActor(segPair[i], og, on, oc, op, opet)
                local rec = a.spells[key]
                if not rec then
                    rec = NewAbility(spellName, opet, missSpellId)
                    a.spells[key] = rec
                end
                rec.miss = rec.miss + 1
            end
        end
        if dstTracked then
            for i = 1, 2 do
                local a = GetActor(segPair[i], dg, dn, classOf[dg], true)
                local rec = a.taken[spellName]
                if not rec then
                    rec = NewAbility(spellName, nil, missSpellId)
                    a.taken[spellName] = rec
                end
                rec.miss = rec.miss + 1
            end
        end
        return
    end

    if kind == 3 then
        -- _HEAL: suffix = amount, overhealing, absorbed, critical
        local amount, over, crit = suffix1, suffix2, suffix4
        if type(amount) ~= "number" then
            Anomaly("heal event with non-numeric amount (" .. sub .. ")")
            return
        end
        if type(over) ~= "number" then over = 0 end
        if not current then return end
        local og, on, oc, op, opet = ResolveOwner(sg, sn, sf)
        local dstTracked = band(df, AFFIL_GROUP) ~= 0 and band(df, TYPE_PLAYER) ~= 0
        if not (og or dstTracked) then return end
        lastEventTs = ts
        lastActivityTs = ts
        segPair[1] = current
        local effective = amount - over
        if og and effective >= 0 then
            local key = opet and PetKey(opet, spellName) or spellName
            local healId = type(a12) == "number" and a12 or nil
            for i = 1, 2 do
                CreditHealing(segPair[i], og, on, oc, op, opet,
                    ts, key, spellName, effective, over, crit and true or false, false, healId)
            end
        end
        -- Heals received feed the death trail
        if dstTracked and effective > 0 then
            local hp, hpMax = PlayerHp(dg)
            RingPush(current, dg, dn, classOf[dg], ts, 2, spellName, effective, hp, hpMax,
                type(a12) == "number" and a12 or nil)
        end
        return
    end
end

-- ---------------------------------------------------------------------------
-- Segment access, reset, modes
-- ---------------------------------------------------------------------------

-- Selector values: "overall", "current", "last", or a fight id (number)
function E.GetSegment(sel)
    if sel == "overall" then return overall end
    if sel == "current" then return current end
    if sel == "last" then return fights[1] end
    for i = 1, #fights do
        if fights[i].id == sel then return fights[i] end
    end
end

function E.GetFights() return fights end
function E.GetCurrent() return current end
function E.GetOverall() return overall end
function E.InFight() return current ~= nil end

-- Duration a rate divides by: wall-clock fight time. Overall divides by
-- accumulated fight time (idle between pulls excluded) — documented in
-- DECISIONS.md as the single biggest meter-vs-meter disagreement.
function E.SegmentDuration(seg, now)
    if seg == overall then
        local dur = overallDur
        if current then dur = dur + max((now or lastEventTs) - current.tsStart, 1) end
        return max(dur, 1)
    end
    if seg.tsEnd then return seg.dur end
    return max((now or lastEventTs) - seg.tsStart, 1)
end

local ClearRowsOut -- forward (defined with the rows scratch below)

function E.ResetCurrent(now)
    if current then
        -- Overall keeps the discarded stretch's damage, so it must keep its
        -- elapsed time too — otherwise Overall's rates divide retained
        -- damage by a duration missing the whole pre-reset window
        overallDur = overallDur + max(lastEventTs - current.tsStart, 0)
        fightCounter = fightCounter - 1 -- the discarded fight never happened
        OpenFight(now)
        -- Re-arm the idle clock: a reset clicked in the post-kill idle
        -- window must not be instantly closed by a stale timer
        lastEventTs = now
        lastActivityTs = now
    end
    ClearRowsOut()
end

function E.ResetAll(now)
    overall = NewSegment(0, now, false)
    segPair[2] = overall
    for i = #fights, 1, -1 do fights[i] = nil end
    fightCounter = 0
    overallDur = 0
    local wasOpen = current ~= nil
    current = nil
    if wasOpen and playerInCombat then
        -- Resetting mid-pull deliberately starts the fight fresh from now:
        -- the rest of this pull records; what came before is gone.
        OpenFight(now)
        lastEventTs = now
        lastActivityTs = now
    end
    ClearRowsOut()
end

-- Modes are data. Adding one = adding a table entry: how to read an
-- actor's value, what the rate is called, and which breakdown lists the
-- detail view shows (field = actor table of ability records or name->number).
local function ValDmg(a) return a.dmg end
local function ValTaken(a) return a.dtaken end
local function ValHeal(a) return a.heal + a.absorb end
local function ValDeaths(a) return a.deaths end
local function ValInts(a) return a.ints end
local function ValDispels(a) return a.dispels end
local function ValCC(a) return a.ccb end

E.MODES = {
    { key = "DMG", label = "DAMAGE", value = ValDmg, rateLabel = "DPS",
        primary = "total", series = "sDmg", active = "activeDmg",
        lists = { { title = "ABILITIES", field = "spells", records = true },
                  { title = "TARGETS", field = "targets" } } },
    { key = "DPS", label = "DPS", value = ValDmg, rateLabel = "DPS",
        primary = "rate", series = "sDmg", active = "activeDmg",
        lists = { { title = "ABILITIES", field = "spells", records = true },
                  { title = "TARGETS", field = "targets" } } },
    { key = "TAKEN", label = "DMG TAKEN", value = ValTaken, rateLabel = "DTPS",
        primary = "total", series = "sTaken",
        lists = { { title = "HIT BY", field = "taken", records = true },
                  { title = "SOURCES", field = "sources" } } },
    { key = "HEAL", label = "HEALING", value = ValHeal, rateLabel = "HPS",
        primary = "total", series = "sHeal", active = "activeHeal",
        lists = { { title = "SPELLS", field = "heals", records = true } } },
    -- Deaths graph the damage-taken series: the spikes around a death are
    -- exactly what the graph is for in this mode
    { key = "DEATHS", label = "DEATHS", value = ValDeaths, rateLabel = nil,
        primary = "total", series = "sTaken", deaths = true,
        lists = {} },
    -- Utility modes: counts, no rates, no series (the graph shows its
    -- no-graph message)
    { key = "INT", label = "INTERRUPTS", value = ValInts, rateLabel = nil,
        primary = "total", series = nil,
        lists = { { title = "SPELLS INTERRUPTED", field = "intSpells", records = true } } },
    { key = "DISPEL", label = "DISPELS", value = ValDispels, rateLabel = nil,
        primary = "total", series = nil,
        lists = { { title = "AURAS DISPELLED", field = "dispelSpells", records = true } } },
    { key = "CCBREAK", label = "CC BREAKS", value = ValCC, rateLabel = nil,
        primary = "total", series = nil,
        lists = { { title = "CC BROKEN", field = "ccSpells", records = true } } },
}

-- Sorted rows for the bar window. `rowsOut` is reused between calls: the
-- repaint is 2 Hz and must not churn tables. Returns rows, count, total, dur.
local rowsOut = {}

-- Resets must drop the actor references pinned here, or a wiped segment
-- stays reachable (with its whole series) while the window is hidden
ClearRowsOut = function()
    for i = 1, #rowsOut do rowsOut[i].actor = nil end
end

-- Hoisted: the 2 Hz repaint must not allocate a comparator closure per call
local function RowOrder(x, y)
    if x.actor == nil then return false end
    if y.actor == nil then return true end
    if x.value ~= y.value then return x.value > y.value end
    return (x.actor.name or "") < (y.actor.name or "")
end

function E.CollectRows(seg, mode, now)
    local n = 0
    local total = 0
    local dur = E.SegmentDuration(seg, now)
    for _, a in pairs(seg.actors) do
        local v = mode.value(a)
        if v > 0 then
            n = n + 1
            local row = rowsOut[n]
            if not row then
                row = {}
                rowsOut[n] = row
            end
            row.actor = a
            row.value = v
            row.rate = v / dur
            total = total + v
        end
    end
    for i = n + 1, #rowsOut do rowsOut[i].actor = nil end
    table.sort(rowsOut, RowOrder)
    return rowsOut, n, total, dur
end

-- ---------------------------------------------------------------------------
-- Debug capture + deterministic serialization
-- ---------------------------------------------------------------------------

function E.SetCapture(tbl)
    capture = tbl
end

function E.CaptureCount()
    return capture and #capture or 0
end

-- Deterministic dump of a segment (sorted keys, stable float format).
-- Harness-only: this is the instrument behind the byte-identical-replay
-- acceptance check; nothing in-game calls it.
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

function E.Serialize(seg)
    local out = {}
    SerializeInto(out, seg, "")
    return table.concat(out)
end

function E.SnapshotAll()
    local out = {}
    out[#out + 1] = "OVERALL="
    out[#out + 1] = E.Serialize(overall)
    out[#out + 1] = "\nCURRENT="
    out[#out + 1] = current and E.Serialize(current) or "nil"
    for i = 1, #fights do
        out[#out + 1] = "\nFIGHT[" .. i .. "]="
        out[#out + 1] = E.Serialize(fights[i])
    end
    return table.concat(out)
end

-- ---------------------------------------------------------------------------
-- Session persistence (opt-in): Overall + Last survive a /reload
-- ---------------------------------------------------------------------------

-- Snapshots are written ONCE, at PLAYER_LOGOUT (SavedVariables only flush
-- on clean logout/reload anyway — the documented mid-play-flush crash), and
-- resumed within the same 10-minute window the suite's RestoreSession uses.
-- The export returns live references, not copies: logout is the end of the
-- session, so nothing mutates them afterwards.
local SESSION_V = 1
local SESSION_WINDOW = 600

function E.ExportSession(now)
    -- A /reload mid-fight loses the open pull's segment, but Overall
    -- already holds that pull's damage — so its elapsed time must ride
    -- along too, or the resumed Overall divides kept damage by a duration
    -- missing the whole in-progress stretch (the ResetCurrent lesson).
    local dur = overallDur
    if current then
        dur = dur + max(lastEventTs - current.tsStart, 0)
    end
    return {
        v = SESSION_V,
        savedAt = now,
        fightCounter = fightCounter,
        overallDur = dur,
        overall = overall,
        last = fights[1],
    }
end

-- Returns true when the snapshot was adopted. Anything malformed or stale
-- is refused (never guessed at) and the session starts fresh.
function E.ImportSession(snap, now)
    if type(snap) ~= "table" or snap.v ~= SESSION_V then return false end
    if type(snap.savedAt) ~= "number" or (now - snap.savedAt) > SESSION_WINDOW
        or now < snap.savedAt then return false end
    local o = snap.overall
    if type(o) ~= "table" or type(o.totals) ~= "table" or type(o.actors) ~= "table"
        or type(o.totals.dmg) ~= "number" then return false end
    if current then return false end -- never clobber a live fight
    overall = o
    segPair[2] = overall
    fightCounter = type(snap.fightCounter) == "number" and snap.fightCounter or 0
    overallDur = type(snap.overallDur) == "number" and snap.overallDur or 0
    for i = #fights, 1, -1 do fights[i] = nil end
    local last = snap.last
    if type(last) == "table" and type(last.totals) == "table"
        and type(last.actors) == "table" and last.tsEnd then
        fights[1] = last
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Init
-- ---------------------------------------------------------------------------

function E.Init(settingsDb, now)
    db = settingsDb
    overall = NewSegment(0, now or 0, false)
    segPair[2] = overall
end
