#!/usr/bin/env python3
"""Generate ../CommanderSpellbookData.lua for Commander_Spellbook.

    python3 make_spellbook_data.py <cache-dir>

<cache-dir> is Commander_Quartermaster/Harness/.cache: the client's DB2 tables for
this build as CSV from wago.tools (see BUILD and DB2_TABLES) and the CMaNGOS TBC
world DB, staged as tbcdb.sqlite (trainers, spawns, quests) next to the dump it was
made from, tbcdb.sql.gz (read here only for the `conditions` table, which the
SQLite stage does not carry).

Where a spell comes from: the class trainers (CMaNGOS npc_trainer / _template rows of
spawned TrainerType 0 NPCs, learn spells resolved to what they teach), talents
(Talent.db2), quest rewards (RewSpell / RewSpellCast of live quests, through learn
spells), books (ItemEffect LEARN_SPELL_ID), or SkillLineAbility's AcquireMethod 1/2
(spells a character simply has: starting spells, Auto Shot).

What it writes, per class (token as UnitClass returns it):
  chains  every rank chain the class can have in its spellbook, rank 1 first, with
          one role (decided on the HIGHEST rank, see role_of) and how rank 1 is
          learned (src: T trainer, L talent, Q quest reward, O other -- a starting
          spell or something none of the three teaches)
  train   what the class trainers teach: spellID = { level, cost[, raceMask] }
and, for everyone, `general` (the General-tab spells by group) and `weapons` (the
weapon skills the weapon masters teach, who teaches them, where they stand).

Hand corrections live in the MANUAL_* tables just below, one line of reason each.
The report printed at the end is the list to look at by hand: rank-order
mismatches, spells left out, chains left as UTILITY by default, and a cross-check
against the third-party What's Training? data beside us (read only, never copied).
"""
import sys, os, csv, collections, sqlite3, gzip, re

if len(sys.argv) < 2:
    sys.exit(__doc__)
CACHE = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.dirname(HERE)
ADDONS = os.path.dirname(ADDON)
OUT = os.path.join(ADDON, "CommanderSpellbookData.lua")
WT_DIR = os.path.join(ADDONS, "WhatsTraining", "Classes")

# The DB2 build the cached CSVs were fetched for (the Quartermaster cache, Aug 2026);
# the tables this generator added to that cache were fetched for the same build.
BUILD = "2.5.6.68941"
DB2_TABLES = ["SkillLine", "SkillLineAbility", "SkillRaceClassInfo", "Spell", "SpellName", "SpellMisc",
              "SpellDuration", "SpellLevels", "SpellEffect", "SpellCategories", "SpellAuraOptions", "Talent",
              "ChrClasses", "ChrRaces", "CharBaseInfo", "FactionTemplate", "UiMap", "UiMapAssignment",
              "ItemSparse", "ItemEffect"]

# ---------------------------------------------------------------------------
# Hand corrections
# ---------------------------------------------------------------------------
# Role by chain (keyed by the chain's rank-1 spell id). The rules in role_of read
# effects and aura types; these are the spells whose point the effects do not say.
MANUAL_ROLE = {
    # WARRIOR
    694: "UTILITY",     # Mocking Blow -- a taunt; the damage is incidental (Taunt is UTILITY too)
    1715: "CONTROL",    # Hamstring -- the point is the slow; the damage is token
    3411: "DEFENSE",    # Intervene -- charges to an ally and takes the next attack meant for them
    5308: "DAMAGE",     # Execute -- a dummy effect: the damage is scripted
    12328: "DAMAGE",    # Sweeping Strikes -- extra hits on a second target
    12975: "DEFENSE",   # Last Stand -- temporary health (a dummy effect)
    20230: "DEFENSE",   # Retaliation -- counterattacks every melee hit for 15 s
    23920: "DEFENSE",   # Spell Reflection -- reflects the next spell (aura 28, outside the rule's list)
    29801: "DAMAGE",    # Rampage -- attack power stacked after a crit
    # PALADIN
    1044: "DEFENSE",    # Blessing of Freedom -- immunity to movement impairment on an ally: a defensive
    6940: "DEFENSE",    # Blessing of Sacrifice -- redirects an ally's damage to the paladin
    19752: "UTILITY",   # Divine Intervention -- sacrifices the paladin to keep one ally out of a wipe
    20164: "CONTROL",   # Seal of Justice -- the seal's point is the stun on hit
    20165: "HEAL",      # Seal of Light -- heals the paladin on hit
    20166: "UTILITY",   # Seal of Wisdom -- mana on hit
    20375: "DAMAGE",    # Seal of Command -- extra holy damage on hit (a proc aura the rules do not read)
    21084: "DAMAGE",    # Seal of Righteousness -- holy damage on every swing (a dummy aura)
    31801: "DAMAGE",    # Seal of Vengeance -- a stacking holy DoT on hit
    31892: "DAMAGE",    # Seal of Blood -- extra damage on hit
    20271: "DAMAGE",    # Judgement -- releases the seal on the target (a script effect)
    348700: "DAMAGE",   # Seal of the Martyr -- the Alliance's Seal of Blood (TBC Classic)
    348704: "DAMAGE",   # Seal of Corruption -- the Horde's Seal of Vengeance (TBC Classic)
    20473: "HEAL",      # Holy Shock -- a dummy that heals an ally or damages an enemy; the lead's call: HEAL
    20216: "HEAL",      # Divine Favor -- the next heal crits
    31842: "HEAL",      # Divine Illumination -- halves the cost of spells for 15 s, Holy's healing cooldown
    # HUNTER
    781: "DEFENSE",     # Disengage -- drops threat
    1499: "CONTROL",    # Freezing Trap -- a trap object; the freeze is on the trap's own spell
    13809: "CONTROL",   # Frost Trap -- a trap object; the slowing ice is on the trap's own spell
    13795: "DAMAGE",    # Immolation Trap -- a trap object that burns
    13813: "DAMAGE",    # Explosive Trap -- a trap object that burns
    34600: "DAMAGE",    # Snake Trap -- a trap object whose snakes bite and poison
    2974: "CONTROL",    # Wing Clip -- the point is the slow
    5384: "DEFENSE",    # Feign Death -- drops combat and threat (a six-minute aura, so no duration rule fits)
    19506: "BUFF",      # Trueshot Aura -- a party attack-power aura, not a stance (the lead's call)
    19577: "CONTROL",   # Intimidation -- the pet's stun
    34026: "DAMAGE",    # Kill Command -- the pet's bonus attack: a damage button
    34477: "UTILITY",   # Misdirection -- hands threat to an ally
    # ROGUE
    703: "DAMAGE",      # Garrote -- a bleed; only the top rank adds the 3-second silence
    1966: "DEFENSE",    # Feint -- drops threat
    5938: "DAMAGE",     # Shiv -- a strike that applies the off-hand poison
    13750: "DAMAGE",    # Adrenaline Rush -- energy regeneration for 15 s, an offensive cooldown
    14177: "DAMAGE",    # Cold Blood -- the next ability crits
    14183: "DAMAGE",    # Premeditation -- combo points for the opener
    36554: "UTILITY",   # Shadowstep -- teleports behind the target (mobility, not an escape)
    # PRIEST
    724: "HEAL",        # Lightwell -- summons a Lightwell that heals whoever clicks it
    13896: "DEFENSE",   # Feedback -- a self aura that burns the mana of whoever casts at the priest
    15237: "HEAL",      # Holy Nova -- the rank spells carry the damage, the heal is a triggered spell; healing reads better for a priest
    15286: "HEAL",      # Vampiric Embrace -- a debuff whose point is healing the party from shadow damage
    32548: "UTILITY",   # Symbol of Hope -- party mana over 15 s, not a lasting buff (like Mana Tide)
    33076: "HEAL",      # Prayer of Mending -- dummy effects; the heal is scripted on each bounce
    # SHAMAN
    974: "HEAL",        # Earth Shield -- heals the target when struck (a proc aura)
    8017: "BUFF",       # Rockbiter Weapon -- a weapon imbue like Flametongue, Frostbrand and Windfury
    16166: "DAMAGE",    # Elemental Mastery -- the next spell crits for free
    16188: "HEAL",      # Nature's Swiftness -- Restoration talent; the instant cast is for a heal
    # Totems: the totem's work is on the totem creature's own spell, so each by what it does
    1535: "DAMAGE",     # Fire Nova Totem
    2062: "DEFENSE",    # Earth Elemental Totem -- a taunting elemental that soaks the fight
    2484: "CONTROL",    # Earthbind Totem
    2894: "DAMAGE",     # Fire Elemental Totem
    3599: "DAMAGE",     # Searing Totem
    3738: "BUFF",       # Wrath of Air Totem
    5394: "HEAL",       # Healing Stream Totem
    5675: "BUFF",       # Mana Spring Totem
    5730: "DEFENSE",    # Stoneclaw Totem -- draws attacks onto itself
    6495: "UTILITY",    # Sentry Totem
    8071: "BUFF",       # Stoneskin Totem
    8075: "BUFF",       # Strength of Earth Totem
    8143: "UTILITY",    # Tremor Totem
    8166: "UTILITY",    # Poison Cleansing Totem
    8170: "UTILITY",    # Disease Cleansing Totem
    8177: "UTILITY",    # Grounding Totem
    8181: "BUFF",       # Frost Resistance Totem
    8184: "BUFF",       # Fire Resistance Totem
    8190: "DAMAGE",     # Magma Totem
    8227: "BUFF",       # Flametongue Totem
    8512: "BUFF",       # Windfury Totem
    8835: "BUFF",       # Grace of Air Totem
    10595: "BUFF",      # Nature Resistance Totem
    15107: "BUFF",      # Windwall Totem
    16190: "UTILITY",   # Mana Tide Totem -- party mana over 12 s (like Symbol of Hope)
    25908: "BUFF",      # Tranquil Air Totem
    30706: "BUFF",      # Totem of Wrath
    # MAGE
    66: "DEFENSE",      # Invisibility -- fades out of sight and threat: an escape
    11129: "DAMAGE",    # Combustion -- stacking fire crit
    12043: "DAMAGE",    # Presence of Mind -- the next spell is instant
    # WARLOCK
    126: "UTILITY",     # Eye of Kilrogg -- a scouting eye, not a pet
    1098: "PET",        # Subjugate (Enslave) Demon -- takes a demon as a temporary pet
    1122: "PET",        # Inferno -- summons an Infernal
    18540: "PET",       # Ritual of Doom -- summons a Doomguard
    18708: "PET",       # Fel Domination -- speeds the next demon summon
    18220: "UTILITY",   # Dark Pact -- drains the pet's mana for the warlock: a mana tool
    29858: "DEFENSE",   # Soulshatter -- drops threat
    # DRUID
    8998: "DEFENSE",    # Cower -- drops threat
    16689: "CONTROL",   # Nature's Grasp -- roots whoever strikes the druid
    17116: "HEAL",      # Nature's Swiftness -- Restoration talent; the instant cast is for a heal
    22842: "DEFENSE",   # Frenzied Regeneration -- rage into health in bear form: a survival cooldown
}

