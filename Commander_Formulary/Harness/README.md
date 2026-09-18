# Commander_Formulary harnesses

Three luajit checks plus the data generator. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit formulary_model_smoke.lua   # data + model — 2603 checks
/opt/homebrew/bin/luajit formulary_ui_harness.lua    # UI + host    — 52 checks
/opt/homebrew/bin/luajit globals_lint.lua            # 4 files, 0 undeclared globals
```

## `make_enchanting.py` — the data

```bash
python3 make_enchanting.py <scratch dir>
```

The scratch dir holds the DB2 CSVs for this build (wago.tools: SkillLineAbility, SpellName,
SpellReagents, SpellEffect, SpellEquippedItems, ItemEffect, ItemSparse, FactionTemplate, Faction,
UiMap, UiMapAssignment, AreaTable, Map) and `tbcdb.pkl`, the CMaNGOS TBC dump read once through
`cmangos.py` (a no-database reader for the SQL file: `cmangos.read(path, tables)` → rows as dicts).
It writes `../CommanderFormularyData_Enchanting.lua` and prints: how many recipes were found and
how many are obtainable; the SkillLineAbility rows that are not recipes (the five rank spells and
Disenchant); every recipe it could not source (the two never added); the category counts; and a
cross-check against Recipe Master's source list — formula by formula, what RM has that we do not.
The remaining differences are presentation caps (twelve droppers per formula, bosses first), not
data holes.

## `formulary_model_smoke.lua` — the data and the model

No mock. **A** is data integrity: every recipe categorised, coloured, making something, with a
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
combat rule, and Restore Defaults.

## `globals_lint.lua` — scoping

As in every module: luajit's bytecode listing, minus the allowed names.
