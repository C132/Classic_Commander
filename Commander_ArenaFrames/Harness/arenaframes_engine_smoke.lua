-- Commander Arena Frames engine smoke (luajit). No WoW mock is needed or
-- wanted: everything under test is a pure function of what it was told and
-- what time it is, which is the reason the engine was split out at all.
--
--   luajit Commander_ArenaFrames/Harness/arenaframes_engine_smoke.lua
--
-- Sections:
--   A  the generated DR table -- the spells an arena actually turns on
--   B  the ladder, including the reset clock everyone gets wrong
--   C  overlapping CC from two enemies (the frozen clock)
--   D  duration prediction under the 10s PvP cap
--   E  the enemy cooldown ledger, and unseen-vs-ready
--   F  specialization by revelation
--   G  aura meaning and formatting

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
local function NEAR(got, want, label, tol)
    CHECK(type(got) == "number" and math.abs(got - want) <= (tol or 0.001), label,
          string.format("got %s want %s", tostring(got), tostring(want)))
end

assert(loadfile(ADDONS .. "/Commander_ArenaFrames/CommanderArenaFramesData.lua"))()
assert(loadfile(ADDONS .. "/Commander_ArenaFrames/CommanderArenaFramesEngine.lua"))()
local DATA, E = CommanderArenaFrames_Data, CommanderArenaFrames_Engine

-- === A: the generated table, on the spells a TBC arena is decided by ========
-- Each of these is a claim about the RULES, not about the data pipeline: if a
-- regeneration ever moves one of them, the change is a behavioural one and
-- should have to be argued for here.
local CAT = {
    -- Kidney Shot has its OWN ladder in TBC. A rogue opening Cheap Shot into a
    -- full-duration Kidney is the single most important thing on this list.
    [1833]  = "STUN",       -- Cheap Shot
    [408]   = "KIDNEY",     -- Kidney Shot
    [853]   = "STUN",       -- Hammer of Justice
    [7922]  = "STUN",       -- Charge Stun: triggered by a SPELL, so an ordinary stun
    [20253] = "STUN",       -- Intercept Stun, same
    [12355] = "STUN_PROC",  -- Impact: triggered by an AURA, so its own ladder
    [5530]  = "STUN_PROC",  -- Mace Stun Effect
    [15269] = "STUN_PROC",  -- Blackout
    [2094]  = "BLIND",      -- Blind and Cyclone share one
    [33786] = "BLIND",      -- Cyclone
    [118]   = "POLY",       -- Polymorph, Gouge, Sap and Repentance share one
    [1776]  = "POLY",       -- Gouge
    [6770]  = "POLY",       -- Sap
    [20066] = "POLY",       -- Repentance
    [22570] = "POLY",       -- Maim
    [5782]  = "FEAR",
    [8122]  = "FEAR",       -- Psychic Scream
    [5484]  = "FEAR",       -- Howl of Terror
    [5246]  = "FEAR",       -- Intimidating Shout
    [6358]  = "FEAR",       -- Seduction
    [10326] = "FEAR",       -- Turn Evil
    [3355]  = "FREEZE",     -- Freezing Trap Effect: NOT the Polymorph ladder
    [122]   = "ROOT",       -- Frost Nova
    [339]   = "ROOT",       -- Entangling Roots
    [19970] = "ROOT",       -- Nature's Grasp's root: the server routes it to CAST root
    [12494] = "ROOT_PROC",  -- Frostbite: its own ladder
    [19185] = "ROOT_PROC",  -- Entrapment
    [23694] = "ROOT_PROC",  -- Improved Hamstring
    [2637]  = "SLEEP",      -- Hibernate
    [19386] = "SLEEP",      -- Wyvern Sting
    [710]   = "BANISH",
    [6789]  = "HORROR",     -- Death Coil
    [676]   = "DISARM",
    [605]   = "CHARM",      -- Mind Control
    [31661] = "DRAGONS",    -- Dragon's Breath
    [1715]  = "LIMIT",      -- Hamstring: capped, never laddered
}
for id, want in pairs(CAT) do
    EQ(E.Category(id), want, "A: category of " .. id)
