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
