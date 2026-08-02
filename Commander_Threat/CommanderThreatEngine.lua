-- Commander Threat: the data layer — pure Lua, zero frames, zero Unit* calls.
-- The UI samples the client's threat API on its tick and hands this engine
-- plain observation tables; the engine owns everything that must be exact
-- and testable: the sorted row list, the TPS moving averages, and the
-- role-aware warning EDGES. Warnings are edges with hysteresis, never
-- levels — a percentage jittering across the threshold alarms once, and
-- re-arms only after falling 10 points back below (or when the mob
-- changes). The client is the only authority on threat; nothing in here
-- estimates anything.
--
-- Lineage note (FINDINGS.md has the long form): KLHThreatMeter re-derived
-- threat from the combat log because vanilla had no API; patch 2.4 gave the
-- client a real one and Omen became a presenter, not a calculator. This
-- engine keeps Omen's discipline — read, sort, warn — and adds nothing.

CommanderThreatEngine = {}
local E = CommanderThreatEngine

local ROLE_TANK, ROLE_HEALER = "TANK", "HEALER"

local ALERT_GAP = 3    -- seconds between same-type alerts (belt over the edges)
local REARM_DROP = 10  -- hysteresis: re-arm this far below WarnAt
local TPS_SAMPLE = 1.0 -- seconds between TPS deltas (tick-rate independent)
local TPS_ALPHA = 0.4  -- EMA weight of the newest delta
local TPS_STALE = 10   -- forget TPS state for units off the list this long

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

local db
local role = "DAMAGE"
local mobGuid, mobName

local rows, rowsN = {}, 0 -- dense sorted array; recycled through rowPool
local rowPool = {}
local playerRow

local tpsTrack = {}       -- guid -> { value, at, tps, seen }
local tpsSweepAt = 0

-- Facts from the UI's nameplate sweep (tank footer, healer worst/inbound)
local plate = { engaged = 0, held = 0, loose = 0, worst = 0, worstName = nil, inbound = nil }

-- Warning edge state. tankingWas nil = adopt the next observation silently,
-- so enabling, role switches, and mob switches never manufacture an edge.
local pullArmed = true
local chaseArmed = true
local tankingWas = nil
local inboundWas = false

local alerts, alertsN = {}, 0
local lastAlertAt = {}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function E.Init(database, startRole)
    db = database
    role = startRole or "DAMAGE"
    E.Reset()
end

