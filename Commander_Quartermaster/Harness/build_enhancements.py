#!/usr/bin/env python3
"""Generate CommanderQuartermasterEnhanceData.lua — every TBC item enhancement.

An "item enhancement" here is anything that permanently or temporarily improves
a piece of gear you are wearing: enchanting enchants, head glyphs and arcanums,
shoulder inscriptions, leg armors and spellthreads, armor kits, weapon chains,
shield spikes, scopes, gems, and the temporary weapon buffs (stones, oils,
poisons, shaman imbues).

Nothing in the output is hand-written. The universe comes from the client's own
tables for the build this account runs — every spell with an ENCHANT_ITEM or
ENCHANT_ITEM_TEMPORARY effect, plus every gem item — so an enhancement cannot
be "forgotten": if the client can apply it, it is in here. Sourcing comes from
the staged world DB (see qm_worlddb.py).

    python3 Harness/tbcdb_to_sqlite.py --fetch     # once
    python3 Harness/build_enhancements.py          # writes the Lua
    python3 Harness/build_enhancements.py --report # what would change, no write
"""
import argparse
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from qm_worlddb import WorldDB, load_csv, _int, STANDING   # noqa: E402

OUT = os.path.join(ADDON, "CommanderQuartermasterEnhanceData.lua")
BUILD = "2.5.6.68941"

# Spell effect ids
EFFECT_ENCHANT_ITEM = 53
EFFECT_ENCHANT_ITEM_TEMP = 54
EFFECT_CREATE_ITEM = 24
EFFECT_LEARN_SPELL = 36

SKILL_NAMES = {
    333: "Enchanting", 202: "Engineering", 164: "Blacksmithing",
    165: "Leatherworking", 197: "Tailoring", 755: "Jewelcrafting",
    171: "Alchemy", 185: "Cooking", 129: "First Aid", 186: "Mining",
    182: "Herbalism", 393: "Skinning", 356: "Fishing", 773: "Inscription",
}

# InventoryType -> our slot key. The enchant spell's EquippedItemInvTypes is a
# bitmask over these, which is how the client itself decides what a scroll can
# land on.
INV_SLOT = {
    1: "HEAD", 3: "SHOULDER", 5: "CHEST", 20: "CHEST", 6: "BELT", 7: "LEGS",
    8: "BOOTS", 9: "BRACER", 10: "GLOVES", 11: "RING", 12: "TRINKET",
    13: "WEAPON", 14: "SHIELD", 15: "RANGED", 16: "CLOAK", 17: "TWOHAND",
    21: "WEAPON", 22: "OFFHAND", 23: "HELD", 25: "THROWN", 26: "RANGED",
    2: "NECK", 28: "RELIC",
}

SLOT_ORDER = ["HEAD", "SHOULDER", "CLOAK", "CHEST", "BRACER", "GLOVES", "BELT",
              "LEGS", "BOOTS", "RING", "WEAPON", "TWOHAND", "SHIELD", "RANGED",
              "GEM", "OTHER"]
SLOT_NAMES = {
    "HEAD": "Head", "SHOULDER": "Shoulder", "CLOAK": "Cloak", "CHEST": "Chest",
    "BRACER": "Bracer", "GLOVES": "Gloves", "BELT": "Belt", "LEGS": "Legs",
    "BOOTS": "Boots", "RING": "Ring", "WEAPON": "Weapon", "TWOHAND": "Two-Hand",
    "SHIELD": "Shield", "RANGED": "Ranged", "GEM": "Gem", "OTHER": "Other",
}

# Gem colour, from GemProperties.Type — a BITMASK, not an enum. An orange gem
# is red|yellow and fits either socket, which is the whole point of the
# TBC gem system, so the colour has to be kept as a set.
GEM_COLORS = [(1, "META"), (2, "RED"), (4, "YELLOW"), (8, "BLUE")]

# Meta-gem activation, from SpellItemEnchantment.Condition_ID ->
# SpellItemEnchantmentCondition. Operand types are colour indices and the
# operators are the three the client implements. Decoded here rather than
# scraped, then checked against Wowhead's rendered sentence: all six metas
# spot-checked agree exactly ("Requires at least 2 Red Gems" and so on).
COND_COLOR = {1: "META", 2: "RED", 3: "YELLOW", 4: "BLUE"}
COND_OP = {2: ">", 3: "<", 5: ">="}


