-- Commander Advisor engine smoke (luajit). No WoW mock: the engine is a pure
-- function of a snapshot table, which is the reason it was split out.
--
--   luajit Commander_Advisor/Harness/advisor_engine_smoke.lua
--
-- Sections:
--   A  the rulebook is well-formed
--   B  the intake book: rate, burst, time-to-die, attackers, school
--   C  maintain rules: missing, up, expiring, grace, quiet switches
--   D  react rules: ladders, blockers, backups, just-cast
--   E  hysteresis: rise per tier, hold, immediate drop
--   F  modes, caution, ranking and the cap
--   G  control: nothing but the trinket while held

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
    CHECK(type(got) == "number" and math.abs(got - want) <= (tol or 0.01), label,
          string.format("got %s want %s", tostring(got), tostring(want)))
end

assert(loadfile(ADDONS .. "/Commander_Advisor/CommanderAdvisorData.lua"))()
assert(loadfile(ADDONS .. "/Commander_Advisor/CommanderAdvisorEngine.lua"))()
local D, E = CommanderAdvisor_Data, CommanderAdvisor_Engine

-- A snapshot with everything quiet; override what a scenario needs
local function Snap(over)
    local S = {
        now = 100, class = "PRIEST", hp = 1.0, mana = 1.0, inCombat = false,
        dead = false, mounted = false, taxi = false, resting = false, stealthed = false,
        taking = false, melee = 0, casters = 0, attackers = 0, enemyPlayers = 0,
        auras = {}, debuffs = {}, debuffTypes = {}, control = {}, incomingCasts = {},
        spells = {}, petSpells = {}, items = {}, recentCasts = {},
        inGroup = false, hasTarget = true, zone = "none", outdoors = true,
    }
    for k, v in pairs(over or {}) do S[k] = v end
    return S
end
local function Known(S, ...)
    for _, name in ipairs({ ... }) do S.spells[name] = { known = true, ready = true, usable = true } end
    return S
end
local function Cfg(over)
    local cfg = {
        modes = {}, reticence = 0, ttlCeiling = 0.75,
        riseSeconds = { 0, 0, 0 }, holdSeconds = 0, castGrace = 2,
        expiringSoon = 20, remindInCombat = true, remindOutOfCombat = true,
        quietWhileResting = false, quietInStealth = true, maxSignals = 0,
    }
    for k, v in pairs(over or {}) do cfg[k] = v end
    return cfg
end
local function Rule(key) local r = D.RULE_BY_KEY[key]; assert(r, key); return r end
local function Find(list, key)
    for _, s in ipairs(list) do if s.rule.key == key then return s end end
end

