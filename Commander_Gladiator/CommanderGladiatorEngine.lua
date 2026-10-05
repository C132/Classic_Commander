-- Commander Gladiator: the rules, with no WoW API in them.
--
-- A match is a pure function of two team lists, a seed, and whatever the
-- player's hand did to it and when. This file never calls GetTime, never
-- makes a frame, never prints; the window steps it on its own clock and
-- draws what it finds, and the smoke test steps it ten thousand times a
-- second under plain luajit and counts who won. That is the only reason the
-- split exists, and it is why there is no wall clock and no math.random
-- anywhere below: the same teams, the same seed and the same pins and taps
-- on the same ticks give the same event log on any machine, byte for byte.
--
-- It also knows no spell by name. Every ability is a row in the data file --
-- a `when` out of five targeting questions and a list of effects out of
-- twelve kinds -- and this file is those five questions, those twelve kinds,
-- and the loop that asks and applies them.
--
-- THE SURFACE (everything the window needs is in this block)
--
--   E.NewMatch(teamA, teamB, seed) -> match
--       teamA/teamB are lists of spec keys from DATA.SPECS, in slot order.
--       Side "A" starts on the left. An unknown key is an error.
--   match:Step()
--       Advances exactly one tick (DATA.ARENA.tick, 0.1 s). Does nothing
--       once the match is over.
--   match:Drain() -> { event, ... }
--       The events since the last Drain, in the order they happened. When
--       nothing happened it hands back ONE shared empty list, the same table
--       every time and for every match: read it, never write to it.
--
--   The player's two verbs. Neither is ever called by Step, and the engine
--   does not know which side the player is on: a match on which nobody
--   calls them is a match of automatic play and nothing else, and the
--   smoke's section G holds two hundred of those to a checksum taken before
--   either verb existed. All three calls below are safe before the first
--   Step, which is how a pin made while the window holds a match at its
--   gates comes to be that match's opening.
--
--   match:Pin(side, unit) -> true if it did anything
--       Pins `unit` as `side`'s kill target, or moves the pin to it from
--       wherever it was; called on the unit already pinned, it lets the pin
--       go. Refused (false, and nothing at all changes) for a unit of
--       `side`'s own, a dead one, nil, and in a finished match. The team's
--       focus is settled inside the call, so match.focus[side] and the FOCUS
--       event are there when it returns, not a beat later.
--   match:Lit(unit) -> true or false
--       Whether a Tap would fire this instant: the match not over, the unit
--       alive and not disabled, its big spell off cooldown, and that spell's
--       own targeting rule finding somebody. Asking changes nothing -- not
--       the dice, not a focus, not the event list -- so it may be asked for
--       every button on every frame. It costs one targeting rule, a walk
--       over the six units, and it allocates nothing except on the rare
--       frame where the rule would have moved the team's focus: there one
--       event table is made and dropped.
--   match:Tap(unit) -> true if it fired
--       Lit, and then the press: the unit's big spell, now, on whoever its
--       rule picks, without waiting for the unit's beat. The spell's
--       cooldown starts and the unit's beat starts again from the tap, so a
--       tap is the same press made sooner and not one more press. A tap
--       that is not lit is refused and changes nothing. No spell takes a
--       target from the hand, and a rule's own gate (Pain Suppression's
--       "an ally under half") holds for a tap as it does for the unit.
--
--   match.time     seconds of match time (tick * 0.1)
--   match.tick     whole ticks so far
--   match.over     true once it has ended
--   match.winner   "A", "B" or "DRAW" once over; nil before
--   match.units    the six units, a stable list: units[id] is unit `id`,
--                  side A is 1..3 and side B is 4..6, dead ones stay in it
--   match.focus    { A = unit, B = unit }: each team's current kill target
--                  (nil for a side until it first picks one)
--   match.pin      { A = unit, B = unit }: the enemy each side has pinned,
--                  nil for a side with no pin, which is how every match
--                  starts. It is not always that side's focus: see the
--                  kill target below. Cleared the moment the pinned unit
--                  dies. Read it; set it with Pin.
--   match.routed   nil, or the side ("A"/"B") that has been routed: see ROUT
--
--   A unit:
--     id, side ("A"/"B"), slot (1..3), spec (the DATA.SPECS row)
--     x, y              place on the floor (0..100 by 0..50)
--     health, healthMax
--     absorb            what is left of its shields, 0 when it has none
--     alive
--     target            the unit it is working on -- the kill target for a
--                       damage dealer, the ally being healed for a healer --
--                       or nil (nothing to do, disabled, or dead)
--     disabled          nil, or which of "sheeped" / "feared" / "stunned" /
--                       "cycloned" it is in; never two at once
--     auras             a list of { state, ability, source (a unit),
--                       expires (match seconds) }; `absorb left` for a
--                       shield is aura.left
--     big               the one row of spec.spells the data marks
--                       `big = true`: the spell Tap fires
--     wait, ready       the tick it may next press anything, and per
--                       ability key the tick that ability is back (absent
--                       until its first press). unit.ready[unit.big.key]
--                       against match.tick and the row's cooldown is what a
--                       button's cooldown is drawn from
--     immune            the tick its grace against disables runs out
--     unit:Is(state)    true while it carries an aura of that state. The
--                       states: sheeped, feared, stunned, cycloned, rooted,
--                       slowed, shielded, suppressed, wounded (healing taken
--                       is cut), empowered (next hit is bigger), afflicted
--                       (a damage-over-time), mending (a heal-over-time).
--
--   Events are plain tables. Every one has `kind` and `time` (seconds).
--   `source` and `target` are unit IDS (match.units[id]); `ability` is the
--   data row itself (ability.key, .name, .icon).
--
--     ABILITY      source, target, ability, basic (true for the spec's basic
--                  attack). One per press. An area press names the nearest
--                  victim as its target. A press made by Tap also carries
--                  hand = true; a press the unit made by itself has no
--                  `hand` field at all.
--     DAMAGE       source, target, ability, amount (health actually lost),
--                  absorbed (soaked by a shield), periodic (a dot tick),
--                  crit
--     HEAL         source, target, ability, amount (health actually
--                  restored; a heal that restores nothing sends no event),
--                  periodic (a hot tick), crit. A Lifebloom bloom is the
--                  HEAL from that ability with periodic = false.
--     AURA_GAINED  source, target, ability, state, duration (seconds),
--                  refresh (true when it was already there and only its
--                  clock restarted -- one AURA_FADED still closes it)
--     AURA_FADED   target, ability, state, reason: "EXPIRED" (ran out),
--                  "BROKEN" (a disable ended by damage), "SPENT" (a shield
--                  used up, an empowered hit thrown), "DEATH"
--     MOVE         source, target, ability, mode ("DASH"/"TELEPORT"),
--                  fromX, fromY, toX, toY. Ordinary walking sends nothing;
--                  read x and y.
--     FOCUS        side, target: that team's kill target changed. When
--                  it changed to the side's pinned enemy -- on the click,
--                  or on coming back to a pin that had been a sheep -- it
--                  also carries pinned = true; a focus the team chose has
--                  no `pinned` field at all. A click on the enemy the team
--                  is already killing changes no focus and sends none:
--                  draw the pin from match.pin, not from this.
--     DEATH        target, source, ability (what killed it)
--     ROUT         side: that side has nothing left that can deal damage --
--                  no damage dealer alive and none of its dots still on a
--                  living enemy -- while the other side has a damage dealer
--                  ALIVE. A dot the dead left behind keeps a match going
--                  and routs nobody. At most one per match; from it on,
--                  nothing heals that side and no new shield goes up on it
--                  (match:Dampening(side) is 0; a shield already up soaks
--                  until it is spent), Choose offers no damage-taken buff for it, every
--                  hit on it lands RULES.routDamage times as hard, and it
--                  has lost: END names the other side, never it and never
--                  a DRAW. Not every match has one: a side whose last
--                  damage dealer is also its last unit goes straight to
--                  END.
--     END          winner ("A"/"B"/"DRAW"). Always the last event.
--
--   What Pin and Tap say is said when they are called, between two ticks,
--   with match.time as it stands then: it is at the head of the next Drain,
--   ahead of everything the following Step says.
--
--   Events are the one thing here that allocates while a match runs: each is
--   a fresh table, about 3 KB per second of match, and only while somebody
--   is stepping it (the window steps it only while it is shown). That is a
--   stated exception to the suite's "hot paths do not allocate" rule, taken
--   because a pooled event would change under a caller still holding it. A
--   tick on which nothing happened -- nearly three in four -- hands back
--   the shared empty list and allocates nothing.
--
-- HOW A MATCH PLAYS (the rules, in the order a tick applies them)
--
--   Auras    dots and hots pulse, whatever has run out fades. Any disable
--            ending, however it ends, leaves its victim immune to disables
--            for RULES.immunity seconds.
--   Actions  each living unit that is not disabled and has finished its beat
--            presses ONE thing: its spells in order, then its basic attack --
--            the first that is off cooldown and whose `when` finds a target.
--            Which side goes first is rolled every tick.
--   Walking  melee close on their target; casters and healers walk into
--            range and hold, and back away from an enemy melee on top of
--            them; a feared unit runs on a rolled heading; a rooted unit
--            does not move (and cannot Charge); a slowed one moves slower.
--            Nobody leaves the floor.
--   The bell a side with nobody standing loses. At RULES.cap, or when nobody
--            left alive can deal damage and no dot is still ticking, the
--            larger total share of health wins, or it is a DRAW. A side
--            that can no longer deal damage while the other has a damage
--            dealer alive is ROUTED: the match goes on to the kill, but
--            nothing heals the routed side any more and no new shield goes
--            up on it (one already up soaks until it is spent), its healer
--            presses no damage-taken buff such as Pain Suppression, and it
--            takes RULES.routDamage times every hit, so the kill is a few
--            seconds off and not a long shoot-out. A routed side never
--            wins and never draws: nothing it has can hurt the side that
--            routed it, and the cap, should it come first, goes to that
--            side whatever health is left.
--
--   The kill target is the enemy with the lowest share of health (an exact
--   tie is rolled for), and it is sticky: a team leaves it only when it dies,
--   is cycloned, is in a disable damage would break, or is under a
--   damage-taken buff such as Pain Suppression -- and then only if somebody
--   better is there to hit. A side with a PIN kills the pinned enemy
--   instead, whatever its health and whether or not it is under such a
--   buff, with one exception: a pin is not an order to break the team's own
--   sheep. While the pinned enemy is in a disable damage would break, or in
--   a cyclone, and somebody else can be hit, the team chooses among the
--   others as if it had no pin, and it goes back to the pin on its first
--   look after the disable ends. Crowd control (a disable that breaks, or a
--   cyclone) is never cast on the kill target and is saved for the enemy
--   healer -- so moving a pin also moves where the next Polymorph goes --
--   and a plain stun rides on kill-target abilities instead. From
--   RULES.dampenStart healing and shields shrink in a straight line to
--   nothing at RULES.dampenEnd, and no healer presses a heal or a shield
--   that dampening would turn into nothing.
--
-- THE SEAMS (what a hand has now, and what the stages after this one bring)
--
--   Choosing and pressing are separate on purpose. match:KillTarget(side)
--   answers "who", match:Choose(unit) answers "what, on whom",
--   match:Use(unit, ability, target) presses it and asks no questions.
--   Stage two put the player's hand on exactly two of those and changed
--   none of them for a match nobody touches:
--     * "Who" takes a pin. KillTarget asks match.pin[side] before it asks
--       anything else, and Pin is the checked way to set it: it refuses the
--       side's own units and the dead, and it says FOCUS.
--     * "What" takes a tap, for one spell per unit. Tap asks the questions
--       Use does not -- the match not over, the unit alive and free, the
--       cooldown, the row's own rule for a target -- and then presses
--       through Use, the same door automatic play uses.
--   Automatic play still presses every spell on the first beat it is ready,
--   the big one included, so a tap only ever fires a spell sooner than the
--   unit would have: there is no holding a spell back, and Choose was not
--   taught to leave one alone. That is what keeps an untouched match a
--   stage-one match by construction.
--
--   What is still not there, for whoever needs it next:
--     * A tap presses the big spell and nothing else, on the rule's target
--       and no other. A second spell under the hand, or a spell aimed by
--       hand, is a new question to ask before Use, not a change to it.
--     * Use itself still checks nothing at all: not range, not the
--       cooldown, not a disable on the presser, not match.over -- so a
--       caller that goes round Tap and presses after the bell puts events
--       after END. The questions Tap asks with (H.Useful, H.CanDisable,
--       H.Distance) are local to this file.
--     * Setting match.pin or match.focus by hand is not checked and says
--       nothing. Pin is the door.
--     * Nothing a hand does is kept from one match to the next: a new match
--       has no pin. Every big spell in the data was chosen for a hand on
--       side A's three; the other three carry the mark so that every spec
--       has one, and nobody has played them.
--
--   match:Damage / match:Heal are the two pipes every point of health goes
--   through, and match:Dampening(side) is the share of healing still
--   allowed on that side (leave the side out for the clock's share alone,
--   whoever is routed). E.Rules[when] and E.Effects[kind] are the two
--   vocabularies.