def decode_condition(row):
    if not row:
        return None, None
    clauses, words = [], []
    for i in range(5):
        lt = _int(row["Lt_operandType_%d" % i])
        if not lt:
            continue
        op = _int(row["Operator_%d" % i])
        rt_type = _int(row["Rt_operandType_%d" % i])
        rt = _int(row["Rt_operand_%d" % i])
        clause = {"lt": COND_COLOR.get(lt), "op": COND_OP.get(op)}
        if rt_type:
            clause["rtColor"] = COND_COLOR.get(rt_type)
        else:
            clause["rt"] = rt
        if not (clause["lt"] and clause["op"]):
            continue
        clauses.append(clause)
        # The client's own phrasing, which is what the player is looking for
        if rt_type:
            words.append(("more %s than %s Gems" if op == 2 else "fewer %s than %s Gems")
                         % (clause["lt"].capitalize(), (clause.get("rtColor") or "?").capitalize()))
        elif op == 5:
            words.append("at least %d %s Gem%s" % (rt, clause["lt"].capitalize(),
                                                   "" if rt == 1 else "s"))
        else:
            words.append("%s %s %d Gems" % (clause["lt"].capitalize(),
                                            COND_OP.get(op, "?"), rt))
    if not clauses:
        return None, None
    return clauses, "Requires " + ", ".join(words)

# Names the client carries but no player ever sees
JUNK = re.compile(r"^(QAEnchant|Test |TEST|zzOLD|OLD |Deprecated|\[?PH\]?|NPC )|"
                  r"(TEST|Deprecated|DEPRECATED|UNUSED)", re.I)

CLASS_BY_MASK = [
    (1, "WARRIOR"), (2, "PALADIN"), (4, "HUNTER"), (8, "ROGUE"), (16, "PRIEST"),
    (64, "SHAMAN"), (128, "MAGE"), (256, "WARLOCK"), (1024, "DRUID"),
]
ALL_CLASSES = 1 + 2 + 4 + 8 + 16 + 64 + 128 + 256 + 1024


def classes_of(mask):
    mask = _int(mask)
    if not mask or mask == -1 or (mask & ALL_CLASSES) == ALL_CLASSES:
        return None
    return [name for bit, name in CLASS_BY_MASK if mask & bit] or None


