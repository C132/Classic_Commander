-- Commander Tracer engine smoke (luajit)
--
--     luajit Commander_Tracer/Harness/tracer_engine_smoke.lua
--
-- The rules, with no client attached. Sections:
--   A  numbers: plain, separated, short
--   B  colours: schools (single and blended), powers, kinds, the flat palette
--   C  classification: every combat-log family the module reads, in the
--      2.5.x field layout, from you / your pet / at you / nobody's business
--   D  routing: lane and ledger from the saved variables
--   E  text: every format, crit marks, partials, counts, the moments
--   F  lanes: spawn, merge, max lines, stagger, scatter
--   G  motion: scroll, fountain, pop and stack over time; fade; punch
--   H  the test volley touches every lane and every kind it claims to

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end
local function EQ(got, want, label)
    CHECK(got == want, label, string.format("got %s want %s", tostring(got), tostring(want)))
end
local function NEAR(got, want, label, eps)
    CHECK(type(got) == "number" and math.abs(got - want) <= (eps or 0.01), label,
        string.format("got %s want %s", tostring(got), tostring(want)))
end

bit = bit or require("bit")
assert(loadfile(ADDONS .. "/Commander_Tracer/CommanderTracerData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Tracer/CommanderTracerEngine.lua"))()
local DATA = CommanderTracer_Data
local E = CommanderTracer_Engine
E.random = function() return 0.75 end

-- ===========================================================================
-- A: numbers
-- ===========================================================================
EQ(E.FormatNumber(1204, "PLAIN"), "1204", "A: plain")
EQ(E.FormatNumber(1204, "SEPARATED"), "1,204", "A: separated")
EQ(E.FormatNumber(1234567, "SEPARATED"), "1,234,567", "A: separated, millions")
EQ(E.FormatNumber(999, "SEPARATED"), "999", "A: separated, under a thousand")
EQ(E.FormatNumber(12345, "SHORT"), "12.3k", "A: short, tens of thousands")
EQ(E.FormatNumber(10000, "SHORT"), "10k", "A: short trims a .0")
EQ(E.FormatNumber(9999, "SHORT"), "9,999", "A: short keeps four digits readable")
EQ(E.FormatNumber(1500000, "SHORT"), "1.5m", "A: short, millions")
EQ(E.FormatNumber(1204.6, "SEPARATED"), "1,205", "A: rounds")
EQ(E.FormatNumber(nil, "SEPARATED"), "0", "A: nil is zero")

-- ===========================================================================
-- B: colours
-- ===========================================================================
local r, g, b = E.SchoolColor(4)
CHECK(r == 1 and g == 0.5 and b == 0.15, "B: fire is orange")
r, g, b = E.SchoolColor(20)
NEAR(r, 0.75, "B: frostfire averages fire and frost (r)")
NEAR(g, 0.65, "B: ...(g)")
r = E.SchoolColor(nil)
EQ(r, 1, "B: nil school is physical")
EQ(E.SchoolName(20), "FireFrost", "B: school name lists the bits")
EQ(E.SchoolName(0), "Physical", "B: no bits is physical")
r, g, b = E.PowerColor(1)
CHECK(r == 1 and g == 0.25, "B: rage is red")
EQ(E.PowerName(3), "Energy", "B: energy is named")
EQ(E.PowerName(99), "Power", "B: an unknown power is 'Power'")
r, g, b = E.KindColor("KillingBlow")
CHECK(r == 1 and g == 0.82, "B: a killing blow is gold")
r = E.KindColor("Nope")
EQ(r, 1, "B: unknown kind is white")
r, g, b = E.FlatColor("EMBER")
CHECK(r == 1 and g == 0.55, "B: the module's own palette")
r, g, b = E.FlatColor("FEL", { { value = "FEL", r = 0.5, g = 0.95, b = 0.15 } })
CHECK(r == 0.5 and g == 0.95, "B: an extra palette (Console's) resolves too")
r = E.FlatColor("MISSING")
EQ(r, 1, "B: a missing key is white")

local hit = { kind = "DamageDone", damage = true, school = 32, amount = 100 }
r, g, b = E.Color({ ColorMode = "SCHOOL" }, hit)
CHECK(r == 0.7 and b == 1, "B: SCHOOL mode paints damage by school")
r, g, b = E.Color({ ColorMode = "KIND" }, hit)
CHECK(r == 1 and g == 1 and b == 1, "B: KIND mode paints your hits white")
r, g, b = E.Color({ ColorMode = "FLAT", FlatColor = "GOLD" }, hit)
CHECK(r == 1 and g == 0.85, "B: FLAT mode uses the picked colour")
r, g, b = E.Color({ ColorMode = "CLASS" }, hit, { 0.41, 0.8, 0.94 })
CHECK(r == 0.41, "B: CLASS mode uses the class colour")
r = E.Color({ ColorMode = "CLASS" }, hit, nil)
EQ(r, 1, "B: ...white without one")
r, g, b = E.Color({ ColorMode = "SCHOOL" }, { kind = "MissDone", missType = "DODGE" })
CHECK(r == 0.72, "B: a miss is grey whatever the school")
r, g, b = E.Color({ ColorMode = "SCHOOL" }, { kind = "Energize", powerType = 3 })
CHECK(r == 1 and g == 1 and b == 0.35, "B: energy gains are yellow")
r, g, b = E.Color({ ColorMode = "SCHOOL" }, { kind = "HealDone", heal = true, school = 2 })
CHECK(r == 0.35 and g == 1, "B: SCHOOL mode still paints a heal green (kind), not holy gold")

