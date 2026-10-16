# Commander_Muster harnesses

Three luajit checks, all in-addon. Run **all three** before any change.

```bash
/opt/homebrew/bin/luajit muster_engine_smoke.lua   # engine, no mock — 140 checks
/opt/homebrew/bin/luajit muster_ui_harness.lua     # UI + inspect flow — 160 checks
/opt/homebrew/bin/luajit globals_lint.lua          # 5 files, 0 undeclared globals
```

All three resolve the AddOns root from their own file location, so they work
in a git worktree as well as in the live AddOns directory. Each prints only
its failures and exits non-zero if there were any.

## `muster_engine_smoke.lua` — the engine

No mock. `CommanderMusterEngine` is pure Lua, so this loads only the Data and
Engine files and scores known items and whole kits through the real calls.
Asserts the TacoTip-compatible per-item numbers (T6 chest 186, T4 helm 145,
heroic bracers 66, Sunwell two-hander 403), the monotonic tier ordering the
original GearScore formula broke at item level 120 (swept 1–170 per quality),
the two-hander and hunter weapon rules, incomplete kits, the weakest piece,
the colour bands at each 400-point boundary, the arena line in every state,
the session book's TTL, keep limit and forget, and the season-best merge
(first sighting, rise, a lower rating keeping the best, games going down as
a new season, the server's high winning, a zero high ignored, pruning), and
the rating merge (name keys, ledger and feed sources, newest-wins with the
live > seen > feed tie order, ages, the one-line format).

## `muster_ui_harness.lua` — the UI and the inspect channel

Loads the **real** shared framework (`CommanderSettingsUI.lua`,
`CommanderEvents.lua`) plus all four module files under a permissive WoW
mock, then drives:

- login and the character readout, including the hover breakdown
- late item data on our own kit (`…` while loading, settles on
  `GET_ITEM_INFO_RECEIVED`)
- the whole quiet inspect for a mouseover — `NotifyInspect`, `INSPECT_READY`,
  `RequestInspectHonorData`, `INSPECT_HONOR_UPDATE`, `ClearInspectPlayer`, and
  the tooltip rebuilding itself with the lines
- the cooldown, the newest-wins queue, the 5s timeout, the 30s backoff, and a
  honor page that never answers
- item data landing mid-inspect, before the honor page
- who is never inspected: the other faction, creatures, ourselves, anyone in
  combat unless asked
- Blizzard's inspect window: no quiet inspect while it is opening, its answer
  fills the book and the inspect readout, and nothing clears the inspect
  under it
- the teams season shape for both our own and an inspected player
- season bests (D10): our own from `GetPersonalRatedInfo`'s second return,
  a stranger's kept in `CommanderMusterBests` through a later, lower rating,
  `best` after the win–loss in both breakdowns with the seen-best footnote,
  unrated players never written, a season reading 0 emptying nothing, a new
  season emptying the ledger, and `forget` leaving it alone
- ratings for anyone (D11): `RatingsFor` by GUID, unit token, bare name and
  Name-Realm; the mocked Commander_Ladder feed giving an other-faction player
  an Arena line with its age and no inspect; unknown names handed to `Want`,
  never ourselves; newest reading wins in both directions
- group lookups (D12): roster change, hover first, cross-realm members, a
  member out of reach passed over then caught, the 30-minute refresh, the
  combat gate and the setting
- Blizzard's lists (D13): the friends line leading with ratings and never
  doubling, the guild row tooltip, the group finder's member panel (loaded
  after login) with the listing's own leader rating, and nothing for players
  nobody knows
- the master switch, the per-surface toggles, both slash spellings, `report`
  and `forget`, and the settings page

The mock's `Hide` runs no `OnHide` and does not cascade to children; the one
place that matters (the inspect readout clearing when the window closes) runs
the hook by hand and says so.

## `globals_lint.lua`

The Armory lint applied here: luajit's bytecode listing names every global a
file touches, so an undeclared one is exact evidence of a local used before
it was declared (which compiles, silently, to nil) or an API that does not
exist. Add a genuinely new WoW API to `ALLOWED` with a note; never add a name
just to make it quiet.
