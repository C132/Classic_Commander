#!/usr/bin/env python3
"""Generate CommanderFormularyData_<Profession>.lua for every profession the
Formulary carries, from the same two sources (see ../DECISIONS.md D2):
  * the client's own DB2 tables for this build, as CSV from wago.tools —
    SkillLineAbility (which spells are the profession's, and their colour
    thresholds), SpellName, SpellReagents, SpellEffect (what a recipe makes:
    an item or an enchantment), SpellEquippedItems (what an enchant can be
    cast on), ItemEffect (which formula or manual teaches which recipe),
    ItemSparse (formula names, required skill, bonding, reputation gate),
    FactionTemplate (which side an NPC trades with), UiMap / UiMapAssignment
    (world -> zone map coordinates), AreaTable (quest zones)
  * the CMaNGOS TBC world DB — trainers and what they teach at what skill
    and price, vendors, creature / object / container loot with chances,
    quest rewards, spawn points for coordinates

Run from anywhere:
    python3 make_formulary.py <scratch-dir-with-csvs-and-tbcdb.pkl> [ENCHANTING|FIRSTAID]

Writes ../CommanderFormularyData_<Name>.lua per profession and prints a
report of what it could not source, which is the list to look at by hand.

Everything a profession decides is in PROFESSIONS below: the skill line,
its rank ladder (and how each rank is actually obtained -- a trainer, a
book from a vendor, or a quest), what a recipe is grouped under, and the
handful of rows the world DB has wrong or does not carry.
"""
import sys, os, csv, collections, pickle, re

SCRATCH = sys.argv[1] if len(sys.argv) > 1 else "."
ONLY = sys.argv[2].upper() if len(sys.argv) > 2 else None
HERE = os.path.dirname(os.path.abspath(__file__))

# Weapon enchants name their targets by weapon SUBCLASS mask (class 2), shields
# by armour subclass 6 (class 4); armour enchants by inventory type mask.
ONE_HAND = {0, 4, 7, 13, 15}          # axe, mace, sword, fist, dagger
TWO_HAND = {1, 5, 6, 8, 10}           # 2h axe, 2h mace, polearm, 2h sword, staff
RANGED = {2, 3, 18, 19}               # bow, gun, crossbow, wand

# Creatures on a zone's rim that the box rule gives to the neighbour: the
# uiMapID they belong to. Both checked against the published location.
PLACE_IN = {
    1081: 1435,     # Mire Lord — Misty Valley, west edge of the Swamp of Sorrows (not Deadwind Pass)
    11557: 1448,    # Meilosh — Timbermaw Hold, north edge of Felwood (not Darkshore)
}

def enchanting_category(rec):
    if rec["enchant"]:
        cls, sub = rec.get("equipClass"), rec.get("equipSubclass") or 0
        if cls == 2:
            bits = {i for i in range(32) if (sub >> i) & 1}
            if bits & ONE_HAND:
                return "WEAPON"
            if bits & TWO_HAND:
                return "TWOHAND"
            if bits & RANGED:
                return "RANGED"
            return "WEAPON"
        if cls == 4 and (sub >> 6) & 1 and not rec["targets"]:
            return "SHIELD"
        t = set(rec["targets"])
        if "wrist" in t: return "WRIST"
        if "chest" in t: return "CHEST"
        if "cloak" in t: return "CLOAK"
        if "feet" in t: return "FEET"
        if "hands" in t: return "HANDS"
        if "shield" in t: return "SHIELD"
        if "finger" in t: return "FINGER"
        return "OTHER"
    name = rec["name"]
    if "Rod" in name: return "RODS"
    if "Wand" in name: return "WANDS"
    if "Oil" in name: return "OILS"
    return "MISC"

def firstaid_category(rec):
    name = rec["name"]
    if "Anti-Venom" in name:
        return "ANTIVENOM"
    if "Netherweave" in name:
        return "OUTLAND"
    return "BANDAGES"