# Spells the trainer rows and talents cannot place, for each class: added to the
# chain candidates (or removed) by hand.
MANUAL_CHAIN_ADD = {
    # Teleport: Moonglade: "Requires level 10" (nether.wowhead.com tooltip, dataEnv 5); its learn
    # spell 19027 is on no CMaNGOS trainer or quest row, so nothing above finds it
    "DRUID": [18960],
}
MANUAL_CHAIN_DROP = {}

# Trainer rows the world DB has wrong or lacks: (class, spell) -> {field: value}.
# "like" copies another spell's trainer cost; the races then come from
# SkillLineAbility's race mask alone.
MANUAL_TRAIN = {
    # Seal of the Martyr / Seal of Corruption: TBC Classic's cross-faction copies of Seal of Blood and
    # Seal of Vengeance, absent from the CMaNGOS (original TBC) trainers. "Requires level 70"
    # (nether.wowhead.com tooltip, dataEnv 5; SpellLevels.db2 70); priced like the seal each copies;
    # SkillLineAbility gives Martyr to Human/Dwarf/Draenei and Corruption to Blood Elf
    ("PALADIN", 348700): {"like": 31892, "level": 70},
    ("PALADIN", 348704): {"like": 31801, "level": 70},
    # Searing Totem rank 7: "Requires level 69" (nether.wowhead.com tooltip; SpellLevels.db2 69);
    # every CMaNGOS shaman trainer row says 70
    ("SHAMAN", 25533): {"level": 69},
}

# Trainers on a zone's rim that the box rule gives to the neighbour: npc -> uiMapID
MANUAL_PLACE_IN = {
    17005: 1941,    # Duelist Larenis -- Falconwing Square, Eversong Woods; the Silvermoon City box reaches
                    # over it, and the rule put her at Silvermoon 38.6, 76.9, outside the city walls
}

# ---------------------------------------------------------------------------
# DB2
# ---------------------------------------------------------------------------
def C(name):
    """One DB2 table (a DB2_TABLES name) as a list of row dicts."""
    path = os.path.join(CACHE, name + ".csv")
    if not os.path.exists(path):
        sys.exit("missing %s -- fetch https://wago.tools/db2/%s/csv?build=%s into %s" % (path, name, BUILD, CACHE))
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))

_missing = [t for t in DB2_TABLES if not os.path.exists(os.path.join(CACHE, t + ".csv"))]
if _missing:
    sys.exit("missing in %s: %s -- fetch each from https://wago.tools/db2/<Table>/csv?build=%s" % (
        CACHE, ", ".join(_missing), BUILD))

def I(v):
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0

spellName = {I(r["ID"]): r["Name_lang"] for r in C("SpellName")}
rankText = {I(r["ID"]): r["NameSubtext_lang"] for r in C("Spell")}
misc = {}
for r in C("SpellMisc"):
    if I(r["DifficultyID"]) == 0:
        misc[I(r["SpellID"])] = r
durations = {I(r["ID"]): I(r["Duration"]) for r in C("SpellDuration")}
effects = collections.defaultdict(list)
for r in C("SpellEffect"):
    if I(r["DifficultyID"]) == 0:
        effects[I(r["SpellID"])].append(r)
for s in effects:
    effects[s].sort(key=lambda e: I(e["EffectIndex"]))
categories = {I(r["SpellID"]): r for r in C("SpellCategories") if I(r["DifficultyID"]) == 0}
spellLevel = {I(r["SpellID"]): I(r["SpellLevel"]) for r in C("SpellLevels") if I(r["DifficultyID"]) == 0}
procCharges = {I(r["SpellID"]): I(r["ProcCharges"]) for r in C("SpellAuraOptions") if I(r["DifficultyID"]) == 0}
skillLine = {I(r["ID"]): r for r in C("SkillLine")}
sla = C("SkillLineAbility")
srci = C("SkillRaceClassInfo")
talents = C("Talent")
classes = {I(r["ID"]): r["Filename"] for r in C("ChrClasses")}
races = {I(r["ID"]): r for r in C("ChrRaces")}
classRaces = collections.defaultdict(set)
for r in C("CharBaseInfo"):
    classRaces[I(r["ClassID"])].add(I(r["RaceID"]))
factionTemplate = {I(r["ID"]): r for r in C("FactionTemplate")}
uimap = {I(r["ID"]): r for r in C("UiMap")}
assign = C("UiMapAssignment")

def bit(n):
    return 1 << (n - 1)

PLAYABLE = sorted({rc for s in classRaces.values() for rc in s})
ALL_RACES = sum(bit(r) for r in PLAYABLE)
ALLIANCE = sum(bit(r) for r in PLAYABLE if I(races[r]["Alliance"]) == 0)
HORDE = sum(bit(r) for r in PLAYABLE if I(races[r]["Alliance"]) == 1)
CLASS_RACES = {c: sum(bit(r) for r in rs) for c, rs in classRaces.items()}
TOKEN_ID = {tok: cid for cid, tok in classes.items()}

