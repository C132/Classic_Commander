#!/usr/bin/env python3
"""Generate ../CommanderOrdersEntrances.lua: where every dungeon and raid is
entered, keyed by instance map id, for Commander Orders' locator
(CommanderOrdersLocate.lua, SPEC 3, critic D4).

Every number in the output is read from installed or published data, never
typed in:

  * the DOOR is the client's own AreaTrigger DB2 row (ContinentID + world
    position, wago.tools CSV for this build) of every CMaNGOS TBC
    `areatrigger_teleport` row whose target_map is a party or raid instance
    (Map DB2 InstanceType 1 or 2). The trigger is the portal itself.
  * the world position becomes a zone map position with Formulary's boundary
    rule (make_formulary.py zone_of: a box that wholly contains another
    candidate loses to it, then the smallest box the point is 10% inside,
    else the deepest), over this build's UiMap / UiMapAssignment DB2.
  * an instance entered only from inside another one (Blackwing Lair, from
    Blackrock Spire) takes that one's doors.
  * the APPROACH: where the trigger is inside a cave, a mountain or under a
    lake the straight arrow to it would run into rock, so the table also
    carries the outdoor mouth the player walks to. It is shipped only where
    an installed source names one (APPROACH below cites each: QuestieDB's
    support/Zones/dungeons.lua, or an AreaPOI DB2 row) and the trigger is
    more than APPROACH_YARDS from it. Orders points at the approach when one
    exists, else at the doors (nearest of several).
  * uiMap -> instance: UiMapAssignment rows of each instance map; a dungeon
    uiMap with no assignment row (Zul'Gurub 337, Serpentshrine 1554, Tempest
    Keep 1555) takes the instance of the assigned uiMap with its name and
    parent.
  * areaId -> instance (Questie's spawn keys, `{-1, -1}` instance spawns):
    QuestieDB's support/Zones/instanceIdToAreaId.lua with zoneIds.lua, plus
    each dungeon's alternative areaIds from dungeons.lua.

Cross-check (SPEC 3, sources 3.3): for every instance, its door nearest
Questie's dungeons.lua spot, in map-% and yards, with a verdict: agrees
(within 0.3 map-%), the portal beside Questie's spot (within APPROACH_YARDS),
approach shipped, doors kept (NO_APPROACH, with the reason), or UNREVIEWED
(a new disagreement nobody has looked at: add an APPROACH row or a
NO_APPROACH reason). The report is printed and written into the file.

Run (from anywhere):
    python3 make_entrances.py                 # write the Lua file, print the report
    python3 make_entrances.py --check         # exit 1 when the file on disk differs
                                              # (2: an input is missing)
    python3 make_entrances.py --fetch --db2 DIR   # download the DB2 CSVs first

Inputs (all read-only):
    --db2 DIR      AreaTrigger.csv, UiMap.csv, UiMapAssignment.csv, Map.csv and
                   AreaPOI.csv of build --build (default: $COMMANDER_DB2, else
                   Commander_Quartermaster/Harness/.cache, the suite's
                   git-ignored DB2 cache). --fetch writes them there from
                   https://wago.tools/db2/<Table>/csv?build=<build>.
    --tbcdb FILE   the CMaNGOS TBC dump (tbcdb.sql.gz, github.com/cmangos/tbc-db
                   Full_DB), default Commander_Quartermaster/Harness/.cache/
                   tbcdb.sql.gz; read with Commander_Formulary/Harness/cmangos.py.
    QuestieDB      ../../QuestieDB/support/Zones (the installed copy) for the
                   areaId keys, the approach points and the cross-check; the
                   generator stops when it is missing (the areaId keys need it).
"""
import argparse, csv, gzip, math, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONS = os.path.normpath(os.path.join(HERE, "..", ".."))
QM_CACHE = os.path.join(ADDONS, "Commander_Quartermaster", "Harness", ".cache")
QUESTIE_ZONES = os.path.join(ADDONS, "QuestieDB", "support", "Zones")
OUT = os.path.join(HERE, "..", "CommanderOrdersEntrances.lua")
BUILD = "2.5.6.69795"
TABLES = ["AreaTrigger", "UiMap", "UiMapAssignment", "Map", "AreaPOI"]
OUTDOOR = (0, 1, 530)
AGREE = 0.3                 # map-% (SPEC 3): a door this close to Questie's agrees
APPROACH_YARDS = 100.0      # a mouth is shipped when a door is further than this from it

