# Commander_Formulary harnesses

Three luajit checks plus the data generator. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit formulary_model_smoke.lua   # data + model — 2766 checks
/opt/homebrew/bin/luajit formulary_ui_harness.lua    # UI + host    — 180 checks
/opt/homebrew/bin/luajit globals_lint.lua            # 5 files, 0 undeclared globals
```

## `make_formulary.py` — the data

```bash
python3 make_formulary.py <scratch dir> [ENCHANTING|FIRSTAID]
```

One generator for every profession the Formulary carries; the `PROFESSIONS` table at its top is
where a profession is described (skill line, rank ladder and how each rank is obtained, category
rule, the manual rows). With no profession named it writes every data file.

The scratch dir holds the DB2 CSVs for this build (wago.tools: SkillLineAbility, SpellName,
SpellReagents, SpellEffect, SpellEquippedItems, ItemEffect, ItemSparse, FactionTemplate, Faction,
UiMap, UiMapAssignment, AreaTable, Map) and `tbcdb.pkl`, the CMaNGOS TBC dump read once through
`cmangos.py` (a no-database reader for the SQL file: `cmangos.read(path, tables)` → rows as dicts).
It writes `../CommanderFormularyData_<Name>.lua` and prints, per profession: how many recipes were found and
how many are obtainable; the SkillLineAbility rows that are not recipes (the five rank spells and
Disenchant); every recipe it could not source (the two never added); the category counts; and a
cross-check against Recipe Master's source list when that addon is installed beside us — formula
by formula, what RM has that we do not. It was, until 2026-09-18, when the check was last run:
every real formula item in RM's list is in ours (its nineteen "extras" are its own encoding of
trainer-taught crafts keyed by spell, plus two mis-mappings), ours carries four it lacks (2H -
Lesser Spirit, Chest - Major Resilience, Void Shatter, Ring - Stats), and the ten source
differences were presentation caps (twelve droppers per formula, bosses first), not data holes.
RM was then uninstalled; the check silently skips when it is absent.

Since 1.2.0 (DECISIONS D15) a creature inside an instance is written `instance = <id>`, its
Map.db2 ID (the client's instanceMapID, what Commander Orders' door table is keyed by), where it was
`instance = true`; a boss with no spawn row keeps `true`. Regenerated 2026-10-05 offline from the
Quartermaster cache (`Commander_Quartermaster/Harness/.cache`: the DB2 CSVs this script reads, plus
`tbcdb.sql.gz` read once through `cmangos.read` into `tbcdb.pkl`; `FactionTemplate.csv` is not in
that cache and came from an earlier wago.tools download; the byte-for-byte run below shows it is
the one the data was built with). Before the change that input reproduced
both data files byte for byte; after it, only the 116 instance lines moved.

## `formulary_model_smoke.lua` — the data and the model

No mock. **A** is data integrity (Enchanting) and **C** the same for First Aid plus its ladder — the
Expert book, Triage, the Master book at 300 — its two manual vendors placed where the guide puts
them, and a First Aider's view with `M.RankRoute` answering per faction. **A** is data integrity: every recipe categorised, coloured, making something, with a
teacher; every reagent and formula named; every formula sourced and teaching a listed recipe; every
vendor placed; the trainers placed; and spot checks — Minor Health's thresholds, Mongoose from
Moroes, the ring enchants as rings, the copper rod as "with the rank", Ring - Spellpower's Honored
gate as ItemSparse 5. **B** drives characters: counts, colours, craftable counts, "held" / "trainer"
/ reputation-short learnability, faction vendor usability, every filter, search by name / dropper /
reagent / faction, collapse, both sorts, and the how-to-learn lines.

## `formulary_ui_harness.lua` — the UI and the host

Loads the real shared framework plus all four files under the suite's widget mock (the
Commander_Tradecraft mock, extended with `HideUIPanel`, spell links, embedded tooltips and font
string heights). Drives login, the window, the navigator's headers and rows, the header readout,
the briefing for a known recipe (reagents with bank share, craftable count, embedded tooltip,
trainer source), the craft macro with and without "on my gear", an unknown recipe with its formula
in the bags and both vendors (one marked other-faction) and their Go buttons sending one owned
Commander Orders waypoint each, a boss drop, a reputation gate, Outland
trainers by faction, the four filters, search, collapse, the craft window being read and put away
(and left alone with the option off, and ignored for Beast Training), status, memory reset, the
combat rule, and Restore Defaults. **C8** is the Trips view walked through Commander Orders (D14): a
one-vendor zone's right-click is a waypoint owned by the vendor, a zone of several vendors (Shattrath)
is one NEAREST route of that zone's stops, Route All Trips is offered on the Trips view only and buys
every listed recipe a placed vendor sells exactly once (the oracle is read off the list itself, so
the reprinted formula items and the vendors inside instances are both accounted for), and without
Orders both print `/way` lines and send nothing. **G** is First Aid: `/cfm firstaid`, the readout and its tooltip,
the Read Recipes button re-aimed, a bandage's bare `/cast`, the trade skill window taking the
profession on screen and being put away, Cooking left alone, and a manual's tooltip verdict judged
against First Aid's skill while Enchanting is on screen.

**3.1 Go-to (D15)**: the harness loads `Commander_Events/CommanderGoButton.lua`, and its Commander
Orders stand-in records 3.1's `GoTo`, `PlaceFor`, `SharePoint`, `CopyText` and the rest (a locator
query is answered from `locatorAnswers`). **B3b** the vendor's Go is a `Commander.UI.GoButton`:
Shift-click shares the place in chat, Ctrl-click copies its `/way` line, neither sends a waypoint;
its tooltip names where, what a press does and the gestures. **B4b** Moroes carries Karazhan's id
(532) and his Go is the door (`{ entrance = { instance = 532 } }`, key "door:532"). **B4c** "any
trainer will teach it now" goes to the nearest Enchanting trainer. **G3b** with First Aid on screen
the rank readout's tooltip offers the next rank's Go; plain right-click does nothing, Ctrl+Right-
click points at the Horde Triage giver. Mutation sweep (2026-10-05, on a scratch copy pointed at a
mutated UI file): the door branch, the door key, the trainer Go, the readout's Ctrl gate, the quest
icon, the one-stop route, the Go tooltip: all killed. **B7** (review 2026-10-05) the stacked Go
buttons of "How to learn it" never overlap: Minor Mana's column of vendors and droppers, Minor
Agility's, and Major Armor's Outland trainers. A row Go is 18 high anchored 1 above a line that may
be only 12 + 3 high, so `GoRow` keeps the next row 18 below the row's top; the mock records the last
`SetPoint` for it. Without that line the check finds 22, 6 and 5 overlapping pairs, 3 px each.
**B3c / B4d** (review round 2, 2026-10-05; 175 -> 180, no check edited) a greyed Go promises no
press: 2.5.6 delivers no OnClick to a disabled Button. With Orders turned off Kulwia's Go is greyed
and neither its hover nor its own tooltip line (`_fmOpts.tooltip`, read straight, since the GoButton
now also hides a module line under an Orders-state reason) says "Prints ..."; without Orders the
placed Go stays live and its line says it prints the `/way` line; without Orders Moroes' door Go is
greyed "Needs Commander Orders" and its line is nil. Against the old wiring (`o.tooltip =
WaypointWords`) the two own-line checks fail.

## `globals_lint.lua` — scoping

As in every module: luajit's bytecode listing, minus the allowed names.
