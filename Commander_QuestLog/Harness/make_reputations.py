#!/usr/bin/env python3
"""Generate CommanderQuestLogReputationData.lua: the reputation rules the
Reputations tab and every quest surface compute their one number from.

Why a generator at all. No API in this client tells an addon what a quest
pays in reputation (GetQuestLogRewardFactionInfo is absent from the 2.5.6
binary), and the one table that does exist, Questie's reputationReward, is
raw and incomplete: it has no reward clamp, it carries spillover written into
the rows as if it were a reward, and it knows nothing of how a gain spills to
other factions. Everything else the engine needs lives in two places this
script reads, and nowhere at run time:

  * the client's own Faction DB2 for this build (wago.tools CSV, 2.5.6.69795):
    each faction's starting standing per race and class, its parent, and the
    spillover columns (rate in, rate out, the highest rank a spill lands in);
    the same table per locale for the names of factions not yet met
  * the CMaNGOS TBC world DB (tbc-db Full_DB dump, read with
    Commander_Formulary/Harness/cmangos.py): the server's spillover template,
    the per-faction reward rates, and per quest the reward clamp
    (RewMaxRepValue), the items a repeatable takes, and who hands out the
    rotating dailies

and one optional input, written by hand after a Wowhead audit:

  * Harness/reputation_overrides.json  {questId: {factionId: value, "src": url,
    "note": "..."}} -- rows where Wowhead (TBC) disagrees with both databases
    and is plausibly right. Every row must cite its page; an uncited row is
    refused, not emitted.

Run (no network unless --fetch):
    python3 Commander_QuestLog/Harness/make_reputations.py            # rebuild from cache
    python3 Commander_QuestLog/Harness/make_reputations.py --fetch    # refresh the locale CSVs first
    python3 Commander_QuestLog/Harness/make_reputations.py --check    # exit 1 if the file is stale
    python3 .../make_reputations.py --questie questie_rep.tsv         # also reconcile against a Questie dump

The cache is the suite's shared, git-ignored generator cache
(Commander_Quartermaster/Harness/.cache, or --cache / $CQL_REP_CACHE). Its
Faction.csv and tbcdb.sql.gz come from Quartermaster's own fetch
(tbcdb_to_sqlite.py --fetch); this script adds Faction_<locale>.csv beside
them. The output is pure data -- one global table, no code -- and the report on
stdout is the list of everything that did not reconcile, which is the list to
read by hand. See ../DECISIONS.md and the 1.6.0 notes in ../ASSUMPTIONS.md.
"""
import argparse
import collections
import csv
import json
import gzip
import os
import re
import struct
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
MODULE = os.path.dirname(HERE)
ADDONS = os.path.dirname(MODULE)
sys.path.insert(0, os.path.join(ADDONS, "Commander_Formulary", "Harness"))
sys.dont_write_bytecode = True   # borrow Formulary's reader without writing into its folder
import cmangos  # noqa: E402  (the suite's one reader for the CMaNGOS dump)

BUILD = "2.5.6.69795"
DEFAULT_CACHE = os.environ.get("CQL_REP_CACHE") or os.path.join(ADDONS, "Commander_Quartermaster", "Harness", ".cache")
DEFAULT_OUT = os.path.join(MODULE, "CommanderQuestLogReputationData.lua")
DEFAULT_OVERRIDES = os.path.join(HERE, "reputation_overrides.json")
WAGO = "https://wago.tools/db2/Faction/csv?build=%s" % BUILD

# The localized names cost about 5 KB of a ~30 KB file. They only matter on a
# non-English client, for a faction the character has not met, and only if
# GetFactionInfoByID answers nil for such a faction (ASSUMPTIONS A21, not yet
# checked in game). False ships an empty names table, and the adapter falls
# back to the enUS name.
SHIP_NAMES = True

# Every locale the Anniversary client can run in other than enUS/enGB. itIT
# is in the list so the report can say it adds nothing (wago's itIT table for
# this build is the enUS one), not because it ships a table.
LOCALES = ["deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW"]

# Playable race bits (ChrRaces.PlayableRaceBit = raceID - 1 for races 1-11)
ALLIANCE_RACES = sum(1 << (r - 1) for r in (1, 3, 4, 7, 11))   # Human, Dwarf, Night Elf, Gnome, Draenei
HORDE_RACES = sum(1 << (r - 1) for r in (2, 5, 6, 8, 10))      # Orc, Undead, Tauren, Troll, Blood Elf

POINTS_IN_RANK = [36000, 3000, 3000, 3000, 6000, 12000, 21000, 1000]   # ReputationMgr.cpp:25-37
BOTTOM, CAP = -42000, 42999

DAILY = 4096          # QuestFlags QUEST_FLAGS_DAILY
REPEATABLE = 1        # SpecialFlags QUEST_SPECIAL_FLAG_REPEATABLE