end

-- And the ones that must NOT diminish in TBC. Silence DR is a 3.0.8 feature;
-- a board that brackets Counterspell is telling an arena player something
-- false about the next kick.
for _, id in ipairs({ 18469, 1330, 15487, 34490, 24259, 19503, 1831, 11113 }) do
    EQ(E.Category(id), nil, "A: no DR for " .. id)
end
-- Blast Wave shares Dragon's Breath's family bit in the client's own data; if
-- the generator ever stops filtering on the disorient, this catches it.
EQ(E.Category(33933), nil, "A: Blast Wave is not Dragon's Breath")

-- === B: the ladder and the reset clock =====================================
local dr = E.NewDR()
local G = "Player-Enemy-1"

EQ(dr:Bracket(G, "STUN", 100), 1, "B: untouched category is full")

-- A 6s Cheap Shot at t=100.
EQ(dr:Applied(G, 1833, 100), "STUN", "B: apply returns the category")
EQ(dr:Bracket(G, "STUN", 100), 2, "B: after one stun the next is half")
EQ(dr:Held(G, "STUN"), true, "B: held while the stun is on them")
EQ(dr:ResetAt(G, "STUN", 100), nil, "B: the clock does not run while it is held")

dr:Faded(G, 1833, 106)
EQ(dr:Held(G, "STUN"), false, "B: not held once it fades")
NEAR(dr:ResetAt(G, "STUN", 106), 121, "B: reset is 15s after the FADE, not the apply")
EQ(dr:Bracket(G, "STUN", 120), 2, "B: still half one second before the reset")
EQ(dr:Bracket(G, "STUN", 122), 1, "B: full again after it")

-- The mistake this whole section exists for: stamping the APPLY would have put
-- the category back to full at t=115, six seconds early -- while the enemy was
-- still stunned for part of it.
EQ(dr:Bracket(G, "STUN", 116), 2, "B: an apply-stamped clock would be full here")

-- Down the ladder, and immune at the fourth.
local dr2 = E.NewDR()
dr2:Applied(G, 1833, 0);  dr2:Faded(G, 1833, 1)
EQ(dr2:Bracket(G, "STUN", 2), 2, "B: 1 -> half")
dr2:Applied(G, 853, 2);   dr2:Faded(G, 853, 3)
EQ(dr2:Bracket(G, "STUN", 4), 3, "B: 2 -> quarter")
dr2:Applied(G, 853, 4);   dr2:Faded(G, 853, 5)
EQ(dr2:Bracket(G, "STUN", 6), 4, "B: 3 -> immune")
dr2:Applied(G, 853, 6);   dr2:Faded(G, 853, 7)
EQ(dr2:Bracket(G, "STUN", 8), 4, "B: a fourth does not overflow past immune")
NEAR(dr2:Multiplier(G, "STUN", 8), 0, "B: immune is a zero multiplier")
EQ(dr2:Bracket(G, "STUN", 23), 1, "B: 15s after the last fade it is full again")

-- Categories are independent: Kidney Shot must not ride the stun ladder.
local dr3 = E.NewDR()
dr3:Applied(G, 1833, 0)      -- Cheap Shot
EQ(dr3:Bracket(G, "STUN", 0), 2, "B: the stun ladder moved")
EQ(dr3:Bracket(G, "KIDNEY", 0), 1, "B: Kidney Shot's own ladder did not")

-- === C: two enemies, one category ==========================================
-- A double-stun overlapping means the clock cannot start when the first drops.
local dr4 = E.NewDR()
dr4:Applied(G, 1833, 0)      -- rogue stuns
dr4:Applied(G, 853, 2)       -- paladin stuns on top
EQ(dr4:Bracket(G, "STUN", 2), 3, "C: two applications, two rungs")
dr4:Faded(G, 1833, 6)        -- the first one ends
EQ(dr4:Held(G, "STUN"), true, "C: still held by the second")
EQ(dr4:ResetAt(G, "STUN", 6), nil, "C: and so the clock is still frozen")
EQ(dr4:Bracket(G, "STUN", 22), 3, "C: 15s past the FIRST fade changes nothing")
dr4:Faded(G, 853, 22)
NEAR(dr4:ResetAt(G, "STUN", 22), 37, "C: the clock starts when the LAST one goes")

