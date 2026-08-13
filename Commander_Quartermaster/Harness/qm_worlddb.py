#!/usr/bin/env python3
"""Where does this item come from? — every answer TBC has, from the world DB.

Backs build_enhancements.py. Reads the SQLite staged by tbcdb_to_sqlite.py
(server-side sourcing) alongside the client's own DB2 CSVs (identity, extended
costs, zone and map names), and resolves one item id into the complete list of
ways a player can obtain it:

    vendor (incl. honor/arena/token/currency costs and reputation gates)
    creature drop (direct and via reference loot, normal and heroic)
    object loot (chests, herb/mining nodes, mailboxes)
    container loot (opened from another item)
    quest reward (given and choice-of)
    disenchant, prospect, fish, pickpocket, skin, mail
    craft (profession, skill rank, reagents — from the client, not the world DB)

Nothing here is curated. Everything is a query, so a corrected world DB or a
new client build changes the answer without anyone editing a Lua list.
"""
import csv
import os
import sqlite3
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.environ.get("QM_CACHE") or os.path.join(HERE, ".cache")


def load_csv(name):
    path = os.path.join(CACHE, name + ".csv")
    if not os.path.exists(path):
        raise SystemExit("missing DB2 cache %s — see Harness/README.md" % path)
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _int(v, default=0):
    try:
        return int(v)
    except (TypeError, ValueError):
        return default


# --- reputation standings, as the game words them -------------------------
STANDING = {0: "Hated", 1: "Hostile", 2: "Unfriendly", 3: "Neutral",
            4: "Friendly", 5: "Honored", 6: "Revered", 7: "Exalted"}

# creature_template.Rank
RANK = {0: None, 1: "Elite", 2: "Rare Elite", 3: "Boss", 4: "Rare"}

# Alliance-only / Horde-only quest gating, from quest_template.RequiredRaces.
ALLIANCE_RACES = 1 | 4 | 8 | 64 | 1024          # human, dwarf, nightelf, gnome, draenei
HORDE_RACES = 2 | 16 | 32 | 128 | 512           # orc, undead, tauren, troll, bloodelf


