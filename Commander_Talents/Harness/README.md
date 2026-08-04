# Commander_Talents offline harness

Run both before any change ships:

```
cd Commander_Talents
/opt/homebrew/bin/luajit Harness/talents_harness.lua
/opt/homebrew/bin/luajit Harness/validate_class_data.lua CommanderTalentsData_Warrior.lua WARRIOR "ARMS,FURY,PROTECTION"
```

- `talents_harness.lua` — engine unit tests on a synthetic class (tier gates,
  prerequisites, removal validation, the 61 cap, export/import round trips),
  then integration checks over every `CommanderTalentsData_<Class>.lua`
  present: each preset build applies with zero problems to exactly 61 points,
  serialization round-trips, and the preset keys cover the Quartermaster
  spec list. Missing class files are reported, not failed, so the harness is
  usable mid-regeneration.
- `validate_class_data.lua` — deep structural validation of ONE class data
  file (grid bounds, unique cells, exactly one 41-pointer per tree, rank-text
  arity, prerequisite geometry, build legality). This is the file the data
  generation agents loop against; spec-key CSVs per class live in
  `talents_harness.lua`'s EXPECTED_SPECS table.

There is also a structural cross-checker against DBC-derived reference data:

```
python3 Harness/crosscheck_wowsims.py
```

It diffs every class's grid — talent roster, position, max rank, and
prerequisite edges — against the pinned wowsims/tbc talent configs in
`Harness/wowsims/` (fetched 2026-08-04 from
`raw.githubusercontent.com/wowsims/tbc/master/ui/core/talents/<class>.ts`).
All nine classes are clean as of that date; "(name-variance)" lines are
wowsims-side typos ('deterrance', 'improvedSayaad'), not our errors. Re-fetch
the snapshots only when deliberately re-baselining.

The engine is pure Lua (no WoW API), so failures here are real logic bugs,
not mock artifacts. UI smoke coverage is backlog — see the suite's
`shield_panel_harness` pattern when adding it.