-- === D: how long would the next one last ===================================
local dr5 = E.NewDR()
-- Polymorph's own duration is 50s; on a player it is capped to 10 first.
local d, cat, bracket = E.PredictDuration(dr5, G, 118, 50, 0)
NEAR(d, 10, "D: first Polymorph is the 10s PvP cap, not 50s")
EQ(cat, "POLY", "D: category comes back with it")
EQ(bracket, 1, "D: at full")
dr5:Applied(G, 118, 0); dr5:Faded(G, 118, 10)
NEAR((E.PredictDuration(dr5, G, 118, 50, 10)), 5, "D: second is half of the CAP, not of 50")
dr5:Applied(G, 118, 10); dr5:Faded(G, 118, 15)
NEAR((E.PredictDuration(dr5, G, 118, 50, 15)), 2.5, "D: third is a quarter")
dr5:Applied(G, 118, 15); dr5:Faded(G, 118, 17)
NEAR((E.PredictDuration(dr5, G, 118, 50, 17)), 0, "D: fourth is immune")
-- Fear is 20s in the book and caps the same way, which is the point of the cap
-- coming first: two different spells, one answer.
local dr6 = E.NewDR()
NEAR((E.PredictDuration(dr6, G, 5782, 20, 0)), 10, "D: Fear caps at 10 as well")
-- Hamstring is capped and never laddered.
local dr7 = E.NewDR()
dr7:Applied(G, 1715, 0); dr7:Faded(G, 1715, 5)
local hd, hcat, hbr = E.PredictDuration(dr7, G, 1715, 15, 5)
NEAR(hd, 10, "D: Hamstring keeps the cap after a second one")
EQ(hcat, "LIMIT", "D: and says which rule it is under")
EQ(hbr, 1, "D: with no bracket")

-- The cap is not universal. The server's limited-duration list leaves out
-- DISARM and DEATHCOIL, so a 10s Disarm stays 10s and a long one stays long.
local dr9 = E.NewDR()
NEAR((E.PredictDuration(dr9, G, 676, 10, 0)), 10, "D: a Disarm is not capped")
dr9:Applied(G, 676, 0); dr9:Faded(G, 676, 10)
NEAR((E.PredictDuration(dr9, G, 676, 10, 10)), 5, "D: but it does still ladder")

-- === E: the cooldown ledger ================================================
local book = E.NewBook()
local H = "Player-Enemy-2"
local left, unseen = book:Remaining(H, "Ice Block", 0)
EQ(left, nil, "E: never seen has no timer")
EQ(unseen, true, "E: and is reported as unseen, not ready")

local used = book:Used(H, "MAGE", "Gnome", 45438, "Ice Block", 100)
CHECK(used and used.name == "Ice Block", "E: Ice Block recorded")
NEAR(used.cd, 300, "E: with the client's own 300s cooldown")
NEAR((book:Remaining(H, "Ice Block", 130)), 270, "E: counting down")
left, unseen = book:Remaining(H, "Ice Block", 401)
EQ(left, nil, "E: ready once it elapses")
EQ(unseen, false, "E: and no longer unseen")

-- An unlisted rank still resolves, by name.
local byName = book:Used(H, "MAGE", "Gnome", 999999, "Ice Block", 500)
CHECK(byName and byName.id == 45438, "E: an unknown rank id resolves by name")