# The outdoor mouths, each with its source. Shipped only when the trigger is
# further than APPROACH_YARDS from it (the generator checks and reports).
#   ("questie", areaId)  QuestieDB support/Zones/dungeons.lua, that dungeon's
#                        entrance list (on its outdoor zone)
#   ("poi", id)          AreaPOI DB2 row id (world position)
APPROACH = {
    269: ("questie", 2366, "the Caverns of Time, in Tanaris: the portal is in the cavern below"),
    534: ("questie", 3606, "the Caverns of Time, in Tanaris: the portal is in the cavern below"),
    560: ("questie", 2367, "the Caverns of Time, in Tanaris: the portal is in the cavern below"),
    229: ("questie", 1583, "Blackrock Mountain's two gates (Searing Gorge, Burning Steppes)"),
    230: ("questie", 1584, "Blackrock Mountain's two gates (Searing Gorge, Burning Steppes)"),
    409: ("questie", 2717, "Blackrock Mountain's two gates (Searing Gorge, Burning Steppes)"),
    469: ("questie", 2677, "Blackrock Mountain's two gates (Searing Gorge, Burning Steppes)"),
    545: ("poi", 2021, "Coilfang Reservoir: the portals are under the lake"),
    546: ("poi", 2021, "Coilfang Reservoir: the portals are under the lake"),
    547: ("poi", 2021, "Coilfang Reservoir: the portals are under the lake"),
    548: ("poi", 2021, "Coilfang Reservoir: the portals are under the lake"),
    43: ("poi", 1068, "the Wailing Caverns' mouth: the portal is inside the cave"),
    349: ("questie", 2100, "Maraudon's outer cave in Desolace: the portals are inside"),
    36: ("questie", 1581, "the Moonbrook mine: the portal is at the end of its tunnel"),
    90: ("questie", 721, "Gnomeregan's outer tunnel in Dun Morogh: the portals are below"),
    109: ("questie", 1477, "the sunken temple in the Pool of Tears: the portal is beneath it"),
    429: ("questie", 2557, "the road up to the ruins of Eldre'Thalas: the wings' doors are on the plateau"),
    531: ("questie", 3428, "the Scarab Wall's gate: the temple is behind it"),
    509: ("questie", 3429, "the Scarab Wall's gate: the ruins are behind it (the portal lies south of every zone map)"),
    48: ("questie", 719, "the Moonshrine Ruins on the Zoram Strand: the portal is down the flooded passage"),
    129: ("questie", 722, "the bramble maze's mouth: the portal is at the end of its path"),
    189: ("questie", 796, "the monastery's gate: the four wings' doors are inside its walls"),
    70: ("questie", 1337, "the dig site's cave and the back door's canyon: the portals are inside"),
}

# Instances where Questie's spot is more than APPROACH_YARDS from every door
# and the doors are shipped as they are, with the reason
AUCHINDOUN = "Auchindoun: Questie's spot is on the same tunnel, about 100 yd short"
NO_APPROACH = {555: AUCHINDOUN, 556: AUCHINDOUN, 557: AUCHINDOUN, 558: AUCHINDOUN}


def die(msg):
    sys.stderr.write("make_entrances.py: " + msg + "\n")
    sys.exit(2)


def read_csv(db2, name):
    path = os.path.join(db2, name + ".csv")
    if not os.path.exists(path):
        die("missing %s (run with --fetch --db2 DIR, or point --db2 at a folder holding it; "
            "https://wago.tools/db2/%s/csv?build=%s)" % (path, name, BUILD))
    with open(path, encoding="utf8") as f:
        return list(csv.DictReader(f))


def fetch(db2, build):
    os.makedirs(db2, exist_ok=True)
    for t in TABLES:
        url = "https://wago.tools/db2/%s/csv?build=%s" % (t, build)
        # wago answers 403 to urllib's default User-Agent
        req = urllib.request.Request(url, headers={"User-Agent": "curl/8.7.1"})
        with urllib.request.urlopen(req, timeout=60) as r:
            data = r.read()
        with open(os.path.join(db2, t + ".csv"), "wb") as f:
            f.write(data)
        print("fetched %s (%d bytes)" % (t, len(data)))


