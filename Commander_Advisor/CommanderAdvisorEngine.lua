-- Commander Advisor — the engine.
--
-- Pure: nothing in here touches the client. It is handed a SNAPSHOT of the
-- player's situation (a plain table the client builds every tick) and the
-- rulebook, and it hands back the signals worth raising, ranked. It runs
-- under plain luajit with no client attached, which is how it is tested.
--
-- Two ideas do the work:
--
-- 1. The INTAKE BOOK. Every hit that lands on you goes in with its time,
--    its amount, who dealt it and how. From that, a conservative estimate
--    of how long you have: the rate is measured over the WHOLE recent window
--    rather than the last big hit, a burst only counts when it is sustained
--    (three hits in two seconds, not one crit), and no time-to-die is claimed
--    at all unless something has hit you in the last few seconds. The same
--    book says how many distinct melee and casters are on you right now and
--    which damage school is doing the hurting.
--
-- 2. HYSTERESIS. A signal has to be true for a moment before it is raised
--    (longer for the low tier, instantly for the high tier), and once raised
--    it holds for a moment after the conditions clear — so a button glows
--    steadily rather than flickering with every health tick. Casting the
--    spell drops its signal at once: a glow for a button you just pressed
--    is the one thing an advisor must never show.
--
-- The word "conservative" in the settings means exactly one thing: the
-- advisor would rather say nothing than say something it cannot back up.

CommanderAdvisor_Engine = CommanderAdvisor_Engine or {}
local E = CommanderAdvisor_Engine

local D = CommanderAdvisor_Data

E.TIER_LOW, E.TIER_MEDIUM, E.TIER_HIGH = 1, 2, 3

-- How long a hit counts as "recent" for each question the book answers
E.WINDOW_RATE   = 5.0   -- damage rate is averaged over this
E.WINDOW_BURST  = 2.0   -- a sustained burst is measured over this
E.BURST_HITS    = 3     -- ... and needs this many hits to count at all
E.WINDOW_TAKING = 3.0   -- "something is hitting me" means within this
E.WINDOW_ATTACK = 5.0   -- an attacker is "on you" for this long after a hit
E.MAX_HITS      = 64    -- the book never grows past this

-- ---------------------------------------------------------------------------
-- The intake book
-- ---------------------------------------------------------------------------

function E.NewIntake()
    return { hits = {}, head = 1, count = 0 }
end

-- kind: "melee" | "spell" | "ranged" | "environment"
-- sourceGUID may be nil (environmental). isPlayer marks a player source.
function E.IntakeObserve(book, t, amount, sourceGUID, kind, school, isPlayer)
    if type(amount) ~= "number" then amount = 0 end
    local hits = book.hits
    if book.count < E.MAX_HITS then
        book.count = book.count + 1
        hits[book.count] = { t = t, amount = amount, src = sourceGUID, kind = kind, school = school, player = isPlayer and true or false }
    else
        -- Ring: overwrite the oldest
        local slot = book.head
        local hit = hits[slot]
        hit.t, hit.amount, hit.src, hit.kind, hit.school, hit.player = t, amount, sourceGUID, kind, school, isPlayer and true or false
        book.head = slot % E.MAX_HITS + 1
    end
end

function E.IntakeClear(book)
    book.hits, book.head, book.count = {}, 1, 0
end

local function CountHits(book) return book.count end