# ---------------------------------------------------------------------------
# Client tables
# ---------------------------------------------------------------------------
class Client:
    def __init__(self, world=None):
        self.world = world
        self.spell_name = {_int(r["ID"]): r["Name_lang"] for r in load_csv("SpellName")}
        self.spell_desc = {}
        for r in load_csv("Spell"):
            self.spell_desc[_int(r["ID"])] = r.get("Description_lang") or ""
        self.ench = {_int(r["ID"]): r for r in load_csv("SpellItemEnchantment")}
        self.item = {_int(r["ID"]): r for r in load_csv("ItemSparse")}
        self.item_cls = {_int(r["ID"]): r for r in load_csv("Item")}
        self.gem_props = {_int(r["ID"]): r for r in load_csv("GemProperties")}
        self.ench_cond = {_int(r["ID"]): r for r in load_csv("SpellItemEnchantmentCondition")}
        self.equipped = {}
        for r in load_csv("SpellEquippedItems"):
            self.equipped[_int(r["SpellID"])] = r
        self.levels = {_int(r["SpellID"]): r for r in load_csv("SpellLevels")}
        self.limit = {_int(r["ID"]): r for r in load_csv("ItemLimitCategory")}

        self.perm, self.temp, self.creates, self.teaches = {}, {}, {}, {}
        for r in load_csv("SpellEffect"):
            sid, eff = _int(r["SpellID"]), _int(r["Effect"])
            if eff == EFFECT_ENCHANT_ITEM:
                self.perm[sid] = _int(r["EffectMiscValue_0"])
            elif eff == EFFECT_ENCHANT_ITEM_TEMP:
                self.temp[sid] = _int(r["EffectMiscValue_0"])
            elif eff == EFFECT_CREATE_ITEM:
                self.creates[sid] = _int(r["EffectItemType"])
            elif eff == EFFECT_LEARN_SPELL:
                self.teaches[sid] = _int(r["EffectTriggerSpell"])

        # item -> spells it casts, and the reverse. TriggerType matters: 6 is
        # "teaches you this", which is what a Formula scroll does. Treating that
        # as a carrier would file every enchanting recipe as if the scroll were
        # the thing you apply to the gear.
        self.item_spells = defaultdict(list)
        self.spell_items = defaultdict(list)
        self.spell_taught_by_item = defaultdict(list)
        for r in load_csv("ItemEffect"):
            iid, sid, trig = _int(r["ParentItemID"]), _int(r["SpellID"]), _int(r["TriggerType"])
            self.item_spells[iid].append((sid, trig))
            if trig == 6:
                self.spell_taught_by_item[sid].append(iid)
            else:
                self.spell_items[sid].append(iid)

        # profession recipes
        self.skill_of_spell = defaultdict(list)
        for r in load_csv("SkillLineAbility"):
            self.skill_of_spell[_int(r["Spell"])].append(
                (_int(r["SkillLine"]), _int(r["MinSkillLineRank"])))

        self.reagents = {}
        for r in load_csv("SpellReagents"):
            got = []
            for i in range(8):
                iid, cnt = _int(r["Reagent_%d" % i]), _int(r["ReagentCount_%d" % i])
                if iid and cnt:
                    got.append((iid, cnt))
            if got:
                self.reagents[_int(r["SpellID"])] = got

        # which spell creates a given item (the crafting recipe)
        self.creator_of_item = defaultdict(list)
        for sid, iid in self.creates.items():
            if iid:
                self.creator_of_item[iid].append(sid)
        # which spell teaches a given spell (the recipe scroll's payload)
        self.teacher_of_spell = defaultdict(list)
        for sid, taught in self.teaches.items():
            if taught:
                self.teacher_of_spell[taught].append(sid)

    def req_skill(self, item_id):
        """The profession you must HAVE to use it — what makes a gem
        jeweller-only or a scope engineer-only."""
        row = self.item.get(item_id)
        if row is None:
            return None
        skill, rank = _int(row["RequiredSkill"]), _int(row["RequiredSkillRank"])
        if not skill or skill not in SKILL_NAMES:
            return None
        return {"skill": SKILL_NAMES[skill], "rank": rank or None}

    def unique_of(self, item_id, world=None):
        """Unique, unique-equipped, or one of a limited family of gems.

        Three different limits in TBC and they are not interchangeable: a
        LimitCategory caps a FAMILY ("Jeweler's Gems (3)"), maxcount caps how
        many you may own, and the unique-equipped item flag caps how many you
        may wear. The world DB carries the flag and the count; the client
        carries the family.
        """
        out = {}
        row = self.item.get(item_id)
        cat = self.limit.get(_int(row["LimitCategory"])) if row is not None else None
        if cat:
            out["family"] = cat["Name_lang"]
            out["max"] = _int(cat["Quantity"])
        if world is not None:
            wrow = world.item_row(item_id)
            if wrow is not None:
                if _int(wrow["Flags"]) & 0x00080000:
                    out["equipped"] = True
                if _int(wrow["maxcount"]) > 0:
                    out["own"] = _int(wrow["maxcount"])
        return out or None

    def item_name(self, iid):
        r = self.item.get(iid)
        return r["Display_lang"] if r else None

    def profession(self, spell_id):
        """Which profession makes this, and at what skill.

        SkillLineAbility.MinSkillLineRank is 1 for most recipes — it is the
        rank at which the ability may EXIST, not the rank that gates it. What
        actually gates a player is the recipe scroll's own RequiredSkillRank
        (Formula: Enchant Weapon - Mongoose says Enchanting 375, and so does
        the live client's tooltip), so prefer that and fall back.
        """
        for skill, rank in self.skill_of_spell.get(spell_id, []):
            if skill not in SKILL_NAMES:
                continue
            for item in self.recipe_items(spell_id):
                row = self.item.get(item)
                if row is not None and _int(row["RequiredSkill"]) == skill:
                    rank = max(rank, _int(row["RequiredSkillRank"]))
            if rank <= 1 and self.world is not None:
                # trainer-taught: no scroll to read the gate off, so ask the
                # trainer (Heavy Knothide Armor Kit is Leatherworking 350, and
                # the client's own SkillLineAbility rank for it is 1)
                for t in self.world.trainers(spell_id):
                    rank = max(rank, t.get("reqSkill") or 0)
            return {"skill": SKILL_NAMES[skill], "skillID": skill, "rank": rank or None}
        return None

    def recipe_items(self, spell):
        """The Formula/Plans/Pattern scroll that teaches this craft, if any.

        Two shapes in the client: the scroll's on-learn effect points straight
        at the craft, or at a wrapper spell whose LEARN_SPELL effect does.
        """
        items = list(self.spell_taught_by_item.get(spell, []))
        for teacher in self.teacher_of_spell.get(spell, []):
            items += self.spell_taught_by_item.get(teacher, [])
            items += self.spell_items.get(teacher, [])
        seen, out = set(), []
        for i in items:
            if i not in seen and self.item.get(i):
                seen.add(i)
                out.append(i)
        return out

    def equip_filter(self, spell_id):
        """The item class and subclass mask the enchant spell accepts.

        This is what separates a wand from a gun and a fishing pole from a
        staff: they share an equip location, and only the subclass mask says
        which of them a scope or a lure may land on.
        """
        r = self.equipped.get(spell_id)
        if not r:
            return None, None
        cls, sub = _int(r["EquippedItemClass"]), _int(r["EquippedItemSubclass"])
        if cls < 0:
            return None, None
        return cls, (sub if sub > 0 else None)

    def slots_for_spell(self, spell_id):
        """Which equipment slots this enchant spell may land on."""
        r = self.equipped.get(spell_id)
        if not r:
            return []
        cls = _int(r["EquippedItemClass"])
        inv_mask = _int(r["EquippedItemInvTypes"])
        sub_mask = _int(r["EquippedItemSubclass"])
        slots = []
        if inv_mask:
            for inv, slot in INV_SLOT.items():
                if inv_mask & (1 << inv) and slot not in slots:
                    slots.append(slot)
        if not slots and cls == 2:      # a weapon enchant with no inv-type mask
            # subclass 1/5/8 are the two-handers (axe, mace, sword) plus 6 polearm
            two = {1, 5, 6, 8, 10}
            one = {0, 4, 7, 13, 15}
            if sub_mask and not (sub_mask & sum(1 << s for s in one)):
                slots = ["TWOHAND"]
            elif sub_mask and not (sub_mask & sum(1 << s for s in two)):
                slots = ["WEAPON"]
            else:
                slots = ["WEAPON"]
            if sub_mask and (sub_mask & sum(1 << s for s in (2, 3, 18))):
                slots = ["RANGED"]
        if not slots and cls == 4:
            # armour with no inv-type mask: the subclass mask is doing the work.
            # Subclass 6 is Shield, which is the only armour piece TBC enchants
            # by weapon-style subclass rather than by slot.
            slots = ["SHIELD"] if sub_mask & (1 << 6) else ["OTHER"]
        return slots