-- ===========================================================================
-- C: classification
-- ===========================================================================
local ME, PET = "Player-1-ME", "Pet-0-1"
local ctx = { player = ME, pet = PET }
local HOSTILE = 0x40 + 0x400
local MINE = 0x1 + 0x400
local MYPET = 0x1 + 0x1000
local function Ev(sub, sg, sn, sf, dg, dn, df, ...)
    return E.Classify(ctx, 1000, sub, false, sg, sn, sf, 0, dg, dn, df, 0, ...)
end

-- a spell hit of yours: prefix (id, name, school) then amount, overkill,
-- school, resisted, blocked, absorbed, critical, glancing, crushing
local rec = Ev("SPELL_DAMAGE", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    27070, "Fireball", 4, 1204, 0, 4, 0, 0, 0, nil, false, false)
EQ(rec and rec.kind, "DamageDone", "C: a Fireball is DamageDone")
EQ(rec.amount, 1204, "C: with its amount")
EQ(rec.spellId, 27070, "C: its id")
EQ(rec.school, 4, "C: its school")
EQ(rec.crit, false, "C: not a crit")
EQ(rec.target, "Boar", "C: the target's name")
EQ(rec.mergeKey, "DamageDone|Fireball", "C: merge key is kind and spell")
CHECK(rec.absorbed == nil and rec.overkill == nil, "C: zero partials are nil")

rec = Ev("SPELL_DAMAGE", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    27070, "Fireball", 4, 2410, 300, 4, 100, 0, 50, 1, false, false)
CHECK(rec.crit == true, "C: a crit is flagged")
EQ(rec.overkill, 300, "C: overkill kept")
EQ(rec.resisted, 100, "C: resisted kept")
EQ(rec.absorbed, 50, "C: absorbed kept")

rec = Ev("SWING_DAMAGE", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    212, 0, 1, 0, 0, 0, nil, false, false)
EQ(rec.kind, "AutoAttack", "C: a swing is AutoAttack")
EQ(rec.spellName, "Melee", "C: named Melee")
EQ(rec.amount, 212, "C: swing amount from a12")

rec = Ev("SPELL_PERIODIC_DAMAGE", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    27215, "Immolate", 4, 187, 0, 4, 0, 0, 0, nil, false, false)
EQ(rec.kind, "PeriodicDone", "C: a dot tick is PeriodicDone")
CHECK(rec.periodic, "C: ...flagged periodic")

rec = Ev("RANGE_DAMAGE", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    75, "Auto Shot", 1, 340, 0, 1, 0, 0, 0, nil, false, false)
EQ(rec.kind, "DamageDone", "C: an auto shot is a hit (not AutoAttack)")

rec = Ev("DAMAGE_SHIELD", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    9910, "Thorns", 8, 18, 0, 8, 0, 0, 0, nil, false, false)
EQ(rec.kind, "DamageDone", "C: thorns damage is yours")

rec = Ev("SPELL_DAMAGE", PET, "Boarpet", MYPET, "Creature-1", "Boar", HOSTILE,
    27049, "Claw", 1, 310, 0, 1, 0, 0, 0, nil, false, false)
EQ(rec.kind, "PetDamage", "C: the pet's Claw is PetDamage")
CHECK(rec.pet, "C: ...and tagged pet")
rec = Ev("SWING_DAMAGE", "Pet-0-9", "Guardian", MYPET, "Creature-1", "Boar", HOSTILE,
    50, 0, 1, 0, 0, 0, nil, false, false)
EQ(rec and rec.kind, "PetDamage", "C: a guardian of yours (by flags, not guid) is PetDamage too")

rec = Ev("SPELL_DAMAGE", "Player-2", "Bonecrush", HOSTILE, ME, "Me", MINE,
    30330, "Mortal Strike", 1, 618, 0, 1, 0, 0, 0, nil, false, false)
EQ(rec.kind, "DamageTaken", "C: a Mortal Strike on you is DamageTaken")
EQ(rec.source, "Bonecrush", "C: with the source's name")
rec = Ev("SPELL_PERIODIC_DAMAGE", "Player-3", "Dotlord", HOSTILE, ME, "Me", MINE,
    27216, "Corruption", 32, 96, 0, 32, 0, 0, 0, nil, false, false)
EQ(rec.kind, "PeriodicTaken", "C: a Corruption tick on you is PeriodicTaken")
rec = Ev("ENVIRONMENTAL_DAMAGE", nil, nil, 0, ME, "Me", MINE,
    "FALLING", 420, 0, 1, 0, 0, 0, nil, false, false)
EQ(rec.kind, "DamageTaken", "C: falling is DamageTaken")
EQ(rec.spellName, "Falling", "C: ...named from the environment type")
EQ(rec.amount, 420, "C: ...environmental amount from a13")
rec = Ev("SPELL_DAMAGE", ME, "Me", MINE, ME, "Me", MINE,
    27213, "Hellfire", 4, 150, 0, 4, 0, 0, 0, nil, false, false)