# ---------------------------------------------------------------------------
# The curated part. The DB2 Expansion column is 0 on every row of this build,
# so which factions are "TBC" cannot be read out of the data; it is this list.
# Group order is the picker's order, TBC first. Within a group the ids are
# sorted by their enUS name (the adapter re-sorts by the name it shows).
# ---------------------------------------------------------------------------
TBC_GROUPS = [
    # key, title, the DB2 header it mirrors (its client name can stand in for the title)
    ("OUTLAND", "Outland", 980),
    ("SHATTRATH", "Shattrath City", 936),
    ("TBC_OTHER", "Other (TBC)", None),
]
# Factions of the TBC era with no Outland or Shattrath parent: the two new
# capitals sit under the Alliance and Horde headers in the DB2, the four
# others under none
TBC_OTHER = [911, 922, 930, 967, 989, 990]
CLASSIC_GROUPS = [
    ("ALLIANCE", "Alliance", 469, "Alliance"),
    ("HORDE", "Horde", 67, "Horde"),
    ("STEAMWHEEDLE", "Steamwheedle Cartel", 169, None),
    ("CLASSIC_OTHER", "Other", None, None),
]

# The two Wanted givers in Shattrath's Lower City hand out one random normal
# (Mah'duun) and one random heroic (Zhareem) each day (warcraft.wiki.gg Wind
# Trader Zhareem). Read off creature_questrelation rather than typed, so a
# quest added to either giver joins the rotation.
ROTATING_GIVERS = {24370: "NORMAL", 24369: "HEROIC"}   # Nether-Stalker Mah'duun, Wind Trader Zhareem

# Dailies that are only offered while your side holds something. Nothing in
# either database says so; this is the list.
CONDITIONAL = {
    11502: "HALAA",   # In Defense of Halaa (Alliance)
    11503: "HALAA",   # Enemies, Old and New (Horde)
}

# Reward clamps the world DB cannot carry because it has no rows for the
# quest: Ally of the Netherwing has a Human copy, 10871, which CMaNGOS keeps
# only as a "BETA" stub with no reward. It must land on the same 0 as 10870
# whatever raw value it is given (Questie's 42000 would read +46,200 for a
# Human; the audit's 38182 reads +42,000), so it gets 10870's clamp.
MANUAL_REWARD_CAP = {
    10871: {1015: 0},   # mirrors 10870 RewMaxRepValue 0
}

# Questie stores spillover in a few rows CMaNGOS does not have at all. Those
# are found again from a Questie dump when one is given (--questie); without
# one, this snapshot of what the 2026-10-04 dump (real QuestieDB 1.0.4, TBC)
# found keeps the output identical. The report says whether the dump and the
# snapshot still agree.
QUESTIE_ONLY_DERIVED = {
    9266: [21, 369, 470],   # Making Amends: Everlook 500 listed with 250 to each goblin town
    9268: [21, 470, 577],   # War at Sea: Gadgetzan 500 listed with 250 to each goblin town
}

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

def fetch(url, path):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    sys.stderr.write("fetching %s\n" % url)
    with urllib.request.urlopen(req, timeout=120) as r:
        body = r.read()
    if not body.startswith(b"Name_lang,"):
        raise SystemExit("unexpected response from %s" % url)
    with open(path + ".part", "wb") as f:
        f.write(body)
    os.replace(path + ".part", path)


def read_csv(path):
    with open(path, encoding="utf8", newline="") as f:
        return {int(r["ID"]): r for r in csv.DictReader(f)}


def read_dump(path, tables):
    """cmangos.read over the gzipped dump, without unpacking it to disk."""
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf8", errors="replace") as f:
        sql = f.read()
    cols = {t: cmangos._columns(sql, t) for t in tables}
    out = {t: [] for t in tables}
    prefixes = {"INSERT INTO `%s` VALUES " % t: t for t in tables}
    for line in sql.split("\n"):
        if not line.startswith("INSERT INTO `"):
            continue
        for prefix, t in prefixes.items():
            if line.startswith(prefix):
                c = cols[t]
                for tup in cmangos._tuples(line[len(prefix):]):
                    out[t].append(dict(zip(c, tup + [None] * (len(c) - len(tup)))))
                break
    return out


def read_questie(path):
    """A Questie dump as the realdata harness writes it (qrep.lua): per quest
    id, reputationReward, requiredMinRep, requiredMaxRep, specialFlags,
    questFlags, questLevel and name, tab-separated, tables as {a,b}."""
    pair =re.compile(r"\{(-?\d+),(-?\d+)\}")
    out = {}
    with open(path, encoding="utf8") as f:
        for line in f:
            p = line.rstrip("\n").split("\t")
            if len(p) < 4 or not p[0].isdigit():
                continue
            rows = [(int(a), int(b)) for a, b in pair.findall(p[1])] if p[1] != "nil" else []
            mn = pair.findall(p[2]) if p[2] != "nil" else []
            mx = pair.findall(p[3]) if p[3] != "nil" else []
            out[int(p[0])] = {
                "rows": dict(rows),
                "min": (int(mn[0][0]), int(mn[0][1])) if mn else None,
                "max": (int(mx[0][0]), int(mx[0][1])) if mx else None,
                "name": p[7] if len(p) > 7 else "",
            }
    return out