-- One press reaches the log twice -- SPELL_CAST_SUCCESS, then the
-- SPELL_AURA_APPLIED that follows it -- and a caller that announces on every
-- stamp says it twice in party chat. The ledger records both and reports only
-- the first as fresh.
local dedupe = E.NewBook()
local D = "Player-Enemy-3"
local _, fresh1 = dedupe:Used(D, "MAGE", nil, 45438, "Ice Block", 1000)
EQ(fresh1, true, "E: the first stamp is fresh")
local _, fresh2 = dedupe:Used(D, "MAGE", nil, 45438, "Ice Block", 1000.2)
EQ(fresh2, false, "E: the same press arriving again is not")
local _, fresh3 = dedupe:Used(D, "MAGE", nil, 45438, "Ice Block", 1002)
EQ(fresh3, true, "E: a genuinely later press is fresh again")
-- The ledger itself is unaffected either way: the second write is identical.
NEAR((dedupe:Remaining(D, "Ice Block", 1002)), 300, "E: the timer restarts from the last stamp")

-- A name two classes share must not cross over.
local shaman = E.BookEntry("SHAMAN", nil, nil, "Nature's Swiftness")
local druid  = E.BookEntry("DRUID",  nil, nil, "Nature's Swiftness")
CHECK(shaman and druid and shaman.id ~= druid.id,
      "E: the shaman's and the druid's Nature's Swiftness are different spells")

-- A racial is scoped by race, not class.
CHECK(E.BookEntry("MAGE", "Gnome", nil, "Escape Artist"), "E: gnome racial resolves")
EQ(E.BookEntry("MAGE", "Orc", nil, "Escape Artist"), nil, "E: an orc has no Escape Artist")