def race_names(mask):
    return ", ".join(races[r]["Name_lang"] for r in PLAYABLE if mask & bit(r))

def attr0(s):
    return I(misc.get(s, {}).get("Attributes_0"))

def is_passive(s):
    return bool(attr0(s) & 0x40)

def is_hidden(s):
    # SPELL_ATTR0_DO_NOT_DISPLAY: the client keeps it out of the spellbook
    # (talent passives, armour and weapon proficiencies, languages, riding)
    return bool(attr0(s) & 0x80)

def duration(s):
    m = misc.get(s)
    if not m or not I(m["DurationIndex"]):
        return 0
    return durations.get(I(m["DurationIndex"]), 0)

def name_of(s):
    return spellName.get(s) or ""

def label(s):
    rt = rankText.get(s) or ""
    return "%s (%s)" % (name_of(s), rt) if rt else name_of(s)

JUNK = re.compile(r"\(OLD\)|^OLD |\bDND\b|\bTEST\b|\bTest\b|^zz|\[PH\]|UNUSED|\bNYI\b|DEPRECATED|\(DEP\)|QAEnabled")

def junk(s):
    n = name_of(s)
    return not n or bool(JUNK.search(n))

RANK_RE = re.compile(r"^Rank (\d+)$")

def rank_no(s):
    m = RANK_RE.match(rankText.get(s) or "")
    return int(m.group(1)) if m else None

# Learn spells: a spell made only of LEARN_SPELL (36) effects (and the SKILL_STEP
# (44) a mount quest's learn spell adds) teaches its targets
learnTeaches = {}
for s, effs in effects.items():
    codes = {I(e["Effect"]) for e in effs}
    if 36 in codes and codes <= {36, 44}:
        learnTeaches[s] = [I(e["EffectTriggerSpell"]) for e in effs if I(e["Effect"]) == 36 and I(e["EffectTriggerSpell"])]

def resolve_learn(s, depth=0):
    if s in learnTeaches and depth < 4:
        out = []
        for t in learnTeaches[s]:
            out += resolve_learn(t, depth + 1)
        return out
    return [s]

# Books: an item whose LEARN_SPELL_ID (TriggerType 6) effect teaches a spell
itemNames = {I(r["ID"]): r["Display_lang"] for r in C("ItemSparse")}
itemTeaches = collections.defaultdict(list)   # spell -> [item]
for r in C("ItemEffect"):
    if I(r["TriggerType"]) == 6 and I(r["ParentItemID"]) in itemNames and not JUNK.search(itemNames[I(r["ParentItemID"])]):
        for s in resolve_learn(I(r["SpellID"])):
            itemTeaches[s].append(I(r["ParentItemID"]))


# ---------------------------------------------------------------------------
# World DB (CMaNGOS TBC)
# ---------------------------------------------------------------------------
db = sqlite3.connect(os.path.join(CACHE, "tbcdb.sqlite"))
db.row_factory = sqlite3.Row
def Q(sql, *args):
    return [dict(r) for r in db.execute(sql, args)]

creature = {r["Entry"]: r for r in Q("select * from creature_template")}
spawns = collections.defaultdict(list)
for r in Q("select guid, id, map, position_x, position_y from creature order by guid"):
    spawns[r["id"]].append((r["map"], r["position_x"], r["position_y"]))
trainerTemplate = collections.defaultdict(list)
for r in Q("select * from npc_trainer_template order by entry, spell"):
    trainerTemplate[r["entry"]].append(r)
trainerDirect = collections.defaultdict(list)
for r in Q("select * from npc_trainer order by entry, spell"):
    trainerDirect[r["entry"]].append(r)

def read_conditions():
    """The `conditions` table from the SQL dump (the SQLite stage leaves it out),
    parsed with Commander_Formulary's no-database reader."""
    sys.path.insert(0, os.path.join(ADDONS, "Commander_Formulary", "Harness"))
    import cmangos
    prefix = "INSERT INTO `conditions` VALUES "
    cols, rows = None, {}
    with gzip.open(os.path.join(CACHE, "tbcdb.sql.gz"), "rt", encoding="utf8", errors="replace") as f:
        create = []
        grabbing = False
        for line in f:
            if line.startswith("CREATE TABLE `conditions`"):
                grabbing = True
            if grabbing:
                create.append(line)
                if line.startswith(") ENGINE"):
                    grabbing = False
                    cols = cmangos._columns("".join(create), "conditions")
            elif line.startswith(prefix):
                for t in cmangos._tuples(line[len(prefix):]):
                    r = dict(zip(cols, t))
                    rows[r["condition_entry"]] = r
    return rows

conditions = read_conditions()

def cond_races(cid, depth=0):
    """The races a trainer row's condition admits (a mask), from player-race
    (14) and team (6) conditions and their AND (-1) / OR (-2) combinations.
    Anything else admits every race (it is not a race gate)."""
    if not cid:
        return ALL_RACES
    c = conditions.get(cid)
    if not c or depth > 6:
        return ALL_RACES
    t = c["type"]
    if t == 14:
        return c["value1"] & ALL_RACES
    if t == 6:
        return ALLIANCE if c["value1"] == 469 else HORDE if c["value1"] == 67 else ALL_RACES
    if t == -1:
        return cond_races(c["value1"], depth + 1) & cond_races(c["value2"], depth + 1)
    if t == -2:
        return cond_races(c["value1"], depth + 1) | cond_races(c["value2"], depth + 1)
    return ALL_RACES

def faction_of(npc):
    """Alliance / Horde / None (both) from the NPC's faction template.
    Copied from Commander_Formulary/Harness/make_formulary.py (faction_of)."""
    ft = factionTemplate.get(npc["Faction"])
    if not ft:
        return None
    enemy, group = I(ft["EnemyGroup"]), I(ft["FactionGroup"])
    if group == 2 or (enemy & 4 and not enemy & 2):
        return "Alliance"
    if group == 4 or (enemy & 2 and not enemy & 4):
        return "Horde"
    return None

FACTION_RACES = {"Alliance": ALLIANCE, "Horde": HORDE, None: ALL_RACES}

def zone_of(mapid, wx, wy, prefer=None):
    """uiMapID and (x, y) in 0..1 for a world position, or None.

    Copied from Commander_Formulary/Harness/make_formulary.py (zone_of), with the
    coordinates kept as fractions: a box that wholly contains another candidate
    loses to it (a city inside its zone); then, among boxes the point is at least
    ten percent from every edge of, the smallest; else the box it is deepest in."""
    hits = []
    for r in assign:
        if I(r["MapID"]) != mapid:
            continue
        u = uimap.get(I(r["UiMapID"]))
        if not u or u["Type"] != "3":
            continue
        x0, y0, x1, y1 = float(r["Region_0"]), float(r["Region_1"]), float(r["Region_3"]), float(r["Region_4"])
        if x0 <= wx <= x1 and y0 <= wy <= y1:
            px, py = (y1 - wy) / (y1 - y0), (x1 - wx) / (x1 - x0)
            hits.append({"area": (x1 - x0) * (y1 - y0), "id": I(r["UiMapID"]), "x": px, "y": py,
                         "depth": min(px, py, 1 - px, 1 - py) * 100, "rect": (x0, y0, x1, y1)})
    if prefer:
        for h in hits:
            if h["id"] == prefer:
                return (h["id"], round(h["x"], 3), round(h["y"], 3))
    def contains(outer, inner):
        return outer is not inner and outer["rect"][0] <= inner["rect"][0] and outer["rect"][1] <= inner["rect"][1] \
            and outer["rect"][2] >= inner["rect"][2] and outer["rect"][3] >= inner["rect"][3]
    hits = [h for h in hits if not any(contains(h, o) for o in hits)]
    deep = [h for h in hits if h["depth"] >= 10]
    best = min(deep, key=lambda h: h["area"]) if deep else (max(hits, key=lambda h: h["depth"]) if hits else None)
    if best:
        return (best["id"], round(best["x"], 3), round(best["y"], 3))
    return None