# ---------------------------------------------------------------------------
# What an enhancement actually grants
# ---------------------------------------------------------------------------
# Parsed from the enchantment's own display string — the green line the game
# prints on the item — rather than reconstructed from aura effects. The string
# is the client's, so it cannot drift from what the player reads; the cost is
# that a phrase we do not recognise yields no stats at all, which is why the
# generator reports its own coverage. These numbers exist to RANK
# enhancements for a spec, never to describe one: the display string is what
# the UI shows.
STAT_NAMES = {
    "stamina": "STA", "agility": "AGI", "strength": "STR",
    "intellect": "INT", "spirit": "SPI", "all stats": "ALLSTATS",
    "attack power": "AP", "ranged attack power": "RAP",
    "attack power in forms": "AP", "attack power in cat": "AP",
    "spell damage": "SP", "damage spells": "SP", "spell power": "SP",
    "healing": "HEAL", "healing spells": "HEAL", "healing power": "HEAL",
    "critical strike rating": "CRIT", "critical rating": "CRIT",
    "melee critical strike rating": "CRIT",
    "spell critical strike rating": "SPELLCRIT", "spell critical rating": "SPELLCRIT",
    "hit rating": "HIT", "spell hit rating": "SPELLHIT", "spell hit": "SPELLHIT",
    "haste rating": "HASTE", "spell haste rating": "SPELLHASTE",
    "expertise rating": "EXPERTISE", "resilience rating": "RESIL",
    "defense rating": "DEF", "defense": "DEF",
    "dodge rating": "DODGE", "parry rating": "PARRY",
    "block value": "BLOCKVALUE", "block rating": "BLOCK", "shield block rating": "BLOCK",
    "armor": "ARMOR", "armor penetration": "ARPEN",
    "all resistances": "ALLRES",
    "fire resistance": "FIRERES", "frost resistance": "FROSTRES",
    "nature resistance": "NATURERES", "shadow resistance": "SHADOWRES",
    "arcane resistance": "ARCANERES", "holy resistance": "HOLYRES",
    "spell penetration": "SPELLPEN",
    "mana": "MANA", "health": "HP",
    "mana regen": "MP5", "mana per 5 sec": "MP5", "mana every 5 seconds": "MP5",
    "mana per 5 seconds": "MP5", "mana every 5 sec": "MP5",
    "health every 5 seconds": "HP5", "health per 5 sec": "HP5",
    "weapon damage": "WEAPONDMG", "damage": "WEAPONDMG", "melee damage": "WEAPONDMG",
    "crit rating": "CRIT", "spell crit rating": "SPELLCRIT", "spell critical": "SPELLCRIT",
    "hp": "HP", "mp": "MANA", "mana restored per 5 seconds": "MP5",
    "resist all": "ALLRES",
    "fire resist": "FIRERES", "frost resist": "FROSTRES", "nature resist": "NATURERES",
    "shadow resist": "SHADOWRES", "arcane resist": "ARCANERES", "holy resist": "HOLYRES",
    # School-locked spell damage is real but only pays for one school, so it
    # gets its own key and the role weights discount it.
    "fire spell damage": "SP_FIRE", "frost spell damage": "SP_FROST",
    "shadow spell damage": "SP_SHADOW", "arcane spell damage": "SP_ARCANE",
    "holy spell damage": "SP_HOLY", "nature spell damage": "SP_NATURE",
    # Creature-type damage is situational to the point of being scenery
    "attack power vs undead": "AP_UNDEAD",
    "attack power vs undead and demons": "AP_UNDEAD",
    "spell damage vs undead": "SP_UNDEAD",
    "beastslaying": "BEASTSLAYING", "elemental slayer": "ELEMSLAYER",
    "fishing": "FISHING", "fishing lure": "FISHING",
    "threat": "THREAT", "stealth": "STEALTH",
    "fishing skill": "FISHING", "mining": "MINING", "herbalism": "HERBALISM",
    "skinning": "SKINNING",
}