EQ(rec.kind, "DamageTaken", "C: self-damage is damage taken")

rec = Ev("SPELL_DAMAGE", "Player-2", "Bonecrush", HOSTILE, "Player-4", "Ally", 0x10 + 0x400,
    30330, "Mortal Strike", 1, 618, 0, 1, 0, 0, 0, nil, false, false)
CHECK(rec == nil, "C: someone else hitting someone else is nobody's business")

-- misses: prefix then missType, isOffHand, amountMissed
rec = Ev("SPELL_MISSED", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE,
    27072, "Frostbolt", 16, "RESIST", false, nil)
EQ(rec.kind, "MissDone", "C: a resisted Frostbolt is MissDone")
EQ(rec.missType, "RESIST", "C: ...with the type")
rec = Ev("SWING_MISSED", "Player-2", "Bonecrush", HOSTILE, ME, "Me", MINE,
    "DODGE", false, nil)
EQ(rec.kind, "MissTaken", "C: dodging a swing is MissTaken")
EQ(rec.spellName, "Melee", "C: ...named Melee")
rec = Ev("SPELL_MISSED", "Player-2", "X", HOSTILE, ME, "Me", MINE,
    1, "Shield Bash", 1, "ABSORB", false, 120)
EQ(rec.amount, 120, "C: an absorbed miss carries the amount")

-- heals: prefix then amount, overhealing, absorbed, critical
rec = Ev("SPELL_HEAL", ME, "Me", MINE, "Player-5", "Leafheal", 0x10 + 0x400,
    25235, "Flash Heal", 2, 1730, 200, 0, nil)
EQ(rec.kind, "HealDone", "C: your Flash Heal is HealDone")
EQ(rec.overheal, 200, "C: overheal kept")
EQ(rec.crit, false, "C: not a crit heal")
rec = Ev("SPELL_PERIODIC_HEAL", ME, "Me", MINE, ME, "Me", MINE,
    25222, "Renew", 2, 250, 0, 0, nil)
EQ(rec.kind, "PeriodicHeal", "C: your own Renew tick on yourself is a hot tick of yours")
rec = Ev("SPELL_HEAL", "Player-6", "Lightbringer", 0x10 + 0x400, ME, "Me", MINE,
    27137, "Flash of Light", 2, 1450, 0, 0, 1)
EQ(rec.kind, "HealTaken", "C: a paladin's heal on you is HealTaken")
CHECK(rec.crit, "C: ...crit flagged")
rec = Ev("SPELL_HEAL", "Player-6", "Lightbringer", 0x10 + 0x400, "Player-5", "Leafheal", 0x10 + 0x400,
    27137, "Flash of Light", 2, 1450, 0, 0, nil)
CHECK(rec == nil, "C: a heal between two others is ignored")

-- energize: (amount, overEnergize, powerType) on this client
rec = Ev("SPELL_ENERGIZE", "Player-6", "Lightbringer", 0x10 + 0x400, ME, "Me", MINE,
    27164, "Judgement of Wisdom", 2, 240, 0, 0)
EQ(rec.kind, "Energize", "C: a JoW proc is Energize")
EQ(rec.powerType, 0, "C: ...mana, from the three-number layout")
rec = Ev("SPELL_ENERGIZE", ME, "Me", MINE, ME, "Me", MINE,
    29131, "Bloodrage", 1, 10, 1)
EQ(rec.powerType, 1, "C: ...rage, from the two-number layout")
rec = Ev("SPELL_PERIODIC_ENERGIZE", ME, "Me", MINE, ME, "Me", MINE,
    29131, "Bloodrage", 1, 1, 0, 1)
CHECK(rec.periodic, "C: a periodic energize is flagged periodic")
rec = Ev("SPELL_ENERGIZE", "Player-6", "L", 0x10, "Player-5", "Leafheal", 0x10,
    27164, "Judgement of Wisdom", 2, 240, 0, 0)
CHECK(rec == nil, "C: someone else's mana is not yours")

-- absorbs, both layouts
rec = Ev("SPELL_ABSORBED", "Player-2", "Bonecrush", HOSTILE, ME, "Me", MINE,
    1752, "Sinister Strike", 1, ME, "Me", MINE, 0, 25218, "Power Word: Shield", 2, 402, nil)
EQ(rec.kind, "AbsorbTaken", "C: a shielded Sinister Strike is AbsorbTaken")
EQ(rec.spellName, "Power Word: Shield", "C: ...named for the shield")
EQ(rec.amount, 402, "C: ...with the absorbed amount (spell layout)")
EQ(rec.attack, "Sinister Strike", "C: ...remembering what it ate")
rec = Ev("SPELL_ABSORBED", "Player-2", "Bonecrush", HOSTILE, ME, "Me", MINE,
    ME, "Me", MINE, 0, 25218, "Power Word: Shield", 2, 150, nil)
EQ(rec.amount, 150, "C: ...and the swing layout")
EQ(rec.attack, "Melee", "C: ...names the swing")

-- the moments
rec = Ev("SPELL_INTERRUPT", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE,
    1766, "Kick", 1, 12826, "Polymorph", 64)