def place_of(entry):
    for mp, x, y in spawns.get(entry, []):
        z = zone_of(mp, x, y, MANUAL_PLACE_IN.get(entry))
        if z:
            return z
    return None

# Quests: spell -> live quests that teach it (RewSpell / RewSpellCast, through learn spells)
QUEST_JUNK = re.compile(r"^OLD |<UNUSED>|\[UNUSED\]|<NYI>|\bNYI\b|DEPRECATED|<TXT>|^ZZ|<TEST>|\[PH\]", re.I)
questStarters = set(r["quest"] for r in Q("select quest from creature_questrelation")) \
    | set(r["quest"] for r in Q("select quest from gameobject_questrelation")) \
    | set(r["startquest"] for r in Q("select startquest from item_template where startquest > 0"))
questTeaches = collections.defaultdict(list)   # spell -> [(quest, RequiredClasses, RequiredRaces)]
for q in Q("select entry, Title, RewSpell, RewSpellCast, RequiredClasses, RequiredRaces, PrevQuestId from quest_template"):
    if QUEST_JUNK.search(q["Title"] or ""):
        continue
    if q["entry"] not in questStarters and not q["PrevQuestId"]:
        continue
    for col in ("RewSpell", "RewSpellCast"):
        if q[col]:
            for s in resolve_learn(q[col]):
                questTeaches[s].append((q["entry"], q["RequiredClasses"] or 0, q["RequiredRaces"] or 0))

# ---------------------------------------------------------------------------
# Class skill lines, talents, trainers
# ---------------------------------------------------------------------------
lineClass = collections.defaultdict(int)     # class skill line -> class mask (SkillRaceClassInfo)
for r in srci:
    s = I(r["SkillID"])
    if s in skillLine and skillLine[s]["CategoryID"] == "7":
        lineClass[s] |= I(r["ClassMask"])
classLines = collections.defaultdict(set)    # class id -> its skill lines
for s, mask in lineClass.items():
    for cid in classes:
        if mask & bit(cid) and mask != -1 and bin(mask & 0xFFFF).count("1") == 1:
            classLines[cid].add(s)
# A profession-like class line (Poisons, Lockpicking: SkillLine.Flags 0x80) lists
# its crafts too; those live in a trade skill window, not in the spellbook.
def craft_line(line):
    return bool(I(skillLine[line]["Flags"]) & 0x80)

talentSpells = collections.defaultdict(set)  # class id -> talent rank spells (and what they teach)
for r in talents:
    cid = I(r["ClassID"])
    for i in range(9):
        s = I(r["SpellRank_%d" % i])
        if s:
            talentSpells[cid].add(s)
            for t in resolve_learn(s):
                talentSpells[cid].add(t)
            for e in effects.get(s, []):
                if I(e["Effect"]) == 36 and I(e["EffectTriggerSpell"]):
                    talentSpells[cid].add(I(e["EffectTriggerSpell"]))

def spawned(entry):
    return bool(spawns.get(entry))

slaBySpell = collections.defaultdict(list)
for r in sla:
    slaBySpell[I(r["Spell"])].append(r)

def class_may_learn(s, cid):
    """SkillLineAbility's ClassMask, where every row of the spell has one, names
    the classes that can learn it (the server will not teach it to another)."""
    rows = slaBySpell.get(s)
    return not rows or any(not I(r["ClassMask"]) or I(r["ClassMask"]) & bit(cid) for r in rows)

# train[cid][spell] -> {"levels": set, "costs": set, "races": mask, "trainers": set}
train = collections.defaultdict(dict)
trainNotes = collections.defaultdict(set)   # (class, spell) a trainer row offers another class
for entry, npc in sorted(creature.items()):
    if npc["TrainerType"] != 0 or not npc["TrainerClass"] or not spawned(entry):
        continue
    cid = npc["TrainerClass"]
    if cid not in classes:
        continue
    reach = FACTION_RACES[faction_of(npc)]
    rows = list(trainerTemplate.get(npc["TrainerTemplateId"], [])) if npc["TrainerTemplateId"] else []
    rows += trainerDirect.get(entry, [])
    for row in rows:
        mask = cond_races(row["condition_id"]) & reach & CLASS_RACES[cid]
        if not mask:
            continue
        for s in resolve_learn(row["spell"]):
            if not class_may_learn(s, cid):
                trainNotes[(cid, s)].add(entry)
                continue
            t = train[cid].setdefault(s, {"levels": set(), "costs": set(), "races": 0, "trainers": set(),
                                         "via": row["spell"] if row["spell"] != s else None})
            t["levels"].add(row["reqlevel"] or 1)    # 0 = no row value; see below
            t["costs"].add(row["spellcost"] or 0)
            t["races"] |= mask
            t["trainers"].add(entry)

for (tok, s), fix in MANUAL_TRAIN.items():
    t = train[TOKEN_ID[tok]].setdefault(s, {"levels": set(), "costs": set(), "races": 0, "trainers": set(), "via": None})
    if "like" in fix:
        other = train[TOKEN_ID[tok]][fix["like"]]
        t["costs"], t["races"], t["trainers"] = set(other["costs"]), ALL_RACES, set(other["trainers"])
    if "level" in fix:
        t["levels"] = {fix["level"]}
    if "cost" in fix:
        t["costs"] = {fix["cost"]}
    if "races" in fix:
        t["races"] = fix["races"]
    if fix.get("drop"):
        del train[TOKEN_ID[tok]][s]

# ---------------------------------------------------------------------------
# Chains
# ---------------------------------------------------------------------------
def creates_item(s):
    return any(I(e["Effect"]) in (24, 59) for e in effects.get(s, []))

report = collections.defaultdict(list)

def candidates(cid):
    """Every spell on the class's skill lines that can be in its spellbook."""
    out = {}
    dropped = []
    for line in sorted(classLines[cid]):
        for r in sla:
            if I(r["SkillLine"]) != line:
                continue
            s = I(r["Spell"])
            cm = I(r["ClassMask"])
            if cm and not cm & bit(cid):
                continue
            if s in out:
                continue
            why = None
            if junk(s):
                why = "junk name"
            elif is_hidden(s):
                why = "hidden"
            elif craft_line(line) and creates_item(s):
                why = "craft"
            if why:
                if s in train[cid]:
                    dropped.append((s, why + " (a trainer teaches it)"))
                continue
            how = []
            if s in train[cid]:
                how.append("T")
            if s in talentSpells[cid]:
                how.append("L")
            if any(not rc or rc & bit(cid) for _, rc, _ in questTeaches.get(s, [])):
                how.append("Q")
            if itemTeaches.get(s):
                how.append("I")
            if I(r["AcquireMethod"]) in (1, 2):
                how.append("A")
            if craft_line(line) and how == ["A"]:
                continue    # a Beast Training row the pet learns (Growl), not the hunter
            if not how:
                dropped.append((s, "nothing teaches it"))
                continue
            out[s] = {"spell": s, "line": line, "how": how, "acq": I(r["AcquireMethod"]),
                      "sup": I(r["SupercedesSpell"]), "slaRace": I(r["RaceMask_0"])}
    for s in MANUAL_CHAIN_ADD.get(classes[cid], ()):
        out.setdefault(s, {"spell": s, "line": 0, "how": ["M"], "acq": 0, "sup": 0, "slaRace": 0})
    for s in MANUAL_CHAIN_DROP.get(classes[cid], ()):
        out.pop(s, None)
    return out, dropped