-- The strip is in book order and covers class + racials.
local strip = book:Strip(H, "MAGE", "Gnome", 100)
CHECK(#strip > 5, "E: the mage strip has entries", #strip)
EQ(strip[1].name, "Ice Block", "E: book order is stable")
local sawRacial = false
for _, row in ipairs(strip) do
    if row.name == "Escape Artist" then sawRacial = true end
end
CHECK(sawRacial, "E: racials ride the same strip")

-- === F: specialization by revelation =======================================
EQ(E.SpecFromSpell("WARRIOR", 12294), "Arms", "F: Mortal Strike proves Arms")
EQ(E.SpecFromSpell("WARRIOR", 23881), "Fury", "F: Bloodthirst proves Fury")
EQ(E.SpecFromSpell("PRIEST", 33206), "Disc", "F: Pain Suppression proves Discipline")
EQ(E.SpecFromSpell("DRUID", 33763), "Resto", "F: Lifebloom proves Restoration")
EQ(E.SpecFromSpell("MAGE", 12294), nil, "F: a marker is scoped to its class")
EQ(E.SpecFromSpell("ROGUE", 8676), nil, "F: an ordinary spell proves nothing")

-- === G: aura meaning and formatting ========================================
CHECK(E.ImmunityNote(45438), "G: Ice Block reads as an immunity")
CHECK(E.ImmunityNote(1020), "G: Divine Shield reads as an immunity")
EQ(E.ImmunityNote(871), nil, "G: Shield Wall is a wall, not an immunity")
EQ(E.AuraNote(871).kind, "WALL", "G: and says so")
EQ(E.AuraNote(23920).kind, "REFLECT", "G: Spell Reflection is its own answer")
EQ(E.AuraNote(1784).kind, "STEALTH", "G: Stealth keeps the slot")
CHECK(E.IsDrink(430), "G: drinking is recognised")
CHECK(not E.IsDrink(45438), "G: and nothing else is")

EQ(E.IsControlAura(1833), true,  "G: a stun is control")
EQ(E.IsControlAura(118),  true,  "G: a polymorph is control")
EQ(E.IsControlAura(3355), true,  "G: a freezing trap is control")
EQ(E.IsControlAura(122),  false, "G: a root is not -- they are still casting")
EQ(E.IsControlAura(676),  false, "G: nor is a disarm")
EQ(E.IsControlAura(1715), false, "G: nor is a hamstring")

EQ(E.FormatTime(nil), "", "G: no time is no text")
EQ(E.FormatTime(0), "", "G: nor is zero")
EQ(E.FormatTime(4.25), "4.2", "G: under ten keeps a decimal")
EQ(E.FormatTime(28.4), "28", "G: over ten does not")
EQ(E.FormatTime(300), "5:00", "G: over a minute is clock time")
EQ(E.FormatTime(65), "1:05", "G: with a padded second")
EQ(E.FormatSlotTime(4.25), "4.2", "G: on a slot, under a minute is the wide form")
EQ(E.FormatSlotTime(176), "3m", "G: past a minute a slot rounds up to minutes")
EQ(E.FormatSlotTime(60), "1m", "G: exactly a minute is one minute")
EQ(E.FormatSlotTime(354 * 60 + 28), "6h", "G: past an hour, hours")

-- === Open(): what a board would actually draw ==============================
local dr8 = E.NewDR()
dr8:Applied(G, 1833, 0)             -- stun ladder to half
dr8:Applied(G, 118, 0)              -- poly ladder to half, still on them
dr8:Faded(G, 1833, 6)
local open = dr8:Open(G, 7)
EQ(#open, 2, "H: two open categories")
local byCat = {}
for _, row in ipairs(open) do byCat[row.cat] = row end
EQ(byCat.STUN.held, false, "H: the stun has faded")
EQ(byCat.POLY.held, true, "H: the polymorph has not")
EQ(byCat.POLY.resetAt, nil, "H: so its clock is not running")
NEAR(byCat.STUN.resetAt, 21, "H: the stun's is")

-- === I: control classification ============================================
--
-- The board's loudest element hangs off this, and the case that matters is
-- the one with no diminishing returns at all: TBC gives silence no ladder, so
-- a silence is in no DR group -- and a board that derives "are they
-- controlled" from the DR table alone never draws a locked-out healer, which
-- is the single most valuable thing it could say to a caster.
EQ(E.ControlKind(6770),  "FULL",    "I: a sap is full control")
EQ(E.ControlKind(118),   "FULL",    "I: so is a polymorph")
EQ(E.ControlKind(408),   "FULL",    "I: and a kidney shot")
EQ(E.ControlKind(2094),  "FULL",    "I: and a blind")
EQ(E.ControlKind(3355),  "FULL",    "I: and a freezing trap")
EQ(E.ControlKind(19503), "FULL",    "I: scatter shot has no DR, and is still control")
EQ(E.ControlKind(15487), "SILENCE", "I: a silence is its own kind")
EQ(E.ControlKind(24259), "SILENCE", "I: spell lock too")
EQ(E.ControlKind(1330),  "SILENCE", "I: and garrote's")
EQ(E.Category(15487),    nil,       "I: ...and none of them carries a DR category")
EQ(E.ControlKind(122),   "ROOT",    "I: a root is control, of a lesser kind")
EQ(E.ControlKind(676),   "DISARM",  "I: so is a disarm")
EQ(E.ControlKind(1715),  nil,       "I: a hamstring is not control at all")
EQ(E.ControlKind(133),   nil,       "I: nor is a fireball")

-- Worst first, and the board shows exactly one per enemy.
EQ(E.ControlRank("FULL") < E.ControlRank("SILENCE"), true,
   "I: a sap outranks a silence")
EQ(E.ControlRank("SILENCE") < E.ControlRank("ROOT"), true,
   "I: a silence outranks a root")
EQ(E.ControlRank(nil) > E.ControlRank("DISARM"), true,
   "I: and nothing outranks nothing")

-- The word is what a player would say mid-fight, not the category key.
EQ(E.ControlWord(6770,  "FULL"),    "INCAP",    "I: a sap reads as an incap")
EQ(E.ControlWord(5782,  "FULL"),    "FEARED",   "I: a fear reads as feared")
EQ(E.ControlWord(408,   "FULL"),    "STUNNED",  "I: a kidney reads as stunned")
EQ(E.ControlWord(3355,  "FULL"),    "TRAPPED",  "I: a trap reads as trapped")
EQ(E.ControlWord(15487, "SILENCE"), "SILENCED", "I: a silence has no category to name it")

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
