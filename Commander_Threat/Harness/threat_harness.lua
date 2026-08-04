-- Commander Threat engine fixture harness (luajit).
-- The engine is pure Lua — no mock needed. Drives canned observation
-- streams through the real Ingest/SetPlateFacts paths and asserts the
-- sorted rows, the TPS math, and every warning EDGE: fires exactly once,
-- hysteresis re-arm, mob-change re-arm, silent adoption on role switches,
-- aggro-lost only on a contested list, and the healer inbound edge.
--
--   /opt/homebrew/bin/luajit threat_harness.lua

-- Resolve the AddOns root from this file's own location so the harness runs
-- in a git worktree as well as the live AddOns directory (the Talents pattern)
local HERE = (debug.getinfo(1, "S").source:match("^@(.*)/[^/]+$")) or "."
if HERE:sub(1, 1) ~= "/" then
    HERE = (os.getenv("PWD") or ".") .. "/" .. HERE
end
-- Invoked by bare filename, HERE ends up ".../Harness/." — normalize, or the
-- match below misses and the live AddOns copy loads instead of this tree's
HERE = HERE:gsub("/%./", "/"):gsub("/%.$", "")
local ADDONS = HERE:match("^(.*)/[^/]+/Harness$") or
    "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

assert(loadfile(ADDONS .. "/Commander_Threat/CommanderThreatEngine.lua"))()
local E = CommanderThreatEngine

local db = { WarnAt = 80 }

