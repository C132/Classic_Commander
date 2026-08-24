# Commander_Dossier harnesses

Two luajit harnesses, both in-addon. Run **both** before any change.

```bash
/opt/homebrew/bin/luajit dossier_harness.lua      # engine fixture — 152 checks
/opt/homebrew/bin/luajit dossier_ui_harness.lua   # UI smoke      — 108 checks
```

Both resolve the AddOns root from their own file location, so they work in a
git worktree as well as in the live AddOns directory.

## `dossier_harness.lua` — the engine

No mock at all: `CommanderDossierEngine` is pure Lua. Drives canned crowd
control and combat histories through the real engine calls.

Covers the data file's TBC canon (no silence category, Blind with Cyclone,
Kidney Shot alone, the three PvE-diminishing categories), the diminishing
ladder, the fade-starts-the-clock rule, the never-saw-it-fade guard, the
immunity edge and its repeat floor, board filtering and ordering, records,
encounter counting, kill and death attribution, pruning, and spec inference.

Two of its checks exist because they caught real bugs and must keep teeth:

- **"the level never climbs past immune"** — the ladder capped one step too
  high, which silently disabled the immunity klaxon entirely.
- **"and it is the RIGHT unit, not a stale busier one"** — the board scratch
  was truncated *after* sorting, so a leftover unit from a busier tick could
  sort itself into the drawn rows. The fixture deliberately makes the busiest
  unit the one that lapses, so the bug cannot pass by luck.

## `dossier_ui_harness.lua` — the UI

Loads the **real** shared framework (`CommanderSettingsUI.lua`,
`CommanderEvents.lua`) plus all four addon files under the suite's permissive
widget mock, with a fixture-driven combat log and unit API. Drives login, the
settings page, live crowd control through the real `COMBAT_LOG_EVENT_UNFILTERED`
path, the board paint, board modes and visibility, geometry (pip overflow,
row ceiling, width changes), the file, the window, and every slash command.

Fixture notes worth keeping:

- The mock clock is a **real epoch** (`1786000000`). A toy clock sits below
  the login prune's cutoff, so the prune check would pass without pruning
  anything.
- `CommanderTalentsData` is mocked in the real data file's shape, so the
  module's own `BuildTalentIndex` is what gets exercised, not a stand-in.
- `HookScript` chains rather than replaces, and `BasicFrameTemplateWithInset`
  frames get real `TitleText`/`CloseButton`/`Bg`/`Inset`/`NineSlice` children —
  both are suite-wide mock lessons, not local ones.
- Reading a diminishing window **settles** it, so a query is only meaningful
  moving forward in time. Fixtures that step backwards will read zeroes.