EQ(rec.kind, "Interrupt", "C: your Kick on a Polymorph is Interrupt")
EQ(rec.spellName, "Polymorph", "C: ...named for what was stopped")
EQ(rec.tool, "Kick", "C: ...remembering the tool")
rec = Ev("SPELL_INTERRUPT", "Player-7", "Gankmage", HOSTILE, ME, "Me", MINE,
    2139, "Counterspell", 64, 27070, "Fireball", 4)
CHECK(rec == nil, "C: being interrupted is not an interrupt of yours")
rec = Ev("SPELL_DISPEL", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE,
    8012, "Purge", 8, 25222, "Renew", 2, "BUFF")
EQ(rec.kind, "Dispel", "C: a Purge is Dispel")
EQ(rec.spellName, "Renew", "C: ...named for what was removed")
rec = Ev("SPELL_STOLEN", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE,
    30449, "Spellsteal", 64, 10952, "Inner Fire", 2, "BUFF")
CHECK(rec.kind == "Dispel" and rec.stolen, "C: a Spellsteal is a Dispel marked stolen")
rec = Ev("PARTY_KILL", ME, "Me", MINE, "Player-7", "Gankmage", HOSTILE)
EQ(rec.kind, "KillingBlow", "C: PARTY_KILL from you is KillingBlow")
EQ(rec.target, "Gankmage", "C: ...naming the victim")
rec = Ev("PARTY_KILL", "Player-4", "Ally", 0x10, "Player-7", "Gankmage", HOSTILE)
CHECK(rec == nil, "C: a partner's kill is not yours")
rec = Ev("SPELL_AURA_APPLIED", "Player-7", "Gankmage", HOSTILE, ME, "Me", MINE,
    12826, "Polymorph", 64, "DEBUFF")
EQ(rec.kind, "DebuffGained", "C: a sheep on you is DebuffGained")
rec = Ev("SPELL_AURA_APPLIED", ME, "Me", MINE, ME, "Me", MINE,
    10952, "Inner Fire", 2, "BUFF")
EQ(rec.kind, "BuffGained", "C: Inner Fire on you is BuffGained")
rec = Ev("SPELL_AURA_REMOVED", ME, "Me", MINE, ME, "Me", MINE,
    10952, "Inner Fire", 2, "BUFF")
EQ(rec.kind, "BuffFaded", "C: ...and its removal BuffFaded")
rec = Ev("SPELL_AURA_REMOVED", "Player-7", "Gankmage", HOSTILE, ME, "Me", MINE,
    12826, "Polymorph", 64, "DEBUFF")
CHECK(rec == nil, "C: a debuff fading is not reported")
rec = Ev("SPELL_AURA_APPLIED", ME, "Me", MINE, "Player-5", "Leafheal", 0x10,
    10952, "Inner Fire", 2, "BUFF")
CHECK(rec == nil, "C: a buff on someone else is not reported")
CHECK(Ev("SPELL_CAST_SUCCESS", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE, 27070, "Fireball", 4) == nil,
    "C: an unknown subevent is nil")
CHECK(Ev("SPELL_DAMAGE", ME, "Me", MINE, "Creature-1", "Boar", HOSTILE, 27070, "Fireball", 4, "junk") == nil,
    "C: a non-numeric amount is nil, not a crash")
CHECK(E.Classify(ctx, 1000, nil) == nil, "C: no subevent is nil")

EQ(E.ProcRecord("Overpower").kind, "ProcReady", "C: a proc record")
EQ(E.HonorRecord("15").amount, 15, "C: an honor record takes a string amount")
CHECK(E.CombatRecord(true).entering, "C: a combat record")

-- ===========================================================================
-- D: routing
-- ===========================================================================
local db = { DamageDoneLane = "Out", DamageDoneLedger = true, AutoAttackLane = "Out", AutoAttackLedger = false,
    BuffGainedLane = "OFF", BuffGainedLedger = true, HonorGainedLane = "Log", HonorGainedLedger = true }
local lane, ledger = E.Route(db, { kind = "DamageDone" })
CHECK(lane == "Out" and ledger == true, "D: your hits go to Outgoing and the ledger")
lane, ledger = E.Route(db, { kind = "AutoAttack" })
CHECK(lane == "Out" and ledger == false, "D: auto-attacks stay off the ledger")
lane, ledger = E.Route(db, { kind = "BuffGained" })
CHECK(lane == nil and ledger == true, "D: OFF is no lane, ledger still possible")
lane, ledger = E.Route(db, { kind = "HonorGained" })
CHECK(lane == "Log" and ledger == false, "D: routed to the ledger lane itself, the flag is redundant")
lane, ledger = E.Route(db, { kind = "Unknown" })
CHECK(lane == nil and ledger == false, "D: an unrouted kind goes nowhere")
CHECK(E.Route(nil, { kind = "DamageDone" }) == nil, "D: no db is nowhere")

