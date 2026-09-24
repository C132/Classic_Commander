-- Commander Diminish engine smoke (luajit). No WoW mock is needed or wanted:
-- everything under test is a pure function of what it was told and what time
-- it is, which is the reason the engine was split out at all.
--
--   luajit Commander_Diminish/Harness/diminish_engine_smoke.lua
--
-- Sections:
--   A  the generated table agrees with Commander Arena Frames' copy
--   B  the categories TBC players get wrong
--   C  the ladder, and the reset clock that starts on the FADE
--   D  two enemies, one category: the frozen clock
--   E  broken CC -- the subevent that fires INSTEAD of removed
--   F  the profile: which ladders THIS character can open
--   G  strips: order, the full-vs-open rule, and the off-profile exception
--   H  forgetting people (the battleground problem)
--   I  duration under the 10s cap, and formatting

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

assert(loadfile(ADDONS .. "/Commander_Diminish/CommanderDiminishData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Diminish/CommanderDiminishEngine.lua"))()
local DATA, E = CommanderDiminish_Data, CommanderDiminish_Engine

-- === A: the two copies of the generated table ==============================
-- This module carries its own copy so it keeps working with Arena Frames
-- disabled -- which is exactly what somebody does before a battleground. The
-- cost of a copy is drift, so the copy is diffed here: regenerate one and
-- forget the other and this fails, rather than a bracket being quietly wrong
-- in a game six weeks later.
do
    local ok = pcall(function()
        assert(loadfile(ADDONS .. "/Commander_ArenaFrames/CommanderArenaFramesData.lua"))()
    end)
    if not ok or not CommanderArenaFrames_Data then
        io.write("note  Commander_ArenaFrames not present -- table parity unchecked\n")
    else
        local theirs = CommanderArenaFrames_Data.DR_BY_SPELL
        local mine = DATA.DR_BY_SPELL
        local mineCount, theirsCount, mismatch = 0, 0, nil
        for id, cat in pairs(mine) do
            mineCount = mineCount + 1
            if theirs[id] ~= cat then mismatch = mismatch or ("id " .. id) end
        end
        for id in pairs(theirs) do
            theirsCount = theirsCount + 1
            if mine[id] == nil then mismatch = mismatch or ("missing id " .. id) end
        end
        EQ(mismatch, nil, "A1 DR table matches Commander Arena Frames")
        EQ(mineCount, theirsCount, "A2 same number of spells in both copies")

        local groupsMatch = #DATA.DR_GROUPS == #CommanderArenaFrames_Data.DR_GROUPS
        for i, group in ipairs(DATA.DR_GROUPS) do
            local other = CommanderArenaFrames_Data.DR_GROUPS[i]
            if not other or other.key ~= group.key then groupsMatch = false end
        end
        CHECK(groupsMatch, "A3 group list matches, in the same order")
    end
end

-- Every category must have a tint and a fallback icon, or the strip draws a
-- blank cell for it. A regenerated table that adds a group should fail here.
for _, group in ipairs(DATA.DR_GROUPS) do
    CHECK(DATA.CAT_TINT[group.key], "A4 tint for " .. group.key)
    CHECK(DATA.CAT_ICON[group.key], "A5 fallback icon for " .. group.key)
end

-- CAT_ICON is not only art. The test board stages fabricated ladders using
-- these ids as the representative spell of each category, so an id that does
-- not classify into its OWN category would stage the wrong ladder -- and, more
-- quietly, would draw a fallback icon that belongs to a different rule.
for cat, id in pairs(DATA.CAT_ICON) do
    EQ(E.Category(id), cat, "A6 " .. cat .. "'s fallback icon is a " .. cat .. " spell")
end

-- Knows() is what lets a caller keep its own per-GUID table in step without
-- reaching into the engine's.
do
    local dr = E.NewDR()
    EQ(dr:Knows("Player-nobody"), false, "A7 nothing known about a stranger")
    dr:Applied("Player-somebody", 1833, 10)
    EQ(dr:Knows("Player-somebody"), true, "A8 known once a ladder opens")
    dr:Clear("Player-somebody")
    EQ(dr:Knows("Player-somebody"), false, "A9 and forgotten on clear")
end

