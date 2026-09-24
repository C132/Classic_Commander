#!/usr/bin/env python3
"""Generate the diminishing-returns half of CommanderArenaFramesData.lua.

Two sources, and neither of them is a guess:

  * the CLIENT's own DB2 tables for this exact build (wago.tools) say what
    MECHANIC each spell carries and which spell family it belongs to -- the
    two inputs the server's classifier reads;
  * CMaNGOS's `GetDiminishingReturnsGroupForSpell` (mangos-tbc, TBC branch)
    is the classifier itself, and it is the closest thing to Blizzard's 2.4.3
    rules that can be read rather than inferred.

So this script is a transcription of that C++ function over the real table,
not a hand-typed spell list -- which matters because a hand-typed list is
always missing a rank, and a missing rank is a DR the board silently fails to
count.

Usage (from the AddOns directory):
    python3 Commander_ArenaFrames/Harness/make_dr_table.py --csv <dir> \
        --out Commander_ArenaFrames/CommanderArenaFramesData.lua.dr

CSV dir must hold, for build 2.5.6.69546:
    SpellName SpellCategories SpellEffect SpellClassOptions
    SkillLineAbility SkillLine SpellDuration SpellMisc
each fetched from https://wago.tools/db2/<Table>/csv?build=2.5.6.69546
"""

import argparse
import csv
import os
import sys
from collections import defaultdict

# --- SharedDefines.h (mangos-tbc, src/game/Globals/SharedDefines.h) ---------
M_CHARM, M_DISORIENTED, M_DISARM, M_FEAR = 1, 2, 3, 5
M_ROOT, M_SILENCE, M_SLEEP, M_SNARE, M_STUN = 7, 9, 10, 11, 12
M_FREEZE, M_KNOCKOUT, M_POLYMORPH, M_BANISH = 13, 14, 17, 18
M_SHACKLE, M_TURN, M_HORROR, M_SAPPED = 20, 23, 24, 30

# --- SpellFamilyName -------------------------------------------------------
FAM_GENERIC, FAM_MAGE, FAM_WARRIOR, FAM_WARLOCK = 0, 3, 4, 5
FAM_PRIEST, FAM_DRUID, FAM_ROGUE, FAM_HUNTER = 6, 7, 8, 9
FAM_PALADIN, FAM_SHAMAN = 10, 11

# The DR groups this client's server enforces, in the order the board should
# offer them. `drtype` mirrors GetDiminishingReturnsGroupType: ALL = it also
# diminishes on creatures, PLAYER = players only, and LIMITONLY has no ladder
# at all -- only the 10s PvP duration cap.
GROUPS = [
    ("STUN",       "Stun",           "ALL",       "Controlled stuns. Cheap Shot, Hammer of Justice, Charge, Intercept, Pounce, Bash, Intimidation, War Stomp, Shadowfury."),
    ("STUN_PROC",  "Proc Stun",      "ALL",       "Stuns that PROC rather than being cast -- Blackout, Impact, Mace Specialization, Seal of Justice. Their own ladder in TBC, so a mace warrior's random stun never eats the team's Hammer."),
    ("KIDNEY",     "Kidney Shot",    "ALL",       "Kidney Shot alone. Its own category in TBC: a rogue can Cheap Shot into a full Kidney."),
    ("BLIND",      "Blind / Cyclone","ALL",       "Blind and Cyclone share one ladder."),
    ("POLY",       "Incapacitate",   "PLAYER",    "Polymorph, Gouge and Sap share one ladder (MECHANIC_POLYMORPH / KNOCKOUT / SAPPED)."),
    ("FEAR",       "Fear",           "PLAYER",    "Fear, Howl of Terror, Psychic Scream, Intimidating Shout, Scare Beast, Seduction, Turn Evil."),
    ("ROOT",       "Root",           "PLAYER",    "Cast roots -- Frost Nova, Entangling Roots, Earth Shock's? no; Nature's Grasp's root counts here too."),
    ("ROOT_PROC",  "Proc Root",      "PLAYER",    "Roots that proc -- Frostbite, Improved Hamstring, Entrapment. Their own ladder."),
    ("FREEZE",     "Freezing Trap",  "PLAYER",    "Freezing Trap (hunter family) and anything else carrying MECHANIC_FREEZE."),
    ("SLEEP",      "Sleep",          "PLAYER",    "Hibernate and Wyvern Sting."),
    ("BANISH",     "Banish",         "PLAYER",    "Banish."),
    ("HORROR",     "Death Coil",     "PLAYER",    "Death Coil (MECHANIC_HORROR)."),
    ("DISARM",     "Disarm",         "PLAYER",    "Disarm and Riposte."),
    ("CHARM",      "Mind Control",   "ALL",       "Mind Control. Diminishes on players only, but the group is DRTYPE_ALL."),
    ("DRAGONS",    "Dragon's Breath","PLAYER",    "Dragon's Breath, on its own ladder (mage family mask 0x800000)."),
    ("LIMIT",      "Hamstring",      "LIMITONLY", "Hamstring. No ladder at all -- just the 10s PvP cap, so the board shows the cap and never a bracket."),
]
GROUP_KEYS = {g[0] for g in GROUPS}