-- ===========================================================================
-- E: text
-- ===========================================================================
local fire = { kind = "DamageDone", damage = true, amount = 1204, spellName = "Fireball", target = "Gankmage" }
local main, sub = E.Text({ Format = "AMOUNT" }, fire, "SEPARATED")
EQ(main, "1,204", "E: AMOUNT")
EQ(sub, "Gankmage", "E: ...the target becomes the sub line")
main = E.Text({ Format = "AMOUNT_SPELL" }, fire, "SEPARATED")
EQ(main, "1,204 Fireball", "E: AMOUNT_SPELL")
main = E.Text({ Format = "SPELL_AMOUNT" }, fire, "SEPARATED")
EQ(main, "Fireball 1,204", "E: SPELL_AMOUNT")
main, sub = E.Text({ Format = "AMOUNT_TARGET" }, fire, "SEPARATED")
EQ(main, "1,204 on Gankmage", "E: AMOUNT_TARGET")
CHECK(sub == nil, "E: ...and no sub line when the target is in the main")
main = E.Text({ Format = "FULL" }, fire, "SHORT")
EQ(main, "Fireball 1,204 on Gankmage", "E: FULL")
main = E.Text({ Format = "AMOUNT" }, { kind = "DamageDone", amount = 12345 }, "SHORT")
EQ(main, "12.3k", "E: number style flows through")

local crit = { kind = "DamageDone", damage = true, amount = 2410, crit = true, spellName = "Fireball" }
EQ(E.Text({ Format = "AMOUNT", CritMark = "BANG" }, crit), "2,410!", "E: crit BANG")
EQ(E.Text({ Format = "AMOUNT", CritMark = "WORD" }, crit), "2,410 crit", "E: crit WORD")
EQ(E.Text({ Format = "AMOUNT", CritMark = "STARS" }, crit), "*2,410*", "E: crit STARS")
EQ(E.Text({ Format = "AMOUNT", CritMark = "NONE" }, crit), "2,410", "E: crit NONE")
EQ(E.Text({ Format = "AMOUNT" }, crit), "2,410!", "E: crit defaults to BANG")

local partial = { kind = "DamageDone", damage = true, amount = 900, spellName = "Fireball", absorbed = 300, resisted = 50 }
EQ(E.Text({ Format = "AMOUNT", ShowPartials = true }, partial), "900 (300 absorbed, 50 resisted)", "E: partials")
EQ(E.Text({ Format = "AMOUNT", ShowPartials = false }, partial), "900", "E: ...off by default")
local over = { kind = "HealDone", heal = true, amount = 1730, spellName = "Flash Heal", overheal = 200 }
EQ(E.Text({ Format = "AMOUNT", ShowPartials = true }, over), "1,730 (200 over)", "E: overheal partial")
local kill = { kind = "DamageDone", damage = true, amount = 500, spellName = "Fireball", overkill = 100 }
EQ(E.Text({ Format = "AMOUNT", ShowPartials = true }, kill), "500 (overkill)", "E: overkill partial")

local merged = { kind = "DamageDone", damage = true, amount = 3600, spellName = "Arcane Explosion", count = 4 }
EQ(E.Text({ Format = "AMOUNT_SPELL" }, merged), "3,600 Arcane Explosion x4", "E: a merged entry carries its count")
local petHit = { kind = "PetDamage", damage = true, amount = 310, spellName = "Claw", pet = true }
EQ(E.Text({ Format = "AMOUNT_SPELL" }, petHit), "Pet: 310 Claw", "E: a pet hit is tagged")
EQ(E.Text({ Format = "AMOUNT_SPELL" }, petHit, "SEPARATED", false), "310 Claw", "E: ...unless the tag is off")

local miss = { kind = "MissDone", missType = "RESIST", spellName = "Frostbolt", target = "Gankmage" }
EQ(E.Text({ Format = "AMOUNT" }, miss), "Resist", "E: a miss is its word")
EQ(E.Text({ Format = "AMOUNT_SPELL" }, miss), "Resist Frostbolt", "E: ...with the spell")
EQ(E.Text({ Format = "SPELL_AMOUNT" }, miss), "Frostbolt Resist", "E: ...spell first")
EQ(E.Text({ Format = "FULL" }, miss), "Frostbolt Resist on Gankmage", "E: ...full")
local dodge = { kind = "MissTaken", missType = "DODGE", spellName = "Melee", source = "Bonecrush" }
EQ(E.Text({ Format = "AMOUNT" }, dodge), "Dodge", "E: a dodge on you")
local absorbMiss = { kind = "MissTaken", missType = "ABSORB", spellName = "Shield Bash", amount = 120 }
EQ(E.Text({ Format = "AMOUNT", ShowPartials = true }, absorbMiss), "Absorb (120)", "E: an absorbed miss shows the amount with partials on")
EQ(E.Text({ Format = "AMOUNT" }, { kind = "MissDone", missType = "WEIRD" }), "Weird", "E: an unknown miss type is capitalised")

local shield = { kind = "AbsorbTaken", amount = 402, spellName = "Power Word: Shield", attack = "Sinister Strike" }
main, sub = E.Text({ Format = "AMOUNT" }, shield)
EQ(main, "402 absorbed", "E: a shield line")
EQ(sub, "Sinister Strike", "E: ...says what it ate")
EQ(E.Text({ Format = "AMOUNT_SPELL" }, shield), "402 absorbed (Power Word: Shield)", "E: ...and names the shield when asked")