-- === B: the categories people get wrong ====================================
local CAT = {
    -- Kidney Shot has its OWN ladder in TBC: a rogue can Cheap Shot into a
    -- full-duration Kidney. The single most important entry in this list.
    [1833]  = "STUN",       -- Cheap Shot
    [408]   = "KIDNEY",     -- Kidney Shot
    [853]   = "STUN",       -- Hammer of Justice
    -- Charge and Intercept are triggered by a spell EFFECT rather than by an
    -- aura, so they are ordinary controlled stuns and share the stun ladder.
    [7922]  = "STUN",       -- Charge Stun
    [20253] = "STUN",       -- Intercept Stun
    -- Proc stuns ladder separately, so a mace warrior's random stun never eats
    -- the team's Hammer of Justice.
    [20170] = "STUN_PROC",  -- Seal of Justice stun
    [15269] = "STUN_PROC",  -- Blackout
    -- Freezing Trap is its own group, NOT the polymorph one.
    [3355]  = "FREEZE",     -- Freezing Trap Effect
    [118]   = "POLY",       -- Polymorph
    [1776]  = "POLY",       -- Gouge
    [6770]  = "POLY",       -- Sap
    -- Blind and Cyclone share one ladder.
    [2094]  = "BLIND",      -- Blind
    [33786] = "BLIND",      -- Cyclone
    [5782]  = "FEAR",       -- Fear
    [8122]  = "FEAR",       -- Psychic Scream
    [122]   = "ROOT",       -- Frost Nova
    [12494] = "ROOT_PROC",  -- Frostbite
    [6789]  = "HORROR",     -- Death Coil
    [676]   = "DISARM",     -- Disarm
    [605]   = "CHARM",      -- Mind Control
    [31661] = "DRAGONS",    -- Dragon's Breath
    [1715]  = "LIMIT",      -- Hamstring
    [710]   = "BANISH",     -- Banish
    [2637]  = "SLEEP",      -- Hibernate
}
for id, want in pairs(CAT) do
    EQ(E.Category(id), want, "B " .. id .. " is " .. want)
end

-- Silence has NO diminishing returns in TBC -- silence DR arrives in 3.0.8.
-- Nor does Scatter Shot. A tracker that shows a bracket for either is showing
-- a rule from a later expansion.
EQ(E.Category(15487), nil, "B Silence does not diminish in TBC")   -- Silence
EQ(E.Category(18469), nil, "B Improved Counterspell has no ladder")
EQ(E.Category(19503), nil, "B Scatter Shot does not diminish")

-- === C: the ladder and the reset clock =====================================
do
    local dr = E.NewDR()
    local guid = "Player-Enemy-1"
    EQ(dr:Bracket(guid, "STUN", 100), 1, "C1 untouched category is full")

    dr:Applied(guid, 1833, 100)                       -- Cheap Shot lands
    EQ(dr:Bracket(guid, "STUN", 100), 2, "C2 next stun is halved")
    -- Kidney is a different ladder, so it is still full mid-Cheap-Shot.
    EQ(dr:Bracket(guid, "KIDNEY", 100), 1, "C3 Kidney unaffected by Cheap Shot")

    dr:Faded(guid, 1833, 104)                         -- four-second stun ends
    -- The clock starts HERE, at the fade, not back at 100. This is the whole
    -- point: at t=116 an apply-stamped tracker says full and is wrong.
    EQ(dr:Bracket(guid, "STUN", 116), 2, "C4 still halved 16s after the APPLY")
    EQ(dr:Bracket(guid, "STUN", 118.9), 2, "C5 still halved just before reset")
    EQ(dr:Bracket(guid, "STUN", 119.1), 1, "C6 full again 15s after the FADE")
    NEAR(dr:ResetAt(guid, "STUN", 110), 119, "C7 reset is fade + 15")

    -- Down the whole ladder.
    local d2 = E.NewDR()
    d2:Applied(guid, 853, 200); d2:Faded(guid, 853, 201)
    EQ(d2:Bracket(guid, "STUN", 202), 2, "C8 second at half")
    d2:Applied(guid, 853, 202); d2:Faded(guid, 853, 203)
    EQ(d2:Bracket(guid, "STUN", 204), 3, "C9 third at quarter")
    d2:Applied(guid, 853, 204); d2:Faded(guid, 853, 205)
    EQ(d2:Bracket(guid, "STUN", 206), 4, "C10 fourth is immune")
    d2:Applied(guid, 853, 206); d2:Faded(guid, 853, 207)
    EQ(d2:Bracket(guid, "STUN", 208), 4, "C11 immune does not overflow")
    NEAR(d2:Multiplier(guid, "STUN", 208), 0, "C12 immune keeps nothing")
    NEAR(d2:Multiplier(guid, "STUN", 230), 1, "C13 full again after the reset")