def read_teleports(path):
    """areatrigger_teleport rows out of the gzipped CMaNGOS dump, through
    Formulary's no-database reader (its CREATE TABLE column order and its
    VALUES tokenizer)."""
    sys.path.insert(0, os.path.join(ADDONS, "Commander_Formulary", "Harness"))
    sys.dont_write_bytecode = True          # nothing written into Formulary's folder
    import cmangos
    if not os.path.exists(path):
        die("missing the CMaNGOS dump %s" % path)
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rb") as f:
        sql = f.read().decode("utf8", "replace")
    cols = cmangos._columns(sql, "areatrigger_teleport")
    prefix = "INSERT INTO `areatrigger_teleport` VALUES "
    rows = []
    for line in sql.split("\n"):
        if line.startswith(prefix):
            for tup in cmangos._tuples(line[len(prefix):]):
                rows.append(dict(zip(cols, tup + [None] * (len(cols) - len(tup)))))
    if not rows:
        die("no areatrigger_teleport rows in %s" % path)
    return rows


# ---------------------------------------------------------------------------
# QuestieDB's zone support files (plain Lua tables, read as text)
# ---------------------------------------------------------------------------
def questie_zone_ids():
    out = {}
    with open(os.path.join(QUESTIE_ZONES, "zoneIds.lua"), encoding="utf8") as f:
        for name, value in re.findall(r"^\s*([A-Z0-9_]+)\s*=\s*(\d+)\s*,", f.read(), re.M):
            out[name] = int(value)
    return out


def questie_instance_areas(zone_ids):
    out = {}
    with open(os.path.join(QUESTIE_ZONES, "instanceIdToAreaId.lua"), encoding="utf8") as f:
        for inst, name in re.findall(r"\[(\d+)\]\s*=\s*ZoneDB\.zoneIDs\.([A-Z0-9_]+)", f.read()):
            if name in zone_ids:
                out[int(inst)] = zone_ids[name]
    return out


def questie_area_maps():
    out = {}
    with open(os.path.join(QUESTIE_ZONES, "areaIdToUiMapId.lua"), encoding="utf8") as f:
        text = f.read()

    def block(name):
        m = re.search(r"ZoneDB\.private\.%s\s*=\s*\[\[(.*?)\]\]" % name, text, re.S)
        return m.group(1) if m else ""
    # Questie's ZoneDB.Initialize applies the overrides ON TOP of the main table
    for part in (block("areaIdToUiMapId"), block("areaIdToUiMapIdOverride")):
        for area, ui in re.findall(r"\[(\d+)\]\s*=\s*(\d+)", part):
            out[int(area)] = int(ui)
    return out


def questie_dungeons():
    """{areaId: (name, [alt areaIds], [(zoneArea, x, y), ...], line)} -- the
    base table only (TBC uses no expansion override)."""
    out = {}
    with open(os.path.join(QUESTIE_ZONES, "dungeons.lua"), encoding="utf8") as f:
        lines = f.read().split("\n")
    for n, line in enumerate(lines, 1):
        if line.startswith("if Expansions"):
            break
        m = re.match(r'\s*\[(\d+)\]\s*=\s*\{"([^"]*)",(nil|\{[^}]*\}),(\d+),\{(.*)\}\},', line)
        if not m:
            continue
        area, name, alts, _parent, locs = m.groups()
        alt = [int(a) for a in re.findall(r"\d+", alts)] if alts != "nil" else []
        pts = [(int(a), float(x), float(y)) for a, x, y in
               re.findall(r"\{(\d+),\s*([\d.]+),\s*([\d.]+)\}", locs)]
        out[int(area)] = (name, alt, pts, n)
    return out


