#!/usr/bin/env python3
"""Second opinion on SOURCING, from AtlasLoot's TBC tables.

crosscheck_enhancements.py verifies identity — name, quality, level, gate —
against Wowhead. It cannot verify SOURCING, because the tooltip endpoint does
not carry any. That leaves the one risk the generator cannot see in itself: a
systematic hole in the world DB, where a whole vendor or a whole wing is
missing and every entry that should point at it quietly points nowhere.

AtlasLoot Classic is an independent, hand-curated dataset built by players
against the live game, and it is installed alongside this addon. Where it
places an item — under a faction at a standing, under a boss, on a PvP
vendor — is a claim we can check ours against.

Checks, for every enhancement item AND every recipe that teaches one:

    KNOWN-NOWHERE  AtlasLoot lists it, we have no source at all
    FACTION        both name a reputation gate, and they disagree
    STANDING       same faction, different standing
    UNSEEN         we source it, AtlasLoot has never heard of it (informational:
                   AtlasLoot does not attempt to cover world drops or trainers)

    python3 Harness/crosscheck_atlasloot.py
    python3 Harness/crosscheck_atlasloot.py --verbose
"""
import argparse
import os
import re
import subprocess
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
ADDONS = os.path.dirname(ADDON)
DATA = os.path.join(ADDON, "CommanderQuartermasterEnhanceData.lua")
LUAJIT = os.environ.get("LUAJIT", "/opt/homebrew/bin/luajit")

# AtlasLoot's TBC files. The suffix matters: data.lua is vanilla, data-wrath
# is the expansion after, and mixing them in would invent sources.
SOURCES = [
    "AtlasLootClassic_Factions/data-tbc.lua",
    "AtlasLootClassic_DungeonsAndRaids/data-tbc.lua",
    "AtlasLootClassic_PvP/data-tbc.lua",
    "AtlasLootClassic_Crafting/data-tbc.lua",
    "AtlasLootClassic_Collections/data-tbc.lua",
]

TABLE = re.compile(r'^data\["([^"]+)"\]\s*=')
FACTION_ID = re.compile(r"^\s*FactionID\s*=\s*(\d+)")
SECTION = re.compile(r'^\s*\{\s*--\s*(.+?)\s*$')
NAME = re.compile(r'^\s*name\s*=\s*(?:ALIL|AL)\["([^"]+)"\]')
NAME_RAW = re.compile(r'^\s*name\s*=\s*"([^"]+)"')
ITEM = re.compile(r"^\s*\{\s*-?\d+\s*,\s*(\d+)\s*[,}]")

STANDINGS = ("Hated", "Hostile", "Unfriendly", "Neutral", "Friendly",
             "Honored", "Revered", "Exalted")


def parse_atlasloot():
    """item id -> list of {table, faction, standing, section, file}."""
    out = defaultdict(list)
    for rel in SOURCES:
        path = os.path.join(ADDONS, rel)
        if not os.path.exists(path):
            sys.stderr.write("skipping absent %s\n" % rel)
            continue
        table, faction, section = None, None, None
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = TABLE.match(line)
                if m:
                    table, faction, section = m.group(1), None, None
                    continue
                m = FACTION_ID.match(line)
                if m:
                    faction = int(m.group(1))
                    continue
                m = SECTION.match(line) or NAME.match(line) or NAME_RAW.match(line)
                if m:
                    section = m.group(1)
                    continue
                m = ITEM.match(line)
                if m:
                    out[int(m.group(1))].append({
                        "table": table, "faction": faction,
                        "standing": section if section in STANDINGS else None,
                        "section": section, "file": rel.split("/")[0],
                    })
    return out


DUMP = r'''
dofile(%s)
local d = CommanderQuartermasterEnhanceData
local out = {}
local function rep(src)
    for _, s in ipairs(src or {}) do
        if s.faction and s.faction.id then
            return s.faction.id, s.faction.standing or ""
        end
    end
    return 0, ""
end
for _, e in ipairs(d.Entries) do
    local fid, standing = rep(e.src)
    local kinds = {}
    for _, s in ipairs(e.src or {}) do kinds[#kinds + 1] = s.k end
    out[#out + 1] = table.concat({ "E", e.item or 0, e.name or "", fid, standing,
                                   table.concat(kinds, "+"), e.unobtainable and 1 or 0 }, "\t")
    -- recipes are sourced separately and are half the sourcing surface
    for _, s in ipairs(e.src or {}) do
        for _, l in ipairs(s.learn or {}) do
            if l.k == "RECIPE" and l.item then
                local lf, ls = rep(l.src)
                local lk = {}
                for _, ss in ipairs(l.src or {}) do lk[#lk + 1] = ss.k end
                out[#out + 1] = table.concat({ "R", l.item, l.name or "", lf, ls,
                                               table.concat(lk, "+"), 0 }, "\t")
            end
        end
    end
end
io.write(table.concat(out, "\n"))
'''


def load_ours():
    proc = subprocess.run([LUAJIT, "-e", DUMP % ("[[%s]]" % DATA)],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("luajit failed: %s" % proc.stderr[:400])
    rows, seen = [], set()
    for line in proc.stdout.splitlines():
        kind, item, name, fid, standing, kinds, unob = line.split("\t")
        item = int(item)
        key = (kind, item)
        if not item or key in seen:
            continue
        seen.add(key)
        rows.append({"kind": kind, "item": item, "name": name, "faction": int(fid),
                     "standing": standing, "kinds": kinds.split("+") if kinds else [],
                     "unobtainable": unob == "1"})
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    atlas = parse_atlasloot()
    ours = load_ours()
    if not atlas:
        raise SystemExit("no AtlasLoot TBC data found next to this addon")

    issues = defaultdict(list)
    overlap = 0
    for row in ours:
        listings = atlas.get(row["item"])
        if not listings:
            if row["kinds"]:
                issues["unseen"].append((row["item"], row["name"]))
            continue
        overlap += 1
        if not row["kinds"]:
            issues["known-nowhere"].append(
                (row["item"], row["name"],
                 "AtlasLoot: %s / %s" % (listings[0]["table"], listings[0]["section"])))
            continue
        theirs = [l for l in listings if l["faction"]]
        if theirs and row["faction"]:
            if not any(l["faction"] == row["faction"] for l in theirs):
                issues["faction"].append(
                    (row["item"], row["name"], row["faction"],
                     ", ".join(str(l["faction"]) for l in theirs)))
            else:
                same = [l for l in theirs if l["faction"] == row["faction"]]
                standings = {l["standing"] for l in same if l["standing"]}
                if standings and row["standing"] and row["standing"] not in standings:
                    issues["standing"].append(
                        (row["item"], row["name"], row["standing"], ", ".join(sorted(standings))))
        elif theirs and not row["faction"]:
            issues["missing-rep"].append(
                (row["item"], row["name"],
                 "AtlasLoot: faction %s %s" % (theirs[0]["faction"], theirs[0]["standing"])))

    print("AtlasLoot knows %d item ids; %d of our %d enhancement/recipe items overlap"
          % (len(atlas), overlap, len(ours)))
    for key in ("known-nowhere", "faction", "standing", "missing-rep", "unseen"):
        rows = issues[key]
        print("  %-14s %4d" % (key, len(rows)))
        show = rows if args.verbose else rows[:10]
        for row in show:
            print("      " + " | ".join(str(x) for x in row))
        if not args.verbose and len(rows) > len(show):
            print("      …%d more (--verbose)" % (len(rows) - len(show)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