end

-- === D: the frozen clock ===================================================
-- Two people stun the same target, overlapping. The clock must not start when
-- the FIRST one drops -- something in the category is still up.
do
    local dr = E.NewDR()
    local guid = "Player-Enemy-2"
    dr:Applied(guid, 1833, 100)          -- rogue's Cheap Shot
    dr:Applied(guid, 853, 102)           -- paladin's Hammer, overlapping
    dr:Faded(guid, 1833, 104)            -- the Cheap Shot ends; Hammer is still on
    EQ(dr:Held(guid, "STUN"), true, "D1 still held while the Hammer is up")
    EQ(dr:ResetAt(guid, "STUN", 105), nil, "D2 no reset time while held")
    EQ(dr:Bracket(guid, "STUN", 120), 3, "D3 the clock never ran -- still quarter")
    dr:Faded(guid, 853, 108)             -- now it is genuinely clear
    EQ(dr:Held(guid, "STUN"), false, "D4 clear once the last one drops")
    NEAR(dr:ResetAt(guid, "STUN", 109), 123, "D5 the clock starts at the LAST fade")
    EQ(dr:Bracket(guid, "STUN", 124), 1, "D6 full again 15s after that")
end

-- === E: CC broken by damage ================================================
-- SPELL_AURA_BROKEN fires INSTEAD of SPELL_AURA_REMOVED, and broken CC is the
-- NORMAL case. The engine takes both through Faded, so what is under test here
-- is that a break really does start the clock -- the failure mode is a bracket
-- stuck at half for the rest of the game.
do
    local dr = E.NewDR()
    local guid = "Player-Enemy-3"
    dr:Applied(guid, 118, 300)                        -- Polymorph lands
    dr:Faded(guid, 118, 301.5)                        -- broken by a stray dot
    EQ(dr:Held(guid, "POLY"), false, "E1 a broken poly is not still up")
    EQ(dr:Bracket(guid, "POLY", 310), 2, "E2 halved while the clock runs")
    EQ(dr:Bracket(guid, "POLY", 317), 1, "E3 and full 15s after the break")
end

-- === E2: a refresh is a new cast, not a second aura ========================
-- SPELL_AURA_REFRESH means the CC was re-cast on someone still under it. The
-- server counts that on the ladder -- but there is still only ONE aura, and
-- only ONE removal will ever arrive. Counting it as a second stack leaves the
-- category permanently one-deep: the clock never starts and it reads as held
-- for the rest of the game.
do
    local dr = E.NewDR()
    local guid = "Player-Enemy-6"
    dr:Applied(guid, 118, 400)                        -- sheep lands
    dr:Applied(guid, 118, 403, true)                  -- re-sheeped, still under it
    EQ(dr:Bracket(guid, "POLY", 403), 3, "E2a a refresh still walks the ladder")
    dr:Faded(guid, 118, 408)                          -- the one and only removal
    EQ(dr:Held(guid, "POLY"), false, "E2b one aura, one removal, stack back to zero")
    NEAR(dr:ResetAt(guid, "POLY", 409), 423, "E2c so the clock actually starts")
    EQ(dr:Bracket(guid, "POLY", 424), 1, "E2d and the category does reset")
end