CommanderGladiator_Engine = CommanderGladiator_Engine or {}
local E = CommanderGladiator_Engine
local DATA = CommanderGladiator_Data
local ARENA, RULES = DATA.ARENA, DATA.RULES
local TICK = ARENA.tick

local floor, sqrt, min, max = math.floor, math.sqrt, math.min, math.max

-- Small questions about a unit, hung on one table so the chunk stays far
-- from the two-hundred-local ceiling however many of them there get to be.
local H = {}

-- ---------------------------------------------------------------------------
-- Time and chance
-- ---------------------------------------------------------------------------
-- Everything that lasts is counted in whole ticks. A cooldown of 1.8 s kept
-- as a float and decremented by 0.1 eighteen times does not reach zero; kept
-- as "ready at tick 418" it does, on every machine.
function H.Ticks(seconds)
    return floor(seconds / TICK + 0.5)
end

local Match = {}
Match.__index = Match

-- The engine's own dice: two small linear congruential generators combined
-- (L'Ecuyer's pair). Every product stays below 2^53, so the arithmetic is
-- exact in a double and the sequence is the same under Lua 5.1, luajit, and
-- whatever the client is built with.
--
-- What two such generators do NOT do by themselves is make neighbouring
-- seeds strangers. Both are multiplications, so if both states start as a
-- straight line in the seed, the k-th roll of seed n+1 is the k-th roll of
-- seed n plus a constant (mod 1) that depends only on k, and no warm-up
-- changes that. Seeds are dealt as 1, 2, 3..., and it is not harmless: the
-- first two rolls of a match are who leads the first tick and which enemy
-- the leading side opens on, their two constants happen to sum to almost
-- exactly one, and so across consecutive seeds the leading side's opening
-- came from half the dice. Measured that way, a side opened on one enemy in
-- half of a thousand matches, and over seeds 10001..11000 a mirror match
-- went to the left side six times in ten. NewMatch therefore puts one of
-- the two states through a non-linear step before play (see there), which
-- is the whole of the cure: section C of the smoke checks that the step
-- from one seed's first roll to the next is no constant.
function Match:Roll()
    local a = (self.rngA * 40014) % 2147483563
    local b = (self.rngB * 40692) % 2147483399
    self.rngA, self.rngB = a, b
    return ((a - b) % 2147483562) / 2147483562
