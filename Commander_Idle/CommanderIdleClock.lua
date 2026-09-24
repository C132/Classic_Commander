-- Commander Idle — the AFK clock. Pure logic; this file creates no frames and
-- reads no globals of its own. Everything it needs arrives in one snapshot so
-- the ladder can be tested headlessly (Harness/idle_clock_smoke.lua).
--
-- THE ONE THING THIS ANSWERS: how long until the battleground throws me out.
--
-- There are two separate ways that happens and they have nothing to do with
-- each other. Confusing them is why the first version of this module was
-- useless to a player who defends bases.
--
-- 1. THE AUTO-AFK KICK — the one that actually catches defenders.
--    The client flags you Away after FIVE MINUTES WITH NO KEYBOARD OR MOUSE
--    INPUT. Going Away inside a battleground removes you IMMEDIATELY — no
--    countdown, no warning, no debuff first — and hands you Deserter for 15
--    minutes. (warcraft.wiki.gg "Away"; CMaNGOS `Player::ToggleAFK()` calls
--    `LeaveBattleground()` on the spot, which casts 26013 on the way out.)
--
--    It does NOT care whether you are fighting, moving, or holding a base.
--    Only input. Standing perfectly still on a flag for the whole match is
--    fine as long as your hand touches the mouse. THIS is the clock the
--    module leads with, because it is the one with no in-game warning.
--
-- 2. THE REPORT LADDER — slow, and it needs three other people.
--      Idle (43680)     "Your teammates have reported you for laziness!"
--      Inactive (43681) "You will be kicked from the battleground if you
--                        remain Inactive."
--    Nothing predicts its arrival — it starts when three teammates press
--    Report AFK — but once an aura is on you the remaining time is exact, and
--    any PvP combat clears it.
--
-- Every countdown on rungs 43680/43681 is read off the aura's own
-- expirationTime. The minute figures above are documentation and a
-- last-resort bar span; they are never the number shown.
--
-- The 15-minute Deserter lockout that follows either exit is deliberately NOT
-- a rung: it is a wait, not a threat, and a bar that sits on screen for a
-- quarter of an hour after the battleground is over says nothing worth the
-- space. Removed 2026-09-13.

CommanderIdleClock = {}
local C = CommanderIdleClock

-- Verified against this client's spell data (Anniversary tooltip dataset),
-- 2026-09-08.
C.SPELL_IDLE = 43680
C.SPELL_INACTIVE = 43681

-- The client's own idle-to-Away threshold. There is NO API for "seconds since
-- last input" on this client (checked the 2.5.6.69546 binary: no
-- GetLastInputTime, no idle-time query of any kind), so the caller has to
-- watch the input it can see and hand the elapsed time in.
C.AUTO_AFK_LIMIT = 300

-- Nominal spans, used ONLY as a bar-fill fallback when an aura reports an
-- expiration but no duration, and by the demo.
C.NOMINAL = {
    [C.SPELL_IDLE] = 180,
    [C.SPELL_INACTIVE] = 180,
}

C.WATCHED = {
    [C.SPELL_IDLE] = true,
    [C.SPELL_INACTIVE] = true,
}

C.SEVERITY_COLOR = {
    INFO     = { 0.6, 0.8, 1 },
    WARN     = { 1, 0.85, 0.2 },
    CRITICAL = { 1, 0.3, 0.2 },
}

local floor, max, min, huge = math.floor, math.max, math.min, math.huge

-- m:ss, ceiling — a countdown reads 0:00 only when it really has run out.
function C.Format(seconds)
    seconds = max(floor((seconds or 0) + 0.999), 0)
    return string.format("%d:%02d", floor(seconds / 60), seconds % 60)
end

-- Seconds left on a scanned aura, or nil when the client reports no
-- expiration. `expirationTime` is on GetTime()'s clock, so `now` must be too.
function C.Remaining(aura, now)
    if not aura then return nil end
    local expires = aura.expirationTime
    if type(expires) ~= "number" or expires <= 0 then return nil end
    return max(expires - (now or 0), 0)
end

-- The warning mark the countdown has just fallen through, or nil.
--
-- `previous` is the remaining time at the last paint; nil (first sighting)
-- counts as infinity, so a clock picked up mid-flight after a /reload still
-- warns instead of running out in silence. When one step crosses several
-- marks at once the answer is the SMALLEST crossed — one chime either way,
-- but the number returned describes where the clock now is.
function C.CrossedMark(marks, previous, remaining)
    if not (marks and remaining) then return nil end
    local before = previous or huge
    local best
    for _, mark in ipairs(marks) do
        if before > mark and remaining <= mark then
            if not best or mark < best then best = mark end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- The rungs
--
-- Worst-first. Exactly one is returned: the one that most needs acting on.
-- Each carries a SHORT `hint` for the bar (read at a glance, mid-fight) and a
-- longer `detail` for the tooltip and the chat line.
-- ---------------------------------------------------------------------------

