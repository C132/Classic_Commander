# Commander Kicks — harness

Four checks and no generator. Nothing here runs in the game; everything here
runs without it.

```
luajit  Harness/kicks_engine_smoke.lua       the rules (the book, the ledger, rows)
luajit  Harness/kicks_ui_smoke.lua           the plumbing (events, roster, pets, paint)
python3 Harness/order_lint.py                use-before-declaration
python3 Harness/settings_reach.py            every setting has a control
```

## Where the book comes from

`CommanderKicksData.lua` is ten entries, curated by hand: the eight class
interrupts of TBC and the blood-elf racial, in the order they take on the
bar. Which abilities count is a judgement call, and a short one — an
interrupt bar that shows anything else is slower to read for it.

The numbers on them are not judgement. Ids and cooldowns are the ones
Commander Arena Frames' generator (`make_cooldown_book.py`) read out of the
client's `SpellCooldowns` for build 2.5.6.69546; lockouts are the spell
descriptions in `Commander_Quartermaster/Harness/.cache/Spell.csv` for the
same build. **Section A of the engine smoke cross-checks every entry Arena
Frames also carries, id and cooldown**, so a patch that changes one and not
the other is a red test rather than a wrong clock.

Ranks are matched by name (the log reports the rank that was cast; the book
carries one id per spell for its icon), the three shocks resolve to Earth
Shock because they spend its cooldown, and Spell Lock is flagged as the
pet's so the module credits the warlock through the `arenapetN` tokens.

## What the UI smoke stands in for

A ~200-line WoW mock: frames that record what was set on them, unit tokens
the test populates, a combat log the test writes, and a ten-hertz OnUpdate
tick. It is deliberately smaller than the Party Frames / Arena Frames mock
— this module has one root, one pool of cells, and no secure frames — and
it asserts on what was painted (texture, desaturation, the clock's text and
colour, the sweep's start, the badge) rather than on internal state.

Two field facts the mock encodes and the game has not yet confirmed:
`arenapetN` tokens resolving to the seats' pets on this client, and
`COMBATLOG_OBJECT_TYPE_PET` being set on a felhunter's Spell Lock. Both
degrade safely if wrong — the pet becomes its own group, badged with its
initial in warlock colour — and `/ckicks report` says who is being tracked.