-- Everything the rules ask about incoming damage, in one pass over the book.
-- hp is the CURRENT health (absolute), so the time-to-die is in seconds.
function E.IntakeSummary(book, now, hp)
    local sum5, sum2, hits2 = 0, 0, 0
    local oldest5
    local lastHit
    local meleeSrc, casterSrc, anySrc = {}, {}, {}
    local melee, casters, attackers, enemyPlayers = 0, 0, 0, 0
    local schoolSum = {}
    local taking = false

    for i = 1, CountHits(book) do
        local hit = book.hits[i]
        local age = now - hit.t
        if age >= 0 and age <= E.WINDOW_RATE then
            sum5 = sum5 + hit.amount
            if not oldest5 or hit.t < oldest5 then oldest5 = hit.t end
            if hit.school and hit.amount > 0 then
                schoolSum[hit.school] = (schoolSum[hit.school] or 0) + hit.amount
            end
        end
        if age >= 0 and age <= E.WINDOW_BURST then
            sum2 = sum2 + hit.amount
            hits2 = hits2 + 1
        end
        if age >= 0 and age <= E.WINDOW_TAKING then
            taking = true
        end
        if age >= 0 and age <= E.WINDOW_ATTACK and hit.src then
            if not anySrc[hit.src] then
                anySrc[hit.src] = true
                attackers = attackers + 1
                if hit.player then enemyPlayers = enemyPlayers + 1 end
            end
            if hit.kind == "melee" and not meleeSrc[hit.src] then
                meleeSrc[hit.src] = true
                melee = melee + 1
            elseif (hit.kind == "spell" or hit.kind == "ranged") and not casterSrc[hit.src] then
                casterSrc[hit.src] = true
                casters = casters + 1
            end
        end
        if not lastHit or hit.t > lastHit then lastHit = hit.t end
    end

    -- The rate is taken over the full window even when the first hit is
    -- newer than that: a fight that started a second ago has not yet earned
    -- a claim about how fast it is going. The burst rate is allowed to
    -- override it only when it is a real burst — several hits, not one.
    local rate = sum5 / E.WINDOW_RATE
    if hits2 >= E.BURST_HITS then
        local burst = sum2 / E.WINDOW_BURST
        if burst > rate then rate = burst end
    end

    local ttl
    if taking and rate > 0 and hp and hp > 0 then
        ttl = hp / rate
    end

    -- Dominant school by share of what landed in the window
    local school, schoolShare
    if sum5 > 0 then
        for mask, amount in pairs(schoolSum) do
            local share = amount / sum5
            if not schoolShare or share > schoolShare then
                school, schoolShare = mask, share
            end
        end
    end

    return {
        rate = rate, ttl = ttl, taking = taking,
        lastHitAge = lastHit and (now - lastHit) or nil,
        melee = melee, casters = casters, attackers = attackers, enemyPlayers = enemyPlayers,
        school = school, schoolShare = schoolShare or 0,
    }
end

-- ---------------------------------------------------------------------------
-- Conditions
-- ---------------------------------------------------------------------------

local function HasAny(set, names)
    if not set then return false end
    for _, name in ipairs(names) do
        if set[name] then return true end
    end
    return false
end