def f32(x):
    """The server keeps spill rates as float32: -1.1 is -1.10000002384."""
    return struct.unpack("f", struct.pack("f", x))[0]


def trunc(x):
    return int(x)   # toward zero, as int32(...) on the server

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def I(r, k):
    return int(float(r[k]))


def F(r, k):
    return round(float(r[k]), 4)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--cache", default=DEFAULT_CACHE)
    ap.add_argument("--fetch", action="store_true", help="refresh Faction_<locale>.csv (and any missing input)")
    ap.add_argument("--questie", help="a Questie reputation dump (qrep.lua format) to reconcile against")
    ap.add_argument("--overrides", default=DEFAULT_OVERRIDES)
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--check", action="store_true", help="write nothing; exit 1 if the output would change")
    args = ap.parse_args()

    cache = args.cache
    faction_csv = os.path.join(cache, "Faction.csv")
    dump = os.path.join(cache, "tbcdb.sql.gz")
    if args.fetch:
        os.makedirs(cache, exist_ok=True)
        if not os.path.exists(faction_csv):
            fetch(WAGO, faction_csv)
        for loc in LOCALES:
            fetch(WAGO + "&locale=" + loc, os.path.join(cache, "Faction_%s.csv" % loc))
    if not os.path.exists(dump):
        raise SystemExit("no %s: run Commander_Quartermaster/Harness/tbcdb_to_sqlite.py --fetch first" % dump)
    if not os.path.exists(faction_csv):
        raise SystemExit("no %s: run with --fetch" % faction_csv)
    missing = [loc for loc in LOCALES if not os.path.exists(os.path.join(cache, "Faction_%s.csv" % loc))]
    if missing:
        raise SystemExit("no Faction_<locale>.csv for %s in %s: run with --fetch" % (", ".join(missing), cache))

    report = []
    say = report.append

    # --- the Faction DB2 ------------------------------------------------------
    rows = read_csv(faction_csv)
    rep = {i: r for i, r in rows.items() if I(r, "ReputationIndex") >= 0}
    children = collections.defaultdict(list)
    for i, r in rep.items():
        children[I(r, "ParentFactionID")].append(i)

    high_halves = [i for i, r in rep.items() for k in range(4) if I(r, "ReputationRaceMasks%d_1" % k)]
    assert not high_halves, "a race mask uses its high 32 bits: %r" % high_halves

    def base_rows(r):
        """The four (race, class, value, flags) rows in DB2 order. A row of all
        zeros fits everyone, so only TRAILING empty rows can be dropped without
        changing which row is first to fit (FactionEntry::GetIndexFitTo)."""
        out = []
        for k in range(4):
            out.append((I(r, "ReputationRaceMasks%d_0" % k), I(r, "ReputationClassMask_%d" % k),
                        I(r, "ReputationBase_%d" % k), I(r, "ReputationFlags_%d" % k)))
        while out and out[-1] == (0, 0, 0, 0):
            out.pop()
        return out

    def fit(fid, race_id, class_id):
        rm, cm = 1 << (race_id - 1), 1 << (class_id - 1)
        for race, cls, val, flg in base_rows(rep[fid]):
            if (race == 0 or race & rm) and (cls == 0 or cls & cm):
                return val
        return 0

    def side(r):
        """Alliance-only when some Horde-only race row starts at -42000, and the
        mirror; the opposite side's rows are NOT flagged hidden in this build
        (Honor Hold, Thrallmar and Kurenai carry flags 0 there)."""
        hated_h = hated_a = False
        for race, cls, val, flg in base_rows(r):
            if val != BOTTOM or not race:
                continue
            if race & HORDE_RACES and not race & ALLIANCE_RACES:
                hated_h = True
            if race & ALLIANCE_RACES and not race & HORDE_RACES:
                hated_a = True
        if hated_h and not hated_a:
            return "Alliance"
        if hated_a and not hated_h:
            return "Horde"
        return None

    def dbc_spill(src):
        """ReputationMgr::SetReputation's DBC path (ReputationMgr.cpp:293-334):
        a header passes a gain to each child at the CHILD's rate in; a child
        with a rate out passes it to each sibling at out x the sibling's in;
        each edge stops at the target's max rank in."""
        r = rows[src]
        edges = []
        flist = children.get(src)
        out = 1.0
        team = I(r, "ParentFactionID")
        if not flist and team and F(r, "ParentFactionMod_1") != 0:
            out = F(r, "ParentFactionMod_1")
            parent = rows.get(team)
            if parent is not None and I(parent, "ReputationIndex") >= 0 and I(parent, "ReputationFlags_0") & 0x80:
                return [(team, out, 7)]   # TEAM_REPUTATION: never set in this build
            flist = children.get(team)
        for t in flist or []:
            if t == src:
                continue
            rin = F(rows[t], "ParentFactionMod_0")
            cap = I(rows[t], "ParentFactionCap_0")
            if out * rin != 0:
                edges.append((t, round(out * rin, 4), cap))
        return edges

    # --- the world DB -----------------------------------------------------------
    db = read_dump(dump, ["reputation_spillover_template", "reputation_reward_rate", "quest_template",
                          "creature_questrelation"])
    template = {}
    for t in db["reputation_spillover_template"]:
        template[t["faction"]] = sorted((t["faction%d" % k], round(float(t["rate_%d" % k]), 4), t["rank_%d" % k])
                                        for k in range(1, 5) if t["faction%d" % k])
    rate = {t["faction"]: (t["quest_rate"], t["creature_rate"], t["spell_rate"]) for t in db["reputation_reward_rate"]}

    spill, mismatches = {}, []
    for src in sorted(rep):
        edges = sorted(dbc_spill(src))
        if src in template:
            if template[src] != edges:
                mismatches.append((src, edges, template[src]))
            edges = template[src]          # the server's own template wins (ReputationMgr.cpp:277)
        if edges:
            spill[src] = edges

    quests = {}
    dropped_rows = []
    for q in db["quest_template"]:
        e = q["entry"]
        pairs, caps = {}, {}
        for k in range(1, 6):
            f, v, mx = q["RewRepFaction%d" % k], q["RewRepValue%d" % k], q["RewMaxRepValue%d" % k]
            if not f:
                continue
            if f not in rep:
                dropped_rows.append((e, f, v))   # ObjectMgr drops these (ObjectMgr.cpp:5160-5176)
                continue
            if v:
                pairs[f] = v
            if mx is not None and mx < CAP:
                caps[f] = mx
        items = []
        for k in range(1, 5):
            item, count = q["ReqItemId%d" % k], q["ReqItemCount%d" % k]
            if item and count and item != q["SrcItemId"]:
                items.append((item, count))
        quests[e] = {
            "title": q["Title"] or "", "rows": pairs, "caps": caps, "items": items,
            "daily": bool(q["QuestFlags"] & DAILY), "repeat": bool(q["SpecialFlags"] & REPEATABLE),
            "min": (q["RequiredMinRepFaction"], q["RequiredMinRepValue"]) if q["RequiredMinRepFaction"] else None,
            "max": (q["RequiredMaxRepFaction"], q["RequiredMaxRepValue"]) if q["RequiredMaxRepFaction"] else None,
        }

    givers = collections.defaultdict(set)
    for r in db["creature_questrelation"]:
        givers[r["quest"]].add(r["id"])

    questie = read_questie(args.questie) if args.questie else None

    # --- reward clamps (RewMaxRepValue) -----------------------------------------
    reward_cap = {e: dict(q["caps"]) for e, q in quests.items() if q["caps"]}
    cm_cap_rows = sum(len(v) for v in reward_cap.values())
    for e, caps in MANUAL_REWARD_CAP.items():
        reward_cap.setdefault(e, {}).update(caps)

    # --- rows that are spillover written down as a reward -------------------------
    equal_header_rows = []

    def derived_of(pairs, e=None):
        """{target: source} for every row T on a quest that is exactly
        trunc(vS x rate) of another row S along a spill edge S -> T. A designer
        does not type 37 or 12; those numbers fall out of a calculation. A
        header's rate-1 edge is the exception: Alliance 10 beside Gnomeregan
        10 is a value someone may well have typed, so equality there proves
        nothing and the row is left alone (and named in the report)."""
        out = {}
        for s, vs in sorted(pairs.items()):
            if not vs:
                continue
            for t, rt, _ in spill.get(s, []):
                if t != s and t in pairs and t not in out and pairs[t] == trunc(vs * f32(rt)):
                    if abs(rt) == 1:
                        if e is not None:
                            equal_header_rows.append((e, s, t))
                        continue
                    out[t] = s
        return out

    derived, derived_src = {}, {}
    for e, q in sorted(quests.items()):
        d = derived_of(q["rows"], e)
        if d:
            derived[e] = set(d)
            derived_src[e] = dict(d)
    questie_only = {}
    if questie is not None:
        for e, qq in questie.items():
            d = derived_of(qq["rows"])
            extra = {t: s for t, s in d.items() if t not in derived.get(e, set())}
            if extra:
                questie_only[e] = sorted(extra)
                derived_src.setdefault(e, {}).update(extra)
    seed = {e: sorted(v) for e, v in QUESTIE_ONLY_DERIVED.items()}
    use = questie_only if questie is not None else seed
    for e, fs in use.items():
        derived.setdefault(e, set()).update(fs)
    edge_hits = collections.Counter()
    edge_examples = collections.defaultdict(list)
    for e in sorted(derived_src):
        for t, s in derived_src[e].items():
            if t in derived.get(e, ()):
                edge_hits[(s, t)] += 1
                edge_examples[(s, t)].append(e)

    # --- repeatables: what a turn-in costs ----------------------------------------
    repeat_cost = {}
    no_item = []
    for e, q in quests.items():
        if not (q["daily"] or q["repeat"]) or not q["rows"]:
            continue
        if q["items"]:
            repeat_cost[e] = q["items"]
        else:
            no_item.append(e)

    # --- rotating and conditional dailies --------------------------------------------
    rotating = {}
    for e, gs in givers.items():
        kinds = {ROTATING_GIVERS[g] for g in gs if g in ROTATING_GIVERS}
        if kinds:
            assert len(kinds) == 1, (e, kinds)
            rotating[e] = kinds.pop()
    for e in rotating:
        assert quests[e]["daily"] and 933 in quests[e]["rows"], "rotating %d is not a Consortium daily" % e
    for e in CONDITIONAL:
        assert e in quests and quests[e]["daily"], "conditional %d is not a daily" % e

    # --- overrides from the Wowhead audit -------------------------------------------------
    overrides, refused = {}, []
    have_overrides = os.path.exists(args.overrides)
    if have_overrides:
        with open(args.overrides, encoding="utf8") as f:
            raw = json.load(f)
        for qk, body in sorted(raw.items(), key=lambda kv: int(kv[0]) if str(kv[0]).isdigit() else 0):
            if not str(qk).isdigit() or not isinstance(body, dict):
                refused.append((qk, "not {questId: {...}}"))
                continue
            src = body.get("src")
            if not isinstance(src, str) or not src.startswith("https://") or "wowhead.com" not in src:
                refused.append((qk, "no Wowhead src"))
                continue
            vals = {}
            bad = False
            for fk, v in body.items():
                if fk in ("src", "note"):
                    continue
                if not str(fk).isdigit() or int(fk) not in rep or not isinstance(v, int) or isinstance(v, bool):
                    refused.append((qk, "bad row %r: %r" % (fk, v)))
                    bad = True
                    break
                vals[int(fk)] = v
            if bad or not vals:
                if not bad:
                    refused.append((qk, "no faction rows"))
                continue
            overrides[int(qk)] = (vals, src, body.get("note"))

    # --- picker groups ---------------------------------------------------------------
    # A classic faction is listed when some quest in the world DB pays or
    # costs it (the world DB, not the optional dump, so the list never
    # depends on which inputs were at hand)
    referenced = collections.Counter()
    for q in quests.values():
        for f in q["rows"]:
            referenced[f] += 1
    name = {i: r["Name_lang"].strip() for i, r in rep.items()}

    def by_name(ids):
        return sorted(ids, key=lambda i: (name[i][4:] if name[i].startswith("The ") else name[i]).lower())
    headers = {i for i in rep if children.get(i)}
    groups = []
    tbc_ids = set()
    for key, title, header in TBC_GROUPS:
        ids = TBC_OTHER if header is None else [c for c in children[header] if c in rep]
        tbc_ids.update(ids)
        groups.append({"key": key, "title": title, "header": header, "tbc": True, "ids": by_name(ids)})
    for i in tbc_ids:
        assert referenced[i] > 0, "TBC faction %d (%s) has no quest rows" % (i, name[i])
    classic_left = [i for i in rep if i not in tbc_ids and i not in headers and referenced[i] > 0]
    omitted = sorted(i for i in rep if i not in tbc_ids and i not in classic_left)
    for key, title, header, side_ in CLASSIC_GROUPS:
        if key == "STEAMWHEEDLE":
            ids = [i for i in classic_left if I(rep[i], "ParentFactionID") == 169]
        elif side_:
            ids = [i for i in classic_left if side(rep[i]) == side_ and I(rep[i], "ParentFactionID") != 169]
        else:
            ids = [i for i in classic_left if side(rep[i]) is None and I(rep[i], "ParentFactionID") != 169]
        g = {"key": key, "title": title, "header": header, "ids": by_name(ids)}
        if side_:
            g["side"] = side_
        groups.append(g)
    placed = [i for g in groups for i in g["ids"]]
    assert len(placed) == len(set(placed)), "a faction sits in two groups"

    # --- localized names --------------------------------------------------------------
    # Only where a faction may be unmet and still listed (the TBC groups: the
    # picker shows them before you have been to Outland), and only names that
    # differ from enUS; the client's own name wins whenever it answers.
    names = {}
    name_scope = sorted(tbc_ids)
    identical = []
    for loc in LOCALES:
        lrows = read_csv(os.path.join(cache, "Faction_%s.csv" % loc))
        for i in rep:
            assert I(lrows[i], "ReputationIndex") == I(rep[i], "ReputationIndex"), (loc, i)
        t = {i: lrows[i]["Name_lang"].strip() for i in name_scope
             if lrows[i]["Name_lang"].strip() and lrows[i]["Name_lang"].strip() != name[i]}
        if not t:
            identical.append(loc)
        elif SHIP_NAMES:
            names[loc] = t

    # --- write ------------------------------------------------------------------------
    def lua_str(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'

    def num(x):
        return ("%g" % x) if isinstance(x, float) else str(x)

    thresholds = []
    acc = BOTTOM
    for p in POINTS_IN_RANK:
        thresholds.append(acc)
        acc += p
    assert acc - 1 == CAP

    L = []
    w = L.append
    w("-- Commander Quest Log: reputation rules data. GENERATED by Harness/make_reputations.py from this")
    w("-- build's Faction DB2 (wago.tools, %s, all locales) and the CMaNGOS TBC world DB (tbc-db" % BUILD)
    w("-- Full_DB: reputation_spillover_template, reputation_reward_rate, quest_template, creature_questrelation),")
    w("-- with the Wowhead-audited overrides from Harness/reputation_overrides.json. Pure data, no code;")
    w("-- the rules that read it are CommanderQuestLogStanding.lua. Do not edit by hand: edit the generator")
    w("-- and re-run it.")
    w("")
    w("CommanderQuestLogReputationData = {")
    w("  build = %s," % lua_str(BUILD))
    w("  bottom = %d, cap = %d," % (BOTTOM, CAP))
    w("  -- lower bound of rank 0..7 (Hated..Exalted); the client's standingID is rank + 1")
    w("  thresholds = { %s }," % ", ".join(str(x) for x in thresholds))
    w("  rules = { lowLevelQuestPenalty = false, diplomacy = 20599, wickerman = 24705, spillClamp = \"capTop\" },")
    w("  -- base = { raceMask, classMask, value, flags } in DB2 order, the first that fits wins;")
    w("  -- spill = { target, rate, maxRankIn }; rate = reputation_reward_rate (quest, kill, spell)")
    w("  factions = {")
    for i in sorted(rep, key=lambda i: I(rep[i], "ReputationIndex")):
        r = rep[i]
        parts = ["name = %s" % lua_str(name[i]), "idx = %d" % I(r, "ReputationIndex")]
        p = I(r, "ParentFactionID")
        if p:
            parts.append("parent = %d" % p)
        if i in headers:
            parts.append("header = true")
        s = side(r)
        if s:
            parts.append("side = %s" % lua_str(s))
        parts.append("base = { %s }" % ", ".join("{ %d, %d, %d, %d }" % x for x in base_rows(r)))
        if i in spill:
            parts.append("spill = { %s }" % ", ".join("{ %d, %s, %d }" % (t, num(rt), c) for t, rt, c in spill[i]))
        if i in rate:
            parts.append("rate = { quest = %s, kill = %s, spell = %s }" % tuple(num(x) for x in rate[i]))
        w("    [%d] = { %s }," % (i, ", ".join(parts)))
    w("  },")
    w("  -- the reputation picker, in order: TBC first, then the classic groups")
    w("  groups = {")
    for g in groups:
        extra = ""
        if g.get("header"):
            extra += ", header = %d" % g["header"]
        if g.get("tbc"):
            extra += ", tbc = true"
        if g.get("side"):
            extra += ", side = %s" % lua_str(g["side"])
        w("    { key = %s, title = %s%s, ids = { %s } }," % (lua_str(g["key"]), lua_str(g["title"]), extra,
                                                         ", ".join(str(i) for i in g["ids"])))
    w("  },")
    w("  -- localized names of the TBC factions, only where they differ from enUS (for factions not yet met)")
    w("  names = {")
    for loc in sorted(names):
        w("    %s = { %s }," % (loc, ", ".join("[%d] = %s" % (i, lua_str(n)) for i, n in sorted(names[loc].items()))))
    w("  },")
    w("  -- RewMaxRepValue below the ceiling: a turn-in never lifts the faction past this value")
    w("  rewardCap = {")
    for e in sorted(reward_cap):
        w("    [%d] = { %s }," % (e, ", ".join("[%d] = %d" % (f, v) for f, v in sorted(reward_cap[e].items()))))
    w("  },")

    def block(key, items, per_line, entry):
        """A keyed table written per_line entries to a row, in id order."""
        if not items:
            w("  %s = {}," % key)
            return
        w("  %s = {" % key)
        for k in range(0, len(items), per_line):
            w("    " + " ".join(entry(e, v) + "," for e, v in items[k:k + per_line]))
        w("  },")

    w("  -- stored rows that are spillover (trunc(source x rate) of another row on the same quest): drop them,")
    w("  -- the spill rules pay them")
    block("derived", sorted(derived.items()), 8,
          lambda e, fs: "[%d] = { %s }" % (e, ", ".join(str(f) for f in sorted(fs))))
    w("  -- what one turn-in of a repeatable or daily takes: { itemId, count[, itemId, count ...] }")
    block("repeatCost", sorted(repeat_cost.items()), 6,
          lambda e, pcs: "[%d] = { %s }" % (e, ", ".join("%d, %d" % pc for pc in pcs)))
    w("  -- the Wanted dailies: one random NORMAL (Nether-Stalker Mah'duun) and one HEROIC (Wind Trader Zhareem) a day")
    block("rotating", sorted(rotating.items()), 6, lambda e, k: "[%d] = %s" % (e, lua_str(k)))
    w("  conditional = { %s }," % ", ".join("[%d] = %s" % (e, lua_str(k)) for e, k in sorted(CONDITIONAL.items())))
    w("  -- rows the Wowhead audit corrected; each cites its page (raw values, not Human-boosted)")
    w("  overrides = {")
    for e in sorted(overrides):
        vals, src, _ = overrides[e]
        w("    [%d] = { %s, src = %s }," % (e, ", ".join("[%d] = %d" % (f, v) for f, v in sorted(vals.items())),
                                         lua_str(src)))
    w("  },")
    w("  -- what the generator reconciled, for the data smoke")
    w("  reconciliation = { spillTemplateRows = %d, spillMismatches = %d, rewardCapRows = %d, derivedQuests = %d,"
      % (len(template), len(mismatches), sum(len(v) for v in reward_cap.values()), len(derived)))
    w("    droppedRows = %d, repeatCost = %d, rotating = %d, overrides = %d, overridesRefused = %d },"
      % (len(dropped_rows), len(repeat_cost), len(rotating), len(overrides), len(refused)))
    w("}")
    text = "\n".join(L) + "\n"

    if args.check:
        old = open(args.out, encoding="utf8").read() if os.path.exists(args.out) else None
        stale = old != text
    else:
        with open(args.out, "w", encoding="utf8", newline="\n") as f:
            f.write(text)
        stale = False

    # --- the report ---------------------------------------------------------------------
    say("Faction DB2 %s: %d factions with a reputation slot, %d spill sources" % (BUILD, len(rep), len(spill)))
    say("spillover: %d template rows, DB2-vs-template mismatches: %d%s" % (
        len(template), len(mismatches), "" if not mismatches else "  " + repr(mismatches)))
    say("  sources the DB2 adds over the template (headers): %s" % ", ".join(
        "%d %s" % (i, name[i]) for i in sorted(spill) if i not in template))
    say("reward rates: %s" % ", ".join("%d %s quest x%s" % (f, name[f], num(rate[f][0])) for f in sorted(rate)))
    say("base fit (Aldor, Scryers, Sporeggar, Kurenai, Mag'har, Netherwing):")
    for race, label in ((1, "Human"), (11, "Draenei"), (10, "Blood Elf"), (2, "Orc")):
        say("  %-9s %s" % (label, [fit(f, race, 1) for f in (932, 934, 970, 978, 941, 1015)]))
    say("rewardCap: %d quests, %d rows from RewMaxRepValue, %d manual (%s)" % (
        len(reward_cap), cm_cap_rows, sum(len(v) for v in MANUAL_REWARD_CAP.values()),
        ", ".join(str(e) for e in sorted(MANUAL_REWARD_CAP))))
    for e in sorted(reward_cap):
        say("  %5d %-34s %s" % (e, (quests.get(e) or {}).get("title", "(not in CMaNGOS)")[:34],
                                ", ".join("%s<=%d" % (name[f], v) for f, v in sorted(reward_cap[e].items()))))
    say("quest rows naming a faction with no reputation slot (dropped, as the server does): %d %s" % (
        len(dropped_rows), dropped_rows[:12]))
    say("derived (spillover-shaped stored rows): %d quests" % len(derived))
    for (s, t), n in sorted(edge_hits.items(), key=lambda kv: (-kv[1], kv[0])):
        say("  %s -> %s: %d  %s" % (name[s], name[t], n, edge_examples[(s, t)][:10] if n < 20 else ""))
    say("  equal rows on a header's rate-1 edge, NOT marked (CMaNGOS): %s" % ", ".join(
        "%d %s=%s" % (e, name[s], name[t]) for e, s, t in equal_header_rows))
    if questie is None:
        say("  Questie-only derived rows from the snapshot (no --questie dump given): %s" % seed)
    else:
        verdict = "agree" if questie_only == seed else "DIFFER: dump %r vs snapshot %r" % (questie_only, seed)
        say("  Questie-only derived rows from the dump: %s (snapshot and dump %s)" % (questie_only, verdict))
    say("repeatCost: %d repeatables/dailies with an item cost; %d with none (kill or deliver): %s" % (
        len(repeat_cost), len(no_item), sorted(no_item)[:30]))
    multi = sorted(e for e, v in repeat_cost.items() if len(v) > 1)
    say("  taking more than one item: %s" % multi)
    say("rotating: %d NORMAL, %d HEROIC" % (sum(1 for v in rotating.values() if v == "NORMAL"),
                                           sum(1 for v in rotating.values() if v == "HEROIC")))
    say("conditional: %s" % ", ".join("%d %s" % (e, quests[e]["title"]) for e in sorted(CONDITIONAL)))
    if not have_overrides:
        say("overrides: %s absent (the Wowhead audit has not written it); none emitted" % os.path.basename(args.overrides))
    else:
        say("overrides: %d emitted, %d refused (value: CMaNGOS / Questie in brackets)" % (len(overrides), len(refused)))
        for e in sorted(overrides):
            vals, src, note = overrides[e]
            cells = []
            for f, v in sorted(vals.items()):
                cmv = quests.get(e, {}).get("rows", {}).get(f, "-")
                qsv = questie[e]["rows"].get(f, "-") if questie and e in questie else ("-" if questie else "?")
                cells.append("%s %d [%s / %s]" % (name[f], v, cmv, qsv))
            say("  %5d %s" % (e, "; ".join(cells)))
            if note:
                say("        %s" % (note if len(note) <= 110 else note[:107] + "..."))
            clash = sorted(set(vals) & derived.get(e, set()))
            if clash:
                say("        NOTE: overrides a row the generator also lists as derived: %s" % [name[f] for f in clash])
        for qk, why in refused:
            say("  REFUSED %s: %s" % (qk, why))
    say("groups: %s" % "; ".join("%s %d" % (g["key"], len(g["ids"])) for g in groups))
    say("  not in the picker (headers, hidden, no quest rows): %s" % ", ".join(
        "%d %s" % (i, name[i]) for i in omitted))
    shipped = ", ".join("%s %d" % (k, len(v)) for k, v in sorted(names.items()))
    say("names: %s; identical to enUS: %s" % (shipped if SHIP_NAMES else "not shipped (SHIP_NAMES = False)",
                                              ", ".join(identical) or "none"))
    if questie is not None:
        cm = {e: q["rows"] for e, q in quests.items() if q["rows"]}
        qs = {e: qq["rows"] for e, qq in questie.items() if qq["rows"]}
        both = set(cm) & set(qs)
        same = [e for e in both if cm[e] == qs[e]]
        say("Questie vs CMaNGOS: %d / %d quests with rows, %d in both, %d identical" % (
            len(qs), len(cm), len(both), len(same)))
        tbc = tbc_ids
        diff = sorted(e for e in both if cm[e] != qs[e] and (set(cm[e]) | set(qs[e])) & tbc)
        say("  differing on a TBC faction: %d" % len(diff))
        for e in diff[:40]:
            a, b = cm[e], qs[e]
            fs = sorted(set(a) | set(b))
            d = ["%s %s/%s" % (name.get(f, f), a.get(f, "-"), b.get(f, "-")) for f in fs if a.get(f) != b.get(f)]
            say("    %5d %-30s %s" % (e, (questie[e]["name"] or "")[:30], "; ".join(d)))
        only_c = sorted(e for e in set(cm) - set(qs) if set(cm[e]) & tbc)
        only_q = sorted(e for e in set(qs) - set(cm) if set(qs[e]) & tbc)
        say("  only CMaNGOS (TBC faction): %s" % only_c)
        say("  only Questie (TBC faction): %s" % only_q)
        gates = []
        for e in sorted(both | (set(questie) & set(quests))):
            q, qq = quests.get(e), questie.get(e)
            if not q or not qq:
                continue
            for kind in ("min", "max"):
                a, b = q[kind], qq[kind]
                if a != b and ((a and a[0] in tbc) or (b and b[0] in tbc)):
                    gates.append((e, kind, a, b))
        say("  rep gates differing on a TBC faction (CMaNGOS vs Questie): %d, e.g. %s" % (len(gates), gates[:8]))
    say("output: %s, %d bytes%s" % (os.path.relpath(args.out, ADDONS), len(text.encode("utf8")),
                                     " (STALE: re-run without --check)" if stale else ""))
    print("\n".join(report))
    if args.check and stale:
        sys.exit(1)


if __name__ == "__main__":
    main()