class WorldDB:
    def __init__(self, db_path=None):
        self.con = sqlite3.connect(db_path or os.path.join(CACHE, "tbcdb.sqlite"))
        self.con.row_factory = sqlite3.Row
        self._load_client_tables()
        self._index_world()

    # -- client-side lookups (names, zones, currencies) ---------------------
    def _load_client_tables(self):
        self.area = {_int(r["ID"]): r["AreaName_lang"] for r in load_csv("AreaTable")}
        self.map = {_int(r["ID"]): r["MapName_lang"] for r in load_csv("Map")}
        self.faction = {_int(r["ID"]): r["Name_lang"] for r in load_csv("Faction")}
        self.extcost = {_int(r["ID"]): r for r in load_csv("ItemExtendedCost")}

        # Zone from a spawn point. The world DB's creature_zone table ships
        # EMPTY (CMaNGOS fills it from the client's maps at runtime), so the
        # zone of a vendor or a boss has to be derived the same way the game
        # derives it: the client's UI-map assignments carry a world-space
        # bounding box per zone per map. Smallest containing box wins, which
        # picks Lower City over Shattrath City and Shattrath City over Outland.
        uimap = {_int(r["ID"]): r["Name_lang"] for r in load_csv("UiMap")}
        self.zone_boxes = defaultdict(list)
        for r in load_csv("UiMapAssignment"):
            name = uimap.get(_int(r["UiMapID"]))
            if not name:
                continue
            x0, y0 = float(r["Region_0"]), float(r["Region_1"])
            x1, y1 = float(r["Region_3"]), float(r["Region_4"])
            if x0 == x1 or y0 == y1:
                continue
            lo_x, hi_x = min(x0, x1), max(x0, x1)
            lo_y, hi_y = min(y0, y1), max(y0, y1)
            self.zone_boxes[_int(r["MapID"])].append(
                ((hi_x - lo_x) * (hi_y - lo_y), lo_x, hi_x, lo_y, hi_y, name))
        for boxes in self.zone_boxes.values():
            boxes.sort()   # smallest area first

    def zone_at(self, map_id, x, y):
        for _area, lo_x, hi_x, lo_y, hi_y, name in self.zone_boxes.get(map_id, ()):
            if lo_x <= x <= hi_x and lo_y <= y <= hi_y:
                return name
        return self.map.get(map_id)

    def _index_world(self):
        c = self.con
        # entry -> every zone it spawns in, commonest first. A patrolling mob or
        # a vendor with a second shop is two zones and both are true.
        self.creature_zone = self._spawn_zones("creature")
        self.go_zone = self._spawn_zones("gameobject")

        # heroic twins: creature_template.HeroicEntry points at the heroic copy.
        # The heroic copy is never spawned in the world — the server swaps it in
        # on a heroic instance — so it has no zone of its own and borrows the
        # normal twin's.
        self.is_heroic = {}
        for r in c.execute("SELECT Entry, HeroicEntry FROM creature_template "
                           "WHERE HeroicEntry > 0"):
            self.is_heroic[_int(r["HeroicEntry"])] = _int(r["Entry"])
        for heroic, normal in self.is_heroic.items():
            if heroic not in self.creature_zone and normal in self.creature_zone:
                self.creature_zone[heroic] = self.creature_zone[normal]

        # vendor templates are shared shelves; fold them back onto the npcs
        self.vendor_template_users = defaultdict(list)
        for r in c.execute("SELECT Entry, VendorTemplateId FROM creature_template "
                           "WHERE VendorTemplateId > 0"):
            self.vendor_template_users[_int(r["VendorTemplateId"])].append(_int(r["Entry"]))
        self.trainer_template_users = defaultdict(list)
        for r in c.execute("SELECT Entry, TrainerTemplateId FROM creature_template "
                           "WHERE TrainerTemplateId > 0"):
            self.trainer_template_users[_int(r["TrainerTemplateId"])].append(_int(r["Entry"]))

        # loot ids are indirections: creature_template.LootId -> loot template entry
        self.loot_owners = defaultdict(list)
        for r in c.execute("SELECT Entry, LootId FROM creature_template WHERE LootId > 0"):
            self.loot_owners[_int(r["LootId"])].append(_int(r["Entry"]))
        self.pickpocket_owners = defaultdict(list)
        for r in c.execute("SELECT Entry, PickpocketLootId FROM creature_template "
                           "WHERE PickpocketLootId > 0"):
            self.pickpocket_owners[_int(r["PickpocketLootId"])].append(_int(r["Entry"]))
        self.skin_owners = defaultdict(list)
        for r in c.execute("SELECT Entry, SkinningLootId FROM creature_template "
                           "WHERE SkinningLootId > 0"):
            self.skin_owners[_int(r["SkinningLootId"])].append(_int(r["Entry"]))
        # gameobject chests keep their loot id in data1
        self.go_loot_owners = defaultdict(list)
        for r in c.execute("SELECT entry, data1 FROM gameobject_template WHERE type IN (3, 25)"):
            self.go_loot_owners[_int(r["data1"])].append(_int(r["entry"]))

        # GM shelves. CMaNGOS carries stock rooms ("Gems Vendor",
        # "Enchantments Vendor") that sell a hundred items each, spawned
        # nowhere; without this every gem in TBC would claim a vendor.
        #
        # "Unspawned" alone is NOT the test, and that distinction is the whole
        # comment: the Consortium's Aether-tech gem vendors are summoned rather
        # than spawned, and so is Nightbane. A shelf gives itself away by
        # stocking more than any real merchant does while having no spawn and
        # no name worth having.
        self.spawned = set(self.creature_zone) | set(self.is_heroic)
        self.gm_shelf = set()
        for r in c.execute("""
                SELECT v.entry AS entry, COUNT(*) AS n FROM npc_vendor v
                GROUP BY v.entry HAVING n >= 50"""):
            npc = _int(r["entry"])
            if npc not in self.spawned:
                self.gm_shelf.add(npc)
        for r in c.execute("SELECT Entry, Name FROM creature_template "
                           "WHERE Name LIKE 'TEST%' OR Name LIKE 'zzOLD%'"):
            self.gm_shelf.add(_int(r["Entry"]))

        # reference loot: which loot templates pull in which reference table
        self.ref_users = defaultdict(list)   # ref entry -> [(table, loot entry, chance)]
        for table in ("creature_loot_template", "gameobject_loot_template",
                      "item_loot_template", "reference_loot_template",
                      "fishing_loot_template", "mail_loot_template",
                      "skinning_loot_template", "pickpocketing_loot_template",
                      "disenchant_loot_template", "prospecting_loot_template"):
            for r in c.execute("SELECT entry, mincountOrRef, ChanceOrQuestChance "
                               "FROM %s WHERE mincountOrRef < 0" % table):
                self.ref_users[-_int(r["mincountOrRef"])].append(
                    (table, _int(r["entry"]), float(r["ChanceOrQuestChance"] or 0)))

    def _spawn_zones(self, table):
        counts = defaultdict(lambda: defaultdict(int))
        for r in self.con.execute("SELECT id, map, position_x, position_y FROM %s" % table):
            zone = self.zone_at(_int(r["map"]), float(r["position_x"] or 0),
                                float(r["position_y"] or 0))
            if zone:
                counts[_int(r["id"])][zone] += 1
        out = {}
        for eid, seen in counts.items():
            out[eid] = [z for z, _n in sorted(seen.items(), key=lambda kv: -kv[1])]
        return out

    # -- naming -------------------------------------------------------------
    def zones_of(self, table_index, entry):
        return table_index.get(entry) or []

    def zone_of(self, table_index, entry):
        z = table_index.get(entry)
        return z[0] if z else None

    def creature_name(self, entry):
        r = self.con.execute("SELECT Name, SubName, MinLevel, MaxLevel, Rank, Faction "
                             "FROM creature_template WHERE Entry = ?", (entry,)).fetchone()
        return r

    def item_name(self, item_id):
        r = self.con.execute("SELECT name FROM item_template WHERE entry = ?",
                             (item_id,)).fetchone()
        return r["name"] if r else None

    def item_row(self, item_id):
        return self.con.execute("SELECT * FROM item_template WHERE entry = ?",
                                (item_id,)).fetchone()

    # -- cost decoding ------------------------------------------------------
    def extended_cost(self, ext_id):
        """Honor / arena / token cost of a vendor item, as a plain dict."""
        row = self.extcost.get(ext_id)
        if not row:
            return None
        out = {}
        # TBC honor and arena points ride in the currency columns of this build's
        # table (CurrencyID 103/104 are not used); the honor/arena columns were
        # folded away in a later expansion's schema, so read both shapes.
        tokens = []
        for i in range(5):
            iid, cnt = _int(row["ItemID_%d" % i]), _int(row["ItemCount_%d" % i])
            if iid and cnt:
                tokens.append({"item": iid, "count": cnt, "name": self.item_name(iid)})
        if tokens:
            out["tokens"] = tokens
        rating = _int(row["RequiredArenaRating"])
        if rating:
            out["arenaRating"] = rating
        fid, rep = _int(row["MinFactionID"]), _int(row["MinReputation"])
        if fid:
            out["faction"] = {"id": fid, "name": self.faction.get(fid),
                              "standing": STANDING.get(rep, str(rep))}
        return out or None

    # -- the sources --------------------------------------------------------
    def vendors(self, item_id):
        out = []
        seen = set()
        rows = list(self.con.execute(
            "SELECT entry, maxcount, incrtime, ExtendedCost, condition_id "
            "FROM npc_vendor WHERE item = ?", (item_id,)))
        for r in self.con.execute(
                "SELECT entry, maxcount, incrtime, ExtendedCost, condition_id "
                "FROM npc_vendor_template WHERE item = ?", (item_id,)):
            for npc in self.vendor_template_users.get(_int(r["entry"]), []):
                rows.append({"entry": npc, "maxcount": r["maxcount"],
                             "incrtime": r["incrtime"], "ExtendedCost": r["ExtendedCost"],
                             "condition_id": r["condition_id"]})
        item = self.item_row(item_id)
        for r in rows:
            npc = _int(r["entry"])
            if npc in seen or npc in self.gm_shelf:
                continue
            seen.add(npc)
            ct = self.creature_name(npc)
            if not ct:
                continue
            rec = {"k": "VENDOR", "npc": npc, "name": ct["Name"],
                   "sub": ct["SubName"] or None,
                   "zone": self.zone_of(self.creature_zone, npc),
                   "price": _int(item["BuyPrice"]) if item else None}
            # The reputation gate lives on the ITEM, not the shelf: this is how
            # the game stops a Neutral player buying the Exalted head glyph.
            fid = _int(item["RequiredReputationFaction"]) if item else 0
            if fid:
                rec["faction"] = {"id": fid, "name": self.faction.get(fid),
                                  "standing": STANDING.get(
                                      _int(item["RequiredReputationRank"]), None)}
            stock = _int(r["maxcount"])
            if stock:
                rec["stock"] = stock
                rec["restock"] = _int(r["incrtime"]) or None
            cost = self.extended_cost(_int(r["ExtendedCost"]))
            if cost:
                rec["cost"] = cost
            out.append(rec)
        return out

    def _loot_rows(self, table, item_id):
        return list(self.con.execute(
            "SELECT entry, ChanceOrQuestChance, groupid, mincountOrRef, maxcount "
            "FROM %s WHERE item = ?" % table, (item_id,)))

    def _expand_refs(self, ref_entry, chance, depth=0):
        """A reference loot entry is a shelf other loot tables point at. Walk
        back up to every table that pulls it in, multiplying the odds."""
        if depth > 3:
            return []
        out = []
        for table, entry, ref_chance in self.ref_users.get(ref_entry, []):
            eff = chance * (abs(ref_chance) / 100.0 if ref_chance else 1.0)
            if table == "reference_loot_template":
                out.extend(self._expand_refs(entry, eff, depth + 1))
            else:
                out.append((table, entry, eff))
        return out

    def drops(self, item_id):
        """Creature, object, container and specialist loot, references resolved."""
        hits = []   # (table, loot entry, chance)
        for table in ("creature_loot_template", "gameobject_loot_template",
                      "item_loot_template", "fishing_loot_template",
                      "mail_loot_template", "skinning_loot_template",
                      "pickpocketing_loot_template", "disenchant_loot_template",
                      "prospecting_loot_template"):
            for r in self._loot_rows(table, item_id):
                hits.append((table, _int(r["entry"]), abs(float(r["ChanceOrQuestChance"] or 0))))
        for r in self._loot_rows("reference_loot_template", item_id):
            hits.extend(self._expand_refs(_int(r["entry"]),
                                          abs(float(r["ChanceOrQuestChance"] or 0)) / 100.0))

        out, seen = [], set()
        for table, entry, chance in hits:
            for rec in self._loot_record(table, entry, chance):
                key = (rec["k"], rec.get("npc") or rec.get("go") or rec.get("item"))
                if key in seen:
                    continue
                seen.add(key)
                out.append(rec)
        return out

    def _loot_record(self, table, entry, chance):
        chance = round(chance, 4) or None
        if table == "creature_loot_template":
            recs = []
            for npc in self.loot_owners.get(entry, []) or ([entry] if self.creature_name(entry) else []):
                ct = self.creature_name(npc)
                if not ct or npc in self.gm_shelf:
                    continue
                recs.append({"k": "DROP", "npc": npc, "name": ct["Name"],
                             "zone": self.zone_of(self.creature_zone, npc),
                             "lvl": _int(ct["MinLevel"]) or None,
                             "rank": RANK.get(_int(ct["Rank"])),
                             "heroic": npc in self.is_heroic or None,
                             "chance": chance})
            return recs
        if table == "gameobject_loot_template":
            recs = []
            for go in self.go_loot_owners.get(entry, []):
                r = self.con.execute("SELECT name FROM gameobject_template WHERE entry = ?",
                                     (go,)).fetchone()
                if not r:
                    continue
                recs.append({"k": "OBJECT", "go": go, "name": r["name"],
                             "zone": self.zone_of(self.go_zone, go), "chance": chance})
            return recs
        if table == "item_loot_template":
            name = self.item_name(entry)
            return [{"k": "CONTAINER", "item": entry, "name": name, "chance": chance}] if name else []
        if table == "disenchant_loot_template":
            return [{"k": "DISENCHANT", "loot": entry, "chance": chance}]
        if table == "prospecting_loot_template":
            name = self.item_name(entry)
            return [{"k": "PROSPECT", "item": entry, "name": name, "chance": chance}] if name else []
        if table == "fishing_loot_template":
            return [{"k": "FISH", "zone": self.area.get(entry) or self.map.get(entry),
                     "chance": chance}]
        if table == "mail_loot_template":
            return [{"k": "MAIL", "loot": entry, "chance": chance}]
        if table == "skinning_loot_template":
            recs = []
            for npc in self.skin_owners.get(entry, []):
                ct = self.creature_name(npc)
                if ct:
                    recs.append({"k": "SKIN", "npc": npc, "name": ct["Name"],
                                 "zone": self.zone_of(self.creature_zone, npc), "chance": chance})
            return recs
        if table == "pickpocketing_loot_template":
            recs = []
            for npc in self.pickpocket_owners.get(entry, []):
                ct = self.creature_name(npc)
                if ct:
                    recs.append({"k": "PICKPOCKET", "npc": npc, "name": ct["Name"],
                                 "zone": self.zone_of(self.creature_zone, npc), "chance": chance})
            return recs
        return []

    def quests(self, item_id):
        out = []
        cols = (["RewItemId%d" % i for i in range(1, 5)] +
                ["RewChoiceItemId%d" % i for i in range(1, 7)])
        where = " OR ".join("%s = ?" % c for c in cols)
        for r in self.con.execute("SELECT * FROM quest_template WHERE " + where,
                                  tuple([item_id] * len(cols))):
            races = _int(r["RequiredRaces"])
            side = None
            if races:
                a, h = races & ALLIANCE_RACES, races & HORDE_RACES
                side = "A" if a and not h else ("H" if h and not a else None)
            choice = any(_int(r["RewChoiceItemId%d" % i]) == item_id for i in range(1, 7))
            rec = {"k": "QUEST", "id": _int(r["entry"]), "name": r["Title"],
                   "lvl": _int(r["QuestLevel"]) or None, "side": side,
                   "choice": choice or None,
                   "zone": self.area.get(_int(r["ZoneOrSort"]))}
            rep = _int(r["RequiredMinRepFaction"])
            if rep:
                rec["faction"] = {"id": rep, "name": self.faction.get(rep),
                                  "value": _int(r["RequiredMinRepValue"])}
            giver = self.con.execute(
                "SELECT id FROM creature_questrelation WHERE quest = ? LIMIT 1",
                (rec["id"],)).fetchone()
            if giver:
                ct = self.creature_name(_int(giver["id"]))
                if ct:
                    rec["giver"] = ct["Name"]
                    rec["zone"] = rec["zone"] or self.zone_of(self.creature_zone, _int(giver["id"]))
            out.append(rec)
        return out

    def trainers(self, spell_id):
        """Who teaches this spell, and what it costs in gold and skill."""
        rows = list(self.con.execute(
            "SELECT entry, spellcost, reqskill, reqskillvalue, reqlevel "
            "FROM npc_trainer WHERE spell = ?", (spell_id,)))
        for r in self.con.execute(
                "SELECT entry, spellcost, reqskill, reqskillvalue, reqlevel "
                "FROM npc_trainer_template WHERE spell = ?", (spell_id,)):
            for npc in self.trainer_template_users.get(_int(r["entry"]), []):
                rows.append({"entry": npc, "spellcost": r["spellcost"],
                             "reqskill": r["reqskill"], "reqskillvalue": r["reqskillvalue"],
                             "reqlevel": r["reqlevel"]})
        out, seen = [], set()
        for r in rows:
            npc = _int(r["entry"])
            if npc in seen or npc in self.gm_shelf:
                continue
            seen.add(npc)
            ct = self.creature_name(npc)
            if not ct:
                continue
            out.append({"k": "TRAINER", "npc": npc, "name": ct["Name"],
                        "sub": ct["SubName"] or None,
                        "zone": self.zone_of(self.creature_zone, npc),
                        "cost": _int(r["spellcost"]) or None,
                        "reqSkill": _int(r["reqskillvalue"]) or None})
        return out

    def reputation(self, item_id):
        """The item's own reputation gate, as a source of last resort.

        The world DB's shelves are not complete — the Consortium's
        quartermasters carry no inventory at all in this revision — but the
        ITEM still knows it requires The Consortium at Exalted, because that
        gate is enforced client-side. When nothing else sources an item, that
        gate is the true and useful answer: go and earn the standing, and your
        quartermaster will have it.
        """
        row = self.item_row(item_id)
        if row is None:
            return None
        fid = _int(row["RequiredReputationFaction"])
        if not fid:
            return None
        return {"k": "REP", "faction": {
            "id": fid, "name": self.faction.get(fid),
            "standing": STANDING.get(_int(row["RequiredReputationRank"]))}}

    def item_sources(self, item_id):
        """Every way to obtain the item itself (not counting crafting it)."""
        found = self.vendors(item_id) + self.drops(item_id) + self.quests(item_id)
        if not found:
            rep = self.reputation(item_id)
            if rep:
                found.append(rep)
        return found
