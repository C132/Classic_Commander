# Commander_Advisor harnesses

Three luajit checks, all in-addon. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit advisor_engine_smoke.lua   # engine, no mock — 1180 checks
/opt/homebrew/bin/luajit advisor_ui_harness.lua     # wiring under a WoW mock — 56 checks
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
items while silenced, everything while merely rooted.

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
lit button, the master switch clearing, and the test lighting three.

## `globals_lint.lua`

Bytecode-exact undeclared-global check over the four files. A local declared
after its use compiles to a global read that returns nil at runtime with no
warning; this names the file and the name.