-- === A: the rulebook ========================================================
do
    local seen = {}
    for _, rule in ipairs(D.RULES) do
        CHECK(not seen[rule.key], "A duplicate key " .. rule.key)
        seen[rule.key] = true
        CHECK(rule.spell or rule.item, "A rule has a spell or item: " .. rule.key)
        CHECK(type(rule.tiers) == "table" and #rule.tiers > 0, "A rule has a ladder: " .. rule.key)
        CHECK(rule.desc and #rule.desc > 10, "A rule has a description: " .. rule.key)
        CHECK(rule.default == "AUTO" or rule.default == "OFF", "A default is AUTO or OFF: " .. rule.key)
        local last = 4
        for _, rung in ipairs(rule.tiers) do
            CHECK(rung.tier >= 1 and rung.tier <= 3, "A tier in range: " .. rule.key)
            CHECK(rung.tier <= last, "A ladder is highest-first: " .. rule.key)
            last = rung.tier
            if rung.ttl then CHECK(rung.hpBelowCeiling, "A ttl rung carries the ceiling: " .. rule.key) end
        end
        if rule.role == "maintain" then
            CHECK(D.FAMILIES[rule.family], "A maintain rule names a family: " .. rule.key)
        end
        if rule.family then
            -- every spell the rule offers is a member of the family it maintains
            for _, name in ipairs(E.SpellList(rule)) do
                local member = false
                for _, fam in ipairs(D.FAMILIES[rule.family]) do if fam == name then member = true end end
                CHECK(member, "A maintain spell is in its family: " .. rule.key .. " / " .. name)
            end
        end
    end
    EQ(#D.RulesForClass("PRIEST") > 10, true, "A priest gets a book")
    local all = 0
    for _, r in ipairs(D.RulesForClass("ROGUE")) do if r.class == "ALL" then all = all + 1 end end
    EQ(all, 3, "A everyone's three rules ride along")
end

-- === B: the intake book =====================================================
do
    local book = E.NewIntake()
    local sum = E.IntakeSummary(book, 100, 5000)
    EQ(sum.taking, false, "B empty book: not taking")
    EQ(sum.ttl, nil, "B empty book: no time-to-die")
    EQ(sum.attackers, 0, "B empty book: no attackers")

    -- One big crit is not a rate
    E.IntakeObserve(book, 100, 2000, "m1", "melee", 0x1, false)
    sum = E.IntakeSummary(book, 100.1, 3000)
    EQ(sum.taking, true, "B one hit: taking")
    NEAR(sum.rate, 400, "B one hit: rate over the whole window")
    NEAR(sum.ttl, 7.5, "B one hit: ttl from the window rate")
    EQ(sum.melee, 1, "B one melee")

    -- A sustained burst does count
    E.IntakeObserve(book, 100.5, 1000, "m1", "melee", 0x1, false)
    E.IntakeObserve(book, 101.0, 1000, "m2", "melee", 0x1, false)
    sum = E.IntakeSummary(book, 101.1, 2000)
    EQ(sum.melee, 2, "B two melee")
    NEAR(sum.rate, 2000, "B burst rate wins (3 hits / 2s)")
    NEAR(sum.ttl, 1, "B burst ttl")

    -- Casters and school
    E.IntakeObserve(book, 101.2, 800, "c1", "spell", 0x20, true)
    sum = E.IntakeSummary(book, 101.3, 2000)
    EQ(sum.casters, 1, "B a caster")
    EQ(sum.attackers, 3, "B three distinct attackers")
    EQ(sum.enemyPlayers, 1, "B one of them a player")
    EQ(sum.school, 0x1, "B physical still dominant")

    -- Time passes: attackers age out, taking stops, ttl goes away
    sum = E.IntakeSummary(book, 105, 2000)
    EQ(sum.taking, false, "B quiet after 3s")
    EQ(sum.ttl, nil, "B no ttl when nothing is hitting you")
    EQ(sum.attackers, 3, "B attackers still counted at 4s")
    sum = E.IntakeSummary(book, 107, 2000)
    EQ(sum.attackers, 0, "B attackers gone after 5s")

    -- Shadow-dominant window
    local b2 = E.NewIntake()
    E.IntakeObserve(b2, 10, 300, "c1", "spell", 0x20)
    E.IntakeObserve(b2, 11, 300, "c1", "spell", 0x20)
    E.IntakeObserve(b2, 11.5, 100, "m1", "melee", 0x1)
    sum = E.IntakeSummary(b2, 12, 1000)
    EQ(sum.school, 0x20, "B shadow dominant")
    NEAR(sum.schoolShare, 600 / 700, "B shadow share")

    -- Ring bound
    local b3 = E.NewIntake()
    for i = 1, 200 do E.IntakeObserve(b3, i, 10, "x", "melee", 0x1) end
    EQ(b3.count, E.MAX_HITS, "B book is bounded")
    sum = E.IntakeSummary(b3, 200, 1000)
    NEAR(sum.rate, 15, "B ring keeps the newest (3 hits in the 2s burst window beat 6 in 5s)")
end

-- === C: maintain rules ======================================================
do
    local rule = Rule("PRIEST_INNER_FIRE")
    local S = Known(Snap(), "Inner Fire")
    local tier, why = E.Assess(rule, S, Cfg())
    EQ(tier, 1, "C Inner Fire missing out of combat: low")
    S.auras["Inner Fire"] = { expire = 0 }
    tier, why = E.Assess(rule, S, Cfg())
    EQ(tier, nil, "C Inner Fire up: nothing")
    EQ(why, "up", "C ... and says so")

    -- Expiring soon is a low note
    S.auras["Inner Fire"] = { expire = 110 }
    tier = E.Assess(rule, S, Cfg({ expiringSoon = 20 }))
    EQ(tier, 1, "C expiring within 20s: low")
    tier = E.Assess(rule, S, Cfg({ expiringSoon = 5 }))
    EQ(tier, nil, "C not expiring within 5s: nothing")

    -- In combat with a melee on you the same missing buff is medium
    S = Known(Snap({ inCombat = true, melee = 1, taking = true }), "Inner Fire")
    tier = E.Assess(rule, S, Cfg())
    EQ(tier, 2, "C Inner Fire missing with melee on you: medium")
    -- ... but an expiring one never climbs past low
    S.auras["Inner Fire"] = { expire = 105 }
    tier = E.Assess(rule, S, Cfg())
    EQ(tier, 1, "C expiring is capped at low even under pressure")

    -- Quiet switches
    S = Known(Snap({ inCombat = true, taking = true }), "Inner Fire")
    EQ(E.Assess(rule, S, Cfg({ remindInCombat = false })), nil, "C quiet in combat")
    S = Known(Snap(), "Inner Fire")
    EQ(E.Assess(rule, S, Cfg({ remindOutOfCombat = false })), nil, "C quiet out of combat")
    S = Known(Snap({ resting = true }), "Inner Fire")
    EQ(E.Assess(rule, S, Cfg({ quietWhileResting = true })), nil, "C quiet while resting")
    EQ(E.Assess(rule, S, Cfg({ quietWhileResting = false })), 1, "C ... unless allowed")
    S = Known(Snap({ mounted = true }), "Inner Fire")
    EQ(E.Assess(rule, S, Cfg()), nil, "C quiet while mounted")
    S = Known(Snap({ dead = true }), "Inner Fire")
    EQ(E.Assess(rule, S, Cfg()), nil, "C quiet while dead")

    -- Missing grace: the buff has to have been gone for a moment
    do
        local st = E.NewState()
        local S2 = Known(Snap(), "Inner Fire")
        local g = Cfg({ missingGrace = 3 })
        local t2, r2 = E.Assess(rule, S2, g, st)
        EQ(r2, "grace", "C freshly missing: grace")
        S2.now = 102
        EQ(E.Assess(rule, S2, g, st), nil, "C ... still inside the grace")
        S2.now = 103
        EQ(E.Assess(rule, S2, g, st), 1, "C ... low once the grace has run")
        S2.auras["Inner Fire"] = { expire = 0 }
        E.Assess(rule, S2, g, st)
        EQ(st.missingSince.PRIEST_INNER_FIRE, nil, "C the buff coming back resets the clock")
        S2.auras["Inner Fire"] = nil
        S2.now = 104
        local _, r3 = E.Assess(rule, S2, g, st)
        EQ(r3, "grace", "C ... so dropping it again starts a new grace")
        EQ(E.Assess(rule, S2, Cfg(), st), 1, "C no grace configured: at once")
    end

    -- A family: Prayer of Fortitude satisfies the Fortitude rule
    local fort = Rule("PRIEST_FORTITUDE")
    S = Known(Snap(), "Power Word: Fortitude")
    EQ(E.Assess(fort, S, Cfg()), 1, "C Fortitude missing: low")
    S.auras["Prayer of Fortitude"] = { expire = 0 }
    EQ(E.Assess(fort, S, Cfg()), nil, "C Prayer of Fortitude satisfies it")

    -- Unknown spell: nothing, and the reason says so
    S = Snap()
    local t, r = E.Assess(fort, S, Cfg())
    EQ(t, nil, "C untrained: nothing")
    EQ(r, "not known", "C untrained: reason")

    -- A mage armour family offers the best-known armour
    local armor = Rule("MAGE_ARMOR")
    S = Known(Snap({ class = "MAGE" }), "Frost Armor", "Ice Armor")
    local tier2, _, name = E.Assess(armor, S, Cfg())
    EQ(tier2, 1, "C mage armour missing")
    EQ(name, "Ice Armor", "C the first known in book order is named")

    -- School-gated maintain: Shadow Protection only when shadow is landing
    local sp = Rule("PRIEST_SHADOW_PROT")
    S = Known(Snap({ inCombat = true, taking = true }), "Shadow Protection")
    EQ(E.Assess(sp, S, Cfg()), nil, "C Shadow Protection: silent without shadow damage")
    S.school, S.schoolShare = 0x20, 0.8
    EQ(E.Assess(sp, S, Cfg()), 2, "C Shadow Protection: medium under shadow damage")

    -- Fear Ward: high while a fear is being cast at you
    local fw = Rule("PRIEST_FEAR_WARD")
    S = Known(Snap({ inCombat = true }), "Fear Ward")
    EQ(E.Assess(fw, S, Cfg()), nil, "C Fear Ward: nothing in PvE combat")
    S.incomingCasts = { { name = "Fear" } }
    EQ(E.Assess(fw, S, Cfg()), 3, "C Fear Ward: high while Fear is being cast at you")
    S = Known(Snap({ zone = "arena" }), "Fear Ward")
    EQ(E.Assess(fw, S, Cfg()), 1, "C Fear Ward: low in an arena")
    S = Known(Snap({ enemyClassesNear = { WARLOCK = true } }), "Fear Ward")
    local tfw, rfw = E.Assess(fw, S, Cfg())
    EQ(tfw, 1, "C Fear Ward: low with a warlock in nameplate range")
    CHECK(rfw:find("enemy warlock nearby"), "C ... and says so", rfw)
    S.inCombat = true
    EQ(E.Assess(fw, S, Cfg()), 2, "C Fear Ward: medium in combat with a warlock near")
    S.enemyClassesNear = { MAGE = true }
    EQ(E.Assess(fw, S, Cfg()), nil, "C Fear Ward: a mage is not a fear")

    -- A ward goes up while the bolt is still being cast
    local fireWard = Rule("MAGE_FIRE_WARD")
    S = Known(Snap({ class = "MAGE", inCombat = true, incomingCasts = { { name = "Pyroblast" } } }), "Fire Ward")
    local tfire, rfire = E.Assess(fireWard, S, Cfg())
    EQ(tfire, 2, "C Fire Ward: medium while Pyroblast is cast at you")
    CHECK(rfire:find("Pyroblast"), "C ... naming the cast", rfire)
    S.incomingCasts = { { name = "Frostbolt" } }
    EQ(E.Assess(fireWard, S, Cfg()), nil, "C Fire Ward: not for a Frostbolt")
    EQ(E.Assess(Rule("MAGE_FROST_WARD"), Known(S, "Frost Ward"), Cfg()), 2, "C Frost Ward: the Frostbolt one")
end

-- === D: react rules =========================================================
do
    local pws = Rule("PRIEST_PWS")
    local S = Known(Snap({ inCombat = true, taking = true, hp = 0.9 }), "Power Word: Shield")
    EQ(E.Assess(pws, S, Cfg()), 1, "D PWS: low while merely taking damage")
    S.hp = 0.7
    EQ(E.Assess(pws, S, Cfg()), 2, "D PWS: medium at 70% under fire")
    S.hp = 0.35
    EQ(E.Assess(pws, S, Cfg()), 3, "D PWS: high at 35% under fire")
    S.debuffs["Weakened Soul"] = { expire = 110 }
    local t, r = E.Assess(pws, S, Cfg())
    EQ(t, nil, "D PWS: blocked by Weakened Soul")
    EQ(r, "blocked", "D PWS: reason blocked")
    S.debuffs["Weakened Soul"] = nil
    S.auras["Power Word: Shield"] = { expire = 120 }
    EQ(E.Assess(pws, S, Cfg()), nil, "D PWS: already up")
    S.auras["Power Word: Shield"] = nil
    S.spells["Power Word: Shield"].ready = false
    t, r = E.Assess(pws, S, Cfg())
    EQ(r, "on cooldown", "D PWS: on cooldown says so")

    -- Time-to-die rung, gated by the ceiling
    S = Known(Snap({ inCombat = true, taking = true, hp = 0.9, ttl = 4 }), "Power Word: Shield")
    EQ(E.Assess(pws, S, Cfg()), 1, "D ttl rung ignored at 90% (ceiling)")
    S.hp = 0.7
    EQ(E.Assess(pws, S, Cfg()), 3, "D ttl 4s at 70%: high")

    -- Dented health bar with nothing hitting you is not an emergency
    S = Known(Snap({ inCombat = true, taking = false, hp = 0.3 }), "Power Word: Shield")
    EQ(E.Assess(pws, S, Cfg()), nil, "D PWS: 30% but nothing hitting you: nothing")

    -- Renew: only when YOUR renew is not rolling
    local renew = Rule("PRIEST_RENEW")
    S = Known(Snap({ inCombat = true, taking = true, hp = 0.5 }), "Renew")
    EQ(E.Assess(renew, S, Cfg()), 2, "D Renew: medium hurt under fire")
    S.auras["Renew"] = { expire = 110, mine = false }
    EQ(E.Assess(renew, S, Cfg()), 2, "D Renew: someone else's does not count")
    S.auras["Renew"] = { expire = 110, mine = true }
    EQ(E.Assess(renew, S, Cfg()), nil, "D Renew: yours does")

    -- Backup plan: Cold Snap only when Ice Block is on cooldown
    local snap = Rule("MAGE_COLD_SNAP")
    S = Known(Snap({ class = "MAGE", inCombat = true, taking = true, hp = 0.2 }), "Cold Snap", "Ice Block")
    EQ(E.Assess(snap, S, Cfg()), nil, "D Cold Snap: silent while Ice Block is ready")
    S.spells["Ice Block"].ready = false
    EQ(E.Assess(snap, S, Cfg()), 3, "D Cold Snap: high once Ice Block is spent")

    -- Just cast
    S = Known(Snap({ inCombat = true, taking = true, hp = 0.3 }), "Power Word: Shield")
    S.recentCasts["Power Word: Shield"] = 99
    t, r = E.Assess(pws, S, Cfg())
    EQ(r, "just cast", "D just cast is quiet")
    S.recentCasts["Power Word: Shield"] = 90
    EQ(E.Assess(pws, S, Cfg()), 3, "D ... for two seconds only")
    S.castingName = "Power Word: Shield"
    t, r = E.Assess(pws, S, Cfg())
    EQ(r, "casting it", "D casting it now is quiet")

    -- Not casting: a direct heal is not suggested mid-cast
    local heal = Rule("PRIEST_FLASH_HEAL")
    S = Known(Snap({ inCombat = true, taking = true, hp = 0.3, casting = true }), "Flash Heal")
    EQ(E.Assess(heal, S, Cfg()), nil, "D Flash Heal: quiet while casting")
    S.casting = false
    EQ(E.Assess(heal, S, Cfg()), 3, "D Flash Heal: high at 30%")

    -- Items: healthstone by rule key
    local pot = Rule("ALL_HEALTH_ITEM")
    S = Snap({ inCombat = true, taking = true, hp = 0.25 })
    EQ(E.Assess(pot, S, Cfg()), nil, "D potion: none on a bar")
    S.items[pot.key] = { name = "Master Healthstone", ready = true, usable = true }
    local t3, _, n3 = E.Assess(pot, S, Cfg())
    EQ(t3, 3, "D healthstone at 25%: high")
    EQ(n3, "Master Healthstone", "D ... naming the item")
    S.items[pot.key].ready = false
    EQ(E.Assess(pot, S, Cfg()), nil, "D healthstone on cooldown: nothing")

    -- Bandage: hurt and NOT being hit
    local band = Rule("ALL_BANDAGE")
    S = Snap({ inCombat = true, taking = true, hp = 0.5 })
    S.items[band.key] = { name = "Heavy Netherweave Bandage", ready = true }
    EQ(E.Assess(band, S, Cfg()), nil, "D bandage: not while being hit")
    S.taking = false
    EQ(E.Assess(band, S, Cfg()), 1, "D bandage: low once it is quiet")
    S.debuffs["Recently Bandaged"] = { expire = 150 }
    EQ(E.Assess(band, S, Cfg()), nil, "D bandage: blocked by Recently Bandaged")

    -- Druid shift out of a root offers whichever form you know
    local shift = Rule("DRUID_SHIFT_ROOT")
    S = Known(Snap({ class = "DRUID", inCombat = true, control = { rooted = true } }), "Cat Form")
    local t4, _, n4 = E.Assess(shift, S, Cfg())
    EQ(t4, 2, "D druid rooted: medium")
    EQ(n4, "Cat Form", "D ... offering Cat Form")
    S.control = { snared = true }
    EQ(E.Assess(shift, S, Cfg()), 1, "D druid snared: low")

    -- Bear at the bottom, but not while already a bear
    local bear = Rule("DRUID_BEAR")
    S = Known(Snap({ class = "DRUID", inCombat = true, taking = true, hp = 0.25 }), "Dire Bear Form")
    EQ(E.Assess(bear, S, Cfg()), 3, "D bear at 25%: high")
    S.form = "Dire Bear Form"
    EQ(E.Assess(bear, S, Cfg()), nil, "D ... not when already a bear")
    local frenzy = Rule("DRUID_FRENZIED")
    Known(S, "Frenzied Regeneration")
    EQ(E.Assess(frenzy, S, Cfg()), 3, "D Frenzied Regeneration in bear at 25%: high")

    -- Warrior Shield Wall needs the stance and a shield
    local wall = Rule("WARRIOR_SHIELD_WALL")
    S = Known(Snap({ class = "WARRIOR", inCombat = true, taking = true, hp = 0.2, form = "Battle Stance", hasShield = true }), "Shield Wall")
    EQ(E.Assess(wall, S, Cfg()), nil, "D Shield Wall: not in Battle Stance")
    S.form = "Defensive Stance"
    EQ(E.Assess(wall, S, Cfg()), 3, "D Shield Wall: high in Defensive Stance with a shield")
    S.hasShield = false
    EQ(E.Assess(wall, S, Cfg()), nil, "D Shield Wall: no shield")

    -- Resistance totem picks the school
    local tot = Rule("SHAMAN_RESIST_TOTEM")
    S = Known(Snap({ class = "SHAMAN", inCombat = true, taking = true, school = 0x4, schoolShare = 0.9 }),
        "Fire Resistance Totem", "Frost Resistance Totem")
    local t5, _, n5 = E.Assess(tot, S, Cfg())
    EQ(t5, 1, "D resistance totem: low under fire damage")
    EQ(n5, "Fire Resistance Totem", "D ... the fire one")
    S.school = 0x10
    local _, _, n6 = E.Assess(tot, S, Cfg())
    EQ(n6, "Frost Resistance Totem", "D ... or the frost one")
    S.school = 0x20
    EQ(E.Assess(tot, S, Cfg()), nil, "D ... nothing for shadow")

    -- Fade is PvE only
    local fade = Rule("PRIEST_FADE")
    S = Known(Snap({ inCombat = true, inGroup = true, attackers = 1, hp = 0.5 }), "Fade")
    EQ(E.Assess(fade, S, Cfg()), 2, "D Fade: medium when a mob turned on you")
    S.enemyPlayers = 1
    EQ(E.Assess(fade, S, Cfg()), nil, "D Fade: not against players")

    -- Grounding: louder when a cast is aimed at you
    local ground = Rule("SHAMAN_GROUNDING")
    S = Known(Snap({ class = "SHAMAN", inCombat = true, casters = 1 }), "Grounding Totem")
    EQ(E.Assess(ground, S, Cfg()), 1, "D Grounding: low with a caster on you")
    S.incomingCasts = { { name = "Frostbolt" } }
    local t7, r7 = E.Assess(ground, S, Cfg())
    EQ(t7, 2, "D Grounding: medium with a cast aimed at you")
    CHECK(r7:find("Frostbolt"), "D ... naming the cast", r7)

    -- An enemy burst: the shield goes up before the damage, not after
    S = Known(Snap({ inCombat = true, hp = 0.95 }), "Power Word: Shield")
    EQ(E.Assess(pws, S, Cfg()), nil, "D PWS: nothing at 95% with nothing happening")
    S.enemyBurst = { melee = true, name = "Recklessness" }
    local tb, rb = E.Assess(pws, S, Cfg())
    EQ(tb, 2, "D PWS: medium the moment Recklessness is seen on someone on you")
    CHECK(rb:find("Recklessness on the enemy"), "D ... naming it", rb)
    local evasion = Rule("ROGUE_EVASION")
    S = Known(Snap({ class = "ROGUE", inCombat = true, melee = 1, enemyBurst = { spell = true, name = "Arcane Power" } }), "Evasion")
    EQ(E.Assess(evasion, S, Cfg()), nil, "D Evasion: a spell burst is not a melee burst")
    S.enemyBurst = { melee = true, name = "Blade Flurry" }
    EQ(E.Assess(evasion, S, Cfg()), 2, "D Evasion: medium on a melee burst with melee on you")
    local cloak = Rule("ROGUE_CLOAK")
    S = Known(Snap({ class = "ROGUE", inCombat = true, casters = 1, enemyBurst = { spell = true, name = "Arcane Power" } }), "Cloak of Shadows")
    EQ(E.Assess(cloak, S, Cfg()), 2, "D Cloak: medium on a caster burst with a caster on you")

    -- Mana Shield needs mana to spend
    local ms = Rule("MAGE_MANA_SHIELD")
    S = Known(Snap({ class = "MAGE", inCombat = true, taking = true, hp = 0.4, mana = 0.2 }), "Mana Shield")
    EQ(E.Assess(ms, S, Cfg()), nil, "D Mana Shield: not at 20% mana")
    S.mana = 0.6
    EQ(E.Assess(ms, S, Cfg()), 2, "D Mana Shield: medium with mana")
end

-- === E: hysteresis ==========================================================
do
    local rules = { Rule("PRIEST_INNER_FIRE"), Rule("PRIEST_PWS") }
    local cfg = Cfg({ riseSeconds = { 1.0, 0.5, 0 }, holdSeconds = 1.0 })
    local state = E.NewState()

    local S = Known(Snap(), "Inner Fire", "Power Word: Shield")
    local out = E.Evaluate(S, rules, cfg, state)
    EQ(#out, 0, "E low tier does not show at once")
    S.now = 100.5
    out = E.Evaluate(S, rules, cfg, state)
    EQ(#out, 0, "E ... nor at half the rise")
    S.now = 101.0
    out = E.Evaluate(S, rules, cfg, state)
    EQ(#out, 1, "E ... but after one second")
    EQ(out[1].isNew, true, "E new on the tick it appears")
    S.now = 101.2
    out = E.Evaluate(S, rules, cfg, state)
    EQ(out[1].isNew, false, "E not new afterwards")

    -- High tier is immediate
    S.inCombat, S.taking, S.hp = true, true, 0.3
    S.now = 102
    out = E.Evaluate(S, rules, cfg, state)
    EQ(#out, 2, "E high tier shows at once")
    EQ(out[1].rule.key, "PRIEST_PWS", "E high sorts first")
    EQ(out[1].tier, 3, "E ... at tier 3")

    -- Falling waits for the hold; rising does not
    S.hp = 0.7
    S.now = 102.5
    out = E.Evaluate(S, rules, cfg, state)
    EQ(Find(out, "PRIEST_PWS").tier, 3, "E holds at high for the hold window")
    S.now = 103.6
    out = E.Evaluate(S, rules, cfg, state)
    EQ(Find(out, "PRIEST_PWS").tier, 2, "E ... then falls to medium")
    S.hp = 0.3
    S.now = 103.7
    out = E.Evaluate(S, rules, cfg, state)
    EQ(Find(out, "PRIEST_PWS").tier, 3, "E rises again at once")

    -- Conditions clear: lingers for the hold, then goes
    S.taking = false
    S.now = 104.0
    out = E.Evaluate(S, rules, cfg, state)
    CHECK(Find(out, "PRIEST_PWS"), "E lingers after conditions clear")
    S.now = 105.0
    out = E.Evaluate(S, rules, cfg, state)
    CHECK(not Find(out, "PRIEST_PWS"), "E ... and is gone after the hold")

    -- Cast it: gone at once
    S.taking, S.hp, S.now = true, 0.3, 106
    out = E.Evaluate(S, rules, cfg, state)
    CHECK(Find(out, "PRIEST_PWS"), "E back under fire")
    S.recentCasts["Power Word: Shield"] = 106.1
    S.now = 106.1
    out = E.Evaluate(S, rules, cfg, state)
    CHECK(not Find(out, "PRIEST_PWS"), "E dropped the instant it is cast")
    E.Drop(state, "PRIEST_INNER_FIRE")
    S.now = 106.2
    out = E.Evaluate(S, rules, cfg, state)
    CHECK(not Find(out, "PRIEST_INNER_FIRE"), "E Drop forgets a signal")
end

-- === F: modes, caution, ranking, cap ========================================
do
    local rules = D.RulesForClass("PRIEST")
    local S = Known(Snap({ inCombat = true, taking = true, hp = 0.3, melee = 2 }),
        "Inner Fire", "Power Word: Shield", "Renew", "Desperate Prayer", "Psychic Scream", "Flash Heal", "Fade")
    local out = E.Evaluate(S, rules, Cfg(), E.NewState())
    CHECK(#out >= 5, "F a priest at 30% with two melee has plenty to say", #out)
    EQ(out[1].tier, 3, "F top is high")
    -- Weight orders inside the tier: Desperate Prayer (95) over PWS (90)
    EQ(out[1].rule.key, "PRIEST_DESPERATE", "F Desperate Prayer first")
    EQ(out[2].rule.key, "PRIEST_PWS", "F then the shield")

    out = E.Evaluate(S, rules, Cfg({ maxSignals = 2 }), E.NewState())
    EQ(#out, 2, "F the cap holds")

    -- OFF silences; a pinned mode overrides the tier
    local cfg = Cfg({ modes = { PRIEST_DESPERATE = "OFF", PRIEST_PWS = "LOW" } })
    out = E.Evaluate(S, rules, cfg, E.NewState())
    CHECK(not Find(out, "PRIEST_DESPERATE"), "F OFF silences a rule")
    EQ(Find(out, "PRIEST_PWS").tier, 1, "F a pinned mode sets the tier")
    cfg = Cfg({ modes = { PRIEST_INNER_FIRE = "HIGH" } })
    S.auras = {}
    out = E.Evaluate(S, rules, cfg, E.NewState())
    EQ(Find(out, "PRIEST_INNER_FIRE").tier, 3, "F pinned HIGH raises a low rule")

    -- Caution: with reticence 0.4 a 35% rung needs 21%
    local pws = Rule("PRIEST_PWS")
    S = Known(Snap({ inCombat = true, taking = true, hp = 0.3 }), "Power Word: Shield")
    EQ(E.Assess(pws, S, Cfg({ reticence = 0 })), 3, "F balanced: 30% is high")
    EQ(E.Assess(pws, S, Cfg({ reticence = 0.4 })), 2, "F very conservative: 30% is only medium")
    S.hp = 0.2
    EQ(E.Assess(pws, S, Cfg({ reticence = 0.4 })), 3, "F very conservative: 20% is high")
    S.hp = 0.45
    EQ(E.Assess(pws, S, Cfg({ reticence = -0.25 })), 3, "F eager: 45% is already high")

    -- The thrown default for a shipped-off rule is honoured
    local thorns = Rule("DRUID_THORNS")
    S = Known(Snap({ class = "DRUID", inCombat = true, melee = 1 }), "Thorns")
    EQ(E.Assess(thorns, S, Cfg()), nil, "F Thorns ships off")
    EQ(E.Assess(thorns, S, Cfg({ modes = { DRUID_THORNS = "AUTO" } })), 1, "F ... and can be turned on")
end

-- === G: control =============================================================
do
    local rules = D.RulesForClass("PRIEST")
    local S = Known(Snap({ inCombat = true, taking = true, hp = 0.3, melee = 1, control = { stunned = true } }),
        "Power Word: Shield", "Desperate Prayer", "Psychic Scream")
    S.items.ALL_PVP_TRINKET = { name = "Medallion of the Alliance", ready = true, usable = true }
    local out = E.Evaluate(S, rules, Cfg(), E.NewState())
    EQ(#out, 1, "G stunned: exactly one signal")
    EQ(out[1].rule.key, "ALL_PVP_TRINKET", "G ... the trinket")
    EQ(out[1].tier, 3, "G ... high at 30%")
    CHECK(out[1].reason:find("stunned"), "G ... and it says stunned", out[1].reason)

    S.control = { silenced = true }
    out = E.Evaluate(S, rules, Cfg(), E.NewState())
    for _, s in ipairs(out) do
        CHECK(s.rule.item ~= nil, "G silenced: only items", s.rule.key)
    end
    CHECK(Find(out, "ALL_PVP_TRINKET"), "G silenced: trinket offered")

    S.control = { rooted = true }
    out = E.Evaluate(S, rules, Cfg(), E.NewState())
    CHECK(Find(out, "PRIEST_PWS"), "G rooted: spells still offered")
    S.hp = 0.9
    out = E.Evaluate(S, rules, Cfg(), E.NewState())
    EQ(Find(out, "ALL_PVP_TRINKET").tier, 2, "G rooted at 90%: trinket is medium")

    -- Trinket not on a bar: silence, not an error
    S.items = {}
    S.control = { stunned = true }
    out = E.Evaluate(S, rules, Cfg(), E.NewState())
    EQ(#out, 0, "G stunned with no trinket: nothing")
end

-- === H: rules about a teammate, and Mending's reach =======================
do
    local pws, pom = Rule("PRIEST_PWS_ALLY"), Rule("PRIEST_POM")
    EQ(pws.scope, "ally", "H the ally shield is scoped to teammates")
    EQ(pom.scope, "group", "H Mending is scoped to the whole group")
    local function Ally(over)
        local a = { unit = "party1", guid = "g1", name = "Rogue", hp = 1, inRange = true,
            auras = {}, debuffs = {}, taking = false, melee = 0 }
        for k, v in pairs(over or {}) do a[k] = v end
        return a
    end
    local function S2(allies)
        local S = Known(Snap({ inCombat = true, inGroup = true }), "Power Word: Shield", "Prayer of Mending")
        S.allies = allies
        return S
    end

    -- The teammate being hit, not the full one
    local S = S2({ Ally({ name = "Rogue", hp = 0.35, taking = true }), Ally({ unit = "party2", name = "Mage", hp = 1 }) })
    local tier, reason, spell, who = E.Assess(pws, S, Cfg(), E.NewState())
    EQ(tier, 3, "H a teammate at 35% taking hits is a high shield")
    EQ(who and who.name, "Rogue", "H ...on the teammate it is about")
    EQ(spell, "Power Word: Shield", "H ...with the shield")
    CHECK(reason and reason:find("^Rogue: health 35%%"), "H ...and the reason names them first", reason)

    -- Weakened Soul on THEM blocks it; on you it does not
    S = S2({ Ally({ hp = 0.35, taking = true, debuffs = { ["Weakened Soul"] = { expire = 108 } } }) })
    tier = E.Assess(pws, S, Cfg(), E.NewState())
    EQ(tier, nil, "H their Weakened Soul blocks a shield on them")
    S = S2({ Ally({ hp = 0.35, taking = true }) })
    S.debuffs["Weakened Soul"] = { expire = 108 }
    tier = E.Assess(pws, S, Cfg(), E.NewState())
    EQ(tier, 3, "H yours does not")
    -- A shield already on them, any caster's
    S = S2({ Ally({ hp = 0.35, taking = true, auras = { ["Power Word: Shield"] = { expire = 120 } } }) })
    EQ(E.Assess(pws, S, Cfg(), E.NewState()), nil, "H a teammate already shielded is not offered")
    -- Out of reach, dead, or you
    S = S2({ Ally({ hp = 0.35, taking = true, inRange = false }) })
    EQ(E.Assess(pws, S, Cfg(), E.NewState()), nil, "H out of range is not offered")
    S = S2({ Ally({ hp = 0, taking = true, dead = true }) })
    EQ(E.Assess(pws, S, Cfg(), E.NewState()), nil, "H the dead are not offered")
    S = S2({ Ally({ isPlayer = true, name = "Me", hp = 0.3, taking = true }) })
    EQ(E.Assess(pws, S, Cfg(), E.NewState()), nil, "H the ally shield leaves you to the self rule")

    -- The worse of two at the same tier
    S = S2({ Ally({ name = "Rogue", hp = 0.65, taking = true }), Ally({ unit = "party2", name = "Mage", hp = 0.55, taking = true }) })
    local _, _, _, w2 = E.Assess(pws, S, Cfg(), E.NewState())
    EQ(w2 and w2.name, "Mage", "H between two mediums, the lower health")
    -- Two melee on a full-health teammate is already a medium
    S = S2({ Ally({ hp = 1, melee = 2 }) })
    EQ(E.Assess(pws, S, Cfg(), E.NewState()), 2, "H two melee on a teammate is a medium shield")
    -- Just cast: quiet for the grace, whoever it went on
    S = S2({ Ally({ hp = 0.35, taking = true }) })
    S.recentCasts["Power Word: Shield"] = 99.5
    local t3, r3 = E.Assess(pws, S, Cfg(), E.NewState())
    CHECK(t3 == nil and r3 == "just cast", "H a shield just cast quiets the ally rule", r3)
    -- Silenced: nothing but items, ally rules included
    S = S2({ Ally({ hp = 0.35, taking = true }) })
    S.control = { silenced = true }
    EQ(E.Assess(pws, S, Cfg(), E.NewState()), nil, "H silenced quiets the ally rule too")
    -- A pin replaces its tier
    S = S2({ Ally({ hp = 0.9, taking = true }) })
    EQ(E.Assess(pws, S, Cfg({ modes = { PRIEST_PWS_ALLY = "HIGH" } }), E.NewState()), 3,
        "H Always high pins an ally rule too")

    -- Evaluate carries who through the hysteresis
    S = S2({ Ally({ name = "Rogue", hp = 0.35, taking = true }) })
    local out = E.Evaluate(S, { pws }, Cfg(), E.NewState())
    EQ(out[1] and out[1].who and out[1].who.name, "Rogue", "H the signal carries who")

    -- Mending: you count, and one already out quiets it
    S = S2({ Ally({ isPlayer = true, name = "Me", hp = 0.6, taking = true }), Ally({ hp = 1 }) })
    local tp, _, _, wp = E.Assess(pom, S, Cfg(), E.NewState())
    EQ(tp, 2, "H Mending on yourself when you are the one being hit")
    CHECK(wp and wp.isPlayer, "H ...aimed at you")
    S.mineOut = { ["Prayer of Mending"] = true }
    local tq, rq = E.Assess(pom, S, Cfg(), E.NewState())
    CHECK(tq == nil and rq == "already out", "H yours already out on anyone quiets it", rq)
    -- Between two equal, the one it can bounce on from
    S = S2({ Ally({ name = "Lonely", hp = 0.6, taking = true, reach = "NO" }),
             Ally({ unit = "party2", name = "Huddled", hp = 0.6, taking = true, reach = "YES" }) })
    local _, rr, _, wr = E.Assess(pom, S, Cfg(), E.NewState())
    EQ(wr and wr.name, "Huddled", "H between equals, the one with somebody to bounce to")
    CHECK(rr and rr:find("someone within 20 yd"), "H ...and the reason says so", rr)
    S = S2({ Ally({ name = "Lonely", hp = 0.6, taking = true, reach = "NO" }) })
    local _, rn = E.Assess(pom, S, Cfg(), E.NewState())
    CHECK(rn and rn:find("it will not bounce"), "H a lone holder is warned about", rn)

    -- Reach, from real positions
    local function P(x, y, inst) return { pos = { x = x, y = y, inst = inst or 1 } } end
    local holder = P(0, 0)
    local st, n = E.BounceReach(holder, { holder, P(10, 0), P(100, 0) })
    CHECK(st == "YES" and n == 1, "H one teammate within twenty yards is a bounce", tostring(st) .. n)
    st = E.BounceReach(holder, { holder, P(21, 0), P(100, 0) })
    EQ(st, "NO", "H everyone further than twenty is no bounce")
    st = E.BounceReach(holder, { holder, P(5, 0, 2) })
    EQ(st, nil, "H another instance is not a distance")
    st = E.BounceReach(holder, { holder })
    EQ(st, nil, "H alone, there is nothing to say")
    st = E.BounceReach(holder, { holder, P(30, 0), { dead = true, pos = { x = 1, y = 0, inst = 1 } } })
    EQ(st, "NO", "H the dead do not take a bounce")

    -- Reach, from range bounds only (no positions: an arena)
    local me = { lo = 0, hi = 0 }
    st = E.BounceReach(me, { me, { lo = 30 }, { lo = 40 } })
    EQ(st, "NO", "H on you, and everyone outside thirty yards: no bounce, provably")
    st = E.BounceReach(me, { me, { lo = 0, hi = 30 } })
    EQ(st, nil, "H inside thirty is not inside twenty: unknown, never claimed")
    st = E.BounceReach({ lo = 0, hi = 30 }, { me, { lo = 0, hi = 30 } })
    EQ(st, nil, "H two people each within thirty of you: unknown")
    st = E.BounceReach({ lo = 0, hi = 8 }, { me, { lo = 0, hi = 30 } })
    EQ(st, "YES", "H a holder within eight of you can bounce to you")
    local least, most = E.Between({ lo = 40 }, { lo = 0, hi = 10 })
    CHECK(least == 30 and most == math.huge, "H the triangle: forty out and ten in are thirty apart at least",
        tostring(least) .. " " .. tostring(most))
end

io.write(string.format("%d checks, %d failed\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