# "+18 Healing and Spell Damage" is eighteen of each; "+33 Healing and +11
# Spell Damage" is not. The difference is the second plus sign, so the split
# has to happen on "and +" and on "and <digit>", never on a bare "and".
SPLIT = re.compile(r"\s*/\s*|\s*,\s*|\s*&\s*|\s+and\s+(?=[+\d])|\s*\+(?=\d)")
# "Sharpened (+14 Crit Rating and +12 Damage)" — the label outside the
# parentheses is the buff's NAME, and everything that matters is inside.
LABELLED = re.compile(r"^[^(+\d]*\((.+)\)\s*$")
CHUNK = re.compile(r"^\s*\+?(\d+)\s+(.+?)[.\s]*$")
COMPOUND = re.compile(r"\s+and\s+")
# Tails that are prose, not stats. They ride along after an "and" and would
# otherwise be counted as vocabulary we failed to learn.
PROSE = {
    "minor run speed increase", "demons", "undead", "chance to stun target",
    "chance to restore health on hit", "chance to restore mana on spellcast",
}


def parse_stats(short):
    """Display string -> { STAT: amount }. Unrecognised phrases yield nothing."""
    if not short:
        return None, 0, 0
    labelled = LABELLED.match(short)
    if labelled:
        short = labelled.group(1)
    out, hit, miss = {}, 0, 0
    for chunk in SPLIT.split(short):
        chunk = chunk.strip()
        if not chunk:
            continue
        m = CHUNK.match(chunk)
        if not m:
            continue
        amount, phrase = int(m.group(1)), m.group(2).strip().lower()
        phrase = re.sub(r"\s+", " ", phrase.rstrip(".").strip())
        names = [p.strip() for p in COMPOUND.split(phrase)] if COMPOUND.search(phrase) else [phrase]
        for name in names:
            if name in PROSE:
                continue
            key = STAT_NAMES.get(name)
            if not key:
                # "+12 Spell Damage and Healing" splits to a bare "healing";
                # "+20 Arcane Resistance" is already exact. Anything left is a
                # phrase worth knowing about.
                miss += 1
                continue
            hit += 1
            if key == "ALLSTATS":
                for stat in ("STA", "AGI", "STR", "INT", "SPI"):
                    out[stat] = out.get(stat, 0) + amount
            elif key == "ALLRES":
                for stat in ("FIRERES", "FROSTRES", "NATURERES", "SHADOWRES", "ARCANERES"):
                    out[stat] = out.get(stat, 0) + amount
            else:
                out[key] = out.get(key, 0) + amount
    return (out or None), hit, miss


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------
MAX_SOURCES = 6


def craft_sources(cl, world, item_id, seen_recipes=None):
    """How the item is made, and how the recipe that makes it is obtained."""
    out = []
    for spell in cl.creator_of_item.get(item_id, []):
        prof = cl.profession(spell)
        rec = {"k": "CRAFT", "spell": spell, "name": cl.spell_name.get(spell)}
        if prof:
            rec["prof"] = prof
        reagents = cl.reagents.get(spell)
        if reagents:
            rec["reagents"] = [{"item": i, "count": c, "name": cl.item_name(i)}
                               for i, c in reagents]
        rec["learn"] = learn_sources(cl, world, spell)
        out.append(rec)
    return out


