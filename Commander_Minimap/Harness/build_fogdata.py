#!/usr/bin/env python3
"""Generate CommanderMinimapFogData.lua — every world-map exploration overlay.

The world map draws an unexplored zone as its dark base art; the bright
terrain you have walked is painted over it as a set of overlay textures, one
per subzone. `C_MapExplorationInfo.GetExploredMapTextures(uiMapID)` hands the
client only the overlays you have EARNED — there is no API that returns the
rest, so defogging the map means shipping the full overlay list and drawing
whatever the client left out.

That list is not curated. It is the client's own tables for the build this
account runs, joined the same way the game joins them:

    WorldMapOverlay      one row per subzone overlay: size and offset on the map,
                         plus the UiMapArt it belongs to
    WorldMapOverlayTile  the overlay's texture files, on a row/column grid
    UiMapXMapArt         UiMapArt -> uiMapID, the id addon code actually has

so an overlay cannot be missing unless the client cannot draw it either.

    python3 Harness/build_fogdata.py            # writes the Lua
    python3 Harness/build_fogdata.py --report   # what would change, no write
    python3 Harness/build_fogdata.py --build 2.5.6.69110

The build defaults to whatever `.build.info` says the installed client is, so
a client patch is picked up by rerunning this with no arguments. File data ids
are build-specific: a stale table draws nothing (or the wrong art), which is
exactly why this regenerates rather than being hand-kept.
"""
import argparse
import csv
import io
import math
import os
import re
import sys
import urllib.request
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
OUT = os.path.join(ADDON, "CommanderMinimapFogData.lua")
BUILD_INFO = os.path.abspath(os.path.join(ADDON, "..", "..", "..", "..", ".build.info"))

WAGO = "https://wago.tools/db2/{table}/csv?build={build}"
TABLES = ("WorldMapOverlay", "WorldMapOverlayTile", "UiMapXMapArt", "UiMap")
UA = "Mozilla/5.0"  # wago.tools 403s a bare urllib agent

# The tile grid in WorldMapOverlayTile is laid out for the 256px tiles every
# TBC zone-map art style uses. The addon re-checks this against the layer the
# client reports at draw time and skips anything that disagrees.
TILE_SIZE = 256


def installed_build():
    """The build string of the client this addon folder lives inside."""
    try:
        with open(BUILD_INFO, encoding="utf-8", errors="replace") as f:
            text = f.read()
    except OSError:
        return None
    builds = re.findall(r"\b2\.\d+\.\d+\.\d+\b", text)
    return builds[0] if builds else None


def fetch(table, build):
    url = WAGO.format(table=table, build=build)
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=120) as resp:
        if resp.status != 200:
            raise SystemExit("%s: HTTP %s" % (table, resp.status))
        body = resp.read().decode("utf-8-sig")
    return list(csv.DictReader(io.StringIO(body)))


def build_overlays(build):
    """-> (by_map, stats). by_map[uiMapID] = [(x, y, w, h, cols, rows, [fileID...])]"""
    overlays, tiles, xmapart, uimap = (fetch(t, build) for t in TABLES)

    art_to_map = {}
    for row in xmapart:
        # A phased art variant would give one art two maps; TBC has none, and
        # silently keeping the last one would be a bug worth hearing about.
        art_to_map.setdefault(row["UiMapArtID"], row["UiMapID"])

    names = {row["ID"]: row["Name_lang"] for row in uimap}

    by_overlay = defaultdict(list)
    for tile in tiles:
        by_overlay[tile["WorldMapOverlayID"]].append(tile)

    by_map = defaultdict(list)
    stats = {"overlays": 0, "tiles": 0, "no_tiles": 0, "no_map": 0, "bad_grid": 0}

    for row in overlays:
        own = by_overlay.get(row["ID"])
        if not own:
            # Empty rows (0x0) and a handful of 128px overlays with no texture
            # files. The client draws nothing for these either.
            stats["no_tiles"] += 1
            continue
        ui_map = art_to_map.get(row["UiMapArtID"])
        if ui_map is None:
            stats["no_map"] += 1
            continue

        w, h = int(row["TextureWidth"]), int(row["TextureHeight"])
        cols = math.ceil(w / TILE_SIZE)
        rows = math.ceil(h / TILE_SIZE)
        grid = {(int(t["RowIndex"]), int(t["ColIndex"])): int(t["FileDataID"]) for t in own}
        if len(grid) != len(own) or len(grid) != cols * rows:
            stats["bad_grid"] += 1
            continue

        # Row-major, the order the client indexes fileDataIDs in:
        #   ((row - 1) * cols) + col
        try:
            files = [grid[(r, c)] for r in range(rows) for c in range(cols)]
        except KeyError:
            stats["bad_grid"] += 1
            continue

        by_map[int(ui_map)].append(
            (int(row["OffsetX"]), int(row["OffsetY"]), w, h, cols, rows, files)
        )
        stats["overlays"] += 1
        stats["tiles"] += len(files)

    for entries in by_map.values():
        entries.sort()
    return by_map, names, stats


