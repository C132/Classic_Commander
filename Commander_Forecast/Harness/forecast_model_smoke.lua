-- Commander Forecast model smoke (luajit).
--
-- Loads the REAL CommanderForecastModel.lua with no client at all — the file's
-- runtime section is gated on CreateFrame existing, so everything below the
-- parser and the arithmetic simply does not build here. What is proven:
--
--   * the tooltip parser against verbatim TBC spell text from nine classes,
--     including the shapes that fool a naive pattern (Immolate's two numbers,
--     Prayer of Mending's "damage" that is not damage, Power Word: Shield's
--     absorb, Sinister Strike's flat-on-a-swing)
--   * TBC's coefficient rules: direct, DoT, channel, and the hybrid split
--   * the running mean, its window, the miss-rate decay, and which of the two
--     estimates Compose picks
--
-- Run:  /opt/homebrew/bin/luajit forecast_model_smoke.lua

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

local function NEAR(a, b, label, tolerance)
    tolerance = tolerance or 0.001
    CHECK(type(a) == "number" and math.abs(a - b) <= tolerance, label,
        string.format("got %s want %s", tostring(a), tostring(b)))
end

-- The model file assigns one global and reads none.
_G.CreateFrame = nil
dofile(ADDONS .. "/Commander_Forecast/CommanderForecastModel.lua")
local M = CommanderForecast.Model
CHECK(M ~= nil, "model namespace exists")

-- ===========================================================================
-- Parser — verbatim 2.5.x spell text
-- ===========================================================================

local function P(text) return M.ParseDescription(text) end

do
    local fireball = P("Hurls a fiery ball that causes 649 to 821 Fire damage and an additional 84 Fire damage over 8 sec.")
    CHECK(fireball and fireball.kind == "damage", "Fireball is damage")
    CHECK(fireball.school == M.SCHOOLS.fire, "Fireball is Fire", fireball.school)
    NEAR(fireball.direct.min, 649, "Fireball direct min")
    NEAR(fireball.direct.max, 821, "Fireball direct max")
    NEAR(fireball.direct.avg, 735, "Fireball direct avg")
    NEAR(fireball.overTime.total, 84, "Fireball DoT total")
    NEAR(fireball.overTime.duration, 8, "Fireball DoT duration")

    local frostbolt = P("Launches a bolt of frost at the enemy, causing 600 to 647 Frost damage and slowing movement speed by 40% for 9 sec.")
    CHECK(frostbolt.school == M.SCHOOLS.frost, "Frostbolt is Frost")
    NEAR(frostbolt.direct.avg, 623.5, "Frostbolt direct avg")
    CHECK(frostbolt.overTime == nil, "Frostbolt has no DoT — the slow is not damage")

    local shadowBolt = P("Sends a shadowy bolt at the enemy causing 544 to 607 Shadow damage.")
    CHECK(shadowBolt.school == M.SCHOOLS.shadow, "Shadow Bolt is Shadow")
    NEAR(shadowBolt.direct.avg, 575.5, "Shadow Bolt avg")

    local corruption = P("Corrupts the target, causing 900 Shadow damage over 18 sec.")
    CHECK(corruption.direct == nil, "Corruption has no direct component")
    NEAR(corruption.overTime.total, 900, "Corruption DoT total")
    NEAR(corruption.overTime.duration, 18, "Corruption DoT duration")

    -- Two numbers, both damage, one of them a DoT: the case that requires the
    -- over-time clause to be removed before the direct patterns run.
    local immolate = P("Burns the enemy for 327 Fire damage and then an additional 485 Fire damage over 15 sec.")
    NEAR(immolate.direct.avg, 327, "Immolate direct")
    NEAR(immolate.overTime.total, 485, "Immolate DoT total")

    local swp = P("A word of darkness that causes 1236 Shadow damage over 18 sec.")
    CHECK(swp.direct == nil, "Shadow Word: Pain has no direct component")
    NEAR(swp.overTime.total, 1236, "Shadow Word: Pain DoT total")

    local mindFlay = P("Assaults the target's mind with Shadow energy, causing 528 Shadow damage over 3 sec.")
    NEAR(mindFlay.overTime.duration, 3, "Mind Flay duration")
end

do
    local flashHeal = P("Heals a friendly target for 890 to 1034.")
    CHECK(flashHeal and flashHeal.kind == "heal", "Flash Heal is a heal")
    NEAR(flashHeal.direct.avg, 962, "Flash Heal avg")

    local renew = P("Heals the target for 1010 over 15 sec.")
    CHECK(renew.kind == "heal", "Renew is a heal")
    CHECK(renew.direct == nil, "Renew has no direct component")
    NEAR(renew.overTime.total, 1010, "Renew HoT total")
    NEAR(renew.overTime.duration, 15, "Renew HoT duration")

    -- "the next time they take damage" must not make this a damage spell.
    local pom = P("Places a spell on the target that heals them for 800 the next time they take damage.")
    CHECK(pom and pom.kind == "heal", "Prayer of Mending is a heal", pom and pom.kind)
    NEAR(pom.direct.avg, 800, "Prayer of Mending amount")

    local shield = P("Draws on the soul of the friendly target to shield them, absorbing 1265 damage.")
    CHECK(shield and shield.kind == "absorb", "Power Word: Shield is an absorb", shield and shield.kind)
    NEAR(shield.direct.avg, 1265, "Power Word: Shield amount")
end

do
    local sinister = P("An instant strike that causes 98 damage in addition to your normal weapon damage.")
    CHECK(sinister and sinister.weapon, "Sinister Strike is weapon based")
    NEAR(sinister.weaponFlat, 98, "Sinister Strike flat bonus")
    NEAR(sinister.weaponMult, 1, "Sinister Strike is a full swing")

    local mortal = P("A vicious strike that deals weapon damage plus 210 and wounds the target.")
    CHECK(mortal.weapon, "Mortal Strike is weapon based")
    NEAR(mortal.weaponFlat, 210, "Mortal Strike flat bonus")

    local heroic = P("A strong attack that increases melee damage by 195.")
    CHECK(heroic == nil or heroic.weapon ~= true, "a spell that only mentions melee damage is not parsed as a swing")

    CHECK(P("Instant") == nil, "a description with no numbers yields no profile")
    CHECK(P(nil) == nil, "nil text yields no profile")
end

do
    -- The false positives that cost a wrong number on a real icon.
    local sunder = P("Reduces an enemy target's armor by 1400 for 30 sec.")
    CHECK(sunder == nil, "Sunder Armor's duration is not a 30 point heal",
        sunder and sunder.kind .. " " .. tostring(sunder.direct and sunder.direct.avg))

    local demoShout = P("Reduces melee attack power by 300 for 30 sec.")
    CHECK(demoShout == nil, "Demoralizing Shout produces no output number")

    local manaPotion = P("Restores 4200 to 4400 mana.")
    CHECK(manaPotion == nil, "a mana potion is not 4300 healing",
        manaPotion and tostring(manaPotion.direct and manaPotion.direct.avg))

    local rejuvPotion = P("Restores 1350 to 2250 health and 1350 to 2250 mana over 30 sec.")
    CHECK(rejuvPotion and rejuvPotion.kind == "heal", "one that restores both is still a heal")

    -- A heal whose duration is written the same way the amount is.
    local wave = P("Heals a friendly target for 1725 to 1967 and another 500 over 12 sec.")
    NEAR(wave.direct.avg, 1846, "talented Healing Wave direct")
    NEAR(wave.overTime.total, 500, "talented Healing Wave HoT")

    local blessing = P("Places a Blessing on the friendly target, healing them for 200 each time they are struck for 30 sec.")
    CHECK(blessing and blessing.kind == "heal", "Blessing of Light style text is a heal")
    NEAR(blessing.direct.avg, 200, "and reads the heal, not the duration")
end

do
    -- Metadata lines must never reach the patterns.
    local lines = {
        "Fireball", "Rank 13", "465 Mana", "35 yd range", "3.5 sec cast",
        "Hurls a fiery ball that causes 649 to 821 Fire damage and an additional 84 Fire damage over 8 sec.",
    }
    local description = M.DescriptionFrom(lines)
    CHECK(not description:find("Mana"), "mana line dropped from the description")
    CHECK(not description:find("yd range"), "range line dropped from the description")
    local profile = P(description)
    NEAR(profile.direct.avg, 735, "full tooltip still parses to the right direct avg")
end

do
    -- The mage bar that was screenshotted: every one of these was wrong or
    -- missing in the field on 2026-09-10, and every one is client-verbatim.
    local iceBarrier = M.DescriptionFrom({
        "Ice Barrier", "Rank 6", "480 Mana", "Instant",
        "Instantly shields you, absorbing 1075 damage.  Lasts 1 min.  While the shield holds, spells will not be interrupted.",
    })
    CHECK(iceBarrier:find("absorbing"), "Ice Barrier's 'Instantly...' line survives the cast-time filter", iceBarrier)
    local barrier = P(iceBarrier)
    CHECK(barrier and barrier.kind == "absorb", "Ice Barrier is an absorb", barrier and barrier.kind)
    NEAR(barrier.direct.avg, 1075, "Ice Barrier amount")
    NEAR(barrier.coefOverride, 0.1, "an absorb keeps a tenth of spell power")

    local ward = P("Absorbs 675 Frost damage.  Lasts 30 sec.")
    CHECK(ward and ward.kind == "absorb", "Frost Ward is an absorb, not 675 Frost damage", ward and ward.kind)
    CHECK(ward.school == M.SCHOOLS.frost, "and it scales off Frost", ward.school)

    local manaShield = P("Absorbs 1050 damage, draining mana instead.  Drains 1 mana per damage absorbed.  Lasts 1 min.")
    CHECK(manaShield and manaShield.kind == "absorb", "Mana Shield is an absorb", manaShield and manaShield.kind)
    NEAR(manaShield.direct.avg, 1050, "Mana Shield amount")

    local missiles = P("Launches Arcane Missiles at the enemy, causing 264 Arcane damage every 1 sec for 5 sec.")
    NEAR(missiles.overTime.total, 1320, "Arcane Missiles is five ticks of 264, not one")
    NEAR(missiles.overTime.duration, 5, "over its five seconds, not its one-second interval")

    local freeze = P("Inflicts 80 Frost damage to an enemy every 3 sec., stunning it for 8 sec.")
    NEAR(freeze.overTime.total, 240, "Freeze rounds 8/3 to three ticks")

    local lance = P("Deals 161 to 187 Frost damage to an enemy target.  Causes triple damage against Frozen targets.")
    NEAR(lance.direct.avg, 174, "Ice Lance direct")
    NEAR(lance.frozenMult, 3, "Ice Lance triples against Frozen targets")
    CHECK(P("Deals 100 Frost damage. Causes double damage against Frozen targets.").frozenMult == 2, "double is read too")
    CHECK(P("Blasts the enemy for 700 Fire damage.").frozenMult == nil, "an unconditional spell has no multiplier")

    local channel = M.DescriptionFrom({ "Arcane Missiles", "Rank 10", "740 Mana", "30 yd range", "Channeled",
        "Launches Arcane Missiles at the enemy, causing 264 Arcane damage every 1 sec for 5 sec." })
    CHECK(not channel:find("^Channeled"), "the bare Channeled line is still dropped")
end

-- ===========================================================================
-- Coefficients
-- ===========================================================================

do
    local direct = { kind = "damage", direct = { avg = 700 } }
    NEAR(select(1, M.Coefficients(direct, 3.0)), 3.0 / 3.5, "3.0s cast keeps 3/3.5")
    NEAR(select(1, M.Coefficients(direct, 4.5)), 1.0, "a cast over the cap is capped at 1.0")
    NEAR(select(1, M.Coefficients(direct, 0)), 1.5 / 3.5, "an instant is charged the global")

    local dot = { kind = "damage", overTime = { total = 900, duration = 18 } }
    local d1, d2 = M.Coefficients(dot, 0)
    NEAR(d1, 0, "a pure DoT has no direct coefficient")
    NEAR(d2, 1.0, "an 18s DoT is capped at the 15s window")

    local shortDot = { kind = "damage", overTime = { total = 300, duration = 12 } }
    NEAR(select(2, M.Coefficients(shortDot, 0)), 12 / 15, "a 12s DoT keeps 12/15")

    -- A channel: "damage over 3 sec" IS the 3 second cast.
    local channel = { kind = "damage", overTime = { total = 528, duration = 3 } }
    local c1, c2 = M.Coefficients(channel, 3.0)
    NEAR(c1, 0, "a channel has no separate direct part")
    NEAR(c2, 3.0 / 3.5, "a channel normalises against the cast window, not the DoT window")

    -- Hybrid: neither half collects its full coefficient.
    local hybrid = { kind = "damage", direct = { avg = 735 }, overTime = { total = 84, duration = 8 } }
    local h1, h2 = M.Coefficients(hybrid, 3.5)
    local dd, dt = 1.0, 8 / 15
    NEAR(h1, dd * dd / (dd + dt), "hybrid direct share")
    NEAR(h2, dt * dt / (dd + dt), "hybrid DoT share")
    CHECK(h1 + h2 < dd + dt, "the hybrid split is strictly less than both coefficients in full")
end

-- ===========================================================================
-- Hit chance and level buckets
-- ===========================================================================

do
    NEAR(M.MissChance(false, 0), 0.04, "spell miss at equal level")
    NEAR(M.MissChance(false, 3), 0.17, "spell miss against a boss")
    NEAR(M.MissChance(false, 9), 0.17, "anything past +3 is the boss row")
    NEAR(M.MissChance(false, 3, false, 0.10), 0.07, "hit rating comes off the miss chance")
    NEAR(M.MissChance(false, 3, false, 0.99), 0.01, "miss chance floors at 1%")
    NEAR(M.MissChance(true, 3), 0.09, "melee has its own boss row")
    NEAR(M.MissChance(false, 3, true), 0.04, "a player target has no boss row")

    CHECK(M.LevelBucket(70, 73, false) == "n3", "a +3 mob is bucket n3")
    CHECK(M.LevelBucket(70, 70, true) == "p0", "an even-level player is bucket p0")
    CHECK(M.LevelBucket(70, -1, false) == "n3", "a skull is bucketed as a boss")
    CHECK(M.LevelBucket(70, 40, false) == "n-3", "everything far below you is one bucket")
end

-- ===========================================================================
-- Sample arithmetic
-- ===========================================================================

do
    local record = M.NewRecord()
    M.Observe(record, 1000, false, 20)
    M.Observe(record, 2000, false, 20)
    NEAR(record.avg, 1500, "two samples average plainly")
    NEAR(record.avgHit, 1500, "non-crit average tracks the same two")
    CHECK(record.nCrit == 0, "no crits recorded")

    M.Observe(record, 3000, true, 20)
    NEAR(record.avgCrit, 3000, "the crit average is its own series")
    NEAR(record.avg, 2000, "the overall average includes the crit")

    -- Past the window the mean tracks rather than converges: feeding a new
    -- value forever must arrive at that value.
    local tracking = M.NewRecord()
    for _ = 1, 200 do M.Observe(tracking, 100, false, 20) end
    for _ = 1, 200 do M.Observe(tracking, 500, false, 20) end
    CHECK(math.abs(tracking.avg - 500) < 1, "the running mean follows a re-geared character", tracking.avg)

    -- ...and the hit/miss counters halve rather than grow without bound.
    CHECK(tracking.landed <= 200, "landed counter is decayed", tracking.landed)

    local rate = M.NewRecord()
    CHECK(M.MissRate(rate) == nil, "no miss rate until there is a sample base")
    for _ = 1, 9 do M.Observe(rate, 100, false, 20) end
    for _ = 1, 1 do M.ObserveMiss(rate) end
    NEAR(M.MissRate(rate), 0.1, "miss rate once there are ten events")
end

-- ===========================================================================
-- The two estimates, and which one wins
-- ===========================================================================

local STATS = {
    level = 70,
    spellPower = { 0, 500, 500, 500, 500, 500, 500 },
    spellCrit = { 0, 0.20, 0.20, 0.20, 0.20, 0.20, 0.20 },
    healPower = 800,
    meleeCrit = 0.25,
    weaponAvg = 200,
    spellHit = 0,
    meleeHit = 0,
}
local BOSS = { exists = true, level = 73, isPlayer = false }

do
    local fireball = P("Hurls a fiery ball that causes 649 to 821 Fire damage and an additional 84 Fire damage over 8 sec.")
    local estimate = M.ModelEstimate(fireball, STATS, BOSS,
        { number = "AVERAGE", applyHit = true, castSeconds = 3.5 })

    local dd, dt = M.Coefficients(fireball, 3.5)
    local direct = 735 + 500 * dd
    local dot = 84 + 500 * dt
    NEAR(estimate.direct, direct, "modeled direct includes spell power at the direct coefficient")
    NEAR(estimate.dot, dot, "modeled DoT includes spell power at the DoT coefficient")
    NEAR(estimate.hit, direct + dot, "a normal hit is the two parts, uncrit")
    NEAR(estimate.crit, direct * 1.5 + dot, "only the direct part crits in TBC")
    NEAR(estimate.average, (direct * (1 + 0.20 * 0.5) + dot) * (1 - 0.17),
        "the average folds in crit and the boss miss chance")

    local noHit = M.ModelEstimate(fireball, STATS, BOSS,
        { number = "AVERAGE", applyHit = false, castSeconds = 3.5 })
    CHECK(noHit.average > estimate.average, "turning off hit chance raises the average")

    -- Healing draws on +healing, never on +damage.
    local flashHeal = P("Heals a friendly target for 890 to 1034.")
    local heal = M.ModelEstimate(flashHeal, STATS, BOSS,
        { number = "HIT", applyHit = true, castSeconds = 1.5 })
    NEAR(heal.power, 800, "a heal reads +healing")
    NEAR(heal.value, 962 + 800 * (1.5 / 3.5), "Flash Heal at its own coefficient")
    NEAR(heal.missChance, 0, "a heal cannot miss")

    -- A weapon ability reads the swing the client already reports.
    local sinister = P("An instant strike that causes 98 damage in addition to your normal weapon damage.")
    local swing = M.ModelEstimate(sinister, STATS, BOSS,
        { number = "HIT", applyHit = true, castSeconds = 0 })
    NEAR(swing.value, 298, "weapon average plus the flat bonus")
    NEAR(swing.critMult, 2.0, "a physical crit is double")
    NEAR(swing.missChance, 0.09, "and it uses the melee miss table")
end

do
    local lance = P("Deals 161 to 187 Frost damage to an enemy target.  Causes triple damage against Frozen targets.")
    local unfrozen = M.ModelEstimate(lance, STATS, BOSS, { number = "HIT", applyHit = false, castSeconds = 0 })
    local frozenBoss = { exists = true, level = 73, isPlayer = false, frozen = true }
    local frozenHit = M.ModelEstimate(lance, STATS, frozenBoss, { number = "HIT", applyHit = false, castSeconds = 0 })
    NEAR(frozenHit.value, unfrozen.value * 3, "a frozen target triples the modeled Ice Lance")
    NEAR(frozenHit.multiplier, 3, "and the estimate says so")
    NEAR(unfrozen.multiplier, 1, "an unfrozen one does not")

    local record = M.NewRecord()
    for _ = 1, 5 do M.Observe(record, 500, false, 20) end
    local scaled = M.MeasuredEstimate(record, lance, { number = "HIT", multiplier = 3 })
    NEAR(scaled.value, 1500, "the measured fallback scales unfrozen samples by the multiplier")

    -- Absorbs: the school's power at a tenth, and never a crit.
    local ward = P("Absorbs 675 Frost damage.  Lasts 30 sec.")
    local wardEstimate = M.ModelEstimate(ward, STATS, BOSS, { number = "AVERAGE", castSeconds = 0 })
    NEAR(wardEstimate.value, 675 + 500 * 0.1, "Frost Ward is its base plus a tenth of frost power")
    NEAR(wardEstimate.critChance, 0, "an absorb cannot crit")
    NEAR(wardEstimate.missChance, 0, "or miss")
end

do
    local corruption = P("Corrupts the target, causing 900 Shadow damage over 18 sec.")
    local record = M.NewRecord()
    for _ = 1, 12 do M.ObserveTick(record, 200, 20) end
    M.ObserveTickCount(record, 6, 20)

    local measured = M.MeasuredEstimate(record, corruption, { number = "AVERAGE" })
    NEAR(measured.value, 1200, "a measured DoT is its tick times its measured tick count")
    CHECK(measured.source == "measured", "and it says so")

    -- With no measured tick count, the tooltip duration at TBC's 3s period.
    local noCount = M.NewRecord()
    for _ = 1, 4 do M.ObserveTick(noCount, 200, 20) end
    NEAR(M.MeasuredEstimate(noCount, corruption, {}).value, 200 * 6,
        "tick count falls back to the tooltip duration over a 3s period")

    CHECK(M.MeasuredEstimate(M.NewRecord(), corruption, {}) == nil,
        "an empty record is not an estimate")
end

do
    local fireball = P("Hurls a fiery ball that causes 649 to 821 Fire damage and an additional 84 Fire damage over 8 sec.")
    local modeled = M.ModelEstimate(fireball, STATS, BOSS,
        { number = "AVERAGE", applyHit = true, castSeconds = 3.5 })

    local thin = M.NewRecord()
    M.Observe(thin, 4000, false, 20)
    local thinMeasured = M.MeasuredEstimate(thin, fireball, { number = "AVERAGE" })

    CHECK(M.Compose(modeled, thinMeasured, "AUTO", 3) == modeled,
        "one sample is not enough to displace the model")
    CHECK(M.Compose(modeled, thinMeasured, "MEASURED", 3) == nil,
        "measured-only shows nothing until the samples are there")
    CHECK(M.Compose(modeled, thinMeasured, "MODEL", 3) == modeled,
        "model-only ignores the log entirely")

    local fat = M.NewRecord()
    for _ = 1, 5 do M.Observe(fat, 4000, false, 20) end
    local fatMeasured = M.MeasuredEstimate(fat, fireball, { number = "AVERAGE" })
    CHECK(M.Compose(modeled, fatMeasured, "AUTO", 3) == fatMeasured,
        "past the threshold the log takes over")
    CHECK(fatMeasured.value > modeled.value,
        "and on a talented spec that is the higher number, which is the whole point")
end

-- ===========================================================================
-- Formatting
-- ===========================================================================

do
    CHECK(M.Format(842, true) == "842", "small numbers are written out")
    CHECK(M.Format(1240, true) == "1.2k", "four digits compact to one decimal")
    CHECK(M.Format(12400, true) == "12k", "five digits lose the decimal")
    CHECK(M.Format(1240, false) == "1240", "compact off writes the number")
    CHECK(M.Format(2.34, false, true) == "2.3", "per-mana values keep a decimal")
    CHECK(M.Format(-5, true) == "0", "a negative estimate is clamped, not printed")
    CHECK(M.Format(nil) == nil, "nil formats to nothing")
end

io.write(string.format("\n%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