local function InList(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

local function SchoolWordOf(mask)
    if not mask then return nil end
    for word, m in pairs(D.SCHOOL_MASK) do
        if m == mask then return word end
    end
    -- A mixed school (Frostfire) counts as whichever of its parts is asked for
    return nil
end

-- Does a school word match the snapshot's dominant school? A mixed mask
-- (e.g. Frostfire 0x14) matches either part.
local function SchoolMatches(S, word)
    local want = D.SCHOOL_MASK[word]
    if not want or not S.school then return false end
    if (S.schoolShare or 0) < 0.5 then return false end
    return S.school % (want * 2) >= want   -- bit test without bit library
end

-- The Caution setting scales the health and time thresholds: r > 0 means
-- the bar has to be lower before anything is said.
local function Scaled(value, r)
    local scaled = value * (1 - r)
    if scaled < 0.05 then scaled = 0.05 end
    return scaled
end

-- One rung of a ladder against a snapshot. Returns true when every
-- condition on it holds.
function E.RungHolds(rung, S, cfg)
    local r = cfg.reticence or 0
    if rung.hp ~= nil and not (S.hp <= Scaled(rung.hp, r)) then return false end
    if rung.hpAbove ~= nil and not (S.hp > rung.hpAbove) then return false end
    if rung.ttl ~= nil then
        if not S.ttl or S.ttl > Scaled(rung.ttl, r) then return false end
    end
    -- A time-to-die rung never fires from full health: a fast rate on a full
    -- bar is a number, not an emergency yet
    if rung.hpBelowCeiling and not (S.hp <= (cfg.ttlCeiling or 0.75)) then return false end
    if rung.combat ~= nil and (S.inCombat and true or false) ~= rung.combat then return false end
    if rung.taking and not S.taking then return false end
    if rung.notTaking and S.taking then return false end
    if rung.melee ~= nil and (S.melee or 0) < rung.melee then return false end
    if rung.casters ~= nil and (S.casters or 0) < rung.casters then return false end
    if rung.attackers ~= nil and (S.attackers or 0) < rung.attackers then return false end
    if rung.enemyPlayers ~= nil then
        -- enemyPlayers = 0 is a PvE-only rung; > 0 is "at least"
        if rung.enemyPlayers == 0 then
            if (S.enemyPlayers or 0) > 0 then return false end
        elseif (S.enemyPlayers or 0) < rung.enemyPlayers then return false end
    end
    if rung.enemyPlayersNear ~= nil and (S.enemyPlayersNear or 0) < rung.enemyPlayersNear then return false end
    if rung.control ~= nil then
        local c = S.control or {}
        if rung.control == "any" then
            if not (c.stunned or c.feared or c.silenced or c.rooted or c.incapacitated or c.disarmed or c.snared) then return false end
        elseif not c[rung.control] then
            return false
        end
    end
    if rung.incomingCast ~= nil then
        local casts = S.incomingCasts or {}
        if #casts == 0 then return false end
        if type(rung.incomingCast) == "table" then
            local found = false
            for _, cast in ipairs(casts) do
                if InList(rung.incomingCast, cast.name) then found = true break end
            end
            if not found then return false end
        end
    end
    if rung.school ~= nil and not SchoolMatches(S, rung.school) then return false end
    if rung.debuffType ~= nil and not (S.debuffTypes and (S.debuffTypes[rung.debuffType] or 0) > 0) then return false end
    if rung.debuff ~= nil and not (S.debuffs and S.debuffs[rung.debuff]) then return false end
    if rung.aura ~= nil and not (S.auras and S.auras[rung.aura]) then return false end
    if rung.notAura ~= nil and (S.auras and S.auras[rung.notAura]) then return false end
    if rung.mana ~= nil and not (S.mana and S.mana <= rung.mana) then return false end
    if rung.manaAbove ~= nil and not (S.mana and S.mana > rung.manaAbove) then return false end
    if rung.petHp ~= nil and not (S.pet and S.petHp and S.petHp <= rung.petHp) then return false end
    if rung.pet and not S.pet then return false end
    if rung.form ~= nil then
        if type(rung.form) == "table" then
            if not (S.form and InList(rung.form, S.form)) then return false end
        elseif S.form ~= rung.form then
            return false
        end
    end
    if rung.notForm ~= nil and S.form and InList(rung.notForm, S.form) then return false end
    if rung.noForm and S.form then return false end
    if rung.shield and not S.hasShield then return false end
    if rung.group ~= nil and (S.inGroup and true or false) ~= rung.group then return false end
    if rung.notCasting and S.casting then return false end
    if rung.hasTarget and not S.hasTarget then return false end
    if rung.outdoors and not S.outdoors then return false end
    if rung.zone ~= nil and not InList(rung.zone, S.zone or "none") then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Rules against a snapshot
-- ---------------------------------------------------------------------------

local function SpellList(rule)
    if type(rule.spell) == "table" then return rule.spell end
    if rule.spell then return { rule.spell } end
    return {}
end
E.SpellList = SpellList

-- The spell a rule would actually have you press: the first one in its list
-- that you know, is off cooldown and usable. Returns the entry from
-- S.spells, plus its name. For item rules the client fills S.items keyed by
-- the rule key. Returns nil, reason when nothing qualifies.
local function PickSpell(rule, S)
    if rule.item then
        local entry = S.items and S.items[rule.key]
        if not entry then return nil, "not on a bar" end
        if not entry.ready then return nil, "on cooldown" end
        if entry.usable == false then return nil, "not usable" end
        return entry, entry.name
    end
    local book = rule.petSpell and S.petSpells or S.spells
    if not book then return nil, "not known" end
    local sawKnown, sawCooldown, sawUnusable = false, false, false
    for _, name in ipairs(SpellList(rule)) do
        local entry = book[name]
        if entry and entry.known then
            sawKnown = true
            -- A school-keyed rule (resistance totems/auras) only offers the
            -- spell for the school that is actually doing the damage
            local schoolOK = true
            if rule.schoolBySpell then
                local word = rule.schoolBySpell[name]
                schoolOK = word and SchoolMatches(S, word) or false
            end
            if schoolOK then
                if entry.ready and entry.usable ~= false then
                    return entry, name
                end
                if not entry.ready then sawCooldown = true else sawUnusable = true end
            end
        end
    end
    if not sawKnown then return nil, "not known" end
    if sawCooldown then return nil, "on cooldown" end
    if sawUnusable then return nil, "not usable now" end
    return nil, "nothing to offer"
end
E.PickSpell = PickSpell

-- Is a maintain rule's family up on the player? Returns the aura entry.
local function FamilyAura(rule, S)
    local names = rule.family and D.FAMILIES[rule.family]
    if not names then return nil end
    for _, name in ipairs(names) do
        local aura = S.auras and S.auras[name]
        if aura then return aura, name end
    end
    return nil
end
E.FamilyAura = FamilyAura

-- The tier a rule earns right now, before hysteresis, and why. Returns
-- tier (or nil), reason, spellName.
function E.Assess(rule, S, cfg, state)
    local mode = cfg.modes and cfg.modes[rule.key] or rule.default or "AUTO"
    if mode == "OFF" then return nil, "off" end

    -- Global quiet: nothing is said while dead, mounted, on a taxi; while
    -- held you cannot press anything but the trinket
    if S.dead then return nil, "dead" end
    if S.taxi then return nil, "on a taxi" end
    if S.mounted and not cfg.remindWhileMounted then return nil, "mounted" end
    local held = S.control and (S.control.stunned or S.control.feared or S.control.incapacitated)
    if held and rule.key ~= "ALL_PVP_TRINKET" then return nil, "held" end
    if S.control and S.control.silenced and not rule.item then return nil, "silenced" end
    if S.stealthed and cfg.quietInStealth and rule.role == "maintain" then return nil, "stealthed" end
    if S.resting and cfg.quietWhileResting and not S.inCombat then return nil, "resting" end

    -- Pointless right now
    if rule.blockedBy and HasAny(S.debuffs, rule.blockedBy) then return nil, "blocked" end
    if rule.notWhile and HasAny(S.auras, rule.notWhile) then return nil, "already up" end
    if rule.notWhileMine then
        for _, name in ipairs(rule.notWhileMine) do
            local aura = S.auras and S.auras[name]
            if aura and aura.mine then return nil, "already up" end
        end
    end
    if rule.notReady then
        local other = S.spells and S.spells[rule.notReady]
        if not other or not other.known then return nil, "no backup needed" end
        if other.ready then return nil, "backup not needed" end
    end
    if rule.requiresReady then
        for _, name in ipairs(rule.requiresReady) do
            local other = S.spells and S.spells[name]
            if not (other and other.known and other.ready) then return nil, "needs " .. name end
        end
    end

    -- Recently cast, or being cast now: the advice was taken
    for _, name in ipairs(SpellList(rule)) do
        local castAt = S.recentCasts and S.recentCasts[name]
        if castAt and (S.now - castAt) < (cfg.castGrace or 2.0) then return nil, "just cast" end
        if S.castingName == name then return nil, "casting it" end
    end

    -- Maintain rules: the family must be missing (or about to be)
    local expiring = false
    if rule.role == "maintain" then
        local aura = FamilyAura(rule, S)
        local missingSince = state and state.missingSince
        if aura then
            if missingSince then missingSince[rule.family] = nil end
            local left = aura.expire and aura.expire > 0 and (aura.expire - S.now) or nil
            if not left or left > (cfg.expiringSoon or 0) then return nil, "up" end
            expiring = true
        elseif missingSince then
            -- The seconds between a buff dropping and you recasting it are
            -- not a glow: it has to have been missing for a moment first
            local since = missingSince[rule.family]
            if not since then
                missingSince[rule.family] = S.now
                since = S.now
            end
            if (S.now - since) < (cfg.missingGrace or 0) then return nil, "grace" end
        end
        if S.inCombat and not cfg.remindInCombat then return nil, "quiet in combat" end
        if not S.inCombat and not cfg.remindOutOfCombat then return nil, "quiet out of combat" end
    end

    local entry, spellName = PickSpell(rule, S)
    if not entry then return nil, spellName end

    -- The ladder, highest first
    local tier, why
    for _, rung in ipairs(rule.tiers) do
        if E.RungHolds(rung, S, cfg) then
            tier = rung.tier
            why = rung
            break
        end
    end
    if not tier then return nil, "conditions not met" end
    if expiring then
        -- An expiring buff is never more than a low note: it is still up
        tier = E.TIER_LOW
    end

    -- A pinned mode overrides the ladder's tier
    if mode == "LOW" then tier = E.TIER_LOW
    elseif mode == "MEDIUM" then tier = E.TIER_MEDIUM
    elseif mode == "HIGH" then tier = E.TIER_HIGH end

    return tier, E.Explain(rule, why, S, expiring, spellName), spellName
end

-- A sentence for the tooltip and the report: what earned the signal.
function E.Explain(rule, rung, S, expiring, spellName)
    local parts = {}
    if expiring then
        parts[#parts + 1] = "about to expire"
    elseif rule.role == "maintain" then
        parts[#parts + 1] = "not on you"
    end
    if rung then
        if rung.hp then parts[#parts + 1] = string.format("health %d%%", math.floor((S.hp or 0) * 100 + 0.5)) end
        if rung.ttl and S.ttl then parts[#parts + 1] = string.format("~%.0fs to live at this rate", S.ttl) end
        if rung.melee then parts[#parts + 1] = string.format("%d melee on you", S.melee or 0) end
        if rung.casters then parts[#parts + 1] = string.format("%d caster%s on you", S.casters or 0, (S.casters or 0) == 1 and "" or "s") end
        if rung.attackers and not rung.melee and not rung.casters then
            parts[#parts + 1] = string.format("%d attacker%s", S.attackers or 0, (S.attackers or 0) == 1 and "" or "s")
        end
        if rung.taking and not rung.hp and not rung.ttl then parts[#parts + 1] = "taking damage" end
        if rung.notTaking then parts[#parts + 1] = "nothing hitting you" end
        if rung.control then
            local c = S.control or {}
            local word = rung.control
            if word == "any" then
                word = (c.stunned and "stunned") or (c.feared and "feared") or (c.silenced and "silenced")
                    or (c.incapacitated and "incapacitated") or (c.rooted and "rooted") or (c.snared and "snared") or "held"
            end
            parts[#parts + 1] = word
        end
        if rung.incomingCast then
            local cast = S.incomingCasts and S.incomingCasts[1]
            parts[#parts + 1] = cast and (cast.name .. " being cast at you") or "a cast aimed at you"
        end
        if rung.school then parts[#parts + 1] = rung.school .. " damage landing on you" end
        if rung.debuffType then parts[#parts + 1] = string.lower(rung.debuffType) .. " on you" end
        if rung.mana then parts[#parts + 1] = string.format("mana %d%%", math.floor((S.mana or 0) * 100 + 0.5)) end
        if rung.petHp then parts[#parts + 1] = string.format("pet at %d%%", math.floor((S.petHp or 0) * 100 + 0.5)) end
        if rung.combat == false and not expiring and rule.role == "maintain" then parts[#parts + 1] = "out of combat" end
        if rung.zone then parts[#parts + 1] = "PvP zone" end
    end
    if #parts == 0 then parts[1] = "conditions met" end
    return table.concat(parts, ", ")
end

-- ---------------------------------------------------------------------------
-- Hysteresis and ranking
-- ---------------------------------------------------------------------------

function E.NewState()
    return { pending = {}, active = {}, missingSince = {} }
end

-- cfg:
--   modes            rule key -> mode
--   reticence        -0.25 .. 0.5; threshold scaling (see Scaled)
--   ttlCeiling       health fraction above which a time-to-die rung is ignored
--   riseSeconds      { [1]=, [2]=, [3]= } how long a tier must hold before it shows
--   holdSeconds      how long a raised signal lingers after conditions clear
--   castGrace        seconds after casting a spell during which it is quiet
--   expiringSoon     seconds left on a maintain buff that counts as "expiring"
--   missingGrace     seconds a maintain buff must have been missing before it is mentioned
--   remindInCombat / remindOutOfCombat / quietWhileResting / quietInStealth / remindWhileMounted
--   maxSignals       how many to return (0 = all)
--
-- Returns the ranked list of { rule, tier, reason, spell, since, rising }
-- and mutates state.
function E.Evaluate(S, rules, cfg, state)
    local now = S.now
    local rise = cfg.riseSeconds or { 0.8, 0.4, 0 }
    local hold = cfg.holdSeconds or 1.0
    local out = {}

    for _, rule in ipairs(rules) do
        local tier, reason, spellName = E.Assess(rule, S, cfg, state)
        local key = rule.key
        local active = state.active[key]
        local pending = state.pending[key]

        if tier then
            if active then
                -- Rising is immediate, falling waits for the hold
                if tier >= active.tier then
                    active.tier, active.reason, active.spell = tier, reason, spellName
                    active.lastTrue = now
                else
                    if now - active.lastTrue >= hold then
                        active.tier, active.reason, active.spell = tier, reason, spellName
                        active.lastTrue = now
                    end
                end
            else
                if not pending or pending.tier ~= tier then
                    pending = { tier = tier, since = now }
                    state.pending[key] = pending
                end
                local need = rise[tier] or 0
                if now - pending.since >= need then
                    active = { tier = tier, reason = reason, spell = spellName, since = now, lastTrue = now }
                    state.active[key] = active
                    state.pending[key] = nil
                end
            end
        else
            state.pending[key] = nil
            if active then
                if reason == "just cast" or reason == "casting it" or reason == "already up"
                    or reason == "up" or reason == "blocked" or reason == "dead" or reason == "held" then
                    -- The advice was taken (or became impossible): drop at once
                    state.active[key] = nil
                    active = nil
                elseif now - active.lastTrue >= hold then
                    state.active[key] = nil
                    active = nil
                end
            end
        end

        if active then
            out[#out + 1] = {
                rule = rule, tier = active.tier, reason = active.reason,
                spell = active.spell, since = active.since,
                isNew = active.since == now,
            }
        end
    end

    table.sort(out, function(a, b)
        if a.tier ~= b.tier then return a.tier > b.tier end
        if (a.rule.weight or 0) ~= (b.rule.weight or 0) then return (a.rule.weight or 0) > (b.rule.weight or 0) end
        return a.rule.key < b.rule.key
    end)

    local limit = cfg.maxSignals or 0
    if limit > 0 and #out > limit then
        for i = #out, limit + 1, -1 do out[i] = nil end
    end
    return out
end

-- Forget one rule's hysteresis (the client calls this when the spell was
-- cast, so the glow is gone before the next tick)
function E.Drop(state, key)
    state.active[key] = nil
    state.pending[key] = nil
end

function E.TierName(tier)
    return D.TIER_NAMES[tier] or tostring(tier)
end