-- === E3: checking the ladder against the server ============================
-- The ladder is inference; the duration the server put on the aura is not. A
-- 10-second polymorph landed at full, a 5-second one at half -- and where the
-- two disagree the reading has to win, or the tracker goes on being confidently
-- wrong for the rest of the game.
do
    E.ResetLearnedDurations()
    local dr = E.NewDR()
    local guid = "Player-Enemy-7"

    -- First sighting is taken as full, and teaches the spell's length.
    EQ(E.LevelFromDuration(118, 10), 1, "E3a a first 10s sheep reads as full")
    EQ(E.LearnedDuration(118), 10, "E3b and that is now the known full length")
    EQ(E.LevelFromDuration(118, 5), 2, "E3c half of it is the second rung")
    EQ(E.LevelFromDuration(118, 2.5), 3, "E3d and a quarter the third")

    -- A duration LONGER than what we thought was full means we learned from a
    -- CC that was already diminished. The longer one is the new full.
    E.ResetLearnedDurations()
    EQ(E.LevelFromDuration(118, 5), 1, "E3e first sighting is assumed full, even at 5s")
    EQ(E.LevelFromDuration(118, 10), 1, "E3f a longer one corrects the assumption")
    EQ(E.LearnedDuration(118), 10, "E3g ...")
    EQ(E.LevelFromDuration(118, 5), 2, "E3h and now 5s reads as half, correctly")

    -- The correction proper. The model believes the category is clean; the
    -- server hands the CC half duration, which means it was NOT clean.
    E.ResetLearnedDurations()
    E.NoteDuration(118, 10)
    dr:Applied(guid, 118, 500)                        -- model thinks: first sheep
    EQ(dr:Bracket(guid, "POLY", 500), 2, "E3i model predicts the next is half")
    local level, predicted, corrected = dr:Observe(guid, 118, 5, 500)
    EQ(level, 2, "E3j but it landed at HALF, so one landed before it")
    EQ(predicted, 1, "E3k the model had counted one cast")
    EQ(corrected, true, "E3l so the ladder is corrected")
    EQ(dr:Bracket(guid, "POLY", 500), 3, "E3m and the next one is a quarter, not a half")

    -- Agreement is silent.
    local _, _, changed = dr:Observe(guid, 118, 5, 500)
    EQ(changed, false, "E3n a reading that agrees corrects nothing")

    -- A spell with no ladder teaches nothing and corrects nothing.
    EQ(dr:Observe(guid, 15487, 5, 500), nil, "E3o silence has no ladder to correct")
end