function E.Reset()
    for i = 1, rowsN do
        rowPool[#rowPool + 1] = rows[i]
        rows[i] = nil
    end
    rowsN = 0
    playerRow = nil
    mobGuid, mobName = nil, nil
    for k in pairs(tpsTrack) do tpsTrack[k] = nil end
    plate.engaged, plate.held, plate.loose, plate.worst = 0, 0, 0, 0
    plate.worstName, plate.inbound = nil, nil
    pullArmed, chaseArmed, tankingWas, inboundWas = true, true, nil, false
    alertsN = 0
    for k in pairs(lastAlertAt) do lastAlertAt[k] = nil end
end

function E.SetRole(newRole)
    if newRole == role then return end
    role = newRole
    -- Re-arm everything and adopt current facts silently: switching role
    -- mid-fight must never manufacture an edge from old state read through
    -- new rules
    pullArmed, chaseArmed = true, true
    tankingWas = nil
    inboundWas = plate.inbound ~= nil
end

function E.GetRole()
    return role
end

-- The display mob changed: TPS history and edges belong to the old mob
function E.SetMob(guid, name)
    if guid == mobGuid then
        if name then mobName = name end
        return
    end
    mobGuid, mobName = guid, name
    for k in pairs(tpsTrack) do tpsTrack[k] = nil end
    pullArmed, chaseArmed = true, true
    tankingWas = nil
    for i = 1, rowsN do
        rowPool[#rowPool + 1] = rows[i]
        rows[i] = nil
    end
    rowsN = 0
    playerRow = nil
end

function E.Mob()
    return mobGuid, mobName
end

-- ---------------------------------------------------------------------------
-- Alerts
-- ---------------------------------------------------------------------------

local function TakeAlert(kind, arg, now)
    local last = lastAlertAt[kind]
    if last and (now - last) < ALERT_GAP then return end
    lastAlertAt[kind] = now
    alertsN = alertsN + 1
    local a = alerts[alertsN]
    if not a then
        a = {}
        alerts[alertsN] = a
    end
    a.kind, a.arg = kind, arg
end

-- Drain this tick's edge alerts (pooled; handler must not keep the args)
function E.DrainAlerts(handler)
    for i = 1, alertsN do
        handler(alerts[i].kind, alerts[i].arg)
    end
    alertsN = 0
end

-- ---------------------------------------------------------------------------
-- TPS: EMA over ~1s deltas of raw threat, per unit, current mob only.
-- The API reports state, not rate — this is the only derived number in the
-- addon, and threat DROPS (fade, feign, wipes) read as 0, not negative.
-- ---------------------------------------------------------------------------

local function TpsFor(guid, value, now)
    local t = tpsTrack[guid]
    if not t then
        t = { value = value, at = now, tps = 0, seen = now }
        tpsTrack[guid] = t
        return 0
    end
    t.seen = now
    local dt = now - t.at
    if dt >= TPS_SAMPLE then
        local inst = (value - t.value) / dt
        if inst < 0 then inst = 0 end
        t.tps = t.tps + (inst - t.tps) * TPS_ALPHA
        t.value, t.at = value, now
    end
    return t.tps
end

local function SweepTps(now)
    if now - tpsSweepAt < TPS_STALE then return end
    tpsSweepAt = now
    for guid, t in pairs(tpsTrack) do
        if now - t.seen > TPS_STALE then
            tpsTrack[guid] = nil
        end
    end
end

-- ---------------------------------------------------------------------------
-- Edges
-- ---------------------------------------------------------------------------

-- Highest scaled percentage on the list that is not the player: the tank's
-- chaser. Pets included — a Growling pet rips like anyone else.
function E.ChaserScaled()
    local best, bestRow = 0, nil
    for i = 1, rowsN do
        local r = rows[i]
        if not r.isPlayer and r.scaled > best then
            best, bestRow = r.scaled, r
        end
    end
    return best, bestRow
end

-- The row the mob is actually on (the aggro holder), if it is on anyone
-- we can see
function E.TankingRow()
    for i = 1, rowsN do
        if rows[i].tanking then return rows[i] end
    end
    return nil
end

local function RunEdges(now)
    local warnAt = (db and db.WarnAt) or 80
    local rearm = warnAt - REARM_DROP
    local p = playerRow
    local tankingNow = (p and p.tanking) and true or false

    if role == ROLE_TANK then
        -- Grip transitions: alert only a true LOSS — previously tanking,
        -- now not, with the list still contested. A dying mob's list just
        -- vanishes and must never read as losing it.
        if tankingWas == nil then
            tankingWas = tankingNow
        elseif tankingNow ~= tankingWas then
            if not tankingNow and rowsN > 0 then
                TakeAlert("AGGRO_LOST", mobName, now)
            end
            tankingWas = tankingNow
        end
        if tankingNow then
            local chase = E.ChaserScaled()
            if chase >= warnAt then
                if chaseArmed then
                    chaseArmed = false
                    TakeAlert("CHASE_WARN", nil, now)
                end
            elseif chase < rearm then
                chaseArmed = true
            end
        else
            chaseArmed = true
        end
        pullArmed = true
    else
        -- DAMAGE and HEALER share the pull ladder; the healer's effective
        -- percentage is the worst across every visible engaged mob, since
        -- heal aggro is diffuse and the current target means little
        local eff = (p and not tankingNow) and p.scaled or 0
        if role == ROLE_HEALER and not tankingNow and plate.worst > eff then
            eff = plate.worst
        end
        if tankingNow then
            pullArmed = false -- past the ledge; the aggro alert owns it now
        elseif eff >= warnAt then
            if pullArmed then
                pullArmed = false
                TakeAlert("PULL_WARN", nil, now)
            end
        elseif eff < rearm then
            pullArmed = true
        end
        if tankingWas == nil then
            tankingWas = tankingNow
        elseif tankingNow ~= tankingWas then
            if tankingNow then
                TakeAlert("AGGRO_GAINED", mobName, now)
            end
            tankingWas = tankingNow
        end
        chaseArmed = true
    end
end

-- ---------------------------------------------------------------------------
-- Ingest
-- ---------------------------------------------------------------------------

local function ByThreatDesc(a, b)
    if a.value ~= b.value then return a.value > b.value end
    return (a.name or "") < (b.name or "")
end

-- obs: array of observation tables (UI-owned scratch, copied out here),
-- fields guid/name/class/isPlayer/isPet/value/raw/scaled/tanking/status.
-- Runs every tick — with n = 0 too, so plate-only facts (a healer with no
-- target) still drive the edges.
function E.Ingest(obs, n, now)
    for i = 1, rowsN do
        rowPool[#rowPool + 1] = rows[i]
        rows[i] = nil
    end
    rowsN = 0
    playerRow = nil
    for i = 1, n do
        local o = obs[i]
        local r = table.remove(rowPool) or {}
        rowsN = rowsN + 1
        rows[rowsN] = r
        r.guid, r.name, r.class = o.guid, o.name, o.class
        r.isPlayer, r.isPet = o.isPlayer, o.isPet
        r.value, r.raw, r.scaled = o.value, o.raw, o.scaled
        r.tanking, r.status = o.tanking, o.status
        r.tps = TpsFor(o.guid, o.value, now)
        if o.isPlayer then playerRow = r end
    end
    table.sort(rows, ByThreatDesc)
    for i = 1, rowsN do
        rows[i].rank = i
    end
    SweepTps(now)
    RunEdges(now)
end

-- Facts from the nameplate sweep. The healer INBOUND edge lives here so it
-- works with no display mob at all; coverage follows enemy-nameplate
-- visibility, which the options say out loud.
function E.SetPlateFacts(engaged, held, worst, worstName, inbound, now)
    plate.engaged = engaged or 0
    plate.held = held or 0
    plate.loose = plate.engaged - plate.held
    if plate.loose < 0 then plate.loose = 0 end
    plate.worst = worst or 0
    plate.worstName = worstName
    plate.inbound = inbound
    local has = inbound ~= nil
    if role == ROLE_HEALER and has and not inboundWas then
        TakeAlert("INBOUND", inbound, now)
    end
    inboundWas = has
end

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------

function E.Rows()
    return rows, rowsN
end

function E.PlayerRow()
    return playerRow
end

function E.PlateFacts()
    return plate
end