# ---------------------------------------------------------------------------
# World -> zone map (Formulary's rule, make_formulary.py zone_of)
# ---------------------------------------------------------------------------
class Zones:
    def __init__(self, uimap_rows, assign_rows):
        self.uimap = {int(r["ID"]): r for r in uimap_rows}
        self.assign = assign_rows
        self.rect = {}
        for r in assign_rows:
            u = self.uimap.get(int(r["UiMapID"]))
            if u and u["Type"] == "3" and int(r["MapID"]) in OUTDOOR:
                self.rect.setdefault(int(r["UiMapID"]), (int(r["MapID"]), float(r["Region_0"]), float(r["Region_1"]),
                                                         float(r["Region_3"]), float(r["Region_4"])))

    def zone_of(self, mapid, wx, wy, prefer=None):
        """(uiMap, x, y) of a world position. prefer: a zone uiMap taken
        whenever the point lies inside its box (the dungeon map's parent)."""
        if prefer:
            r = self.rect.get(prefer)
            if r and r[0] == mapid and r[1] <= wx <= r[3] and r[2] <= wy <= r[4]:
                inst, x0, y0, x1, y1 = r
                return prefer, (y1 - wy) / (y1 - y0), (x1 - wx) / (x1 - x0)
        hits = []
        for r in self.assign:
            if int(r["MapID"]) != mapid:
                continue
            u = self.uimap.get(int(r["UiMapID"]))
            if not u or u["Type"] != "3":
                continue
            x0, y0, x1, y1 = float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"])
            if x0 <= wx <= x1 and y0 <= wy <= y1:
                px, py = (y1 - wy) / (y1 - y0), (x1 - wx) / (x1 - x0)
                hits.append({"area": (x1 - x0) * (y1 - y0), "id": int(r["UiMapID"]), "x": px, "y": py,
                             "depth": min(px, py, 1 - px, 1 - py) * 100, "rect": (x0, y0, x1, y1)})

        def contains(outer, inner):
            return outer is not inner and outer["rect"][0] <= inner["rect"][0] and outer["rect"][1] <= inner["rect"][1] \
                and outer["rect"][2] >= inner["rect"][2] and outer["rect"][3] >= inner["rect"][3]
        hits = [h for h in hits if not any(contains(h, o) for o in hits)]
        deep = [h for h in hits if h["depth"] >= 10]
        best = min(deep, key=lambda h: h["area"]) if deep else (max(hits, key=lambda h: h["depth"]) if hits else None)
        if not best:
            return None
        return best["id"], best["x"], best["y"]

    def world_of(self, ui, x, y):
        r = self.rect.get(ui)
        if not r:
            return None
        inst, x0, y0, x1, y1 = r
        return inst, x1 - y * (x1 - x0), y1 - x * (y1 - y0)

    def yards(self, a, b):
        """Distance between two (uiMap, x, y) points; None across worlds."""
        wa, wb = self.world_of(*a), self.world_of(*b)
        if not wa or not wb or wa[0] != wb[0]:
            return None
        return math.hypot(wa[1] - wb[1], wa[2] - wb[2])