local STAGES = {
    {
        key = "INACTIVE",
        title = "Kicked in",
        hint = "Hit an enemy player.",
        detail = "Reported inactive. You are removed from the battleground when this runs out. Any PvP combat clears it.",
        severity = "CRITICAL",
        icon = "Interface\\Icons\\Spell_Nature_Polymorph_Cow",
    },
    {
        key = "IDLE",
        title = "Inactive in",
        hint = "Hit an enemy player.",
        detail = "Three teammates reported you. When this ends you are marked Inactive, and the kick clock starts. Any PvP combat clears it.",
        severity = "WARN",
        icon = "Interface\\Icons\\Ability_Hibernation",
    },
    {
        -- The client says we are flagged but no id matched. Nothing here ever
        -- depends on a localized aura NAME, so the fallback is a rung.
        key = "FLAGGED",
        title = "Reported inactive",
        hint = "Hit an enemy player.",
        detail = "The client reports you as inactive here, but is not saying how long is left. Any PvP combat clears it.",
        severity = "WARN",
        icon = "Interface\\Icons\\Spell_Nature_Polymorph_Cow",
    },
    {
        key = "AUTOAFK",
        title = "AFK kick in",
        hint = "Touch the mouse or a key.",
        detail = "The client marks you Away after five minutes without input, and going Away in a battleground removes you instantly with a 15-minute Deserter. Fighting does not reset this — only input does.",
        severity = "CRITICAL",
        icon = "Interface\\Icons\\INV_Misc_PocketWatch_01",
    },
}

C.STAGES = STAGES

local BY_KEY = {}
for _, stage in ipairs(STAGES) do BY_KEY[stage.key] = stage end
C.StageByKey = BY_KEY

local function Build(stage, seconds, span)
    local fraction
    if span and span > 0 and seconds then
        fraction = min(max(seconds / span, 0), 1)
    end
    return {
        stage = stage.key,
        title = stage.title,
        hint = stage.hint,
        detail = stage.detail,
        severity = stage.severity,
        icon = stage.icon,
        seconds = seconds,
        span = span,
        fraction = fraction,
        exact = seconds ~= nil,
    }
end

local function FromAura(stage, aura, now)
    local remaining = C.Remaining(aura, now)
    local span = aura and aura.duration
    if type(span) ~= "number" or span <= 0 then
        span = C.NOMINAL[aura and aura.spellId]
    end
    -- A span smaller than what is left would draw an over-full bar; the aura
    -- is the truth, so widen the span to fit it
    if span and remaining and remaining > span then span = remaining end
    return Build(stage, remaining, span)
end

-- Snapshot fields (all optional; missing means "no"):
--   now                GetTime()'s clock
--   inBattleground     instanceType == "pvp"
--   pvpInactive        PlayerIsPVPInactive("player")
--   auras              { [spellId] = { spellId=, expirationTime=, duration= } }
--   sinceInput         seconds since the last input the caller could see
--   autoAfkLimit       the client's idle-to-Away threshold (default 300)
--   warnUnder          only show the auto-AFK clock inside this many seconds
--   watchBattleground  draw the in-battleground rungs at all
--
-- Returns nil when there is nothing worth putting on screen. Silence is the
-- normal state: while you are playing, this module shows nothing at all.
function C.Evaluate(s)
    if not s then return nil end
    local now = s.now or 0
    local auras = s.auras or {}

    if s.watchBattleground ~= false and s.inBattleground then
        local inactive = auras[C.SPELL_INACTIVE]
        if inactive then return FromAura(BY_KEY.INACTIVE, inactive, now) end

        local idle = auras[C.SPELL_IDLE]
        if idle then return FromAura(BY_KEY.IDLE, idle, now) end

        if s.pvpInactive then return Build(BY_KEY.FLAGGED, nil, nil) end

        -- The auto-AFK clock. Shown only inside the warning window: while you
        -- are playing normally it resets constantly and a bar counting down
        -- from five minutes would be on screen for the whole match saying
        -- nothing. Silence until it is nearly out is the entire point.
        local limit = s.autoAfkLimit or C.AUTO_AFK_LIMIT
        if s.sinceInput then
            local left = max(limit - s.sinceInput, 0)
            local warnUnder = s.warnUnder or 60
            if left <= warnUnder then
                return Build(BY_KEY.AUTOAFK, left, warnUnder)
            end
        end
    end

    return nil
end

-- The line /cidle status prints, and the one announced on a rung change.
-- Kept here so chat and the bar can never drift apart.
function C.Line(state)
    if not state then
        return "clear — nothing is counting down on you."
    end
    if state.seconds then
        return string.format("%s %s — %s", state.title, C.Format(state.seconds), state.detail)
    end
    return string.format("%s — %s", state.title, state.detail)
end