def build_chains(cid):
    cands, dropped = candidates(cid)
    groups = collections.defaultdict(list)
    for s, c in cands.items():
        groups[name_of(s)].append(c)
    chains = []
    for name, members in groups.items():
        ranked = [m for m in members if rank_no(m["spell"]) is not None]
        unranked = [m for m in members if rank_no(m["spell"]) is None]
        if unranked and ranked:
            report["rank"].append("%s %s: ranked and unranked spells share the name: %s / %s" % (
                classes[cid], name, [m["spell"] for m in ranked], [m["spell"] for m in unranked]))
        # unranked spells of one name: each its own chain (rare) -- or one if single
        for m in unranked:
            chains.append({"ranks": [m["spell"]], "first": None, "members": [m]})
        if not ranked:
            continue
        byRank = collections.defaultdict(list)
        for m in ranked:
            byRank[rank_no(m["spell"])].append(m)
        ranks = []
        for rn in sorted(byRank):
            ms = byRank[rn]
            if len(ms) > 1:
                # Two spells claim one rank: the one the other supersedes goes
                # first (Seal of Righteousness: the starting spell, then the
                # trainer's), else the one a trainer teaches
                ids = {m["spell"] for m in ms}
                sup = [m for m in ms if m["sup"] in ids]
                if sup:
                    keep = sup[0]
                    report["dupRank"].append("%s %s Rank %d: %s supersedes %s -- the chain keeps %d" % (
                        classes[cid], name, rn, keep["spell"], keep["sup"], keep["spell"]))
                else:
                    ms.sort(key=lambda m: ("T" not in m["how"], m["spell"]))
                    keep = ms[0]
                    report["dupRank"].append("%s %s Rank %d: %s -- the chain keeps %d" % (
                        classes[cid], name, rn, [m["spell"] for m in ms], keep["spell"]))
                ms = [keep]
            ranks.append((rn, ms[0]))
        nums = [rn for rn, _ in ranks]
        if nums != list(range(nums[0], nums[0] + len(nums))):
            report["gap"].append("%s %s: ranks %s" % (classes[cid], name, nums))
        chain = {"ranks": [m["spell"] for _, m in ranks], "first": nums[0] if nums[0] != 1 else None,
                 "members": [m for _, m in ranks], "rankNos": nums}
        # SupercedesSpell, where this build fills it, must name the previous rank
        for i, (_, m) in enumerate(ranks):
            if m["sup"] and i > 0 and m["sup"] != ranks[i - 1][1]["spell"] and m["sup"] in cands:
                report["supersede"].append("%s %s: %d supersedes %d but the previous rank is %d" % (
                    classes[cid], name, m["spell"], m["sup"], ranks[i - 1][1]["spell"]))
        # rank order against the spell levels: a later rank never needs a lower level
        lv = [spellLevel.get(m["spell"], 0) for _, m in ranks]
        if any(b and a and b < a for a, b in zip(lv, lv[1:])):
            report["rankLevel"].append("%s %s: ranks %s have spell levels %s" % (classes[cid], name, nums, lv))
        chains.append(chain)
    chains.sort(key=lambda c: c["ranks"][0])
    return chains, dropped

# ---------------------------------------------------------------------------
# Roles
# ---------------------------------------------------------------------------
SELF = {1}
PET = {5}
ENEMY = {6, 15, 16, 24, 28, 53, 54, 77, 104, 111}
ALLY = {20, 21, 30, 31, 33, 37, 45, 56, 57, 61}            # 25 (any unit) is neither side
TOTEM = {41, 42, 43, 44}
HARD_CC_AURA = {2, 5, 6, 7, 12, 26, 27, 60, 67}            # possess confuse charm fear stun root silence pacify-silence disarm
HARD_CC_MECH = {1, 2, 3, 5, 7, 9, 10, 12, 13, 14, 17, 18, 20, 23, 24, 26, 30}
DAMAGE_EFF = {2, 8, 9, 17, 31, 58, 62, 121}               # school, power drain, leech, weapon (4), power burn
DAMAGE_AURA = {3, 53, 64}                                 # periodic damage, leech, mana leech
HEAL_EFF = {10, 67, 136}
HEAL_AURA = {8}
UTIL_AURA = {1, 16, 17, 19, 32, 44, 45, 78, 82, 104, 105, 106, 151, 201, 378}  # sight, stealth, detect, mount, tracking, water/fall/hover
DEFENSE_AURA_SELF = {10, 18, 31, 34, 39, 40, 47, 49, 51, 66, 69, 74, 77, 87, 97, 103, 129, 133, 184, 185, 186}
DEFENSE_AURA_ALLY = {39, 40, 87}
LESS_IS_GOOD = {10, 87, 103, 184, 185, 186}                # threat, damage taken, attacker hit: only a reduction defends
OFFENSE_AURA = {13, 52, 57, 65, 79, 99, 107, 108, 124, 138, 140, 192}
TRIGGER_AURA = {23}
UTILITY_EFF = {5, 18, 24, 33, 50, 59, 71, 85, 113, 151, 252, 329}   # teleport, resurrect, create item, open lock, object, pick pocket, summon, ritual
SUMMON_EFF = {28, 56}

def effect_rows(s, depth=0, seen=None):
    """A spell's effects plus those of the spells it triggers outright (effect 64
    TRIGGER_SPELL, aura 23 PERIODIC_TRIGGER_SPELL), one level deep."""
    seen = seen or set()
    if s in seen:
        return []
    seen.add(s)
    out = [(s, e) for e in effects.get(s, [])]
    if depth < 1:
        for e in effects.get(s, []):
            t = I(e["EffectTriggerSpell"])
            if t and (I(e["Effect"]) == 64 or I(e["EffectAura"]) in TRIGGER_AURA):
                out += effect_rows(t, depth + 1, seen)
    return out

def targets(e):
    return {I(e["ImplicitTarget_0"]), I(e["ImplicitTarget_1"])} - {0}