-- === E4: an observation with no combat log behind it =======================
--
-- Observe CREATES ladder entries, and every other writer stamps the clock.
-- This one did not -- so a CC seen on someone whose SPELL_AURA_APPLIED never
-- reached us (sapped out of combat-log range, targeted mid-polymorph, zoned in
-- already under one) minted a row with `used` counted and `faded` nil. That
-- row could never expire, so the bracket stuck for the rest of the game, and
-- ResetAt walked into `nil + 15` and took the strip down with it -- from
-- inside a draw that runs every frame, so it threw six times before anyone
-- could read it.
--
-- This is the section that would have caught it: every other Observe test
-- above runs on a guid that Applied touched first.
do
    E.ResetLearnedDurations()
    local dr = E.NewDR()
    local guid = "Player-Unwitnessed"
    E.NoteDuration(118, 10)

    -- A half-length sheep on someone we never saw get sheeped. The observation
    -- is real information -- five seconds of a ten-second spell means one
    -- landed before it -- so it is recorded rather than discarded.
    local level, predicted, corrected, cat = dr:Observe(guid, 118, 5, 500, 505)
    EQ(level, 2, "E4a the aura reads as the second rung")
    EQ(predicted, 0, "E4b nothing had been counted for this person")
    EQ(corrected, true, "E4c so the ladder is opened from the reading alone")
    EQ(cat, "POLY", "E4d in the right category")
    EQ(dr:Bracket(guid, "POLY", 500), 3, "E4e and the next sheep is a quarter")

    -- The crash, exactly as it arrived: ResetAt on that row, and then the
    -- Strip that calls it.
    local ok, resetAt = pcall(dr.ResetAt, dr, guid, "POLY", 500)
    CHECK(ok, "E4f ResetAt survives a row born from an observation", resetAt)
    local okStrip, rows = pcall(dr.Strip, dr, guid, 500, nil, false, {})
    CHECK(okStrip, "E4g ...and so does the strip that draws it", rows)
    CHECK(okStrip and #rows == 1, "E4h which has a row to draw",
          okStrip and #rows or "-")

    -- The clock starts when the AURA is due to end, not when it was read.
    -- Observation runs off UNIT_AURA, so nothing re-reads a polymorph quietly
    -- running its course -- stamping the read would call the category full
    -- while the target is still standing there sheeped.
    NEAR(resetAt, 520, "E4i the fifteen seconds start at the aura's expiry")
    EQ(dr:Bracket(guid, "POLY", 519), 3, "E4j so it is still a quarter at 19s")
    EQ(dr:Bracket(guid, "POLY", 521), 1, "E4k and full only after the aura's own clock")

    -- A real removal overwrites the projection. If the sheep is broken early,
    -- the fifteen seconds start THEN -- the combat log wins over an estimate.
    dr:Faded(guid, 118, 507)
    NEAR(dr:ResetAt(guid, "POLY", 508), 522, "E4l a break re-stamps the clock")

    -- Observing the same aura twice must not pull the clock in.
    local dr2 = E.NewDR()
    dr2:Observe("Player-Twice", 118, 5, 500, 505)
    dr2:Observe("Player-Twice", 118, 5, 503, 505)
    NEAR(dr2:ResetAt("Player-Twice", "POLY", 503), 520,
         "E4m a second reading of the same aura leaves the clock alone")

    -- The invariant, guarded rather than assumed. A row with no stamp has no
    -- clock to report, and the only honest answer is none -- never an error
    -- thrown out of the middle of a strip.
    local dr3 = E.NewDR()
    dr3:Applied("Player-Poked", 118, 500)
    dr3:Faded("Player-Poked", 118, 501)
    dr3.state["Player-Poked"].POLY.faded = nil
    local okNil, value = pcall(dr3.ResetAt, dr3, "Player-Poked", "POLY", 502)
    CHECK(okNil, "E4n an unstamped row does not throw", value)
    EQ(okNil and value, nil, "E4o it reports no clock")
end

-- === F: the profile ========================================================
-- Which ladders THIS character can open, derived from spell ids rather than
-- from a table of classes -- so it follows a respec and a pet swap.
do
    -- A frost mage: Polymorph, Frost Nova, Frostbite. No Dragon's Breath.
    local mage = E.Profile({ 118, 122, 12494, 133 --[[Fireball, no ladder]] })
    EQ(mage.POLY, true, "F1 mage opens the incapacitate ladder")
    EQ(mage.ROOT, true, "F2 and roots")
    EQ(mage.ROOT_PROC, true, "F3 Frostbite is its own ladder")
    EQ(mage.DRAGONS, nil, "F4 an untalented mage has no Dragon's Breath")
    EQ(mage.KIDNEY, nil, "F5 and certainly no Kidney Shot")

    -- The same class, talented differently.
    local fire = E.Profile({ 118, 122, 31661 })
    EQ(fire.DRAGONS, true, "F6 a fire mage does have it")

    -- A rogue.
    local rogue = E.Profile({ 1833, 408, 6770, 1776, 2094 })
    EQ(rogue.STUN, true, "F7 rogue stuns")
    EQ(rogue.KIDNEY, true, "F8 and kidneys, on their own ladder")
    EQ(rogue.POLY, true, "F9 Sap and Gouge are the incapacitate ladder")
    EQ(rogue.BLIND, true, "F10 and blind")

    -- The manual escape hatch: a partner's CC, asked for explicitly.
    local withExtra = E.Profile({ 118 }, { FEAR = true })
    EQ(withExtra.FEAR, true, "F11 extras join the profile")
    EQ(withExtra.POLY, true, "F12 without displacing what was derived")

    -- Order is the generated group order, always.
    local list = E.ProfileList(rogue)
    EQ(list[1], "STUN", "F13 profile list is in group order")
    EQ(list[2], "KIDNEY", "F14 ...")
    EQ(list[3], "BLIND", "F15 ...")
    EQ(list[4], "POLY", "F16 ...")
    EQ(#list, 4, "F17 and carries nothing else")
end

-- === G: strips =============================================================
do
    local dr = E.NewDR()
    local guid = "Player-Enemy-4"
    local rogue = E.Profile({ 1833, 408, 6770, 2094 })

    -- Nothing has happened yet. With a profile in hand the strip still draws,
    -- greyed: that is what tells a rogue what they HAVE.
    local strip = dr:Strip(guid, 500, rogue, true)
    EQ(#strip, 4, "G1 full profile drawn when nothing is open")
    EQ(strip[1].bracket, 1, "G2 all at full")
    EQ(strip[1].open, false, "G3 and marked not-open, so a board can grey them")

    -- Without includeFull, a clean target draws nothing at all.
    EQ(#dr:Strip(guid, 500, rogue, false), 0, "G4 nothing drawn when nothing is open")

    dr:Applied(guid, 408, 500)                        -- Kidney lands
    local open = dr:Strip(guid, 501, rogue, false)
    EQ(#open, 1, "G5 one open category")
    EQ(open[1].cat, "KIDNEY", "G6 the right one")
    EQ(open[1].held, true, "G7 held while it is still on them")
    EQ(open[1].last, 408, "G8 carrying the spell that opened it")

    -- Something OUTSIDE the profile, done to them by somebody else. It must
    -- still appear: on your own row that is the entire story.
    dr:Applied(guid, 5782, 502)                       -- a warlock's Fear
    local mixed = dr:Strip(guid, 503, rogue, true)
    local seen = {}
    for _, row in ipairs(mixed) do seen[row.cat] = row end
    CHECK(seen.FEAR ~= nil, "G9 an off-profile category that is OPEN still draws")
    EQ(#mixed, 5, "G10 profile plus the one open extra")
    -- ...but only while it is open. A closed off-profile category is noise.
    dr:Faded(guid, 5782, 503)
    EQ(#dr:Strip(guid, 525, rogue, true), 4, "G11 and drops off once it resets")

    -- Order never depends on what happened first.
    local order = dr:Strip(guid, 503, rogue, true)
    EQ(order[1].cat, "STUN", "G12 strip order is group order, always")
    EQ(order[2].cat, "KIDNEY", "G13 ...")
end

-- === H: forgetting people ==================================================
-- The battleground problem: forty enemies through one combat log, and a table
-- keyed by GUID that only grows.
do
    local dr = E.NewDR()
    for i = 1, 40 do
        dr:Applied("Player-BG-" .. i, 1833, 600)
        dr:Faded("Player-BG-" .. i, 1833, 602)
    end
    EQ(dr:Count(), 40, "H1 forty people tracked")
    EQ(dr:Prune(610, 10), 0, "H2 nobody dropped while their ladders still run")
    EQ(dr:Count(), 40, "H3 ...")
    EQ(dr:Prune(640, 10), 40, "H4 all dropped once every ladder has reset")
    EQ(dr:Count(), 0, "H5 and the table is empty again")

    -- Somebody still stunned is never forgotten, however long the fight runs.
    dr:Applied("Player-BG-held", 853, 700)             -- applied, never faded
    EQ(dr:Prune(900, 10), 0, "H6 an active aura is never pruned")

    -- Recent(): most recently touched first, capped.
    local d2 = E.NewDR()
    d2:Applied("Player-A", 1833, 800); d2:Faded("Player-A", 1833, 801)
    d2:Applied("Player-B", 1833, 805); d2:Faded("Player-B", 1833, 806)
    d2:Applied("Player-C", 1833, 803); d2:Faded("Player-C", 1833, 804)
    local recent = d2:Recent(810, 5)
    EQ(recent[1], "Player-B", "H7 most recently touched first")
    EQ(recent[2], "Player-C", "H8 ...")
    EQ(recent[3], "Player-A", "H9 ...")
    EQ(#d2:Recent(810, 2), 2, "H10 and the cap is honoured")
    EQ(#d2:Recent(830, 5), 0, "H11 people with nothing open are not listed")
end

-- === I: duration and formatting ============================================
do
    local dr = E.NewDR()
    local guid = "Player-Enemy-5"
    -- The cap applies BEFORE the ladder, which is why a 50s Polymorph and a
    -- 20s Fear both come out at 5s on the second cast.
    NEAR((E.PredictDuration(dr, guid, 118, 50, 900)), 10, "I1 first poly is capped to 10s")
    dr:Applied(guid, 118, 900); dr:Faded(guid, 118, 901)
    NEAR((E.PredictDuration(dr, guid, 118, 50, 902)), 5, "I2 second is 5s, not 25s")
    NEAR((E.PredictDuration(dr, guid, 5782, 20, 902)), 10, "I3 a fresh fear is its own ladder")

    -- Disarm is not duration-capped: the server's list names neither DISARM
    -- nor DEATHCOIL.
    NEAR((E.PredictDuration(dr, guid, 676, 10, 902)), 10, "I4 disarm is not capped")

    -- Hamstring has the cap and no ladder at all.
    local d2 = E.NewDR()
    d2:Applied(guid, 1715, 900); d2:Faded(guid, 1715, 901)
    local dur, cat, bracket = E.PredictDuration(d2, guid, 1715, 15, 902)
    NEAR(dur, 10, "I5 hamstring is capped")
    EQ(cat, "LIMIT", "I6 ...")
    EQ(bracket, 1, "I7 ...and never brackets")

    EQ(E.FormatTime(nil), "", "I8 nothing to say about nil")
    EQ(E.FormatTime(0), "", "I9 or about an elapsed timer")
    EQ(E.FormatTime(4.25), "4.2", "I10 a decimal under ten")
    EQ(E.FormatTime(12.4), "12", "I11 and none over it")
end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