# ---------------------------------------------------------------------------
def build(args):
    trig = {int(r["ID"]): r for r in read_csv(args.db2, "AreaTrigger")}
    uimap_rows = read_csv(args.db2, "UiMap")
    assign_rows = read_csv(args.db2, "UiMapAssignment")
    maps = {int(r["ID"]): r for r in read_csv(args.db2, "Map")}
    pois = {int(r["ID"]): r for r in read_csv(args.db2, "AreaPOI")}
    tele = read_teleports(args.tbcdb)
    if not os.path.isdir(QUESTIE_ZONES):
        die("QuestieDB is not installed beside us (%s): the areaId keys come from it" % QUESTIE_ZONES)
    zones = Zones(uimap_rows, assign_rows)
    zone_ids = questie_zone_ids()
    inst_area = questie_instance_areas(zone_ids)
    area_ui = questie_area_maps()
    dungeons = questie_dungeons()
    uimap = zones.uimap

    instances = {i: r for i, r in maps.items() if r["InstanceType"] in ("1", "2")}

    # dungeon uiMaps per instance (UiMapAssignment), then the unassigned ones
    # by name and parent
    inst_maps = {}
    for r in assign_rows:
        ui, mid = int(r["UiMapID"]), int(r["MapID"])
        u = uimap.get(ui)
        if u and mid in instances and u["Type"] in ("4", "5", "6"):
            inst_maps.setdefault(mid, set()).add(ui)
    assigned = {ui: mid for mid, s in inst_maps.items() for ui in s}
    unassigned_notes = []
    for ui, u in uimap.items():
        if u["Type"] in ("4", "6") and ui not in assigned:
            for other, mid in sorted(assigned.items()):
                o = uimap[other]
                if o["Name_lang"] == u["Name_lang"] and o["ParentUiMapID"] == u["ParentUiMapID"]:
                    inst_maps[mid].add(ui)
                    unassigned_notes.append("%d %s -> %d (as %d)" % (ui, u["Name_lang"], mid, other))
                    break

    # the zone a dungeon map opens from (UiMap ParentUiMapID): the boxes of
    # Mulgore and the Barrens overlap, and the box rule alone puts the
    # Wailing Caverns in Mulgore and Onyxia's Lair in Thousand Needles
    parents = {}
    for mid, s_ in inst_maps.items():
        for ui in sorted(s_):
            par = int(uimap[ui]["ParentUiMapID"])
            if par in uimap and uimap[par]["Type"] == "3":
                parents[mid] = par
                break

    # doors: teleports into an instance from the open world
    doors, inner = {}, {}
    for t in sorted(tele, key=lambda r: r["id"]):
        mid = t["target_map"]
        if mid not in instances:
            continue
        a = trig.get(t["id"])
        if not a:
            continue
        src = int(a["ContinentID"])
        wx, wy = float(a["Pos_0"]), float(a["Pos_1"])
        if src in OUTDOOR:
            z = zones.zone_of(src, wx, wy, parents.get(mid))
            if z:
                doors.setdefault(mid, []).append((z[0], z[1], z[2], t["id"], t["name"]))
        elif src in instances and src != mid:
            inner.setdefault(mid, set()).add(src)
    chained = {}
    for mid, srcs in inner.items():
        if mid not in doors:
            for src in sorted(srcs):
                if src in doors:
                    doors[mid] = list(doors[src])
                    chained[mid] = src
                    break

    def name_of(mid):
        ui = sorted(inst_maps.get(mid, []))
        n = uimap[ui[0]]["Name_lang"] if ui else None
        if n and n.endswith("OLD"):
            n = n[:-3]
        if not n:
            area = inst_area.get(mid)
            n = dungeons[area][0] if area in dungeons else maps[mid]["MapName_lang"]
        return n

    def questie_points(area):
        d = dungeons.get(area)
        if not d:
            return []
        out = []
        for zarea, x, y in d[2]:
            ui = area_ui.get(zarea)
            if ui:
                out.append((ui, x / 100, y / 100))
        return out

    rows, report, nodoor = [], [], []
    for mid in sorted(instances):
        if mid not in doors and mid not in APPROACH:
            nodoor.append("%d %s" % (mid, maps[mid]["MapName_lang"]))
            continue
        doors.setdefault(mid, [])
        row = {"id": mid, "name": name_of(mid), "raid": instances[mid]["InstanceType"] == "2",
               "doors": doors[mid], "maps": sorted(inst_maps.get(mid, [])), "chained": chained.get(mid)}
        # areaIds (Questie's spawn keys): the instance's own and its alternatives
        area = inst_area.get(mid)
        areas = []
        if area:
            areas.append(area)
            if area in dungeons:
                areas.extend(dungeons[area][1])
        row["areas"] = areas
        # the approach, when cited and far enough from every door
        ap = APPROACH.get(mid)
        row["approach"] = None
        if ap:
            kind, ref, why = ap
            if kind == "questie":
                pts = questie_points(ref)
                cite = "QuestieDB dungeons.lua:%d" % dungeons[ref][3] if ref in dungeons else None
            else:
                p = pois.get(ref)
                pts = []
                if p:
                    z = zones.zone_of(int(p["ContinentID"]), float(p["Pos_0"]), float(p["Pos_1"]), parents.get(mid))
                    if z:
                        pts = [z]
                cite = "AreaPOI %d %s" % (ref, p["Name_lang"]) if p else None
            if not pts:
                report.append((row["name"], "APPROACH %s %s found no point: not shipped" % (kind, ref)))
            else:
                # the door furthest from its nearest mouth decides (Uldaman's
                # back door is beside its canyon, its front door deep in a cave)
                far = max([min((zones.yards((d[0], d[1], d[2]), q) or 1e9) for q in pts) for d in row["doors"]]
                          or [None], key=lambda v: -1 if v is None else v)
                if far is None or far > APPROACH_YARDS:
                    row["approach"] = (pts, cite, why, far)
                else:
                    report.append((row["name"], "APPROACH %s is %.0f yd from a door: not shipped" % (cite, far)))
        # cross-check against Questie's entrance: the door nearest its spot
        qp = questie_points(area) if area else []
        best = None
        for d in row["doors"]:
            for q in qp:
                yd = zones.yards((d[0], d[1], d[2]), q)
                pct = math.hypot((d[1] - q[1]) * 100, (d[2] - q[2]) * 100) if q[0] == d[0] else None
                if yd is not None and (best is None or yd < best[0]):
                    best = (yd, pct, d, q)
        if not row["doors"]:
            verdict = "no door on any zone map: the approach only" if row["approach"] else "no door"
        elif not qp:
            verdict = "Questie has no entrance (areaId %s)" % area
        elif best is None:
            verdict = "Questie's spot is on another continent"
        else:
            yd, pct, d, q = best
            if pct is not None:
                where = "%5.2f map-%%, %4.0f yd" % (pct, yd)
            else:
                where = "%4.0f yd (Questie's spot on uiMap %d, the door on %d)" % (yd, q[0], d[0])
            if pct is not None and pct <= AGREE:
                verdict = where + ": agrees"
            elif row["approach"]:
                verdict = where + ": approach shipped"
            elif mid in NO_APPROACH:
                verdict = where + ": doors kept, " + NO_APPROACH[mid]
            elif yd <= APPROACH_YARDS:
                verdict = where + ": the portal beside Questie's spot"
            else:
                verdict = where + ": UNREVIEWED (add an APPROACH row or say why not)"
        report.append((row["name"], "%3d %s" % (mid, verdict)))
        if not row["doors"] and not row["approach"]:
            nodoor.append("%d %s" % (mid, maps[mid]["MapName_lang"]))
            continue
        rows.append(row)
    return rows, report, nodoor, unassigned_notes, len(tele), len(trig)


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(rows, report, nodoor, unassigned, nTele, nTrig, build):
    doorCount = sum(len(r["doors"]) for r in rows)
    out = []
    w = out.append
    w("-- Commander Orders: where every dungeon and raid is entered.")
    w("--")
    w("-- GENERATED by Harness/make_entrances.py -- do not edit by hand; change the")
    w("-- generator and run it again (python3 Harness/make_entrances.py, then")
    w("-- --check). Pure data, loaded second (after CommanderOrdersData.lua); the")
    w("-- locator (CommanderOrdersLocate.lua) answers Orders' R.DoorLookup from it.")
    w("--")
    w("-- Sources, all read, none typed in:")
    w("--   doors     the client's AreaTrigger DB2 (build %s, wago.tools) joined" % build)
    w("--             to the CMaNGOS TBC areatrigger_teleport table (%d rows; %d" % (nTele, nTrig))
    w("--             triggers): every trigger that teleports into a party or raid")
    w("--             instance (Map DB2 InstanceType 1 / 2) from the open world")
    w("--             (continent 0, 1 or 530). World positions became zone map")
    w("--             positions with Formulary's boundary rule over this build's")
    w("--             UiMap / UiMapAssignment. Blackwing Lair is entered from inside")
    w("--             Blackrock Spire and takes its doors.")
    w("--   approach  the outdoor mouth, where the portal is inside a cave, a")
    w("--             mountain or under a lake (each cited on its row): Orders")
    w("--             points there, never through rock at the portal itself.")
    w("--   maps      dungeon uiMap -> instance: UiMapAssignment, and the")
    w("--             unassigned uiMaps by name and parent:")
    for note in unassigned:
        w("--               " + note)
    w("--   areas     Questie areaId -> instance (the keys of Questie's instance")
    w("--             spawns): QuestieDB support/Zones/instanceIdToAreaId.lua and")
    w("--             dungeons.lua's alternative areaIds.")
    w("-- %d instances, %d doors, %d with an approach. Not shipped (no door from" % (
        len(rows), doorCount, sum(1 for r in rows if r["approach"])))
    w("-- the open world): %s." % ", ".join(nodoor))
    w("--")
    w("-- Cross-check against Questie's dungeons.lua (QuestieDB): Questie names one")
    w("-- outdoor spot per dungeon, the trigger is the portal itself. Per instance,")
    w("-- the door nearest Questie's spot (agreement: within %.1f map-%%):" % AGREE)
    for name, text in report:
        w("--   %-26s %s" % (name, text))
    w("")
    w("CommanderOrders = CommanderOrders or {}")
    w("CommanderOrders.Entrances = {")
    w("    BUILD = %s," % lua_str(build))
    w("    -- [instance map id] = { name, raid, doors = { { uiMap, x, y, trigger }, ... },")
    w("    --   approach = { { uiMap, x, y }, ... } (the mouth, when cited) }")
    w("    DOORS = {")
    for r in rows:
        doors = ", ".join("{ %d, %.4f, %.4f, %d }" % (d[0], d[1], d[2], d[3]) for d in r["doors"])
        w("        [%d] = { name = %s, raid = %s," % (r["id"], lua_str(r["name"]), "true" if r["raid"] else "false"))
        w("            doors = { %s }," % doors if doors else "            doors = {},")
        if r["approach"]:
            pts, cite, why, far = r["approach"]
            w("            -- " + why)
            if far is None:
                w("            -- %s (no portal on any zone map)" % cite)
            else:
                w("            -- %s (%.0f yd from the portal)" % (cite, far))
            w("            approach = { %s }," % ", ".join("{ %d, %.4f, %.4f }" % p for p in pts))
        if r["chained"]:
            w("            -- entered from inside instance %d" % r["chained"])
        w("        },")
    w("    },")
    w("    -- [dungeon uiMap] = instance map id")
    w("    MAPS = {")
    pairs = sorted((ui, r["id"]) for r in rows for ui in r["maps"])
    line = "       "
    for ui, mid in pairs:
        item = " [%d] = %d," % (ui, mid)
        if len(line) + len(item) > 100:
            w(line)
            line = "       "
        line += item
    if line.strip():
        w(line)
    w("    },")
    w("    -- [Questie areaId] = instance map id")
    w("    AREAS = {")
    pairs = sorted((a, r["id"]) for r in rows for a in r["areas"])
    seen = set()
    line = "       "
    for a, mid in pairs:
        if a in seen:
            continue
        seen.add(a)
        item = " [%d] = %d," % (a, mid)
        if len(line) + len(item) > 100:
            w(line)
            line = "       "
        line += item
    if line.strip():
        w(line)
    w("    },")
    w("}")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--db2", default=os.environ.get("COMMANDER_DB2", QM_CACHE))
    ap.add_argument("--tbcdb", default=os.path.join(QM_CACHE, "tbcdb.sql.gz"))
    ap.add_argument("--build", default=BUILD)
    ap.add_argument("--fetch", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out", default=OUT)
    args = ap.parse_args()
    if args.fetch:
        fetch(args.db2, args.build)
    rows, report, nodoor, unassigned, nTele, nTrig = build(args)
    text = emit(rows, report, nodoor, unassigned, nTele, nTrig, args.build)
    print("%d instances, %d doors, %d with an approach; %d cross-check notes" % (
        len(rows), sum(len(r["doors"]) for r in rows), sum(1 for r in rows if r["approach"]), len(report)))
    for name, note in report:
        print("  %-26s %s" % (name, note))
    if nodoor:
        print("no open-world door: " + ", ".join(nodoor))
    if args.check:
        try:
            with open(args.out, encoding="utf8") as f:
                old = f.read()
        except OSError:
            old = None
        if old != text:
            print("CHECK FAILED: %s differs from what the generator writes" % args.out)
            sys.exit(1)
        print("CHECK OK: %s is current" % args.out)
        return
    with open(args.out, "w", encoding="utf8") as f:
        f.write(text)
    print("wrote %s (%d bytes)" % (args.out, len(text.encode("utf8"))))


if __name__ == "__main__":
    main()