def role_of(s):
    """(role, reason) for one spell, by its effects (and those of the spells it
    triggers outright). Order matters: a spell that both damages and stuns is
    CONTROL, one that damages and slows is DAMAGE; a dispel is UTILITY even when
    it ticks; an offensive cooldown is DAMAGE before any defensive aura on it."""
    if is_passive(s):
        return "PASSIVE", "passive"
    rows = effect_rows(s)
    effs = [e for _, e in rows]
    own = [e for src, e in rows if src == s]
    dur = duration(s)
    mech = I(categories.get(s, {}).get("Mechanic"))
    def has(pred):
        return any(pred(e) for e in effs)
    eff = lambda e: I(e["Effect"])
    aura = lambda e: I(e["EffectAura"])
    bp = lambda e: I(e["EffectBasePoints"])
    tg = targets
    def enemy(e):
        return not tg(e) or bool(tg(e) & ENEMY) or not tg(e) <= (SELF | PET | ALLY)
    def selfOnly(e):
        return bool(tg(e)) and tg(e) <= SELF
    # FORM: a shapeshift (not the Stealth form); a party aura with no end
    # (paladin auras, Aspect of the Pack / Wild); a self aura with no end and
    # no charges to spend (the other aspects)
    if has(lambda e: aura(e) == 36 and I(e["EffectMiscValue_0"]) != 30):
        return "FORM", "shapeshift"
    if dur == -1 and any(eff(e) in (35, 65) for e in own):
        return "FORM", "toggled party aura"
    if dur == -1 and not procCharges.get(s) and own and all(selfOnly(e) for e in own) \
            and any(eff(e) == 6 for e in own) and not any(aura(e) in UTIL_AURA for e in own):
        return "FORM", "toggled self aura"
    # PET: summons a pet, or works on the pet
    if has(lambda e: eff(e) in (55, 56, 101, 102, 109)):
        return "PET", "pet summon/control effect"
    if own and all(tg(e) & PET or not tg(e) - SELF for e in own) and any(tg(e) & PET for e in own):
        return "PET", "acts on the pet"
    if any(eff(e) == 28 and not tg(e) & TOTEM for e in own):
        return "PET", "summons a creature"
    if any(eff(e) == 28 and tg(e) & TOTEM for e in own):
        return "UTILITY", "totem (unclassified)"
    # CONTROL: hard crowd control or an interrupt on an enemy
    if has(lambda e: enemy(e) and (aura(e) in HARD_CC_AURA or eff(e) == 68 or I(e["EffectMechanic"]) in HARD_CC_MECH)):
        return "CONTROL", "hard CC / interrupt"
    if mech in HARD_CC_MECH and has(lambda e: enemy(e) and eff(e) in (6, 27, 2, 3, 77, 64)):
        return "CONTROL", "CC mechanic %d" % mech
    # HEAL
    if has(lambda e: eff(e) in HEAL_EFF and not tg(e) & PET) or has(lambda e: aura(e) in HEAL_AURA and not tg(e) & PET):
        return "HEAL", "heal"
    if has(lambda e: aura(e) == 69 and tg(e) & ALLY):
        return "HEAL", "absorb on an ally"
    # DAMAGE
    if has(lambda e: eff(e) in DAMAGE_EFF or aura(e) in DAMAGE_AURA):
        return "DAMAGE", "damage"
    # UTILITY: dispels and spell steal with no damage (Abolish Poison ticks, it is
    # still a cure; Shield Slam and Arcane Shot dispel as a rider)
    if has(lambda e: eff(e) in (38, 126)):
        return "UTILITY", "dispel"
    # CONTROL: a slow with no damage
    if has(lambda e: aura(e) == 33 and enemy(e)):
        return "CONTROL", "snare"
    # DAMAGE: a short offensive cooldown on oneself
    if 0 < dur < 300000 and any(eff(e) == 6 and selfOnly(e) and aura(e) in OFFENSE_AURA and bp(e) >= 0 for e in own):
        return "DAMAGE", "offensive cooldown"
    # DEFENSE: escapes, survival auras on oneself, immunity / damage reduction on an ally
    if has(lambda e: eff(e) in (29, 79)):
        return "DEFENSE", "escape (leap / sanctuary)"
    def defends(e):
        return aura(e) not in LESS_IS_GOOD or bp(e) < 0
    if 0 < dur < 300000 and has(lambda e: selfOnly(e) and aura(e) in DEFENSE_AURA_SELF and defends(e)):
        return "DEFENSE", "self survival aura"
    if has(lambda e: tg(e) & ALLY and aura(e) in DEFENSE_AURA_ALLY and defends(e)):
        return "DEFENSE", "ally immunity / damage reduction"
    # TRAVEL: getting somewhere, its own foldout so a mage's twenty-odd
    # portals and teleports do not bury the conjures (added 2026-10-26 by the
    # lead). By name for the teleports and portals: Shadowstep teleports too
    # (effect 5, behind the target) and is no journey; by the mount aura for
    # the summoned steeds. Shapeshifts (Travel Form, Ghost Wolf) stay FORM.
    nm = name_of(s) or ""
    if nm.startswith("Teleport:") or nm.startswith("Portal:") or nm == "Astral Recall":
        return "TRAVEL", "teleport / portal"
    if has(lambda e: aura(e) in (32, 78) and selfOnly(e)):
        return "TRAVEL", "summoned mount"
    # UTILITY auras before BUFF: tracking, detection, sight, mounts, water walking, falling
    if has(lambda e: aura(e) in UTIL_AURA):
        return "UTILITY", "utility aura"
    # UTILITY by effect: conjure / create, teleport, portal or ritual object,
    # resurrect, pick a lock or a pocket, summon a player
    if any(eff(e) in UTILITY_EFF for e in own):
        return "UTILITY", "utility effect"
    # BUFF: an aura on allies / the party, a long one on oneself, a weapon imbue
    if has(lambda e: eff(e) in (6, 35, 65) and tg(e) & ALLY):
        return "BUFF", "aura on allies"
    if has(lambda e: eff(e) in (35, 65)):
        return "BUFF", "party aura"
    if has(lambda e: eff(e) == 6 and selfOnly(e)) and dur >= 300000:
        return "BUFF", "long self aura"
    if has(lambda e: eff(e) == 54):
        return "BUFF", "weapon imbue"
    return "UTILITY", "default"

# ---------------------------------------------------------------------------
# Build per class
# ---------------------------------------------------------------------------
data = {}
classOrder = sorted(classes)
for cid in classOrder:
    tok = classes[cid]
    chains, dropped = build_chains(cid)
    for ch in chains:
        r1 = ch["ranks"][0]
        top = ch["ranks"][-1]
        if r1 in MANUAL_ROLE:
            ch["role"], ch["why"] = MANUAL_ROLE[r1], "manual"
        else:
            ch["role"], ch["why"] = role_of(top)
        how = ch["members"][0]["how"]
        ch["src"] = "T" if "T" in how else "L" if "L" in how else "Q" if "Q" in how else "O"
    report["dropped"] += ["%s %d %s: %s" % (tok, s, label(s), why) for s, why in dropped]
    data[tok] = {"cid": cid, "chains": chains, "train": train[cid]}

# Train: one level and cost per spell; race mask when not every race of the class
trainOut = {}
for tok, d in data.items():
    cid = d["cid"]
    out = {}
    for s, t in sorted(d["train"].items()):
        if junk(s):
            report["trainJunk"].append("%s %d %s" % (tok, s, label(s)))
            continue
        # a trainer row with reqlevel 0 is a hole in that row, not "level 1",
        # when another trainer gives the spell a level
        levels = {l for l in t["levels"] if l > 1} or t["levels"]
        level, cost = min(levels), min(t["costs"])
        if spellLevel.get(s) and spellLevel[s] != level and (tok, s) not in MANUAL_TRAIN:
            report["levelVsDB2"].append("%s %d %s: trainer %d, SpellLevels %d" % (tok, s, label(s), level, spellLevel[s]))
        if len(levels) > 1 or len(t["costs"]) > 1:
            report["trainConflict"].append("%s %d %s: levels %s costs %s" % (
                tok, s, label(s), sorted(t["levels"]), sorted(t["costs"])))
        # The races the trainers reach (their side, their row conditions), within
        # the races SkillLineAbility allows: the server checks both, and a neutral
        # trainer (Shattrath) leans on the second alone
        mask = t["races"] & CLASS_RACES[cid]
        rows = slaBySpell.get(s, [])
        slaMask = ALL_RACES if not rows or any(not I(r["RaceMask_0"]) for r in rows) else 0
        for r in rows:
            slaMask |= I(r["RaceMask_0"])
        if (slaMask & mask) != mask:
            report["raceVsSLA"].append("%s %d %s: trainers %s, SkillLineAbility %s -> %s" % (
                tok, s, label(s), race_names(mask), race_names(slaMask & CLASS_RACES[cid]), race_names(slaMask & mask)))
        mask &= slaMask
        out[s] = (level, cost, None if mask == CLASS_RACES[cid] else mask)
    trainOut[tok] = out

# ---------------------------------------------------------------------------
# General tab
# ---------------------------------------------------------------------------
RACIAL_LINES = {s for s, r in skillLine.items() if r["CategoryID"] == "9" and "Racial" in r["DisplayName_lang"]}
PROFESSION_LINES = {s for s, r in skillLine.items() if r["CategoryID"] == "11"} \
    | {s for s, r in skillLine.items() if r["CategoryID"] == "9" and r["DisplayName_lang"] in ("First Aid", "Cooking", "Fishing", "Survival")}
GENERAL_LINES = {s for s, r in skillLine.items() if r["CategoryID"] in ("6", "12")} \
    | {s for s, r in skillLine.items() if r["CategoryID"] == "9" and ("Riding" in r["DisplayName_lang"] or "Piloting" in r["DisplayName_lang"] or "Horsemanship" in r["DisplayName_lang"])}
RECIPE_EFF = {24, 53, 59, 157}
general = {}
for r in sla:
    line, s = I(r["SkillLine"]), I(r["Spell"])
    if line in RACIAL_LINES:
        grp = "RACIAL"
    elif line in PROFESSION_LINES:
        grp = "PROFESSION"
    elif line in GENERAL_LINES:
        grp = "GENERAL"
    else:
        continue
    if junk(s) or is_hidden(s) or any(I(e["Effect"]) in RECIPE_EFF for e in effects.get(s, [])):
        continue
    general.setdefault(s, grp)