PROFESSIONS = {
    "ENCHANTING": {
        "key": "ENCHANTING", "name": "Enchanting", "skill": 333, "abilitySpell": 7411,
        "icon": "Interface\\Icons\\Trade_Engraving",
        # Enchanting uses the CRAFT frame on this client (it moved to the
        # trade skill frame in Wrath)
        "frame": "CRAFT",
        "out": "CommanderFormularyData_Enchanting.lua",
        # The rank spells themselves: not recipes, and how a trainer is told
        # apart from a vendor who happens to sell a formula
        "rankSpells": {7411, 7412, 7413, 13920, 28029},
        "ranks": [
            {"name": "Apprentice", "spell": 7411, "at": 0, "cap": 75},
            {"name": "Journeyman", "spell": 7412, "at": 50, "cap": 150},
            {"name": "Expert", "spell": 7413, "at": 125, "cap": 225},
            {"name": "Artisan", "spell": 13920, "at": 200, "cap": 300},
            {"name": "Master", "spell": 28029, "at": 275, "cap": 375, "outland": True},
        ],
        # The two recipes every enchanter is handed with Apprentice
        # Enchanting itself: no trainer row, no formula, known from the
        # first second
        "autoLearned": {7418, 7421},
        # Recipes the client carries that were never put in the game
        "neverAdded": {27958, 28021},
        # Sources the world DB does not carry (TBC Classic additions, or a
        # mechanic rather than a loot row). Vendor prices in copper.
        "manualVendors": {
            186683: [(19932, 170000)],          # Formula: Enchant Ring - Stats — Andormu, Caverns of Time (Keepers of Time)
            22535: [(20242, 100000)],           # Formula: Enchant Ring - Striking — Karaaz, the Stormspire (Consortium Revered)
        },
        # Vendor rows the world DB has wrong: Ring - Striking sits on Ythyar
        # (a Violet Eye vendor in Karazhan) while the item is gated on
        # Consortium standing
        "manualRemoveVendors": {22535: {17518}},
        "manualNotes": {
            35498: "Dropped by the prisoners released from Ethereum Prisons in Netherstorm (Ethereum Prison Key).",
        },
        "category": enchanting_category,
        "categoryOrder": ["WEAPON", "TWOHAND", "RANGED", "WRIST", "CHEST", "CLOAK", "FEET", "HANDS", "SHIELD", "FINGER", "OTHER",
                          "RODS", "WANDS", "OILS", "MISC"],
        "categoryLabel": {"WEAPON": "Weapon", "TWOHAND": "Two-Hand Weapon", "RANGED": "Ranged", "WRIST": "Bracer", "CHEST": "Chest",
                          "CLOAK": "Cloak", "FEET": "Boots", "HANDS": "Gloves", "SHIELD": "Shield", "FINGER": "Ring",
                          "OTHER": "Other Enchants", "RODS": "Rods", "WANDS": "Wands", "OILS": "Oils", "MISC": "Shards & Spheres"},
        # The formula word, for the report
        "formulaWord": "formula",
        "disenchant": True,
        "rmFile": "Enchanting.lua",
    },
    "FIRSTAID": {
        "key": "FIRSTAID", "name": "First Aid", "skill": 129, "abilitySpell": 3273,
        "icon": "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
        # First Aid is a trade skill: the TRADE SKILL frame and its API
        "frame": "TRADESKILL",
        "out": "CommanderFormularyData_FirstAid.lua",
        "rankSpells": {3273, 3274, 7924, 10846, 27028},
        # How each rank is obtained is the thing First Aid does differently
        # from every primary profession, and the world DB agrees with the
        # published guides: Apprentice and Journeyman from any trainer;
        # Expert from a BOOK sold by two vendors (Deneb Walker in Stromgarde,
        # Balai Lok'Wein in Brackenwall Village); Artisan from the Triage
        # QUEST (Doctor Gustaf VanHowzen in Theramore for the Alliance,
        # Doctor Gregory Victor in Hammerfall for the Horde -- the book
        # "Artisan First Aid - Heal Thyself" exists in the item table and is
        # sold by nobody); Master from a book sold by Burko (Temple of
        # Telhamat) and Aresella (Falcon Watch), which needs 300, not 275.
        "ranks": [
            {"name": "Apprentice", "spell": 3273, "at": 0, "cap": 75},
            {"name": "Journeyman", "spell": 3274, "at": 50, "cap": 150},
            {"name": "Expert", "spell": 7924, "at": 125, "cap": 225, "book": 16084},
            {"name": "Artisan", "spell": 10846, "at": 225, "cap": 300,
             "quests": [(6624, "Alliance", 12939), (6622, "Horde", 12920)]},
            {"name": "Master", "spell": 27028, "at": 300, "cap": 375, "outland": True, "book": 22012},
        ],
        # Linen Bandage comes with Apprentice First Aid itself
        "autoLearned": {3275},
        # Crystal Infused Bandage: its manual is the reward of an unused
        # quest and its reagent is a deprecated placeholder item
        "neverAdded": {30021},
        "manualVendors": {},
        "manualRemoveVendors": {},
        "manualNotes": {},
        "category": firstaid_category,
        "categoryOrder": ["BANDAGES", "OUTLAND", "ANTIVENOM"],
        "categoryLabel": {"BANDAGES": "Bandages", "OUTLAND": "Outland Bandages", "ANTIVENOM": "Anti-Venom"},
        "formulaWord": "manual",
        "disenchant": False,
        "rmFile": "FirstAid.lua",
    },
}

def C(name):
    return list(csv.DictReader(open(os.path.join(SCRATCH, name + ".csv"))))

# ---------------------------------------------------------------------------
# DB2
# ---------------------------------------------------------------------------
slaAll = C("SkillLineAbility")
spellName = {int(r["ID"]): r["Name_lang"] for r in C("SpellName")}
effects = collections.defaultdict(list)
for r in C("SpellEffect"):
    effects[int(r["SpellID"])].append(r)
reagents = {}
for r in C("SpellReagents"):
    reagents[int(r["SpellID"])] = [(int(r["Reagent_%d" % i]), int(r["ReagentCount_%d" % i]))
                                    for i in range(8) if int(r["Reagent_%d" % i])]
equipped = {}
for r in C("SpellEquippedItems"):
    equipped[int(r["SpellID"])] = (int(r["EquippedItemClass"]), int(r["EquippedItemInvTypes"]), int(r["EquippedItemSubclass"]))
itemSparse = {int(r["ID"]): r for r in C("ItemSparse")}
# A formula's ItemEffect rows: slot 0 is the generic "Learning" spell 483,
# slot 1 (TriggerType 6, LEARN_SPELL_ID) is the recipe it teaches
itemTeaches = collections.defaultdict(list)
for r in C("ItemEffect"):
    if r["TriggerType"] == "6":
        itemTeaches[int(r["ParentItemID"])].append(int(r["SpellID"]))
factionTemplate = {int(r["ID"]): r for r in C("FactionTemplate")}
factionName = {int(r["ID"]): r["Name_lang"] for r in C("Faction")}
areaName = {int(r["ID"]): r["AreaName_lang"] for r in C("AreaTable")}
uimap = {int(r["ID"]): r for r in C("UiMap")}
assign = [r for r in C("UiMapAssignment")]
mapName = {int(r["ID"]): r["MapName_lang"] for r in C("Map")}