# Stuns and roots the server treats as TRIGGERED, which in TBC get their own
# ladder. `triggered` is a runtime property of the cast rather than a column:
# Spell.cpp passes `m_triggeredByAuraSpell != nullptr || (m_IsTriggeredSpell &&
# m_CastItem)`, so it means "this landed because an AURA procced it" (or an
# item did). That is a short, closed list in TBC -- every talent that procs a
# stun or a root -- and it is the one thing here that has to be named by hand.
#
# What the rule does NOT cover is worth stating, because it is the question
# people get wrong: Charge Stun and Intercept Stun are triggered by a SPELL
# EFFECT, not by an aura, so they are ordinary controlled stuns and share the
# Stun ladder. The classifier gets that right on its own.
TRIGGERED_STUN_NAMES = {
    "Blackout",                   # priest, Shadow talent proc
    "Impact",                     # mage, Fire talent proc
    "Mace Stun Effect",           # warrior/rogue/paladin, Mace Specialization
    "Revenge Stun",               # warrior, Improved Revenge
    "Starfire Stun",              # druid, Improved Starfire
    "Improved Concussive Shot",   # hunter talent proc
}
# Procs whose spell NAME is too generic to key on ("Stun"). Explicit ids.
TRIGGERED_STUN_IDS = {
    20170,   # the stun Seal of Justice procs -- named simply "Stun"
}
TRIGGERED_ROOT_NAMES = {
    "Frostbite",              # mage, Frost talent proc
    "Improved Hamstring",     # warrior, Arms talent proc
    "Entrapment",             # hunter, Survival talent proc
}
# CMaNGOS routes Nature's Grasp's triggered root back to the CAST root group
# explicitly, so it must not fall through the name list above.
FORCE_CAST_ROOT_NAMES = {"Nature's Grasp"}

# There is deliberately NO "only player spells" filter. The obvious one --
# keep what SkillLineAbility says a class can train -- throws away exactly the
# rows the board needs, because the thing that LANDS on an enemy is usually a
# separate triggered aura that nobody trains: Freezing Trap Effect, Seduction's
# applied aura, Intimidation's stun. A creature spell left in the table costs
# one dead key and can only ever be consulted if that spell is applied to an
# arena enemy, which cannot happen; a missing player rank costs a bracket the
# board silently fails to count. The asymmetry decides it.
#
# Attributes values CMaNGOS tests alongside a family flag (SpellMisc.Attributes_0).
ATTR_TURN_EVIL = 0x40010000
ATTR_NATURES_GRASP_ROOT = 0x49010000