def learn_sources(cl, world, spell):
    """Trainer taught, or a recipe item — and where THAT comes from.

    The client sometimes carries two recipe items with the same name for one
    craft (Design: Relentless Earthstorm Diamond is both 32412 and 33622), and
    only one of them is on a shelf. Listing both would print the same line
    twice with different answers, so the best-sourced one speaks for the name.
    """
    out = list(world.trainers(spell)[:MAX_SOURCES])
    best = {}
    for item in cl.recipe_items(spell):
        name = cl.item_name(item)
        src = world.item_sources(item)
        prior = best.get(name)
        if prior and len(prior[1]) >= len(src):
            continue
        best[name] = (item, src)
    for name, (item, src) in best.items():
        rec = {"k": "RECIPE", "item": item, "name": name, "src": trim(src)}
        if len(src) > MAX_SOURCES:
            rec["more"] = len(src) - MAX_SOURCES
        out.append(rec)
    return out


def source_weight(s):
    """Best-first: a named vendor beats a 0.1% world drop."""
    order = {"VENDOR": 0, "TRAINER": 1, "QUEST": 2, "CRAFT": 3, "DROP": 4,
             "OBJECT": 5, "CONTAINER": 6, "RECIPE": 7, "PROSPECT": 8,
             "DISENCHANT": 9, "FISH": 10, "SKIN": 11, "PICKPOCKET": 12, "MAIL": 13}
    return (order.get(s["k"], 99), -(s.get("chance") or 0))


def trim(sources):
    return sorted(sources, key=source_weight)[:MAX_SOURCES]


def era_of(cl, item_id, spell_id, prof):
    """VANILLA or TBC.

    ItemSparse.ExpansionID is no help — this client stamps 254 on 30,025 of its
    30,128 items. What does separate the eras cleanly is the skill ceiling
    (vanilla professions stopped at 300) and, for things no profession makes,
    the level TBC content sits above.
    """
    if prof and prof.get("rank"):
        return "TBC" if prof["rank"] > 300 else "VANILLA"
    row = cl.item.get(item_id) if item_id else None
    if row is not None:
        if _int(row["RequiredLevel"]) >= 58 or _int(row["ItemLevel"]) >= 60:
            return "TBC"
    return "VANILLA"


TAGS = re.compile(r"\$[a-zA-Z0-9]+|\|4[^;]*;|\s+")


BOILERPLATE = re.compile(
    r"\s*Does not stack with other enchantments for the selected equipment slot\.",
    re.I)


def clean_desc(text):
    if not text:
        return None
    text = BOILERPLATE.sub("", text)
    text = TAGS.sub(lambda m: " " if m.group(0).isspace() else "", text)
    return text.strip() or None