def zone_of(mapid, wx, wy, prefer=None):
    """Zone map name, uiMapID and (x, y) percent for a world position.

    Zone boxes overlap, so the rule has three parts. A box that wholly
    contains another candidate loses to it (a city inside its zone: Lower
    City is Shattrath, not Terokkar). Then, among boxes the point sits well
    inside (ten percent from every edge), the smallest wins; a point that is
    at the edge of every box goes to the box it is deepest in. Smallest-box-
    alone put Deneb Walker at Hillsbrad 90.8, 91.2 (he is at Stromgarde,
    Arathi 27.0, 58.8), Balai Lok'Wein at Mulgore 96.1, 82.4 (Brackenwall,
    Dustwallow 36.5, 30.4) and Dalria at Stonetalon 73.1, 7.6 (Astranaar,
    Ashenvale 35.1, 52.1). `prefer` names a uiMapID to take when it is a
    candidate, for the handful of creatures that live on a zone's rim
    (PLACE_IN below). Inside an instance (no zone box) the instance's name
    and no coordinates: a boss is found by his room, not by a map percent."""
    hits = []
    for r in assign:
        if int(r["MapID"]) != mapid:
            continue
        u = uimap.get(int(r["UiMapID"]))
        if not u or u["Type"] != "3":
            continue
        x0, y0, x1, y1 = float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"])
        if x0 <= wx <= x1 and y0 <= wy <= y1:
            px, py = (y1 - wy) / (y1 - y0) * 100, (x1 - wx) / (x1 - x0) * 100
            hits.append({"area": (x1 - x0) * (y1 - y0), "name": u["Name_lang"], "id": int(r["UiMapID"]),
                         "x": round(px, 1), "y": round(py, 1), "depth": min(px, py, 100 - px, 100 - py),
                         "rect": (x0, y0, x1, y1)})
    if prefer:
        for h in hits:
            if h["id"] == prefer:
                return (h["name"], h["id"], h["x"], h["y"])
    def contains(outer, inner):
        return outer is not inner and outer["rect"][0] <= inner["rect"][0] and outer["rect"][1] <= inner["rect"][1] \
            and outer["rect"][2] >= inner["rect"][2] and outer["rect"][3] >= inner["rect"][3]
    hits = [h for h in hits if not any(contains(h, o) for o in hits)]
    deep = [h for h in hits if h["depth"] >= 10]
    best = min(deep, key=lambda h: h["area"]) if deep else (max(hits, key=lambda h: h["depth"]) if hits else None)
    if best:
        return (best["name"], best["id"], best["x"], best["y"])
    if mapid not in (0, 1, 530) and mapid in mapName:
        return (mapName[mapid], 0, None, None)
    return None

# ---------------------------------------------------------------------------
# World DB
# ---------------------------------------------------------------------------
db = pickle.load(open(os.path.join(SCRATCH, "tbcdb.pkl"), "rb"))
creature = {r["Entry"]: r for r in db["creature_template"]}
itemTemplate = {r["entry"]: r for r in db["item_template"]}
spawns = collections.defaultdict(list)
for r in db["creature"]:
    spawns[r["id"]].append((r["map"], r["position_x"], r["position_y"]))
# pooled spawns: creature rows with id 0 use creature_spawn_entry (guid -> entry)
guidMap = collections.defaultdict(list)
for r in db["creature_spawn_entry"]:
    guidMap[r["guid"]].append(r["entry"])
guidPos = {r["guid"]: (r["map"], r["position_x"], r["position_y"]) for r in db["creature"] if r["id"] == 0}
for guid, entries in guidMap.items():
    if guid in guidPos:
        for e in entries:
            spawns[e].append(guidPos[guid])
gobj = {r["entry"]: r for r in db["gameobject_template"]}
gspawns = collections.defaultdict(list)
for r in db["gameobject"]:
    gspawns[r["id"]].append((r["map"], r["position_x"], r["position_y"]))
quests = {r["entry"]: r for r in db["quest_template"]}
conditions = {r["condition_entry"]: r for r in db.get("conditions", [])}

def rep_condition(cid, depth=0):
    """A (faction, minRank) pair if the vendor row's condition is a reputation
    gate (type 5, or an AND (-1) containing one); ranks are 0-based like
    ItemSparse. Nothing else is a gate this window needs."""
    c = conditions.get(cid)
    if not c or depth > 4:
        return None
    if c["type"] == 5:
        return (c["value1"], c["value2"])
    if c["type"] == -1:
        return rep_condition(c["value1"], depth + 1) or rep_condition(c["value2"], depth + 1)
    return None

