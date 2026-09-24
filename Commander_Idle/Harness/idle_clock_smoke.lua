-- Commander Idle — AFK clock smoke (luajit):
--     luajit idle_clock_smoke.lua
--
-- Loads the REAL CommanderIdleClock.lua (it is pure by construction — no
-- frames, no globals of its own) and pins down the one behaviour the module
-- exists for: ONE number, and only when something is actually about to throw
-- you out of a battleground.
--
-- The rule the tests are really defending is SILENCE. The first version of
-- this module put a stopwatch on screen while the player was legitimately
-- holding a base, which is worse than showing nothing at all. Most of the
-- checks below assert that Evaluate returns nil.

local ADDONS = "/Applications/World of Warcraft/_anniversary_/Interface/AddOns"

local checks, fails = 0, 0
local function CHECK(cond, label, detail)
    checks = checks + 1
    if not cond then
        fails = fails + 1
        io.write("FAIL  ", label, detail and ("  [" .. tostring(detail) .. "]") or "", "\n")
    end
end

local chunk, err = loadfile(ADDONS .. "/Commander_Idle/CommanderIdleClock.lua")
if not chunk then error(err) end
chunk()

local C = CommanderIdleClock
local NOW = 1000

local function Aura(spellId, remaining, duration)
    return { spellId = spellId, expirationTime = NOW + remaining, duration = duration }
end

