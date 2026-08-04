-- Commander Meters headless harness (luajit).
-- Stage A: engine correctness against a self-accounting fixture (§7 invariants)
-- Stage B: throughput + repaint-cost measurement
-- Stage C: UI smoke — real CommanderSettingsUI/CommanderEvents + DB + UI files
--          under a permissive WoW mock; drives slashes, menus, repaint, resets.

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

local function eq(a, b, label)
    CHECK(a == b, label, tostring(a) .. " ~= " .. tostring(b))
end

local function near(a, b, label)
    CHECK(math.abs(a - b) < 1e-9, label, tostring(a) .. " ~= " .. tostring(b))
end

-- ===========================================================================
-- Stage A/B environment: minimal stubs (engine touches almost no WoW API)
-- ===========================================================================

local printLog = {}
local realPrint = print
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
    printLog[#printLog + 1] = table.concat(parts, " ")
end

local feignTokens = {}
local hpByToken = {}
function UnitIsFeignDeath(token) return feignTokens[token] or false end
function UnitHealth(token) return (hpByToken[token] and hpByToken[token][1]) or 5000 end
function UnitHealthMax(token) return (hpByToken[token] and hpByToken[token][2]) or 8000 end

local function LoadEngine()
    CommanderMetersEngine = nil
    local chunk = assert(loadfile(METERS .. "/CommanderMetersEngine.lua"))
    chunk()
    return CommanderMetersEngine
end

-- Combat-log flag constants (engine falls back to these same hex values)
local FP_MINE  = 0x511   -- mine + friendly + player-controlled + TYPE_PLAYER
local FP_PARTY = 0x512   -- party-affiliated player
local FPET     = 0x1112  -- party pet (TYPE_PET)
local FTOTEM   = 0x4112  -- party totem (TYPE_OBJECT)
local FGUARD   = 0x2112  -- party guardian (TYPE_GUARDIAN)
local FENEMY   = 0xA48   -- hostile NPC
local FNONE    = 0x80000000

-- ===========================================================================
-- Self-accounting fixture: expected values accumulate alongside the events
-- ===========================================================================

local Fixture = {}
Fixture.__index = Fixture

local function NewFixture(E, db)
    return setmetatable({
        E = E, db = db,
        exp = {},          -- fightNo -> per-actor expected {dmg, heal, absorb, taken, deaths, misses}
        expTotals = {},    -- fightNo -> {dmg, heal, dtaken, deaths}
        fightNo = 0,
    }, Fixture)
end

function Fixture:bucket(fight, guid, field, amount)
    local f = self.exp[fight]
    if not f then f = {}; self.exp[fight] = f end
    local a = f[guid]
    if not a then
        a = { dmg = 0, heal = 0, absorb = 0, taken = 0, deaths = 0, misses = 0,
            ints = 0, dispels = 0, ccb = 0 }
        f[guid] = a
    end
    a[field] = a[field] + amount
    local t = self.expTotals[fight]
    if not t then t = { dmg = 0, heal = 0, dtaken = 0, deaths = 0 }; self.expTotals[fight] = t end
    if field == "dmg" then t.dmg = t.dmg + amount
    elseif field == "heal" or field == "absorb" then t.heal = t.heal + amount
    elseif field == "taken" then t.dtaken = t.dtaken + amount
    elseif field == "deaths" then t.deaths = t.deaths + amount end
end

-- Damage credit rule mirroring the engine's: tracked players credit
-- themselves; minions credit the explicit owner param; enemies credit nobody
local function CreditGuid(sg, sf, owner)
    if owner then return owner end
    if sf == 0x511 or sf == 0x512 then return sg end
    return nil
end

function Fixture:spellDamage(ts, sg, sn, sf, dg, dn, df, spellId, spell, amount, absorbed, crit, owner, dstOwned)
    self.E.OnCleu(ts, "SPELL_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0,
        spellId, spell, 4, amount, 0, 4, 0, 0, absorbed or 0, crit or false, false, false, false)
    local credit = CreditGuid(sg, sf, owner)
    if credit then self:bucket(self.fightNo, credit, "dmg", amount + (absorbed or 0)) end
    if dstOwned then self:bucket(self.fightNo, dg, "taken", amount + (absorbed or 0)) end
end

function Fixture:swing(ts, sg, sn, sf, dg, dn, df, amount, absorbed, crit, owner, dstOwned)
    self.E.OnCleu(ts, "SWING_DAMAGE", nil, sg, sn, sf, 0, dg, dn, df, 0,
        amount, 0, 1, 0, 0, absorbed or 0, crit or false, false, false, false)
    local credit = CreditGuid(sg, sf, owner)
    if credit then self:bucket(self.fightNo, credit, "dmg", amount + (absorbed or 0)) end
    if dstOwned then self:bucket(self.fightNo, dg, "taken", amount + (absorbed or 0)) end
end

function Fixture:miss(ts, sg, sn, sf, dg, dn, df, missType, amountMissed, owner, dstOwned)
    self.E.OnCleu(ts, "SWING_MISSED", nil, sg, sn, sf, 0, dg, dn, df, 0,
        missType, false, amountMissed or 0, false)
    local credit = CreditGuid(sg, sf, owner)
    if missType == "ABSORB" and amountMissed and amountMissed > 0 then
        if credit then self:bucket(self.fightNo, credit, "dmg", amountMissed) end
        if dstOwned then self:bucket(self.fightNo, dg, "taken", amountMissed) end
    elseif credit then
        self:bucket(self.fightNo, credit, "misses", 1)
    end
end

function Fixture:heal(ts, sg, sn, sf, dg, dn, df, spellId, spell, amount, over, crit, owner, dstOwned)
    self.E.OnCleu(ts, "SPELL_HEAL", nil, sg, sn, sf, 0, dg, dn, df, 0,
        spellId, spell, 2, amount, over or 0, 0, crit or false)
    self:bucket(self.fightNo, owner or sg, "heal", amount - (over or 0))
end

-- SPELL_ABSORBED, spell-triggered form
function Fixture:absorbSpell(ts, ag, an, af, dg, dn, df, cg, cn, cf, amount)
    self.E.OnCleu(ts, "SPELL_ABSORBED", nil, ag, an, af, 0, dg, dn, df, 0,
        27682, "Shadow Bolt", 32, cg, cn, cf, 0, 17, "Power Word: Shield", 2, amount, false)
    self:bucket(self.fightNo, cg, "absorb", amount)
end

-- SPELL_ABSORBED, swing-triggered form
function Fixture:absorbSwing(ts, ag, an, af, dg, dn, df, cg, cn, cf, amount)
    self.E.OnCleu(ts, "SPELL_ABSORBED", nil, ag, an, af, 0, dg, dn, df, 0,
        cg, cn, cf, 0, 17, "Power Word: Shield", 2, amount, false)
    self:bucket(self.fightNo, cg, "absorb", amount)
end

function Fixture:death(ts, dg, dn, df)
    self.E.OnCleu(ts, "UNIT_DIED", nil, nil, nil, FNONE, 0, dg, dn, df, 0, 0, false)
    self:bucket(self.fightNo, dg, "deaths", 1)
end

function Fixture:summon(ts, sg, sn, sf, dg, dn, df, spellId, spell)
    self.E.OnCleu(ts, "SPELL_SUMMON", nil, sg, sn, sf, 0, dg, dn, df, 0, spellId, spell, 8)
end

function Fixture:environmental(ts, dg, dn, df, envType, amount)
    self.E.OnCleu(ts, "ENVIRONMENTAL_DAMAGE", nil, nil, nil, FNONE, 0, dg, dn, df, 0,
        envType, amount, 0, 1, 0, 0, 0, false, false, false)
    self:bucket(self.fightNo, dg, "taken", amount)
end

function Fixture:interrupt(ts, sg, sn, sf, dg, dn, df, what, owner)
    self.E.OnCleu(ts, "SPELL_INTERRUPT", nil, sg, sn, sf, 0, dg, dn, df, 0,
        6552, "Pummel", 1, 999, what, 32)
    self:bucket(self.fightNo, owner or sg, "ints", 1)
end

function Fixture:dispel(ts, sg, sn, sf, dg, dn, df, what, stolen, owner)
    self.E.OnCleu(ts, stolen and "SPELL_STOLEN" or "SPELL_DISPEL", nil,
        sg, sn, sf, 0, dg, dn, df, 0,
        527, "Dispel Magic", 2, 888, what, 32, "DEBUFF")
    self:bucket(self.fightNo, owner or sg, "dispels", 1)
end

-- counted: whether the harness expects the engine to count it (CC filter)
function Fixture:ccbreak(ts, sg, sn, sf, dg, dn, df, aura, counted, viaSpell)
    if viaSpell then
        self.E.OnCleu(ts, "SPELL_AURA_BROKEN_SPELL", nil, sg, sn, sf, 0, dg, dn, df, 0,
            6770, aura, 1, 686, "Shadow Bolt", 32, "DEBUFF")
    else
        self.E.OnCleu(ts, "SPELL_AURA_BROKEN", nil, sg, sn, sf, 0, dg, dn, df, 0,
            118, aura, 64, "DEBUFF")
    end
    if counted then
        self:bucket(self.fightNo, sg, "ccb", 1)
    end
end

-- ===========================================================================
-- The canonical fixture fight: 4 players, a pet, a totem, a guardian, crits,
-- misses, both absorb forms, overheal, environmental damage, one death.
-- ===========================================================================

local A = "Player-0-AAAA" -- warrior
local B = "Player-0-BBBB" -- warlock (owns pet)
local C = "Player-0-CCCC" -- priest (dies)
local D = "Player-0-DDDD" -- shaman (owns totem + guardian)
local PET = "Pet-0-0-0-0-417-0001"
local TOTEM = "Creature-0-0-0-0-2523-0001"
local GUARD = "Creature-0-0-0-0-15438-0001"
local ORPHAN = "Pet-0-0-0-0-999-0002"
local M1 = "Creature-0-0-0-0-9001-0001"
local M2 = "Creature-0-0-0-0-9002-0001"

local function SetupRoster(E)
    E.SetRosterEntry(A, "player", "Vanguard", "WARRIOR")
    E.SetRosterEntry(B, "party1", "Diabolist", "WARLOCK")
    E.SetRosterEntry(C, "party2", "Confessor", "PRIEST")
    E.SetRosterEntry(D, "party3", "Farseer", "SHAMAN")
    E.SetCCNames({ Polymorph = true, Sap = true, Fear = true })
end

local T0 = 1000000

local function RunFight1(fx)
    local E = fx.E
    fx.fightNo = 1
    fx:summon(T0 - 5, B, "Diabolist", FP_PARTY, PET, "Grimtongue", FPET, 688, "Summon Felguard")
    fx:summon(T0 - 4, D, "Farseer", FP_PARTY, TOTEM, "Searing Totem", FTOTEM, 3599, "Searing Totem")
    -- Summons land before any fight opens: they must not open one
    CHECK(not E.InFight(), "A: summons do not open a fight")

    -- t=0: warrior swings open the fight
    fx:swing(T0 + 0, A, "Vanguard", FP_MINE, M1, "Gnarl", FENEMY, 400, 0, false)
    CHECK(E.InFight(), "A: damage opens the fight")

    for i = 1, 9 do
        fx:swing(T0 + i, A, "Vanguard", FP_MINE, M1, "Gnarl", FENEMY, 400 + i, 0, i % 3 == 0)
    end
    for i = 0, 7 do
        fx:spellDamage(T0 + 1 + i * 2, B, "Diabolist", FP_PARTY, M1, "Gnarl", FENEMY,
            686, "Shadow Bolt", 900 + i, (i == 3) and 150 or 0, i % 2 == 0)
    end
    -- Pet, totem, and guardian damage folds into the owners
    for i = 0, 5 do
        fx:swing(T0 + 2 + i * 3, PET, "Grimtongue", FPET, M2, "Gnarl Guard", FENEMY,
            210 + i, 0, false, B)
        fx:spellDamage(T0 + 3 + i * 3, TOTEM, "Searing Totem", FTOTEM, M1, "Gnarl", FENEMY,
            3606, "Attack", 55 + i, 0, false, D)
    end
    fx:summon(T0 + 9, D, "Farseer", FP_PARTY, GUARD, "Greater Fire Elemental", FGUARD, 32982, "Fire Elemental Totem")
    fx:spellDamage(T0 + 10, GUARD, "Greater Fire Elemental", FGUARD, M1, "Gnarl", FENEMY,
        32981, "Fire Blast", 500, 0, false, D)
    -- An orphan pet nobody summoned: stays visible as its own actor, loudly
    fx:swing(T0 + 11, ORPHAN, "Stray", FPET, M1, "Gnarl", FENEMY, 77, 0, false, ORPHAN)

    fx:miss(T0 + 12, A, "Vanguard", FP_MINE, M1, "Gnarl", FENEMY, "DODGE")
    -- The tank dodges an enemy swing: symmetric miss on the taken record
    fx:miss(T0 + 12.5, M1, "Gnarl", FENEMY, A, "Vanguard", FP_MINE, "DODGE")
    -- Enemy hits the tank (partial absorb on the damage event)
    fx:swing(T0 + 13, M1, "Gnarl", FENEMY, A, "Vanguard", FP_MINE, 1500, 350, false, nil, true)
    -- The priest's shield fully eats a swing on C: absorb-miss (attacker side)
    -- + SPELL_ABSORBED (healer side), then the same pair in spell form
    fx:miss(T0 + 14, M2, "Gnarl Guard", FENEMY, C, "Confessor", FP_MINE, "ABSORB", 620, nil, true)
    fx:absorbSwing(T0 + 14, M2, "Gnarl Guard", FENEMY, C, "Confessor", FP_MINE, C, "Confessor", FP_MINE, 620)
    fx:absorbSpell(T0 + 15, M1, "Gnarl", FENEMY, C, "Confessor", FP_MINE, C, "Confessor", FP_MINE, 480)
    -- Heals: crit with overheal, then a periodic tick
    fx:heal(T0 + 16, C, "Confessor", FP_MINE, A, "Vanguard", FP_MINE, 2060, "Greater Heal", 2400, 700, true)
    fx:heal(T0 + 17, C, "Confessor", FP_MINE, A, "Vanguard", FP_MINE, 139, "Renew", 300, 0, false)
    -- Falling damage on the warrior
    fx:environmental(T0 + 18, A, "Vanguard", FP_MINE, "Falling", 260)
    -- Hit-table detail: a glancing, partially resisted+blocked warrior swing
    -- and a crushing blow coming back
    E.OnCleu(T0 + 18.2, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        200, 0, 1, 50, 30, 0, false, true, false, false)
    fx:bucket(1, A, "dmg", 200)
    E.OnCleu(T0 + 18.4, "SWING_DAMAGE", nil, M1, "Gnarl", FENEMY, 0, A, "Vanguard", FP_MINE, 0,
        2000, 0, 1, 0, 0, 0, false, false, true, false)
    fx:bucket(1, A, "taken", 2000)
    -- Utility: interrupts (one by the pet, folding to the warlock), a
    -- dispel, a steal, and CC breaks (one filtered out as non-CC)
    fx:interrupt(T0 + 18.5, A, "Vanguard", FP_MINE, M1, "Gnarl", FENEMY, "Gnarl Bolt")
    fx:interrupt(T0 + 18.6, PET, "Grimtongue", FPET, M2, "Gnarl Guard", FENEMY, "Guard Heal", B)
    fx:dispel(T0 + 18.7, C, "Confessor", FP_MINE, A, "Vanguard", FP_MINE, "Dummy Curse")
    fx:dispel(T0 + 18.8, D, "Farseer", FP_PARTY, M1, "Gnarl", FENEMY, "Gnarl Might", true)
    fx:ccbreak(T0 + 18.85, A, "Vanguard", FP_MINE, M2, "Gnarl Guard", FENEMY, "Polymorph", true)
    fx:ccbreak(T0 + 18.9, B, "Diabolist", FP_PARTY, M2, "Gnarl Guard", FENEMY, "Sap", true, true)
    fx:ccbreak(T0 + 18.95, A, "Vanguard", FP_MINE, M2, "Gnarl Guard", FENEMY, "Ice Armor", false)
    -- The priest gets focused and dies (one hit crits — taken-side crit)
    for i = 0, 4 do
        fx:spellDamage(T0 + 19 + i, M1, "Gnarl", FENEMY, C, "Confessor", FP_MINE,
            15621, "Skull Crack", 900 + i * 100, 0, i == 4, nil, true)
    end
    fx:death(T0 + 24, C, "Confessor", FP_MINE)
end

local function RunFight2(fx)
    fx.fightNo = 2
    local base = T0 + 40
    for i = 0, 4 do
        fx:swing(base + i, A, "Vanguard", FP_MINE, M2, "Gnarl Guard", FENEMY, 300 + i, 0, false)
    end
end

-- Segment checkers ---------------------------------------------------------

local function SumRecords(map)
    local total = 0
    for _, rec in pairs(map) do
        total = total + (type(rec) == "table" and rec.total or rec)
    end
    return total
end

local function SumSeries(series)
    if not series then return 0 end
    local total = 0
    for _, v in pairs(series) do total = total + v end
    return total
end

local function CheckSegment(E, seg, expected, expTotals, label, wantSeries)
    if not seg then CHECK(false, label .. ": segment exists") return end
    local sumDmg, sumHeal, sumTaken, sumDeaths = 0, 0, 0, 0
    for guid, exp in pairs(expected) do
        local a = seg.actors[guid]
        if exp.dmg > 0 or exp.heal > 0 or exp.absorb > 0 or exp.taken > 0 or exp.deaths > 0 or exp.misses > 0 then
            if not a then
                CHECK(false, label .. ": actor present " .. guid)
            else
                eq(a.dmg, exp.dmg, label .. ": dmg " .. guid)
                eq(a.heal + a.absorb, exp.heal + exp.absorb, label .. ": heal+absorb " .. guid)
                eq(a.dtaken, exp.taken, label .. ": taken " .. guid)
                eq(a.deaths, exp.deaths, label .. ": deaths " .. guid)
                eq(a.ints, exp.ints, label .. ": interrupts " .. guid)
                eq(a.dispels, exp.dispels, label .. ": dispels " .. guid)
                eq(a.ccb, exp.ccb, label .. ": cc breaks " .. guid)
                eq(SumRecords(a.intSpells), a.ints, label .. ": int records sum " .. guid)
                eq(SumRecords(a.dispelSpells), a.dispels, label .. ": dispel records sum " .. guid)
                eq(SumRecords(a.ccSpells), a.ccb, label .. ": cc records sum " .. guid)
                -- Invariant: per-ability == actor total == per-target
                eq(SumRecords(a.spells), a.dmg, label .. ": spells sum == dmg " .. guid)
                eq(SumRecords(a.targets), a.dmg, label .. ": targets sum == dmg " .. guid)
                eq(SumRecords(a.heals), a.heal + a.absorb, label .. ": heals sum " .. guid)
                eq(SumRecords(a.taken), a.dtaken, label .. ": taken sum " .. guid)
                eq(SumRecords(a.sources), a.dtaken, label .. ": sources sum " .. guid)
                -- Invariant: series buckets sum to totals
                if wantSeries then
                    eq(SumSeries(a.sDmg), a.dmg, label .. ": sDmg sum " .. guid)
                    eq(SumSeries(a.sHeal), a.heal + a.absorb, label .. ": sHeal sum " .. guid)
                    eq(SumSeries(a.sTaken), a.dtaken, label .. ": sTaken sum " .. guid)
                else
                    CHECK(a.sDmg == nil and a.sHeal == nil and a.sTaken == nil,
                        label .. ": no series " .. guid)
                end
            end
        end
        sumDmg = sumDmg + exp.dmg
        sumHeal = sumHeal + exp.heal + exp.absorb
        sumTaken = sumTaken + exp.taken
        sumDeaths = sumDeaths + exp.deaths
    end
    eq(seg.totals.dmg, sumDmg, label .. ": totals.dmg")
    eq(seg.totals.heal, sumHeal, label .. ": totals.heal")
    eq(seg.totals.dtaken, sumTaken, label .. ": totals.dtaken")
    eq(seg.totals.deaths, sumDeaths, label .. ": totals.deaths")
    eq(seg.totals.dmg, expTotals.dmg, label .. ": fixture totals.dmg")
end

local function RunFixture(E, db)
    E.Init(db, T0 - 100)
    SetupRoster(E)
    local fx = NewFixture(E, db)
    RunFight1(fx)

    -- Mid-fight checkpoint: Current is live and self-consistent
    local liveSeg = E.GetCurrent()
    CheckSegment(E, liveSeg, fx.exp[1], fx.expTotals[1], "MID", true)

    -- Close fight 1 (player never entered real combat in the harness;
    -- SetPlayerCombat(false) is the default state)
    E.Tick(T0 + 24 + 3)
    CHECK(not E.InFight(), "A: fight 1 closed by idle timeout")
    CHECK(E.GetSegment("last") == liveSeg, "A: Current became Last (same table)")
    eq(liveSeg.dur, 24, "A: duration stamped at last event")
    CHECK(liveSeg.name == "Gnarl", "A: fight named after main enemy", liveSeg.name)

    RunFight2(fx)
    CHECK(E.InFight(), "A: fight 2 open")
    E.Tick(T0 + 44 + 4)
    CHECK(not E.InFight(), "A: fight 2 closed")

    return fx
end

-- ===========================================================================
-- STAGE A
-- ===========================================================================

local dbA = { IdleTimeout = 3 }
local E = LoadEngine()
local fx = RunFixture(E, dbA)

local last = E.GetSegment("last")
local f1 = E.GetSegment(1)
local f2 = E.GetSegment(2)
CHECK(f1 and f2 and last == f2, "A: fight list holds both fights, Last == newest")

CheckSegment(E, f1, fx.exp[1], fx.expTotals[1], "F1", true)
CheckSegment(E, f2, fx.exp[2], fx.expTotals[2], "F2", true)

-- Overall == sum of segments (per mode and per actor), and keeps no series
local overall = E.GetOverall()
do
    local expOverall, expTotals = {}, { dmg = 0, heal = 0, dtaken = 0, deaths = 0 }
    for fight = 1, 2 do
        for guid, exp in pairs(fx.exp[fight]) do
            local o = expOverall[guid]
            if not o then
                o = { dmg = 0, heal = 0, absorb = 0, taken = 0, deaths = 0, misses = 0,
                    ints = 0, dispels = 0, ccb = 0 }
                expOverall[guid] = o
            end
            for k, v in pairs(exp) do o[k] = o[k] + v end
        end
        for k, v in pairs(fx.expTotals[fight]) do expTotals[k] = expTotals[k] + v end
    end
    CheckSegment(E, overall, expOverall, expTotals, "OVERALL", false)
end

-- Pets/totems/guardians: exactly once, under the owner
CHECK(f1.actors[PET] == nil and f1.actors[TOTEM] == nil and f1.actors[GUARD] == nil,
    "A: no standalone pet/totem/guardian actors")
CHECK(f1.actors[B].spells["Grimtongue: Melee"] ~= nil, "A: pet damage keyed under owner")
CHECK(f1.actors[D].spells["Searing Totem: Attack"] ~= nil, "A: totem damage keyed under owner")
CHECK(f1.actors[D].spells["Greater Fire Elemental: Fire Blast"] ~= nil, "A: guardian damage keyed under owner")
CHECK(f1.actors[ORPHAN] ~= nil, "A: orphan minion stays visible as its own actor")
do
    local found = false
    for key in pairs(E.GetAnomalies()) do
        if key:find("unknown owner") then found = true end
    end
    CHECK(found, "A: orphan minion raised a loud anomaly")
end

-- Ability detail: crits/misses/min/max recorded
do
    local sb = f1.actors[B].spells["Shadow Bolt"]
    eq(sb.count, 8, "A: shadow bolt hit count")
    eq(sb.crit, 4, "A: shadow bolt crit count")
    eq(sb.min, 900, "A: shadow bolt min")
    eq(sb.max, 903 + 150, "A: shadow bolt max (incl. absorbed part)")
    eq(sb.absorbed, 150, "A: shadow bolt absorbed sum")
    local swings = f1.actors[A].spells["Melee"]
    eq(swings.miss, 1, "A: warrior dodge recorded as miss")
    -- Full-absorb hits count as damage on the attacker
    local guardSwing = f1.actors[M2] == nil
    CHECK(guardSwing, "A: enemy actors never become bar actors")
end

-- Absorbs: attacker side vs healer side, no double count
eq(f1.actors[C].absorb, 620 + 480, "A: healer absorb credit (both CLEU forms)")
CHECK(f1.actors[C].heals["Power Word: Shield"] ~= nil
    and f1.actors[C].heals["Power Word: Shield"].total == 1100,
    "A: absorb credited as PW:S healing record")
eq(f1.actors[C].heal, 1700 + 300, "A: priest effective healing excludes overheal")
eq(f1.actors[C].overheal, 700, "A: overheal tracked")

-- Damage taken symmetry + environmental
eq(f1.actors[A].dtaken, 1850 + 260 + 2000, "A: warrior taken incl. environmental + crush")
CHECK(f1.actors[A].taken["Falling"] ~= nil, "A: environmental keyed by type")
CHECK(f1.actors[A].sources["Environment"] ~= nil or f1.actors[A].sources["Falling"] ~= nil,
    "A: environmental source recorded")
-- Taken-side detail stats: crit, absorbed, and enemy misses all land
eq(f1.actors[C].taken["Skull Crack"].crit, 1, "A: taken record counts crits")
eq(f1.actors[A].taken["Melee"].absorbed, 350, "A: taken record counts partial absorb")
eq(f1.actors[C].taken["Melee"].absorbed, 620, "A: taken record counts full absorb")
eq(f1.actors[A].taken["Melee"].miss, 1, "A: enemy miss recorded on the victim")

-- Hit-table detail: glancing/resisted/blocked on the attacker, crushing on
-- the victim
eq(f1.actors[A].spells["Melee"].glance, 1, "A: glancing counted on the attacker")
eq(f1.actors[A].spells["Melee"].resisted, 50, "A: partial resist summed")
eq(f1.actors[A].spells["Melee"].blocked, 30, "A: partial block summed")
eq(f1.actors[A].taken["Melee"].crush, 1, "A: crushing counted on the victim")

-- Spell ids captured on records and the death trail (icon source)
eq(f1.actors[B].spells["Shadow Bolt"].id, 686, "A: damage record carries spell id")
CHECK(f1.actors[A].spells["Melee"].id == nil, "A: melee record has no id")
eq(f1.actors[C].taken["Skull Crack"].id, 15621, "A: taken record carries spell id")
eq(f1.actors[C].heals["Power Word: Shield"].id, 17, "A: absorb credit carries the shield id")
eq(f1.actors[C].heals["Greater Heal"].id, 2060, "A: heal record carries spell id")
eq(f1.actors[B].intSpells["Guard Heal"].id, 999, "A: interrupt record carries the target spell id")
do
    local trail = f1.deaths[1].log
    CHECK(trail[#trail].id == 15621, "A: death trail entries carry spell ids")
end

-- Utility modes: interrupts (pet folds to owner), dispels + steals, CC
-- breaks with the non-CC aura filtered out
eq(f1.actors[A].ints, 1, "A: warrior interrupt")
eq(f1.actors[B].ints, 1, "A: pet interrupt folded to the warlock")
CHECK(f1.actors[B].intSpells["Guard Heal"] ~= nil, "A: interrupted spell keyed")
eq(f1.actors[C].dispels, 1, "A: priest dispel")
eq(f1.actors[D].dispels, 1, "A: spellsteal counts as a dispel")
eq(f1.actors[A].ccb, 1, "A: polymorph break counted")
eq(f1.actors[B].ccb, 1, "A: sap break via spell counted")
CHECK(f1.actors[A].ccSpells["Ice Armor"] == nil, "A: non-CC aura break filtered")

-- Kill/wipe tagging: mid-fight, post-close within the window, and never
-- rewriting older history
do
    local E5 = LoadEngine()
    E5.Init({ IdleTimeout = 3 }, T0)
    SetupRoster(E5)
    E5.OnCleu(T0 + 1, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    E5.OnEncounterEnd("Gruul the Dragonkiller", 1, T0 + 2)
    CHECK(E5.GetCurrent().name == "Gruul the Dragonkiller", "A: encounter end names the open fight")
    CHECK(E5.GetCurrent().success == true, "A: kill tagged on the open fight")
    E5.Tick(T0 + 6)
    CHECK(E5.GetFights()[1].success == true, "A: tag survives the close")
    -- Second fight: tag arrives just after the idle close
    E5.OnCleu(T0 + 20, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    E5.Tick(T0 + 24)
    E5.OnEncounterEnd("High King Maulgar", 0, T0 + 26)
    CHECK(E5.GetFights()[1].name == "High King Maulgar", "A: post-close tag lands on the newest fight")
    CHECK(E5.GetFights()[1].success == false, "A: wipe tagged")
    -- Too late: must not rewrite history
    E5.OnEncounterEnd("Wrong Boss", 1, T0 + 60)
    CHECK(E5.GetFights()[1].name == "High King Maulgar", "A: stale encounter end ignored")
end

-- Death log: last events with hp, in order
do
    eq(#f1.deaths, 1, "A: one death recorded")
    local d = f1.deaths[1]
    eq(d.guid, C, "A: the priest died")
    CHECK(#d.log > 0 and #d.log <= 10, "A: death log bounded at 10", #d.log)
    local ordered = true
    for i = 2, #d.log do
        if d.log[i].ts < d.log[i - 1].ts then ordered = false end
    end
    CHECK(ordered, "A: death log in chronological order")
    local blow = d.log[#d.log]
    eq(blow.what, "Skull Crack", "A: killing blow is the last logged hit")
    CHECK(blow.hp == 5000 and blow.hpMax == 8000, "A: hp snapshot captured")
end

-- Feign death: UNIT_DIED for a feigning tracked player is ignored
feignTokens["party1"] = true
E.OnCleu(T0 + 60, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
    100, 0, 1, 0, 0, 0, false, false, false, false)
E.OnCleu(T0 + 61, "UNIT_DIED", nil, nil, nil, FNONE, 0, B, "Diabolist", FP_PARTY, 0, 0, false)
CHECK(E.GetCurrent().actors[B] == nil or E.GetCurrent().actors[B].deaths == 0,
    "A: feign death not counted")
feignTokens["party1"] = nil
E.Tick(T0 + 65)

-- Reset Current mid-fight: current restarts, Overall intact
do
    local overallDmgBefore = E.GetOverall().totals.dmg
    E.OnCleu(T0 + 80, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        500, 0, 1, 0, 0, 0, false, false, false, false)
    local cur = E.GetCurrent()
    eq(cur.totals.dmg, 500, "A: fight 4 recording")
    local overallAfterHit = E.GetOverall().totals.dmg
    eq(overallAfterHit, overallDmgBefore + 500, "A: overall accumulated the hit")
    E.ResetCurrent(T0 + 81)
    local fresh = E.GetCurrent()
    CHECK(fresh ~= nil and fresh ~= cur, "A: reset current started a fresh segment")
    eq(fresh.totals.dmg, 0, "A: reset current zeroed the pull")
    eq(fresh.id, cur.id, "A: reset current keeps the fight number")
    eq(E.GetOverall().totals.dmg, overallAfterHit, "A: reset current left Overall intact")
    E.OnCleu(T0 + 82, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        111, 0, 1, 0, 0, 0, false, false, false, false)
    eq(E.GetCurrent().totals.dmg, 111, "A: fresh segment records after reset")
    E.Tick(T0 + 86)
end

-- Reset All mid-fight: everything cleared, in-progress fight restarts fresh
do
    E.OnCleu(T0 + 100, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        250, 0, 1, 0, 0, 0, false, false, false, false)
    E.SetPlayerCombat(true, T0 + 100)
    E.ResetAll(T0 + 101)
    CHECK(E.GetOverall().totals.dmg == 0 and E.GetOverall().totals.heal == 0,
        "A: reset all cleared overall")
    eq(#E.GetFights(), 0, "A: reset all cleared the fight list")
    CHECK(E.InFight(), "A: reset all mid-combat reopens a live fight")
    eq(E.GetCurrent().id, 1, "A: fight numbering restarted")
    E.OnCleu(T0 + 102, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        300, 0, 1, 0, 0, 0, false, false, false, false)
    eq(E.GetCurrent().totals.dmg, 300, "A: recording continues after reset all")
    eq(E.GetOverall().totals.dmg, 300, "A: overall accumulates after reset all")
    E.SetPlayerCombat(false, T0 + 103)
    E.Tick(T0 + 107)
end

-- Retention: 12 fights -> 10 kept, series only on newest 5
do
    E.ResetAll(T0 + 200)
    for f = 1, 12 do
        local base = T0 + 200 + f * 20
        E.OnCleu(base, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
            100 + f, 0, 1, 0, 0, 0, false, false, false, false)
        E.Tick(base + 5)
    end
    local list = E.GetFights()
    eq(#list, 10, "A: fight ring capped at 10")
    eq(list[1].id, 12, "A: newest fight first")
    eq(list[10].id, 3, "A: oldest kept fight is #3")
    for i = 1, 10 do
        local hasSeries = list[i].actors[A].sDmg ~= nil
        if i <= 5 then
            CHECK(hasSeries, "A: series kept on newest 5 (#" .. list[i].id .. ")")
        else
            CHECK(not hasSeries, "A: series dropped beyond 5 (#" .. list[i].id .. ")")
        end
    end
    -- Overall keeps totals even for pruned fights: 12 fights recorded
    local sum = 0
    for f = 1, 12 do sum = sum + 100 + f end
    eq(E.GetOverall().totals.dmg, sum, "A: overall survives fight pruning")
end

-- Auto-reset on new fight
do
    local dbAuto = { IdleTimeout = 3, AutoResetOnNewFight = true }
    local E2 = LoadEngine()
    E2.Init(dbAuto, T0)
    E2.OnCleu(T0 + 1, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    E2.Tick(T0 + 5)
    E2.OnCleu(T0 + 20, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        200, 0, 1, 0, 0, 0, false, false, false, false)
    eq(E2.GetOverall().totals.dmg, 200, "A: auto-reset-on-new-fight wiped the old pull")
    eq(#E2.GetFights(), 0, "A: auto-reset cleared the fight list")
    eq(E2.GetCurrent().id, 1, "A: auto-reset restarted numbering")
end

-- SPELL_ABSORBED on a clean state opens the fight (shielded-puller opener)
do
    E.ResetAll(T0 + 700)
    E.OnCleu(T0 + 700, "SPELL_ABSORBED", nil, M1, "Gnarl", FENEMY, 0, C, "Confessor", FP_MINE, 0,
        27682, "Shadow Bolt", 32, C, "Confessor", FP_MINE, 0, 17, "Power Word: Shield", 2, 480, false)
    CHECK(E.InFight(), "A: absorb event opens the fight")
    eq(E.GetCurrent().actors[C].absorb, 480, "A: opener absorb credited to the healer")
    E.Tick(T0 + 704)
    CHECK(not E.InFight(), "A: absorb-opened fight closes")
end

-- ResetCurrent folds the discarded stretch's elapsed time into Overall
do
    E.ResetAll(T0 + 800)
    E.OnCleu(T0 + 800, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        1000, 0, 1, 0, 0, 0, false, false, false, false)
    E.OnCleu(T0 + 900, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        1000, 0, 1, 0, 0, 0, false, false, false, false)
    E.ResetCurrent(T0 + 900)
    E.OnCleu(T0 + 901, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        500, 0, 1, 0, 0, 0, false, false, false, false)
    E.Tick(T0 + 905)
    eq(E.GetOverall().totals.dmg, 2500, "A: overall keeps pre-reset damage")
    eq(E.SegmentDuration(E.GetOverall(), T0 + 905), 101,
        "A: overall keeps pre-reset elapsed time (no DPS inflation)")
end

-- A reset in the idle window must not spawn a phantom empty fight
do
    E.ResetAll(T0 + 1000)
    E.OnCleu(T0 + 1000, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    E.Tick(T0 + 1004)
    local fightsBefore = #E.GetFights()
    E.OnCleu(T0 + 1010, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    E.ResetCurrent(T0 + 1012)
    CHECK(E.InFight(), "A: reset in idle window reopens for the moment")
    E.Tick(T0 + 1016)
    CHECK(not E.InFight(), "A: empty reopened fight closes")
    eq(#E.GetFights(), fightsBefore, "A: no phantom fight inserted")
    E.OnCleu(T0 + 1020, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    eq(E.GetCurrent().id, 2, "A: discarded fight returned its number")
    E.Tick(T0 + 1024)
end

-- Session persistence: export at "logout", import on a fresh engine —
-- byte-identical Overall/Last, working selectors, sane numbering
do
    local E6 = LoadEngine()
    local fx6 = RunFixture(E6, { IdleTimeout = 3 })
    local overallBefore = E6.Serialize(E6.GetOverall())
    local lastBefore = E6.Serialize(E6.GetSegment("last"))
    local snap = E6.ExportSession(T0 + 500)

    local E7 = LoadEngine()
    E7.Init({ IdleTimeout = 3 }, T0 + 550)
    SetupRoster(E7)
    CHECK(E7.ImportSession(snap, T0 + 550) == true, "A: fresh session import adopted")
    eq(E7.Serialize(E7.GetOverall()), overallBefore, "A: imported Overall byte-identical")
    eq(E7.Serialize(E7.GetSegment("last")), lastBefore, "A: imported Last byte-identical")
    local rows, n = E7.CollectRows(E7.GetOverall(), E7.MODES[1], T0 + 550)
    CHECK(n >= 1, "A: imported data collects rows")
    -- Numbering continues after the imported history
    E7.OnCleu(T0 + 560, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    eq(E7.GetCurrent().id, 3, "A: fight numbering continues after import")
    E7.Tick(T0 + 564)

    -- Rejections: stale, corrupt, wrong version, live fight
    local E8 = LoadEngine()
    E8.Init({ IdleTimeout = 3 }, T0)
    CHECK(E8.ImportSession(snap, T0 + 500 + 601) == false, "A: stale snapshot refused")
    CHECK(E8.ImportSession(nil, T0 + 500) == false, "A: nil snapshot refused")
    CHECK(E8.ImportSession({ v = 99, savedAt = T0 + 500 }, T0 + 500) == false,
        "A: wrong-version snapshot refused")
    CHECK(E8.ImportSession({ v = 1, savedAt = T0 + 500, overall = "garbage" }, T0 + 500) == false,
        "A: corrupt snapshot refused")
    CHECK(E8.GetOverall().totals.dmg == 0, "A: refused imports leave a clean state")
    E8.OnCleu(T0 + 500, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    CHECK(E8.ImportSession(snap, T0 + 501) == false, "A: import refused while a fight is live")

    -- Export mid-fight folds the open pull's elapsed time into overallDur
    E8.OnCleu(T0 + 530, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0, M1, "Gnarl", FENEMY, 0,
        100, 0, 1, 0, 0, 0, false, false, false, false)
    local midSnap = E8.ExportSession(T0 + 531)
    local E10 = LoadEngine()
    E10.Init({ IdleTimeout = 3 }, T0 + 540)
    CHECK(E10.ImportSession(midSnap, T0 + 540) == true, "A: mid-fight snapshot adopts")
    eq(E10.GetOverall().totals.dmg, 200, "A: mid-fight overall damage carried")
    eq(E10.SegmentDuration(E10.GetOverall(), T0 + 540), 30,
        "A: mid-fight overall duration carried (no resume inflation)")
end

-- Name-map caps: 70 distinct targets fold into 60 + "(other)", sums intact
do
    local E9 = LoadEngine()
    E9.Init({ IdleTimeout = 3 }, T0)
    SetupRoster(E9)
    for i = 1, 70 do
        E9.OnCleu(T0 + i * 0.1, "SWING_DAMAGE", nil, A, "Vanguard", FP_MINE, 0,
            "Creature-0-0-0-0-9001-" .. i, "Gnarl" .. i, FENEMY, 0,
            10, 0, 1, 0, 0, 0, false, false, false, false)
        -- and 70 distinct sources hitting the warrior
        E9.OnCleu(T0 + i * 0.1 + 0.05, "SWING_DAMAGE", nil,
            "Creature-0-0-0-0-9002-" .. i, "Biter" .. i, FENEMY, 0,
            A, "Vanguard", FP_MINE, 0,
            5, 0, 1, 0, 0, 0, false, false, false, false)
    end
    local a = E9.GetCurrent().actors[A]
    eq(a.targetsN, 60, "A: target names capped at 60")
    eq(a.sourcesN, 60, "A: source names capped at 60")
    CHECK(a.targets["(other)"] ~= nil, "A: target overflow folded into (other)")
    eq(SumRecords(a.targets), a.dmg, "A: capped targets still sum to dmg")
    eq(SumRecords(a.sources), a.dtaken, "A: capped sources still sum to taken")
    E9.Tick(T0 + 20)
    local name = E9.GetFights()[1].name
    CHECK(name ~= "(other)", "A: overflow bucket never names a fight", name)
end

-- Determinism: same fixture twice from clean state, byte-identical
do
    local E3 = LoadEngine()
    RunFixture(E3, { IdleTimeout = 3 })
    local snap1 = E3.SnapshotAll()
    local E4 = LoadEngine()
    RunFixture(E4, { IdleTimeout = 3 })
    local snap2 = E4.SnapshotAll()
    CHECK(snap1 == snap2, "A: replay is byte-identical", #snap1 .. " vs " .. #snap2)
    CHECK(#snap1 > 1000, "A: snapshot non-trivial", #snap1)
end

-- CollectRows: ordering + reuse
do
    local rows, n, total, dur = E.CollectRows(E.GetOverall(), E.MODES[1], T0 + 500)
    CHECK(n >= 1, "A: overall rows collected", n)
    local sorted = true
    for i = 2, n do
        if rows[i].value > rows[i - 1].value then sorted = false end
    end
    CHECK(sorted, "A: rows sorted descending")
    CHECK(dur > 0, "A: duration positive")
end

io.write(string.format("STAGE A: %d checks, %d failures\n", checks, fails))

-- ===========================================================================
-- STAGE B: throughput
-- ===========================================================================

local EB = LoadEngine()
EB.Init({ IdleTimeout = 3 }, T0)
SetupRoster(EB)

local NEVENTS = 300000
local actors, spells = {}, { "Shadow Bolt", "Frostbolt", "Sinister Strike" }
for i = 1, 25 do actors[i] = "Player-0-P" .. i end

local t0 = os.clock()
local ts = T0
for i = 1, NEVENTS do
    local src = actors[(i % 25) + 1]
    ts = ts + 0.02
    EB.OnCleu(ts, "SPELL_DAMAGE", nil, src, "Raider" .. ((i % 25) + 1), FP_PARTY, 0,
        M1, "Boss", FENEMY, 0,
        686, spells[(i % 3) + 1], 32, 500 + (i % 700), 0, 32, 0, 0, (i % 11 == 0) and 40 or 0,
        i % 5 == 0, false, false, false)
end
local ingestSecs = os.clock() - t0
local perEventUs = ingestSecs / NEVENTS * 1e6

t0 = os.clock()
local REPAINTS = 2000
for i = 1, REPAINTS do
    EB.CollectRows(EB.GetCurrent(), EB.MODES[1], ts)
end
local collectMs = (os.clock() - t0) / REPAINTS * 1000

t0 = os.clock()
local snap = EB.SnapshotAll()
local serializeMs = (os.clock() - t0) * 1000

io.write(string.format(
    "STAGE B: %d events in %.3fs = %.0f events/sec (%.2f us/event)\n" ..
    "         CollectRows(25 actors) = %.3f ms/call; SnapshotAll = %.1f ms (%.0f KB)\n",
    NEVENTS, ingestSecs, NEVENTS / ingestSecs, perEventUs, collectMs, serializeMs, #snap / 1024))

-- Memory: bucket-count sanity for the ceiling statement
do
    local seg = EB.GetCurrent()
    local buckets = 0
    for _, a in pairs(seg.actors) do
        if a.sDmg then for _ in pairs(a.sDmg) do buckets = buckets + 1 end end
    end
    io.write(string.format("         series buckets in flight: %d (25 actors, %.0fs fight)\n",
        buckets, ts - T0))
end

if fails > 0 then
    io.write(string.format("RESULT: %d/%d FAILED\n", fails, checks))
    os.exit(1)
end
io.write(string.format("RESULT: all %d checks passed\n", checks))