def generate(P):
    print("== %s ==" % P["name"])
    # ---------------------------------------------------------------------------
    # Recipes
    # ---------------------------------------------------------------------------
    INVTYPE_NAMES = {1: "head", 2: "neck", 3: "shoulder", 5: "chest", 6: "waist", 7: "legs", 8: "feet", 9: "wrist", 10: "hands",
                     11: "finger", 12: "trinket", 13: "onehand", 14: "shield", 15: "ranged", 16: "cloak", 17: "twohand", 20: "chest",
                     21: "mainhand", 22: "offhand", 23: "holdable", 26: "ranged"}

    def inv_types(mask):
        return sorted({INVTYPE_NAMES[i] for i in range(32) if (mask >> i) & 1 and i in INVTYPE_NAMES})

    recipes = {}
    skipped = []
    for r in [r for r in slaAll if r["SkillLine"] == str(P["skill"])]:
        spell = int(r["Spell"])
        effs = effects.get(spell, [])
        codes = {e["Effect"] for e in effs}
        if "53" not in codes and "24" not in codes:
            skipped.append((spell, spellName.get(spell), sorted(codes)))
            continue
        rec = {
            "spell": spell, "name": spellName.get(spell, "?"),
            "yellow": int(r["TrivialSkillLineRankLow"]), "grey": int(r["TrivialSkillLineRankHigh"]),
            "reagents": reagents.get(spell, []),
            "creates": None, "enchant": None, "targets": [],
        }
        for e in effs:
            if e["Effect"] == "24":
                rec["creates"] = int(e["EffectItemType"])
                # How many a cast makes: base points + 1 (Void Shatter makes two)
                rec["makes"] = int(e["EffectBasePoints"]) + max(1, int(e["EffectDieSides"]))
            elif e["Effect"] == "53":
                rec["enchant"] = int(e["EffectMiscValue_0"])
        if spell in equipped:
            cls, mask, sub = equipped[spell]
            rec["targets"] = inv_types(mask)
            rec["equipClass"], rec["equipSubclass"] = cls, sub
            if cls == 2:
                bits = {i for i in range(32) if (sub >> i) & 1}
                rec["targets"] = sorted(({"onehand"} if bits & ONE_HAND else set()) | ({"twohand"} if bits & TWO_HAND else set()) | ({"ranged"} if bits & RANGED else set()))
            elif cls == 4 and (sub >> 6) & 1 and not rec["targets"]:
                rec["targets"] = ["shield"]
        rec["category"] = P["category"](rec)
        recipes[spell] = rec

    # ---------------------------------------------------------------------------
    # Trainers
    # ---------------------------------------------------------------------------
    def faction_of(npc):
        ft = factionTemplate.get(npc["Faction"])
        if not ft:
            return None
        enemy, group = int(ft["EnemyGroup"]), int(ft["FactionGroup"])
        if group == 2 or (enemy & 4 and not enemy & 2):
            return "Alliance"
        if group == 4 or (enemy & 2 and not enemy & 4):
            return "Horde"
        return None

    def npc_place(entry):
        for mp, x, y in spawns.get(entry, []):
            z = zone_of(mp, x, y, PLACE_IN.get(entry))
            if z:
                return z + (mp,)
        return None

    trainerTemplates = collections.defaultdict(list)   # template id -> rows
    for r in db["npc_trainer_template"]:
        trainerTemplates[r["entry"]].append(r)
    directTrainer = collections.defaultdict(list)
    for r in db["npc_trainer"]:
        directTrainer[r["entry"]].append(r)

    trainers = {}      # npc -> info
    teaches = collections.defaultdict(dict)  # spell -> {npc: (skill, cost)}
    for entry, npc in creature.items():
        rows = list(trainerTemplates.get(npc["TrainerTemplateId"], [])) + list(directTrainer.get(entry, []))
        ours = [row for row in rows if row["spell"] in recipes or row["spell"] in P["rankSpells"]]
        if not ours:
            continue
        place = npc_place(entry)
        if not place:
            continue  # never spawned: a GM stock trainer
        zone, mapId, x, y, mp = place
        if x is None:
            continue  # a trainer inside an instance is not where anyone goes to train
        trainers[entry] = {"name": npc["Name"], "zone": zone, "map": mapId, "x": x, "y": y,
                           "faction": faction_of(npc), "outland": mp == 530}
        for row in ours:
            if row["spell"] in recipes:
                teaches[row["spell"]][entry] = (row["reqskillvalue"], row["spellcost"])

    for spell, rec in recipes.items():
        if spell in P["autoLearned"]:
            rec["trainer"] = {"skill": 0, "cost": 0, "outland": False, "count": 0, "withRank": True}
            continue
        t = teaches.get(spell)
        if t:
            skills = {v[0] for v in t.values()}
            costs = {v[1] for v in t.values()}
            rec["trainer"] = {"skill": min(skills), "cost": min(costs),
                              "outland": all(trainers[n]["outland"] for n in t),
                              "count": len(t)}

    # ---------------------------------------------------------------------------
    # Formulas
    # ---------------------------------------------------------------------------
    learnSpell = {}   # learn spell id -> recipe spell
    for spell, effs in effects.items():
        for e in effs:
            if e["Effect"] == "36" and int(e["EffectTriggerSpell"]) in recipes:
                learnSpell[spell] = int(e["EffectTriggerSpell"])
    formulas = {}
    for item, spells in itemTeaches.items():
        for s in spells:
            if s in recipes:
                rec = recipes[s]
                sp = itemSparse.get(item)
                if not sp:
                    continue
                formulas[item] = {
                    "item": item, "learns": rec["spell"], "name": sp["Display_lang"],
                    "skill": int(sp["RequiredSkillRank"]), "bop": int(sp["Bonding"]) == 1,
                    "rep": (int(sp["MinFactionID"]), int(sp["MinReputation"])) if int(sp["MinFactionID"]) else None,
                    "vendors": [], "drops": [], "objects": [], "containers": [], "quests": [],
                }
                rec.setdefault("formulas", []).append(item)

    # Vendors
    vendorRows = collections.defaultdict(list)
    for r in db["npc_vendor"]:
        vendorRows[r["item"]].append(r)
    # Most TBC stock is on vendor TEMPLATES shared between NPCs
    vendorTemplateNpcs = collections.defaultdict(list)
    for entry, npc in creature.items():
        if npc.get("VendorTemplateId"):
            vendorTemplateNpcs[npc["VendorTemplateId"]].append(entry)
    for r in db["npc_vendor_template"]:
        for entry in vendorTemplateNpcs.get(r["entry"], []):
            row = dict(r)
            row["entry"] = entry
            vendorRows[r["item"]].append(row)
    npcs = {}   # every npc we mention
    def add_npc(entry, kind):
        npc = creature.get(entry)
        if not npc:
            return False
        place = npc_place(entry)
        if not place and npc["Rank"] == 3:
            place = ("(summoned)", 0, None, None, 0)
        info = npcs.get(entry) or {"name": npc["Name"], "level": (npc["MinLevel"], npc["MaxLevel"]),
                                   "faction": faction_of(npc), "kinds": set()}
        if place:
            zone, mapId, x, y, mp = place
            # Inside an instance: the instance's map id (Map.db2 ID, the
            # client's instanceMapID), so the window can send the player to
            # its door (Commander Orders' Entrance({ instance = id })). A
            # boss with no spawn row ("(summoned)") has none: True.
            info.update({"zone": zone, "map": mapId, "x": x, "y": y, "instance": (mp or True) if x is None else None})
        info["kinds"].add(kind)
        npcs[entry] = info
        return place is not None

    for item, f in formulas.items():
        for r in vendorRows.get(item, []):
            if r["entry"] in P["manualRemoveVendors"].get(item, set()):
                continue
            if add_npc(r["entry"], "vendor"):
                price = itemTemplate.get(item, {}).get("BuyPrice", 0)
                gate = rep_condition(r.get("condition_id") or 0)
                f["vendors"].append({"npc": r["entry"], "cost": price, "limited": r["maxcount"] > 0, "rep": gate})
        for npc, cost in P["manualVendors"].get(item, []):
            if add_npc(npc, "vendor") and not any(v["npc"] == npc for v in f["vendors"]):
                f["vendors"].append({"npc": npc, "cost": cost, "limited": False})
        if item in P["manualNotes"]:
            f["note"] = P["manualNotes"][item]

    # Loot: creature, gameobject, item(container), with references resolved
    def loot_index(rows):
        byEntry = collections.defaultdict(list)
        for r in rows:
            byEntry[r["entry"]].append(r)
        return byEntry
    refLoot = loot_index(db["reference_loot_template"])

    def chance_in(rows, item, depth=0):
        """Effective % chance of `item` from one loot list (with group shares and references)."""
        total = 0.0
        groups = collections.defaultdict(list)
        for r in rows:
            groups[r["groupid"]].append(r)
        for gid, members in groups.items():
            explicit = sum(m["ChanceOrQuestChance"] for m in members if m["ChanceOrQuestChance"] > 0)
            zeros = [m for m in members if m["ChanceOrQuestChance"] == 0]
            share = (max(0.0, 100.0 - explicit) / len(zeros)) if (gid and zeros) else 0.0
            for m in members:
                c = m["ChanceOrQuestChance"]
                if c < 0:
                    c = -c  # quest drop
                elif c == 0:
                    c = share if gid else 100.0
                if m["mincountOrRef"] < 0:
                    ref = refLoot.get(-m["mincountOrRef"], [])
                    if depth < 4:
                        inner = chance_in(ref, item, depth + 1)
                        if inner:
                            total += c * inner / 100.0
                elif m["item"] == item:
                    total += c
        return total

    def item_in_ref(item, rows, depth=0, seen=None):
        for r in rows:
            if r["item"] == item:
                return True
            if r["mincountOrRef"] < 0 and depth < 4:
                if item_in_ref(item, refLoot.get(-r["mincountOrRef"], []), depth + 1):
                    return True
        return False

    creatureLoot = loot_index(db["creature_loot_template"])
    objectLoot = loot_index(db["gameobject_loot_template"])
    containerLoot = loot_index(db["item_loot_template"])
    formulaItems = set(formulas)

    def scan_loot(index, want):
        """item -> [(entry, chance)] for every entry whose list (incl references) holds a wanted item."""
        out = collections.defaultdict(list)
        # which references hold which wanted items, transitively
        refHolds = {}
        def holds(refId, depth=0):
            if refId in refHolds:
                return refHolds[refId]
            found = set()
            for r in refLoot.get(refId, []):
                if r["item"] in want:
                    found.add(r["item"])
                if r["mincountOrRef"] < 0 and depth < 4:
                    found |= holds(-r["mincountOrRef"], depth + 1)
            refHolds[refId] = found
            return found
        for entry, rows in index.items():
            candidates = set()
            for r in rows:
                if r["item"] in want:
                    candidates.add(r["item"])
                elif r["mincountOrRef"] < 0:
                    candidates |= holds(-r["mincountOrRef"])
            for item in candidates:
                c = chance_in(rows, item)
                if c > 0:
                    out[item].append((entry, c))
        return out

    creatureDrops = scan_loot(creatureLoot, formulaItems)
    objectDrops = scan_loot(objectLoot, formulaItems)
    containerDrops = scan_loot(containerLoot, formulaItems)

    WORLD_DROP_MIN = 25
    for item, f in formulas.items():
        # Unspawned creatures are GM stock rooms — except bosses, which are
        # summoned (Ouro, Nightbane) and are the whole point
        drops = [(e, c) for e, c in creatureDrops.get(item, []) if e in creature and (spawns.get(e) or creature[e]["Rank"] == 3)]
        if len(drops) >= WORLD_DROP_MIN:
            levels = [creature[e]["MinLevel"] for e, _ in drops] + [creature[e]["MaxLevel"] for e, _ in drops]
            f["worldDrop"] = {"minLevel": min(levels), "maxLevel": max(levels), "mobs": len(drops)}
            # keep the notable ones: rank > 0 (rares, elites, bosses) or chance well above the crowd
            notable = [(e, c) for e, c in drops if creature[e]["Rank"] > 0 or c >= 5.0]
            notable.sort(key=lambda t: -t[1])
            for e, c in notable[:6]:
                if add_npc(e, "drop"):
                    f["drops"].append({"npc": e, "chance": round(c, 2)})
        else:
            # Many droppers in one instance read as "that instance's trash" with
            # the bosses named; a handful anywhere are simply listed
            byZone = collections.defaultdict(list)
            for e, c in drops:
                place = npc_place(e)
                if place:
                    byZone[place[0]].append((e, c))
            f["zones"] = []
            listed = set()
            for zone, members in byZone.items():
                bosses = [(e, c) for e, c in members if creature[e]["Rank"] == 3]
                rest = [(e, c) for e, c in members if creature[e]["Rank"] != 3]
                if len(rest) >= 3 and all(npc_place(e)[2] is None for e, _ in members):
                    f["zones"].append({"zone": zone, "mobs": len(rest), "chance": round(max(c for _, c in rest), 2),
                                       "bosses": [e for e, _ in bosses]})
                    for e, c in bosses:
                        if add_npc(e, "drop"):
                            f["drops"].append({"npc": e, "chance": round(c, 2)})
                    listed |= {e for e, _ in members}
            drops.sort(key=lambda t: -t[1])
            for e, c in [d for d in drops if d[0] not in listed][:12]:
                if add_npc(e, "drop"):
                    f["drops"].append({"npc": e, "chance": round(c, 2)})
        for e, c in sorted(objectDrops.get(item, []), key=lambda t: -t[1])[:6]:
            g = gobj.get(e)
            if not g or not gspawns.get(e):
                continue
            z = None
            for mp, x, y in gspawns[e]:
                z = zone_of(mp, x, y)
                if z:
                    break
            f["objects"].append({"object": e, "name": g["name"], "zone": z and z[0], "chance": round(c, 2), "spawns": len(gspawns[e])})
        for e, c in sorted(containerDrops.get(item, []), key=lambda t: -t[1])[:4]:
            it = itemTemplate.get(e)
            if it:
                f["containers"].append({"item": e, "name": it["name"], "chance": round(c, 2)})
        for q in quests.values():
            rewards = [q.get("RewItemId%d" % i) for i in range(1, 5)] + [q.get("RewChoiceItemId%d" % i) for i in range(1, 7)]
            if item in rewards:
                f["quests"].append({"quest": q["entry"], "name": q["Title"], "level": q["QuestLevel"],
                                    "zone": areaName.get(q["ZoneOrSort"]) if q["ZoneOrSort"] > 0 else None,
                                    "races": q["RequiredRaces"]})

    # ---------------------------------------------------------------------------
    # What could not be sourced
    # ---------------------------------------------------------------------------
    def sourced(f):
        return bool(f["vendors"] or f["drops"] or f["objects"] or f["containers"] or f["quests"] or f.get("worldDrop") or f.get("zones") or f.get("note"))

    # A formula the world DB knows no source for is noise beside a trainer that
    # teaches the same recipe; it is dropped from that recipe's list (and the
    # output) unless it is the recipe's only teacher, in which case the recipe
    # is reported below.
    for spell, rec in recipes.items():
        items = rec.get("formulas", [])
        keep = [i for i in items if sourced(formulas[i])]
        if keep or "trainer" in rec:
            rec["formulas"] = keep
    for item in list(formulas):
        if item not in recipes[formulas[item]["learns"]].get("formulas", []):
            del formulas[item]

    unsourced = []
    for spell, rec in recipes.items():
        ok = "trainer" in rec
        if spell in P["neverAdded"]:
            ok = False
        for item in rec.get("formulas", []):
            f = formulas[item]
            if f["vendors"] or f["drops"] or f["objects"] or f["containers"] or f["quests"] or f.get("worldDrop") or f.get("zones") or f.get("note"):
                ok = True
        rec["obtainable"] = ok
        if not ok:
            unsourced.append((spell, rec["name"], rec.get("formulas", [])))

    # ---------------------------------------------------------------------------
    # Item names for everything referenced
    # ---------------------------------------------------------------------------
    itemNames = {}
    def name_item(i):
        sp = itemSparse.get(i)
        if sp:
            itemNames[i] = sp["Display_lang"]
        elif i in itemTemplate:
            itemNames[i] = itemTemplate[i]["name"]
    for rec in recipes.values():
        if not rec["obtainable"]:
            continue
        for i, _ in rec["reagents"]:
            name_item(i)
        if rec["creates"]:
            name_item(rec["creates"])
    for item in formulas:
        name_item(item)

    # ---------------------------------------------------------------------------
    # Write
    # ---------------------------------------------------------------------------
    def lstr(s):
        return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

    CATEGORY_ORDER = P["categoryOrder"]
    CATEGORY_LABEL = P["categoryLabel"]

    out = []
    w = out.append
    w("-- Commander Formulary: %s recipe data. GENERATED by Harness/make_formulary.py" % P["name"])
    w("-- from this build's DB2 tables (wago.tools, 2.5.6.69795) and the CMaNGOS TBC world DB.")
    w("-- Do not edit by hand; edit the generator and re-run it. See DECISIONS.md D2.")
    w("")
    w("CommanderFormulary_Data = CommanderFormulary_Data or {}")
    w("local D = CommanderFormulary_Data")
    w("")
    w("D.%s = {" % P["key"])
    w("    key = %s, name = %s, skillLine = %d, abilitySpell = %d," % (lstr(P["key"]), lstr(P["name"]), P["skill"], P["abilitySpell"]))
    w("    icon = %s, frame = %s," % (lstr(P["icon"]), lstr(P["frame"])))
    w("    ranks = {")
    for r in P["ranks"]:
        fields = ["name = %s" % lstr(r["name"]), "spell = %d" % r["spell"], "at = %d" % r["at"], "cap = %d" % r["cap"]]
        if r.get("outland"):
            fields.append("outland = true")
        if r.get("book"):
            # A rank taught by a book: the item, what it needs, and who sells it
            item = r["book"]
            sp = itemSparse.get(item)
            sellers = []
            for row in vendorRows.get(item, []):
                if add_npc(row["entry"], "vendor"):
                    sellers.append(row["entry"])
            name_item(item)
            fields.append("book = { item = %d, skill = %d, cost = %d, vendors = { %s } }" % (
                item, int(sp["RequiredSkillRank"]) if sp else r["at"], itemTemplate.get(item, {}).get("BuyPrice", 0),
                ", ".join(str(n) for n in sorted(set(sellers)))))
        if r.get("quests"):
            # A rank rewarded by a quest, one per faction, with who gives it
            qs = []
            for qid, faction, giver in r["quests"]:
                q = quests.get(qid, {})
                add_npc(giver, "quest")
                qs.append("{ quest = %d, name = %s, faction = %s, npc = %d, level = %d }" % (
                    qid, lstr(q.get("Title") or "?"), lstr(faction), giver, q.get("QuestLevel", 0)))
            fields.append("quests = { %s }" % ", ".join(qs))
        w("        { %s }," % ", ".join(fields))
    w("    },")
    w("    categories = {")
    for k in CATEGORY_ORDER:
        w("        { key = %s, label = %s }," % (lstr(k), lstr(CATEGORY_LABEL[k])))
    w("    },")
    w("    recipes = {")
    for spell in sorted(recipes):
        rec = recipes[spell]
        if not rec["obtainable"]:
            continue
        fields = ["spell = %d" % spell, "name = %s" % lstr(rec["name"]), "category = %s" % lstr(rec["category"]),
                  "yellow = %d" % rec["yellow"], "grey = %d" % rec["grey"]]
        if rec["creates"]:
            fields.append("creates = %d" % rec["creates"])
            if rec.get("makes", 1) > 1:
                fields.append("makes = %d" % rec["makes"])
        if rec["enchant"]:
            fields.append("enchant = %d" % rec["enchant"])
        if rec["targets"]:
            fields.append("targets = { %s }" % ", ".join(lstr(t) for t in rec["targets"]))
        fields.append("reagents = { %s }" % ", ".join("{ %d, %d }" % (i, n) for i, n in rec["reagents"]))
        if "trainer" in rec:
            t = rec["trainer"]
            fields.append("trainer = { skill = %d, cost = %d%s%s }" % (t["skill"], t["cost"], ", outland = true" if t["outland"] else "", ", withRank = true" if t.get("withRank") else ""))
        if rec.get("formulas"):
            fields.append("formulas = { %s }" % ", ".join(str(i) for i in rec["formulas"]))
        w("        { %s }," % ", ".join(fields))
    w("    },")
    w("    formulas = {")
    for item in sorted(formulas):
        f = formulas[item]
        if not recipes[f["learns"]]["obtainable"]:
            continue
        fields = ["learns = %d" % f["learns"], "skill = %d" % f["skill"]]
        if f["bop"]:
            fields.append("bop = true")
        if f["rep"]:
            fields.append("rep = { faction = %d, standing = %d, name = %s }" % (f["rep"][0], f["rep"][1], lstr(factionName.get(f["rep"][0], "?"))))
        if f.get("worldDrop"):
            wd = f["worldDrop"]
            fields.append("worldDrop = { minLevel = %d, maxLevel = %d, mobs = %d }" % (wd["minLevel"], wd["maxLevel"], wd["mobs"]))
        if f["vendors"]:
            fields.append("vendors = { %s }" % ", ".join("{ npc = %d, cost = %d%s%s }" % (
                v["npc"], v["cost"], ", limited = true" if v["limited"] else "",
                (", rep = { faction = %d, standing = %d, name = %s }" % (v["rep"][0], v["rep"][1], lstr(factionName.get(v["rep"][0], "?")))) if v.get("rep") else "")
                for v in f["vendors"]))
        if f.get("zones"):
            fields.append("zones = { %s }" % ", ".join("{ zone = %s, mobs = %d%s }" % (lstr(z["zone"]), z["mobs"], (", chance = %s" % z["chance"]) if z["chance"] else "") for z in f["zones"]))
        if f["drops"]:
            fields.append("drops = { %s }" % ", ".join("{ npc = %d, chance = %s }" % (d["npc"], d["chance"]) for d in f["drops"]))
        if f.get("note"):
            fields.append("note = %s" % lstr(f["note"]))
        if f["objects"]:
            fields.append("objects = { %s }" % ", ".join("{ name = %s, zone = %s, chance = %s }" % (lstr(o["name"]), lstr(o["zone"]) if o["zone"] else "nil", o["chance"]) for o in f["objects"]))
        if f["containers"]:
            fields.append("containers = { %s }" % ", ".join("{ item = %d, name = %s, chance = %s }" % (c["item"], lstr(c["name"]), c["chance"]) for c in f["containers"]))
        if f["quests"]:
            fields.append("quests = { %s }" % ", ".join("{ quest = %d, name = %s, level = %d%s }" % (q["quest"], lstr(q["name"] or "?"), q["level"], (", zone = " + lstr(q["zone"])) if q["zone"] else "") for q in f["quests"]))
        w("        [%d] = { %s }," % (item, ", ".join(fields)))
    w("    },")
    disenchant = {}
    if P["disenchant"]:
        # Disenchanting: the world DB gives each item a disenchant loot id; the ids
        # fall into item-level brackets per quality and class (armour / weapon),
        # which is the rule an addon can apply to any item it is shown. Results are
        # the loot rows with group shares resolved.
        deLoot = collections.defaultdict(list)
        for r in db.get("disenchant_loot_template", []):
            deLoot[r["entry"]].append(r)
        def de_results(entry):
            rows = deLoot.get(entry, [])
            groups = collections.defaultdict(list)
            for r in rows:
                groups[r["groupid"]].append(r)
            out = []
            for gid, members in groups.items():
                explicit = sum(m["ChanceOrQuestChance"] for m in members if m["ChanceOrQuestChance"] > 0)
                zeros = [m for m in members if m["ChanceOrQuestChance"] == 0]
                share = (max(0.0, 100.0 - explicit) / len(zeros)) if zeros else 0.0
                for m in members:
                    c = m["ChanceOrQuestChance"] if m["ChanceOrQuestChance"] > 0 else share
                    out.append((m["item"], round(c, 2), max(1, m["mincountOrRef"]), max(1, m["maxcount"])))
            out.sort(key=lambda t: -t[1])
            return out
        byQC = collections.defaultdict(lambda: collections.defaultdict(collections.Counter))
        for r in db["item_template"]:
            if r.get("DisenchantID") and r["Quality"] in (2, 3, 4) and r["class"] in (2, 4):
                byQC[(r["Quality"], r["class"])][r["ItemLevel"]][r["DisenchantID"]] += 1
        disenchant = {}
        for key in sorted(byQC):
            runs = []
            for lvl in sorted(byQC[key]):
                did = byQC[key][lvl].most_common(1)[0][0]
                if runs and runs[-1][2] == did:
                    runs[-1][1] = lvl
                else:
                    runs.append([lvl, lvl, did])
            # gaps between runs belong to the LATER run (the 66-78 green gap is
            # Outland's, and Outland greens disenchant to Arcane Dust); the first
            # run starts where it starts and the last is open-ended
            for i, run in enumerate(runs):
                if i > 0:
                    run[0] = runs[i - 1][1] + 1
                if i + 1 == len(runs):
                    run[1] = 200
            disenchant[key] = [(a, b, did, de_results(did)) for a, b, did in runs]
            for a, b, did, res in disenchant[key]:
                for item, _, _, _ in res:
                    name_item(item)

    w("    trainers = {")
    for entry in sorted(trainers, key=lambda e: (trainers[e]["outland"], trainers[e]["zone"], trainers[e]["name"])):
        t = trainers[entry]
        w("        { npc = %d, name = %s, zone = %s, map = %d, x = %s, y = %s%s%s }," % (
            entry, lstr(t["name"]), lstr(t["zone"]), t["map"], t["x"], t["y"],
            (", faction = " + lstr(t["faction"])) if t["faction"] else "", ", outland = true" if t["outland"] else ""))
    w("    },")
    w("    npcs = {")
    for entry in sorted(npcs):
        n = npcs[entry]
        fields = ["name = %s" % lstr(n["name"])]
        if "zone" in n:
            fields.append("zone = %s" % lstr(n["zone"]))
            if n.get("x") is not None:
                fields += ["map = %d" % n["map"], "x = %s" % n["x"], "y = %s" % n["y"]]
            elif n.get("instance") is True:
                fields.append("instance = true")
            else:
                fields.append("instance = %d" % n["instance"])
        if "drop" in n["kinds"]:
            fields.append("level = { %d, %d }" % n["level"])
        if n["faction"] and "vendor" in n["kinds"]:
            fields.append("faction = %s" % lstr(n["faction"]))
        w("        [%d] = { %s }," % (entry, ", ".join(fields)))
    w("    },")
    # Reagents any spawned vendor sells, at the vendor price: the price an
    # enchanter actually pays for a Copper Rod or a vial
    # "Sells" means at least three spawned vendors carry it unlimited: one odd
    # GM room or a single limited-stock row is not a supply line
    vendorSold = set()
    for item, rows in vendorRows.items():
        sellers = {r["entry"] for r in rows if spawns.get(r["entry"]) and r["maxcount"] == 0}
        if len(sellers) >= 3:
            vendorSold.add(item)
    reagentItems = set()
    for rec in recipes.values():
        for i, _ in rec["reagents"]:
            reagentItems.add(i)
    w("    -- Reagents a trade-supply vendor sells, at the vendor's price in copper")
    w("    vendorBuy = {")
    for i in sorted(reagentItems & vendorSold):
        price = itemTemplate.get(i, {}).get("BuyPrice", 0)
        if price > 0:
            w("        [%d] = %d, -- %s" % (i, price, itemNames.get(i, "?")))
    w("    },")
    if P["disenchant"]:
        w("    -- Disenchanting: [quality][class] = ordered item-level brackets, each with")
        w("    -- what comes out and how often. Class 2 is weapons, 4 is armour.")
        w("    disenchant = {")
        for (quality, cls), runs in sorted(disenchant.items()):
            w("        [\"%d:%d\"] = {" % (quality, cls))
            for a, b, did, res in runs:
                w("            { min = %d, max = %d, results = { %s } }," % (a, b, ", ".join("{ %d, %s, %d, %d }" % r for r in res)))
            w("        },")
        w("    },")
    w("    items = {")
    for i in sorted(itemNames):
        w("        [%d] = %s," % (i, lstr(itemNames[i])))
    w("    },")
    w("}")
    open(os.path.join(HERE, "..", P["out"]), "w").write("\n".join(out) + "\n")

    print("recipes:", len(recipes), "obtainable:", sum(1 for r in recipes.values() if r["obtainable"]))
    print("formulas:", len(formulas), "trainers:", len(trainers), "npcs:", len(npcs))
    print("skipped SLA rows (not recipes):", skipped)
    print("UNSOURCED (excluded):")
    for s in unsourced:
        print("   ", s)
    cats = collections.Counter(r["category"] for r in recipes.values() if r["obtainable"])
    print("categories:", dict(cats))
    wd = [f["name"] for f in formulas.values() if f.get("worldDrop")]
    print("world drops:", len(wd))

    # ---------------------------------------------------------------------------
    # Cross-check against Recipe Master's curated sources (installed beside us)
    # ---------------------------------------------------------------------------
    RM = os.path.join(HERE, "..", "..", "RecipeMaster", "Source", "Database", "Sources", "Recipes", P["rmFile"])
    if os.path.exists(RM):
        text = open(RM).read()
        blocks = re.split(r"\n\t\[(\d+)\] = \{", text)
        rm = {}
        for item, body in zip(blocks[1::2], blocks[2::2]):
            kinds = {}
            for kind, inner in re.findall(r"\n\t\t(\w+) = \{(.*?)\n\t\t\}", body, re.S):
                kinds[kind] = set(int(x) for x in re.findall(r"\[(\d+)\]", inner))
            rm[int(item)] = kinds
        print("RM cross-check (formula: what RM has that we do not):")
        missing = 0
        for item in sorted(formulas):
            f = formulas[item]
            r = rm.get(item)
            if not r:
                continue
            ours = {"vendor": {v["npc"] for v in f["vendors"]}, "drop": {d["npc"] for d in f["drops"]}}
            gaps = {}
            for kind in ("vendor", "drop"):
                extra = r.get(kind, set()) - ours[kind]
                if extra and not (kind == "drop" and f.get("worldDrop")):
                    gaps[kind] = sorted(extra)[:8]
            if gaps:
                missing += 1
                print("   ", item, f["name"], gaps)
        print("formulas with RM sources we lack:", missing, "of", len(formulas))


for key, P in PROFESSIONS.items():
    if ONLY is None or ONLY == key:
        generate(P)