-- Alert capture
local fired = {}
local function Drain()
    local out = {}
    E.DrainAlerts(function(kind, arg)
        out[#out + 1] = kind
        fired[#fired + 1] = { kind = kind, arg = arg }
    end)
    return out
end

local function Has(list, kind)
    for _, k in ipairs(list) do
        if k == kind then return true end
    end
    return false
end

-- Observation builder: value-relative raw/scaled like the live sampler
local scratch = {}
local function Obs(n, guid, name, value, top, tanking, isPlayer, status)
    n = n + 1
    local o = scratch[n]
    if not o then o = {}; scratch[n] = o end
    o.guid, o.name, o.class = guid, name, "WARRIOR"
    o.isPlayer, o.isPet = isPlayer or false, false
    o.value = value
    o.raw = top > 0 and (value / top * 100) or 0
    o.scaled = tanking and 100 or (o.raw / 1.1)
    o.tanking = tanking or false
    o.status = status or (tanking and 3 or 0)
    return n
end

-- ===========================================================================
-- Sort, ranks, player row, pooling
-- ===========================================================================

E.Init(db, "DAMAGE")
E.SetMob("mob-1", "Deviate Guardian")

local now = 100
local n = 0
n = Obs(n, "u-tank", "Brakk", 1000, 1000, true)
n = Obs(n, "u-me", "Devinp", 600, 1000, false, true)
n = Obs(n, "u-rogue", "Vexa", 800, 1000, false)
E.Ingest(scratch, n, now)

local rows, rowsN = E.Rows()
CHECK(rowsN == 3, "E: three rows ingested", rowsN)
CHECK(rows[1].guid == "u-tank" and rows[2].guid == "u-rogue" and rows[3].guid == "u-me",
    "E: rows sorted by threat desc")
CHECK(rows[1].rank == 1 and rows[3].rank == 3, "E: ranks assigned")
CHECK(E.PlayerRow() and E.PlayerRow().guid == "u-me", "E: player row found")
CHECK(E.TankingRow() and E.TankingRow().guid == "u-tank", "E: tanking row found")
CHECK(select(1, E.ChaserScaled()) > 0, "E: chaser scaled reads")
CHECK(Drain()[1] == nil, "E: no alerts at 55% scaled")

-- Shrinking the list recycles rows without leaving stale tails
n = 0
n = Obs(n, "u-tank", "Brakk", 1200, 1200, true)
E.Ingest(scratch, n, now + 0.25)
rows, rowsN = E.Rows()
CHECK(rowsN == 1 and rows[1].guid == "u-tank" and rows[2] == nil,
    "E: pool shrink leaves a dense array")
CHECK(E.PlayerRow() == nil, "E: player off the list clears playerRow")

-- ===========================================================================
-- TPS: EMA over ~1s samples, drops clamp to zero
-- ===========================================================================

E.Reset()
E.SetMob("mob-tps", "Dummy")
local t = 200
n = 0; n = Obs(n, "u-me", "Devinp", 100, 100, true, true)
E.Ingest(scratch, n, t)
CHECK(E.PlayerRow().tps == 0, "E: tps starts at 0")

n = 0; n = Obs(n, "u-me", "Devinp", 250, 250, true, true)
E.Ingest(scratch, n, t + 1)
local tps = E.PlayerRow().tps
CHECK(math.abs(tps - 60) < 0.01, "E: first 1s delta EMAs at alpha 0.4", tps)

n = 0; n = Obs(n, "u-me", "Devinp", 400, 400, true, true)
E.Ingest(scratch, n, t + 2)
tps = E.PlayerRow().tps
CHECK(math.abs(tps - 96) < 0.01, "E: second delta compounds", tps)

-- Sub-sample ingests do not resample
n = 0; n = Obs(n, "u-me", "Devinp", 405, 405, true, true)
E.Ingest(scratch, n, t + 2.25)
CHECK(math.abs(E.PlayerRow().tps - 96) < 0.01, "E: sub-1s tick keeps the EMA")

-- A threat DROP (feign, fade) reads as zero output, not negative
n = 0; n = Obs(n, "u-me", "Devinp", 50, 50, true, true)
E.Ingest(scratch, n, t + 3.5)
tps = E.PlayerRow().tps
CHECK(math.abs(tps - 57.6) < 0.01, "E: drop clamps instantaneous to 0", tps)

-- ===========================================================================
-- DAMAGE: pull-warn edge with hysteresis + aggro-gained
-- ===========================================================================

E.Reset()
E.SetMob("mob-2", "Ravager")
t = 300

local function DmgTick(scaledPct, tanking, at)
    local top = 1000
    local mine = tanking and top * 1.2 or top * (scaledPct * 1.1 / 100)
    local m = 0
    m = Obs(m, "u-tank", "Brakk", top, math.max(top, mine), not tanking)
    m = Obs(m, "u-me", "Devinp", mine, math.max(top, mine), tanking, true)
    -- Feed exact scaled: Obs derives it, so overwrite for precision
    scratch[2].scaled = tanking and 100 or scaledPct
    E.Ingest(scratch, m, at)
    return Drain()
end

CHECK(not Has(DmgTick(79, false, t), "PULL_WARN"), "E: 79% below threshold")
CHECK(Has(DmgTick(81, false, t + 1), "PULL_WARN"), "E: 81% fires the pull warn")
CHECK(not Has(DmgTick(85, false, t + 5), "PULL_WARN"), "E: stays disarmed above")
CHECK(not Has(DmgTick(75, false, t + 6), "PULL_WARN"), "E: 75% is inside hysteresis (no re-arm)")
CHECK(not Has(DmgTick(85, false, t + 7), "PULL_WARN"), "E: re-cross without re-arm is silent")
DmgTick(65, false, t + 8) -- below WarnAt-10: re-arms
CHECK(Has(DmgTick(85, false, t + 12), "PULL_WARN"), "E: re-armed edge fires again")

local out = DmgTick(100, true, t + 20)
CHECK(Has(out, "AGGRO_GAINED"), "E: taking aggro fires the loud alert")
CHECK(not Has(out, "PULL_WARN"), "E: tanking suppresses the pull warn")
CHECK(not Has(DmgTick(100, true, t + 21), "AGGRO_GAINED"), "E: aggro alert is an edge, not a level")

-- Alert gap: two distinct edges inside 3s collapse to one
E.Reset()
E.SetMob("mob-3", "Stalker")
t = 400
DmgTick(85, false, t)
DmgTick(60, false, t + 0.5)  -- re-arm
out = DmgTick(90, false, t + 1)
CHECK(not Has(out, "PULL_WARN"), "E: same-type alert inside the 3s gap is swallowed")

-- Fresh state adopts silently: first sight of "already tanking" is no edge
E.Reset()
E.SetMob("mob-4", "Guardian")
out = DmgTick(100, true, 500)
CHECK(not Has(out, "AGGRO_GAINED"), "E: first observation adopts silently")

-- Mob switch re-arms the pull warn
E.Reset()
E.SetMob("mob-5", "First")
DmgTick(85, false, 600)
E.SetMob("mob-6", "Second")
CHECK(Has(DmgTick(85, false, 610), "PULL_WARN"), "E: mob change re-arms the edge")

-- ===========================================================================
-- TANK: chase warn + aggro lost (only on a contested list)
-- ===========================================================================

E.Init(db, "TANK")
E.SetMob("mob-7", "Foreman")
t = 700

local function TankTick(chasePct, holding, at, contested)
    local m = 0
    local you = 1000
    local chaser = you * (chasePct * 1.1 / 100)
    m = Obs(m, "u-me", "Devinp", holding and you or chaser * 0.8, math.max(you, chaser), holding, true)
    scratch[m].scaled = holding and 100 or 80
    if contested ~= false then
        m = Obs(m, "u-vexa", "Vexa", chaser, math.max(you, chaser), not holding)
        scratch[m].scaled = holding and chasePct or 100
    end
    E.Ingest(scratch, m, at)
    return Drain()
end

CHECK(not Has(TankTick(70, true, t), "CHASE_WARN"), "E: 70% chaser quiet")
CHECK(Has(TankTick(82, true, t + 1), "CHASE_WARN"), "E: 82% chaser fires chase warn")
CHECK(not Has(TankTick(85, true, t + 5), "CHASE_WARN"), "E: chase warn is an edge")
TankTick(60, true, t + 6)
CHECK(Has(TankTick(85, true, t + 10), "CHASE_WARN"), "E: chase re-arms below hysteresis")

out = TankTick(100, false, t + 20)
CHECK(Has(out, "AGGRO_LOST"), "E: losing the mob to a live chaser alerts")
CHECK(not Has(TankTick(100, false, t + 21), "AGGRO_LOST"), "E: loss is an edge")

-- A mob death (list empties) is NOT a loss
E.Init(db, "TANK")
E.SetMob("mob-8", "Doomed")
TankTick(50, true, 800)
E.Ingest(scratch, 0, 801)
CHECK(not Has(Drain(), "AGGRO_LOST"), "E: an emptied list never reads as a loss")

-- ===========================================================================
-- Role switching mid-fight adopts silently
-- ===========================================================================

E.Init(db, "DAMAGE")
E.SetMob("mob-9", "Shifter")
DmgTick(100, true, 900) -- adopt tanking silently (fresh)
E.SetRole("TANK")
out = TankTick(50, true, 901)
CHECK(not Has(out, "AGGRO_LOST") and not Has(out, "AGGRO_GAINED"),
    "E: role switch manufactures no edge")
CHECK(E.GetRole() == "TANK", "E: role stored")

-- ===========================================================================
-- HEALER: plate-driven worst + inbound edge, with and without rows
-- ===========================================================================

E.Init(db, "HEALER")
E.SetMob(nil, nil)
t = 1000

E.SetPlateFacts(3, 2, 60, "Stalker", nil, t)
E.Ingest(scratch, 0, t)
CHECK(Drain()[1] == nil, "E: healer 60% worst quiet")

E.SetPlateFacts(3, 2, 85, "Stalker", nil, t + 1)
E.Ingest(scratch, 0, t + 1)
CHECK(Has(Drain(), "PULL_WARN"), "E: healer worst-mob 85% fires with no target at all")

E.SetPlateFacts(3, 2, 88, "Stalker", "Stalker", t + 5)
out = Drain()
CHECK(Has(out, "INBOUND"), "E: a mob turning to the healer fires INBOUND")
CHECK(fired[#fired].arg == "Stalker", "E: inbound alert names the mob")
E.SetPlateFacts(3, 2, 88, "Stalker", "Stalker", t + 6)
CHECK(not Has(Drain(), "INBOUND"), "E: inbound is an edge")
E.SetPlateFacts(3, 3, 40, nil, nil, t + 10)
E.SetPlateFacts(3, 2, 40, "Stalker", "Stalker", t + 11)
CHECK(Has(Drain(), "INBOUND"), "E: inbound re-arms once clear")

local plate = E.PlateFacts()
CHECK(plate.loose == 1 and plate.held == 2 and plate.engaged == 3,
    "E: loose derives from engaged minus held")

-- Held can never exceed engaged into negative loose
E.SetPlateFacts(2, 5, 0, nil, nil, t + 20)
CHECK(E.PlateFacts().loose == 0, "E: loose clamps at zero")

-- Damage role ignores the inbound edge
E.Init(db, "DAMAGE")
E.SetPlateFacts(3, 2, 90, "Stalker", "Stalker", 1100)
E.Ingest(scratch, 0, 1100)
out = Drain()
CHECK(not Has(out, "INBOUND"), "E: damage role has no inbound alert")
CHECK(not Has(out, "PULL_WARN"), "E: damage role ignores plate worst (target-based)")

-- ===========================================================================
-- Reset clears everything
-- ===========================================================================

E.Init(db, "DAMAGE")
E.SetMob("mob-z", "Zed")
DmgTick(85, false, 1200)
E.Reset()
rows, rowsN = E.Rows()
CHECK(rowsN == 0 and E.PlayerRow() == nil and E.Mob() == nil, "E: reset clears rows and mob")
CHECK(E.PlateFacts().engaged == 0 and E.PlateFacts().inbound == nil, "E: reset clears plate facts")
E.SetMob("mob-z", "Zed")
CHECK(Has(DmgTick(85, false, 1204), "PULL_WARN"), "E: reset re-arms the edges")

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