def build():
    world = WorldDB()
    cl = Client(world)
    entries = []

    def add(entry):
        entries.append(entry)

    # --- 1. every enchant the client can apply -----------------------------
    for table, kind_default in ((cl.perm, "ENCHANT"), (cl.temp, "TEMP")):
        for spell, ench_id in sorted(table.items()):
            name = cl.spell_name.get(spell)
            ench = cl.ench.get(ench_id)
            if not name or not ench or JUNK.search(name):
                continue
            short = ench["Name_lang"]
            if short and JUNK.search(short):
                continue
            prof = cl.profession(spell)
            carriers = [i for i in cl.spell_items.get(spell, [])
                        if cl.item.get(i) and not JUNK.search(cl.item_name(i) or "")]
            slots = cl.slots_for_spell(spell)
            item_id = carriers[0] if carriers else None
            row = cl.item.get(item_id) if item_id else None

            kind = kind_default
            if kind == "ENCHANT" and item_id:
                kind = carrier_kind(cl, item_id, slots)

            src = []
            if item_id:
                src += world.item_sources(item_id)
                src += craft_sources(cl, world, item_id)
            elif prof:
                src += [{"k": "CRAFT", "spell": spell, "prof": prof,
                         "reagents": [{"item": i, "count": c, "name": cl.item_name(i)}
                                      for i, c in cl.reagents.get(spell, [])] or None,
                         "learn": learn_sources(cl, world, spell)}]

            if not src:
                # No item, no profession — but a class may still teach it.
                # The shaman's weapon imbues live here, and a shaman's weapon
                # is not "unenhanced" just because nothing was consumed.
                taught = world.trainers(spell)
                if taught:
                    src = [{"k": "TRAINER", **t} if False else t for t in taught]
                    kind = "TEMP"
            if not src and not prof:
                continue          # nothing in TBC hands this to a player

            add({
                "ench": ench_id, "spell": spell, "item": item_id,
                "name": (cl.item_name(item_id) if item_id else name),
                "recipe": name if (item_id and name != cl.item_name(item_id)) else None,
                "short": short,
                "stats": parse_stats(short)[0],
                "note": clean_desc(cl.spell_desc.get(spell)),
                "slots": slots or ["OTHER"],
                "cls": cl.equip_filter(spell)[0],
                "sub": cl.equip_filter(spell)[1],
                "kind": kind,
                "prof": prof,
                "quality": _int(row["OverallQualityID"]) if row is not None else None,
                "lvl": _int(row["RequiredLevel"]) if row is not None else None,
                # the minimum item level the target must be, which the client
                # enforces and the tooltip prints as "requires a level N item"
                "ilvl": _int(cl.levels.get(spell, {}).get("BaseLevel", 0)) or None,
                "era": era_of(cl, item_id, spell, prof),
                "classes": classes_of(row["AllowableClass"]) if row is not None else None,
                "bind": _int(row["Bonding"]) if row is not None else None,
                "reqSkill": cl.req_skill(item_id) if item_id else None,
                "unique": cl.unique_of(item_id, world) if item_id else None,
                "src": trim(src),
                "more": max(0, len(src) - MAX_SOURCES) or None,
            })

    # --- 2. gems ------------------------------------------------------------
    for iid, row in cl.item.items():
        cls = cl.item_cls.get(iid)
        if not cls or _int(cls["ClassID"]) != 3:
            continue
        name = row["Display_lang"]
        if not name or JUNK.search(name):
            continue
        gp = cl.gem_props.get(_int(row["Gem_properties"]))
        if not gp:
            continue
        ench_id = _int(gp["Enchant_ID"])
        ench = cl.ench.get(ench_id)
        colors = [c for bit, c in GEM_COLORS if _int(gp["Type"]) & bit]
        if not colors:
            continue   # "fits into a tonk Overdrive socket" — not player gear
        color = colors[0]
        clauses, cond_text = decode_condition(
            cl.ench_cond.get(_int(ench["Condition_ID"])) if ench else None)
        src = world.item_sources(iid) + craft_sources(cl, world, iid)
        add({
            "ench": ench_id, "spell": None, "item": iid, "name": name,
            "short": ench["Name_lang"] if ench else None,
            "stats": parse_stats(ench["Name_lang"] if ench else None)[0],
            "slots": ["GEM"], "kind": "GEM", "color": color, "colors": colors,
            "cond": clauses, "condText": cond_text,
            "prof": None, "ilvl": None,
            "quality": _int(row["OverallQualityID"]),
            "lvl": _int(row["RequiredLevel"]) or None,
            "era": era_of(cl, iid, None, None),
            "classes": classes_of(row["AllowableClass"]),
            "bind": _int(row["Bonding"]),
            "reqSkill": cl.req_skill(iid),
            "unique": cl.unique_of(iid, world),
            "src": trim(src),
            "more": max(0, len(src) - MAX_SOURCES) or None,
        })

    # A crafted carrier (Nethercleft Leg Armor, Adamantite Sharpening Stone)
    # has no profession of its own — the profession is on the craft source.
    # Lift it so "who makes this" is one field everywhere.
    for e in entries:
        if not e["src"]:
            e["unobtainable"] = True
        if not e.get("prof"):
            for s in e["src"]:
                if s["k"] == "CRAFT" and s.get("prof"):
                    e["prof"] = s["prof"]
                    break

    return cl, world, entries


def carrier_kind(cl, item_id, slots):
    """Name the family a carrier item belongs to, the way a player would."""
    name = (cl.item_name(item_id) or "").lower()
    for needle, kind in (("armor kit", "KIT"), ("leg armor", "LEG_ARMOR"),
                         ("spellthread", "SPELLTHREAD"), ("scope", "SCOPE"),
                         ("weapon chain", "CHAIN"), ("counterweight", "CHAIN"),
                         ("shield spike", "SPIKE"), ("spurs", "SPURS"),
                         ("inscription", "INSCRIPTION"), ("arcanum", "ARCANUM"),
                         ("glyph", "GLYPH")):
        if needle in name:
            return kind
    if "HEAD" in slots:
        return "ARCANUM"
    if "SHOULDER" in slots:
        return "INSCRIPTION"
    return "ITEM"


# ---------------------------------------------------------------------------
# Lua emission
# ---------------------------------------------------------------------------
# One source record per line reads fine and costs a third of what a fully
# exploded table costs on disk.
INLINE = 400


def lua_str(s):
    return '"%s"' % str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\n", " ")


def lua_val(v, indent=0):
    pad = " " * indent
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        if not v:
            return "nil"
        inner = ", ".join(lua_val(x, indent) for x in v)
        if len(inner) < INLINE:
            return "{ %s }" % inner
        parts = ["\n%s    %s," % (pad, lua_val(x, indent + 4)) for x in v]
        return "{%s\n%s}" % ("".join(parts), pad)
    if isinstance(v, dict):
        items = [(k, x) for k, x in v.items() if x is not None and x != [] and x != {}]
        if not items:
            return "nil"
        inner = ", ".join("%s = %s" % (k, lua_val(x, indent)) for k, x in items)
        if len(inner) < INLINE:
            return "{ %s }" % inner
        parts = ["\n%s    %s = %s," % (pad, k, lua_val(x, indent + 4)) for k, x in items]
        return "{%s\n%s}" % ("".join(parts), pad)
    raise TypeError(type(v))


