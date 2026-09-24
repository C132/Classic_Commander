# Commander_Formulary harnesses

Three luajit checks plus the data generator. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit formulary_model_smoke.lua   # data + model — 2766 checks
/opt/homebrew/bin/luajit formulary_ui_harness.lua    # UI + host    — 116 checks
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
in the bags and both vendors (one marked other-faction), a boss drop, a reputation gate, Outland
trainers by faction, the four filters, search, collapse, the craft window being read and put away
(and left alone with the option off, and ignored for Beast Training), status, memory reset, the
combat rule, and Restore Defaults. **G** is First Aid: `/cfm firstaid`, the readout and its tooltip,
the Read Recipes button re-aimed, a bandage's bare `/cast`, the trade skill window taking the
profession on screen and being put away, Cooking left alone, and a manual's tooltip verdict judged
against First Aid's skill while Enchanting is on screen.

## `globals_lint.lua` — scoping

As in every module: luajit's bytecode listing, minus the allowed names.
