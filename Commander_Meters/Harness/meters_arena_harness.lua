-- Commander Meters ARENA engine harness (luajit).
-- A scripted 3v3 (RMP vs warrior/druid/warlock) driven through the REAL
-- arena engine: both teams' attribution, the DR ladder (reset from the
-- FADE, frozen while stacked), a teammate breaking a fear, a Polymorph
-- into immunity, a drink, a mana burn, kicks, purges, two deaths with
-- killing blows, the scoreboard merge, replay state at chosen seconds,
-- the pressure series, retention, and the persistence round trip.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"
local METERS = ADDONS .. "/Commander_Meters"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function eq(a, b, label) CHECK(a == b, label, tostring(a) .. " ~= " .. tostring(b)) end
local function near(a, b, label) CHECK(math.abs(a - b) < 1e-6, label, tostring(a) .. " ~= " .. tostring(b)) end

local printLog = {}
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local function LoadArena()
    CommanderMetersArena = nil
    assert(loadfile(METERS .. "/CommanderMetersDispel.lua"))()
    assert(loadfile(METERS .. "/CommanderMetersArena.lua"))()
    return CommanderMetersArena
end

-- Flags
local F_ME    = 0x511    -- mine, friendly, player-controlled, TYPE_PLAYER
local F_PARTY = 0x512
local F_ENEMY = 0x548    -- hostile, outsider, player-controlled, TYPE_PLAYER
local F_EPET  = 0x1148   -- hostile pet
local F_FPET  = 0x1112   -- party pet

-- Seats
local ME, R2, P3 = "Player-0-ME", "Player-0-ROGUE", "Player-0-PRIEST"      -- us: mage, rogue, priest
local W1, D2, L3 = "Player-1-WARR", "Player-1-DRUID", "Player-1-LOCK"       -- them
local FELHUNTER = "Pet-0-FEL"
local ORPHAN = "Pet-0-ORPHAN"

local T0 = 1000000

local A = LoadArena()
A.SetDRTable({ [1833] = "STUN", [408] = "KIDNEY", [10308] = "STUN", [8122] = "FEAR",
    [12826] = "POLY", [339] = "ROOT", [1715] = "LIMIT" }, { [15487] = "SILENCE", [24259] = "SILENCE" })
A.SetBook({
    WARRIOR = { { id = 871, name = "Shield Wall", role = "DEF", cd = 1800 } },
    PRIEST = { { id = 33206, name = "Pain Suppression", role = "DEF", cd = 120 } },
    WARLOCK = { { id = 19647, name = "Spell Lock", role = "KICK", cd = 24 } },
}, { BloodElf = { { id = 28730, name = "Arcane Torrent", role = "KICK", cd = 120 } } })
A.SetDrinkIds({ 430, 27089 })
A.SetSpecMarkers({ WARRIOR = { { spec = "Arms", ids = { 12294, 30330 } } },
    WARLOCK = { { spec = "Affli", ids = { 30108 } } } })

local started, ended = 0, nil
A.onMatchStart = function() started = started + 1 end
A.onMatchEnd = function(m) ended = m end

-- Event helpers (arg positions per the engine's DISPATCH decode)
local function spellDmg(ts, sg, sn, sf, dg, dn, df, id, name, amount, absorbed, crit)
    A.OnCleu(ts, "SPELL_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0,
        id, name, 16, amount, 0, 16, 0, 0, absorbed or 0, crit or false, false, false, false)
end
local function swing(ts, sg, sn, sf, dg, dn, df, amount, absorbed, crit)
    A.OnCleu(ts, "SWING_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0,
        amount, 0, 1, 0, 0, absorbed or 0, crit or false, false, false, false)
end
local function heal(ts, sg, sn, sf, dg, dn, df, id, name, amount, over, crit)
    A.OnCleu(ts, "SPELL_HEAL", nil, sg, sn, sf, 0, dg, dn, df, 0,
        id, name, 2, amount, over or 0, 0, crit or false)
end
local function aura(ts, sub, sg, sn, sf, dg, dn, df, id, name)
    A.OnCleu(ts, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 1, "DEBUFF")
end
local function cast(ts, sg, sn, sf, dg, dn, df, id, name)
    A.OnCleu(ts, "SPELL_CAST_SUCCESS", nil, sg, sn, sf, 0, dg or "", dn or "", df or 0x80000000, 0, id, name, 1)
end
local function kick(ts, sg, sn, sf, dg, dn, df, id, name, exId, exName)
    A.OnCleu(ts, "SPELL_INTERRUPT", nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 1, exId, exName, 8)
end
local function dispel(ts, sub, sg, sn, sf, dg, dn, df, id, name, exId, exName, auraType)
    A.OnCleu(ts, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 2, exId, exName, 8, auraType or "BUFF")
end
local function broken(ts, sg, sn, sf, dg, dn, df, auraId, auraName, byId, byName)
    A.OnCleu(ts, "SPELL_AURA_BROKEN_SPELL", nil, sg, sn, sf, 0, dg, dn, df, 0,
        auraId, auraName, 32, byId, byName, 16, "DEBUFF")
end
local function miss(ts, sg, sn, sf, dg, dn, df, id, name, missType, amountMissed)
    A.OnCleu(ts, "SPELL_MISSED", nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 64, missType, false, amountMissed or 0, false)
end
local function drain(ts, sg, sn, sf, dg, dn, df, id, name, amount)
    A.OnCleu(ts, "SPELL_DRAIN", nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 32, amount, 0, 0)
end
local function died(ts, dg, dn, df)
    A.OnCleu(ts, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, dg, dn, df, 0)
end

-- ===========================================================================
-- Stage A: a match
-- ===========================================================================

CHECK(not A.InMatch(), "A: no match at load")
local m = A.Begin(T0, "Nagrand Arena")
eq(started, 1, "A: start hook fired")
CHECK(A.InMatch() and A.Live() == m, "A: match live")
A.Begin(T0 + 1, "Other")
eq(A.Live().map, "Nagrand Arena", "A: a second Begin never replaces the live match")

A.SetSeat("us", ME, "Devinp", "MAGE", "Human", "player")
A.SetSeat("us", R2, "Shiv", "ROGUE", "NightElf", "party1")
A.SetSeat("us", P3, "Vespers", "PRIEST", "Dwarf", "party2")
eq(m.bracket, 3, "A: bracket from the friendly roster (3)")
-- The enemy is only partly known before the gates: the druid is stealthed
A.SetSeat("them", W1, "Gorehowl", "WARRIOR", "Orc", "arena1")
A.SetSeat("them", L3, "Nethra", "WARLOCK", "Undead", "arena3")
A.SetSeat("them", L3, nil, nil, nil, "arena3") -- nil = not right now
eq(m.seats[L3].name, "Nethra", "A: nil fields never erase a seat's identity")
A.SetOwner(FELHUNTER, L3, "Felhunter")

-- Prep aura fades on us: gates at +60
aura(T0 + 60, "SPELL_AURA_REMOVED", ME, "Devinp", F_ME, ME, "Devinp", F_ME, 32727, "Arena Preparation")
near(m.tGates, 60, "A: gates from the prep aura fade")
eq(m.ledger[1].kind, "GATES", "A: gates moment first")

-- HP snapshots before anything happens
A.SetHealth(ME, 8000, 8000, T0 + 60)
A.SetHealth(W1, 12000, 12000, T0 + 60)

-- Opener: rogue Cheap Shots the druid — a seat the log reveals before any
-- unit token did (hostile PLAYER flags), stealthed until now
aura(T0 + 70, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 1833, "Cheap Shot")
CHECK(m.seats[D2] ~= nil and m.seats[D2].team == "them", "A: hostile player auto-seated on THEM")
eq(m.seats[D2].name, "Leafshade", "A: auto-seat takes the name from the log")
eq(m.bracket, 3, "A: bracket holds at 3 with 3v3")
local cs = m.ledger[m.ledgerN]
eq(cs.kind, "CC", "A: cheap shot is a CC moment")
eq(cs.x, 1, "A: first stun lands at full (bracket 1)")
eq(cs.cat, "STUN", "A: stun category recorded")
eq(m.seats[R2].ccCasts, 1, "A: rogue credited one CC cast")
eq(m.seats[D2].ccTaken, 1, "A: druid took one CC")

-- Rogue damage during the stun; the druid hits back nothing (stunned)
swing(T0 + 71, R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 400, 0, false)
spellDmg(T0 + 72, R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 26862, "Sinister Strike", 600, 0, true)
near(m.seats[R2].dmg, 1000, "A: rogue damage 1000")
near(m.seats[D2].taken, 1000, "A: druid taken 1000")
eq(m.seats[R2].crits, 1, "A: one crit counted")
CHECK(m.seats[R2].spells["Melee"] and m.seats[R2].spells["Melee"].total == 400, "A: melee record")
CHECK(m.seats[R2].targets["Leafshade"] == 1000, "A: target tally")
CHECK(m.seats[D2].sources["Shiv"] == 1000, "A: source tally")

-- Cheap shot fades at +74; Kidney Shot at +74 is its OWN ladder: full
aura(T0 + 74, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 1833, "Cheap Shot")
near(m.ledger[2].t2, 74, "A: cheap shot closed at its fade")
near(m.seats[D2].ccTakenSeconds, 4, "A: druid controlled 4 s so far")
near(m.seats[R2].ccSeconds, 4, "A: rogue's control time 4 s")
aura(T0 + 74, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 408, "Kidney Shot")
eq(m.ledger[m.ledgerN].x, 1, "A: kidney shot is its own category — full")
aura(T0 + 80, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 408, "Kidney Shot")

-- Priest's Hammer? No — the MAGE has no stun; the priest... use a second
-- STUN from the rogue's team: the mage's Impact would be STUN_PROC. Use a
-- paladin-less test: rogue Cheap Shot again at +85 (11 s after the fade at
-- +74): still inside the 15 s window → HALF
aura(T0 + 85, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 1833, "Cheap Shot")
eq(m.ledger[m.ledgerN].x, 2, "A: second stun within 15 s of the FADE lands at half")
aura(T0 + 87, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 1833, "Cheap Shot")
-- A third stun (Hammer id) at +90 → quarter
aura(T0 + 90, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 10308, "Hammer of Justice")
eq(m.ledger[m.ledgerN].x, 3, "A: third stun in the ladder lands at quarter")
aura(T0 + 91, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 10308, "Hammer of Justice")
-- Refresh of an aura that is not open counts as a new application; a
-- refresh of an OPEN one does not
aura(T0 + 92, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 339, "Entangling Roots")
local rootsIdx = m.ledgerN
aura(T0 + 93, "SPELL_AURA_REFRESH", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 339, "Entangling Roots")
eq(m.ledgerN, rootsIdx, "A: refreshing an open CC adds no moment")
aura(T0 + 95, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 339, "Entangling Roots")
-- Stun fully reset: 15 s after the last stun fade (+91) → at +107 full again
aura(T0 + 107, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 1833, "Cheap Shot")
eq(m.ledger[m.ledgerN].x, 1, "A: stun ladder resets 15 s after the FADE")
aura(T0 + 109, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, D2, "Leafshade", F_ENEMY, 1833, "Cheap Shot")

-- Hamstring (LIMIT) is never a CC moment
local beforeN = m.ledgerN
aura(T0 + 109, "SPELL_AURA_APPLIED", W1, "Gorehowl", F_ENEMY, R2, "Shiv", F_PARTY, 1715, "Hamstring")
eq(m.ledgerN, beforeN, "A: Hamstring (LIMIT) is not control")

-- Silence: a control kind with no ladder → CC moment with no bracket
aura(T0 + 110, "SPELL_AURA_APPLIED", FELHUNTER, "Felhunter", F_EPET, P3, "Vespers", F_PARTY, 24259, "Spell Lock")
local sl = m.ledger[m.ledgerN]
eq(sl.kind, "CC", "A: Spell Lock is a CC moment")
eq(sl.x, nil, "A: silence carries no bracket")
eq(sl.src, L3, "A: the felhunter's silence is credited to the warlock")
eq(m.seats[L3].ccCasts, 1, "A: warlock CC cast count via pet")
aura(T0 + 113, "SPELL_AURA_REMOVED", FELHUNTER, "Felhunter", F_EPET, P3, "Vespers", F_PARTY, 24259, "Spell Lock")

-- Spell Lock as a book cooldown (pet cast folds to the warlock for CDs)
cast(T0 + 110, FELHUNTER, "Felhunter", F_EPET, P3, "Vespers", F_PARTY, 19647, "Spell Lock")
eq(m.seats[L3].cds, 1, "A: pet's Spell Lock is the warlock's cooldown")
eq(m.seats[L3].casts, 0, "A: a pet cast is not the warlock's APM")
local cd = m.ledger[m.ledgerN]
eq(cd.kind, "CD", "A: cooldown moment")
eq(cd.x, "KICK", "A: cooldown role from the book")
eq(cd.amount, 24, "A: cooldown length from the book")

-- Warlock fears the priest; the MAGE (a teammate of the caster? no — of the
-- victim) breaks it with a Frostbolt... the mistake is breaking your OWN
-- team's CC: the WARRIOR (warlock's teammate) hits the feared priest
aura(T0 + 115, "SPELL_AURA_APPLIED", L3, "Nethra", F_ENEMY, P3, "Vespers", F_PARTY, 8122, "Psychic Scream")
local fearIdx = m.ledgerN
eq(m.ledger[fearIdx].x, 1, "A: fear at full")
swing(T0 + 116, W1, "Gorehowl", F_ENEMY, P3, "Vespers", F_PARTY, 900, 0, false)
broken(T0 + 116, W1, "Gorehowl", F_ENEMY, P3, "Vespers", F_PARTY, 8122, "Psychic Scream", 6603, "Attack")
near(m.ledger[fearIdx].t2, 116, "A: broken fear closed at the break")
eq(m.ledger[fearIdx].brk, W1, "A: breaker recorded on the moment")
eq(m.ledger[fearIdx].own, true, "A: flagged as an own-team break")
eq(m.seats[W1].ccBroke, 1, "A: warrior broke his team's CC (the mistake counter)")
near(m.seats[L3].ccSeconds, 3 + 1, "A: warlock's control time: 3 s silence + 1 s fear")

-- Mage polymorphs the druid... who is immune (trinket/Berserker Rage
-- would be a different story; IMMUNE arrives as a miss)
miss(T0 + 118, ME, "Devinp", F_ME, D2, "Leafshade", F_ENEMY, 12826, "Polymorph", "IMMUNE")
eq(m.seats[ME].ccWasted, 1, "A: polymorph into immunity is wasted CC")
eq(m.ledger[m.ledgerN].kind, "CCFAIL", "A: CC fail moment")
eq(m.ledger[m.ledgerN].x, "IMMUNE", "A: CC fail carries the miss type")
eq(m.seats[ME].misses, 1, "A: miss counted")
-- A plain damage miss is not wasted CC
miss(T0 + 118, ME, "Devinp", F_ME, D2, "Leafshade", F_ENEMY, 27072, "Frostbolt", "RESIST")
eq(m.seats[ME].ccWasted, 1, "A: a resisted Frostbolt is not wasted CC")

-- Kicks: mage Counterspells the druid's heal; druid Feral Charges the mage
kick(T0 + 120, ME, "Devinp", F_ME, D2, "Leafshade", F_ENEMY, 2139, "Counterspell", 26979, "Regrowth")
eq(m.seats[ME].ints, 1, "A: mage interrupt")
eq(m.seats[D2].intsTaken, 1, "A: druid interrupted")
eq(m.ledger[m.ledgerN].name, "Regrowth", "A: kick moment names the stopped spell")
eq(m.ledger[m.ledgerN].x, "Counterspell", "A: kick moment names the kick")

-- Dispels: priest dispels the mage's Hamstring? No: dispel a friendly
-- (defensive) and purge an enemy (offensive)
dispel(T0 + 121, "SPELL_DISPEL", P3, "Vespers", F_PARTY, ME, "Devinp", F_ME, 527, "Dispel Magic", 8122, "Psychic Scream", "DEBUFF")
eq(m.seats[P3].dispels, 1, "A: friendly dispel counted as a dispel")
eq(m.seats[P3].purges, 0, "A: friendly dispel is not a purge")
dispel(T0 + 122, "SPELL_DISPEL", P3, "Vespers", F_PARTY, D2, "Leafshade", F_ENEMY, 527, "Dispel Magic", 33763, "Lifebloom")
eq(m.seats[P3].purges, 1, "A: enemy dispel counted as a purge")
eq(m.seats[D2].purgesTaken, 1, "A: druid was purged")
eq(m.ledger[m.ledgerN].x, "PURGE", "A: purge moment tagged")
-- Spellsteal is an offensive dispel too
dispel(T0 + 123, "SPELL_STOLEN", ME, "Devinp", F_ME, D2, "Leafshade", F_ENEMY, 30449, "Spellsteal", 774, "Rejuvenation")
eq(m.seats[ME].purges, 1, "A: spellsteal is a purge")

-- A dispelled CC ends now: warlock fears the rogue, priest dispels it
aura(T0 + 124, "SPELL_AURA_APPLIED", L3, "Nethra", F_ENEMY, R2, "Shiv", F_PARTY, 8122, "Psychic Scream")
local fear2 = m.ledgerN
dispel(T0 + 125, "SPELL_DISPEL", P3, "Vespers", F_PARTY, R2, "Shiv", F_PARTY, 527, "Dispel Magic", 8122, "Psychic Scream", "DEBUFF")
near(m.ledger[fear2].t2, 125, "A: dispelled CC closed at the dispel")
eq(m.ledger[fear2].brk, P3, "A: dispeller recorded as the breaker")
eq(m.seats[P3].ccBroke, 0, "A: dispelling an ENEMY's CC is not a mistake")

