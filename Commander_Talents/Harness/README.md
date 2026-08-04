# Commander_Talents offline harness

Run all of these before any change ships:

```
cd Commander_Talents
/opt/homebrew/bin/luajit Harness/talents_harness.lua
/opt/homebrew/bin/luajit Harness/talents_ui_harness.lua
/opt/homebrew/bin/luajit Harness/validate_class_data.lua CommanderTalentsData_Warrior.lua WARRIOR "ARMS,FURY,PROTECTION"
```

- `talents_harness.lua` — engine unit tests on a synthetic class (tier gates,
  prerequisites, removal validation, the 61 cap, export/import round trips),
  then integration checks over every `CommanderTalentsData_<Class>.lua`
  present: each preset build applies with zero problems to exactly 61 points,
  serialization round-trips, and the preset keys cover the Quartermaster
  spec list. Missing class files are reported, not failed, so the harness is
  usable mid-regeneration.
- `talents_ui_harness.lua` — loads the REAL shared framework
  (`CommanderSettingsUI.lua`, `CommanderEvents.lua`) plus every
  Commander_Talents file under a permissive WoW mock, then drives the whole
  window: login and defaults, lazy window creation, tree binding on all nine
  classes, talent clicks in both directions, tier/prerequisite/cap refusals
  and their messages, desaturation of locked talents, the bent Rogue arrow,
  preset and custom loadouts (save, re-select, delete, sidebar overflow),
  export/import including a Wowhead URL and a garbage string, the briefing
  panel with Quartermaster present, spec-less, and absent entirely, class
  switching, live-talent import in both `GetTalentInfo` shapes, and settings
  application. The mock chains `HookScript` handlers rather than replacing
  them, and `SetFont` asserts on invalid flag strings — both are real client
  behaviours that have burned this suite before.
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

The engine is pure Lua (no WoW API), so failures there are real logic bugs,
not mock artifacts. The UI harness resolves the AddOns root from its own
file location, so it runs from a git worktree as well as the live
directory.
