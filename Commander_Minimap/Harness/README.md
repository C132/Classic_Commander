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

    /opt/homebrew/bin/luajit worldmap_defog_harness.lua    # 37 checks

Loads the real fog table, settings file and defog module under a WoW mock and
drives the calls the client makes. Covers the setting (default on, reachable in
the panel), the generated table's shape (every entry's tile grid matches its own
size, first tile file unique per map), and the draw itself against a synthetic
overlay whose tiling is worked out by hand: row-major tile order, the
partial-tile crop at the right and bottom edges, anchor offsets, the sublayer
that keeps revealed ground under the client's own overlays, the skip for ground
already drawn, both release paths, the live toggle, and the guard that skips a
tiled overlay when the layer's tile size disagrees with the table.

Must exit 0 before any defog change ships.
