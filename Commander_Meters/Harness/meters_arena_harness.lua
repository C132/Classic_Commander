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
local function dispel(ts, sub, sg, sn, sf, dg, dn, df, id, name, exId, exName)
    A.OnCleu(ts, sub, nil, sg, sn, sf, 0, dg, dn, df, 0, id, name, 2, exId, exName, 8, "BUFF")
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
dispel(T0 + 121, "SPELL_DISPEL", P3, "Vespers", F_PARTY, ME, "Devinp", F_ME, 527, "Dispel Magic", 8122, "Psychic Scream")
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
dispel(T0 + 125, "SPELL_DISPEL", P3, "Vespers", F_PARTY, R2, "Shiv", F_PARTY, 527, "Dispel Magic", 8122, "Psychic Scream")
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

if fails > 0 then
    io.write(string.format("RESULT: %d/%d FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("RESULT: all %d arena checks passed\n", checks))