local mana = { kind = "Energize", amount = 240, spellName = "Judgement of Wisdom", powerType = 0 }
EQ(E.Text({ Format = "AMOUNT" }, mana), "+240 Mana", "E: energize")
EQ(E.Text({ Format = "AMOUNT_SPELL" }, mana), "+240 Mana (Judgement of Wisdom)", "E: ...with its source spell")
EQ(E.Text({ Format = "AMOUNT" }, { kind = "Energize", amount = 10, powerType = 1 }), "+10 Rage", "E: rage")

main, sub = E.Text({ Format = "FULL" }, { kind = "KillingBlow", target = "Gankmage" })
EQ(main, "Killing Blow: Gankmage", "E: killing blow")
EQ(E.Text({ Format = "AMOUNT" }, { kind = "KillingBlow" }), "Killing Blow", "E: ...unnamed")
main, sub = E.Text({ Format = "FULL" }, { kind = "Interrupt", spellName = "Polymorph", target = "Gankmage" })
CHECK(main == "Interrupted Polymorph" and sub == "Gankmage", "E: interrupt")
EQ(E.Text({}, { kind = "Dispel", spellName = "Renew" }), "Dispelled Renew", "E: dispel")
EQ(E.Text({}, { kind = "Dispel", spellName = "Inner Fire", stolen = true }), "Stole Inner Fire", "E: steal")
EQ(E.Text({}, { kind = "ProcReady", spellName = "Overpower" }), "Overpower ready", "E: proc")
EQ(E.Text({}, { kind = "HonorGained", amount = 15 }), "+15 Honor", "E: honor")
EQ(E.Text({}, { kind = "HonorGained", amount = 45, count = 3 }), "+45 Honor x3", "E: merged honor")
EQ(E.Text({}, { kind = "CombatState", entering = true }), "Entering combat", "E: entering")
EQ(E.Text({}, { kind = "CombatState", entering = false }), "Leaving combat", "E: leaving")
EQ(E.Text({}, { kind = "BuffGained", spellName = "Inner Fire" }), "+ Inner Fire", "E: buff gained")
EQ(E.Text({}, { kind = "BuffFaded", spellName = "Inner Fire" }), "- Inner Fire", "E: buff faded")
main, sub = E.Text({}, { kind = "DebuffGained", spellName = "Polymorph", source = "Gankmage" })
CHECK(main == "Polymorph" and sub == "Gankmage", "E: debuff gained names the caster below")

-- ===========================================================================
-- F: lanes
-- ===========================================================================
local cfg = { Motion = "SCROLL", Direction = "UP", Duration = 2, Speed = 100, Spread = 20, Merge = 0, MaxLines = 3 }
local L = E.NewLane("Out")
local e1 = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "DamageDone|Fireball" }, 10, cfg)
CHECK(e1 and #L.entries == 1, "F: a spawn lands")
NEAR(e1.jitter, 10, "F: scatter is random within Spread (0.75 -> +10 of 20)")
EQ(e1.stagger, 0, "F: the first has no stagger")
local e2 = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "DamageDone|Fireball" }, 10.1, cfg)
EQ(e2.stagger, 1, "F: a second within the window is staggered")
local e3 = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "DamageDone|Frostbolt" }, 10.2, cfg)
EQ(e3.stagger, 2, "F: ...and a third further")
EQ(#L.entries, 3, "F: three in flight")
local e4 = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "x" }, 11, cfg)
EQ(#L.entries, 3, "F: MaxLines holds at three")
CHECK(L.entries[1] ~= e1, "F: ...the oldest went")
EQ(e4.stagger, 0, "F: a spawn outside the window restarts the stagger")

-- merge
cfg.Merge = 1.0
cfg.MaxLines = 10
L = E.NewLane("Out")
local m1 = E.Spawn(L, { kind = "DamageDone", amount = 900, spellName = "Arcane Explosion", mergeKey = "DamageDone|Arcane Explosion" }, 20, cfg)
local m2, merged2 = E.Spawn(L, { kind = "DamageDone", amount = 800, crit = true, spellName = "Arcane Explosion", mergeKey = "DamageDone|Arcane Explosion" }, 20.3, cfg)
CHECK(merged2 and m2 == m1, "F: the same spell inside the window merges")
EQ(m1.rec.amount, 1700, "F: ...summing the amount")
EQ(m1.rec.count, 2, "F: ...counting")
CHECK(m1.rec.crit == true, "F: ...a crit among them marks the merged entry")
EQ(m1.punchAt, 20.3, "F: ...and punches")
local m3, merged3 = E.Spawn(L, { kind = "DamageDone", amount = 700, spellName = "Arcane Explosion", mergeKey = "DamageDone|Arcane Explosion" }, 21.5, cfg)
CHECK(not merged3 and m3 ~= m1, "F: outside the window it is a new entry")
local m4, merged4 = E.Spawn(L, { kind = "DamageDone", amount = 700, spellName = "Fireball", mergeKey = "DamageDone|Fireball" }, 21.6, cfg)
CHECK(not merged4, "F: a different spell never merges")
local m5, merged5 = E.Spawn(L, { kind = "KillingBlow" }, 21.7, cfg)
CHECK(not merged5 and #L.entries == 4, "F: a record with no merge key is always new")

-- side alternates for fountains
cfg = { Motion = "FOUNTAIN", Side = "ALTERNATE", Duration = 2, Speed = 100, Spread = 0, MaxLines = 10 }
L = E.NewLane("Out")
local f1 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 30, cfg)
local f2 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 31, cfg)
CHECK(f1.side ~= f2.side, "F: fountain sides alternate")
cfg.Side = "LEFT"
local f3 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 32, cfg)
local f4 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 33, cfg)
CHECK(f3.side == -1 and f4.side == -1, "F: LEFT is always left")

