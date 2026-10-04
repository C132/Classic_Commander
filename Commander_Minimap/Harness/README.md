# Headless harness (never loaded by the client — not in the TOC)

## The world-map fog table

    python3 build_fogdata.py            # writes ../CommanderMinimapFogData.lua
    python3 build_fogdata.py --report   # what would change, no write

Generates every world-map exploration overlay from the client's own DB2s
(`WorldMapOverlay` + `WorldMapOverlayTile` joined to a uiMapID through
`UiMapXMapArt`), pulled from wago.tools for the build `.build.info` says is
installed. 750 overlays / 1170 tiles across 52 zone maps at 2.5.6.69110.

The client only hands out the overlays you have already explored
(`C_MapExplorationInfo.GetExploredMapTextures`), so the rest have to be shipped
for the defog option to draw them.

**File data ids are build-specific.** Rerun this after a client patch — a stale
table draws the wrong art or none at all. Overlays with no texture files (65 of
them: empty rows and a handful of 128px leftovers) are dropped; the client draws
nothing for those either.

## Verification

    /opt/homebrew/bin/luajit worldmap_defog_harness.lua    # 43 checks

Loads the real fog table, settings file and defog module under a WoW mock and
drives the calls the client makes. Covers the setting (default on, reachable in
the panel), the generated table's shape (every entry's tile grid matches its own
size, first tile file unique per map), and the draw itself against a synthetic
overlay whose tiling is worked out by hand: row-major tile order, the
partial-tile crop at the right and bottom edges, anchor offsets, the sublayer
that keeps revealed ground under the client's own overlays, the skip for ground
already drawn, both release paths, the live toggle, and the guard that skips a
tiled overlay when the layer's tile size disagrees with the table.

Its last six checks are not about the fog: they load `CommanderMinimap.lua` in
a sealed sandbox (neither harness here loads that file otherwise) and prove the
global `GetMinimapShape()` it defines for the square mask (2.4.0, for Commander
Orders' minimap pins and every HereBeDragons/LibDBIcon user): nothing defined
while the file merely loads or on another addon's ADDON_LOADED, the square mask
goes on, the function then answers `SQUARE`, and an existing `GetMinimapShape`
from another addon is never overwritten. Commander Orders'
`orders_pins_harness.lua` section K loads the same file inside its own mock and
checks that its pins clamp to the square and survive the button tidy.

Must exit 0 before any defog change ships.

## The XP tracker (information button)

    /opt/homebrew/bin/luajit xp_tracker_harness.lua     # 57 checks

Loads the real XP model (`CommanderMinimapXP.lua`) and the real button file
under a WoW mock and drives login, kill lines (plain, rested, rested + group),
quest turn-ins, exploration XP and a level-up across the boundary. Covers the
chat parsing (built from the client's own `COMBATLOG_XPGAIN_*` format strings),
the session split by source, XP/hour and time to level, kills to level with
rested doubling applied to the base-XP average, the rested marker spilling into
the next level, time to the 150% rested cap, every button display mode, the
right-click menu, shift-click paste, ctrl-click reset, and the max-level state.

Must exit 0 before any XP tracker change ships.