local function Snap(over)
    local s = {
        now = NOW,
        inBattleground = true,
        pvpInactive = false,
        auras = nil,
        sinceInput = 0,
        autoAfkLimit = 300,
        warnUnder = 60,
        watchBattleground = true,
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

-- ===========================================================================
-- Silence is the normal state
-- ===========================================================================

CHECK(C.Evaluate(Snap()) == nil,
    "silent: a battleground with nothing wrong shows nothing")
CHECK(C.Evaluate(Snap({ sinceInput = 239 })) == nil,
    "silent: four minutes of stillness is still four minutes from a kick")
CHECK(C.Evaluate(Snap({ inBattleground = false, sinceInput = 3600 })) == nil,
    "silent: out in the world nothing can kick you, however long you idle")
CHECK(C.Evaluate(Snap({ sinceInput = nil })) == nil,
    "silent: with no input clock handed in, nothing is invented")

-- The whole complaint that produced this design: standing on a flag not
-- fighting anybody is NOT a warnable state
CHECK(C.Evaluate(Snap({ sinceInput = 30 })) == nil,
    "silent: defending a base without a fight for half a minute")
CHECK(C.Evaluate(Snap({ sinceInput = 120 })) == nil,
    "silent: ...or for two minutes")

-- ===========================================================================
-- The auto-AFK kick — the one with no in-game warning
-- ===========================================================================

CHECK(C.Evaluate(Snap({ sinceInput = 241 })) ~= nil,
    "autoafk: appears as the warning window opens (300 - 60)")

local state = C.Evaluate(Snap({ sinceInput = 250 }))
CHECK(state.stage == "AUTOAFK", "autoafk: the rung", state.stage)
CHECK(state.seconds == 50, "autoafk: 300 - 250", state.seconds)
CHECK(state.severity == "CRITICAL",
    "autoafk: critical -- it is instant removal plus 15 minutes, not a debuff", state.severity)
CHECK(state.hint:lower():find("mouse") or state.hint:lower():find("key"),
    "autoafk: the hint says INPUT, not combat", state.hint)
CHECK(not state.detail:lower():find("pvp combat clears"),
    "autoafk: never claims fighting resets it -- it does not", state.detail)

-- The bar drains across the WARNING window, not across the five minutes: a
-- bar that spends its first four minutes at 100% tells you nothing
CHECK(state.span == 60, "autoafk: the bar spans the warning window", state.span)
CHECK(math.abs(state.fraction - 50 / 60) < 1e-9, "autoafk: fraction", state.fraction)

CHECK(C.Evaluate(Snap({ sinceInput = 300 })).seconds == 0,
    "autoafk: reads 0:00 at the limit, not a negative")
CHECK(C.Evaluate(Snap({ sinceInput = 999 })).seconds == 0,
    "autoafk: and stays at zero past it")

-- The threshold is the user's, and it really moves
CHECK(C.Evaluate(Snap({ sinceInput = 250, warnUnder = 30 })) == nil,
    "autoafk: a tighter window stays quiet longer")
CHECK(C.Evaluate(Snap({ sinceInput = 250, warnUnder = 120 })) ~= nil,
    "autoafk: a wider window opens sooner")

-- ===========================================================================
-- The report ladder, when it is actually on you
-- ===========================================================================

state = C.Evaluate(Snap({ auras = { [C.SPELL_IDLE] = Aura(C.SPELL_IDLE, 122, 180) } }))
CHECK(state.stage == "IDLE", "idle: the rung", state.stage)
CHECK(state.seconds == 122, "idle: counts the aura's own remaining", state.seconds)
CHECK(math.abs(state.fraction - 122 / 180) < 1e-9, "idle: drains against its duration", state.fraction)

state = C.Evaluate(Snap({ auras = { [C.SPELL_INACTIVE] = Aura(C.SPELL_INACTIVE, 47, 180) } }))
CHECK(state.stage == "INACTIVE", "inactive: the rung", state.stage)
CHECK(state.seconds == 47, "inactive: the kick countdown", state.seconds)
CHECK(state.severity == "CRITICAL", "inactive: critical", state.severity)
CHECK(state.title == "Kicked in", "inactive: the title IS the sentence", state.title)

-- Ordering. A reported player who is also about to be auto-AFK'd is told
-- about the report clock only if it is the sooner threat... no: the report
-- rungs always win, because they are the ones an addon can measure exactly
state = C.Evaluate(Snap({ sinceInput = 299,
    auras = { [C.SPELL_INACTIVE] = Aura(C.SPELL_INACTIVE, 47, 180) } }))
CHECK(state.stage == "INACTIVE", "order: a live debuff outranks the input clock", state.stage)
state = C.Evaluate(Snap({ auras = {
    [C.SPELL_IDLE] = Aura(C.SPELL_IDLE, 1, 180),
    [C.SPELL_INACTIVE] = Aura(C.SPELL_INACTIVE, 180, 180),
} }))
CHECK(state.stage == "INACTIVE", "order: Inactive outranks Idle", state.stage)

-- The client's own answer, so nothing ever matches a localized aura name
state = C.Evaluate(Snap({ pvpInactive = true }))
CHECK(state.stage == "FLAGGED", "fallback: PlayerIsPVPInactive alone still says something", state.stage)
CHECK(state.seconds == nil, "fallback: no aura means no invented countdown", state.seconds)
state = C.Evaluate(Snap({ pvpInactive = true,
    auras = { [C.SPELL_IDLE] = Aura(C.SPELL_IDLE, 90, 180) } }))
CHECK(state.stage == "IDLE", "fallback: an id with a clock beats the generic flag", state.stage)
-- ...and it must not shout down the auto-AFK clock when the client is quiet
CHECK(C.Evaluate(Snap({ pvpInactive = false, sinceInput = 290 })).stage == "AUTOAFK",
    "fallback: absent, the input clock still gets through")

-- ===========================================================================
-- Deserter is NOT a rung (removed 2026-09-13): the lockout after you are out
-- is a wait, not a threat, and the module shows nothing for it
-- ===========================================================================

CHECK(C.StageByKey.DESERTER == nil, "deserter: no stage exists for the lockout")
CHECK(C.Evaluate(Snap({ inBattleground = false,
    auras = { [26013] = Aura(26013, 872, 900) } })) == nil,
    "deserter: the lockout aura outside a battleground shows nothing")
CHECK(C.Evaluate(Snap({ inBattleground = true, sinceInput = 0,
    auras = { [26013] = Aura(26013, 872, 900) } })) == nil,
    "deserter: ...and nothing inside one either")

-- No duration reported still gets a bar, off the nominal span, while the
-- NUMBER stays the client's
state = C.Evaluate(Snap({ auras = {
    [C.SPELL_IDLE] = { spellId = C.SPELL_IDLE, expirationTime = NOW + 90, duration = 0 },
} }))
CHECK(state.span == 180 and math.abs(state.fraction - 0.5) < 1e-9,
    "idle: nominal span for the BAR only", state.span)
CHECK(state.seconds == 90, "idle: ...the number stays the client's", state.seconds)

-- An aura reporting more time left than its own duration must not draw an
-- over-full bar
state = C.Evaluate(Snap({ auras = {
    [C.SPELL_INACTIVE] = { spellId = C.SPELL_INACTIVE, expirationTime = NOW + 240, duration = 180 },
} }))
CHECK(state.fraction == 1, "bar: never draws past full", state.fraction)
CHECK(state.seconds == 240, "bar: ...and still reports the honest number", state.seconds)

-- ===========================================================================
-- The master switch
-- ===========================================================================

CHECK(C.Evaluate(Snap({ watchBattleground = false, sinceInput = 299,
    auras = { [C.SPELL_INACTIVE] = Aura(C.SPELL_INACTIVE, 10, 180) } })) == nil,
    "switch: the battleground rungs go quiet")

-- ===========================================================================
-- Formatting and warning marks
-- ===========================================================================

CHECK(C.Format(0) == "0:00", "format: zero", C.Format(0))
CHECK(C.Format(59) == "0:59", "format: under a minute", C.Format(59))
CHECK(C.Format(60) == "1:00", "format: a minute", C.Format(60))
-- Ceiling, not floor: reading 0:00 with half a second left is a lie about the
-- one number this module exists to report
CHECK(C.Format(0.4) == "0:01", "format: rounds UP, so 0:00 means gone", C.Format(0.4))
CHECK(C.Format(899.2) == "15:00", "format: a quarter hour rounds up", C.Format(899.2))

CHECK(C.Remaining(Aura(C.SPELL_INACTIVE, 47, 180), NOW) == 47, "remaining: off expirationTime")
CHECK(C.Remaining({ expirationTime = 0 }, NOW) == nil, "remaining: none reported is nil, not zero")
CHECK(C.Remaining(Aura(C.SPELL_INACTIVE, -5, 180), NOW) == 0, "remaining: floors at zero")
CHECK(C.Remaining(nil, NOW) == nil, "remaining: no aura")

local MARKS = { 30, 10 }
CHECK(C.CrossedMark(MARKS, 32, 29) == 30, "marks: crossing 30", C.CrossedMark(MARKS, 32, 29))
CHECK(C.CrossedMark(MARKS, 29, 28) == nil, "marks: fires once, not every tick")
CHECK(C.CrossedMark(MARKS, 11, 10) == 10, "marks: the mark itself counts as crossed")
CHECK(C.CrossedMark(MARKS, 8, 40) == nil, "marks: never fires on the way back up")
CHECK(C.CrossedMark(MARKS, 40, 5) == 10, "marks: a jump fires once, at the nearest mark",
    C.CrossedMark(MARKS, 40, 5))
CHECK(C.CrossedMark(MARKS, nil, 8) == 10, "marks: a clock picked up mid-flight still warns")
CHECK(C.CrossedMark(MARKS, nil, 175) == nil, "marks: a fresh full-length clock does not warn")
CHECK(C.CrossedMark(MARKS, 20, nil) == nil, "marks: nothing to cross without a remaining")

-- ===========================================================================
-- Every rung carries a bar line and a tooltip line
-- ===========================================================================

for _, stage in ipairs(C.STAGES) do
    CHECK(type(stage.hint) == "string" and #stage.hint > 0 and #stage.hint <= 40,
        "stage " .. stage.key .. ": one short bar line", stage.hint)
    CHECK(type(stage.detail) == "string" and #stage.detail > #stage.hint,
        "stage " .. stage.key .. ": the tooltip says more than the bar")
    CHECK(type(stage.title) == "string" and type(stage.icon) == "string",
        "stage " .. stage.key .. ": has a title and an icon")
end

local carried = {
    C.Evaluate(Snap({ auras = { [C.SPELL_INACTIVE] = Aura(C.SPELL_INACTIVE, 20, 180) } })),
    C.Evaluate(Snap({ auras = { [C.SPELL_IDLE] = Aura(C.SPELL_IDLE, 20, 180) } })),
    C.Evaluate(Snap({ pvpInactive = true })),
    C.Evaluate(Snap({ sinceInput = 280 })),
}
CHECK(#carried == 4, "carried: every branch produced a state", #carried)
for _, built in ipairs(carried) do
    CHECK(built.hint == C.StageByKey[built.stage].hint,
        "carried: " .. built.stage .. " keeps its bar hint")
    CHECK(built.detail == C.StageByKey[built.stage].detail,
        "carried: " .. built.stage .. " keeps its tooltip line")
end
-- All five rungs are reachable, so none of them is dead wording
local seen = {}
for _, built in ipairs(carried) do seen[built.stage] = true end
for _, stage in ipairs(C.STAGES) do
    CHECK(seen[stage.key], "reachable: " .. stage.key .. " can actually happen")
end

-- ===========================================================================
-- The chat line
-- ===========================================================================

local line = C.Line(C.Evaluate(Snap({
    auras = { [C.SPELL_INACTIVE] = Aura(C.SPELL_INACTIVE, 47, 180) } })))
CHECK(line:find("0:47", 1, true), "line: carries the number", line)
CHECK(line:find("Kicked in", 1, true), "line: names the consequence", line)

line = C.Line(C.Evaluate(Snap({ sinceInput = 280 })))
CHECK(line:find("0:20", 1, true), "line: the auto-AFK clock too", line)
CHECK(C.Line(nil):find("clear", 1, true), "line: nothing on the clock", C.Line(nil))

io.write(string.format("%d checks, %d failures\n", checks, fails))
os.exit(fails == 0 and 0 or 1)
