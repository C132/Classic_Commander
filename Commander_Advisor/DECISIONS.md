# Commander_Advisor — decisions

Design calls that should not be re-litigated without a reason.

**D1 — It is a rules engine, and says so.** "AI" in the request became a
declarative rulebook (`CommanderAdvisorData.lua`), a pure evaluator with
hysteresis (`CommanderAdvisorEngine.lua`) and a measured intake model. No
network, no model; the settings page and the TOC say "not a language model"
so nobody expects one. What makes it feel intelligent is the conservatism:
it is quiet unless it can back the claim up.

**D2 — Conservative means quiet, not early.** A time-to-die is only claimed
while something has hit you in the last three seconds, and only from the
rate over the whole five-second window; a two-second burst may override
that only when it is three hits or more. A single crit is a number, not an
emergency. Time-to-die rungs are ignored above the ceiling (75% health by
default). The shipped Caution is "Conservative": every health and time
threshold in the book is scaled down by a fifth.

**D3 — Three tiers, and a pinned mode overrides the ladder.** Every rule
carries its own ladder of rungs, highest first, first match wins. The
per-rule setting is one dropdown: As written / Off / Always low / medium /
high — a pin replaces whatever tier the ladder produced, it does not cap
it. That is the whole per-rule surface; thresholds are global (Caution),
not per rule, because 108 rules × thresholds is a settings page nobody
would finish.

**D4 — Hysteresis lives in the engine, not the painter.** Rise per tier
(low 1.0s, medium 0.4s, high instant), hold on the way down (1s), instant
drop when the spell is cast, the buff comes up or the blocker lands. The
client only maps rule → buttons and draws.

**D5 — Missing buffs are on the same ladder as defensives.** Out of combat
a missing self-buff is a low note; in combat with something hitting you it
is a medium prompt. "Expiring soon" is always low. A family satisfies a
rule (Prayer of Fortitude counts as Fortitude; any armour counts as armour).

**D6 — Held means silence except the trinket.** Stunned, feared,
incapacitated: nothing can be pressed, so nothing glows but a PvP trinket.
Silenced: items only. Rooted and snared: everything, plus the escape rules
that key on them.

**D7 — Blizzard's own proc art, tinted.** The client ships the modern
`UI-HUD-ActionBar-Proc-Loop-Flipbook` atlas; drawn on our own frame with a
FlipBook animation and vertex-tinted per tier it reads exactly like a
native spell alert in three colours. A plain additive border is the quieter
style and the fallback. Tier pips (one, two, three) in the top-left corner
carry the tier without colour.

**D8 — The cap is applied after the bar filter.** The engine ranks every
signal; the client counts only those with a button, so a high-ranked rule
whose spell is not on a bar does not consume one of the three slots (it
still appears in `/cadv report`, marked "not on a bar", which is how you
learn it belongs on one).

**D9 — Blizzard's bars only.** Same reasoning as Commander_Forecast: the
suite's own bar module reuses those frames and there is no third-party bar
to test against.

**D10 — The book is filtered by what you have TRAINED.** A rule for a spell
not in your spellbook never fires, whatever it is set to, and every class's
racial priest spells are simply listed — an untrained one is silent.

**D11 — The enemy's offensive cooldowns are a defensive signal.** Recklessness,
Death Wish, Blade Flurry, Adrenaline Rush, Bestial Wrath, Arcane Power,
Presence of Mind, Icy Veins, Power Infusion... seen (CLEU aura/cast, hostile
by flag) on someone who is already hitting you or has you targeted, raise
the shield / barrier / Evasion / Cloak / Shield Block rung to medium at
once, at any health. That is the one place the advisor speaks BEFORE the
damage: the burst is a fact the moment the aura lands, not an estimate. A
burst on a stranger is ignored; melee and spell bursts are told apart so
Evasion does not answer Arcane Power.

**D12 — A healer's button is pressed on somebody else (1.3.0, 2026-10-16).**
Every rule used to be about you. A rule can now be scoped to the group
(`scope = "ally"` teammates only, `"group"` teammates and you): the client
builds a small snapshot per seat — health, that teammate's own intake book
from the combat log, their buffs and debuffs, whether your spell reaches
them — and `E.AssessAllies` walks the rule's ladder against each one. The
highest tier wins, the lower health breaks a tie, and the signal carries
WHO, so the hover names them. `blockedBy`/`notWhile` read the teammate's
auras: their Weakened Soul blocks your shield on them, yours does not.
Shipped for the disc priest only: `PRIEST_PWS_ALLY` (the shield on a bare,
unlocked teammate being hit; the self rule `PRIEST_PWS` is untouched) and
`PRIEST_POM` (Mending kept rolling while yours is not out on anyone,
grouped only, aimed at whoever is being hit — and between two equally
urgent, the one with somebody within twenty yards to bounce to).

**D13 — The Shield and Mending buttons say who they are about.** An action
button shows a spell's cooldown and nothing about the target, and the one
fact that decides a Power Word: Shield press — Weakened Soul on whoever it
would land on — is not on it. Both buttons now wear an insecure overlay for
the unit the button would land on RIGHT NOW: a macro's own `@unit` when the
client's parser (`SecureCmdOptionParse`) says its conditions pick one, else
a friendly target, else you. Shield: Weakened Soul as a dark red clock with
its seconds (red when they are bare, pale while a shield still holds), a red
rim for bare-and-locked, their name across the top, and one pip per seat
along the bottom (yellow shieldable, blue shielded, red locked and bare, grey
dead; the teammate the ally rule wants stands taller). Mending: the holder's
name, its charges, and a rim for whether it can bounce on (D14). The hover
says all of it in words. Off with `ShieldWatch` / `MendingWatch`.

**D14 — Bounce range is proven or not claimed.** Mending jumps to a group
member within twenty yards of the holder. `E.BounceReach` takes two kinds of
evidence and uses each only for what it proves: a real position pair
(`UnitPosition`, same instance) is a distance; a friendly spell range check
from you is a BOUND (inside a 30-yard spell: at most 30; outside it: at least
30), and bounds only ever prove something through the triangle inequality.
Green = somebody provably within twenty; red = everyone provably beyond it;
no rim otherwise — never a guess. In practice that means: wherever the
client gives group positions the rim is exact; where it does not (see
ASSUMPTIONS on arenas) the only provable case is "Mending on you, everyone
else beyond thirty yards", which is red. `/cadv range` prints what each
seat's evidence is, so one arena skirmish settles which world you are in.

**D15 — The Mending end sound stays in Commander Party Frames.** That board
already follows Mending as the travelling object it is (a grace window that
tells a bounce from an end), and two addons tracking the same object would
mean two sounds for one end. The "wasted" ending — expired, purged, or a
heal with nobody in range to jump to — got its own line and sound there
(Party Frames 5.44.0, the holy fizzle).
