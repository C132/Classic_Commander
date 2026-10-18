# Commander_Advisor harnesses

Three luajit checks, all in-addon. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit advisor_engine_smoke.lua   # engine, no mock — 1241 checks
/opt/homebrew/bin/luajit advisor_ui_harness.lua     # wiring under a WoW mock — 90 checks
/opt/homebrew/bin/luajit globals_lint.lua           # 4 files, 0 undeclared globals
```

Each prints only its failures and exits non-zero if there were any.

## `advisor_engine_smoke.lua` — the judgement

No mock. `CommanderAdvisor_Engine` is a pure function of a snapshot table,
so this loads only the Data and Engine files. Section A walks every rule in
the book (unique keys, a ladder that is highest-first, every time-to-die
rung carrying the health ceiling, every maintain spell a member of its own
family) — that is where most of the count comes from. Then: the intake book
(rate over the whole window, a burst only when sustained, no time-to-die
unless something is hitting you, attackers ageing out, the dominant
school, the ring bound); maintain rules (missing, up, expiring, the missing
grace, every quiet switch, families, school gating, Fear Ward's fear-cast
rung); react rules (ladders, Weakened Soul, own-Renew-only, the Cold Snap
backup plan, just-cast, not-while-casting, items by rule key, the bandage's
nothing-hitting-you rule, druid shifts, bear at the bottom, Shield Wall's
stance and shield, resistance totems by school, Fade PvE-only, Grounding's
two tiers, Mana Shield's mana floor); hysteresis (rise per tier, hold on
the way down, instant rise, instant drop on cast); modes, caution, ranking
and the cap; and control — nothing but the trinket while stunned, only
items while silenced, everything while merely rooted. Section H (1.3.0) is
the rules about a teammate: the ally shield picks the teammate being hit and
names them, THEIR Weakened Soul blocks it and yours does not, a shield
already on them / out of range / dead / you are skipped, the lower health
wins a tie, just-cast and silenced quiet it, a pin replaces its tier, the
signal carries who through the hysteresis; Mending counts you, is quiet
while yours is out anywhere, prefers the teammate with somebody to bounce
to and warns about a lone holder; and E.BounceReach from real positions
(within twenty, beyond, another instance, alone, the dead) and from range
bounds only (provable no, never-claimed unknown, the triangle).

## `advisor_ui_harness.lua` — the wiring

Loads the **real** shared framework (`CommanderSettingsUI.lua`,
`CommanderEvents.lua`) plus all four module files under a permissive WoW
mock (copied from Commander_Forecast's harness and extended with auras,
loss-of-control, a spellbook, action bars, items and animation groups), then
drives: login, a glow holder on every button using the proc flipbook atlas,
a missing Inner Fire glowing low only after the grace and the rise, the
glow dropping on `UNIT_SPELLCAST_SENT` before the aura lands, a melee burst
at 30% lighting the shield high with the birth flash and one sound, the
mediums waiting their rise and the fourth being cut by the cap, the tooltip
reason, Weakened Soul clearing the shield the same tick, the report, the
trinket alone while stunned, everything lapsing once nothing has hit you,
Fear Ward high while a nameplate casts Fear at you, the settings page with
one mode dropdown per priest rule, a colour and style change repainting a
lit button, the master switch clearing, and the test lighting three. The
teammate scenario (1.3.0) grows the mock a party member with per-unit auras,
positions and a @mouseover macro, then checks the Shield overlay (Weakened
Soul clock, red seconds and rim when bare, the name, one pip per seat,
the hover in words), that auras are re-read on UNIT_AURA rather than every
tick, that the macro answers for its mouseover and falls through to the
target, the pale seconds under a holding shield, the ally shield lighting
high for a teammate at 30% with their pip standing taller and the hover
naming them (and dropping when their Weakened Soul lands), the Mending
overlay (holder, charges, green rim inside twenty yards, red at thirty, no
rim without a position), `/cadv range`, and both switches clearing.

## `globals_lint.lua`

Bytecode-exact undeclared-global check over the four files. A local declared
after its use compiles to a global read that returns nil at runtime with no
warning; this names the file and the name.