-- ===========================================================================
-- G: motion
-- ===========================================================================
cfg = { Motion = "SCROLL", Direction = "UP", Duration = 2, Speed = 100, Spread = 0, Merge = 0, MaxLines = 10, CritScale = 1.5 }
L = E.NewLane("Out")
E.random = function() return 0.5 end
local s1 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 40, cfg)
E.Step(L, 40, cfg, 20)
NEAR(s1.y, 0, "G: scroll starts at the anchor")
NEAR(s1.alpha, 0, "G: ...fading in")
E.Step(L, 40.5, cfg, 20)
NEAR(s1.y, 50, "G: scroll: 100px/s up for half a second")
NEAR(s1.alpha, 1, "G: ...fully visible")
NEAR(s1.scale, 1, "G: ...a plain hit at scale 1")
local s2 = E.Spawn(L, { kind = "DamageDone", amount = 1, crit = true }, 40.6, cfg)
E.Step(L, 40.6, cfg, 20)
NEAR(s2.y, 0, "G: a second outside the stagger window starts at the anchor")
CHECK(s2.scale > 1.5, "G: a crit punches in above its scale", s2.scale)
E.Step(L, 40.8, cfg, 20)
NEAR(s2.scale, 1.5, "G: ...and settles at CritScale")
local s3 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 40.85, cfg)
E.Step(L, 40.85, cfg, 20)
NEAR(s3.y, -20, "G: a third inside the window sits one line behind the second")
E.Step(L, 41.7, cfg, 20)
CHECK(s1.alpha < 1 and s1.alpha > 0, "G: fading out at the end", s1.alpha)
EQ(E.Step(L, 42.01, cfg, 20), 2, "G: the first expires at Duration")
E.Step(L, 43, cfg, 20)
EQ(#L.entries, 0, "G: ...then the others")

cfg.Direction = "DOWN"
L = E.NewLane("In")
local d1 = E.Spawn(L, { kind = "DamageTaken", amount = 1 }, 50, cfg)
E.Step(L, 50.5, cfg, 20)
NEAR(d1.y, -50, "G: DOWN scrolls down")

cfg = { Motion = "FOUNTAIN", Direction = "UP", Side = "RIGHT", Duration = 2, Speed = 100, Spread = 0, MaxLines = 10 }
L = E.NewLane("Out")
local a1 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 60, cfg)
E.Step(L, 60.25, cfg, 20)
local yEarly = a1.y
CHECK(a1.x > 0, "G: a right fountain moves right", a1.x)
CHECK(yEarly > 0, "G: ...and rises first", yEarly)
E.Step(L, 61.5, cfg, 20)
CHECK(a1.y < yEarly, "G: ...then falls", a1.y)
CHECK(a1.x > 100, "G: ...still travelling outward", a1.x)

cfg = { Motion = "POP", Direction = "DOWN", Duration = 2, Speed = 100, Spread = 0, MaxLines = 10 }
L = E.NewLane("Call")
local p1 = E.Spawn(L, { kind = "KillingBlow" }, 70, cfg)
E.Step(L, 70, cfg, 30)
CHECK(p1.scale > 1.3, "G: a pop punches in", p1.scale)
E.Step(L, 70.5, cfg, 30)
NEAR(p1.scale, 1, "G: ...and settles")
NEAR(p1.y, 0, "G: ...in place")
local p2 = E.Spawn(L, { kind = "Interrupt" }, 70.6, cfg)
E.Step(L, 70.6, cfg, 30)
NEAR(p2.y, 0, "G: a second pop outside the window takes the anchor")
local p2b = E.Spawn(L, { kind = "Interrupt" }, 70.7, cfg)
E.Step(L, 70.7, cfg, 30)
NEAR(p2b.y, -30, "G: a second pop inside the window sits one line below (DOWN)")
cfg.Direction = "UP"
local p3 = E.Spawn(L, { kind = "Interrupt" }, 70.8, cfg)
E.Step(L, 70.8, cfg, 30)
NEAR(p3.y, 60, "G: ...or above (UP), two lines for the third")