def render(by_map, names, build, stats):
    out = []
    w = out.append
    w("-- Commander Minimap — the world-map exploration overlay table.")
    w("-- GENERATED by Harness/build_fogdata.py from the client's own tables for")
    w("-- build %s (wago.tools DB2). DO NOT HAND-EDIT: rerun the generator" % build)
    w("-- instead, or the next run silently reverts you.")
    w("--")
    w("-- Every overlay the world map can draw for a zone, explored or not. The")
    w("-- client only hands out the ones you have earned, so defogging means")
    w("-- drawing the difference between this table and")
    w("-- C_MapExplorationInfo.GetExploredMapTextures.")
    w("--")
    w("-- File data ids are BUILD-SPECIFIC. After a client patch, rerun the")
    w("-- generator; a stale table draws the wrong art or none at all.")
    w("--")
    w("-- Shape:")
    w("--   CommanderMinimapFogData[uiMapID][i] = {")
    w("--     offsetX, offsetY,        -- top-left of the overlay on the map canvas")
    w("--     width, height,           -- its size in canvas pixels")
    w("--     cols, rows,              -- the %dpx tile grid the files are cut into" % TILE_SIZE)
    w("--     fileID, fileID, ...      -- the tiles, row-major")
    w("--   }")
    w("--")
    w("-- %d overlays / %d tiles across %d maps." % (stats["overlays"], stats["tiles"], len(by_map)))
    w("")
    w("CommanderMinimapFogData = {")
    for ui_map in sorted(by_map):
        w("    -- %s" % (names.get(str(ui_map)) or "map %d" % ui_map))
        w("    [%d] = {" % ui_map)
        for x, y, ow, oh, cols, rows, files in by_map[ui_map]:
            w("        {%d,%d,%d,%d,%d,%d,%s},"
              % (x, y, ow, oh, cols, rows, ",".join(str(f) for f in files)))
        w("    },")
    w("}")
    w("")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--build", help="client build (default: the installed one)")
    ap.add_argument("--report", action="store_true", help="print the summary, write nothing")
    args = ap.parse_args()

    build = args.build or installed_build()
    if not build:
        raise SystemExit("could not read a build from %s — pass --build" % BUILD_INFO)

    by_map, names, stats = build_overlays(build)
    if not by_map:
        raise SystemExit("no overlays resolved for build %s — refusing to write" % build)

    text = render(by_map, names, build, stats)
    print("build %s: %d overlays, %d tiles, %d maps"
          % (build, stats["overlays"], stats["tiles"], len(by_map)))
    print("  skipped: %d with no texture files, %d with no uiMapID, %d with an inconsistent grid"
          % (stats["no_tiles"], stats["no_map"], stats["bad_grid"]))

    if args.report:
        old = ""
        if os.path.exists(OUT):
            with open(OUT, encoding="utf-8") as f:
                old = f.read()
        print("  %s" % ("unchanged" if old == text else "WOULD CHANGE " + OUT))
        return

    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("  wrote %s (%.0f KB)" % (OUT, len(text) / 1024))


if __name__ == "__main__":
    main()