end

-- A direct hit or heal as it actually lands: spread about its written
-- amount, and sometimes a crit.
function Match:Vary(amount)
    amount = amount * (1 + RULES.variance * (2 * self:Roll() - 1))
    local crit = self:Roll() < RULES.critChance
    if crit then amount = amount * RULES.critFactor end
    return amount, crit
end

-- The share of healing and absorbs still allowed. Whole until dampenStart,
-- then a straight line down to nothing at dampenEnd. This is what guarantees
-- an ending: two healers can out-heal two damage dealers for ever, and past
-- dampenEnd nobody heals at all.
--
-- A routed side is at nothing already, whatever the clock says: it has
-- nothing left to win with, and a healer keeping itself up against the last
-- enemy's one attack is the dull tail this rule exists to cut. Called with
-- no side it answers for the clock alone.
function Match:Dampening(side)
    if side and side == self.routed then return 0 end
    if self.time <= RULES.dampenStart then return 1 end
    return max(0, 1 - (self.time - RULES.dampenStart) / (RULES.dampenEnd - RULES.dampenStart))
end

function Match:Emit(event)
    event.time = self.time
    self.events[#self.events + 1] = event
end

-- On nearly three ticks in four nothing happens, and the window drains
-- every tick. An empty drain hands back this one list instead of trading an
-- empty table for a new empty table. Nobody may write to it: it is every
-- match's.
H.NOTHING = {}

function Match:Drain()
    local events = self.events
    if events[1] == nil then return H.NOTHING end
    self.events = {}
    return events
end

-- ---------------------------------------------------------------------------
-- Units
-- ---------------------------------------------------------------------------
local Unit = {}
Unit.__index = Unit

function Unit:Is(state)
    for _, aura in ipairs(self.auras) do
        if aura.state == state then return true end
    end
    return false
end

function H.Distance(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return sqrt(dx * dx + dy * dy)
end

function H.Clamp(x, y)
    return min(max(x, ARENA.minX), ARENA.maxX), min(max(y, ARENA.minY), ARENA.maxY)
end

-- The aura this exact effect row left on the unit, if it is there.
function H.Has(unit, effect)
    for _, aura in ipairs(unit.auras) do
        if aura.effect == effect then return aura end
    end
    return nil
end

-- The first aura of a kind, whoever's row it came from.
function H.Find(unit, kind)
    for _, aura in ipairs(unit.auras) do
        if aura.effect.kind == kind then return aura end
    end
    return nil
end

function H.Shield(unit)
    local total = 0
    for _, aura in ipairs(unit.auras) do
        total = total + (aura.left or 0)
    end
    return total
end

-- Alive and not in a cyclone: something can land on it at all.
function H.Touchable(unit)
    return unit.alive and not (unit.hold and unit.hold.effect.untouchable)
end

-- A new disable would stick: nothing holds it already, and the grace after
-- its last one has run out.
function H.CanDisable(match, unit)
    return H.Touchable(unit) and not unit.hold and match.tick >= unit.immune
end

-- How good a thing to hit a unit is, lower being better; nil for "cannot be
-- hit at all".
--   1  nothing in the way
--   2  under a damage-taken buff: most of every hit is wasted
--   3  in a disable that enough damage would end (a fear)
--   4  in a disable that ANY damage would end (a sheep)
-- Left to itself a team only ever takes its kill target from the best tier
-- that has anybody in it, which is the whole of "nobody breaks the sheep
-- while there is someone else to hit". A pin can hold it in tier 2 and no
-- lower, so that sentence stays true with a hand on the team.
function H.Tier(unit)
    if not H.Touchable(unit) then return nil end
    local held = unit.hold and unit.hold.effect
    if held and held.breakOnDamage then return 4 end
    if held and held.breakAfter then return 3 end
    local guard = H.Find(unit, "DAMAGE_TAKEN")
    if guard and guard.effect.factor < 1 then return 2 end
    return 1
end

-- Whether a spec can ever make anybody lose health. Two healers left alone
-- in an arena cannot, and the match is called rather than left to the bell.
function H.Armed(spec)
    local rows = { spec.basic, spec.spells[1], spec.spells[2] }
    for _, ability in ipairs(rows) do
        for _, effect in ipairs(ability.effects) do
            if effect.kind == "DAMAGE" or effect.kind == "DOT" then return true end
        end
    end
    return false
end

-- The one spell of a spec the data marks `big`: the one a hand may fire.
function H.Big(spec)
    for _, ability in ipairs(spec.spells) do
        if ability.big then return ability end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Auras
-- ---------------------------------------------------------------------------
-- One aura per effect row per unit. Landing it again restarts its clock and
-- says `refresh` rather than stacking a second copy, so a Frostbolt every two
-- seconds is one slow that never drops and not a pile of them.
function Match:Gain(source, target, ability, effect)
    local aura = H.Has(target, effect)
    local refresh = aura ~= nil
    if not aura then
        aura = { effect = effect, ability = ability, state = effect.state }
        target.auras[#target.auras + 1] = aura
    end
    aura.source = source
    aura.ends = self.tick + H.Ticks(effect.duration)
    aura.expires = aura.ends * TICK
    self:Emit({
        kind = "AURA_GAINED", source = source.id, target = target.id, ability = ability,
        state = effect.state, duration = effect.duration, refresh = refresh,
    })
    return aura
end

function Match:Fade(unit, aura, reason)
    for index, held in ipairs(unit.auras) do
        if held == aura then
            table.remove(unit.auras, index)
            break
        end
    end
    aura.faded = true
    self:Emit({
        kind = "AURA_FADED", target = unit.id, ability = aura.ability,
        state = aura.state, reason = reason,
    })
    if unit.hold == aura then
        -- However a disable ends -- ran out, broken, anything -- its victim
        -- gets the same grace. Without it a healer feared, then cycloned,
        -- then sheeped never plays, and the match is decided by who has more
        -- buttons rather than by anything you can watch.
        unit.hold, unit.disabled = nil, nil
        unit.immune = self.tick + H.Ticks(RULES.immunity)
    end
    if aura.left then unit.absorb = H.Shield(unit) end
    -- The bloom is paid whenever the hot comes off. A bearer that died under
    -- it gets nothing all the same, because nothing heals the dead.
    if aura.effect.bloom then
        self:Heal(aura.source, unit, aura.ability, aura.effect.bloom, false, false)
    end
end

-- ---------------------------------------------------------------------------
-- The two pipes
-- ---------------------------------------------------------------------------
-- Every point of health lost goes through here, in this order: the caster's
-- empowered hit, the target's damage-taken buff, the rout (a routed side
-- takes RULES.routDamage times everything), the target's shield, and only
-- then health. A shield that soaks the whole hit means no health was lost,
-- and a disable only breaks on health lost -- a shielded sheep stays a
-- sheep.
function Match:Damage(source, target, ability, amount, periodic, crit)
    if not H.Touchable(target) then return end
    if not periodic then
        local boost = H.Find(source, "EMPOWER")
        if boost then
            amount = amount * boost.effect.factor
            self:Fade(source, boost, "SPENT")
        end
    end
    local guard = H.Find(target, "DAMAGE_TAKEN")
    if guard then amount = amount * guard.effect.factor end
    if target.side == self.routed then amount = amount * RULES.routDamage end
    amount = floor(amount + 0.5)

    local absorbed = 0
    while absorbed < amount do
        local shield = H.Find(target, "ABSORB")
        if not shield then break end
        local soak = min(shield.left, amount - absorbed)
        shield.left = shield.left - soak
        absorbed = absorbed + soak
        if shield.left <= 0 then self:Fade(target, shield, "SPENT") end
    end
    target.absorb = H.Shield(target)

    local taken = min(amount - absorbed, target.health)
    target.health = target.health - taken
    self:Emit({
        kind = "DAMAGE", source = source.id, target = target.id, ability = ability,
        amount = taken, absorbed = absorbed, periodic = periodic and true or false,
        crit = crit and true or false,
    })

    if target.health <= 0 then
        target.alive = false
        while target.auras[1] do
            self:Fade(target, target.auras[#target.auras], "DEATH")
        end
        -- Nobody is left pointing at a corpse, the corpse included. Wish
        -- walks a unit toward its `target` at the end of this same tick, a
        -- tick before Aim next chooses, and the smoke's audit holds every
        -- unit to "no target is dead" after every step.
        for _, other in ipairs(self.units) do
            if other.target == target or other == target then other.target = nil end
        end
        -- Nor is a pin: it was a pin on somebody to kill, and that is done.
        -- The enemies of a unit are all on one side, so one field is all
        -- there is to look at.
        local foe = target.side == "A" and "B" or "A"
        if self.pin[foe] == target then self.pin[foe] = nil end
        self:Emit({ kind = "DEATH", target = target.id, source = source.id, ability = ability })
        return
    end

    local hold = target.hold
    if hold and taken > 0 then
        hold.taken = hold.taken + taken
        local rule = hold.effect
        if rule.breakOnDamage or (rule.breakAfter and hold.taken >= rule.breakAfter) then
            self:Fade(target, hold, "BROKEN")
        end
    end
end

-- And every point restored goes through here: the target's healing-taken
-- debuff, then dampening (the clock's, or none at all on a routed side),
-- then the ceiling.
function Match:Heal(source, target, ability, amount, periodic, crit)
    if not H.Touchable(target) then return end
    local wound = H.Find(target, "HEALING_TAKEN")
    if wound then amount = amount * wound.effect.factor end
    amount = floor(amount * self:Dampening(target.side) + 0.5)
    local healed = min(amount, target.healthMax - target.health)
    if healed <= 0 then return end
    target.health = target.health + healed
    self:Emit({
        kind = "HEAL", source = source.id, target = target.id, ability = ability,
        amount = healed, periodic = periodic and true or false, crit = crit and true or false,
    })
end

-- ---------------------------------------------------------------------------
-- The twelve effect kinds
-- ---------------------------------------------------------------------------
-- Each is (match, source, target, ability, effect). MOVE and EMPOWER act on
-- the caster; the rest act on the target, and are never called on one that
-- is dead or in a cyclone.
E.Effects = {}
local Effects = E.Effects

H.onCaster = { MOVE = true, EMPOWER = true }

function Effects.DAMAGE(match, source, target, ability, effect)
    local amount, crit = match:Vary(effect.amount)
    match:Damage(source, target, ability, amount, false, crit)
end

function Effects.HEAL(match, source, target, ability, effect)
    local amount, crit = match:Vary(effect.amount)
    match:Heal(source, target, ability, amount, false, crit)
end

-- A shield is dampened when it is CAST, like a heal, and is whatever is left
-- of that from then on. One that would be worth nothing is not put up.
function Effects.ABSORB(match, source, target, ability, effect)
    local amount = floor(effect.amount * match:Dampening(target.side) + 0.5)
    if amount <= 0 then return end
    local aura = match:Gain(source, target, ability, effect)
    aura.left = amount
    target.absorb = H.Shield(target)
end

function Effects.DOT(match, source, target, ability, effect)
    local aura = match:Gain(source, target, ability, effect)
    aura.pulse = match.tick + H.Ticks(effect.interval)
end
Effects.HOT = Effects.DOT

function Effects.DISABLE(match, source, target, ability, effect)
    if not H.CanDisable(match, target) then return end
    local aura = match:Gain(source, target, ability, effect)
    aura.taken = 0
    aura.turn = match.tick
    target.hold, target.disabled, target.target = aura, effect.state, nil
end

function Effects.SLOW(match, source, target, ability, effect)
    match:Gain(source, target, ability, effect)
end
Effects.ROOT = Effects.SLOW
Effects.HEALING_TAKEN = Effects.SLOW
Effects.DAMAGE_TAKEN = Effects.SLOW

function Effects.EMPOWER(match, source, _, ability, effect)
    match:Gain(source, source, ability, effect)
end

-- A dash stops on the near side of the target and a teleport lands on the
-- far side -- "behind" -- both at the distance the unit would have walked
-- to. Clamping to the floor can only bring the landing closer to a target
-- that is itself on the floor, so either always ends in reach.
function Effects.MOVE(match, source, target, ability, effect)
    local dx, dy = target.x - source.x, target.y - source.y
    local distance = sqrt(dx * dx + dy * dy)
    if distance > 0 then
        dx, dy = dx / distance, dy / distance
    else
        dx, dy = 1, 0
    end
    local gap = source.spec.range * RULES.reach
    if effect.mode == "DASH" then gap = -gap end
    local x, y = H.Clamp(target.x + dx * gap, target.y + dy * gap)
    match:Emit({
        kind = "MOVE", source = source.id, target = target.id, ability = ability,
        mode = effect.mode, fromX = source.x, fromY = source.y, toX = x, toY = y,
    })
    source.x, source.y = x, y
end

-- ---------------------------------------------------------------------------
-- Choosing a target
-- ---------------------------------------------------------------------------
-- The team's kill target: whoever in the best tier has the lowest share of
-- their health left. It is STICKY -- the team stays on the unit it picked
-- for as long as nobody is in a better tier than it, however far somebody
-- else's health drops -- because a target that changes every time two bars
-- cross is three tokens spinning on the spot.
--
-- An exact tie is settled by the match's own dice among the tied units, and
-- the dice are thrown only when the team is really choosing (nothing sticky
-- to keep), so it costs one roll per change of target and none per tick.
-- The tie that matters is the first one: at the opening everybody is whole,
-- and a tie that went to the lower slot sent every match ever played at the
-- same unit and down the same road after it.
--
-- So a target is dropped when it dies, when it cannot be hit (a cyclone),
-- when hitting it would throw away a disable (a sheep), or when hitting it
-- is mostly wasted (Pain Suppression) -- and only if somebody better is
-- there to hit instead. That last one is the swap you see in every real
-- arena match, and it is what sends a warrior across the floor at the mage.
--
-- A PIN goes before all of that. The enemy the side has pinned is the kill
-- target whoever is lower and whatever buff it is under: that is what the
-- player asked for. What a pin does not do is break the team's own sheep.
-- A pinned enemy in a disable damage would end (tiers 3 and 4), or in a
-- cyclone, is passed over while anybody in a better tier is there, the
-- choice among the rest is made exactly as it is with no pin, and the team
-- is back on the pin the first time it looks after the disable is over. A
-- pin that obeyed whatever state its enemy was in was measured against
-- this one: it was worth nothing to a player who knows what to click (side
-- A's share of a thousand matches the same to the second decimal), and it
-- cost the ones who do not, since the easiest wrong click there is, is the
-- enemy healer a moment after the mage has sheeped her.
--
-- A focus taken from a pin says so (`pinned`), and throws no dice.
function Match:KillTarget(side)
    local best, bestTier, bestShare, tied
    for _, unit in ipairs(self.units) do
        local tier = unit.side ~= side and H.Tier(unit)
        if tier then
            local share = unit.health / unit.healthMax
            if not best or tier < bestTier or (tier == bestTier and share < bestShare) then
                best, bestTier, bestShare, tied = unit, tier, share, 1
            elseif tier == bestTier and share == bestShare then
                tied = tied + 1
            end
        end
    end
    if not best then return nil end
    local current = self.focus[side]
    local pin = self.pin[side]
    if pin then
        local tier = H.Tier(pin)
        if tier and (tier < 3 or tier == bestTier) then
            if pin ~= current then
                self.focus[side] = pin
                self:Emit({ kind = "FOCUS", side = side, target = pin.id, pinned = true })
            end
            return pin
        end
    end
    if current and H.Tier(current) == bestTier then return current end
    if tied > 1 then
        local pick = 1 + floor(self:Roll() * tied)
        for _, unit in ipairs(self.units) do
            if unit.side ~= side and H.Tier(unit) == bestTier
                and unit.health / unit.healthMax == bestShare then
                pick = pick - 1
                if pick == 0 then
                    best = unit
                    break
                end
            end
        end
    end
    if best ~= current then
        self.focus[side] = best
        self:Emit({ kind = "FOCUS", side = side, target = best.id })
    end
    return best
end

-- Whether pressing this on that target would change anything. It is what
-- stops a Corruption being cast onto a Corruption, a stun being thrown at
-- somebody who is immune to it, a heal landing on a full bar, and a heal, a
-- shield or a hot being pressed into dampening that leaves nothing of it --
-- one question for every row instead of a rule per spell.
--
-- A routed side is refused twice over. Its heals, shields and hots go by
-- the dampening line above, which answers nothing for it. And a damage-taken
-- BUFF (a factor under one: Pain Suppression) is refused by its kind,
-- because on a side that can no longer win it does exactly one thing: it
-- takes back most of what the rout added to every hit and puts the long
-- ending back. While it was still pressed -- over five thousand seeds of
-- the preset, in about one in seven of the routs of the priest's side --
-- the kill came 7.0 s after such a rout and 4.3 s after the others. One
-- that is already up when the rout is said runs out its time; it is only
-- not pressed again. A damage-taken DEBUFF, were a row ever to carry one,
-- is as well worth pressing on a routed enemy as on any other.
function H.Useful(match, unit, ability, target)
    for _, effect in ipairs(ability.effects) do
        local kind = effect.kind
        if kind == "DAMAGE" or kind == "MOVE" then
            return true
        elseif kind == "HEAL" then
            if target.health < target.healthMax and match:Dampening(target.side) > 0 then return true end
        elseif kind == "ABSORB" or kind == "HOT" then
            if not H.Has(target, effect)
                and floor(effect.amount * match:Dampening(target.side) + 0.5) > 0 then
                return true
            end
        elseif kind == "DISABLE" then
            if H.CanDisable(match, target) then return true end
        elseif kind == "EMPOWER" then
            if not H.Has(unit, effect) then return true end
        elseif kind == "DAMAGE_TAKEN" and effect.factor < 1 then
            if not H.Has(target, effect) and target.side ~= match.routed then return true end
        elseif not H.Has(target, effect) then
            return true
        end
    end
    return false
end

-- The ally missing the largest share of their health, ties to the lower
-- slot; nil when nobody is hurt. With an ability it is narrowed to allies
-- that ability could usefully be pressed on from here.
function H.MostHurt(match, unit, ability)
    local best, bestShare = nil, 1
    for _, other in ipairs(match.units) do
        if other.side == unit.side and H.Touchable(other) then
            local share = other.health / other.healthMax
            if share < bestShare and (not ability or (
                share < (ability.below or 1)
                and H.Distance(unit, other) <= ability.range
                and H.Useful(match, unit, ability, other))) then
                best, bestShare = other, share
            end
        end
    end
    return best
end

-- The five targeting questions. Each is (match, unit, ability) and answers
-- with the unit to press it on, or nil for "not now".
E.Rules = {}
local Rules = E.Rules

function Rules.KILL_TARGET(match, unit, ability)
    local focus = match:KillTarget(unit.side)
    if focus and H.Distance(unit, focus) <= ability.range and H.Useful(match, unit, ability, focus) then
        return focus
    end
    return nil
end

-- Crowd control goes on somebody the team is NOT hitting: a sheep on the
-- kill target is a sheep for one global. And it goes on the healer, because
-- a healer out of the fight is what turns pressure into a kill -- so while
-- the other side has a healer the team is not already killing, the button is
-- HELD for that healer (through its grace, through somebody else's disable)
-- rather than spent on a damage dealer the moment it comes up. Only a team
-- with no healer to save it for throws it at whoever else is there.
function Rules.OFF_TARGET(match, unit, ability)
    local focus = match:KillTarget(unit.side)
    local pick, saving = nil, false
    for _, other in ipairs(match.units) do
        if other.side ~= unit.side and other ~= focus and other.alive then
            local open = H.CanDisable(match, other) and H.Distance(unit, other) <= ability.range
            if other.spec.role == "HEALER" then
                if open then return other end
                saving = true
            elseif open then
                pick = pick or other
            end
        end
    end
    if saving then return nil end
    return pick
end

function Rules.MOST_HURT_ALLY(match, unit, ability)
    return H.MostHurt(match, unit, ability)
end

-- A root holds a unit where it stands, and that includes holding it back
-- from the button that would have carried it out.
function Rules.GAP_CLOSER(match, unit, ability)
    if unit:Is("rooted") then return nil end
    local focus = match:KillTarget(unit.side)
    if not focus then return nil end
    local distance = H.Distance(unit, focus)
    if distance > unit.spec.range and distance <= ability.range then return focus end
    return nil
end

function Rules.ENEMY_NEAR(match, unit, ability)
    local best, bestDistance
    for _, other in ipairs(match.units) do
        if other.side ~= unit.side and H.Touchable(other) and not other.hold then
            local distance = H.Distance(unit, other)
            if distance <= ability.range and (not best or distance < bestDistance)
                and H.Useful(match, unit, ability, other) then
                best, bestDistance = other, distance
            end
        end
    end
    return best
end

-- ---------------------------------------------------------------------------
-- Choosing an ability, and pressing it
-- ---------------------------------------------------------------------------
-- Spells first, in the order the spec lists them, then the basic attack: the
-- first one that is off cooldown and has somebody to be pressed on.
function Match:Choose(unit)
    for _, ability in ipairs(unit.abilities) do
        if self.tick >= (unit.ready[ability.key] or 0) then
            local target = Rules[ability.when](self, unit, ability)
            if target then return ability, target end
        end
    end
    return nil
end

function Match:Land(unit, ability, target)
    for _, effect in ipairs(ability.effects) do
        if H.onCaster[effect.kind] or H.Touchable(target) then
            Effects[effect.kind](self, unit, target, ability, effect)
        end
    end
end

-- Press it. No questions asked here -- range, cooldown and sense were
-- Choose's job, or Tap's -- so that a hand on the controls presses through
-- the same door the automatic play does. `hand` is Tap saying which of the
-- two it was, and it is all Tap adds: the event of a press a unit made by
-- itself is, field for field, what it was before there was a hand.
function Match:Use(unit, ability, target, hand)
    unit.ready[ability.key] = self.tick + H.Ticks(ability.cooldown)
    unit.wait = self.tick + H.Ticks(RULES.beat)
    self:Emit({
        kind = "ABILITY", source = unit.id, target = target.id, ability = ability,
        basic = ability == unit.spec.basic, hand = hand and true or nil,
    })
    if not ability.area then
        self:Land(unit, ability, target)
        return
    end
    for _, other in ipairs(self.units) do
        if other.side ~= unit.side and H.Distance(unit, other) <= ability.range then
            self:Land(unit, ability, other)
        end
    end
end

-- ---------------------------------------------------------------------------
-- The hand
-- ---------------------------------------------------------------------------
-- The player's two verbs. Neither is called from Step, and neither knows
-- which side the player is on: the window calls them for its own side only,
-- and a match in which nobody calls them is a stage-one match.
--
-- Pin an enemy as the side's kill target, move the pin to another, or -- by
-- pinning the pinned -- let it go. The team's focus is settled here and now
-- rather than on its next beat, so that the mark the window draws from
-- match.focus moves on the click and a pin made at the gates is the opening.
function Match:Pin(side, unit)
    if self.over or not unit or not unit.alive or unit.side == side then return false end
    if self.pin[side] == unit then
        self.pin[side] = nil
        return true
    end
    self.pin[side] = unit
    self:KillTarget(side)
    return true
end

-- Whether a tap would fire the unit's big spell right now. It is asked by
-- the window for every button on every frame, so asking must leave the match
-- exactly as it was -- and a targeting rule does not: most of them ask for
-- the kill target, which can throw the dice, move the focus and say so. All
-- three are put back. A rule that ever comes to write anything else has to
-- be put back here too; section G of the smoke asks this of every unit twice
-- a tick for two hundred matches and holds the logs to the untouched ones.
function Match:Lit(unit)
    local ability = unit.big
    if self.over or not ability or not unit.alive or unit.hold
        or self.tick < (unit.ready[ability.key] or 0) then
        return false
    end
    local side, events = unit.side, self.events
    local rngA, rngB, focus, count = self.rngA, self.rngB, self.focus[side], #events
    local target = Rules[ability.when](self, unit, ability)
    self.rngA, self.rngB, self.focus[side] = rngA, rngB, focus
    for index = #events, count + 1, -1 do events[index] = nil end
    return target ~= nil
end

-- Fire the unit's big spell now, on whoever its own rule picks, without
-- waiting for the unit's beat. It goes through Use like any other press, so
-- the spell's cooldown starts and so does a new beat: a tap moves a press
-- earlier, it does not add one. A tap that would not fire changes nothing,
-- which is why the question is asked with Lit first and the rule run again
-- for its answer: the second asking finds the dice where the first left
-- them and so names the same target.
function Match:Tap(unit)
    if not self:Lit(unit) then return false end
    local ability = unit.big
    self:Use(unit, ability, Rules[ability.when](self, unit, ability), true)
    return true
end

-- ---------------------------------------------------------------------------
-- One tick
-- ---------------------------------------------------------------------------
-- Auras first: dots and hots pulse, and whatever has run out fades. A pulse
-- can kill its bearer or break the disable on it, either of which pulls
-- auras out of the list being walked, so the walk is over a copy -- one
-- scratch list for every unit, since nothing in here walks two at once.
H.aging = {}

function Match:Age(unit)
    local list = H.aging
    local count = #unit.auras
    for index = 1, count do list[index] = unit.auras[index] end
    for index = count + 1, #list do list[index] = nil end
    for index = 1, count do
        local aura = list[index]
        if not unit.alive then break end
        if not aura.faded then
            if aura.pulse and self.tick >= aura.pulse then
                aura.pulse = aura.pulse + H.Ticks(aura.effect.interval)
                if aura.effect.kind == "DOT" then
                    self:Damage(aura.source, unit, aura.ability, aura.effect.amount, true, false)
                else
                    self:Heal(aura.source, unit, aura.ability, aura.effect.amount, true, false)
                end
            end
            if unit.alive and not aura.faded and self.tick >= aura.ends then
                self:Fade(unit, aura, "EXPIRED")
            end
        end
    end
end

-- What a unit is working on, which is also where it walks: the ally most in
-- need for a healer, the team's kill target for everybody else.
function Match:Aim(unit)
    if unit.spec.role == "HEALER" then return H.MostHurt(self, unit) end
    return self:KillTarget(unit.side)
end

function Match:Act(unit)
    if not unit.alive or unit.hold then return end
    unit.target = self:Aim(unit)
    if self.tick < unit.wait then return end
    local ability, target = self:Choose(unit)
    if ability then self:Use(unit, ability, target) end
end

-- Eight headings for a feared unit, as constants rather than sin and cos of
-- a rolled angle: the last bit of a sine is the one thing here that differs
-- between two machines' maths libraries.
H.COMPASS = {
    { 1, 0 }, { 0.7071, 0.7071 }, { 0, 1 }, { -0.7071, 0.7071 },
    { -1, 0 }, { -0.7071, -0.7071 }, { 0, -1 }, { 0.7071, -0.7071 },
}

-- Where a unit would like to be at the end of this tick.
function Match:Wish(unit)
    local x, y = unit.x, unit.y
    if not unit.alive or unit:Is("rooted") then return x, y end
    local step = unit.spec.speed * TICK
    local slow = H.Find(unit, "SLOW")
    if slow then step = step * slow.effect.factor end

    local hold = unit.hold
    if hold then
        if not hold.effect.runs then return x, y end
        if self.tick >= hold.turn then
            hold.turn = self.tick + H.Ticks(RULES.fearTurn)
            hold.heading = H.COMPASS[1 + floor(self:Roll() * 8)]
        end
        local wantX, wantY = x + hold.heading[1] * step, y + hold.heading[2] * step
        local nx, ny = H.Clamp(wantX, wantY)
        -- Ran into a wall: pick again next tick rather than push at it.
        if nx ~= wantX or ny ~= wantY then hold.turn = self.tick end
        return nx, ny
    end

    if unit.spec.role ~= "MELEE" then
        local threat, threatDistance
        for _, other in ipairs(self.units) do
            if other.side ~= unit.side and other.alive and not other.hold
                and other.spec.role == "MELEE" then
                local distance = H.Distance(unit, other)
                if distance < RULES.kite and (not threat or distance < threatDistance) then
                    threat, threatDistance = other, distance
                end
            end
        end
        if threat then
            if threatDistance > 0 then
                return H.Clamp(x + (x - threat.x) / threatDistance * step,
                               y + (y - threat.y) / threatDistance * step)
            end
            return H.Clamp(x + (unit.side == "A" and -step or step), y)
        end
    end

    local target = unit.target
    if target and target.alive and target ~= unit then
        local distance = H.Distance(unit, target)
        local want = unit.spec.range * RULES.reach
        if distance > want then
            local stride = min(step, distance - want)
            return H.Clamp(x + (target.x - x) / distance * stride,
                           y + (target.y - y) / distance * stride)
        end
    end
    return x, y
end

-- The bell. A side with nobody standing has lost; at the cap, or once there
-- is nobody left who could make anybody lose health (two healers, and no dot
-- still ticking), the side holding the larger total share of its health
-- wins. One comparison covers all of it, because a dead unit holds a share
-- of nothing -- all of it but a routed side at the cap, which has lost
-- whatever it holds.
--
-- Two things can still take health: a damage dealer who is alive, and a dot
-- that is still on a living unit, whether or not whoever cast it is. Either
-- keeps the match going. Only the first can rout anybody.
--
-- A side is ROUTED when it has neither left and the other side has a damage
-- dealer ALIVE. The match is then decided but not over: it still ends on the
-- kill, because a result banner over a healer at full health reads as a
-- match that was stopped, not won. So the rout is said once, and from then
-- on Dampening answers nothing for that side, H.Useful finds a damage-taken
-- buff on it not worth pressing, and Damage multiplies what it takes -- and
-- the kill comes in a few seconds.
--
-- It is decided because nothing can undo it. The routed side has nothing
-- that takes health and can get nothing (the dead stay dead and a healer
-- lays no dots), so the damage dealer that routed it is never hurt again
-- and keeps hitting until the last of them is down. The cap is the one
-- other way out, and there the routed side has lost whatever health it is
-- holding: the line that names the winner asks who was routed first.
--
-- A dot left behind by the dead is not a damage dealer. If that were enough
-- to rout the other side -- it was, once -- the side so routed could be
-- left facing nobody who could finish it: the dot ran out, both sides were
-- harmless, the match was called on health, and a side that had been told
-- it was routed won. With only a dead unit's dot between two harmless sides
-- nobody is routed; the match waits for the dot and is called as below.
function Match:Judge()
    local standingA, standingB, shareA, shareB = 0, 0, 0, 0
    local armedA, armedB, dotA, dotB = false, false, false, false
    for _, unit in ipairs(self.units) do
        if unit.alive then
            local share = unit.health / unit.healthMax
            if unit.side == "A" then
                standingA, shareA = standingA + 1, shareA + share
                armedA = armedA or unit.armed
            else
                standingB, shareB = standingB + 1, shareB + share
                armedB = armedB or unit.armed
            end
            for _, aura in ipairs(unit.auras) do
                if aura.effect.kind == "DOT" then
                    if aura.source.side == "A" then dotA = true else dotB = true end
                end
            end
        end
    end
    local threatA, threatB = armedA or dotA, armedB or dotB
    if standingA > 0 and standingB > 0 and (threatA or threatB) and self.tick < H.Ticks(RULES.cap) then
        if not self.routed then
            local routed = (armedA and not threatB and "B") or (armedB and not threatA and "A")
            if routed then
                self.routed = routed
                self:Emit({ kind = "ROUT", side = routed })
            end
        end
        return
    end
    self.over = true
    self.winner = (self.routed == "A" and "B") or (self.routed == "B" and "A")
        or (shareA > shareB and "A") or (shareB > shareA and "B") or "DRAW"
    self:Emit({ kind = "END", winner = self.winner })
end

-- One tick, in three passes.
--
-- WHO ACTS FIRST is the one place a side could be favoured: whoever's turn
-- comes earlier lands the killing blow before the answer to it. So each tick
-- the dice pick which side leads, and the two sides alternate slot by slot
-- behind it. Nothing else in the tick depends on order: auras touch only
-- their own bearer, and every unit decides where to walk from where
-- everybody stood before anybody moved.
function Match:Step()
    if self.over then return end
    self.tick = self.tick + 1
    self.time = self.tick * TICK

    for _, unit in ipairs(self.units) do
        if unit.alive then self:Age(unit) end
    end

    local lead, trail = self.sides.A, self.sides.B
    if self:Roll() < 0.5 then lead, trail = trail, lead end
    for slot = 1, max(#lead, #trail) do
        if lead[slot] then self:Act(lead[slot]) end
        if trail[slot] then self:Act(trail[slot]) end
    end

    for _, unit in ipairs(self.units) do
        unit.wishX, unit.wishY = self:Wish(unit)
    end
    for _, unit in ipairs(self.units) do
        unit.x, unit.y = unit.wishX, unit.wishY
    end

    self:Judge()
end

-- ---------------------------------------------------------------------------
-- A new match
-- ---------------------------------------------------------------------------
function E.NewMatch(teamA, teamB, seed)
    seed = floor(math.abs(tonumber(seed) or 0)) % 2147483647
    -- The non-linear step promised at Roll: one state is the seed put four
    -- times through x * x + 12345, modulo a prime just under 2^26 so that
    -- every product is exact in a double. The other state stays a straight
    -- line in the seed on purpose -- squaring is not one-to-one, and the
    -- straight line is what keeps two different seeds from ever being dealt
    -- the same dice.
    local mixed = seed % 67108859
    for _ = 1, 4 do mixed = (mixed * mixed + 12345) % 67108859 end
    local match = setmetatable({
        tick = 0, time = 0, over = false, winner = nil,
        units = {}, sides = { A = {}, B = {} }, focus = {}, pin = {}, events = {},
        rngA = mixed + 1,
        rngB = (seed * 69069 + 1) % 2147483398 + 1,
    }, Match)
    -- The first few rolls of a freshly seeded LCG still look like the seed.
    for _ = 1, 10 do match:Roll() end

    for _, side in ipairs({ "A", "B" }) do
        for slot, key in ipairs(side == "A" and teamA or teamB) do
            local spec = DATA.SPECS[key]
            if not spec then error("Commander Gladiator: unknown spec " .. tostring(key), 2) end
            local mark = ARENA.start[side][spec.role]
            local unit = setmetatable({
                id = #match.units + 1, side = side, slot = slot, spec = spec,
                x = mark.x, y = mark.y,
                health = spec.health, healthMax = spec.health, absorb = 0,
                alive = true, target = nil, disabled = nil, hold = nil,
                auras = {}, ready = {}, immune = 0,
                abilities = { spec.spells[1], spec.spells[2], spec.basic },
                big = H.Big(spec),
                armed = H.Armed(spec),
                wait = 1 + floor(match:Roll() * H.Ticks(RULES.stagger)),
            }, Unit)
            match.units[unit.id] = unit
            match.sides[side][slot] = unit
        end
    end
    return match
end