# ---------------------------------------------------------------------------
# Weapon masters
# ---------------------------------------------------------------------------
weaponLine = {}     # weapon skill spell -> its skill line
for r in sla:
    line, s = I(r["SkillLine"]), I(r["Spell"])
    if line in skillLine and skillLine[line]["CategoryID"] == "6" and any(I(e["Effect"]) == 60 for e in effects.get(s, [])):
        weaponLine[s] = line
weaponClasses = collections.defaultdict(int)
for r in srci:
    weaponClasses[I(r["SkillID"])] |= I(r["ClassMask"]) & sum(bit(c) for c in classes)
weapons = {}
for entry, npc in sorted(creature.items()):
    if npc["TrainerType"] != 2 or not spawned(entry):
        continue
    rows = (list(trainerTemplate.get(npc["TrainerTemplateId"], [])) if npc["TrainerTemplateId"] else []) + trainerDirect.get(entry, [])
    rows = [row for row in rows if row["spell"] in weaponLine]
    if not rows:
        continue
    place = place_of(entry)
    if not place:
        report["weapons"].append("weapon master %d %s: no zone for the spawn" % (entry, npc["Name"]))
        continue
    fac = faction_of(npc)
    for row in rows:
        w = weapons.setdefault(row["spell"], {"levels": set(), "costs": set(), "trainers": {"Alliance": {}, "Horde": {}}})
        w["levels"].add(max(row["reqlevel"] or 1, 1))
        w["costs"].add(row["spellcost"])
        for side in ([fac] if fac else ["Alliance", "Horde"]):
            w["trainers"][side][entry] = {"npc": entry, "name": npc["Name"], "map": place[0], "x": place[1], "y": place[2]}
for s, w in weapons.items():
    if len(w["levels"]) > 1 or len(w["costs"]) > 1:
        report["weapons"].append("%d %s: levels %s costs %s" % (s, name_of(s), sorted(w["levels"]), sorted(w["costs"])))
    w["level"], w["cost"] = min(w["levels"]), min(w["costs"])
    w["classMask"] = weaponClasses[weaponLine[s]]

# ---------------------------------------------------------------------------
# Cross-check: What's Training? (third party, MIT, read only)
# ---------------------------------------------------------------------------
def lua_table(text, i):
    """Parse a Lua table constructor starting at text[i] == '{'; returns (value, next index).
    Enough Lua for What's Training?'s data files: numbers, strings, booleans, nested
    tables, [n] = and name = keys."""
    tok = re.compile(r'\s*(--[^\n]*\n|\{|\}|\[|\]|=|,|;|"(?:[^"\\]|\\.)*"|-?\d+(?:\.\d+)?|[A-Za-z_][A-Za-z_0-9.]*)', re.S)
    def nxt(j):
        while True:
            m = tok.match(text, j)
            if not m:
                raise ValueError("lua parse at %d: %r" % (j, text[j:j + 40]))
            if m.group(1).startswith("--"):
                j = m.end()
                continue
            return m.group(1), m.end()
    def value(j):
        t, j2 = nxt(j)
        if t == "{":
            return table(j2)
        if t.startswith('"'):
            return t[1:-1], j2
        if re.match(r"-?\d", t):
            return (float(t) if "." in t else int(t)), j2
        if t in ("true", "false"):
            return t == "true", j2
        if t == "nil":
            return None, j2
        t2, _ = nxt(j2)
        if t2 in ("]", ",", "}", ";"):
            return ("<id>", t), j2
        # an expression (e.g. version == "tbc"): skip to the next , or }
        depth = 0
        k = j2
        while k < len(text):
            ch = text[k]
            if ch in "({":
                depth += 1
            elif ch in ")}":
                if depth == 0:
                    break
                depth -= 1
            elif ch == "," and depth == 0:
                break
            k += 1
        return ("<expr>", t), k
    def table(j):
        arr, hsh = [], {}
        while True:
            t, j2 = nxt(j)
            if t == "}":
                return (hsh if hsh else arr) if not (hsh and arr) else dict(hsh, **{i + 1: v for i, v in enumerate(arr)}), j2
            if t in (",", ";"):
                j = j2
                continue
            if t == "[":
                k, j3 = value(j2)
                _, j3 = nxt(j3)  # ]
                _, j3 = nxt(j3)  # =
                v, j = value(j3)
                hsh[k] = v
                continue
            t2, j3 = nxt(j2)
            if re.match(r"[A-Za-z_]", t) and t2 == "=":
                v, j = value(j3)
                hsh[t] = v
                continue
            v, j = value(j)
            arr.append(v)
    assert text[i] == "{"
    return table(i + 1)

WT_FILES = {"WARRIOR": "Warrior", "PALADIN": "Paladin", "HUNTER": "Hunter", "ROGUE": "Rogue", "PRIEST": "Priest",
            "SHAMAN": "Shaman", "MAGE": "Mage", "WARLOCK": "Warlock", "DRUID": "Druid"}

def wt_class(tok):
    path = os.path.join(WT_DIR, "TBC", WT_FILES[tok] + ".lua")
    if not os.path.exists(path):
        return None
    text = open(path, encoding="utf-8").read()
    m = re.search(r"SpellsByLevel\s*=\s*(?:[\w.:]+\(\s*)?\{", text)
    tbl, _ = lua_table(text, m.end() - 1)
    out = {}
    for level, spells in tbl.items():
        for sp in spells:
            rmask = None
            if sp.get("race"):
                rmask = bit(sp["race"])
            elif sp.get("races"):
                rmask = sum(bit(x) for x in (sp["races"].values() if isinstance(sp["races"], dict) else sp["races"]))
            elif sp.get("faction"):
                rmask = ALLIANCE if sp["faction"] == "Alliance" else HORDE
            out[sp["id"]] = (level, sp.get("cost"), rmask, sp.get("requiredTalentId"))
    return out