cfg = { Motion = "STACK", Direction = "DOWN", Duration = 6, SlideIn = 40, Spread = 0, MaxLines = 10, Merge = 2 }
L = E.NewLane("Log")
local r1 = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "a" }, 80, cfg)
E.Step(L, 80, cfg, 30)
NEAR(r1.x, -40, "G: a stack row starts slid out")
NEAR(r1.y, 0, "G: ...in the top slot")
E.Step(L, 80.3, cfg, 30)
NEAR(r1.x, 0, "G: ...and slides in")
E.Step(L, 80.98, cfg, 30)
local r2 = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "b" }, 81, cfg)
E.Step(L, 81, cfg, 30)
NEAR(r2.y, 0, "G: the newest takes the top slot")
CHECK(r1.y < 0 and r1.y > -30, "G: ...the older is shoving down, not teleporting", r1.y)
for t = 81.05, 82, 0.05 do E.Step(L, t, cfg, 30) end
NEAR(r1.y, -30, "G: ...and arrives one row down", 0.5)
local r3, merged = E.Spawn(L, { kind = "DamageDone", amount = 100, mergeKey = "a" }, 81.5, cfg)
CHECK(merged and r3 == r1, "G: a merge in a stack lane")
EQ(r1.born, 81.5, "G: ...restarts its linger")
for t = 81.5, 82.5, 0.05 do E.Step(L, t, cfg, 30) end
NEAR(r1.y, 0, "G: ...and brings it back to the top", 0.5)
EQ(r1.rec.count, 2, "G: ...with a count")
cfg.Direction = "UP"
L = E.NewLane("Log")
local u1 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 90, cfg)
local u2 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 91, cfg)
for t = 91, 92, 0.05 do E.Step(L, t, cfg, 30) end
CHECK(u2.y == 0 and u1.y > 29, "G: UP grows upward: newest at the anchor, older above", u1.y)
E.Step(L, 98, cfg, 30)
EQ(#L.entries, 0, "G: stack rows expire at Duration")

EQ(E.LineHeight({ FontSize = 16, Motion = "SCROLL" }), 20, "G: a scroll line is 1.25x the size")
CHECK(E.LineHeight({ FontSize = 13, Motion = "STACK", Sub = true, Icon = "LEFT", IconSize = 16 }) > 30, "G: a ledger row is taller: two lines and padding")
CHECK(E.LineHeight({ FontSize = 10, Motion = "STACK", Sub = false, Icon = "LEFT", IconSize = 40 }) == 48, "G: ...never shorter than its icon")

-- a big dt is clamped so a hitch does not fling the stack
L = E.NewLane("Log")
local h1 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 100, cfg)
E.Step(L, 100, cfg, 30)
local h2 = E.Spawn(L, { kind = "DamageDone", amount = 1 }, 100.1, cfg)
E.Step(L, 103, cfg, 30)
CHECK(h1.y > 0 and h1.y <= 30, "G: a three-second hitch still moves the row at most one step", h1.y)

-- ===========================================================================
-- H: the volley
-- ===========================================================================
local volley = E.TestVolley()
CHECK(#volley >= 20, "H: the volley is a real few seconds", #volley)
local seenKind, seenLane = {}, {}
local defaults = {}
for _, kind in ipairs(DATA.KINDS) do
    defaults[kind.key .. "Lane"] = kind.lane
    defaults[kind.key .. "Ledger"] = kind.ledger
end
local last = -1
for _, shot in ipairs(volley) do
    CHECK(shot.at >= last, "H: the volley is in time order")
    last = shot.at
    CHECK(DATA.KIND_BY_KEY[shot.rec.kind] ~= nil, "H: every shot is a known kind", shot.rec.kind)
    seenKind[shot.rec.kind] = true
    local laneKey, ledger = E.Route(defaults, shot.rec)
    if laneKey then seenLane[laneKey] = true end
    if ledger then seenLane.Log = true end
    local ok, err = pcall(E.Text, { Format = "FULL", ShowPartials = true }, shot.rec, "SEPARATED")
    CHECK(ok, "H: every shot has text", err)
    ok, err = pcall(E.Color, { ColorMode = "SCHOOL" }, shot.rec)
    CHECK(ok, "H: every shot has a colour", err)
end
for _, lane in ipairs(DATA.LANES) do
    CHECK(seenLane[lane.key], "H: the volley reaches the " .. lane.title .. " lane under the default routing")
end
for _, kind in ipairs(DATA.KINDS) do
    if kind.key ~= "BuffFaded" and kind.key ~= "CombatState" then
        CHECK(seenKind[kind.key], "H: the volley shows a " .. kind.label)
    end
end

-- Every kind's default lane is a real lane or OFF, every default sound a
-- real sound, every colour option a real key
for _, kind in ipairs(DATA.KINDS) do
    CHECK(kind.lane == "OFF" or DATA.LANE_BY_KEY[kind.lane] ~= nil, "H: " .. kind.key .. " defaults to a real lane", kind.lane)
    CHECK(kind.sound == nil or (function()
        for _, slot in ipairs(DATA.SOUND_SLOTS) do if slot.key == kind.sound then return true end end
    end)(), "H: " .. kind.key .. " names a real sound slot", kind.sound)
end
for _, slot in ipairs(DATA.SOUND_SLOTS) do
    CHECK(DATA.SOUND_BY_KEY[slot.default] ~= nil, "H: sound slot " .. slot.key .. " defaults to a real sound")
end
for _, lane in ipairs(DATA.LANES) do
    local okMotion
    for _, m in ipairs(DATA.MOTIONS) do if m.value == lane.motion then okMotion = true end end
    CHECK(okMotion, "H: lane " .. lane.key .. " defaults to a real motion")
    CHECK(DATA.FONTS[DATA.LANE_DEFAULTS.Font] ~= nil, "H: the default face exists")
end

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