HEADER = '''-- Commander Quartermaster — the item-enhancement database.
-- GENERATED by Harness/build_enhancements.py from the client's own tables for
-- build %s (wago.tools DB2) married to the CMaNGOS TBC world database.
-- DO NOT HAND-EDIT: rerun the generator instead, or the next run silently
-- reverts you.
--
-- The universe is not a curated list. It is every spell in the client with an
-- ENCHANT_ITEM or ENCHANT_ITEM_TEMPORARY effect, plus every gem item — so an
-- enhancement cannot be missing unless the client cannot apply it.
--
-- Shape:
--   Entries[i] = {
--       ench    = SpellItemEnchantment id — the number an item LINK carries,
--                 which is how an equipped item is identified as enchanted
--       spell   = the spell that applies it (nil for gems)
--       item    = the item you consume to apply it (nil for enchanter-cast)
--       name    = what you look for (item name, or the enchant's spell name)
--       recipe  = the enchant's own name when `name` is the carrier item
--       short   = the green line the enchant prints on the gear
--       slots   = { "HEAD", ... } — every slot it may land on
--       kind    = ENCHANT | GLYPH | ARCANUM | INSCRIPTION | KIT | LEG_ARMOR |
--                 SPELLTHREAD | SCOPE | CHAIN | SPIKE | SPURS | GEM | TEMP
--       prof    = { skill, skillID, rank } when a profession applies it
--       src     = every way to obtain it, best first (see SourceKinds)
--       more    = sources beyond the %d kept
--   }
--
-- Source records carry whatever the world DB knows: vendor npc + zone + price
-- + reputation gate + token cost, drop npc + zone + rank + chance, quest +
-- giver + side, craft profession + rank + reagents + how the recipe is learned.

CommanderQuartermasterEnhanceData = {
    Build = %s,
    SlotOrder = %s,
    SlotNames = %s,
    SourceKinds = { "VENDOR", "TRAINER", "QUEST", "CRAFT", "RECIPE", "DROP",
                    "OBJECT", "CONTAINER", "PROSPECT", "DISENCHANT", "FISH",
                    "SKIN", "PICKPOCKET", "MAIL" },
    Entries = {
'''


def emit(entries):
    slot_names = "{\n" + "".join(
        "        %s = %s,\n" % (k, lua_str(SLOT_NAMES[k])) for k in SLOT_ORDER) + "    }"
    out = [HEADER % (BUILD, MAX_SOURCES, lua_str(BUILD),
                     lua_val(SLOT_ORDER), slot_names)]
    for e in sorted(entries, key=lambda e: (SLOT_ORDER.index(e["slots"][0])
                                            if e["slots"][0] in SLOT_ORDER else 99,
                                            -(e.get("lvl") or 0), e["name"] or "")):
        out.append("        %s,\n" % lua_val(e, 8))
    out.append("    },\n}\n")
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="summarise, do not write")
    args = ap.parse_args()

    cl, world, entries = build()
    by_slot = defaultdict(int)
    by_kind = defaultdict(int)
    sourceless = []
    for e in entries:
        by_slot[e["slots"][0]] += 1
        by_kind[e["kind"]] += 1
        if not e["src"]:
            sourceless.append(e)
    sys.stderr.write("entries: %d\n" % len(entries))
    for k in SLOT_ORDER:
        if by_slot.get(k):
            sys.stderr.write("  %-10s %4d\n" % (k, by_slot[k]))
    sys.stderr.write("kinds: %s\n" % dict(sorted(by_kind.items())))
    with_stats = sum(1 for e in entries if e.get("stats"))
    phrases = defaultdict(int)
    for e in entries:
        _, _, miss = parse_stats(e.get("short"))
        if miss:
            phrases[e.get("short")] += 1
    sys.stderr.write("stats parsed for %d/%d entries; %d display strings have a phrase we do not know\n"
                     % (with_stats, len(entries), len(phrases)))
    for phrase in list(phrases)[:15]:
        sys.stderr.write("    ? %s\n" % phrase)
    sys.stderr.write("no source at all: %d\n" % len(sourceless))
    for e in sourceless[:20]:
        sys.stderr.write("    %s (%s)\n" % (e["name"], e["ench"]))
    if args.report:
        return
    text = emit(entries)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    sys.stderr.write("wrote %s (%d lines)\n" % (OUT, text.count("\n")))


if __name__ == "__main__":
    main()