def cross_check():
    lines = []
    for tok in sorted(data):
        cid = data[tok]["cid"]
        theirs = wt_class(tok)
        if theirs is None:
            lines.append("%s: What's Training? not found, skipped" % tok)
            continue
        ours = trainOut[tok]
        onlyOurs = sorted(s for s in ours if s not in theirs)
        onlyTheirs = sorted(s for s in theirs if s not in ours)
        lvl, cost, race = [], [], []
        for s in sorted(set(ours) & set(theirs)):
            ol, oc, om = ours[s]
            tl, tc, tm, _ = theirs[s]
            if ol != tl:
                lvl.append("%d %s %d/%d" % (s, label(s), ol, tl))
            if tc is not None and oc != tc:
                cost.append("%d %s %d/%d" % (s, label(s), oc, tc))
            om2 = (om or CLASS_RACES[cid]) & CLASS_RACES[cid]
            tm2 = (tm or CLASS_RACES[cid]) & CLASS_RACES[cid]
            if om2 != tm2:
                race.append("%d %s ours [%s] theirs [%s]" % (s, label(s), race_names(om2), race_names(tm2)))
        lines.append("%s: ours %d, theirs %d, both %d; only ours %d, only theirs %d, level %d, cost %d, race %d" % (
            tok, len(ours), len(theirs), len(set(ours) & set(theirs)), len(onlyOurs), len(onlyTheirs), len(lvl), len(cost), len(race)))
        for s in onlyOurs:
            lines.append("    only ours   %d %s (L%d)" % (s, label(s), ours[s][0]))
        for s in onlyTheirs:
            lines.append("    only theirs %d %s (L%d)" % (s, label(s), theirs[s][0]))
        for x in lvl:
            lines.append("    level  " + x)
        for x in cost:
            lines.append("    cost   " + x)
        for x in race:
            lines.append("    race   " + x)
    # weapons
    path = os.path.join(WT_DIR, "WeaponSkills.lua")
    if os.path.exists(path):
        text = open(path, encoding="utf-8").read()
        m = re.search(r"local weaponMasters\s*=\s*\{", text)
        masters, _ = lua_table(text, m.end() - 1)
        consts = {k: int(v) for k, v in re.findall(r"local (\w+) = (\d+)\n", text)}
        m = re.search(r"local zones\s*=\s*\{", text)
        zones, _ = lua_table(text, m.end() - 1)
        uimapOf = {}
        for k, z in zones.items():
            key = consts.get(k[1]) if isinstance(k, tuple) else k
            uimapOf[key] = z["uiMapId"]
        wl = []
        for npc, mm in sorted(masters.items(), key=lambda kv: kv[0]):
            if not mm["versions"].get("tbc"):
                continue
            teach = {consts.get(k[1], k) if isinstance(k, tuple) else k for k in mm["teaches"]}
            ourTeach = {s for s, w in weapons.items() if any(npc in w["trainers"][side] for side in ("Alliance", "Horde"))}
            loc = mm.get("location") or {}
            zid = loc.get("zoneId")
            zid = consts.get(zid[1]) if isinstance(zid, tuple) else zid
            wtMap = uimapOf.get(zid)
            ours = place_of(npc)
            if ours and wtMap and (ours[0] != wtMap or abs(ours[1] * 100 - loc["x"]) > 1 or abs(ours[2] * 100 - loc["y"]) > 1):
                wl.append("    %d %s: placed at %d %.1f, %.1f; theirs %d %.1f, %.1f" % (npc, mm["names"]["enUS"],
                          ours[0], ours[1] * 100, ours[2] * 100, wtMap, loc["x"], loc["y"]))
            if teach != ourTeach:
                wl.append("    %d %s: only ours %s, only theirs %s" % (npc, mm["names"]["enUS"],
                          sorted(name_of(s) for s in ourTeach - teach), sorted(name_of(s) for s in teach - ourTeach)))
        ourNpcs = {n for w in weapons.values() for side in ("Alliance", "Horde") for n in w["trainers"][side]}
        theirNpcs = {n for n, mm in masters.items() if mm["versions"].get("tbc")}
        lines.append("WEAPONS: masters ours %d theirs %d; only ours %s; only theirs %s" % (
            len(ourNpcs), len(theirNpcs), sorted(ourNpcs - theirNpcs), sorted(theirNpcs - ourNpcs)))
        lines += wl
    return lines

# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------
def write():
    L = []
    w = L.append
    w("-- GENERATED by Harness/make_spellbook_data.py — do not edit by hand.")
    w("-- From the client's own DB2 tables for build %s (wago.tools: SkillLine, SkillLineAbility," % BUILD)
    w("-- SkillRaceClassInfo, Spell, SpellName, SpellMisc, SpellEffect, Talent, CharBaseInfo, ChrRaces,")
    w("-- UiMapAssignment) married to the CMaNGOS TBC world DB (class and weapon trainers with their")
    w("-- conditions, spawn points, quest rewards). classes[TOKEN].chains: every rank chain the class can")
    w("-- have in its spellbook (rank 1 first; role decided on the highest rank; src = how rank 1 is learned:")
    w("-- T trainer, L talent, Q quest, O other or a starting spell). classes[TOKEN].train: what the class")
    w("-- trainers teach, spellID = { level, cost in copper[, raceMask] } (mask bit 2^(raceID-1), absent when")
    w("-- every race of the class may learn it). general: the General-tab spells by group. weapons: the")
    w("-- weapon skills weapon masters teach (classMask bit 2^(classID-1)), with each side's masters placed")
    w("-- on the uiMap (x, y in 0..1). Names below are English comments only; the addon reads names at runtime.")
    w("CommanderSpellbookData = {")
    w('    build = "%s",' % BUILD)
    w("    classes = {")
    for cid in classOrder:
        tok = classes[cid]
        d = data[tok]
        w("        %s = {" % tok)
        w("            chains = {")
        for ch in d["chains"]:
            first = ", first = %d" % ch["first"] if ch["first"] else ""
            w('                { role = "%s", src = "%s"%s, ranks = { %s } }, -- %s' % (
                ch["role"], ch["src"], first, ", ".join(str(s) for s in ch["ranks"]), name_of(ch["ranks"][0])))
        w("            },")
        w("            train = {")
        for s, (level, cost, mask) in sorted(trainOut[tok].items()):
            if mask is None:
                w("                [%d] = { %d, %d }, -- %s" % (s, level, cost, label(s)))
            else:
                w("                [%d] = { %d, %d, %d }, -- %s — %s" % (s, level, cost, mask, label(s), race_names(mask)))
        w("            },")
        w("        },")
    w("    },")
    w("    general = {")
    for s in sorted(general):
        w('        [%d] = "%s", -- %s' % (s, general[s], label(s)))
    w("    },")
    w("    weapons = {")
    for s in sorted(weapons):
        wp = weapons[s]
        w("        [%d] = { level = %d, cost = %d, classMask = %d, -- %s" % (s, wp["level"], wp["cost"], wp["classMask"], name_of(s)))
        w("            trainers = {")
        for side in ("Alliance", "Horde"):
            items = []
            for npc in sorted(wp["trainers"][side]):
                t = wp["trainers"][side][npc]
                items.append('{ npc = %d, name = "%s", map = %d, x = %.3f, y = %.3f }' % (t["npc"], t["name"].replace('"', '\\"'), t["map"], t["x"], t["y"]))
            w("                %s = { %s }," % (side, ", ".join(items)) if items else "                %s = {}," % side)
        w("            },")
        w("        },")
    w("    },")
    w("}")
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(L) + "\n")

write()

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
ROLES = ["HEAL", "DAMAGE", "CONTROL", "DEFENSE", "BUFF", "FORM", "UTILITY", "TRAVEL", "PET", "PASSIVE"]
print("== %s -> %s" % (BUILD, OUT))
for cid in classOrder:
    tok = classes[cid]
    chains = data[tok]["chains"]
    rc = collections.Counter(c["role"] for c in chains)
    sc = collections.Counter(c["src"] for c in chains)
    print("%-8s chains %3d  train %3d  %s  src %s" % (tok, len(chains), len(trainOut[tok]),
          " ".join("%s %d" % (r, rc[r]) for r in ROLES if rc[r]), dict(sorted(sc.items()))))
print("general %d (%s)" % (len(general), dict(collections.Counter(general.values()))))
print("weapons %d" % len(weapons))
report["trainClass"] = ["%s %d %s: on %d trainers, but SkillLineAbility gives it to other classes only -- left out" % (
    classes[cid], s, label(s), len(n)) for (cid, s), n in sorted(trainNotes.items())]
for key in ("rank", "dupRank", "gap", "supersede", "rankLevel", "trainClass", "trainConflict", "levelVsDB2", "raceVsSLA", "trainJunk", "weapons"):
    if report[key]:
        print("-- %s (%d)" % (key, len(report[key])))
        for x in report[key]:
            print("   " + x)
VERBOSE = os.environ.get("SPELLBOOK_VERBOSE")
if VERBOSE:
    print("-- dropped (%d)" % len(report["dropped"]))
    for x in report["dropped"]:
        print("   " + x)
print("-- UTILITY by default (no rule matched, no manual role)")
for cid in classOrder:
    tok = classes[cid]
    left = [c for c in data[tok]["chains"] if c["role"] == "UTILITY" and c["why"] in ("default", "totem (unclassified)")]
    if left:
        print("   %s: %s" % (tok, ", ".join("%s %d" % (name_of(c["ranks"][0]), c["ranks"][0]) for c in left)))
if VERBOSE:
    print("-- all chains")
    for cid in classOrder:
        tok = classes[cid]
        for c in data[tok]["chains"]:
            print("   %s %-8s %-7s %s %-34s %s" % (tok, c["role"], c["why"][:7], c["src"], name_of(c["ranks"][0])[:34],
                  ",".join(str(s) for s in c["ranks"])))
print("-- cross-check against What's Training? (ours/theirs)")
for x in cross_check():
    print("   " + x)