def read_csv(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def to_int(value, default=0):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def mask_of(row, prefix, count=4):
    """SpellClassMask_0..3 as one integer (low word first).

    Each column is a SIGNED 32-bit int in the CSV, so 0x80000000 arrives as
    -2147483648. Python has no fixed width: OR-ing that in directly gives a
    number with infinitely many leading 1 bits, and every family-flag test
    above bit 31 then matches everything. Mask each word back to unsigned
    first -- Holy Light reading as Turn Evil is what this line prevents.
    """
    total = 0
    for i in range(count):
        total |= (to_int(row.get("%s_%d" % (prefix, i))) & 0xFFFFFFFF) << (32 * i)
    return total


def load(csv_dir):
    names = {}
    for row in read_csv(os.path.join(csv_dir, "SpellName.csv")):
        names[to_int(row["ID"])] = row["Name_lang"]

    mechanic = {}
    for row in read_csv(os.path.join(csv_dir, "SpellCategories.csv")):
        spell = to_int(row["SpellID"])
        mech = to_int(row["Mechanic"])
        if mech:
            mechanic.setdefault(spell, set()).add(mech)

    for row in read_csv(os.path.join(csv_dir, "SpellEffect.csv")):
        spell = to_int(row["SpellID"])
        mech = to_int(row["EffectMechanic"])
        if mech:
            mechanic.setdefault(spell, set()).add(mech)

    family, classmask = {}, {}
    for row in read_csv(os.path.join(csv_dir, "SpellClassOptions.csv")):
        spell = to_int(row["SpellID"])
        family[spell] = to_int(row["SpellClassSet"])
        classmask[spell] = mask_of(row, "SpellClassMask")

    # Attributes_0 only: the two rules that read it (Turn Evil, Nature's
    # Grasp) both compare the whole first word.
    attributes = {}
    for row in read_csv(os.path.join(csv_dir, "SpellMisc.csv")):
        spell = to_int(row.get("SpellID") or row.get("ID"))
        attributes[spell] = to_int(row.get("Attributes_0")) & 0xFFFFFFFF

    return names, mechanic, family, classmask, attributes


def classify(spell, names, mechanic, family, classmask, attributes):
    """A transcription of CMaNGOS GetDiminishingReturnsGroupForSpell (TBC).

    Returns a group key from GROUPS, or None for DIMINISHING_NONE. The
    `triggered` branches are resolved by name (see TRIGGERED_*_NAMES).
    """
    name = names.get(spell, "")
    mech = mechanic.get(spell, set())
    fam = family.get(spell, FAM_GENERIC)
    mask = classmask.get(spell, 0)
    attr = attributes.get(spell, 0)

    # --- explicit family branches, in the server's own order ---------------
    if fam == FAM_GENERIC:
        if M_TURN in mech:
            return None                      # "some generic arena spells have MECHANIC_TURN"
        if spell == 24394:
            return "STUN"                    # Hunter Pet Intimidation
    elif fam == FAM_MAGE:
        # Blast Wave carries the SAME family bit as Dragon's Breath in this
        # client's data, and the server's own classifier does hand both to the
        # Dragon's Breath group -- harmless there, because Blast Wave applies a
        # snare rather than a disorient and so never opens a bracket. The board
        # keys a bracket off the aura it watches land, so it has to be told
        # apart here: require the disorient the group is actually named for.
        if (mask & 0x000800000) and M_DISORIENTED in mech:
            return "DRAGONS"                 # Dragon's Breath
    elif fam == FAM_ROGUE:
        if mask & 0x000200000:
            return "KIDNEY"
        if mask & 0x001000000:
            return "BLIND"
    elif fam == FAM_HUNTER:
        if mask & 0x000000008:
            return "FREEZE"                  # Freezing Trap
    elif fam == FAM_WARLOCK:
        if (mask & 0x040000000) and spell != 7870:
            return "FEAR"                    # Seduction (7870 = Lesser Invisibility)
    elif fam == FAM_DRUID:
        if mask & 0x02000000000:
            return "BLIND"                   # Cyclone
        if (mask & 0x00000000200) and attr == ATTR_NATURES_GRASP_ROOT:
            return "ROOT"                    # Nature's Grasp triggered root
        if spell == 45334:
            return None                      # Feral Charge root effect
    elif fam == FAM_WARRIOR:
        if mask & 0x000000002:
            return "LIMIT"                   # Hamstring: capped, never laddered
    elif fam == FAM_PALADIN:
        # The family bit alone is shared with Divine Protection and
        # Vindication; the Attributes word is what actually names Turn Evil,
        # and CMaNGOS tests both for exactly that reason.
        if (mask & 0x0000400000000000) and attr == ATTR_TURN_EVIL:
            return "FEAR"                    # Turn Evil (2.4.0)

    if not mech:
        return None

    # --- by mechanic, in the server's own order ---------------------------
    if M_STUN in mech:
        base = name.split("(")[0].strip()
        if spell in TRIGGERED_STUN_IDS or base in TRIGGERED_STUN_NAMES:
            return "STUN_PROC"
        return "STUN"
    if M_SLEEP in mech:
        return "SLEEP"
    if mech & {M_KNOCKOUT, M_SAPPED, M_POLYMORPH}:
        return "POLY"
    if M_ROOT in mech:
        base = name.split("(")[0].strip()
        if base in FORCE_CAST_ROOT_NAMES:
            return "ROOT"
        return "ROOT_PROC" if base in TRIGGERED_ROOT_NAMES else "ROOT"
    if M_FEAR in mech:
        return "FEAR"
    if M_CHARM in mech:
        return "CHARM"
    if M_DISARM in mech:
        return "DISARM"
    if M_FREEZE in mech:
        return "FREEZE"
    if M_BANISH in mech:
        return "BANISH"
    if M_HORROR in mech:
        return "HORROR"
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True, help="directory holding the DB2 CSVs")
    ap.add_argument("--out", required=True, help="Lua fragment to write")
    ap.add_argument("--build", default="2.5.6.69546")
    args = ap.parse_args()

    names, mechanic, family, classmask, attributes = load(args.csv)

    by_group = defaultdict(list)
    for spell in sorted(set(mechanic) | set(family)):
        group = classify(spell, names, mechanic, family, classmask, attributes)
        if group:
            by_group[group].append(spell)

    missing = set(by_group) - GROUP_KEYS
    if missing:
        sys.exit("classifier produced unknown groups: %s" % sorted(missing))

    total = sum(len(v) for v in by_group.values())
    lines = []
    lines.append("-- GENERATED by Harness/make_dr_table.py -- do not hand-edit.")
    lines.append("-- Client build %s; classifier transcribed from CMaNGOS" % args.build)
    lines.append("-- mangos-tbc GetDiminishingReturnsGroupForSpell.")
    lines.append("-- %d player spells across %d groups." % (total, len(by_group)))
    lines.append("")
    lines.append("DATA.DR_GROUPS = {")
    for key, label, drtype, note in GROUPS:
        lines.append('    { key = "%s", label = "%s", drtype = "%s",' % (key, label, drtype))
        lines.append('      note = "%s" },' % note.replace('"', "'"))
    lines.append("}")
    lines.append("")
    lines.append("DATA.DR_BY_SPELL = {")
    for key, label, _drtype, _note in GROUPS:
        spells = sorted(by_group.get(key, ()))
        if not spells:
            continue
        lines.append("    -- %s (%d)" % (label, len(spells)))
        row = []
        for spell in spells:
            row.append('[%d] = "%s",' % (spell, key))
            if len(row) == 4:
                lines.append("    " + " ".join(row))
                row = []
        if row:
            lines.append("    " + " ".join(row))
    lines.append("}")
    lines.append("")

    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")

    for key, label, _d, _n in GROUPS:
        sample = sorted(by_group.get(key, ()))[:3]
        print("%-10s %4d  %s" % (key, len(by_group.get(key, ())),
                                 ", ".join(names.get(s, "?") for s in sample)))
    print("total %d -> %s" % (total, args.out))


if __name__ == "__main__":
    main()