-- Mana burn: priest drains the druid
drain(T0 + 126, P3, "Vespers", F_PARTY, D2, "Leafshade", F_ENEMY, 25380, "Mana Burn", 1200)
eq(m.seats[P3].drained, 1200, "A: mana drained credited")
eq(m.seats[D2].drainedTaken, 1200, "A: mana drained taken")
eq(m.ledger[m.ledgerN].kind, "DRAIN", "A: drain moment")
-- Non-mana drains (rage) do not count
A.OnCleu(T0 + 126, "SPELL_DRAIN", nil, P3, "Vespers", F_PARTY, 0, W1, "Gorehowl", F_ENEMY, 0, 1, "X", 1, 50, 1, 0)
eq(m.seats[P3].drained, 1200, "A: rage drain ignored")

-- Drinking: the druid sits down
aura(T0 + 130, "SPELL_AURA_APPLIED", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
eq(m.seats[D2].drinks, 1, "A: drink counted")
aura(T0 + 131, "SPELL_AURA_REFRESH", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
eq(m.seats[D2].drinks, 1, "A: a drink refresh is the same drink")
aura(T0 + 138, "SPELL_AURA_REMOVED", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
near(m.seats[D2].drinkSeconds, 8, "A: drink time 8 s")

-- Trinket
cast(T0 + 140, W1, "Gorehowl", F_ENEMY, nil, nil, nil, 42292, "PvP Trinket")
eq(m.seats[W1].trinkets, 1, "A: trinket counted")
eq(m.ledger[m.ledgerN].kind, "TRINKET", "A: trinket moment")
eq(m.seats[W1].casts, 1, "A: trinket press is also a cast (APM)")
-- Auto shot never counts as a cast
cast(T0 + 140, W1, "Gorehowl", F_ENEMY, nil, nil, nil, 75, "Auto Shot")
eq(m.seats[W1].casts, 1, "A: auto shot excluded from APM")
-- Racial from the racial book
cast(T0 + 141, W1, "Gorehowl", F_ENEMY, nil, nil, nil, 28730, "Arcane Torrent")
eq(m.seats[W1].cds, 1, "A: racial cooldown from the racial book")
eq(m.ledger[m.ledgerN - 1].amount, 120, "A: the trinket moment carries its 120 s cooldown")
-- Spec revealed by a signature cast; a pet's cast reveals nothing
eq(m.seats[W1].spec, nil, "A: no spec before a marker is cast")
cast(T0 + 142, W1, "Gorehowl", F_ENEMY, ME, "Devinp", F_ME, 30330, "Mortal Strike")
eq(m.seats[W1].spec, "Arms", "A: Mortal Strike reveals Arms")
eq(m.seats[W1].specRevealed, true, "A: revealed specs are marked as inferred")
eq(m.ledger[m.ledgerN].kind, "SPEC", "A: a SPEC moment is logged")
eq(m.ledger[m.ledgerN].name, "Arms", "A: ...naming the spec")
cast(T0 + 142.5, W1, "Gorehowl", F_ENEMY, ME, "Devinp", F_ME, 12294, "Mortal Strike")
eq(m.ledger[m.ledgerN].kind ~= "SPEC" or m.ledger[m.ledgerN].t ~= T0 + 142.5 - T0, true, "A: a second marker cast reveals nothing new")
cast(T0 + 143, FELHUNTER, "Felhunter", F_EPET, P3, "Vespers", F_PARTY, 30108, "Unstable Affliction")
eq(m.seats[L3].spec, nil, "A: a pet's cast never reveals its owner's spec")
-- Cooldowns at the cursor: the trinket (120 s from +140) and Arcane Torrent (120 s from +141)
local cdState = A.StateAt(m, 150, {})
eq(cdState.seats[W1].cdN, 2, "A: two cooldowns running at +150")
near(cdState.seats[W1].cdLeft[1], 110, "A: trinket has 110 s left at +150")
cdState = A.StateAt(m, 139, cdState)
eq(cdState.seats[W1].cdN, 0, "A: nothing running before the press")
cdState = A.StateAt(m, 261, cdState)
eq(cdState.seats[W1].cdN, 0, "A: cooldowns expire after their length")

-- Healing with overheal; absorb credit via SPELL_ABSORBED (spell form)
heal(T0 + 145, P3, "Vespers", F_PARTY, ME, "Devinp", F_ME, 25213, "Greater Heal", 3000, 500, true)
near(m.seats[P3].heal, 2500, "A: effective healing 2500")
near(m.seats[P3].overheal, 500, "A: overheal tracked")
A.OnCleu(T0 + 146, "SPELL_ABSORBED", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0,
    5308, "Execute", 1, P3, "Vespers", F_PARTY, 0, 25218, "Power Word: Shield", 2, 700, false)
near(m.seats[P3].absorb, 700, "A: shield absorb credited to the priest")
CHECK(m.seats[P3].heals["Power Word: Shield"] and m.seats[P3].heals["Power Word: Shield"].total == 700,
    "A: shield shows as a healing record")
-- The paired damage: 300 landed + 700 absorbed = 1000 on both sides
spellDmg(T0 + 146, W1, "Gorehowl", F_ENEMY, ME, "Devinp", F_ME, 5308, "Execute", 300, 700, false)
near(m.seats[W1].dmg, 900 + 1000, "A: warrior damage includes the absorbed portion")
near(m.seats[ME].taken, 1000, "A: mage taken includes the absorbed portion")
near(m.seats[W1].absorbedOut, 700, "A: absorbed-of-his-hits tracked")

-- Orphan enemy minion: skipped with an anomaly, never guessed
spellDmg(T0 + 147, ORPHAN, "Voidwalker", F_EPET, ME, "Devinp", F_ME, 3716, "Torment", 100, 0, false)
near(m.seats[ME].taken, 1100, "A: victim side still records an orphan minion's hit")
CHECK(A.GetAnomalies()["minion with unknown owner (Voidwalker)"] == 1, "A: orphan minion anomaly counted")
eq(m.seats[ORPHAN], nil, "A: orphan minion never becomes a seat")

-- Chained summon: the warlock summons a new pet mid-match
A.OnCleu(T0 + 148, "SPELL_SUMMON", nil, L3, "Nethra", F_ENEMY, 0, "Pet-0-SUCC", "Succubus", F_EPET, 0, 712, "Summon Succubus", 32)
spellDmg(T0 + 149, "Pet-0-SUCC", "Succubus", F_EPET, ME, "Devinp", F_ME, 7870, "Lash of Pain", 250, 0, false)
near(m.seats[L3].dmg, 250, "A: summoned pet damage lands on the warlock")
CHECK(m.seats[L3].spells["Succubus: Lash of Pain"] ~= nil, "A: pet key names the pet")

-- HP snapshots over time
A.SetHealth(ME, 6000, 8000, T0 + 150)
A.SetHealth(ME, 3000, 8000, T0 + 155)
A.SetHealth(D2, 2000, 10000, T0 + 155)

-- Deaths: the druid dies to the mage's Frostbolt at +160 (last hit within 6 s)
spellDmg(T0 + 158, ME, "Devinp", F_ME, D2, "Leafshade", F_ENEMY, 27072, "Frostbolt", 1800, 0, true)
died(T0 + 160, D2, "Leafshade", F_ENEMY)
eq(m.seats[D2].deaths, 1, "A: druid death")
eq(m.seats[ME].kills, 1, "A: mage killing blow (last hit within the window)")
eq(#m.deaths, 1, "A: one death in the list")
eq(m.deaths[1].killer, ME, "A: death names the killer")
eq(m.deaths[1].name, "Frostbolt", "A: death names the blow")
CHECK(m.firstBlood and m.firstBlood.guid == D2, "A: first blood is the druid")
eq(m.ledger[m.ledgerN].kind, "DEATH", "A: death moment")
-- A death with no recent hit credits nobody
died(T0 + 170, P3, "Vespers", F_PARTY)
eq(m.seats[P3].deaths, 1, "A: priest death")
eq(m.seats[W1].kills, 0, "A: stale hit (>6 s) earns no kill")
eq(m.deaths[2].killer, nil, "A: unattributed death has no killer")

-- Cumulative values at a cursor time (replay)
local DMG = A.StatByKey("DMG")
local v = A.SeatValueAt(m, m.seats[R2], DMG, 71.5)
near(v, 400, "A: rogue damage at +71.5 = 400 (the swing only)")
v = A.SeatValueAt(m, m.seats[R2], DMG, 72)
near(v, 1000, "A: rogue damage at +72 includes the strike")
v = A.SeatValueAt(m, m.seats[W1], DMG, nil)
near(v, 1900, "A: whole-match value")
local CC = A.StatByKey("CC")
local secs, count = A.SeatValueAt(m, m.seats[R2], CC, 76)
-- cheap shot 70-74 (4 s) + kidney 74-76 (2 s so far) = 6, two casts
near(secs, 6, "A: control seconds at +76 (open CC counted to the cursor)")
eq(count, 2, "A: control casts at +76")
local KILLS = A.StatByKey("KILLS")
eq((A.SeatValueAt(m, m.seats[ME], KILLS, 159)), 0, "A: no kill before the death")
eq((A.SeatValueAt(m, m.seats[ME], KILLS, 160)), 1, "A: kill at the death")
local MANA = A.StatByKey("MANA")
eq((A.SeatValueAt(m, m.seats[P3], MANA, 200)), 1200, "A: ledger amount stat")
local CDS = A.StatByKey("CDS")
eq((A.SeatValueAt(m, m.seats[W1], CDS, 200)), 2, "A: cooldowns + trinkets at the cursor")

-- Rows and team totals
local rows, n, totals = A.CollectRows(m, DMG, nil)
eq(n, 6, "A: six seats in the rows")
eq(rows[1].seat.guid, W1, "A: warrior leads damage (1900)")
eq(rows[2].seat.guid, ME, "A: mage second (1800)")
near(totals.us, 1800 + 1000, "A: friendly team damage")
near(totals.them, 1900 + 250, "A: enemy team damage")

-- Replay state
local state = A.StateAt(m, 152, {})
near(state.seats[ME].hp, 0.75, "A: mage hp at +152 is the +150 snapshot")
near(state.seats[W1].hp, 1, "A: warrior hp from the +60 snapshot")
eq(state.seats[D2].alive, true, "A: druid alive at +152")
state = A.StateAt(m, 161, state)
eq(state.seats[D2].alive, false, "A: druid dead at +161")
eq(state.seats[D2].hp, 0, "A: dead seat reads 0 hp")
state = A.StateAt(m, 72, state)
eq(state.seats[D2].ccN, 1, "A: druid under one control at +72")
eq(state.seats[D2].cc[1].name, "Cheap Shot", "A: the control is the cheap shot")
state = A.StateAt(m, 74.5, state)
eq(state.seats[D2].ccN, 1, "A: kidney shot covers +74.5")
eq(state.seats[D2].cc[1].name, "Kidney Shot", "A: control swapped to the kidney shot")
state = A.StateAt(m, 100, state)
eq(state.seats[D2].ccN, 0, "A: no control at +100")

-- Ledger search
local idx = A.LedgerIndexAt(m, 115)
eq(m.ledger[idx].t, 115, "A: ledger index at exactly 115")
idx = A.LedgerIndexAt(m, 114.5)
eq(m.ledger[idx].t, 115, "A: ledger index rounds forward")
eq(A.LedgerIndexAt(m, 1e9), m.ledgerN + 1, "A: past the end")

-- Scoreboard merge + team info + finish
local merged = A.MergeScoreboard(m, {
    { name = "Devinp-Realm", kb = 1, hk = 3, deaths = 0, dmg = 20000, heal = 100, ratingChange = 14, mmr = 1900, classToken = "MAGE" },
    { name = "Leafshade", kb = 0, hk = 1, deaths = 1, dmg = 3000, heal = 15000, ratingChange = -12, mmr = 1880, classToken = "DRUID", race = "Tauren" },
    { name = "Nobody", kb = 0 },
})
eq(merged, 2, "A: two scoreboard rows merged by short name")
eq(m.seats[ME].sb.ratingChange, 14, "A: rating change on the seat")
eq(m.seats[D2].race, "Tauren", "A: race filled from the scoreboard")
eq(m.rated, true, "A: a rating change marks the match rated")
A.SetTeamInfo(m, "us", { name = "Big Chungus", before = 1850, after = 1864 })
A.SetTeamInfo(m, "them", { name = "Leaf Me Alone", before = 1870, after = 1858, mmr = 1866 })
eq(m.teams.us.name, "Big Chungus", "A: team name")
eq(m.teams.them.ratingAfter, 1858, "A: enemy rating after")

-- An open CC at the end is closed at the end
aura(T0 + 175, "SPELL_AURA_APPLIED", ME, "Devinp", F_ME, W1, "Gorehowl", F_ENEMY, 12826, "Polymorph")
local polyIdx = m.ledgerN
local closed = A.Finish(T0 + 180, "WIN", 118)
CHECK(closed == m and ended == m, "A: finish returned and hooked the match")
CHECK(not A.InMatch(), "A: no live match after finish")
eq(m.result, "WIN", "A: result")
near(m.tEnd, 180, "A: end stamp")
near(m.dur, 120, "A: duration from the gates to the end")
eq(m.runTime, 118, "A: server run time kept")
near(m.ledger[polyIdx].t2, 180, "A: open CC closed at the end")
eq(m.ledger[m.ledgerN].kind, "END", "A: END moment last")
eq(m.ledger[m.ledgerN].name, "WIN", "A: END carries the result")
eq(A.GetMatch("last"), m, "A: last selector")
eq(A.GetMatch(m.id), m, "A: id selector")
eq(A.GetMatch("live"), nil, "A: live selector empty")
CHECK(A.SeatValueAt(m, m.seats[ME], CC, nil) == m.seats[ME].ccSeconds, "A: whole-match CC value is the counter")
near(A.DurationAt(m, nil), 120, "A: whole-match duration")
near(A.DurationAt(m, 90), 30, "A: duration at a cursor")
near(A.DurationAt(m, 10), 1, "A: pre-gate duration floors at 1")

-- Pressure series
local pr = A.Pressure(m, {})
eq(pr.n, 180, "A: pressure buckets to the end")
near(pr.us[72], 400, "A: friendly pressure bucket 72 (the +71 swing)")
near(pr.us[73], 600, "A: friendly pressure bucket 73 (the +72 strike)")
near(pr.them[147], 1000, "A: enemy pressure at +147 (bucket of the execute)")
CHECK(pr.peak >= 1800, "A: peak is the biggest bucket", pr.peak)

-- Insights: the match read back as findings
local ins = A.Insights(m, {})
local byKind = {}
for i = 1, ins.n do byKind[ins[i].kind] = byKind[ins[i].kind] or {}; table.insert(byKind[ins[i].kind], ins[i]) end
CHECK(byKind.FIRSTBLOOD and byKind.FIRSTBLOOD[1].guid == D2, "A: first blood insight names the druid")
CHECK(ins[1].kind == "OWNBREAK", "A: the earliest timed insight leads (the own-team break at +116)", ins[1].kind)
eq(#byKind.KILL, 2, "A: one KILL insight per death")
local killD2 = byKind.KILL[1]
CHECK(killD2.guid == D2 and killD2.killer == ME and killD2.blow == "Frostbolt", "A: kill insight names victim, killer and blow")
eq(#killD2.controlled, 0, "A: no teammate of the druid was controlled in the 10 s before")
CHECK(byKind.OWNBREAK and #byKind.OWNBREAK == 1 and byKind.OWNBREAK[1].guid == W1 and byKind.OWNBREAK[1].victim == P3,
    "A: the warrior's own-team fear break is an insight")
CHECK(byKind.TRINKET and byKind.TRINKET[1].guid == W1 and byKind.TRINKET[1].aura == nil,
    "A: trinket insight with nothing broken")
CHECK(byKind.WASTED and byKind.WASTED[1].guid == ME and byKind.WASTED[1].count == 1, "A: wasted CC insight")
CHECK(byKind.DRINK and byKind.DRINK[1].guid == D2 and math.abs(byKind.DRINK[1].seconds - 8) < 1e-6, "A: drink insight")
CHECK(byKind.SHARE and #byKind.SHARE == 3, "A: damage share per team + healing share (only US healed)", byKind.SHARE and #byKind.SHARE)
CHECK(byKind.CCTIME and byKind.CCTIME[1].us > byKind.CCTIME[1].them, "A: control time insight compares teams")
CHECK(byKind.KICKS and byKind.KICKS[1].us == 1 and byKind.KICKS[1].them == 0, "A: kick totals")
-- Timed insights come first in clock order, summaries after
local lastTimed = 0
for i = 1, ins.n do if ins[i].t then lastTimed = i end end
for i = 1, lastTimed - 1 do
    CHECK(ins[i].t and ins[i + 1].t and ins[i].t <= ins[i + 1].t, "A: insights sorted by time at " .. i)
end
-- A kill with a controlled teammate: poly on the warrior 175-180, warrior's teammate... use a fresh scenario
do
    local K = LoadArena()
    K.SetDRTable({ [12826] = "POLY" }, {})
    local km = K.Begin(T0, "K")
    K.SetSeat("us", ME, "Devinp", "MAGE")
    K.SetSeat("them", W1, "Gorehowl", "WARRIOR")
    K.SetSeat("them", D2, "Leafshade", "DRUID")
    K.OnCleu(T0 + 10, "SPELL_AURA_APPLIED", nil, ME, "Devinp", F_ME, 0, D2, "Leafshade", F_ENEMY, 0, 12826, "Polymorph", 1, "DEBUFF")
    K.OnCleu(T0 + 14, "SPELL_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 27072, "Frostbolt", 16, 5000, 0, 16, 0, 0, 0, true, false, false, false)
    K.OnCleu(T0 + 15, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, W1, "Gorehowl", F_ENEMY, 0)
    K.OnCleu(T0 + 18, "SPELL_AURA_REMOVED", nil, ME, "Devinp", F_ME, 0, D2, "Leafshade", F_ENEMY, 0, 12826, "Polymorph", 1, "DEBUFF")
    K.Finish(T0 + 20, "WIN")
    local ki = K.Insights(K.GetMatches()[1], {})
    local kill
    for i = 1, ki.n do if ki[i].kind == "KILL" then kill = ki[i] end end
    CHECK(kill and #kill.controlled == 1 and kill.controlled[1].guid == D2, "A: the healer's sheep shows on the kill")
    near(kill.controlled[1].dur, 5, "A: controlled 5 s of the 10 s window before the kill (10→15)")
    -- Trinket that broke a CC is named
    local T = LoadArena()
    T.SetDRTable({ [12826] = "POLY" }, {})
    local tmm = T.Begin(T0, "T")
    T.SetSeat("us", ME, "Devinp", "MAGE")
    T.SetSeat("them", W1, "Gorehowl", "WARRIOR")
    T.OnCleu(T0 + 10, "SPELL_AURA_APPLIED", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 12826, "Polymorph", 1, "DEBUFF")
    T.OnCleu(T0 + 12, "SPELL_CAST_SUCCESS", nil, W1, "Gorehowl", F_ENEMY, 0, "", "", 0x80000000, 0, 42292, "PvP Trinket", 1)
    T.OnCleu(T0 + 12, "SPELL_AURA_REMOVED", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 12826, "Polymorph", 1, "DEBUFF")
    T.OnCleu(T0 + 13, "SWING_DAMAGE", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 100, 0, 1, 0, 0, 0, false, false, false, false)
    T.Finish(T0 + 20, "WIN")
    local ti = T.Insights(T.GetMatches()[1], {})
    local trk
    for i = 1, ti.n do if ti[i].kind == "TRINKET" then trk = ti[i] end end
    CHECK(trk and trk.aura == "Polymorph", "A: the trinket insight names the control it broke")
end

-- A fixed bucket count spans the plot regardless of where damage stopped
local prF = A.Pressure(m, {}, 400)
eq(prF.n, 400, "A: Pressure honors an explicit bucket count")
near(prF.us[400], 0, "A: buckets past the last blow read zero")
near(prF.us[73], 600, "A: ...and the real buckets are unchanged")
eq(A.Pressure(m, {}, 0).n, 1, "A: Pressure never spans fewer than one bucket")

-- Events after the finish are dropped (no live match)
local snapBefore = A.Serialize(m)
spellDmg(T0 + 181, ME, "Devinp", F_ME, W1, "Gorehowl", F_ENEMY, 27072, "Frostbolt", 1800, 0, false)
eq(A.Serialize(m), snapBefore, "A: a closed match is immutable")

-- ===========================================================================
-- Stage B: discard, abort, retention, fallback CC names
-- ===========================================================================

-- A match nobody played is discarded outright
A.Begin(T0 + 1000, "Blade's Edge Arena")
A.SetSeat("us", ME, "Devinp", "MAGE")
ended = "unset"
local r = A.Abort(T0 + 1010)
eq(r, nil, "B: an unplayed match is discarded")
eq(ended, nil, "B: end hook receives nil for a discard")
eq(#A.GetMatches(), 1, "B: nothing archived")
local m2 = A.Begin(T0 + 2000, "Ruins of Lordaeron")
eq(m2.id, 2, "B: discarded match returns its number")

-- LEFT result with gates but no blows still archives (a forfeit)
A.SetSeat("us", ME, "Devinp", "MAGE")
A.SetGates(T0 + 2030)
A.Abort(T0 + 2040)
eq(A.GetMatches()[1].result, "LEFT", "B: leaving archives as LEFT once the gates opened")
eq(#A.GetMatches(), 2, "B: two matches kept")

-- Name fallback when no DR table is installed
local A2 = LoadArena()
A2.SetCCNames({ ["Polymorph"] = true })
local mx = A2.Begin(T0, "X")
A2.SetSeat("us", ME, "Devinp", "MAGE")
aura(T0 + 10, "SPELL_AURA_APPLIED", ME, "Devinp", F_ME, W1, "Gorehowl", F_ENEMY, 12826, "Polymorph")
-- (aura helper uses the global A; call A2 directly)
A2.OnCleu(T0 + 10, "SPELL_AURA_APPLIED", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 12826, "Polymorph", 1, "DEBUFF")
eq(mx.ledger[mx.ledgerN].kind, "CC", "B: name fallback recognizes CC")
eq(mx.ledger[mx.ledgerN].x, nil, "B: name fallback has no bracket")
eq(mx.ledger[mx.ledgerN].cat, "CC", "B: name fallback category")
A2.OnCleu(T0 + 11, "SPELL_AURA_APPLIED", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 1833, "Cheap Shot", 1, "DEBUFF")
eq(mx.ledgerN, 1, "B: unknown names are not CC without a table")

-- Retention: MAX_MATCHES ring
local A3 = LoadArena()
for i = 1, 25 do
    local mm = A3.Begin(T0 + i * 1000, "Map" .. i)
    A3.SetSeat("us", ME, "Devinp", "MAGE")
    A3.OnCleu(T0 + i * 1000 + 5, "SWING_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "G", F_ENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    A3.Finish(T0 + i * 1000 + 10, "WIN")
end
eq(#A3.GetMatches(), 20, "B: ring holds 20 matches")
eq(A3.GetMatches()[1].id, 25, "B: newest first")
eq(A3.GetMatches()[20].id, 6, "B: oldest kept is #6")

-- Ledger cap: deaths still land past the cap, the drop count is honest
local A4 = LoadArena()
local mc = A4.Begin(T0, "Cap")
A4.SetSeat("us", ME, "Devinp", "MAGE")
A4.SetSeat("them", W1, "Gorehowl", "WARRIOR")
for i = 1, 4100 do
    A4.OnCleu(T0 + i * 0.01, "SPELL_INTERRUPT", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0,
        2139, "Counterspell", 1, 1, "Heal", 2)
end
eq(mc.ledgerN, 4000, "B: ledger capped at 4000")
eq(mc.ledgerDropped, 100, "B: drops counted")
eq(mc.seats[ME].ints, 4100, "B: counters keep counting past the ledger cap")
A4.OnCleu(T0 + 50, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, W1, "Gorehowl", F_ENEMY, 0)
eq(mc.ledger[mc.ledgerN].kind, "DEATH", "B: a death still lands past the cap")

-- History over the kept matches (A has: the WIN vs WARRIOR/DRUID/WARLOCK
-- with first blood drawn, and the LEFT forfeit)
do
    local H = LoadArena()
    local function play(i, result, comp, fbTeam, before, after, map)
        local hm = H.Begin(T0 + i * 1000, map or "Nagrand Arena")
        H.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
        for j, cls in ipairs(comp) do H.SetSeat("them", "Player-1-H" .. i .. j, "E" .. j, cls) end
        H.SetGates(T0 + i * 1000 + 10)
        H.OnCleu(T0 + i * 1000 + 20, "SWING_DAMAGE", nil, ME, "Devinp", F_ME, 0, "Player-1-H" .. i .. "1", "E1", F_ENEMY, 0,
            100, 0, 1, 0, 0, 0, false, false, false, false)
        if fbTeam == "them" then
            H.OnCleu(T0 + i * 1000 + 40, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, "Player-1-H" .. i .. "1", "E1", F_ENEMY, 0)
        elseif fbTeam == "us" then
            H.OnCleu(T0 + i * 1000 + 40, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, ME, "Devinp", F_ME, 0)
        end
        if before then H.SetTeamInfo(hm, "us", { before = before, after = after }) end
        H.Finish(T0 + i * 1000 + 130, result)
    end
    play(1, "WIN", { "WARRIOR", "DRUID" }, "them", 1500, 1512)
    play(2, "LOSS", { "WARRIOR", "DRUID" }, "us", 1512, 1500)
    play(3, "WIN", { "ROGUE", "PRIEST" }, "them", 1500, 1513, "Blade's Edge Arena")
    play(4, "LEFT", { "ROGUE", "PRIEST" }, nil)
    play(5, "WIN", { "MAGE", "ROGUE", "PRIEST" }, "us", nil, nil)
    local hist = H.History(H.GetMatches(), {})
    local by = {}
    for i = 1, hist.n do by[hist[i].kind] = by[hist[i].kind] or {}; table.insert(by[hist[i].kind], hist[i]) end
    local recd = by.RECORD[1]
    CHECK(recd.played == 5 and recd.wins == 3 and recd.losses == 1 and recd.left == 1, "H: record 3-1 with one forfeit")
    CHECK(by.RATING and by.RATING[1].delta == 13 and by.RATING[1].from == 1500 and by.RATING[1].to == 1513 and by.RATING[1].n == 3,
        "H: rating trend +13 across the three rated games, oldest first", by.RATING and by.RATING[1].delta)
    CHECK(by.BRACKET and #by.BRACKET == 2 and by.BRACKET[1].size == 2 and by.BRACKET[1].played == 4 and by.BRACKET[1].wins == 2
        and by.BRACKET[2].size == 3 and by.BRACKET[2].wins == 1, "H: per-bracket records")
    CHECK(by.COMP and by.COMP[1].played == 2 and by.COMP[2].played == 2 and by.COMP[3].comp == "MAGE/PRIEST/ROGUE",
        "H: comps sorted by games then name; classes sorted inside a comp", by.COMP and by.COMP[3].comp)
    local wd
    for _, c in ipairs(by.COMP) do if c.comp == "DRUID/WARRIOR" then wd = c end end
    CHECK(wd and wd.wins == 1 and wd.losses == 1, "H: 1-1 against warrior/druid")
    CHECK(by.MAP and by.MAP[1].map == "Nagrand Arena" and by.MAP[1].played == 4 and by.MAP[2].played == 1, "H: per-map records")
    local fbr = by.FIRSTBLOOD[1]
    CHECK(fbr.drew == 2 and fbr.wonWhenDrew == 2 and fbr.gave == 2 and fbr.wonWhenGave == 1, "H: first-blood conversion")
    local tim = by.TIMING[1]
    CHECK(tim.n == 4 and math.abs(tim.avgDur - 120) < 1e-6, "H: average length excludes the forfeit", tim.avgDur)
    CHECK(math.abs(tim.avgFirstBlood - 30) < 1e-6, "H: average first blood from the gates", tim.avgFirstBlood)
    eq(H.History({}, {}).n, 1, "H: an empty history still carries a RECORD line")
    -- Store ladder: a newer store is refused; the current one imports
    local st = H.Export(10)
    eq(H.Import({ v = 99, matches = {} }), 0, "H: a store from the future is refused")
    local H2 = LoadArena()
    eq(H2.Import(st), 5, "H: a current store imports whole")
    eq(H2.Import({ v = 0, matches = {} }), 0, "H: an older store with no migration step is refused")
end

-- Personal rating (teamless season): YOUR scoreboard row is the number,
-- never a teammate's, never the team fields
do
    local P = LoadArena()
    local function game(i, myChange, mateChange, opts)
        opts = opts or {}
        local pm = P.Begin(T0 + i * 1000, "Nagrand Arena")
        P.SetSeat("us", R2, "Shiv", "ROGUE", nil, "party1") -- seated first, so pairs() order cannot save us
        P.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
        P.SetSeat("them", W1, "Gorehowl", "WARRIOR")
        P.SetSeat("them", D2, "Leafshade", "DRUID")
        if opts.mine then P.SetMyRatings(pm, opts.mine) end
        P.SetGates(T0 + i * 1000 + 10)
        P.OnCleu(T0 + i * 1000 + 20, "SWING_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0,
            100, 0, 1, 0, 0, 0, false, false, false, false)
        P.MergeScoreboard(pm, {
            { name = "Shiv", ratingChange = mateChange },
            { name = "Devinp-Realm", ratingChange = myChange },
            { name = "Gorehowl", ratingChange = -myChange },
        }, 0)
        P.SetTeamInfo(pm, "us", { name = opts.teamName, before = opts.tb, after = opts.ta, mmr = 1720, teamless = opts.teamless })
        P.SetTeamInfo(pm, "them", { before = 0, after = 0, mmr = 1690, teamless = opts.teamless })
        P.Finish(T0 + i * 1000 + 120, myChange > 0 and "WIN" or "LOSS")
        if opts.late then P.SetMyRatings(pm, opts.late) end
        return pm
    end
    local g1 = game(1, 17, 9, { teamless = true, tb = 0, ta = 0, mine = { [2] = 1600, [3] = 1400 } })
    local b, a, c = P.OurRating(g1)
    CHECK(b == 1600 and a == 1617 and c == 17, "R: teamless reads my row and my 2v2 rating before the gates", tostring(b) .. "/" .. tostring(a) .. "/" .. tostring(c))
    CHECK(g1.teamless and g1.teams.us.ratingBefore == nil and g1.teams.them.ratingAfter == nil, "R: teamless keeps no team rating")
    eq(g1.teams.us.mmr, 1720, "R: teamless keeps the side's average MMR")
    local g2 = game(2, -11, -20, { teamless = true, late = { [2] = 1500 } })
    b, a, c = P.OurRating(g2)
    CHECK(b == nil and c == -11, "R: no snapshot -> change only; a post-result ratings read is refused", tostring(b) .. "/" .. tostring(c))
    -- A record from before `teamless` existed, carrying nonsense team numbers
    local g3 = game(3, 14, 22, { tb = 1500, ta = 1536 })
    b, a, c = P.OurRating(g3)
    eq(c, 14, "R: my scoreboard row outranks stale team before/after")
    local hist = P.History(P.GetMatches(), {})
    local rt
    for i = 1, hist.n do if hist[i].kind == "RATING" then rt = hist[i] end end
    CHECK(rt and rt.delta == 20 and rt.n == 3 and rt.from == 1600 and rt.to == 1617, "R: history sums my own changes", rt and (rt.delta .. " n" .. rt.n .. " " .. tostring(rt.from) .. ">" .. tostring(rt.to)))
end

-- ===========================================================================
-- Stage C: persistence round trip
-- ===========================================================================

local store = A.Export(10)
eq(#store.matches, 2, "C: export keeps up to N matches")
eq(store.v, 1, "C: store version")
-- Strip removed live bookkeeping
CHECK(store.matches[2].seats[ME].dr and next(store.matches[2].seats[ME].dr) == nil, "C: DR clocks stripped")
local exportedSnap = A.Serialize(store.matches[2])

local A5 = LoadArena()
eq(A5.Import(store), 2, "C: import adopts both matches")
eq(#A5.GetMatches(), 2, "C: imported matches listed")
eq(A5.Serialize(A5.GetMatches()[2]), exportedSnap, "C: imported match is byte-identical to the export")
eq(A5.GetMatch(1).result, "WIN", "C: imported match keeps its result")
-- New matches number past the imported ones
local mn = A5.Begin(T0 + 9000, "New")
eq(mn.id, 3, "C: counter continues past imported ids")

-- Malformed stores are refused
eq(A5.Import({ v = 99, matches = {} }), 0, "C: wrong version refused")
eq(A5.Import("junk"), 0, "C: non-table refused")
local bad = { v = 1, matches = { { id = 7, seats = "x" } } }
eq(A5.Import(bad), 0, "C: malformed match refused")
local badSeat = { v = 1, matches = { { id = 7, seats = { [ME] = { dmg = "no", spells = {}, team = "us" } },
    teams = { us = {}, them = {} }, ledger = {}, ledgerN = 0, dur = 1, tsStart = 1, deaths = {} } } }
eq(A5.Import(badSeat), 0, "C: malformed seat refused")
-- A session already at the ring limit takes nothing more
local A6 = LoadArena()
for i = 1, 20 do
    A6.Begin(T0 + i * 100, "M")
    A6.SetSeat("us", ME, "Devinp", "MAGE")
    A6.OnCleu(T0 + i * 100 + 1, "SWING_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "G", F_ENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    A6.Finish(T0 + i * 100 + 5, "WIN")
end
eq(A6.Import(store), 0, "C: a full ring adopts nothing")

-- ResetAll
A6.ResetAll()
eq(#A6.GetMatches(), 0, "C: reset clears the ring")
CHECK(not A6.InMatch(), "C: reset clears the live match")

-- ===========================================================================
-- Stage D: determinism — the same fixture twice serializes identically
-- ===========================================================================

local function RunFixture()
    local X = LoadArena()
    X.SetDRTable({ [1833] = "STUN", [408] = "KIDNEY" }, {})
    local mm = X.Begin(T0, "Det")
    X.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
    X.SetSeat("them", W1, "Gorehowl", "WARRIOR", nil, "arena1")
    X.OnCleu(T0 + 5, "SPELL_AURA_APPLIED", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 1833, "Cheap Shot", 1, "DEBUFF")
    X.OnCleu(T0 + 6, "SPELL_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0,
        27072, "Frostbolt", 16, 900, 0, 16, 0, 0, 0, false, false, false, false)
    X.OnCleu(T0 + 9, "SPELL_AURA_REMOVED", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 1833, "Cheap Shot", 1, "DEBUFF")
    X.SetHealth(W1, 5000, 10000, T0 + 7)
    X.Finish(T0 + 20, "WIN", 15)
    return X.Serialize(X.GetMatches()[1])
end
eq(RunFixture(), RunFixture(), "D: byte-identical replay")

-- ===========================================================================
-- Stage E: throughput
-- ===========================================================================

local AB = LoadArena()
AB.SetDRTable({ [1833] = "STUN" }, {})
local mb = AB.Begin(T0, "Bench")
AB.SetSeat("us", ME, "Devinp", "MAGE")
AB.SetSeat("us", R2, "Shiv", "ROGUE")
AB.SetSeat("us", P3, "Vespers", "PRIEST")
AB.SetSeat("them", W1, "Gorehowl", "WARRIOR")
AB.SetSeat("them", D2, "Leafshade", "DRUID")
AB.SetSeat("them", L3, "Nethra", "WARLOCK")
local srcs = { ME, R2, P3, W1, D2, L3 }
local NEVENTS = 200000
local t0 = os.clock()
for i = 1, NEVENTS do
    local s = srcs[(i % 6) + 1]
    local d = srcs[((i + 3) % 6) + 1]
    local sf = (i % 6) < 3 and F_PARTY or F_ENEMY
    local df = (i % 6) < 3 and F_ENEMY or F_PARTY
    AB.OnCleu(T0 + i * 0.005, "SPELL_DAMAGE", nil, s, "S", sf, 0, d, "D", df, 0,
        27072, "Frostbolt", 16, 500 + (i % 300), 0, 16, 0, 0, (i % 7 == 0) and 40 or 0, i % 5 == 0, false, false, false)
end
local ingest = os.clock() - t0
t0 = os.clock()
local st = {}
for i = 1, 500 do AB.StateAt(mb, 500 + i, st) end
local stateMs = (os.clock() - t0) / 500 * 1000
t0 = os.clock()
for i = 1, 500 do AB.CollectRows(mb, AB.STATS[1], 600) end
local rowsMs = (os.clock() - t0) / 500 * 1000
t0 = os.clock()
local pp = {}
for i = 1, 100 do AB.Pressure(mb, pp) end
local pressMs = (os.clock() - t0) / 100 * 1000
io.write(string.format("STAGE E: %d events in %.3fs (%.2f us/event); StateAt %.3f ms; CollectRows(DMG@t) %.3f ms; Pressure %.3f ms\n",
    NEVENTS, ingest, ingest / NEVENTS * 1e6, stateMs, rowsMs, pressMs))

-- ===========================================================================
-- Stage F: review pass 1 — missed fades, self-kills, END ordering,
-- scoreboard-only seats, the one-pass ledger accumulator
-- ===========================================================================

do
    local F = LoadArena()
    F.SetDRTable({ [1833] = "STUN", [12826] = "POLY" }, {})
    F.SetDrinkIds({ 430 })
    local fm = F.Begin(T0, "Review")
    F.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
    F.SetSeat("us", R2, "Shiv", "ROGUE", nil, "party1")
    F.SetSeat("them", W1, "Gorehowl", "WARRIOR", nil, "arena1")
    F.SetSeat("them", D2, "Leafshade", "DRUID", nil, "arena2")
    local function fa(ts, sub, sg, sn, sf, dg, dn, df, id, name)
        F.OnCleu(ts, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 1, "DEBUFF")
    end
    -- (1) A Cheap Shot whose fade was never logged: the next Cheap Shot must
    -- still count, and the stale one closes at the 12 s cap
    fa(T0 + 10, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, W1, "Gorehowl", F_ENEMY, 1833, "Cheap Shot")
    local firstIdx = fm.ledgerN
    fa(T0 + 40, "SPELL_AURA_APPLIED", R2, "Shiv", F_PARTY, W1, "Gorehowl", F_ENEMY, 1833, "Cheap Shot")
    eq(fm.ledgerN, firstIdx + 1, "F: a fresh APPLIED while the aura is stale-open counts as a new CC")
    near(fm.ledger[firstIdx].t2, 22, "F: the stale CC closed at its 12 s cap")
    eq(fm.seats[W1].ccTaken, 2, "F: both applications counted on the victim")
    -- 30 s after the (capped) fade the stun ladder had reset: full again
    eq(fm.ledger[fm.ledgerN].x, 1, "F: ladder reset after the capped fade (>15 s)")
    -- A REFRESH while open is still the same CC
    fa(T0 + 41, "SPELL_AURA_REFRESH", R2, "Shiv", F_PARTY, W1, "Gorehowl", F_ENEMY, 1833, "Cheap Shot")
    eq(fm.ledgerN, firstIdx + 1, "F: a REFRESH of an open CC adds nothing")
    fa(T0 + 44, "SPELL_AURA_REMOVED", R2, "Shiv", F_PARTY, W1, "Gorehowl", F_ENEMY, 1833, "Cheap Shot")
    near(fm.seats[R2].ccSeconds, 12 + 4, "F: control time = capped 12 + real 4")
    -- Same for drinks: a second APPLIED without a REMOVED is a second drink
    fa(T0 + 50, "SPELL_AURA_APPLIED", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
    fa(T0 + 100, "SPELL_AURA_APPLIED", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
    eq(fm.seats[D2].drinks, 2, "F: a fresh drink APPLIED while one is stale-open is a second drink")
    near(fm.seats[D2].drinkSeconds, 30, "F: the stale drink closed at its 30 s cap")
    fa(T0 + 101, "SPELL_AURA_REFRESH", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
    eq(fm.seats[D2].drinks, 2, "F: a drink REFRESH is the same drink")
    fa(T0 + 105, "SPELL_AURA_REMOVED", D2, "Leafshade", F_ENEMY, D2, "Leafshade", F_ENEMY, 430, "Drink")
    near(fm.seats[D2].drinkSeconds, 35, "F: drink seconds 30 + 5")

    -- (3) Self-inflicted death credits nobody; an unseated hitter names the
    -- blow but is no killer
    F.OnCleu(T0 + 110, "SPELL_DAMAGE", nil, ME, "Devinp", F_ME, 0, ME, "Devinp", F_ME, 0,
        1454, "Life Tap", 32, 900, 0, 32, 0, 0, 0, false, false, false, false)
    F.OnCleu(T0 + 111, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, ME, "Devinp", F_ME, 0)
    eq(fm.seats[ME].kills, 0, "F: a Life Tap death is not a kill for the victim")
    eq(fm.deaths[1].killer, nil, "F: self-inflicted death has no killer")
    eq(fm.deaths[1].name, "Life Tap", "F: ...but the blow is named")
    F.OnCleu(T0 + 120, "SPELL_DAMAGE", nil, "Creature-0-0-0-0-1-X", "Shadowfiend", 0x1148, 0, R2, "Shiv", F_PARTY, 0,
        1, "Bite", 32, 5000, 0, 32, 0, 0, 0, false, false, false, false)
    F.OnCleu(T0 + 121, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, R2, "Shiv", F_PARTY, 0)
    eq(fm.deaths[2].killer, nil, "F: an unseated (orphan-minion) hitter is no killer")
    eq(fm.deaths[2].name, "Bite", "F: ...the blow is still named")

    -- (4) END stays last even when the caller's clock trails the log
    F.OnCleu(T0 + 130.7, "SWING_DAMAGE", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    fm.tGates = fm.tGates or 5
    -- (5) Scoreboard rows for players the log never saw take seats
    local merged = F.MergeScoreboard(fm, {
        { name = "Devinp", kb = 0, deaths = 1, dmg = 900, heal = 0, faction = 1 },
        { name = "Ghost-Realm", kb = 0, deaths = 0, dmg = 15000, heal = 200, faction = 0, classToken = "HUNTER", race = "Orc" },
        { name = "Phantom", kb = 1, deaths = 0, dmg = 100, heal = 30000, faction = 1, classToken = "PALADIN" },
    }, 1)
    eq(merged, 3, "F: unseen scoreboard players merged as seats")
    local ghost = fm.seats["Score-Ghost"]
    CHECK(ghost and ghost.team == "them" and ghost.fromScoreboard and ghost.class == "HUNTER",
        "F: the unseen enemy is seated on THEM with class and a synthetic guid")
    CHECK(fm.seats["Score-Phantom"] and fm.seats["Score-Phantom"].team == "us", "F: the unseen friendly is seated on US")
    eq(fm.bracket, 3, "F: bracket grows with scoreboard seats (3 a side)")
    CHECK(fm.seats[ME].sb and fm.seats[ME].sb.dmg == 900, "F: our own row still merges onto the log seat")
    -- Without a faction the unseen rows are skipped, never guessed
    eq(F.MergeScoreboard(fm, { { name = "Nobody", faction = 0 } }), 0, "F: unseen rows need a faction to seat")
    local fin = F.Finish(T0 + 130, "WIN", nil)
    near(fin.tEnd, 130.7, "F: END is stamped no earlier than the last event")
    eq(fin.ledger[fin.ledgerN].kind, "END", "F: END is the last moment")
    CHECK(fin.ledger[fin.ledgerN].t >= fin.ledger[fin.ledgerN - 1].t, "F: ledger stays time-ordered through END")

    -- (6) The one-pass accumulator agrees with the per-seat scan for every
    -- ledger stat, at a cursor and for the whole match
    for _, key in ipairs({ "CC", "KICKS", "DISPEL", "KILLS", "MANA", "CDS" }) do
        local stat = F.StatByKey(key)
        for _, tcur in ipairs({ 45, 112, nil }) do
            local rows, n = F.CollectRows(fin, stat, tcur)
            for i = 1, n do
                local v, c = F.SeatValueAt(fin, rows[i].seat, stat, tcur)
                CHECK(math.abs(v - rows[i].value) < 1e-9 and (c == rows[i].count),
                    "F: one-pass " .. key .. " agrees with the per-seat scan at " .. tostring(tcur),
                    tostring(v) .. "/" .. tostring(rows[i].value))
            end
        end
    end
    -- Scoreboard-only seats read zero from the log for every stat
    local rows, n = F.CollectRows(fin, F.StatByKey("DMG"), nil)
    local ghostRow
    for i = 1, n do if rows[i].seat == ghost then ghostRow = rows[i] end end
    CHECK(ghostRow and ghostRow.value == 0, "F: a scoreboard-only seat has no log damage")
    eq(n, 6, "F: six seats in the rows after the merge")

    -- The ledger stays bisection-safe even if a fixture misorders events:
    -- a moment behind the newest one is clamped up to it
    local G = LoadArena()
    G.SetDRTable({ [1833] = "STUN" }, {})
    local gm = G.Begin(T0, "Order")
    G.SetSeat("us", ME, "Devinp", "MAGE")
    G.SetSeat("them", W1, "Gorehowl", "WARRIOR")
    G.OnCleu(T0 + 50, "SPELL_INTERRUPT", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 2139, "Counterspell", 1, 1, "Heal", 2)
    G.OnCleu(T0 + 40, "SPELL_INTERRUPT", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 2139, "Counterspell", 1, 1, "Heal", 2)
    near(gm.ledger[2].t, 50, "F: a late-arriving moment is clamped to the newest time")
    eq(G.LedgerIndexAt(gm, 45), 1, "F: bisection still finds the right slot")
end

-- ===========================================================================
-- Stage G: the replay records — power, casts + GCD, aura intervals
-- ===========================================================================

do
    local G = LoadArena()
    G.SetDRTable({ [1833] = "STUN" }, {})
    local gm = G.Begin(T0, "Replay")
    G.SetGates(T0 + 5)
    G.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
    G.SetSeat("them", W1, "Gorehowl", "WARRIOR", nil, "arena1")
    G.SetOwner(FELHUNTER, W1, "Felhunter")
    -- Power snapshots read back as fractions with their type
    G.SetPower(ME, 4200, 8400, 0, T0 + 10)
    G.SetPower(W1, 35, 100, 1, T0 + 10)
    local st = G.StateAt(gm, 12, {})
    near(st.seats[ME].pow, 0.5, "G: mana fraction at +12")
    eq(st.seats[ME].powType, 0, "G: mana type")
    near(st.seats[W1].pow, 0.35, "G: rage fraction")
    eq(st.seats[W1].powType, 1, "G: rage type")
    -- A hard cast: start, then success 2.5 s later
    G.OnCleu(T0 + 20, "SPELL_CAST_START", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16)
    st = G.StateAt(gm, 21, st)
    CHECK(st.seats[ME].cast and st.seats[ME].cast.name == "Frostbolt" and st.seats[ME].cast.r == nil, "G: a cast in progress at +21")
    G.OnCleu(T0 + 22.5, "SPELL_CAST_SUCCESS", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 27072, "Frostbolt", 16)
    eq(gm.seats[ME].castLog[1].r, "OK", "G: the success closes the cast as OK")
    near(gm.seats[ME].castLog[1].t2, 22.5, "G: cast end stamped")
    eq(gm.seats[ME].castLogN, 1, "G: one record for start+success")
    st = G.StateAt(gm, 23, st)
    eq(st.seats[ME].cast, nil, "G: no cast in progress after the success")
    near(st.seats[ME].gcd, 0.5 / 1.5, "G: GCD fraction 0.5 s after the success")
    CHECK(st.seats[ME].gcdCast and st.seats[ME].gcdCast.name == "Frostbolt", "G: the GCD names the cast it was spent on")
    st = G.StateAt(gm, 24.5, st)
    eq(st.seats[ME].gcd, nil, "G: GCD over after 1.5 s")
    eq(st.seats[ME].gcdCast, nil, "G: ...and names nothing")
    -- The success carried a target: who the mage is on, for 8 s
    eq(gm.seats[ME].castLog[1].tgt, W1, "G: a cast success records its target seat")
    st = G.StateAt(gm, 25, st)
    eq(st.seats[ME].target, W1, "G: the card knows who the mage is on")
    st = G.StateAt(gm, 31, st)
    eq(st.seats[ME].target, nil, "G: the target memory lapses after 8 s")
    -- An instant spends a GCD and records as an instant
    G.OnCleu(T0 + 30, "SPELL_CAST_SUCCESS", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 1953, "Blink", 1)
    CHECK(gm.seats[ME].castLog[2].instant == true and gm.seats[ME].castLog[2].r == "OK", "G: an instant records as such")
    st = G.StateAt(gm, 30.3, st)
    near(st.seats[ME].gcd, 0.2, "G: an instant starts a GCD")
    -- A kicked cast
    G.OnCleu(T0 + 40, "SPELL_CAST_START", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16)
    G.OnCleu(T0 + 41, "SPELL_INTERRUPT", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 6552, "Pummel", 1, 27072, "Frostbolt", 16)
    eq(gm.seats[ME].castLog[3].r, "KICKED", "G: a kick closes the cast as KICKED")
    near(gm.seats[ME].castLog[3].t2, 41, "G: ...at the kick")
    -- A failed cast (moved)
    G.OnCleu(T0 + 50, "SPELL_CAST_START", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16)
    G.OnCleu(T0 + 50.8, "SPELL_CAST_FAILED", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16, "Interrupted")
    eq(gm.seats[ME].castLog[4].r, "FAIL", "G: a failed cast closes as FAIL")
    -- A pet's cast start is not its owner's bar
    G.OnCleu(T0 + 55, "SPELL_CAST_START", nil, FELHUNTER, "Felhunter", F_EPET, 0, "", "", 0x80000000, 0, 19647, "Spell Lock", 32)
    eq(gm.seats[W1].openCast, nil, "G: a pet's cast start opens nothing on the owner")
    -- A start with no end is capped at 10 s
    G.OnCleu(T0 + 60, "SPELL_CAST_START", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16)
    G.OnCleu(T0 + 80, "SPELL_CAST_START", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16)
    near(gm.seats[ME].castLog[5].t2, 70, "G: an unended cast is closed at the cap when the next starts")
    eq(gm.seats[ME].castLog[5].r, "FAIL", "G: ...as a failure")
    -- Auras: buff and debuff intervals, refreshes extend, removal closes
    G.OnCleu(T0 + 100, "SPELL_AURA_APPLIED", nil, ME, "Devinp", F_ME, 0, ME, "Devinp", F_ME, 0, 27134, "Ice Barrier", 16, "BUFF")
    G.OnCleu(T0 + 101, "SPELL_AURA_APPLIED", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 1715, "Hamstring", 1, "DEBUFF")
    G.OnCleu(T0 + 102, "SPELL_AURA_REFRESH", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 1715, "Hamstring", 1, "DEBUFF")
    G.OnCleu(T0 + 103, "SPELL_AURA_APPLIED_DOSE", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 30070, "Deep Wound", 1, "DEBUFF", 2)
    eq(gm.seats[ME].aurasN, 3, "G: three aura intervals (refresh extends, a dose of a new aura opens one)")
    st = G.StateAt(gm, 104, st)
    eq(st.seats[ME].buffN, 1, "G: one buff on the mage at +104")
    eq(st.seats[ME].debuffN, 2, "G: two debuffs at +104")
    eq(st.seats[ME].buffs[1].name, "Ice Barrier", "G: the buff is the barrier")
    eq(st.seats[ME].debuffs[1].name, "Deep Wound", "G: newest debuff first")
    eq(st.seats[ME].debuffs[1].src, W1, "G: aura source recorded")
    G.OnCleu(T0 + 110, "SPELL_AURA_REMOVED", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 1715, "Hamstring", 1, "DEBUFF")
    st = G.StateAt(gm, 111, st)
    eq(st.seats[ME].debuffN, 1, "G: the removed debuff is gone at +111")
    st = G.StateAt(gm, 105, st)
    eq(st.seats[ME].debuffN, 2, "G: ...but still there when scrubbed back to +105")
    -- A CC aura is BOTH a control moment and a debuff interval
    G.OnCleu(T0 + 120, "SPELL_AURA_APPLIED", nil, W1, "Gorehowl", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 1833, "Cheap Shot", 1, "DEBUFF")
    st = G.StateAt(gm, 121, st)
    CHECK(st.seats[ME].ccN == 1 and st.seats[ME].debuffN == 2, "G: a stun is a control AND a debuff (Deep Wound + Cheap Shot)")
    -- Death closes auras and casts
    G.OnCleu(T0 + 125, "SPELL_CAST_START", nil, ME, "Devinp", F_ME, 0, "", "", 0x80000000, 0, 27072, "Frostbolt", 16)
    G.OnCleu(T0 + 126, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, ME, "Devinp", F_ME, 0)
    near(gm.seats[ME].auras[1].t2, 126, "G: death closes the open buff")
    eq(gm.seats[ME].openCast, nil, "G: death closes the open cast")
    -- Aura cap: overflow is counted, not silent
    for i = 1, 900 do
        G.OnCleu(T0 + 130 + i * 0.01, "SPELL_AURA_APPLIED", nil, W1, "Gorehowl", F_ENEMY, 0, W1, "Gorehowl", F_ENEMY, 0, 100 + i, "Aura" .. i, 1, "BUFF")
    end
    eq(gm.seats[W1].aurasN, 600, "G: aura intervals capped at 600 per seat")
    eq(gm.seats[W1].auraDropped, 300, "G: dropped intervals counted")
    -- Some damage on the warrior, so the cumulative cache below has data
    G.OnCleu(T0 + 150, "SWING_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 700, 0, 1, 0, 0, 0, false, false, false, false)
    G.OnCleu(T0 + 152.5, "SWING_DAMAGE", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 300, 0, 1, 0, 0, 0, false, false, false, false)
    -- Finish closes everything open; persistence keeps the replay records
    G.Finish(T0 + 200, "LOSS")
    local last = G.GetMatches()[1]
    CHECK(last.seats[W1].auras[1].t2 == 200, "G: an open aura closes at the end", last.seats[W1].auras[1].t2)
    -- Cumulative caches: a closed match answers "damage up to t" from a
    -- prefix array; it must agree with the direct sum and never persist
    local DMGs = G.StatByKey("DMG")
    local direct = 0
    for b = 1, 152 do direct = direct + (last.seats[W1].sTaken[b] or 0) end
    eq(direct, 700, "G: direct sum to +151 is the first swing only")
    eq((G.SeatValueAt(last, last.seats[W1], G.StatByKey("TAKEN"), 151.5)), 700, "G: cached cumulative equals the direct sum")
    eq((G.SeatValueAt(last, last.seats[W1], G.StatByKey("TAKEN"), 153)), 1000, "G: ...and includes the next bucket past it")
    CHECK(last.seats[W1]._cum ~= nil, "G: the cache was built on first use")
    eq((G.SeatValueAt(last, last.seats[W1], G.StatByKey("TAKEN"), 0.2)), (last.seats[W1].sTaken and last.seats[W1].sTaken[1]) or 0, "G: cumulative at the first bucket")
    local store = G.Export(5)
    CHECK(store.matches[1].seats[W1]._cum == nil, "G: the cache is stripped from the store")
    local G2 = LoadArena()
    eq(G2.Import(store), 1, "G: replay records import")
    eq(G2.GetMatches()[1].seats[ME].castLogN, 7, "G: cast log survives the round trip")
    eq(G2.GetMatches()[1].seats[ME].aurasN, 4, "G: aura log survives the round trip")
end

-- ===========================================================================
-- Stage H: the trinket press, from three sources that must agree
-- (Devin, in game: "the addon isn't actually properly tracking the cooldown")
-- ===========================================================================

do
    local H = LoadArena()
    local hm = H.Begin(T0, "Trinket")
    H.SetGates(T0 + 5)
    H.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
    H.SetSeat("them", W1, "Gorehowl", "WARRIOR", nil, "arena1")
    H.SetOwner(FELHUNTER, W1, "Felhunter")
    local function castS(ts, sg, sn, sf, id, name)
        H.OnCleu(ts, "SPELL_CAST_SUCCESS", nil, sg, sn, sf, 0, "", "", 0x80000000, 0, id, name, 1)
    end
    -- The medallion casts its OWN item spell: an id the engine has never
    -- seen, a name it knows
    eq(H.IsTrinketSpell(42292, "anything"), "TRINKET", "H: 42292 is the trinket by id")
    eq(H.IsTrinketSpell(99999, "Medallion of the Horde"), "TRINKET", "H: a medallion is the trinket by name")
    eq(H.IsTrinketSpell(99999, "Frostbolt"), nil, "H: an ordinary spell is not")
    castS(T0 + 20, W1, "Gorehowl", F_ENEMY, 99999, "Medallion of the Horde")
    eq(hm.seats[W1].trinkets, 1, "H: a press with an unknown id and a known name is recorded")
    eq(hm.ledger[hm.ledgerN].kind, "TRINKET", "H: ...as a TRINKET moment")
    eq(hm.ledger[hm.ledgerN].amount, 120, "H: ...with the two-minute default")
    -- The client reports the same press a moment later, with its own length
    H.OnTrinket(W1, T0 + 21, 118, 99999, "Medallion of the Horde")
    eq(hm.seats[W1].trinkets, 1, "H: the client's report of the same press is not a second press")
    eq(hm.ledger[hm.ledgerN].amount, 118, "H: ...and its cooldown length wins")
    -- The 1 Hz re-read of the client's answer changes nothing
    H.OnTrinket(W1, T0 + 21, 118, 99999, "Medallion of the Horde")
    H.OnTrinket(W1, T0 + 22, 118, 99999, nil)
    eq(hm.seats[W1].trinkets, 1, "H: repeated reads of one press stay one press")
    local st = H.StateAt(hm, 60, {})
    eq(st.seats[W1].cdN, 1, "H: the press is a running cooldown at +60")
    near(st.seats[W1].cdLeft[1], 20 + 118 - 60, "H: time left from the press and the client's length")
    st = H.StateAt(hm, 139, st)
    eq(st.seats[W1].cdN, 0, "H: it is back up after its length")
    -- A second press, two and a half minutes on, is a second press
    H.OnTrinket(W1, T0 + 170, 120, 99999, nil)
    eq(hm.seats[W1].trinkets, 2, "H: a later press is counted")
    -- The client names a press that started five seconds ago, after newer
    -- moments were already logged: the moment is clamped, the END is not
    H.OnCleu(T0 + 300, "SPELL_INTERRUPT", nil, ME, "Devinp", F_ME, 0, W1, "Gorehowl", F_ENEMY, 0, 2139, "Counterspell", 1, 1, "Heal", 2)
    local late = H.OnTrinket(ME, T0 + 295, 120, 42292, "PvP Trinket")
    CHECK(late ~= nil, "H: a press from our own side records")
    near(late.t, 300, "H: a late-reported moment is clamped to the ledger's newest time")
    near(late.t + late.amount, 295 + 120, "H: ...but its cooldown still ends when it really does")
    -- Re-reading that late press dedups against its REAL press time
    H.OnTrinket(ME, T0 + 295, 120, 42292, "PvP Trinket")
    eq(hm.seats[ME].trinkets, 1, "H: a clamped press still dedups on its real time")
    near(late.t + late.amount, 295 + 120, "H: ...and keeps its end")
    -- A pet's cast named like a trinket is not its owner's trinket
    castS(T0 + 320, FELHUNTER, "Felhunter", F_EPET, 99998, "PvP Trinket")
    eq(hm.seats[W1].trinkets, 2, "H: a pet's cast is never a trinket press")
    -- A report for someone not in the match is ignored
    eq(H.OnTrinket("Player-9-NOBODY", T0 + 330, 120, 42292, nil), nil, "H: a report for an unseated guid is ignored")
    -- The localized name fed at login matches too
    H.SetTrinketNames({ "JcJ-Schmuckstück" })
    eq(H.IsTrinketSpell(1, "JcJ-Schmuckstück"), "TRINKET", "H: the localized trinket name matches")
    -- Racial breaks keep their own cooldowns and tags
    castS(T0 + 340, W1, "Gorehowl", F_ENEMY, 20589, "Escape Artist")
    eq(hm.ledger[hm.ledgerN].x, "ESCAPE", "H: Escape Artist keeps its own tag")
    eq(hm.ledger[hm.ledgerN].amount, 60, "H: ...and its 60 s")
    H.OnTrinket(W1, T0 + 340, 120, 99999, nil)
    eq(hm.seats[W1].trinkets, 3, "H: counts: two medallion presses and the racial")
end

-- ===========================================================================
-- Stage I: Feign Death is not a death (Devin, in game: "feign death is
-- messing up the replay system — it seems to not recover")
-- ===========================================================================

do
    local HU = "Player-1-HUNTER"
    local function NewFeign()
        local I = LoadArena()
        local im = I.Begin(T0, "Feign")
        I.SetGates(T0 + 5)
        I.SetSeat("us", ME, "Devinp", "MAGE", nil, "player")
        I.SetSeat("them", HU, "Sting", "HUNTER", nil, "arena1")
        I.SetOwner("Pet-0-CAT", HU, "Cat")
        I.OnCleu(T0 + 10, "SPELL_DAMAGE", nil, ME, "Devinp", F_ME, 0, HU, "Sting", F_ENEMY, 0,
            27072, "Frostbolt", 16, 900, 0, 16, 0, 0, 0, false, false, false, false)
        return I, im
    end
    local function died(I, ts) I.OnCleu(ts, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, HU, "Sting", F_ENEMY, 0) end
    local function feignCast(I, ts) I.OnCleu(ts, "SPELL_CAST_SUCCESS", nil, HU, "Sting", F_ENEMY, 0, "", "", 0x80000000, 0, 5384, "Feign Death", 1) end
    local function feignAura(I, ts, sub) I.OnCleu(ts, sub, nil, HU, "Sting", F_ENEMY, 0, HU, "Sting", F_ENEMY, 0, 5384, "Feign Death", 1, "BUFF") end

    -- 1. The normal order: cast, aura, then the feign's own UNIT_DIED
    local I, im = NewFeign()
    feignCast(I, T0 + 12)
    feignAura(I, T0 + 12, "SPELL_AURA_APPLIED")
    died(I, T0 + 12.2)
    eq(im.seats[HU].deaths, 0, "I: a feign's UNIT_DIED is not a death")
    eq(#im.deaths, 0, "I: no death record")
    eq(im.firstBlood, nil, "I: no first blood from a feign")
    eq(im.seats[ME].kills, 0, "I: no kill credited for a feign")
    eq(im.ledger[im.ledgerN].kind, "FEIGN", "I: a FEIGN moment marks it")
    local st = I.StateAt(im, 13, {})
    eq(st.seats[HU].alive, true, "I: the hunter is alive while feigning")
    eq(st.seats[HU].feign, true, "I: ...and flagged as feigning")
    eq(st.seats[HU].buffN, 1, "I: his auras were not closed by the feign")
    -- The hunter cancels: the aura fades, he is simply alive
    feignAura(I, T0 + 16, "SPELL_AURA_REMOVED")
    st = I.StateAt(im, 17, st)
    CHECK(st.seats[HU].alive == true and st.seats[HU].feign == false, "I: after the cancel he is alive and no longer feigning")
    -- A REAL death later (the feign long over) is a death
    I.OnCleu(T0 + 30, "SPELL_DAMAGE", nil, ME, "Devinp", F_ME, 0, HU, "Sting", F_ENEMY, 0,
        27072, "Frostbolt", 16, 5000, 0, 16, 0, 0, 0, true, false, false, false)
    died(I, T0 + 31)
    eq(im.seats[HU].deaths, 1, "I: a real death long after a feign counts")
    eq(im.seats[ME].kills, 1, "I: ...with its kill")
    st = I.StateAt(im, 32, st)
    eq(st.seats[HU].alive, false, "I: dead after the real death")
    -- A second UNIT_DIED for an already-dead seat changes nothing
    died(I, T0 + 33)
    eq(im.seats[HU].deaths, 1, "I: one death per seat")

    -- 2. Out of order: UNIT_DIED first, the feign's aura a moment later
    I, im = NewFeign()
    died(I, T0 + 12)
    eq(im.seats[HU].deaths, 1, "I: (out of order) the death is recorded first")
    eq(im.seats[ME].kills, 1, "I: ...with a kill")
    feignAura(I, T0 + 12.3, "SPELL_AURA_APPLIED")
    eq(im.seats[HU].deaths, 0, "I: the feign arriving a moment later undoes the death")
    eq(im.seats[ME].kills, 0, "I: ...and the kill credit")
    eq(#im.deaths, 0, "I: ...and the death record")
    eq(im.firstBlood, nil, "I: ...and first blood")
    local feignMoment
    for i = 1, im.ledgerN do if im.ledger[i].kind == "FEIGN" then feignMoment = im.ledger[i] end end
    CHECK(feignMoment ~= nil and feignMoment.src == HU, "I: the DEATH moment became a FEIGN moment")
    for i = 1, im.ledgerN do CHECK(im.ledger[i].kind ~= "DEATH", "I: no DEATH moment remains (" .. i .. ")") end
    eq(I.StateAt(im, 20, {}).seats[HU].alive, true, "I: alive in the replay")

    -- 3. A feign the log never announced: the "dead" hunter casts again
    I, im = NewFeign()
    died(I, T0 + 12)
    eq(I.StateAt(im, 14, {}).seats[HU].alive, false, "I: (unannounced) dead until proven otherwise")
    I.OnCleu(T0 + 18, "SPELL_CAST_SUCCESS", nil, HU, "Sting", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 27019, "Arcane Shot", 64)
    eq(im.seats[HU].deaths, 0, "I: the dead do not cast — the death is undone")
    eq(im.seats[ME].kills, 0, "I: ...with its kill")
    eq(I.StateAt(im, 14, {}).seats[HU].alive, true, "I: the replay no longer shows him dead at +14")

    -- 3b. The buffs the false death closed come back with him
    I, im = NewFeign()
    I.OnCleu(T0 + 8, "SPELL_AURA_APPLIED", nil, HU, "Sting", F_ENEMY, 0, HU, "Sting", F_ENEMY, 0, 27044, "Aspect of the Hawk", 1, "BUFF")
    died(I, T0 + 12)
    eq(I.StateAt(im, 14, {}).seats[HU].buffN, 0, "I: a death closes the seat's auras")
    I.SetHealth(HU, 4000, 8000, T0 + 15)
    eq(I.StateAt(im, 14, {}).seats[HU].buffN, 1, "I: undoing the death hands the auras back")
    eq(I.StateAt(im, 40, {}).seats[HU].buffN, 1, "I: ...still open, not ended at the false death")
    I.OnCleu(T0 + 45, "SPELL_AURA_REMOVED", nil, HU, "Sting", F_ENEMY, 0, HU, "Sting", F_ENEMY, 0, 27044, "Aspect of the Hawk", 1, "BUFF")
    eq(I.StateAt(im, 46, {}).seats[HU].buffN, 0, "I: ...and a later fade closes it as usual")
    do
        local blob = I.Serialize and I.Export and I.Export(6)
        CHECK(blob ~= nil, "I: a match with an undone death still exports")
    end

    -- 4. ...or starts a cast
    I, im = NewFeign()
    died(I, T0 + 12)
    I.OnCleu(T0 + 15, "SPELL_CAST_START", nil, HU, "Sting", F_ENEMY, 0, "", "", 0x80000000, 0, 27016, "Steady Shot", 1)
    eq(im.seats[HU].deaths, 0, "I: a cast start revives too")

    -- 5. ...or swings
    I, im = NewFeign()
    died(I, T0 + 12)
    I.OnCleu(T0 + 15, "SWING_DAMAGE", nil, HU, "Sting", F_ENEMY, 0, ME, "Devinp", F_ME, 0, 300, 0, 1, 0, 0, 0, false, false, false, false)
    eq(im.seats[HU].deaths, 0, "I: a melee swing revives")

    -- 6. ...or reads alive on the unit frame a moment later
    I, im = NewFeign()
    died(I, T0 + 12)
    I.SetHealth(HU, 4000, 8000, T0 + 12.5)
    eq(im.seats[HU].deaths, 1, "I: a reading half a second after the death proves nothing")
    I.SetHealth(HU, 4000, 8000, T0 + 14)
    eq(im.seats[HU].deaths, 0, "I: a living reading two seconds later undoes the death")
    I.SetHealth(HU, 0, 8000, T0 + 20)
    eq(im.seats[HU].deaths, 0, "I: a zero reading revives nobody and kills nobody")

    -- 7. What does NOT revive: a dot ticking, a bolt landing, the pet acting
    I, im = NewFeign()
    died(I, T0 + 12)
    I.OnCleu(T0 + 13, "SPELL_PERIODIC_DAMAGE", nil, HU, "Sting", F_ENEMY, 0, ME, "Devinp", F_ME, 0,
        27016, "Serpent Sting", 8, 200, 0, 8, 0, 0, 0, false, false, false, false)
    I.OnCleu(T0 + 13, "SPELL_DAMAGE", nil, HU, "Sting", F_ENEMY, 0, ME, "Devinp", F_ME, 0,
        27019, "Arcane Shot", 64, 600, 0, 64, 0, 0, 0, false, false, false, false)
    I.OnCleu(T0 + 14, "SWING_DAMAGE", nil, "Pet-0-CAT", "Cat", F_EPET, 0, ME, "Devinp", F_ME, 0, 150, 0, 1, 0, 0, 0, false, false, false, false)
    I.OnCleu(T0 + 14, "SPELL_CAST_SUCCESS", nil, "Pet-0-CAT", "Cat", F_EPET, 0, ME, "Devinp", F_ME, 0, 27050, "Bite", 1)
    eq(im.seats[HU].deaths, 1, "I: dots, bolts in flight and the pet do not revive their owner")

    -- 8. Two seats: undoing the hunter's false death keeps the real first blood
    I, im = NewFeign()
    I.SetSeat("them", W1, "Gorehowl", "WARRIOR", nil, "arena2")
    died(I, T0 + 12)
    I.OnCleu(T0 + 20, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, W1, "Gorehowl", F_ENEMY, 0)
    eq(im.firstBlood.guid, HU, "I: first blood is the (false) hunter death for now")
    feignCast(I, T0 + 25) -- too late to be this death's feign: he ACTED, so it revives him
    eq(im.firstBlood.guid, W1, "I: first blood passes to the real death")
    eq(#im.deaths, 1, "I: one real death remains")

    -- 9. The localized feign name matches
    local J = LoadArena()
    J.SetFeignNames({ "Totstellen" })
    local jm = J.Begin(T0, "DE")
    J.SetGates(T0 + 1)
    J.SetSeat("them", HU, "Sting", "HUNTER")
    J.OnCleu(T0 + 5, "SPELL_AURA_APPLIED", nil, HU, "Sting", F_ENEMY, 0, HU, "Sting", F_ENEMY, 0, 14325, "Totstellen", 1, "BUFF")
    J.OnCleu(T0 + 5.1, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, HU, "Sting", F_ENEMY, 0)
    eq(jm.seats[HU].deaths, 0, "I: a localized feign name is recognised")
end

-- ===========================================================================
-- Stage J: dispels — offensive / defensive by the aura's type, the dispel
-- log cast by cast, and Mass Dispel's shattered shields (Devin: "not
-- tracking everything I offensively and defensively dispel when I'm using
-- my MD in arena")
-- ===========================================================================

do
    local PA = "Player-1-PALADIN"
    local MG = "Player-1-MAGE"
    local FEL = "Pet-1-FEL"
    local function NewDispels()
        local J = LoadArena()
        local jm = J.Begin(T0, "Blade's Edge Arena")
        J.SetGates(T0 + 5)
        J.SetSeat("us", P3, "Vespers", "PRIEST", nil, "player")
        J.SetSeat("us", ME, "Devinp", "MAGE", nil, "party1")
        J.SetSeat("them", PA, "Lightbane", "PALADIN", nil, "arena1")
        J.SetSeat("them", MG, "Frostbyte", "MAGE", nil, "arena2")
        J.SetSeat("them", L3, "Nethra", "WARLOCK", nil, "arena3")
        J.SetOwner(FEL, L3, "Felhunter")
        return J, jm
    end
    local function ev(J, ts, sub, sg, sn, sf, dg, dn, df, ...)
        J.OnCleu(ts, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, ...)
    end
    local function mdCast(J, ts, sg, sn, sf)
        ev(J, ts, "SPELL_CAST_SUCCESS", sg or P3, sn or "Vespers", sf or F_ME, "", "", 0x80000000, 32375, "Mass Dispel", 1)
    end
    local function mdHit(J, ts, id, dg, dn, df, exId, exName, auraType)
        ev(J, ts, "SPELL_DISPEL", P3, "Vespers", F_ME, dg, dn, df, id, "Mass Dispel", 1, exId, exName, 8, auraType)
    end
    local function shield(J, ts, sub, dg, dn, id, name)
        ev(J, ts, sub, dg, dn, F_ENEMY, dg, dn, F_ENEMY, id, name, 2, "BUFF")
    end

    -- 1. The aura's type decides the side — a pet's buff included
    local J, jm = NewDispels()
    ev(J, T0 + 10, "SPELL_DISPEL", P3, "Vespers", F_ME, FEL, "Felhunter", F_EPET, 527, "Dispel Magic", 2, 27268, "Fel Intelligence", 32, "BUFF")
    eq(jm.seats[P3].purges, 1, "J: a buff off an enemy PET is an offensive dispel (it was a defensive one)")
    eq(jm.seats[P3].dispels, 0, "J: ...and not a defensive one")
    eq(jm.seats[L3].purgesTaken, 1, "J: the pet's loss is its owner's")
    local c = jm.dlog[1]
    CHECK(c and c.hits[1].dst == L3 and c.hits[1].pet == "Felhunter", "J: the log names the pet and its owner")
    eq(jm.ledger[jm.ledgerN].dst, L3, "J: the moment points at the owner's seat")
    eq(jm.ledger[jm.ledgerN].pet, "Felhunter", "J: ...with the pet's name")
    -- A debuff off a friend is defensive whatever the flags say
    ev(J, T0 + 12, "SPELL_DISPEL", P3, "Vespers", F_ME, ME, "Devinp", F_PARTY, 988, "Dispel Magic", 2, 12826, "Polymorph", 64, "DEBUFF")
    eq(jm.seats[P3].dispels, 1, "J: a debuff off a teammate is a defensive dispel")
    eq(jm.seats[ME].dispelsTaken, 1, "J: the teammate was freed")
    -- No aura type in the log: the teams decide
    ev(J, T0 + 14, "SPELL_DISPEL", P3, "Vespers", F_ME, MG, "Frostbyte", F_ENEMY, 527, "Dispel Magic", 2, 27125, "Mage Armor", 64)
    eq(jm.seats[P3].purges, 2, "J: without an aura type, an enemy target is offensive")
    -- Two removals of one Dispel Magic in one instant are one cast; the
    -- next press 1.5 s later is another
    ev(J, T0 + 20, "SPELL_DISPEL", P3, "Vespers", F_ME, PA, "Lightbane", F_ENEMY, 988, "Dispel Magic", 2, 27149, "Blessing of Might", 2, "BUFF")
    ev(J, T0 + 20, "SPELL_DISPEL", P3, "Vespers", F_ME, PA, "Lightbane", F_ENEMY, 988, "Dispel Magic", 2, 25898, "Greater Blessing of Kings", 2, "BUFF")
    ev(J, T0 + 21.5, "SPELL_DISPEL", P3, "Vespers", F_ME, PA, "Lightbane", F_ENEMY, 988, "Dispel Magic", 2, 27154, "Blessing of Wisdom", 2, "BUFF")
    local n = jm.dlogN
    eq(#jm.dlog[n - 1].hits, 2, "J: a rank-2 Dispel Magic's two removals are one cast")
    eq(#jm.dlog[n].hits, 1, "J: the next press is its own cast")
    eq(jm.dlog[n - 1].name, "Dispel Magic", "J: the cast keeps the spell's name")
    eq(jm.dlog[n - 1].id, 988, "J: ...and its id")

    -- 2. Mass Dispel: one press, both halves under it, in log order
    J, jm = NewDispels()
    mdCast(J, T0 + 30)
    eq(jm.dlogN, 1, "J: the Mass Dispel press opens its log record")
    mdHit(J, T0 + 30, 32375, ME, "Devinp", F_PARTY, 10890, "Psychic Scream", "DEBUFF")
    mdHit(J, T0 + 30, 32592, PA, "Lightbane", F_ENEMY, 27149, "Blessing of Might", "BUFF")
    mdHit(J, T0 + 30, 32592, L3, "Nethra", F_ENEMY, 28176, "Fel Armor", "BUFF")
    eq(jm.dlogN, 1, "J: both halves (32375 friendly, 32592 enemy) join the one cast")
    local md = jm.dlog[1]
    eq(#md.hits, 3, "J: three removals under the Mass Dispel")
    CHECK(md.hits[1].off == false and md.hits[2].off == true and md.hits[3].off == true,
        "J: the friendly half is defensive, the enemy half offensive")
    eq(md.hits[2].name, "Blessing of Might", "J: removals keep the log's order")
    eq(jm.seats[P3].purges, 2, "J: two offensive removals")
    eq(jm.seats[P3].dispels, 1, "J: one defensive removal")
    local e = jm.ledger[jm.ledgerN]
    eq(e.by, "Mass Dispel", "J: each DISPEL moment names the cast")
    -- A Mass Dispel into nothing still reads as a press
    mdCast(J, T0 + 40)
    eq(jm.dlogN, 2, "J: a Mass Dispel that took nothing is still a log record")
    eq(#jm.dlog[2].hits, 0, "J: ...with no removals")

    -- 3. The shatter: Divine Shield fades as an enemy Mass Dispel lands —
    -- the log names no dispel for it
    J, jm = NewDispels()
    shield(J, T0 + 50, "SPELL_AURA_APPLIED", PA, "Lightbane", 1020, "Divine Shield")
    mdCast(J, T0 + 53)
    mdHit(J, T0 + 53, 32592, L3, "Nethra", F_ENEMY, 28176, "Fel Armor", "BUFF")
    shield(J, T0 + 53, "SPELL_AURA_REMOVED", PA, "Lightbane", 1020, "Divine Shield")
    eq(jm.seats[P3].shatters, 1, "J: the bubble Mass Dispel broke is credited")
    eq(jm.seats[P3].purges, 2, "J: ...as an offensive removal (Fel Armor + the bubble)")
    eq(jm.seats[PA].purgesTaken, 1, "J: the paladin lost it")
    md = jm.dlog[1]
    eq(#md.hits, 2, "J: the shatter sits under the same Mass Dispel")
    CHECK(md.hits[2].inf == true and md.hits[2].name == "Divine Shield", "J: flagged inferred, named")
    e = jm.ledger[jm.ledgerN]
    CHECK(e.kind == "DISPEL" and e.inf == true and e.x == "PURGE" and e.dst == PA, "J: a PURGE moment flagged inferred")
    -- The reverse log order: the fade printed before the cast line
    J, jm = NewDispels()
    shield(J, T0 + 60, "SPELL_AURA_APPLIED", MG, "Frostbyte", 45438, "Ice Block")
    shield(J, T0 + 63, "SPELL_AURA_REMOVED", MG, "Frostbyte", 45438, "Ice Block")
    eq(jm.seats[P3].shatters, 0, "J: a fade alone is no shatter (yet)")
    mdCast(J, T0 + 63.1)
    eq(jm.seats[P3].shatters, 1, "J: the Mass Dispel logged just after claims the Ice Block that fell")
    CHECK(jm.dlog[1].hits[1] and jm.dlog[1].hits[1].name == "Ice Block", "J: under that cast")
    -- The log names it after all (if the server does print the mechanic
    -- removal): upgraded, never counted twice
    J, jm = NewDispels()
    shield(J, T0 + 70, "SPELL_AURA_APPLIED", PA, "Lightbane", 1020, "Divine Shield")
    mdCast(J, T0 + 72)
    shield(J, T0 + 72, "SPELL_AURA_REMOVED", PA, "Lightbane", 1020, "Divine Shield")
    mdHit(J, T0 + 72, 39897, PA, "Lightbane", F_ENEMY, 1020, "Divine Shield", "BUFF")
    eq(jm.seats[P3].purges, 1, "J: a shatter the log names later is counted once")
    CHECK(jm.dlog[1].hits[1].inf == nil, "J: ...and is no longer marked inferred")
    eq(#jm.dlog[1].hits, 1, "J: one removal, not two")
    -- Named first: the fade that follows is not inferred again
    J, jm = NewDispels()
    shield(J, T0 + 80, "SPELL_AURA_APPLIED", PA, "Lightbane", 10278, "Blessing of Protection")
    mdCast(J, T0 + 82)
    mdHit(J, T0 + 82, 32592, PA, "Lightbane", F_ENEMY, 10278, "Blessing of Protection", "BUFF")
    shield(J, T0 + 82, "SPELL_AURA_REMOVED", PA, "Lightbane", 10278, "Blessing of Protection")
    eq(jm.seats[P3].purges, 1, "J: a BoP the enemy half dispelled is one removal")
    eq(jm.seats[P3].shatters, 0, "J: ...not also a shatter")
    -- What must NOT shatter
    J, jm = NewDispels()
    shield(J, T0 + 90, "SPELL_AURA_APPLIED", PA, "Lightbane", 1020, "Divine Shield")
    mdCast(J, T0 + 102)
    shield(J, T0 + 102, "SPELL_AURA_REMOVED", PA, "Lightbane", 1020, "Divine Shield")
    eq(jm.seats[P3].shatters, 0, "J: a bubble that ran its full 12 s expired")
    shield(J, T0 + 110, "SPELL_AURA_APPLIED", MG, "Frostbyte", 45438, "Ice Block")
    shield(J, T0 + 112, "SPELL_AURA_REMOVED", MG, "Frostbyte", 45438, "Ice Block")
    mdCast(J, T0 + 113)
    eq(jm.seats[P3].shatters, 0, "J: an Ice Block cancelled during the 1.5 s cast was not broken by it")
    ev(J, T0 + 120, "SPELL_AURA_APPLIED", ME, "Devinp", F_PARTY, ME, "Devinp", F_PARTY, 45438, "Ice Block", 16, "BUFF")
    mdCast(J, T0 + 122)
    ev(J, T0 + 122, "SPELL_AURA_REMOVED", ME, "Devinp", F_PARTY, ME, "Devinp", F_PARTY, 45438, "Ice Block", 16, "BUFF")
    eq(jm.seats[P3].shatters, 0, "J: our own Mass Dispel never breaks our own team's Ice Block")
    -- The enemy priest's Mass Dispel breaks OUR shield: credited to them
    local EP = "Player-1-PRIEST"
    J.SetSeat("them", EP, "Hexa", "PRIEST", nil, "arena4")
    ev(J, T0 + 130, "SPELL_AURA_APPLIED", ME, "Devinp", F_PARTY, ME, "Devinp", F_PARTY, 45438, "Ice Block", 16, "BUFF")
    mdCast(J, T0 + 132, EP, "Hexa", F_ENEMY)
    ev(J, T0 + 132, "SPELL_AURA_REMOVED", ME, "Devinp", F_PARTY, ME, "Devinp", F_PARTY, 45438, "Ice Block", 16, "BUFF")
    eq(jm.seats[EP].shatters, 1, "J: an enemy Mass Dispel on our Ice Block is theirs")
    eq(jm.seats[ME].purgesTaken, 1, "J: our mage lost it")

    -- 4. Attempts that took nothing: resisted, immune
    J, jm = NewDispels()
    ev(J, T0 + 140, "SPELL_DISPEL_FAILED", P3, "Vespers", F_ME, L3, "Nethra", F_ENEMY, 527, "Dispel Magic", 2, 28176, "Fel Armor", 32)
    eq(jm.seats[P3].dispelFails, 1, "J: a failed dispel is counted")
    eq(jm.seats[P3].purges, 0, "J: ...never as a removal")
    CHECK(jm.dlog[1].hits[1].r == "FAIL" and jm.dlog[1].hits[1].name == "Fel Armor", "J: the log names what resisted")
    ev(J, T0 + 145, "SPELL_MISSED", P3, "Vespers", F_ME, MG, "Frostbyte", F_ENEMY, 32592, "Mass Dispel", 1, "IMMUNE", false, 0, false)
    eq(jm.seats[P3].dispelFails, 2, "J: a Mass Dispel into immunity took nothing")
    CHECK(jm.dlog[2].hits[1].r == "IMMUNE" and jm.dlog[2].hits[1].dst == MG, "J: the miss names its type and target")
    ev(J, T0 + 150, "SPELL_MISSED", FEL, "Felhunter", F_EPET, P3, "Vespers", F_ME, 27277, "Devour Magic", 32, "RESIST", false, 0, false)
    eq(jm.seats[L3].dispelFails, 1, "J: the felhunter's resisted Devour Magic is its warlock's")
    eq(jm.dlog[3].pet, "Felhunter", "J: the cast record names the pet that pressed it")
    ev(J, T0 + 155, "SPELL_MISSED", P3, "Vespers", F_ME, MG, "Frostbyte", F_ENEMY, 25235, "Flash Heal", 2, "RESIST", false, 0, false)
    eq(jm.dlogN, 3, "J: a non-dispel miss is not a log line")

    -- 5. Reading it back: the stat's split, tallies and the index as of a cursor
    J, jm = NewDispels()
    ev(J, T0 + 10, "SPELL_DISPEL", P3, "Vespers", F_ME, ME, "Devinp", F_PARTY, 988, "Dispel Magic", 2, 12826, "Polymorph", 64, "DEBUFF")
    ev(J, T0 + 20, "SPELL_DISPEL", P3, "Vespers", F_ME, PA, "Lightbane", F_ENEMY, 988, "Dispel Magic", 2, 27149, "Blessing of Might", 2, "BUFF")
    ev(J, T0 + 30, "SPELL_STOLEN", ME, "Devinp", F_PARTY, PA, "Lightbane", F_ENEMY, 30449, "Spellsteal", 64, 27149, "Blessing of Freedom", 2, "BUFF")
    local stat = J.StatByKey("DISPEL")
    local v, cnt = J.SeatValueAt(jm, jm.seats[P3], stat, nil)
    eq(v, 2, "J: the DISPEL stat counts every removal")
    eq(cnt, 1, "J: its count is the offensive share")
    v, cnt = J.SeatValueAt(jm, jm.seats[P3], stat, 15)
    CHECK(v == 1 and cnt == 0, "J: as of 0:10 after the gates: one defensive, no offensive", tostring(v) .. "/" .. tostring(cnt))
    local rowsData, rn = J.CollectRows(jm, stat, 25)
    local pr
    for i = 1, rn do if rowsData[i].seat.guid == P3 then pr = rowsData[i] end end
    CHECK(pr and pr.value == 2 and pr.count == 1, "J: a pane at a cursor gets the split too")
    local tally = J.DispelTallyAt(jm, 25, {})
    CHECK(tally[P3].off == 1 and tally[P3].def == 1 and tally[ME].cleansed == 1 and tally[PA].lost == 1,
        "J: tallies as of a cursor: who did what, who lost and who was freed")
    eq(J.DispelTallyAt(jm, nil, tally)[ME].off, 1, "J: the whole match counts the steal")
    eq(jm.dlog[3].hits[1].steal, true, "J: a steal is marked")
    eq(J.DispelIndexAt(jm, 25), 2, "J: the last cast at or before a cursor")
    eq(J.DispelIndexAt(jm, 5), 0, "J: none before the first")

    -- 6. A match saved before the log existed rebuilds it from its moments
    jm.dlog, jm.dlogN = nil, nil
    local log, ln = J.DispelLog(jm)
    eq(ln, 3, "J: a pre-log match rebuilds one cast per DISPEL moment group")
    CHECK(log[2].hits[1].off == true and log[1].hits[1].off == false, "J: rebuilt hits keep their side")
    eq(log[1].name, "Dispel Magic", "J: rebuilt casts keep the name the moments carried")
    J.Finish(T0 + 200, "WIN")
    local st = J.Export(5)
    eq(st.matches[1]._dlog, nil, "J: the rebuilt log is session-only (stripped on export)")

    -- 7. Persistence: the log rides the store byte-identically
    J, jm = NewDispels()
    mdCast(J, T0 + 30)
    mdHit(J, T0 + 30, 32592, PA, "Lightbane", F_ENEMY, 27149, "Blessing of Might", "BUFF")
    J.Finish(T0 + 60, "WIN")
    local snap = J.Serialize(J.GetMatch("last"))
    local K = LoadArena()
    eq(K.Import(J.Export(5)), 1, "J: a match with a dispel log imports")
    eq(K.Serialize(K.GetMatch("last")), snap, "J: ...byte-identical")
    eq(K.GetMatch("last").dlog[1].hits[1].name, "Blessing of Might", "J: the log survives the store")
end

-- ===========================================================================
-- Stage K: the scoreboard (D31) — one seat's whole-match line, the board
-- merged again onto a CLOSED match, and an MMR change read from the
-- player's next game (the client never reports one)
-- ===========================================================================

do
    local K = LoadArena()
    local SH, GH, LS, NE = "Player-0-SHIV", "Player-1-GORE", "Player-1-LEAF", "Player-1-NETH"
    -- One game: our character + Shiv against two, a blow so it is played,
    -- the board merged, closed. `me` renames our character (an alt).
    local function Game(ts, opts)
        local m = K.Begin(ts, opts.map or "Nagrand Arena")
        local meName = opts.me or "Devinp"
        K.SetSeat("us", ME, meName, "MAGE", "Human", "player")
        K.SetSeat("us", SH, opts.shivName or "Shiv", opts.shivClass or "ROGUE", "NightElf", "party1")
        for _, e in ipairs(opts.them or { { GH, "Gorehowl", "WARRIOR" }, { LS, "Leafshade", "DRUID" } }) do
            K.SetSeat("them", e[1], e[2], e[3])
        end
        if opts.bracket == 3 then K.SetSeat("them", "Player-1-X3", "Third", "PALADIN") end
        K.OnCleu(ts + 5, "SWING_DAMAGE", nil, ME, meName, F_ME, 0, GH, "Gorehowl", F_ENEMY, 0,
            100, 0, 1, 0, 0, 0, false, false, false, false)
        m.rated = opts.rated
        if opts.rows then K.MergeScoreboard(m, opts.rows, 1) end
        K.Finish(ts + (opts.dur or 120), opts.result or "WIN")
        return m
    end
    local function Row(name, mmr, rc, extra)
        local r = { name = name, kb = 1, hk = 0, deaths = 0, dmg = 10000, heal = 2000, ratingChange = rc, mmr = mmr, faction = 1 }
        for k, v in pairs(extra or {}) do r[k] = v end
        return r
    end
    local MIN = 60

    -- 1. ScoreLine: server numbers, the log's deaths, ratings only when rated
    local g1 = Game(T0, { rated = true, rows = {
        Row("Devinp", 1800, 12, { kb = 2, dmg = 31200, heal = 150, deaths = 0 }),
        Row("Shiv", 1750, 10), Row("Gorehowl", 1820, -11), Row("Leafshade", 1790, -9) } })
    g1.seats[GH].deaths = 1  -- the log saw him die; the board says 0 for everyone
    local dmg, heal, kb, deaths, mmr, rc, server = K.ScoreLine(g1, g1.seats[ME])
    CHECK(dmg == 31200 and heal == 150 and kb == 2 and server == true, "K: a scored seat reads the server's damage, healing and killing blows")
    CHECK(mmr == 1800 and rc == 12, "K: ...and its MMR and rating change")
    local _, _, _, gd = K.ScoreLine(g1, g1.seats[GH])
    eq(gd, 1, "K: deaths come from the log — the arena board answers 0 for everyone")
    local unscored = g1.seats[ME].sb
    g1.seats[ME].sb = nil
    local ld, lh, lk, _, lm, lr, ls = K.ScoreLine(g1, g1.seats[ME])
    CHECK(ld == g1.seats[ME].dmg and lh == g1.seats[ME].heal + g1.seats[ME].absorb and lk == g1.seats[ME].kills,
        "K: no board row: the log's damage, healing and kills stand in")
    CHECK(lm == nil and lr == nil and ls == false, "K: ...with no ratings, marked not the server's")
    g1.seats[ME].sb = unscored
    -- A rated game can move someone by exactly 0
    g1.seats[SH].sb.ratingChange = 0
    local _, _, _, _, zm, zr = K.ScoreLine(g1, g1.seats[SH])
    CHECK(zm == 1750 and zr == 0, "K: a rated +0 is a change of zero, not no change")
    g1.seats[SH].sb.ratingChange = 10

    -- 2. The next game teaches the change: you, a teammate, an opponent met again
    local g2 = Game(T0 + 120 + 5 * MIN, { rated = true, rows = {
        Row("Devinp", 1824, 9), Row("Shiv", 1771, 8), Row("Gorehowl", 1801, -10) },
        them = { { GH, "Gorehowl", "WARRIOR" }, { NE, "Nethra", "WARLOCK" } } })
    local after, nm, gap, sure = K.NextMmr(g1, g1.seats[ME])
    CHECK(after == 1824 and nm == g2 and gap == 5 * MIN and sure == true, "K: your MMR after a game is your pre-match MMR in the next", tostring(after) .. " " .. tostring(gap))
    after, nm, gap, sure = K.NextMmr(g1, g1.seats[SH])
    CHECK(after == 1771 and sure == true, "K: a teammate queued with you again: theirs too, surely")
    after, nm, gap, sure = K.NextMmr(g1, g1.seats[GH])
    CHECK(after == 1801 and sure == false, "K: an opponent met again: reported, not sure")
    local none, why = K.NextMmr(g1, g1.seats[LS])
    CHECK(none == nil and why == "UNKNOWN", "K: a player not in your next game: unknown", why)
    none, why = K.NextMmr(g2, g2.seats[ME])
    CHECK(none == nil and why == "PENDING", "K: the newest game: its change is still to come", why)

    -- 3. A skirmish in between is skipped; another bracket and an alt never count
    local g3 = Game(T0 + 900, { rated = false, rows = { Row("Devinp", 0, 0), Row("Shiv", 0, 0) } })
    local sm, sr = select(5, K.ScoreLine(g3, g3.seats[ME]))
    CHECK(sm == nil and sr == nil, "K: a skirmish's MMR 0 and change 0 read as none")
    eq(K.NextMmr(g3, g3.seats[ME]), nil, "K: a skirmish has no MMR to move")
    Game(T0 + 1200, { rated = true, bracket = 3, rows = { Row("Devinp", 1650, 14), Row("Shiv", 1600, 14) } })
    Game(T0 + 1500, { rated = true, me = "Altchar", rows = { Row("Altchar", 1500, 10), Row("Shiv", 1400, 10) } })
    none, why = K.NextMmr(g2, g2.seats[ME])
    CHECK(none == nil and why == "PENDING", "K: a skirmish, a 3v3 and an alt's game are not your next 2v2", why)
    local g4 = Game(T0 + 1800, { rated = true, rows = { Row("Devinp", 1810, -12), Row("Shiv", 1760, -11) } })
    after = K.NextMmr(g2, g2.seats[ME])
    eq(after, 1810, "K: ...the next rated 2v2 is")
    eq(K.NextMmr(g2, g2.seats[SH]), 1760, "K: and the teammate's, past the skirmish they played with you")

    -- 4. Past half an hour only your own number is trusted
    local g5 = Game(T0 + 1800 + 120 + 2 * 3600, { rated = true, rows = { Row("Devinp", 1830, 11), Row("Shiv", 1780, 12) } })
    after, nm, gap = K.NextMmr(g4, g4.seats[ME])
    CHECK(after == 1830 and gap == 2 * 3600, "K: yours, two hours later: still your next game")
    none, why = K.NextMmr(g4, g4.seats[SH])
    CHECK(none == nil and why == "UNKNOWN", "K: a teammate two hours later may have played without you")

    -- 5. A rated game without a board in between ends the search: two games' worth is not one
    local g6 = Game(T0 + 10000, { rated = nil, result = "LEFT" })
    Game(T0 + 10300, { rated = true, rows = { Row("Devinp", 1790, -15), Row("Shiv", 1750, -14) } })
    none, why = K.NextMmr(g5, g5.seats[ME])
    CHECK(none == nil and why == "UNKNOWN", "K: a left game between hides the change", why)
    eq(K.NextMmr(g6, g6.seats[ME]), nil, "K: the left game itself has no board, so no MMR")

    -- 6. Names: a realm suffix still matches; a namesake of another class does not
    local h1 = Game(T0 + 20000, { rated = true, rows = { Row("Devinp", 1700, 10), Row("Shiv", 1650, 10) } })
    Game(T0 + 20300, { rated = true, shivName = "Shiv-Nightslayer", rows = { Row("Devinp", 1715, 9), Row("Shiv-Nightslayer", 1662, 9) } })
    eq(K.NextMmr(h1, h1.seats[SH]), 1662, "K: Shiv and Shiv-Nightslayer are one player")
    local h2 = K.GetMatch("last")
    Game(T0 + 20600, { rated = true, shivClass = "PRIEST", rows = { Row("Devinp", 1722, 8), Row("Shiv", 1900, 8) } })
    none, why = K.NextMmr(h2, h2.seats[SH])
    CHECK(none == nil and why == "UNKNOWN", "K: a Shiv of another class is someone else")

    -- 7. The board merged again onto a CLOSED match: the late ratings land,
    -- an unseen player is seated, and no match is brought back to life
    local late = Game(T0 + 30000, { rated = nil, rows = { Row("Devinp", 0, 0), Row("Shiv", 0, 0) } })
    eq(late.rated, nil, "K: a board with no ratings yet does not decide rated")
    local rev = late.sbRev
    K.MergeScoreboard(late, { Row("Devinp", 0, 0), Row("Shiv", 0, 0) }, 1)
    eq(late.sbRev, rev, "K: the same board again changes nothing")
    K.MergeScoreboard(late, { Row("Devinp", 1740, 13), Row("Shiv", 1690, 12), Row("Hidden", 1720, -12, { faction = 0 }) }, 1)
    CHECK(late.sbRev == rev + 1, "K: the late ratings count as a change of the board")
    CHECK(late.seats[ME].sb.mmr == 1740 and late.seats[ME].sb.ratingChange == 13, "K: ...and land on the closed match")
    eq(late.rated, true, "K: a late rating change marks it rated")
    local hidden = late.seats["Score-Hidden"]
    CHECK(hidden and hidden.team == "them" and hidden.fromScoreboard, "K: an unseen player on the late board takes a seat")
    eq(K.Live(), nil, "K: merging onto a closed match never makes it live again")
    eq(late.bracket, 3, "K: a third enemy on the late board makes it a 3v3, as it would before the result")

    -- 8. The store keeps the board's revision and every reading round-trips
    local store = K.Export(20)   -- strips the live bookkeeping first
    local snap = K.Serialize(late)
    local K2 = LoadArena()
    CHECK(K2.Import(store) > 0, "K: the matches import")
    local back
    for _, mm in ipairs(K2.GetMatches()) do if mm.id == late.id then back = mm end end
    eq(back and K2.Serialize(back), snap, "K: a re-merged match round-trips byte-identically")
    local b1
    for _, mm in ipairs(K2.GetMatches()) do if mm.id == g1.id then b1 = mm end end
    eq(b1 and K2.NextMmr(b1, b1.seats[ME]), 1824, "K: the next-game reading works on an imported history")
end

-- ===========================================================================
-- Stage L: debuff uptime (D32) — the debuffs one side kept on one player,
-- the window from the gates to their death, the drops, the healing-reduced
-- union, and what never counts (their own team's debuffs, buffs, a source
-- that is no seat)
-- ===========================================================================

do
    local L = LoadArena()
    local WA, PA, RO = "Player-0-WARR", "Player-0-PALA", "Player-0-ROGU"
    local DR, PR = "Player-1-DRU", "Player-1-PRI"
    local m = L.Begin(T0, "Nagrand Arena")
    L.SetSeat("us", WA, "Bonecrush", "WARRIOR", "Orc", "player")
    L.SetSeat("us", PA, "Lightbringer", "PALADIN", "BloodElf", "party1")
    L.SetSeat("us", RO, "Shiv", "ROGUE", "Undead", "party2")
    L.SetSeat("them", DR, "Leafshade", "DRUID", "NightElf", "arena1", "Resto")
    L.SetSeat("them", PR, "Vespera", "PRIEST", "Human", "arena2")
    L.SetGates(T0 + 60)
    local function On(ts, sub, sg, sn, dg, dn, id, name, kind)
        L.OnCleu(T0 + ts, sub, nil, sg, sn, sg and (sg:find("^Player%-1") and F_ENEMY or F_PARTY) or 0, 0,
            dg, dn, dg:find("^Player%-1") and F_ENEMY or F_PARTY, 0, id, name, 1, kind or "DEBUFF")
    end
    -- Mortal Strike: three stretches, two drops (10 s, then 15 s)
    On(65, "SPELL_AURA_APPLIED", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    On(70, "SPELL_AURA_REFRESH", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    On(75, "SPELL_AURA_REFRESH", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    On(85, "SPELL_AURA_REMOVED", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    On(95, "SPELL_AURA_APPLIED", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    On(105, "SPELL_AURA_REMOVED", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    On(120, "SPELL_AURA_APPLIED", WA, "Bonecrush", DR, "Leafshade", 30330, "Mortal Strike")
    -- Judgement of Justice: faded and judged again the same second — one stretch
    On(62, "SPELL_AURA_APPLIED", PA, "Lightbringer", DR, "Leafshade", 20184, "Judgement of Justice")
    On(82, "SPELL_AURA_REMOVED", PA, "Lightbringer", DR, "Leafshade", 20184, "Judgement of Justice")
    On(82, "SPELL_AURA_APPLIED", PA, "Lightbringer", DR, "Leafshade", 20184, "Judgement of Justice")
    On(100, "SPELL_AURA_REMOVED", PA, "Lightbringer", DR, "Leafshade", 20184, "Judgement of Justice")
    -- Wound Poison, stacking, overlapping both Mortal Strikes' edges
    On(80, "SPELL_AURA_APPLIED", RO, "Shiv", DR, "Leafshade", 27189, "Wound Poison V")
    On(82, "SPELL_AURA_APPLIED_DOSE", RO, "Shiv", DR, "Leafshade", 27189, "Wound Poison V")
    On(98, "SPELL_AURA_REMOVED", RO, "Shiv", DR, "Leafshade", 27189, "Wound Poison V")
    -- Repentance broken by a blow with no REMOVED after it: the break ends it
    On(108, "SPELL_AURA_APPLIED", PA, "Lightbringer", DR, "Leafshade", 20066, "Repentance")
    L.OnCleu(T0 + 110, "SPELL_AURA_BROKEN_SPELL", nil, WA, "Bonecrush", F_PARTY, 0, DR, "Leafshade", F_ENEMY, 0,
        20066, "Repentance", 1, 30330, "Mortal Strike", 1, "DEBUFF")
    -- Never counted: their own priest's Weakened Soul, a buff, a source with no seat
    On(70, "SPELL_AURA_APPLIED", PR, "Vespera", DR, "Leafshade", 6788, "Weakened Soul")
    On(85, "SPELL_AURA_REMOVED", PR, "Vespera", DR, "Leafshade", 6788, "Weakened Soul")
    On(70, "SPELL_AURA_APPLIED", PR, "Vespera", DR, "Leafshade", 25218, "Power Word: Shield", "BUFF")
    L.OnCleu(T0 + 90, "SPELL_AURA_APPLIED", nil, "Creature-0-DUMMY", "Dummy", 0xa48, 0,
        DR, "Leafshade", F_ENEMY, 0, 1, "Creature Curse", 1, "DEBUFF")
    -- On us: their priest's Shadow Word: Pain on the warrior
    On(70, "SPELL_AURA_APPLIED", PR, "Vespera", WA, "Bonecrush", 25368, "Shadow Word: Pain")
    On(88, "SPELL_AURA_REMOVED", PR, "Vespera", WA, "Bonecrush", 25368, "Shadow Word: Pain")
    -- Damage: the priest takes the most (the one trained) — the shared
    -- helpers drive Stage A's engine, so this stage calls its own
    local function Hit(ts, dg, dn, amount)
        L.OnCleu(T0 + ts, "SPELL_DAMAGE", nil, WA, "Bonecrush", F_ME, 0, dg, dn, F_ENEMY, 0,
            30330, "Mortal Strike", 1, amount, 0, 1, 0, 0, 0, false, false, false, false)
    end
    Hit(66, DR, "Leafshade", 1000)
    Hit(67, PR, "Vespera", 3000)

    -- Live, mid-way: an open Mortal Strike counts to the cursor
    local u = {}
    L.Uptime(m, DR, 125, u)
    local live
    for i = 1, u.n do if u.rows[i].name == "Mortal Strike" then live = u.rows[i] end end
    near(live and live.secs or 0, 35, "L: live, the open Mortal Strike counts to the cursor (20 + 10 + 5)")
    eq(L.UptimeTarget(m), PR, "L: the drawer opens on the enemy who took the most damage")

    Hit(129, DR, "Leafshade", 2500)
    L.OnCleu(T0 + 130, "UNIT_DIED", nil, nil, nil, 0x80000000, 0, DR, "Leafshade", F_ENEMY, 0)
    L.Finish(T0 + 140, "WIN")

    -- The whole match: gates (60) to the druid's death (130) = 70 s
    L.Uptime(m, DR, m.tEnd, u)
    CHECK(u.t0 == 60 and u.tFull == 130 and u.t1 == 130 and u.span == 70, "L: the window runs from the gates to their death",
        string.format("%s %s %s %s", u.t0, u.tFull, u.t1, u.span))
    eq(u.died, 130, "L: their death is in the window")
    eq(u.n, 4, "L: four debuffs from the other team")
    local byName = {}
    for i = 1, u.n do byName[u.rows[i].name] = u.rows[i] end
    CHECK(not byName["Weakened Soul"] and not byName["Power Word: Shield"] and not byName["Creature Curse"],
        "L: their own team's debuff, a buff and a seatless source never count")
    local ms, jj, wp = byName["Mortal Strike"], byName["Judgement of Justice"], byName["Wound Poison V"]
    CHECK(byName["Repentance"] and byName["Repentance"].secs == 2, "L: a broken debuff ends at the break, REMOVED or not")
    CHECK(u.rows[1] == ms and u.rows[2] == jj and u.rows[3] == wp, "L: rows by seconds up, most first")
    near(ms.secs, 40, "L: Mortal Strike up 40 s (closed by the death)")
    near(ms.pct, 40 / 70, "L: ...57% of the time alive")
    CHECK(ms.n == 3 and ms.longest == 20 and ms.first == 65, "L: ...in three stretches, the longest 20 s, first at 65",
        string.format("%s %s %s", ms.n, ms.longest, ms.first))
    CHECK(ms.gap == 15 and ms.gapAt == 105, "L: ...the longest drop 15 s from 1:45", string.format("%s %s", ms.gap, tostring(ms.gapAt)))
    near(ms.srcs[WA] or 0, 40, "L: ...all of it the warrior's")
    CHECK(ms.ivN == 6 and ms.iv[1] == 65 and ms.iv[2] == 85 and ms.iv[5] == 120 and ms.iv[6] == 130, "L: ...its stretches for the strip")
    CHECK(jj.n == 1 and jj.secs == 38, "L: a fade and a judgement the same second is one stretch", jj.n .. " " .. jj.secs)
    CHECK(jj.gap == 30 and jj.gapAt == 100, "L: the drop after the last fade counts (100 to the death)")
    -- Healing reduced: MS [65,85] [95,105] [120,130] ∪ WP [80,98] = [65,105] + [120,130]
    local h = u.heal
    CHECK(h ~= nil, "L: a healing-reduced row")
    CHECK(h and h.secs == 50 and h.n == 2 and h.gap == 15 and h.gapAt == 105, "L: ...the union of Mortal Strike and Wound Poison",
        h and string.format("%s %s %s %s", h.secs, h.n, h.gap, tostring(h.gapAt)))
    CHECK(h and h.srcs["Mortal Strike"] == 37 and h.srcs["Wound Poison V"] == 13, "L: ...credited to whichever was on first")

    -- As of a cursor: 1:30 (window 60-90)
    L.Uptime(m, DR, 90, u)
    eq(u.span, 30, "L: the cursor shortens the window")
    eq(u.died, nil, "L: a death after the cursor is not in it")
    CHECK(u.rows[1].name == "Judgement of Justice" and u.rows[1].secs == 28, "L: at the cursor JoJ leads (28 s)")
    CHECK(u.rows[2].name == "Mortal Strike" and u.rows[2].secs == 20 and u.rows[2].gap == 5 and u.rows[2].gapAt == 85,
        "L: ...Mortal Strike 20 s, dropped 5 s ago")
    CHECK(u.heal and u.heal.secs == 25, "L: ...healing reduced 25 s")
    L.Uptime(m, DR, 50, u)
    CHECK(u.span == 0 and u.n == 0 and u.heal == nil, "L: before the gates there is nothing to read")

    -- The other side, on the same out table: rows never leak between targets
    L.Uptime(m, WA, m.tEnd, u)
    CHECK(u.n == 1 and #u.rows == 1 and u.rows[1].name == "Shadow Word: Pain", "L: on our warrior: their priest's dot alone")
    CHECK(u.tFull == 140 and u.span == 80 and u.heal == nil, "L: ...alive to the end, no healing reduced")
    near(u.rows[1].srcs[PR] or 0, 18, "L: ...credited to their priest")
    CHECK(next(u.rows[1].srcs, next(u.rows[1].srcs)) == nil, "L: a reused row keeps no stale casters")
    L.Uptime(m, "Player-9-NOBODY", m.tEnd, u)
    CHECK(u.n == 0 and #u.rows == 0, "L: an unknown seat reads empty")
    m.seats[DR].auraDropped = 2
    L.Uptime(m, DR, m.tEnd, u)
    eq(u.dropped, 2, "L: intervals past the cap are reported")
    m.seats[DR].auraDropped = 0

    -- The store keeps every interval: an imported match reads the same
    local store = L.Export(20)
    local L2 = LoadArena()
    CHECK(L2.Import(store) > 0, "L: the match imports")
    local back = L2.GetMatches()[1]
    local u2 = L2.Uptime(back, DR, back.tEnd, {})
    CHECK(u2.n == 4 and u2.rows[1].secs == 40 and u2.heal and u2.heal.secs == 50, "L: an imported match reads the same uptime")
end

-- ===========================================================================
-- Stage M: the breakdown (D33) — one seat's damage by ability and by
-- target, its healing by spell and by whom it landed on, whole match and as
-- of a cursor, adding up to the METERS band's numbers at any second
-- ===========================================================================

do
    local M = LoadArena()
    local MA, PR = "Player-0-MAGE", "Player-0-PRI"
    local WA, DR = "Player-1-WAR", "Player-1-DRU"
    local WE, TOTEM = "Pet-0-ELEM", "Creature-0-GROUND"
    local m = M.Begin(T0, "Blade's Edge Arena")
    M.SetSeat("us", PR, "Vespers", "PRIEST", "Dwarf", "party1", "Disc")
    M.SetSeat("us", MA, "Frostweaver", "MAGE", "Human", "player", "Frost")
    M.SetSeat("them", WA, "Gorehowl", "WARRIOR", "Orc", "arena1")
    M.SetSeat("them", DR, "Leafshade-Mograine", "DRUID", "Tauren", "arena2", "Resto")
    M.SetOwner(WE, MA, "Water Elemental")
    M.SetGates(T0 + 60)
    local function Dmg(ts, sg, sn, sf, dg, dn, df, id, name, amount, absorbed, crit)
        M.OnCleu(T0 + ts, "SPELL_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0,
            id, name, 16, amount, 0, 16, 0, 0, absorbed or 0, crit or false, false, false, false)
    end
    local function Heal(ts, sub, dg, dn, df, id, name, amount, over)
        M.OnCleu(T0 + ts, sub, nil, PR, "Vespers", F_PARTY, 0, dg, dn, df, 0, id, name, 2, amount, over or 0, 0, false)
    end
    -- The mage: Frostbolts on both, one into a shield, one wholly absorbed
    Dmg(65, MA, "Frostweaver", F_ME, WA, "Gorehowl", F_ENEMY, 27072, "Frostbolt", 2000)
    Dmg(70, MA, "Frostweaver", F_ME, DR, "Leafshade", F_ENEMY, 27079, "Fire Blast", 900)
    Dmg(80, MA, "Frostweaver", F_ME, WA, "Gorehowl", F_ENEMY, 27072, "Frostbolt", 2500, 0, true)
    Dmg(85, WE, "Water Elemental", F_FPET, WA, "Gorehowl", F_ENEMY, 31707, "Waterbolt", 1100)
    Dmg(90, MA, "Frostweaver", F_ME, DR, "Leafshade", F_ENEMY, 27072, "Frostbolt", 1200, 300)
    Dmg(100, MA, "Frostweaver", F_ME, WA, "Gorehowl", F_ENEMY, 27072, "Frostbolt", 1800)
    M.OnCleu(T0 + 108, "SPELL_DAMAGE", nil, MA, "Frostweaver", F_ME, 0, TOTEM, "Grounding Totem", 0xa48, 0,
        27079, "Fire Blast", 4, 150, 0, 4, 0, 0, 0, false, false, false, false)
    M.OnCleu(T0 + 110, "SPELL_MISSED", nil, MA, "Frostweaver", F_ME, 0, WA, "Gorehowl", F_ENEMY, 0,
        27072, "Frostbolt", 16, "ABSORB", false, 700, false)
    M.OnCleu(T0 + 112, "SPELL_MISSED", nil, MA, "Frostweaver", F_ME, 0, DR, "Leafshade", F_ENEMY, 0,
        12826, "Polymorph", 64, "RESIST", false, 0, false)
    -- The priest: a Flash Heal on the mage, a Renew tick on herself, a
    -- Greater Heal that was all overheal, a shield, a Smite
    Heal(75, "SPELL_HEAL", MA, "Frostweaver", F_ME, 25235, "Flash Heal", 1500, 200)
    Heal(85, "SPELL_PERIODIC_HEAL", PR, "Vespers", F_PARTY, 25222, "Renew", 400)
    Heal(95, "SPELL_HEAL", MA, "Frostweaver", F_ME, 25213, "Greater Heal", 3000, 3000)
    M.OnCleu(T0 + 100, "SPELL_ABSORBED", nil, WA, "Gorehowl", F_ENEMY, 0, MA, "Frostweaver", F_ME, 0,
        30330, "Mortal Strike", 1, PR, "Vespers", F_PARTY, 0, 25218, "Power Word: Shield", 2, 1000, false)
    Dmg(105, PR, "Vespers", F_PARTY, WA, "Gorehowl", F_ENEMY, 25364, "Smite", 800)
    -- The warrior spreads 10 a hit over 42 dummies, then one more past the cap
    for i = 1, 42 do
        M.OnCleu(T0 + 70, "SWING_DAMAGE", nil, WA, "Gorehowl", F_ENEMY, 0, "Creature-0-D" .. i, "Dummy " .. i, 0xa48, 0,
            10, 0, 1, 0, 0, 0, false, false, false, false)
    end
    M.OnCleu(T0 + 120, "SWING_DAMAGE", nil, WA, "Gorehowl", F_ENEMY, 0, "Creature-0-D50", "Dummy 50", 0xa48, 0,
        10, 0, 1, 0, 0, 0, false, false, false, false)
    M.Finish(T0 + 130, "WIN")

    eq(M.BreakdownSeat(m), MA, "M: the drawer opens on you")
    local DMG, HEAL = M.StatByKey("DMG"), M.StatByKey("HEAL")
    local o = M.Breakdown(m, MA, nil, {})
    local d = o.dmg
    eq(o.whole, false, "M: a whole-match read is no fallback")
    eq(d.full, m.seats[MA].dmg, "M: the abilities add up to the mage's damage")
    eq(d.total, d.full, "M: ...and at the end the cursor reads the whole match")
    eq(d.n, 3, "M: Frostbolt, Waterbolt, Fire Blast; the resisted Polymorph did no damage")
    CHECK(d.rows[1].key == "Frostbolt" and d.rows[1].full == 8500, "M: Frostbolt leads with 8500 (a shield's share and a full absorb in it)",
        d.rows[1].key .. " " .. d.rows[1].full)
    CHECK(d.rows[2].key == "Water Elemental: Waterbolt" and d.rows[2].pet == "Water Elemental" and d.rows[2].name == "Waterbolt",
        "M: the pet's ability is the mage's, under the pet's name")
    CHECK(d.rows[3].key == "Fire Blast" and d.rows[3].full == 1050, "M: Fire Blast, the totem's 150 in it")
    CHECK(d.rows[1].rec.crit == 1 and d.rows[1].rec.count == 5 and d.rows[1].rec.max == 2500, "M: a row carries its record (hits, crits, biggest)")
    eq(d.onN, 3, "M: three targets")
    CHECK(d.on[1].key == "Gorehowl" and d.on[1].full == 8100 and d.on[1].guid == WA, "M: the warrior took 8100, and is a seat")
    CHECK(d.on[2].key == "Leafshade" and d.on[2].guid == DR, "M: a target named without a realm finds the seat with one")
    CHECK(d.on[3].key == "Grounding Totem" and d.on[3].guid == nil and d.on[3].full == 150, "M: a totem is a target with no seat")
    local h = o.heal
    eq(h.full, m.seats[MA].heal + m.seats[MA].absorb, "M: the mage healed nothing")
    eq(h.n, 0, "M: ...and lists nothing")

    local p = M.Breakdown(m, PR, nil, {})
    h = p.heal
    eq(h.full, 2700, "M: the priest's healing, shields included")
    eq(h.full, m.seats[PR].heal + m.seats[PR].absorb, "M: ...the HEAL stat exactly")
    eq(h.n, 4, "M: four spells, the all-overheal Greater Heal among them")
    CHECK(h.rows[1].key == "Flash Heal" and h.rows[2].key == "Power Word: Shield" and h.rows[3].key == "Renew"
        and h.rows[4].key == "Greater Heal" and h.rows[4].full == 0 and h.rows[4].rec.overheal == 3000,
        "M: by healing done, the wasted Greater Heal last with its overheal")
    eq(h.onN, 2, "M: two players healed")
    CHECK(h.on[1].key == "Frostweaver" and h.on[1].full == 2300 and h.on[1].guid == MA, "M: the mage got the Flash Heal and the shield's 1000")
    CHECK(h.on[2].key == "Vespers" and h.on[2].full == 400, "M: the priest's Renew on herself")
    eq(p.dmg.full, 800, "M: the priest's Smite")

    -- As of 1:25.5 (bucket 86): the METERS band's numbers, the whole-match order
    o = M.Breakdown(m, MA, 85.5, o)
    d = o.dmg
    eq(d.total, 6500, "M: at the cursor: two Frostbolts, the Waterbolt that second, the Fire Blast")
    eq(d.total, M.SeatValueAt(m, m.seats[MA], DMG, 85.5), "M: ...the meters band's DMG at the cursor")
    CHECK(d.rows[1].key == "Frostbolt" and d.rows[1].value == 4500, "M: Frostbolt 4500 so far, still first")
    CHECK(d.rows[3].key == "Fire Blast" and d.rows[3].value == 900, "M: Fire Blast without the later totem")
    CHECK(d.on[1].value == 5600 and d.on[2].value == 900 and d.on[3].value == 0, "M: targets as of the cursor; the totem listed at 0")
    eq(d.full, 10650, "M: the whole match rides along")
    p = M.Breakdown(m, PR, 85.5, p)
    eq(p.heal.total, 1700, "M: the priest's healing at the cursor: the Flash Heal and the Renew")
    eq(p.heal.total, M.SeatValueAt(m, m.seats[PR], HEAL, 85.5), "M: ...the meters band's HEAL at the cursor")
    CHECK(p.heal.rows[2].key == "Power Word: Shield" and p.heal.rows[2].value == 0, "M: the shield not absorbed yet")
    CHECK(p.heal.on[1].value == 1300 and p.heal.on[2].value == 400, "M: healed as of the cursor")
    o = M.Breakdown(m, MA, 50, o)
    CHECK(o.dmg.total == 0 and o.dmg.n == 3, "M: before the gates: every row listed, nothing done")

    -- Past the cap: names fold into (other), its series too
    local w = M.Breakdown(m, WA, nil, {})
    local other
    for i = 1, w.dmg.onN do if w.dmg.on[i].key == "(other)" then other = w.dmg.on[i] end end
    eq(w.dmg.onN, 41, "M: forty names and (other)")
    CHECK(other and other.full == 30, "M: (other) holds the two past the cap and the late one")
    w = M.Breakdown(m, WA, 100, w)
    other = nil
    for i = 1, w.dmg.onN do if w.dmg.on[i].key == "(other)" then other = w.dmg.on[i] end end
    CHECK(other and other.value == 20, "M: ...and reads its own cursor")
    eq(w.dmg.total, M.SeatValueAt(m, m.seats[WA], DMG, 100), "M: the warrior's total at the cursor")

    -- A reused out table on an unknown seat holds no stale rows
    M.Breakdown(m, "Player-9-NOBODY", nil, o)
    CHECK(o.dmg.n == 0 and #o.dmg.rows == 0 and o.dmg.onN == 0 and #o.dmg.on == 0 and o.heal.n == 0,
        "M: an unknown seat reads empty")

    -- The store keeps the series: an imported match reads the same cursor
    local store = M.Export(20)
    local M2 = LoadArena()
    CHECK(M2.Import(store) > 0, "M: the match imports")
    local back = M2.GetMatches()[1]
    local b2 = M2.Breakdown(back, PR, 85.5, {})
    CHECK(b2.whole == false and b2.heal.total == 1700 and b2.heal.on[1].key == "Frostweaver", "M: an imported match reads the same at the cursor")
    -- A match saved before the breakdown: no series, no healed names; it
    -- reads whole-match at any cursor and says so
    back.keySeries = nil
    for _, seat in pairs(back.seats) do
        seat.healTargets, seat.healTargetsN, seat.sTargets, seat.sHealTargets = nil, nil, nil, nil
        for _, rec in pairs(seat.spells) do rec.s = nil end
        for _, rec in pairs(seat.heals) do rec.s = nil end
    end
    local old = M2.Export(20)
    local M3 = LoadArena()
    CHECK(M3.Import(old) > 0, "M: an old store imports")
    local oldM = M3.GetMatches()[1]
    local b3 = M3.Breakdown(oldM, PR, 85.5, {})
    CHECK(b3.whole == true and b3.heal.total == 2700 and b3.heal.onN == 0, "M: an old store reads the whole match, healed names unknown")
    eq(M3.Breakdown(oldM, PR, nil, {}).whole, false, "M: ...and at the end it is no fallback")
end

if fails > 0 then
    io.write(string.format("RESULT: %d/%d FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("RESULT: all %d arena checks passed\n", checks))
